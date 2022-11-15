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
import Foundation
@testable import fltrVault
import VaultTestLibrary
import XCTest

final class CodableTests: XCTestCase {
    var encoder: JSONEncoder!
    var decoder: JSONDecoder!
    
    override func setUp() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    override func tearDown() {
        self.encoder = nil
        self.decoder = nil
    }
    
    func testEncodeDecodeChildNumber() {
        let master: HD.ChildNumber = .master
        let normal: HD.ChildNumber = .normal(1)
        let hardened: HD.ChildNumber = .hardened(1)
        
        let encodeMaster = Test.encode(master)
        XCTAssertEqual(Test.decode(encodeMaster), master)
        XCTAssertEqual(encodeMaster.encoded, "{\"master\":null}")
        
        let encodeNormal = Test.encode(normal)
        XCTAssertEqual(Test.decode(encodeNormal), normal)
        XCTAssertEqual(encodeNormal.encoded, "{\"normal\":1}")
        
        let encodeHardened = Test.encode(hardened)
        XCTAssertEqual(Test.decode(encodeHardened), hardened)
        XCTAssertEqual(encodeHardened.encoded, "{\"hardened\":1}")
    }
    
    func testEncodeDecodeExtendedKey() {
        let seed = HD.Seed.seed(size: 16)
        let fullNode = HD.FullNode(seed)!
        let key = fullNode.key
        
        let encodeKey = Test.encode(key)
        XCTAssertEqual(Test.decode(encodeKey).private, key.private)
        
        let neuteredKey = fullNode.neuter().key
        let encodeNeutered = Test.encode(neuteredKey)
        XCTAssertEqual(Test.decode(encodeNeutered).public, neuteredKey.public)
    }
    
    func testEncodeDecodeHDNode() {
        let seed = HD.Seed.seed(size: 16)
        let fullNode = HD.FullNode(seed)!
        let neuteredNode = fullNode.neuter()
        
        let encodeFullNode = Test.encode(fullNode)
        XCTAssertEqual(Test.decode(encodeFullNode).serialize(for: .bip44, network: .main),
                       fullNode.serialize(for: .bip44, network: .main))
        
        let encodeNeuteredNode = Test.encode(neuteredNode)
        XCTAssertEqual(Test.decode(encodeNeuteredNode).serialize(for: .bip44, network: .main),
                       neuteredNode.serialize(for: .bip44, network: .main))
    }
    
    func testEncodeDecodeHDNodeKey() {
        let seed = HD.Seed.seed(size: 16)
        let fullNode = HD.FullNode(seed)!
        let neuteredNode = fullNode.neuter()
        
        let fullKey = HD.NodeKey(fullNode.key)
        let encodeFullKey = Test.encode(fullKey)
        XCTAssertEqual(Test.decode(encodeFullKey).hash, fullKey.hash)
        
        let neuteredKey = HD.NodeKey(neuteredNode.key)
        let encodeNeuteredKey = Test.encode(neuteredKey)
        XCTAssertEqual(Test.decode(encodeNeuteredKey).hash, neuteredKey.hash)
    }
    
    func testEncodeDeccodeHDPath() {
        let empty = HD.Path.empty
        let path0: HD.Path = [ .master ]
        let path1: HD.Path = [ .master, .hardened(1), ]
        
        let encodeEmpty = Test.encode(empty)
        XCTAssertEqual(Test.decode(encodeEmpty), empty)
        XCTAssertEqual(encodeEmpty.encoded, "{\"value\":[]}")
        
        let encodePath0 = Test.encode(path0)
        XCTAssertEqual(Test.decode(encodePath0), path0)
        XCTAssertEqual(encodePath0.encoded, "{\"value\":[{\"master\":null}]}")
        
        let encodePath1 = Test.encode(path1)
        XCTAssertEqual(Test.decode(encodePath1), path1)
        XCTAssertEqual(encodePath1.encoded, "{\"value\":[{\"master\":null},{\"hardened\":1}]}")
    }
    
    func testEncodeDecodeWalletSeedCodable() {
        let seed0 = Vault.WalletSeedCodable(entropy: [], language: .japanese)
        let seed1 = Vault.WalletSeedCodable(entropy: (0..<16).map(UInt8.init), language: .english)
        
        let encodeSeed0 = Test.encode(seed0)
        XCTAssertEqual(Test.decode(encodeSeed0), seed0)
        XCTAssertEqual(encodeSeed0.encoded, "{\"entropy\":[],\"language\":\"japanese\"}")
        
        let encodeSeed1 = Test.encode(seed1)
        XCTAssertEqual(Test.decode(encodeSeed1), seed1)
        XCTAssertEqual(encodeSeed1.encoded, "{\"entropy\":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],\"language\":\"english\"}")
    }
}
