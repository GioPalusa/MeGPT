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

    /// Sends a streaming request and returns two separate streams: one for reasoning content and one for main content.
    /// - Parameters:
    ///   - endpoint: The API endpoint to send the request to.
    ///   - method: The HTTP method to use (default is "POST").
    ///   - payload: The payload to send in the request body.
    /// - Returns: A tuple containing a reasoning stream and a content stream.
    private func sendStreamingRequest(
        endpoint: Endpoint,
        method: String = "POST",
        payload: [String: Any]
    ) -> (reasoningStream: AsyncStream<String>, contentStream: AsyncStream<String>) {
        // Create a variable to hold the continuation for the reasoning stream
        var reasoningContinuation: AsyncStream<String>.Continuation?
        // Initialize the reasoning stream
        let reasoningStream = AsyncStream<String> { continuation in
            reasoningContinuation = continuation
        }

        // Create a variable to hold the continuation for the content stream
        var contentContinuation: AsyncStream<String>.Continuation?
        // Initialize the content stream
        let contentStream = AsyncStream<String> { continuation in
            contentContinuation = continuation
        }

        // Launch an asynchronous task to handle the streaming network request
        Task {
            var request = URLRequest(url: endpoint.url(baseURL: baseURL))
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

            // Serialize the payload into JSON
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = .infinity
            config.timeoutIntervalForResource = .infinity

            let session = URLSession(configuration: config)

            var didYieldReasoningPrefix = false // Flag to track if the prefix has been yielded
            do {
                // Start receiving the streaming response
                let (bytes, _) = try await session.bytes(for: request)

                // Process each line received from the stream
                for try await line in bytes.lines {
                    if line.starts(with: "data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                        if let jsonData = jsonString.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                           let choice = chunk.choices.first {
                            // If a reasoning part is available, yield it to the reasoning stream
                            if let reasoning = choice.delta.reasoning_content {
                                if didYieldReasoningPrefix {
                                    // For subsequent chunks, yield only the reasoning text
                                    reasoningContinuation?.yield(reasoning) // yields additional reasoning text without prefix
                                } else {
                                    // For the first chunk, yield with the prefix
                                    reasoningContinuation?.yield("[Reasoning]: \(reasoning)") // Inline documentation: yields reasoning part with prefix
                                    didYieldReasoningPrefix = true
                                }
                            }

                            // If main content is available, yield it to the content stream
                            if let content = choice.delta.content {
                                contentContinuation?.yield(content) // Inline documentation: yields main content part
                            }
                        }
                    }
                }
            } catch {
                print("Streaming request failed: \(error)")
            }
            // Finish both streams after processing completes
            reasoningContinuation?.finish()
            contentContinuation?.finish()
        }

        return (reasoningStream: reasoningStream, contentStream: contentStream)
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

    /// Sends a streaming chat completion and returns a tuple of two streams: one for reasoning content and one for main content.
    /// - Parameters:
    ///   - conversation: An array of `Message` objects representing the conversation.
    ///   - modelId: The identifier of the model to use for the chat completion.
    ///   - topP: Optional parameter for nucleus sampling probability.
    ///   - temperature: Optional parameter for controlling randomness in the output.
    ///   - maxTokens: Optional parameter to limit the maximum number of tokens in the output.
    ///   - stream: A Boolean value indicating whether to use streaming mode (true).
    ///   - stop: Optional array of stop sequences.
    ///   - presencePenalty: Optional penalty to discourage repetition.
    ///   - frequencyPenalty: Optional penalty based on token frequency.
    ///   - logitBias: Optional dictionary to bias logits.
    ///   - repeatPenalty: Optional repeat penalty.
    ///   - seed: Optional seed value for randomization.
    /// - Returns: A tuple containing a reasoning stream and a content stream.
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
    ) -> (reasoningStream: AsyncStream<String>, contentStream: AsyncStream<String>) {
        // Construct the payload with the required parameters
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

        // Return the tuple of streams provided by sendStreamingRequest
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
