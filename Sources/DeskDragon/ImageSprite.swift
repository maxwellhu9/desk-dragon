import AppKit
import Vision
import CoreImage

/// Lets any picture be the pet. The main subject is lifted off its background with Vision, fitted
/// into the canvas facing left, and animated with the whole-body parts of the pose (bob, lean, squash).
enum ImageSprite {
    static private(set) var active = false
    static private var sprite: NSImage?
    static private var alpha: NSBitmapImageRep?
    static private(set) var opaqueBounds = NSRect.zero
    static var snout: NSPoint { NSPoint(x: opaqueBounds.minX + opaqueBounds.width * 0.12, y: opaqueBounds.minY + opaqueBounds.height * 0.6) }
    static var headTop: NSPoint { NSPoint(x: opaqueBounds.midX, y: opaqueBounds.maxY) }
    static var headCenter: NSPoint { NSPoint(x: opaqueBounds.midX, y: opaqueBounds.minY + opaqueBounds.height * 0.7) }

    /// The picture used when nothing else is chosen: `pet.png` next to the app bundle or in the project folder.
    static func defaultURL() -> URL? {
        var candidates: [URL] = []
        let bundle = Bundle.main.bundleURL
        candidates.append(bundle.deletingLastPathComponent().appendingPathComponent("pet.png"))
        candidates.append(bundle.appendingPathComponent("Contents/Resources/pet.png"))
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent("Projects/desk-dragon/pet.png"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() {
        active = false
        sprite = nil
        alpha = nil
    }

    @discardableResult
    static func load(url: URL) -> Bool {
        guard let src = NSImage(contentsOf: url), let cut = cutout(src) else { return false }
        let canvas = DinoArt.canvas
        let w = Int(canvas.width), h = Int(canvas.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * 2, pixelsHigh: h * 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = canvas
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        // Leave the top band for the speech bubble.
        let fit = NSRect(x: 12, y: 8, width: canvas.width - 24, height: canvas.height - 78)
        let scale = min(fit.width / cut.size.width, fit.height / cut.size.height)
        let dw = cut.size.width * scale, dh = cut.size.height * scale
        cut.draw(in: NSRect(x: fit.midX - dw / 2, y: fit.minY, width: dw, height: dh), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: canvas)
        img.addRepresentation(rep)
        sprite = img
        alpha = rep
        opaqueBounds = measure(rep)
        active = opaqueBounds.width > 10
        return active
    }

    /// Lift the largest subject out of the picture (drops small decorations like stars or clouds).
    private static func cutout(_ img: NSImage) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }

        var best: (CIImage, CGFloat)?
        for instance in result.allInstances {
            guard let buffer = try? result.generateMaskedImage(ofInstances: [instance], from: handler, croppedToInstancesExtent: true) else { continue }
            let ci = CIImage(cvPixelBuffer: buffer)
            let area = ci.extent.width * ci.extent.height
            if best == nil || area > best!.1 { best = (ci, area) }
        }
        guard let (ci, _) = best else { return nil }
        let rep = NSCIImageRep(ciImage: ci)
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }

    /// Bounding box of the non-transparent pixels, in canvas points.
    private static func measure(_ rep: NSBitmapImageRep) -> NSRect {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) where alphaAt(rep, x, y) > 20 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .zero }
        let s = CGFloat(w) / DinoArt.canvas.width
        return NSRect(x: CGFloat(minX) / s, y: CGFloat(h - 1 - maxY) / s,
                      width: CGFloat(maxX - minX) / s, height: CGFloat(maxY - minY) / s)
    }

    private static func alphaAt(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> UInt8 {
        guard let data = rep.bitmapData else { return 0 }
        return data[y * rep.bytesPerRow + x * (rep.bitsPerPixel / 8) + 3]
    }

    /// Draw in art space (facing left); the view flips it when facing right.
    static func draw(_ p: Pose) {
        guard let sprite else { return }
        NSGraphicsContext.saveGraphicsState()
        var t = AffineTransform(translationByX: DinoArt.pivot.x, byY: DinoArt.pivot.y)
        t.rotate(byDegrees: -p.lean)
        t.translate(x: -DinoArt.pivot.x, y: -DinoArt.pivot.y)
        t.translate(x: 0, y: p.bob + p.breath * 0.8)
        let sq = p.squash * (1 + p.breath * 0.006)
        t.translate(x: opaqueBounds.midX, y: opaqueBounds.minY)
        t.scale(x: 1 + (1 - sq) * 0.5, y: sq)
        t.translate(x: -opaqueBounds.midX, y: -opaqueBounds.minY)
        (t as NSAffineTransform).concat()
        NSColor(srgbRed: 0.35, green: 0.3, blue: 0.5, alpha: 0.14).setFill()
        NSBezierPath(ovalIn: NSRect(x: opaqueBounds.midX - opaqueBounds.width * 0.42, y: opaqueBounds.minY - 6,
                                    width: opaqueBounds.width * 0.84, height: 16)).fill()
        sprite.draw(in: NSRect(origin: .zero, size: DinoArt.canvas), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func hitTest(_ point: NSPoint) -> Bool {
        guard let alpha else { return false }
        let s = CGFloat(alpha.pixelsWide) / DinoArt.canvas.width
        let x = Int(point.x * s), y = alpha.pixelsHigh - 1 - Int(point.y * s)
        guard x >= 0, y >= 0, x < alpha.pixelsWide, y < alpha.pixelsHigh else { return false }
        return alphaAt(alpha, x, y) > 20
    }

    static func debugPNG() -> Data? { alpha?.representation(using: .png, properties: [:]) }
}

/// Points and drawing for whichever sprite is active.
enum Art {
    static var snout: NSPoint { ImageSprite.active ? ImageSprite.snout : DinoArt.snout }
    static var headTop: NSPoint { ImageSprite.active ? ImageSprite.headTop : DinoArt.headTop }
    static var headCenter: NSPoint { ImageSprite.active ? ImageSprite.headCenter : DinoArt.headCenter }
    static func draw(_ p: Pose) { ImageSprite.active ? ImageSprite.draw(p) : DinoArt.draw(p) }
    static func hitTest(_ point: NSPoint, pose: Pose) -> Bool {
        ImageSprite.active ? ImageSprite.hitTest(point) : DinoArt.hitTest(point, pose: pose)
    }
}
