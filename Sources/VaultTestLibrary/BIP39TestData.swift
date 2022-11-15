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
@testable import fltrVault
import NIO

public extension Test {
    static let Entropy: Vault.WalletSeedCodable = {
        let password = [ "Can", "Cherry", "Intact", "Height",
                         "Enact", "Rapid", "Erode", "Cable",
                         "Category", "Theme", "Gym", "Bread" ]
        let entropy = BIP39.Language.english.entropyBytes(from: password.map { $0.lowercased() })!
        return Vault.WalletSeedCodable(entropy: entropy,
                                       language: .english)
    }()
    
    static func walletProperties(eventLoop: EventLoop,
                                 threadPool: NIOThreadPool) -> Vault.Properties {
        try! Vault.initializeAllProperties(eventLoop: eventLoop,
                                           threadPool: threadPool,
                                           walletSeed: Test.Entropy)
            .wait()
            .properties
    }
}
