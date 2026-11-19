import SwiftUI

enum Theme: String, CaseIterable, Hashable {
    case glass, solid
    var title: String { self == .glass ? "Glass" : "Solid black" }
}

enum NotchSection: String, CaseIterable, Identifiable, Hashable {
    case home, music, tray, calendar, tools
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .tray: return "Tray"
        case .calendar: return "Calendar"
        case .tools: return "Tools"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .music: return "music.note"
        case .tray: return "tray"
        case .calendar: return "calendar"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

enum MusicTab: String, CaseIterable, Identifiable, Hashable {
    case player, lyrics, search, queue, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .player: return "Player"
        case .lyrics: return "Lyrics"
        case .search: return "Search"
        case .queue: return "Queue"
        case .library: return "Library"
        }
    }
    var icon: String {
        switch self {
        case .player: return "play"
        case .lyrics: return "quote.bubble"
        case .search: return "magnifyingglass"
        case .queue: return "list.bullet"
        case .library: return "house"
        }
    }
    var optional: Bool { self == .lyrics || self == .queue || self == .library }
}

enum HomeWidget: String, CaseIterable, Identifiable, Hashable {
    case nowPlaying, nextEvent, todos, clock, timer, tray, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nowPlaying: return "Now playing"
        case .nextEvent: return "Next meeting"
        case .todos: return "To-dos"
        case .clock: return "Clock and battery"
        case .timer: return "Timer"
        case .tray: return "Tray"
        case .clipboard: return "Clipboard"
        }
    }
    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .nextEvent: return "calendar"
        case .todos: return "checklist"
        case .clock: return "clock"
        case .timer: return "timer"
        case .tray: return "tray"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

enum ToolKind: String, CaseIterable, Identifiable, Hashable {
    case notes, todos, timer, mirror, shortcuts, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notes: return "Notes"
        case .todos: return "To-dos"
        case .timer: return "Timer"
        case .mirror: return "Mirror"
        case .shortcuts: return "Shortcuts"
        case .clipboard: return "Clipboard"
        }
    }
    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .todos: return "checklist"
        case .timer: return "timer"
        case .mirror: return "camera"
        case .shortcuts: return "square.stack.3d.up"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

enum ActivityKind: String, CaseIterable, Identifiable, Hashable {
    case music, trackPeek, timer, meetings, charging, tray, agents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .music: return "Now playing in the notch"
        case .trackPeek: return "Pull down on track change"
        case .timer: return "Timer and Pomodoro countdown"
        case .meetings: return "Meeting countdown and alerts"
        case .charging: return "Charging"
        case .tray: return "Files added to tray"
        case .agents: return "Claude Code approvals"
        }
    }
}

/// Everything the user can customize. Saved to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var theme: Theme = .glass { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var sectionOrder: [NotchSection] = NotchSection.allCases { didSet { saveList(sectionOrder, "sectionOrder") } }
    @Published var hiddenSections: Set<NotchSection> = [] { didSet { saveSet(hiddenSections, "hiddenSections") } }
    @Published var widgetOrder: [HomeWidget] = HomeWidget.allCases { didSet { saveList(widgetOrder, "widgetOrder") } }
    @Published var hiddenWidgets: Set<HomeWidget> = [] { didSet { saveSet(hiddenWidgets, "hiddenWidgets") } }
    @Published var toolOrder: [ToolKind] = ToolKind.allCases { didSet { saveList(toolOrder, "toolOrder") } }
    @Published var hiddenTools: Set<ToolKind> = [] { didSet { saveSet(hiddenTools, "hiddenTools") } }
    @Published var hiddenMusicTabs: Set<MusicTab> = [] { didSet { saveSet(hiddenMusicTabs, "hiddenMusicTabs") } }
    @Published var disabledActivities: Set<ActivityKind> = [] { didSet { saveSet(disabledActivities, "disabledActivities") } }
    @Published var hoverDelay: Double = 0.12 { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var collapseDelay: Double = 0.55 { didSet { d.set(collapseDelay, forKey: "collapseDelay") } }
    @Published var meetingLead: Int = 5 { didSet { d.set(meetingLead, forKey: "meetingLead") } }
    @Published var clipboardHistory = true { didSet { d.set(clipboardHistory, forKey: "clipboardHistory") } }

    init() {
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .glass
        sectionOrder = loadList("sectionOrder")
        hiddenSections = loadSet("hiddenSections", default: [])
        widgetOrder = loadList("widgetOrder")
        hiddenWidgets = loadSet("hiddenWidgets", default: [.timer, .tray, .clipboard])
        toolOrder = loadList("toolOrder")
        hiddenTools = loadSet("hiddenTools", default: [])
        hiddenMusicTabs = loadSet("hiddenMusicTabs", default: [])
        disabledActivities = loadSet("disabledActivities", default: [])
        if let v = d.object(forKey: "hoverDelay") as? Double { hoverDelay = v }
        if let v = d.object(forKey: "collapseDelay") as? Double { collapseDelay = v }
        if let v = d.object(forKey: "meetingLead") as? Int { meetingLead = v }
        if let v = d.object(forKey: "clipboardHistory") as? Bool { clipboardHistory = v }
    }

    // MARK: What's visible

    var visibleSections: [NotchSection] {
        let v = sectionOrder.filter { !hiddenSections.contains($0) }
        return v.isEmpty ? [.music] : v
    }
    var visibleWidgets: [HomeWidget] { widgetOrder.filter { !hiddenWidgets.contains($0) } }
    var visibleTools: [ToolKind] {
        let v = toolOrder.filter { !hiddenTools.contains($0) }
        return v.isEmpty ? [.notes] : v
    }
    var visibleMusicTabs: [MusicTab] { MusicTab.allCases.filter { !hiddenMusicTabs.contains($0) } }
    func isOn(_ a: ActivityKind) -> Bool { !disabledActivities.contains(a) }

    /// A toggle that is on when `value` is NOT in the given "hidden" set.
    func shownBinding<T: Hashable>(_ kp: ReferenceWritableKeyPath<AppSettings, Set<T>>, _ value: T) -> Binding<Bool> {
        Binding(get: { !self[keyPath: kp].contains(value) },
                set: { on in
                    if on { self[keyPath: kp].remove(value) } else { self[keyPath: kp].insert(value) }
                })
    }

    // MARK: Persistence helpers

    private func saveList<T: RawRepresentable>(_ v: [T], _ k: String) where T.RawValue == String {
        d.set(v.map { $0.rawValue }, forKey: k)
    }
    private func saveSet<T: RawRepresentable & Hashable>(_ v: Set<T>, _ k: String) where T.RawValue == String {
        d.set(v.map { $0.rawValue }, forKey: k)
    }
    private func loadList<T: RawRepresentable & CaseIterable & Equatable>(_ k: String) -> [T] where T.RawValue == String {
        let saved = (d.stringArray(forKey: k) ?? []).compactMap { T(rawValue: $0) }
        var out: [T] = []
        for s in saved where !out.contains(s) { out.append(s) }
        for c in T.allCases where !out.contains(c) { out.append(c) }
        return out
    }
    private func loadSet<T: RawRepresentable & Hashable>(_ k: String, default def: Set<T>) -> Set<T> where T.RawValue == String {
        guard let arr = d.stringArray(forKey: k) else { return def }
        return Set(arr.compactMap { T(rawValue: $0) })
    }
}
