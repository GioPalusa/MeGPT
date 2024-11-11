import Foundation

/// An API client to interact with an LM Studio server
class LMStudioApiClient: ObservableObject {
    @Published var baseURL: URL {
        didSet {
            UserDefaults.standard.set(baseURL.absoluteString, forKey: "baseURL")
        }
    }
    private let userDefaultsKey = "savedConversations"
    private let lastSelectedModelKey = "lastSelectedModelID"
    var currentConversationID: UUID?
    var titleGenerated = false
    
    @Published var models: [LMStudioModel] = []
    @Published var savedConversations: [Conversation] = []
    @Published var selectedModelID: String?
    
    init(baseURL: String) {
        let savedBaseURL = UserDefaults.standard.string(forKey: "baseURL") ?? baseURL
        self.baseURL = URL(string: savedBaseURL)!

        loadConversations()
        loadLastSelectedModelID()
        
        if savedConversations.isEmpty {
            startNewConversation()
        } else {
            currentConversationID = savedConversations.sorted(by: { $0.lastUsed > $1.lastUsed }).first?.id
        }
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

    func startNewConversation() {
        let newConversation = Conversation()
        savedConversations.append(newConversation)
        saveConversations()
        
        currentConversationID = newConversation.id
        titleGenerated = false
    }
        
    /// Send the full conversation for completion with optional parameters, supporting streaming
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
        
        guard let currentConversationID = currentConversationID else {
            startNewConversation()
            return try await sendChatCompletion(
                conversation: conversation,
                modelId: modelId,
                topP: topP,
                temperature: temperature,
                maxTokens: maxTokens,
                stream: stream,
                stop: stop,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                logitBias: logitBias,
                repeatPenalty: repeatPenalty,
                seed: seed
            )
        }
        
        if !titleGenerated, let modelId = selectedModelID {
            // Generate a title asynchronously on the first user message
            Task {
                do {
                    let generatedTitle = try await generateConversationTitle(conversation: conversation, modelId: modelId)
                    print("Generated Title: \(generatedTitle)")
                    titleGenerated = true  // Ensure title is generated only once per conversation
                } catch {
                    print("Failed to generate title: \(error)")
                }
            }
        }
        
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages = conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        
        var payload: [String: Any] = [
            "model": modelId,
            "messages": messages,
            "stream": stream
        ]
        
        // Add optional parameters to the payload
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
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                
                self.appendMessages(conversation, toConversationWithID: currentConversationID)
            }
            task.resume()
        }
    }
    
    /// Send a single chat completion without streaming
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
            seed: String? = nil
        ) async throws -> String {
            
            var request = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let messages = conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
            
            var payload: [String: Any] = [
                "model": modelId,
                "messages": messages
            ]
            
            // Add optional parameters to the payload
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
            
            guard let message = chatResponse.choices.first?.message.content else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in response"])
            }
            
            if let currentConversationID = currentConversationID {
                let completionMessage = Message(id: UUID(), text: message, isUser: false)
                appendMessages([completionMessage], toConversationWithID: currentConversationID)
            }
            
            return message
        }

    func appendMessages(_ messages: [Message], toConversationWithID conversationID: UUID) {
        guard let index = savedConversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        
        let uniqueMessages = messages.filter { newMessage in
            !savedConversations[index].messages.contains { $0.id == newMessage.id }
        }
        
        DispatchQueue.main.async {
            self.savedConversations[index].messages.append(contentsOf: uniqueMessages)
            self.savedConversations[index].lastUsed = Date()
            self.saveConversations()
        }
    }
    
    func saveConversations() {
        if let data = try? JSONEncoder().encode(savedConversations) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    /// Deletes a conversation with the given UUID and updates saved conversations
    func deleteConversation(withID id: UUID) {
        // Remove conversation from the array and update UserDefaults
        if let index = savedConversations.firstIndex(where: { $0.id == id }) {
            savedConversations.remove(at: index)
            saveConversations()  // Persist the updated list to UserDefaults
        }
    }
    
    /// Loads all conversations from UserDefaults, ensuring messages and titles are restored.
    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let loadedConversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return
        }

        self.savedConversations = loadedConversations.map { conversation in
            var uniqueMessages = [UUID: Message]()
            conversation.messages.forEach { message in
                uniqueMessages[message.id] = message
            }
            return Conversation(
                id: conversation.id,
                messages: Array(uniqueMessages.values),
                title: conversation.title,
                date: conversation.date,
                lastUsed: conversation.lastUsed
            )
        }
    }
    
    func saveLastSelectedModelID(_ modelID: String) {
        UserDefaults.standard.set(modelID, forKey: lastSelectedModelKey)
        self.selectedModelID = modelID
    }
    
    private func loadLastSelectedModelID() {
        self.selectedModelID = UserDefaults.standard.string(forKey: lastSelectedModelKey)
    }
    
    private func setLastSelectedModel(byID modelID: String) {
        self.selectedModelID = modelID
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
