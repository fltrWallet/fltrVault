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
import Foundation
import FileRepo
@testable import fltrVault
import NIO
import NIOTransportServices

public extension Test {
    static let CoinOne = GlobalFltrWalletSettings.DataFileDirectory
        .appendingPathComponent(GlobalFltrWalletSettings.CoinRepoFileName + ".1").path
    static let CoinTwo = GlobalFltrWalletSettings.DataFileDirectory
        .appendingPathComponent(GlobalFltrWalletSettings.CoinRepoFileName + ".2").path

    static func createCoinRepoFiles() {
        let fm = FileManager.default
        try! fm.createDirectory(at: GlobalFltrWalletSettings.DataFileDirectory,
                                withIntermediateDirectories: true, attributes: nil)
        fm.createFile(atPath: CoinOne,
                      contents: Data([]),
                      attributes: nil)
        fm.createFile(atPath: CoinTwo,
                      contents: Data([]),
                      attributes: nil)
    }
    
    static func removeCoinRepoFiles() throws {
        try FileManager.default.removeItem(
            atPath: Vault.pathString(from: GlobalFltrWalletSettings.CoinRepoFileName + ".1",
                                      in: GlobalFltrWalletSettings.DataFileDirectory))
        try FileManager.default.removeItem(
            atPath: Vault.pathString(from: GlobalFltrWalletSettings.CoinRepoFileName + ".2",
                                      in: GlobalFltrWalletSettings.DataFileDirectory))
    }
    
    static func withCoinRepo<T>(fn: (Vault.CoinRepo) throws -> T) rethrows -> T {
        let niots = NIOTSEventLoopGroup(loopCount: 1)
        let eventLoop = niots.next()
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        
        let fileIO = NonBlockingFileIOClient.live(threadPool)
        let fileHandle = try! fileIO.openFile(path: CoinOne,
                                              mode: [ .read, .write ],
                                              flags: .default,
                                              eventLoop: eventLoop).wait()
        
        let coinRepo = Vault.CoinRepo(fileHandle: fileHandle,
                                       nonBlockingFileIO: fileIO,
                                       eventLoop: eventLoop)
        
        defer {
            try! coinRepo.close().wait()
            try! threadPool.syncShutdownGracefully()
            try! niots.syncShutdownGracefully()
            
        }

        return try fn(coinRepo)
    }
    
    static func write(coins: [HD.Coin]) {
        Self.withCoinRepo { coinRepo in
            try! coinRepo.append(coins).wait()
        }
    }
}
