import AppKit

/// Steam carries the state so it reads at 16 pt: two wisps while awake, one while paused, none when
/// the Mac can sleep.
enum Mug {
    enum Mood {
        case awake, asleep, drowsy, alarmed

        init(_ state: HoldState) {
            switch state {
            case .holding: self = .awake
            case .idle, .disabled: self = .asleep
            case .paused: self = .drowsy
            case .blocked: self = .alarmed
            }
        }

        var wisps: Int {
            switch self {
            case .awake: 2
            case .drowsy: 1
            case .asleep, .alarmed: 0
            }
        }
    }

    /// At menu bar sizes the eyes grow and the smile drops out, so the face still reads.
    static func image(_ mood: Mood, size: CGFloat = 16) -> NSImage {
        let compact = size <= 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.scaleBy(x: size, y: size)
            NSColor.black.setFill()
            NSColor.black.setStroke()
            draw(ctx, mood: mood, compact: compact)
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Drawing (unit square, y down)

    private static func draw(_ ctx: CGContext, mood: Mood, compact: Bool) {
        roundedRect(ctx, CGRect(x: 0.12, y: 0.36, width: 0.58, height: 0.54), radius: 0.11)
        ctx.setLineWidth(0.08)
        ctx.strokeEllipse(in: CGRect(x: 0.6, y: 0.47, width: 0.25, height: 0.27))

        for i in 0..<mood.wisps {
            let x: CGFloat = i == 0 ? 0.32 : 0.5
            let wisp = CGMutablePath()
            wisp.move(to: CGPoint(x: x, y: 0.29))
            wisp.addCurve(to: CGPoint(x: x, y: 0.05),
                          control1: CGPoint(x: x - 0.09, y: 0.21), control2: CGPoint(x: x + 0.09, y: 0.13))
            ctx.setLineWidth(compact ? 0.07 : 0.06)
            ctx.setLineCap(.round)
            ctx.addPath(wisp)
            ctx.strokePath()
        }

        let k: CGFloat = compact ? 1.3 : 1
        let w = 0.08 * k, h = 0.13 * k
        let eyes = [CGPoint(x: 0.31, y: 0.57), CGPoint(x: 0.51, y: 0.57)]
        punch(ctx) {
            for (i, eye) in eyes.enumerated() {
                switch mood {
                case .awake:
                    pill(ctx, center: eye, width: w, height: h)
                case .drowsy:
                    pill(ctx, center: CGPoint(x: eye.x, y: eye.y + h * 0.25), width: w, height: h * 0.45)
                case .asleep:
                    arc(ctx, center: CGPoint(x: eye.x, y: eye.y - h * 0.1), radius: h * 0.4, lineWidth: w * 0.6)
                case .alarmed:
                    let s = h * 0.34
                    let dir: CGFloat = i == 0 ? 1 : -1
                    lines(ctx, [CGPoint(x: eye.x - s * dir, y: eye.y - s),
                                CGPoint(x: eye.x + s * dir, y: eye.y),
                                CGPoint(x: eye.x - s * dir, y: eye.y + s)], lineWidth: w * 0.6)
                }
            }
            if !compact, mood == .awake {
                arc(ctx, center: CGPoint(x: 0.41, y: 0.66), radius: 0.05, lineWidth: 0.035)
            }
        }
    }

    // MARK: - Primitives

    private static func punch(_ ctx: CGContext, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        draw()
        ctx.restoreGState()
    }

    private static func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    private static func pill(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat) {
        roundedRect(ctx, CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                    radius: min(width, height) / 2)
    }

    private static func arc(_ ctx: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
        ctx.strokePath()
    }

    private static func lines(_ ctx: CGContext, _ points: [CGPoint], lineWidth: CGFloat) {
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addLines(between: points)
        ctx.strokePath()
    }
}
