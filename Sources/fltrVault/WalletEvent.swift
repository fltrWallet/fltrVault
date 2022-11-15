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

public enum WalletEvent: Hashable {
    case scriptPubKey(ScriptPubKey)
    case tally(TallyEvent)

    var scriptPubKey: ScriptPubKey? {
        switch self {
        case .scriptPubKey(let value): return value
        case .tally: return nil
        }
    }
}

public enum TallyEvent: Hashable {
    case receiveConfirmed(UInt64)
    case receivePromoted(UInt64)
    case receiveUnconfirmed(UInt64)
    case spentConfirmed(UInt64)
    case spentPromoted(UInt64)
    case spentUnconfirmed(UInt64)
    
    case rollback
}
