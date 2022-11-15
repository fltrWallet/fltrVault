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
import Stream64
import XCTest
import HaByLo

final class BIP39Tests: XCTestCase {
    func executeTest(_ data: TestData, for language: BIP39.Language) {
        guard let entropy = BIP39.words(fromRandomness: data.hex, language: language)
        else {
            XCTFail()
            return
        }

        XCTAssertNil(BIP39.words(fromRandomness: data.hex + [0], language: language))
        XCTAssertNil(BIP39.words(fromRandomness: data.hex.dropLast(), language: language))

        var words = entropy.words()
        XCTAssertEqual(words, data.words)
        
        let seed = entropy.bip32Seed(password: data.passphrase)
        seed.withUnsafeBytes { seed in
            XCTAssertEqual(Array(seed), data.seed)
        }
        XCTAssertNotEqual(entropy.bip32Seed(password: data.passphrase + "0"), seed)
        
        guard let entropyFromWords = language.entropyBytes(from: words)
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(entropyFromWords, data.hex)
        
        // break checksum by finding a new last word that invalidates checksum
        // there are plenty of collisions that still generate a valid one
        let last = words.popLast()!
        var random = language.words.randomElement()!
        var validChecksum = language.entropyBytes(from: words + [ random ])
        var maxAttempts = 100
        while random == last || validChecksum != nil {
            defer { maxAttempts -= 1 }
            
            guard maxAttempts > 0
            else {
                XCTFail()
                return
            }
            random = language.words.randomElement()!
            validChecksum = language.entropyBytes(from: words + [ random ])
        }
        XCTAssertNil(validChecksum)
        
        guard let fullNode = HD.FullNode(seed)
        else {
            XCTFail()
            return
        }
        let serialized = fullNode.serialize(for: .bip44, network: .main)
        XCTAssertEqual(serialized, data.bip32)
    }
    
    func testVectors() {
        TestData.english.forEach {
            self.executeTest($0, for: .english)
        }
        
        TestData.japanese.forEach {
            self.executeTest($0, for: .japanese)
        }
    }
}

