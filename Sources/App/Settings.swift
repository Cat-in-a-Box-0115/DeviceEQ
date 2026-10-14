import AppKit
import SwiftUI
import ServiceManagement

enum AppAppearance: String, CaseIterable, Identifiable {
  case system, light, dark
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
  var nativeAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}

@MainActor final class AppPreferences: ObservableObject {
  static let shared = AppPreferences()
  private let defaults: UserDefaults
  @Published var appearance: AppAppearance {
    didSet {
      defaults.set(appearance.rawValue, forKey: "appearance")
      applyAppearance()
    }
  }
  @Published var guideCompleted: Bool { didSet { defaults.set(guideCompleted, forKey: "editorTourCompleted") } }
  @Published var showMenuBar: Bool { didSet { persist() } }
  @Published var keepRunning: Bool { didSet { persist() } }
  @Published var showDockInBackground: Bool { didSet { persist() } }
  @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
  @Published private(set) var loginError = ""
  var onChange: (() -> Void)?
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: ["showMenuBar": true, "keepRunning": true, "showDockInBackground": false])
    appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
    guideCompleted = defaults.bool(forKey: "editorTourCompleted")
    showMenuBar = defaults.bool(forKey: "showMenuBar")
    keepRunning = defaults.bool(forKey: "keepRunning")
    showDockInBackground = defaults.bool(forKey: "showDockInBackground")
    refreshLoginStatus()
  }
  func applyAppearance() { NSApp?.appearance = appearance.nativeAppearance }
  private func persist() {
    defaults.set(showMenuBar, forKey: "showMenuBar")
    defaults.set(keepRunning, forKey: "keepRunning")
    defaults.set(showDockInBackground, forKey: "showDockInBackground")
    onChange?()
  }
  var launchAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
  func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }
  func setLaunchAtLogin(_ enabled: Bool) {
    loginError = ""
    do {
      if enabled { try SMAppService.mainApp.register() }
      else { try SMAppService.mainApp.unregister() }
    } catch { loginError = error.localizedDescription }
    refreshLoginStatus()
  }
}

struct PreferencesView: View {
  var showGuide: () -> Void = { NotificationCenter.default.post(name: .showDeviceEQGuide, object: nil) }
  @ObservedObject private var preferences = AppPreferences.shared
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Theme", selection: $preferences.appearance) {
          ForEach(AppAppearance.allCases) { mode in Text(mode.label).tag(mode) }
        }.pickerStyle(.segmented).help("System follows macOS appearance")
      }
      Section("Startup") {
        Toggle("Launch at login", isOn: Binding(get: { preferences.launchAtLogin }, set: preferences.setLaunchAtLogin)).help("Start when signing in")
        Text("Starts DeviceEQ when you sign in and resumes EQ for enabled devices.")
          .font(.caption).foregroundStyle(.secondary)
        if preferences.loginStatus == .requiresApproval {
          Text("Allow DeviceEQ in macOS Login Items to finish enabling this setting.").font(.caption)
          Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if !preferences.loginError.isEmpty { Text(preferences.loginError).font(.caption).foregroundStyle(.red) }
      }
      Section("Background behavior") {
        Toggle("Keep EQ running when the window closes", isOn: $preferences.keepRunning).help("Keep processing after close")
        Toggle("Show menu-bar icon", isOn: $preferences.showMenuBar).help("Show quick controls")
        Toggle("Show Dock icon in background", isOn: $preferences.showDockInBackground).help("Keep Dock icon visible")
          .disabled(!preferences.keepRunning || !preferences.showMenuBar)
        Text(preferences.showMenuBar
          ? "Close the editor to keep EQ running. Open DeviceEQ from its menu-bar icon or Finder. Quit DeviceEQ stops all processing."
          : "The Dock icon stays available while the menu-bar icon is hidden. Click it to reopen the editor. Quit DeviceEQ stops all processing.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Section("Getting started") {
        Button("Show setup guide…") {
          showGuide()
        }
      }
      Section("About") {
        Text("DeviceEQ " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
        Text("Vibe coded by Cat-in-a-Box").font(.caption).foregroundStyle(.secondary)
      }
      Section("Privacy") {
        Button("Open audio recording permissions…") {
          NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        Text("EQ runs locally. Audio is never uploaded.").font(.caption).foregroundStyle(.secondary)
      }
    }.formStyle(.grouped).frame(width: 460).padding(12)
      .onAppear { preferences.applyAppearance(); preferences.refreshLoginStatus() }
      .onChange(of: scenePhase) { _, phase in if phase == .active { preferences.refreshLoginStatus() } }
  }
}

/// Wrap complete controls onto the next line instead of compressing their labels.
struct WrappingControls: Layout {
  var spacing: CGFloat = 10
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    layout(width: proposal.width, subviews: subviews).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = layout(width: bounds.width, subviews: subviews)
    for (view, point) in zip(subviews, result.points) {
      view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
    }
  }
  private func layout(width: CGFloat?, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
    let limit = width ?? .greatestFiniteMagnitude
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, used: CGFloat = 0
    var points = [CGPoint]()
    var sizes = [CGSize]()
    var rowStart = 0
    func centerRow() {
      for index in rowStart..<points.count { points[index].y += (rowHeight - sizes[index].height) / 2 }
      rowStart = points.count
    }
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > limit { centerRow(); x = 0; y += rowHeight + spacing; rowHeight = 0 }
      points.append(CGPoint(x: x, y: y))
      sizes.append(size)
      used = max(used, x + size.width)
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    centerRow()
    return (CGSize(width: width ?? used, height: y + rowHeight), points)
  }
}
