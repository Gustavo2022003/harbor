import AVFoundation
import SwiftUI

/// Câmera para o "espelho" no notch. Só liga enquanto a aba está visível.
final class CameraManager: ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var currentDevice: AVCaptureDevice?
    @Published var mirrored: Bool {
        didSet { UserDefaults.standard.set(mirrored, forKey: "camera.mirrored") }
    }

    private let queue = DispatchQueue(label: "harbor.camera", qos: .userInitiated)
    private var wantsRunning = false
    private let disabled = CommandLine.arguments.contains("--snapshot")

    init() {
        mirrored = UserDefaults.standard.object(forKey: "camera.mirrored") as? Bool ?? true
    }

    func start() {
        guard !disabled else { return }
        wantsRunning = true
        refreshDevices()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .authorized
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.status = granted ? .authorized : .denied
                    if granted, self?.wantsRunning == true { self?.run() }
                }
            }
        default:
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        wantsRunning = false
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func select(_ device: AVCaptureDevice) {
        UserDefaults.standard.set(device.uniqueID, forKey: "camera.device")
        currentDevice = device
        if wantsRunning { run() }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        devices = discovery.devices
        let saved = UserDefaults.standard.string(forKey: "camera.device")
        if currentDevice == nil || !devices.contains(where: { $0.uniqueID == currentDevice?.uniqueID }) {
            currentDevice = devices.first(where: { $0.uniqueID == saved })
                ?? devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? devices.first
                ?? AVCaptureDevice.default(for: .video)
        }
    }

    private func run() {
        guard let device = currentDevice else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
            if let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
            guard self.wantsRunning else { return }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }
}

/// Camada de preview da câmera para SwiftUI.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        return v
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
