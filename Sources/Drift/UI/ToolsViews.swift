import SwiftUI
import AppKit
import AVFoundation

struct ToolsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let tools = settings.visibleTools
        let current = tools.contains(model.tool) ? model.tool : (tools.first ?? .notes)
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tools) { t in
                        ToolChip(tool: t, on: t == current) { model.selectTool(t) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            ZStack(alignment: .top) {
                switch current {
                case .notes: NotesTool(notes: model.notes)
                case .todos: TodosTool(todos: model.todos)
                case .timer: TimerTool(timer: model.timer)
                case .mirror: MirrorTool()
                case .shortcuts: ShortcutsTool(shortcuts: model.shortcuts)
                case .clipboard: ClipboardTool(clipboard: model.clipboard, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(current)
            .transition(.opacity)
        }
    }
}

struct ToolChip: View {
    let tool: ToolKind
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tool.icon).font(.system(size: 10, weight: .bold))
                Text(tool.title)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(on ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
        .animation(Anim.quick, value: on)
    }
}

// MARK: - Text input helpers (AppKit, no SwiftUI state)

func makeDriftField(_ placeholder: String) -> NSTextField {
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
        string: placeholder,
        attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 13)])
    return f
}

/// Single-line field that hands its text to `onSubmit` on Return, then clears.
struct NativeField: NSViewRepresentable {
    let placeholder: String
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSubmit: onSubmit) }

    func makeNSView(context: Context) -> NSTextField {
        let f = makeDriftField(placeholder)
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) { context.coordinator.onSubmit = onSubmit }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onSubmit: (String) -> Void
        init(onSubmit: @escaping (String) -> Void) { self.onSubmit = onSubmit }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let s = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { onSubmit(s) }
            control.stringValue = ""
            return true
        }
    }
}

/// Multi-line plain text editor for notes.
struct NativeTextView: NSViewRepresentable {
    let notes: NotesModel

    func makeCoordinator() -> Coordinator { Coordinator(notes: notes) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        if let tv = scroll.documentView as? NSTextView {
            tv.drawsBackground = false
            tv.textColor = .white
            tv.insertionPointColor = .white
            tv.font = .systemFont(ofSize: 13)
            tv.isRichText = false
            tv.allowsUndo = true
            tv.textContainerInset = NSSize(width: 2, height: 4)
            tv.string = notes.text
            tv.delegate = context.coordinator
        }
        return scroll
    }

    func updateNSView(_ v: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let notes: NotesModel
        init(notes: NotesModel) { self.notes = notes }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            notes.text = tv.string
        }
    }
}

// MARK: - Notes

struct NotesTool: View {
    @ObservedObject var notes: NotesModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            NativeTextView(notes: notes)
            if notes.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.leading, 7)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

// MARK: - To-dos

struct TodosTool: View {
    @ObservedObject var todos: TodoModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                NativeField(placeholder: "Add a to-do and press Return") { todos.add($0) }
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
            .padding(.horizontal, 16)

            if todos.items.isEmpty {
                MessageView(icon: "checklist", title: "Nothing to do", subtitle: "Add your first to-do above.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(todos.items) { t in TodoRow(todo: t, todos: todos) }
                    }
                    .padding(.horizontal, 8)
                }
                HStack {
                    Text("\(todos.remaining) left").font(.system(size: 11)).foregroundColor(.dim)
                    Spacer()
                    if todos.items.contains(where: { $0.done }) {
                        Button("Clear done") { todos.clearDone() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.dim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }
}

struct TodoRow: View {
    let todo: Todo
    let todos: TodoModel

    var body: some View {
        HStack(spacing: 10) {
            Button { todos.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(todo.done ? .green : .white.opacity(0.5))
            }
            .buttonStyle(PressStyle())
            Text(todo.title)
                .font(.system(size: 13))
                .strikethrough(todo.done)
                .foregroundColor(todo.done ? .white.opacity(0.4) : .white)
                .lineLimit(2)
            Spacer(minLength: 6)
            IconButton(systemName: "xmark", size: 9, color: .white.opacity(0.4), help: "Delete") { todos.remove(todo) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(HoverFill(selected: false))
    }
}

// MARK: - Timer

struct TimerTool: View {
    @ObservedObject var timer: TimerModel

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                ProgressRing(progress: timer.active ? timer.progress : 0,
                             color: timer.phase == .rest ? .green : .orange, lineWidth: 8)
                VStack(spacing: 2) {
                    Text(formatTime(timer.remaining))
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                    Text(timer.label).font(.system(size: 11, weight: .medium)).foregroundColor(.dim)
                }
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Chip(title: "Timer", on: !timer.pomodoro) { timer.setMinutes(5) }
                    Chip(title: "Pomodoro", on: timer.pomodoro) { timer.startPomodoro() }
                }
                if timer.pomodoro {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("25 min focus · 5 min break").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                        Text("Long break every 4 · \(timer.focusDone) done").font(.system(size: 11)).foregroundColor(.dim)
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                        ForEach([1, 5, 10, 15, 25, 45], id: \.self) { m in
                            Chip(title: "\(m) min", on: !timer.active && Int(timer.duration) == m * 60) { timer.setMinutes(Double(m)) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    IconButton(systemName: "minus", size: 12, help: "Minus 1 min") { timer.adjust(-60) }
                    PillButton(title: timer.running ? "Pause" : (timer.active ? "Resume" : "Start"),
                               icon: timer.running ? "pause.fill" : "play.fill") { timer.toggle() }
                    IconButton(systemName: "plus", size: 12, help: "Plus 1 min") { timer.adjust(60) }
                    IconButton(systemName: "arrow.counterclockwise", size: 12, help: "Reset") { timer.reset() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }
}

// MARK: - Mirror

struct MirrorTool: View {
    var body: some View {
        CameraPreview()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraView {
        let v = CameraView()
        v.start()
        return v
    }
    func updateNSView(_ v: CameraView, context: Context) {}
    static func dismantleNSView(_ v: CameraView, coordinator: ()) { v.stop() }
}

final class CameraView: NSView {
    private let session = AVCaptureSession()
    private let preview: AVCaptureVideoPreviewLayer
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        label.textColor = NSColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        preview.frame = bounds
        label.frame = NSRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 20)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.configure() } else { self.show("Camera access was denied") }
                }
            }
        default:
            show("Allow camera access in System Settings → Privacy")
        }
    }

    private func configure() {
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            show("No camera found")
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    func stop() {
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    private func show(_ msg: String) { label.stringValue = msg }
}

// MARK: - Shortcuts

struct ShortcutsTool: View {
    @ObservedObject var shortcuts: ShortcutsModel

    var body: some View {
        if shortcuts.loading && shortcuts.names.isEmpty {
            Spinner()
        } else if shortcuts.names.isEmpty {
            MessageView(icon: "square.stack.3d.up", title: "No shortcuts found",
                        subtitle: "Make some in the Shortcuts app.", actionTitle: "Refresh") { shortcuts.load() }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(shortcuts.names, id: \.self) { n in
                        Button { shortcuts.run(n) } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.purple.opacity(0.3))
                                    if shortcuts.running == n {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundColor(.white)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                Text(n).font(.system(size: 12, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardTool: View {
    @ObservedObject var clipboard: ClipboardModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        if !settings.clipboardHistory {
            MessageView(icon: "doc.on.clipboard", title: "Clipboard history is off",
                        subtitle: "Turn it on in Settings → General.")
        } else if clipboard.items.isEmpty {
            MessageView(icon: "doc.on.clipboard", title: "Nothing copied yet",
                        subtitle: "Copy text anywhere and it shows up here. Passwords are skipped.")
        } else {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(clipboard.items) { c in ClipRow(item: c, clipboard: clipboard) }
                    }
                    .padding(.horizontal, 8)
                }
                HStack {
                    Text("Click to copy again").font(.system(size: 11)).foregroundColor(.dim)
                    Spacer()
                    Button("Clear") { clipboard.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.dim)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardModel

    var body: some View {
        let copied = clipboard.copiedId == item.id
        HStack(spacing: 10) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(copied ? .green : .white.opacity(0.4))
                .frame(width: 16)
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer(minLength: 6)
            Text(item.date, style: .relative).font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
            IconButton(systemName: item.pinned ? "pin.fill" : "pin", size: 9,
                       color: item.pinned ? .yellow : .white.opacity(0.4), help: "Pin") { clipboard.togglePin(item) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(HoverFill(selected: copied))
        .contentShape(Rectangle())
        .onTapGesture { clipboard.copy(item) }
    }
}
