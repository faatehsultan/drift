import Foundation
import Network

/// One permission request from Claude Code, waiting for a decision in the notch.
struct AgentRequest: Identifiable {
    let id = UUID()
    let tool: String
    let detail: String
    let project: String
    fileprivate let reply: (String) -> Void
}

/// A tiny local HTTP server (127.0.0.1 only). Claude Code's PermissionRequest hook
/// posts to it with curl and waits; the notch answers allow / deny / ask.
@MainActor
final class AgentModel: ObservableObject {
    static let port: UInt16 = 47823

    enum Decision { case allow, deny, ask }

    @Published private(set) var pending: [AgentRequest] = []
    @Published private(set) var hookInstalled = false
    @Published private(set) var status = ""

    private var listener: NWListener?

    init() { hookInstalled = Self.isHookInstalled() }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: port)
            l.newConnectionHandler = { [weak self] conn in
                DispatchQueue.main.async { self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    if case .failed(let e) = state { self?.status = "Couldn't listen for Claude Code: \(e)" }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            status = "Couldn't listen for Claude Code: \(error.localizedDescription)"
        }
    }

    private func accept(_ conn: NWConnection) {
        let http = HTTPConnection(conn) { [weak self] body, respond in
            DispatchQueue.main.async { self?.handle(body, respond) }
        }
        http.start()
    }

    private func handle(_ body: Data, _ respond: @escaping (String) -> Void) {
        let obj = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:]
        guard obj["tool_name"] != nil || obj["hook_event_name"] != nil else {
            respond("{}")
            return
        }
        let tool = obj["tool_name"] as? String ?? "a tool"
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        let cwd = obj["cwd"] as? String ?? ""
        let req = AgentRequest(tool: tool, detail: Self.describe(input),
                               project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent,
                               reply: respond)
        pending.append(req)
        let id = req.id
        // Fall back to the normal terminal prompt before the hook times out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 110) { [weak self] in self?.resolve(id, .ask) }
    }

    func resolve(_ id: UUID, _ decision: Decision) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let r = pending.remove(at: i)
        r.reply(Self.body(decision))
    }

    static func body(_ d: Decision) -> String {
        switch d {
        case .allow:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .deny:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Drift"}}}"#
        case .ask:
            return "{}"
        }
    }

    static func describe(_ input: [String: Any]) -> String {
        for key in ["command", "file_path", "url", "pattern", "path", "query"] {
            if let s = input[key] as? String, !s.isEmpty { return s }
        }
        if let d = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            return String(s.prefix(500))
        }
        return ""
    }

    // MARK: Hook install

    static var hookPath: String { NSHomeDirectory() + "/.drift/claude-permission-hook.sh" }
    static var settingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }

    static let hookScript = """
    #!/bin/bash
    # Drift: shows Claude Code permission requests in the notch.
    # If Drift isn't running, Claude Code asks in the terminal as usual.
    curl -s -m 115 -X POST -H 'Content-Type: application/json' -H 'Expect:' --data-binary @- http://127.0.0.1:47823/claude 2>/dev/null || echo '{}'

    """

    func installHook() {
        do {
            let fm = FileManager.default
            try fm.createDirectory(atPath: NSHomeDirectory() + "/.drift", withIntermediateDirectories: true)
            try Self.hookScript.write(toFile: Self.hookPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.hookPath)

            var root = try Self.readSettings()
            if fm.fileExists(atPath: Self.settingsPath) {
                let backup = Self.settingsPath + ".drift-backup"
                try? fm.removeItem(atPath: backup)
                try? fm.copyItem(atPath: Self.settingsPath, toPath: backup)
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            var list = (hooks["PermissionRequest"] as? [[String: Any]] ?? []).filter { !Self.isDriftEntry($0) }
            let handler: [String: Any] = ["type": "command", "command": Self.hookPath, "timeout": 120]
            let entry: [String: Any] = ["matcher": "*", "hooks": [handler]]
            list.append(entry)
            hooks["PermissionRequest"] = list
            root["hooks"] = hooks
            try Self.writeSettings(root)
            hookInstalled = true
            status = "Installed. Start a new Claude Code session to use it."
        } catch {
            status = "Install failed: \(error.localizedDescription)"
        }
    }

    func uninstallHook() {
        do {
            var root = try Self.readSettings()
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            let list = (hooks["PermissionRequest"] as? [[String: Any]] ?? []).filter { !Self.isDriftEntry($0) }
            if list.isEmpty { hooks.removeValue(forKey: "PermissionRequest") } else { hooks["PermissionRequest"] = list }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
            try Self.writeSettings(root)
            hookInstalled = false
            status = "Removed."
        } catch {
            status = "Remove failed: \(error.localizedDescription)"
        }
    }

    private static func isDriftEntry(_ entry: [String: Any]) -> Bool {
        let hs = entry["hooks"] as? [[String: Any]] ?? []
        return hs.contains { ($0["command"] as? String)?.contains("claude-permission-hook.sh") == true }
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Drift", code: 1, userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json isn't a JSON object"])
        }
        return obj
    }

    private static func writeSettings(_ obj: [String: Any]) throws {
        try FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.claude", withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }

    static func isHookInstalled() -> Bool {
        guard let root = try? readSettings(), let hooks = root["hooks"] as? [String: Any],
              let list = hooks["PermissionRequest"] as? [[String: Any]] else { return false }
        return list.contains { isDriftEntry($0) }
    }
}

/// Minimal HTTP/1.1: reads one request, hands over the body, writes one JSON reply.
final class HTTPConnection {
    private let conn: NWConnection
    private var buffer = Data()
    private let onRequest: (Data, @escaping (String) -> Void) -> Void

    init(_ conn: NWConnection, onRequest: @escaping (Data, @escaping (String) -> Void) -> Void) {
        self.conn = conn
        self.onRequest = onRequest
    }

    func start() {
        conn.start(queue: .main)
        read()
    }

    private func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, done, error in
            if let data = data { self.buffer.append(data) }
            if let body = self.parseBody() {
                self.onRequest(body) { json in self.send(json) }
                return
            }
            if done || error != nil {
                self.conn.cancel()
                return
            }
            self.read()
        }
    }

    private func parseBody() -> Data? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(data: buffer.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
        var length = 0
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let start = range.upperBound
        guard buffer.count - start >= length else { return nil }
        return buffer.subdata(in: start..<(start + length))
    }

    private func send(_ json: String) {
        let body = Data(json.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let c = conn
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
}
