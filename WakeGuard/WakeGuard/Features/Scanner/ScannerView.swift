import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var scanner: ScannerViewModel
    @State private var initialMode: ScannerMode

    init(initialMode: ScannerMode = .qrCode) {
        _initialMode = State(initialValue: initialMode)
    }

    var body: some View {
        WakeGuardBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    modePicker
                    cameraCard
                    resultCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Scanner")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            scanner.selectedMode = initialMode
            scanner.refreshPermissionState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Scanner")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(theme.palette.text)

            Text("Architecture is ready for QR scanning, VisionKit, Vision framework, or an external AI recognition service.")
                .font(.body)
                .foregroundStyle(theme.palette.secondaryText)
                .lineSpacing(4)
        }
    }

    private var modePicker: some View {
        Picker("Scanner mode", selection: $scanner.selectedMode) {
            ForEach(ScannerMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var cameraCard: some View {
        WakeCard {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(theme.palette.elevatedSurface.opacity(theme.mode == .dark ? 0.64 : 1))
                        .frame(height: 290)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(theme.palette.divider, lineWidth: 1)
                        }

                    VStack(spacing: 14) {
                        Image(systemName: scanner.selectedMode.systemImage)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                            .symbolEffect(.pulse, options: .repeating, isActive: scanner.isProcessing)

                        Text(scanner.permissionState.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.palette.text)

                        Text(scanner.permissionState.message)
                            .font(.subheadline)
                            .foregroundStyle(theme.palette.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if scanner.isProcessing {
                            ProgressView()
                                .tint(theme.mode == .dark ? theme.palette.primary : theme.palette.secondary)
                        }
                    }
                    .padding()
                }

                scannerActions
            }
        }
    }

    @ViewBuilder
    private var scannerActions: some View {
        switch scanner.permissionState {
        case .notDetermined:
            WakePrimaryButton(title: "Allow Camera", systemImage: "camera.fill") {
                Task {
                    await scanner.requestCameraAccess()
                }
            }
        case .authorized:
            WakePrimaryButton(title: scanner.isProcessing ? "Processing..." : "Run Placeholder Scan", systemImage: "viewfinder") {
                Task {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    await scanner.runPlaceholderScan()
                }
            }
            .disabled(scanner.isProcessing)
            .opacity(scanner.isProcessing ? 0.72 : 1)
        case .denied, .restricted:
            WakeSecondaryButton(title: "Open Settings Later", systemImage: "gearshape.fill") {}
                .disabled(true)
                .opacity(0.65)
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if let result = scanner.result {
            WakeSection("Result") {
                WakeCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: result.mode.systemImage)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(result.needsManualConfirmation ? theme.palette.warning : theme.palette.success)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.label)
                                    .font(.headline)
                                    .foregroundStyle(theme.palette.text)
                                Text("Confidence \(result.confidence.formatted(.percent.precision(.fractionLength(0))))")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.palette.mutedText)
                            }

                            Spacer()
                        }

                        if result.needsManualConfirmation {
                            manualFallback
                        }

                        Button("Reset Scan") {
                            scanner.reset()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private var manualFallback: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What object is this?")
                .font(.headline)
                .foregroundStyle(theme.palette.text)

            TextField("Type object name", text: $scanner.manualObjectName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)

            WakeSecondaryButton(title: "Continue", systemImage: "arrow.right.circle.fill") {
                scanner.confirmManualObjectName()
            }
        }
    }
}
