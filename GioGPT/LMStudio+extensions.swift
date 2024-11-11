//
//  LMStudio+extensions.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-10.
//

import Foundation

extension LMStudioApiClient {
    
    func generateConversationTitle(conversation: [Message], modelId: String) async throws -> String {
        let titlePrompt = """
        Provide a very short, descriptive title for this message. Limit to max 6 words and focus only on the main topic or purpose.
        Respond only with the title.
        """

        var messagesForTitle = Array(conversation.prefix(1))
        messagesForTitle.insert(Message(text: titlePrompt, isUser: false), at: 0)

        let title = try await sendChatCompletions(
            conversation: messagesForTitle,
            modelId: modelId,
            topP: 0.5,
            temperature: 0.2,
            maxTokens: 15,
            presencePenalty: 0.5,
            frequencyPenalty: 0.5
        )
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        if let currentConversationID = currentConversationID,
           let index = savedConversations.firstIndex(where: { $0.id == currentConversationID }) {
            DispatchQueue.main.async {
                self.savedConversations[index].title = trimmedTitle
                self.titleGenerated = true
                self.saveConversations()  // Persist the conversation with the new title
            }
        }
        
        return trimmedTitle
    }
}
