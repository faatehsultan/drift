import Foundation
import WebKit
import CryptoKit

enum InnerTubeError: LocalizedError {
    case http(Int), badJSON
    var errorDescription: String? {
        switch self {
        case .http(let c): return "YouTube Music returned \(c)"
        case .badJSON: return "Unexpected response"
        }
    }
}

/// Client for YouTube Music's internal "youtubei" API (the one the web app uses).
/// Unofficial: if Google changes it, fixes go here and in Parser.swift.
final class InnerTube {
    static let shared = InnerTube()
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    static let origin = "https://music.youtube.com"

    private let session: URLSession
    private var cookieHeader = ""
    private var sapisid: String?
    var isSignedIn: Bool { sapisid != nil }

    init() {
        let c = URLSessionConfiguration.default
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.timeoutIntervalForRequest = 15
        session = URLSession(configuration: c)
    }

    @MainActor
    func refreshCookies() async {
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        let yt = cookies.filter { $0.domain.hasSuffix("youtube.com") }
        cookieHeader = yt.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        sapisid = yt.first(where: { $0.name == "SAPISID" })?.value
            ?? yt.first(where: { $0.name == "__Secure-3PAPISID" })?.value
    }

    private func authHeader() -> String? {
        guard let sid = sapisid else { return nil }
        let ts = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(ts) \(sid) \(Self.origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(ts)_\(hex)"
    }

    func call(_ endpoint: String, _ body: JSON) async throws -> JSON {
        var payload = body
        let client: JSON = ["clientName": "WEB_REMIX", "clientVersion": "1.20241106.01.00", "hl": "en", "gl": "US"]
        let context: JSON = ["client": client, "user": JSON()]
        payload["context"] = context
        var req = URLRequest(url: URL(string: "\(Self.origin)/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.origin, forHTTPHeaderField: "Origin")
        req.setValue(Self.origin, forHTTPHeaderField: "X-Origin")
        req.setValue(Self.origin + "/", forHTTPHeaderField: "Referer")
        req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        if !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        if let a = authHeader() { req.setValue(a, forHTTPHeaderField: "Authorization") }

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InnerTubeError.http(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? JSON else { throw InnerTubeError.badJSON }
        return obj
    }

    // MARK: Endpoints

    func suggestions(_ q: String) async throws -> [String] {
        let r = try await call("music/get_search_suggestions", ["input": q])
        return findAll("searchSuggestionRenderer", in: r).compactMap { jText(jget($0, "suggestion")).nilIfEmpty }
    }

    func search(_ q: String, filter: SearchFilter) async throws -> SearchResults {
        var body: JSON = ["query": q]
        if let p = filter.params { body["params"] = p }
        return Parser.search(try await call("search", body))
    }

    func home() async throws -> [Shelf] {
        Parser.shelves(try await call("browse", ["browseId": "FEmusic_home"]))
    }

    func collection(_ id: String) async throws -> DetailData {
        Parser.collection(try await call("browse", ["browseId": id]))
    }

    func artist(_ id: String) async throws -> DetailData {
        Parser.artist(try await call("browse", ["browseId": id]))
    }

    func libraryPlaylists() async throws -> [MusicCollection] {
        let r = try await call("browse", ["browseId": "FEmusic_liked_playlists"])
        return findAll("musicTwoRowItemRenderer", in: r).compactMap { any -> MusicCollection? in
            if case .collection(let c)? = Parser.twoRow(any) { return c }
            return nil
        }
    }

    /// The "radio" that YouTube Music builds after a song: used to fill the queue.
    func radio(for videoId: String) async throws -> [Track] {
        let r = try await call("next", [
            "videoId": videoId,
            "playlistId": "RDAMVM" + videoId,
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL"
        ])
        return findAll("playlistPanelVideoRenderer", in: r).compactMap { Parser.panelTrack($0 as? JSON) }
    }

    func like(_ videoId: String, _ on: Bool) async throws {
        _ = try await call(on ? "like/like" : "like/removelike", ["target": ["videoId": videoId]])
    }
}
