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
import bech32
import FileRepo
import fltrTx
import Foundation
import NIO
import KeyChainClientLive
import KeyChainClientAsync
import UserDefaultsClientLive

public extension Vault {
    struct Settings {
        public let BlockExplorerURL: String
        public let BIP39Legacy0AccountPath: HD.Path
        public let BIP39Legacy44AccountPath: HD.Path
        public let BIP39LegacySegwitAccountPath: HD.Path
        public let BIP39SegwitAccountPath: HD.Path
        public let BIP39TaprootAccountPath: HD.Path
        public let BIP39PrivateKeyPassword: String
        public let BIP39PrivateKeyStringKey: String
        public let BIP39PublicKeyStringKeyLegacy0: String
        public let BIP39PublicKeyStringKeyLegacy0Change: String
        public let BIP39PublicKeyStringKeyLegacy44: String
        public let BIP39PublicKeyStringKeyLegacy44Change: String
        public let BIP39PublicKeyStringKeyLegacySegwit: String
        public let BIP39PublicKeyStringKeyLegacySegwitChange: String
        public let BIP39PublicKeyStringKeySegwit: String
        public let BIP39PublicKeyStringKeySegwitChange: String
        public let BIP39PublicKeyStringKeyTaproot: String
        public let BIP39PublicKeyStringKeyTaprootChange: String
        public let BIP39SeedEntropy: BIP39.Width
        public let BIP39SeedLanguage: BIP39.Language
        public let CoinConsolidateBacklog: Int
        public let CoinConsolidateUnconfirmed: Int
        public let CoinRepoFileName: String
        public let DataFileDirectory: URL
        public let DustAmount: UInt64
        public let MaximumRollback: Int
        public let Network: Network
        public let NIOByteBufferAllocator: ByteBufferAllocator
        public let NonBlockingFileIOClientFactory: (NIOThreadPool) -> NonBlockingFileIOClient
        public var PubKeyLookahead: Int
        public let PubKeyRepoFindBuffer: Int
        public let WalletPropertiesFactory: (EventLoop, NIOThreadPool) -> Vault.Properties
        

        public init(BlockExplorerURL: String,
                    BIP39Legacy0AccountPath: HD.Path,
                    BIP39Legacy44AccountPath: HD.Path,
                    BIP39LegacySegwitAccountPath: HD.Path,
                    BIP39SegwitAccountPath: HD.Path,
                    BIP39TaprootAccountPath: HD.Path,
                    BIP39PrivateKeyPassword: String,
                    BIP39PrivateKeyStringKey: String,
                    BIP39PublicKeyStringKeyLegacy0: String,
                    BIP39PublicKeyStringKeyLegacy0Change: String,
                    BIP39PublicKeyStringKeyLegacy44: String,
                    BIP39PublicKeyStringKeyLegacy44Change: String,
                    BIP39PublicKeyStringKeyLegacySegwit: String,
                    BIP39PublicKeyStringKeyLegacySegwitChange: String,
                    BIP39PublicKeyStringKeySegwit: String,
                    BIP39PublicKeyStringKeySegwitChange: String,
                    BIP39PublicKeyStringKeyTaproot: String,
                    BIP39PublicKeyStringKeyTaprootChange: String,
                    BIP39SeedEntropy: BIP39.Width,
                    BIP39SeedLanguage: BIP39.Language,
                    CoinConsolidateBacklog: Int,
                    CoinConsolidateUnconfirmed: Int,
                    CoinRepoFileName: String,
                    DataFileDirectory: URL,
                    DustAmount: UInt64,
                    MaximumRollback: Int,
                    Network: Network,
                    NIOByteBufferAllocator: ByteBufferAllocator,
                    NonBlockingFileIOClientFactory: @escaping (NIOThreadPool) -> NonBlockingFileIOClient,
                    PubKeyLookahead: Int,
                    PubKeyRepoFindBuffer: Int,
                    WalletPropertiesFactory: @escaping (EventLoop, NIOThreadPool) -> Vault.Properties) {
            self.BlockExplorerURL = BlockExplorerURL
            self.BIP39Legacy0AccountPath = BIP39Legacy0AccountPath
            self.BIP39Legacy44AccountPath = BIP39Legacy44AccountPath
            self.BIP39LegacySegwitAccountPath = BIP39LegacySegwitAccountPath
            self.BIP39SegwitAccountPath = BIP39SegwitAccountPath
            self.BIP39TaprootAccountPath = BIP39TaprootAccountPath
            self.BIP39PrivateKeyPassword = BIP39PrivateKeyPassword
            self.BIP39PrivateKeyStringKey = BIP39PrivateKeyStringKey
            self.BIP39PublicKeyStringKeyLegacy0 = BIP39PublicKeyStringKeyLegacy0
            self.BIP39PublicKeyStringKeyLegacy0Change = BIP39PublicKeyStringKeyLegacy0Change
            self.BIP39PublicKeyStringKeyLegacy44 = BIP39PublicKeyStringKeyLegacy44
            self.BIP39PublicKeyStringKeyLegacy44Change = BIP39PublicKeyStringKeyLegacy44Change
            self.BIP39PublicKeyStringKeyLegacySegwit = BIP39PublicKeyStringKeyLegacySegwit
            self.BIP39PublicKeyStringKeyLegacySegwitChange = BIP39PublicKeyStringKeyLegacySegwitChange
            self.BIP39PublicKeyStringKeySegwit = BIP39PublicKeyStringKeySegwit
            self.BIP39PublicKeyStringKeySegwitChange = BIP39PublicKeyStringKeySegwitChange
            self.BIP39PublicKeyStringKeyTaproot = BIP39PublicKeyStringKeyTaproot
            self.BIP39PublicKeyStringKeyTaprootChange = BIP39PublicKeyStringKeyTaprootChange
            self.BIP39SeedEntropy = BIP39SeedEntropy
            self.BIP39SeedLanguage = BIP39SeedLanguage
            self.CoinConsolidateBacklog = CoinConsolidateBacklog
            self.CoinConsolidateUnconfirmed = CoinConsolidateUnconfirmed
            self.CoinRepoFileName = CoinRepoFileName
            self.DataFileDirectory = DataFileDirectory
            self.DustAmount = DustAmount
            self.MaximumRollback = MaximumRollback
            self.Network = Network
            self.NIOByteBufferAllocator = NIOByteBufferAllocator
            self.NonBlockingFileIOClientFactory = NonBlockingFileIOClientFactory
            self.PubKeyLookahead = PubKeyLookahead
            self.PubKeyRepoFindBuffer = PubKeyRepoFindBuffer
            self.WalletPropertiesFactory = WalletPropertiesFactory
        }
    }
}
