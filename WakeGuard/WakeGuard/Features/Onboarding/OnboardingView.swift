import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String
    let highlights: [String]
    var showsWakeObjectPicker = false
}

struct OnboardingView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selectedPage = 0
    @State private var isPreparing = false
    let onFinished: () -> Void

    private let pages = [
        OnboardingPage(
            eyebrow: "WakeGuard",
            title: "Wake up with a real first step.",
            message: "WakeGuard is built for people who need more than a bedside button. It pairs with a smart alarm clock and turns waking up into a short, intentional routine.",
            systemImage: "sunrise.fill",
            highlights: ["Designed for hard mornings", "Built around movement", "Made to reduce accidental dismissals"]
        ),
        OnboardingPage(
            eyebrow: "Why it matters",
            title: "Oversleeping is not just a willpower problem.",
            message: "Narcolepsy, severe sleep inertia, medication schedules, and chronic oversleeping can make alarms easy to miss or dismiss before you are fully awake.",
            systemImage: "bed.double.fill",
            highlights: ["Sleeping through alarms", "Waking up confused or groggy", "Turning alarms off on autopilot"]
        ),
        OnboardingPage(
            eyebrow: "How it helps",
            title: "Dismissal requires proof you are up.",
            message: "When a protected alarm rings, WakeGuard asks you to leave bed and verify a real object in your home before the alarm can be dismissed.",
            systemImage: "sparkle.magnifyingglass",
            highlights: ["Choose an object away from bed", "Verify it with AI image recognition", "Build a repeatable morning path"]
        ),
        OnboardingPage(
            eyebrow: "Personalize",
            title: "Choose a wake object.",
            message: "Pick something you naturally interact with in the morning, like a bathroom sink, toothbrush, coffee maker, or medication.",
            systemImage: "viewfinder.circle.fill",
            highlights: ["Editable any time in Settings", "Use an object that starts your routine", "Keep it far enough away to get moving"],
            showsWakeObjectPicker: true
        ),
        OnboardingPage(
            eyebrow: "Setup",
            title: "Then connect your WakeGuard clock.",
            message: "After onboarding, WakeGuard prepares the verification setup and walks you into pairing so alarms, time, and settings can stay synchronized.",
            systemImage: "dot.radiowaves.left.and.right",
            highlights: ["Bluetooth sync for alarms", "Camera access for verification", "Clear progress while setup runs"]
        )
    ]

    var body: some View {
        WakeGuardBackground {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    TabView(selection: $selectedPage) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            OnboardingPageView(page: page)
                                .frame(width: proxy.size.width)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    footer
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                }
                .overlay {
                    if isPreparing {
                        PreparingWakeGuardView()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.28), value: selectedPage)
        .animation(.smooth(duration: 0.22), value: isPreparing)
    }

    private var header: some View {
        HStack(spacing: 14) {
            WakeGuardLogoMark(size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("WakeGuard")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("Step \(selectedPage + 1) of \(pages.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.palette.mutedText)
            }

            Spacer()
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            PageDots(count: pages.count, selectedIndex: selectedPage)

            WakePrimaryButton(
                title: selectedPage == pages.count - 1 ? "Prepare WakeGuard" : "Continue",
                systemImage: selectedPage == pages.count - 1 ? "arrow.right.circle.fill" : "arrow.right"
            ) {
                if selectedPage == pages.count - 1 {
                    prepareAndFinish()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.smooth(duration: 0.32)) {
                        selectedPage += 1
                    }
                }
            }
            .disabled(isPreparing)

            if selectedPage < pages.count - 1 {
                Button("Skip for now") {
                    prepareAndFinish(shortDelay: true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.palette.mutedText)
                .frame(minHeight: 44)
            }
        }
    }

    private func prepareAndFinish(shortDelay: Bool = false) {
        guard !isPreparing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isPreparing = true

        Task {
            try? await Task.sleep(for: .milliseconds(shortDelay ? 450 : 850))
            await MainActor.run {
                onFinished()
            }
        }
    }
}

private struct OnboardingPageView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settingsStore: SettingsStore
    let page: OnboardingPage

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: proxy.size.height < 500 ? 18 : 24) {
                    iconHero(compact: proxy.size.height < 560)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.eyebrow.uppercased())
                            .font(.caption.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                        Text(page.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(theme.palette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(page.message)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.highlights, id: \.self) { highlight in
                            Label(highlight, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(theme.palette.secondaryText)
                                .symbolRenderingMode(.palette)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if page.showsWakeObjectPicker {
                        wakeObjectPicker
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, proxy.size.height < 560 ? 8 : 18)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func iconHero(compact: Bool) -> some View {
        ZStack {
            Circle()
                .fill(theme.mode == .dark ? theme.palette.primary.opacity(0.18) : theme.palette.secondary.opacity(0.12))
                .frame(width: compact ? 112 : 150, height: compact ? 112 : 150)

            Image(systemName: page.systemImage)
                .symbolRenderingMode(.palette)
                .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary, theme.palette.tertiary)
                .font(.system(size: compact ? 48 : 68, weight: .semibold))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
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
                    .frame(width: index == selectedIndex ? 24 : 8, height: 8)
                    .animation(.smooth(duration: 0.25), value: selectedIndex)
            }
        }
        .accessibilityLabel("Page \(selectedIndex + 1) of \(count)")
    }
}

private struct PreparingWakeGuardView: View {
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()

            WakeCard {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                    VStack(spacing: 6) {
                        Text("Preparing WakeGuard")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.palette.text)

                        Text("Setting up your wake challenge and pairing flow.")
                            .font(.subheadline)
                            .foregroundStyle(theme.palette.mutedText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
        }
    }
}
