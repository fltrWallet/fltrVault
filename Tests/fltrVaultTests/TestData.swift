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
import fltrVault

struct TestData: Codable {
    static func loadEnglish() -> Data {
        let url = Bundle.module.url(forResource: "vectors", withExtension: "json")!
        return try! Data(contentsOf: url)
    }
    
    static func loadJapaneese() -> Data {
        let url = Bundle.module.url(forResource: "test_JP_BIP39", withExtension: "json")!
        return try! Data(contentsOf: url)
    }
    
    struct JSONEnglish: Codable {
        let english: [[String]]
    }
 
    static var english: [TestData] {
        let decode = try! JSONDecoder().decode(JSONEnglish.self, from: Self.loadEnglish())
        
        return decode.english
        .map {
            TestData(hex: $0[0].hex2Bytes,
                     words: $0[1]
                        .split(separator: " ")
                        .map(String.init),
                     seed: $0[2].hex2Bytes,
                     passphrase: "TREZOR",
                     bip32: $0[3])
        }
    }
    
    struct JSONJapaneese: Codable {
        let entropy: String
        let mnemonic: String
        let passphrase: String
        let seed: String
        let bip32_xprv: String
    }
    
    static var japanese: [TestData] {
        let decode = try! JSONDecoder().decode([JSONJapaneese].self, from: Self.loadJapaneese())
        
        return decode
        .map { (input: JSONJapaneese) -> TestData in
            TestData(hex: input.entropy.hex2Bytes,
                     words: input.mnemonic
                        .split(separator: "　")
                        .map(String.init),
                     seed: input.seed.hex2Bytes,
                     passphrase: input.passphrase,
                     bip32: input.bip32_xprv)
        }
    }
    
    let hex: [UInt8]
    let words: [String]
    let seed: [UInt8]
    let passphrase: String
    let bip32: String
}

struct Language: Codable {
    let english: [[String]]
}
