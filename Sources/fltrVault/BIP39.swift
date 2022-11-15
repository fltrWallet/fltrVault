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
import CommonCrypto
import Foundation
import Stream64

public enum BIP39 {}

extension BIP39 {
    @usableFromInline
    static let IterationCount = 2048
    @usableFromInline
    static let Algorithm = PseudoRandom.SHA512
    @usableFromInline
    static let BitWidth = 8
    @usableFromInline
    static let DerivedKeyLength = 512 / Self.BitWidth
    @usableFromInline
    static let PasswordPrefix = "mnemonic"
    @usableFromInline
    static let WordsBitWidth = 11
}

// MARK: Language
public extension BIP39 {
    enum Language: String, Codable {
        case english
        case chinese_simplified
        case chinese_traditional
        case japanese
        case korean
        case french
        case italian
        case spanish
        
        var words: [String] {
            BIP39.Language.load(language: self)
        }
    }
}

extension BIP39.Language {
    @usableFromInline
    static func load(language: BIP39.Language) -> [String] {
        let url = Bundle.module.url(forResource: language.rawValue, withExtension: "txt")!
        let contents = try! String(contentsOf: url, encoding: .utf8)
        
        var result: [String] = []
        contents.enumerateLines { line, _ in
            result.append(line)
        }
        
        return result
    }
    
    @usableFromInline
    func load() -> [String] {
        BIP39.Language.load(language: self)
    }
    
    @inlinable
    public func entropyBytes(from words: [String]) -> [UInt8]? {
        guard let entropy = BIP39.Width.allCases.first(where: { $0.MS == words.count })
        else { return nil }

        let wordList = self.load()
        let indices = words.map {
            wordList.firstIndex(of: $0).map(UInt64.init)
        }
        let filtered = indices.compactMap { $0 }
        guard indices.count == filtered.count,
              var bytes = try? Stream64.streamWrite(values: filtered, p: 11),
              let checksum = bytes.popLast().map(entropy.align(checksum:)),
              let sha = bytes.sha256.first.map(entropy.align(checksum:)),
              checksum == sha
        else { return nil }

        return bytes
    }
    
    @inlinable
    public func isValid(word: String) -> Bool {
        self.load().contains(word)
    }
    
    @inlinable
    public func words(for prefix: String) -> [String] {
        let filtered = self.load().filter {
            $0.starts(with: prefix)
        }
        
        guard filtered.firstIndex(of: prefix) == nil
        else { //exact match
            return [prefix]
        }
        
        guard filtered.count <= 4
        else { return [] }
        
        return filtered
    }

    @usableFromInline
    var whitespace: String {
        switch self {
        case .chinese_simplified, .chinese_traditional, .english, .french,
             .italian, .korean, .spanish:
            return " "
        case .japanese:
            return "\u{3000}"
        }
    }
}

// MARK: Width
public extension BIP39 {
    enum Width: CaseIterable, Equatable {
        case b128
        case b160
        case b192
        case b224
        case b256

        @usableFromInline
        var rawValue: (ENT: Int, CS: Int, MS: Int) {
            switch self {
            case .b128: return (ENT: 128, CS: 4, MS: 12)
            case .b160: return (ENT: 160, CS: 5, MS: 15)
            case .b192: return (ENT: 192, CS: 6, MS: 18)
            case .b224: return (ENT: 224, CS: 7, MS: 21)
            case .b256: return (ENT: 256, CS: 8, MS: 24)
            }
        }
        
        @inlinable
        public func random(for language: Language) -> WordIndexStream {
            let initial: [UInt8] = (0..<self.byteSize.ENT).map { _ in .random(in: .min ... .max) }
            return BIP39.words(fromRandomness: initial, language: language)!
        }
        
        @usableFromInline
        func align(checksum byte: UInt8) -> UInt8 {
            let cs = self.CS
            let shift = 8 - cs
            
            return byte &>> shift
        }
       
        @inlinable
        public var byteSize: (ENT: Int, CS: Int, ENTCS: Int) {
            (ENT: self.ENT / 8,
             CS: 1,
             ENTCS: (self.ENT / 8) + 1)
        }
        
        @inlinable
        public var ENT: Int {
            self.rawValue.ENT
        }
        
        @inlinable
        public var CS: Int {
            self.rawValue.CS
        }
        
        @inlinable
        public var MS: Int {
            self.rawValue.MS
        }
        
        @inlinable
        public var ENTCS: Int {
            self.rawValue.ENT + self.rawValue.CS
        }
        
        @inlinable
        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.ENT == rhs.ENT
        }
    }
    
    @inlinable
    static func words(fromRandomness bytes: [UInt8], language: Language) -> WordIndexStream? {
        BIP39.Width.allCases.first(where: { $0.byteSize.ENT == bytes.count })
        .map { width in
            let cs = bytes.sha256.first!
            let unalignedBuffer = (0..<7).map { _ in UInt8(0) }
            let data = bytes + [ cs ] + unalignedBuffer
            let stream64 = Stream64(data: data, count: width.MS, p: BIP39.WordsBitWidth)
            
            return WordIndexStream(stream64, language: language)
        }
    }
}

// MARK: WordIndexStream
public extension BIP39 {
    struct WordIndexStream: Sequence {
        @usableFromInline
        let stream64: Stream64
        @usableFromInline
        let _language: Language
        @usableFromInline
        let dictionary: [String]
        
        @inlinable
        public var language: Language {
            self._language
        }
        
        @usableFromInline
        init(_ stream64: Stream64, language: Language) {
            self.stream64 = stream64
            self._language = language
            self.dictionary = language.words
        }
        
        @inlinable
        public func makeIterator() -> AnyIterator<Array<String>.Index> {
            var iterator = self.stream64.makeIterator()
            
            return AnyIterator {
                iterator.next().map {
                    Array<String>.Index($0)
                }
            }
        }
        
        @inlinable
        public func words() -> [String] {
            self.map {
                self.dictionary[$0]
            }
        }
        
        @inlinable
        public func bip32SeedWithoutPassword() -> HD.Seed {
            self.bip32Seed(password: "")
        }
        
        @inlinable
        public func bip32Seed(password: String) -> HD.Seed {
            let words = self.words()
            
            return try! BIP39.seed(from: words,
                                   password: password,
                                   separator: self.language.whitespace)
        }
    }
}

 
// MARK: PBKDF and Seed Generation Utility Functions
extension BIP39 {
    @usableFromInline
    static func normalize(_ string: String) -> [UInt8] {
        [UInt8](string.decomposedStringWithCompatibilityMapping.utf8)
    }

    @usableFromInline
    static func pbkdf(input: [UInt8], salt: [UInt8], rounds: Int,
                      length: Int, algorithm: PseudoRandom = .SHA512) throws -> HD.Seed {
        try HD.Seed(unsafeUninitializedCapacity: length) { buffer, setSizeTo in
            let result = input.withUnsafeBytes { input in
                salt.withUnsafeBufferPointer { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         input.bindMemory(to: Int8.self).baseAddress,
                                         input.count,
                                         salt.baseAddress!,
                                         salt.count,
                                         algorithm(),
                                         UInt32(rounds),
                                         buffer.baseAddress!,
                                         length)
                }
            }
            
            guard result == kCCSuccess
            else {
                throw CCKeyDerivationPBKDFError(code: result)
            }
            setSizeTo = length
        }
    }

    @usableFromInline
    static func seed(from mnemonic: [String], password: String, separator: String) throws -> HD.Seed {
        let pbkdfInput: [UInt8] = Self.normalize(mnemonic.joined(separator: separator))
        let pbkdfSalt: [UInt8] = Self.normalize([BIP39.PasswordPrefix, password, ].joined())
        
        return try BIP39.pbkdf(input: pbkdfInput,
                               salt: pbkdfSalt,
                               rounds: BIP39.IterationCount,
                               length: BIP39.DerivedKeyLength,
                               algorithm: BIP39.Algorithm)
    }

    @usableFromInline
    enum PseudoRandom {
        case SHA1
        case SHA224
        case SHA256
        case SHA384
        case SHA512

        @usableFromInline
        func callAsFunction() -> CCPseudoRandomAlgorithm {
            switch self {
            case .SHA1:
                return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case .SHA224:
                return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
            case .SHA256:
                return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case .SHA384:
                return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
            case .SHA512:
                return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            }
        }
    }
    
    struct CCKeyDerivationPBKDFError: Error {
        @usableFromInline
        let code: Int32
    }
}
