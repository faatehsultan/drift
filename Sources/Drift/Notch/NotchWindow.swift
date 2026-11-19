import AppKit
import SwiftUI
import Combine

enum NotchLayout {
    /// Transparent canvas the notch draws into. Bigger than the largest panel so shadows fit.
    static let canvas = CGSize(width: 600, height: 520)
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the borderless panel over the notch, hover detection, click-outside and fullscreen hiding.
@MainActor
final class NotchWindowController {
    let model: NotchModel
    let panel: NotchPanel

    private var timer: Timer?
    private var enterAt: Date?
    private var leaveAt: Date?
    private var menuOpen = false
    private var ticks = 0
    private var dragBaseline = 0
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: NotchLayout.canvas),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: NotchRootView(model: model, player: model.player, settings: model.settings))
        host.frame = NSRect(origin: .zero, size: NotchLayout.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        reposition()
        panel.orderFrontRegardless()
        NotchSpace.shared.add(panel)

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = true
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = false
            self?.leaveAt = nil
        }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refreshVisibility() }
        }
        wnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refreshVisibility() }
        }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self = self else { return }
            self.dragBaseline = NSPasteboard(name: .drag).changeCount
            guard self.model.state == .expanded else { return }
            self.model.collapse()
        }) { monitors.append(m) }

        // Dragging a file toward the notch opens the tray.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.handleDrag()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self = self, self.model.state == .expanded else { return e }
            if e.keyCode == 53 { self.model.escape(); return nil }
            return e
        }) { monitors.append(m) }

        model.$state.sink { [weak self] s in self?.stateChanged(s) }.store(in: &cancellables)

        let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Placement

    private var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    func reposition() {
        guard let screen = screen else { return }
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            model.hasNotch = true
            model.notchSize = CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            model.hasNotch = false
            let menuBar = f.maxY - screen.visibleFrame.maxY
            model.notchSize = CGSize(width: 150, height: menuBar > 10 ? menuBar : 24)
        }
        panel.setFrame(NSRect(x: f.midX - NotchLayout.canvas.width / 2, y: f.maxY - NotchLayout.canvas.height,
                              width: NotchLayout.canvas.width, height: NotchLayout.canvas.height), display: true)
    }

    // MARK: Hover

    private var isTyping: Bool { panel.isKeyWindow && panel.firstResponder is NSTextView }

    private func tick() {
        ticks += 1
        if ticks % 30 == 0 { refreshVisibility() }
        guard panel.isVisible, let screen = screen else { return }
        let m = NSEvent.mouseLocation
        let f = screen.frame
        guard m.x >= f.minX && m.x <= f.maxX else { enterAt = nil; return }
        let s = model.size
        let r = NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)

        switch model.state {
        case .collapsed, .peek:
            let half = max(r.width, model.notchSize.width) / 2 + 8
            let inside = abs(m.x - f.midX) <= half && m.y >= r.minY - 2 && m.y <= f.maxY + 1
            if inside {
                if let since = enterAt {
                    if Date().timeIntervalSince(since) > model.settings.hoverDelay { enterAt = nil; model.expand() }
                } else {
                    enterAt = Date()
                }
            } else {
                enterAt = nil
            }
        case .expanded:
            enterAt = nil
            let inside = r.insetBy(dx: -10, dy: -10).contains(m) || (abs(m.x - f.midX) <= r.width / 2 + 10 && m.y >= f.maxY - 2)
            if inside {
                leaveAt = nil
                if model.pinned { model.pinned = false }
            } else if !model.pinned && !isTyping && !menuOpen && !model.showingApproval {
                if let since = leaveAt {
                    if Date().timeIntervalSince(since) > model.settings.collapseDelay { leaveAt = nil; model.collapse() }
                } else {
                    leaveAt = Date()
                }
            } else {
                leaveAt = nil
            }
        }
    }

    private func stateChanged(_ s: NotchState) {
        panel.ignoresMouseEvents = s != .expanded
        guard s == .collapsed else { return }
        // Give keyboard focus back to whatever app the user was in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self, self.model.state == .collapsed, self.panel.isKeyWindow else { return }
            self.panel.makeFirstResponder(nil)
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
            NotchSpace.shared.add(self.panel)
        }
    }

    private func handleDrag() {
        guard model.state != .expanded, let screen = screen else { return }
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragBaseline, pb.types?.contains(.fileURL) == true else { return }
        let m = NSEvent.mouseLocation
        let f = screen.frame
        guard abs(m.x - f.midX) < 260, m.y > f.maxY - 90 else { return }
        model.expandForDrop()
    }

    // MARK: Hotkeys

    func toggleFromHotkey() {
        model.toggle()
        if model.state == .expanded { panel.makeKey() }
    }

    func openSearch() {
        model.expand(pinned: true)
        panel.makeKey()
        model.select(.search)
    }

    // MARK: Fullscreen

    func refreshVisibility() {
        guard let screen = screen else { return }
        let hide = model.hideInFullscreen && Self.isFullscreen(on: screen)
        if hide {
            if panel.isVisible { model.collapse(); panel.orderOut(nil) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            NotchSpace.shared.add(panel)
        }
    }

    static func isFullscreen(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let sf = screen.frame
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            if b.width >= sf.width && b.height >= sf.height { return true }
        }
        return false
    }
}
