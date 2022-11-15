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
import HaByLo
import NIO

internal extension Vault.Clerk {
    func storeAndSwitch(coins: [HD.Coin]) -> EventLoopFuture<Void> {
        self.checkLoadedState()
        .flatMap { loaded in
            loaded.fileIO.changeFileSize(fileHandle: loaded.coinRepos.backup.nioFileHandle,
                                         size: 0,
                                         eventLoop: self.eventLoop)
            .flatMap {
                loaded.coinRepos.backup.append(coins)
            }
            .flatMap {
                loaded.coinRepos.switch(threadPool: loaded.threadPool,
                                        eventLoop: self.eventLoop)
            }
        }
    }
}

public extension Vault.Clerk {
    func consolidate(tip height: Int) -> EventLoopFuture<Void> {
        func filterOutBefore(coins: [HD.Coin], height: Int) -> [HD.Coin] {
            coins.sorted().compactMap { coin in
                switch (coin.receivedState, coin.spentState) {
                case (.confirmed(let rHeight), .spent(let spent)) where rHeight < height && spent.height < height:
                    return nil
                case (.confirmed, .pending(let pending))
                        where pending.height < (height
                                                    - GlobalFltrWalletSettings.CoinConsolidateUnconfirmed
                                                    + GlobalFltrWalletSettings.CoinConsolidateBacklog):
                    return nil
                case (.unconfirmed(let rHeight), .unspent)
                        where rHeight < (height
                                            - GlobalFltrWalletSettings.CoinConsolidateUnconfirmed
                                            + GlobalFltrWalletSettings.CoinConsolidateBacklog):
                    return nil
                case (.rollback, .pending(let pending))
                        where pending.height < (height
                                                    - GlobalFltrWalletSettings.CoinConsolidateUnconfirmed
                                                    + GlobalFltrWalletSettings.CoinConsolidateBacklog):
                    return nil
                case (.rollback(let rHeight), _)
                        where rHeight < (height
                                                    - GlobalFltrWalletSettings.CoinConsolidateUnconfirmed
                                                    + GlobalFltrWalletSettings.CoinConsolidateBacklog):
                    return nil
                case (.confirmed, .unspent),
                     (.confirmed, .spent),
                     (.confirmed, .pending),
                     (.unconfirmed, .unspent),
                     (.rollback, .pending):
                    return coin.unranked()
                case (.unconfirmed, .spent),
                     (.unconfirmed, .pending),
                     (.rollback, .spent),
                     (.rollback, .unspent):
                    preconditionFailure()
                }
            }
        }
        
        func doConsolidate() -> EventLoopFuture<Void> {
            self.checkLoadedState()
            .flatMap { loaded in
                loaded.coinRepos.current.find(from: 0)
                    .map { coins in
                        filterOutBefore(coins: coins, height: height - GlobalFltrWalletSettings.CoinConsolidateBacklog)
                    }
                    .flatMap { filteredCoins in
                        self.storeAndSwitch(coins: filteredCoins)
                    }
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doConsolidate()
            : self.eventLoop.flatSubmit(doConsolidate)
    }

    func rollback(to height: Int) -> EventLoopFuture<Void> {
        func filterCoins(_ coins: [HD.Coin]) -> [HD.Coin] {
            return coins.compactMap { coin in
                func copy(receivedState: HD.Coin.ReceivedState? = nil,
                          spentState: HD.Coin.SpentState? = nil) -> HD.Coin {
                    .init(outpoint: coin.outpoint,
                          amount: coin.amount,
                          receivedState: receivedState ?? coin.receivedState,
                          spentState: spentState ?? coin.spentState,
                          source: coin.source,
                          path: coin.path)
                }
                
                switch (coin.receivedState, coin.spentState) {
                case (.confirmed(let receivedHeight), .spent(let spent)):
                    if receivedHeight < height {
                        let spentState = spent.height < height
                            ? coin.spentState
                            : HD.Coin.SpentState.unspent
                        return copy(spentState: spentState)
                    } else {
                        return nil
                    }
                case (.confirmed(let receivedHeight), .pending):
                    if receivedHeight < height {
                        return copy()
                    } else {
                        return copy(receivedState: .rollback(receivedHeight))
                    }
                case (.confirmed(let receivedHeight), .unspent),
                     (.unconfirmed(let receivedHeight), .unspent):
                    if receivedHeight < height {
                        return copy()
                    } else {
                        return nil
                    }
                case (.rollback, .pending):
                    return copy()
                case (.rollback, .spent),
                     (.rollback, .unspent),
                     (.unconfirmed, .pending),
                     (.unconfirmed, .spent):
                    preconditionFailure()
                }
            }
        }
        
        func doRollback() -> EventLoopFuture<Void> {
            self.checkLoadedState()
            .flatMap { loaded in
                loaded.coinRepos.current.find(from: 0)
                .flatMapError {
                    switch $0 {
                    case let error as File.NoExactMatchFound<HD.Coin>:
                        return loaded.coinRepos.current.find(from: 0,
                                                             through: error.left.id)
                    default:
                        return self.eventLoop.makeFailedFuture($0)
                    }
                }
                .map(filterCoins(_:))
                .flatMap(self.storeAndSwitch(coins:))
                .flatMapError {
                    switch $0 {
                    case File.Error.noDataFoundFileEmpty:
                        return self.eventLoop.makeSucceededFuture(())
                    default:
                        return self.eventLoop.makeFailedFuture($0)
                    }
                }
                .always { result in
                    loaded.walletEventHandler(.tally(.rollback))
                    .whenComplete { _ in
                        logger.info("Vault.Clear \(#function) - Sending rollback "
                                        + "event to event handler. Rollback result [\(result)]")
                    }
                }
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doRollback()
            : self.eventLoop.flatSubmit(doRollback)
    }
}
