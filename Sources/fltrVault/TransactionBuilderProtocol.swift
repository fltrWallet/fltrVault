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
import Foundation

internal protocol TransactionBuilderProtocol: TransactionProtocol {
    var costRate: Double { get }
    var funds: UInt64 { get }
    var recipient: Tx.Out { get }
    var refund: Tx.Out? { get set }
}

internal extension TransactionBuilderProtocol {
    var vout: [Tx.Out] {
        self.refund
        .map { refund in
            [ self.recipient, refund, ]
        }
        ?? [ self.recipient ]
    }
    
    var transactionCost: UInt64 {
        UInt64(
            round(self.vBytes * self.costRate)
        )
    }
    
    var hasRefund: Bool {
        self.refund != nil
    }
    
    var isInsufficient: Bool {
        self.funds < self.transactionCost + self.recipient.value
    }
}

public enum TransactionBuilderError: Swift.Error {
    case insufficientFunds
    case inputsUnsigned
    case noRefund
    case refundOutputAlreadySet
}
