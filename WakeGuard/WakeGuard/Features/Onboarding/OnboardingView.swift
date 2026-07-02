import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let highlights: [String]
}

struct OnboardingView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selectedPage = 0
    let onFinished: () -> Void

    private let pages = [
        OnboardingPage(
            title: "Welcome to WakeGuard",
            message: "A smarter alarm companion built for people who need a purposeful first step before an alarm can be dismissed.",
            systemImage: "shield.checkered",
            highlights: ["Autonomous alarm clock", "AI object wake challenge", "Polished iPhone control"]
        ),
        OnboardingPage(
            title: "Bluetooth That Stays Honest",
            message: "WakeGuard searches for your HM-10 clock, connects over BLE, and keeps connection state visible instead of hiding problems.",
            systemImage: "dot.radiowaves.left.and.right",
            highlights: ["Search nearby clocks", "Reconnect from settings", "Clear disconnect state"]
        ),
        OnboardingPage(
            title: "Alarms Sync to Hardware",
            message: "Alarms and timers are designed to live on the clock itself, so the hardware can keep waking you even after the phone disconnects.",
            systemImage: "alarm.waves.left.and.right.fill",
            highlights: ["Local hardware autonomy", "Time synchronization", "No duplicate alarm intent"]
        ),
        OnboardingPage(
            title: "Choose a Wake Object",
            message: "Pick something away from bed that naturally starts your day, like your bathroom sink, toothbrush, coffee maker, or medication.",
            systemImage: "sparkle.magnifyingglass",
            highlights: ["Personalized verification", "Morning-routine objects", "Editable in Settings"]
        ),
        OnboardingPage(
            title: "Permissions With Context",
            message: "Camera access powers object verification and backup-code scanning. Bluetooth access connects to the clock.",
            systemImage: "lock.shield.fill",
            highlights: ["Camera for verification", "Bluetooth for pairing", "Settings remain reversible"]
        ),
        OnboardingPage(
            title: "Ready to Connect",
            message: "Pair your clock next, or use the temporary development bypass to explore the app without pretending Bluetooth is connected.",
            systemImage: "checkmark.seal.fill",
            highlights: ["Search for Clock", "Development skip available", "WakeGuard stays synchronized"]
        )
    ]

    var body: some View {
        WakeGuardBackground {
            VStack(spacing: 26) {
                HStack {
                    WakeGuardLogoMark(size: 54)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("WakeGuard")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.palette.text)
                        Text("Smart alarm companion")
                            .font(.subheadline)
                            .foregroundStyle(theme.palette.mutedText)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $selectedPage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(page: page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    if pages[selectedPage].title == "Choose a Wake Object" {
                        wakeObjectPicker
                    }

                    PageDots(count: pages.count, selectedIndex: selectedPage)

                    WakePrimaryButton(
                        title: selectedPage == pages.count - 1 ? "Continue to Pairing" : "Next",
                        systemImage: selectedPage == pages.count - 1 ? "arrow.right.circle.fill" : "arrow.right"
                    ) {
                        if selectedPage == pages.count - 1 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onFinished()
                        } else {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.smooth(duration: 0.3)) {
                                selectedPage += 1
                            }
                        }
                    }

                    if selectedPage < pages.count - 1 {
                        Button("Skip Intro") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFinished()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.palette.mutedText)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var wakeObjectPicker: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Wake Object", selection: $settingsStore.clockSettings.wakeChallengeObject) {
                    ForEach(WakeChallenge.suggestedObjects, id: \.self) { object in
                        Text(object).tag(object)
                    }
                }
                .pickerStyle(.menu)

                TextField("Custom object", text: $settingsStore.clockSettings.wakeChallengeObject)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .onSubmit {
                        settingsStore.clockSettings.wakeChallengeObject = WakeChallenge.cleanedObjectName(settingsStore.clockSettings.wakeChallengeObject)
                    }
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPageView: View {
    @EnvironmentObject private var theme: ThemeManager
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(theme.mode == .dark ? theme.palette.primary.opacity(0.18) : theme.palette.secondary.opacity(0.12))
                    .frame(width: 190, height: 190)

                Image(systemName: page.systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary, theme.palette.tertiary)
                    .font(.system(size: 76, weight: .semibold))
                    .accessibilityHidden(true)
            }

            WakeCard {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(page.title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(theme.palette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(page.message)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(page.highlights, id: \.self) { highlight in
                            Label(highlight, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(theme.palette.secondaryText)
                                .symbolRenderingMode(.palette)
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
    }
}

private struct PageDots: View {
    @EnvironmentObject private var theme: ThemeManager
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? theme.palette.primary : theme.palette.mutedText.opacity(0.35))
                    .frame(width: index == selectedIndex ? 22 : 8, height: 8)
                    .animation(.smooth(duration: 0.25), value: selectedIndex)
            }
        }
        .accessibilityLabel("Page \(selectedIndex + 1) of \(count)")
    }
}
