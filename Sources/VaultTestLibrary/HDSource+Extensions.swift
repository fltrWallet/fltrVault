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
@testable import fltrVault
import fltrECC
import fltrWAPI

public extension HD.Source {
    func publicKeyDto(neutered node: HD.NeuteredNode, index: Int) -> PublicKeyDTO {
        var node = node
        
        if self.xPoint {
            let publicKey = node.tweak(for: index)
            return .init(id: index, point: publicKey)
        } else {
            let publicKey = node.childKey(index: index).key.public
            return .init(id: index, point: DSA.PublicKey(publicKey))
        }
    }
}
