import SwiftUI

struct CalendarView: View {
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        switch calendar.access {
        case .granted:
            if calendar.events.isEmpty {
                MessageView(icon: "calendar", title: "Nothing coming up", subtitle: "The next four days are clear.")
            } else {
                let nextId = calendar.next?.id
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(calendar.days, id: \.date) { day in
                            SectionLabel(day.title)
                            ForEach(day.events) { e in
                                EventRow(event: e, isNext: e.id == nextId)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        case .unknown:
            MessageView(icon: "calendar", title: "See your meetings here",
                        subtitle: "Drift reads the macOS Calendar, including Google calendars you've added there.",
                        actionTitle: "Allow calendar access") { calendar.requestAccess() }
        case .denied:
            MessageView(icon: "calendar.badge.exclamationmark", title: "Calendar access is off",
                        subtitle: "Turn on Drift in Privacy & Security → Calendars.",
                        actionTitle: "Open settings") { calendar.openPrivacySettings() }
        }
    }
}

struct EventRow: View {
    let event: CalEvent
    let isNext: Bool

    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(event.color).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text([event.timeRange, event.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isNext {
                Text(event.countdownText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(event.color.opacity(0.35)))
            }
            if let u = event.joinURL { JoinButton(url: u, service: event.service) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(HoverFill(selected: isNext))
    }
}
