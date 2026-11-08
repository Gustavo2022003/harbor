import AppKit
import SwiftUI

/// Acompanha sessões do Claude Code via hooks → URL `harbor://claude?d=<json base64url>`.
final class ClaudeActivity: ObservableObject {
    struct Session: Identifiable, Equatable {
        let id: String
        var project: String
        var working: Bool
        var since: Date
    }

    static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757

    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var hooksInstalled = false

    /// Aviso a mostrar no notch (ligado ao AlertCenter pelo controller).
    var onAlert: ((NotchAlert) -> Void)?

    var workingSession: Session? {
        sessions.values.filter(\.working).sorted { $0.since < $1.since }.first
    }

    private let hookDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".harbor")
    private var hookScript: URL { hookDir.appendingPathComponent("claude-hook.sh") }
    private var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private static let events = ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"]

    init() { refreshInstalled() }

    // MARK: - Eventos

    func handle(url: URL) {
        guard url.host == "claude",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var b64 = comps.queryItems?.first(where: { $0.name == "d" })?.value else { return }
        b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["hook_event_name"] as? String else { return }

        let id = json["session_id"] as? String ?? "default"
        let cwd = json["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent

        switch event {
        case "UserPromptSubmit":
            sessions[id] = Session(id: id, project: project, working: true, since: Date())
        case "Stop":
            let elapsed = sessions[id].map { Date().timeIntervalSince($0.since) } ?? 0
            sessions[id]?.working = false
            onAlert?(NotchAlert(icon: "checkmark.seal.fill",
                                title: "\(project) · pronto" + (elapsed > 5 ? " (\(Self.duration(elapsed)))" : ""),
                                tint: Self.claudeColor))
        case "Notification":
            let msg = (json["message"] as? String) ?? "precisa de você"
            let short = msg.lowercased().contains("permission") || msg.lowercased().contains("permiss")
                ? "pede permissão" : "precisa de você"
            onAlert?(NotchAlert(icon: "hand.raised.fill", title: "\(project) \(short)", tint: Self.claudeColor))
        case "SessionEnd":
            sessions.removeValue(forKey: id)
        default:
            break
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 60 ? "\(s / 60)m\(String(format: "%02d", s % 60))s" : "\(s)s"
    }

    // MARK: - Instalação dos hooks (só quando o usuário clica)

    func refreshInstalled() {
        guard let data = try? Data(contentsOf: settingsURL),
              let text = String(data: data, encoding: .utf8) else { hooksInstalled = false; return }
        hooksInstalled = text.contains("claude-hook.sh") && FileManager.default.fileExists(atPath: hookScript.path)
    }

    /// Cria ~/.harbor/claude-hook.sh e adiciona os hooks em ~/.claude/settings.json (com backup).
    func installHooks() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: hookDir, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        # Harbor ⚓︎ — repassa eventos do Claude Code para o notch (não imprime nada).
        d=$(base64 | tr '+/' '-_' | tr -d '=\\n')
        open -g "harbor://claude?d=$d" >/dev/null 2>&1 &
        exit 0
        """
        try script.write(to: hookScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)

        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Harbor", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "settings.json não é um objeto JSON"])
            }
            root = obj
            let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.harbor-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"$HOME/.harbor/claude-hook.sh\""
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let already = groups.contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains("claude-hook.sh") == true }
            }
            if !already {
                groups.append(["hooks": [["type": "command", "command": command]]])
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
        refreshInstalled()
    }

    /// Remove apenas os hooks do Harbor do settings.json.
    func uninstallHooks() throws {
        guard let data = try? Data(contentsOf: settingsURL),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else { refreshInstalled(); return }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { g in
                var g = g
                let inner = (g["hooks"] as? [[String: Any]] ?? [])
                    .filter { ($0["command"] as? String)?.contains("claude-hook.sh") != true }
                if inner.isEmpty { return nil }
                g["hooks"] = inner
                return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
        refreshInstalled()
    }
}
