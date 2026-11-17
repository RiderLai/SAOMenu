import Cocoa
import WebKit
import Carbon.HIToolbox
import AVFoundation

// MARK: - Paths

let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/sao-menu")
let configURL = configDir.appendingPathComponent("config.json")

// MARK: - Hotkey parsing ("alt+s", "ctrl+alt+space", ...)

struct HotKey {
    var keyCode: UInt32
    var modifiers: UInt32
}

let keyCodes: [String: UInt32] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
    "escape": 53, "esc": 53,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

func parseHotKey(_ text: String) -> HotKey? {
    var mods: UInt32 = 0
    var key: UInt32?
    for raw in text.lowercased().split(separator: "+") {
        let part = raw.trimmingCharacters(in: .whitespaces)
        switch part {
        case "cmd", "command": mods |= UInt32(cmdKey)
        case "alt", "option", "opt": mods |= UInt32(optionKey)
        case "ctrl", "control": mods |= UInt32(controlKey)
        case "shift": mods |= UInt32(shiftKey)
        default: key = keyCodes[part]
        }
    }
    // F-keys may be used bare; everything else needs a modifier.
    guard let k = key, mods != 0 || text.lowercased().hasPrefix("f") else { return nil }
    return HotKey(keyCode: k, modifiers: mods)
}

// MARK: - Sound

/// Plays UI sounds natively. Each sound is a short synthesized chime, unless the
/// user drops a file named <sound>.wav/.mp3/.m4a/.aiff into ~/.config/sao-menu/sounds/.
final class SoundBank {
    // (frequency Hz, start s, duration s, gain)
    static let notes: [String: [(Double, Double, Double, Double)]] = [
        // rising glassy arpeggio (E6 B6 E7 G#7), last note rings
        "open": [(1318.5, 0, 0.22, 0.20), (1975.5, 0.055, 0.22, 0.20),
                 (2637.0, 0.11, 0.30, 0.20), (3322.4, 0.165, 0.60, 0.18)],
        "close": [(2637.0, 0, 0.16, 0.18), (1975.5, 0.05, 0.18, 0.18), (1318.5, 0.10, 0.34, 0.18)],
        "select": [(1975.5, 0, 0.10, 0.20), (2637.0, 0.05, 0.32, 0.20)],
        "move": [(2093.0, 0, 0.07, 0.10)],
        "back": [(1975.5, 0, 0.10, 0.18), (1318.5, 0.05, 0.24, 0.18)],
        "launch": [(1318.5, 0, 0.14, 0.18), (1661.2, 0.045, 0.14, 0.18), (1975.5, 0.09, 0.16, 0.18),
                   (2637.0, 0.135, 0.70, 0.20)],
        "tick": [(2637.0, 0, 0.10, 0.16)],
        "welcome": [(1318.5, 0, 0.9, 0.14), (1661.2, 0.07, 0.9, 0.14), (1975.5, 0.14, 0.9, 0.14),
                    (2637.0, 0.21, 1.2, 0.16)],
        "error": [(311.1, 0, 0.20, 0.26), (233.1, 0.12, 0.34, 0.26)],
    ]
    // bell-like partials: (frequency ratio, level, decay speed-up)
    static let partials: [(Double, Double, Double)] = [(1, 1, 1), (2, 0.28, 1.6), (3.01, 0.12, 2.4), (4.2, 0.05, 3.5)]
    // echo taps: (delay s, level)
    static let echoes: [(Double, Double)] = [(0.11, 0.30), (0.22, 0.12)]
    // rising whooshes for the launch sequence: (from Hz, to Hz, duration s, gain)
    static let sweeps: [String: (Double, Double, Double, Double)] = [
        "dive": (160, 2200, 2.3, 0.22),
        "logout": (2000, 140, 2.0, 0.22),
        "warp": (500, 3400, 0.8, 0.20),
    ]
    static let dir = configDir.appendingPathComponent("sounds")

    var enabled = true
    var volume: Float = 0.7
    private var players: [String: AVAudioPlayer] = [:]

    /// Forget loaded sounds so replaced files are picked up.
    func invalidate() { players.removeAll() }

    func play(_ name: String) {
        guard enabled else { return }
        if players[name] == nil { players[name] = load(name) }
        guard let p = players[name] else { return }
        p.volume = volume
        p.currentTime = 0
        if !p.play() { NSLog("sound %@ failed to play", name) }
    }

    private func load(_ name: String) -> AVAudioPlayer? {
        for ext in ["wav", "mp3", "m4a", "aiff", "aif"] {
            let url = SoundBank.dir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path),
                let p = try? AVAudioPlayer(contentsOf: url)
            {
                p.prepareToPlay()
                return p
            }
        }
        var data: Data?
        if let notes = SoundBank.notes[name] { data = SoundBank.synth(notes) }
        if let sw = SoundBank.sweeps[name] { data = SoundBank.sweep(sw) }
        guard let data = data else { return nil }
        let p = try? AVAudioPlayer(data: data)
        p?.prepareToPlay()
        return p
    }

    /// Renders bell-like tones into a 16-bit mono WAV.
    static func synth(_ notes: [(Double, Double, Double, Double)]) -> Data {
        let rate = 44100.0
        let total = notes.map { $0.1 + $0.2 }.max() ?? 0
        var dry = [Double](repeating: 0, count: Int((total + 0.3) * rate))
        for (freq, at, dur, gain) in notes {
            let start = Int(at * rate)
            for i in 0..<Int(dur * rate) where start + i < dry.count {
                let t = Double(i) / rate
                var tone = 0.0
                for (ratio, level, speed) in partials {
                    tone += level * sin(2 * .pi * freq * ratio * t) * exp(-6.9 * speed * t / dur)
                }
                dry[start + i] += gain * min(t / 0.004, 1) * tone
            }
        }
        var buf = dry
        for (delay, level) in echoes {
            let d = Int(delay * rate)
            for i in d..<buf.count { buf[i] += dry[i - d] * level }
        }
        return wav(buf)
    }

    /// Renders a rising tone plus airy noise that swells and cuts off.
    static func sweep(_ spec: (Double, Double, Double, Double)) -> Data {
        let (f0, f1, dur, gain) = spec
        let rate = 44100.0
        var buf = [Double](repeating: 0, count: Int(dur * rate))
        var phase = 0.0, noise = 0.0
        for i in 0..<buf.count {
            let u = Double(i) / Double(buf.count)
            phase += 2 * .pi * f0 * pow(f1 / f0, u) / rate
            noise += 0.12 * (Double.random(in: -1...1) - noise)
            // rising sweeps swell, falling sweeps die away
            let env = f1 > f0 ? pow(u, 1.6) * min((1 - u) / 0.06, 1) : pow(1 - u, 1.3) * min(u / 0.04, 1)
            buf[i] = gain * env * (sin(phase) + 0.35 * sin(1.5 * phase) + 2.2 * noise)
        }
        return wav(buf)
    }

    static func wav(_ buf: [Double]) -> Data {
        let rate = 44100.0
        var pcm = Data(capacity: buf.count * 2)
        for v in buf {
            var s = Int16(max(-1, min(1, v)) * 32767).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!); put32(UInt32(36 + pcm.count))
        wav.append("WAVEfmt ".data(using: .ascii)!); put32(16); put16(1); put16(1)
        put32(UInt32(rate)); put32(UInt32(rate) * 2); put16(2); put16(16)
        wav.append("data".data(using: .ascii)!); put32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

// MARK: - Window

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    WKScriptMessageHandlerWithReply
{
    var panel: OverlayPanel!
    var webView: OverlayWebView!
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?

    var pageReady = false
    var visible = false
    var configMTime: Date?
    var hotkeyText = "alt+s"
    var pendingToast: String?
    let sounds = SoundBank()
    var introEnabled = true

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        ensureDefaultConfig()
        buildPanel()
        buildStatusItem()
        installHotKeyHandler()
        registerHotKey(hotkeyText)
    }

    /// Launching the app again (e.g. `open SAOMenu.app`) summons the menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return false
    }

    func buildPanel() {
        panel = OverlayPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu  // after isFloatingPanel, which resets the level
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "sao")
        webView = OverlayWebView(frame: panel.frame, configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        panel.contentView = webView

        let res = Bundle.main.resourceURL!
        webView.loadFileURL(res.appendingPathComponent("index.html"), allowingReadAccessTo: res)
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "SAO Menu") {
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "S"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "呼出菜单", action: #selector(showFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "编辑配置…", action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SAO Menu", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc func showFromMenu() { show() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func editConfig() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", configURL.path]
        try? p.run()
    }

    // MARK: Config

    func ensureDefaultConfig() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path),
            let def = Bundle.main.url(forResource: "default-config", withExtension: "json")
        else { return }
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: def, to: configURL)
    }

    /// Re-reads the config when the file changed on disk. Called on every summon,
    /// so edits take effect the next time the menu opens.
    func reloadConfigIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        let mtime = attrs?[.modificationDate] as? Date
        if mtime != nil && mtime == configMTime { return }
        configMTime = mtime
        do {
            let data = try Data(contentsOf: configURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "sao", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "顶层必须是一个 JSON 对象"])
            }
            let json = String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
            webView.evaluateJavaScript("SAO.setConfig(\(json))")
            introEnabled = (obj["intro"] as? Bool) ?? true
            sounds.enabled = (obj["sound"] as? Bool) ?? true
            sounds.volume = Float(max(0, min(1, (obj["volume"] as? Double) ?? 0.7)))
            let hk = (obj["hotkey"] as? String) ?? "alt+s"
            if hk != hotkeyText {
                hotkeyText = hk
                registerHotKey(hk)
            }
        } catch {
            NSLog("config error: %@", error.localizedDescription)
            pendingToast = "配置文件有误，沿用上一次的配置：\(error.localizedDescription)"
        }
    }

    // MARK: Hotkey

    func installHotKeyHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggle() }
                return noErr
            }, 1, &spec, nil, nil)
    }

    func registerHotKey(_ text: String) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        guard let hk = parseHotKey(text) else {
            pendingToast = "无法识别热键 \"\(text)\"，请检查配置里的 hotkey"
            return
        }
        let id = EventHotKeyID(signature: OSType(0x53414F4D), id: 1)
        let status = RegisterEventHotKey(
            hk.keyCode, hk.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            pendingToast = "热键 \"\(text)\" 注册失败（可能被其他应用占用）"
        }
    }

    // MARK: Show / hide

    func toggle() {
        if visible { webView.evaluateJavaScript("SAO.close()") } else { show() }
    }

    /// intro: play the launch sequence first (only used at app start).
    func show(intro: Bool = false) {
        guard pageReady else { return }
        sounds.invalidate()
        reloadConfigIfChanged()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        else { return }
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(webView)
        visible = true
        let x = mouse.x - screen.frame.minX
        let y = screen.frame.maxY - mouse.y
        if intro && introEnabled,
            let data = try? JSONSerialization.data(withJSONObject: [NSUserName()]),
            let user = String(data: data, encoding: .utf8)
        {
            webView.evaluateJavaScript("SAO.intro(\(user)[0], \(x), \(y))")
        } else {
            webView.evaluateJavaScript("SAO.open(\(x), \(y))")
        }
        if let msg = pendingToast {
            pendingToast = nil
            if let data = try? JSONSerialization.data(withJSONObject: [msg]),
                let arr = String(data: data, encoding: .utf8)
            {
                webView.evaluateJavaScript("SAO.toast(\(arr)[0])")
            }
        }
    }

    func hide() {
        visible = false
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if visible { webView.evaluateJavaScript("SAO.close()") }
    }

    // MARK: JS bridge

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "bad message")
            return
        }
        switch cmd {
        case "ready":
            pageReady = true
            replyHandler(["ok": true], nil)
            show(intro: true)
        case "hide":
            hide()
            replyHandler(["ok": true], nil)
        case "run":
            let action = body["action"] as? [String: Any] ?? [:]
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.run(action)
                DispatchQueue.main.async { replyHandler(result, nil) }
            }
        case "icon":
            replyHandler(["icon": appIcon(body["app"] as? String ?? "") as Any], nil)
        case "sfx":
            sounds.play(body["name"] as? String ?? "")
            replyHandler(["ok": true], nil)
        case "log":
            NSLog("[js] %@", String(describing: body["msg"] ?? ""))
            replyHandler(["ok": true], nil)
        default:
            replyHandler(nil, "unknown cmd \(cmd)")
        }
    }

    // MARK: Actions

    /// Finds an app by path, bundle id, or name ("Music", "Visual Studio Code").
    func resolveApp(_ name: String) -> URL? {
        let fm = FileManager.default
        if name.contains("/") {
            let p = (name as NSString).expandingTildeInPath
            return fm.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        let file = name.hasSuffix(".app") ? name : name + ".app"
        let dirs = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities",
            "/Applications/Utilities", NSHomeDirectory() + "/Applications",
            "/System/Library/CoreServices", "/System/Library/CoreServices/Applications",
        ]
        for dir in dirs where fm.fileExists(atPath: dir + "/" + file) {
            return URL(fileURLWithPath: dir + "/" + file)
        }
        return nil
    }

    /// The app's own icon as a PNG data URL, for showing in the menu.
    func appIcon(_ name: String) -> String? {
        guard let url = resolveApp(name),
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        let size = NSSize(width: 64, height: 64)
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSWorkspace.shared.icon(forFile: url.path).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// Opens urls (with a specific app if given), or just launches the app. Never blocks.
    func launch(_ urls: [URL], with appURL: URL?) {
        let cfg = NSWorkspace.OpenConfiguration()
        let done: (NSRunningApplication?, Error?) -> Void = { _, err in
            if let err = err { NSLog("open failed: %@", err.localizedDescription) }
        }
        if let appURL = appURL {
            if urls.isEmpty {
                NSWorkspace.shared.openApplication(at: appURL, configuration: cfg, completionHandler: done)
            } else {
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg, completionHandler: done)
            }
        } else if let url = urls.first {
            NSWorkspace.shared.open(url, configuration: cfg, completionHandler: done)
        }
    }

    /// Validates and starts an action. Runs off the main thread, so a system
    /// permission prompt can never freeze the overlay on top of itself.
    func run(_ action: [String: Any]) -> [String: Any] {
        func fail(_ msg: String) -> [String: Any] { ["ok": false, "error": msg] }
        func text(_ key: String) -> String {
            ((action[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fm = FileManager.default
        let type = (action["type"] as? String) ?? "open"

        // optional "app": which application handles the file / url / terminal
        var appURL: URL?
        let appName = text("app")
        if !appName.isEmpty {
            guard let url = resolveApp(appName) else { return fail("找不到应用：\(appName)") }
            appURL = url
        }

        switch type {
        case "open":
            let raw = text("path")
            guard !raw.isEmpty else { return fail("动作缺少 path") }
            let path = (raw as NSString).expandingTildeInPath
            guard fm.fileExists(atPath: path) else { return fail("路径不存在：\(raw)") }
            launch([URL(fileURLWithPath: path)], with: appURL)
        case "app":
            guard let appURL = appURL else { return fail("动作缺少 app") }
            launch([], with: appURL)
        case "url":
            var raw = text("url")
            guard !raw.isEmpty else { return fail("动作缺少 url") }
            if !raw.contains(":") { raw = "https://" + raw }
            guard let url = URL(string: raw), url.scheme != nil else { return fail("网址无效：\(raw)") }
            launch([url], with: appURL)
        case "terminal":
            let cwdRaw = text("cwd").isEmpty ? "~" : text("cwd")
            let cwd = (cwdRaw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else {
                return fail("目录不存在：\(cwdRaw)")
            }
            guard let term = appURL ?? resolveApp("Terminal") else { return fail("找不到终端应用") }
            // A self-deleting .command script: the terminal app runs it in a new
            // window, then drops into a normal shell so the window stays usable.
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sao-menu")
            let script = dir.appendingPathComponent("run-\(UUID().uuidString.prefix(8)).command")
            let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
            var body = "#!/bin/zsh -i\nrm -f \"$0\"\ncd \(quoted) || exit 1\nclear\n"
            if !text("command").isEmpty { body += text("command") + "\n" }
            body += "exec \"${SHELL:-/bin/zsh}\" -l\n"
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try body.write(to: script, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            } catch {
                return fail("无法创建终端脚本：\(error.localizedDescription)")
            }
            launch([script], with: term)
        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
        default:
            return fail("暂不支持的动作类型：\(type)")
        }
        return ["ok": true]
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
