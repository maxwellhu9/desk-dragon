import AppKit

enum Mood { case normal, happy, surprised, sleepy, eating }

/// Everything the artist needs to draw one moment of the dino. Filled in by PetBrain each tick.
struct Pose {
    var t: TimeInterval = 0
    var blink: CGFloat = 0          // 0 open ... 1 closed
    var look = CGPoint.zero         // eye offset, each axis -1...1
    var mood: Mood = .normal
    var bob: CGFloat = 0            // whole-body vertical offset
    var lean: CGFloat = 0           // whole-body tilt in degrees (positive leans forward)
    var legLift: (CGFloat, CGFloat) = (0, 0)   // front, back foot lift in px
    var armSwing: CGFloat = 0       // degrees
    var tailSway: CGFloat = 0       // px, tip up/down
    var mouthOpen: CGFloat = 0      // 0 closed ... 1 wide open
    var squash: CGFloat = 1         // vertical scale of the body (1 = normal)
    var breath: CGFloat = 0         // -1...1 slow breathing cycle
}

/// A chibi blue dino in a flat anime-sticker style: pale blue fills, dark outlines, shine spots.
/// Art space is `canvas` points, origin bottom-left, dino facing LEFT, feet near the bottom.
/// The top band of the canvas is reserved for the speech bubble.
enum DinoArt {
    static let canvas = NSSize(width: 320, height: 370)
    /// Transparent room around the canvas so fire, dust and bubbles aren't clipped at the window edge.
    static let margin: CGFloat = 260
    static var windowSize: NSSize { NSSize(width: canvas.width + margin * 2, height: canvas.height + 60) }
    static let snout = NSPoint(x: 52, y: 180)       // where fire comes out (art space, facing left)
    static let headTop = NSPoint(x: 125, y: 300)    // where hearts, Zs and the speech bubble anchor
    static let headCenter = NSPoint(x: 125, y: 205)
    static let pivot = NSPoint(x: 140, y: 30)

    // Palette
    static let blue = NSColor(srgbRed: 0.66, green: 0.85, blue: 1.0, alpha: 1)
    static let blueShade = NSColor(srgbRed: 0.55, green: 0.76, blue: 0.97, alpha: 1)
    static let spikeBlue = NSColor(srgbRed: 0.80, green: 0.91, blue: 1.0, alpha: 1)
    static let belly = NSColor(srgbRed: 0.94, green: 0.97, blue: 1.0, alpha: 1)
    static let outline = NSColor(srgbRed: 0.24, green: 0.30, blue: 0.52, alpha: 1)
    static let blush = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.62, alpha: 0.65)
    static let eye = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.18, alpha: 1)
    static let mouthDark = NSColor(srgbRed: 0.45, green: 0.18, blue: 0.30, alpha: 1)
    static let tongue = NSColor(srgbRed: 0.98, green: 0.55, blue: 0.65, alpha: 1)
    static let lineWidth: CGFloat = 3.2

    // MARK: Shapes

    struct Shapes {
        var tail: NSBezierPath
        var tailSpikes: [NSBezierPath]
        var backSpikes: [NSBezierPath]
        var crest: [NSBezierPath]
        var body, belly: NSBezierPath
        var armFront, armBack: NSBezierPath
        var footFront, footBack: NSBezierPath
        var head: NSBezierPath
        var solids: [NSBezierPath] { [tail, body, armFront, armBack, footFront, footBack, head] + tailSpikes + backSpikes + crest }
    }

    static func shapes(_ p: Pose) -> Shapes {
        let bob = p.bob
        let breathe = p.breath * 1.5

        // Tail: a tapered curve out the back (right side), tip curling up.
        let tail = NSBezierPath()
        let tip = NSPoint(x: 296, y: 118 + bob + p.tailSway)
        tail.move(to: NSPoint(x: 168, y: 52 + bob))
        tail.curve(to: tip, controlPoint1: NSPoint(x: 232, y: 30 + bob), controlPoint2: NSPoint(x: 296, y: 60 + bob + p.tailSway * 0.5))
        tail.curve(to: NSPoint(x: 176, y: 122 + bob),
                   controlPoint1: NSPoint(x: 274, y: 138 + bob + p.tailSway), controlPoint2: NSPoint(x: 214, y: 142 + bob))
        tail.close()
        // Spikes along the top edge of the tail (evaluate that bezier).
        let a = tip, c1 = NSPoint(x: 274, y: 138 + bob + p.tailSway), c2 = NSPoint(x: 214, y: 142 + bob), d = NSPoint(x: 176, y: 122 + bob)
        var tailSpikes: [NSBezierPath] = []
        for (f, h) in [(0.2, 12.0), (0.42, 15.0), (0.64, 17.0), (0.86, 18.0)] {
            let t = CGFloat(f)
            let pt = bezier(a, c1, c2, d, t)
            let tg = bezierTangent(a, c1, c2, d, t)
            let n = CGVector(dx: tg.dy, dy: -tg.dx)   // outward (up) normal for this direction of travel
            tailSpikes.append(spike(base: pt, dir: n, width: 16, height: CGFloat(h)))
        }

        let bodyRect = NSRect(x: 72, y: 22 + bob, width: 134, height: (140 + breathe) * p.squash)
        let body = NSBezierPath(ovalIn: bodyRect)
        let belly = NSBezierPath(ovalIn: NSRect(x: 76, y: 30 + bob, width: 98, height: 112 * p.squash))

        // Back spikes on the body's rear (right) edge.
        var backSpikes: [NSBezierPath] = []
        for (deg, h) in [(8.0, 16.0), (32.0, 18.0), (56.0, 18.0)] {
            let r = deg * .pi / 180
            let base = NSPoint(x: bodyRect.midX + cos(r) * bodyRect.width / 2, y: bodyRect.midY + sin(r) * bodyRect.height / 2)
            backSpikes.append(spike(base: base, dir: CGVector(dx: cos(r), dy: sin(r)), width: 18, height: CGFloat(h)))
        }

        func arm(x: CGFloat, swing: CGFloat) -> NSBezierPath {
            let a = NSBezierPath(ovalIn: NSRect(x: x, y: 74 + bob, width: 42, height: 50))
            var t = AffineTransform(translationByX: x + 21, byY: 118 + bob)
            t.rotate(byDegrees: swing)
            t.translate(x: -(x + 21), y: -(118 + bob))
            a.transform(using: t)
            return a
        }
        let armFront = arm(x: 46, swing: 18 + p.armSwing)
        let armBack = arm(x: 166, swing: -18 - p.armSwing)

        let footFront = NSBezierPath(ovalIn: NSRect(x: 66, y: 6 + p.legLift.0, width: 66, height: 46))
        let footBack = NSBezierPath(ovalIn: NSRect(x: 148, y: 6 + p.legLift.1, width: 66, height: 46))

        let headRect = NSRect(x: 45, y: 128 + bob, width: 162, height: 152)
        let head = NSBezierPath(ovalIn: headRect)
        var crest: [NSBezierPath] = []
        for (deg, h, w) in [(152.0, 20.0, 22.0), (124.0, 26.0, 26.0), (96.0, 30.0, 28.0), (68.0, 26.0, 26.0), (42.0, 20.0, 22.0)] {
            let r = deg * .pi / 180
            let base = NSPoint(x: headRect.midX + cos(r) * headRect.width / 2 * 0.97, y: headRect.midY + sin(r) * headRect.height / 2 * 0.97)
            crest.append(spike(base: base, dir: CGVector(dx: cos(r), dy: sin(r)), width: CGFloat(w), height: CGFloat(h)))
        }

        return Shapes(tail: tail, tailSpikes: tailSpikes, backSpikes: backSpikes, crest: crest,
                      body: body, belly: belly, armFront: armFront, armBack: armBack,
                      footFront: footFront, footBack: footBack, head: head)
    }

    private static func bezier(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ d: NSPoint, _ t: CGFloat) -> NSPoint {
        let u = 1 - t
        return NSPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                       y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
    }
    private static func bezierTangent(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ d: NSPoint, _ t: CGFloat) -> CGVector {
        let u = 1 - t
        let dx = 3*u*u*(b.x-a.x) + 6*u*t*(c.x-b.x) + 3*t*t*(d.x-c.x)
        let dy = 3*u*u*(b.y-a.y) + 6*u*t*(c.y-b.y) + 3*t*t*(d.y-c.y)
        let len = max(1, hypot(dx, dy))
        return CGVector(dx: dx / len, dy: dy / len)
    }

    /// A rounded triangle from `base` along `dir`, with its base sunk a little into the parent shape.
    private static func spike(base: NSPoint, dir: CGVector, width: CGFloat, height: CGFloat) -> NSBezierPath {
        let len = max(1, hypot(dir.dx, dir.dy))
        let u = CGVector(dx: dir.dx / len, dy: dir.dy / len)
        let n = CGVector(dx: -u.dy, dy: u.dx)
        let s = NSBezierPath()
        let b = NSPoint(x: base.x - u.dx * 8, y: base.y - u.dy * 8)
        let tip = NSPoint(x: base.x + u.dx * height, y: base.y + u.dy * height)
        s.move(to: NSPoint(x: b.x + n.dx * width / 2, y: b.y + n.dy * width / 2))
        s.curve(to: tip,
                controlPoint1: NSPoint(x: base.x + n.dx * width / 2.6 + u.dx * height * 0.5, y: base.y + n.dy * width / 2.6 + u.dy * height * 0.5),
                controlPoint2: NSPoint(x: tip.x + n.dx * 3, y: tip.y + n.dy * 3))
        s.curve(to: NSPoint(x: b.x - n.dx * width / 2, y: b.y - n.dy * width / 2),
                controlPoint1: NSPoint(x: tip.x - n.dx * 3, y: tip.y - n.dy * 3),
                controlPoint2: NSPoint(x: base.x - n.dx * width / 2.6 + u.dx * height * 0.5, y: base.y - n.dy * width / 2.6 + u.dy * height * 0.5))
        s.close()
        return s
    }

    // MARK: Painting helpers

    private static func fillStroke(_ path: NSBezierPath, _ fill: NSColor, width: CGFloat = lineWidth) {
        fill.setFill(); path.fill()
        outline.setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func shine(_ rect: NSRect, angle: CGFloat = -20, alpha: CGFloat = 0.85) {
        let p = NSBezierPath(ovalIn: rect)
        var t = AffineTransform(translationByX: rect.midX, byY: rect.midY)
        t.rotate(byDegrees: angle)
        t.translate(x: -rect.midX, y: -rect.midY)
        p.transform(using: t)
        NSColor(white: 1, alpha: alpha).setFill()
        p.fill()
    }

    // MARK: Drawing

    static func draw(_ p: Pose) {
        NSGraphicsContext.saveGraphicsState()
        var t = AffineTransform(translationByX: pivot.x, byY: pivot.y)
        t.rotate(byDegrees: -p.lean)
        t.translate(x: -pivot.x, y: -pivot.y)
        (t as NSAffineTransform).concat()

        let s = shapes(p)
        let bob = p.bob

        // Ground shadow
        NSColor(srgbRed: 0.35, green: 0.3, blue: 0.5, alpha: 0.14).setFill()
        NSBezierPath(ovalIn: NSRect(x: 60, y: 2, width: 170, height: 16)).fill()

        // Tail with spikes (spikes first so their bases hide under the tail)
        for sp in s.tailSpikes { fillStroke(sp, spikeBlue) }
        fillStroke(s.tail, blue)
        shine(NSRect(x: 246, y: 96 + bob, width: 16, height: 8), angle: 20)

        // Back spikes and back arm behind the body
        for sp in s.backSpikes { fillStroke(sp, spikeBlue) }
        fillStroke(s.armBack, blue)

        // Body, belly, feet
        fillStroke(s.body, blue)
        belly.setFill(); s.belly.fill()
        outline.withAlphaComponent(0.35).setStroke(); s.belly.lineWidth = 2; s.belly.stroke()
        fillStroke(s.footBack, blue)
        fillStroke(s.footFront, blue)
        toes(s.footFront); toes(s.footBack)
        shine(NSRect(x: 78, y: 28 + p.legLift.0, width: 18, height: 9))
        shine(NSRect(x: 160, y: 28 + p.legLift.1, width: 18, height: 9))
        shine(NSRect(x: 92, y: 118 + bob, width: 24, height: 11))

        // Front arm
        fillStroke(s.armFront, blue)
        shine(NSRect(x: 56, y: 104 + bob, width: 14, height: 7))

        // Head with crest
        for sp in s.crest { fillStroke(sp, spikeBlue) }
        fillStroke(s.head, blue)
        shine(NSRect(x: 62, y: 246 + bob, width: 40, height: 18), angle: -25)
        shine(NSRect(x: 108, y: 262 + bob, width: 14, height: 8), angle: -25)

        face(p)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func toes(_ foot: NSBezierPath) {
        let b = foot.bounds
        outline.setStroke()
        for f: CGFloat in [0.22, 0.5, 0.78] {
            let x = b.minX + b.width * f
            let l = NSBezierPath()
            l.move(to: NSPoint(x: x - 5, y: b.minY + 4))
            l.curve(to: NSPoint(x: x + 5, y: b.minY + 4), controlPoint1: NSPoint(x: x - 2, y: b.minY + 12), controlPoint2: NSPoint(x: x + 2, y: b.minY + 12))
            l.lineWidth = 2.2
            l.lineCapStyle = .round
            l.stroke()
        }
    }

    private static func face(_ p: Pose) {
        let bob = p.bob
        let lx = p.look.x * 4, ly = p.look.y * 3

        // Blush
        blush.setFill()
        NSBezierPath(ovalIn: NSRect(x: 58, y: 176 + bob, width: 30, height: 13)).fill()
        NSBezierPath(ovalIn: NSRect(x: 142, y: 180 + bob, width: 30, height: 13)).fill()

        eye(center: NSPoint(x: 84 + lx, y: 206 + bob + ly), rx: 13, ry: 16, p: p)
        eye(center: NSPoint(x: 152 + lx, y: 211 + bob + ly), rx: 12, ry: 15, p: p)

        mouth(p)
    }

    private static func eye(center c: NSPoint, rx: CGFloat, ry: CGFloat, p: Pose) {
        if p.mood == .sleepy || p.blink > 0.9 || p.mood == .happy {
            let path = NSBezierPath()
            let lift: CGFloat = p.mood == .happy ? 9 : -5
            path.move(to: NSPoint(x: c.x - rx * 0.9, y: c.y))
            path.curve(to: NSPoint(x: c.x + rx * 0.9, y: c.y),
                       controlPoint1: NSPoint(x: c.x - rx * 0.3, y: c.y + lift),
                       controlPoint2: NSPoint(x: c.x + rx * 0.3, y: c.y + lift))
            path.lineWidth = 3.5
            path.lineCapStyle = .round
            eye.setStroke()
            path.stroke()
            return
        }
        let openRy = ry * (1 - p.blink * 0.85)
        let scale: CGFloat = p.mood == .surprised ? 1.15 : 1
        let e = NSBezierPath(ovalIn: NSRect(x: c.x - rx * scale, y: c.y - openRy * scale, width: rx * 2 * scale, height: openRy * 2 * scale))
        eye.setFill(); e.fill()
        NSGraphicsContext.saveGraphicsState()
        e.addClip()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - rx * 0.75, y: c.y + openRy * 0.1, width: rx * 0.8, height: openRy * 0.7)).fill()
        NSBezierPath(ovalIn: NSRect(x: c.x + rx * 0.15, y: c.y - openRy * 0.65, width: rx * 0.4, height: openRy * 0.3)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func mouth(_ p: Pose) {
        let bob = p.bob
        let open = p.mood == .sleepy ? 0 : p.mouthOpen
        if p.mood == .surprised {
            let r = 6 + 7 * max(open, 0.4)
            fillStroke(NSBezierPath(ovalIn: NSRect(x: 112 - r * 0.8, y: 170 + bob - r, width: r * 1.6, height: r * 2)), mouthDark, width: 2.5)
            return
        }
        if open > 0.12 {
            let w = 20 + 22 * open, h = 6 + 16 * open
            let top: CGFloat = 176 + bob
            let m = NSBezierPath(ovalIn: NSRect(x: 112 - w / 2, y: top - h, width: w, height: h * 2))
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas.width, height: top)).addClip()
            fillStroke(m, mouthDark, width: 2.5)
            m.addClip()
            tongue.setFill()
            NSBezierPath(ovalIn: NSRect(x: 112 - w * 0.3, y: top - h - 2, width: w * 0.6, height: h * 0.9)).fill()
            NSGraphicsContext.restoreGraphicsState()
            fang(at: NSPoint(x: 104, y: top))
            return
        }
        let m = NSBezierPath()
        let smile: CGFloat = p.mood == .happy ? 9 : 5
        m.move(to: NSPoint(x: 92, y: 176 + bob))
        m.curve(to: NSPoint(x: 128, y: 178 + bob),
                controlPoint1: NSPoint(x: 100, y: 176 + bob - smile),
                controlPoint2: NSPoint(x: 120, y: 178 + bob - smile))
        m.lineWidth = 2.8
        m.lineCapStyle = .round
        outline.setStroke()
        m.stroke()
        fang(at: NSPoint(x: 120, y: 176 + bob))
    }

    private static func fang(at p: NSPoint) {
        let f = NSBezierPath()
        f.move(to: NSPoint(x: p.x - 4, y: p.y))
        f.line(to: NSPoint(x: p.x + 4, y: p.y))
        f.line(to: NSPoint(x: p.x, y: p.y - 9))
        f.close()
        NSColor.white.setFill(); f.fill()
        outline.setStroke(); f.lineWidth = 1.5; f.lineJoinStyle = .round; f.stroke()
    }

    // MARK: Hit testing

    static func hitTest(_ point: NSPoint, pose: Pose) -> Bool {
        let s = shapes(pose)
        return s.solids.contains { $0.contains(point) }
    }
}
