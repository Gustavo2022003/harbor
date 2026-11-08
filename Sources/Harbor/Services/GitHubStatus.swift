import AppKit
import SwiftUI

/// Status dos seus PRs (checks de CI e revisões) e PRs aguardando sua revisão, via `gh` CLI.
final class GitHubStatus: ObservableObject {
    enum Checks: String { case success = "SUCCESS", failure = "FAILURE", error = "ERROR",
                               pending = "PENDING", expected = "EXPECTED" }
    enum Review: String { case approved = "APPROVED", changes = "CHANGES_REQUESTED", required = "REVIEW_REQUIRED" }

    struct PR: Identifiable, Equatable {
        let url: String
        let number: Int
        let title: String
        let repo: String
        let author: String
        let isDraft: Bool
        let checks: Checks?
        let review: Review?
        let updatedAt: Date
        var id: String { url }
        var short: String { "\(repo.split(separator: "/").last ?? "")#\(number)" }
    }

    static let alertsKey = "github.alerts"

    @Published private(set) var mine: [PR] = []
    @Published private(set) var toReview: [PR] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    var onAlert: ((NotchAlert) -> Void)?

    private var timer: Timer?
    private var firstLoad = true
    private let queue = DispatchQueue(label: "harbor.github", qos: .utility)

    static let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    var pendingCount: Int { mine.filter { $0.checks == .pending || $0.checks == .expected }.count }

    func start() {
        UserDefaults.standard.register(defaults: [Self.alertsKey: true])
        refresh()
        let t = Timer(timeInterval: 90, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func open(_ pr: PR) {
        if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) }
    }

    func refresh() {
        guard !loading else { return }
        guard let gh = Self.ghPath else {
            error = "GitHub CLI não encontrado. Instale com: brew install gh && gh auth login"
            return
        }
        loading = true
        queue.async { [weak self] in
            let result = Self.run(gh, ["api", "graphql", "-f", "query=\(Self.query)"])
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    // MARK: - Consulta

    private static let query = """
    query {
      viewer {
        pullRequests(first: 25, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { ...pr } }
      }
      search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 15) {
        nodes { ... on PullRequest { ...pr } }
      }
    }
    fragment pr on PullRequest {
      number title url isDraft reviewDecision updatedAt
      repository { nameWithOwner }
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    private static func run(_ path: String, _ args: [String]) -> Result<Data, Error> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(NSError(domain: "gh", code: Int(p.terminationStatus),
                                        userInfo: [NSLocalizedDescriptionKey: msg?.isEmpty == false ? msg! : "Falha no gh"]))
            }
            return .success(data)
        } catch {
            return .failure(error)
        }
    }

    private static func parse(_ node: [String: Any]) -> PR? {
        guard let url = node["url"] as? String, let number = node["number"] as? Int else { return nil }
        let commit = ((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any]
        let state = (commit?["statusCheckRollup"] as? [String: Any])?["state"] as? String
        let iso = ISO8601DateFormatter()
        return PR(url: url, number: number,
                  title: node["title"] as? String ?? "",
                  repo: (node["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? "",
                  author: (node["author"] as? [String: Any])?["login"] as? String ?? "",
                  isDraft: node["isDraft"] as? Bool ?? false,
                  checks: state.flatMap(Checks.init(rawValue:)),
                  review: (node["reviewDecision"] as? String).flatMap(Review.init(rawValue:)),
                  updatedAt: (node["updatedAt"] as? String).flatMap(iso.date(from:)) ?? Date())
    }

    private func apply(_ result: Result<Data, Error>) {
        loading = false
        switch result {
        case .failure(let e):
            error = e.localizedDescription
        case .success(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any] else {
                error = "Resposta inesperada do GitHub"
                return
            }
            let mineNodes = ((d["viewer"] as? [String: Any])?["pullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            let reviewNodes = (d["search"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            let newMine = mineNodes.compactMap(Self.parse)
            let newReview = reviewNodes.compactMap(Self.parse)
            if !firstLoad && UserDefaults.standard.bool(forKey: Self.alertsKey) {
                diff(oldMine: mine, newMine: newMine, oldReview: toReview, newReview: newReview)
            }
            firstLoad = false
            mine = newMine
            toReview = newReview
            error = nil
            lastUpdate = Date()
        }
    }

    /// Gera avisos quando algo muda entre duas consultas.
    private func diff(oldMine: [PR], newMine: [PR], oldReview: [PR], newReview: [PR]) {
        let old = Dictionary(uniqueKeysWithValues: oldMine.map { ($0.id, $0) })
        for pr in newMine {
            guard let before = old[pr.id] else { continue }
            if before.checks != pr.checks {
                switch pr.checks {
                case .success?:
                    onAlert?(NotchAlert(icon: "checkmark.circle.fill", title: "\(pr.short) checks passaram", tint: Theme.green))
                case .failure?, .error?:
                    onAlert?(NotchAlert(icon: "xmark.octagon.fill", title: "\(pr.short) checks falharam", tint: .red))
                default: break
                }
            }
            if before.review != pr.review {
                switch pr.review {
                case .approved?:
                    onAlert?(NotchAlert(icon: "hand.thumbsup.fill", title: "\(pr.short) aprovado", tint: Theme.green))
                case .changes?:
                    onAlert?(NotchAlert(icon: "exclamationmark.bubble.fill", title: "\(pr.short) pede mudanças",
                                        tint: Theme.orange))
                default: break
                }
            }
        }
        let oldReviewIDs = Set(oldReview.map(\.id))
        for pr in newReview where !oldReviewIDs.contains(pr.id) {
            onAlert?(NotchAlert(icon: "eye.fill", title: "Revisão pedida: \(pr.short)",
                                tint: Color(red: 0.4, green: 0.75, blue: 1)))
        }
    }
}
