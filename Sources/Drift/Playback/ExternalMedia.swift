import AppKit
import SwiftUI

/// What another app (Chrome, Safari, Arc, Spotify, Music…) reports as now playing.
struct ExternalInfo: Equatable {
    var bundleId: String
    var appName: String
    var title: String
    var artist: String
    var album: String
    var playing: Bool
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var artwork: NSImage?

    /// Playback position, extrapolated from the last report.
    func position(at now: Date = Date()) -> Double {
        let p = elapsed + (playing ? now.timeIntervalSince(timestamp) : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Reads system-wide Now Playing through the bundled MediaRemote adapter
/// (Apple's own /usr/bin/perl is allowed to use MediaRemote on macOS 15.4+),
/// and sends basic commands back: play, pause, next, previous, seek.
@MainActor
final class ExternalMediaModel: ObservableObject {
    @Published private(set) var info: ExternalInfo?
    @Published private(set) var accent: Color = .white
    @Published private(set) var available = false

    var onStartedPlaying: () -> Void = {}
    var onTrackChanged: () -> Void = {}

    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var restartDelay: Double = 1
    private var lastArtworkData: String?
    private var suppressStartUntil = Date.distantPast
    private var stopping = false
    private let ownBundle = Bundle.main.bundleIdentifier ?? "com.drift.player"
    private static var appNames: [String: String] = [:]

    private var scriptURL: URL? { Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") }
    private var frameworkURL: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
    }

    // MARK: Stream

    func start() {
        guard process == nil, let s = scriptURL, let f = frameworkURL,
              FileManager.default.fileExists(atPath: f.path) else { return }
        stopping = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [s.path, f.path, "stream", "--micros", "--debounce=250"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.streamEnded() }
        }
        do {
            try p.run()
            process = p
            available = true
        } catch {
            available = false
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
        state = [:]
        buffer = Data()
        info = nil
        available = false
    }

    private func streamEnded() {
        process = nil
        available = false
        guard !stopping, AppSettings.shared.externalMedia else { return }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start() }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard !line.isEmpty,
              let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return }
        restartDelay = 1
        if (obj["diff"] as? Bool) == true {
            for (k, v) in payload {
                if v is NSNull { state.removeValue(forKey: k) } else { state[k] = v }
            }
        } else {
            state = payload
        }
        rebuild()
    }

    private func rebuild() {
        guard let bid = state["bundleIdentifier"] as? String,
              let title = state["title"] as? String, !title.isEmpty else {
            info = nil
            return
        }
        let parent = state["parentApplicationBundleIdentifier"] as? String
        // Drift's own hidden player shows up in Now Playing too. Never treat it as "another app".
        if bid == ownBundle || parent == ownBundle {
            info = nil
            return
        }
        let appBid = parent ?? bid
        var art = info?.artwork
        if let b64 = state["artworkData"] as? String {
            if b64 != lastArtworkData {
                lastArtworkData = b64
                art = Data(base64Encoded: b64).flatMap { NSImage(data: $0) }
            }
        } else if info?.title != title {
            lastArtworkData = nil
            art = nil
        }
        let new = ExternalInfo(
            bundleId: appBid,
            appName: Self.appName(appBid),
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            playing: state["playing"] as? Bool ?? false,
            duration: (state["durationMicros"] as? Double ?? 0) / 1_000_000,
            elapsed: (state["elapsedTimeMicros"] as? Double ?? 0) / 1_000_000,
            timestamp: (state["timestampEpochMicros"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date(),
            artwork: art)
        let old = info
        info = new
        if old?.artwork !== new.artwork {
            let c = new.artwork?.vibrantColor() ?? .white
            withAnimation(.easeInOut(duration: 0.5)) { accent = c }
        }
        if (old?.title != new.title || old?.bundleId != new.bundleId) && new.playing { onTrackChanged() }
        if new.playing && !(old?.playing ?? false) && Date() > suppressStartUntil { onStartedPlaying() }
    }

    static func appName(_ bid: String) -> String {
        if let n = appNames[bid] { return n }
        var name = bid
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        appNames[bid] = name
        return name
    }

    static func appIcon(_ bid: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Commands

    func togglePlay() {
        guard var i = info else { return }
        i.elapsed = i.position()
        i.timestamp = Date()
        i.playing.toggle()
        info = i
        if i.playing { suppressStartUntil = Date().addingTimeInterval(1.5) }
        send(2)
    }

    func play() { send(0) }

    /// Pause because Drift started playing. Ignores the "started" echo for a moment.
    func pauseForDrift() {
        guard var i = info, i.playing else { return }
        i.elapsed = i.position()
        i.timestamp = Date()
        i.playing = false
        info = i
        send(1)
    }

    func next() { send(4) }
    func previous() { send(5) }

    func seek(_ seconds: Double) {
        if var i = info {
            i.elapsed = seconds
            i.timestamp = Date()
            info = i
        }
        run(["seek", "\(Int(seconds * 1_000_000))"])
    }

    private func send(_ command: Int) { run(["send", "\(command)"]) }

    private func run(_ args: [String]) {
        guard let s = scriptURL, let f = frameworkURL else { return }
        let all = [s.path, f.path] + args
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = all
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }
}
