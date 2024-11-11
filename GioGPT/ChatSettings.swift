//
//  ChatSettings.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import Foundation
import SwiftUI

/// ChatSettings class with modifiable parameters for user preferences
class ChatSettings: ObservableObject {
    @Published var temperature: Double? {
        didSet {
            UserDefaults.standard.set(temperature, forKey: "temperature")
        }
    }
    
    @Published var topP: Double? {
        didSet {
            UserDefaults.standard.set(topP, forKey: "topP")
        }
    }
    
    @Published var maxTokens: Int? {
        didSet {
            UserDefaults.standard.set(maxTokens, forKey: "maxTokens")
        }
    }
    
    @Published var presencePenalty: Double? {
        didSet {
            UserDefaults.standard.set(presencePenalty, forKey: "presencePenalty")
        }
    }
    
    @Published var frequencyPenalty: Double? {
        didSet {
            UserDefaults.standard.set(frequencyPenalty, forKey: "frequencyPenalty")
        }
    }
    
    @Published var repeatPenalty: Double? {
        didSet {
            UserDefaults.standard.set(repeatPenalty, forKey: "repeatPenalty")
        }
    }
    
    @Published var seed: String? {
        didSet {
            UserDefaults.standard.set(seed, forKey: "seed")
        }
    }
    
    @Published var stopSequences: String? {
        didSet {
            UserDefaults.standard.set(stopSequences, forKey: "stopSequences")
        }
    }
    
    @Published var stream: Bool? {
        didSet {
            UserDefaults.standard.set(stream, forKey: "stream")
        }
    }
    
    init() {
        // Initialize with values from UserDefaults, or default if unset
        self.temperature = UserDefaults.standard.object(forKey: "temperature") as? Double ?? 1.0
        self.topP = UserDefaults.standard.object(forKey: "topP") as? Double ?? 1.0
        self.maxTokens = UserDefaults.standard.object(forKey: "maxTokens") as? Int ?? 100
        self.presencePenalty = UserDefaults.standard.object(forKey: "presencePenalty") as? Double ?? 0.0
        self.frequencyPenalty = UserDefaults.standard.object(forKey: "frequencyPenalty") as? Double ?? 0.0
        self.repeatPenalty = UserDefaults.standard.object(forKey: "repeatPenalty") as? Double ?? 1.0
        self.seed = UserDefaults.standard.string(forKey: "seed")
        self.stopSequences = UserDefaults.standard.string(forKey: "stopSequences")
        self.stream = UserDefaults.standard.object(forKey: "stream") as? Bool ?? true
    }
    
    /// Resets all settings to their default values.
    func resetToDefaults() {
        self.temperature = 1.0
        self.topP = 1.0
        self.maxTokens = 100
        self.presencePenalty = 0.0
        self.frequencyPenalty = 0.0
        self.repeatPenalty = 1.0
        self.seed = nil
        self.stopSequences = nil
        self.stream = true
        
        // Update UserDefaults as well
        UserDefaults.standard.set(temperature, forKey: "temperature")
        UserDefaults.standard.set(topP, forKey: "topP")
        UserDefaults.standard.set(maxTokens, forKey: "maxTokens")
        UserDefaults.standard.set(presencePenalty, forKey: "presencePenalty")
        UserDefaults.standard.set(frequencyPenalty, forKey: "frequencyPenalty")
        UserDefaults.standard.set(repeatPenalty, forKey: "repeatPenalty")
        UserDefaults.standard.set(seed, forKey: "seed")
        UserDefaults.standard.set(stopSequences, forKey: "stopSequences")
        UserDefaults.standard.set(stream, forKey: "stream")
    }
}
