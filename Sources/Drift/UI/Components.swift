import SwiftUI
import AppKit

// Note: no @State / @StateObject / @Binding anywhere. Your Command Line Tools
// can't expand SwiftUI's macros, so all state lives in ObservableObjects.

extension Color {
    static let dim = Color.white.opacity(0.55)
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 16
    var color: Color = .white
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(color)
                .frame(width: size + 18, height: size + 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}

struct PillButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(PressStyle())
    }
}

struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(on ? .black : .white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
        .animation(Anim.quick, value: on)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }
}

struct Spinner: View {
    var body: some View {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 90)
    }
}

struct MessageView: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(.white.opacity(0.35))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundColor(.dim).multilineTextAlignment(.center)
            }
            if let t = actionTitle, let a = action {
                PillButton(title: t, action: a).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
    }
}

// MARK: - Equalizer

struct EqualizerView: View {
    let playing: Bool
    let color: Color
    var maxHeight: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color).frame(width: 3, height: barHeight(i, t))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        guard playing else { return 3 }
        let speeds: [Double] = [6.1, 8.3, 5.2, 7.4]
        let v = (sin(t * speeds[i] + Double(i) * 1.7) + sin(t * speeds[(i + 2) % 4] * 0.6)) / 4 + 0.5
        return 3 + (maxHeight - 3) * CGFloat(max(0, min(1, v)))
    }
}

// MARK: - Hover highlight (AppKit, so it needs no SwiftUI state)

struct HoverFill: NSViewRepresentable {
    var selected: Bool
    var radius: CGFloat = 10

    func makeNSView(context: Context) -> HoverFillView {
        let v = HoverFillView()
        v.radius = radius
        v.selected = selected
        return v
    }

    func updateNSView(_ v: HoverFillView, context: Context) { v.selected = selected }
}

final class HoverFillView: NSView {
    var radius: CGFloat = 10 { didSet { layer?.cornerRadius = radius } }
    var selected = false { didSet { if oldValue != selected { refresh() } } }
    private var hovering = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    private func refresh() {
        let a: CGFloat = selected ? 0.1 : (hovering ? 0.06 : 0)
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.duration = 0.15
        layer?.add(anim, forKey: "bg")
        layer?.backgroundColor = NSColor.white.withAlphaComponent(a).cgColor
    }
}

// MARK: - Images

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    init() { cache.countLimit = 300 }

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL) async -> NSImage? {
        if let c = cached(url) { return c }
        if let t = inflight[url] { return await t.value }
        let task = Task<NSImage?, Never> {
            guard let res = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: res.0)
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img = img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// One shared loader per URL, so views can observe it without owning state.
@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private static var pool: [URL: ImageLoader] = [:]
    static let blank = ImageLoader(url: nil)

    static func of(_ url: URL?) -> ImageLoader {
        guard let url = url else { return blank }
        if let l = pool[url] { return l }
        if pool.count > 160 { pool.removeAll() }
        let l = ImageLoader(url: url)
        pool[url] = l
        return l
    }

    private init(url: URL?) {
        guard let url = url else { return }
        if let c = ImageCache.shared.cached(url) { image = c; return }
        Task {
            let img = await ImageCache.shared.image(for: url)
            self.image = img
        }
    }
}

struct RemoteImage: View {
    @ObservedObject var loader: ImageLoader
    var icon: String
    var iconSize: CGFloat

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let img = loader.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .animation(.easeOut(duration: 0.25), value: loader.image != nil)
    }
}

struct Art: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let circle: Bool
    let icon: String

    init(_ url: URL?, size: CGFloat, radius: CGFloat = 8, circle: Bool = false, icon: String = "music.note") {
        self.url = url
        self.width = size
        self.height = size
        self.radius = radius
        self.circle = circle
        self.icon = icon
    }

    init(_ url: URL?, width: CGFloat, height: CGFloat, radius: CGFloat = 8, icon: String = "music.note") {
        self.url = url
        self.width = width
        self.height = height
        self.radius = radius
        self.circle = false
        self.icon = icon
    }

    var body: some View {
        RemoteImage(loader: ImageLoader.of(url), icon: icon, iconSize: min(width, height) * 0.36)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: circle ? min(width, height) / 2 : radius, style: .continuous))
    }
}

extension NSImage {
    /// The most vivid color in the image, brightened so it reads on black.
    func vibrantColor() -> Color {
        let w = 12, h = 12
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return .white }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var bestScore: CGFloat = -1
        var best = NSColor.white
        for i in 0..<(w * h) {
            let c = NSColor(srgbRed: CGFloat(px[i * 4]) / 255, green: CGFloat(px[i * 4 + 1]) / 255,
                            blue: CGFloat(px[i * 4 + 2]) / 255, alpha: 1)
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            let score = sat * 0.7 + bri * 0.3
            if score > bestScore {
                bestScore = score
                best = NSColor(hue: hue, saturation: min(sat, 0.75), brightness: max(bri, 0.85), alpha: 1)
            }
        }
        return Color(nsColor: best)
    }
}
