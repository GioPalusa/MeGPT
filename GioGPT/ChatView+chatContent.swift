//
//  ChatView+chatContent.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2025-03-18.
//

import SwiftUI
import Lottie

extension ChatView {
    var chatContent: some View {
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
    }
}
