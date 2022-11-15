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
import NIO

extension Vault {
    final class CoinRepoPair {
        private var coinRepos: (current: CoinRepo, backup: CoinRepo)
        private let callback: () -> Void
        
        init(current: CoinRepo, backup: CoinRepo, `switch` callback: @escaping () -> Void) {
            self.coinRepos = (current, backup)
            self.callback = callback
        }
        
        var current: CoinRepo {
            self.coinRepos.current
        }
        
        var backup: CoinRepo {
            self.coinRepos.backup
        }
        
        func `switch`(threadPool: NIOThreadPool, eventLoop: EventLoop) -> EventLoopFuture<Void> {
            self.coinRepos = (current: self.coinRepos.backup,
                              backup: self.coinRepos.current)
            
            return threadPool.runIfActive(eventLoop: eventLoop) {
                self.callback()
            }
        }
        
        func close() -> EventLoopFuture<Void> {
            self.coinRepos.current.close()
            .and(
                self.coinRepos.backup.close()
            )
            .map { _ in () }
        }
    }
}
