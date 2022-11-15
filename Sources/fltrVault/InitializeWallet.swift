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
import fltrECC
import Foundation
import NIO
import fltrWAPI

extension Vault {
    enum IntegrityError: Swift.Error {
        case configuration
        case supportDirectoryFailure(Swift.Error)
        case coinRepoFileError
        case pubKeyFileError
    }
    
    static func integrityCheckRepoFiles() throws {
        let base = GlobalFltrWalletSettings.DataFileDirectory
        
        guard Vault.fileExists(name: GlobalFltrWalletSettings.CoinRepoFileName + ".1", base: base)
        else { throw IntegrityError.coinRepoFileError }
        
        guard Vault.fileExists(name: GlobalFltrWalletSettings.CoinRepoFileName + ".2", base: base)
        else { throw IntegrityError.coinRepoFileError }
        
        let allPubKeyRepos = Self.allPublicKeyRepoFileNames()
        .reduce(true) {
            $0 && Vault.fileExists(name: $1.value, base: base)
        }

        guard allPubKeyRepos
        else { throw IntegrityError.pubKeyFileError }
    }
    
    static func touchDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            throw IntegrityError.supportDirectoryFailure(error)
        }
    }
    
    public static func pathString(from name: String, in directory: URL) -> String {
        directory.appendingPathComponent(name)
            .path
    }

    private static func fileExists(name: String, base: URL) -> Bool {
        let fm = FileManager.default
        
        let path = Vault.pathString(from: name, in: base)
        
        var directory = ObjCBool(false)
        let exists = fm.fileExists(atPath: path,
                                   isDirectory: &directory)
        guard exists && !directory.boolValue,
              fm.isReadableFile(atPath: path)
        else {
            return false
        }
        
        return true
    }

    static func fileHandles(fileIO: NonBlockingFileIOClient,
                            eventLoop: EventLoop)
    -> EventLoopFuture<(coinRepo1: NIOFileHandle,
                        coinRepo2: NIOFileHandle,
                        allPublicKeyHandles: [HD.Source : NIOFileHandle])> {
        let directory = GlobalFltrWalletSettings.DataFileDirectory
        let coinRepo = GlobalFltrWalletSettings.CoinRepoFileName

        let coinRepoPath1 = Vault.pathString(from: coinRepo + ".1", in: directory)
        let coinRepoPath2 = Vault.pathString(from: coinRepo + ".2", in: directory)

        let allPublicRepoFileNames = Self.allPublicKeyRepoFileNames()
        .mapValues { name in
            Vault.pathString(from: name, in: directory)
        }
        
        let coinRepoFutures = fileIO.openFile(path: coinRepoPath1,
                                              mode: [ .read, .write ],
                                              flags: .default,
                                              eventLoop: eventLoop)
        .and(
            fileIO.openFile(path: coinRepoPath2,
                            mode: [ .read, .write ],
                            flags: .default,
                            eventLoop: eventLoop)
        )
        .map { (coinRepo1: $0.0, coinRepo2: $0.1) }
        .recover { preconditionFailure("\($0)") }

        let allPublicKeyFutures = allPublicRepoFileNames
        .map { keyValue in
            fileIO.openFile(path: keyValue.value, mode: [ .read, .write ], flags: .default, eventLoop: eventLoop)
            .map { (keyValue.key, $0) }
        }
        
        let allPublicKeyRepos = EventLoopFuture.whenAllSucceed(allPublicKeyFutures, on: eventLoop)
        .recover { preconditionFailure("\($0)") }
        .map {
            $0.reduce(into: [HD.Source : NIOFileHandle]()) {
                $0[$1.0] = $1.1
            }
        }
        
        return coinRepoFutures.and(allPublicKeyRepos).map {
            ($0.0, $0.1, $1)
        }
    }
    
    static func allPublicKeyRepoFileNames() -> [HD.Source : String] {
        HD.Source.uniqueCases.map {
            ($0, $0.fileName!)
        }
        .reduce(into: [HD.Source : String]()) {
            $0[$1.0] = $1.1
        }
    }
    
    static func createAllPublicKeyRepos(fileIO: NonBlockingFileIOClient,
                                        eventLoop: EventLoop)
    -> EventLoopFuture<[HD.Source : NIOFileHandle]> {
        let directory = GlobalFltrWalletSettings.DataFileDirectory
        let futures: [EventLoopFuture<(HD.Source, NIOFileHandle)>] = Self.allPublicKeyRepoFileNames()
        .map { keyValue in
            let path = Vault.pathString(from: keyValue.value, in: directory)
            
            return fileIO.openFile(path: path,
                                   mode: [ .read, .write ],
                                   flags: .allowFileCreation(posixMode: 0o600),
                                   eventLoop: eventLoop)
            .map { (keyValue.key, $0) }
        }
        
        return EventLoopFuture.whenAllSucceed(futures, on: eventLoop)
        .recover { preconditionFailure("\($0)") }
        .map {
            $0.reduce(into: [HD.Source : NIOFileHandle]()) {
                $0[$1.0] = $1.1
            }
        }
    }

    
    private static func createFiles(properties: Properties,
                                    eventLoop: EventLoop,
                                    threadPool: NIOThreadPool,
                                    fileIO: NonBlockingFileIOClient) -> EventLoopFuture<Void> {
        let directory = GlobalFltrWalletSettings.DataFileDirectory
        let coinRepo = GlobalFltrWalletSettings.CoinRepoFileName

        func check(exists: Bool) -> EventLoopFuture<Void> {
            threadPool.runIfActive(eventLoop: eventLoop) {
                let allPublicKeyRepos = Self.allPublicKeyRepoFileNames()
                .map(\.value)
                .map {
                    Vault.fileExists(name: $0, base: directory)
                }
                .reduce(exists) { $0 && $1 }
                
                guard exists == Vault.fileExists(name: coinRepo + ".1", base: directory),
                      exists == Vault.fileExists(name: coinRepo + ".2", base: directory),
                      exists == allPublicKeyRepos
                else {
                    preconditionFailure("Expected file \(exists ? "" : "NOT") to exist")
                }
            }
        }
        
        func createDirectory(_ path: String) -> EventLoopFuture<Void> {
            threadPool.runIfActive(eventLoop: eventLoop) {
                try FileManager.default.createDirectory(atPath: path,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            }
        }

        func createCoinRepos() -> EventLoopFuture<(coinRepo1: NIOFileHandle, coinRepo2: NIOFileHandle)> {
            let first = fileIO.openFile(path: Vault.pathString(from: coinRepo + ".1", in: directory),
                                        mode: [ .read, .write ],
                                        flags: .allowFileCreation(posixMode: 0o600),
                                        eventLoop: eventLoop)
            let second = fileIO.openFile(path: Vault.pathString(from: coinRepo + ".2", in: directory),
                                         mode: [ .read, .write ],
                                         flags: .allowFileCreation(posixMode: 0o600),
                                         eventLoop: eventLoop)
            
            return first.and(second)
            .map { ($0, $1) }
        }
        
        
        let promise = eventLoop.makePromise(of: Void.self)
        let checkFuture = check(exists: false)
        let coinHandlesFuture = checkFuture.flatMap { _ in
            createDirectory(GlobalFltrWalletSettings.DataFileDirectory.path)
            .flatMap {
                createCoinRepos()
                .recover { preconditionFailure("\($0)") }
            }
        }
        coinHandlesFuture.cascadeFailure(to: promise)
        
        let allPubKeyRepos = coinHandlesFuture.flatMap { _ in
            Self.createAllPublicKeyRepos(fileIO: fileIO, eventLoop: eventLoop)
        }

        allPubKeyRepos
        .flatMap { handles -> EventLoopFuture<Void> in
            let repos = Self.allPublicKeyRepos(from: handles,
                                               fileIO: fileIO,
                                               eventLoop: eventLoop)
            return Vault.populateAll(properties: properties,
                                     allRepos: repos,
                                     eventLoop: eventLoop)
        }
        .whenComplete { _ in
            coinHandlesFuture.and(allPubKeyRepos)
            .whenSuccess { coinHandles, pubKeyHandles in
                let futures = [ fileIO.close(fileHandle: coinHandles.coinRepo1, eventLoop: eventLoop),
                                fileIO.close(fileHandle: coinHandles.coinRepo2, eventLoop: eventLoop) ]
                + pubKeyHandles
                    .map(\.value)
                    .map { fileIO.close(fileHandle: $0, eventLoop: eventLoop) }
                
                EventLoopFuture.andAllSucceed(futures, on: eventLoop)
                .whenComplete {
                    switch $0 {
                    case .success:
                        promise.succeed(())
                    case .failure(let error):
                        promise.fail(error)
                    }
                }
            }
        }
        
        return promise.futureResult
        .flatMap {
            check(exists: true)
        }
    }
    
    static func allPublicKeyRepos(from handles: [HD.Source : NIOFileHandle],
                                  fileIO: NonBlockingFileIOClient,
                                  eventLoop: EventLoop) -> Vault.AllPublicKeyRepos {
        func makeRepo(from handle: NIOFileHandle,
                      source: HD.Source) -> Vault.SourcePublicKeyRepo {
            let repo = PublicKeyRepo(nioFileHandle: handle,
                                     fileIO: fileIO,
                                     eventLoop: eventLoop)
            return .init(repo: repo, source: source)
        }

        let legacySegwit0Repo = PublicKeyRepo(nioFileHandle: handles[.legacy0]!,
                                              fileIO: fileIO,
                                              eventLoop: eventLoop)
        let legacySegwit0ChangeRepo = PublicKeyRepo(nioFileHandle: handles[.legacy0Change]!,
                                                    fileIO: fileIO,
                                                    eventLoop: eventLoop)
        return Vault.AllPublicKeyRepos(legacy0Repo: .init(repo: legacySegwit0Repo, source: .legacy0),
                                       legacy0ChangeRepo: .init(repo: legacySegwit0ChangeRepo, source: .legacy0Change),
                                       legacy44Repo: makeRepo(from: handles[.legacy44]!, source: .legacy44),
                                       legacy44ChangeRepo: makeRepo(from: handles[.legacy44Change]!,
                                                                    source: .legacy44Change),
                                       legacySegwitRepo: makeRepo(from: handles[.legacySegwit]!,
                                                                  source: .legacySegwit),
                                       legacySegwitChangeRepo: makeRepo(from: handles[.legacySegwitChange]!,
                                                                        source: .legacySegwitChange),
                                       segwit0Repo: .init(repo: legacySegwit0Repo, source: .segwit0),
                                       segwit0ChangeRepo: .init(repo: legacySegwit0ChangeRepo, source: .segwit0Change),
                                       segwitRepo: makeRepo(from: handles[.segwit]!, source: .segwit),
                                       segwitChangeRepo: makeRepo(from: handles[.segwitChange]!,
                                                                  source: .segwitChange),
                                       taprootRepo: makeRepo(from: handles[.taproot]!,
                                                             source: .taproot),
                                       taprootChangeRepo: makeRepo(from: handles[.taprootChange]!,
                                                                   source: .taprootChange))
    }
    
    public static func initializeAll(eventLoop: EventLoop,
                                     threadPool: NIOThreadPool,
                                     fileIO: NonBlockingFileIOClient,
                                     entropy: [UInt8]?)
    -> EventLoopFuture<(properties: Properties, words: [String])> {
        let seed: WalletSeedCodable = {
            if let entropy = entropy {
                return WalletSeedCodable(entropy: entropy, language: .english)
            } else {
                return Vault.walletSeedFactory(password: GlobalFltrWalletSettings.BIP39PrivateKeyPassword,
                                               language: GlobalFltrWalletSettings.BIP39SeedLanguage,
                                               seedEntropy: GlobalFltrWalletSettings.BIP39SeedEntropy)
            }
        }()

        return Vault.initializeAllProperties(eventLoop: eventLoop,
                                             threadPool: threadPool,
                                             walletSeed: seed)
        .flatMap { vaultProperties, words in
            Vault.createFiles(properties: vaultProperties,
                              eventLoop: eventLoop,
                              threadPool: threadPool,
                              fileIO: fileIO)
            .map {
                (properties: vaultProperties, words: words)
            }
        }
    }
    
    static func initializeAllProperties(eventLoop: EventLoop,
                                        threadPool: NIOThreadPool,
                                        walletSeed codable: WalletSeedCodable)
    -> EventLoopFuture<(properties: Properties, words: [String])> {
        let properties = GlobalFltrWalletSettings.WalletPropertiesFactory(eventLoop, threadPool)
        properties.reset()
        properties.resetActiveWalletFile()
        
        let entropy = BIP39.words(fromRandomness: codable.entropy, language: codable.language)!
        var root = HD.FullNode(entropy.bip32Seed(password: GlobalFltrWalletSettings.BIP39PrivateKeyPassword))!
        
        let publicKeyNodes: [Properties.WalletPublicKeyNodes] = HD.Source
        .uniqueCases
        .map {
            let node = try! $0.fullNode(from: &root).neuter()
            return Properties.WalletPublicKeyNodes($0, node: node)
        }
        
        let storeFutures = [
            properties.storePrivateKey(codable)
            .recover {
                preconditionFailure("\($0)")
            }
        ]
        + publicKeyNodes.map {
            properties.storePublicKey($0)
            .recover {
                preconditionFailure("\($0)")
            }
        }

        return Future.andAllSucceed(storeFutures, on: eventLoop)
        .map {
            (properties, entropy.words())
        }
    }
    
    static func populateAll(properties: Properties,
                            allRepos: Vault.AllPublicKeyRepos,
                            eventLoop: EventLoop) -> EventLoopFuture<Void> {
        func populateFuture(source: HD.Source,
                            populator: @escaping (Int, HD.NeuteredNode, Vault.SourcePublicKeyRepo) -> EventLoopFuture<Void>)
        -> EventLoopFuture<Void> {
            guard GlobalFltrWalletSettings.PubKeyLookahead > 0
            else {
                return eventLoop.makeFailedFuture(Vault.IntegrityError.configuration)
            }
            
            return properties.loadPublicKey(source: source)
            .flatMap { node in
                let futures: [Future<Void>] = (0...GlobalFltrWalletSettings.PubKeyLookahead)
                .map { index -> Future<Void> in
                    populator(index, node.node, node.sourceRepo.repo(from: allRepos))
                }
                
                return Future.andAllSucceed(futures, on: eventLoop)
                .recover { preconditionFailure("\($0)") }
            }
        }
        
        let futures = HD.Source.uniqueCases
        .map {
            $0.xPoint
            ? populateFuture(source: $0, populator: self.populateX(index:node:repo:))
            : populateFuture(source: $0, populator: self.populateECC(index:node:repo:))
        }

        return Future.andAllSucceed(futures, on: eventLoop)
        .recover { preconditionFailure("\($0)") }
    }

    fileprivate static func checkPopulate(repo: PublicKeyRepo,
                                          publicKey dto: PublicKeyDTO) -> EventLoopFuture<Void> {
        repo.write(dto)
        .flatMap {
            repo.range()
            .always {
                switch $0 {
                case .success(let range):
                    precondition(range.upperBound - 1 <= GlobalFltrWalletSettings.PubKeyLookahead + 1)
                case .failure(let error):
                    preconditionFailure("\(error)")
                }
            }
            .map { _ in () }
        }
    }
    
    static func populateECC(index: Int,
                            node: HD.NeuteredNode,
                            repo: Vault.SourcePublicKeyRepo) -> EventLoopFuture<Void> {
        var copy = node
        let childKey = copy.childKey(index: index)
        
        return repo.write(PublicKeyDTO(id: index, point: DSA.PublicKey(childKey.key.public)))
        .map { _ in () }
    }
    
    static func populateX(index: Int,
                          node: HD.NeuteredNode,
                          repo: Vault.SourcePublicKeyRepo) -> EventLoopFuture<Void> {
        let tweaked = node.tweak(for: index)

        return repo.write(PublicKeyDTO(id: index, point: tweaked))
        .map { _ in () }
    }
        
    static func load(properties: Properties,
                     eventLoop: EventLoop,
                     threadPool: NIOThreadPool,
                     fileIO: NonBlockingFileIOClient? = nil,
                     dispatchHandler: @escaping Vault.DispatchHandler,
                     walletEventHandler: @escaping Vault.WalletEventHandler)
    -> EventLoopFuture<Vault.State.LoadedState> {
        try! Vault.integrityCheckRepoFiles()
        
        let nonBlockingFileIO = fileIO ?? GlobalFltrWalletSettings.NonBlockingFileIOClientFactory(threadPool)
        
        return Vault.fileHandles(
            fileIO: nonBlockingFileIO,
            eventLoop: eventLoop
        )
        .map { fh -> (coinRepos: CoinRepoPair, allPublicKeyHandles: [HD.Source : NIOFileHandle]) in
            let firstRepo = CoinRepo(fileHandle: fh.coinRepo1,
                                     nonBlockingFileIO: nonBlockingFileIO,
                                     eventLoop: eventLoop)
            let secondRepo = CoinRepo(fileHandle: fh.coinRepo2,
                                      nonBlockingFileIO: nonBlockingFileIO,
                                      eventLoop: eventLoop)
            
            let coinRepos: CoinRepoPair = {
                if properties.firstActive {
                    return CoinRepoPair(current: firstRepo, backup: secondRepo, switch: properties.switch)
                } else {
                    return CoinRepoPair(current: secondRepo, backup: firstRepo, switch: properties.switch)
                }
            }()
            
            return (coinRepos, fh.allPublicKeyHandles)
        }
        .map {
            Vault.State.LoadedState(threadPool: threadPool,
                                    fileIO: nonBlockingFileIO,
                                    properties: properties,
                                    coinRepos: $0.coinRepos,
                                    publicKeyRepos: Self.allPublicKeyRepos(from: $0.allPublicKeyHandles,
                                                                           fileIO: nonBlockingFileIO,
                                                                           eventLoop: eventLoop),
                                    dispatchHandler: dispatchHandler,
                                    walletEventHandler: walletEventHandler)
        }
    }
}
