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
import HaByLo

fileprivate extension HD {
    static func uncheckedScalar(from hash: BlockChain.Hash<TapTweak>)
    -> UncheckedScalar {
        UncheckedScalar(unsafeUninitializedCapacity: 32) { bytes, size in
            hash.littleEndian.enumerated().forEach { i, h in
                bytes[i] = h
            }
            size = 32
        }
    }
}

public extension HD.FullNode {
    func tweak(for index: Int) -> X.SecretKey {
        var copy = self
        var diff = 0
        repeat {
            defer { diff += 1 }
            let privateKey = copy.childKey(index: index + diff).key.private
            let xKey = X.SecretKey(privateKey)
            let hash: BlockChain.Hash<TapTweak> = .makeHash(
                from: xKey
                    .pubkey()
                    .xPoint
                    .serialize()
            )
            let unchecked = HD.uncheckedScalar(from: hash)
            
            guard let tweak = Scalar(unchecked),
                  let tweakedKeyPair = xKey.tweak(add: tweak)
            else { continue }
            return tweakedKeyPair
        } while true
    }
}

public extension HD.NeuteredNode {
    func tweak(for index: Int) -> X.PublicKey {
        var copy = self
        var diff = 0
        repeat {
            defer { diff += 1 }
            let eccPoint = copy.childKey(index: index + diff).key.public
            let xPoint = X.PublicKey(eccPoint)
            let hash: BlockChain.Hash<TapTweak> = .makeHash(from: xPoint.serialize())
            let unchecked = HD.uncheckedScalar(from: hash)
            
            guard let tweak = Scalar(unchecked),
                  let tweakedPoint = xPoint.tweak(add: tweak)
            else { continue }
            return tweakedPoint.xOnly().xPubkey
        } while true
    }
}
