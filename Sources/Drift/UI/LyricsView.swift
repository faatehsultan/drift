import SwiftUI

struct LyricsView: View {
    @ObservedObject var lyrics: LyricsModel
    @ObservedObject var player: PlayerModel

    var body: some View {
        if player.current == nil {
            MessageView(icon: "quote.bubble", title: "Nothing playing", subtitle: "Lyrics show up here while a song plays.")
        } else if lyrics.loading {
            Spinner()
        } else if !lyrics.lines.isEmpty {
            synced
        } else if let p = lyrics.plain, !p.isEmpty {
            ScrollView(showsIndicators: false) {
                Text(p)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        } else {
            MessageView(icon: "quote.bubble", title: "No lyrics for this one", subtitle: "Lyrics come from LRCLIB.")
        }
    }

    private var synced: some View {
        let current = lyrics.index(at: player.position)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 100)
                    ForEach(lyrics.lines) { line in
                        let on = line.id == current
                        Text(line.text)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(on ? .white : .white.opacity(line.id < current ? 0.3 : 0.45))
                            .scaleEffect(on ? 1 : 0.9, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .id(line.id)
                            .onTapGesture { player.seek(line.time) }
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: on)
                    }
                    Color.clear.frame(height: 140)
                }
                .padding(.horizontal, 26)
            }
            .onChange(of: current) { v in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) { proxy.scrollTo(v, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }
}
