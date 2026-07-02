import AVFoundation
import Combine
import Foundation

enum CameraPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var title: String {
        switch self {
        case .notDetermined: "Camera Permission Needed"
        case .authorized: "Camera Ready"
        case .denied: "Camera Access Denied"
        case .restricted: "Camera Restricted"
        }
    }

    var message: String {
        switch self {
        case .notDetermined:
            return "WakeGuard needs camera access to scan QR codes and prepare future object recognition."
        case .authorized:
            return "Point the camera at a QR code or object when scanner support is connected."
        case .denied:
            return "Enable camera access in Settings to use scanner workflows."
        case .restricted:
            return "Camera access is restricted on this device."
        }
    }
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var permissionState: CameraPermissionState = .notDetermined
    @Published var selectedMode: ScannerMode = .qrCode
    @Published var isProcessing = false
    @Published var result: RecognitionResult?
    @Published var manualObjectName = ""

    init() {
        refreshPermissionState()
    }

    func refreshPermissionState() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            permissionState = .notDetermined
        case .authorized:
            permissionState = .authorized
        case .denied:
            permissionState = .denied
        case .restricted:
            permissionState = .restricted
        @unknown default:
            permissionState = .restricted
        }
    }

    func requestCameraAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionState = granted ? .authorized : .denied
    }

    func runPlaceholderScan() async {
        guard permissionState == .authorized else {
            return
        }

        result = nil
        isProcessing = true
        try? await Task.sleep(for: .milliseconds(1100))

        switch selectedMode {
        case .qrCode:
            result = RecognitionResult(
                mode: .qrCode,
                label: "WakeGuard QR placeholder",
                confidence: 0.96,
                needsManualConfirmation: false
            )
        case .objectRecognition:
            result = RecognitionResult(
                mode: .objectRecognition,
                label: "Uncertain object",
                confidence: 0.42,
                needsManualConfirmation: true
            )
        }

        isProcessing = false
    }

    func confirmManualObjectName() {
        let trimmedName = manualObjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        result = RecognitionResult(
            mode: .objectRecognition,
            label: trimmedName,
            confidence: 1,
            needsManualConfirmation: false
        )
        manualObjectName = ""
    }

    func reset() {
        result = nil
        isProcessing = false
        manualObjectName = ""
    }
}
