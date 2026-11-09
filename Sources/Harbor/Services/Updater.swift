import AppKit
import Combine
import Security
import SwiftUI

/// Compara a versão do app com a última release do GitHub e, se houver uma mais nova,
/// baixa o .zip, confere a assinatura (tem que ser do mesmo certificado do app atual)
/// e troca o app antigo pelo novo, reabrindo em seguida.
///
/// O repositório é privado, então a consulta usa o `gh` CLI (já autenticado para a aba PRs).
/// Sem `gh`, tenta a API pública (funciona se o repositório for público).
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)          // versão
        case downloading
        case installing
        case failed(String)
    }

    struct Release: Equatable {
        var version: String
        var tag: String
        var notes: String
        var zipName: String?
        var zipURL: URL?                 // só na API pública
        var page: URL?
    }

    static let repo = "Gustavo2022003/harbor"
    static let autoCheckKey = "update.autoCheck"
    private static let notifiedKey = "update.notifiedVersion"

    @Published private(set) var state: State = .idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastCheck: Date?

    var onAlert: ((NotchAlert) -> Void)?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "harbor.updater", qos: .utility)

    var current: String { HarborLinks.version }
    var isBusy: Bool { [.checking, .downloading, .installing].contains(state) }

    func start() {
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
        guard !CommandLine.arguments.contains("--snapshot") else { return }
        // Teste de ponta a ponta: procura e, se houver versão nova, instala sem clique.
        if CommandLine.arguments.contains("--update-now") {
            check()
            var cancel: AnyCancellable?
            cancel = $state.sink { [weak self] st in
                if case .available = st { DispatchQueue.main.async { self?.install(); cancel?.cancel() } }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.autoCheck() }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.autoCheck() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func autoCheck() {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        check(silent: true)
    }

    // MARK: - Verificar

    func check(silent: Bool = false) {
        guard !isBusy else { return }
        state = .checking
        queue.async { [weak self] in
            let result = Self.fetchLatest()
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastCheck = Date()
                switch result {
                case .failure(let e):
                    self.state = silent ? .idle : .failed(e.localizedDescription)
                case .success(let r):
                    self.latest = r
                    if Self.compare(r.version, self.current) > 0 {
                        self.state = .available(r.version)
                        let d = UserDefaults.standard
                        if d.string(forKey: Self.notifiedKey) != r.version {
                            d.set(r.version, forKey: Self.notifiedKey)
                            self.onAlert?(NotchAlert(icon: "arrow.down.app.fill",
                                                     title: "Harbor \(r.version) disponível",
                                                     tint: Theme.orange))
                        }
                    } else {
                        self.state = .upToDate
                    }
                }
            }
        }
    }

    /// -1, 0, 1 comparando "2.10.0" com "2.9.1" numericamente.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return 0
    }

    private static func fetchLatest() -> Result<Release, Error> {
        if let gh = GitHubStatus.ghPath {
            let r = run(gh, ["release", "view", "--repo", repo, "--json", "tagName,body,assets,url"])
            if case .success(let data) = r,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = obj["tagName"] as? String {
                let assets = obj["assets"] as? [[String: Any]] ?? []
                let zip = assets.compactMap { $0["name"] as? String }.first { $0.hasSuffix(".zip") }
                return .success(Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")),
                                        tag: tag, notes: obj["body"] as? String ?? "", zipName: zip,
                                        page: (obj["url"] as? String).flatMap(URL.init(string:))))
            }
        }
        // API pública (sem autenticação)
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failure(err("URL inválida"))
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Harbor-Updater", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var out: Result<Release, Error> = .failure(err("Sem resposta do GitHub"))
        URLSession.shared.dataTask(with: req) { data, resp, e in
            defer { sem.signal() }
            if let e { out = .failure(e); return }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                out = .failure(err(GitHubStatus.ghPath == nil
                    ? "Instale e autentique o GitHub CLI (brew install gh && gh auth login) para buscar atualizações do repositório privado."
                    : "Não foi possível ler a última release. Rode `gh auth status` no Terminal."))
                return
            }
            let assets = obj["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            out = .success(Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")), tag: tag,
                                   notes: obj["body"] as? String ?? "", zipName: zip?["name"] as? String,
                                   zipURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                                   page: (obj["html_url"] as? String).flatMap(URL.init(string:))))
        }.resume()
        sem.wait()
        return out
    }

    // MARK: - Atualizar

    func install() {
        guard let r = latest, !isBusy else { return }
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("Sem permissão para escrever em \(parent.path).")
            return
        }
        state = .downloading
        queue.async { [weak self] in
            let result = Self.downloadAndVerify(r)
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let e): self.state = .failed(e.localizedDescription)
                case .success(let newApp):
                    self.state = .installing
                    self.swap(old: target, new: newApp)
                }
            }
        }
    }

    private static func downloadAndVerify(_ r: Release) -> Result<URL, Error> {
        let fm = FileManager.default
        let work = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.gustavo.harbor/update-\(r.version)")
        try? fm.removeItem(at: work)
        do { try fm.createDirectory(at: work, withIntermediateDirectories: true) } catch { return .failure(error) }

        // 1. Baixa o .zip
        var zip: URL?
        if let gh = GitHubStatus.ghPath, let name = r.zipName {
            if case .failure(let e) = run(gh, ["release", "download", r.tag, "--repo", repo,
                                               "--pattern", name, "--dir", work.path, "--clobber"]) {
                return .failure(e)
            }
            zip = work.appendingPathComponent(name)
        } else if let url = r.zipURL {
            let sem = DispatchSemaphore(value: 0)
            var failure: Error?
            URLSession.shared.downloadTask(with: url) { tmp, _, e in
                defer { sem.signal() }
                guard let tmp else { failure = e ?? err("Falha no download"); return }
                let dest = work.appendingPathComponent(url.lastPathComponent)
                do { try fm.moveItem(at: tmp, to: dest); zip = dest } catch { failure = error }
            }.resume()
            sem.wait()
            if let failure { return .failure(failure) }
        }
        guard let zip, fm.fileExists(atPath: zip.path) else { return .failure(err("A release não tem o .zip do app.")) }

        // 2. Extrai
        let out = work.appendingPathComponent("app")
        if case .failure(let e) = run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]) { return .failure(e) }
        guard let app = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else {
            return .failure(err("O .zip não contém um .app."))
        }

        // 3. Confere a versão e a assinatura (mesmo certificado do app que está rodando)
        let newVersion = Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard compare(newVersion, r.version) == 0 else {
            return .failure(err("O app baixado é v\(newVersion), esperado v\(r.version)."))
        }
        if let msg = verifySignature(app) { return .failure(err(msg)) }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return .success(app)
    }

    /// nil se o app novo foi assinado pelo mesmo certificado do app atual.
    private static func verifySignature(_ app: URL) -> String? {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement else {
            return "Não foi possível ler a assinatura deste app."
        }
        var newStatic: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newStatic) == errSecSuccess, let newStatic else {
            return "O app baixado não está assinado."
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(newStatic, flags, requirement)
        return status == errSecSuccess ? nil
            : "A assinatura do app baixado não confere com a deste app (\(status)). Atualização cancelada."
    }

    /// Script que espera o Harbor fechar, troca o app e abre o novo. Se a troca falhar, devolve o antigo.
    private func swap(old: URL, new: URL) {
        let backup = old.path + ".old-update"
        let script = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(backup)"
        if mv "\(old.path)" "\(backup)" && mv "\(new.path)" "\(old.path)"; then
          rm -rf "\(backup)"
        else
          [ -d "\(backup)" ] && [ ! -d "\(old.path)" ] && mv "\(backup)" "\(old.path)"
        fi
        LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
        [ -x "$LSREG" ] && "$LSREG" -f "\(old.path)"
        open "\(old.path)"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-update.sh")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [url.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
        } catch {
            state = .failed("Não foi possível iniciar a troca: \(error.localizedDescription)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    // MARK: - Utilitários

    private static func run(_ path: String, _ args: [String]) -> Result<Data, Error> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), errPipe = Pipe()
        p.standardOutput = out
        p.standardError = errPipe
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let e = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: e, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .failure(err(msg.isEmpty ? "\((path as NSString).lastPathComponent) falhou" : msg))
            }
            return .success(data)
        } catch {
            return .failure(error)
        }
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "Harbor.Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
