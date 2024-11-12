import Foundation
import SwiftData

class LMStudioApiClient: ObservableObject {
    var context: ModelContext
    @Published var baseURL: URL {
        didSet {
            UserDefaults.standard.set(baseURL.absoluteString, forKey: "baseURL")
        }
    }

    private let lastSelectedModelKey = "lastSelectedModelID"
    var titleGenerated = false

    @Published var models: [LMStudioModel] = []
    @Published var selectedModelID: String?
    @Published var currentConversation: Conversation?
    
    init(baseURL: String, context: ModelContext) {
        let savedBaseURL = UserDefaults.standard.string(forKey: "baseURL") ?? baseURL
        self.baseURL = URL(string: savedBaseURL)!
        self.context = context
        loadLastSelectedModelID()
    }

    func updateBaseURL(_ newBaseURL: String) async throws {
        if let url = URL(string: newBaseURL) {
            await MainActor.run {
                self.baseURL = url
            }
            try await fetchModels()
        }
    }

    func fetchModels() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/models"))
        request.httpMethod = "GET"

        let (data, _) = try await URLSession.shared.data(for: request)
        let modelsResponse = try JSONDecoder().decode(LMStudioModelsResponse.self, from: data)
        
        await MainActor.run {
            self.models = modelsResponse.data
            if let lastModelID = selectedModelID, models.contains(where: { $0.id == lastModelID }) {
                setLastSelectedModel(byID: lastModelID)
            } else if let firstModel = models.first {
                setLastSelectedModel(byID: firstModel.id)
            }
        }
    }

    func startNewConversation() -> Conversation {
        let conversation = Conversation()
        conversation.date = Date()
        conversation.lastUsed = Date()
        
        context.insert(conversation)
        currentConversation = conversation
        titleGenerated = false
        
        return conversation
    }

    @MainActor
    func addMessage(to conversation: Conversation, text: String, isUser: Bool) -> Message? {
        // Create a new message
        let message = Message(text: text, isUser: isUser)
        message.timestamp = Date()
        message.conversation = conversation
        
        // Insert the message into the context
        context.insert(message)
        
        // Update the last used time for the conversation
        conversation.lastUsed = Date()
        
        // Save context to persist changes
        do {
            try context.save() // Save to ensure messages persist
            return message  // Return the saved message if needed for further updates
        } catch {
            print("Failed to save message: \(error)")
            return nil
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        // Remove from context
        context.delete(conversation)
        
        // If the deleted conversation is the current one, clear it
        if currentConversation === conversation {
            currentConversation = nil
        }

        // Save the changes
        do {
            try context.save()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    func sendChatCompletion(
        conversation: [Message],
        modelId: String,
        topP: Double? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = true,
        stop: [String]? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        logitBias: [String: Double]? = nil,
        repeatPenalty: Double? = nil,
        seed: String? = nil
    ) async throws -> AsyncStream<String> {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        
        var payload: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "stream": stream
        ]
        
        if let topP = topP { payload["top_p"] = topP }
        if let temperature = temperature { payload["temperature"] = temperature }
        if let maxTokens = maxTokens { payload["max_completion_tokens"] = maxTokens }
        if let stop = stop { payload["stop"] = stop }
        if let presencePenalty = presencePenalty { payload["presence_penalty"] = presencePenalty }
        if let frequencyPenalty = frequencyPenalty { payload["frequency_penalty"] = frequencyPenalty }
        if let logitBias = logitBias { payload["logit_bias"] = logitBias }
        if let repeatPenalty = repeatPenalty { payload["repeat_penalty"] = repeatPenalty }
        if let seed = seed { payload["seed"] = seed }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return AsyncStream { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                guard let data = data, error == nil else {
                    continuation.finish()
                    return
                }

                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                for line in lines {
                    if line.starts(with: "data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                        if let jsonData = jsonString.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                           let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                }
                continuation.finish()
            }
            task.resume()
        }
    }

    func sendChatCompletions(
        conversation: [Message],
        modelId: String,
        topP: Double? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stop: [String]? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        logitBias: [String: Double]? = nil,
        repeatPenalty: Double? = nil,
        seed: String? = nil) async throws -> String? {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
        let messages = conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
            
        var payload: [String: Any] = [
            "model": modelId,
            "messages": messages
        ]
            
        if let topP = topP { payload["top_p"] = topP }
        if let temperature = temperature { payload["temperature"] = temperature }
        if let maxTokens = maxTokens { payload["max_completion_tokens"] = maxTokens }
        if let stop = stop { payload["stop"] = stop }
        if let presencePenalty = presencePenalty { payload["presence_penalty"] = presencePenalty }
        if let frequencyPenalty = frequencyPenalty { payload["frequency_penalty"] = frequencyPenalty }
        if let logitBias = logitBias { payload["logit_bias"] = logitBias }
        if let repeatPenalty = repeatPenalty { payload["repeat_penalty"] = repeatPenalty }
        if let seed = seed { payload["seed"] = seed }
            
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        let chatResponse = try JSONDecoder().decode(LMStudioChatResponse.self, from: data)
            
        guard let messageContent = chatResponse.choices.first?.message.content else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in response"])
        }
            
        return messageContent
    }

    func appendMessages(_ messages: [Message], toConversation conversation: Conversation) {
        let uniqueMessages = messages.filter { newMessage in
            !conversation.messages.contains { $0.id == newMessage.id }
        }
        
        for message in uniqueMessages {
            context.insert(message)
            conversation.messages.append(message)
        }
        
        conversation.lastUsed = Date()
        
        do {
            try context.save()
        } catch {
            print("Failed to save messages to conversation: \(error)")
        }
    }

    func saveLastSelectedModelID(_ modelID: String) {
        UserDefaults.standard.set(modelID, forKey: lastSelectedModelKey)
        selectedModelID = modelID
    }
    
    private func loadLastSelectedModelID() {
        selectedModelID = UserDefaults.standard.string(forKey: lastSelectedModelKey)
    }
    
    private func setLastSelectedModel(byID modelID: String) {
        selectedModelID = modelID
        saveLastSelectedModelID(modelID)
    }
}

/// Metadata structure for saved conversations
struct ConversationMetadata: Identifiable, Codable {
    let id: String
    let date: Date
    var lastUsed: Date
}

/// A response chunk for a streaming chat completion
struct ChatCompletionChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
