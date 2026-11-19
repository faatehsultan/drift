import Foundation

typealias JSON = [String: Any]

/// Walk a JSON tree by keys (String) and indexes (Int, negative counts from the end).
func jget(_ obj: Any?, _ path: Any...) -> Any? { jpath(obj, path) }

func jpath(_ obj: Any?, _ path: [Any]) -> Any? {
    var cur: Any? = obj
    for p in path {
        if let key = p as? String {
            guard let d = cur as? JSON else { return nil }
            cur = d[key]
        } else if let i = p as? Int {
            guard let a = cur as? [Any] else { return nil }
            let idx = i < 0 ? a.count + i : i
            guard idx >= 0 && idx < a.count else { return nil }
            cur = a[idx]
        } else {
            return nil
        }
        if cur == nil { return nil }
    }
    return cur
}

/// Depth-first search for every value stored under `key`. Array order is preserved.
func findAll(_ key: String, in obj: Any?, limit: Int = Int.max) -> [Any] {
    var out: [Any] = []
    func walk(_ o: Any) {
        if out.count >= limit { return }
        if let d = o as? JSON {
            if let v = d[key] { out.append(v) }
            for (k, v) in d where k != key { walk(v) }
        } else if let a = o as? [Any] {
            for v in a { walk(v) }
        }
    }
    if let obj = obj { walk(obj) }
    return Array(out.prefix(limit))
}

func jText(_ obj: Any?) -> String {
    guard let d = obj as? JSON else { return "" }
    if let s = d["simpleText"] as? String { return s }
    if let runs = d["runs"] as? [JSON] { return runs.compactMap { $0["text"] as? String }.joined() }
    return ""
}

func jRuns(_ obj: Any?) -> [JSON] {
    ((obj as? JSON)?["runs"] as? [JSON]) ?? []
}

func jThumb(_ obj: Any?) -> URL? {
    guard let arr = findAll("thumbnails", in: obj, limit: 1).first as? [JSON],
          let s = arr.last?["url"] as? String else { return nil }
    return URL(string: hiRes(s))
}

/// Ask Google's image CDN for a bigger version of a thumbnail.
func hiRes(_ s: String, size: Int = 544) -> String {
    var u = s.hasPrefix("//") ? "https:" + s : s
    if let r = u.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
        u.replaceSubrange(r, with: "=w\(size)-h\(size)")
    } else if let r = u.range(of: #"=s\d+"#, options: .regularExpression) {
        u.replaceSubrange(r, with: "=s\(size)")
    }
    return u
}
