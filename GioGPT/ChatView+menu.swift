//
//  ChatView+menu.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2025-03-18.
//

import SwiftUI

extension ChatView {
    var menu: some View {
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
