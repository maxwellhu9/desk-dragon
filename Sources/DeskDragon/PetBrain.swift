import AppKit

enum PetState {
    case idle, walking, sleeping, falling, held, zoomies, eating
}

/// Things you can do with the pet. The pet hints at the ones you haven't found yet.
enum Trick: String, CaseIterable {
    case click, doubleClick, drag, hover, feed, rightClick

    var title: String {
        switch self {
        case .click: return "Click it: fire breath"
        case .doubleClick: return "Double-click it: zoomies"
        case .drag: return "Drag it around, throw it"
        case .hover: return "Hold the cursor on it: pets"
        case .feed: return "Drop a file on it: snack"
        case .rightClick: return "Right-click it: menu"
        }
    }
    var hint: String {
        switch self {
        case .click: return "psst... click me"
        case .doubleClick: return "double-click me, I dare you"
        case .drag: return "you can pick me up, y'know"
        case .hover: return "rest your mouse on me a sec"
        case .feed: return "so hungry... drop me a file?"
        case .rightClick: return "right-click me sometime"
        }
    }
    var reaction: String {
        switch self {
        case .click: return "FIRE!!"
        case .doubleClick: return "ZOOMIES"
        case .drag: return "hey! put me down!"
        case .hover: return "hehe, that tickles"
        case .feed: return "nom nom nom"
        case .rightClick: return "ooh, options"
        }
    }
}

struct Particle {
    enum Kind { case fire, heart, star, z, dust }
    var kind: Kind
    var pos: NSPoint       // window-local coordinates
    var vel: NSPoint
    var life: TimeInterval
    var maxLife: TimeInterval
    var size: CGFloat
    var age: CGFloat { CGFloat(1 - life / maxLife) }
}

/// Owns the pet's position, velocity, and behavior. Positions are in screen coordinates
/// (AppKit: origin bottom-left) and refer to the bottom-left corner of the pet window.
final class PetBrain {
    var state: PetState = .idle
    var position: NSPoint
    var velocity = NSPoint.zero
    var facingRight = false          // the art faces left by default
    var clock: TimeInterval = 0
    var particles: [Particle] = []
    var hovering = false
    var wantsFood = false
    var bubble: (text: String, until: TimeInterval)?
    private(set) var discovered: Set<Trick> = []

    private var stateTimer: TimeInterval = 0
    private var blinkTimer: TimeInterval = 2
    private var blinkPhase: TimeInterval = -1
    private var idleFor: TimeInterval = 0
    private var hoverFor: TimeInterval = 0
    private var happyFor: TimeInterval = 0
    private var heartTimer: TimeInterval = 0
    private var zTimer: TimeInterval = 0
    private var dustTimer: TimeInterval = 0
    private var hintTimer: TimeInterval = 12
    private var hintIndex = 0
    private var walkDir: CGFloat = -1
    private var grabOffset = NSPoint.zero
    private var lastMouse = NSPoint.zero
    private var throwVelocity = NSPoint.zero
    private var zoomTimer: TimeInterval = 0
    private var mouth: CGFloat = 0
    private var look = CGPoint.zero

    let size: NSSize
    private let gravity: CGFloat = 2400
    private let walkSpeed: CGFloat = 70
    private let zoomSpeed: CGFloat = 520

    init(size: NSSize, start: NSPoint) {
        self.size = size
        self.position = start
        if let saved = UserDefaults.standard.stringArray(forKey: "discoveredTricks") {
            discovered = Set(saved.compactMap(Trick.init(rawValue:)))
        }
    }

    // MARK: Environment

    var screen: NSScreen {
        let center = NSPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    var ground: CGFloat { screen.visibleFrame.minY - 4 }
    var minX: CGFloat { screen.visibleFrame.minX - DinoArt.margin - 30 }
    var maxX: CGFloat { screen.visibleFrame.maxX - size.width + DinoArt.margin + 30 }

    /// Art space faces left and sits `margin` points in from the window's left edge; flip x when facing right.
    func windowPoint(_ art: NSPoint) -> NSPoint {
        let p = facingRight ? NSPoint(x: DinoArt.canvas.width - art.x, y: art.y) : art
        return NSPoint(x: p.x + DinoArt.margin, y: p.y)
    }

    // MARK: Talking and tricks

    func say(_ text: String, for seconds: TimeInterval = 3) {
        bubble = (text, clock + seconds)
    }

    func did(_ trick: Trick) {
        let isNew = !discovered.contains(trick)
        discovered.insert(trick)
        UserDefaults.standard.set(discovered.map(\.rawValue), forKey: "discoveredTricks")
        if isNew {
            say(trick.reaction + "  (new trick!)", for: 3.5)
        } else if Double.random(in: 0..<1) < 0.5 {
            say(trick.reaction, for: 2)
        }
    }

    func resetTricks() {
        discovered = []
        UserDefaults.standard.removeObject(forKey: "discoveredTricks")
        hintTimer = 3
        say("okay, teach me again", for: 2.5)
    }

    private func maybeHint(_ dt: TimeInterval) {
        guard state == .idle || state == .walking, bubble == nil else { return }
        hintTimer -= dt
        guard hintTimer <= 0 else { return }
        let remaining = Trick.allCases.filter { !discovered.contains($0) }
        if remaining.isEmpty {
            let chatter = ["hi", "...", "nice desk", "rawr", "I'm bored", "what're you working on?", "*yawn*", "boop"]
            say(chatter.randomElement()!, for: 2.5)
            hintTimer = Double.random(in: 60...150)
        } else {
            let trick = remaining[hintIndex % remaining.count]
            hintIndex += 1
            say(trick.hint, for: 4)
            hintTimer = Double.random(in: 25...45)
        }
    }

    // MARK: Input

    func grab(atScreen p: NSPoint) {
        state = .held
        grabOffset = NSPoint(x: p.x - position.x, y: p.y - position.y)
        lastMouse = p
        throwVelocity = .zero
    }

    func drag(toScreen p: NSPoint, dt: TimeInterval) {
        guard state == .held else { return }
        let target = NSPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
        if dt > 0 {
            let v = NSPoint(x: (p.x - lastMouse.x) / dt, y: (p.y - lastMouse.y) / dt)
            throwVelocity = NSPoint(x: throwVelocity.x * 0.6 + v.x * 0.4, y: throwVelocity.y * 0.6 + v.y * 0.4)
        }
        lastMouse = p
        position = target
    }

    func release() {
        guard state == .held else { return }
        velocity = NSPoint(x: throwVelocity.x.clamped(-1500, 1500), y: throwVelocity.y.clamped(-500, 1500))
        state = .falling
        did(.drag)
    }

    func breatheFire() {
        if state == .sleeping { wake(); say("huh? wha?", for: 2); return }
        guard state != .held else { return }
        mouth = 1
        let origin = windowPoint(Art.snout)
        let dir: CGFloat = facingRight ? 1 : -1
        for _ in 0..<24 {
            let life = Double.random(in: 0.4...0.8)
            particles.append(Particle(
                kind: .fire, pos: origin,
                vel: NSPoint(x: dir * CGFloat.random(in: 150...300), y: CGFloat.random(in: -50...80)),
                life: life, maxLife: life, size: CGFloat.random(in: 7...14)))
        }
        did(.click)
    }

    func zoomies() {
        if state == .sleeping { wake() }
        guard state == .idle || state == .walking || state == .falling else { return }
        state = .zoomies
        zoomTimer = Double.random(in: 3...5)
        walkDir = position.x < (minX + maxX) / 2 ? 1 : -1
        facingRight = walkDir > 0
        did(.doubleClick)
    }

    func eat() {
        wantsFood = false
        if state == .sleeping { wake() }
        state = .eating
        stateTimer = 1.4
        velocity = .zero
        did(.feed)
    }

    func sleep() {
        state = .sleeping
        position.y = max(position.y, ground)
        bubble = nil
    }

    func wake() {
        state = .idle
        idleFor = 0
        stateTimer = 1
    }

    // MARK: Simulation

    func update(dt: TimeInterval) {
        clock += dt
        updateBlink(dt)
        updateLook()
        updateParticles(dt)
        maybeHint(dt)
        if let b = bubble, clock > b.until { bubble = nil }
        mouth = max(0, mouth - CGFloat(dt) * 3)
        happyFor = max(0, happyFor - dt)

        // Petting: hover on the body for a moment.
        if hovering && (state == .idle || state == .walking) {
            hoverFor += dt
            if hoverFor > 0.7 {
                if state == .walking { state = .idle; stateTimer = 1 }
                if happyFor == 0 { did(.hover) }
                happyFor = 0.6
                idleFor = 0
                heartTimer -= dt
                if heartTimer <= 0 {
                    heartTimer = 0.4
                    spawnLove()
                }
            }
        } else {
            hoverFor = 0
        }

        switch state {
        case .held:
            break

        case .falling:
            velocity.y -= gravity * CGFloat(dt)
            position.x += velocity.x * CGFloat(dt)
            position.y += velocity.y * CGFloat(dt)
            if position.x < minX { position.x = minX; velocity.x = -velocity.x * 0.5 }
            if position.x > maxX { position.x = maxX; velocity.x = -velocity.x * 0.5 }
            if position.y <= ground {
                position.y = ground
                if velocity.y < -700 {
                    velocity.y = -velocity.y * 0.35
                    velocity.x *= 0.7
                    puffDust(count: 6)
                } else {
                    velocity = .zero
                    state = .idle
                    idleFor = 0
                    stateTimer = Double.random(in: 0.5...2)
                }
            }

        case .idle:
            idleFor += dt
            stateTimer -= dt
            if idleFor > 90 { sleep(); return }
            if stateTimer <= 0 {
                let roll = Double.random(in: 0..<1)
                if roll < 0.5 {
                    state = .walking
                    walkDir = Bool.random() ? 1 : -1
                    if position.x < minX + 120 { walkDir = 1 }
                    if position.x > maxX - 120 { walkDir = -1 }
                    facingRight = walkDir > 0
                    stateTimer = Double.random(in: 1...4)
                } else if roll < 0.54 {
                    zoomies()
                } else {
                    stateTimer = Double.random(in: 1...4)
                }
            }

        case .walking:
            idleFor = 0
            stateTimer -= dt
            position.x += walkDir * walkSpeed * CGFloat(dt)
            if position.x <= minX { position.x = minX; walkDir = 1; facingRight = true }
            if position.x >= maxX { position.x = maxX; walkDir = -1; facingRight = false }
            if position.y > ground + 1 { state = .falling }
            if stateTimer <= 0 {
                state = .idle
                stateTimer = Double.random(in: 1...5)
            }

        case .zoomies:
            idleFor = 0
            zoomTimer -= dt
            if position.y > ground + 1 { position.y = max(ground, position.y - 900 * CGFloat(dt)) }
            position.x += walkDir * zoomSpeed * CGFloat(dt)
            if position.x <= minX { position.x = minX; walkDir = 1; facingRight = true; puffDust(count: 8) }
            if position.x >= maxX { position.x = maxX; walkDir = -1; facingRight = false; puffDust(count: 8) }
            dustTimer -= dt
            if dustTimer <= 0 { dustTimer = 0.07; puffDust(count: 1) }
            if zoomTimer <= 0 {
                state = .idle
                stateTimer = Double.random(in: 2...4)
                happyFor = 1.5
                say(["*pant pant*", "whew", "again!"].randomElement()!, for: 2)
            }

        case .eating:
            stateTimer -= dt
            if stateTimer <= 0 {
                state = .idle
                stateTimer = 2
                happyFor = 2.5
                for _ in 0..<3 { spawnLove() }
            }

        case .sleeping:
            zTimer -= dt
            if zTimer <= 0 {
                zTimer = 1.3
                let p = windowPoint(Art.headTop)
                particles.append(Particle(kind: .z, pos: NSPoint(x: p.x + (facingRight ? -20 : 20), y: p.y - 30),
                                          vel: NSPoint(x: facingRight ? -14 : 14, y: 26), life: 2.2, maxLife: 2.2, size: 14))
            }
        }
    }

    private func updateBlink(_ dt: TimeInterval) {
        if blinkPhase >= 0 {
            blinkPhase += dt
            if blinkPhase > 0.22 { blinkPhase = -1 }
        } else {
            blinkTimer -= dt
            if blinkTimer <= 0 {
                blinkPhase = 0
                blinkTimer = Double.random(in: 1.5...5)
            }
        }
    }

    private var blinkAmount: CGFloat {
        guard blinkPhase >= 0 else { return 0 }
        let x = CGFloat(blinkPhase / 0.22)
        return x < 0.5 ? x * 2 : (1 - x) * 2
    }

    private func updateLook() {
        guard state != .sleeping else { look = .zero; return }
        let m = NSEvent.mouseLocation
        let head = windowPoint(Art.headCenter)
        let hx = position.x + head.x, hy = position.y + head.y
        var dx = (m.x - hx) / 260, dy = (m.y - hy) / 260
        dx = dx.clamped(-1, 1); dy = dy.clamped(-1, 1)
        if facingRight { dx = -dx }
        look.x += (dx - look.x) * 0.25
        look.y += (dy - look.y) * 0.25
        if state == .idle, abs(m.x - hx) > 60, abs(m.x - hx) < 360, abs(m.y - hy) < 360 {
            facingRight = m.x > hx
        }
    }

    private func spawnLove() {
        let p = windowPoint(Art.headTop)
        let star = Double.random(in: 0..<1) < 0.35
        particles.append(Particle(
            kind: star ? .star : .heart,
            pos: NSPoint(x: p.x + CGFloat.random(in: -40...40), y: p.y - 30),
            vel: NSPoint(x: CGFloat.random(in: -12...12), y: CGFloat.random(in: 40...65)),
            life: 1.4, maxLife: 1.4, size: CGFloat.random(in: 10...15)))
    }

    private func puffDust(count: Int) {
        let behind: CGFloat = DinoArt.margin + (facingRight ? 60 : DinoArt.canvas.width - 60)
        for _ in 0..<count {
            let life = Double.random(in: 0.5...0.9)
            particles.append(Particle(
                kind: .dust, pos: NSPoint(x: behind + CGFloat.random(in: -10...10), y: CGFloat.random(in: 6...20)),
                vel: NSPoint(x: (facingRight ? -1 : 1) * CGFloat.random(in: 20...60), y: CGFloat.random(in: 10...40)),
                life: life, maxLife: life, size: CGFloat.random(in: 8...16)))
        }
    }

    private func updateParticles(_ dt: TimeInterval) {
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].pos.x += particles[i].vel.x * CGFloat(dt)
            particles[i].pos.y += particles[i].vel.y * CGFloat(dt)
            switch particles[i].kind {
            case .fire:
                particles[i].vel.y += 90 * CGFloat(dt)
                particles[i].vel.x *= 0.97
            case .dust:
                particles[i].vel.x *= 0.96
            default: break
            }
        }
        particles.removeAll { $0.life <= 0 }
    }

    // MARK: Presentation

    var pose: Pose {
        var p = Pose()
        p.t = clock
        p.blink = blinkAmount
        p.look = look
        p.breath = CGFloat(sin(clock * 2.2))
        p.tailSway = CGFloat(sin(clock * 1.7)) * 8
        p.armSwing = CGFloat(sin(clock * 1.3)) * 3
        p.mouthOpen = mouth

        switch state {
        case .held:
            p.mood = .surprised
            p.legLift = (8, 8)
            p.armSwing = 25 + CGFloat(sin(clock * 16)) * 10
        case .falling:
            p.mood = .surprised
            p.legLift = (8, 8)
            p.armSwing = 30
        case .zoomies:
            let phase = clock * 22
            p.bob = abs(CGFloat(sin(phase))) * 6
            p.legLift = (max(0, CGFloat(sin(phase))) * 12, max(0, CGFloat(sin(phase + .pi))) * 12)
            p.lean = 14
            p.armSwing = 20 + CGFloat(sin(phase)) * 15
            p.tailSway = CGFloat(sin(phase)) * 16
            p.mood = .happy
        case .walking:
            let phase = clock * 9
            p.bob = abs(CGFloat(sin(phase))) * 4
            p.legLift = (max(0, CGFloat(sin(phase))) * 8, max(0, CGFloat(sin(phase + .pi))) * 8)
            p.lean = 3 + CGFloat(sin(phase)) * 2
            p.armSwing = CGFloat(sin(phase)) * 10
        case .sleeping:
            p.mood = .sleepy
            p.breath = CGFloat(sin(clock * 1.2))
            p.squash = 0.96
        case .eating:
            p.mood = .eating
            p.mouthOpen = 0.5 + 0.5 * CGFloat(sin(clock * 16))
            p.bob = abs(CGFloat(sin(clock * 16))) * 2
        case .idle:
            break
        }
        if wantsFood && state != .held { p.mouthOpen = 1; p.mood = .surprised }
        if happyFor > 0 && state == .idle { p.mood = .happy }
        return p
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}
