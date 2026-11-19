import AppKit
import WebKit

/// One-time Google sign-in. Shares the default cookie store with the API client and the audio engine.
final class SignInWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    var onFinish: () -> Void = {}

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 660), configuration: config)
        wv.customUserAgent = InnerTube.userAgent
        wv.navigationDelegate = self

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 660),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Sign in to YouTube Music"
        w.contentView = wv
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        webView = wv

        let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
        wv.load(URLRequest(url: url))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let host = webView.url?.host, host.contains("music.youtube.com") else { return }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let ok = cookies.contains { $0.domain.hasSuffix("youtube.com") && ($0.name == "SAPISID" || $0.name == "__Secure-3PAPISID") }
            if ok { self?.window?.close() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        webView = nil
        onFinish()
    }
}
