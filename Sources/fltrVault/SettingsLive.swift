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
import NIO

public extension Vault.Settings {
    static let live: Self = .init(
        BlockExplorerURL: "https://www.blockchain.com",
        BIP39Legacy0AccountPath: [ .hardened(0), ],
        BIP39Legacy44AccountPath: [ .hardened(44), .hardened(0), .hardened(0) ],
        BIP39LegacySegwitAccountPath: [ .hardened(49), .hardened(0), .hardened(0) ],
        BIP39SegwitAccountPath: [ .hardened(84), .hardened(0), .hardened(0) ],
        BIP39TaprootAccountPath: [ .hardened(86), .hardened(0), .hardened(0) ],
        BIP39PrivateKeyPassword: "",
        BIP39PrivateKeyStringKey: "BIP39 private seed",
        BIP39PublicKeyStringKeyLegacy0: "BIP39 public key legacy0 chain",
        BIP39PublicKeyStringKeyLegacy0Change: "BIP39 public key legacy0 change chain",
        BIP39PublicKeyStringKeyLegacy44: "BIP39 public key legacy44 chain",
        BIP39PublicKeyStringKeyLegacy44Change: "BIP39 public key legacy44 change chain",
        BIP39PublicKeyStringKeyLegacySegwit: "BIP39 public key legacy-segwit chain",
        BIP39PublicKeyStringKeyLegacySegwitChange: "BIP39 public key legacy-segwit change chain",
        BIP39PublicKeyStringKeySegwit: "BIP39 public key segwit chain",
        BIP39PublicKeyStringKeySegwitChange: "BIP39 public key segwit change chain",
        BIP39PublicKeyStringKeyTaproot: "BIP39 public key taproot chain",
        BIP39PublicKeyStringKeyTaprootChange: "BIP39 public key taproot change chain",
        BIP39SeedEntropy: .b128,
        BIP39SeedLanguage: .english,
        CoinConsolidateBacklog: 6,
        CoinConsolidateUnconfirmed: 100,
        CoinRepoFileName: "wcoin.dat",
        DataFileDirectory: Self.libPath(),
        DustAmount: 546,
        MaximumRollback: 20_000,
        Network: .main,
        NIOByteBufferAllocator: ByteBufferAllocator(),
        NonBlockingFileIOClientFactory: NonBlockingFileIOClient.live(_:),
        PubKeyLookahead: 25,
        PubKeyRepoFindBuffer: 2000,
        WalletPropertiesFactory: {
            Vault.Properties.live(eventLoop: $0,
                                  threadPool: $1,
                                  userDefaults: UserDefaults.standard)
        }
    )

    static let simulatorMain: Self = .init(
        BlockExplorerURL: "https://www.blockchain.com",
        BIP39Legacy0AccountPath: [ .hardened(0), ],
        BIP39Legacy44AccountPath: [ .hardened(44), .hardened(0), .hardened(0) ],
        BIP39LegacySegwitAccountPath: [ .hardened(49), .hardened(0), .hardened(0) ],
        BIP39SegwitAccountPath: [ .hardened(84), .hardened(0), .hardened(0) ],
        BIP39TaprootAccountPath: [ .hardened(86), .hardened(0), .hardened(0) ],
        BIP39PrivateKeyPassword: "",
        BIP39PrivateKeyStringKey: "BIP39 private seed",
        BIP39PublicKeyStringKeyLegacy0: "BIP39 public key legacy0 chain",
        BIP39PublicKeyStringKeyLegacy0Change: "BIP39 public key legacy0 change chain",
        BIP39PublicKeyStringKeyLegacy44: "BIP39 public key legacy44 chain",
        BIP39PublicKeyStringKeyLegacy44Change: "BIP39 public key legacy44 change chain",
        BIP39PublicKeyStringKeyLegacySegwit: "BIP39 public key legacy-segwit chain",
        BIP39PublicKeyStringKeyLegacySegwitChange: "BIP39 public key legacy-segwit change chain",
        BIP39PublicKeyStringKeySegwit: "BIP39 public key segwit chain",
        BIP39PublicKeyStringKeySegwitChange: "BIP39 public key segwit change chain",
        BIP39PublicKeyStringKeyTaproot: "BIP39 public key taproot chain",
        BIP39PublicKeyStringKeyTaprootChange: "BIP39 public key taproot change chain",
        BIP39SeedEntropy: .b128,
        BIP39SeedLanguage: .english,
        CoinConsolidateBacklog: 6,
        CoinConsolidateUnconfirmed: 100,
        CoinRepoFileName: "wcoin.dat",
        DataFileDirectory: Self.libPath(),
        DustAmount: 546,
        MaximumRollback: 100000,
        Network: .main,
        NIOByteBufferAllocator: ByteBufferAllocator(),
        NonBlockingFileIOClientFactory: NonBlockingFileIOClient.live(_:),
        PubKeyLookahead: 25,
        PubKeyRepoFindBuffer: 2000,
        WalletPropertiesFactory: {
            Vault.Properties.simulator(eventLoop: $0,
                                  threadPool: $1,
                                  userDefaults: UserDefaults.standard)
        }
    )

    static let simulatorTest: Self = .init(
        BlockExplorerURL: "https://www.blockchain.com",
        BIP39Legacy0AccountPath: [ .hardened(0), ],
        BIP39Legacy44AccountPath: [ .hardened(44), .hardened(0), .hardened(0) ],
        BIP39LegacySegwitAccountPath: [ .hardened(49), .hardened(0), .hardened(0) ],
        BIP39SegwitAccountPath: [ .hardened(84), .hardened(0), .hardened(0) ],
        BIP39TaprootAccountPath: [ .hardened(86), .hardened(0), .hardened(0) ],
        BIP39PrivateKeyPassword: "",
        BIP39PrivateKeyStringKey: "BIP39 private seed",
        BIP39PublicKeyStringKeyLegacy0: "BIP39 public key legacy0 chain",
        BIP39PublicKeyStringKeyLegacy0Change: "BIP39 public key legacy0 change chain",
        BIP39PublicKeyStringKeyLegacy44: "BIP39 public key legacy44 chain",
        BIP39PublicKeyStringKeyLegacy44Change: "BIP39 public key legacy44 change chain",
        BIP39PublicKeyStringKeyLegacySegwit: "BIP39 public key legacy-segwit chain",
        BIP39PublicKeyStringKeyLegacySegwitChange: "BIP39 public key legacy-segwit change chain",
        BIP39PublicKeyStringKeySegwit: "BIP39 public key segwit chain",
        BIP39PublicKeyStringKeySegwitChange: "BIP39 public key segwit change chain",
        BIP39PublicKeyStringKeyTaproot: "BIP39 public key taproot chain",
        BIP39PublicKeyStringKeyTaprootChange: "BIP39 public key taproot change chain",
        BIP39SeedEntropy: .b128,
        BIP39SeedLanguage: .english,
        CoinConsolidateBacklog: 6,
        CoinConsolidateUnconfirmed: 100,
        CoinRepoFileName: "wcoin.dat",
        DataFileDirectory: Self.libPath(),
        DustAmount: 546,
        MaximumRollback: 100000,
        Network: .testnet,
        NIOByteBufferAllocator: ByteBufferAllocator(),
        NonBlockingFileIOClientFactory: NonBlockingFileIOClient.live(_:),
        PubKeyLookahead: 25,
        PubKeyRepoFindBuffer: 2000,
        WalletPropertiesFactory: {
            Vault.Properties.simulator(eventLoop: $0,
                                       threadPool: $1,
                                       userDefaults: UserDefaults.standard)
        }
    )

    static let testnet: Self = .init(
        BlockExplorerURL: "https://www.blockchain.com/btc-testnet",
        BIP39Legacy0AccountPath: [ .hardened(0), ],
        BIP39Legacy44AccountPath: [ .hardened(44), .hardened(0), .hardened(0) ],
        BIP39LegacySegwitAccountPath: [ .hardened(49), .hardened(0), .hardened(0) ],
        BIP39SegwitAccountPath: [ .hardened(84), .hardened(0), .hardened(0) ],
        BIP39TaprootAccountPath: [ .hardened(86), .hardened(0), .hardened(0) ],
        BIP39PrivateKeyPassword: "",
        BIP39PrivateKeyStringKey: "BIP39 private seed",
        BIP39PublicKeyStringKeyLegacy0: "BIP39 public key legacy0 chain",
        BIP39PublicKeyStringKeyLegacy0Change: "BIP39 public key legacy0 change chain",
        BIP39PublicKeyStringKeyLegacy44: "BIP39 public key legacy44 chain",
        BIP39PublicKeyStringKeyLegacy44Change: "BIP39 public key legacy44 change chain",
        BIP39PublicKeyStringKeyLegacySegwit: "BIP39 public key legacy-segwit chain",
        BIP39PublicKeyStringKeyLegacySegwitChange: "BIP39 public key legacy-segwit change chain",
        BIP39PublicKeyStringKeySegwit: "BIP39 public key segwit chain",
        BIP39PublicKeyStringKeySegwitChange: "BIP39 public key segwit change chain",
        BIP39PublicKeyStringKeyTaproot: "BIP39 public key taproot chain",
        BIP39PublicKeyStringKeyTaprootChange: "BIP39 public key taproot change chain",
        BIP39SeedEntropy: .b128,
        BIP39SeedLanguage: .english,
        CoinConsolidateBacklog: 6,
        CoinConsolidateUnconfirmed: 100,
        CoinRepoFileName: "wcoin.dat",
        DataFileDirectory: Self.libPath(),
        DustAmount: 546,
        MaximumRollback: 200,
        Network: .testnet,
        NIOByteBufferAllocator: ByteBufferAllocator(),
        NonBlockingFileIOClientFactory: NonBlockingFileIOClient.live(_:),
        PubKeyLookahead: 25,
        PubKeyRepoFindBuffer: 2000,
        WalletPropertiesFactory: {
            Vault.Properties.live(eventLoop: $0,
                                  threadPool: $1,
                                  userDefaults: UserDefaults.standard)
        }
    )

    private static func libPath() -> URL {
        let fm = FileManager.default
        
        var supportDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).last!
        supportDirectory.appendPathComponent(Bundle.main.bundleIdentifier ?? "app.fltr.fltrWallet")
        
        return supportDirectory
    }
}

#if DEBUG
public var GlobalFltrWalletSettings: Vault.Settings = .testnet
#else
public let GlobalFltrWalletSettings: Vault.Settings = .live
#endif


// TODO: BUG in iOS Simulator, which cannot access the keychain
// Below and alternative implementation where keyChain is accessed
// used properties instead. WARN: NOT FOR PRODUCTION.
import KeyChainClientAPI
import UserDefaultsClientAPI

extension Vault.Properties {
    static func simulator(eventLoop: EventLoop,
                          threadPool: NIOThreadPool,
                          userDefaults: UserDefaults) -> Self {
#if DEBUG
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        return .init(eventLoop: eventLoop,
                     threadPool: threadPool,
                     keyChain: .properties,
                     privateKeyHash: .live(key: "WalletPrivateKeyHash", defaults: userDefaults, encoder: encoder, decoder: decoder),
                     bip39Language: .live(key: "WalletBIP39SeedLanguage", defaults: userDefaults, encoder: encoder, decoder: decoder),
                     walletActive: .live(key: "WalletActiveFile", defaults: userDefaults, encoder: encoder, decoder: decoder)) {
            .live(key: $0, defaults: userDefaults, encoder: encoder, decoder: decoder)
        }
#else
        fatalError()
#endif
    }
}

extension KeyChainClient {
    static let properties: Self = {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let userDefaults = UserDefaults.standard
        
        let factory: (String) -> UserDefaultsProperty<[UInt8]> = { key in
            .live(key: key, defaults: userDefaults, encoder: encoder, decoder: decoder)
        }
        
        return .init(exists: { key in
            let property = factory(key)
            return property.exists()
        }, get: { key in
            let property = factory(key)
            return property.get()!
        }, put: { key, data, _ in
            let property = factory(key)
            property.put(data)
        })
    }()
}
