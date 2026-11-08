import AppKit
import CoreMedia
import Metal
import MetalPerformanceShaders
import ScreenCaptureKit

/// Captura (via ScreenCaptureKit) o que está atrás da janela do Harbor e entrega uma textura já desfocada,
/// usada pelo shader de refração do Liquid Glass. Só roda enquanto o island está aberto.
final class BackdropCapture: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = BackdropCapture()
    static let blurKey = "glassBlur"

    let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    private lazy var commandQueue: MTLCommandQueue = device.makeCommandQueue()!

    @Published private(set) var permissionGranted = CGPreflightScreenCaptureAccess()
    /// Última textura desfocada (lida pelas views na main thread).
    private(set) var blurred: MTLTexture?
    /// Tamanho, em pontos, da área capturada (= frame da janela).
    private(set) var capturePointSize: CGSize = .zero

    private var stream: SCStream?
    private var starting = false
    private var users = 0
    private var stopWork: DispatchWorkItem?
    private let captureQueue = DispatchQueue(label: "harbor.backdrop", qos: .userInteractive)
    private var textureCache: CVMetalTextureCache?
    private var ring: [MTLTexture] = []
    private var ringIndex = 0
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = -1

    override init() {
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    // MARK: - Ciclo de vida (contagem de usuários)

    func retain() {
        users += 1
        stopWork?.cancel()
        stopWork = nil
        startIfPossible()
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func requestPermission() {
        permissionGranted = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
        if permissionGranted, users > 0 { startIfPossible() }
    }

    private func startIfPossible() {
        permissionGranted = CGPreflightScreenCaptureAccess()
        guard permissionGranted, stream == nil, !starting,
              let panel = NSApp.windows.first(where: { $0 is NotchPanel }),
              let screen = panel.screen ?? NSScreen.main else { return }
        starting = true
        let windowFrame = panel.frame
        let screenFrame = screen.frame
        let scale = screen.backingScaleFactor
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                else { await MainActor.run { self.starting = false }; return }
                // Exclui o próprio Harbor da captura (evita "ver a si mesmo").
                let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: windowFrame.minX - screenFrame.minX,
                                        y: screenFrame.maxY - windowFrame.maxY,
                                        width: windowFrame.width, height: windowFrame.height)
                cfg.width = Int(windowFrame.width * scale)
                cfg.height = Int(windowFrame.height * scale)
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.showsCursor = false
                cfg.queueDepth = 4

                let s = SCStream(filter: filter, configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                try await s.startCapture()
                await MainActor.run {
                    self.capturePointSize = windowFrame.size
                    self.stream = s
                    self.starting = false
                    if self.users == 0 { self.stop() }
                }
            } catch {
                await MainActor.run {
                    self.starting = false
                    self.permissionGranted = CGPreflightScreenCaptureAccess()
                }
            }
        }
    }

    private func stop() {
        guard let s = stream else { return }
        stream = nil
        Task { try? await s.stopCapture() }
        blurred = nil
    }

    // MARK: - SCStreamDelegate / Output

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            if self.stream === stream { self.stream = nil; self.blurred = nil }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sb),
              let cache = textureCache else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .bgra8Unorm, w, h, 0, &cvTexture)
        guard let cvTexture, let source = CVMetalTextureGetTexture(cvTexture),
              let target = nextTarget(width: w, height: h),
              let cb = commandQueue.makeCommandBuffer() else { return }

        // CSS: blur(Npx) → sigma N pontos (em pixels de tela).
        let points = UserDefaults.standard.object(forKey: Self.blurKey) as? Double ?? 12
        let sigma = Float(points) * Float(w) / Float(max(1, capturePointSize.width == 0 ? CGFloat(w) / 2 : capturePointSize.width))
        if sigma > 0.5 {
            if blurKernel == nil || abs(blurSigma - sigma) > 0.01 {
                let k = MPSImageGaussianBlur(device: device, sigma: sigma)
                k.edgeMode = .clamp
                blurKernel = k
                blurSigma = sigma
            }
            blurKernel?.encode(commandBuffer: cb, sourceTexture: source, destinationTexture: target)
        } else if let blit = cb.makeBlitCommandEncoder() {
            blit.copy(from: source, to: target)
            blit.endEncoding()
        }
        cb.addCompletedHandler { [weak self] _ in
            _ = cvTexture // mantém o buffer vivo até o fim da GPU
            DispatchQueue.main.async { self?.blurred = target }
        }
        cb.commit()
    }

    private func nextTarget(width: Int, height: Int) -> MTLTexture? {
        if ring.first.map({ $0.width != width || $0.height != height }) ?? true {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                             mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            ring = (0..<3).compactMap { _ in device.makeTexture(descriptor: d) }
        }
        guard !ring.isEmpty else { return nil }
        ringIndex = (ringIndex + 1) % ring.count
        return ring[ringIndex]
    }
}
