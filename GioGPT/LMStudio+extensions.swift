//
//  LMStudio+extensions.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-10.
//

import Foundation
import SwiftData

extension LMStudioApiClient {
    
    /// Generates a conversation title based on its content and updates the title in the Core Data model.
    @MainActor
    func generateConversationTitle(conversation: [Message], modelId: String, context: ModelContext) async throws -> String {
        // Adjusted prompt to request a concise title
        let titlePrompt = """
        Generate a concise, relevant title (max 6 words) for this conversation based on the main topic. Never answer the user, just summarize what the user wants from this text: \(conversation.first?.text ?? ""). Only respond with the title, no other text.
        """
        
        // Request the title from the model
        let title = try await sendChatCompletions(
            conversation: [Message(text: titlePrompt, isUser: false)],
            modelId: modelId,
            topP: 0.5,
            temperature: 0.2,
            maxTokens: 15,
            presencePenalty: 0.5,
            frequencyPenalty: 0.5
        )
        
        // Trim and format the generated title
        var trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        // Ensure the title is not too verbose
        if let title = trimmedTitle, title.count > 50 {
            trimmedTitle = String(title.prefix(50)) + "..."
        }
        
        // Update the conversation title in Core Data if it doesn't already exist
        if let currentConversation = currentConversation, currentConversation.title == nil {
            await MainActor.run {
                currentConversation.title = trimmedTitle
                titleGenerated = true
                
                // Save the updated title to Core Data
                do {
                    try context.save()
                } catch {
                    print("Failed to save conversation title: \(error)")
                }
            }
        }
        
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        } else {
            return "New Chat"
        }
    }
}
