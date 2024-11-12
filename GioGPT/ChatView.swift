import CoreHaptics
import SwiftData
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var settings: ChatSettings
    @EnvironmentObject var lmStudioClient: LMStudioApiClient
    @Environment(\.modelContext) private var context
    @State private var prompt = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var isInitialAppear = true
    @Environment(\.colorScheme) var colorScheme
    
    @Query(sort: \Conversation.lastUsed, order: .reverse) private var savedConversations: [Conversation]

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Spacer()
                    
                    // Settings button with dropdown menu
                    Menu {
                        if !savedConversations.isEmpty {
                            Menu("Load Conversation") {
                                ForEach(savedConversations) { conversationMetadata in
                                    Button(action: {
                                        lmStudioClient.currentConversation = conversationMetadata
                                    }) {
                                        if let title = conversationMetadata.title {
                                            Text(title)
                                        } else {
                                            Text("Conversation on \(conversationMetadata.date.formatted(date: .abbreviated, time: .shortened))")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Button("New Conversation") {
                            lmStudioClient.currentConversation = lmStudioClient.startNewConversation()
                        }
                        
                        Button("Settings") {
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .padding()
                }
                
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let conversation = lmStudioClient.currentConversation, !conversation.messages.isEmpty {
                                // Show messages if conversation is not empty
                                ForEach(conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }), id: \.id) { message in
                                    HStack {
                                        if message.isUser {
                                            Spacer()
                                            Text(message.text)
                                                .padding(10)
                                                .background(Color(red: 0.5, green: 0.0, blue: 0.0))
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                                .textSelection(.enabled)
                                        } else {
                                            Text(message.text)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                    }
                                    .id(message.id)
                                }
                            } else {
                                // Display welcome message if no conversation or it's empty
                                Text("Welcome to Gio GPT")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            }
                            
                            if let errorMessage = errorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding()
                            }
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                        .onChange(of: lmStudioClient.currentConversation?.messages.count) { _, _ in
                            if let lastMessage = lmStudioClient.currentConversation?.messages.last {
                                scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                            }
                        }
                        .background(
                            EmptyView()
                                .navigationDestination(isPresented: $isShowingSettings) {
                                    SettingsView(lmStudioClient: lmStudioClient)
                                }
                        )
                    }
                    
                    HStack {
                        TextField("What do you need?", text: $prompt)
                            .padding()
                            .submitLabel(.send)
                            .onSubmit {
                                Task {
                                    await sendMessage(scrollViewProxy: scrollViewProxy)
                                }
                            }
                            .background(.clear)
                            .cornerRadius(8)
                        
                        Button(action: {
                            Task {
                                await sendMessage(scrollViewProxy: scrollViewProxy)
                            }
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(isLoading ? Color.gray : .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || prompt.isEmpty)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .navigationTitle(lmStudioClient.currentConversation?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isInitialAppear {
                    Task {
                        do {
                            try await lmStudioClient.fetchModels()
                            await MainActor.run {
                                if let lastModelID = lmStudioClient.selectedModelID,
                                   let model = lmStudioClient.models.first(where: { $0.id == lastModelID })
                                {
                                    lmStudioClient.selectedModelID = model.id
                                } else if let firstModelID = lmStudioClient.models.first?.id {
                                    lmStudioClient.selectedModelID = firstModelID
                                    lmStudioClient.saveLastSelectedModelID(firstModelID)
                                }
                            }
                        } catch {
                            print("Error fetching models: \(error)")
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
        }
    }

    private func sendMessage(scrollViewProxy: ScrollViewProxy) async {
        guard let selectedModelID = lmStudioClient.selectedModelID else {
            errorMessage = "Please select a model"
            return
        }

        let userPrompt = prompt
        prompt = ""
        var accumulatedContent = ""
        var aiResponseMessage: Message?
        
        if lmStudioClient.currentConversation == nil {
            let newconversation = lmStudioClient.startNewConversation()
            lmStudioClient.currentConversation = newconversation
        }

        guard let currentConversation = lmStudioClient.currentConversation else {
            errorMessage = "Error creating conversation"
            return
        }
        if let userMessage = lmStudioClient.addMessage(to: currentConversation, text: userPrompt, isUser: true) {
            scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: userMessage)
                
            if lmStudioClient.currentConversation?.title == nil, let currentConversation = lmStudioClient.currentConversation {
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

        do {
            if settings.stream == true {
                let stream = try await lmStudioClient.sendChatCompletion(
                    conversation: lmStudioClient.currentConversation!.messages,
                    modelId: selectedModelID,
                    topP: settings.topP,
                    temperature: settings.temperature,
                    maxTokens: settings.maxTokens,
                    stream: true
                )

                for try await content in stream {
                    accumulatedContent += content

                    try await MainActor.run {
                        if aiResponseMessage == nil {
                            aiResponseMessage = lmStudioClient.addMessage(to: lmStudioClient.currentConversation!, text: accumulatedContent, isUser: false)
                        } else {
                            aiResponseMessage?.text = accumulatedContent
                            try context.save()
                        }

                        if let lastMessage = aiResponseMessage {
                            scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                        }
                    }
                }
            } else {
                guard let responseContent = try await lmStudioClient.sendChatCompletions(
                    conversation: lmStudioClient.currentConversation!.messages,
                    modelId: selectedModelID,
                    topP: settings.topP,
                    temperature: settings.temperature,
                    maxTokens: settings.maxTokens
                ) else { return }

                if let finalMessage = lmStudioClient.addMessage(to: lmStudioClient.currentConversation!, text: responseContent, isUser: false) {
                    scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: finalMessage)
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to get a response 📣 🆘 \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    private func scrollToLastMessage(scrollViewProxy: ScrollViewProxy, lastMessage: Message) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}
