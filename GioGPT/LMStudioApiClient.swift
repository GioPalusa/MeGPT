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
            DispatchQueue.main.async {
                self.baseURL = url
            }
            try await fetchModels()
        } else {
            throw URLError(.badURL)
        }
    }

    func fetchModels() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/models"))
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check the HTTP status code
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }

            // Decode the response data
            let modelsResponse = try JSONDecoder().decode(LMStudioModelsResponse.self, from: data)

            // Update UI on the main thread
            await MainActor.run {
                self.models = modelsResponse.data
                if let lastModelID = selectedModelID, models.contains(where: { $0.id == lastModelID }) {
                    setLastSelectedModel(byID: lastModelID)
                } else if let firstModel = models.first {
                    setLastSelectedModel(byID: firstModel.id)
                }
            }
            
        } catch let error as URLError {
            // Explicitly check for SSL error code and throw a specific `sslError`
            if error.code == .secureConnectionFailed {
                throw NetworkError.sslError
            } else {
                throw handleNetworkError(error)
            }
        } catch {
            // Catch any other unexpected errors
            throw NetworkError.unexpectedError
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
        let message = Message(text: text, isUser: isUser)
        message.timestamp = Date()
        message.conversation = conversation

        context.insert(message)
        conversation.lastUsed = Date()

        do {
            try context.save()
            return message
        } catch {
            print("Failed to save message: \(error)")
            return nil
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        context.delete(conversation)

        if currentConversation === conversation {
            currentConversation = nil
        }

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

        // Capture the async part in a Task, yielding results in the non-async AsyncStream.
        return AsyncStream<String> { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                var lines: [Substring] = []
                if let data {
                    lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                }

                // Process response data as chunks for streaming
                for line in lines {
                    if line.starts(with: "data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                        if let jsonData = jsonString.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                           let content = chunk.choices.first?.delta.content
                        {
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
        seed: String? = nil
    ) async throws -> String? {
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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            }

            let chatResponse = try JSONDecoder().decode(LMStudioChatResponse.self, from: data)
            guard let messageContent = chatResponse.choices.first?.message.content else {
                throw NetworkError.unexpectedError
            }

            return messageContent
        } catch let error as URLError {
            throw handleNetworkError(error)
        } catch {
            throw NetworkError.unexpectedError
        }
    }

    // Helper to handle specific network errors
    private func handleNetworkError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost:
            return .connectionError
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return .sslError
        default:
            return .unexpectedError
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

    enum NetworkError: LocalizedError {
        case sslError
        case connectionError
        case serverError(statusCode: Int)
        case unexpectedError

        var errorDescription: String? {
            switch self {
            case .sslError:
                return "A secure connection could not be established. Please check your HTTPS settings or try again later."
            case .connectionError:
                return "Unable to connect to the server. Please check your internet connection and try again."
            case .serverError(let statusCode):
                return "Server returned an error with status code: \(statusCode). Please contact support if this issue persists."
            case .unexpectedError:
                return "An unexpected error occurred. Please try again later."
            }
        }
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
