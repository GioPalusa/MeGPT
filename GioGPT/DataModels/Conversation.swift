//
//  Conversation.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-11.
//

import SwiftData
import Foundation

@Model
final class Conversation {
    // Properties
    @Attribute(.unique) var id: UUID
    var title: String?
    var date: Date
    var lastUsed: Date
    
    // Relationship to messages
    @Relationship(inverse: \Message.conversation) var messages: [Message] = []

    // Initializer for required properties
    init(id: UUID = UUID(), title: String? = nil, date: Date = Date(), lastUsed: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.lastUsed = lastUsed
    }
}

@Model
final class Message {
    // Properties
    @Attribute(.unique) var id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date
    
    // Relationship to conversation
    @Relationship var conversation: Conversation?

    // Initializer for required properties
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}
