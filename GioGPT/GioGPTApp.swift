//
//  GioGPTApp.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import SwiftUI
import SwiftData

@main
struct GioGPTApp: App {
    @StateObject private var settings = ChatSettings()
    
    // Initialize the model container directly with each model type
    let modelContainer: ModelContainer = try! ModelContainer(for: Conversation.self, Message.self)
    
    @StateObject private var lmStudioClient: LMStudioApiClient
    
    init() {
        // Initialize `lmStudioClient` with the main context of `modelContainer`
        let apiClient = LMStudioApiClient(baseURL: "http://myaddress.to.lmStudio:1234", context: modelContainer.mainContext)
        _lmStudioClient = StateObject(wrappedValue: apiClient)
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }
            .environmentObject(settings)
            .environmentObject(lmStudioClient)
            .modelContainer(modelContainer) // Provide the container to SwiftUI
        }
    }
}
