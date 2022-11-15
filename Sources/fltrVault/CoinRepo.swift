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
import FileRepo
import fltrTx
import HaByLo
import NIO

extension Vault {
    final class CoinRepo: FileRepo {
        typealias Model = HD.Coin
        let allocator: ByteBufferAllocator = .init()
        let nioFileHandle: NIOFileHandle

        let nonBlockingFileIO: NonBlockingFileIOClient
        let eventLoop: EventLoop
        let recordSize: Int = 4096
        let constantOverhead = 63
        @usableFromInline
        var txBufferSize: Int { self.recordSize - self.constantOverhead }
        let offset: Int = 0
        
        init(fileHandle: NIOFileHandle,
             nonBlockingFileIO: NonBlockingFileIOClient,
             eventLoop: EventLoop) {
            self.nioFileHandle = fileHandle
            self.nonBlockingFileIO = nonBlockingFileIO
            self.eventLoop = eventLoop
        }
    }
}

extension Vault.CoinRepo {
    func fileDecode(id: Int, buffer: inout ByteBuffer) throws -> HD.Coin {
        guard let transactionId: [UInt8] = buffer.readBytes(length: 32),
              let index: UInt32 = buffer.readInteger(),
              let amount: UInt64 = buffer.readInteger(),
              let sourceRaw = buffer.readInteger(as: UInt8.self),
              let source = HD.Source.init(rawValue: sourceRaw),
              let path: UInt32 = buffer.readInteger(),
              let receivedType: UInt8 = buffer.readInteger(),
              let receivedTypeHeight = buffer.readInteger(as: UInt32.self).map(Int.init),
              let spentType = buffer.readInteger(as: UInt8.self),
              let spentTypeHeight = buffer.readInteger(as: UInt32.self).map(Int.init),
              let change1 = buffer.readInteger(as: UInt8.self),
              let change2 = buffer.readInteger(as: UInt8.self),
              let change3 = buffer.readInteger(as: UInt8.self),
              let change4 = buffer.readInteger(as: UInt8.self),
              var spentTxBuffer = buffer.readSlice(length: self.txBufferSize)
        else {
            preconditionFailure()
        }
        
        let receivedState: HD.Coin.ReceivedState = {
            switch receivedType {
            case 0:
                return .unconfirmed(receivedTypeHeight)
            case 1:
                return .confirmed(receivedTypeHeight)
            case 2:
                return .rollback(receivedTypeHeight)
            default:
                preconditionFailure()
            }
        }()
        
        let spentState: HD.Coin.SpentState = {
            precondition(spentType <= 2)
            guard spentType > 0
            else { return .unspent }
            
            guard let tx = Tx.AnyTransaction(fromBuffer: &spentTxBuffer)
            else {
                preconditionFailure()
            }
            
            func remap(change: UInt8) -> UInt8? {
                guard change < .max
                else { return nil }
                
                return change
            }
            
            let changeOuts = [ change1, change2, change3, change4 ].compactMap(remap(change:))

            let spent: HD.Coin.Spent = .init(height: spentTypeHeight,
                                             changeOuts: changeOuts,
                                             tx: tx)
            if spentType == 1 {
                return .pending(spent)
            } else {
                return .spent(spent)
            }
        }()
        
        return HD.Coin(outpoint: Tx.Outpoint(transactionId: .little(transactionId), index: index),
                       amount: amount,
                       receivedState: receivedState,
                       spentState: spentState,
                       source: source,
                       path: path)
        .rank(id: id)
    }
    
    func fileEncode(_ row: HD.Coin, buffer: inout ByteBuffer) throws {
        buffer.writeBytes(row.outpoint.transactionId.littleEndian)
        buffer.writeInteger(row.outpoint.index)
        buffer.writeInteger(row.amount)
        buffer.writeInteger(row.source.rawValue)
        buffer.writeInteger(row.path)
        let (receivedType, receivedState): (UInt8, UInt32) = {
            switch row.receivedState {
            case .unconfirmed(let h):
                return (0, UInt32(h))
            case .confirmed(let h):
                return (1, UInt32(h))
            case .rollback(let h):
                return (2, UInt32(h))
            }
        }()
        buffer.writeInteger(receivedType)
        buffer.writeInteger(receivedState)

        func writeSpentState(_ spent: HD.Coin.Spent) {
            buffer.writeInteger(UInt32(spent.height))
            var change = spent.changeOuts[...]
            buffer.writeInteger(change.popFirst() ?? .max)
            buffer.writeInteger(change.popFirst() ?? .max)
            buffer.writeInteger(change.popFirst() ?? .max)
            buffer.writeInteger(change.popFirst() ?? .max)
            let base = buffer.writerIndex
            spent.tx.write(to: &buffer)
            let difference = buffer.writerIndex - base
            precondition(difference > 0)
            precondition(difference <= self.txBufferSize)
            buffer.moveWriterIndex(forwardBy: self.txBufferSize - difference)
        }
        
        switch row.spentState {
        case .unspent:
            buffer.writeInteger(UInt8(0))
            buffer.moveWriterIndex(forwardBy: self.txBufferSize + 4)
        case .pending(let pending):
            buffer.writeInteger(UInt8(1))
            writeSpentState(pending)
        case .spent(let spent):
            buffer.writeInteger(UInt8(2))
            writeSpentState(spent)
        }
        
    }
    
    public enum CoinRepoError: Swift.Error, Hashable {
        case spentTwice
        case illegalStateSpent
        case illegalStateUnconfirmed
    }

    func append(_ row: HD.Coin) -> Future<Void> {
        self.range()
        .map(\.upperBound)
        .flatMapError {
            switch $0 {
            case File.Error.noDataFoundFileEmpty:
                return self.eventLoop.makeSucceededFuture(0)
            default:
                return self.eventLoop.makeFailedFuture($0)
            }
        }
        .flatMap { count in
            switch row._id {
            case .append:
                return self.write(row.rank(id: count))
                .flatMap(self.sync)
            case .id:
                return self.eventLoop.makeFailedFuture(File.Error.illegalArgument)
            }
        }
    }
    
    func append(_ rows: [HD.Coin]) -> Future<Void> {
        var future: Future<Void> = self.eventLoop.makeSucceededVoidFuture()

        func _append(row: HD.Coin) {
            future = future.flatMap { self.append(row) }
        }
        
        for row in rows {
            _append(row: row)
        }
        
        return future
    }
    
    fileprivate func tallyError(_ error: Swift.Error) -> Future<Tally> {
        switch error {
        case File.Error.seekError:
            return self.count()
            .flatMapThrowing {
                if $0 == 0 {
                    return []
                } else {
                    throw error
                }
            }
        default:
            return self.eventLoop.makeFailedFuture(error)
        }
    }
    
    func spendableTally() -> Future<Tally> {
        return self.find(from: 0)
        .map {
            $0.filter { $0.isSpendable }
        }
        .flatMapError(self.tallyError(_:))
    }
    
    func fullTally() -> Future<(available: Tally,
                                pendingReceive: Tally,
                                pendingSpend: Tally)> {
        let promise = self.eventLoop.makePromise(of: (available: Tally,
                                                      pendingReceive: Tally,
                                                      pendingSpend: Tally).self)
        self.find(from: 0)
        .whenComplete {
            switch $0 {
            case .success(let coins):
                let available = coins.filter {
                    $0.isSpendable
                }
                
                let receivePending = coins.filter {
                    $0.receivedState.isPending
                }
                
                let spendPending = coins.filter {
                    $0.spentState.isPending
                }
                
                promise.succeed((available: available,
                                 pendingReceive: receivePending,
                                 pendingSpend: spendPending))
            case .failure(let error):
                promise.fail(error)
            }
        }
        
        return promise.futureResult
        .flatMapError {
            self.tallyError($0)
            .map { _ in (available: [],
                         pendingReceive: [],
                         pendingSpend: []) }
        }
    }
    
    func outpoints() -> Future<[Tx.Outpoint]> {
        self.fullTally()
        .map(\.available)
        .map { coins in
            coins.map(\.outpoint)
        }
    }
    
    func pendingTransactions() -> Future<[Tx.AnyTransaction]> {
        return self.find(from: 0)
        .map {
            $0.compactMap {
                switch $0.spentState {
                case .pending(let pending):
                    return pending.tx
                case .spent, .unspent:
                    return nil
                }
            }
        }
    }
    
    func spent(id: Int, state setSpent: HD.Coin.SpentState) -> Future<TallyEvent?> {
        return self.find(id: id)
        .flatMapThrowing { coin -> (HD.Coin, TallyEvent) in
            
            func updateCoin(confirmHeight: Int, pendingHeight: Int) -> HD.Coin {
                guard confirmHeight <= pendingHeight
                else { preconditionFailure() }
            
                return HD.Coin(outpoint: coin.outpoint,
                               amount: coin.amount,
                               receivedState: coin.receivedState,
                               spentState: setSpent,
                               source: coin.source,
                               path: coin.path)
                    .rank(id: coin.id)
            }
            
            switch (coin.receivedState, coin.spentState, setSpent) {
            case (.confirmed(let confirmHeight), .unspent, .pending(let pending)):
                let update = updateCoin(confirmHeight: confirmHeight, pendingHeight: pending.height)
                let event = TallyEvent.spentUnconfirmed(coin.amount)
                return (update, event)
            case (.confirmed(let confirmHeight), .unspent, .spent(let spent)):
                let update = updateCoin(confirmHeight: confirmHeight, pendingHeight: spent.height)
                let event = TallyEvent.spentConfirmed(coin.amount)
                return (update, event)
            case (.confirmed(let confirmHeight), .pending(let pending), .spent(let spent)):
                guard pending.height <= spent.height
                else { preconditionFailure() }
                let update = updateCoin(confirmHeight: confirmHeight, pendingHeight: pending.height)
                let event = TallyEvent.spentPromoted(coin.amount)
                return (update, event)
            case (.confirmed, .pending, .pending):
                throw CoinRepoError.spentTwice // silence logging for the common case
            case (.confirmed, .spent, .pending):
                logger.info("CoinRepo \(#function) - Error: trying to ROLLBACK coin [\(coin)] that is already spent")
                throw CoinRepoError.illegalStateSpent
            case (.confirmed, .spent, .spent):
                logger.info("CoinRepo \(#function) - Error: trying to spend coin [\(coin)] that is already spent")
                throw CoinRepoError.spentTwice
            case (.unconfirmed, _, _),
                 (.rollback, _, _),
                 (_, _, .unspent):
                preconditionFailure()
            }
        }
        .flatMap { updateCoin, tallyEvent in
            self.write(updateCoin)
            .flatMap(self.sync)
            .map {
                tallyEvent
            }
        }
        .flatMapError {
            switch $0 {
            case CoinRepoError.spentTwice:
                return self.eventLoop.makeSucceededFuture(nil)
            default:
                return self.eventLoop.makeFailedFuture($0)
            }
        }
    }
    
    func atEdgeOrNext<C: Comparable>(comparable: C,
                                     selector: @escaping (Model) -> C,
                                     comparator: @escaping (C, C) -> Bool,
                                     range: Range<Int>,
                                     next: @escaping (Model) -> Future<Model>) -> Future<Model> {
        func findNext(prior: Model) -> Future<Model> {
            return next(prior)
            .flatMap { current in
                if comparator(selector(current), comparable) {
                    return self.eventLoop.makeSucceededFuture(prior)
                } else {
                    return findNext(prior: current)
                }
            }
            .flatMapErrorThrowing {
                switch $0 {
                case File.Error.seekError:
                    return prior
                default:
                    throw $0
                }
            }
        }
        
        return self.binarySearch(comparable: comparable,
                                 left: range.lowerBound,
                                 right: range.upperBound - 1,
                                 selector: selector)
        .flatMapErrorThrowing {
            switch $0 {
            case let e as File.NoExactMatchFound<Model>:
                let edge = comparator(selector(e.left), selector(e.right)) ? e.left : e.right
                if comparator(selector(edge), comparable) {
                    return edge
                } else {
                    fallthrough
                }
            default:
                throw $0
            }
        }
        .flatMap {
            findNext(prior: $0)
        }
    }

    func firstWith(height: Int) -> Future<Model> {
        self.range().flatMap { range in
            self.atEdgeOrNext(comparable: height,
                              selector: \.receivedHeight,
                              comparator: <,
                              range: range) { coin in
                self.find(id: coin.id - 1)
            }
        }
    }
    
    func lastWith(height: Int) -> Future<Model> {
        self.range().flatMap { range in
            self.atEdgeOrNext(comparable: height,
                              selector: \.receivedHeight,
                              comparator: >,
                              range: range) { coin in
                self.find(id: coin.id + 1)
            }
        }
    }
}
