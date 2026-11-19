import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: NotchModel

    init(model: NotchModel) { self.model = model }

    func show() {
        if window == nil {
            let view = SettingsView(model: model, settings: model.settings, agent: model.agent, calendar: model.calendar)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Drift Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 580, height: 620))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var agent: AgentModel
    @ObservedObject var calendar: CalendarModel

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            layout.tabItem { Label("Layout", systemImage: "rectangle.3.group") }
            home.tabItem { Label("Home", systemImage: "square.grid.2x2") }
            activities.tabItem { Label("Live activities", systemImage: "bolt.horizontal") }
            integrations.tabItem { Label("Integrations", systemImage: "puzzlepiece") }
        }
        .frame(width: 580, height: 620)
    }

    private var general: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { settings.theme }, set: { settings.theme = $0 })) {
                    ForEach(Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Glass uses Liquid Glass on macOS 26 and later, and a frosted blur before that.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Behavior") {
                Slider(value: Binding(get: { settings.hoverDelay }, set: { settings.hoverDelay = $0 }), in: 0...0.6) {
                    Text("Hover delay")
                }
                Slider(value: Binding(get: { settings.collapseDelay }, set: { settings.collapseDelay = $0 }), in: 0.2...2) {
                    Text("Collapse delay")
                }
                Toggle("Hide in fullscreen apps", isOn: Binding(get: { model.hideInFullscreen }, set: { model.hideInFullscreen = $0 }))
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
                Toggle("Keep clipboard history", isOn: Binding(get: { settings.clipboardHistory }, set: { settings.clipboardHistory = $0 }))
            }
            Section("About") {
                LabeledContent("Version", value: model.appVersion)
                Button("Check for Updates…") { model.checkForUpdates() }
            }
            Section("Hotkeys") {
                LabeledContent("Show or hide", value: "⌥ Space")
                LabeledContent("Search music", value: "⌥⌘ F")
                LabeledContent("Play or pause", value: "⌥⌘ P")
                LabeledContent("Previous, next", value: "⌥⌘ ← →")
                LabeledContent("Volume", value: "⌥⌘ ↑ ↓")
                LabeledContent("Like", value: "⌥⌘ L")
            }
        }
        .formStyle(.grouped)
    }

    private var layout: some View {
        Form {
            Section("Sections in the notch · drag to reorder") {
                List {
                    ForEach(settings.sectionOrder) { s in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundColor(.secondary)
                            Toggle(isOn: settings.shownBinding(\.hiddenSections, s)) { Label(s.title, systemImage: s.icon) }
                        }
                    }
                    .onMove { settings.sectionOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: 180)
            }
            Section("Music tabs") {
                ForEach(MusicTab.allCases.filter { $0.optional }) { t in
                    Toggle(isOn: settings.shownBinding(\.hiddenMusicTabs, t)) { Label(t.title, systemImage: t.icon) }
                }
            }
            Section("Tools · drag to reorder") {
                List {
                    ForEach(settings.toolOrder) { t in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundColor(.secondary)
                            Toggle(isOn: settings.shownBinding(\.hiddenTools, t)) { Label(t.title, systemImage: t.icon) }
                        }
                    }
                    .onMove { settings.toolOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: 210)
            }
        }
        .formStyle(.grouped)
    }

    private var home: some View {
        Form {
            Section("Home widgets · drag to reorder") {
                List {
                    ForEach(settings.widgetOrder) { w in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundColor(.secondary)
                            Toggle(isOn: settings.shownBinding(\.hiddenWidgets, w)) { Label(w.title, systemImage: w.icon) }
                        }
                    }
                    .onMove { settings.widgetOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: 250)
                Text("Four widgets fit without scrolling.").font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var activities: some View {
        Form {
            Section("Show in the notch") {
                ForEach(ActivityKind.allCases) { a in
                    Toggle(a.title, isOn: settings.shownBinding(\.disabledActivities, a))
                }
            }
            Section("Meetings") {
                Stepper("Alert \(settings.meetingLead) min before a meeting",
                        value: Binding(get: { settings.meetingLead }, set: { settings.meetingLead = $0 }), in: 1...30)
            }
        }
        .formStyle(.grouped)
    }

    private var integrations: some View {
        Form {
            Section("YouTube Music") {
                HStack {
                    Text(model.signedIn ? "Signed in" : "Not signed in")
                    Spacer()
                    Button(model.signedIn ? "Sign out" : "Sign in") {
                        if model.signedIn { model.signOut() } else { model.openSignInWindow() }
                    }
                }
            }
            Section("Calendar") {
                HStack {
                    Text(calendarStatus)
                    Spacer()
                    if calendar.access == .unknown { Button("Allow access") { calendar.requestAccess() } }
                    if calendar.access == .denied { Button("Open Privacy settings") { calendar.openPrivacySettings() } }
                }
            }
            Section("Claude Code") {
                Text("Approve or deny Claude Code permission requests right from the notch. Installs a small hook in ~/.claude/settings.json (a backup is saved next to it).")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Text(agent.hookInstalled ? "Hook installed" : "Not installed")
                    Spacer()
                    Button(agent.hookInstalled ? "Remove hook" : "Install hook") {
                        if agent.hookInstalled { agent.uninstallHook() } else { agent.installHook() }
                    }
                }
                if !agent.status.isEmpty { Text(agent.status).font(.caption).foregroundColor(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private var calendarStatus: String {
        switch calendar.access {
        case .granted: return "Connected"
        case .denied: return "Access denied"
        case .unknown: return "Not connected"
        }
    }
}
