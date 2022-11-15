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
@testable import fltrVault
import fltrTx
import Foundation
import HaByLo

public extension Test {
    static let CoinTransactionId = BlockChain.Hash<TransactionLegacyHash>.little((1...32).map { UInt8($0) })
    
    static func coinData01() {
        let coins: [HD.Coin] = [
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .legacySegwit),
            .makeCoin(with: .confirmed(101), spent: .spent(height: 200), source: .segwit),
            .makeCoin(with: .unconfirmed(102), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(200), spent: .unspent, source: .segwit),
            .makeCoin(with: .unconfirmed(201), spent: .unspent, source: .legacySegwit),
            .makeCoin(with: .confirmed(202), spent: .pending(height: 1000), source: .segwit),
        ]
        
        return Test.write(coins: coins)
    }
    
    static func coinData02() {
        let coins: [HD.Coin] = [
            .makeCoin(with: .confirmed(1), spent: .spent(height: 1), source: .segwit),
            .makeCoin(with: .unconfirmed(1), spent: .unspent, source: .segwit),
            .makeCoin(with: .unconfirmed(1), spent: .unspent, source: .legacySegwit),
            .makeCoin(with: .confirmed(1), spent: .spent(height: 1), source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .taproot),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .taproot),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .taproot),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .taprootChange),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(100), spent: .unspent, source: .segwit),
        ]
        
        return Test.write(coins: coins)
    }
    
    static func coinData03() {
        var c = 0
        func counter() -> Int {
            defer { c += 1 }
            return c
        }
        
        let outpointId1: Tx.TxId = .makeHash(from: [ 00, 01, 02, 03 ])
        let outpointId2: Tx.TxId = .makeHash(from: "outpoint2".ascii)
        let outpointId3: Tx.TxId = .makeHash(from: "outpoint3".ascii)
        let txIn1 = Tx.In(outpoint: .init(transactionId: outpointId1, index: 0),
                          scriptSig: [],
                          sequence: .disable,
                          witness: { .init(witnessField: [[01, 02], [01, 02, 03]]) })
        let txIn2 = Tx.In(outpoint: .init(transactionId: outpointId2, index: 0),
                          scriptSig: [],
                          sequence: .disable,
                          witness: { .init(witnessField: [[01, 02], [01, 02, 03, 04]]) })
        let txIn3 = Tx.In(outpoint: .init(transactionId: .makeHash(from: "spentAll".ascii), index: 0),
                          scriptSig: [],
                          sequence: .disable,
                          witness: { .init(witnessField: [[01, 02], [01, 02, 03]]) })
        
        func script(for string: String) -> [UInt8] {
            Script([ .opN(1),
                     .pushdata0(string.ascii.sha256) ]).bytes
        }
        
        let tx1: Tx.AnyTransaction = .segwit(.init(version: 1,
                                                   vin: [ txIn1 ],
                                                   vout: [ .init(value: 8_001,
                                                                 scriptPubKey: Script([.opN(1), .pushdata0((1...32).map { $0 })]).bytes),
                                                           .init(value: 1_700, scriptPubKey: script(for: "change0"))],
                                                   locktime: .disable(.max - 1))!)
        let tx2: Tx.AnyTransaction = .segwit(.init(version: 1,
                                                   vin: [ txIn2 ],
                                                   vout: [ .init(value: 8_002,
                                                                 scriptPubKey: Script([.opN(1), .pushdata0((1...32).reversed().map { $0 })]).bytes),
                                                           .init(value: 1_600, scriptPubKey:  script(for: "change1"))],
                                                   locktime: .disable(.max - 1))!)
        let tx3: Tx.AnyTransaction = .segwit(.init(version: 1,
                                                   vin: [ txIn3 ],
                                                   vout: [ .init(value: 9_503,
                                                                 scriptPubKey: Script([.opN(1), .pushdata0((2...33).map { $0 })]).bytes), ],
                                                   locktime: .disable(.max - 1))!)

        let coins: [HD.Coin] = [
            HD.Coin(outpoint: .init(transactionId: outpointId3, index: 5),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: outpointId3, index: 1),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: .makeHash(from: "change0".ascii), index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .taprootChange,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: outpointId3, index: 2),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: outpointId3, index: 3),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: outpointId3, index: 4),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: .makeHash(from: "taproot0".ascii), index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(2),
                    spentState: .unspent,
                    source: .taproot,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: .makeHash(from: "legacy1".ascii), index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(30),
                    spentState: .unspent,
                    source: .legacySegwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: outpointId1, index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .pending(HD.Coin.Spent(height: 3, changeOuts: [1], tx: tx1)),
                    source: .taproot,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: Tx.AnyIdentifiableTransaction(tx1).txId,
                                    index: 1),
                    amount: 1_700,
                    receivedState: .unconfirmed(3),
                    spentState: .unspent,
                    source: .taprootChange,
                    path: 2),
            HD.Coin(outpoint: .init(transactionId: outpointId2, index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(4),
                    spentState: .spent(HD.Coin.Spent(height: 10, changeOuts: [1], tx: tx2)),
                    source: .taproot,
                    path: 3),
            HD.Coin(outpoint: .init(transactionId: Tx.AnyIdentifiableTransaction(tx2).txId,
                                    index: 1),
                    amount: 1_800,
                    receivedState: .confirmed(10),
                    spentState: .unspent,
                    source: .taprootChange, path: 3),
            HD.Coin(outpoint: .init(transactionId: .makeHash(from: "spentAll".ascii), index: 0),
                    amount: 10_000,
                    receivedState: .confirmed(5),
                    spentState: .spent(HD.Coin.Spent(height: 20, changeOuts: [1], tx: tx3)),
                    source: .taprootChange,
                    path: 1),
        ]
        
        return Test.write(coins: coins)
    }
    
    static func coinData04() {
        var c = 0
        func counter() -> Int {
            defer { c += 1 }
            return c
        }
        
        let outpointId1: Tx.TxId = .makeHash(from: [ 00, 01, 02, 03 ])
        let txIn1 = Tx.In(outpoint: .init(transactionId: outpointId1, index: 0),
                          scriptSig: [],
                          sequence: .disable,
                          witness: { .init(witnessField: [[01, 02], [01, 02, 03]]) })
        
        func script(for string: String) -> [UInt8] {
            Script([ .opN(1),
                     .pushdata0(string.ascii.sha256) ]).bytes
        }
        
        let tx1: Tx.AnyTransaction = .segwit(.init(version: 1,
                                                   vin: [ txIn1 ],
                                                   vout: [ .init(value: 8_001,
                                                                 scriptPubKey: Script([.opN(1), .pushdata0((1...32).map { $0 })]).bytes),
                                                           .init(value: 1_700, scriptPubKey: script(for: "change0"))],
                                                   locktime: .disable(.max - 1))!)
        let coins: [HD.Coin] = [
            HD.Coin(outpoint: .init(transactionId: outpointId1, index: 1),
                    amount: 10_000,
                    receivedState: .confirmed(1),
                    spentState: .pending(HD.Coin.Spent(height: 2, changeOuts: [1], tx: tx1)),
                    source: .segwit,
                    path: 1),
            HD.Coin(outpoint: .init(transactionId: Tx.AnyIdentifiableTransaction(tx1).txId, index: 0),
                    amount: 8_001,
                    receivedState: .unconfirmed(2),
                    spentState: .unspent,
                    source: .taprootChange,
                    path: 1),
        ]
        
        return Test.write(coins: coins)
    }

    static func coinDataRollback01() {
        let coins: [HD.Coin] = [
            .makeCoin(with: .confirmed(101), spent: .unspent, source: .segwit),
            .makeCoin(with: .unconfirmed(102), spent: .unspent, source: .segwit),
            .makeCoin(with: .confirmed(103), spent: .spent(height: 104), source: .segwit),
            .makeCoin(with: .rollback(110), spent: .pending(height: 111), source: .segwit),
        ]
        
        return Test.write(coins: coins)
    }
}


public extension HD.Coin {
    enum SpentStateTesting {
        case pending(height: Int)
        case spent(height: Int)
        case unspent
    }
    
    static func makeCoin(amount: Int? = nil,
                         privateKey: HD.FullNode = .init(
                            HD.Seed(unsafeUninitializedCapacity: 32,
                                    initializingWith: { b, s in
                                        (0..<32).forEach { b[$0] = UInt8($0) }
                                        s = 32
                                    }))!,
                         with received: HD.Coin.ReceivedState,
                         spent state: SpentStateTesting,
                         source: HD.Source) -> HD.Coin {
        let i: Int = {
            if let amount = amount {
                return amount
            }
            
            switch received {
            case .confirmed(let height),
                 .unconfirmed(let height),
                 .rollback(let height):
                return height
            }
        }()
        
        let outpoint = Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                   index: UInt32(i))
        
        let spentState: HD.Coin.SpentState = {
            switch state {
            case .pending(let height):
                let tx = Tx.makeSegwitTx(for: outpoint)
                let spent = HD.Coin.Spent(height: height, changeOuts: [], tx: tx)
                return .pending(spent)
            case .spent(let height):
                let tx = Tx.makeSegwitTx(for: outpoint)
                let spent = HD.Coin.Spent(height: height, changeOuts: [], tx: tx)
                return .spent(spent)
            case .unspent:
                return .unspent
            }
        }()
        
        return .init(outpoint: .init(transactionId: Test.CoinTransactionId,
                                     index: UInt32(i)),
                     amount: UInt64(i),
                     receivedState: received,
                     spentState: spentState,
                     source: source,
                     path: UInt32(i))
    }
}
