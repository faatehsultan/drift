import AppKit
import WebKit

@MainActor
protocol AudioEngineDelegate: AnyObject {
    func engineTick(position: Double, duration: Double, paused: Bool, isAd: Bool)
    func engineEnded()
    func engineStarted()
}

/// Breaks the retain cycle WKUserContentController would create.
final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var engine: AudioEngine?
    init(_ engine: AudioEngine) { self.engine = engine }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        engine?.handle(message.body)
    }
}

/// Plays audio through a YouTube Music page that is never shown.
/// Everything the user sees is native; this only produces sound.
@MainActor
final class AudioEngine: NSObject {
    weak var delegate: AudioEngineDelegate?

    private let webView: WKWebView
    private let window: NSWindow
    private var volume: Double = 0.8
    private var currentId: String?
    private var wantsPlay = false
    private var resumeAttempts = 0
    private var lastAd = false
    private var loadedAt = Date.distantPast

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 640), configuration: config)
        webView.customUserAgent = InnerTube.userAgent
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 960, height: 640),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        let ucc = webView.configuration.userContentController
        ucc.add(ScriptProxy(self), name: "drift")
        ucc.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = webView
        window.orderBack(nil)
    }

    func play(_ videoId: String) {
        currentId = videoId
        wantsPlay = true
        resumeAttempts = 0
        loadedAt = Date()
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com/watch?v=\(videoId)")!))
    }

    func resume() {
        wantsPlay = true
        run("var p=document.getElementById('movie_player'); if(p&&p.playVideo){p.playVideo();}else{var v=document.querySelector('video'); if(v){v.play();}}")
    }

    func pause() {
        wantsPlay = false
        run("var p=document.getElementById('movie_player'); if(p&&p.pauseVideo){p.pauseVideo();}else{var v=document.querySelector('video'); if(v){v.pause();}}")
    }

    func seek(_ seconds: Double) {
        run("var p=document.getElementById('movie_player'); if(p&&p.seekTo){p.seekTo(\(seconds), true);}else{var v=document.querySelector('video'); if(v){v.currentTime=\(seconds);}}")
    }

    func setVolume(_ level: Double) {
        volume = level
        applyVolume()
    }

    private func applyVolume() {
        let pct = Int((volume * 100).rounded())
        run("var p=document.getElementById('movie_player'); if(p&&p.setVolume){p.setVolume(\(pct)); if(p.unMute){p.unMute();}} var v=document.querySelector('video'); if(v){v.volume=\(volume);}")
    }

    private func run(_ js: String) {
        webView.evaluateJavaScript("(function(){" + js + "})()", completionHandler: nil)
    }

    func handle(_ body: Any) {
        guard let m = body as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "tick":
            let t = (m["t"] as? Double) ?? 0
            let d = (m["d"] as? Double) ?? 0
            let paused = (m["paused"] as? Bool) ?? true
            let ad = (m["ad"] as? Bool) ?? false
            lastAd = ad
            // The page moved to its own next song: take over with ours.
            if let vid = m["vid"] as? String, !vid.isEmpty, let cur = currentId, vid != cur, !ad,
               Date().timeIntervalSince(loadedAt) > 3 {
                currentId = nil
                delegate?.engineEnded()
                return
            }
            // Autoplay sometimes doesn't kick in after a page load.
            if wantsPlay && paused && !ad && resumeAttempts < 8 && Date().timeIntervalSince(loadedAt) > 1.5 {
                resumeAttempts += 1
                resume()
            }
            delegate?.engineTick(position: t, duration: d, paused: paused, isAd: ad)
        case "ended":
            if !lastAd && currentId != nil { delegate?.engineEnded() }
        case "playing":
            resumeAttempts = 0
            applyVolume()
            delegate?.engineStarted()
        default:
            break
        }
    }

    private static let bridge = #"""
    (function(){
      if (window.__drift) return; window.__drift = true;
      function post(m){ try { window.webkit.messageHandlers.drift.postMessage(m); } catch(e){} }
      var bound = null;
      setInterval(function(){
        var still = document.querySelector('ytmusic-you-there-renderer button');
        if (still) { still.click(); }
        var v = document.querySelector('video');
        if (!v) return;
        if (bound !== v) {
          bound = v;
          v.addEventListener('ended', function(){ post({type:'ended'}); });
          v.addEventListener('playing', function(){ post({type:'playing'}); });
        }
        var p = document.getElementById('movie_player');
        var ad = !!(p && p.classList && p.classList.contains('ad-showing'));
        var vid = new URLSearchParams(location.search).get('v') || '';
        post({type:'tick', t: v.currentTime || 0, d: isFinite(v.duration) ? v.duration : 0, paused: v.paused, ad: ad, vid: vid});
      }, 500);
    })();
    """#
}
