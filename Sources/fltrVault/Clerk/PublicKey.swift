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
import FileRepo
import fltrTx
import HaByLo
import NIO
import fltrWAPI

internal extension Vault.Clerk {
    func checkPath(repo: Vault.SourcePublicKeyRepo,
                   scriptPubKey: ScriptPubKey) -> EventLoopFuture<Bool> {
        repo.scriptPubKey(id: Int(scriptPubKey.index))
        .map {
            if let source = HD.Source(rawValue: scriptPubKey.tag),
               source == repo.source,
               $0.elementsEqual(scriptPubKey.opcodes) {
                return true
            } else {
                return false
            }
        }
        .flatMapError { error in
            switch error {
            case File.Error.seekError:
                return self.eventLoop.makeSucceededFuture(false)
            default:
                return self.eventLoop.makeFailedFuture(error)
            }
        }
    }
}

public extension Vault.Clerk {
    func lastAddress(for source: HD.Source) -> EventLoopFuture<String> {
        func doLastAddress() -> EventLoopFuture<String> {
            self.checkLoadedState()
            .flatMap { loaded in
                source.repo(from: loaded.publicKeyRepos)
                .lastAddress()
                .recover { preconditionFailure("\($0)") }
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doLastAddress()
            : self.eventLoop.flatSubmit(doLastAddress)
    }
    
    func scriptPubKey(type source: HD.Source) -> EventLoopFuture<[ScriptPubKey]> {
        func doScriptPubKey() -> EventLoopFuture<[ScriptPubKey]> {
            self.checkLoadedState()
            .flatMap { loaded in
                source.repo(from: loaded.publicKeyRepos)
                .scriptPubKeys()
            }
            .flatMapError { error in
                preconditionFailure("\(error)")
            }
        }
        
        return self.eventLoop.inEventLoop
            ? doScriptPubKey()
            : self.eventLoop.flatSubmit(doScriptPubKey)
    }
    
    func scriptPubKeys() -> EventLoopFuture<[ScriptPubKey]> {
        let futures = HD.Source.allCases.map(self.scriptPubKey(type:))
        
        return EventLoopFuture.whenAllSucceed(futures, on: self.eventLoop)
        .map {
            Array($0.joined())
        }
    }
}
