import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                AlarmsView()
            }
            .tabItem {
                Label("Alarms", systemImage: "alarm.fill")
            }

            NavigationStack {
                ClockView()
            }
            .tabItem {
                Label("Clock", systemImage: "deskclock.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
    }
}

