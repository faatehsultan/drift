import AppKit
import Carbon.HIToolbox
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var player: PlayerModel!
    private var model: NotchModel!
    private var notch: NotchWindowController!
    private var statusItem: NSStatusItem!
    private var signIn: SignInWindowController!
    private var settingsWindow: SettingsWindowController!
    private var updater: SPUStandardUpdaterController?

    // main.swift creates this outside the main actor, so the init must be nonisolated.
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signIn = SignInWindowController()
        player = PlayerModel()
        model = NotchModel(player: player)
        notch = NotchWindowController(model: model)
        settingsWindow = SettingsWindowController(model: model)
        model.openSettings = { [weak self] in self?.settingsWindow.show() }
        model.checkForUpdates = { [weak self] in self?.checkForUpdates() }
        // Auto-updates turn on once scripts/setup-sparkle.sh has added the signing key.
        if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }

        model.openSignInWindow = { [weak self] in self?.signIn.show() }
        model.onFullscreenSettingChanged = { [weak self] in self?.notch.refreshVisibility() }
        signIn.onFinish = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.model.refreshAuth()
                self.model.resetLibraryCaches()
            }
        }
        Task { @MainActor in await self.model.refreshAuth() }

        setupStatusItem()
        registerHotKeys()
    }

    // MARK: Menu bar icon

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Drift")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "Show Drift   ⌥Space", #selector(showNotch))
        add(menu, "Settings…", #selector(openSettings), key: ",")
        add(menu, "Check for Updates…", #selector(checkForUpdates))
        add(menu, "Search   ⌥⌘F", #selector(openSearch))
        menu.addItem(.separator())
        add(menu, model.signedIn ? "Sign out of YouTube Music" : "Sign in to YouTube Music", #selector(toggleAuth))
        add(menu, "Launch at login", #selector(toggleLogin)).state = model.launchAtLogin ? .on : .off
        add(menu, "Hide in fullscreen apps", #selector(toggleFullscreen)).state = model.hideInFullscreen ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit Drift", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func showNotch() { notch.toggleFromHotkey() }
    @objc private func openSearch() { notch.openSearch() }
    @objc private func openSettings() { settingsWindow.show() }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        if let updater = updater {
            updater.checkForUpdates(nil)
        } else {
            let alert = NSAlert()
            alert.messageText = "Updates aren't set up in this build"
            alert.informativeText = "Run scripts/setup-sparkle.sh, then rebuild."
            alert.runModal()
        }
    }
    @objc private func toggleAuth() { if model.signedIn { model.signOut() } else { signIn.show() } }
    @objc private func toggleLogin() { model.toggleLaunchAtLogin() }
    @objc private func toggleFullscreen() { model.hideInFullscreen.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Global hotkeys

    private func registerHotKeys() {
        let hk = HotKeyCenter.shared
        let opt = optionKey
        let optCmd = optionKey | cmdKey
        hk.register(keyCode: kVK_Space, modifiers: opt) { [weak self] in self?.notch.toggleFromHotkey() }
        hk.register(keyCode: kVK_ANSI_F, modifiers: optCmd) { [weak self] in self?.notch.openSearch() }
        hk.register(keyCode: kVK_ANSI_P, modifiers: optCmd) { [weak self] in self?.player.togglePlay() }
        hk.register(keyCode: kVK_RightArrow, modifiers: optCmd) { [weak self] in self?.player.next() }
        hk.register(keyCode: kVK_LeftArrow, modifiers: optCmd) { [weak self] in self?.player.previous() }
        hk.register(keyCode: kVK_UpArrow, modifiers: optCmd) { [weak self] in self?.player.nudgeVolume(0.08) }
        hk.register(keyCode: kVK_DownArrow, modifiers: optCmd) { [weak self] in self?.player.nudgeVolume(-0.08) }
        hk.register(keyCode: kVK_ANSI_L, modifiers: optCmd) { [weak self] in self?.player.toggleLike() }
    }
}
