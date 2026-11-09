import AppKit
import SwiftUI
import os

/// Acompanha sessões do Claude Code via hooks → URL `harbor://claude?d=<json base64url>`.
final class ClaudeActivity: ObservableObject {
    struct Session: Identifiable, Equatable {
        let id: String
        var project: String
        var working: Bool
        var since: Date
        var cwd: String = ""
        /// Pedido enviado ao Claude (UserPromptSubmit).
        var prompt: String = ""
        /// Esperando o usuário (permissão / pergunta).
        var waiting = false
        var transcript: String?
        /// Lido do transcript: ferramenta em uso agora e quantas já rodaram neste pedido.
        var tool: String?
        var toolDetail: String?
        var toolCount = 0
        var lastText: String?
    }

    private static let log = Logger(subsystem: "com.gustavo.harbor", category: "claude")
    static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757

    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var hooksInstalled = false

    /// Aviso a mostrar no notch (ligado ao AlertCenter pelo controller).
    var onAlert: ((NotchAlert) -> Void)?

    var workingSession: Session? {
        sessions.values.filter(\.working).sorted { $0.since < $1.since }.first
    }

    /// Sessões em andamento (trabalhando ou esperando o usuário), mais antigas primeiro.
    var liveSessions: [Session] {
        sessions.values.filter { $0.working || $0.waiting }.sorted { $0.since < $1.since }
    }

    private var transcriptTimer: Timer?
    private let readQueue = DispatchQueue(label: "harbor.claude.transcript", qos: .utility)

    private let hookDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".harbor")
    private var hookScript: URL { hookDir.appendingPathComponent("claude-hook.sh") }
    private var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private static let events = ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"]

    private var appPathFile: URL { hookDir.appendingPathComponent("app-path") }

    init() {
        refreshInstalled()
        claimHook()
    }

    /// Conteúdo do script do hook. Ele entrega o evento ao Harbor que está aberto (caminho em
    /// ~/.harbor/app-path), e não à cópia que o LaunchServices escolher: com várias cópias do app
    /// no disco (build/, /Applications, a do CI) os eventos podiam ir parar num app que abre e fecha.
    private static let script = """
    #!/bin/sh
    # Harbor ⚓︎ — repassa eventos do Claude Code para o notch (não imprime nada).
    d=$(base64 | tr '+/' '-_' | tr -d '=\\n')
    app=$(cat "$HOME/.harbor/app-path" 2>/dev/null)
    if [ -n "$app" ] && [ -d "$app" ]; then
      open -g -a "$app" "harbor://claude?d=$d" >/dev/null 2>&1 &
    else
      open -g "harbor://claude?d=$d" >/dev/null 2>&1 &
    fi
    exit 0
    """

    /// Ao abrir: marca este app como destino dos eventos e atualiza o script se ele for de uma versão antiga.
    private func claimHook() {
        guard !CommandLine.arguments.contains("--snapshot") else { return }
        try? FileManager.default.createDirectory(at: hookDir, withIntermediateDirectories: true)
        try? Bundle.main.bundleURL.path.write(to: appPathFile, atomically: true, encoding: .utf8)
        if hooksInstalled, (try? String(contentsOf: hookScript, encoding: .utf8)) != Self.script {
            try? writeScript()
        }
    }

    private func writeScript() throws {
        try Self.script.write(to: hookScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)
    }

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
        Self.log.notice("evento \(event, privacy: .public) sessão \(id, privacy: .public)")
        let cwd = json["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent

        let transcript = json["transcript_path"] as? String

        switch event {
        case "UserPromptSubmit":
            let prompt = (json["prompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[id] = Session(id: id, project: project, working: true, since: Date(),
                                   cwd: cwd, prompt: prompt, transcript: transcript)
            updateTranscriptPolling()
        case "Stop":
            let elapsed = sessions[id].map { Date().timeIntervalSince($0.since) } ?? 0
            sessions[id]?.working = false
            sessions[id]?.waiting = false
            updateTranscriptPolling()
            onAlert?(NotchAlert(icon: "checkmark.seal.fill",
                                title: "\(project) · pronto" + (elapsed > 5 ? " (\(Self.duration(elapsed)))" : ""),
                                tint: Self.claudeColor))
        case "Notification":
            let msg = (json["message"] as? String) ?? "precisa de você"
            let short = msg.lowercased().contains("permission") || msg.lowercased().contains("permiss")
                ? "pede permissão" : "precisa de você"
            // Só conta como "esperando você" no meio de um pedido (ex.: permissão).
            // O aviso de ociosidade chega depois do Stop e não deve prender um cartão na aba "Agora".
            if sessions[id]?.working == true { sessions[id]?.waiting = true }
            onAlert?(NotchAlert(icon: "hand.raised.fill", title: "\(project) \(short)", tint: Self.claudeColor))
        case "SessionEnd":
            sessions.removeValue(forKey: id)
            updateTranscriptPolling()
        default:
            break
        }
    }

    /// Abre a pasta do projeto no Finder.
    func reveal(_ s: Session) {
        guard !s.cwd.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: s.cwd))
    }

    /// Sessão fictícia para o `--snapshot`.
    func injectDemo() {
        sessions["demo"] = Session(id: "demo", project: "harbor", working: true, since: Date().addingTimeInterval(-94),
                                   cwd: "/tmp", prompt: "Adicione uma aba temporária que mostre o que está em execução no notch",
                                   tool: "Bash", toolDetail: "swift build -c release", toolCount: 7,
                                   lastText: "Compilando para conferir a nova aba…")
    }

    // MARK: - Transcript (o que o Claude está fazendo agora)

    private func updateTranscriptPolling() {
        let needs = sessions.values.contains { $0.working && $0.transcript != nil }
        if needs, transcriptTimer == nil {
            let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.pollTranscripts() }
            RunLoop.main.add(t, forMode: .common)
            transcriptTimer = t
            pollTranscripts()
        } else if !needs {
            transcriptTimer?.invalidate()
            transcriptTimer = nil
        }
    }

    private func pollTranscripts() {
        let targets = sessions.values.filter { $0.working }.compactMap { s in s.transcript.map { (s.id, $0, s.since) } }
        readQueue.async { [weak self] in
            let results = targets.map { ($0.0, Self.readTranscript(path: $0.1, since: $0.2)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, r) in results {
                    guard let r, var s = self.sessions[id], s.working else { continue }
                    s.tool = r.tool; s.toolDetail = r.detail; s.toolCount = r.count; s.lastText = r.text
                    if s != self.sessions[id] { self.sessions[id] = s }
                }
            }
        }
    }

    struct TranscriptInfo { var tool: String?; var detail: String?; var count = 0; var text: String? }

    /// Lê o fim do transcript (JSONL) e acha a última ferramenta usada e o último texto do Claude.
    static func readTranscript(path: String, since: Date) -> TranscriptInfo? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let chunk: UInt64 = 256 * 1024
        try? h.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }

        var info = TranscriptInfo()
        var seen = Set<String>()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"assistant\""),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any], msg["role"] as? String == "assistant",
                  let content = msg["content"] as? [[String: Any]] else { continue }
            if let ts = obj["timestamp"] as? String, let d = iso.date(from: ts), d < since.addingTimeInterval(-2) { break }
            for item in content.reversed() {
                switch item["type"] as? String {
                case "tool_use":
                    let id = item["id"] as? String ?? UUID().uuidString
                    guard seen.insert(id).inserted else { continue }
                    info.count += 1
                    if info.tool == nil {
                        info.tool = item["name"] as? String
                        info.detail = describe(input: item["input"] as? [String: Any])
                    }
                case "text":
                    if info.text == nil, let t = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                        info.text = String(t.prefix(240))
                    }
                default: break
                }
            }
        }
        return info
    }

    private static func describe(input: [String: Any]?) -> String? {
        guard let input else { return nil }
        for key in ["description", "command", "file_path", "pattern", "url", "query", "prompt", "path"] {
            if let v = input[key] as? String, !v.isEmpty {
                let one = v.replacingOccurrences(of: "\n", with: " ")
                return key == "file_path" || key == "path" ? (one as NSString).lastPathComponent : String(one.prefix(160))
            }
        }
        return nil
    }

    /// Nome amigável da ferramenta.
    static func toolLabel(_ name: String?) -> String {
        switch name {
        case "Bash": return "Rodando comando"
        case "Read": return "Lendo"
        case "Edit", "MultiEdit": return "Editando"
        case "Write": return "Escrevendo"
        case "Grep", "Glob": return "Buscando"
        case "WebFetch", "WebSearch": return "Pesquisando na web"
        case "Agent", "Task": return "Subagente"
        case "TodoWrite": return "Planejando"
        case nil: return "Pensando"
        default: return name!.hasPrefix("mcp__") ? "Ferramenta MCP" : name!
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
        try writeScript()
        try? Bundle.main.bundleURL.path.write(to: appPathFile, atomically: true, encoding: .utf8)

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
