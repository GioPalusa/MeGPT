import Foundation
import SwiftData

class LMStudioApiClient: ObservableObject {
    @Published var errorMessage: String?

    var context: ModelContext
    @Published var baseURL: URL {
        didSet {
            UserDefaults.standard.set(baseURL.absoluteString, forKey: "baseURL")
        }
    }

    var currentProtocol: String {
        get {
            baseURL.scheme ?? "http"
        }
        set {
            updateProtocol(to: newValue)
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

    enum Endpoint: String {
        case models = "/v1/models"
        case chatCompletions = "/v1/chat/completions"

        func url(baseURL: URL) -> URL {
            baseURL.appendingPathComponent(rawValue)
        }
    }

    // Centraliserad metod för icke-streamande förfrågningar
    private func sendRequest<T: Decodable>(
        endpoint: Endpoint,
        method: String = "GET",
        payload: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url(baseURL: baseURL))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let payload = payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600

        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(responseType, from: data)
    }

    // Centraliserad metod för streamande förfrågningar
    private func sendStreamingRequest(
        endpoint: Endpoint,
        method: String = "POST",
        payload: [String: Any]
    ) -> AsyncStream<String> {
        AsyncStream<String> { continuation in
            Task {
                var request = URLRequest(url: endpoint.url(baseURL: baseURL))
                request.httpMethod = method
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

                request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = .infinity
                config.timeoutIntervalForResource = .infinity

                let session = URLSession(configuration: config)

                do {
                    let (bytes, _) = try await session.bytes(for: request)

                    var reasoningContent = ""
                    for try await line in bytes.lines {
                        if line.starts(with: "data: ") {
                            let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                            if let jsonData = jsonString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                               let choice = chunk.choices.first {
                                
                                if let reasoning = choice.delta.reasoning_content {
                                    let formattedReasoning = reasoningContent.isEmpty ? "[Reasoning]: \(reasoning)" : " \(reasoning)"
                                    continuation.yield(formattedReasoning) // Stream reasoning content immediately
                                    reasoningContent += formattedReasoning
                                }

                                if let content = choice.delta.content {
                                    continuation.yield(reasoningContent + content)
                                    reasoningContent = ""
                                }
                            }
                        }
                    }
                } catch {
                    print("Streaming request failed: \(error)")
                }
                
                continuation.finish()
            }
        }
    }

    // Fetch models (icke-streamande)
    func fetchModels() async throws {
        do {
            let modelsResponse: LMStudioModelsResponse = try await sendRequest(
                endpoint: .models,
                responseType: LMStudioModelsResponse.self
            )

            await MainActor.run {
                self.models = modelsResponse.data
                if let lastModelID = selectedModelID, models.contains(where: { $0.id == lastModelID }) {
                    setLastSelectedModel(byID: lastModelID)
                } else if let firstModel = models.first {
                    setLastSelectedModel(byID: firstModel.id)
                }
            }
        } catch let error as NetworkError {
            self.errorMessage = error.localizedDescription
        }
    }

    // Skicka chatt-komplettering (icke-streamande)
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
        var payload: [String: Any] = [
            "model": modelId,
            "messages": conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
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

        let chatResponse: LMStudioChatResponse = try await sendRequest(
            endpoint: .chatCompletions,
            method: "POST",
            payload: payload,
            responseType: LMStudioChatResponse.self
        )

        return chatResponse.choices.first?.message.content
    }

    // Skicka chatt-komplettering (streamande)
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
    ) -> AsyncStream<String> {
        var payload: [String: Any] = [
            "model": modelId,
            "messages": conversation.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] },
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

        return sendStreamingRequest(endpoint: .chatCompletions, method: "POST", payload: payload)
    }

    /// Adds a new message to the specified conversation
    /// - Parameters:
    ///   - conversation: The `Conversation` object to which the message should be added
    ///   - text: The text content of the message
    ///   - isUser: A Boolean indicating if the message is from the user (`true`) or AI (`false`)
    /// - Returns: The newly created `Message` object, or `nil` if adding failed
    func addMessage(to conversation: Conversation, text: String, isUser: Bool) -> Message? {
        guard !text.isEmpty else {
            errorMessage = "Message text cannot be empty."
            return nil
        }

        let newMessage = Message(text: text, isUser: isUser, timestamp: Date())
        newMessage.conversation = conversation
        conversation.lastUsed = Date()

        // Insert the message into the SwiftData context
        context.insert(newMessage)

        // Save the context to persist the changes
        do {
            try context.save()
            return newMessage
        } catch {
            errorMessage = "Failed to save the message: \(error.localizedDescription)"
            return nil
        }
    }

    enum NetworkError: LocalizedError {
        case sslError
        case connectionError
        case serverError(statusCode: Int)
        case unexpectedError
        case timeoutError

        var errorDescription: String? {
            switch self {
            case .sslError:
                return "A secure connection could not be established."
            case .connectionError:
                return "Unable to connect to the server."
            case .serverError(let statusCode):
                return "Server returned an error with status code \(statusCode)."
            case .unexpectedError:
                return "An unexpected error occurred."
            case .timeoutError:
                return "The request timed out."
            }
        }
    }

    // Ladda senaste valda modell-ID från UserDefaults
    private func loadLastSelectedModelID() {
        if let lastSelectedModelID = UserDefaults.standard.string(forKey: lastSelectedModelKey) {
            selectedModelID = lastSelectedModelID
        }
    }

    // Spara det valda modell-ID:t i UserDefaults och uppdatera det lokala tillståndet
    func setLastSelectedModel(byID modelID: String) {
        UserDefaults.standard.set(modelID, forKey: lastSelectedModelKey)
        selectedModelID = modelID
    }

    /// Updates the protocol for the base URL
    func updateProtocol(to scheme: String) {
        guard scheme == "http" || scheme == "https" else {
            print("Invalid scheme: \(scheme). Use 'http' or 'https'.")
            return
        }

        let currentURLString = baseURL.absoluteString
        if let updatedURL = URL(string: currentURLString.replacingOccurrences(of: baseURL.scheme ?? "", with: scheme)) {
            baseURL = updatedURL
        }
    }

    func startNewConversation() -> Conversation {
        let conversation = Conversation()
        conversation.date = Date()
        conversation.lastUsed = Date()

        // Sätt titel som nil för att indikera att den behöver genereras
        conversation.title = nil

        // Lägg till konversationen i SwiftData-kontexten
        context.insert(conversation)

        // Uppdatera den aktuella konversationen
        currentConversation = conversation

        // Spara kontexten
        do {
            try context.save()
        } catch {
            print("Failed to save new conversation: \(error)")
        }

        // Returnera den nyskapade konversationen
        return conversation
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
    let id: String
    let object: String
    let created: Int
    let model: String
    let systemFingerprint: String
    let choices: [Choice]

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices
        case systemFingerprint = "system_fingerprint"
    }

    struct Choice: Codable {
        let finishReason: String?
        let delta: Delta
        let logprobs: String?
        let index: Int

        enum CodingKeys: String, CodingKey {
            case finishReason = "finish_reason"
            case delta, logprobs, index
        }
    }

    struct Delta: Codable {
        let content: String?
        let reasoning_content: String? // Properly declared as optional string
        let role: String
    }
}
