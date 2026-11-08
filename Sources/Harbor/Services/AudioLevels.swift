import Accelerate
import AppKit
import CoreMedia
import ScreenCaptureKit

/// Captura o áudio do sistema (ScreenCaptureKit) e calcula bandas de frequência (FFT) para o visualizador real.
final class AudioLevels: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = AudioLevels()
    static let modeKey = "viz.real"

    static let bandCount = 12
    /// Bandas 0...1, da mais grave para a mais aguda.
    @Published private(set) var bands = [Float](repeating: 0, count: AudioLevels.bandCount)
    @Published private(set) var isRunning = false

    private var stream: SCStream?
    private var starting = false
    private let queue = DispatchQueue(label: "harbor.audio", qos: .userInteractive)

    // FFT
    private let fftSize = 1024
    private lazy var log2n = vDSP_Length(log2(Float(fftSize)))
    private lazy var fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private lazy var window: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return w
    }()
    private var ring = [Float]()
    private var smoothed = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var lastPublish = Date.distantPast
    /// Ganho automático: acompanha o pico recente para usar a altura toda mesmo com som baixo.
    private var agcPeak: Float = 0.3

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.modeKey) }

    /// Liga/desliga conforme a música e a preferência.
    func update(musicPlaying: Bool) {
        let want = enabled && musicPlaying && CGPreflightScreenCaptureAccess()
        if want && stream == nil && !starting { start() }
        if !want && stream != nil { stop() }
    }

    private func start() {
        starting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { await MainActor.run { self.starting = false }; return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                cfg.sampleRate = 48_000
                cfg.channelCount = 1
                // Vídeo mínimo (obrigatório), praticamente sem custo
                cfg.width = 2
                cfg.height = 2
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                cfg.queueDepth = 3
                let s = SCStream(filter: filter, configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
                try await s.startCapture()
                await MainActor.run {
                    self.stream = s
                    self.starting = false
                    self.isRunning = true
                }
            } catch {
                await MainActor.run { self.starting = false }
            }
        }
    }

    private func stop() {
        guard let s = stream else { return }
        stream = nil
        isRunning = false
        Task { try? await s.stopCapture() }
        bands = [Float](repeating: 0, count: Self.bandCount)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            if self.stream === stream { self.stream = nil; self.isRunning = false }
        }
    }

    // MARK: - Processamento

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid else { return }
        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: nil, bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = abl.mBuffers.mData else { return }
        let count = Int(abl.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
        ring.append(contentsOf: samples)
        if ring.count > fftSize * 2 { ring.removeFirst(ring.count - fftSize) }
        guard ring.count >= fftSize else { return }
        analyze(Array(ring.suffix(fftSize)))
    }

    private func analyze(_ input: [Float]) {
        guard let fft else { return }
        var x = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(input, 1, window, 1, &x, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }

        // Bandas logarítmicas de ~60 Hz a ~16 kHz
        let nyquist: Float = 24_000
        let lo: Float = 60, hi: Float = 16_000
        var out = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let f0 = lo * pow(hi / lo, Float(b) / Float(Self.bandCount))
            let f1 = lo * pow(hi / lo, Float(b + 1) / Float(Self.bandCount))
            let i0 = max(1, Int(f0 / nyquist * Float(half)))
            let i1 = min(half - 1, max(i0 + 1, Int(f1 / nyquist * Float(half))))
            var peak: Float = 0
            for i in i0..<i1 { peak = max(peak, mags[i]) }
            // magnitude → dB → 0...1
            let db = 20 * log10(max(peak / Float(fftSize), 1e-7))
            // mais sensível: faixa de 45 dB começando em -72 dB; graves com leve reforço
            let tilt: Float = 1.15 - 0.3 * Float(b) / Float(Self.bandCount - 1)
            let norm = min(1, max(0, (db + 72) / 45)) * tilt
            // ataque quase instantâneo, queda rápida (mais "dançante")
            smoothed[b] = norm > smoothed[b] ? smoothed[b] * 0.1 + norm * 0.9 : smoothed[b] * 0.68 + norm * 0.32
            out[b] = smoothed[b]
        }
        // ganho automático
        agcPeak = max(agcPeak * 0.996, out.max() ?? 0, 0.25)
        out = out.map { min(1, $0 / agcPeak) }

        let now = Date()
        guard now.timeIntervalSince(lastPublish) > 1.0 / 60.0 else { return }
        lastPublish = now
        DispatchQueue.main.async { self.bands = out }
    }
}
