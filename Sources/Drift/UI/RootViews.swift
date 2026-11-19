import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let s = model.size
        let expanded = model.state == .expanded
        let topR: CGFloat = expanded ? 14 : 7
        let botR: CGFloat = expanded ? 28 : (model.state == .peek ? 20 : 11)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(topRadius: topR, bottomRadius: botR,
                                glass: settings.theme == .glass && expanded,
                                notchHeight: model.notchSize.height)
                content
                    .frame(width: s.width, height: s.height, alignment: .top)
                    .clipShape(NotchShape(topRadius: 0, bottomRadius: botR))
            }
            .frame(width: s.width + topR * 2, height: s.height)
            .shadow(color: Color.black.opacity(expanded ? 0.45 : 0), radius: 22, x: 0, y: 12)
            .animation(Anim.morph, value: s)
            .animation(Anim.morph, value: model.state)
            Spacer(minLength: 0)
        }
        .frame(width: NotchLayout.canvas.width, height: NotchLayout.canvas.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .collapsed:
            CollapsedView(model: model, player: player, timer: model.timer).transition(.opacity)
        case .peek:
            PeekView(model: model, player: player, timer: model.timer).transition(.opacity)
        case .expanded:
            ExpandedView(model: model, player: player, settings: settings)
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(.easeOut(duration: 0.24).delay(0.06)),
                    removal: AnyTransition.opacity.animation(.easeIn(duration: 0.1))))
        }
    }
}

// MARK: - Background (solid or glass)

struct NotchBackground: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let glass: Bool
    let notchHeight: CGFloat

    var body: some View {
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        ZStack {
            shape.fill(Color.black).opacity(glass ? 0 : 1)
            if glass {
                GlassFill(shape: shape)
                // Keep the strip next to the hardware notch pure black so it blends in.
                VStack(spacing: 0) {
                    Color.black.frame(height: notchHeight)
                    LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                    Spacer(minLength: 0)
                }
                .clipShape(shape)
                shape.stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .animation(Anim.morph, value: glass)
    }
}

struct GlassFill: View {
    let shape: NotchShape
    var body: some View {
        ZStack {
            VisualEffectBlur().clipShape(shape)
            shape.fill(Color.black.opacity(0.34))
            GlassLayer(shape: shape)
        }
    }
}

struct GlassLayer: View {
    let shape: NotchShape
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Color.white.opacity(0.03)), in: shape)
        } else {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                      startPoint: .top, endPoint: .bottom))
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Collapsed (live activities)

struct CollapsedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var timer: TimerModel

    var body: some View {
        HStack(spacing: 0) {
            switch model.liveActivity {
            case .idle:
                Spacer(minLength: 0)
                if !model.hasNotch {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                }
            case .music:
                NowArtwork(model: model, size: 22, radius: 6).padding(.leading, 11)
                Spacer(minLength: 0)
                EqualizerView(playing: model.nowIsPlaying, color: model.nowAccent).frame(width: 18, height: 12).padding(.trailing, 13)
            case .timer:
                ProgressRing(progress: timer.progress, color: timer.phase == .rest ? .green : .orange, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 13)
                Spacer(minLength: 0)
                Text(formatTime(timer.remaining))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.trailing, 12)
            case .meeting(let e):
                Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundColor(e.color).padding(.leading, 13)
                Spacer(minLength: 0)
                Text(e.countdownText).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).padding(.trailing, 12)
            case .agent:
                Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundColor(.orange).padding(.leading, 13)
                Spacer(minLength: 0)
                PulseDot(color: .orange).frame(width: 8, height: 8).padding(.trailing, 15)
            }
        }
        .frame(height: model.notchSize.height)
    }
}

struct PeekView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var timer: TimerModel

    var body: some View {
        VStack(spacing: 0) {
            CollapsedView(model: model, player: player, timer: timer)
            HStack(spacing: 12) {
                detail
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.peekKind {
        case .track:
            if let title = model.nowTitle {
                NowArtwork(model: model, size: 40, radius: 9)
                titles(title, model.nowArtist)
            }
        case .charging(let p):
            ZStack {
                ProgressRing(progress: Double(p) / 100, color: .green, lineWidth: 3.5)
                Image(systemName: "bolt.fill").font(.system(size: 13)).foregroundColor(.green)
            }
            .frame(width: 38, height: 38)
            titles("Charging", "\(p)%")
        case .tray(let n):
            IconBadge("tray.and.arrow.down.fill", .blue)
            titles("Added to tray", n == 1 ? "1 file" : "\(n) files")
        case .timer(let msg):
            IconBadge("timer", .orange)
            titles(msg, "Timer")
        case .meeting(let title):
            IconBadge("calendar", .red)
            titles("Starting soon", title)
        }
    }

    private func titles(_ a: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(a).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Text(b).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
        }
    }
}

// MARK: - Expanded shell

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            TopStrip(model: model, player: player, settings: settings).frame(height: model.notchSize.height)
            ZStack(alignment: .top) {
                if model.showingApproval {
                    AgentApprovalView(agent: model.agent)
                        .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    sectionContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            model.tray.add(providers: providers)
            return true
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch model.section {
        case .home: HomeDashboard(model: model).transition(Self.fade)
        case .music: MusicSection(model: model, player: player, settings: settings).transition(Self.fade)
        case .tray: TrayView(model: model, tray: model.tray).transition(Self.fade)
        case .calendar: CalendarView(calendar: model.calendar).transition(Self.fade)
        case .tools: ToolsView(model: model, settings: settings).transition(Self.fade)
        }
    }

    static let fade = AnyTransition.opacity.combined(with: .scale(scale: 0.97))

    static func slide(_ edge: Edge) -> AnyTransition {
        .asymmetric(insertion: AnyTransition.move(edge: edge).combined(with: .opacity), removal: .opacity)
    }
}

/// Section switcher on the left of the notch, mini player and settings on the right.
struct TopStrip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(settings.visibleSections) { s in
                    let on = model.section == s
                    Button { model.selectSection(s) } label: {
                        Image(systemName: s.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(on ? .white : .white.opacity(0.42))
                            .frame(width: 26, height: 22)
                            .background(Capsule().fill(Color.white.opacity(on ? 0.14 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help(s.title)
                    .animation(Anim.quick, value: on)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if model.activeSource != nil, model.section != .music {
                    Button { model.select(.player) } label: {
                        HStack(spacing: 6) {
                            EqualizerView(playing: model.nowIsPlaying, color: model.nowAccent, maxHeight: 10).frame(width: 14, height: 10)
                            NowArtwork(model: model, size: 18, radius: 4)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .transition(.opacity)
                }
                SettingsMenu(model: model)
            }
        }
        .padding(.horizontal, 14)
    }
}

struct SettingsMenu: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        Menu {
            Button("Settings…") { model.openSettings() }
            Button("Check for Updates…") { model.checkForUpdates() }
            if model.signedIn {
                Button("Sign out of YouTube Music") { model.signOut() }
            } else {
                Button("Sign in to YouTube Music") { model.openSignInWindow() }
            }
            Divider()
            Button("Quit Drift") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).foregroundColor(.dim)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Music section

struct MusicSection: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            if model.needsSignIn {
                SignInView(model: model).transition(.opacity)
            } else {
                ZStack(alignment: .top) { tabContent }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                MusicTabBar(model: model, player: player, settings: settings)
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.currentMusicTab {
        case .player: PlayerTab(model: model, player: player).transition(ExpandedView.fade)
        case .lyrics: LyricsView(lyrics: model.lyrics, player: player).transition(ExpandedView.fade)
        case .search: SearchTab(model: model, player: player).transition(ExpandedView.slide(.trailing))
        case .queue: QueueTab(model: model, player: player).transition(ExpandedView.slide(.bottom))
        case .library: LibraryTab(model: model, player: player).transition(ExpandedView.fade)
        }
    }
}

struct MusicTabBar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: PlayerModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(settings.visibleMusicTabs) { t in
                let on = model.currentMusicTab == t
                Button { model.select(t) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(on ? .white : .white.opacity(0.4))
                        Circle().fill(on ? player.accent : Color.clear).frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help(t.title)
                .animation(Anim.quick, value: on)
            }
        }
        .padding(.horizontal, 24)
        .overlay(Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5), alignment: .top)
    }
}

struct SignInView: View {
    let model: NotchModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundColor(Color(red: 1, green: 0.31, blue: 0.27))
            Text("Sign in to YouTube Music").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            Text("Your likes, playlists and mixes need your account. Opens a Google sign-in window once.")
                .font(.system(size: 12))
                .foregroundColor(.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            PillButton(title: "Continue with Google") { model.openSignInWindow() }.padding(.top, 8)
            Button("Skip for now") { model.skipSignIn() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.dim)
                .padding(.top, 4)
        }
        .padding(.top, 6)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Small shared pieces

struct ProgressRing: View {
    let progress: Double
    var color: Color = .white
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

struct PulseDot: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle().fill(color).opacity(0.45 + 0.55 * (sin(t * 4) + 1) / 2)
        }
    }
}

struct IconBadge: View {
    let icon: String
    let color: Color
    init(_ icon: String, _ color: Color) {
        self.icon = icon
        self.color = color
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.22))
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(color)
        }
        .frame(width: 40, height: 40)
    }
}

struct OutlineButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

struct SmallButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(PressStyle())
    }
}

struct JoinButton: View {
    let url: URL
    let service: String
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill").font(.system(size: 10))
                Text("Join \(service)")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.green))
        }
        .buttonStyle(PressStyle())
    }
}
