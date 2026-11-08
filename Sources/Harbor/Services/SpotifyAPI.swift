import AppKit
import CryptoKit
import Network
import Security

/// Integração com a Web API do Spotify (fila e "curtir"). Login OAuth com PKCE —
/// o usuário cria um app em developer.spotify.com e informa o Client ID.
final class SpotifyAPI: ObservableObject {
    struct Track: Identifiable, Equatable {
        let id: String
        let name: String
        let artist: String
        let artworkURL: URL?
    }

    static let redirectURI = "http://127.0.0.1:47878/callback"
    static let clientIDKey = "spotify.clientID"
    private static let scopes = "user-read-playback-state user-read-currently-playing user-library-read user-library-modify user-modify-playback-state"

    @Published private(set) var connected = false
    @Published private(set) var queue: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var isLiked = false
    @Published private(set) var error: String?

    private var accessToken: String?
    private var tokenExpiry = Date.distantPast
    private var verifier = ""
    private var listener: NWListener?
    private let keychainService = "Harbor.Spotify"

    var clientID: String { UserDefaults.standard.string(forKey: Self.clientIDKey)?.trimmingCharacters(in: .whitespaces) ?? "" }

    init() {
        connected = readRefreshToken() != nil
    }

    // MARK: - Login (PKCE + servidor local de callback)

    func connect() {
        guard !clientID.isEmpty else { error = "Informe o Client ID"; return }
        error = nil
        verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        guard startCallbackServer() else { error = "Porta 47878 ocupada"; return }
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes),
        ]
        NSWorkspace.shared.open(c.url!)
    }

    func disconnect() {
        deleteRefreshToken()
        accessToken = nil
        connected = false
        queue = []
        current = nil
        isLiked = false
    }

    private func startCallbackServer() -> Bool {
        listener?.cancel()
        guard let l = try? NWListener(using: .tcp, on: 47878) else { return false }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let code = URLComponents(string: "http://x" + path)?.queryItems?.first { $0.name == "code" }?.value
                let ok = code != nil
                let html = """
                <html><body style="font-family:-apple-system;background:#111;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh">
                <h2>\(ok ? "⚓️ Harbor conectado ao Spotify — pode fechar esta aba." : "Não foi possível conectar.")</h2></body></html>
                """
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                if let code {
                    self?.listener?.cancel()
                    self?.listener = nil
                    self?.exchange(code: code)
                }
            }
        }
        l.start(queue: .main)
        listener = l
        return true
    }

    private func exchange(code: String) {
        tokenRequest([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "client_id": clientID, "code_verifier": verifier,
        ])
    }

    private func tokenRequest(_ params: [String: String], completion: (() -> Void)? = nil) {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self else { return }
                if let token = json?["access_token"] as? String {
                    self.accessToken = token
                    self.tokenExpiry = Date().addingTimeInterval(Double(json?["expires_in"] as? Int ?? 3600) - 60)
                    if let refresh = json?["refresh_token"] as? String { self.saveRefreshToken(refresh) }
                    self.connected = true
                    self.error = nil
                    completion?()
                } else {
                    self.error = (json?["error_description"] as? String) ?? "Falha no login do Spotify"
                    if (json?["error"] as? String) == "invalid_grant" { self.disconnect() }
                }
            }
        }.resume()
    }

    private func withToken(_ action: @escaping (String) -> Void) {
        if let t = accessToken, Date() < tokenExpiry { action(t); return }
        guard let refresh = readRefreshToken(), !clientID.isEmpty else { connected = false; return }
        tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID]) { [weak self] in
            if let t = self?.accessToken { action(t) }
        }
    }

    // MARK: - API

    private func call(_ method: String, _ path: String, completion: ((Any?, Int) -> Void)? = nil) {
        withToken { token in
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if method != "GET" { req.setValue("0", forHTTPHeaderField: "Content-Length") }
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                DispatchQueue.main.async { completion?(json, status) }
            }.resume()
        }
    }

    /// Atualiza a fila e se a música atual está curtida.
    func refresh() {
        guard connected else { return }
        call("GET", "/me/player/queue") { [weak self] json, status in
            guard let self else { return }
            guard status == 200, let d = json as? [String: Any] else {
                if status == 403 { self.error = "Sem acesso — confira os escopos/usuários do app no Spotify" }
                return
            }
            self.current = (d["currently_playing"] as? [String: Any]).flatMap(Self.track)
            self.queue = ((d["queue"] as? [[String: Any]]) ?? []).compactMap(Self.track).prefix(8).map { $0 }
            self.error = nil
            if let id = self.current?.id {
                self.call("GET", "/me/tracks/contains?ids=\(id)") { json, _ in
                    self.isLiked = (json as? [Bool])?.first ?? false
                }
            }
        }
    }

    func toggleLike() {
        guard let id = current?.id else { return }
        let liked = isLiked
        isLiked.toggle() // otimista
        call(liked ? "DELETE" : "PUT", "/me/tracks?ids=\(id)") { [weak self] _, status in
            if !(200..<300).contains(status) { self?.isLiked = liked }
        }
    }

    /// Pula até uma música da fila (avança N faixas).
    func skip(to track: Track) {
        guard let idx = queue.firstIndex(of: track) else { return }
        func next(_ n: Int) {
            guard n > 0 else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }; return }
            call("POST", "/me/player/next") { _, _ in next(n - 1) }
        }
        next(idx + 1)
    }

    private static func track(_ d: [String: Any]) -> Track? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        let artists = (d["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
            ?? ((d["show"] as? [String: Any])?["name"] as? String ?? "")
        let images = ((d["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? (d["images"] as? [[String: Any]]) ?? []
        let art = (images.last?["url"] as? String).flatMap(URL.init(string:))
        return Track(id: id, name: name, artist: artists, artworkURL: art)
    }

    // MARK: - Keychain

    private func saveRefreshToken(_ token: String) {
        deleteRefreshToken()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: keychainService,
                                kSecAttrAccount as String: "refresh_token",
                                kSecValueData as String: Data(token.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    private func readRefreshToken() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: keychainService,
                                kSecAttrAccount as String: "refresh_token",
                                kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func deleteRefreshToken() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: keychainService,
                                kSecAttrAccount as String: "refresh_token"]
        SecItemDelete(q as CFDictionary)
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
