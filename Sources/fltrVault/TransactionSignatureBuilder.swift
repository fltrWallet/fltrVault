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
import HaByLo
import NIO

struct TransactionSignatureBuilder {
    let costPredictor: TransactionCostPredictor
    
    var privateKey: HD.FullNode
    var refund: Tx.Out?
    var vin: [Tx.In]
    
    init(costPredictor: TransactionCostPredictor,
         privateKey: HD.FullNode,
         with refundScript: [UInt8]) {
        self.costPredictor = costPredictor
        guard let predictorRefund = costPredictor.refund
        else { preconditionFailure() }
        self.refund = Tx.Out(value: predictorRefund.value,
                             scriptPubKey: refundScript)
        self.vin = costPredictor.vin
        self.privateKey = privateKey
    }
    
    init(costPredictor: TransactionCostPredictor,
         privateKey: HD.FullNode) {
        self.costPredictor = costPredictor
        precondition(!costPredictor.hasRefund)
        self.refund = nil
        self.vin = costPredictor.vin
        self.privateKey = privateKey
    }
}

extension TransactionSignatureBuilder: TransactionBuilderProtocol {
    var costRate: Double {
        self.costPredictor.costRate
    }
    var funds: UInt64 {
        self.costPredictor.funds
    }
    var hasWitnesses: Bool {
        self.costPredictor.hasWitnesses
    }
    var inputs: [HD.Coin] {
        self.costPredictor.inputs
    }
    var locktime: Tx.Locktime {
        self.costPredictor.locktime
    }
    var recipient: Tx.Out {
        self.costPredictor.recipient
    }
    var version: Int32 {
        self.costPredictor.version
    }
}

internal extension TransactionSignatureBuilder {
    enum RefundEnum {
        case modified
        case noChange
        
        var isChanged: Bool {
            switch self {
            case .modified: return true
            case .noChange: return false
            }
        }
        
        func whenChanged(do closure: () -> Void) {
            self.isChanged ? closure() : ()
        }
    }
    
    @discardableResult
    mutating func rebalanceRefund() throws -> RefundEnum {
        guard let oldRefund = self.refund
        else {
            throw TransactionBuilderError.noRefund
        }

        let oldChange = oldRefund.value
        let change = self.funds - (self.transactionCost + self.recipient.value)
        self.refund = Tx.Out(value: change,
                             scriptPubKey: oldRefund.scriptPubKey)
        
        return oldChange == change ? .noChange : .modified
    }

    static func signSegwit<Transaction: TransactionProtocol>(tx: Transaction,
                                                             sign index: Int,
                                                             outpoint: Tx.Outpoint,
                                                             amount: UInt64,
                                                             sequence: Tx.Sequence,
                                                             keyPair: DSA.SecretKey,
                                                             publicKeyHash: PublicKeyHash,
                                                             scriptSig: [UInt8])
    -> Tx.In {
        let signatureType = Tx.Signature.SigHashType.ALL
        let sigHash = Tx.Signature.sigHash(tx: tx,
                                           signatureType: signatureType,
                                           inputIndex: index,
                                           amount: amount,
                                           outpointPublicKeyHash: publicKeyHash)
        let eccSignature = keyPair.sign(message: Array(sigHash.littleEndian))
        let witnessFirstField = eccSignature.serializeDer() + [ signatureType.rawValue ]
        let witnessSecondField = keyPair.pubkey().serialize()
        let witness: Tx.Witness = .init(witnessField: [ witnessFirstField, witnessSecondField ])
        
        return Tx.In(outpoint: outpoint,
                     scriptSig: scriptSig,
                     sequence: sequence,
                     witness: { witness })
    }
    
    @discardableResult
    mutating func signInputs() -> [Tx.Out] {
        let keys = self.keysScriptSig()
        precondition(keys.count == self.inputs.count)
        
        let prevouts: [Tx.Out] = zip(self.inputs.map(\.amount),
                                     keys.map(\.scriptPubKey))
            .map(Tx.Out.init)
        
        self.vin = self.inputs.enumerated().map { index, input in
            switch (input.receivedState, input.spentState) {
            case (.confirmed, .unspent):
                break
            case (.confirmed, .pending),
                 (.confirmed, .spent),
                 (.unconfirmed, _),
                 (.rollback, _):
                preconditionFailure()
            }
            
            let key = keys[index]
            switch key {
            case .legacy(let keyPair, let publicKeyHash):
                let signatureType = Tx.Signature.SigHashType.ALL
                let sigHash = Tx.Signature.sigHash(tx: self,
                                                   signatureType: signatureType,
                                                   inputIndex: index,
                                                   amount: input.amount,
                                                   outpointPublicKeyHash: publicKeyHash)
                let secretKey = DSA.SecretKey(keyPair)
                let eccSignature = secretKey.sign(message: Array(sigHash.littleEndian))
                let signatureBytes = eccSignature.serializeDer() + [ signatureType.rawValue ]
                let pubKeyBytes = secretKey.pubkey().serialize()
                let scriptSig: [UInt8] = Array(signatureBytes.count.variableLengthCode) + signatureBytes
                + Array(pubKeyBytes.count.variableLengthCode) + pubKeyBytes
                
                return Tx.In(outpoint: self.vin[index].outpoint,
                             scriptSig: scriptSig,
                             sequence: self.vin[index].sequence,
                             witness: { nil })
            case .legacySegwit(let keyPair, let publicKeyHash):
                return Self.signSegwit(tx: self,
                                       sign: index,
                                       outpoint: self.vin[index].outpoint,
                                       amount: input.amount,
                                       sequence: self.vin[index].sequence,
                                       keyPair: DSA.SecretKey(keyPair),
                                       publicKeyHash: publicKeyHash,
                                       scriptSig: [ 0x16 ] + publicKeyHash.scriptPubKeyWPKH)
            case .segwit(let keyPair, let publicKeyHash):
                return Self.signSegwit(tx: self,
                                       sign: index,
                                       outpoint: self.vin[index].outpoint,
                                       amount: input.amount,
                                       sequence: self.vin[index].sequence,
                                       keyPair: DSA.SecretKey(keyPair),
                                       publicKeyHash: publicKeyHash,
                                       scriptSig: [])
            case .taproot(let tweaked):
                let signatureType = Tx.Signature.SigHashType.DEFAULT
                let sigHash = Tx.TapRoot.sigHash(tx: self,
                                                 inputIndex: index,
                                                 type: signatureType,
                                                 prevouts: prevouts)
                let signature = tweaked.sign(message: Array(sigHash.littleEndian))
                let witness: Tx.Witness = .init(witnessField: [signature.serialize()])
                
                return Tx.In(outpoint: self.vin[index].outpoint,
                             scriptSig: [],
                             sequence: self.vin[index].sequence,
                             witness: { witness })
            }
        }
        
        return prevouts
    }
    
    enum KeyPair {
        case legacy(Scalar, PublicKeyHash)
        case legacySegwit(Scalar, PublicKeyHash)
        case segwit(Scalar, PublicKeyHash)
        case taproot(X.SecretKey)
        
        var scriptPubKey: [UInt8] {
            switch self {
            case .legacy(_, let publicKeyHash):
                return publicKeyHash.scriptPubKeyLegacyPKH
            case .legacySegwit(_, let publicKeyHash):
                return publicKeyHash.scriptPubKeyLegacyWPKH
            case .segwit(_, let publicKeyHash):
                return publicKeyHash.scriptPubKeyWPKH
            case .taproot(let keyPair):
                return keyPair.pubkey().xPoint.scriptPubKey
            }
        }
    }
    
    mutating func keysScriptSig() -> [Self.KeyPair] {
        var legacy0CommonNode: HD.FullNode!
        var legacy44CommonNode: HD.FullNode!
        var legacySegwitCommonNode: HD.FullNode!
        var segwitCommonNode: HD.FullNode!
        var taprootCommonNode: HD.FullNode!
        
        func cacheLegacy0CommonNode() {
            if legacy0CommonNode == nil {
                legacy0CommonNode = try! self.privateKey.makeChildNode(
                    for: GlobalFltrWalletSettings.BIP39Legacy0AccountPath
                )
                .last!
            }
        }
        
        func cacheLegacy44CommonNode() {
            if legacy44CommonNode == nil {
                legacy44CommonNode = try! self.privateKey.makeChildNode(
                    for: GlobalFltrWalletSettings.BIP39Legacy44AccountPath
                )
                .last!
            }
        }
        
        func cacheLegacySegwitCommonNode() {
            if legacySegwitCommonNode == nil {
                legacySegwitCommonNode = try! self.privateKey.makeChildNode(
                    for: GlobalFltrWalletSettings.BIP39LegacySegwitAccountPath
                )
                .last!
            }
        }

        func cacheSegwitCommonNode() {
            if segwitCommonNode == nil {
                segwitCommonNode = try! self.privateKey.makeChildNode(
                    for: GlobalFltrWalletSettings.BIP39SegwitAccountPath
                )
                .last!
            }
        }
        
        func cacheTaprootCommonNode() {
            if taprootCommonNode == nil {
                taprootCommonNode = try! self.privateKey.makeChildNode(
                    for: GlobalFltrWalletSettings.BIP39TaprootAccountPath
                )
                .last!
            }
        }

        func base(for key: inout HD.FullNode) -> HD.FullNode {
            try! key.makeChildNode(relative: .normal(0)).last!
        }
        
        func change(for key: inout HD.FullNode) -> HD.FullNode {
            try! key.makeChildNode(relative: .normal(1)).last!
        }
        
        func makeKeyPairAndPublicKeyHash(node: inout HD.FullNode, index: Int) -> (Scalar, PublicKeyHash) {
            let privateKey = node.childKey(index: index).key.private
            let publicKeyHash = PublicKeyHash(DSA.PublicKey(Point(privateKey)))
            
            return (privateKey, publicKeyHash)
        }
        
        return self.inputs.map { coin in
            var node: HD.FullNode = {
                switch coin.source {
                case .legacy0:
                    cacheLegacy0CommonNode()
                    return base(for: &legacy0CommonNode)
                case .legacy0Change:
                    cacheLegacy0CommonNode()
                    return change(for: &legacy0CommonNode)
                case .legacy44:
                    cacheLegacy44CommonNode()
                    return base(for: &legacy44CommonNode)
                case .legacy44Change:
                    cacheLegacy44CommonNode()
                    return change(for: &legacy44CommonNode)
                case .legacySegwit:
                    cacheLegacySegwitCommonNode()
                    return base(for: &legacySegwitCommonNode)
                case .legacySegwitChange:
                    cacheLegacySegwitCommonNode()
                    return change(for: &legacySegwitCommonNode)
                case .segwit0:
                    cacheLegacy0CommonNode()
                    return base(for: &legacy0CommonNode)
                case .segwit0Change:
                    cacheLegacy0CommonNode()
                    return change(for: &legacy0CommonNode)
                case .segwit:
                    cacheSegwitCommonNode()
                    return base(for: &segwitCommonNode)
                case .segwitChange:
                    cacheSegwitCommonNode()
                    return change(for: &segwitCommonNode)
                case .taproot:
                    cacheTaprootCommonNode()
                    return base(for: &taprootCommonNode)
                case .taprootChange:
                    cacheTaprootCommonNode()
                    return change(for: &taprootCommonNode)
                }
            }()

            switch coin.source {
            case .legacy0, .legacy0Change, .legacy44, .legacy44Change:
                let (keyPair, publicKeyHash) = makeKeyPairAndPublicKeyHash(node: &node,
                                                                           index: Int(coin.path))
                return .legacy(keyPair, publicKeyHash)
            case .legacySegwit, .legacySegwitChange:
                let (keyPair, publicKeyHash) = makeKeyPairAndPublicKeyHash(node: &node,
                                                                           index: Int(coin.path))
                return .legacySegwit(keyPair, publicKeyHash)
            case .segwit, .segwitChange, .segwit0, .segwit0Change:
                let (keyPair, publicKeyHash) = makeKeyPairAndPublicKeyHash(node: &node,
                                                                           index: Int(coin.path))
                return .segwit(keyPair, publicKeyHash)
            case .taproot, .taprootChange:
                let tweaked = node.tweak(for: Int(coin.path))
                return .taproot(tweaked)
            }
        }
    }
}
