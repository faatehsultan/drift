import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import AVFoundation
import QuickLookThumbnailing

struct TrayItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var path: String
    var pinned = false
    var added = Date()
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
}

/// Files dropped on the notch. Shelf items clear after a day; Pocket items stay.
@MainActor
final class TrayModel: ObservableObject {
    @Published private(set) var items: [TrayItem] = []
    @Published var showPocket = false
    @Published private(set) var busy: Set<UUID> = []
    @Published private(set) var toast: String?

    var onAdded: (Int) -> Void = { _ in }
    private var toastTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "tray"),
           let saved = try? JSONDecoder().decode([TrayItem].self, from: data) {
            items = saved
        }
        prune()
    }

    var visibleItems: [TrayItem] { items.filter { $0.pinned == showPocket } }
    var shelfCount: Int { items.filter { !$0.pinned }.count }
    var pocketCount: Int { items.filter { $0.pinned }.count }
    var visiblePDFs: [TrayItem] { visibleItems.filter { $0.isPDF } }

    func add(_ urls: [URL]) {
        var n = 0
        for u in urls where !items.contains(where: { $0.path == u.path }) {
            items.insert(TrayItem(path: u.path), at: 0)
            n += 1
        }
        guard n > 0 else { return }
        showPocket = false
        save()
        onAdded(n)
    }

    func add(providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async { self.add([url]) }
            }
        }
    }

    func remove(_ i: TrayItem) {
        items.removeAll { $0.id == i.id }
        save()
    }

    func togglePin(_ i: TrayItem) {
        guard let idx = items.firstIndex(where: { $0.id == i.id }) else { return }
        items[idx].pinned.toggle()
        items[idx].added = Date()
        save()
    }

    func clearVisible() {
        let pocket = showPocket
        items.removeAll { $0.pinned == pocket }
        save()
    }

    func open(_ i: TrayItem) { NSWorkspace.shared.open(i.url) }
    func reveal(_ i: TrayItem) { NSWorkspace.shared.activateFileViewerSelecting([i.url]) }

    func airdrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func convert(_ item: TrayItem, _ action: ConvertAction) {
        busy.insert(item.id)
        let url = item.url
        Task {
            do {
                let outs = try await Converter.run(action, url)
                self.add(outs)
                self.flash(outs.count == 1 ? "Saved \(outs[0].lastPathComponent)" : "Saved \(outs.count) files")
            } catch {
                self.flash("Couldn't convert: \(error.localizedDescription)")
            }
            self.busy.remove(item.id)
        }
    }

    func mergeVisiblePDFs() {
        let urls = visiblePDFs.reversed().map { $0.url }
        Task {
            do {
                let out = try await Converter.merge(Array(urls))
                self.add([out])
                self.flash("Saved \(out.lastPathComponent)")
            } catch {
                self.flash("Couldn't merge PDFs")
            }
        }
    }

    func flash(_ text: String) {
        toastTask?.cancel()
        withAnimation(Anim.quick) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Anim.quick) { self.toast = nil }
        }
    }

    private func prune() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        items.removeAll { !fm.fileExists(atPath: $0.path) || (!$0.pinned && $0.added < cutoff) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: "tray") }
    }
}

// MARK: - File conversion

enum ConvertAction: String, CaseIterable, Identifiable {
    case png, jpeg, heic, pdf, text, mp4, m4a, splitPDF, pngPages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .pdf: return "PDF"
        case .text: return "Plain text (.txt)"
        case .mp4: return "MP4 video"
        case .m4a: return "Audio only (.m4a)"
        case .splitPDF: return "Split into pages"
        case .pngPages: return "Pages as PNG"
        }
    }
}

enum ConvertError: LocalizedError {
    case unreadable, failed
    var errorDescription: String? { self == .unreadable ? "the file couldn't be read" : "the conversion failed" }
}

enum Converter {
    static func actions(for url: URL) -> [ConvertAction] {
        let ext = url.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext) else { return [] }
        if type.conforms(to: .pdf) { return [.text, .splitPDF, .pngPages] }
        if type.conforms(to: .image) {
            let current = (ext == "jpg") ? "jpeg" : ext
            return [ConvertAction.png, .jpeg, .heic, .pdf].filter { $0.rawValue != current }
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return [.mp4, .m4a] }
        if type.conforms(to: .audio) { return [.m4a] }
        if ["rtf", "rtfd", "doc", "docx", "html", "htm", "odt", "md"].contains(ext) { return [.text] }
        return []
    }

    static func run(_ a: ConvertAction, _ url: URL) async throws -> [URL] {
        switch a {
        case .png: return [try image(url, type: .png, ext: "png")]
        case .jpeg: return [try image(url, type: .jpeg, ext: "jpg")]
        case .heic: return [try image(url, type: .heic, ext: "heic")]
        case .pdf: return [try imageToPDF(url)]
        case .text: return [try toText(url)]
        case .mp4: return [try await export(url, preset: AVAssetExportPreset1920x1080, type: .mp4, ext: "mp4")]
        case .m4a: return [try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
        case .splitPDF: return try splitPDF(url)
        case .pngPages: return try pdfPages(url)
        }
    }

    static func output(for src: URL, ext: String, suffix: String = "") -> URL {
        let fm = FileManager.default
        var dir = src.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: dir.path) {
            dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = src.deletingPathExtension().lastPathComponent + suffix
        var out = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var i = 1
        while fm.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base)-\(i)").appendingPathExtension(ext)
            i += 1
        }
        return out
    }

    static func image(_ url: URL, type: UTType, ext: String) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ConvertError.unreadable }
        let out = output(for: url, ext: ext)
        guard let dst = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.failed
        }
        let props = [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        CGImageDestinationAddImage(dst, img, props)
        guard CGImageDestinationFinalize(dst) else { throw ConvertError.failed }
        return out
    }

    static func imageToPDF(_ url: URL) throws -> URL {
        guard let img = NSImage(contentsOf: url), let page = PDFPage(image: img) else { throw ConvertError.unreadable }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        let out = output(for: url, ext: "pdf")
        guard doc.write(to: out) else { throw ConvertError.failed }
        return out
    }

    static func toText(_ url: URL) throws -> URL {
        let ext = url.pathExtension.lowercased()
        var text = ""
        if ext == "pdf" {
            guard let d = PDFDocument(url: url) else { throw ConvertError.unreadable }
            text = d.string ?? ""
        } else if ext == "md" {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        let out = output(for: url, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func export(_ url: URL, preset: String, type: AVFileType, ext: String) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConvertError.failed
        }
        let same = url.pathExtension.lowercased() == ext
        let out = output(for: url, ext: ext, suffix: same ? "-compressed" : "")
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed else { throw session.error ?? ConvertError.failed }
        return out
    }

    static func splitPDF(_ url: URL) throws -> [URL] {
        guard let d = PDFDocument(url: url) else { throw ConvertError.unreadable }
        var outs: [URL] = []
        for i in 0..<d.pageCount {
            guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
            let nd = PDFDocument()
            nd.insert(p, at: 0)
            let out = output(for: url, ext: "pdf", suffix: "-p\(i + 1)")
            if nd.write(to: out) { outs.append(out) }
        }
        if outs.isEmpty { throw ConvertError.failed }
        return outs
    }

    static func pdfPages(_ url: URL) throws -> [URL] {
        guard let d = PDFDocument(url: url) else { throw ConvertError.unreadable }
        var outs: [URL] = []
        for i in 0..<min(d.pageCount, 30) {
            guard let p = d.page(at: i) else { continue }
            let b = p.bounds(for: .mediaBox)
            let w: CGFloat = 1600
            let h = b.width > 0 ? w * b.height / b.width : w
            let img = p.thumbnail(of: NSSize(width: w, height: h), for: .mediaBox)
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let out = output(for: url, ext: "png", suffix: "-p\(i + 1)")
            if (try? png.write(to: out)) != nil { outs.append(out) }
        }
        if outs.isEmpty { throw ConvertError.failed }
        return outs
    }

    static func merge(_ urls: [URL]) async throws -> URL {
        let doc = PDFDocument()
        for u in urls {
            guard let d = PDFDocument(url: u) else { continue }
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) }
            }
        }
        guard let first = urls.first, doc.pageCount > 0 else { throw ConvertError.failed }
        let out = output(for: first, ext: "pdf", suffix: "-merged")
        guard doc.write(to: out) else { throw ConvertError.failed }
        return out
    }
}

// MARK: - File thumbnails

@MainActor
final class FileThumb: ObservableObject {
    @Published private(set) var image: NSImage
    private static var pool: [String: FileThumb] = [:]

    static func of(_ url: URL) -> FileThumb {
        if let t = pool[url.path] { return t }
        if pool.count > 200 { pool.removeAll() }
        let t = FileThumb(url: url)
        pool[url.path] = t
        return t
    }

    private init(url: URL) {
        image = NSWorkspace.shared.icon(forFile: url.path)
        Task {
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 128, height: 128),
                                                   scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                self.image = rep.nsImage
            }
        }
    }
}
