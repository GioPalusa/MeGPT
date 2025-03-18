import CoreHaptics
import Lottie
import SwiftData
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var settings: ChatSettings
    @EnvironmentObject var lmStudioClient: LMStudioApiClient
    @Environment(\.modelContext) private var context
    @State private var prompt = ""
    @State private var isLoading = false
    @State private var isShowingSettings = false
    @State private var isInitialAppear = true
    @State private var isKeyboardVisible = false
    @State private var generationTask: Task<Void, Never>? = nil
    @Environment(\.colorScheme) var colorScheme

    @Query(sort: \Conversation.lastUsed, order: .reverse) private var savedConversations: [Conversation]

    var body: some View {
        NavigationStack {
            VStack {
                ScrollViewReader { scrollViewProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let messages = lmStudioClient.currentConversation?.messages, !messages.isEmpty {
                                ForEach(messages.sorted(by: { $0.timestamp < $1.timestamp }), id: \.id) { message in
                                    HStack {
                                        if message.isUser {
                                            Spacer()

                                            Text(LocalizedStringKey(message.text))
                                                .textSelection(.enabled)
                                                .padding(10)
                                                .background(settings.userBubbleColor)
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                        } else {
                                            if message.text.starts(with: "[Reasoning]:") {
                                                DisclosureGroup("Reasoning") {
                                                    // Remove the prefix before displaying the text inside the disclosure group
                                                    Text(LocalizedStringKey(message.text.replacingOccurrences(of: "[Reasoning]: ", with: "")))
                                                        .font(.footnote)
                                                        .italic()
                                                        .foregroundColor(.gray)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            } else {
                                                if settings.showAIBubble {
                                                    Text(LocalizedStringKey(message.text))
                                                        .padding(10)
                                                        .background(settings.aiBubbleColor)
                                                        .cornerRadius(8)
                                                        .foregroundColor(.primary)
                                                } else {
                                                    Text(LocalizedStringKey(message.text))
                                                        .textSelection(.enabled)
                                                }
                                            }
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

                            if let errorMessage = lmStudioClient.errorMessage {
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
                                LottieView(animation: .named("generation"))
                                    .looping()
                                    .resizable()
                                    .frame(height: 40)
                            }
                        }
                        .padding()
                        .onChange(of: prompt) { _, _ in
                            if let lastMessage = lmStudioClient.currentConversation?.messages.last {
                                scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                            }
                        }
                    }
                    .simultaneousGesture(DragGesture().onChanged { _ in hideKeyboard() })

                    // Text input and action button
                    HStack {
                        TextField("What do you need?", text: $prompt)
                            .padding()
                            .submitLabel(.send)
                            .onSubmit {
                                if !isLoading {
                                    generationTask = Task {
                                        await sendMessage(scrollViewProxy: scrollViewProxy)
                                    }
                                }
                            }
                            .disabled(isLoading) // Disable text field during generation
                            .background(.clear)
                            .cornerRadius(8)
                        
                        if isLoading {
                            // Show a stop button when generation is in progress
                            Button(action: {
                                generationTask?.cancel()
                                isLoading = false
                            }) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Show the send button when not generating
                            Button(action: {
                                generationTask = Task {
                                    await sendMessage(scrollViewProxy: scrollViewProxy)
                                }
                            }) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(prompt.isEmpty ? Color.gray : .primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(prompt.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        isKeyboardVisible = true
                        if let lastMessage = lmStudioClient.currentConversation?.messages.last {
                            scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        isKeyboardVisible = false
                    }
                }
            }
            .gesture(TapGesture().onEnded { hideKeyboard() })
            .navigationTitle(lmStudioClient.currentConversation?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isInitialAppear {
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
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(lmStudioClient: lmStudioClient)
            }
        }
    }

    private func sendMessage(scrollViewProxy: ScrollViewProxy) async {
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
                        if Task.isCancelled { break }  // Check for cancellation
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
                    if Task.isCancelled { break }  // Check for cancellation
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

    private func scrollToLastMessage(scrollViewProxy: ScrollViewProxy, lastMessage: Message) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
