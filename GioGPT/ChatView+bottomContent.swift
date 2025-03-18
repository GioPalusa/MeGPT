//
//  ChatView+bottomContent.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2025-03-18.
//

import SwiftUI

extension ChatView {
    @ViewBuilder
    func bottomContent(scrollViewProxy: ScrollViewProxy) -> some View {
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
    }
}
