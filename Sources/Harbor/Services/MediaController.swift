import AppKit
import SwiftUI

enum MediaSource: String {
    case spotify = "Spotify"
    case music = "Música"
    case system = "Sistema"

    var bundleID: String? {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .system: return nil
        }
    }
}

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var source: MediaSource
    var artworkURL: String?
    var timestamp: Date

    var artKey: String { "\(source.rawValue)|\(title)|\(album)|\(artist)" }

    func currentPosition(at date: Date = Date()) -> Double {
        let p = position + (isPlaying ? date.timeIntervalSince(timestamp) : 0)
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }
}

/// Lê o que está tocando (Spotify / Música via AppleScript, demais apps via MediaRemote quando disponível).
final class MediaController: ObservableObject {
    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white

    private let queue = DispatchQueue(label: "harbor.media", qos: .userInitiated)
    private var pollTimer: Timer?
    private var polling = false
    private var lastArtKey: String?
    private let remote = MediaRemoteBridge()
    private var scripts: [String: NSAppleScript] = [:]

    var isPlaying: Bool { info?.isPlaying ?? false }

    func start() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo"] {
            dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
        }
    }

    // MARK: - Commands

    func togglePlayPause() {
        command(script: "playpause", remote: 2)
        if var i = info {
            i.position = i.currentPosition()
            i.timestamp = Date()
            i.isPlaying.toggle()
            info = i
        }
    }

    func next() { command(script: "next track", remote: 4) }
    func previous() { command(script: "previous track", remote: 5) }

    func seek(to seconds: Double) {
        guard var i = info else { return }
        switch i.source {
        case .spotify, .music:
            let app = i.source == .spotify ? "Spotify" : "Music"
            runAsync("tell application \"\(app)\" to set player position to \(String(format: "%.2f", seconds))")
        case .system:
            remote.setElapsed(seconds)
        }
        i.position = seconds
        i.timestamp = Date()
        info = i
    }

    func openSourceApp() {
        guard let id = info?.source.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func command(script: String, remote cmd: Int32) {
        switch info?.source {
        case .spotify?: runAsync("tell application \"Spotify\" to \(script)")
        case .music?: runAsync("tell application \"Music\" to \(script)")
        default: remote.send(cmd)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll() }
    }

    private func runAsync(_ source: String) {
        queue.async {
            var err: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&err)
        }
    }

    // MARK: - Polling

    private func poll() {
        guard !polling else { return }
        polling = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let previousKey = lastArtKey

        queue.async { [weak self] in
            guard let self else { return }
            var candidates: [NowPlaying] = []
            if running.contains("com.spotify.client"), let s = self.fetchSpotify() { candidates.append(s) }
            if running.contains("com.apple.Music"), let m = self.fetchMusic() { candidates.append(m) }

            var result = candidates.first(where: { $0.isPlaying })
            var remoteInfo: (NowPlaying, Data?)?
            if result == nil {
                remoteInfo = self.remote.nowPlaying()
                if let r = remoteInfo, r.0.isPlaying { result = r.0 }
            }
            if result == nil { result = candidates.first ?? remoteInfo?.0 }

            var newArt: NSImage?
            var artChanged = false
            if let r = result, r.artKey != previousKey {
                artChanged = true
                switch r.source {
                case .spotify:
                    if let s = r.artworkURL, let url = URL(string: s), let d = try? Data(contentsOf: url) {
                        newArt = NSImage(data: d)
                    }
                case .music:
                    newArt = self.fetchMusicArtwork()
                case .system:
                    if let d = remoteInfo?.1 { newArt = NSImage(data: d) }
                }
            } else if result == nil, previousKey != nil {
                artChanged = true
            }
            let color = newArt.flatMap { $0.vibrantAverageColor() }

            DispatchQueue.main.async {
                self.polling = false
                if self.info != result { self.info = result }
                if artChanged {
                    self.lastArtKey = result?.artKey
                    self.artwork = newArt
                    self.accent = color.map { Color(nsColor: $0) } ?? .white
                }
            }
        }
    }

    private func script(_ src: String) -> NSAppleEventDescriptor? {
        let s: NSAppleScript
        if let cached = scripts[src] { s = cached } else {
            guard let n = NSAppleScript(source: src) else { return nil }
            var e: NSDictionary?
            n.compileAndReturnError(&e)
            scripts[src] = n
            s = n
        }
        var err: NSDictionary?
        let out = s.executeAndReturnError(&err)
        return err == nil ? out : nil
    }

    private static let sep = "|~|"

    private func fetchSpotify() -> NowPlaying? {
        let src = """
        tell application "Spotify"
            if player state is stopped then return "stopped"
            set t to current track
            return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (artwork url of t) & "|~|" & (duration of t as string) & "|~|" & (player position as string)
        end tell
        """
        guard let s = script(src)?.stringValue, s != "stopped" else { return nil }
        let p = s.components(separatedBy: Self.sep)
        guard p.count >= 7 else { return nil }
        return NowPlaying(title: p[1], artist: p[2], album: p[3],
                          duration: (Self.num(p[5]) ?? 0) / 1000.0,
                          position: Self.num(p[6]) ?? 0,
                          isPlaying: p[0] == "playing", source: .spotify,
                          artworkURL: p[4], timestamp: Date())
    }

    private func fetchMusic() -> NowPlaying? {
        let src = """
        tell application "Music"
            if player state is stopped then return "stopped"
            set t to current track
            return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (duration of t as string) & "|~|" & (player position as string)
        end tell
        """
        guard let s = script(src)?.stringValue, s != "stopped" else { return nil }
        let p = s.components(separatedBy: Self.sep)
        guard p.count >= 6 else { return nil }
        return NowPlaying(title: p[1], artist: p[2], album: p[3],
                          duration: Self.num(p[4]) ?? 0,
                          position: Self.num(p[5]) ?? 0,
                          isPlaying: p[0] == "playing", source: .music,
                          artworkURL: nil, timestamp: Date())
    }

    private func fetchMusicArtwork() -> NSImage? {
        let src = """
        tell application "Music"
            try
                if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track
            end try
        end tell
        return ""
        """
        guard let d = script(src)?.data, !d.isEmpty else { return nil }
        return NSImage(data: d)
    }

    private static func num(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - MediaRemote (framework privado; em versões recentes do macOS pode não retornar dados)

final class MediaRemoteBridge {
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, NSDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var getInfo: GetInfoFn?
    private var sendCommand: SendCommandFn?
    private var setElapsedTime: SetElapsedFn?

    init() {
        let url = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url) else { return }
        if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getInfo = unsafeBitCast(p, to: GetInfoFn.self)
        }
        if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(p, to: SendCommandFn.self)
        }
        if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            setElapsedTime = unsafeBitCast(p, to: SetElapsedFn.self)
        }
    }

    func send(_ cmd: Int32) { _ = sendCommand?(cmd, nil) }
    func setElapsed(_ t: Double) { setElapsedTime?(t) }

    /// Chamada síncrona (com timeout) — usar fora da main thread.
    func nowPlaying() -> (NowPlaying, Data?)? {
        guard let getInfo else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: (NowPlaying, Data?)?
        getInfo(DispatchQueue.global(qos: .userInitiated)) { dict in
            defer { sem.signal() }
            guard let d = dict as? [String: Any],
                  let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else { return }
            let rate = (d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0
            let elapsed = (d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0
            let ts = (d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()
            let np = NowPlaying(title: title,
                                artist: d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                                album: d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                                duration: d["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
                                position: elapsed, isPlaying: rate > 0, source: .system,
                                artworkURL: nil, timestamp: ts)
            result = (np, d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
        }
        _ = sem.wait(timeout: .now() + 0.5)
        return result
    }
}

// MARK: - Cor de destaque da capa

extension NSImage {
    func vibrantAverageColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let c = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.15 { return .white } // capas em preto e branco → branco
        return NSColor(hue: h, saturation: min(1, s * 1.3), brightness: max(0.8, b), alpha: 1)
    }
}
