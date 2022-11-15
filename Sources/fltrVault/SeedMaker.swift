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
import fltrWAPI

public extension Vault {
    struct WalletSeedCodable: Hashable, Codable {
        public let entropy: [UInt8]
        public let language: BIP39.Language
    }
    
    static func walletSeedFactory(password: String,
                                  language: BIP39.Language,
                                  seedEntropy: BIP39.Width) -> WalletSeedCodable {
        let randomBytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        
        let entropyBytes: ArraySlice<UInt8> = {
            switch seedEntropy {
            case .b128: return randomBytes.prefix(16)
            case .b160: return randomBytes.prefix(20)
            case .b192: return randomBytes.prefix(24)
            case .b224: return randomBytes.prefix(28)
            case .b256: return randomBytes[...]
            }
        } ()
        
        let entropy = BIP39.words(fromRandomness: Array(entropyBytes), language: language)!
        let bip32Seed = entropy.bip32Seed(password: password)

        guard Self.verifyPaths(for: bip32Seed)
        else {
            // Generate new random data for paths to work
            return Self.walletSeedFactory(password: password,
                                          language: language,
                                          seedEntropy: seedEntropy)
        }
        
        return WalletSeedCodable(entropy: Array(entropyBytes), language: language)
    }
    
    @inlinable
    static func verifyPaths(for bip32Seed: HD.Seed) -> Bool {
        guard var fullNode = HD.FullNode(bip32Seed)
        else { return false }

        func verifyPaths(nodes: [HD.FullNode], paths: HD.Path) -> Bool {
            var nodes = nodes[...]
            var paths = paths[...]
            
            guard nodes.popFirst()!.keyNumber == paths.popFirst()!,
                  nodes.popFirst()!.keyNumber == paths.popFirst()!
            else { return false }

            if let keyNumber = nodes.popFirst()?.keyNumber {
                return keyNumber == paths.popFirst()!
            } else {
                return true
            }
        }
        
        return HD.Source.allCases
        .map { source -> ([HD.FullNode], HD.Path) in
            let path = source.hdPath
            let nodes = try! fullNode.makeChildNode(for: path)
            
            return (nodes, path)
        }
        .reduce(true) {
            $0 && verifyPaths(nodes: $1.0, paths: $1.1)
        }
    }
    
    static func load(walletSeed: WalletSeedCodable, password: String) -> HD.FullNode {
        let entropy = BIP39.words(fromRandomness: walletSeed.entropy, language: walletSeed.language)!
        let bip32Seed = entropy.bip32Seed(password: password)
        
        return HD.FullNode(bip32Seed)!
    }
}
