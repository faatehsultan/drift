import AppKit
import SwiftUI
import IOKit.ps

// MARK: - Notes

@MainActor
final class NotesModel: ObservableObject {
    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: "notes") }
    }
    init() { text = UserDefaults.standard.string(forKey: "notes") ?? "" }
}

// MARK: - To-dos

struct Todo: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done = false
    var created = Date()
}

@MainActor
final class TodoModel: ObservableObject {
    @Published private(set) var items: [Todo] = []

    init() {
        if let d = UserDefaults.standard.data(forKey: "todos"), let s = try? JSONDecoder().decode([Todo].self, from: d) {
            items = s
        }
    }

    var remaining: Int { items.filter { !$0.done }.count }
    var open: [Todo] { items.filter { !$0.done } }

    func add(_ title: String) {
        withAnimation(Anim.quick) { items.insert(Todo(title: title), at: 0) }
        save()
    }

    func toggle(_ t: Todo) {
        guard let i = items.firstIndex(where: { $0.id == t.id }) else { return }
        withAnimation(Anim.quick) {
            items[i].done.toggle()
            // Done items sink to the bottom.
            let item = items.remove(at: i)
            if item.done { items.append(item) } else { items.insert(item, at: 0) }
        }
        save()
    }

    func remove(_ t: Todo) {
        withAnimation(Anim.quick) { items.removeAll { $0.id == t.id } }
        save()
    }

    func clearDone() {
        withAnimation(Anim.quick) { items.removeAll { $0.done } }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: "todos") }
    }
}

// MARK: - Timer and Pomodoro

@MainActor
final class TimerModel: ObservableObject {
    enum Phase { case timer, focus, rest }

    @Published private(set) var phase: Phase = .timer
    @Published private(set) var duration: TimeInterval = 300
    @Published private(set) var remaining: TimeInterval = 300
    @Published private(set) var running = false
    @Published private(set) var active = false
    @Published private(set) var focusDone = 0
    @Published private(set) var pomodoro = false

    var onFinish: (String) -> Void = { _ in }
    private var endDate: Date?
    private var ticker: Timer?

    var progress: Double { duration > 0 ? 1 - remaining / duration : 0 }

    var label: String {
        if pomodoro { return phase == .focus ? "Focus" : "Break" }
        if running { return "Running" }
        return active ? "Paused" : "Ready"
    }

    func setMinutes(_ m: Double) {
        stopTicker()
        pomodoro = false
        phase = .timer
        duration = m * 60
        remaining = duration
        running = false
        active = false
    }

    func startPomodoro() {
        pomodoro = true
        phase = .focus
        focusDone = 0
        duration = 25 * 60
        remaining = duration
        start()
    }

    func start() {
        guard remaining > 0 else { return }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        active = true
        startTicker()
    }

    func pause() {
        tick()
        running = false
        stopTicker()
    }

    func toggle() { if running { pause() } else { start() } }

    func reset() {
        stopTicker()
        running = false
        active = false
        if pomodoro { phase = .focus; duration = 25 * 60 }
        remaining = duration
    }

    func adjust(_ seconds: TimeInterval) {
        let r = max(10, remaining + seconds)
        if running { endDate = Date().addingTimeInterval(r) }
        remaining = r
        duration = max(r, duration + seconds)
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard running, let end = endDate else { return }
        let r = max(0, end.timeIntervalSinceNow)
        if abs(r - remaining) >= 0.2 || r == 0 { remaining = r }
        if r <= 0 { finish() }
    }

    private func finish() {
        stopTicker()
        running = false
        NSSound(named: NSSound.Name("Glass"))?.play()
        if pomodoro {
            if phase == .focus {
                focusDone += 1
                phase = .rest
                duration = (focusDone % 4 == 0 ? 15 : 5) * 60
                onFinish("Focus done, take a break")
            } else {
                phase = .focus
                duration = 25 * 60
                onFinish("Break's over, back to it")
            }
            remaining = duration
            start()
        } else {
            active = false
            remaining = duration
            onFinish("Time's up")
        }
    }
}

// MARK: - Clipboard history

struct ClipItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
}

@MainActor
final class ClipboardModel: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var copiedId: UUID?

    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private static let secretTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword")
    ]

    init() {
        if let d = UserDefaults.standard.data(forKey: "clipboard"), let s = try? JSONDecoder().decode([ClipItem].self, from: d) {
            items = s
        }
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard AppSettings.shared.clipboardHistory else { return }
        let types = pb.types ?? []
        if types.contains(where: { Self.secretTypes.contains($0) }) { return }
        guard let s = pb.string(forType: .string) else { return }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, s.count < 20000 else { return }
        var pinned = false
        if let i = items.firstIndex(where: { $0.text == s }) {
            pinned = items[i].pinned
            items.remove(at: i)
        }
        items.insert(ClipItem(text: s, pinned: pinned), at: 0)
        trim()
        save()
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChange = pb.changeCount
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            let it = items.remove(at: i)
            items.insert(it, at: 0)
        }
        withAnimation(Anim.quick) { copiedId = item.id }
        let id = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedId == id { withAnimation(Anim.quick) { self?.copiedId = nil } }
        }
        save()
    }

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        withAnimation(Anim.quick) { items.removeAll { !$0.pinned } }
        save()
    }

    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= 50
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: "clipboard") }
    }
}

// MARK: - Shortcuts

@MainActor
final class ShortcutsModel: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var running: String?
    private var loaded = false

    func loadIfNeeded() { if !loaded { load() } }

    func load() {
        loaded = true
        loading = true
        Task {
            let out = await Self.shell(["list"])
            self.names = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self.loading = false
        }
    }

    func run(_ name: String) {
        running = name
        Task {
            _ = await Self.shell(["run", name])
            self.running = nil
        }
    }

    nonisolated static func shell(_ args: [String]) async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    c.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    c.resume(returning: "")
                }
            }
        }
    }
}

// MARK: - Battery

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var pluggedIn = false
    @Published private(set) var charging = false
    @Published private(set) var hasBattery = false

    var onPluggedIn: (Int) -> Void = { _ in }
    private var timer: Timer?
    private var first = true

    init() {
        refresh()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            hasBattery = true
            level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            if plugged && !pluggedIn && !first { onPluggedIn(level) }
            pluggedIn = plugged
            first = false
            return
        }
        hasBattery = false
    }
}
