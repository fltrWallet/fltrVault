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

public extension HD.Seed {
    static var testing: HD.Seed = {
        Self.seed(size: 32)
    }()

    static func seed(size: Int) -> HD.Seed {
        .init(unsafeUninitializedCapacity: size) { bytes, setSize in
            (0..<size).forEach {
                bytes[$0] = UInt8(truncatingIfNeeded: $0)
            }
            setSize = size
        }
    }
    
    static func seed(from bytes: [UInt8]) -> HD.Seed {
        bytes.withUnsafeBytes { bytes in
            HD.Seed(unsafeUninitializedCapacity: bytes.count) { seed, size in
                (0..<bytes.count).forEach {
                    seed[$0] = bytes[$0]
                }
                size = bytes.count
            }
        }
    }
}
