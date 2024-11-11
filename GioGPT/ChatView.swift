import SwiftUI
import CoreHaptics

struct ChatView: View {
    @EnvironmentObject var settings: ChatSettings
    @EnvironmentObject var lmStudioClient: LMStudioApiClient
    @State private var prompt = ""
    @State private var isLoading = false
    @State private var conversation: Conversation?
    @State private var errorMessage: String?
    @State private var isShowingSettings = false
    @State private var isInitialAppear = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Spacer()
                    
                    // Settings button with dropdown menu
                    Menu {
                        // List saved conversations
                        if !lmStudioClient.savedConversations.isEmpty {
                            Menu("Load Conversation") {
                                ForEach(lmStudioClient.savedConversations) { conversationMetadata in
                                    Button(action: {
                                        conversation = lmStudioClient.savedConversations.first(where: { $0.id == conversationMetadata.id })
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
                        
                        // New conversation option
                        Button("New Conversation") {
                            conversation = Conversation()  // Reset to a new conversation instance
                            lmStudioClient.startNewConversation()
                        }
                        
                        // Navigate to settings
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
                            if let conversation = conversation {
                                ForEach(conversation.messages.sorted(), id: \.id) { message in
                                    HStack {
                                        if message.isUser {
                                            Spacer()
                                            Text(message.text)
                                                .padding(10)
                                                .background(Color(red: 0.5, green: 0.0, blue: 0.0)) // Dark red
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                                .textSelection(.enabled)
                                        } else {
                                            Text(message.text)
                                                .padding(10)
                                                .background(.clear) // Dark forest green
                                                .cornerRadius(8)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                    }
                                    .id(message.id)
                                }
                            } else {
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
                        .onChange(of: conversation?.messages.count) { _, _ in
                            if let lastMessage = conversation?.messages.last {
                                scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                            }
                        }
                        .background(
                            NavigationLink(destination: SettingsView(lmStudioClient: lmStudioClient), isActive: $isShowingSettings) {
                                EmptyView()
                            }
                            .hidden()
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
            .onAppear {
                if isInitialAppear {
                    Task {
                        // Fetch models and set selected model
                        do {
                            try await lmStudioClient.fetchModels()
                            await MainActor.run {
                                if let lastModelID = lmStudioClient.selectedModelID,
                                   let model = lmStudioClient.models.first(where: { $0.id == lastModelID }) {
                                    lmStudioClient.selectedModelID = model.id
                                } else {
                                    lmStudioClient.selectedModelID = lmStudioClient.models.first?.id
                                    if let firstModelID = lmStudioClient.selectedModelID {
                                        lmStudioClient.saveLastSelectedModelID(firstModelID)
                                    }
                                }
                            }
                        } catch {
                            print("Error fetching models: \(error)")
                        }
                        
                        // Load the most recent conversation
                        if let recentConversationID = lmStudioClient.currentConversationID {
                            conversation = lmStudioClient.savedConversations.first(where: { $0.id == recentConversationID })
                        } else {
                            conversation = Conversation() // Start a new conversation if none exists
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
        let userMessage = Message(id: UUID(), text: userPrompt, isUser: true)

        // Add user message to conversation and save it immediately
        withAnimation { conversation?.messages.append(userMessage) }
        if let conversation = conversation {
            lmStudioClient.appendMessages([userMessage], toConversationWithID: conversation.id)
        }

        isLoading = true

        do {
            let stream = try await lmStudioClient.sendChatCompletion(
                conversation: conversation?.messages ?? [],
                modelId: selectedModelID,
                topP: settings.topP,
                temperature: settings.temperature,
                maxTokens: settings.maxTokens,
                stream: settings.stream ?? true
            )

            var accumulatedContent = ""
            
            // Temporary message for displaying streaming content without saving yet
            var streamingMessage: Message? = nil

            for try await content in stream {
                accumulatedContent += content

                DispatchQueue.main.async {
                    withAnimation {
                        if let existingMessage = streamingMessage {
                            // Update the message that is already being displayed
                            if let index = conversation?.messages.firstIndex(where: { $0.id == existingMessage.id }) {
                                conversation?.messages[index].text = accumulatedContent
                            }
                        } else {
                            // Create a new message for the first chunk of the response
                            let partialMessage = Message(id: UUID(), text: accumulatedContent, isUser: false)
                            conversation?.messages.append(partialMessage)
                            streamingMessage = partialMessage
                        }
                        scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: streamingMessage!)
                    }
                }
            }

            // Save the complete AI message after streaming has finished
            if var finalMessage = streamingMessage {
                DispatchQueue.main.async {
                    finalMessage.text = accumulatedContent
                    if let conversation = conversation {
                        lmStudioClient.appendMessages([finalMessage], toConversationWithID: conversation.id)
                    }
                    triggerHapticFeedback()
                }
            }

        } catch {
            DispatchQueue.main.async {
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
