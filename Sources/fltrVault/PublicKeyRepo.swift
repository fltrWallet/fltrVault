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
import FileRepo
import fltrTx
import fltrWAPI
import NIO

struct PublicKeyDTO: Identifiable {
    enum FirstByte: UInt8, Hashable {
        case xPoint = 1
        case even = 2
        case odd = 3
    }
    
    let id: Int
    let firstByte: FirstByte
    let bytes: Array<UInt8>
    
    fileprivate init(id: Int, firstByte: FirstByte, bytes: Array<UInt8>) {
        self.id = id
        self.firstByte = firstByte
        self.bytes = bytes
    }
    
    init(id: Int, point: DSA.PublicKey) {
        self.id = id
        
        var bytesSlice = point.serialize(format: .compressed)[...]
        guard let firstByte =  bytesSlice.popFirst().flatMap(FirstByte.init(rawValue:))
        else {
            preconditionFailure()
        }
        switch firstByte {
        case .even, .odd: break
        case .xPoint: preconditionFailure()
        }
        
        self.firstByte = firstByte
        self.bytes = Array(bytesSlice)
    }
    
    init(id: Int, point: X.PublicKey) {
        self.id = id
        
        self.firstByte = .xPoint
        self.bytes = point.serialize()
    }
    
    enum PointType: Hashable {
        case ecc(DSA.PublicKey)
        case x(X.PublicKey)
        
        var isECC: Bool {
            switch self {
            case .ecc:
                return true
            case .x:
                return false
            }
        }

        var isX: Bool {
            switch self {
            case .ecc:
                return false
            case .x:
                return true
            }
        }
        
        var ecc: DSA.PublicKey {
            switch self {
            case .ecc(let point): return point
            case .x: preconditionFailure()
            }
        }
        
        var x: X.PublicKey {
            switch self {
            case .ecc: preconditionFailure()
            case .x(let point): return point
            }
        }
    }
    
    var point: PointType {
        switch self.firstByte {
        case .xPoint:
            return .x(X.PublicKey(from: self.bytes)!)
        case .even, .odd:
            return .ecc(DSA.PublicKey(from: [ self.firstByte.rawValue ] + self.bytes)!)
        }
    }

    var ecc: DSA.PublicKey {
        self.point.ecc
    }
    
    var x: X.PublicKey {
        self.point.x
    }
    
    var isECC: Bool {
        self.point.isECC
    }
    
    var isX:Bool {
        self.point.isX
    }
}

extension Vault {
    final class PublicKeyRepo: FileRepo {
        let allocator: ByteBufferAllocator
        let eventLoop: EventLoop
        let nioFileHandle: NIOFileHandle
        let nonBlockingFileIO: NonBlockingFileIOClient
        let offset: Int = 0
        let recordSize: Int = 33
        
        init(nioFileHandle: NIOFileHandle,
             fileIO: NonBlockingFileIOClient,
             eventLoop: EventLoop) {
            self.nioFileHandle = nioFileHandle
            self.nonBlockingFileIO = fileIO
            self.allocator = GlobalFltrWalletSettings.NIOByteBufferAllocator
            self.eventLoop = eventLoop
        }
    }
}

extension Vault.PublicKeyRepo {
    func fileDecode(id: Int, buffer: inout ByteBuffer) throws -> PublicKeyDTO {
        var buffer = buffer
        guard let firstByte = buffer.readInteger(as: UInt8.self).flatMap(PublicKeyDTO.FirstByte.init(rawValue:)),
              let bytes: [UInt8] = buffer.readBytes(length: 32)
        else {
            preconditionFailure()
        }
        
        return PublicKeyDTO(id: id, firstByte: firstByte, bytes: bytes)
    }
    
    func fileEncode(_ row: PublicKeyDTO, buffer: inout ByteBuffer) throws {
        buffer.writeInteger(row.firstByte.rawValue)
        assert(row.bytes.count == 32)
        buffer.writeBytes(row.bytes)
    }
    
    func write(id: Int, row: DSA.PublicKey) -> Future<Void> {
        let dto = PublicKeyDTO(id: id, point: row)
        
        return self.write(dto)
    }
    
    func write(id: Int, row: X.PublicKey) -> Future<Void> {
        let dto = PublicKeyDTO(id: id, point: row)
        
        return self.write(dto)
        .flatMap(self.sync)
    }
    
    func endIndex() -> Future<Int> {
        self.range()
        .flatMapError {
            switch $0 {
            case File.Error.noDataFoundFileEmpty:
                return self.eventLoop.makeSucceededFuture((self.offset..<self.offset + 1))
            default:
                return self.eventLoop.makeFailedFuture($0)
            }
        }
        .map {
            $0.upperBound - 1
        }
    }
    
    func findIndex(for scriptPubKey: ScriptPubKey, event: StaticString = #function) -> Future<UInt32> {
        self.range()
        .map(\.upperBound)
        .flatMap {
            self.findIndex(for: scriptPubKey,
                           through: $0 - 1,
                           event: event)
        }
    }
    
    public struct ScriptNotFoundError: Swift.Error {}
    public struct InvalidSourceError: Swift.Error {}
    
    func findIndex(for scriptPubKey: ScriptPubKey,
                   through index: Int,
                   event: StaticString = #function) -> Future<UInt32> {
        let start = max(self.offset, index - GlobalFltrWalletSettings.PubKeyRepoFindBuffer)
        
        guard let source = HD.Source(rawValue: scriptPubKey.tag)
        else {
            return self.eventLoop.makeFailedFuture(InvalidSourceError())
        }

        guard index >= self.offset, start <= index
        else {
            return self.eventLoop.makeFailedFuture(ScriptNotFoundError())
        }

        return self.find(from: start, through: index)
        .map {
            return $0.map { publicKeyDto -> [UInt8] in
                source.scriptPubKey(from: publicKeyDto)
            }
        }
        .flatMap { scripts in
            if let index = scripts.firstIndex(where: { scriptPubKey.opcodes == $0 }) {
                return self.eventLoop.makeSucceededFuture(UInt32(start + index))
            } else {
                return self.findIndex(for: scriptPubKey, through: start - 1)
            }
        }
    }
}
