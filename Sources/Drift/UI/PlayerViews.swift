import SwiftUI

struct PlayerTab: View {
    let model: NotchModel
    @ObservedObject var player: PlayerModel

    var body: some View {
        if let t = player.current {
            HStack(alignment: .top, spacing: 18) {
                Art(t.thumbnail, size: 128, radius: 14)
                    .shadow(color: player.accent.opacity(0.35), radius: 18, x: 0, y: 6)
                    .scaleEffect(player.isPlaying ? 1 : 0.94)
                    .animation(Anim.morph, value: player.isPlaying)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(player.isAd ? "Ad · your song starts after this" : subtitle(t))
                                .font(.system(size: 12))
                                .foregroundColor(.dim)
                                .lineLimit(1)
                                .onTapGesture { openArtist(t) }
                        }
                        Spacer(minLength: 0)
                        let liked = player.likedIds.contains(t.videoId)
                        IconButton(systemName: liked ? "heart.fill" : "heart", size: 15,
                                   color: liked ? player.accent : .white, help: "Like  ⌥⌘L") { player.toggleLike() }
                    }
                    Spacer(minLength: 8)
                    ProgressBar(player: player)
                    Spacer(minLength: 4)
                    Controls(player: player)
                }
                .frame(height: 128)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
        } else {
            EmptyPlayer(model: model)
        }
    }

    private func subtitle(_ t: Track) -> String {
        [t.artist, t.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func openArtist(_ t: Track) {
        guard let id = t.artistId else { return }
        model.open(.artist(ArtistRef(id: id, name: t.artist, subtitle: "Artist", thumbnail: nil)))
    }
}

struct ProgressBar: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        let total = max(player.duration, 1)
        let shown = min(player.scrubPosition ?? player.position, total)
        let scrubbing = player.scrubPosition != nil
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(player.accent)
                        .frame(width: max(4, w * CGFloat(shown / total)))
                        .animation(scrubbing ? nil : Animation.linear(duration: 0.5), value: shown)
                }
                .frame(height: scrubbing ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            player.scrubPosition = Double(min(max(v.location.x / w, 0), 1)) * total
                        }
                        .onEnded { v in
                            let p = Double(min(max(v.location.x / w, 0), 1)) * total
                            player.scrubPosition = nil
                            player.seek(p)
                        }
                )
                .animation(Anim.quick, value: scrubbing)
            }
            .frame(height: 12)
            HStack {
                Text(formatTime(shown))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.dim)
        }
    }
}

struct Controls: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "shuffle", size: 14,
                       color: player.shuffle ? player.accent : .white.opacity(0.55), help: "Shuffle") { player.toggleShuffle() }
            Spacer(minLength: 0)
            IconButton(systemName: "backward.fill", size: 18, help: "Previous  ⌥⌘←") { player.previous() }
            Spacer(minLength: 0)
            Button { player.togglePlay() } label: {
                ZStack {
                    Circle().fill(Color.white)
                    if player.isLoadingTrack && player.isPlaying {
                        ProgressView().controlSize(.small).colorScheme(.light)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: player.isPlaying ? 0 : 1.5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 42, height: 42)
                .animation(Anim.quick, value: player.isPlaying)
            }
            .buttonStyle(PressStyle())
            .help("Play or pause  ⌥⌘P")
            Spacer(minLength: 0)
            IconButton(systemName: "forward.fill", size: 18, help: "Next  ⌥⌘→") { player.next() }
            Spacer(minLength: 0)
            IconButton(systemName: player.repeatMode == .one ? "repeat.1" : "repeat", size: 14,
                       color: player.repeatMode == .off ? .white.opacity(0.55) : player.accent, help: "Repeat") { player.cycleRepeat() }
        }
    }
}

struct EmptyPlayer: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08))
                Image(systemName: "music.note").font(.system(size: 30)).foregroundColor(.white.opacity(0.35))
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                Text("Search for a song or open home to start.").font(.system(size: 12)).foregroundColor(.dim)
                HStack(spacing: 8) {
                    PillButton(title: "Search", icon: "magnifyingglass") { model.select(.search) }
                    IconButton(systemName: "house", size: 14, help: "Library") { model.select(.library) }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}
