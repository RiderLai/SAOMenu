// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift tools/make-icon.swift   (run from the project root)
import Cocoa

let px = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// rounded-square background
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.30, green: 0.44, blue: 0.56, alpha: 1),
           ending: NSColor(red: 0.09, green: 0.14, blue: 0.21, alpha: 1))!.draw(in: tile, angle: -90)

// the menu: three round buttons, the middle one selected, with its panel
func button(_ cy: CGFloat, selected: Bool) {
    let r: CGFloat = 92, cx: CGFloat = 360
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    (selected ? NSColor(red: 0.95, green: 0.64, blue: 0.05, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.9).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: cx - r + 10, y: cy - r + 10, width: 2 * r - 20, height: 2 * r - 20))
    ring.lineWidth = 6
    ring.stroke()
}
button(742, selected: false)
button(512, selected: true)
button(282, selected: false)

NSColor(white: 0.97, alpha: 1).setFill()
let pointer = NSBezierPath()
pointer.move(to: NSPoint(x: 492, y: 512))
pointer.line(to: NSPoint(x: 536, y: 548))
pointer.line(to: NSPoint(x: 536, y: 476))
pointer.close()
pointer.fill()
NSBezierPath(roundedRect: NSRect(x: 534, y: 372, width: 300, height: 280), xRadius: 26, yRadius: 26).fill()
NSColor(red: 0.95, green: 0.64, blue: 0.05, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 562, y: 556, width: 244, height: 62), xRadius: 14, yRadius: 14).fill()
NSColor(white: 0.72, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 578, y: 492, width: 190, height: 22), xRadius: 11, yRadius: 11).fill()
NSBezierPath(roundedRect: NSRect(x: 578, y: 426, width: 150, height: 22), xRadius: 11, yRadius: 11).fill()
NSGraphicsContext.current?.flushGraphics()

let fm = FileManager.default
let set = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try fm.createDirectory(at: set, withIntermediateDirectories: true)
let master = set.appendingPathComponent("icon_512x512@2x.png")
try rep.representation(using: .png, properties: [:])!.write(to: master)

func sh(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                     ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512)] {
    sh(["/usr/bin/sips", "-z", "\(size)", "\(size)", master.path, "--out", set.appendingPathComponent("icon_\(name).png").path])
}
sh(["/usr/bin/iconutil", "-c", "icns", set.path, "-o", "Resources/AppIcon.icns"])
print("Wrote Resources/AppIcon.icns")
