import SwiftUI
import Combine
import WebKit
import ServiceManagement

enum NotchState: Equatable { case collapsed, peek, expanded }

enum PeekKind: Equatable {
    case track
    case charging(Int)
    case tray(Int)
    case timer(String)
    case meeting(String)
}

/// What the collapsed notch shows on its sides, highest priority first.
enum LiveActivity: Equatable {
    case idle, agent, timer, meeting(CalEvent), music
}

enum Anim {
    static let morph = Animation.spring(response: 0.44, dampingFraction: 0.8)
    static let tab = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let quick = Animation.easeOut(duration: 0.16)
}

/// All notch UI state, plus every feature model.
@MainActor
final class NotchModel: ObservableObject {
    static let panelWidth: CGFloat = 520

    @Published var state: NotchState = .collapsed
    @Published var peekKind: PeekKind = .track
    @Published var section: NotchSection = .home
    @Published var tab: MusicTab = .player
    @Published var tool: ToolKind = .notes
    @Published var pinned = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true

    @Published var query = ""
    @Published var suggestions: [String] = []
    @Published var recent: [String] = []
    @Published var showingResults = false
    @Published var filter: SearchFilter = .top
    @Published var results = SearchResults.empty
    @Published var searching = false
    @Published var searchError: String?
    @Published var focusSearchToken = 0

    @Published var searchRoute: [Route] = []
    @Published var homeRoute: [Route] = []

    @Published var home: [Shelf] = []
    @Published var homeLoading = false
    @Published var homeError: String?

    @Published var signedIn = false
    @Published var showSignIn = true
    @Published var hideInFullscreen = true {
        didSet {
            UserDefaults.standard.set(hideInFullscreen, forKey: "hideInFullscreen")
            onFullscreenSettingChanged()
        }
    }

    let player: PlayerModel
    let settings = AppSettings.shared
    let calendar = CalendarModel()
    let tray = TrayModel()
    let notes = NotesModel()
    let todos = TodoModel()
    let timer = TimerModel()
    let clipboard = ClipboardModel()
    let shortcuts = ShortcutsModel()
    let battery = BatteryModel()
    let agent = AgentModel()
    let lyrics = LyricsModel()

    var openSignInWindow: () -> Void = {}
    var openSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var onFullscreenSettingChanged: () -> Void = {}

    private var cancellables = Set<AnyCancellable>()
    private var peekTask: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var suppressQueryChange = false
    private var agentPinned = false
    private var detailCache: [Route: DetailModel] = [:]

    init(player: PlayerModel) {
        self.player = player
        let d = UserDefaults.standard
        recent = d.stringArray(forKey: "recentSearches") ?? []
        showSignIn = !d.bool(forKey: "skippedSignIn")
        hideInFullscreen = (d.object(forKey: "hideInFullscreen") as? Bool) ?? true
        section = settings.visibleSections.first ?? .music
        tool = settings.visibleTools.first ?? .notes

        player.trackChanged.sink { [weak self] t in
            guard let self = self else { return }
            self.lyrics.load(for: t)
            if self.settings.isOn(.trackPeek) { self.peek(.track) }
        }.store(in: &cancellables)

        // Things that change the notch's size or live activity.
        player.$index.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        timer.$active.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        calendar.$tick.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        calendar.$events.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        tray.$items.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        tray.$showPocket.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        agent.$pending.sink { [weak self] p in self?.agentChanged(p) }.store(in: &cancellables)

        battery.onPluggedIn = { [weak self] pct in
            guard let self = self, self.settings.isOn(.charging) else { return }
            self.peek(.charging(pct))
        }
        tray.onAdded = { [weak self] n in self?.trayAdded(n) }
        timer.onFinish = { [weak self] msg in
            guard let self = self, self.settings.isOn(.timer) else { return }
            self.peek(.timer(msg))
        }
        calendar.onMeetingSoon = { [weak self] e in
            guard let self = self, self.settings.isOn(.meetings) else { return }
            self.peek(.meeting(e.title))
        }

        $query.dropFirst().removeDuplicates().sink { [weak self] q in self?.queryChanged(q) }.store(in: &cancellables)
        agent.start()
    }

    var needsSignIn: Bool { showSignIn && !signedIn }
    var showingApproval: Bool { settings.isOn(.agents) && !agent.pending.isEmpty }
    var currentMusicTab: MusicTab { settings.visibleMusicTabs.contains(tab) ? tab : .player }

    var liveActivity: LiveActivity {
        if showingApproval { return .agent }
        if settings.isOn(.timer) && timer.active { return .timer }
        if settings.isOn(.meetings), let e = calendar.imminent { return .meeting(e) }
        if settings.isOn(.music) && player.current != nil { return .music }
        return .idle
    }

    /// Size of the black shape (without the top flares) for the current state.
    var size: CGSize {
        let n = notchSize
        let w = Self.panelWidth
        switch state {
        case .collapsed:
            return liveActivity == .idle ? n : CGSize(width: n.width + 96, height: n.height)
        case .peek:
            return CGSize(width: max(n.width + 170, 350), height: n.height + 60)
        case .expanded:
            if showingApproval { return CGSize(width: w, height: n.height + 206) }
            switch section {
            case .home:
                return CGSize(width: w, height: n.height + 262)
            case .music:
                if needsSignIn { return CGSize(width: w, height: n.height + 200) }
                if currentMusicTab == .player { return CGSize(width: w, height: n.height + (player.current == nil ? 170 : 196)) }
                return CGSize(width: w, height: n.height + 380)
            case .tray:
                return CGSize(width: w, height: n.height + (tray.visibleItems.isEmpty ? 176 : 216))
            case .calendar:
                return CGSize(width: w, height: n.height + 300)
            case .tools:
                return CGSize(width: w, height: n.height + 320)
            }
        }
    }

    // MARK: Shape state

    func peek(_ kind: PeekKind) {
        guard state != .expanded else { return }
        if kind == .track && player.current == nil { return }
        peekTask?.cancel()
        peekKind = kind
        withAnimation(Anim.morph) { state = .peek }
        peekTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, self.state == .peek else { return }
            withAnimation(Anim.morph) { self.state = .collapsed }
        }
    }

    func expand(pinned p: Bool = false) {
        peekTask?.cancel()
        pinned = p
        guard state != .expanded else { return }
        if !settings.visibleSections.contains(section) { section = settings.visibleSections[0] }
        withAnimation(Anim.morph) { state = .expanded }
        if section == .music && tab == .library && home.isEmpty { loadHome() }
    }

    func expandForDrop() {
        expand()
        if settings.visibleSections.contains(.tray) { selectSection(.tray) }
    }

    func collapse() {
        guard !showingApproval else { return }
        pinned = false
        guard state != .collapsed else { return }
        withAnimation(Anim.morph) { state = .collapsed }
    }

    func toggle() {
        if state == .expanded { collapse() } else { expand(pinned: true) }
    }

    func selectSection(_ s: NotchSection) {
        withAnimation(Anim.tab) { section = s }
        if s == .calendar { calendar.refresh() }
        if s == .tools && tool == .shortcuts { shortcuts.loadIfNeeded() }
        if s == .music && tab == .library && home.isEmpty { loadHome() }
    }

    func select(_ t: MusicTab) {
        withAnimation(Anim.tab) {
            section = .music
            tab = t
        }
        if t == .search { focusSearchToken += 1 }
        if t == .library && home.isEmpty { loadHome() }
    }

    func selectTool(_ t: ToolKind) {
        withAnimation(Anim.tab) { tool = t }
        if t == .shortcuts { shortcuts.loadIfNeeded() }
    }

    func escape() {
        if showingApproval { return }
        if section == .music && tab == .library && !homeRoute.isEmpty { back(); return }
        if section == .music && tab == .search && !searchRoute.isEmpty { back(); return }
        collapse()
    }

    private func trayAdded(_ n: Int) {
        if state == .expanded {
            if section != .tray && settings.visibleSections.contains(.tray) { selectSection(.tray) }
        } else if settings.isOn(.tray) {
            peek(.tray(n))
        }
    }

    private func agentChanged(_ p: [AgentRequest]) {
        objectWillChange.send()
        guard settings.isOn(.agents) else { return }
        if !p.isEmpty {
            agentPinned = true
            peekTask?.cancel()
            pinned = true
            if state != .expanded { withAnimation(Anim.morph) { state = .expanded } }
        } else if agentPinned {
            agentPinned = false
            pinned = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.collapse() }
        }
    }

    // MARK: Search

    private func queryChanged(_ q: String) {
        if suppressQueryChange { suppressQueryChange = false; return }
        if showingResults { withAnimation(Anim.quick) { showingResults = false } }
        if !searchRoute.isEmpty { searchRoute = [] }
        suggestTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let s = (try? await InnerTube.shared.suggestions(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            self.suggestions = Array(s.prefix(6))
        }
    }

    func submit(_ text: String? = nil) {
        let q = (text ?? query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if q != query { suppressQueryChange = true; query = q }
        suggestTask?.cancel()
        recent.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recent.insert(q, at: 0)
        recent = Array(recent.prefix(6))
        UserDefaults.standard.set(recent, forKey: "recentSearches")
        searchRoute = []
        withAnimation(Anim.tab) { showingResults = true }
        runSearch()
    }

    func setFilter(_ f: SearchFilter) {
        guard f != filter else { return }
        withAnimation(Anim.quick) { filter = f }
        runSearch()
    }

    private func runSearch() {
        let q = query
        let f = filter
        searchTask?.cancel()
        searching = true
        searchError = nil
        searchTask = Task {
            do {
                let r = try await InnerTube.shared.search(q, filter: f)
                guard !Task.isCancelled else { return }
                withAnimation(Anim.quick) { self.results = r }
            } catch {
                if Task.isCancelled { return }
                self.searchError = "Couldn't search. Check your connection."
            }
            self.searching = false
        }
    }

    // MARK: Music navigation

    func activate(_ item: MusicItem, context: [Track]? = nil) {
        switch item {
        case .song(let t): player.play(t, in: context)
        case .collection(let c): open(.collection(c))
        case .artist(let a): open(.artist(a))
        }
    }

    func open(_ r: Route) {
        withAnimation(Anim.tab) {
            section = .music
            if tab == .library {
                homeRoute.append(r)
            } else {
                tab = .search
                searchRoute.append(r)
            }
        }
    }

    func openLibrary(_ r: Route) {
        if !signedIn {
            withAnimation(Anim.morph) { showSignIn = true }
            return
        }
        open(r)
    }

    func back() {
        withAnimation(Anim.tab) {
            if tab == .library { _ = homeRoute.popLast() } else { _ = searchRoute.popLast() }
        }
    }

    func detail(for r: Route) -> DetailModel {
        if let d = detailCache[r] { return d }
        let d = DetailModel(route: r)
        detailCache[r] = d
        return d
    }

    func loadHome() {
        guard !homeLoading else { return }
        homeLoading = true
        homeError = nil
        Task {
            do {
                let h = try await InnerTube.shared.home()
                withAnimation(Anim.quick) { self.home = h }
            } catch {
                self.homeError = "Couldn't load music home."
            }
            self.homeLoading = false
        }
    }

    // MARK: Account and settings

    func refreshAuth() async {
        await InnerTube.shared.refreshCookies()
        signedIn = InnerTube.shared.isSignedIn
        if signedIn { showSignIn = false }
    }

    func skipSignIn() {
        UserDefaults.standard.set(true, forKey: "skippedSignIn")
        withAnimation(Anim.morph) { showSignIn = false }
    }

    func resetLibraryCaches() {
        home = []
        homeRoute = []
        detailCache.removeAll()
        if state == .expanded && section == .music && tab == .library { loadHome() }
    }

    func signOut() {
        Task {
            let store = WKWebsiteDataStore.default()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await store.dataRecords(ofTypes: types)
            let mine = records.filter { $0.displayName.contains("youtube") || $0.displayName.contains("google") }
            await store.removeData(ofTypes: types, for: mine)
            await self.refreshAuth()
            self.resetLibraryCaches()
        }
    }

    var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (build \(b))"
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Drift: launch at login failed: \(error)")
        }
        objectWillChange.send()
    }
}

/// Loads one album, playlist, artist or library page. Cached per route, so going back is instant.
@MainActor
final class DetailModel: ObservableObject {
    let route: Route
    @Published var data: DetailData?
    @Published var error: String?
    private var loading = false

    init(route: Route) {
        self.route = route
        load()
    }

    func load() {
        guard !loading else { return }
        loading = true
        error = nil
        let r = route
        Task {
            do {
                switch r {
                case .collection(let c):
                    self.data = try await InnerTube.shared.collection(c.id)
                case .artist(let a):
                    self.data = try await InnerTube.shared.artist(a.id)
                case .library:
                    let l = try await InnerTube.shared.libraryPlaylists()
                    self.data = DetailData(title: "Your playlists", subtitle: "\(l.count) playlists", thumbnail: nil,
                                           isArtist: false, tracks: [], collections: l)
                }
            } catch {
                self.error = InnerTube.shared.isSignedIn ? "Couldn't load this page." : "Sign in to see this."
            }
            self.loading = false
        }
    }
}
