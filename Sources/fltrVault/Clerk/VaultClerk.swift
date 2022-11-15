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
import FileRepo
import fltrTx
import HaByLo
import NIO

extension Vault {
    public final class Clerk {
        internal let eventLoop: EventLoop
        internal var state: State
        
        init(eventLoop: EventLoop,
             state: State) {
            self.eventLoop = eventLoop
            self.state = state
        }
    }
}

// MARK: Factory
public extension Vault.Clerk {
    static func factory(eventLoop: EventLoop,
                        threadPool: NIOThreadPool,
                        tx dispatch: @escaping (Tx.AnyTransaction) -> EventLoopFuture<Void>,
                        event handler: @escaping (WalletEvent) -> EventLoopFuture<Void>)
    -> EventLoopFuture<Vault.Clerk> {
        eventLoop.submit {
            Vault.Clerk(eventLoop: eventLoop,
                        state: .idle(threadPool, dispatch, handler))
        }
        .always { _ in
            try! Vault.touchDirectory(GlobalFltrWalletSettings.DataFileDirectory)
        }
    }
}

// MARK: Error
internal extension Vault.Clerk {
    enum Error: Swift.Error {
        case illegalArgument(String?)
        case illegalState(String, event: StaticString)
        
        static func illegalState(_ state: Vault.Clerk, function: StaticString = #function) -> Self {
            return .illegalState(String(describing: state.state), event: function)
        }
    }
}

internal extension Vault.Clerk {
    func privateKey() -> EventLoopFuture<HD.FullNode> {
        self.checkLoadedState()
        .flatMap { loaded in
            loaded.properties.loadPrivateKey()
        }
        .map { walletSeedCodable in
            Vault.load(walletSeed: walletSeedCodable,
                        password: GlobalFltrWalletSettings.BIP39PrivateKeyPassword)
        }
    }
    
    func spendableCoins() -> EventLoopFuture<Tally> {
        self.checkLoadedState()
        .flatMap { loaded in
            loaded.coinRepos.current.spendableTally()
            
        }
    }
}

// MARK: Public API
public extension Vault.Clerk {
    func availableCoins() -> EventLoopFuture<(available: Tally,
                                              pendingReceive: Tally,
                                              pendingSpend: Tally)> {
        func doAvailableCoins() -> EventLoopFuture<(available: Tally,
                                                    pendingReceive: Tally,
                                                    pendingSpend: Tally)> {
            self.checkLoadedState()
            .flatMap { loaded in
                loaded.coinRepos.current.fullTally()
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doAvailableCoins()
            : self.eventLoop.flatSubmit(doAvailableCoins)
    }
    
    func pendingTransactions() -> EventLoopFuture<[Tx.AnyTransaction]> {
        func doPending() -> EventLoopFuture<[Tx.AnyTransaction]> {
            self.checkLoadedState()
            .flatMap { loaded in
                loaded.coinRepos.current.pendingTransactions()
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doPending()
            : self.eventLoop.flatSubmit(doPending)
    }
    
    func history(bhLookup: @escaping (Int) -> EventLoopFuture<UInt32?>)
    -> EventLoopFuture<(History, [Int : UInt32])> {
        func doHistory() -> EventLoopFuture<(History, [Int : UInt32])> {
            self.checkLoadedState()
            .flatMap { loaded in
                loaded.coinRepos.current.find(from: 0)
                    .flatMapError { error in
                        switch error {
                        case File.Error.seekError:
                            return loaded.coinRepos.current.count()
                            .flatMap {
                                if $0 == 0 {
                                    return self.eventLoop.makeSucceededFuture([])
                                } else {
                                    return self.eventLoop.makeFailedFuture(error)
                                }
                            }
                            
                        default:
                            return self.eventLoop.makeFailedFuture(error)
                        }
                    }
                    .and(loaded.properties.loadAllNodes())
                .flatMap { coins, nodes in
                    let history = History.from(coins: coins,
                                               nodes: nodes)
                    var heightsSet: Set<Int> = .init()
                    history.value.forEach {
                        heightsSet.insert($0.record.height)
                    }
                    
                    let heightLookups: [EventLoopFuture<(Int, UInt32)?>] = heightsSet
                    .map { height in
                        bhLookup(height)
                        .map {
                            guard let time = $0
                            else { return nil }
                            
                            return (height, time)
                        }
                    }
                    
                    return EventLoopFuture.whenAllSucceed(heightLookups, on: self.eventLoop)
                    .map { all -> [Int : UInt32] in
                        var dict: [Int : UInt32] = [:]
                        all.forEach {
                            if let (height, time) = $0 {
                                dict[height] = time
                            }
                        }
                        
                        return dict
                    }
                    .map {
                        (history, $0)
                    }
                }
            }
        }
        
        return self.eventLoop.flatSubmit(doHistory)
        .always { result in
            switch result {
            case .failure(let err):
                logger.error("Vault.Clerk \(#function) - error loading history: \(err)")
            case .success:
                break
            }
        }
    }
    
    internal func _testingCoinRepo() -> EventLoopFuture<Vault.CoinRepoPair> {
        self.eventLoop.inEventLoop
            ? self.checkLoadedState().map { $0.coinRepos }
            : self.eventLoop.flatSubmit {
                self.checkLoadedState().map { $0.coinRepos }
            }
    }
}
