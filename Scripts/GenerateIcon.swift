import AppKit
import Foundation

@main struct IconGenerator {
  static func main() throws {
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for size in [16, 32, 64, 128, 256, 512, 1024] {
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
      let s = CGFloat(size)
      NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
      NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88),
        xRadius: s * 0.18, yRadius: s * 0.18).fill()
      BrandMark.draw(in: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88),
        color: NSColor(calibratedWhite: 0.96, alpha: 1))
      NSGraphicsContext.restoreGraphicsState()
      let names: [String]
      switch size {
      case 16: names = ["icon_16x16.png"]
      case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
      case 64: names = ["icon_32x32@2x.png"]
      case 128: names = ["icon_128x128.png"]
      case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
      case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
      default: names = ["icon_512x512@2x.png"]
      }
      let data = bitmap.representation(using: .png, properties: [:])!
      for name in names { try data.write(to: destination.appendingPathComponent(name)) }
    }
  }
}
