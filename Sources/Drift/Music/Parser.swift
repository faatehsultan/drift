import Foundation

/// Turns YouTube Music's renderer JSON into our models. Deliberately forgiving:
/// it searches for the pieces it needs instead of relying on exact paths.
enum Parser {

    static func kind(_ endpoint: Any?) -> PageKind {
        guard let t = jget(endpoint, "browseEndpoint", "browseEndpointContextSupportedConfigs",
                           "browseEndpointContextMusicConfig", "pageType") as? String else { return .other }
        switch t {
        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL", "MUSIC_PAGE_TYPE_LIBRARY_ARTIST": return .artist
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK": return .album
        case "MUSIC_PAGE_TYPE_PLAYLIST": return .playlist
        default: return .other
        }
    }

    static func browseId(_ e: Any?) -> String? { jget(e, "browseEndpoint", "browseId") as? String }

    struct Credits {
        var artist = ""
        var artistId: String?
        var album: String?
        var albumId: String?
        var duration: String?
    }

    static let kindLabels: Set<String> = ["Song", "Video", "Album", "Single", "EP", "Artist", "Playlist",
                                          "Episode", "Podcast", "Profile", "Station", "Community playlist"]

    static func credits(_ runs: [JSON]) -> Credits {
        var c = Credits()
        var artists: [String] = []
        var plain: [String] = []
        for r in runs {
            guard let raw = r["text"] as? String else { continue }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t == "•" || t == "&" || t == "," { continue }
            let ep = r["navigationEndpoint"]
            switch kind(ep) {
            case .artist:
                artists.append(t)
                if c.artistId == nil { c.artistId = browseId(ep) }
            case .album:
                c.album = t
                c.albumId = browseId(ep)
            default:
                if t.range(of: #"^\d+(:\d{2})+$"#, options: .regularExpression) != nil {
                    c.duration = t
                } else {
                    plain.append(t)
                }
            }
        }
        if artists.isEmpty, let first = plain.first(where: { p in
            !kindLabels.contains(p) && !p.contains("views") && !p.contains("plays") &&
            !p.contains("subscribers") && !p.contains("songs") &&
            p.range(of: #"^\d{4}$"#, options: .regularExpression) == nil
        }) {
            artists = [first]
        }
        c.artist = artists.joined(separator: ", ")
        return c
    }

    static func subtitle(_ runs: [JSON]) -> String {
        runs.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: Items

    static func listItem(_ any: Any?) -> MusicItem? {
        guard let r = any as? JSON else { return nil }
        let cols = (r["flexColumns"] as? [Any]) ?? []
        func col(_ i: Int) -> Any? { jget(cols, i, "musicResponsiveListItemFlexColumnRenderer", "text") }
        let title = jText(col(0))
        guard !title.isEmpty else { return nil }
        var sub: [JSON] = []
        if cols.count > 1 { for i in 1..<cols.count { sub += jRuns(col(i)) } }
        let cr = credits(sub)
        let thumb = jThumb(r["thumbnail"])
        let nav = r["navigationEndpoint"]
        let k = kind(nav)
        if let bid = browseId(nav), k != .other {
            if k == .artist { return .artist(ArtistRef(id: bid, name: title, subtitle: subtitle(sub), thumbnail: thumb)) }
            return .collection(MusicCollection(id: bid, title: title, subtitle: subtitle(sub), thumbnail: thumb, kind: k))
        }
        let vid = (jget(r, "playlistItemData", "videoId") as? String)
            ?? (jget(r, "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                     "playNavigationEndpoint", "watchEndpoint", "videoId") as? String)
            ?? (jget(jRuns(col(0)).first, "navigationEndpoint", "watchEndpoint", "videoId") as? String)
        guard let videoId = vid else { return nil }
        var dur = cr.duration
        if dur == nil {
            dur = jText(jget(r, "fixedColumns", 0, "musicResponsiveListItemFixedColumnRenderer", "text")).nilIfEmpty
        }
        return .song(Track(videoId: videoId, title: title, artist: cr.artist, artistId: cr.artistId,
                           album: cr.album, albumId: cr.albumId, thumbnail: thumb, durationText: dur))
    }

    static func twoRow(_ any: Any?) -> MusicItem? {
        guard let r = any as? JSON else { return nil }
        let title = jText(r["title"])
        guard !title.isEmpty else { return nil }
        let subRuns = jRuns(r["subtitle"])
        let sub = subtitle(subRuns)
        let thumb = jThumb(r["thumbnailRenderer"])
        let nav = r["navigationEndpoint"]
        let k = kind(nav)
        if let bid = browseId(nav) {
            if k == .artist { return .artist(ArtistRef(id: bid, name: title, subtitle: sub, thumbnail: thumb)) }
            return .collection(MusicCollection(id: bid, title: title, subtitle: sub, thumbnail: thumb,
                                               kind: k == .other ? .playlist : k))
        }
        if let vid = jget(nav, "watchEndpoint", "videoId") as? String {
            let cr = credits(subRuns)
            return .song(Track(videoId: vid, title: title, artist: cr.artist, artistId: cr.artistId,
                               album: cr.album, albumId: cr.albumId, thumbnail: thumb, durationText: cr.duration))
        }
        if let pid = jget(nav, "watchPlaylistEndpoint", "playlistId") as? String {
            return .collection(MusicCollection(id: "VL" + pid, title: title, subtitle: sub, thumbnail: thumb, kind: .playlist))
        }
        return nil
    }

    static func cardItem(_ c: JSON) -> MusicItem? {
        let title = jText(c["title"])
        guard !title.isEmpty else { return nil }
        let sub = jRuns(c["subtitle"])
        let thumb = jThumb(c["thumbnail"])
        let nav = jRuns(c["title"]).first?["navigationEndpoint"]
        let k = kind(nav)
        if let bid = browseId(nav) {
            if k == .artist { return .artist(ArtistRef(id: bid, name: title, subtitle: subtitle(sub), thumbnail: thumb)) }
            return .collection(MusicCollection(id: bid, title: title, subtitle: subtitle(sub), thumbnail: thumb,
                                               kind: k == .other ? .playlist : k))
        }
        if let vid = jget(nav, "watchEndpoint", "videoId") as? String {
            let cr = credits(sub)
            return .song(Track(videoId: vid, title: title, artist: cr.artist, artistId: cr.artistId,
                               album: cr.album, albumId: cr.albumId, thumbnail: thumb, durationText: cr.duration))
        }
        return nil
    }

    static func panelTrack(_ r: JSON?) -> Track? {
        guard let r = r, let vid = r["videoId"] as? String else { return nil }
        let c = credits(jRuns(r["longBylineText"]))
        let artist = c.artist.isEmpty ? jText(r["shortBylineText"]) : c.artist
        return Track(videoId: vid, title: jText(r["title"]), artist: artist, artistId: c.artistId,
                     album: c.album, albumId: c.albumId, thumbnail: jThumb(r["thumbnail"]),
                     durationText: jText(r["lengthText"]).nilIfEmpty)
    }

    // MARK: Pages

    static func search(_ r: JSON) -> SearchResults {
        var top: MusicItem?
        var items: [MusicItem] = []
        var seen = Set<String>()
        func add(_ i: MusicItem?) {
            guard let i = i, !seen.contains(i.id) else { return }
            seen.insert(i.id)
            items.append(i)
        }
        for card in findAll("musicCardShelfRenderer", in: r) {
            guard let c = card as? JSON else { continue }
            if top == nil, let t = cardItem(c) { top = t; seen.insert(t.id) }
            for x in (c["contents"] as? [Any]) ?? [] { add(listItem(jget(x, "musicResponsiveListItemRenderer"))) }
        }
        for shelf in findAll("musicShelfRenderer", in: r) {
            for x in (jget(shelf, "contents") as? [Any]) ?? [] { add(listItem(jget(x, "musicResponsiveListItemRenderer"))) }
        }
        return SearchResults(top: top, items: items)
    }

    static func shelves(_ r: JSON) -> [Shelf] {
        findAll("musicCarouselShelfRenderer", in: r).compactMap { s -> Shelf? in
            let title = jText(jget(s, "header", "musicCarouselShelfBasicHeaderRenderer", "title"))
            let items = ((jget(s, "contents") as? [Any]) ?? []).compactMap { c -> MusicItem? in
                if let t = jget(c, "musicTwoRowItemRenderer") { return twoRow(t) }
                if let l = jget(c, "musicResponsiveListItemRenderer") { return listItem(l) }
                return nil
            }
            return items.isEmpty ? nil : Shelf(title: title.isEmpty ? "For you" : title, items: items)
        }
    }

    static func firstDict(_ keys: [String], in r: Any) -> JSON {
        for k in keys {
            if let d = findAll(k, in: r, limit: 1).first as? JSON { return d }
        }
        return [:]
    }

    static func collection(_ r: JSON) -> DetailData {
        let header = firstDict(["musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer"], in: r)
        let title = jText(header["title"])
        let strap = jText(header["straplineTextOne"])
        let sub = [strap, jText(header["subtitle"]), jText(header["secondSubtitle"])]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let thumb = jThumb(header["thumbnail"]) ?? jThumb(header)
        var tracks: [Track] = []
        for it in findAll("musicResponsiveListItemRenderer", in: r) {
            if case .song(var t)? = listItem(it) {
                if t.thumbnail == nil { t.thumbnail = thumb }
                if t.artist.isEmpty { t.artist = strap }
                if t.album == nil, !title.isEmpty { t.album = title }
                tracks.append(t)
            }
        }
        return DetailData(title: title, subtitle: sub, thumbnail: thumb, isArtist: false, tracks: tracks, collections: [])
    }

    static func artist(_ r: JSON) -> DetailData {
        let header = firstDict(["musicImmersiveHeaderRenderer", "musicVisualHeaderRenderer", "musicResponsiveHeaderRenderer"], in: r)
        let name = jText(header["title"])
        let thumb = jThumb(header["thumbnail"]) ?? jThumb(header["foregroundThumbnail"]) ?? jThumb(header)
        var subs = jText(jget(header, "subscriptionButton", "subscribeButtonRenderer", "subscriberCountText"))
        if !subs.isEmpty && !subs.contains("subscriber") { subs += " subscribers" }

        var tracks: [Track] = []
        for shelf in findAll("musicShelfRenderer", in: r) {
            for x in (jget(shelf, "contents") as? [Any]) ?? [] {
                if case .song(var t)? = listItem(jget(x, "musicResponsiveListItemRenderer")) {
                    if t.artist.isEmpty { t.artist = name }
                    tracks.append(t)
                }
            }
        }
        var albums: [MusicCollection] = []
        var seen = Set<String>()
        for s in findAll("musicCarouselShelfRenderer", in: r) {
            for x in (jget(s, "contents") as? [Any]) ?? [] {
                if case .collection(let c)? = twoRow(jget(x, "musicTwoRowItemRenderer")), c.kind == .album, !seen.contains(c.id) {
                    seen.insert(c.id)
                    albums.append(c)
                }
            }
        }
        return DetailData(title: name, subtitle: subs.isEmpty ? "Artist" : subs, thumbnail: thumb,
                          isArtist: true, tracks: tracks, collections: albums)
    }
}
