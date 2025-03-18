//
//  ChatView+prepareStart.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2025-03-18.
//

import SwiftUI

extension ChatView {
    func prepareStart() {
        Task {
            do {
                try await lmStudioClient.fetchModels()
                await MainActor.run {
                    if let firstModelID = lmStudioClient.models.first?.id {
                        lmStudioClient.selectedModelID = firstModelID
                        lmStudioClient.setLastSelectedModel(byID: firstModelID)
                    }
                }
            } catch {
                lmStudioClient.errorMessage = "Error fetching models: \(error)"
            }

            if let lastConversation = savedConversations.first {
                lmStudioClient.currentConversation = lastConversation
            } else {
                lmStudioClient.currentConversation = lmStudioClient.startNewConversation()
            }

            prepareHaptics()
            isInitialAppear = false
        }
    }
}
