import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

/// Synced lyrics from LRCLIB (free, no key), with plain lyrics as a fallback.
@MainActor
final class LyricsModel: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plain: String?
    @Published private(set) var loading = false

    private var forId: String?
    private var task: Task<Void, Never>?

    func load(for t: Track) {
        guard t.videoId != forId else { return }
        forId = t.videoId
        lines = []
        plain = nil
        loading = true
        task?.cancel()
        let title = Self.clean(t.title)
        let artist = t.artist.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? t.artist
        let duration = parseDuration(t.durationText)
        let id = t.videoId
        task = Task {
            let result = await Self.fetch(title: title, artist: artist, duration: duration)
            guard !Task.isCancelled, self.forId == id else { return }
            if let s = result.synced { self.lines = Self.parseLRC(s) }
            if self.lines.isEmpty { self.plain = result.plain }
            self.loading = false
        }
    }

    /// Index of the line that should be highlighted at this playback position.
    func index(at position: Double) -> Int {
        var idx = -1
        for l in lines {
            if l.time <= position + 0.3 { idx = l.id } else { break }
        }
        return idx
    }

    nonisolated static func clean(_ title: String) -> String {
        let pattern = #"\s*[\(\[][^\)\]]*(official|video|audio|lyric|visualizer|mv|hd|4k|remaster)[^\)\]]*[\)\]]"#
        return title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func fetch(title: String, artist: String, duration: Double?) async -> (synced: String?, plain: String?) {
        var results = await search([URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)])
        if results.isEmpty { results = await search([URLQueryItem(name: "q", value: "\(artist) \(title)")]) }
        guard !results.isEmpty else { return (nil, nil) }
        let synced = results.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
        let pool = synced.isEmpty ? results : synced
        let best: [String: Any]
        if let d = duration {
            best = pool.min { abs(((($0["duration"] as? Double) ?? 0) - d)) < abs(((($1["duration"] as? Double) ?? 0) - d)) } ?? pool[0]
        } else {
            best = pool[0]
        }
        return (best["syncedLyrics"] as? String, best["plainLyrics"] as? String)
    }

    nonisolated static func search(_ items: [URLQueryItem]) async -> [[String: Any]] {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = items
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Drift/1.0 (macOS notch player)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let res = try? await URLSession.shared.data(for: req),
              let arr = (try? JSONSerialization.jsonObject(with: res.0)) as? [[String: Any]] else { return [] }
        return arr
    }

    nonisolated static func parseLRC(_ s: String) -> [LyricLine] {
        guard let rx = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#) else { return [] }
        var out: [(Double, String)] = []
        for raw in s.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let full = NSRange(location: 0, length: ns.length)
            let matches = rx.matches(in: raw, range: full)
            guard !matches.isEmpty else { continue }
            let text = rx.stringByReplacingMatches(in: raw, range: full, withTemplate: "").trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                out.append((mm * 60 + ss, text))
            }
        }
        return out.sorted { $0.0 < $1.0 }.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1.isEmpty ? "♪" : $0.element.1)
        }
    }
}
