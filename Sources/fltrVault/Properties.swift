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
import KeyChainClientAPI
import NIO
import UserDefaultsClientAPI
import fltrWAPI

public extension Vault {
    enum ActiveWalletFile: String, Codable {
        case first
        case second
    }
    
    struct Properties {
        public init(eventLoop: EventLoop,
                    threadPool: NIOThreadPool,
                    keyChain: KeyChainClient,
                    privateKeyHash: UserDefaultsProperty<[UInt8]>,
                    bip39Language: UserDefaultsProperty<BIP39.Language>,
                    walletActive: UserDefaultsProperty<ActiveWalletFile>,
                    property factory: @escaping (String) -> UserDefaultsProperty<[UInt8]>) {
            self.eventLoop = eventLoop
            self.threadPool = threadPool
            self._keyChain = keyChain
            self._privateKeyHash = privateKeyHash
            self._bip39Language = bip39Language
            self._walletActive = walletActive
            
            self._publicKeyHashDictionary = {
                HD.Source.uniqueCases.map { sourceRepo in
                    (sourceRepo, "\(sourceRepo) HASH")
                }
                .reduce(into: [HD.Source : UserDefaultsProperty<[UInt8]>]()) {
                    $0[$1.0] = factory($1.1)
                }
            }()
        }
        
        private let eventLoop: EventLoop
        private let threadPool: NIOThreadPool
        private let _keyChain: KeyChainClient
        private let _privateKeyHash: UserDefaultsProperty<[UInt8]>
        private let _bip39Language: UserDefaultsProperty<BIP39.Language>
        private let _publicKeyHashDictionary: [HD.Source : UserDefaultsProperty<[UInt8]>]
        private let _walletActive: UserDefaultsProperty<ActiveWalletFile>
    }
}

public extension Vault.Properties {
    func reset() {
        self._privateKeyHash.delete()
        self._bip39Language.delete()
        self._walletActive.delete()
        
        self._publicKeyHashDictionary.map(\.value).forEach {
            $0.delete()
        }
    }
    
    func publicKeyNodeHash(for source: HD.Source) -> [UInt8] {
        self._publicKeyHashDictionary[source]!.get()!
    }
    
    func savePublicKeyNodeHash(_ value: [UInt8], for source: HD.Source) {
        self._publicKeyHashDictionary[source]!.put(value)
    }
}

extension Vault.Properties {
    static func live(eventLoop: EventLoop, threadPool: NIOThreadPool, userDefaults: UserDefaults) -> Self {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        return .init(eventLoop: eventLoop,
                     threadPool: threadPool,
                     keyChain: .passcode,
                     privateKeyHash: .live(key: "WalletPrivateKeyHash", defaults: userDefaults, encoder: encoder, decoder: decoder),
                     bip39Language: .live(key: "WalletBIP39SeedLanguage", defaults: userDefaults, encoder: encoder, decoder: decoder),
                     walletActive: .live(key: "WalletActiveFile", defaults: userDefaults, encoder: encoder, decoder: decoder)) {
            .live(key: $0, defaults: userDefaults, encoder: encoder, decoder: decoder)
        }
    }

    var firstActive: Bool {
        switch self._walletActive.get()! {
        case .first:
            return true
        case .second:
            return false
        }
    }

    func `switch`() -> Void {
        switch self._walletActive.get()! {
        case .first:
            self._walletActive.put(.second)
        case .second:
            self._walletActive.put(.first)
        }
    }
    
    
    func resetActiveWalletFile() {
        precondition(!self._walletActive.exists())
        self._walletActive.put(.first)
    }
    
    public func loadPrivateKey() -> EventLoopFuture<Vault.WalletSeedCodable> {
        let hash = self._privateKeyHash.get()!
        let language = self._bip39Language.get()!
        
        return self._keyChain.get(key: GlobalFltrWalletSettings.BIP39PrivateKeyStringKey,
                                  threadPool: self.threadPool,
                                  eventLoop: self.eventLoop)
        .map {
            Vault.WalletSeedCodable(entropy: $0, language: language)
        }
        .always {
            switch $0 {
            case .success(let privateKey):
                guard privateKey.entropy.sha256 == hash
                else {
                    preconditionFailure("KeyChain or properties have been tampered (hash mismatch)")
                }
            case .failure(let error) where error is KeyChainClient.Error:
                break
            case .failure(let error):
                preconditionFailure(error.localizedDescription)
            }
        }
    }
    
    func storePrivateKey(_ privateKey: Vault.WalletSeedCodable) -> EventLoopFuture<Void> {
        self._privateKeyHash.put(privateKey.entropy.sha256)
        self._bip39Language.put(privateKey.language)
        
        return self._keyChain.put(key: GlobalFltrWalletSettings.BIP39PrivateKeyStringKey,
                                  data: privateKey.entropy,
                                  threadPool: self.threadPool,
                                  eventLoop: self.eventLoop)
    }
    
    enum WalletPublicKeyNodes {
        case legacy0(HD.NeuteredNode)
        case legacy0Change(HD.NeuteredNode)
        case legacy44(HD.NeuteredNode)
        case legacy44Change(HD.NeuteredNode)
        case legacySegwit(HD.NeuteredNode)
        case legacySegwitChange(HD.NeuteredNode)
        case segwit(HD.NeuteredNode)
        case segwitChange(HD.NeuteredNode)
        case taproot(HD.NeuteredNode)
        case taprootChange(HD.NeuteredNode)
        
        init(_ sourceRepo: HD.Source, node: HD.NeuteredNode) {
            let result: WalletPublicKeyNodes = {
                switch sourceRepo {
                case .legacy0:
                    return .legacy0(node)
                case .legacy0Change:
                    return .legacy0Change(node)
                case .legacy44:
                    return .legacy44(node)
                case .legacy44Change:
                    return .legacy44Change(node)
                case .legacySegwit:
                    return .legacySegwit(node)
                case .legacySegwitChange:
                    return .legacySegwitChange(node)
                case .segwit0:
                    return .legacy0(node)
                case .segwit0Change:
                    return .legacy0Change(node)
                case .segwit:
                    return .segwit(node)
                case .segwitChange:
                    return .segwitChange(node)
                case .taproot:
                    return .taproot(node)
                case .taprootChange:
                    return .taprootChange(node)
                }
            }()
            self = result
        }
        
        private static func _load(keyChain: KeyChainClient,
                                  key: HD.Source,
                                  decoder: JSONDecoder,
                                  threadPool: NIOThreadPool,
                                  eventLoop: EventLoop,
                                  checksum load: @escaping (HD.Source) -> [UInt8]) -> EventLoopFuture<HD.NeuteredNode> {
            keyChain.get(key: "\(key)",
                         threadPool: threadPool,
                         eventLoop: eventLoop)
            .recover { preconditionFailure("\($0)") }
            .map { bytes in
                guard bytes.sha256 == load(key)
                else { preconditionFailure("KeyChain or properties have been tampered (hash mismatch)") }
                
                return try! decoder.decode(HD.NeuteredNode.self, from: Data(bytes))
            }
        }
        
        private static func _store(value: HD.NeuteredNode,
                                   keyChain: KeyChainClient,
                                   key: HD.Source,
                                   encoder: JSONEncoder,
                                   threadPool: NIOThreadPool,
                                   eventLoop: EventLoop,
                                   checksum store: @escaping ([UInt8], HD.Source) -> Void) -> EventLoopFuture<Void> {
            let encoded = Array(try! encoder.encode(value))
            
            return keyChain.put(system: "\(key)",
                                data: encoded,
                                threadPool: threadPool,
                                eventLoop: eventLoop)
            .recover { preconditionFailure("\($0)") }
            .map {
                store(encoded.sha256, key)
            }
        }
        
        func store(properties: Vault.Properties,
                   encoder: JSONEncoder,
                   threadPool: NIOThreadPool,
                   eventLoop: EventLoop) -> EventLoopFuture<Void> {
            let source = self.sourceRepo
            let node = self.node
            
            return Self._store(value: node,
                               keyChain: properties._keyChain,
                               key: source,
                               encoder: encoder,
                               threadPool: threadPool,
                               eventLoop: eventLoop,
                               checksum: properties.savePublicKeyNodeHash(_:for:))
        }

        var node: HD.NeuteredNode {
            switch self {
            case .legacy0(let node),
                    .legacy0Change(let node),
                    .legacy44(let node),
                    .legacy44Change(let node),
                    .legacySegwit(let node),
                    .legacySegwitChange(let node),
                    .segwit(let node),
                    .segwitChange(let node),
                    .taproot(let node),
                    .taprootChange(let node):
                return node
            }
        }
        
        var sourceRepo: HD.Source {
            switch self {
            case .legacy0: return .legacy0
            case .legacy0Change: return .legacy0Change
            case .legacy44: return .legacy44
            case .legacy44Change: return .legacy44Change
            case .legacySegwit: return .legacySegwit
            case .legacySegwitChange: return .legacySegwitChange
            case .segwit: return .segwit
            case .segwitChange: return .segwitChange
            case .taproot: return .taproot
            case .taprootChange: return .taprootChange
            }
        }
        
        static func load(source: HD.Source,
                         properties: Vault.Properties,
                         decoder: JSONDecoder,
                         threadPool: NIOThreadPool,
                         eventLoop: EventLoop) -> EventLoopFuture<Self> {
            self._load(keyChain: properties._keyChain,
                       key: source,
                       decoder: decoder,
                       threadPool: threadPool,
                       eventLoop: eventLoop,
                       checksum: properties.publicKeyNodeHash(for:))
            .map {
                WalletPublicKeyNodes(source, node: $0)
            }
            
        }
    }

    func loadPublicKey(source: HD.Source,
                       decoder: JSONDecoder = JSONDecoder()) -> EventLoopFuture<WalletPublicKeyNodes> {
        WalletPublicKeyNodes.load(source: source,
                                  properties: self,
                                  decoder: decoder,
                                  threadPool: threadPool,
                                  eventLoop: eventLoop)
    }
    
    typealias AllPublicKeyNodes = [HD.Source : HD.NeuteredNode]
    func loadAllNodes(decoder: JSONDecoder = JSONDecoder()) -> EventLoopFuture<AllPublicKeyNodes> {
        let futures: [EventLoopFuture<(HD.Source, HD.NeuteredNode)>] =
        HD.Source.uniqueCases.map { source in
            source.node(from: self)
            .map {
                (source, $0.node)
            }
        }

        return EventLoopFuture.whenAllSucceed(futures, on: self.eventLoop)
        .map {
            $0.reduce(into: AllPublicKeyNodes()) { result, next in
                result[next.0] = next.1
            }
        }
        .map {
            var copy = $0
            copy[.segwit0] = copy[.legacy0]!
            copy[.segwit0Change] = copy[.legacy0Change]!
            return copy
        }
    }
    
    func storePublicKey(_ publicKey: WalletPublicKeyNodes, encoder: JSONEncoder = JSONEncoder()) -> EventLoopFuture<Void> {
        publicKey.store(properties: self,
                        encoder: encoder,
                        threadPool: self.threadPool,
                        eventLoop: self.eventLoop)
    }
}
