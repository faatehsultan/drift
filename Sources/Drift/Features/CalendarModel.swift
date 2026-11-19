import AppKit
import SwiftUI
import EventKit

enum CalAccess { case unknown, granted, denied }

struct CalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let location: String
    let calendarName: String
    let joinURL: URL?

    init(e: EKEvent) {
        id = e.calendarItemIdentifier + "-\(Int(e.startDate.timeIntervalSince1970))"
        title = e.title ?? "Untitled"
        start = e.startDate
        end = e.endDate
        allDay = e.isAllDay
        color = Color(nsColor: e.calendar?.color ?? .systemBlue)
        location = e.location ?? ""
        calendarName = e.calendar?.title ?? ""
        let texts: [String] = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }
        joinURL = CalEvent.findMeetingURL(texts)
    }

    static func findMeetingURL(_ texts: [String]) -> URL? {
        let pattern = #"https?://[^\s<>"']*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"']*"#
        for t in texts {
            if let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return URL(string: String(t[r]))
            }
        }
        return nil
    }

    var service: String {
        guard let h = joinURL?.host?.lowercased() else { return "" }
        if h.contains("zoom") { return "Zoom" }
        if h.contains("meet.google") { return "Meet" }
        if h.contains("teams") { return "Teams" }
        if h.contains("webex") { return "Webex" }
        return "call"
    }

    var timeRange: String {
        if allDay { return "All day" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    var countdownText: String {
        let now = Date()
        if allDay { return "today" }
        if start <= now && end > now { return "now" }
        let mins = Int(ceil(start.timeIntervalSince(now) / 60))
        if mins < 60 { return "in \(max(mins, 1))m" }
        let h = mins / 60
        if h < 24 { return mins % 60 == 0 ? "in \(h)h" : "in \(h)h \(mins % 60)m" }
        return "in \(h / 24)d"
    }
}

struct DayGroup {
    let date: Date
    let title: String
    let events: [CalEvent]
}

/// Reads the macOS Calendar (which includes Google, iCloud and Exchange accounts added there).
@MainActor
final class CalendarModel: ObservableObject {
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var access: CalAccess = .unknown
    @Published private(set) var tick = 0

    var onMeetingSoon: (CalEvent) -> Void = { _ in }

    private let store = EKEventStore()
    private var notified = Set<String>()
    private var timer: Timer?

    init() {
        updateAccess()
        refresh()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.halfMinute() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event).rawValue {
        case 3: access = .granted
        case 0: access = .unknown
        default: access = .denied
        }
    }

    func requestAccess() {
        Task {
            var granted = false
            if #available(macOS 14.0, *) {
                granted = (try? await store.requestFullAccessToEvents()) ?? false
            } else {
                granted = (try? await store.requestAccess(to: .event)) ?? false
            }
            self.access = granted ? .granted : .denied
            self.refresh()
        }
    }

    func openPrivacySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(u)
        }
    }

    func refresh() {
        guard access == .granted else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 4, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let now = Date()
        let raw = store.events(matching: pred)
            .filter { $0.endDate > now || ($0.isAllDay && cal.isDateInToday($0.startDate)) }
            .sorted { $0.startDate < $1.startDate }
        events = raw.prefix(40).map { CalEvent(e: $0) }
    }

    private func halfMinute() {
        tick += 1
        if tick % 10 == 0 { refresh() }
        let now = Date()
        let lead = Double(AppSettings.shared.meetingLead) * 60
        for e in events where !e.allDay && e.start > now && e.start.timeIntervalSince(now) <= lead && !notified.contains(e.id) {
            notified.insert(e.id)
            onMeetingSoon(e)
        }
    }

    /// The next timed event that hasn't ended.
    var next: CalEvent? {
        let now = Date()
        return events.first { !$0.allDay && $0.end > now }
    }

    /// An event starting within 10 minutes, or one that started in the last 5.
    var imminent: CalEvent? {
        guard let e = next else { return nil }
        let delta = e.start.timeIntervalSinceNow
        return (delta <= 600 && delta >= -300) ? e : nil
    }

    var days: [DayGroup] {
        let cal = Calendar.current
        var groups: [DayGroup] = []
        var byDay: [Date: [CalEvent]] = [:]
        for e in events { byDay[cal.startOfDay(for: e.start), default: []].append(e) }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        for d in byDay.keys.sorted() {
            let title: String
            if cal.isDateInToday(d) { title = "Today" }
            else if cal.isDateInTomorrow(d) { title = "Tomorrow" }
            else { title = f.string(from: d) }
            groups.append(DayGroup(date: d, title: title, events: byDay[d] ?? []))
        }
        return groups
    }
}
