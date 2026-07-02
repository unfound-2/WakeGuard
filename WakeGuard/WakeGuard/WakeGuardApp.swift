//
//  WakeGuardApp.swift
//  WakeGuard
//
//  Created by Nameless on 7/2/26.
//

import SwiftUI

@main
struct WakeGuardApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var scannerViewModel = ScannerViewModel()
    @StateObject private var bluetoothService = BluetoothClockService()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(themeManager)
                .environmentObject(alarmStore)
                .environmentObject(settingsStore)
                .environmentObject(scannerViewModel)
                .environmentObject(bluetoothService)
                .preferredColorScheme(themeManager.mode.colorScheme)
        }
    }
}
