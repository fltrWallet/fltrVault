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
    static func createPublicKeyRepoFiles() {
        let fm = FileManager.default
        try! fm.createDirectory(at: GlobalFltrWalletSettings.DataFileDirectory,
                                withIntermediateDirectories: true, attributes: nil)
        
        Vault.allPublicKeyRepoFileNames()
        .map(\.value)
        .map {
            Vault.pathString(from: $0, in: GlobalFltrWalletSettings.DataFileDirectory)
        }
        .forEach {
            fm.createFile(atPath: $0,
                          contents: Data([]),
                          attributes: nil)
        }
    }
    
    static func removePublicKeyRepoFiles() throws {
        let fm = FileManager.default
        
        try Vault.allPublicKeyRepoFileNames()
        .map(\.value)
        .forEach {
            try fm.removeItem(atPath: Vault.pathString(from: $0,
                                                        in: GlobalFltrWalletSettings.DataFileDirectory))
        }
    }
    
    static func withPubKeyRepo<T>(source: HD.Source,
                                  fn: (Vault.PublicKeyRepo) -> T) -> T {
        let niots = NIOTSEventLoopGroup(loopCount: 1)
        let eventLoop = niots.next()
        let threadPool = NIOThreadPool(numberOfThreads: 1)
        threadPool.start()
        
        let fileName = Vault.pathString(from: HD.Source.uniqueCases.first(where: { source.mirror.contains($0) })!.fileName!,
                                        in: GlobalFltrWalletSettings.DataFileDirectory)
        let fileIO = NonBlockingFileIOClient.live(threadPool)
        let fileHandle = try! fileIO.openFile(path: fileName,
                                              mode: [ .read, .write ],
                                              flags: .default,
                                              eventLoop: eventLoop).wait()
        
        let pkhRepo = Vault.PublicKeyRepo(nioFileHandle: fileHandle,
                                          fileIO: fileIO,
                                          eventLoop: eventLoop)

        defer {
            try! pkhRepo.close().wait()
            try! threadPool.syncShutdownGracefully()
            try! niots.syncShutdownGracefully()
        }

        return fn(pkhRepo)
    }
}
