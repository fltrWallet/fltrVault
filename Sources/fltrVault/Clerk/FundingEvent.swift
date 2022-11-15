//===----------------------------------------------------------------------===//
//
// This source file is part of the fltrVault open source project
//
// Copyright (c) 2022 fltrWallet AG and the fltrVault project authors
// Licensed under Apache License v2.0
//
// See LICENSE.md for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import fltrECC
import fltrTx
import FileRepo
import HaByLo
import NIO
import fltrWAPI

// MARK: Internal backend code
internal extension Vault.Clerk {
    func add(funding: FundingOutpoint,
             receivedState: HD.Coin.ReceivedState) -> EventLoopFuture<TransactionEventCommitOutcome> {
        precondition(funding.scriptPubKey.index < .max)
        guard let sourceRepo = HD.Source(rawValue: funding.scriptPubKey.tag)
        else {
            preconditionFailure("funding tag \(funding.scriptPubKey.tag) provided is invalid")
        }

        func rebufferPubKeys(repo: Vault.SourcePublicKeyRepo,
                             pathIndex: UInt32,
                             loaded: Vault.State.LoadedState)
        -> EventLoopFuture<TransactionEventCommitOutcome> {
            repo.rebuffer(index: Int(pathIndex),
                          properties: loaded.properties,
                          walletEventHandler: loaded.walletEventHandler)
            .map { _ in () }
            .recover { preconditionFailure("\($0)") }
            .map {
                guard pathIndex > 0
                else { return .relaxed }
                
                return Int(pathIndex) % (max(1, GlobalFltrWalletSettings.PubKeyLookahead)) == 0
                ? .strict
                : .relaxed
            }
        }
        
        func fund(_ input: (UInt64) -> TallyEvent) -> TallyEvent {
            input(funding.amount)
        }
        
        enum CoinOutcome {
            case rollforward(HD.Coin)
            case promoted(HD.Coin, TallyEvent)
            case new(HD.Coin, TallyEvent)
            case none(EventLoop)
            
            func write(_ coinRepo: Vault.CoinRepo) -> EventLoopFuture<TallyEvent?> {
                switch self {
                case .rollforward(let coin):
                    return coinRepo.write(coin).map { nil }
                case .promoted(let coin, let event):
                    return coinRepo.write(coin).map { event }
                case .new(let coin, let event):
                    return coinRepo.append(coin).map { event }
                case .none(let eventLoop):
                    return eventLoop.makeSucceededFuture(nil)
                }
            }
        }
        
        func coinEvent(found coin: HD.Coin?,
                       pathIndex: UInt32) -> CoinOutcome {
            
            let newCoin: HD.Coin = .init(outpoint: funding.outpoint,
                                         amount: funding.amount,
                                         receivedState: receivedState,
                                         spentState: .unspent,
                                         source: sourceRepo,
                                         path: pathIndex)

            switch (coin?.receivedState, receivedState) {
            case (.unconfirmed, .confirmed):
                return .promoted(newCoin.rank(id: coin!.id), fund(TallyEvent.receivePromoted))
            case (.unconfirmed, .unconfirmed),
                (.confirmed, .unconfirmed):
                return .none(self.eventLoop)
            case (.confirmed, .confirmed):
                logger.error("Vault.Clerk - Received duplicate "
                             + "confirmed outpoint \(funding.outpoint)")
                return .none(self.eventLoop)
            case (.rollback, .unconfirmed):
                logger.error("Vault.Clerk - Received unconfirmed "
                             + "spend of rollback outpoint \(funding.outpoint)")
                return .none(self.eventLoop)
            case (.rollback, .confirmed):
                switch coin!.spentState {
                case .pending:
                    break
                case .spent, .unspent:
                    preconditionFailure()
                }

                let pendingCoin = HD.Coin(outpoint: funding.outpoint,
                                          amount: funding.amount,
                                          receivedState: receivedState,
                                          spentState: coin!.spentState,
                                          source: sourceRepo,
                                          path: pathIndex)
                    .rank(id: coin!.id)
                return .rollforward(pendingCoin)
            case (nil, .confirmed):
                return .new(newCoin, fund(TallyEvent.receiveConfirmed))
            case (nil, .unconfirmed):
                return .new(newCoin, fund(TallyEvent.receiveUnconfirmed))
            case (.unconfirmed, .rollback),
                (.confirmed, .rollback),
                (.rollback, .rollback),
                (nil, .rollback):
                preconditionFailure()
            }
        }
        
        logger.info("Vault.Clerk \(#function)\n"
                    + "🟦🟦🟦 ADD💵 \(funding) Confirmed[\(receivedState.isPending ? "❌" : "✅")]")
        return self.checkLoadedState()
        .flatMap { loaded in
            let repo = sourceRepo.repo(from: loaded.publicKeyRepos)
            let pathIndex = funding.scriptPubKey.index

            return self.checkPath(repo: repo, scriptPubKey: funding.scriptPubKey)
            .recover { preconditionFailure("\($0)") }
            .flatMap { checks -> EventLoopFuture<TransactionEventCommitOutcome> in
                precondition(checks)
                return rebufferPubKeys(repo: repo, pathIndex: pathIndex, loaded: loaded)
                .flatMap { commitOutcome in
                    self.find(outpoint: funding.outpoint)
                    .map { coinEvent(found: $0, pathIndex: pathIndex) }
                    .flatMap {
                        $0.write(loaded.coinRepos.current)
                    }
                    .flatMap { eventOptional in
                        if let event = eventOptional {
                            return loaded.walletEventHandler(WalletEvent.tally(event))
                        } else {
                            return self.eventLoop.makeSucceededVoidFuture()
                        }
                    }
                    .map { commitOutcome }
                    .recover {
                        preconditionFailure("\($0)")
                    }
                }
            }
        }
    }
    
    func find(outpoint: Tx.Outpoint) -> EventLoopFuture<HD.Coin?> {
        self.checkLoadedState()
        .flatMap { loaded in
            loaded.coinRepos.current.range()
            .flatMap { range in
                func search(start: Int, end: Int) -> EventLoopFuture<HD.Coin> {
                    guard start < range.upperBound//, range.upperBound - 1 <= end
                    else { // base case
                        return self.eventLoop.makeFailedFuture(Vault.OutpointNotFoundError())
                    }
                    
                    let upper = min(range.upperBound - 1, end)
                    
                    let repo: Vault.CoinRepo = loaded.coinRepos.current
                    return repo.find(from: start, through: upper)
                    .flatMap { (coins: [HD.Coin]) in
                        if let match = coins.first(where: { $0.outpoint == outpoint }) {
                            return self.eventLoop.makeSucceededFuture(match)
                        } else {
                            return search(start: end + 1, end: end + 1 + GlobalFltrWalletSettings.PubKeyRepoFindBuffer)
                        }
                    }
                }
                
                return search(start: range.lowerBound,
                              end: range.lowerBound + GlobalFltrWalletSettings.PubKeyRepoFindBuffer)
                .map(HD.Coin?.some)
            }
        }
        .flatMapError {
            switch $0 {
            case is Vault.OutpointNotFoundError,
                File.Error.noDataFoundFileEmpty:
                return self.eventLoop.makeSucceededFuture(nil)
            default:
                return self.eventLoop.makeFailedFuture($0)
            }
        }
    }
}

// MARK: Public API
public extension Vault.Clerk {
    func addConfirmed(funding: FundingOutpoint, height: Int) -> EventLoopFuture<TransactionEventCommitOutcome> {
        func doAdd() -> EventLoopFuture<TransactionEventCommitOutcome> {
            self.add(funding: funding, receivedState: .confirmed(height))
        }
        
        return self.eventLoop.inEventLoop
            ? doAdd()
            : self.eventLoop.flatSubmit(doAdd)
    }

    func addUnconfirmed(funding: FundingOutpoint, height: Int) -> EventLoopFuture<Void> {
        func doAdd() -> EventLoopFuture<Void> {
            self.add(funding: funding, receivedState: .unconfirmed(height))
            .map { _ in () }
        }
        
        return self.eventLoop.inEventLoop
            ? doAdd()
            : self.eventLoop.flatSubmit(doAdd)
    }
}
