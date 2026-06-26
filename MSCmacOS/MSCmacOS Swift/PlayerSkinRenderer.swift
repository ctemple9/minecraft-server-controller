// PlayerSkinRenderer.swift
import AppKit

enum PlayerSkinRenderer {

    // MARK: - Public API

    /// Extracts the 8×8 face + hat layer composite from a skin texture.
    static func extractFace(from skin: NSImage) -> NSImage? {
        let skinH = Int(skin.size.height)
        guard skinH >= 16, Int(skin.size.width) >= 48 else { return nil }

        let canvas = NSImage(size: NSSize(width: 8, height: 8))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        // Face at skin (8, 8, 8, 8) — nsY flipped
        let faceNSY = CGFloat(skinH - 8 - 8)  // skinH - skinY - h
        skin.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8),
                  from: NSRect(x: 8, y: faceNSY, width: 8, height: 8),
                  operation: .copy, fraction: 1)

        // Hat at skin (40, 8, 8, 8) — same nsY
        skin.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8),
                  from: NSRect(x: 40, y: faceNSY, width: 8, height: 8),
                  operation: .sourceOver, fraction: 1)

        return canvas
    }

    /// Renders a flat 2D front-view character (16×32 px) from a skin texture.
    static func renderFrontView(skin: NSImage) -> NSImage? {
        let skinW = Int(skin.size.width)
        let skinH = Int(skin.size.height)
        guard skinW >= 64, skinH >= 32 else { return nil }

        let isNewFormat = skinH >= 64
        let slim = isSlimArms(skin)
        let armPx = slim ? 3 : 4

        let canvasW = 16, canvasH = 32
        let canvas = NSImage(size: NSSize(width: CGFloat(canvasW), height: CGFloat(canvasH)))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        // Helper: draw skin region at canvas position.
        // skinY and dstY are in top-origin coords; NSImage uses bottom-origin.
        func draw(sx: Int, sy: Int, sw: Int, sh: Int, dx: Int, dy: Int) {
            let srcNSY = CGFloat(skinH - sy - sh)
            let dstNSY = CGFloat(canvasH - dy - sh)
            skin.draw(in: NSRect(x: CGFloat(dx), y: dstNSY, width: CGFloat(sw), height: CGFloat(sh)),
                      from: NSRect(x: CGFloat(sx), y: srcNSY, width: CGFloat(sw), height: CGFloat(sh)),
                      operation: .sourceOver, fraction: 1)
        }

        // Helper: draw mirrored horizontally
        func drawMirrored(sx: Int, sy: Int, sw: Int, sh: Int, dx: Int, dy: Int) {
            let srcNSY = CGFloat(skinH - sy - sh)
            let dstNSY = CGFloat(canvasH - dy - sh)
            NSGraphicsContext.saveGraphicsState()
            let xform = NSAffineTransform()
            xform.translateX(by: CGFloat(dx + sw), yBy: dstNSY)
            xform.scaleX(by: -1, yBy: 1)
            xform.concat()
            skin.draw(in: NSRect(x: 0, y: 0, width: CGFloat(sw), height: CGFloat(sh)),
                      from: NSRect(x: CGFloat(sx), y: srcNSY, width: CGFloat(sw), height: CGFloat(sh)),
                      operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Draw back-to-front

        // Right leg (character right = viewer left)
        draw(sx: 4, sy: 20, sw: 4, sh: 12, dx: 4, dy: 20)
        if isNewFormat { draw(sx: 4, sy: 36, sw: 4, sh: 12, dx: 4, dy: 20) }

        // Left leg
        if isNewFormat {
            draw(sx: 20, sy: 52, sw: 4, sh: 12, dx: 8, dy: 20)
            draw(sx: 4,  sy: 52, sw: 4, sh: 12, dx: 8, dy: 20)
        } else {
            drawMirrored(sx: 4, sy: 20, sw: 4, sh: 12, dx: 8, dy: 20)
        }

        // Body
        draw(sx: 20, sy: 20, sw: 8, sh: 12, dx: 4, dy: 8)
        if isNewFormat { draw(sx: 20, sy: 36, sw: 8, sh: 12, dx: 4, dy: 8) }

        // Right arm (character right = viewer left)
        let rDx = 4 - armPx   // classic: 0, slim: 1
        draw(sx: 44, sy: 20, sw: armPx, sh: 12, dx: rDx, dy: 8)
        if isNewFormat { draw(sx: 44, sy: 36, sw: armPx, sh: 12, dx: rDx, dy: 8) }

        // Left arm (character left = viewer right)
        let lDx = 16 - armPx  // classic: 12, slim: 13
        if isNewFormat {
            draw(sx: 36, sy: 52, sw: armPx, sh: 12, dx: lDx, dy: 8)
            draw(sx: 52, sy: 52, sw: armPx, sh: 12, dx: lDx, dy: 8)
        } else {
            drawMirrored(sx: 44, sy: 20, sw: armPx, sh: 12, dx: lDx, dy: 8)
        }

        // Head face + hat
        draw(sx: 8,  sy: 8, sw: 8, sh: 8, dx: 4, dy: 0)
        draw(sx: 40, sy: 8, sw: 8, sh: 8, dx: 4, dy: 0)

        return canvas
    }

    // MARK: - Slim arm detection

    private static func isSlimArms(_ skin: NSImage) -> Bool {
        let sz = skin.size
        guard sz.width >= 56, sz.height >= 32 else { return false }

        // Draw into fresh RGBA bitmap to reliably read alpha (avoids TIFF stripping alpha)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(sz.width), pixelsHigh: Int(sz.height),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return false }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        skin.draw(in: NSRect(origin: .zero, size: sz))
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = bitmap.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }

        // Pixel (55, 20) in skin coords (y=0 top): transparent → slim, opaque → classic
        // NSBitmapImageRep.cgImage has row 0 = top of image (consistent with skin coords)
        let stride = bitmap.bytesPerRow
        let idx = 20 * stride + 55 * 4 + 3   // alpha byte (RGBA)
        guard idx < CFDataGetLength(data) else { return false }
        return ptr[idx] < 10
    }
}
