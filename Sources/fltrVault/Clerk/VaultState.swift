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
import fltrTx
import NIO

extension Vault {
    struct AllPublicKeyRepos {
        let legacy0Repo: Vault.SourcePublicKeyRepo
        let legacy0ChangeRepo: Vault.SourcePublicKeyRepo
        let legacy44Repo: Vault.SourcePublicKeyRepo
        let legacy44ChangeRepo: Vault.SourcePublicKeyRepo
        let legacySegwitRepo: Vault.SourcePublicKeyRepo
        let legacySegwitChangeRepo: Vault.SourcePublicKeyRepo
        let segwit0Repo: Vault.SourcePublicKeyRepo
        let segwit0ChangeRepo: Vault.SourcePublicKeyRepo
        let segwitRepo: Vault.SourcePublicKeyRepo
        let segwitChangeRepo: Vault.SourcePublicKeyRepo
        let taprootRepo: Vault.SourcePublicKeyRepo
        let taprootChangeRepo: Vault.SourcePublicKeyRepo
    }
}

extension Vault {
    typealias DispatchHandler = (Tx.AnyTransaction) -> EventLoopFuture<Void>
    typealias WalletEventHandler = (WalletEvent) -> EventLoopFuture<Void>
    enum State {
        case idle(NIOThreadPool, DispatchHandler, WalletEventHandler)
        case running(LoadedState)
        case stopped
    
        struct LoadedState {
            let threadPool: NIOThreadPool
            let fileIO: NonBlockingFileIOClient
            let properties: Properties
            let coinRepos: CoinRepoPair
            let publicKeyRepos: Vault.AllPublicKeyRepos
            let dispatchHandler: Vault.DispatchHandler
            let walletEventHandler: Vault.WalletEventHandler
        }
    }
}

extension Vault.Clerk {
    public func load(properties: Vault.Properties) -> EventLoopFuture<Void> {
        switch self.state {
        case .idle(let threadPool, let dispatchHandler, let walletEventHandler):
            return Vault.load(properties: properties,
                              eventLoop: eventLoop,
                              threadPool: threadPool,
                              dispatchHandler: dispatchHandler,
                              walletEventHandler: walletEventHandler)
            .map {
                self.state = .running($0)
            }
        case .running:
            return self.eventLoop.makeFailedFuture(Error.illegalState(self))
        case .stopped:
            return self.eventLoop.makeFailedFuture(Error.illegalState(self))
        }
    }
    
    public func stop() -> EventLoopFuture<Void> {
        switch self.state {
        case .running(let loaded):
            let closers = HD.Source.uniqueCases
            .map {
                $0.repo(from: loaded.publicKeyRepos)
            }
            .map {
                $0.close()
                .recover {
                    preconditionFailure("\($0)")
                }
            }
            
            return loaded.coinRepos.close()
            .recover {
                preconditionFailure("\($0)")
            }
            .and(
                EventLoopFuture.andAllSucceed(closers, on: self.eventLoop)
            )
            .map { _ in
                self.state = .stopped
            }
        case .stopped, .idle:
            return self.eventLoop.makeFailedFuture(Error.illegalState(self))
        }
    }

    func checkLoadedState() -> EventLoopFuture<Vault.State.LoadedState> {
        switch self.state {
        case .running(let state):
            return self.eventLoop.makeSucceededFuture(state)
        case .idle, .stopped:
            return self.eventLoop.makeFailedFuture(Error.illegalState(self))
        }
    }
}

extension Vault.State: CustomDebugStringConvertible {
    var debugDescription: String {
        var str = [ "Vault.Clerk(state: " ]
        
        str.append(
            {
                switch self {
                case .idle:
                    return ".start"
                case .running:
                    return ".load"
                case .stopped:
                    return ".stop"
                }
            }()
        )
        
        str.append(")")
        
        return str.joined()
    }
}
