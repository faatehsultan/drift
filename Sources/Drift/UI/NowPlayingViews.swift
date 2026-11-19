import SwiftUI
import AppKit

/// Artwork for whichever player is in control (Drift or another app).
struct NowArtwork: View {
    @ObservedObject var model: NotchModel
    let size: CGFloat
    var radius: CGFloat = 6

    var body: some View {
        if model.activeSource == .external {
            ExternalArt(image: model.externalInfo?.artwork, size: size, radius: radius)
        } else {
            Art(model.player.current?.thumbnail, size: size, radius: radius)
        }
    }
}

struct ExternalArt: View {
    let image: NSImage?
    let size: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image = image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// "Playing in Google Chrome" with the app's icon.
struct SourceBadge: View {
    let bundleId: String
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            if let icon = ExternalMediaModel.appIcon(bundleId) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            }
            Text("Playing in \(name)").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// Player for media from another app: basic controls only (no search, queue or likes).
struct ExternalPlayerView: View {
    let model: NotchModel
    @ObservedObject var external: ExternalMediaModel

    var body: some View {
        if let e = external.info {
            HStack(alignment: .top, spacing: 18) {
                ExternalArt(image: e.artwork, size: 128, radius: 14)
                    .shadow(color: external.accent.opacity(0.35), radius: 18, x: 0, y: 6)
                    .scaleEffect(e.playing ? 1 : 0.94)
                    .animation(Anim.morph, value: e.playing)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text([e.artist, e.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundColor(.dim)
                            .lineLimit(1)
                        SourceBadge(bundleId: e.bundleId, name: e.appName).padding(.top, 3)
                    }
                    Spacer(minLength: 6)
                    if e.duration > 0 {
                        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                            ExternalProgress(info: e, now: ctx.date, accent: external.accent) { external.seek($0) }
                        }
                        .frame(height: 30)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        IconButton(systemName: "backward.fill", size: 18, help: "Previous") { external.previous() }
                        Spacer(minLength: 0)
                        Button { external.togglePlay() } label: {
                            ZStack {
                                Circle().fill(Color.white)
                                Image(systemName: e.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.black)
                                    .offset(x: e.playing ? 0 : 1.5)
                            }
                            .frame(width: 42, height: 42)
                        }
                        .buttonStyle(PressStyle())
                        Spacer(minLength: 0)
                        IconButton(systemName: "forward.fill", size: 18, help: "Next") { external.next() }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 128)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }
}

struct ExternalProgress: View {
    let info: ExternalInfo
    let now: Date
    let accent: Color
    let onSeek: (Double) -> Void

    var body: some View {
        let pos = info.position(at: now)
        let total = max(info.duration, 1)
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(accent).frame(width: max(4, w * CGFloat(pos / total)))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    onSeek(Double(min(max(v.location.x / w, 0), 1)) * total)
                })
            }
            .frame(height: 12)
            HStack {
                Text(formatTime(pos))
                Spacer()
                Text(formatTime(info.duration))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.dim)
        }
    }
}
