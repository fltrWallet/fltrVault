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
import fltrTx
import HaByLo
import NIO
import fltrWAPI

extension Vault {
    struct SourcePublicKeyRepo {
        private let repo: PublicKeyRepo
        let source: HD.Source
        
        // TESTING
        var __repo: PublicKeyRepo {
            self.repo
        }
        
        init(repo: Vault.PublicKeyRepo, source: HD.Source) {
            self.repo = repo
            self.source = source
        }
        
        func changeCallback(properties: Vault.Properties,
                            walletEventHandler: @escaping Vault.WalletEventHandler)
        -> EventLoopFuture<(index: UInt32, script: [UInt8])> {
            let uniqueSource = self._uniqueSource()
            
            return properties.loadPublicKey(source: uniqueSource)
            .flatMap { node in
                self.rebuffer(properties: properties,
                              walletEventHandler: walletEventHandler)
                .flatMap { index in
                    self.repo.find(id: index)
                    .always {
                        switch $0 {
                        case .success(let dto):
                            logger.info("Vault.Clerk \(#function) - "
                                        + "🥏 Change address #️⃣\(index) "
                                        + "\(self.source.address(from: dto))")
                        case .failure(let error):
                            preconditionFailure("\(error)")
                        }
                    }
                    .map { (UInt32(index), self.source.scriptPubKey(from: $0)) }
                }
            }
            
        }
        
        func close() -> EventLoopFuture<Void> {
            self.repo.close()
        }
        
        func endIndex() -> Future<Int> {
            self.repo.endIndex()
        }
        
        func lastAddress() -> EventLoopFuture<String> {
            self._lastPublicKey()
            .map {
                self.source.address(from: $0)
            }
        }
        
        func _lastPublicKey() -> EventLoopFuture<PublicKeyDTO> {
            self.repo.range()
            .map(\.upperBound)
            .flatMap { height in
                repo.find(id: height - GlobalFltrWalletSettings.PubKeyLookahead)
            }
        }
        
        private func _makeNextPubKeys(base: Int,
                                      count: Int,
                                      properties: Vault.Properties,
                                      wallet eventHandler: @escaping Vault.WalletEventHandler) -> EventLoopFuture<Void> {
            // execute in sequence and return most nested future
            func inner(_ i: Int, _ future: EventLoopFuture<Void>) -> EventLoopFuture<Void> {
                if i > 0 {
                    let nextFuture: EventLoopFuture<Void> = future.flatMap {
                        self._pubKey(for: base + count - i,
                                     properties: properties)
                        .flatMap { publicKeyDto in
                            self._pubKeyStoreNotify(publicKeyDto: publicKeyDto,
                                                    wallet: eventHandler)
                        }
                    }
                    return inner(i - 1, nextFuture)
                } else { // recursive base case
                    return future
                }
            }
            
            return inner(count, self.repo.eventLoop.makeSucceededVoidFuture())
        }
        
        // TESTING
        func __makeNextPubKeys(base: Int,
                               count: Int,
                               properties: Vault.Properties,
                               wallet eventHandler: @escaping Vault.WalletEventHandler)
        -> EventLoopFuture<Void> {
            self._makeNextPubKeys(base: base,
                                  count: count,
                                  properties: properties,
                                  wallet: eventHandler)
        }
        
        private func _pubKeyStoreNotify(publicKeyDto: PublicKeyDTO,
                                        wallet eventHandler: @escaping Vault.WalletEventHandler)
        -> EventLoopFuture<Void> {
            let promise = self.repo.eventLoop.makePromise(of: Void.self)
            
            self.write(publicKeyDto)
            .whenComplete {
                switch $0 {
                case .success(let scriptPubKeys):
                    let futures = scriptPubKeys.map {
                        eventHandler(.scriptPubKey($0))
                    }
                    
                    EventLoopFuture.andAllSucceed(futures, on: self.repo.eventLoop)
                    .cascade(to: promise)
                case .failure(let error):
                    promise.fail(error)
                }
            }

            return promise.futureResult
        }

        private func _eccPubKey(node: HD.NeuteredNode, index: Int) -> PublicKeyDTO {
            var copy = node
            let pubKey = copy.childKey(index: index).key.public
            return PublicKeyDTO(id: index, point: DSA.PublicKey(pubKey))
        }

        private func _xPubKey(node: HD.NeuteredNode, index: Int) -> PublicKeyDTO {
            let tweakedPoint = node.tweak(for: index)
            return PublicKeyDTO(id: index, point: tweakedPoint)
        }

        private func _pubKey(for index: Int,
                             properties: Vault.Properties) -> EventLoopFuture<PublicKeyDTO> {
            let source = self._uniqueSource()
            
            return properties.loadPublicKey(source: source)
            .map { publicKey in
                source.pubKeyFunc(ecc: self._eccPubKey(node:index:), x: self._xPubKey(node:index:),
                                  node: publicKey.node, index: index)
            }
        }
        
        private func _uniqueSource() -> HD.Source {
            self.source.mirror.first(where: { source in
                HD.Source.uniqueCases.contains(source)
            })!
        }
        
        func rebuffer(index: Int? = nil,
                      properties: Vault.Properties,
                      walletEventHandler: @escaping Vault.WalletEventHandler)
        -> EventLoopFuture<Int> {
            self.endIndex()
            .flatMap { endIndex in
                let deltaAndIndex: EventLoopFuture<(Int, Int)> = {
                    if endIndex > 0 {
                        let pathIndex = index ?? endIndex + 1 - GlobalFltrWalletSettings.PubKeyLookahead
                        precondition(pathIndex >= 0)
                        return self.repo.eventLoop.makeSucceededFuture((pathIndex.distance(to: endIndex), pathIndex))
                    } else {
                        return self._makeNextPubKeys(base: 0,
                                                     count: 1,
                                                     properties: properties,
                                                     wallet: walletEventHandler)
                        .map {
                            (0, 1)
                        }
                    }
                }()

                return deltaAndIndex.map { delta, pathIndex in
                    let rebuffer = delta < GlobalFltrWalletSettings.PubKeyLookahead
                    ? delta.distance(to: GlobalFltrWalletSettings.PubKeyLookahead)
                    : 0
                    
                    return (rebuffer, pathIndex)
                }
                .flatMap { rebuffer, pathIndex in
                    self._makeNextPubKeys(base: endIndex + 1,
                                          count: rebuffer,
                                          properties: properties,
                                          wallet: walletEventHandler)
                    .map { pathIndex }
                }
            }
        }
        
        func scriptPubKey(id: Int, event: StaticString = #function) -> EventLoopFuture<[UInt8]> {
            self.repo.find(id: id, event: event)
            .map {
                self.source.scriptPubKey(from: $0)
            }
        }
        
        func scriptPubKeys(event: StaticString = #function) -> EventLoopFuture<[ScriptPubKey]> {
            self.repo.find(from: 0, event: event)
            .recover {
                preconditionFailure("Cannot load pubkeys from repo \(source): \($0)")
            }
            .map { pubKeyDtos in
                pubKeyDtos.map {
                    ScriptPubKey(tag: self.source.rawValue,
                                 index: UInt32($0.id),
                                 opcodes: self.source.scriptPubKey(from: $0))
                }
            }
        }
        
        func write(_ dto: PublicKeyDTO, event: StaticString = #function) -> EventLoopFuture<[ScriptPubKey]> {
            self.repo.write(dto)
            .map {
                self.source.mirror.map {
                    ScriptPubKey(tag: $0.rawValue,
                                 index: UInt32(dto.id),
                                 opcodes: $0.scriptPubKey(from: dto))
                }
                
            }
        }
    }
}

fileprivate extension HD.Source {
    func pubKeyFunc(ecc: (HD.NeuteredNode, Int) -> PublicKeyDTO,
                    x: (HD.NeuteredNode, Int) -> PublicKeyDTO,
                    node: HD.NeuteredNode,
                    index: Int) -> PublicKeyDTO {
        self.xPoint
        ? x(node, index)
        : ecc(node, index)
    }
}

