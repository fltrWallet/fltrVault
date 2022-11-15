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
@testable import fltrVault
import HaByLo
import NIO
import NIOTransportServices
import VaultTestLibrary
import XCTest

final class BuildTransactionTests: XCTestCase {
    var eventLoop: EventLoop!
    var niots: NIOTSEventLoopGroup!
    
    override func setUp() {
        GlobalFltrWalletSettings = .test
        
        try? Test.removeAllFiles()
        
        Test.createCoinRepoFiles()
        Test.coinData01()
        
        self.niots = NIOTSEventLoopGroup(loopCount: 2)
        self.eventLoop = self.niots.next()
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try Test.removeCoinRepoFiles())
        XCTAssertNoThrow(try self.niots.syncShutdownGracefully())
    }
    
    func testBuildTransaction() {
        XCTAssertNoThrow(
            try Test.withCoinRepo { coinRepo in
                try coinRepo.append(HD.Coin(outpoint: .init(transactionId: "201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201", index: 101), amount: 101, receivedState: .confirmed(101), spentState: .unspent, source: .segwit, path: 101)).wait()
                
                let all = try coinRepo.find(from: 0).wait()
                let filtered = all.filter {
                    switch $0.spentState {
                    case .unspent: return true
                    default: return false
                    }
                }
                .filter {
                    switch $0.receivedState {
                    case .confirmed: return true
                    default: return false
                    }
                }
                
                let testOutput = DSA.PublicKey(42)
                let scriptPubKey = PublicKeyHash(testOutput).scriptPubKeyLegacyWPKH
                
                let built = TransactionCostPredictor.buildTx(amount: 55,
                                                             scriptPubKey: scriptPubKey,
                                                             costRate: 1.02,
                                                             coins: filtered,
                                                             height: nil)!
                XCTAssertEqual(built.vBytes, 312.5)
                XCTAssertEqual(built.weight, 1250)
                
                let bip32Seed = HD.Seed(unsafeUninitializedCapacity: 32) { bytes, size in
                    (0..<32).forEach {
                        bytes[$0] = UInt8($0)
                    }
                    size = 32
                }
                let fullNode = HD.FullNode.init(bip32Seed)!
                let (signedTx, _) = try! built.signAndSerialize(using: fullNode, eventLoop: self.eventLoop, change: {
                    return self.eventLoop.makeSucceededFuture(
                        (1, X.PublicKey(.G).scriptPubKey)
                    )
                }).wait()
                
                var copy: ByteBuffer = ByteBufferAllocator().buffer(capacity: 1000)
                signedTx.write(to: &copy)
                XCTAssertNotNil(
                    Tx.SegwitTransaction(fromBuffer: &copy)
                )

                var other = TransactionSignatureBuilder(costPredictor: built,
                                                        privateKey: fullNode,
                                                        with: X.PublicKey(.G).scriptPubKey)
                other.signInputs()
                XCTAssertGreaterThanOrEqual(other.vBytes, 311)
                XCTAssertGreaterThanOrEqual(signedTx.vBytes, 311)
                XCTAssertGreaterThanOrEqual(built.weight, 1247)
                XCTAssertGreaterThanOrEqual(other.weight, 1247)
                XCTAssertGreaterThanOrEqual(signedTx.weight, 1247)
                XCTAssertEqual(built.recipient.value, 55)
                XCTAssertEqual(signedTx.vout[0].value, 55)
                XCTAssertGreaterThanOrEqual(other.transactionCost, 318)
                XCTAssertNotNil(other.refund)
                XCTAssertGreaterThan(signedTx.vout.count, 1)

                other.signInputs()
                XCTAssertGreaterThanOrEqual(other.vBytes, 311)
                XCTAssertGreaterThanOrEqual(other.transactionCost, 318)
                XCTAssertEqual(other.recipient.value, 55)
                guard let refund = other.refund
                else { XCTFail(); return }
                XCTAssertGreaterThanOrEqual(refund.value, 27)
            }
        )
    }
}
