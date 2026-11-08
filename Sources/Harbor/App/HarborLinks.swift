import AppKit

/// Endereços oficiais do Harbor (repositório, feedback, manual).
enum HarborLinks {
    static let repo = URL(string: "https://github.com/Gustavo2022003/harbor")!
    static let feedback = URL(string: "https://github.com/Gustavo2022003/harbor/issues/new?template=feedback.yml")!
    static let bug = URL(string: "https://github.com/Gustavo2022003/harbor/issues/new?template=bug.yml")!
    static let manual = URL(string: "https://github.com/Gustavo2022003/harbor/blob/main/docs/manual/Harbor-Manual.pdf")!
    static let releases = URL(string: "https://github.com/Gustavo2022003/harbor/releases")!

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    /// Link de bug já com a versão do app e do macOS preenchidas.
    static var bugWithContext: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var c = URLComponents(url: bug, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [
            URLQueryItem(name: "version", value: "\(version) (\(build))"),
            URLQueryItem(name: "macos", value: os),
        ]
        return c.url ?? bug
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
