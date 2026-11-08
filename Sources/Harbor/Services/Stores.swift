import AppKit
import EventKit
import SwiftUI

// MARK: - Tarefas

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

final class TaskStore: ObservableObject {
    @Published var items: [TaskItem] = [] { didSet { save() } }
    private let key = "nook.tasks"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([TaskItem].self, from: d) {
            items = v
        }
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TaskItem(title: t))
    }

    func toggle(_ item: TaskItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].done.toggle()
    }

    func remove(_ item: TaskItem) { items.removeAll { $0.id == item.id } }
    func clearDone() { items.removeAll { $0.done } }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Bandeja de arquivos

struct ShelfItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
}

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    private let key = "nook.shelf"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ShelfItem.init)
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(ShelfItem(url: url))
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Recebe arquivos arrastados.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { self.add(url) }
            }
        }
        return accepted
    }

    private func save() {
        UserDefaults.standard.set(items.map { $0.url.path }, forKey: key)
    }
}

// MARK: - Agenda

struct DayEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    /// Link de videochamada (Meet, Zoom, Teams…), se houver.
    var link: URL?
}

enum MeetingLink {
    private static let regex = try? NSRegularExpression(
        pattern: #"https://(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com|whereby\.com|[\w.-]*webex\.com|app\.slack\.com/huddle|discord\.gg|facetime\.apple\.com)[^\s<>"')]*"#,
        options: [.caseInsensitive])

    static func find(in texts: [String?]) -> URL? {
        for t in texts.compactMap({ $0 }) {
            let r = NSRange(t.startIndex..., in: t)
            if let m = regex?.firstMatch(in: t, range: r), let range = Range(m.range, in: t) {
                return URL(string: String(t[range]))
            }
        }
        return nil
    }
}

final class CalendarStore: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var events: [DayEvent] = []
    @Published var selectedDate = Date() { didSet { load() } }
    /// Próxima reunião de hoje (começa em até 15 min ou começou há até 5 min).
    @Published private(set) var nextMeeting: DayEvent?

    private let store = EKEventStore()
    private var meetingTimer: Timer?

    init() {
        refreshStatus()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.load()
            self?.refreshNextMeeting()
        }
        load()
        refreshNextMeeting()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refreshNextMeeting() }
        RunLoop.main.add(t, forMode: .common)
        meetingTimer = t
    }

    func refreshNextMeeting() {
        guard authorized else { if nextMeeting != nil { nextMeeting = nil }; return }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 60),
                                            end: now.addingTimeInterval(16 * 60), calendars: nil)
        let next = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.startDate > now.addingTimeInterval(-5 * 60)
                && $0.startDate < now.addingTimeInterval(15 * 60) && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
            .map(Self.makeEvent)
        if next != nextMeeting { nextMeeting = next }
    }

    private static func makeEvent(_ e: EKEvent) -> DayEvent {
        DayEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                 title: e.title ?? "Sem título",
                 start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                 color: Color(cgColor: e.calendar.cgColor),
                 link: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]))
    }

    private func refreshStatus() {
        let s = EKEventStore.authorizationStatus(for: .event)
        authorized = s == .fullAccess
        denied = s == .denied || s == .restricted
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshStatus()
                self?.load()
                self?.refreshNextMeeting()
            }
        }
    }

    func load() {
        guard authorized else { events = []; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: pred)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map(Self.makeEvent)
    }
}

// MARK: - Conta-gotas

final class ColorPickerStore: ObservableObject {
    @Published private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "picker.recent") ?? []
    var onPicked: ((String) -> Void)?

    /// Abre a lupa do sistema; a cor escolhida vai para a área de transferência em HEX.
    func pick() {
        NSColorSampler().show { [weak self] color in
            guard let self, let c = color?.usingColorSpace(.sRGB) else { return }
            func comp(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
            let hex = String(format: "#%02X%02X%02X", comp(c.redComponent), comp(c.greenComponent), comp(c.blueComponent))
            self.copy(hex)
            self.recent.removeAll { $0 == hex }
            self.recent.insert(hex, at: 0)
            if self.recent.count > 12 { self.recent.removeLast(self.recent.count - 12) }
            UserDefaults.standard.set(self.recent, forKey: "picker.recent")
            self.onPicked?(hex)
        }
    }

    func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }

    func clear() {
        recent = []
        UserDefaults.standard.set(recent, forKey: "picker.recent")
    }
}
