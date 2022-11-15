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
import fltrECCTesting
import fltrTx
@testable import fltrVault
import NIO
import NIOTransportServices
import XCTest


final class PublicKeyRepoTests: XCTestCase {
    var nioFileHandle: NIOFileHandle!
    var nioThreadPool: NIOThreadPool!
    var fileIO: NonBlockingFileIOClient!
    var publicKeyRepo: Vault.PublicKeyRepo!
    var sourcePublicKeyRepo: Vault.SourcePublicKeyRepo!
    var niots: NIOTSEventLoopGroup!
    var eventLoop: EventLoop!

    override func setUp() {
        self.nioThreadPool = NIOThreadPool(numberOfThreads: 2)
        self.nioThreadPool?.start()
        self.fileIO = NonBlockingFileIOClient.live(self.nioThreadPool)
        try? FileManager.default.removeItem(atPath: "/tmp/pubkeyrepo.dat")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/pubkeyrepo.dat"))
        XCTAssertNoThrow(self.nioFileHandle = try NIOFileHandle(path: "/tmp/pubkeyrepo.dat",
                                                                mode: [.read, .write, ],
                                                                flags: .allowFileCreation(posixMode: 0o664)))
        self.niots = NIOTSEventLoopGroup(loopCount: 1)
        self.eventLoop = self.niots.next()
        self.publicKeyRepo = Vault.PublicKeyRepo(nioFileHandle: try! self.nioFileHandle.duplicate(),
                                                 fileIO: self.fileIO,
                                                 eventLoop: self.eventLoop)
        self.sourcePublicKeyRepo = Vault.SourcePublicKeyRepo(repo: self.publicKeyRepo,
                                                             source: .segwit)
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.sourcePublicKeyRepo.close().wait())
        self.publicKeyRepo = nil
        self.sourcePublicKeyRepo = nil
        XCTAssertNoThrow(try self.nioFileHandle.close())
        self.nioFileHandle = nil
        self.fileIO = nil
        XCTAssertNoThrow(try self.nioThreadPool.syncShutdownGracefully())
        self.eventLoop = nil
        XCTAssertNoThrow(try self.niots.syncShutdownGracefully())
        self.niots = nil
    }

    func testFindIndex() {
        self.writeTestData()
        for i in (0...100) {
            XCTAssertNoThrow(
                XCTAssertEqual(try self.publicKeyRepo.findIndex(for: tagged(for: i)).wait(),
                               UInt32(i))
            )
        }
        XCTAssertThrowsError(try self.publicKeyRepo.findIndex(for: tagged(for: 101)).wait())
    }
    
    func testFindIndexFailEmptyOpcodes() {
        self.writeTestData()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.segwit.rawValue,
                                        index: 1,
                                        opcodes: [])
        XCTAssertThrowsError(try self.publicKeyRepo.findIndex(for: scriptPubKey).wait())
    }
    
    func testFindIndexFailInvalidSource() {
        self.writeTestData()
        let scriptPubKey = ScriptPubKey(tag: HD.Source.legacySegwit.rawValue,
                                        index: 1,
                                        opcodes: PublicKeyHash(DSA.PublicKey(.G))
                                            .scriptPubKeyWPKH)
        XCTAssertThrowsError(try self.publicKeyRepo.findIndex(for: scriptPubKey).wait())
    }

    func testWriteReadXPoint() {
        self.writeTestData()
        
        let pubKey = X.PublicKey(.G)
        let pubKeyDto = PublicKeyDTO(id: 101, point: pubKey)
        XCTAssertNoThrow(try self.publicKeyRepo.write(pubKeyDto).wait())
        var read: PublicKeyDTO!
        XCTAssertNoThrow(read = try self.publicKeyRepo.find(id: 101).wait())
        switch read.point {
        case .x(let p):
            XCTAssertEqual(p.serialize(), pubKey.serialize())
        case .ecc:
            XCTFail()
            return
        }
        XCTAssertTrue(read.isX)
        
        XCTAssertNoThrow(
            XCTAssertFalse(try self.publicKeyRepo.find(id: 100).wait().isX)
        )
    }
    
    func writeTestData() {
        XCTAssertNoThrow(
            try (0...100).forEach {
                let scalar = DSA.SecretKey(Scalar(Int($0 + 1)))
                try self.publicKeyRepo.write(id: $0, row: scalar.pubkey()).wait()
            }
        )
    }
}

fileprivate func tagged(for i: Int) -> ScriptPubKey {
    let secKey = DSA.SecretKey(Scalar(Int(i + 1)))
    let opcodes = PublicKeyHash(secKey.pubkey()).scriptPubKeyWPKH
    return ScriptPubKey(tag: HD.Source.segwit.rawValue,
                        index: UInt32(i + 1),
                        opcodes: opcodes)
}
