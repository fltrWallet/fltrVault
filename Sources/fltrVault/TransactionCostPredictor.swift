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

struct TransactionCostPredictor: TransactionBuilderProtocol {
    let costRate: Double
    var hasWitnesses: Bool {
        self.inputs.reduce(false) {
            $0 || $1.source.witness
        }
    }
    let inputs: [HD.Coin]
    let locktime: Tx.Locktime
    let version: Int32 = 2
    let recipient: Tx.Out
    var refund: Tx.Out? = nil

    var funds: UInt64 {
        self.inputs
        .map(\.amount)
        .reduce(0, +)
    }
    
    private func sequence() -> Tx.Sequence {
        self.locktime.enabled
            ? .locktimeOnly
            : .disable
    }

    var vin: [Tx.In] {
        let vin = self.inputs.map { coin -> Tx.In in
            switch coin.source {
            case .legacy0, .legacy0Change,
                    .legacy44, .legacy44Change:
                return Tx.In(outpoint: coin.outpoint,
                             scriptSig: Self.legacyScriptSig,
                             sequence: self.sequence(),
                             witness: { nil })
            case .legacySegwit, .legacySegwitChange:
                return Tx.In(outpoint: coin.outpoint,
                             scriptSig: Self.legacySegwitScriptSig,
                             sequence: self.sequence(),
                             witness: { Self.fakeWitness0 })
            case .segwit0, .segwit0Change,
                    .segwit, .segwitChange:
                return Tx.In(outpoint: coin.outpoint,
                             scriptSig: [],
                             sequence: self.sequence(),
                             witness: { Self.fakeWitness0 })
            case .taproot, .taprootChange:
                return Tx.In(outpoint: coin.outpoint,
                             scriptSig: [],
                             sequence: self.sequence(),
                             witness: { Self.fakeWitness1 })
            }
        }
        
        return vin
    }

    internal init(costRate: Double,
                  inputs: [HD.Coin],
                  recipient: Tx.Out,
                  height: Int?,
                  refund: Tx.Out? = nil) {
        if let height = height {
            self.locktime = .enable(UInt32(height))
        } else {
            self.locktime = .disable(0)
        }
        
        self.costRate = costRate
        self.inputs = inputs
        self.recipient = recipient
        self.refund = refund
    }
}

// MARK: Fake stubs
internal extension TransactionCostPredictor {
//    static var fakeRefundScriptPubKey: [UInt8] {
//        let fakeSegwitPubkey = ECC.Point.G
//        return PublicKeyHash(fakeSegwitPubkey).scriptPubKeyWPKH
//    } // using segwit refund address
    
    static var fakeRefundScriptPubKey: [UInt8] {
        X.PublicKey(Point.G).scriptPubKey
    }
    
    static var fakeWitness0: Tx.Witness {
        let firstField: [UInt8] = (0..<72).map { UInt8($0) }
        let secondField: [UInt8] = (0..<33).map { UInt8($0) }
        return .init(witnessField: [ firstField, secondField ])
    }

    static var fakeWitness1: Tx.Witness {
        return .init(witnessField: [ (0..<64).map(UInt8.init) ])
    }
    
    static var legacyScriptSig: [UInt8] {
        (0..<(74 + 34)).map { _ in UInt8(0) }
    }

    static var legacySegwitScriptSig: [UInt8] {
        (0..<23).map { UInt8($0) }
    }
}

internal extension TransactionCostPredictor {
    mutating func computeRefund() throws {
        guard self.refund == nil
        else { throw TransactionBuilderError.refundOutputAlreadySet }
        
        let costWithoutRefund = self.recipient.value + self.transactionCost
        
        guard self.funds >= costWithoutRefund
        else { throw TransactionBuilderError.insufficientFunds }
        
        if self.funds > costWithoutRefund + GlobalFltrWalletSettings.DustAmount {
            self.refund = Tx.Out(value: 1,
                                 scriptPubKey: Self.fakeRefundScriptPubKey)
            let costWithRefund = self.recipient.value + self.transactionCost
            
            guard self.funds > costWithRefund + GlobalFltrWalletSettings.DustAmount
            else {
                self.refund = nil
                return
            }
            
            self.refund = Tx.Out(value: self.funds - costWithRefund,
                                 scriptPubKey: Self.fakeRefundScriptPubKey)
        }
    }
}

// MARK: TransactionCostPredictor factory
internal extension TransactionCostPredictor {
    static func buildTx(amount: UInt64,
                        scriptPubKey destination: [UInt8],
                        costRate: Double,
                        coins: Tally,
                        height: Int?) -> Self? {
        let recipient: Tx.Out = .init(value: amount, scriptPubKey: destination)
        
        var result = self.init(costRate: costRate,
                               inputs: coins,
                               recipient: recipient,
                               height: height)
        do {
            try result.computeRefund()
        } catch {
            return nil
        }
        
        return result
    }
}

// MARK: Sign and Serialize
internal extension TransactionCostPredictor {
    func signAndSerialize(using privateKey: HD.FullNode,
                          eventLoop: EventLoop,
                          change: () -> EventLoopFuture<(index: UInt32, script: [UInt8])> )
    -> EventLoopFuture<(tx: Tx.AnyTransaction,
                        change: (index: UInt32, txOut: Tx.Out)?)> {
        func verifyTransaction(_ tx: TransactionSignatureBuilder, prevouts: [Tx.Out]) -> Bool {
            return tx.inputs
            .enumerated()
            .map { index, _ in
                tx.verifySignature(index: index, prevouts: prevouts)
            }
            .reduce(true) { $0 && $1 }
        }
        
        let promise = eventLoop.makePromise(of: (tx: Tx.AnyTransaction, change: (index: UInt32, txOut: Tx.Out)?).self)
        
        if self.hasRefund {
            change().whenComplete {
                switch $0 {
                case .success(let (index, script)):
                    do {
                        var signatureBuilder = TransactionSignatureBuilder(costPredictor: self,
                                                                           privateKey: privateKey,
                                                                           with: script)
                        var prevouts = signatureBuilder.signInputs()
                        
                        func recursiveRebalanceRefund() throws {
                            let outcome = try signatureBuilder.rebalanceRefund()

                            guard outcome.isChanged // base case
                            else { return }

                            prevouts = signatureBuilder.signInputs()
                            
                            try recursiveRebalanceRefund() // recursion
                        }

                        try recursiveRebalanceRefund()
                        
                        precondition(verifyTransaction(signatureBuilder, prevouts: prevouts))
  
                        promise.succeed((tx: Tx.AnyTransaction(signatureBuilder)!,
                                         change: (index, signatureBuilder.refund!)))
                    } catch {
                        promise.fail(error)
                    }
                case .failure(let error):
                    promise.fail(error)
                }
            }
        } else {
            var signatureBuilder = TransactionSignatureBuilder(costPredictor: self,
                                                               privateKey: privateKey)
            let prevouts = signatureBuilder.signInputs()
            precondition(verifyTransaction(signatureBuilder, prevouts: prevouts))
            promise.succeed((tx: Tx.AnyTransaction(signatureBuilder)!,
                             change: nil))
        }
        
        return promise.futureResult
    }
}


extension TransactionCostPredictor: CustomDebugStringConvertible {
    var debugDescription: String {
        var result: [String] = []
        result.append("inputs:[\(self.inputs)]\n")
        result.append("recipient:[\(self.recipient)]")
        result.append("refund:[\(self.hasRefund ? String(describing: self.refund!) : "❌")]\n")
        result.append("costRate:[\(self.costRate)]")
        result.append("funds:[\(self.funds)]")

        return result.joined(separator: " ")
    }
}
