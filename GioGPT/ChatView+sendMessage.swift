//
//  ChatView+sendMessage.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2025-03-18.
//

import SwiftUI

extension ChatView {
    func sendMessage(scrollViewProxy: ScrollViewProxy) async {
        // Ensure a model is selected
        guard let selectedModelID = lmStudioClient.selectedModelID else {
            lmStudioClient.errorMessage = "Please select a model"
            return
        }
        lmStudioClient.errorMessage = nil
        let userPrompt = prompt
        prompt = ""
        var accumulatedContent = ""
        var aiResponseMessage: Message?
        
        // Ensure there is a current conversation, else start a new one
        if lmStudioClient.currentConversation == nil {
            let newConversation = lmStudioClient.startNewConversation()
            lmStudioClient.currentConversation = newConversation
        }
        
        guard let currentConversation = lmStudioClient.currentConversation else {
            lmStudioClient.errorMessage = "Error creating conversation"
            return
        }
        
        // Add the user's message to the conversation and scroll to it
        if let userMessage = lmStudioClient.addMessage(to: currentConversation, text: userPrompt, isUser: true) {
            scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: userMessage)
            
            // Generate a title if needed
            if lmStudioClient.currentConversation?.title == nil {
                Task {
                    let generatedTitle = try await lmStudioClient.generateConversationTitle(
                        conversation: currentConversation.messages,
                        modelId: selectedModelID,
                        context: context
                    )
                    lmStudioClient.currentConversation?.title = generatedTitle
                    try context.save()
                }
            }
        }
        
        isLoading = true
        defer {
            Task {
                await MainActor.run {
                    isLoading = false
                    generationTask = nil
                }
            }
        }
        
        do {
            if settings.stream == true {
                // Get the tuple of streams (reasoning and content) from sendChatCompletion
                let (reasoningStream, contentStream) = lmStudioClient.sendChatCompletion(
                    conversation: currentConversation.messages,
                    modelId: selectedModelID,
                    topP: settings.topP,
                    temperature: settings.temperature,
                    maxTokens: settings.maxTokens,
                    stream: true
                )
                
                // Process the reasoning stream concurrently by accumulating reasoning text into a single message
                var accumulatedReasoning = ""
                var aiReasoningMessage: Message?
                Task {
                    for await reasoning in reasoningStream {
                        if Task.isCancelled { break } // Check for cancellation
                        accumulatedReasoning += reasoning
                        try await MainActor.run {
                            try withAnimation(.easeIn) {
                                if aiReasoningMessage == nil {
                                    aiReasoningMessage = lmStudioClient.addMessage(to: currentConversation, text: accumulatedReasoning, isUser: false)
                                } else {
                                    aiReasoningMessage?.text = accumulatedReasoning
                                    try context.save()
                                }
                                if let lastMessage = currentConversation.messages.last {
                                    scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                                }
                            }
                        }
                    }
                }
                
                // Process the main content stream sequentially and accumulate the content
                for try await content in contentStream {
                    if Task.isCancelled { break } // Check for cancellation
                    accumulatedContent += content
                    try await MainActor.run {
                        try withAnimation(.easeIn) {
                            if aiResponseMessage == nil {
                                aiResponseMessage = lmStudioClient.addMessage(to: currentConversation, text: accumulatedContent, isUser: false)
                            } else {
                                aiResponseMessage?.text = accumulatedContent
                                try context.save()
                            }
                            if let lastMessage = aiResponseMessage {
                                scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                            }
                        }
                    }
                }
            } else {
                // Non-streaming implementation remains unchanged
                guard let responseContent = try await lmStudioClient.sendChatCompletions(
                    conversation: currentConversation.messages,
                    modelId: selectedModelID,
                    topP: settings.topP,
                    temperature: settings.temperature,
                    maxTokens: settings.maxTokens
                ) else { return }
                
                if let finalMessage = lmStudioClient.addMessage(to: currentConversation, text: responseContent, isUser: false) {
                    scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: finalMessage)
                }
            }
        } catch {
            if (error as? CancellationError) == nil {
                await MainActor.run {
                    lmStudioClient.errorMessage = "Failed to get a response 📣 🆘 \(error.localizedDescription)"
                }
            }
        }
        isLoading = false
    }
}
