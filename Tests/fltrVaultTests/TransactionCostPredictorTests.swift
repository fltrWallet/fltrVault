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
import fltrECCTesting
import fltrTx
@testable import fltrVault
import NIO
import NIOTransportServices
import VaultTestLibrary
import XCTest

final class TransactionSignatureBuilderTests: XCTestCase {
    var eventLoop: EventLoop!
    var niots: NIOTSEventLoopGroup!
    var txIdIndex: Int!
    var scriptPubKeyRecipient: [UInt8]!
    var privateKey: HD.FullNode!
    
    override func setUp() {
        let niots = NIOTSEventLoopGroup(loopCount: 1)
        self.eventLoop = niots.next()
        self.niots = niots
        self.txIdIndex = 0
        self.scriptPubKeyRecipient = PublicKeyHash(DSA.PublicKey(.G)).scriptPubKeyWPKH
        self.privateKey = HD.FullNode(.testing)
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.niots.syncShutdownGracefully())
        self.niots = nil
        self.eventLoop = nil
        self.txIdIndex = nil
        self.scriptPubKeyRecipient = nil
    }
    
    func nextOutpoint() -> Tx.Outpoint {
        defer { self.txIdIndex += 1 }
        
        let base: [UInt8] = (0..<31).map { _ in 0 }
        let txId: Tx.TxId = .little(base + [ UInt8(self.txIdIndex) ])
        
        return .init(transactionId: txId, index: UInt32(self.txIdIndex))
    }
    
    func makeCoin(amount: UInt64, source: HD.Source) -> HD.Coin {
        return .init(outpoint: self.nextOutpoint(),
                     amount: amount,
                     receivedState: .confirmed(1),
                     spentState: .unspent,
                     source: source,
                     path: 1)
    }
    
    var testInputs01: [HD.Coin] {[
        self.makeCoin(amount: 1000, source: .taprootChange),
        self.makeCoin(amount: 1000, source: .taproot),
        self.makeCoin(amount: 1000, source: .legacySegwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .taprootChange),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .legacySegwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .legacySegwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .segwit),
        self.makeCoin(amount: 1000, source: .legacySegwit),
    ]}
    
    func testInternalConstructorState() {
        let out: Tx.Out = .init(value: 1800,
                                scriptPubKey: self.scriptPubKeyRecipient)
        let predictor: TransactionCostPredictor = .init(costRate: 1,
                                                        inputs: self.testInputs01,
                                                        recipient: out,
                                                        height: nil)
        
        XCTAssertEqual(predictor.funds, 20000)
        XCTAssertEqual(predictor.costRate, 1)
        XCTAssertEqual(predictor.locktime, .disable(0))
        predictor.vin.forEach {
            XCTAssert($0.hasWitness)
            XCTAssertEqual($0.sequence.rawValue, .max)
        }
        XCTAssertNil(predictor.refund)
        
        let predictor2: TransactionCostPredictor = .init(costRate: 1,
                                                         inputs: self.testInputs01,
                                                         recipient: out,
                                                         height: 1)
        XCTAssertNil(predictor.locktime.date)
        XCTAssertNil(predictor.locktime.height)
        XCTAssertNil(predictor2.locktime.date)
        XCTAssertEqual(predictor2.locktime.height, 1)
        predictor2.vin.forEach {
            XCTAssertEqual($0.sequence.rawValue, .max - 1)
        }
    }
    
    func testBuildTx01() {
        guard let predictor: TransactionCostPredictor = .buildTx(amount: 1,
                                                                 scriptPubKey: self.scriptPubKeyRecipient,
                                                                 costRate: 1,
                                                                 coins: self.testInputs01,
                                                                 height: nil)
        else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(predictor.vin.count, 20)
        XCTAssertEqual(predictor.transactionCost, 1505)
        XCTAssertEqual(predictor.refund?.value, 18494)
    }
    
    func testSignAndSerialize01() {
        guard let predictor: TransactionCostPredictor = .buildTx(amount: 1,
                                                                 scriptPubKey: self.scriptPubKeyRecipient,
                                                                 costRate: 1,
                                                                 coins: self.testInputs01,
                                                                 height: nil)
        else {
            XCTFail()
            return
        }

        XCTAssertNoThrow(
            XCTAssertGreaterThanOrEqual(
                try predictor.signAndSerialize(using: privateKey,
                                               eventLoop: self.eventLoop,
                                               change: {
                                                return self.eventLoop.makeSucceededFuture(
                                                    (1, self.scriptPubKeyRecipient)
                                                )
                                               })
                    .wait().change!.txOut.value,
                18507
            )
        )
    }
    
    func testSignAndSerialize01NoRefund() {
        guard let predictor: TransactionCostPredictor = .buildTx(amount: 1,
                                                                 scriptPubKey: self.scriptPubKeyRecipient,
                                                                 costRate: 13.385,
                                                                 coins: self.testInputs01,
                                                                 height: 1000),
              let privateKey = HD.FullNode(.seed(size: 32)),
              let segwitTx = try? predictor.signAndSerialize(using: privateKey,
                                                      eventLoop: self.eventLoop,
                                                      change: {
                                                        XCTFail()
                                                        return self.eventLoop.makeSucceededFuture(
                                                            (1, self.scriptPubKeyRecipient)
                                                        )
                                                      })
                .wait()
                .tx
        else {
            XCTFail()
            return
        }

        XCTAssertEqual(predictor.transactionCost, UInt64(round(13.385 * predictor.vBytes)))
        segwitTx.vin.forEach {
            XCTAssertEqual($0.sequence, .locktimeOnly)
        }
        XCTAssertEqual(segwitTx.locktime, .enable(1000))
        XCTAssertEqual(segwitTx.vin.count, 20)
        XCTAssertEqual(segwitTx.vout.count, 1)
        XCTAssertGreaterThanOrEqual(round(13.385 * segwitTx.vBytes), 19525)
    }
}
