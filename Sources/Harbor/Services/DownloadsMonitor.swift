import AppKit

/// Acompanha downloads em andamento na pasta Downloads (Chrome/Edge/Brave, Safari, Firefox).
final class DownloadsMonitor: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String          // caminho do arquivo temporário
        var name: String        // nome final
        var bytes: Int64
        var total: Int64?
        var speed: Double       // bytes/s

        var fraction: Double? {
            guard let total, total > 0 else { return nil }
            return min(1, Double(bytes) / Double(total))
        }
    }

    @Published private(set) var items: [Item] = []

    var onFinished: ((URL) -> Void)?

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private var timer: Timer?
    private var last: [String: (bytes: Int64, at: Date)] = [:]
    private var published: [String: Double] = [:]   // fração publicada via NSProgress (Chrome/Safari)
    private var progressSubscriber: Any?

    var active: Item? { items.max { $0.bytes < $1.bytes } }

    func start() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        subscribeToFileProgress()
        scan()
    }

    /// Navegadores publicam o progresso do arquivo (é o que desenha a barrinha no Finder).
    private func subscribeToFileProgress() {
        progressSubscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let path = progress.fileURL?.path
            let obs = progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                guard let path else { return }
                DispatchQueue.main.async { self?.published[path] = p.fractionCompleted }
            }
            return {
                obs.invalidate()
                if let path { DispatchQueue.main.async { self?.published.removeValue(forKey: path) } }
            }
        }
    }

    private static let partialExtensions = ["crdownload", "download", "part"]

    private func scan() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let now = Date()
        var current: [Item] = []

        for name in names {
            let ext = (name as NSString).pathExtension.lowercased()
            guard Self.partialExtensions.contains(ext) else { continue }
            let url = folder.appendingPathComponent(name)
            let finalName = (name as NSString).deletingPathExtension
            var bytes: Int64 = 0
            var total: Int64?

            if ext == "download" {
                // Safari: pacote com o arquivo parcial + Info.plist com totais
                let info = url.appendingPathComponent("Info.plist")
                if let d = NSDictionary(contentsOf: info) {
                    bytes = (d["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    total = (d["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                }
                if bytes == 0, let inner = try? fm.contentsOfDirectory(atPath: url.path) {
                    for f in inner where f != "Info.plist" {
                        bytes += (try? fm.attributesOfItem(atPath: url.appendingPathComponent(f).path)[.size] as? Int64) ?? 0
                    }
                }
            } else {
                bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            }

            let prev = last[url.path]
            var speed = 0.0
            if let prev, now.timeIntervalSince(prev.at) > 0 {
                speed = max(0, Double(bytes - prev.bytes) / now.timeIntervalSince(prev.at))
            }
            last[url.path] = (bytes, now)

            var item = Item(id: url.path, name: finalName.hasPrefix("Unconfirmed") ? "Download" : finalName,
                            bytes: bytes, total: total, speed: speed)
            // Fração publicada pelo navegador → estima o total
            if item.total == nil, let f = published[url.path], f > 0.001 {
                item.total = Int64(Double(bytes) / f)
            }
            current.append(item)
        }

        // Terminados: sumiram da lista e o arquivo final existe
        let currentIDs = Set(current.map(\.id))
        for old in items where !currentIDs.contains(old.id) {
            last.removeValue(forKey: old.id)
            let finalURL = folder.appendingPathComponent(
                ((old.id as NSString).lastPathComponent as NSString).deletingPathExtension)
            if fm.fileExists(atPath: finalURL.path) { onFinished?(finalURL) }
        }

        if current != items { items = current }
    }

    static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
