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

public struct ChainCode: SecretBytes, Codable, Equatable {
    public let buffer: CodableBuffer
    public init(_ buffer: CodableBuffer) {
        assert(buffer.count == 32)
        self.buffer = buffer
    }
}

