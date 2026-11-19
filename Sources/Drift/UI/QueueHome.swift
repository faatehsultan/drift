import SwiftUI

struct QueueTab: View {
    let model: NotchModel
    @ObservedObject var player: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            if let cur = player.current {
                HStack {
                    Text("Queue · \(player.queue.count) tracks")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if !player.upNext.isEmpty {
                        Button("Clear") { withAnimation(Anim.tab) { player.clearUpNext() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.dim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                SectionLabel("Now playing").padding(.horizontal, 8)
                SongRow(track: cur, model: model, player: player, tapAction: { model.select(.player) })
                    .padding(.horizontal, 8)
                SectionLabel("Up next · drag to reorder").padding(.horizontal, 8)

                if player.upNext.isEmpty {
                    MessageView(icon: "sparkles", title: "Finding more like this", subtitle: "Radio tracks show up here.")
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(player.upNext) { item in
                            QueueRow(item: item, player: player)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in player.moveUpNext(from: from, to: to) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                }
            } else {
                MessageView(icon: "list.bullet", title: "Queue is empty",
                            subtitle: "Play something and what's next shows up here.")
                Spacer(minLength: 0)
            }
        }
    }
}

struct QueueRow: View {
    let item: QueueItem
    let player: PlayerModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            Art(item.track.thumbnail, size: 32, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text(item.track.artist).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            IconButton(systemName: "xmark", size: 10, color: .white.opacity(0.45), help: "Remove") {
                withAnimation(Anim.tab) { player.remove(item) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(HoverFill(selected: false))
        .contentShape(Rectangle())
        .onTapGesture { player.jump(to: item) }
    }
}

struct LibraryTab: View {
    @ObservedObject var model: NotchModel
    let player: PlayerModel

    var body: some View {
        if let route = model.homeRoute.last {
            DetailView(model: model, player: player, route: route)
                .id(route)
                .transition(ExpandedView.slide(.trailing))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let first = model.home.first {
                        ShelfView(shelf: first, model: model, player: player)
                    }
                    LibraryChips(model: model).padding(.horizontal, 16)
                    if model.home.isEmpty {
                        if model.homeLoading {
                            Spinner()
                        } else if let e = model.homeError {
                            MessageView(icon: "wifi.exclamationmark", title: e, actionTitle: "Try again") { model.loadHome() }
                        }
                    }
                    ForEach(model.home.dropFirst()) { shelf in
                        ShelfView(shelf: shelf, model: model, player: player)
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear { if model.home.isEmpty { model.loadHome() } }
            .transition(.opacity)
        }
    }
}

struct ShelfView: View {
    let shelf: Shelf
    let model: NotchModel
    let player: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(shelf.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(shelf.items) { item in
                        HomeCard(item: item, model: model, player: player)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct HomeCard: View {
    let item: MusicItem
    let model: NotchModel
    let player: PlayerModel

    var body: some View {
        let info = details
        Button { model.activate(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Art(info.thumb, width: 140, height: 96, radius: 12, icon: info.icon)
                Text(info.title).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text(info.subtitle).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            switch item {
            case .song(let t): TrackMenuItems(track: t, model: model, player: player)
            default: EmptyView()
            }
        }
    }

    private var details: (title: String, subtitle: String, thumb: URL?, icon: String) {
        switch item {
        case .song(let t): return (t.title, t.artist, t.thumbnail, "music.note")
        case .collection(let c): return (c.title, c.subtitle, c.thumbnail, "square.stack")
        case .artist(let a): return (a.name, a.subtitle, a.thumbnail, "person.fill")
        }
    }
}

struct LibraryChips: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 6) {
            chip("Liked songs", "heart", primary: true) {
                model.openLibrary(.collection(MusicCollection(id: "VLLM", title: "Liked songs", subtitle: "Your likes",
                                                              thumbnail: nil, kind: .playlist)))
            }
            chip("Playlists", "music.note.list", primary: false) { model.openLibrary(.library) }
            chip("Recent", "clock", primary: false) {
                model.openLibrary(.collection(MusicCollection(id: "FEmusic_history", title: "Recently played",
                                                              subtitle: "History", thumbnail: nil, kind: .playlist)))
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, _ icon: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(primary ? .black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
    }
}
