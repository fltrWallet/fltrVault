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
import XCTest

public extension Test {
    struct CodingTest<T: Codable> {
        public let encoded: String
        public let type: T.Type
    }

    static func encode<E: Codable>(_ value: E) -> CodingTest<E> {
        let encoder = JSONEncoder()
        var data: Data!
        XCTAssertNoThrow(data = try encoder.encode(value))

        return CodingTest(encoded: String(decoding: data, as: UTF8.self), type: E.self)
    }

    static func decode<C: Codable>(_ value: CodingTest<C>) -> C {
        let decoder = JSONDecoder()
        let data = value.encoded.data(using: .utf8)!
        var result: C!
        XCTAssertNoThrow(result = try decoder.decode(C.self, from: data))
        
        return result
    }
}
