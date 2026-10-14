import SwiftUI
import AppKit

extension Notification.Name {
  static let showDeviceEQGuide = Notification.Name("DeviceEQ.showSetupGuide")
}
enum TourTarget: Hashable { case devices, output, graph, headroom, bands, actions, profiles }
struct TourAnchors: PreferenceKey {
  static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
  static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
extension View {
  func tourTarget(_ target: TourTarget) -> some View {
    anchorPreference(key: TourAnchors.self, value: .bounds) { [target: $0] }
  }
}
struct TourStep {
  let target: TourTarget
  let title: String
  let detail: String
  static let all: [TourStep] = [
    .init(target: .devices, title: "Your output devices", detail: "Choose the device to edit. Each output keeps its own EQ. This list does not switch your Mac’s sound output."),
    .init(target: .output, title: "EQ for this device", detail: "Turn EQ on here, then use the normal macOS Sound menu. macOS requests audio permission; processing stays local. Other disabled outputs play normally."),
    .init(target: .graph, title: "Frequency response", detail: "The curve shows your EQ’s frequency changes, not a headphone measurement. Select a band to adjust it on the graph."),
    .init(target: .headroom, title: "Gain and headroom", detail: "Auto headroom lowers gain to reduce clipping risk. Effective is the gain applied. Disable Auto headroom to set the manual preamp. DeviceEQ adds no hard clipping."),
    .init(target: .bands, title: "Parametric bands", detail: "Set filter type, channel, frequency, gain and Q. Q controls bandwidth. Only this band list scrolls; the main controls stay in place."),
    .init(target: .actions, title: "Build or import EQ", detail: "Add bands or import a parametric preset from Squiglink, AutoEq or Equalizer APO. Reset clears this EQ; Undo restores edits."),
    .init(target: .profiles, title: "Saved profiles", detail: "Save a name or choose a profile. Updates and deletion ask first. Show in Finder reveals the profile file. Settings controls startup and background behavior.")
  ]
}
struct SpotlightMask: Shape {
  let target: CGRect
  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    path.addRoundedRect(in: target, cornerSize: CGSize(width: 10, height: 10))
    return path
  }
}
struct EditorTour: View {
  @Binding var step: Int
  let target: CGRect
  let size: CGSize
  let finish: () -> Void
  private var cardWidth: CGFloat { min(340, size.width - 32) }
  private let cardHeight: CGFloat = 224
  private var cardCenter: CGPoint {
    let w = cardWidth, h = cardHeight, gap: CGFloat = 16
    let candidates = [
      CGRect(x: target.minX, y: target.maxY + gap, width: w, height: h),
      CGRect(x: target.minX, y: target.minY - gap - h, width: w, height: h),
      CGRect(x: target.maxX + gap, y: target.midY - h / 2, width: w, height: h),
      CGRect(x: target.minX - gap - w, y: target.midY - h / 2, width: w, height: h)
    ]
    let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
    if let rect = candidates.first(where: { bounds.contains($0) }) { return CGPoint(x: rect.midX, y: rect.midY) }
    // Clamp the tip above/below a wide target without covering the highlighted region where possible.
    let y = target.minY >= h + gap ? target.minY - h / 2 - gap : target.maxY + h / 2 + gap
    return CGPoint(x: min(max(target.midX, w / 2 + 12), size.width - w / 2 - 12),
      y: min(max(y, h / 2 + 12), size.height - h / 2 - 12))
  }
  var body: some View {
    let item = TourStep.all[step]
    ZStack(alignment: .topLeading) {
      SpotlightMask(target: target).fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
        .contentShape(Rectangle()).onTapGesture { }
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("\(step + 1) / \(TourStep.all.count)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Skip") { finish() }.buttonStyle(TourButtonStyle()).help("Close tour")
        }
        Text(item.title).font(.headline)
        Text(item.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack {
          Button("Back") { step -= 1 }.buttonStyle(TourButtonStyle()).disabled(step == 0)
          Spacer()
          Button(step == TourStep.all.count - 1 ? "Done" : "Next") {
            if step == TourStep.all.count - 1 { finish() } else { step += 1 }
          }.buttonStyle(TourButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
        }
      }.padding(16).frame(width: cardWidth, height: cardHeight)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .position(cardCenter)
        .accessibilityElement(children: .contain).accessibilityLabel("Editor tour")
    }.frame(width: size.width, height: size.height)
  }
}

/// Keep tour controls flat instead of inheriting the system's glass button treatment.
private struct TourButtonStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .padding(.horizontal, 12).padding(.vertical, 6)
      .foregroundStyle(prominent ? Color.white : Color.primary)
      .background(prominent ? Color.accentColor : Color.primary.opacity(0.07),
                  in: RoundedRectangle(cornerRadius: 6))
      .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.7 : 1)
  }
}
