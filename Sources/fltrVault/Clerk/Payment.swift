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
import var HaByLo.logger
import NIO

// MARK: Internal backend code
internal extension Vault.Clerk {
    func prepare(payment amount: UInt64,
                 to address: AddressDecoder,
                 costRate: Double,
                 height: Int,
                 threadPool: NIOThreadPool) -> EventLoopFuture<TransactionCostPredictor> {
        func checkArguments() throws {
            guard amount > GlobalFltrWalletSettings.DustAmount
            else { throw Vault.PaymentError.dustAmount }
            
            guard costRate > 0
            else { throw Vault.PaymentError.illegalCostRate }
        }
        
        func build(using coins: [HD.Coin]) -> TransactionCostPredictor? {
            return TransactionCostPredictor.buildTx(amount: amount,
                                                    scriptPubKey: address.scriptPubKey,
                                                    costRate: costRate,
                                                    coins: coins,
                                                    height: height)
        }

        func findOutputAdapted(sorted coins: Tally) -> TransactionCostPredictor? {
            let upper = amount << 2
            let lower = amount >> 1
            
            var result: Tally = []
            
            var coinsPrefix = coins.prefix(6)[...]
            while let coin = coinsPrefix.popFirst() {
                result.append(coin)
                
                if let next = build(using: result) {
                    if let nextRefund = next.refund {
                        guard nextRefund.value <= upper
                        else { return nil }
                        
                        if nextRefund.value >= max(lower, GlobalFltrWalletSettings.DustAmount) {
                            return next
                        }
                    } else {
                        // perfect match, no refund necessary
                        return next
                    }
                }
            }
            
            return nil
        }
        
        func findGreatestFirst(sorted coins: Tally) -> TransactionCostPredictor? {
            var result: Tally = []
            
            var coins = coins
            while let coin = coins.popLast() {
                result.append(coin)
                
                if let next = build(using: result) {
                    return next
                }
            }
            
            return nil
        }

        func coinSelection(spendable coins: Tally,
                           threadPool: NIOThreadPool) -> EventLoopFuture<TransactionCostPredictor> {
            threadPool.runIfActive(eventLoop: self.eventLoop) {
                try checkArguments()
                
                guard let all = build(using: coins)
                else {
                    if let zeroTx = TransactionCostPredictor.buildTx(amount: 0,
                                                                     scriptPubKey: address.scriptPubKey,
                                                                     costRate: costRate,
                                                                     coins: coins,
                                                                     height: height) {
                        throw Vault.PaymentError.notEnoughFunds(txCost: zeroTx.transactionCost)
                    } else {
                        throw Vault.PaymentError.transactionCostGreaterThanFunds
                    }
                    
                }

                let sortedCoins = coins.sorted()
                
                return findOutputAdapted(sorted: sortedCoins)
                    ?? findGreatestFirst(sorted: sortedCoins)
                    ?? all
            }
        }
        
        return self.spendableCoins()
        .flatMap { coins in
            coinSelection(spendable: coins,
                          threadPool: threadPool)
        }
        // DEBUG
//        .always {
//            _ = $0.map {
//                print("CoinSelection Inputs", $0.inputs)
//            }
//        }
    }

    
}

// MARK: Public Payment API
public extension Vault.Clerk {
    func estimateCost(amount: UInt64,
                      to address: AddressDecoder,
                      costRate: Double) -> EventLoopFuture<UInt64> {
        func doEstimateCost() -> EventLoopFuture<UInt64> {
            self.checkLoadedState()
            .flatMap { loaded in
                self.prepare(payment: amount,
                             to: address,
                             costRate: costRate,
                             height: 0,
                             threadPool: loaded.threadPool)
                .map(\.transactionCost)
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doEstimateCost()
            : self.eventLoop.flatSubmit(doEstimateCost)
    }

    func pay(amount: UInt64,
             to address: AddressDecoder,
             costRate: Double,
             height: Int) -> EventLoopFuture<Void> {
        func spent(coins: Tally, changeIndices: [UInt8], tx: Tx.AnyTransaction) -> EventLoopFuture<Void> {
            let futures = coins.map {
                self.spentUnconfirmed(outpoint: $0.outpoint,
                                      height: height,
                                      changeIndices: changeIndices,
                                      tx: tx)
            }
            
            return EventLoopFuture.andAllSucceed(futures, on: self.eventLoop)
        }
        
        func refund(txId: Tx.TxId, out: (UInt32, Tx.Out)?) -> EventLoopFuture<Void> {
            guard let out = out
            else {
                return self.eventLoop.makeSucceededFuture(())
            }
            
            let funding = FundingOutpoint(outpoint: Tx.Outpoint(transactionId: txId, index: 1),
                                          amount: out.1.value,
                                          scriptPubKey: .init(tag: HD.Source.taprootChange.rawValue,
                                                              index: out.0,
                                                              opcodes: out.1.scriptPubKey))
            return self.addUnconfirmed(funding: funding, height: height)
        }
        
        func doPay(function: StaticString = #function) -> EventLoopFuture<Void> {
            self.checkLoadedState()
            .flatMap { loaded in
                self.prepare(payment: amount,
                             to: address,
                             costRate: costRate,
                             height: height,
                             threadPool: loaded.threadPool)
                .flatMap { transactionCostPredictor -> EventLoopFuture<Void> in
                    self.privateKey().flatMap { privateKey in
                        transactionCostPredictor
                        .signAndSerialize(using: privateKey,
                                          eventLoop: self.eventLoop,
                                          change: {
                            loaded.publicKeyRepos.taprootChangeRepo
                            .changeCallback(properties: loaded.properties,
                                            walletEventHandler: loaded.walletEventHandler)
                        })
                        .flatMap { tx, change -> EventLoopFuture<Void> in
                            return loaded.dispatchHandler(tx)
                            .flatMap {
                                let txWithId = Tx.AnyIdentifiableTransaction(tx)
                                logger.info("Vault.Clerk \(function) - "
                                            + "🦋 Paying \(amount) to:[\(address.string)] "
                                            + "txId:[\(txWithId.txId)] with change:[\(change != nil)]")
                                return refund(txId: txWithId.txId, out: change)
                            }
                            .flatMap {
                                spent(coins: transactionCostPredictor.inputs,
                                      changeIndices: [ 1, ],
                                      tx: tx)
                            }
                        }
                    }
                }
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doPay()
            : self.eventLoop.flatSubmit { doPay() }
    }
}
