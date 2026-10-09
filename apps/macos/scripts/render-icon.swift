// Renders an SVG into a macOS .iconset folder: render-icon <icon.svg> <out.iconset>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let svg = NSImage(contentsOfFile: arguments[1]) else {
  FileHandle.standardError.write(Data("usage: render-icon <icon.svg> <out.iconset>\n".utf8))
  exit(1)
}
let iconset = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = points * scale
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)
    else { exit(1) }
    // The point size tags the PNG with the right DPI, which iconutil reads to place @2x images.
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // AppKit's SVG renderer skips filters, so the grid's drop shadow is drawn here.
    let unit = CGFloat(points) / 1024
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.shadowBlurRadius = 20 * unit
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    svg.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
  }
}
