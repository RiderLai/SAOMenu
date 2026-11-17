// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift tools/make-icon.swift   (run from the project root)
import Cocoa

let px = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let center = NSPoint(x: 512, y: 512)
func polar(_ angle: CGFloat, _ radius: CGFloat) -> NSPoint {
    NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
}

// rounded-square sky, clipped so the burst stays inside
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(colors: [rgb(120, 230, 255), rgb(64, 150, 255), rgb(96, 84, 230)])!.draw(in: tile, angle: -90)

// speed-line burst: alternating light rays from the center
let rays = 26
for i in 0..<rays {
    let a = CGFloat(i) / CGFloat(rays) * 2 * .pi + 0.07
    let half: CGFloat = i % 2 == 0 ? 0.062 : 0.034
    let ray = NSBezierPath()
    ray.move(to: center)
    ray.line(to: polar(a - half, 760))
    ray.line(to: polar(a + half, 760))
    ray.close()
    NSColor.white.withAlphaComponent(i % 2 == 0 ? 0.20 : 0.11).setFill()
    ray.fill()
}

// coloured light streaks flying outward
let streaks: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
    (0.42, 300, 120, 24, rgb(255, 120, 190)), (1.25, 330, 100, 18, rgb(255, 232, 110)),
    (2.05, 310, 130, 22, rgb(150, 255, 170)), (2.75, 345, 90, 16, rgb(255, 255, 255)),
    (3.62, 305, 125, 24, rgb(255, 214, 96)), (4.30, 335, 100, 18, rgb(255, 130, 200)),
    (5.05, 300, 130, 22, rgb(170, 255, 250)), (5.80, 340, 95, 16, rgb(255, 255, 255)),
]
for (a, r, len, width, color) in streaks {
    let bar = NSBezierPath()
    bar.move(to: polar(a, r))
    bar.line(to: polar(a, r + len))
    bar.lineWidth = width
    bar.lineCapStyle = .round
    color.withAlphaComponent(0.92).setStroke()
    bar.stroke()
}
NSGraphicsContext.restoreGraphicsState()

// glowing orange halo behind the main button
NSGradient(colors: [rgb(255, 252, 225, 0.95), rgb(255, 244, 190, 0.5), rgb(255, 255, 255, 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 512 - 330, y: 512 - 330, width: 660, height: 660)),
          relativeCenterPosition: .zero)

// the round menu button: white disc, orange ring, soft top highlight
let shadow = NSShadow()
shadow.shadowColor = rgb(20, 30, 90, 0.45)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
let disc = NSBezierPath(ovalIn: NSRect(x: 512 - 236, y: 512 - 236, width: 472, height: 472))
disc.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor.white, rgb(232, 240, 250)])!.draw(in: disc, angle: -90)
rgb(246, 160, 16).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 512 - 204, y: 512 - 204, width: 408, height: 408))
ring.lineWidth = 16
ring.stroke()

// a sword across the button, tip up-right
NSGraphicsContext.saveGraphicsState()
let turn = NSAffineTransform()
turn.translateX(by: 512, yBy: 512)
turn.rotate(byDegrees: -45)
turn.concat()
let blade = NSBezierPath()
blade.move(to: NSPoint(x: 0, y: 172))
blade.line(to: NSPoint(x: 21, y: 132))
blade.line(to: NSPoint(x: 21, y: -62))
blade.line(to: NSPoint(x: -21, y: -62))
blade.line(to: NSPoint(x: -21, y: 132))
blade.close()
rgb(46, 58, 92).setFill()
blade.fill()
let shine = NSBezierPath()
shine.move(to: NSPoint(x: 0, y: 160))
shine.line(to: NSPoint(x: 10, y: 130))
shine.line(to: NSPoint(x: 10, y: -62))
shine.line(to: NSPoint(x: 0, y: -62))
shine.close()
rgb(120, 200, 255).setFill()
shine.fill()
rgb(246, 160, 16).setFill()
NSBezierPath(roundedRect: NSRect(x: -66, y: -86, width: 132, height: 28), xRadius: 14, yRadius: 14).fill()
rgb(46, 58, 92).setFill()
NSBezierPath(roundedRect: NSRect(x: -13, y: -150, width: 26, height: 68), xRadius: 8, yRadius: 8).fill()
rgb(246, 160, 16).setFill()
NSBezierPath(ovalIn: NSRect(x: -19, y: -180, width: 38, height: 38)).fill()
NSGraphicsContext.restoreGraphicsState()

// four-point sparkles
func sparkle(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
    let p = NSBezierPath()
    let thin = size * 0.16
    p.move(to: NSPoint(x: x, y: y + size))
    p.curve(to: NSPoint(x: x + size, y: y), controlPoint1: NSPoint(x: x + thin, y: y + thin), controlPoint2: NSPoint(x: x + thin, y: y + thin))
    p.curve(to: NSPoint(x: x, y: y - size), controlPoint1: NSPoint(x: x + thin, y: y - thin), controlPoint2: NSPoint(x: x + thin, y: y - thin))
    p.curve(to: NSPoint(x: x - size, y: y), controlPoint1: NSPoint(x: x - thin, y: y - thin), controlPoint2: NSPoint(x: x - thin, y: y - thin))
    p.curve(to: NSPoint(x: x, y: y + size), controlPoint1: NSPoint(x: x - thin, y: y + thin), controlPoint2: NSPoint(x: x - thin, y: y + thin))
    NSColor.white.setFill()
    p.fill()
}
sparkle(742, 760, 62)
sparkle(812, 652, 30)
sparkle(262, 282, 44)
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
