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
import fltrTx

public enum Vault {}

public extension Vault {
    @inlinable
    static func decode(address: String) -> AddressDecoder? {
        AddressDecoder(decoding: address,
                       network: GlobalFltrWalletSettings.Network)
    }
}

// MARK: Vault Errors
public extension Vault {
    struct OutpointNotFoundError: Swift.Error {}

    enum PaymentError: Swift.Error {
        case dustAmount
        case illegalAddress
        case illegalCostRate
        case internalError(TransactionBuilderError)
        case notEnoughFunds(txCost: UInt64)
        case transactionCostGreaterThanFunds
    }
}
