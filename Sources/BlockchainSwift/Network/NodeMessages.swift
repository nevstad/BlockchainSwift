//
//  NodeMessages.swift
//  App
//
//  Created by Magnus Nevstad on 10/04/2019.
//

import Foundation

/// All messages get wrapped
public struct Message: Serializable, Deserializable, Codable {
    public enum Commands: String {
        case version
        case transactions
        case getBlocks
        case blocks
    }
    
    public let command: String
    public let payload: Data
    
    func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    static func deserialize(_ data: Data) throws -> Message {
        return try JSONDecoder().decode(Message.self, from: data)
    }
}

/// The version message
public struct VersionMessage: Serializable, Deserializable, Codable {
    public let version: Int
    public let blockHeight: Int
    public let fromAddress: NodeAddress

    func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    static func deserialize(_ data: Data) throws -> VersionMessage {
        return try JSONDecoder().decode(VersionMessage.self, from: data)
    }
}

/// The transactions message contains new transations
public struct TransactionsMessage: Serializable, Deserializable, Codable {
    public let transactions: [Transaction]
    public let fromAddress: NodeAddress

    func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    static func deserialize(_ data: Data) throws -> TransactionsMessage {
        return try JSONDecoder().decode(TransactionsMessage.self, from: data)
    }
}

/// The GetBlocksMessage object will request Blocks
public struct GetBlocksMessage: Serializable, Deserializable, Codable {
    public let fromBlockHash: Data
    public let fromAddress: NodeAddress

    func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    static func deserialize(_ data: Data) throws -> GetBlocksMessage {
        return try JSONDecoder().decode(GetBlocksMessage.self, from: data)
    }
}

/// The BlocksMessage contains transferred Blocks
public struct BlocksMessage: Serializable, Deserializable, Codable {
    public let blocks: [Block]
    public let fromAddress: NodeAddress

    func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    static func deserialize(_ data: Data) throws -> BlocksMessage {
        return try JSONDecoder().decode(BlocksMessage.self, from: data)
    }
}