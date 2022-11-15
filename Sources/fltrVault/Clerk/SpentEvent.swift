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
import fltrTx
import HaByLo
import NIO

internal extension Vault.Clerk {
    func spent(outpoint: Tx.Outpoint, state: HD.Coin.SpentState) -> EventLoopFuture<Void> {
        self.checkLoadedState()
        .and(self.find(outpoint: outpoint))
        .flatMap { loaded, coin in
            logger.info("Vault.Clerk \(#function)\n🟪🟪🟪 SPENT \(coin!.outpoint) 💰[\(coin!.amount)] "
                            + "Confirmed[\(state.isPending ? "❌" : "✅")]")
            return loaded.coinRepos.current.spent(id: coin!.id, state: state)
            .flatMap { eventOptional in
                guard let event = eventOptional
                else {
                    return self.eventLoop.makeSucceededFuture(())
                }
                
                return loaded.walletEventHandler(WalletEvent.tally(event))
            }
        }
        .flatMapError {
            switch $0 {
            case is Vault.OutpointNotFoundError:
                preconditionFailure()
            default:
                return self.eventLoop.makeFailedFuture($0)
            }
        }
    }
}

public extension Vault.Clerk {
    func spentConfirmed(outpoint: Tx.Outpoint,
                        height: Int,
                        changeIndices: [UInt8],
                        tx: Tx.AnyTransaction) -> EventLoopFuture<Void> {
        func doSpent() -> EventLoopFuture<Void> {
            let spent: HD.Coin.Spent = .init(height: height,
                                             changeOuts: changeIndices,
                                             tx: tx)
            return self.spent(outpoint: outpoint, state: .spent(spent))
        }
        
        return self.eventLoop.inEventLoop
            ? doSpent()
            : self.eventLoop.flatSubmit(doSpent)
    }

    func spentUnconfirmed(outpoint: Tx.Outpoint,
                          height: Int,
                          changeIndices: [UInt8],
                          tx: Tx.AnyTransaction) -> EventLoopFuture<Void> {
        func doSpent() -> EventLoopFuture<Void> {
            let pending: HD.Coin.Spent = .init(height: height,
                                               changeOuts: changeIndices,
                                               tx: tx)
            return self.spent(outpoint: outpoint, state: .pending(pending))
        }
        
        return self.eventLoop.inEventLoop
            ? doSpent()
            : self.eventLoop.flatSubmit(doSpent)
    }
}
