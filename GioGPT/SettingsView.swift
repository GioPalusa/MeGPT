//
//  SettingsView.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    private var context: ModelContext?
    @EnvironmentObject var settings: ChatSettings
    @EnvironmentObject var lmStudioClient: LMStudioApiClient

    @State private var baseURL: String
    @State private var port: String
    @State private var protocolType: String = "http"
    @State private var isRefreshing = false
    @State private var serverSettingsError: String? = nil
    @State private var modelRefreshError: String? = nil
    @State private var successfullyConfigured: Bool = false
    
    @Query(sort: \Conversation.lastUsed, order: .reverse) var conversations: [Conversation]
    @Environment(\.modelContext) private var modelContext

    init(lmStudioClient: LMStudioApiClient) {
        let fullBaseURL = lmStudioClient.baseURL
        _baseURL = State(initialValue: fullBaseURL.host ?? "")
        _port = State(initialValue: "\(fullBaseURL.port ?? 1234)")
        _protocolType = State(initialValue: fullBaseURL.scheme ?? "http")
    }
    
    var body: some View {
        Form {
            Section(header: Text("Server Settings")) {
                Picker("Protocol", selection: $protocolType) {
                    Text("HTTP").tag("http")
                    Text("HTTPS").tag("https")
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: protocolType) { _, newType in
                    Task {
                        try await lmStudioClient.updateBaseURL(newType)
                    }
                }

                TextField("Server Address", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: {
                    Task {
                        try await applyNewBaseURL()
                    }
                }) {
                    Text("Apply Server Settings")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                            
                if let error = serverSettingsError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                } else if successfullyConfigured {
                    Text("Successfully connected to server")
                        .font(.footnote)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Model Selection")) {
                Picker("Select Model", selection: $lmStudioClient.selectedModelID) {
                    ForEach(lmStudioClient.models, id: \.self) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                Button(action: {
                    Task {
                        await refreshModels()
                    }
                }) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Text("Refresh")
                    }
                }
                
                if let error = modelRefreshError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Generation Settings")) {
                DisclosureGroup("Temperature") {
                    Text("Controls the randomness of the model's responses. Higher values (up to 2) make outputs more random, while lower values (down to 0) make them more focused and deterministic.\n\nDefault: 1.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { settings.temperature ?? 1.0 },
                            set: { settings.temperature = $0 }
                        ), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", settings.temperature ?? 1.0))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                DisclosureGroup("Top P ") {
                    Text("Nucleus sampling parameter. Limits the model’s token choices to those within the top probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.\n\nDefault: 1.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { settings.topP ?? 1.0 },
                            set: { settings.topP = $0 }
                        ), in: 0...1, step: 0.1)
                        Text(String(format: "%.1f", settings.topP ?? 1.0))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                DisclosureGroup("Max Completion Tokens") {
                    Text("Sets the upper bound for the number of tokens that can be generated for a completion, including visible output tokens and reasoning tokens.\n\nDefault: 100")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Stepper("Max Tokens: \(settings.maxTokens ?? 100)", value: Binding(
                        get: { settings.maxTokens ?? 100 },
                        set: { settings.maxTokens = $0 }
                    ), in: 1...1000)
                }
                
                DisclosureGroup("Stream Response") {
                    Text("If enabled, partial message deltas will be sent as they become available, like in ChatGPT.\n\nDefault: true")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Toggle("Stream Response", isOn: Binding(
                        get: { settings.stream ?? false },
                        set: { settings.stream = $0 }
                    ))
                }
                
                DisclosureGroup("Stop Sequences") {
                    Text("Up to 4 sequences where the API will stop generating further tokens.\n\nDefault: None")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("Stop Sequences (comma-separated)", text: Binding(
                        get: { settings.stopSequences ?? "" },
                        set: { settings.stopSequences = $0 }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
            Section(header: Text("Penalties")) {
                DisclosureGroup("Presence Penalty") {
                    Text("Penalizes new tokens based on whether they appear in the text so far, encouraging the model to talk about new topics.\n\nDefault: 0.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { settings.presencePenalty ?? 0.0 },
                            set: { settings.presencePenalty = $0 }
                        ), in: -2...2, step: 0.1)
                        Text(String(format: "%.1f", settings.presencePenalty ?? 0.0))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                DisclosureGroup("Frequency Penalty") {
                    Text("Penalizes new tokens based on their existing frequency in the text so far, discouraging the model from repeating the same line verbatim.\n\nDefault: 0.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { settings.frequencyPenalty ?? 0.0 },
                            set: { settings.frequencyPenalty = $0 }
                        ), in: -2...2, step: 0.1)
                        Text(String(format: "%.1f", settings.frequencyPenalty ?? 0.0))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                DisclosureGroup("Repeat Penalty") {
                    Text("Discourages the model from repeating similar tokens in the output, useful to reduce repetitive responses.\n\nDefault: 1.0")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { settings.repeatPenalty ?? 1.0 },
                            set: { settings.repeatPenalty = $0 }
                        ), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", settings.repeatPenalty ?? 1.0))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                DisclosureGroup("Seed") {
                    Text("A seed for deterministic generation. Repeated requests with the same seed and parameters should return the same result.\n\nDefault: None")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    TextField("Seed (optional)", text: Binding(
                        get: { settings.seed ?? "" },
                        set: { settings.seed = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section {
                    Button(action: {
                        settings.resetToDefaults()
                    }) {
                        Text("Reset to Default Settings")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }

                Section(header: Text("Chat Conversations")) {
                    if conversations.isEmpty {
                        Text("No conversations available.")
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(conversations) { conversation in
                                HStack {
                                    Text(conversation.title ?? "Untitled Conversation")
                                        .font(.headline)
                                    Spacer()
                                    Text(conversation.date, style: .date)
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                            .onDelete(perform: deleteConversation)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationTitle("Settings")
        .toolbar {
            EditButton()
        }
    }
    
    // Function to handle deletion and persistence
    private func deleteConversation(at offsets: IndexSet) {
        for index in offsets {
            let conversationToDelete = conversations[index]
            if conversationToDelete == lmStudioClient.currentConversation {
                lmStudioClient.currentConversation = nil
            }
            modelContext.delete(conversationToDelete) // Delete the conversation from the context
        }
        
        // Explicitly save the context after deletion to persist changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context after deletion: \(error)")
        }
    }
    
    private func applyNewBaseURL() async throws {
        let formattedBaseURL = "\(protocolType)://\(baseURL):\(port)"
        do {
            try await lmStudioClient.updateBaseURL(formattedBaseURL)
            successfullyConfigured = true
        } catch {
            serverSettingsError = error.localizedDescription
        }
    }
    
    private func refreshModels() async {
        isRefreshing = true
        modelRefreshError = nil
        do {
            try await lmStudioClient.fetchModels()
            successfullyConfigured = true
        } catch {
            serverSettingsError = error.localizedDescription
        }
        isRefreshing = false
    }
}
