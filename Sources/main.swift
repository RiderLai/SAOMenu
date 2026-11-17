import Cocoa
import WebKit
import Carbon.HIToolbox
import AVFoundation
import UniformTypeIdentifiers

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

// MARK: - Mouse gesture

/// Hold the left and right buttons together and drag down to summon the menu.
/// With Accessibility permission an event tap swallows the second button press,
/// so the app underneath never sees it. Without permission it falls back to
/// just watching, which works but can let a context menu through.
final class MouseGesture {
    var onTrigger: (() -> Void)?
    private var enabled = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private var retry: Timer?

    private var start: CGPoint?
    private var fired = false
    private var swallowUp: CGEventType?
    private let distance: CGFloat = 70

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on { install() } else { remove() }
    }

    private func install() {
        if installTap() { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.watch() }
        // switch to the tap as soon as permission is granted
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, self.enabled, self.tap == nil, self.installTap() else { return }
            self.removeMonitor()
        }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        retry?.invalidate()
        retry = nil
    }

    private func remove() {
        removeMonitor()
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
            CFMachPortInvalidate(port)
        }
        tap = nil
        source = nil
        start = nil
        swallowUp = nil
    }

    private func installTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [
            .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MouseGesture>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        return true
    }

    /// Event tap path. Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            let other: CGMouseButton = type == .leftMouseDown ? .right : .left
            guard CGEventSource.buttonState(.combinedSessionState, button: other) else { return false }
            start = event.location
            fired = false
            swallowUp = type == .leftMouseDown ? .leftMouseUp : .rightMouseUp
            return true
        case .leftMouseDragged, .rightMouseDragged:
            guard let s = start else { return false }
            let p = event.location  // y grows downward here
            let dy = p.y - s.y
            if !fired && dy > distance && abs(p.x - s.x) < dy {
                fired = true
                onTrigger?()
            }
            return true
        case .leftMouseUp, .rightMouseUp:
            start = nil
            if type == swallowUp {
                swallowUp = nil
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Fallback path without permission: observe only.
    private func watch() {
        let both = NSEvent.pressedMouseButtons & 3 == 3
        let p = NSEvent.mouseLocation  // y grows upward here
        guard both else {
            start = nil
            return
        }
        guard let s = start else {
            start = p
            fired = false
            return
        }
        let dy = s.y - p.y
        if !fired && dy > distance && abs(p.x - s.x) < dy {
            fired = true
            onTrigger?()
        }
    }
}

// MARK: - Trackpad tap

/// Detects an N-finger tap on the trackpad. macOS has no public API for global
/// trackpad touches, so this reads them from the private MultitouchSupport
/// framework, loaded at runtime; if anything is missing the feature stays off.
final class TrackpadTap {
    static let shared = TrackpadTap()
    var onTap: (() -> Void)?
    private(set) var available = false

    private typealias Callback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32

    private var devices: [UnsafeMutableRawPointer] = []
    private var retry: Timer?
    private var unregister: Register?
    private var stop: Stop?

    // touch state, only used on the framework's callback thread
    private var target = 0
    private var maxCount = 0
    private var began = 0.0
    private var origin: (Float, Float)?
    private var moved = false

    /// fingers: 3, 4 or 5; 0 turns the gesture off.
    func setFingers(_ fingers: Int) {
        guard fingers != target else { return }
        target = fingers
        retry?.invalidate()
        retry = nil
        if fingers == 0 { return stopDevices() }
        if devices.isEmpty { startDevices() }
        if devices.isEmpty {
            // no trackpad right now (e.g. a Bluetooth one that is off): keep looking
            retry = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                self.startDevices()
                if !self.devices.isEmpty { timer.invalidate() }
            }
        }
    }

    private func startDevices() {
        guard let lib = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
            let pList = dlsym(lib, "MTDeviceCreateList"),
            let pReg = dlsym(lib, "MTRegisterContactFrameCallback"),
            let pUnreg = dlsym(lib, "MTUnregisterContactFrameCallback"),
            let pStart = dlsym(lib, "MTDeviceStart"),
            let pStop = dlsym(lib, "MTDeviceStop")
        else {
            NSLog("trackpad: MultitouchSupport unavailable")
            return
        }
        let createList = unsafeBitCast(pList, to: CreateList.self)
        let register = unsafeBitCast(pReg, to: Register.self)
        let start = unsafeBitCast(pStart, to: Start.self)
        unregister = unsafeBitCast(pUnreg, to: Register.self)
        stop = unsafeBitCast(pStop, to: Stop.self)

        guard let list = createList()?.takeRetainedValue() else { return }
        let callback: Callback = { _, touches, count, _, _ in
            TrackpadTap.shared.frame(touches, Int(count))
            return 0
        }
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            _ = Unmanaged<AnyObject>.fromOpaque(raw).retain()  // keep the device alive
            register(device, callback)
            _ = start(device, 0)
            devices.append(device)
        }
        available = !devices.isEmpty
        if available { NSLog("trackpad: watching %d device(s)", devices.count) }
    }

    private func stopDevices() {
        let callback: Callback = { _, _, _, _, _ in 0 }
        for device in devices {
            unregister?(device, callback)
            _ = stop?(device)
        }
        devices.removeAll()
    }

    /// One frame of touch data. A tap is: fingers land, never exceed or move
    /// away from the target count's starting spot, and all lift quickly.
    private func frame(_ touches: UnsafeMutableRawPointer?, _ count: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        if count == 0 {
            if target > 0 && maxCount == target && !moved && now - began < 0.35 {
                DispatchQueue.main.async { self.onTap?() }
            }
            maxCount = 0
            origin = nil
            moved = false
            return
        }
        if maxCount == 0 { began = now }
        if count > maxCount {
            maxCount = count
            origin = nil
        }
        guard count == maxCount, let touches = touches else { return }
        // Each touch record is 96 bytes with the normalized position at offset 32.
        var x: Float = 0, y: Float = 0
        for i in 0..<count {
            let px = touches.load(fromByteOffset: i * 96 + 32, as: Float.self)
            let py = touches.load(fromByteOffset: i * 96 + 36, as: Float.self)
            // positions are 0...1; anything else means the layout isn't what we expect
            guard px > -0.5, px < 1.5, py > -0.5, py < 1.5 else { return }
            x += px
            y += py
        }
        x /= Float(count)
        y /= Float(count)
        if let o = origin {
            if hypot(x - o.0, y - o.1) > 0.04 { moved = true }
        } else {
            origin = (x, y)
        }
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
    let mouseGesture = MouseGesture()
    var settingsWindow: NSWindow?
    var settingsWeb: WKWebView?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        ensureDefaultConfig()
        buildPanel()
        buildStatusItem()
        buildMainMenu()
        mouseGesture.onTrigger = { [weak self] in
            guard let self = self, !self.visible else { return }
            self.show()
        }
        TrackpadTap.shared.onTap = { [weak self] in self?.toggle() }
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
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SAO Menu", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc func showFromMenu() { show() }
    @objc func quit() { NSApp.terminate(nil) }
    /// The app has no menu bar of its own, but text fields in the settings window
    /// only get ⌘C / ⌘V / ⌘A etc. through a main menu.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "退出 SAO Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Settings window

    @objc func openSettings() {
        // keep the last config that was in place before this editing session
        let backup = configDir.appendingPathComponent("config.backup.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: configURL, to: backup)

        if let web = settingsWeb {
            web.evaluateJavaScript("Settings.reload()")
        } else {
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "settings")
            let frame = NSRect(x: 0, y: 0, width: 940, height: 660)
            let web = WKWebView(frame: frame, configuration: cfg)
            if #available(macOS 13.3, *) { web.isInspectable = true }
            let win = NSWindow(
                contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "SAO Menu 设置"
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 760, height: 480)
            win.contentView = web
            win.center()
            let res = Bundle.main.resourceURL!
            web.loadFileURL(res.appendingPathComponent("settings.html"), allowingReadAccessTo: res)
            settingsWindow = win
            settingsWeb = web
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func handleSettings(_ cmd: String, _ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        switch cmd {
        case "load":
            let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let defaults = Bundle.main.url(forResource: "default-config", withExtension: "json")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "{}"
            reply(["text": text, "defaults": defaults, "trusted": AXIsProcessTrusted()], nil)
        case "axPrompt":
            // shows the system dialog that leads to the Accessibility settings
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            reply(["trusted": AXIsProcessTrustedWithOptions([key: true] as CFDictionary)], nil)
        case "save":
            guard let text = body["text"] as? String, let data = text.data(using: .utf8),
                (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
            else {
                reply(["ok": false, "error": "配置内容无效"], nil)
                return
            }
            do {
                try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
                try data.write(to: configURL, options: .atomic)
            } catch {
                reply(["ok": false, "error": "写入失败：\(error.localizedDescription)"], nil)
                return
            }
            reloadConfigIfChanged()  // applies a changed hotkey right away
            var result: [String: Any] = ["ok": true]
            if let warning = pendingToast {
                result["warning"] = warning
                pendingToast = nil
            }
            reply(result, nil)
        case "pick":
            let kind = body["kind"] as? String ?? "file"
            let open = NSOpenPanel()
            open.canChooseFiles = kind != "dir"
            open.canChooseDirectories = kind != "app"
            open.treatsFilePackagesAsDirectories = false
            if kind == "app" {
                open.allowedContentTypes = [.application]
                open.directoryURL = URL(fileURLWithPath: "/Applications")
            }
            open.begin { response in
                guard response == .OK, let url = open.url else {
                    reply(["path": NSNull()], nil)
                    return
                }
                var path = (url.path as NSString).abbreviatingWithTildeInPath
                if kind == "app" {
                    // prefer the plain name when it resolves to the same app
                    let name = url.deletingPathExtension().lastPathComponent
                    if self.resolveApp(name)?.standardizedFileURL.path == url.standardizedFileURL.path {
                        path = name
                    }
                }
                reply(["path": path], nil)
            }
        case "hotkey":
            // while the settings window records a new hotkey, the old one must not fire
            if body["suspend"] as? Bool == true {
                if let ref = hotKeyRef {
                    UnregisterEventHotKey(ref)
                    hotKeyRef = nil
                }
            } else {
                registerHotKey(hotkeyText)
                pendingToast = nil
            }
            reply(["ok": true], nil)
        case "preview":
            show()
            reply(["ok": true], nil)
        case "openFile":
            editConfig()
            reply(["ok": true], nil)
        default:
            reply(nil, "unknown cmd \(cmd)")
        }
    }

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
            mouseGesture.setEnabled((obj["mouseGesture"] as? Bool) ?? false)
            let taps = ["tap3": 3, "tap4": 4, "tap5": 5]
            TrackpadTap.shared.setFingers(taps[(obj["trackpad"] as? String) ?? "off"] ?? 0)
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
        if message.name == "settings" {
            handleSettings(cmd, body, replyHandler)
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
        case "settings":
            DispatchQueue.main.async { self.openSettings() }
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
