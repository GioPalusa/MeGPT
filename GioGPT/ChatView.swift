import CoreHaptics
import SwiftData
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var settings: ChatSettings
    @EnvironmentObject var lmStudioClient: LMStudioApiClient
    @Environment(\.modelContext) var context
    @State var prompt = ""
    @State var isLoading = false
    @State var isShowingSettings = false
    @State var isInitialAppear = true
    @State var isKeyboardVisible = false
    @State var generationTask: Task<Void, Never>? = nil
    @Environment(\.colorScheme) var colorScheme

    @Query(sort: \Conversation.lastUsed, order: .reverse) var savedConversations: [Conversation]

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    chatContent
                        .padding()
                        .onChange(of: prompt) { _, _ in
                            if let lastMessage = lmStudioClient.currentConversation?.messages.last {
                                scrollToLastMessage(scrollViewProxy: scrollViewProxy, lastMessage: lastMessage)
                            }
                        }
                }
                bottomContent(scrollViewProxy: scrollViewProxy)
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
                prepareStart()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                menu
            }
        }
        .navigationDestination(isPresented: $isShowingSettings) {
            SettingsView(lmStudioClient: lmStudioClient)
        }
    }

    

    func scrollToLastMessage(scrollViewProxy: ScrollViewProxy, lastMessage: Message) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
