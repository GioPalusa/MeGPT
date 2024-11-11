//
//  Extensions.swift
//  GioGPT
//
//  Created by Giovanni Palusa on 2024-11-09.
//

import SwiftUI
import CoreHaptics

extension View {
        
    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try? CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptic engine creation error: \(error.localizedDescription)")
        }
    }
    
    func triggerHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ], relativeTime: 0)
            ], parameters: [])
            let engine = try? CHHapticEngine()
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Haptic feedback trigger error: \(error.localizedDescription)")
        }
    }
}
