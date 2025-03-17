//
//  LMStudioModel.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import Foundation

/// Representerar en modell i LM Studio
struct LMStudioModel: Identifiable, Codable, Hashable {
    let id: String
    let object: String

    private enum CodingKeys: String, CodingKey {
        case id
        case object
    }
}

/// Representerar svaret från /v1/models endpoint
struct LMStudioModelsResponse: Codable {
    let data: [LMStudioModel]
    let object: String
}

/// Representerar ett enskilt svar från chat completion
struct LMStudioChatChoice: Codable {
    let message: LMStudioMessage
    let finishReason: String?
}

/// Representerar hela svaret från /v1/chat/completions endpoint
struct LMStudioChatResponse: Codable {
    let choices: [LMStudioChatChoice]
}

/// Representerar meddelandestrukturen i ett chattsvar
struct LMStudioMessage: Codable {
    let role: String
    let content: String
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
    }
}
