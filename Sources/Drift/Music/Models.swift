import Foundation

struct Track: Hashable {
    let videoId: String
    var title: String
    var artist: String
    var artistId: String?
    var album: String?
    var albumId: String?
    var thumbnail: URL?
    var durationText: String?
}

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let track: Track
}

enum PageKind: Hashable { case album, artist, playlist, other }

struct MusicCollection: Hashable {
    let id: String
    var title: String
    var subtitle: String
    var thumbnail: URL?
    var kind: PageKind
}

struct ArtistRef: Hashable {
    let id: String
    var name: String
    var subtitle: String
    var thumbnail: URL?
}

enum MusicItem: Identifiable, Hashable {
    case song(Track)
    case collection(MusicCollection)
    case artist(ArtistRef)

    var id: String {
        switch self {
        case .song(let t): return "s:" + t.videoId
        case .collection(let c): return "c:" + c.id
        case .artist(let a): return "a:" + a.id
        }
    }
}

struct Shelf: Identifiable {
    let id = UUID()
    var title: String
    var items: [MusicItem]
}

enum SearchFilter: String, CaseIterable, Hashable {
    case top = "Top", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists"

    var params: String? {
        switch self {
        case .top: return nil
        case .songs: return "EgWKAQIIAWoMEA4QChADEAQQCRAF"
        case .albums: return "EgWKAQIYAWoMEA4QChADEAQQCRAF"
        case .artists: return "EgWKAQIgAWoMEA4QChADEAQQCRAF"
        case .playlists: return "EgWKAQIoAWoMEA4QChADEAQQCRAF"
        }
    }
}

struct SearchResults {
    var top: MusicItem?
    var items: [MusicItem]
    static let empty = SearchResults(top: nil, items: [])
}

struct DetailData {
    var title: String
    var subtitle: String
    var thumbnail: URL?
    var isArtist: Bool
    var tracks: [Track]
    var collections: [MusicCollection]
}

enum Route: Hashable {
    case collection(MusicCollection)
    case artist(ArtistRef)
    case library
}

func parseDuration(_ s: String?) -> Double? {
    guard let s = s, !s.isEmpty else { return nil }
    let parts = s.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let i = Int(s)
    if i >= 3600 { return String(format: "%d:%02d:%02d", i / 3600, (i % 3600) / 60, i % 60) }
    return String(format: "%d:%02d", i / 60, i % 60)
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
