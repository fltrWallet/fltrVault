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

struct CodableScalar: SecretBytes, Codable {
    public let buffer: CodableBuffer
    init(_ buffer: CodableBuffer) {
        assert(buffer.count == 32)
        self.buffer = buffer
    }
    
    init(_ scalar: Scalar) {
        self = scalar.withUnsafeBytes { scalar in
            Self.init(unsafeUninitializedCapacity: 32) { bytes, size in
                scalar.enumerated().forEach { i, _ in
                    bytes[i] = scalar[i]
                }
                size = scalar.count
            }
        }
    }
}

extension Scalar: Codable {
    enum CodingKeys: String, CodingKey {
        case scalar
    }
  
    public func encode(to encoder: Encoder) throws {
        try CodableScalar(self).encode(to: encoder)
    }
    
    public init(from decoder: Decoder) throws {
        let codable = try CodableScalar(from: decoder)
        self = codable.withUnsafeBytes { codable in
            Self.init(unsafeUninitializedCapacity: codable.count) { bytes, size in
                codable.enumerated().forEach { i, _ in
                    bytes[i] = codable[i]
                }
                size = codable.count
            }
        }
    }
}
