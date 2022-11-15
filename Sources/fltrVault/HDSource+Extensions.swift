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

// MARK: FileName
public extension HD.Source {
    var fileName: String? {
        func fileName() -> String {
            "PublicKey - \(self).dat"
        }
        
        if Self.uniqueCases.contains(self) {
            return fileName()
        } else {
            return nil
        }
    }
}

// MARK: Address
extension HD.Source {
    enum PublicKey: Hashable, Identifiable {
        case ecc(DSA.PublicKey)
        case x(X.PublicKey)
        
        init(_ dto: PublicKeyDTO) {
            if dto.isECC {
                self = .ecc(dto.ecc)
            } else {
                self = .x(dto.x)
            }
        }
        
        public var id: [UInt8] {
            switch self {
            case .ecc(let point):
                return point.serialize()
            case .x(let xPoint):
                return xPoint.serialize()
            }
        }
    }

    func address(from pubKey: PublicKey) -> String? {
        switch (self, pubKey) {
        case (.legacy0, .ecc(let point)), (.legacy0Change, .ecc(let point)),
            (.legacy44, .ecc(let point)), (.legacy44Change, .ecc(let point)):
            return PublicKeyHash(point).addressLegacyPKH(GlobalFltrWalletSettings.Network.legacyAddressPrefix)
        case (.legacySegwit, .ecc(let point)), (.legacySegwitChange, .ecc(let point)):
            return PublicKeyHash(point).addressLegacyWPKH(GlobalFltrWalletSettings.Network.legacyAddressPrefix)
        case (.segwit0, .ecc(let point)), (.segwit0Change, .ecc(let point)),
            (.segwit, .ecc(let point)), (.segwitChange, .ecc(let point)):
            return PublicKeyHash(point).addressSegwit(GlobalFltrWalletSettings.Network.bech32HumanReadablePart)
        case (.taproot, .x(let point)), (.taprootChange, .x(let point)):
            return point.addressTaproot(GlobalFltrWalletSettings.Network.bech32HumanReadablePart)
        case (.legacy0, _), (.legacy0Change, _),
            (.legacy44, _), (.legacy44Change, _),
            (.legacySegwitChange, _), (.segwit0Change, _), (.segwitChange, _), (.taprootChange, _),
            (.legacySegwit, .x),
            (.segwit0, .x),
            (.segwit, .x),
            (.taproot, .ecc):
            return nil
        }
    }
    
    func address(from dto: PublicKeyDTO) -> String {
        let publicKey: PublicKey = .init(dto)
        
        return self.address(from: publicKey)!
    }
}

extension HD.Source {
    func repo(from all: Vault.AllPublicKeyRepos) -> Vault.SourcePublicKeyRepo {
        switch self {
        case .legacy0:
            return all.legacy0Repo
        case .legacy0Change:
            return all.legacy0ChangeRepo
        case .legacy44:
            return all.legacy44Repo
        case .legacy44Change:
            return all.legacy44ChangeRepo
        case .legacySegwit:
            return all.legacySegwitRepo
        case .legacySegwitChange:
            return all.legacySegwitChangeRepo
        case .segwit0:
            return all.segwit0Repo
        case .segwit0Change:
            return all.segwit0ChangeRepo
        case .segwit:
            return all.segwitRepo
        case .segwitChange:
            return all.segwitChangeRepo
        case .taproot:
            return all.taprootRepo
        case .taprootChange:
            return all.taprootChangeRepo
        }
    }
}

extension HD.Source {
    @inlinable
    public var hdPath: HD.Path {
        switch self {
        case .legacy0, .segwit0:
            return GlobalFltrWalletSettings.BIP39Legacy0AccountPath + .normal(0)
        case .legacy0Change, .segwit0Change:
            return GlobalFltrWalletSettings.BIP39Legacy0AccountPath + .normal(1)
        case .legacy44:
            return GlobalFltrWalletSettings.BIP39Legacy44AccountPath + .normal(0)
        case .legacy44Change:
            return GlobalFltrWalletSettings.BIP39Legacy44AccountPath + .normal(1)
        case .legacySegwit:
            return GlobalFltrWalletSettings.BIP39LegacySegwitAccountPath + .normal(0)
        case .legacySegwitChange:
            return GlobalFltrWalletSettings.BIP39LegacySegwitAccountPath + .normal(1)
        case .segwit:
            return GlobalFltrWalletSettings.BIP39SegwitAccountPath + .normal(0)
        case .segwitChange:
            return GlobalFltrWalletSettings.BIP39SegwitAccountPath + .normal(1)
        case .taproot:
            return GlobalFltrWalletSettings.BIP39TaprootAccountPath + .normal(0)
        case .taprootChange:
            return GlobalFltrWalletSettings.BIP39TaprootAccountPath + .normal(1)
        }
    }

    func fullNode(from root: inout HD.FullNode) throws -> HD.FullNode {
        try root.makeChildNode(for: self.hdPath).last!
    }
    
    func node(from properties: Vault.Properties) -> EventLoopFuture<Vault.Properties.WalletPublicKeyNodes> {
        properties.loadPublicKey(source: self)
    }
}

// MARK: ScriptPubKey
extension HD.Source {
    private func _legacyScript(_ ecc: DSA.PublicKey) -> [UInt8] {
        let pkh = PublicKeyHash(ecc)
        return pkh.scriptPubKeyLegacyPKH
    }

    private func _legacySegwitScript(_ ecc: DSA.PublicKey) -> [UInt8] {
        let pkh = PublicKeyHash(ecc)
        return pkh.scriptPubKeyLegacyWPKH
    }
    
    private func _segwitScript(_ ecc: DSA.PublicKey) -> [UInt8] {
        let pkh = PublicKeyHash(ecc)
        return pkh.scriptPubKeyWPKH
    }
    
    func scriptPubKey(from dto: PublicKeyDTO) -> [UInt8] {
        switch (self, dto.isECC) {
        case (.legacy0, true), (.legacy0Change, true),
            (.legacy44, true), (.legacy44Change, true):
            return self._legacyScript(dto.ecc)
        case (.legacySegwit, true), (.legacySegwitChange, true):
            return _legacySegwitScript(dto.ecc)
        case (.segwit0, true), (.segwit0Change, true),
            (.segwit, true), (.segwitChange, true):
            return self._segwitScript(dto.ecc)
        case (.taproot, false), (.taprootChange, false):
            return dto.x.scriptPubKey
        case (.legacy0, false), (.legacy0Change, false),
            (.legacy44, false), (.legacy44Change, false),
            (.legacySegwit, false), (.legacySegwitChange, false),
            (.segwit0, false), (.segwit0Change, false),
            (.segwit, false), (.segwitChange, false),
            (.taproot, true), (.taprootChange, true):
            preconditionFailure()
        }
    }
}
