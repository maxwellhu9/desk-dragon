import AppKit

/// `--dump-frames dir` renders a few poses to PNG so the art can be checked without launching.
if let i = CommandLine.arguments.firstIndex(of: "--dump-frames") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "frames"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var poses: [(String, Pose)] = []
    var p = Pose(); poses.append(("idle", p))
    p = Pose(); p.mood = .happy; poses.append(("happy", p))
    p = Pose(); p.mood = .surprised; p.legLift = (8, 8); p.armSwing = 30; poses.append(("held", p))
    p = Pose(); p.mood = .sleepy; poses.append(("sleep", p))
    p = Pose(); p.mouthOpen = 1; p.look = CGPoint(x: -0.8, y: 0.2); poses.append(("fire", p))
    p = Pose(); p.lean = 14; p.legLift = (12, 0); p.armSwing = 30; p.mood = .happy; p.tailSway = 12; poses.append(("zoom", p))
    for (name, pose) in poses {
        let s = 2
        let w = Int(DinoArt.canvas.width) * s, h = Int(DinoArt.canvas.height) * s
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(white: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        let t = NSAffineTransform(); t.scale(by: CGFloat(s)); t.concat()
        DinoArt.draw(pose)
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    print("wrote previews to \(dir)")
    exit(0)
}

/// `--cutout in.png out.png` tests the background removal.
if let i = CommandLine.arguments.firstIndex(of: "--cutout"), CommandLine.arguments.count > i + 2 {
    let ok = ImageSprite.load(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    if ok, let png = ImageSprite.debugPNG() {
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        print("cutout ok: opaque bounds \(ImageSprite.opaqueBounds)")
    } else {
        print("cutout failed")
    }
    exit(ok ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var brain: PetBrain!
    var timer: Timer?
    var last = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = DinoArt.windowSize
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let start = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY)
        brain = PetBrain(size: size, start: start)
        brain.state = .falling
        if let i = CommandLine.arguments.firstIndex(of: "--image"), CommandLine.arguments.count > i + 1 {
            ImageSprite.load(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        } else if let saved = UserDefaults.standard.string(forKey: "spriteImagePath"), ImageSprite.load(url: URL(fileURLWithPath: saved)) {
        } else if let url = ImageSprite.defaultURL() {
            ImageSprite.load(url: url)
        }
        window = PetWindow(brain: brain)
        window.orderFrontRegardless()
        brain.say(brain.discovered.isEmpty ? "hi! I'm new here" : "I'm back!", for: 3)

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(last), 0.05)
        last = now
        brain.update(dt: dt)
        if brain.state != .held {
            window.setFrameOrigin(brain.position)
        }
        updateHover()
        window.contentView?.needsDisplay = true
    }

    /// Track whether the cursor is over the dino's body, and let clicks pass through elsewhere.
    private func updateHover() {
        if brain.state == .held { window.ignoresMouseEvents = false; brain.hovering = true; return }
        let m = NSEvent.mouseLocation
        let f = window.frame
        guard f.contains(m) else { window.ignoresMouseEvents = true; brain.hovering = false; return }
        var local = NSPoint(x: m.x - f.minX - DinoArt.margin, y: m.y - f.minY)
        if brain.facingRight { local.x = DinoArt.canvas.width - local.x }
        let hit = Art.hitTest(local, pose: brain.pose)
        brain.hovering = hit
        window.ignoresMouseEvents = !hit
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
