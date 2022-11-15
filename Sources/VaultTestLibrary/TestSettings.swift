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
import fltrVault
import Foundation
import NIO

public extension Vault.Settings {
    static let test: Self = .init(
        BlockExplorerURL: "https://mempool.space/tx/",
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
        CoinConsolidateBacklog: 2,
        CoinConsolidateUnconfirmed: 4,
        CoinRepoFileName: "wcoin.dat",
        DataFileDirectory: URL(fileURLWithPath: "/tmp/test-fltr-wallet", isDirectory: true),
        DustAmount: 10,
        MaximumRollback: 2,
        Network: .testnet,
        NIOByteBufferAllocator: ByteBufferAllocator(),
        NonBlockingFileIOClientFactory: NonBlockingFileIOClient.live(_:),
        PubKeyLookahead: 10,
        PubKeyRepoFindBuffer: 2,
        WalletPropertiesFactory: { .test(eventLoop: $0, threadPool: $1) }
    )
}
