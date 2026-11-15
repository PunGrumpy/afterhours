import AfterhoursCore
import AppKit
import SwiftUI

/// Steam carries the state so it reads at 16 pt: two wisps while awake, one while paused, none when
/// the Mac can sleep.
enum Mug {
    enum Mood: CaseIterable {
        case awake, asleep, drowsy, alarmed
        case off
        case needsLookUp, needsWide, needsDot, needsBang

        init(_ state: HoldState) {
            switch state {
            case .holding: self = .awake
            case .idle: self = .asleep
            case .disabled: self = .off
            case .paused: self = .drowsy
            case .blocked: self = .alarmed
            }
        }

        var wisps: Int {
            switch self {
            case .awake, .needsLookUp, .needsWide, .needsDot: 2
            case .drowsy, .needsBang: 1
            case .asleep, .alarmed, .off: 0
            }
        }

        /// The mug's face with its smile, which only shows above menu bar sizes.
        var hasSmile: Bool {
            switch self {
            case .awake, .needsLookUp, .needsWide, .needsDot, .needsBang: true
            case .asleep, .drowsy, .alarmed, .off: false
            }
        }

        /// The body outweighs the handle, so the mug looks off to the left, and without steam it sits low.
        var opticalOffset: CGPoint {
            switch self {
            case .awake, .drowsy, .needsLookUp, .needsWide, .needsDot, .needsBang: CGPoint(x: 0.022, y: -0.015)
            case .asleep, .alarmed, .off: CGPoint(x: 0.021, y: -0.13)
            }
        }
    }

    /// At menu bar sizes the eyes grow and the smile drops out, so the face still reads.
    static func image(_ mood: Mood, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            paint(ctx, mood: mood, size: size)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Paints into a `size` square whose origin is the context's, with y down.
    private static func paint(_ ctx: CGContext, mood: Mood, size: CGFloat) {
        // Off dims the sleeping mug like an unavailable menu item; the template mask keeps the alpha.
        if mood == .off { ctx.setAlpha(0.45) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.scaleBy(x: size, y: size)
        ctx.translateBy(x: mood.opticalOffset.x, y: mood.opticalOffset.y)
        NSColor.black.setFill()
        NSColor.black.setStroke()
        draw(ctx, mood: mood, compact: size <= 20)
        ctx.endTransparencyLayer()
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
        if mood == .needsDot {
            ctx.fillEllipse(in: CGRect(x: 0.71, y: 0.17, width: 0.18, height: 0.18))
        }
        if mood == .needsBang {
            ctx.setLineWidth(compact ? 0.07 : 0.06)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 0.5, y: 0.06))
            ctx.addLine(to: CGPoint(x: 0.5, y: 0.18))
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: 0.46, y: 0.235, width: 0.08, height: 0.08))
        }

        let k: CGFloat = compact ? 1.3 : 1
        let w = 0.08 * k, h = 0.13 * k
        let eyes = [CGPoint(x: 0.31, y: 0.57), CGPoint(x: 0.51, y: 0.57)]
        punch(ctx) {
            for (i, eye) in eyes.enumerated() {
                switch mood {
                case .awake, .needsDot, .needsBang:
                    pill(ctx, center: eye, width: w, height: h)
                case .needsLookUp:
                    pill(ctx, center: CGPoint(x: eye.x, y: eye.y - 0.06), width: w, height: h)
                case .needsWide:
                    ctx.fillEllipse(in: CGRect(x: eye.x - h / 2, y: eye.y - h / 2, width: h, height: h))
                case .drowsy:
                    pill(ctx, center: CGPoint(x: eye.x, y: eye.y + h * 0.25), width: w, height: h * 0.45)
                case .asleep, .off:
                    arc(ctx, center: CGPoint(x: eye.x, y: eye.y - h * 0.1), radius: h * 0.4, lineWidth: w * 0.6)
                case .alarmed:
                    let s = h * 0.34
                    let dir: CGFloat = i == 0 ? 1 : -1
                    lines(ctx, [CGPoint(x: eye.x - s * dir, y: eye.y - s),
                                CGPoint(x: eye.x + s * dir, y: eye.y),
                                CGPoint(x: eye.x - s * dir, y: eye.y + s)], lineWidth: w * 0.6)
                }
            }
            if !compact, mood.hasSmile {
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

// MARK: - Sheet

extension Mug {
    /// A mood drawn into pixels, which is what the menu bar shows, so moods can be compared by counting.
    private struct Raster {
        let rep: NSBitmapImageRep
        var side: Int { rep.pixelsWide }

        func alpha(_ x: Int, _ y: Int) -> Int {
            guard let data = rep.bitmapData else { return 0 }
            return Int(data[y * rep.bytesPerRow + x * 4 + 3])
        }

        func isBlack(_ x: Int, _ y: Int) -> Bool {
            guard let data = rep.bitmapData else { return true }
            let row = data + y * rep.bytesPerRow + x * 4
            return row[0] == 0 && row[1] == 0 && row[2] == 0
        }

        var image: NSImage {
            let image = NSImage(size: NSSize(width: side, height: side))
            image.addRepresentation(rep)
            return image
        }

        /// Pixels whose alpha differs by more than half, over the whole square or the given columns and rows.
        func differences(from other: Raster, columns: Range<Int>? = nil, rows: Range<Int>? = nil, any: Bool = false) -> Int {
            var count = 0
            for y in rows ?? 0..<side {
                for x in columns ?? 0..<side {
                    let delta = abs(alpha(x, y) - other.alpha(x, y))
                    if any ? delta > 0 : delta * 2 > 255 { count += 1 }
                }
            }
            return count
        }

        var peakAlpha: Int {
            (0..<side * side).map { alpha($0 % side, $0 / side) }.max() ?? 0
        }

        var notBlack: Int {
            (0..<side * side).count { alpha($0 % side, $0 / side) > 0 && !isBlack($0 % side, $0 / side) }
        }
    }

    private static let sheetCell: CGFloat = 128
    private static let sheetSizes: [(size: CGFloat, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2)]
    /// Where the two wisps are, which no needs-you mood may change: they end at 0.31 once the optical offset is applied.
    private static let wispColumns: (from: Double, to: Double) = (0.2, 0.66)
    private static let wispRows: Double = 0.33

    private static func blankRep(side: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    private static func raster(_ mood: Mood, size: CGFloat, scale: Int) -> Raster? {
        let side = Int(size) * scale
        guard let rep = blankRep(side: side), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        image(mood, size: size).draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return Raster(rep: rep)
    }

    /// Paints on a canvas three squares wide and counts the pixels that land outside the middle square.
    private static func pixelsOutsideSquare(_ mood: Mood, size: CGFloat) -> Int {
        let scale = 2
        let square = Int(size) * scale
        let side = square * 3
        guard let rep = blankRep(side: side), let context = NSGraphicsContext(bitmapImageRep: rep) else { return -1 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.clear(CGRect(x: 0, y: 0, width: side, height: side))
        cg.translateBy(x: 0, y: CGFloat(side))
        cg.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        cg.translateBy(x: size, y: size)
        paint(cg, mood: mood, size: size)
        NSGraphicsContext.restoreGraphicsState()
        let canvas = Raster(rep: rep)
        let middle = square..<2 * square
        var outside = 0
        for y in 0..<side {
            for x in 0..<side where canvas.alpha(x, y) > 0 && !(middle.contains(x) && middle.contains(y)) {
                outside += 1
            }
        }
        return outside
    }

    /// Writes every mood at 16 and 32 pt, at 1x and 2x, on a light and a dark menu bar, and prints how many pixels
    /// separate each pair at 16 pt and what each mood draws outside its square, so a mood is judged by counts.
    static func snapshotSheet(to path: String) -> Never {
        let moods = Mood.allCases
        let names = moods.map { String(describing: $0) }
        let width = (names.map(\.count).max() ?? 0) + 2

        func cell(_ value: String) -> String { value.padding(toLength: 7, withPad: " ", startingAt: 0) }

        var report = ["Pixels whose alpha differs by more than half"]
        for scale in [1, 2] {
            let rasters = moods.compactMap { raster($0, size: 16, scale: scale) }
            guard rasters.count == moods.count else { fputs("Afterhours: could not draw a mood.\n", stderr); exit(1) }
            report.append("")
            report.append("16 pt, \(scale)x (\(16 * scale) px square)")
            report.append("".padding(toLength: width, withPad: " ", startingAt: 0) + names.map { cell(String($0.prefix(6))) }.joined())
            for (row, name) in names.enumerated() {
                report.append(name.padding(toLength: width, withPad: " ", startingAt: 0)
                    + rasters.indices.map { cell($0 == row ? "." : String(rasters[row].differences(from: rasters[$0]))) }.joined())
            }
        }

        report.append("")
        report.append("Per mood at 16 pt, against awake")
        report.append("mood".padding(toLength: width, withPad: " ", startingAt: 0)
            + ["outside", "peak", "notBlk", "wispDf1", "wispDf2"].map(cell).joined())
        let awake1 = raster(.awake, size: 16, scale: 1), awake2 = raster(.awake, size: 16, scale: 2)
        for (mood, name) in zip(moods, names) {
            guard let one = raster(mood, size: 16, scale: 1), let two = raster(mood, size: 16, scale: 2),
                  let awake1, let awake2 else { continue }
            let columns1 = Int(wispColumns.from * 16)..<Int((wispColumns.to * 16).rounded(.up))
            let columns2 = Int(wispColumns.from * 32)..<Int((wispColumns.to * 32).rounded(.up))
            let wisp1 = one.differences(from: awake1, columns: columns1, rows: 0..<Int((wispRows * 16).rounded(.up)), any: true)
            let wisp2 = two.differences(from: awake2, columns: columns2, rows: 0..<Int((wispRows * 32).rounded(.up)), any: true)
            report.append(name.padding(toLength: width, withPad: " ", startingAt: 0)
                + [String(pixelsOutsideSquare(mood, size: 16)), String(two.peakAlpha), String(two.notBlack),
                   String(wisp1), String(wisp2)].map(cell).joined())
        }
        print(report.joined(separator: "\n"))

        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(zip(moods, names)), id: \.1) { mood, name in
                HStack(alignment: .top, spacing: 14) {
                    Text(name).font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(width: 110, alignment: .leading)
                    ForEach([true, false], id: \.self) { light in
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(sheetSizes.indices, id: \.self) { index in
                                sheetCellView(mood, size: sheetSizes[index].size, scale: sheetSizes[index].scale,
                                              light: light, magnified: true)
                            }
                            ForEach(sheetSizes.prefix(2).indices, id: \.self) { index in
                                sheetCellView(mood, size: sheetSizes[index].size, scale: sheetSizes[index].scale,
                                              light: light, magnified: false)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.97))
        .foregroundStyle(.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fputs("Afterhours: could not render the sheet.\n", stderr)
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        exit(0)
    }

    /// One cell: the mood's real pixels, magnified without smoothing to fill the cell, or shown at their own size.
    private static func sheetCellView(_ mood: Mood, size: CGFloat, scale: Int, light: Bool, magnified: Bool) -> some View {
        let raster = raster(mood, size: size, scale: scale)
        let label = "\(Int(size)) pt \(scale)x" + (magnified ? "" : " px")
        return VStack(spacing: 2) {
            ZStack {
                Rectangle().fill(light ? Color(white: 0.92) : Color(white: 0.14))
                if let raster {
                    Image(nsImage: raster.image)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.none)
                        .foregroundStyle(light ? .black : .white)
                        .frame(width: magnified ? sheetCell : CGFloat(raster.side), height: magnified ? sheetCell : CGFloat(raster.side))
                }
            }
            .frame(width: sheetCell * (magnified ? 1 : 0.4), height: sheetCell)
            Text(label).font(.system(size: 10, design: .monospaced))
        }
    }
}
