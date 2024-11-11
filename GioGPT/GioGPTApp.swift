//
//  GioGPTApp.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import SwiftUI

@main
struct GioGPTApp: App {
    @StateObject private var settings = ChatSettings()
    @StateObject private var lmStudioClient = LMStudioApiClient(baseURL: "http://palusa.tplinkdns.com:1234")
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }.environmentObject(settings)
            .environmentObject(lmStudioClient)
        }
    }
}
