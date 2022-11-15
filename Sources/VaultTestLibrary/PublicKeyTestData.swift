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
import fltrTx
@testable import fltrVault
import HaByLo

public extension Test {
    struct PublicKeyNodes {
        public let `private`: HD.FullNode
        public let nodeDictionary: [HD.Source : HD.FullNode]
    }
    
    static func dataSet01() -> Test.PublicKeyNodes {
        var root = Vault.load(walletSeed: Test.Entropy, password: GlobalFltrWalletSettings.BIP39PrivateKeyPassword)

        let allNodes = HD.Source.allCases.map {
            ($0, try! $0.fullNode(from: &root))
        }
        .reduce(into: [HD.Source : HD.FullNode]()) {
            $0[$1.0] = $1.1
        }
        
        HD.Source.allCases
        .forEach { source in
            Test.withPubKeyRepo(source: source) { repo in
                (0...Int(10)).forEach { index in
                    var node = allNodes[source]!
                    let dto: PublicKeyDTO = {
                        if source.xPoint {
                            let tweaked = node.tweak(for: index)
                            return PublicKeyDTO(id: index, point: tweaked.pubkey().xPoint)
                        } else {
                            let secretKey = DSA.SecretKey(node.childKey(index: index).key.private)
                            return PublicKeyDTO(id: index, point: secretKey.pubkey())

                        }
                    }()
                    
                    try! repo.write(dto).wait()
                }
            }
        }
        
        return Test.PublicKeyNodes(private: root,
                                   nodeDictionary: allNodes)
    }
}
