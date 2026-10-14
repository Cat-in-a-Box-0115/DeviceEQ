import AppKit
import SwiftUI
import Carbon

@MainActor final class Lifecycle: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var store: Store?
  var openEditor: (() -> Void)?
  var openPreferences: (() -> Void)?
  private var editingMonitor: Any?
  private var windowObserver: Any?
  private var shuttingDown = false
  private var startedAtLogin = false
  private let preferences = AppPreferences.shared
  private var statusItem: NSStatusItem?
  private var statusTimer: Timer?
  private var lastIconFrame: Int?
  private var iconFrames: [Int: NSImage] = [:]
  private var actions: [Int: () -> Void] = [:]
  func applicationDidFinishLaunching(_ notification: Notification) {
    preferences.applyAppearance()
    startedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
      .paramDescriptor(forKeyword: keyAEPropData)?
      .paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue == true
    preferences.onChange = { [weak self] in self?.applyPreferences() }
    windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
      DispatchQueue.main.async { self?.updateDockVisibility() }
    }
    if let url = Bundle.main.url(forResource: "DeviceEQ", withExtension: "icns"),
       let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
    // End field editing before handling an outside click, without swallowing that click.
    editingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
      guard let window = event.window,
        let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return event }
      if event.type == .keyDown {
        if event.keyCode == 53 { window.makeFirstResponder(nil); return nil }
        return event
      }
      guard let content = window.contentView else { return event }
      var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
      while let view = hit {
        if let field = view as? NSTextField, field.isEditable { return event }
        if let text = view as? NSTextView, text.isEditable { return event }
        hit = view.superview
      }
      window.makeFirstResponder(nil)
      return event
    }
  }
  func installMenu() {
    guard preferences.showMenuBar, statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    updateStatusIcon()
    statusTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateStatusIcon() }
    }
  }
  func updateStatusIcon() {
    let active = store?.isEQActive == true
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let frame = active ? (reduceMotion ? 16 : Int(ProcessInfo.processInfo.systemUptime * 8) % 16) : -1
    guard frame != lastIconFrame else { return }
    lastIconFrame = frame
    let image: NSImage
    if let cached = iconFrames[frame] { image = cached }
    else {
      image = NSImage(size: NSSize(width: 20, height: 20))
      image.lockFocus()
      BrandMark.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20), color: .black,
        active: active, phase: frame == 16 ? 0 : Double(frame) * 2 * .pi / 16)
      image.unlockFocus()
      image.isTemplate = true
      iconFrames[frame] = image
    }
    statusItem?.button?.image = image
    statusItem?.button?.toolTip = active ? "DeviceEQ — EQ on" : "DeviceEQ — EQ off"
    statusItem?.button?.setAccessibilityLabel(active ? "DeviceEQ, EQ on" : "DeviceEQ, EQ off")
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let store else { return }
    menu.removeAllItems()
    actions.removeAll()
    @discardableResult func add(_ title: String, to parent: NSMenu, action: @escaping () -> Void) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
      item.target = self
      item.tag = actions.count + 1
      actions[item.tag] = action
      parent.addItem(item)
      return item
    }
    let activeName = store.physical.first(where: { $0.uid == store.activeOutputUID })?.name ?? "No physical output selected"
    menu.addItem(NSMenuItem(title: "EQ \(store.eqState(uid: store.activeOutputUID).label.lowercased()) · \(activeName)", action: nil, keyEquivalent: ""))
    for device in store.physical {
      let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: device.name)
      add("Edit profile", to: submenu) { [weak self] in
        store.selectedUID = device.uid
        self?.openEditor?()
        NSApp.activate(ignoringOtherApps: true)
      }
      add(store.library.profiles[device.uid]?.routeEnabled == true ? "Turn EQ off" : "Turn EQ on", to: submenu) {
        store.selectedUID = device.uid
        store.toggleRoute()
      }
      for preset in store.library.profiles[device.uid]?.presets ?? [] {
        add(preset.name, to: submenu) {
          store.selectedUID = device.uid
          store.loadPreset(preset)
        }
      }
      item.submenu = submenu
      submenu.autoenablesItems = false
      menu.addItem(item)
    }
    menu.addItem(.separator())
    add("Open DeviceEQ", to: menu) { [weak self] in
      self?.openEditor?()
      NSApp.activate(ignoringOtherApps: true)
    }
    add("Setup guide…", to: menu) { [weak self] in self?.showSetupGuide() }
    add("Settings…", to: menu) { [weak self] in self?.openPreferences?() }
    add("Quit DeviceEQ", to: menu) { NSApp.terminate(nil) }
    menu.autoenablesItems = false
  }
  func showSetupGuide() {
    openEditor?()
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .showDeviceEQGuide, object: nil)
    }
  }
  func applyPreferences() {
    if preferences.showMenuBar { installMenu() }
    else {
      statusTimer?.invalidate(); statusTimer = nil
      if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
      statusItem = nil
      lastIconFrame = nil
    }
    updateDockVisibility()
  }
  func updateDockVisibility() {
    guard !shuttingDown else { return }
    let visibleWindow = NSApp.windows.contains { $0.styleMask.contains(.titled) && $0.isVisible }
    let showDock = visibleWindow || !preferences.showMenuBar || preferences.showDockInBackground
    let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
    if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
  }
  func editorAppeared(_ window: NSWindow?) {
    window?.identifier = NSUserInterfaceItemIdentifier("deviceeq.editor")
    applyPreferences()
    if startedAtLogin && preferences.keepRunning {
      startedAtLogin = false
      window?.orderOut(nil)
      updateDockVisibility()
    } else {
      NSApp.setActivationPolicy(.regular)
      window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !preferences.keepRunning
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { openEditor?() }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    return true
  }
  @objc private func runMenuAction(_ sender: NSMenuItem) { actions[sender.tag]?() }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    shuttingDown = true
    guard let store else { return .terminateNow }
    var replied = false
    let finish = {
      guard !replied else { return }
      replied = true
      sender.reply(toApplicationShouldTerminate: true)
    }
    store.shutdown(completion: finish)
    // A stuck HAL call must not prevent quitting. Process exit releases its audio clients;
    // ownership leases allow stale private routes to be cleaned on the next launch.
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish() }
    return .terminateLater
  }
}

struct EditorRoot: View {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @EnvironmentObject private var store: Store
  let lifecycle: Lifecycle
  var body: some View {
    ContentView().onAppear {
      lifecycle.store = store
      lifecycle.openPreferences = {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }
      lifecycle.openEditor = {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "deviceeq.editor" }) {
          window.makeKeyAndOrderFront(nil)
        } else {
          openWindow(id: "editor")
        }
      }
      lifecycle.installMenu()
      Task { @MainActor in
        store.readyForAudio = true
        store.refresh()
        // Finish scene creation before activating its editor window.
        await Task.yield()
        lifecycle.editorAppeared(NSApp.windows.first(where: { $0.styleMask.contains(.titled) && !$0.title.hasSuffix("Settings") }))
      }
    }
  }
}

@main struct DeviceEQApp: App {
  @NSApplicationDelegateAdaptor(Lifecycle.self) var lifecycle
  @StateObject private var store = Store()
  var body: some Scene {
    WindowGroup("DeviceEQ", id: "editor") {
      EditorRoot(lifecycle: lifecycle).environmentObject(store)
    }
    .defaultSize(width: 1040, height: 780)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appInfo) {
        Button("About DeviceEQ") {
          NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: "Vibe coded by Cat-in-a-Box")])
        }
      }
      CommandGroup(replacing: .help) {
        Button("Setup guide…") {
          lifecycle.showSetupGuide()
        }
      }
      CommandGroup(after: .appInfo) {
        Button("Open audio recording permissions") {
          NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
      }
    }
    Settings { PreferencesView(showGuide: lifecycle.showSetupGuide) }
  }
}
