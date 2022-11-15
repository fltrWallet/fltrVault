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
import fltrVault
import KeyChainClientTest
import NIO
import UserDefaultsClientTest

extension Vault.Properties {
    static func test(eventLoop: EventLoop, threadPool: NIOThreadPool) -> Self {
        return .init(eventLoop: eventLoop,
                     threadPool: threadPool,
                     keyChain: .dict,
                     privateKeyHash: .inMemory(),
                     bip39Language: .inMemory(),
                     walletActive: .inMemory(),
                     property: { _ in .inMemory() })
    }
}
