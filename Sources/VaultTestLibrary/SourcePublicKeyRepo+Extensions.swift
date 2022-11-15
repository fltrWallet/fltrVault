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
import fltrTx
import fltrWAPI
import NIO

extension Vault.SourcePublicKeyRepo {
    func lastScriptPubKey() -> EventLoopFuture<ScriptPubKey> {
        self._lastPublicKey()
        .map { dto in
            ScriptPubKey(tag: self.source.rawValue,
                         index: UInt32(dto.id),
                         opcodes: self.source.scriptPubKey(from: dto))
        }
    }
    
    public func findIndex(for scriptPubKey: ScriptPubKey,
                   event: StaticString = #function) -> EventLoopFuture<UInt32> {
        self.__repo.findIndex(for: scriptPubKey, event: event)
    }
}
