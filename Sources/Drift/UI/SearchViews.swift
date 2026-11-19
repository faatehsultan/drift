import SwiftUI
import AppKit

struct SearchTab: View {
    @ObservedObject var model: NotchModel
    let player: PlayerModel

    var body: some View {
        if let route = model.searchRoute.last {
            DetailView(model: model, player: player, route: route)
                .id(route)
                .transition(ExpandedView.slide(.trailing))
        } else {
            VStack(spacing: 0) {
                SearchField(model: model).padding(.horizontal, 16).padding(.top, 2)
                if model.showingResults {
                    ResultsView(model: model, player: player).transition(.opacity)
                } else {
                    SuggestionsView(model: model).transition(.opacity)
                }
            }
            .transition(.opacity)
        }
    }
}

struct SearchField: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            NativeSearchField(model: model, focusToken: model.focusSearchToken)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            if !model.query.isEmpty {
                IconButton(systemName: "xmark.circle.fill", size: 12, color: .white.opacity(0.5), help: "Clear") {
                    model.query = ""
                    model.focusSearchToken += 1
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(model.showingResults ? 0 : 0.28), lineWidth: 1)
        )
        .animation(Anim.quick, value: model.showingResults)
    }
}

/// Plain AppKit text field: reliable focus inside a non-activating panel, no SwiftUI state.
struct NativeSearchField: NSViewRepresentable {
    let model: NotchModel
    let focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 13)
        f.textColor = .white
        f.usesSingleLineMode = true
        f.maximumNumberOfLines = 1
        f.lineBreakMode = .byTruncatingTail
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        f.placeholderAttributedString = NSAttributedString(
            string: "Search songs, artists, albums",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 13)])
        f.delegate = context.coordinator
        f.stringValue = model.query
        context.coordinator.lastToken = focusToken
        DispatchQueue.main.async {
            if f.window?.isKeyWindow == true { f.window?.makeFirstResponder(f) }
        }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        if f.stringValue != model.query { f.stringValue = model.query }
        if context.coordinator.lastToken != focusToken {
            context.coordinator.lastToken = focusToken
            DispatchQueue.main.async {
                f.window?.makeKey()
                f.window?.makeFirstResponder(f)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: NotchModel
        var lastToken = 0

        init(model: NotchModel) { self.model = model }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            model.query = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                model.submit()
                return true
            }
            return false
        }
    }
}

struct SuggestionsView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.suggestions.isEmpty {
                    SectionLabel("Suggestions")
                    ForEach(model.suggestions, id: \.self) { s in
                        TextRow(icon: "magnifyingglass", text: s, trailing: "arrow.up.left") { model.submit(s) }
                    }
                }
                if !model.recent.isEmpty {
                    SectionLabel("Recent")
                    ForEach(model.recent, id: \.self) { s in
                        TextRow(icon: "clock", text: s, trailing: nil) { model.submit(s) }
                    }
                }
                if model.suggestions.isEmpty && model.recent.isEmpty {
                    MessageView(icon: "magnifyingglass", title: "Search YouTube Music",
                                subtitle: "Songs, artists, albums and playlists.")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

struct TextRow: View {
    let icon: String
    let text: String
    let trailing: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 16)
            Text(text).font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing = trailing {
                Image(systemName: trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(HoverFill(selected: false))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct ResultsView: View {
    @ObservedObject var model: NotchModel
    let player: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SearchFilter.allCases, id: \.self) { f in
                        Chip(title: f.rawValue, on: model.filter == f) { model.setFilter(f) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)

            if model.searching && model.results.items.isEmpty && model.results.top == nil {
                Spinner()
            } else if let e = model.searchError {
                MessageView(icon: "wifi.exclamationmark", title: e, actionTitle: "Try again") { model.submit() }
            } else if displayItems.isEmpty {
                MessageView(icon: "magnifyingglass", title: "No results", subtitle: "Try a different search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayItems) { item in
                            ItemRow(item: item, model: model, player: player)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .opacity(model.searching ? 0.5 : 1)
                .animation(Anim.quick, value: model.searching)
            }
        }
    }

    private var displayItems: [MusicItem] {
        var all = model.results.items
        if model.filter == .top, let top = model.results.top {
            all.removeAll { $0.id == top.id }
            all.insert(top, at: 0)
        }
        return all
    }
}

struct ItemRow: View {
    let item: MusicItem
    let model: NotchModel
    let player: PlayerModel

    var body: some View {
        switch item {
        case .song(let t):
            SongRow(track: t, model: model, player: player)
        case .collection(let c):
            NavRow(title: c.title, subtitle: c.subtitle, thumb: c.thumbnail, circle: false, icon: "square.stack") {
                model.open(.collection(c))
            }
        case .artist(let a):
            NavRow(title: a.name, subtitle: a.subtitle.isEmpty ? "Artist" : a.subtitle, thumb: a.thumbnail,
                   circle: true, icon: "person.fill") {
                model.open(.artist(a))
            }
        }
    }
}

struct SongRow: View {
    let track: Track
    let model: NotchModel
    @ObservedObject var player: PlayerModel
    var context: [Track]? = nil
    var tapAction: (() -> Void)? = nil

    var body: some View {
        let isCurrent = player.current?.videoId == track.videoId
        HStack(spacing: 10) {
            ZStack {
                Art(track.thumbnail, size: 36, radius: 6)
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.5))
                    EqualizerView(playing: player.isPlaying, color: .white, maxHeight: 11).frame(width: 14, height: 11)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isCurrent ? player.accent : .white)
                    .lineLimit(1)
                Text(track.artist).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let d = track.durationText {
                Text(d).font(.system(size: 11).monospacedDigit()).foregroundColor(.white.opacity(0.45))
            }
            TrackMenu(track: track, model: model, player: player)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(HoverFill(selected: isCurrent))
        .contentShape(Rectangle())
        .onTapGesture {
            if let a = tapAction { a() } else { player.play(track, in: context) }
        }
        .contextMenu { TrackMenuItems(track: track, model: model, player: player) }
    }
}

struct NavRow: View {
    let title: String
    let subtitle: String
    let thumb: URL?
    let circle: Bool
    let icon: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Art(thumb, size: 36, radius: 6, circle: circle, icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(HoverFill(selected: false))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct TrackMenu: View {
    let track: Track
    let model: NotchModel
    let player: PlayerModel

    var body: some View {
        Menu {
            TrackMenuItems(track: track, model: model, player: player)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct TrackMenuItems: View {
    let track: Track
    let model: NotchModel
    let player: PlayerModel

    var body: some View {
        Button("Play next") { player.playNext(track) }
        Button("Add to queue") { player.addToQueue(track) }
        if let id = track.albumId {
            Button("Go to album") {
                model.open(.collection(MusicCollection(id: id, title: track.album ?? "Album", subtitle: track.artist,
                                                       thumbnail: track.thumbnail, kind: .album)))
            }
        }
        if let id = track.artistId {
            Button("Go to artist") {
                model.open(.artist(ArtistRef(id: id, name: track.artist, subtitle: "Artist", thumbnail: nil)))
            }
        }
    }
}

struct DetailView: View {
    let model: NotchModel
    let player: PlayerModel
    @ObservedObject var detail: DetailModel

    init(model: NotchModel, player: PlayerModel, route: Route) {
        self.model = model
        self.player = player
        self._detail = ObservedObject(wrappedValue: model.detail(for: route))
    }

    var body: some View {
        let h = header
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconButton(systemName: "chevron.left", size: 13, help: "Back") { model.back() }
                Art(h.thumb, size: 72, radius: 12, circle: h.isArtist, icon: h.isArtist ? "person.fill" : "music.note.list")
                VStack(alignment: .leading, spacing: 3) {
                    Text(h.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                    Text(h.subtitle).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let tracks = detail.data?.tracks, !tracks.isEmpty {
                    PillButton(title: "Play", icon: "play.fill") { player.playCollection(tracks) }
                    IconButton(systemName: "shuffle", size: 14, help: "Shuffle") { player.playCollection(tracks, shuffled: true) }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.top, 2)
            .padding(.bottom, 8)

            if let d = detail.data {
                list(d)
            } else if let e = detail.error {
                MessageView(icon: "exclamationmark.triangle", title: e, actionTitle: "Try again") { detail.load() }
            } else {
                Spinner()
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func list(_ d: DetailData) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if d.isArtist && !d.tracks.isEmpty { SectionLabel("Top songs") }
                ForEach(Array(d.tracks.enumerated()), id: \.offset) { pair in
                    SongRow(track: pair.element, model: model, player: player, context: d.tracks)
                }
                if !d.collections.isEmpty {
                    if d.isArtist {
                        SectionLabel("Albums")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(d.collections, id: \.id) { c in
                                    AlbumCard(c: c) { model.open(.collection(c)) }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    } else {
                        ForEach(d.collections, id: \.id) { c in
                            NavRow(title: c.title, subtitle: c.subtitle, thumb: c.thumbnail, circle: false,
                                   icon: "music.note.list") { model.open(.collection(c)) }
                        }
                    }
                }
                if d.tracks.isEmpty && d.collections.isEmpty {
                    MessageView(icon: "music.note", title: "Nothing here yet")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    private var header: (title: String, subtitle: String, thumb: URL?, isArtist: Bool) {
        var title = ""
        var subtitle = ""
        var thumb: URL? = nil
        var isArtist = false
        switch detail.route {
        case .collection(let c): title = c.title; subtitle = c.subtitle; thumb = c.thumbnail
        case .artist(let a): title = a.name; subtitle = a.subtitle; thumb = a.thumbnail; isArtist = true
        case .library: title = "Your playlists"
        }
        if let d = detail.data {
            if !d.title.isEmpty { title = d.title }
            if !d.subtitle.isEmpty { subtitle = d.subtitle }
            if d.thumbnail != nil { thumb = d.thumbnail }
        }
        return (title, subtitle, thumb, isArtist)
    }
}

struct AlbumCard: View {
    let c: MusicCollection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Art(c.thumbnail, size: 96, radius: 10, icon: "square.stack")
                Text(c.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text(c.subtitle).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(PressStyle())
    }
}
