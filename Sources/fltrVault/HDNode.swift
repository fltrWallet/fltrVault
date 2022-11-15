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
import HaByLo

public protocol NodeProtocol {
    associatedtype HashFunction: CryptoKit.HashFunction
    
    var chainCode: ChainCode { get }
    var isHardened: Bool { get }
    var keyNumber: HD.ChildNumber { get }
    var parent: HD.NodeKey { get }
    var pathPrefix: HD.Path { get }
    
    mutating func makeChildNode(for: HD.Path) throws -> [Self]
}

public extension NodeProtocol {
    mutating func childKey(index: Int) -> Self {
        precondition(index >= 0 && index < 0x80_00_00_00)

        return self.childKey(path: self.pathPrefix + [ self.keyNumber, .normal(UInt32(index)) ])
    }
    
    mutating func childKey(path: HD.Path) -> Self {
        return try! self.makeChildNode(for: path).last!
    }
}

extension HD {
    public enum DeserializedType {
        case full(HD.FullNode)
        case neutered(HD.NeuteredNode)
    }
    
    enum KeyPrivateOrPublic {
        case `private`(Scalar)
        case `public`(Point)
    }
}

extension HD {
    enum Error: Swift.Error {
        case invalidRootPath
        case illegalHDPath
        case illegalHDPathHardenedKey
    }
}

public extension NodeProtocol {
    var depth: Int {
        self.isRoot
            ? 0
            : self.pathPrefix.count + 1
    }
    
    var isRoot: Bool {
        switch self.keyNumber {
        case .master:
            precondition(self.pathPrefix.isEmpty)
            return true
        case .hardened, .normal:
            return false
        }
    }
}

// MARK: Serialization
public protocol HDSerialization {
    static var hasPrivateKey: Bool { get }
    var keyBytes: [UInt8] { get }
    
    func serialize(for: HD.SerializationMode, network: NetworkParameters) -> String
}

extension HD {
    public enum SerializationMode {
        case bip44
        case bip84
    }
}

extension NodeProtocol where Self: HDSerialization {
    public func serialize(for version: HD.SerializationMode,
                          network: NetworkParameters) -> String {
        let versionData: UInt32 = {
            switch (version, self.hasPrivateKey) {
            case (.bip44, false):
                return network.BITCOIN_BIP44_VERSION_PREFIX.rawValue.public
            case (.bip44, true):
                return network.BITCOIN_BIP44_VERSION_PREFIX.rawValue.private
            case (.bip84, false):
                return network.BITCOIN_BIP84_VERSION_PREFIX.rawValue.public
            case (.bip84, true):
                return network.BITCOIN_BIP84_VERSION_PREFIX.rawValue.private
            }
        }()

        return self.chainCode.withUnsafeBytes { chainCode in
            [ versionData.bigEndianBytes,
              [ UInt8(self.depth) ],
              Array(self.parent.fingerprint.value),
              self.keyNumber.index().bigEndianBytes,
              Array(chainCode),
              self.keyBytes ]
                .joined()
                .base58CheckEncode()
        }
    }
}

extension HD {
    static public func deserialize(from bytes: [UInt8],
                                   network: NetworkParameters,
                                   available fingerprints: [(HD.NodeKey, HD.Path)]) -> HD.DeserializedType? {
        func deSerializeComponents(_ bytes: [UInt8], network: NetworkParameters)
        -> (
            depth: UInt8,
            fingerprint: [UInt8],
            childNumber: UInt32,
            chainCode: ChainCode,
            bip: SerializationMode,
            keyType: KeyPrivateOrPublic
        )? {
            func loadUInt32BigEndian(bytes: ArraySlice<UInt8>) -> UInt32 {
                bytes.withUnsafeBufferPointer { bp in
                    var offset = 0
                    return stride(from: 24, through: 0, by: -8).reduce(into: UInt32(0)) {
                        defer { offset += 1 }
                        let byte = bp[offset]
                        $0 |= UInt32(byte) &<< $1
                    }
                }
            }
            
            guard bytes.count == 78
            else { return nil }
            
            let version = bytes[0..<4]
            let depth = bytes[4]
            let fingerPrint = bytes[5..<9]
            let childNumberBytes = bytes[9..<13]
            let chainCode = ChainCode(unsafeUninitializedCapacity: 32) { chainCode, size in
                (0..<32).forEach {
                    chainCode[$0] = bytes[$0 + 13]
                }
                size = 32
            }
            let key = Array(bytes[45..<78])
            let childNumber = loadUInt32BigEndian(bytes: childNumberBytes)
            
            let versionNumber = loadUInt32BigEndian(bytes: version)
            guard let (bip, keyType) = { () -> (SerializationMode, KeyPrivateOrPublic)? in
                switch versionNumber {
                case network.BITCOIN_BIP44_VERSION_PREFIX.rawValue.public:
                    guard let point = Point(from: key)
                    else { return nil }
                    return (.bip44, .public(point))
                case network.BITCOIN_BIP44_VERSION_PREFIX.rawValue.private:
                    let unchecked = UncheckedScalar(unsafeUninitializedCapacity: 32) { b, s in
                        let key = key.dropFirst()
                        (0..<32).forEach {
                            b[$0] = key[$0]
                        }
                        s = 32
                    }
                    guard let scalar = Scalar(unchecked)
                    else { return nil }
                    return (.bip44, .private(scalar))
                case network.BITCOIN_BIP84_VERSION_PREFIX.rawValue.public:
                    guard let point = Point(from: key)
                    else { return nil }
                    return (.bip84, .public(point))
                case network.BITCOIN_BIP84_VERSION_PREFIX.rawValue.private:
                    let unchecked = UncheckedScalar(unsafeUninitializedCapacity: 32) { b, s in
                        let key = key.dropFirst()
                        (0..<32).forEach {
                            b[$0] = key[$0]
                        }
                        s = 32
                    }
                    guard let scalar = Scalar(unchecked)
                    else { return nil }
                    return (.bip84, .private(scalar))
                default: return nil
                }
            }()
            else { return nil }

            return (
                depth,
                Array(fingerPrint),
                childNumber,
                chainCode,
                bip,
                keyType
            )
        }

        guard let (depth, fingerprint, childNumber, chainCode, _, keyType)
                = deSerializeComponents(bytes, network: network)
        else { return nil }
        
        var parent: NodeKey!
        var pathPrefix: HD.Path!
        if let match = fingerprints
            .filter({
                $0.1.count == depth - 1
            })
            .first(where: { $0.0.fingerprint.value.elementsEqual(fingerprint) }) {
            parent = match.0
            pathPrefix = match.1
        } else if (depth == 0 && fingerprint == [0, 0, 0, 0, ]) {
            parent = NodeKey(root: ())
            pathPrefix = .empty
        } else {
            return nil
        }

        let hdChildNumber = HD.ChildNumber.child(for: childNumber)
        switch keyType {
        case .private(let privateKey):
            let p: BIP32<HD.HashFunction>.PrivateExtendedKey = hdChildNumber.isHardened
                ? .hardened(.init(private: privateKey, chainCode: chainCode))
                : .normal(.init(private: privateKey, chainCode: chainCode))
            let full = p.full()
            
            return .full(FullNode(key: full,
                                  keyNumber: hdChildNumber,
                                  parent: parent,
                                  pathPrefix: pathPrefix,
                                  hashCache: nil))
        case .public(let publicKey):
            let n = BIP32<HD.HashFunction>.NeuteredExtendedKey(public: publicKey, chainCode: chainCode)
            return .neutered(NeuteredNode(key: n,
                                          keyNumber: hdChildNumber,
                                          parent: parent,
                                          pathPrefix: pathPrefix,
                                          hashCache: nil))
        }
    }
}

extension NodeProtocol where Self: HDSerialization {
    var hasPrivateKey: Bool {
        Self.hasPrivateKey
    }
}

extension HD.NeuteredNode: HDSerialization {
    static public var hasPrivateKey: Bool {
        false
    }
    
    
    public var keyBytes: [UInt8] {
        DSA.PublicKey(self.key.public).serialize()
    }
}

extension HD.FullNode: HDSerialization {
    static public var hasPrivateKey: Bool {
        true
    }

    public var keyBytes: [UInt8] {
        self.key.private.withUnsafeBytes { key in
            [0] + Array(key)
        }
    }
}

public extension HD {
    typealias HashFunction = SHA512

    internal static func nextKey<T>(childNumber: HD.ChildNumber, calling: (HD.ChildNumber) -> T?) -> (T, HD.ChildNumber) {
        func nextIndex(from: HD.ChildNumber) -> HD.ChildNumber {
            switch from {
            case .hardened(let index):
                return .hardened(index + 1)
            case .normal(let index):
                precondition(index + 1 < (1 << 31))
                return .normal(index + 1)
            case .master:
                preconditionFailure()
            }
        }
        
        var currentIndex = childNumber
        while true {
            if let n = calling(currentIndex) {
                return (n, currentIndex)
            } else {
                logger.info("HD.nextKey<\(T.self)>(childNumber: [\(childNumber)], calling:) - Skipping index due to undefined ECC point")
                currentIndex = nextIndex(from: currentIndex)
                continue
            }
        }
    }
    
    struct NeuteredNode: NodeProtocol {
        public typealias HashFunction = HD.HashFunction
        let key: BIP32<HashFunction>.NeuteredExtendedKey
        public let keyNumber: HD.ChildNumber
        public let parent: HD.NodeKey
        public let pathPrefix: HD.Path
        
        var hashCache: HD.NodeKey?
        
        public var chainCode: ChainCode {
            self.key.chainCode
        }
        
        public var isHardened: Bool {
            self.keyNumber.isHardened
        }
        
        public mutating func makeChildNode(for path: HD.Path) throws -> [HD.NeuteredNode] {
            if self.hashCache == nil {
                self.hashCache = HD.NodeKey(self.key)
            }
            
            var key = self.key
            let checkPrefix = self.isRoot
                ? HD.Path.empty
                : self.pathPrefix + [ self.keyNumber ]
            guard let makePath = checkPrefix.matchPrefix(path)
            else { throw HD.Error.illegalHDPath }

            var parent: HD.NodeKey = self.hashCache!
            var pathPrefix: HD.Path = makePath.prefix
            var nodes: [HD.NeuteredNode] = []
            for path in makePath.remaining {
                switch path {
                case .hardened, .master:
                    throw HD.Error.illegalHDPathHardenedKey
                case .normal:
                    let (nextKey, availableIndex) = HD.nextKey(childNumber: path) { key.makePublicChild(for: $0) }
                    key = nextKey
                    let saveParent = parent
                    parent = HD.NodeKey(key)
                    nodes.append(
                        HD.NeuteredNode(key: key,
                                        keyNumber: availableIndex,
                                        parent: saveParent,
                                        pathPrefix: pathPrefix,
                                        hashCache: parent)
                    )
                }
                pathPrefix = pathPrefix.appending(path)
            }
            
            return nodes
        }
    }
    
    struct FullNode: NodeProtocol {
        public typealias HashFunction = HD.HashFunction
        let key: BIP32<HashFunction>.FullExtendedKey
        public let keyNumber: HD.ChildNumber
        public let parent: HD.NodeKey
        public let pathPrefix: HD.Path
        
        var hashCache: HD.NodeKey?
        
        public var chainCode: ChainCode {
            self.key.chainCode
        }
        
        public var isHardened: Bool {
            switch key {
            case .hardened:
                return true
            case .normal:
                return false
            }
        }

        init(key: BIP32<HashFunction>.FullExtendedKey,
             keyNumber: HD.ChildNumber,
             parent: HD.NodeKey,
             pathPrefix: HD.Path,
             hashCache: HD.NodeKey?) {
            self.key = key
            self.keyNumber = keyNumber
            self.parent = parent
            self.pathPrefix = pathPrefix
            self.hashCache = hashCache
        }

        public init?(_ seed: Seed) {
            let hmac = seed.withUnsafeBytes { seed in
                HMAC<HashFunction>.authenticationCode(for: seed,
                                                      using: SymmetricKey(data: BIP32_SEED_PHRASE.ascii))
            }
            let (uncheckedScalar, chainCode) = BIP32<HashFunction>.scalarAndChainCode(from: hmac)

            guard let privateKey = Scalar(uncheckedScalar)
            else {
                return nil
            }
            
            let fullExtendedKey = BIP32<HashFunction>.FullExtendedKey.normal(
                .init(private: privateKey,
                      public: Point(privateKey),
                      chainCode: chainCode)
            )

            self.init(key: fullExtendedKey,
                      keyNumber: .master,
                      parent: .root,
                      pathPrefix: .empty,
                      hashCache: nil)
        }
        
        public mutating func makeChildNode(relative: HD.Path) throws -> [HD.FullNode] {
            let base: HD.Path = self.isRoot
            ? HD.Path.empty
            : self.pathPrefix + [ self.keyNumber ]
            
            return try self.makeChildNode(for: base + relative)
        }
        
        public mutating func makeChildNode(for path: HD.Path) throws -> [HD.FullNode] {
            if self.hashCache == nil {
                self.hashCache = HD.NodeKey(self.key)
            }
            
            var key = self.key
            let checkPrefix = self.isRoot
                ? HD.Path.empty
                : self.pathPrefix + [ self.keyNumber ]
            guard let makePath = checkPrefix.matchPrefix(path)
            else { throw HD.Error.illegalHDPath }

            var parent: HD.NodeKey = self.hashCache!
            var pathPrefix: HD.Path = makePath.prefix
            var nodes: [HD.FullNode] = []
            for path in makePath.remaining {
                switch path {
                case .hardened, .normal: break
                case .master: throw HD.Error.illegalHDPath
                }
                
                let (nextKey, availableIndex) = HD.nextKey(childNumber: path) { key.makePrivateChild(for: $0) }
                let fullKey = nextKey.full()
                key = fullKey
                let saveParent = parent
                parent = HD.NodeKey(key)
                nodes.append(
                    HD.FullNode(key: key,
                                keyNumber: availableIndex,
                                parent: saveParent,
                                pathPrefix: pathPrefix,
                                hashCache: parent)
                )
                pathPrefix = pathPrefix.appending(path)
            }
            
            return nodes
        }
        
        public func neuter() -> HD.NeuteredNode {
            HD.NeuteredNode(key: self.key.neuter(),
                            keyNumber: self.keyNumber,
                            parent: self.parent,
                            pathPrefix: self.pathPrefix,
                            hashCache: self.hashCache)
        }
    }
}

public extension HD {
    struct NodeKey {
        let hash: [UInt8]
        
        init(_ key: BIP32<HD.HashFunction>.FullExtendedKey) {
            self.hash = DSA.PublicKey(key.public)
                .serialize()
                .hash160
            
            self.fingerprint = Fingerprint(self.hash)
        }
        
        init(_ key: BIP32<HD.HashFunction>.NeuteredExtendedKey) {
            self.hash = DSA.PublicKey(key.public)
                .serialize()
                .hash160
            
            self.fingerprint = Fingerprint(self.hash)
        }
        
        init(root: Void?) {
            self.hash = .init(repeating: 0, count: 20)
            self.fingerprint = Fingerprint(self.hash)
        }
        
        init(_ bytes: [UInt8]) {
            assert(bytes.count == 20)
            self.hash = bytes
            self.fingerprint = Fingerprint(bytes)
        }
        
        public static let root: Self = .init(root: nil)
        
        
        public struct Fingerprint: Equatable {
            let value: ArraySlice<UInt8>
            
            init(_ hash: [UInt8]) {
                assert(hash.count == 20)
                
                self.value = hash[..<4]
            }
        }
        
        let fingerprint: Fingerprint
    }
}

// MARK: Codable
extension HD.NodeKey: Codable {
    public enum CodingKeys: String, CodingKey {
        case hash
    }
    
    public func encode(to encoder: Encoder) throws {
        var encoder = encoder.container(keyedBy: CodingKeys.self)
        
        try encoder.encode(self.hash, forKey: .hash)
    }
    
    public init(from decoder: Decoder) throws {
        let decoder = try decoder.container(keyedBy: CodingKeys.self)
        
        let hash = try decoder.decode([UInt8].self, forKey: .hash)
        let fingerprint = Fingerprint(hash)
        
        self.hash = hash
        self.fingerprint = fingerprint
    }
}

extension HD.FullNode: Codable {}

extension HD.NeuteredNode: Codable {}


public extension HD {
    struct Seed: SecretBytes, Codable, Equatable {
        public let buffer: CodableBuffer
        public init?(_ buffer: CodableBuffer) {
            guard buffer.count >= 16
            else { return nil }
            
            self.buffer = buffer
        }
    }
}
