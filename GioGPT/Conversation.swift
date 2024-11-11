//
//  Conversation.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID  // Unique identifier for the conversation
    var messages: [Message]  // Array of messages within this conversation
    var date: Date  // When the conversation was created
    var lastUsed: Date  // When the conversation was last used
    var title: String?
    
    init(id: UUID = UUID(), messages: [Message] = [], title: String? = nil, date: Date = Date(), lastUsed: Date = Date()) {
            self.id = id
            self.messages = messages
            self.title = title
            self.date = date
            self.lastUsed = lastUsed
    }
}
