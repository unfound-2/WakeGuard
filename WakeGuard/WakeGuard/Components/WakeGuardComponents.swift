import SwiftUI

struct WakeGuardBackground<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    theme.palette.background,
                    theme.palette.secondary.opacity(theme.mode == .dark ? 0.42 : 0.08),
                    theme.palette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
        }
    }
}

struct WakeCard<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(theme.palette.surface.opacity(theme.mode == .dark ? 0.82 : 0.94))
                    .shadow(color: Color.black.opacity(theme.mode == .dark ? 0.24 : 0.08), radius: 18, y: 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(theme.palette.divider, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
    }
}

struct WakeSection<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.palette.text)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.mutedText)
                }
            }
            .padding(.horizontal, 2)

            content
        }
    }
}

struct WakePrimaryButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.mode == .dark ? theme.palette.tertiary : Color.white)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityAddTraits(.isButton)
    }
}

struct WakeSecondaryButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.mode == .dark ? theme.palette.tertiary : theme.palette.tertiary)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.palette.elevatedSurface.opacity(theme.mode == .dark ? 0.76 : 1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.palette.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityAddTraits(.isButton)
    }
}

struct StatusPill: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(color)
            .background(color.opacity(theme.mode == .dark ? 0.18 : 0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}

struct WakeGuardLogoMark: View {
    @EnvironmentObject private var theme: ThemeManager
    var size: CGFloat = 74

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(theme.mode == .dark ? theme.palette.secondary : theme.palette.secondary.opacity(0.92))

            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .symbolRenderingMode(.palette)
                .foregroundStyle(theme.palette.primary, theme.palette.tertiary)
                .font(.system(size: size * 0.45, weight: .semibold))
        }
        .frame(width: size, height: size)
        .shadow(color: theme.palette.secondary.opacity(0.24), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

struct MetricTile: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(theme.palette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.palette.mutedText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(theme.palette.elevatedSurface.opacity(theme.mode == .dark ? 0.62 : 1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.palette.divider, lineWidth: 1)
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        WakeCard {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.palette.text)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(theme.palette.mutedText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

extension View {
    func wakeNavigationStyle() -> some View {
        toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

