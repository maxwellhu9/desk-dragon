import AppKit

final class PetView: NSView {
    let brain: PetBrain
    private var lastDrag = Date()
    private var mouseDownAt = NSPoint.zero
    private var moved = false

    init(brain: PetBrain) {
        self.brain = brain
        super.init(frame: NSRect(origin: .zero, size: brain.size))
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.shouldAntialias = true
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: DinoArt.margin, yBy: 0)
        if brain.facingRight {
            t.translateX(by: DinoArt.canvas.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
        }
        t.concat()
        Art.draw(brain.pose)
        ctx.restoreGraphicsState()
        drawParticles()
        if let b = brain.bubble { drawBubble(b.text, timeLeft: b.until - brain.clock) }
    }

    // MARK: Speech bubble

    private func drawBubble(_ text: String, timeLeft: TimeInterval) {
        let alpha = CGFloat(min(1, timeLeft / 0.25))
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.2, green: 0.22, blue: 0.35, alpha: alpha)]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let pad: CGFloat = 10
        let w = min(bounds.width - 8, textSize.width + pad * 2), h = textSize.height + pad * 1.2
        let anchor = brain.windowPoint(Art.headTop)
        var x = anchor.x - w / 2
        x = max(4, min(bounds.width - w - 4, x))
        let y = min(bounds.height - h - 4, anchor.y + 14)
        let rect = NSRect(x: x, y: y, width: w, height: h)

        let bubble = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        let tail = NSBezierPath()
        let tx = max(rect.minX + 14, min(rect.maxX - 14, anchor.x))
        tail.move(to: NSPoint(x: tx - 7, y: rect.minY + 1))
        tail.line(to: NSPoint(x: tx, y: rect.minY - 9))
        tail.line(to: NSPoint(x: tx + 7, y: rect.minY + 1))
        tail.close()
        bubble.append(tail)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.18 * alpha)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor(white: 1, alpha: alpha).setFill()
        bubble.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.24, green: 0.30, blue: 0.52, alpha: alpha).setStroke()
        bubble.lineWidth = 2
        bubble.lineJoinStyle = .round
        bubble.stroke()
        str.draw(in: NSRect(x: rect.minX + pad, y: rect.minY + pad * 0.6, width: w - pad * 2, height: textSize.height))
    }

    // MARK: Particles

    private func drawParticles() {
        for p in brain.particles {
            let fade = 1 - p.age
            switch p.kind {
            case .fire:
                let c: NSColor = p.age < 0.35
                    ? NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: fade)
                    : (p.age < 0.7 ? NSColor(srgbRed: 1, green: 0.5, blue: 0.15, alpha: fade)
                                   : NSColor(srgbRed: 0.85, green: 0.2, blue: 0.1, alpha: fade))
                c.setFill()
                let r = p.size * (1 - p.age * 0.5)
                NSBezierPath(ovalIn: NSRect(x: p.pos.x - r, y: p.pos.y - r, width: r * 2, height: r * 2)).fill()
            case .dust:
                let r = p.size * (0.6 + p.age * 0.8)
                let puff = NSBezierPath(ovalIn: NSRect(x: p.pos.x - r, y: p.pos.y - r * 0.8, width: r * 2, height: r * 1.6))
                NSColor(srgbRed: 0.85, green: 0.87, blue: 0.95, alpha: fade * 0.9).setFill(); puff.fill()
                NSColor(srgbRed: 0.24, green: 0.30, blue: 0.52, alpha: fade * 0.8).setStroke(); puff.lineWidth = 1.5; puff.stroke()
            case .heart:
                NSColor(srgbRed: 1, green: 0.4, blue: 0.55, alpha: fade).setFill()
                heart(at: p.pos, size: p.size).fill()
            case .star:
                NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: fade).setFill()
                let s = star(at: p.pos, size: p.size)
                s.fill()
                NSColor(srgbRed: 0.24, green: 0.30, blue: 0.52, alpha: fade).setStroke(); s.lineWidth = 1.2; s.stroke()
            case .z:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: p.size, weight: .bold),
                    .foregroundColor: NSColor(srgbRed: 0.24, green: 0.30, blue: 0.52, alpha: fade),
                ]
                NSAttributedString(string: "z", attributes: attrs).draw(at: p.pos)
            }
        }
    }

    private func heart(at c: NSPoint, size s: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y - s * 0.5))
        p.curve(to: NSPoint(x: c.x - s * 0.5, y: c.y + s * 0.25), controlPoint1: NSPoint(x: c.x - s * 0.6, y: c.y - s * 0.15), controlPoint2: NSPoint(x: c.x - s * 0.75, y: c.y + s * 0.15))
        p.curve(to: NSPoint(x: c.x, y: c.y + s * 0.15), controlPoint1: NSPoint(x: c.x - s * 0.25, y: c.y + s * 0.6), controlPoint2: NSPoint(x: c.x, y: c.y + s * 0.45))
        p.curve(to: NSPoint(x: c.x + s * 0.5, y: c.y + s * 0.25), controlPoint1: NSPoint(x: c.x, y: c.y + s * 0.45), controlPoint2: NSPoint(x: c.x + s * 0.25, y: c.y + s * 0.6))
        p.curve(to: NSPoint(x: c.x, y: c.y - s * 0.5), controlPoint1: NSPoint(x: c.x + s * 0.75, y: c.y + s * 0.15), controlPoint2: NSPoint(x: c.x + s * 0.6, y: c.y - s * 0.15))
        p.close()
        return p
    }

    private func star(at c: NSPoint, size s: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? s * 0.5 : s * 0.22
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let pt = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        p.lineJoinStyle = .round
        return p
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = NSEvent.mouseLocation
        moved = false
        lastDrag = Date()
        brain.grab(atScreen: mouseDownAt)
    }

    override func mouseDragged(with event: NSEvent) {
        let now = Date()
        let p = NSEvent.mouseLocation
        if hypot(p.x - mouseDownAt.x, p.y - mouseDownAt.y) > 3 { moved = true }
        brain.drag(toScreen: p, dt: now.timeIntervalSince(lastDrag))
        lastDrag = now
        window?.setFrameOrigin(brain.position)
    }

    override func mouseUp(with event: NSEvent) {
        if moved {
            brain.release()
            return
        }
        brain.velocity = .zero
        brain.state = brain.position.y > brain.ground + 2 ? .falling : .idle
        if event.clickCount >= 2 {
            brain.zoomies()
        } else {
            brain.breatheFire()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        brain.did(.rightClick)
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, to m: NSMenu = menu, checked: Bool = false) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            item.state = checked ? .on : .off
            m.addItem(item)
        }
        add("Breathe fire", #selector(fire))
        add("Zoomies", #selector(zoom))
        add(brain.state == .sleeping ? "Wake up" : "Go to sleep", #selector(toggleSleep))
        menu.addItem(.separator())
        let tricks = NSMenu()
        for trick in Trick.allCases {
            add(trick.title, #selector(noop), to: tricks, checked: brain.discovered.contains(trick))
        }
        tricks.addItem(.separator())
        add("Forget what I've found", #selector(resetTricks), to: tricks)
        let found = brain.discovered.count
        let tricksItem = NSMenuItem(title: "Tricks (\(found)/\(Trick.allCases.count) found)", action: nil, keyEquivalent: "")
        tricksItem.submenu = tricks
        menu.addItem(tricksItem)
        menu.addItem(.separator())
        add("Use a picture…", #selector(pickImage))
        if ImageSprite.active { add("Back to the drawn dino", #selector(useDrawn)) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func fire() { brain.breatheFire() }
    @objc private func zoom() { brain.zoomies() }
    @objc private func toggleSleep() { if brain.state == .sleeping { brain.wake() } else { brain.sleep() } }
    @objc private func resetTricks() { brain.resetTricks() }
    @objc private func noop() {}
    @objc private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        panel.message = "Pick a picture of your pet. The background is removed automatically."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ImageSprite.load(url: url) {
            UserDefaults.standard.set(url.path, forKey: "spriteImagePath")
            brain.say("is this me?", for: 3)
        } else {
            let alert = NSAlert()
            alert.messageText = "Couldn't use that picture"
            alert.informativeText = "No clear subject was found. Try a picture with one creature on a plain background."
            alert.runModal()
        }
    }
    @objc private func useDrawn() {
        ImageSprite.clear()
        UserDefaults.standard.removeObject(forKey: "spriteImagePath")
    }

    // MARK: Feeding (drop a file on it)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { brain.wantsFood = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { brain.wantsFood = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { brain.wantsFood = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { brain.eat(); return true }
}

final class PetWindow: NSWindow {
    init(brain: PetBrain) {
        super.init(contentRect: NSRect(origin: brain.position, size: brain.size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        contentView = PetView(brain: brain)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
