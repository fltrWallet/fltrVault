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
import CryptoKit
import fltrWAPI
import Foundation
import protocol Foundation.DataProtocol
import HaByLo


public enum BIP32<H: HashFunction> {}

let BIP32_SEED_PHRASE = "Bitcoin seed"

public protocol PrivateExtendedKeyProtocol {
    var `private`: Scalar { get }
    var `chainCode`: ChainCode { get }
}

public protocol FullExtendedKeyProtocol {
    var `private`: Scalar { get }
    var `public`: Point { get }
    var `chainCode`: ChainCode { get }
}

public extension BIP32 {
    struct NeuteredExtendedKey: Equatable {
        public let `public`: Point
        public let chainCode: ChainCode
    }
    
    enum PrivateExtendedKey {
        case hardened(BIP32.HardenedPrivateState)
        case normal(BIP32.PrivateState)
        
        var state: PrivateExtendedKeyProtocol {
            switch self {
            case .hardened(let state as PrivateExtendedKeyProtocol),
                 .normal(let state as PrivateExtendedKeyProtocol):
                return state
            }
        }
        
        var `private`: Scalar {
            switch self {
            case .hardened(let state):
                return state.private
            case .normal(let state):
                return state.private
            }
        }
        
        var `chainCode`: ChainCode {
            switch self {
            case .hardened(let state):
                return state.chainCode
            case .normal(let state):
                return state.chainCode
            }
        }
    }
    
    enum FullExtendedKey {
        case hardened(BIP32.HardenedFullState)
        case normal(BIP32.FullState)

        var state: FullExtendedKeyProtocol {
            switch self {
            case .hardened(let state as FullExtendedKeyProtocol),
                 .normal(let state as FullExtendedKeyProtocol):
                return state
            }
        }
        
        var `private`: Scalar {
            switch self {
            case .hardened(let state):
                return state.private
            case .normal(let state):
                return state.private
            }
        }
        
        var `public`: Point {
            switch self {
            case .hardened(let state):
                return state.public
            case .normal(let state):
                return state.public
            }
        }
        
        var `chainCode`: ChainCode {
            switch self {
            case .hardened(let state):
                return state.chainCode
            case .normal(let state):
                return state.chainCode
            }
        }
    }
    
    struct PrivateState: PrivateExtendedKeyProtocol, Equatable {
        public let `private`: Scalar
        public let chainCode: ChainCode
    }
    
    struct FullState: FullExtendedKeyProtocol, Equatable {
        public let `private`: Scalar
        public let `public`: Point
        public let chainCode: ChainCode
    }
    
    struct HardenedPrivateState: PrivateExtendedKeyProtocol, Equatable {
        public let `private`: Scalar
        public let chainCode: ChainCode
    }
    
    struct HardenedFullState: FullExtendedKeyProtocol, Equatable {
        public let `private`: Scalar
        public let `public`: Point
        public let chainCode: ChainCode
    }
}

extension BIP32 {
    struct AuthenticationCodeSecret: SecretBytes {
        let buffer: fltrECCAdapter.Buffer
        init(_ buffer: fltrECCAdapter.Buffer) {
            self.buffer = buffer
        }
        
        static func secret(privateKey: Scalar, hardenedIndex: UInt32) -> Self {
            .init(unsafeUninitializedCapacity: 37) { bytes, size in
                privateKey.withUnsafeBytes { privateKey in
                    bytes[0] = 0
                    (0..<32).forEach {
                        bytes[$0 + 1] = privateKey[$0]
                    }
                    let bigEndianBytes = hardenedIndex.bigEndianBytes
                    (0..<4).forEach {
                        bytes[$0 + 33] = bigEndianBytes[$0]
                    }
                }
                size = 37
            }
        }
    }
    
    static func scalarAndChainCode<HMAC>(from hmac: HMAC) -> (unchecked: UncheckedScalar, chainCode: ChainCode)
    where HMAC: MessageAuthenticationCode {
        let keyBytes: UncheckedScalar = .init(unsafeUninitializedCapacity: 32) { bytes, size in
            hmac.withUnsafeBytes { hmac in
                (0..<32).forEach { i in
                    bytes[i] = hmac[i]
                }
            }
            size = 32
        }
        let childChainCode: ChainCode = .init(unsafeUninitializedCapacity: 32) { bytes, size in
            hmac.withUnsafeBytes { hmac in
                (0..<32).forEach { i in
                    bytes[i] = hmac[i + 32]
                }
            }
            size = 32
        }
        
        return (unchecked: keyBytes, chainCode: childChainCode)
    }

    static func makePrivateKey<HMAC: MessageAuthenticationCode>(from hmac: HMAC,
                                                                privateKey: Scalar)
    -> (key: Scalar, chainCode: ChainCode)? {
        assert(hmac.byteCount == 64)
        
        let (unchecked, childChainCode) = Self.scalarAndChainCode(from: hmac)

        guard let childScalar = Scalar(unchecked),
              let newKey = privateKey + childScalar
        else {
            return nil
        }
        
        return (newKey, childChainCode)
    }
    
    
    static func makeHardenedPrivateChild(for index: UInt32,
                                         privateKey: Scalar,
                                         chainCode: ChainCode) -> BIP32.PrivateExtendedKey? {
        let hardenedIndex = index + (1 << 31)
        let hmac = AuthenticationCodeSecret.secret(privateKey: privateKey, hardenedIndex: hardenedIndex)
        .withUnsafeBytes { secret in
            chainCode.withUnsafeBytes { chainCode in
                HMAC<H>.authenticationCode(for: secret,
                                           using: SymmetricKey(data: chainCode))
            }
        }

        return Self.makePrivateKey(from: hmac, privateKey: privateKey)
        .map {
            .hardened(BIP32.HardenedPrivateState(private: $0.key, chainCode: $0.chainCode))
        }
    }
    
    static func makeNonHardenedPrivateChild(for index: UInt32,
                                            privateKey: Scalar,
                                            publicKey: Point,
                                            chainCode: ChainCode) -> BIP32.PrivateExtendedKey? {
        let publicKey = DSA.PublicKey(publicKey)
        let hmac = chainCode.withUnsafeBytes { chainCode in
            HMAC<H>.authenticationCode(for: publicKey.serialize() + index.bigEndianBytes,
                                       using: SymmetricKey(data: chainCode))
        }
        
        return Self.makePrivateKey(from: hmac, privateKey: privateKey)
        .map {
            .normal(BIP32.PrivateState(private: $0.key, chainCode: $0.chainCode))
        }
    }
    
    static func makeHardenedPublicChild(for index: UInt32,
                                        privateKey: Scalar,
                                        chainCode: ChainCode) -> BIP32.FullExtendedKey? {
        Self.makeHardenedPrivateChild(for: index,
                                      privateKey: privateKey,
                                      chainCode: chainCode)
        .flatMap {
            $0.full()
        }
    }

    static func makeNonHardenedPublicChild(for index: UInt32,
                                           publicKey: Point,
                                           chainCode: ChainCode) -> BIP32<H>.NeuteredExtendedKey? {
        let dsaPublicKey = DSA.PublicKey(publicKey)
        let hmac = chainCode.withUnsafeBytes { chainCode in
            HMAC<H>.authenticationCode(for: dsaPublicKey.serialize() + index.bigEndianBytes,
                                       using: SymmetricKey(data: chainCode))
        }
        
        let (unchecked, childChainCode) = Self.scalarAndChainCode(from: hmac)
        
        guard let childScalar = Scalar(unchecked),
              let childPoint = Point(childScalar) + publicKey
        else {
            return nil
        }
        
        return BIP32.NeuteredExtendedKey(public: childPoint, chainCode: childChainCode)
    }
}

public extension BIP32.NeuteredExtendedKey {
    func makePublicChild(for index: HD.ChildNumber) -> BIP32.NeuteredExtendedKey? {
        switch index {
        case .normal(let index):
            return BIP32.makeNonHardenedPublicChild(for: index,
                                                    publicKey: self.public,
                                                    chainCode: self.chainCode)
        case .hardened, .master:
            preconditionFailure()
        }
    }
}

public extension BIP32.PrivateExtendedKey {
    func full() -> BIP32.FullExtendedKey {
        switch self {
        case .hardened(let state):
            return .hardened(BIP32.HardenedFullState(private: state.private,
                                                     public: Point(state.private),
                                                     chainCode: state.chainCode))
        case .normal(let state):
            return .normal(BIP32.FullState(private: state.private,
                                           public: Point(state.private),
                                           chainCode: state.chainCode))
        }
    }
    
    func makePrivateChild(for index: HD.ChildNumber) -> BIP32.PrivateExtendedKey? {
        let state = self.state
        
        switch index {
        case .hardened(let index):
            return BIP32.makeHardenedPrivateChild(for: index,
                                                  privateKey: state.private,
                                                  chainCode: state.chainCode)
        case .normal, .master:
            preconditionFailure()
        }
    }
}

public extension BIP32.FullExtendedKey {
    func makePrivateChild(for index: HD.ChildNumber) -> BIP32.PrivateExtendedKey? {
        let state = self.state
        
        switch index {
        case .hardened(let index):
            return BIP32.makeHardenedPrivateChild(for: index,
                                                  privateKey: state.private,
                                                  chainCode: state.chainCode)
        case .normal(let index):
            return BIP32.makeNonHardenedPrivateChild(for: index,
                                                     privateKey: state.private,
                                                     publicKey: state.public,
                                                     chainCode: state.chainCode)
        case .master:
            preconditionFailure()
        }
    }
    
    func makePublicChild(for index: HD.ChildNumber) -> BIP32.NeuteredExtendedKey? {
        switch (self, index) {
        case (.normal(let state), .normal(let index)):
            return BIP32.makeNonHardenedPublicChild(for: index,
                                             publicKey: state.public,
                                             chainCode: state.chainCode)
        case (.normal(let state as FullExtendedKeyProtocol), .hardened(let index)),
             (.hardened(let state as FullExtendedKeyProtocol), .hardened(let index)):
            return BIP32.makeHardenedPublicChild(for: index,
                                                 privateKey: state.private,
                                                 chainCode: state.chainCode)
            .map {
                BIP32.NeuteredExtendedKey(public: $0.public, chainCode: $0.chainCode)
            }
        case (.hardened(let state), .normal(let index)):
            return BIP32.makeNonHardenedPrivateChild(for: index,
                                                     privateKey: state.private,
                                                     publicKey: state.public,
                                                     chainCode: state.chainCode)
            .map {
                $0.full()
            }
            .map {
                BIP32.NeuteredExtendedKey(public: $0.public, chainCode: $0.chainCode)
            }
        case (_, .master):
            preconditionFailure()
        }
    }
    
    func neuter() -> BIP32.NeuteredExtendedKey {
        let state = self.state
        
        return BIP32.NeuteredExtendedKey(public: state.public,
                                         chainCode: state.chainCode)
    }
}

// MARK: Codable
extension BIP32 {
    public struct KeyNotFoundError: Error {}
}

extension Point: Codable {
    enum CodingKeys: String, CodingKey {
        case point
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DSA.PublicKey(self).serialize(), forKey: .point)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let serialized = try container.decode([UInt8].self, forKey: .point)
        self = .init(from: serialized)!
    }
}

extension BIP32.NeuteredExtendedKey: Codable {}

extension BIP32.PrivateExtendedKey: Codable {
    public enum CodingKeys: String, CodingKey {
        case hardened, normal
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .hardened(let hardenedPrivateState):
            try container.encode(hardenedPrivateState, forKey: .hardened)
        case .normal(let privateState):
            try container.encode(privateState, forKey: .normal)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        switch container.allKeys.first {
        case .some(.hardened):
            let state = try container.decode(BIP32.HardenedPrivateState.self, forKey: .hardened)
            self = .hardened(state)
        case .some(.normal):
            let state = try container.decode(BIP32.PrivateState.self, forKey: .normal)
            self = .normal(state)
        case .none:
            throw BIP32.KeyNotFoundError()
        }
    }
}

extension BIP32.HardenedPrivateState: Codable {}

extension BIP32.PrivateState: Codable {}

extension BIP32.FullExtendedKey: Codable {
    public enum CodingKeys: String, CodingKey {
        case hardened, normal
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .hardened(let hardenedFullState):
            try container.encode(hardenedFullState, forKey: .hardened)
        case .normal(let fullState):
            try container.encode(fullState, forKey: .normal)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        switch container.allKeys.first {
        case .some(.hardened):
            let state = try container.decode(BIP32.HardenedFullState.self, forKey: .hardened)
            self = .hardened(state)
        case .some(.normal):
            let state = try container.decode(BIP32.FullState.self, forKey: .normal)
            self = .normal(state)
        case .none:
            throw BIP32.KeyNotFoundError()
        }
    }
}

extension BIP32.HardenedFullState: Codable {}

extension BIP32.FullState: Codable {}
