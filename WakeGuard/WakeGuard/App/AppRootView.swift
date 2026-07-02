import SwiftUI

struct AppRootView: View {
    @AppStorage("wakeguard.hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("wakeguard.hasCompletedInitialPairing") private var hasCompletedInitialPairing = false
    @EnvironmentObject private var bluetoothService: BluetoothClockService

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !hasCompletedInitialPairing && !bluetoothService.developmentBypassPairing {
                PairingView(
                    onConnected: {
                        hasCompletedInitialPairing = true
                    },
                    onSkipForDevelopment: {
                        bluetoothService.developmentBypassPairing = true
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.smooth(duration: 0.35), value: hasSeenOnboarding)
        .animation(.smooth(duration: 0.35), value: hasCompletedInitialPairing)
        .animation(.smooth(duration: 0.35), value: bluetoothService.developmentBypassPairing)
        .onChange(of: bluetoothService.connectedDevice) { _, connectedDevice in
            if connectedDevice != nil {
                hasCompletedInitialPairing = true
            }
        }
    }
}

