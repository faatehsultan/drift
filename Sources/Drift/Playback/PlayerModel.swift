import AppKit
import SwiftUI
import Combine

enum RepeatMode { case off, all, one }

/// Now playing, queue and transport. Owns the audio engine.
@MainActor
final class PlayerModel: ObservableObject, AudioEngineDelegate {
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var index = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoadingTrack = false
    @Published private(set) var isAd = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var scrubPosition: Double?
    @Published private(set) var volume: Double = 0.8
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var likedIds: Set<String> = []
    @Published private(set) var accent: Color = .white

    let trackChanged = PassthroughSubject<Track, Never>()
    /// Called right before Drift starts making sound (used to pause other apps).
    var willStartPlaying: () -> Void = {}
    private let engine = AudioEngine()
    private var radioSeed: String?
    private var lastUserToggle = Date.distantPast

    init() {
        volume = (UserDefaults.standard.object(forKey: "volume") as? Double) ?? 0.8
        engine.delegate = self
        engine.setVolume(volume)
    }

    var current: Track? { queue.indices.contains(index) ? queue[index].track : nil }
    var upNext: [QueueItem] { index + 1 < queue.count ? Array(queue[(index + 1)...]) : [] }

    // MARK: Starting playback

    /// Play a track. With a context (album, playlist) the queue is that list;
    /// without one, the queue is the track plus YouTube Music's radio for it.
    func play(_ track: Track, in context: [Track]? = nil) {
        if let ctx = context, let i = ctx.firstIndex(where: { $0.videoId == track.videoId }) {
            queue = ctx.map { QueueItem(track: $0) }
            index = i
        } else {
            queue = [QueueItem(track: track)]
            index = 0
        }
        radioSeed = nil
        if shuffle { shuffleUpcoming() }
        startCurrent()
        if context == nil { loadRadio(seed: track) }
    }

    func playCollection(_ tracks: [Track], shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        var list = tracks
        if shuffled { list.shuffle() }
        queue = list.map { QueueItem(track: $0) }
        index = 0
        radioSeed = nil
        shuffle = shuffled
        startCurrent()
    }

    private func startCurrent() {
        guard let t = current else { return }
        position = 0
        duration = parseDuration(t.durationText) ?? 0
        willStartPlaying()
        isPlaying = true
        isLoadingTrack = true
        isAd = false
        engine.play(t.videoId)
        trackChanged.send(t)
        updateAccent(for: t)
    }

    private func loadRadio(seed: Track) {
        radioSeed = seed.videoId
        Task {
            guard let list = try? await InnerTube.shared.radio(for: seed.videoId) else { return }
            guard self.queue.contains(where: { $0.track.videoId == seed.videoId }) else { return }
            let existing = Set(self.queue.map { $0.track.videoId })
            self.queue += list.filter { !existing.contains($0.videoId) }.map { QueueItem(track: $0) }
        }
    }

    private func topUpIfNeeded() {
        guard let c = current, upNext.count < 3, radioSeed != c.videoId else { return }
        loadRadio(seed: c)
    }

    // MARK: Transport

    func togglePlay() {
        guard current != nil else { return }
        lastUserToggle = Date()
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            willStartPlaying()
            engine.resume()
            isPlaying = true
        }
    }

    /// Another app started playing: step aside.
    func pauseForOtherAudio() {
        guard isPlaying else { return }
        lastUserToggle = Date()
        engine.pause()
        isPlaying = false
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if auto && repeatMode == .one { seek(0); engine.resume(); return }
        if index + 1 < queue.count {
            index += 1
            startCurrent()
        } else if repeatMode == .all {
            index = 0
            startCurrent()
        } else if let c = current {
            Task {
                let more = (try? await InnerTube.shared.radio(for: c.videoId)) ?? []
                let existing = Set(self.queue.map { $0.track.videoId })
                let fresh = more.filter { !existing.contains($0.videoId) }
                guard !fresh.isEmpty else { self.isPlaying = false; return }
                self.queue += fresh.map { QueueItem(track: $0) }
                self.index += 1
                self.startCurrent()
            }
            return
        }
        topUpIfNeeded()
    }

    func previous() {
        guard current != nil else { return }
        if position > 3 || index <= 0 { seek(0) } else { index -= 1; startCurrent() }
    }

    func seek(_ seconds: Double) {
        position = seconds
        engine.seek(seconds)
    }

    func setVolume(_ v: Double) {
        volume = min(1, max(0, v))
        UserDefaults.standard.set(volume, forKey: "volume")
        engine.setVolume(volume)
    }

    func nudgeVolume(_ delta: Double) { setVolume(volume + delta) }

    func toggleShuffle() {
        shuffle.toggle()
        if shuffle { shuffleUpcoming() }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func shuffleUpcoming() {
        guard index + 1 < queue.count else { return }
        var rest = Array(queue[(index + 1)...])
        rest.shuffle()
        queue.replaceSubrange((index + 1)..., with: rest)
    }

    func toggleLike() {
        guard let t = current else { return }
        let on = !likedIds.contains(t.videoId)
        if on { likedIds.insert(t.videoId) } else { likedIds.remove(t.videoId) }
        Task { try? await InnerTube.shared.like(t.videoId, on) }
    }

    // MARK: Queue editing

    func jump(to item: QueueItem) {
        guard let i = queue.firstIndex(of: item) else { return }
        index = i
        startCurrent()
        topUpIfNeeded()
    }

    func remove(_ item: QueueItem) {
        guard let i = queue.firstIndex(of: item), i != index else { return }
        queue.remove(at: i)
        if i < index { index -= 1 }
    }

    func moveUpNext(from: IndexSet, to: Int) {
        var rest = upNext
        rest.move(fromOffsets: from, toOffset: to)
        queue.replaceSubrange((index + 1)..., with: rest)
    }

    func playNext(_ t: Track) {
        guard current != nil else { play(t); return }
        queue.insert(QueueItem(track: t), at: index + 1)
    }

    func addToQueue(_ t: Track) {
        guard current != nil else { play(t); return }
        queue.append(QueueItem(track: t))
    }

    func clearUpNext() {
        guard index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
    }

    // MARK: Engine callbacks

    func engineTick(position p: Double, duration d: Double, paused: Bool, isAd ad: Bool) {
        if isAd != ad { isAd = ad }
        guard !ad else { return }
        if scrubPosition == nil && abs(position - p) > 0.05 { position = p }
        if d > 0 && abs(duration - d) > 0.5 { duration = d }
        if isLoadingTrack {
            if p > 0.3 && !paused { isLoadingTrack = false; isPlaying = true }
        } else if Date().timeIntervalSince(lastUserToggle) > 1.2 && isPlaying == paused {
            isPlaying = !paused
        }
    }

    func engineEnded() { next(auto: true) }

    func engineStarted() {
        isLoadingTrack = false
        isPlaying = true
    }

    // MARK: Accent color from artwork

    private func updateAccent(for t: Track) {
        guard let url = t.thumbnail else { accent = .white; return }
        Task {
            guard let img = await ImageCache.shared.image(for: url), self.current?.videoId == t.videoId else { return }
            let c = img.vibrantColor()
            withAnimation(.easeInOut(duration: 0.6)) { self.accent = c }
        }
    }
}
