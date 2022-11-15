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
import NIO

public struct History {
    @usableFromInline
    let value: [InOut]
    
    @inlinable
    public func callAsFunction() -> [InOut] {
        self.value
    }
    
    @inlinable
    public init(_ value: [InOut]) {
        self.value = value
    }
    
    @inlinable
    public var pending: [InOut] {
        self.value.filter(\.record.pending)
    }
    
    @inlinable
    public var confirmed: [InOut] {
        self.value.filter { !$0.record.pending }
    }
    
    @inlinable
    public func received(pending: Bool) -> [InOut] {
        self.value.filter {
            switch $0 {
            case .incoming(let record):
                return pending == record.pending
            case .outgoing:
                return false
            }
        }
    }
    
    @inlinable
    public func sent(pending: Bool) -> [InOut] {
        self.value.filter {
            switch $0 {
            case .outgoing(let record):
                return pending == record.pending
            case .incoming:
                return false
            }
        }
    }
}

public extension History {
    struct Record: Hashable {
        public let pending: Bool
        public let txId: Tx.TxId
        public let address: String?
        public let amount: UInt64
        public let height: Int

        public init(pending: Bool,
                    txId: Tx.TxId,
                    address: String?,
                    amount: UInt64,
                    height: Int) {
            self.pending = pending
            self.txId = txId
            self.address = address
            self.amount = amount
            self.height = height
        }
    }
    
    enum InOut: Hashable, Identifiable {
        case incoming(Record)
        case outgoing(Record)
        
        @inlinable
        public var id: Self { self }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .incoming(let record):
                hasher.combine(0)
                hasher.combine(record)
            case .outgoing(let record):
                hasher.combine(1)
                hasher.combine(record)
            }
        }
        
        @inlinable
        public var incoming: Bool {
            switch self {
            case .incoming: return true
            case .outgoing: return false
            }
        }
        
        @inlinable
        public var outgoing: Bool { !self.incoming }
       
        @inlinable
        public var record: Record {
            switch self {
            case .incoming(let record),
                    .outgoing(let record):
                return record
            }
        }
    }
}

extension History {
    static func from(coins: [HD.Coin],
                     nodes: Vault.Properties.AllPublicKeyNodes) -> History {
        let pendingIn: [(Int, HD.Coin)] = coins.compactMap {
            switch ($0.receivedState, $0.spentState) {
            case (.unconfirmed(let height), .unspent): return (height, $0)
            case (.unconfirmed, .spent),
                (.unconfirmed, .pending),
                (.confirmed, _),
                (.rollback, _): return nil
            }
        }

        let pendingOut: [(HD.Coin, HD.Coin.Spent)] = coins.compactMap {
            switch ($0.receivedState, $0.spentState) {
            case (.confirmed, .pending(let spent)): return ($0, spent)
            case (.unconfirmed, .pending),
                (.rollback, .pending),
                (_, .spent),
                (_, .unspent): return nil
            }
        }
        
        let received: [(Int, HD.Coin)] = coins.compactMap {
            switch ($0.receivedState, $0.spentState) {
            case (.confirmed(let height), .unspent),
                (.confirmed(let height), .pending),
                (.confirmed(let height), .spent): return (height, $0)
            case (.unconfirmed, _),
                (.rollback, _): return nil
            }
        }
        
        let spent: [(HD.Coin, HD.Coin.Spent)] = coins.compactMap {
            switch $0.spentState {
            case .spent(let spent): return ($0, spent)
            case .pending, .unspent: return nil
            }
        }

        func address(received coin: HD.Coin) -> String? {
            let path = coin.path
            var node = nodes[coin.source]!
            
            switch coin.source {
            case .legacy0, .legacy44,
                    .legacySegwit,
                    .segwit0,
                    .segwit:
                let point = node.childKey(index: Int(path)).key.public
                return coin.source.address(from: .ecc(DSA.PublicKey(point)))
            case .taproot:
                let xPubkey = node.tweak(for: Int(path))
                return coin.source.address(from: .x(xPubkey))
            case .legacy0Change, .legacy44Change,
                    .legacySegwitChange,
                    .segwit0Change, .segwitChange,
                    .taprootChange:
                return nil
            }
        }
        
        func getAddress(spent: [UInt8]) -> String? {
            guard let script = try? spent.script.get()
            else {
                return nil
            }
            
            return script.address(GlobalFltrWalletSettings.Network).value
        }
        
        func groupedIncoming(data: [(Int, HD.Coin)]) -> [Tx.TxId : (height: Int,
                                                             address: String?,
                                                             amounts: [UInt64])] {
            data.reduce(into: [Tx.TxId : (height: Int, address: String?, amounts: [UInt64])]()) { result, next in
                guard let nextAddress = address(received: next.1)
                else { return }
                
                let txId = next.1.outpoint.transactionId
                let height: Int
                let address: String?
                var amounts: [UInt64]
                if let current = result[txId] {
                    assert(current.height == next.0)
                    height = current.height
                    assert(current.address == nextAddress)
                    address = current.address
                    amounts = current.amounts
                } else {
                    height = next.0
                    address = nextAddress
                    amounts = .init()
                }
                
                amounts.append(next.1.amount)
                result[txId] = (height, address, amounts)
            }
        }
        
        func groupedSpend(data: [(HD.Coin, HD.Coin.Spent)]) -> [Tx.TxId: (height: Int,
                                                                   address: String?,
                                                                   amount: UInt64)] {
            data.reduce(into: [Tx.TxId: (height: Int, address: String?, amount: UInt64)]()) { result, next in
                let txId = Tx.AnyIdentifiableTransaction(next.1.tx).txId
                let nextAmount = next.1.tx.vout.enumerated().reduce(UInt64(0)) { amt, n in
                    let index = UInt8(truncatingIfNeeded: n.0)
                    
                    let stepAmount = next.1.changeOuts.contains(index) ? 0 : UInt64(n.1.value)
                    return amt + stepAmount
                }
                let height: Int
                let address: String?
                if let current = result[txId] {
                    assert(current.height == next.1.height)
                    height = current.height
                    address = current.address ?? getAddress(spent: next.1.tx.vout[0].scriptPubKey)
                    assert(current.amount == nextAmount)
                } else {
                    height = next.1.height
                    address = getAddress(spent: next.1.tx.vout[0].scriptPubKey)
                }
                
                result[txId] = (height, address, nextAmount)
            }
        }
        
        let pendingInData = groupedIncoming(data: pendingIn)
        let receivedData = groupedIncoming(data: received)
        let pendingOutData = groupedSpend(data: pendingOut)
        let spentData = groupedSpend(data: spent)
        
        let pendingInRecords: [Record] = pendingInData.compactMap { key, value in
            Record(pending: true,
                   txId: key,
                   address: value.address,
                   amount: value.amounts.reduce(0, +),
                   height: value.height)
        }
        
        let receiveRecords: [Record] = receivedData.compactMap { key, value in
            Record(pending: false,
                   txId: key,
                   address: value.address,
                   amount: value.amounts.reduce(0, +),
                   height: value.height)
        }

        let pendingOutRecords: [Record] = pendingOutData.map { key, value in
            Record(pending: true,
                   txId: key,
                   address: value.address,
                   amount: value.amount,
                   height: value.height)
        }
        let spentRecords: [Record] = spentData.map { key, value in
            Record(pending: false,
                   txId: key,
                   address: value.address,
                   amount: value.amount,
                   height: value.height)
        }
        
        let mapped = pendingInRecords.map(InOut.incoming) + receiveRecords.map(InOut.incoming)
        + pendingOutRecords.map(InOut.outgoing) + spentRecords.map(InOut.outgoing)
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.record.height == rhs.record.height {
                if lhs.outgoing && rhs.outgoing {
                    return lhs.record.txId < rhs.record.txId
                } else if lhs.outgoing {
                    return true
                } else {
                    return lhs.record.txId < rhs.record.txId
                }
            } else {
                return lhs.record.height < rhs.record.height
            }
        }
        
        return .init(sorted)
    }
}
