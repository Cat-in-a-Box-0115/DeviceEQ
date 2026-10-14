import AppKit

// Original response-curve mark shared by the app and menu bar.
enum BrandMark {
  private static let activeImage = makeImage(active: true)
  private static let inactiveImage = makeImage(active: false)
  static func statusImage(active: Bool) -> NSImage { active ? activeImage : inactiveImage }
  private static func makeImage(active: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 22))
    image.lockFocus()
    draw(in: NSRect(x: 0, y: 0, width: 22, height: 22), color: .black, active: active)
    image.unlockFocus()
    image.isTemplate = true
    return image
  }
  static func draw(in rect: NSRect, color: NSColor, active: Bool = true, phase: Double = 0) {
    color.setStroke()
    let curve = NSBezierPath()
    curve.lineWidth = rect.width * 0.055
    curve.lineCapStyle = .round
    curve.lineJoinStyle = .round
    let amplitude = active ? 0.28 * (0.75 + 0.25 * sin(phase)) : 0
    for step in 0...80 {
      let t = Double(step) / 80
      // Flat endpoints, one broad boost and one broad cut, like a response plot.
      let envelope = pow(sin(.pi * t), 2)
      let y = 0.5 + amplitude * sin(2 * .pi * t) * envelope
      let point = NSPoint(x: rect.minX + rect.width * (0.12 + 0.76 * t),
        y: rect.minY + rect.height * y)
      if step == 0 { curve.move(to: point) } else { curve.line(to: point) }
    }
    curve.stroke()
  }
}
