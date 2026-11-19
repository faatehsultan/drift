import SwiftUI

struct HomeDashboard: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let widgets = model.settings.visibleWidgets
        if widgets.isEmpty {
            MessageView(icon: "square.grid.2x2", title: "No widgets", subtitle: "Pick some in Settings → Home.",
                        actionTitle: "Open Settings") { model.openSettings() }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(widgets) { w in
                        card(w).frame(height: 104)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder private func card(_ w: HomeWidget) -> some View {
        switch w {
        case .nowPlaying: NowPlayingCard(model: model, player: model.player)
        case .nextEvent: NextEventCard(model: model, calendar: model.calendar)
        case .todos: TodosCard(model: model, todos: model.todos)
        case .clock: ClockCard(battery: model.battery)
        case .timer: TimerCard(model: model, timer: model.timer)
        case .tray: TrayCard(model: model, tray: model.tray)
        case .clipboard: ClipboardCard(model: model, clipboard: model.clipboard)
        }
    }
}

struct Card<Content: View>: View {
    let action: (() -> Void)?
    let content: Content

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { action?() }
    }
}

struct CardHeader: View {
    let icon: String
    let title: String
    var color: Color = .white
    var trailing: String = ""

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.dim)
            Spacer(minLength: 0)
            if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundColor(.white.opacity(0.45)) }
        }
    }
}

struct NowPlayingCard: View {
    let model: NotchModel
    @ObservedObject var player: PlayerModel

    var body: some View {
        Card(action: { model.select(.player) }) {
            if let t = player.current {
                HStack(spacing: 10) {
                    Art(t.thumbnail, size: 80, radius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                        Text(t.artist).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            IconButton(systemName: "backward.fill", size: 12) { player.previous() }
                            IconButton(systemName: player.isPlaying ? "pause.fill" : "play.fill", size: 14) { player.togglePlay() }
                            IconButton(systemName: "forward.fill", size: 12) { player.next() }
                        }
                        .offset(x: -8)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    CardHeader(icon: "music.note", title: "Music", color: .pink)
                    Spacer(minLength: 0)
                    Text("Nothing playing").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    Text("Tap to search YouTube Music").font(.system(size: 11)).foregroundColor(.dim)
                }
            }
        }
    }
}

struct NextEventCard: View {
    let model: NotchModel
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        Card(action: { model.selectSection(.calendar) }) {
            VStack(alignment: .leading, spacing: 4) {
                CardHeader(icon: "calendar", title: "Next up", color: .red)
                Spacer(minLength: 0)
                switch calendar.access {
                case .granted:
                    if let e = calendar.next {
                        HStack(spacing: 8) {
                            Capsule().fill(e.color).frame(width: 3, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                                Text("\(e.timeRange) · \(e.countdownText)").font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
                            }
                        }
                        if let u = e.joinURL { JoinButton(url: u, service: e.service) }
                    } else {
                        Text("Nothing else coming up").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        Text("Enjoy the free time").font(.system(size: 11)).foregroundColor(.dim)
                    }
                case .unknown:
                    Text("See your meetings").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    SmallButton(title: "Allow calendar", icon: "checkmark") { calendar.requestAccess() }
                case .denied:
                    Text("Calendar access is off").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    SmallButton(title: "Open settings", icon: "gearshape") { calendar.openPrivacySettings() }
                }
            }
        }
    }
}

struct TodosCard: View {
    let model: NotchModel
    @ObservedObject var todos: TodoModel

    var body: some View {
        Card(action: { model.selectSection(.tools); model.selectTool(.todos) }) {
            VStack(alignment: .leading, spacing: 5) {
                CardHeader(icon: "checklist", title: "To-dos", color: .green, trailing: todos.remaining > 0 ? "\(todos.remaining) left" : "")
                if todos.open.isEmpty {
                    Spacer(minLength: 0)
                    Text("All done").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text("Tap to add one").font(.system(size: 11)).foregroundColor(.dim)
                } else {
                    ForEach(todos.open.prefix(3)) { t in
                        HStack(spacing: 7) {
                            Button { todos.toggle(t) } label: {
                                Image(systemName: "circle").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            }
                            .buttonStyle(PressStyle())
                            Text(t.title).font(.system(size: 12)).foregroundColor(.white).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct ClockCard: View {
    @ObservedObject var battery: BatteryModel

    var body: some View {
        Card {
            HStack {
                TimelineView(.everyMinute) { ctx in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundColor(.white)
                        Text(ctx.date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.system(size: 11))
                            .foregroundColor(.dim)
                    }
                }
                Spacer(minLength: 0)
                if battery.hasBattery {
                    ZStack {
                        ProgressRing(progress: Double(battery.level) / 100,
                                     color: battery.level <= 20 && !battery.pluggedIn ? .red : .green, lineWidth: 4)
                        VStack(spacing: 0) {
                            if battery.pluggedIn {
                                Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundColor(.green)
                            }
                            Text("\(battery.level)%").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    .frame(width: 52, height: 52)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct TimerCard: View {
    let model: NotchModel
    @ObservedObject var timer: TimerModel

    var body: some View {
        Card(action: { model.selectSection(.tools); model.selectTool(.timer) }) {
            VStack(alignment: .leading, spacing: 4) {
                CardHeader(icon: "timer", title: timer.pomodoro ? "Pomodoro" : "Timer", color: .orange, trailing: timer.label)
                Spacer(minLength: 0)
                HStack {
                    Text(formatTime(timer.remaining))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                    IconButton(systemName: timer.running ? "pause.fill" : "play.fill", size: 14) { timer.toggle() }
                }
            }
        }
    }
}

struct TrayCard: View {
    let model: NotchModel
    @ObservedObject var tray: TrayModel

    var body: some View {
        Card(action: { model.selectSection(.tray) }) {
            VStack(alignment: .leading, spacing: 6) {
                CardHeader(icon: "tray", title: "Tray", color: .blue, trailing: tray.items.isEmpty ? "" : "\(tray.items.count)")
                Spacer(minLength: 0)
                if tray.items.isEmpty {
                    Text("Drop files on the notch").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                } else {
                    HStack(spacing: 6) {
                        ForEach(tray.items.prefix(4)) { i in
                            ThumbView(thumb: FileThumb.of(i.url)).frame(width: 40, height: 40)
                        }
                    }
                }
            }
        }
    }
}

struct ClipboardCard: View {
    let model: NotchModel
    @ObservedObject var clipboard: ClipboardModel

    var body: some View {
        Card(action: { model.selectSection(.tools); model.selectTool(.clipboard) }) {
            VStack(alignment: .leading, spacing: 5) {
                CardHeader(icon: "doc.on.clipboard", title: "Clipboard", color: .purple)
                if clipboard.items.isEmpty {
                    Spacer(minLength: 0)
                    Text("Copy something").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                } else {
                    ForEach(clipboard.items.prefix(3)) { c in
                        Text(c.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11))
                            .foregroundColor(clipboard.copiedId == c.id ? .green : .white.opacity(0.85))
                            .lineLimit(1)
                            .onTapGesture { clipboard.copy(c) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
