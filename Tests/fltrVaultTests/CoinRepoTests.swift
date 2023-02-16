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
import Foundation
import fltrTx
@testable import fltrVault
import NIO
import NIOTransportServices
import VaultTestLibrary
import XCTest

final class CoinRepoTests: XCTestCase {
    var nioFileHandle1: NIOFileHandle!
    var nioFileHandle2: NIOFileHandle!
    var nioThreadPool: NIOThreadPool!
    var fileIO: NonBlockingFileIOClient!
    var coinRepo: Vault.CoinRepoPair!
    var niots: NIOTSEventLoopGroup!
    var eventLoop: EventLoop!
    var switchEvent: Int!
        
    override func setUp() {
        GlobalFltrWalletSettings = .test
        self.switchEvent = 0
        self.nioThreadPool = NIOThreadPool(numberOfThreads: 2)
        self.nioThreadPool?.start()
        self.fileIO = NonBlockingFileIOClient.live(self.nioThreadPool)
        let path = URL(fileURLWithPath: Test.CoinOne).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: Test.CoinOne)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Test.CoinOne))
        XCTAssertNoThrow(self.nioFileHandle1 = try NIOFileHandle(path: Test.CoinOne,
                                                                 mode: [.read, .write, ],
                                                                 flags: .allowFileCreation(posixMode: 0o664)))
        try? FileManager.default.removeItem(atPath: Test.CoinTwo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Test.CoinTwo))
        XCTAssertNoThrow(self.nioFileHandle2 = try NIOFileHandle(path: Test.CoinTwo,
                                                                 mode: [.read, .write, ],
                                                                 flags: .allowFileCreation(posixMode: 0o664)))
        self.niots = NIOTSEventLoopGroup(loopCount: 1)
        self.eventLoop = self.niots.next()
        
        let coinRepo1 = Vault.CoinRepo(fileHandle: try! self.nioFileHandle1.duplicate(),
                                        nonBlockingFileIO: self.fileIO,
                                        eventLoop: self.eventLoop)
        let coinRepo2 = Vault.CoinRepo(fileHandle: try! self.nioFileHandle2.duplicate(),
                                        nonBlockingFileIO: self.fileIO,
                                        eventLoop: self.eventLoop)
        self.coinRepo = Vault.CoinRepoPair(current: coinRepo1, backup: coinRepo2, switch: self.switchTest)
    }
    
    override func tearDown() {
        self.switchEvent = nil
        XCTAssertNoThrow(try self.coinRepo.close().wait())
        self.coinRepo = nil
        XCTAssertNoThrow(try self.nioFileHandle1.close())
        self.nioFileHandle1 = nil
        XCTAssertNoThrow(try self.nioFileHandle2.close())
        self.nioFileHandle2 = nil
        self.fileIO = nil
        XCTAssertNoThrow(try self.nioThreadPool.syncShutdownGracefully())
        self.eventLoop = nil
        XCTAssertNoThrow(try self.niots.syncShutdownGracefully())
        self.niots = nil
    }

    func switchTest() -> Void {
        self.switchEvent += 1
    }
    
    func removeFiles() {
        try? Test.removeCoinRepoFiles()
        try? Test.removePublicKeyRepoFiles()
    }

    func testSpent() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 1000))
        
        guard let readBack = try? self.coinRepo.current.find(from: 0, through: 999).wait()
        else {
            XCTFail()
            return
        }
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.spendableTally()
                            .wait()
                            .total(), 1000)
        )
        
        XCTAssertNoThrow(
            try readBack
            .dropLast()
            .forEach { data in
                let segwitTx = Tx.makeSegwitTx(for: data.outpoint)
                let spent: HD.Coin.SpentState = .pending(HD.Coin.Spent(height: 200_000, changeOuts: [], tx: segwitTx))
                XCTAssertEqual(try self.coinRepo.current.spent(id: data.id, state: spent).wait(),
                               TallyEvent.spentUnconfirmed(1))
            }
        )

        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.spendableTally()
                            .wait()
                            .total(), 1)
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .available
                            .total(), 1)
        )

        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .pendingSpend
                            .total(), 999)
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .pendingReceive
                            .total(), 0)
        )
        
        XCTAssertNoThrow(
            try readBack
            .dropLast()
            .forEach { data in
                let segwitTx = Tx.makeSegwitTx(for: data.outpoint)
                let spent: HD.Coin.SpentState = .spent(.init(height: 200_000, changeOuts: [], tx: segwitTx))
                XCTAssertEqual(try self.coinRepo.current.spent(id: data.id, state: spent).wait(),
                               TallyEvent.spentPromoted(1))
            }
        )

        let segwitTx = Tx.makeSegwitTx(for: readBack.last!.outpoint)
        let spent: HD.Coin.SpentState = .spent(.init(height: 200_001, changeOuts: [], tx: segwitTx))
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.spent(id: readBack.last!.id,
                                                           state: spent).wait(),
                           TallyEvent.spentConfirmed(1))
        
        )

        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.spendableTally()
                            .wait()
                            .total(), 0)
        )
        
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .available
                            .total(), 0)
        )

        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .pendingSpend
                            .total(), 0)
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo
                            .current
                            .fullTally()
                            .wait()
                            .pendingReceive
                            .total(), 0)
        )
    }
    
    func testFirstWithHeight() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .confirmed(1)))
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .unconfirmed(2)))
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .confirmed(3)))
        XCTAssertThrowsError(
            try coinRepo.current.firstWith(height: 0).wait()
        ) { error in
            switch error {
            case let e as File.NoExactMatchFound<HD.Coin>:
                XCTAssertEqual(e.left.id, 0)
                XCTAssertEqual(e.right.id, 0)
            default: XCTFail("\(error)")
            }
        }
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.firstWith(height: 1).wait().id,
                           0)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.firstWith(height: 2).wait().id,
                           1000)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.firstWith(height: 3).wait().id,
                           2000)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.firstWith(height: 4).wait().id,
                           2999)
        )
    }
    
    func testLastWithHeight() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .confirmed(1)))
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .unconfirmed(2)))
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current,
                                           count: 1_000,
                                           received: .confirmed(3)))
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.lastWith(height: 0).wait().id,
                           0)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.lastWith(height: 1).wait().id,
                           999)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.lastWith(height: 2).wait().id,
                           1999)
        )
        XCTAssertNoThrow(
            XCTAssertEqual(try coinRepo.current.lastWith(height: 3).wait().id,
                           2999)
        )
        XCTAssertThrowsError(
            try coinRepo.current.lastWith(height: 4).wait()
        ) { error in
            switch error {
            case let e as File.NoExactMatchFound<HD.Coin>:
                XCTAssertEqual(e.left.id, 2999)
                XCTAssertEqual(e.right.id, 2999)
            default: XCTFail("\(error)")
            }
        }
    }
    
    func testAppendWrite() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 1))
        var coin0: HD.Coin!
        XCTAssertNoThrow(
            coin0 = try self.coinRepo.current.find(id: 0).wait()
        )
        XCTAssertEqual(coin0?.id, 0)
        XCTAssertNoThrow(try self.coinRepo.current.write(coin0.rank(id: 1)).wait())
        var coin1: HD.Coin!
        XCTAssertNoThrow(coin1 = try self.coinRepo.current.find(id: 1).wait())
        
        XCTAssertNoThrow(XCTAssertEqual(try self.coinRepo.current.count().wait(), 2))
        XCTAssertNotEqual(coin0.id, coin1.id)
//        XCTAssertEqual(coin0.prevout, coin1.prevout)
        XCTAssertEqual(coin0.amount, coin1.amount)
        XCTAssertEqual(coin0.outpoint, coin1.outpoint)
        XCTAssertEqual(coin0.source, coin1.source)
        XCTAssertEqual(coin0.path, coin1.path)
        XCTAssertEqual(coin0.receivedState, coin1.receivedState)
        XCTAssertEqual(coin0.spentState, coin1.spentState)
    }
    
    func testTally() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 1000))
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.spendableTally().wait().total(), 1000)
        )
        
        func checkFullTally() throws {
            let fullTally = try self.coinRepo.current.fullTally().wait()
            XCTAssertEqual(fullTally.available.total(), 1000)
            XCTAssertEqual(fullTally.pendingReceive.total(), 0)
            XCTAssertEqual(fullTally.pendingSpend.total(), 0)
        }
        XCTAssertNoThrow(try checkFullTally())
    }
    
    func testOutpoints() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 10))
        XCTAssertNoThrow(
            XCTAssertEqual(try self.coinRepo.current.outpoints().wait().map(\.index),
                           (0..<10).map { _ in UInt32.zero })
        )
    }

    func testSwitch() {
        XCTAssertNoThrow(try self.coinRepo.switch(threadPool: self.nioThreadPool,
                                                  eventLoop: self.eventLoop).wait())
        XCTAssertEqual(self.switchEvent, 1)
    }
    
    func testWriteSwitchWrite() {
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 10))
        XCTAssertNoThrow(XCTAssertEqual(try self.coinRepo.current.count().wait(), 10))
        XCTAssertNoThrow(try self.coinRepo.switch(threadPool: self.nioThreadPool,
                                                  eventLoop: self.eventLoop).wait())
        XCTAssertNoThrow(try writeTestData(coinRepo: self.coinRepo.current, count: 20))
        XCTAssertNoThrow(XCTAssertEqual(try self.coinRepo.current.count().wait(), 20))
        XCTAssertNoThrow(try self.coinRepo.switch(threadPool: self.nioThreadPool,
                                                  eventLoop: self.eventLoop).wait())
        XCTAssertNoThrow(XCTAssertEqual(try self.coinRepo.current.count().wait(), 10))
        XCTAssertEqual(self.switchEvent, 2)
    }
    
    func testHistoryCoinData03() {
        Test.coinData03()
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.nioThreadPool)
        guard let coins = try? self.coinRepo.current.find(from: 0).wait(),
              !coins.isEmpty,
              let nodes = try? properties.loadAllNodes().wait()
        else { XCTFail(); return }

        
        var history = History.from(coins: coins, nodes: nodes)
            .pending[...]
        var current = history.popFirst()
        XCTAssertEqual(current?.outgoing, true)
        XCTAssertEqual(current?.record.address, "tb1pqypqxpq9qcrsszg2pvxq6rs0zqg3yyc5z5tpwxqergd3c8g7rusqe7ea7u")
        XCTAssertEqual(current?.record.amount, 8_001)
        
        history = History.from(coins: coins, nodes: nodes)
            .confirmed[...]
        current = history.popFirst()
        XCTAssertEqual(current?.incoming, true)
        XCTAssertEqual(current?.record.address, "tb1p4tlxkhj204q23ulx5kz0elje3cltfahfk8uw7kjyl86rewdfgh6qu6jvx5")
        XCTAssertEqual(current?.record.amount, 10_000)
        current = history.popFirst()
        XCTAssertEqual(current?.incoming, true)
        XCTAssertEqual(current?.record.address, "tb1q3a42wa3kntl8urvn6yvzqvfmlmjhh4khcr3avn")
        XCTAssertEqual(current?.record.amount, 50_000)
        current = history.popFirst()
        XCTAssertEqual(current?.incoming, true)
        XCTAssertEqual(current?.record.address, "tb1p4tlxkhj204q23ulx5kz0elje3cltfahfk8uw7kjyl86rewdfgh6qu6jvx5")
        XCTAssertEqual(current?.record.amount, 10_000)
        current = history.popFirst()
        XCTAssertEqual(current?.incoming, true)
        XCTAssertEqual(current?.record.address, "tb1p8qmrqwq2w32hjzknachyfcm8rkgzrhgd4sqlh6zccum4gvaugjtssq68hs")
        XCTAssertEqual(current?.record.amount, 10_000)
        current = history.popFirst()
        XCTAssertEqual(current?.outgoing, true)
        XCTAssertEqual(current?.record.address, "tb1pyq03u8gurvdpjxqhzc23gycjzygq7rsdps9s5zggqurq2pqrqgqsk3r239")
        XCTAssertEqual(current?.record.amount, 8_002)
        current = history.popFirst()
        XCTAssertEqual(current?.outgoing, true)
        XCTAssertEqual(current?.record.address, "tb1pqgpsgpgxquyqjzstpsxsurcszyfpx9q4zct3sxg6rvwp68slyqssn3yfga")
        XCTAssertEqual(current?.record.amount, 9_503)
        current = history.popFirst()
        XCTAssertEqual(current?.incoming, true)
        XCTAssertEqual(current?.record.address, "2NDiK6LFoJjBqgQFRFLKFm1cggXqHMbT6Zk")
        XCTAssertEqual(current?.record.amount, 10_000)
        XCTAssertNil(history.popFirst())
    }

    func testHistoryCoinData04() {
        Test.coinData04()
        
        let properties = Test.walletProperties(eventLoop: self.eventLoop,
                                               threadPool: self.nioThreadPool)
        guard let coins = try? self.coinRepo.current.find(from: 0).wait(),
              !coins.isEmpty,
              let nodes = try? properties.loadAllNodes().wait()
        else { XCTFail(); return }

        let history = History.from(coins: coins, nodes: nodes)

        XCTAssertEqual(history.pending.first?.incoming, false)
        XCTAssertEqual(history.pending.first?.record.address,
                       "tb1pqypqxpq9qcrsszg2pvxq6rs0zqg3yyc5z5tpwxqergd3c8g7rusqe7ea7u")
        XCTAssertEqual(history.pending.first?.record.amount,
                       8001)
        
        XCTAssertEqual(history.confirmed.first?.incoming, true)
        XCTAssertEqual(history.confirmed.first?.record.address,
                       "tb1q3a42wa3kntl8urvn6yvzqvfmlmjhh4khcr3avn")
        XCTAssertEqual(history.confirmed.first?.record.amount, 10000)
    }
}

func loadTestnetCoins(_ decoder: (inout ByteBuffer) -> HD.Coin) -> [HD.Coin] {
    let url = Bundle.module.url(forResource: "testcoins", withExtension: "hex")!
    let hex = try! String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
    let data = hex.hex2Bytes
    var buffer = GlobalFltrWalletSettings.NIOByteBufferAllocator.buffer(bytes: data)
    var coins: [HD.Coin] = []
    while buffer.readableBytes > 0 {
        coins.append(decoder(&buffer))
    }
    
    return coins
}

func makeTestData(count: Int) -> [HD.Coin] {
    (0..<count).map {
        let randomTransactionId = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return .init(outpoint: .init(transactionId: .little(randomTransactionId), index: 0),
                     amount: 1,
                     receivedState: .confirmed(100_000 + $0 * 10),
                     spentState: .unspent,
                     source: .taprootChange,
                     path: UInt32($0))
    }
}

func writeTestData(coinRepo: Vault.CoinRepo,
                   count: Int,
                   received: HD.Coin.ReceivedState? = nil) throws {
    try (0..<count).forEach {
        let randomTransactionId = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let testRow = HD.Coin(outpoint: .init(transactionId: .little(randomTransactionId), index: 0),
                              amount: 1,
                              receivedState: received ?? .confirmed(100_000 + $0 * 10),
                              spentState: .unspent,
                              source: .legacySegwit,
                              path: 1000)
        try coinRepo.append(testRow).wait()
    }
}

@discardableResult
func writeDuplicateHeightTestData(coinRepo: Vault.CoinRepo, count: Int) throws -> [HD.Coin] {
    var result: [HD.Coin] = []
    
    result.append(try {
        let randomTransactionId = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let testRow = HD.Coin(outpoint: .init(transactionId: .little(randomTransactionId), index: 0),
                              amount: 1,
                              receivedState: .confirmed(0),
                              spentState: .unspent,
                              source: .segwit,
                              path: 1000).rank(id: 0)
        try coinRepo.write(testRow).wait()
        
        return testRow
    }())
    
    result.append(
        contentsOf: try (1..<count).map {
            let randomTransactionId = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
            let testRow = HD.Coin(outpoint: .init(transactionId: .little(randomTransactionId), index: 0),
                                  amount: 1,
                                  receivedState: .confirmed(100_000),
                                  spentState: .unspent,
                                  source: .segwit,
                                  path: 1000).rank(id: $0)
            try coinRepo.write(testRow).wait()
            
            return testRow
        }
    )

    return result
}

