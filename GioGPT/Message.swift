//
//  Message.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import Foundation

struct Message: Identifiable, Codable, Comparable {
    let id: UUID
    var text: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
    
    // Conformance to Comparable to allow sorting by timestamp
    static func < (lhs: Message, rhs: Message) -> Bool {
        return lhs.timestamp < rhs.timestamp
    }
}
