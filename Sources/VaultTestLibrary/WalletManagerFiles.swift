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
@testable import fltrVault
import Foundation

public extension Test {
    static func removeAllFiles() throws {
        try FileManager.default.removeItem(
            atPath: Vault.pathString(from: GlobalFltrWalletSettings.CoinRepoFileName + ".1",
                                      in: GlobalFltrWalletSettings.DataFileDirectory))
        try FileManager.default.removeItem(
            atPath: Vault.pathString(from: GlobalFltrWalletSettings.CoinRepoFileName + ".2",
                                      in: GlobalFltrWalletSettings.DataFileDirectory))

        try Vault.allPublicKeyRepoFileNames()
        .map(\.value)
        .forEach {
            try FileManager.default.removeItem(
                atPath: Vault.pathString(from: $0,
                                          in: GlobalFltrWalletSettings.DataFileDirectory))
        }
    }
}
