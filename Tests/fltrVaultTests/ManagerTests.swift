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
import FileRepo
import fltrTx
import Foundation
@testable import fltrVault
import NIO
import NIOTransportServices
import VaultTestLibrary
import XCTest

final class ManagerTests: XCTestCase {
    var eventLoop: EventLoop!
    var manager: Vault.Clerk!
    var niots: NIOTSEventLoopGroup!
    var fileIO: NonBlockingFileIOClient!
    var threadPool: NIOThreadPool!
    var transactionBuffer: [Tx.AnyIdentifiableTransaction]!
    var eventTestBuffer: [WalletEvent]!
    var failNextWalletEvent: Bool!

    struct WalletEventFail: Swift.Error {}

    override func setUp() {
        GlobalFltrWalletSettings = .test
        try? Test.removeAllFiles()
        
        self.threadPool = NIOThreadPool(numberOfThreads: 2)
        self.threadPool!.start()
        
        self.niots = NIOTSEventLoopGroup(loopCount: 1)
        self.eventLoop = self.niots.next()
        self.transactionBuffer = []
        self.eventTestBuffer = []
        self.failNextWalletEvent = false
        
        XCTAssertNoThrow(
            self.manager = try Vault.Clerk.factory(
                eventLoop: self.eventLoop,
                threadPool: self.threadPool,
                tx: { tx in
                    self.eventLoop.submit {
                        let segwitId = Tx.AnyIdentifiableTransaction(tx)
                        self.transactionBuffer.append(segwitId)
                    }
                },
                event: { walletEvent in
                    self.eventTestBuffer.append(walletEvent)
                    return self.failNextWalletEvent
                        ? self.eventLoop.makeFailedFuture(WalletEventFail())
                        : self.eventLoop.makeSucceededFuture(())
                }
            )
            .wait()
        )
        try? Test.removeAllFiles()
        
        self.fileIO = GlobalFltrWalletSettings.NonBlockingFileIOClientFactory(self.threadPool)
    }

    override func tearDown() {
        self.transactionBuffer?.removeAll()
        XCTAssert(self.eventTestBuffer?.isEmpty ?? true)
        self.eventTestBuffer?.removeAll()
        self.failNextWalletEvent = nil
        XCTAssertNoThrow(try self.manager.stop().wait())
        
        XCTAssertNoThrow(try self.threadPool.syncShutdownGracefully())
        XCTAssertNoThrow(try self.niots.syncShutdownGracefully())
    }
    
    func load(properties: Vault.Properties) {
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
    }
    
    func createTestFiles() {
        Test.createCoinRepoFiles()
        Test.createPublicKeyRepoFiles()
    }
    
    @discardableResult
    func loadTestData01() -> Test.PublicKeyNodes {
        self.createTestFiles()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        Test.coinData01()
        let nodes = Test.dataSet01()
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
        
        return nodes
    }
    
    @discardableResult
    func loadTestData02() -> Test.PublicKeyNodes {
        self.createTestFiles()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        Test.coinData02()
        let nodes = Test.dataSet01()
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
        
        return nodes
    }
    
    @discardableResult
    func loadTestDataRollback01() -> Test.PublicKeyNodes {
        self.createTestFiles()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        Test.coinDataRollback01()
        let nodes = Test.dataSet01()
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
        
        return nodes
    }
    
    @discardableResult
    func loadTestDataEmptyCoinRepo() -> Test.PublicKeyNodes {
        self.createTestFiles()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        let nodes = Test.dataSet01()
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
        
        return nodes
    }
    
    func opcodes(from nodes: Test.PublicKeyNodes, source: HD.Source, index: Int) -> [UInt8] {
        let node = nodes.nodeDictionary[source]!
        let neutered = node.neuter()
        let dto = source.publicKeyDto(neutered: neutered, index: index)
        return source.scriptPubKey(from: dto)
    }
    
    func consumeScriptPubKey() {
        switch self.eventTestBuffer.popLast() {
        case .some(.scriptPubKey):
            break
        default: XCTFail()
        }
    }
    
    func testTestData01() {
        self.loadTestData01()
        var loadedPubKeys: [ScriptPubKey]!
        var privateKey: Scalar!
        var privateKeyPair: X.SecretKey!
        for i in (0...10) {
            XCTAssertNoThrow(loadedPubKeys = try self.manager.scriptPubKey(type: .legacySegwit).wait())
            let pubKey = loadedPubKeys[i]

            let path: HD.Path = GlobalFltrWalletSettings.BIP39LegacySegwitAccountPath + [ .normal(0), .child(for: UInt32(i)) ]
            XCTAssertNoThrow(privateKey = try self.manager.privateECCKey(for: path).wait())
            let pkh = PublicKeyHash(DSA.PublicKey(Point(privateKey)))
            
            XCTAssertEqual(pkh.scriptPubKeyLegacyWPKH, pubKey.opcodes)
            switch pubKey.tag {
            case HD.Source.legacySegwit.rawValue: break
            default: XCTFail()
            }
        }
        for i in (1...10) {
            XCTAssertNoThrow(loadedPubKeys = try self.manager.scriptPubKey(type: .segwit).wait())
            let pubKey = loadedPubKeys[i]

            let path: HD.Path = GlobalFltrWalletSettings.BIP39SegwitAccountPath + [ .normal(0), .child(for: UInt32(i)) ]
            XCTAssertNoThrow(privateKey = try self.manager.privateECCKey(for: path).wait())
            let pkh = PublicKeyHash(DSA.PublicKey(Point(privateKey)))
            
            XCTAssertEqual(pkh.scriptPubKeyWPKH, pubKey.opcodes)
            switch pubKey.tag {
            case HD.Source.segwit.rawValue: break
            default: XCTFail()
            }
        }
        for i in (1...10) {
            XCTAssertNoThrow(loadedPubKeys = try self.manager.scriptPubKey(type: .taproot).wait())
            let pubKey = loadedPubKeys[i]

            let path: HD.Path = GlobalFltrWalletSettings.BIP39TaprootAccountPath + [ .normal(0), .child(for: UInt32(i)) ]
            XCTAssertNoThrow(privateKeyPair = try self.manager.privateXKey(for: path).wait())
            XCTAssertEqual(privateKeyPair.pubkey().xPoint.scriptPubKey, pubKey.opcodes)
            switch pubKey.tag {
            case HD.Source.taproot.rawValue: break
            default: XCTFail()
            }
        }
        for i in (1...10) {
            XCTAssertNoThrow(loadedPubKeys = try self.manager.scriptPubKey(type: .taprootChange).wait())
            let pubKey = loadedPubKeys[i]

            let path: HD.Path = GlobalFltrWalletSettings.BIP39TaprootAccountPath + [ .normal(1), .child(for: UInt32(i)) ]
            XCTAssertNoThrow(privateKeyPair = try self.manager.privateXKey(for: path).wait())
            XCTAssertEqual(privateKeyPair.pubkey().xPoint.scriptPubKey, pubKey.opcodes)
            switch pubKey.tag {
            case HD.Source.taprootChange.rawValue: break
            default: XCTFail()
            }
        }

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingSpend
                            .count, 1)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingReceive
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .spendableCoins()
                            .wait()
                            .count, 2)
        )

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            ._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 6)
        )
    }

    func testTestData01FindPaths() {
        let nodes = self.loadTestData01()

        let legacyScripts: [ScriptPubKey] = (1...10).map { index in
            var copy = nodes.nodeDictionary[.legacySegwit]!
            let pkh = PublicKeyHash(DSA.PublicKey(copy.childKey(index: index).key.public)).scriptPubKeyLegacyWPKH
            return ScriptPubKey(tag: HD.Source.legacySegwit.rawValue,
                                index: UInt32(index),
                                opcodes: pkh)
        }
        let segwitScripts: [ScriptPubKey] = (1...10).map { index in
            var copy = nodes.nodeDictionary[.segwit]!
            let pkh = PublicKeyHash(DSA.PublicKey(copy.childKey(index: index).key.public)).scriptPubKeyWPKH
            return ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                index: UInt32(index),
                                opcodes: pkh)
        }
        let taprootScripts: [ScriptPubKey] = (1...10).map { index in
            let copy = nodes.nodeDictionary[.taproot]!
            let tweaked = copy.tweak(for: index)
            return ScriptPubKey(tag: HD.Source.taproot.rawValue,
                                index: UInt32(index),
                                opcodes: tweaked.pubkey().xPoint.scriptPubKey)
        }
        let changeScripts: [ScriptPubKey] = (1...10).map { index in
            let copy = nodes.nodeDictionary[.taprootChange]!
            let tweaked = copy.tweak(for: index)
            return ScriptPubKey(tag: HD.Source.taprootChange.rawValue,
                                index: UInt32(index),
                                opcodes: tweaked.pubkey().xPoint.scriptPubKey)
        }
        
        for script in legacyScripts {
            XCTAssertNoThrow(
                XCTAssert(try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                                        .wait()
                                                        .publicKeyRepos
                                                        .legacySegwitRepo,
                                                     scriptPubKey: script).wait())
            )
        }
        for script in segwitScripts {
            XCTAssertNoThrow(
                XCTAssert(try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                                        .wait()
                                                        .publicKeyRepos
                                                        .segwitRepo,
                                                     scriptPubKey: script).wait())
            )
        }
        for script in taprootScripts {
            XCTAssertNoThrow(
                XCTAssert(try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                                        .wait()
                                                        .publicKeyRepos
                                                        .taprootRepo,
                                                     scriptPubKey: script).wait())
            )
        }
        for script in changeScripts {
            XCTAssertNoThrow(
                XCTAssert(try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                                        .wait()
                                                        .publicKeyRepos
                                                        .taprootChangeRepo,
                                                     scriptPubKey: script).wait())
            )
        }
    }
    
    func testTestData01FindPathFail() {
        self.loadTestData01()
        
        let failScript = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                      index: 0,
                                      opcodes: [ 0, 0 ])
        XCTAssertNoThrow(XCTAssertFalse(try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                                                    .wait()
                                                                    .publicKeyRepos
                                                                    .segwitRepo,
                                                                   scriptPubKey: failScript).wait()))
//        let failScript = TaggedScriptPubKey(source: .segwit, opcodes: [ 0, 0 ])
//        XCTAssertThrowsError(try self.manager.path(for: failScript,
//                                                      loaded: self.manager.checkLoadedState().wait()).wait()) { error in
//            switch error {
//            case is Vault.PublicKeyRepo.ScriptNotFoundError:
//                break
//            default: XCTFail()
//            }
//        }
    }
    
    func testTestData01FindPathFailSeek() {
        self.loadTestData01()
        
        let failScript = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                      index: 50_000_000,
                                      opcodes: [ 0, 0 ])
        XCTAssertFalse(
            try self.manager.checkPath(repo: self.manager.checkLoadedState()
                                        .wait()
                                        .publicKeyRepos
                                        .segwitRepo,
                                       scriptPubKey: failScript).wait()
        )
    }
    
    func testTestData01FindOutpoint() {
        self.loadTestData01()

        let outpoint: (Int) -> Tx.Outpoint = { Tx.Outpoint(transactionId: Test.CoinTransactionId, index: UInt32($0)) }
        
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(100)).wait())
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(101)).wait())
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(102)).wait())
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(200)).wait())
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(201)).wait())
        XCTAssertNoThrow(try self.manager.find(outpoint: outpoint(202)).wait())
        
        let notFound = outpoint(0x8f_ff_ff_ff)
        XCTAssertNil(try self.manager.find(outpoint: notFound).wait())
    }
    
    func testTestData01AddOutputs() {
        self.loadTestData01()
        
        func funding(num: Int, index: UInt32, opcodes: [UInt8]) -> FundingOutpoint {
            let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue, index: index, opcodes: opcodes)
            return FundingOutpoint(outpoint: .init(transactionId: Test.CoinTransactionId, index: UInt32(num)),
                                   amount: UInt64(num),
                                   scriptPubKey: scriptPubKey)
        }

        for i in (1...50) {
            guard let scriptPubKey = try? self.manager.lastOpcodes(for: .segwit).wait(),
                  let index = try? self.manager.checkLoadedState()
                    .wait()
                    .publicKeyRepos
                    .segwitRepo
                    .findIndex(for: scriptPubKey)
                    .wait()
            else {
                XCTFail()
                return
            }
            
            let f = funding(num: 2000 + i, index: index, opcodes: scriptPubKey.opcodes)
            XCTAssertNoThrow(
                try self.manager.addConfirmed(funding: f, height: 2000 + i).wait()
            )
        }
    
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .spendableCoins()
                            .wait()
                            .total(), 101575)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .total(), 101575)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingSpend
                            .total(), 202)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingReceive
                            .total(), 303)
        )

        XCTAssertNoThrow(try self.manager.consolidate(tip: 1_000_000).wait())

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available,
                           try self.manager._testingCoinRepo().wait().current.find(from: 0).wait())
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager.availableCoins()
                            .wait()
                            .available
                            .total(), 101575)
        )
        
        (2001...2050)
        .reversed()
        .forEach {
            XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(UInt64($0))))
            self.consumeScriptPubKey()
        }
    }
    
    func testTestData01Rollback() {
        self.loadTestData01()
        
        XCTAssertNoThrow(try self.manager.rollback(to: 1000).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 6)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 999).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 6)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 202).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 6)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 201).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 5)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 200).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 4)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 199).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 4)
        )
        
        XCTAssertNoThrow(try self.manager.rollback(to: 102).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 2)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 3)
        )
        
        XCTAssertNoThrow(try self.manager.rollback(to: 101).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 1)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 2)
        )
        
        XCTAssertNoThrow(try self.manager.rollback(to: 100).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 0)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 1)
        )
        
        XCTAssertNoThrow(try self.manager.rollback(to: 99).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .count, 0)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .count()
                            .wait(), 1)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 0).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
    }
    
    func testManyRowsRollback() {
        func createCoin(number: Int) -> FundingOutpoint {
            let txId: Tx.TxId = .makeHash(from: number.cVarInt)
            let outpoint: Tx.Outpoint = .init(transactionId: txId, index: 0)
            let amount = UInt64(number) + 100_000
            let source: HD.Source = number & 1 > 0
                ? HD.Source.legacySegwit
                : HD.Source.segwit
            let scriptPubKey = try! self.manager.lastOpcodes(for: source == .legacySegwit
                                                                ? .legacySegwit
                                                                : .segwit).wait()
            XCTAssertNoThrow(
                try source.repo(from: self.manager.checkLoadedState()
                                .wait()
                                .publicKeyRepos)
                .findIndex(for: scriptPubKey)
                .wait()
            )
                
            return FundingOutpoint(outpoint: outpoint,
                                   amount: amount,
                                   scriptPubKey: scriptPubKey)
        }
        
        self.createTestFiles()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())
        var state: Vault.State.LoadedState?
        XCTAssertNoThrow(
            state = try self.manager.checkLoadedState().wait()
        )

        guard let state = state
        else { XCTFail(); return }
        XCTAssertNoThrow(
            try Vault.populateAll(properties: properties,
                                  allRepos: state.publicKeyRepos,
                                  eventLoop: eventLoop).wait()
        )

        let funding = (1...100).map(createCoin(number:))
        for f in funding {
            XCTAssertNoThrow(
                try self.manager.addUnconfirmed(funding: f,
                                                height: 1000).wait()
            )
        }
        for i in (2...100).reversed() {
            XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(UInt64(i) + 100_000)))
        }
        self.consumeScriptPubKey()
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(100_001)))
        self.consumeScriptPubKey()

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo().wait()
                            .current
                            .count()
                            .wait(), 100)
        )

        for f in funding {
            XCTAssertNoThrow(
                try self.manager.addConfirmed(funding: f,
                                              height: 1000).wait()
            )
        }
        for i in (1...100).reversed() {
            XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receivePromoted(UInt64(i) + 100_000)))
        }

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo().wait()
                            .current
                            .count()
                            .wait(), 100)
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 999).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo().wait().current.count().wait(), 0)
        )

        for f in funding {
            XCTAssertNoThrow(
                try self.manager.addConfirmed(funding: f,
                                              height: 1000).wait()
            )
        }
        for i in (1...100).reversed() {
            XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(UInt64(i) + 100_000)))
        }
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo().wait()
                            .current
                            .count()
                            .wait(), 100)
        )
    }

    func testPreparePayment01() {
        self.loadTestData01()
        let addressSegwitNative = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressSegwit(GlobalFltrWalletSettings
                                                        .Network
                                                        .bech32HumanReadablePart)
        )!
        guard let prepare = try? self.manager.prepare(payment: 286,
                                                      to: addressSegwitNative,
                                                      costRate: 0.01,
                                                      height: 1000,
                                                      threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(prepare.funds, 300)
        XCTAssertEqual(prepare.transactionCost, 2)
        XCTAssertEqual(prepare.refund?.value, 12) // Dust is configuered to 10
        XCTAssertLessThanOrEqual(prepare.funds - prepare.vout.map(\.value).reduce(0, +) - prepare.transactionCost, 10)
    }
    
    func testPreparePayment02() {
        self.loadTestData01()
        let addressSegwitNative = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressSegwit(GlobalFltrWalletSettings
                                                        .Network
                                                        .bech32HumanReadablePart)
        )!
        guard let prepare = try? self.manager.prepare(payment: 288,
                                                      to: addressSegwitNative,
                                                      costRate: 0.00990,
                                                      height: 1000,
                                                      threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(prepare.funds, 300)
        XCTAssertEqual(prepare.transactionCost, 2)
        XCTAssertNil(prepare.refund)
        // The lost amount is one greater than configured dust but is due to a decrease in transaction size and cost
        // from 3 to 2 with only one vout as opposed to recipient + refund
        XCTAssertEqual(prepare.funds - prepare.vout.map(\.value).reduce(0, +) - prepare.transactionCost, 10)
    }
    
    func testPay01() {
        self.loadTestData01()
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .spendableCoins()
                            .wait()
                            .total(), 300)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .total(), 300)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingSpend
                            .total(), 202)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingReceive
                            .total(), 303)
        )

        let addressLegacy = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressLegacyPKH(GlobalFltrWalletSettings
                                                            .Network
                                                            .legacyAddressPrefix)
        )!
        XCTAssertNoThrow(try self.manager.pay(amount: 50, to: addressLegacy, costRate: 0.01, height: 2_000).wait())

        var coinRepo: Vault.CoinRepoPair!
        XCTAssertNoThrow(coinRepo = try self.manager._testingCoinRepo().wait())
        var last: HD.Coin!
        XCTAssertNoThrow(
            last = try coinRepo.current.range()
            .flatMap({ range in
                coinRepo.current.find(id: range.upperBound - 1)
            })
            .wait()
        )
        XCTAssertEqual(last.amount, 48)
        
        let scriptPubKey = ScriptPubKey(tag: HD.Source.taprootChange.rawValue,
                                        index: 10,
                                        opcodes: "512087967b463e92703115de2f8821d1129a4296ce5303ce7e1a165c1bde41543689".hex2Bytes)
        let refund: FundingOutpoint = .init(outpoint: last.outpoint,
                                            amount: last.amount,
                                            scriptPubKey: scriptPubKey)
        
        // deal with (ignore) duplicate unconfirmed notifications
        XCTAssertNoThrow(try self.manager.addUnconfirmed(funding: refund, height: 2_000).wait())
        // now confirmed notifications
        XCTAssertNoThrow(try self.manager.addConfirmed(funding: refund, height: 2_001).wait())
        // update total funds
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .spendableCoins()
                            .wait()
                            .total(), 248)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .available
                            .total(), 248)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingSpend
                            .total(), 302)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager
                            .availableCoins()
                            .wait()
                            .pendingReceive
                            .total(), 303)
        )
        
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receivePromoted(48)))
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        self.consumeScriptPubKey()
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.spentUnconfirmed(100)))
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(48)))
        self.consumeScriptPubKey()
    }
    
    func testPayDustAmount() {
        self.loadTestData01()
        
        let addressSegwitCompatible = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressLegacyWPKH(GlobalFltrWalletSettings
                                                            .Network
                                                            .legacyAddressPrefix)
        )!
        
        XCTAssertThrowsError(
            try self.manager.pay(amount: GlobalFltrWalletSettings.DustAmount,
                                 to: addressSegwitCompatible,
                                 costRate: 0.1,
                                 height: 2_009).wait()
        ) { error in
            switch error {
            case Vault.PaymentError.dustAmount:
                break
            default:
                XCTFail()
            }
        }
        
        XCTAssertNoThrow(
            try self.manager.pay(amount: GlobalFltrWalletSettings.DustAmount + 1,
                                 to: addressSegwitCompatible,
                                 costRate: 0.1,
                                 height: 2_010).wait()
        )
        
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.spentUnconfirmed(200)))
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(174)))
        self.consumeScriptPubKey()
    }
    
    func testPayIllegalCostRate() {
        self.loadTestData01()
        
        let addressSegwitNative = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressSegwit(GlobalFltrWalletSettings
                                                        .Network
                                                        .bech32HumanReadablePart)
        )!
        
        XCTAssertThrowsError(
            try self.manager.pay(amount: 50,
                                 to: addressSegwitNative,
                                 costRate: 0,
                                 height: 2_001).wait()
        ) { error in
            switch error {
            case Vault.PaymentError.illegalCostRate:
                break
            default:
                XCTFail()
            }
        }
    }
    
    func testPayNotEnoughFunds() {
        self.loadTestData01()
        
        let addressSegwitNative = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressSegwit(GlobalFltrWalletSettings
                                                        .Network
                                                        .bech32HumanReadablePart)
        )!
        
        XCTAssertThrowsError(
            try self.manager.pay(amount: 500,
                                 to: addressSegwitNative,
                                 costRate: 1,
                                 height: 2_001).wait()
        ) { error in
            switch error {
            case Vault.PaymentError.notEnoughFunds(txCost: 244):
                break
            default:
                XCTFail()
            }
        }

        XCTAssertThrowsError(
            try self.manager.pay(amount: 11,
                                 to: addressSegwitNative,
                                 costRate: 5000,
                                 height: 2_001).wait()
        ) { error in
            switch error {
            case Vault.PaymentError.transactionCostGreaterThanFunds:
                break
            default:
                XCTFail("\(error)")
            }
        }
    }
    
    func testAppendCoin() {
        self.loadTestData01()
        
        _ = HD.Coin(outpoint: .init(transactionId: .zero, index: 0),
                    amount: 1,
                    receivedState: .confirmed(1),
                    spentState: .unspent,
                    source: .taprootChange,
                    path: 1)
    }
    
    func testFindOutpoint() {
        self.loadTestData01()
        
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 100))
                .wait()
        )
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 101))
                .wait()
        )
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 102))
                .wait()
        )
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 200))
                .wait()
        )
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 201))
                .wait()
        )
        XCTAssertNoThrow(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                        index: 202))
                .wait()
        )
    }
    
    func testFindOutpointFail() {
        self.loadTestData01()
        
        XCTAssertNil(
            try self.manager.find(outpoint: Tx.Outpoint(transactionId: .zero,
                                                        index: 0))
                .wait()
        )
    }
    
    func testPreparePaymentData01() {
        self.loadTestData01()
        
        _ = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressLegacyPKH(GlobalFltrWalletSettings
                .Network
                .legacyAddressPrefix)
        )!
        let addressSegwitNative = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressSegwit(GlobalFltrWalletSettings
                .Network
                .bech32HumanReadablePart)
        )!
        _ = Vault.decode(
            address: PublicKeyHash(DSA.PublicKey(.G)).addressLegacyWPKH(GlobalFltrWalletSettings
                .Network
                .legacyAddressPrefix)
        )!
        
        guard let p1 = try? self.manager.prepare(payment: 286,
                                                 to: addressSegwitNative,
                                                 costRate: 0.01,
                                                 height: 1000,
                                                 threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(p1.funds, 300)
        XCTAssertEqual(p1.transactionCost, 2)
        XCTAssertEqual(p1.refund?.value, 12) // Dust is configuered to 10

        guard let p2 = try? self.manager.prepare(payment: 288,
                                                 to: addressSegwitNative,
                                                 costRate: 0.01,
                                                 height: 1000,
                                                 threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(p2.funds, 300)
        XCTAssertEqual(p2.transactionCost, 2)
        XCTAssertNil(p2.refund)
        XCTAssertLessThanOrEqual(p2.funds - p2.recipient.value - p2.transactionCost, 11)
    }
    
    func testEmptyCoinRepoAddConfirmed() {
        self.loadTestDataEmptyCoinRepo()
        
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: "00148f6aa776369afe7e0d93d11820313bfee57bd6d7".hex2Bytes)
        let fundingBogus: FundingOutpoint = .init(outpoint: Tx.Outpoint(transactionId: .zero, index: 1),
                                                  amount: 1000,
                                                  scriptPubKey: scriptPubKey)
        
        XCTAssertNoThrow(
            try self.manager.addConfirmed(funding: fundingBogus, height: 2_000).wait()
        )
        
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(1000)))
        self.consumeScriptPubKey()
    }
    
    func testEmptyCoinRepoAddUnConfirmed() {
        self.loadTestDataEmptyCoinRepo()
        
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: "00148f6aa776369afe7e0d93d11820313bfee57bd6d7".hex2Bytes)
        let fundingBogus: FundingOutpoint = .init(outpoint: Tx.Outpoint(transactionId: .zero, index: 1),
                                                  amount: 1000,
                                                  scriptPubKey: scriptPubKey)
        
        XCTAssertNoThrow(
            try self.manager.addUnconfirmed(funding: fundingBogus, height: 2_000).wait()
        )
        
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(1000)))
        self.consumeScriptPubKey()
    }
    
    func testVerifyPayWithRefund() {
        let nodes = self.loadTestDataEmptyCoinRepo()
        var subNode = nodes.nodeDictionary[.segwit]!
        let pubKey = subNode.childKey(index: 5).key.public
        let pkh = PublicKeyHash(DSA.PublicKey(pubKey))
        let opcodes = pkh.scriptPubKeyWPKH
        
        
        let id: Tx.TxId = .big("48c8f7f2603c1b1998915e0e6c2660eeeb4eb73a13cb55f3cc87e74e44ec03a2".hex2Bytes)
        let outpoint = Tx.Outpoint(transactionId: id, index: 1)
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 5,
                                        opcodes: opcodes)
        let funding: FundingOutpoint = .init(outpoint: outpoint,
                                             amount: 10000,
                                             scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(
            try self.manager.addConfirmed(funding: funding, height: 1935417).wait()
        )
        
        
        XCTAssertNoThrow(
            try self.manager.pay(amount: 1000,
                                 to: AddressDecoder(decoding: "tb1qd0j2wuvr502gxlpf2vhgz5n8qfw6t0cnamd0p8", network: .testnet)!,
                                 costRate: 4,
                                 height: 1935418).wait()
        )

        XCTAssertGreaterThan(self.transactionBuffer.count, 0)
        
        guard let segwitTransaction = self.transactionBuffer.first
        else {
            XCTFail()
            return
        }
        
        let prevouts = [ Tx.Out(value: 10_000, scriptPubKey: [ OpCodes.OP_0, 0x20 ]
                                + "97527302a9915a62dd4e8ef50051ad9b81ff55f8".hex2Bytes) ]
        XCTAssert(segwitTransaction.verifySignature(index: 0, prevouts: prevouts))
        XCTAssertEqual(segwitTransaction.vout.count, 2)
        
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.spentUnconfirmed(10000)))
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(8390)))
        self.consumeScriptPubKey()
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(10000)))
        (0..<5).forEach { _ in self.consumeScriptPubKey() }
    }

    func testVerifyTransactionWithoutRefund() {
        self.loadTestDataEmptyCoinRepo()
        
        let id: Tx.TxId = .big("48c8f7f2603c1b1998915e0e6c2660eeeb4eb73a13cb55f3cc87e74e44ec03a2".hex2Bytes)
        let outpoint = Tx.Outpoint(transactionId: id, index: 1)
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1, // TODO: unknown index, needs fix
                                        opcodes: "00148f6aa776369afe7e0d93d11820313bfee57bd6d7".hex2Bytes)
        let funding: FundingOutpoint = .init(outpoint: outpoint,
                                             amount: 10000,
                                             scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(
            try self.manager.addConfirmed(funding: funding, height: 1935417).wait()
        )
        
        
        XCTAssertNoThrow(
            try self.manager.pay(amount: 9435,
                                 to: AddressDecoder(decoding: "tb1qd0j2wuvr502gxlpf2vhgz5n8qfw6t0cnamd0p8",
                                                    network: .testnet)!,
                                 costRate: 4,
                                 height: 1935418).wait()
        )

        XCTAssertGreaterThan(self.transactionBuffer.count, 0)
        
        guard let segwitTransaction = self.transactionBuffer.first
        else {
            XCTFail()
            return
        }

        let prevouts = [ Tx.Out(value: 10_000, scriptPubKey: [ OpCodes.OP_0, 0x20 ]
                                + "97527302a9915a62dd4e8ef50051ad9b81ff55f8".hex2Bytes) ]
        XCTAssert(segwitTransaction.verifySignature(index: 0, prevouts: prevouts))
        XCTAssertEqual(segwitTransaction.vout.count, 1)
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.spentUnconfirmed(10000)))
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(10000)))
        self.consumeScriptPubKey()
    }
    
    func testPrivateKeysAddConfirmedForTestData01() {
        self.loadTestData01()
        
        XCTAssertNoThrow(
            try (UInt32(1)...20).forEach { i in
                guard let legacy = try? self.manager.privateECCKey(for: GlobalFltrWalletSettings
                                                                        .BIP39LegacySegwitAccountPath
                                                                      + [ .normal(0), .normal(i) ])
                        .wait(),
                      let segwit = try? self.manager.privateECCKey(for: GlobalFltrWalletSettings
                                                                        .BIP39SegwitAccountPath
                                                                      + [ .normal(0), .normal(i) ])
                        .wait()
                else {
                    XCTFail()
                    return
                }
                
                let pkhLegacy = PublicKeyHash(DSA.PublicKey(.init(legacy)))
                let pkhSegwit = PublicKeyHash(DSA.PublicKey(.init(segwit)))
                
                try [ HD.Source.legacySegwit, .segwit ].forEach { tag in
                    let opcode: [UInt8] = {
                        switch tag {
                        case .legacy0, .legacy0Change,
                                .legacy44, .legacy44Change,
                                .legacySegwitChange,
                                .segwit0, .segwit0Change,
                                .segwitChange,
                                .taproot, .taprootChange:
                            preconditionFailure()
                        case .legacySegwit:
                            return pkhLegacy.scriptPubKeyLegacyWPKH
                        case .segwit:
                            return pkhSegwit.scriptPubKeyWPKH
                        }
                    }()
                    
                    
                    let txId: Tx.TxId = .little((0..<32).map({ _ in .random(in: .min ... .max) }))
                    let outpoint: Tx.Outpoint = .init(transactionId: txId, index: 1)
                    let scriptPubKey = ScriptPubKey(tag: tag.rawValue,
                                                    index: i,
                                                    opcodes: opcode)
                    let funding: FundingOutpoint = .init(outpoint: outpoint,
                                                         amount: UInt64(1000),
                                                         scriptPubKey: scriptPubKey)
                    _ = try self.manager.addConfirmed(funding: funding, height: 1935417).wait()
                    XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(1000)))
                }
            }
        )
        
        (0..<22).forEach { _ in self.consumeScriptPubKey() }
        
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager._testingCoinRepo().wait()
                    .current.find(from: 0).wait()
                    .count,
                46
            )
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager.spendableCoins()
                    .wait()
                    .total(),
                40300)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager.availableCoins()
                    .wait()
                    .available
                    .total(),
                40300)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager.availableCoins()
                    .wait()
                    .pendingSpend
                    .total(),
                202)
        )
        
        (0..<18).forEach { _ in self.consumeScriptPubKey() }
    }
    
    func testPrepareNoRefund() {
        self.loadTestData02()

        guard let address = AddressDecoder(decoding: "tb1qd0j2wuvr502gxlpf2vhgz5n8qfw6t0cnamd0p8", network: .testnet),
              let predictor = try? self.manager.prepare(payment: 96,
                                                        to: address,
                                                        costRate: 1.4,
                                                        height: 1000,
                                                        threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }

        XCTAssertEqual(predictor.transactionCost, 1903)
        XCTAssertEqual(predictor.vin.count, 20)
        XCTAssertNil(predictor.refund)
        XCTAssertEqual(predictor.vout.first?.value, 96)
        XCTAssertEqual(predictor.vout.first?.scriptPubKey, address.scriptPubKey)
    }
    
    func testPrepareSelectOptimalRefund() {
        self.loadTestData02()
        
        guard let address = AddressDecoder(decoding: "tb1qd0j2wuvr502gxlpf2vhgz5n8qfw6t0cnamd0p8", network: .testnet),
              let predictor = try? self.manager.prepare(payment: 133,
                                                        to: address,
                                                        costRate: 0.00000001,
                                                        height: 1000,
                                                        threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }

        XCTAssertEqual(predictor.funds, 200)
        XCTAssertEqual(predictor.refund.map { $0.value }, 67)
        
        guard let predictorUndershoot = try? self.manager.prepare(payment: 134,
                                                                  to: address,
                                                                  costRate: 0.00000001,
                                                                  height: 1000,
                                                                  threadPool: self.threadPool).wait()
        else {
            XCTFail()
            return
        }

        XCTAssertEqual(predictorUndershoot.funds, 300)
        XCTAssertEqual(predictorUndershoot.refund.map { $0.value }, 166)
    }

    func loadStates() -> Vault.State.LoadedState? {
        try? self.manager.checkLoadedState().wait()
    }

    func testNextPubKeyTaprootMulti() {
        self.loadTestData01()

        guard let loaded = loadStates()
        else {
            XCTFail()
            return
        }

        XCTAssertNoThrow(
            try loaded.publicKeyRepos.taprootRepo
            .__makeNextPubKeys(base: 11,
                               count: 3,
                               properties: loaded.properties,
                               wallet: loaded.walletEventHandler)
            .wait()
        )
        
        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.taproot.rawValue,
                                     index: 14,
                                     opcodes: "5120112e4dc07f43f9eb8d2e6887b645c5d3cb9fddb9c1c8c5e2118a83b366595afd".hex2Bytes)
                       )
        )
        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.taproot.rawValue,
                                     index: 13,
                                     opcodes: "5120521676eea43a81ad472b17b04655afea90cb1a2262ca9cba1da17bb8e5e9d319".hex2Bytes)
                       )
        )
        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.taproot.rawValue,
                                     index: 12,
                                     opcodes: "512028f2ebc43150a087a28359e2c00b7ec6088aa8d84af074220441fa53ae3a4c6f".hex2Bytes)
                       )
        )

    }
    
    func testNextPubkeyLegacySegwit() {
        self.loadTestData01()

        guard let loaded = loadStates()
        else {
            XCTFail()
            return
        }

        XCTAssertNoThrow(
            try loaded.publicKeyRepos.legacySegwitRepo
            .__makeNextPubKeys(base: 11,
                               count: 1,
                               properties: loaded.properties,
                               wallet: loaded.walletEventHandler)
            .wait()
        )
        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.legacySegwit.rawValue,
                                     index: 12,
                                     opcodes: "a9144b895ae0cbb70437ab93539db50322298a9b29dc87".hex2Bytes)
                       )
        )
    }

    func testNextPubkeySegwit() {
        self.loadTestData01()

        guard let loaded = loadStates()
        else {
            XCTFail()
            return
        }

        XCTAssertNoThrow(
            try loaded.publicKeyRepos.segwitRepo
            .__makeNextPubKeys(base: 11,
                               count: 1,
                               properties: loaded.properties,
                               wallet: loaded.walletEventHandler)
            .wait()
        )

        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                     index: 12,
                                     opcodes: "0014c856fea6f1848c71f7bb659044867ba5ef2a6eba".hex2Bytes)
                       )
        )
    }
    
    func testNextPubkeyTaprootChange() {
        self.loadTestData01()

        guard let loaded = loadStates()
        else {
            XCTFail()
            return
        }

        XCTAssertNoThrow(
            try loaded.publicKeyRepos.taprootChangeRepo
            .__makeNextPubKeys(base: 11,
                               count: 1,
                               properties: loaded.properties,
                               wallet: loaded.walletEventHandler)
            .wait()
        )
        XCTAssertEqual(self.eventTestBuffer.popLast(),
                       WalletEvent.scriptPubKey(
                        ScriptPubKey(tag: HD.Source.taprootChange.rawValue,
                                     index: 12, // 11 + 1
                                     opcodes: "5120b9a78031fb1f1d3523a97d57299a5d91b613e94b04326f927e7525cb55768cdd".hex2Bytes)
                       )
        )
    }

    func testNextPubkeyTaprootFailEvent() {
        self.loadTestData01()

        guard let loaded = loadStates()
        else {
            XCTFail()
            return
        }

        self.failNextWalletEvent = true

        XCTAssertThrowsError(
            try loaded.publicKeyRepos.taprootRepo
            .__makeNextPubKeys(base: 11,
                               count: 1,
                               properties: loaded.properties,
                               wallet: loaded.walletEventHandler)
            .wait()
        ) { error in
            switch error {
            case is WalletEventFail:
                break
            default:
                XCTFail()
            }
        }
        
        self.consumeScriptPubKey()
    }
    
    func testReceiveConfirmedEvent() {
        let nodes = self.loadTestData01()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: self.opcodes(from: nodes, source: .segwit, index: 1))
        let funding = FundingOutpoint(outpoint: .init(transactionId: Test.CoinTransactionId, index: 0),
                                      amount: 100,
                                      scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(try self.manager.addConfirmed(funding: funding, height: 2_000).wait())
        
        XCTAssertEqual(self.eventTestBuffer.count, 2)
        XCTAssertEqual(self.eventTestBuffer.popLast(), WalletEvent.tally(TallyEvent.receiveConfirmed(100)))
        self.consumeScriptPubKey()

        // Ensure no rollback occurs
        XCTAssertNoThrow(
            XCTAssertNotNil(
                try self.manager.find(outpoint: .init(transactionId: Test.CoinTransactionId,
                                                      index: 0)).wait()
            )
        )
        XCTAssertNoThrow(try self.manager.rollback(to: 2001).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
        XCTAssertNoThrow(
            XCTAssertNotNil(
                try self.manager.find(outpoint: .init(transactionId: Test.CoinTransactionId,
                                                      index: 0)).wait()
            )
        )

        XCTAssertNoThrow(try self.manager.rollback(to: 2000).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
        XCTAssertNoThrow(
            XCTAssertNil(
                try self.manager.find(outpoint: .init(transactionId: Test.CoinTransactionId,
                                                      index: 0)).wait()
            )
        )

        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    func testReceiveConfirmedEventTaprootRebuffer() {
        let nodes = self.loadTestData01()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.taproot.rawValue,
                                        index: 10,
                                        opcodes: self.opcodes(from: nodes, source: .taproot, index: 10))
        let funding = FundingOutpoint(outpoint: .init(transactionId: Test.CoinTransactionId, index: 0),
                                      amount: 100,
                                      scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(try self.manager.addConfirmed(funding: funding, height: 2_000).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), WalletEvent.tally(TallyEvent.receiveConfirmed(100)))
        (0..<10).forEach { _ in self.consumeScriptPubKey() }
    }
    
    func testReceiveUnconfirmedEvent() {
        let nodes = self.loadTestData01()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: self.opcodes(from: nodes, source: .segwit, index: 1))
        let funding: FundingOutpoint = .init(outpoint: .init(transactionId: Test.CoinTransactionId, index: 0),
                                             amount: 100,
                                             scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(try self.manager.addUnconfirmed(funding: funding, height: 2_000).wait())
        
        XCTAssertEqual(self.eventTestBuffer.count, 2)
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(100)))
        self.consumeScriptPubKey()
        
        // Duplicate receive, should only yield log message and no event
        XCTAssertNoThrow(try self.manager.addUnconfirmed(funding: funding, height: 2_000).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    func testReceivePromotedEvent() {
        let nodes = self.loadTestData01()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: self.opcodes(from: nodes, source: .segwit, index: 1))
        let funding: FundingOutpoint = .init(outpoint: .init(transactionId: Test.CoinTransactionId, index: 0),
                                             amount: 100,
                                             scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(try self.manager.addUnconfirmed(funding: funding, height: 2_000).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 2)
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(100)))

        XCTAssertNoThrow(try self.manager.addConfirmed(funding: funding, height: 2_000).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 2)
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receivePromoted(100)))
        
        self.consumeScriptPubKey()
    }
    
    func testSpentConfirmedEvent() {
        self.loadTestData01()
        
        let outpoint = Tx.Outpoint(transactionId: Test.CoinTransactionId, index: 100)
        let segwitTx = Tx.makeSegwitTx(for: outpoint)
        XCTAssertNoThrow(try self.manager.spentConfirmed(outpoint: outpoint,
                                                         height: 2_000,
                                                         changeIndices: [],
                                                         tx: segwitTx).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 1)
        XCTAssertEqual(self.eventTestBuffer.popLast(), WalletEvent.tally(TallyEvent.spentConfirmed(100)))

        // Duplicate spend, should only yield log message and no event
        XCTAssertNoThrow(try self.manager.spentConfirmed(outpoint: outpoint,
                                                         height: 2_000,
                                                         changeIndices: [],
                                                         tx: segwitTx).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    func testSpentUnconfirmedEvent() {
        self.loadTestData01()

        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager.pendingTransactions().wait().count, 1)
        )
        let outpoint = Tx.Outpoint(transactionId: Test.CoinTransactionId, index: 200)
        let segwitTx = Tx.makeSegwitTx(for: outpoint)
        XCTAssertNoThrow(try self.manager.spentUnconfirmed(outpoint: outpoint,
                                                           height: 2_000,
                                                           changeIndices: [],
                                                           tx: segwitTx).wait())
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager.pendingTransactions().wait().count, 2)
        )
        XCTAssertNoThrow(
            XCTAssert(try self.manager.pendingTransactions().wait().contains(segwitTx))
        )
        
        XCTAssertEqual(self.eventTestBuffer.count, 1)
        XCTAssertEqual(self.eventTestBuffer.popLast(), WalletEvent.tally(TallyEvent.spentUnconfirmed(200)))

        // Duplicate spend, should only yield log message and no event
        XCTAssertNoThrow(try self.manager.spentUnconfirmed(outpoint: outpoint,
                                                           height: 2_000,
                                                           changeIndices: [],
                                                           tx: segwitTx).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    func testSpentPromotedEvent() {
        self.loadTestData01()

        let outpoint = Tx.Outpoint(transactionId: Test.CoinTransactionId, index: 202)
        let segwitTx = Tx.makeSegwitTx(for: outpoint)
        XCTAssertNoThrow(try self.manager.spentConfirmed(outpoint: outpoint,
                                                         height: 2_000,
                                                         changeIndices: [],
                                                         tx: segwitTx).wait())
        
        XCTAssertEqual(self.eventTestBuffer.count, 1)
        XCTAssertEqual(self.eventTestBuffer.popLast(), WalletEvent.tally(TallyEvent.spentPromoted(202)))

        // Duplicate spend, should only yield log message and no event
        XCTAssertNoThrow(try self.manager.spentConfirmed(outpoint: outpoint,
                                                         height: 2_000,
                                                         changeIndices: [],
                                                         tx: segwitTx).wait())
        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    // We do not yet allow spending uncofirmed coins, meaning
    // outputs that have not made it into a block yet
    func testSpentPending() {
        self.loadTestData01()
        let pendingOutpoint = Tx.Outpoint(transactionId: Test.CoinTransactionId, index: 102)

        guard let allCoinsBefore = try? self.manager._testingCoinRepo().wait().current.find(from: 0).wait()
        else { XCTFail(); return }

        let segwitTx = Tx.makeSegwitTx(for: pendingOutpoint)
        // No error is thrown, however no state change is produced.
        // Only update once the transaction is received/confirmed in a block.
        XCTAssertNoThrow(try self.manager.spentUnconfirmed(outpoint: pendingOutpoint,
                                                           height: 2_000,
                                                           changeIndices: [],
                                                           tx: segwitTx).wait())
        guard let allCoinsAfter = try? self.manager._testingCoinRepo().wait().current.find(from: 0).wait()
        else { XCTFail(); return }

        XCTAssertEqual(allCoinsBefore, allCoinsAfter)
        XCTAssertEqual(self.eventTestBuffer.count, 0)
    }
    
    func testPendingAmount() {
        self.loadTestData01()

        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager
                    .availableCoins()
                    .wait()
                    .pendingReceive
                    .total(), 303)
        )

        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager
                    .availableCoins()
                    .wait()
                    .pendingSpend
                    .total(), 202)
        )

        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager
                    .spendableCoins()
                    .wait()
                    .total(), 100 + 200)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager
                    .availableCoins()
                    .wait()
                    .available
                    .total(), 300)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager
                    .availableCoins()
                    .wait()
                    .pendingSpend
                    .total(), 202)
        )
    }
    
    func testSpendRollbackUnconfirmed() {
        self.loadTestDataRollback01()
        
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: "00148f6aa776369afe7e0d93d11820313bfee57bd6d7".hex2Bytes)
        let fundingBogus: FundingOutpoint = .init(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                                        index: 110),
                                                  amount: 1_000,
                                                  scriptPubKey: scriptPubKey)

        XCTAssertNoThrow(
            try self.manager.addUnconfirmed(funding: fundingBogus, height: 2_000).wait()
        )
        
        self.consumeScriptPubKey()
    }

    func testSpendRollbackConfirmed() {
        self.loadTestDataRollback01()
        
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: "00148f6aa776369afe7e0d93d11820313bfee57bd6d7".hex2Bytes)
        let fundingBogus: FundingOutpoint = .init(outpoint: Tx.Outpoint(transactionId: Test.CoinTransactionId,
                                                                        index: 110),
                                                  amount: 1_000,
                                                  scriptPubKey: scriptPubKey)
        
        XCTAssertNoThrow(
            try self.manager.addConfirmed(funding: fundingBogus, height: 2_000).wait()
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.manager._testingCoinRepo()
                            .wait()
                            .current
                            .find(from: 0)
                            .wait()
                            .last?
                            .spentState
                            .isPending, true)
        )

        self.consumeScriptPubKey()
        XCTAssertTrue(self.eventTestBuffer.isEmpty)
    }
    
    func testRollbackPendingSpent() {
        self.loadTestData01()
        
        XCTAssertNoThrow(
            try self.manager.rollback(to: 201).wait()
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(
                try self.manager._testingCoinRepo()
                    .wait()
                    .current
                    .find(from: 0)
                    .wait()
                    .last?
                    .receivedState,  .rollback(202)
            )
        )
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
    }
    
    func testAddUnconfirmedThenRollbackThenAddConfirmed() {
        self.createTestFiles()
        
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.threadPool)
        XCTAssertNoThrow(try self.manager.load(properties: properties).wait())

        guard let loaded = self.loadStates()
        else { XCTFail(); return }
        
        XCTAssertNoThrow(
            try loaded.publicKeyRepos.segwitRepo.rebuffer(properties: loaded.properties,
                                                          walletEventHandler: loaded.walletEventHandler)
            .wait()
        )

        guard let scriptPubKey = try? self.manager.lastOpcodes(for: .segwit).wait()
        else { XCTFail(); return }
        let funding = FundingOutpoint(outpoint: .init(transactionId: Test.CoinTransactionId, index: UInt32(1)),
                                      amount: UInt64(10_000),
                                      scriptPubKey: scriptPubKey)
        XCTAssertNoThrow(try self.manager.addUnconfirmed(funding: funding, height: 2).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveUnconfirmed(10_000)))
        XCTAssertNoThrow(try self.manager.rollback(to: 1).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.rollback))
        XCTAssertNoThrow(try self.manager.addConfirmed(funding: funding, height: 2).wait())
        XCTAssertEqual(self.eventTestBuffer.popLast(), .tally(.receiveConfirmed(10_000)))
        (0..<12).forEach { _ in self.consumeScriptPubKey() }
    }
}
