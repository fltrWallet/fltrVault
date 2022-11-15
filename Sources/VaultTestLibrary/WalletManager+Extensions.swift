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
@testable import fltrVault
import fltrTx
import NIO

public extension Vault.Clerk {
    func privateECCKey(for path: HD.Path) -> EventLoopFuture<Scalar> {
        self.privateKey()
        .map {
            var fullNode = $0
            
            return fullNode
                .childKey(path: path)
                .key
                .private
        }
    }

    func privateXKey(for path: HD.Path) -> EventLoopFuture<X.SecretKey> {
        self.privateKey()
        .map {
            var fullNode = $0
            
            let last = path.last!
            let path: HD.Path = HD.Path(path.dropLast())
            
            return fullNode
                .childKey(path: path)
                .tweak(for: Int(last.index()))
        }
    }
    
    func lastOpcodes(for source: HD.Source) -> EventLoopFuture<ScriptPubKey> {
        self.checkLoadedState()
        .flatMap { loaded in
            source.repo(from: loaded.publicKeyRepos)
            .lastScriptPubKey()
        }
    }
}
