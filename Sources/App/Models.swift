import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OutputDevice: Codable, Identifiable, Equatable {
  var id: UInt32
  var uid: String
  var name: String
  var channels: Int
  var sampleRate: Double
  var isDefault: Bool
  var isVirtual: Bool
  var managed: Bool
}
struct Band: Codable, Identifiable, Equatable {
  var id = UUID()
  var type = "peak"
  var frequency = 1000.0
  var gain = 0.0
  var q = 0.707
  var enabled = true
  var channel = "both"
  enum CodingKeys: String, CodingKey { case id, type, frequency, gain, q, enabled, channel }
  init(
    type: String = "peak", frequency: Double = 1000, gain: Double = 0, q: Double = 0.707,
    enabled: Bool = true, channel: String = "both"
  ) {
    self.type = type
    self.frequency = frequency
    self.gain = gain
    self.q = q
    self.enabled = enabled
    self.channel = channel
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    type = try c.decode(String.self, forKey: .type)
    frequency = try c.decode(Double.self, forKey: .frequency)
    gain = try c.decode(Double.self, forKey: .gain)
    q = try c.decode(Double.self, forKey: .q)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "both"
  }
}
struct Preset: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var bands: [Band]
  var preamp: Double
  var autoHeadroom: Bool?
  var metadata: [String: String]?
  var curves: CorrectionCurves?
  var sourceCurves: [String: JSONValue]?
}
func presetNameKey(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines)
    .precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
}

/// Retain every legacy preset, giving collisions distinct names. Keep the active name first.
@discardableResult func normalizePresetNames(_ profile: inout DeviceProfile) -> Bool {
  let before = profile
  let activeID = profile.activePresetID ?? profile.presets.first(where: {
    $0.name == profile.name && $0.bands == profile.bands && $0.preamp == profile.preamp
  })?.id
  let reserved = Set(profile.presets.map { presetNameKey($0.name) })
  var used = Set<String>()
  let indices = profile.presets.indices.sorted {
    (profile.presets[$0].id == activeID ? 0 : 1, $0) < (profile.presets[$1].id == activeID ? 0 : 1, $1)
  }
  for index in indices {
    let original = profile.presets[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = original.isEmpty ? "Untitled profile" : original
    var name = base
    if used.contains(presetNameKey(name)) {
      var suffix = 2
      repeat { name = "\(base) (\(suffix))"; suffix += 1 }
      while used.contains(presetNameKey(name)) || reserved.contains(presetNameKey(name))
    }
    used.insert(presetNameKey(name))
    let previousName = profile.presets[index].name
    profile.presets[index].name = name
    if profile.presets[index].id == activeID && presetNameKey(profile.name) == presetNameKey(previousName) {
      profile.activePresetID = activeID
      profile.name = name
    }
  }
  return profile != before
}

struct DeviceProfile: Codable, Equatable {
  var uid: String
  var deviceName: String
  var name = "Manual"
  var bands = [Band]()
  var preamp = 0.0
  var autoHeadroom = true
  var bypass = false
  var routeEnabled = false
  var presets = [Preset]()
  var activePresetID: UUID?
  var metadata = [String: String]()
  var curves: CorrectionCurves?
  var sourceCurves: [String: JSONValue]?
}
struct Library: Codable {
  var version = 1
  var profiles = [String: DeviceProfile]()
}
struct CorrectionCurves: Codable, Equatable {
  var frequency: [Double]
  var measurement: [Double]
  var target: [Double]
  var desiredCorrection: [Double]
  var correction: [Double]
  var predicted: [Double]
}
indirect enum JSONValue: Codable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
  init(from d: Decoder) throws {
    let c = try d.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  func encode(to e: Encoder) throws {
    var c = e.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  var text: String {
    switch self {
    case .string(let s): return s
    default: return String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }
  }
}
func consume(_ p: UnsafeMutablePointer<CChar>?) -> String {
  guard let p else { return "" }
  defer { DEQFreeString(p) }
  return String(cString: p)
}
func configFor(_ p: DeviceProfile, rate: Double) -> DEQConfig {
  var c = DEQConfig()
  c.sampleRate = rate
  c.bandCount = Int32(min(64, p.bands.count))
  c.preampDB = p.preamp
  c.autoHeadroom = p.autoHeadroom ? 1 : 0
  c.limiter = 0 // Legacy ceiling flags are ignored; DeviceEQ never hard clips PCM.
  c.bypass = p.bypass ? 1 : 0
  let types = ["peak": 0, "lowShelf": 1, "highShelf": 2, "highPass": 3, "lowPass": 4, "notch": 5]
  withUnsafeMutableBytes(of: &c.bands) { raw in
    let b = raw.bindMemory(to: DEQBand.self)
    for (i, v) in p.bands.prefix(64).enumerated() {
      b[i] = DEQBand(
        type: Int32(types[v.type] ?? 0),
        channel: v.channel == "left" ? 1 : v.channel == "right" ? 2 : 0, enabled: v.enabled ? 1 : 0,
        frequency: v.frequency, gainDB: v.gain, q: v.q)
    }
  }
  return c
}
@MainActor final class Store: ObservableObject {
  @Published var devices = [OutputDevice]()
  @Published var library = Library()
  @Published var selectedUID = ""
  @Published var selectedBand: UUID?
  @Published var operationError: String?
  @Published var message = "Choose a device and turn on EQ. Its saved profile applies whenever you listen on that device."
  @Published var stats = [String: [String: Double]]()
  @Published var activeOutputUID = ""
  var routes = [String: OpaquePointer]()
  var history = [String: [DeviceProfile]]()
  var redoHistory = [String: [DeviceProfile]]()
  var timer: Timer?
  var refreshInFlight = false
  var sleeping = false
  var pendingUpdates = Set<String>()
  var resumeSelectionUID: String?
  var readyForAudio = false
  var creatingRoutes = Set<String>()
  @Published var stalledRoutes = Set<String>()
  var failedRouteState = [String: String]()
  func deviceState(_ device: OutputDevice) -> String { "\(device.channels):\(device.sampleRate)" }
  let routeCreationQueue = DispatchQueue(label: "DeviceEQ.route-construction")
  let displayCache = EQDisplayCache()
  let storage: URL
  init(storageURL: URL? = nil, observeAudio: Bool = true) {
    if let flag = CommandLine.arguments.firstIndex(of: "--verify-physical") {
      let args = Array(CommandLine.arguments.dropFirst(flag + 1))
      if args.count == 2 {
        _ = DEQCleanupStaleRoutes()
        let obj: [String: Any] = ["deviceUID": args[1],
          "toneHelperPath": Bundle.main.resourceURL!.appendingPathComponent("route-tone").path]
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let text = String(data: data, encoding: .utf8) {
          let result = text.withCString { consume(DEQPhysicalRoutingVerify($0)) }
          try? Data(result.utf8).write(to: URL(fileURLWithPath: args[0]), options: .atomic)
        }
      }
      exit(0)
    }
    if let flag = CommandLine.arguments.firstIndex(of: "--verify-isolation") {
      let args = Array(CommandLine.arguments.dropFirst(flag + 1))
      if args.count == 3 {
        let obj: [String: Any] = [
          "deviceUIDs": Array(args.dropFirst()),
          "toneHelperPath": Bundle.main.resourceURL!.appendingPathComponent("route-tone").path,
        ]
        _ = DEQCleanupStaleRoutes()
        if let data = try? JSONSerialization.data(withJSONObject: obj),
          let text = String(data: data, encoding: .utf8)
        {
          let result = text.withCString { consume(DEQRoutingVerify($0)) }
          try? Data(result.utf8).write(to: URL(fileURLWithPath: args[0]), options: .atomic)
        }
      }
      exit(0)
    }
    if let flag = CommandLine.arguments.firstIndex(of: "--verify-routing") {
      verifyRouting(Array(CommandLine.arguments.dropFirst(flag + 1)))
      exit(0)
    }
    storage = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DeviceEQ/profiles.json")
    if let data = try? Data(contentsOf: storage),
      let value = try? JSONDecoder().decode(Library.self, from: data)
    {
      library = value
    }
    // The comparison control was removed. Resume legacy paused profiles on load.
    var resumedLegacyProfile = false
    for uid in library.profiles.keys where library.profiles[uid]?.bypass == true {
      library.profiles[uid]?.bypass = false
      resumedLegacyProfile = true
    }
    if normalizeLibraryPresetNames() { resumedLegacyProfile = true }
    if resumedLegacyProfile { save() }
    guard observeAudio else { sleeping = true; return }
    routeCreationQueue.async { _ = DEQCleanupStaleRoutes() }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.rememberSelection()
        self?.sleeping = true
        self?.stopAll()
      }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.sleeping = false
        self?.refresh()
      }
    }
  }
  var physical: [OutputDevice] { devices.filter { !$0.isVirtual && !$0.managed } }
  var current: DeviceProfile {
    library.profiles[selectedUID]
      ?? DeviceProfile(
        uid: selectedUID,
        deviceName: physical.first { $0.uid == selectedUID }?.name ?? "Disconnected output")
  }
  var activePreset: Preset? {
    current.presets.first {
      (current.activePresetID == nil || current.activePresetID == $0.id) && $0.name == current.name && $0.bands == current.bands && $0.preamp == current.preamp && ($0.autoHeadroom ?? true) == current.autoHeadroom
        && ($0.metadata ?? [:]) == current.metadata && $0.curves == current.curves
        && $0.sourceCurves == current.sourceCurves
    }
  }
  var profileLabel: String { activePreset?.name ?? "Custom EQ · unsaved" }
  var rate: Double { physical.first { $0.uid == selectedUID }?.sampleRate ?? 48000 }
  func refresh() {
    guard !sleeping, !refreshInFlight else { return }
    refreshInFlight = true
    // Handles stay alive until their queued snapshot completes; all HAL teardown shares this queue.
    let capturedRoutes = routes.mapValues { UInt(bitPattern: $0) }
    routeCreationQueue.async { [weak self] in
      let deviceText = consume(DEQDevicesJSON())
      let defaultUID = consume(DEQDefaultOutputUID())
      var routeTexts = [String: String]()
      for (uid, address) in capturedRoutes {
        routeTexts[uid] = consume(DEQRouteStatsJSON(OpaquePointer(bitPattern: address)!))
      }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshInFlight = false
        guard !self.sleeping, let data = deviceText.data(using: .utf8),
          let list = try? JSONDecoder().decode([OutputDevice].self, from: data) else { return }
        let connectedUIDs = Set(list.map(\.uid))
        self.failedRouteState = self.failedRouteState.filter { connectedUIDs.contains($0.key) }
        if self.devices != list { self.devices = list }
        if self.selectedUID.isEmpty { self.selectedUID = self.physical.first?.uid ?? "" }
        for d in self.physical where self.library.profiles[d.uid] == nil {
          self.library.profiles[d.uid] = DeviceProfile(uid: d.uid, deviceName: d.name)
        }
        if self.activeOutputUID != defaultUID { self.activeOutputUID = defaultUID }
        for (uid, text) in routeTexts where self.routes[uid].map({ UInt(bitPattern: $0) }) == capturedRoutes[uid] {
          if let data = text.data(using: .utf8),
            let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.stats[uid] = values.compactMapValues { ($0 as? NSNumber)?.doubleValue }
            if (self.stats[uid]?["invalid"] ?? 0) > 0
              || !self.physical.contains(where: { $0.uid == uid })
              || abs((self.stats[uid]?["sampleRate"] ?? 0)
                - (self.physical.first { $0.uid == uid }?.sampleRate ?? 0)) > 1 {
              if let route = self.routes.removeValue(forKey: uid) { self.destroyRoute(route) }
              self.stats.removeValue(forKey: uid)
              self.message = "Output changed or disconnected; its EQ route was stopped."
            }
          }
        }
        for d in self.physical where self.readyForAudio
          && self.library.profiles[d.uid]?.routeEnabled == true && self.routes[d.uid] == nil
          && self.failedRouteState[d.uid] != self.deviceState(d) { self.start(uid: d.uid) }
        for uid in self.pendingUpdates { self.apply(uid: uid) }
      }
    }
  }
  func destroyRoute(_ route: OpaquePointer) {
    let address = UInt(bitPattern: route)
    routeCreationQueue.async { DEQRouteDestroy(OpaquePointer(bitPattern: address)!) }
  }
  func save() {
    do {
      try FileManager.default.createDirectory(
        at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(library).write(to: storage, options: .atomic)
    } catch { message = "Could not save profiles: \(error.localizedDescription)"; operationError = message }
  }
  func edit(_ mutate: (inout DeviceProfile) -> Void) {
    guard !selectedUID.isEmpty else { return }
    let before = current
    var p = before
    mutate(&p)
    guard p != before else { return }
    if p.bands != before.bands, var curves = p.curves {
      var c = configFor(p, rate: rate)
      curves.correction = curves.frequency.map { DEQResponseDB(&c, $0, 0) }
      curves.predicted = zip(curves.measurement, curves.correction).map(+)
      p.curves = curves
      p.metadata["editedAfterFit"] = "true"
    }
    guard validate(p, rate: rate) else {
      message =
        "Rejected invalid EQ: use 1 Hz to below Nyquist, Q 0.05–100, gain ±48 dB, and at most 64 bands."
      return
    }
    history[selectedUID, default: []].append(before)
    if history[selectedUID]!.count > 100 { history[selectedUID]!.removeFirst() }
    redoHistory[selectedUID] = []
    library.profiles[selectedUID] = p
    apply(uid: selectedUID)
    save()
  }
  func apply(uid: String) {
    guard let p = library.profiles[uid], let r = routes[uid] else { return }
    var c = configFor(p, rate: physical.first { $0.uid == uid }?.sampleRate ?? 48000)
    if DEQRouteUpdate(r, &c) == 0 {
      pendingUpdates.insert(uid)
      message = "EQ change queued; waiting for the audio callback."
    } else {
      pendingUpdates.remove(uid)
    }
  }
  func start(uid: String) {
    guard readyForAudio, !creatingRoutes.contains(uid), let profile = library.profiles[uid],
      let device = physical.first(where: { $0.uid == uid })
    else { return }
    creatingRoutes.insert(uid)
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      self?.markRouteStalled(uid: uid)
    }
    message = "Turning on EQ for \(device.name)…"
    let configuration = configFor(profile, rate: device.sampleRate)
    let cleanupQueue = routeCreationQueue
    routeCreationQueue.async { [weak self] in
      var config = configuration
      let route = uid.withCString { DEQRouteCreatePhysical($0, &config) }
      let error = route == nil ? consume(DEQRouteError()) : ""
      Task { @MainActor [weak self] in
        guard let self else {
          if let route {
            let address = UInt(bitPattern: route)
            cleanupQueue.async { DEQRouteDestroy(OpaquePointer(bitPattern: address)!) }
          }
          return
        }
        self.creatingRoutes.remove(uid)
        self.stalledRoutes.remove(uid)
        if let route {
          guard self.readyForAudio, !self.sleeping, self.library.profiles[uid]?.routeEnabled == true,
            self.physical.contains(where: { $0.uid == uid })
          else {
            self.destroyRoute(route)
            return
          }
          self.failedRouteState.removeValue(forKey: uid)
          self.routes[uid] = route
          self.apply(uid: uid)
          self.message = self.library.profiles[uid]?.bypass == true
            ? "EQ is paused for \(device.name) while comparing original sound."
            : "EQ is on for \(device.name). Native volume controls remain available."
        } else {
          // Preserve the preference across temporary Bluetooth/telephone formats.
          // Retry only after device format/reconnection changes, or explicit off/on.
          self.failedRouteState[uid] = self.deviceState(device)
          self.message = error
        }
      }
    }
  }
  func toggleRoute() {
    let uid = selectedUID
    let enabled = !current.routeEnabled
    failedRouteState.removeValue(forKey: uid)
    library.profiles[uid]?.routeEnabled = enabled
    // An explicit Turn EQ on resumes processing, even after an earlier comparison.
    if enabled { library.profiles[uid]?.bypass = false }
    if creatingRoutes.contains(uid) {
      message = enabled ? "Turning on EQ; waiting for this device's route." : "EQ cancelled; finishing audio cleanup."
    } else if enabled {
      start(uid: uid)
    } else {
      if let route = routes.removeValue(forKey: uid) { destroyRoute(route) }
      stats.removeValue(forKey: uid)
      message = "EQ is off for this device. It plays normally."
    }
    save()
    refresh()
  }
  func markRouteStalled(uid: String) {
    guard creatingRoutes.contains(uid) else { return }
    stalledRoutes.insert(uid)
    message = "macOS audio is taking too long to respond. Quit DeviceEQ and restart the Mac if EQ remains unavailable. Your profiles are saved."
  }
  func eqState(uid: String) -> EQState {
    guard physical.contains(where: { $0.uid == uid }) else { return .disconnected }
    guard library.profiles[uid]?.routeEnabled == true else { return .off }
    if stalledRoutes.contains(uid) { return .unavailable }
    if creatingRoutes.contains(uid) { return .starting }
    guard routes[uid] != nil, (stats[uid]?["invalid"] ?? 0) == 0 else { return .unavailable }
    return library.profiles[uid]?.bypass == true ? .paused : .active
  }
  var isEQActive: Bool { eqState(uid: activeOutputUID) == .active }
  var selectedStatus: String {
    switch eqState(uid: selectedUID) {
    case .active: return "EQ is on for this device."
    case .paused: return "EQ is paused — original sound is playing. Turn EQ off and on to resume processing."
    case .off: return "EQ is off — this device plays normally."
    case .starting: return "Starting EQ for this device…"
    case .unavailable: return "EQ is enabled but its audio route is unavailable."
    case .disconnected: return "This device is disconnected. Its settings remain saved."
    }
  }
  func rememberSelection() { /* Native physical selection survives route teardown. */ }
  func stopAll() {
    let oldRoutes = Array(routes.values)
    routes.removeAll()
    stats.removeAll()
    for route in oldRoutes { destroyRoute(route) }
  }
  func shutdown(completion: @escaping () -> Void) {
    readyForAudio = false
    sleeping = true
    timer?.invalidate()
    stopAll()
    finishShutdown(completion: completion)
  }
  private func finishShutdown(completion: @escaping () -> Void) {
    guard creatingRoutes.isEmpty else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.finishShutdown(completion: completion)
      }
      return
    }
    routeCreationQueue.async {
      DispatchQueue.main.async { completion() }
    }
  }
  func undo() {
    guard let p = history[selectedUID]?.popLast() else { return }
    redoHistory[selectedUID, default: []].append(current)
    restoreEQHistory(p)
  }
  func redo() {
    guard let p = redoHistory[selectedUID]?.popLast() else { return }
    history[selectedUID, default: []].append(current)
    restoreEQHistory(p)
  }
  private func restoreEQHistory(_ previous: DeviceProfile) {
    var profile = previous
    profile.routeEnabled = current.routeEnabled
    profile.bypass = current.bypass
    library.profiles[selectedUID] = profile
    apply(uid: selectedUID)
    save()
  }
  func chooseOpen(types: [String] = ["txt", "csv", "json"], completion: (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url { completion(url) }
  }
  func exportFile(name: String, data: Data) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    if panel.runModal() == .OK, let u = panel.url {
      do {
        try data.write(to: u, options: .atomic)
        message = "Saved \(u.lastPathComponent)"
      } catch { message = error.localizedDescription; operationError = message }
    }
  }
  @discardableResult func importPreset(at url: URL) throws -> Int {
    let parsed = try parseAPO(readPresetText(Data(contentsOf: url)))
    var candidate = current
    candidate.bands = parsed.bands.map {
      Band(type: $0.type, frequency: $0.frequency, gain: $0.gain, q: $0.q,
           enabled: $0.enabled, channel: $0.channel)
    }
    candidate.preamp = parsed.preamp
    candidate.name = url.deletingPathExtension().lastPathComponent
    candidate.metadata = ["source": url.lastPathComponent]
    candidate.curves = nil
    candidate.sourceCurves = nil
    guard validate(candidate, rate: rate) else {
      throw APOError(message: "This preset exceeds this device’s frequency, gain or filter limits. Nothing was changed.")
    }
    edit { $0 = candidate }
    message = "Imported \(candidate.bands.count) filters from \(url.lastPathComponent)."
    return candidate.bands.count
  }
  func importAPO() {
    chooseOpen(types: ["txt", "cfg"]) { url in
      do { try self.importPreset(at: url) }
      catch { self.message = error.localizedDescription; self.operationError = self.message }
    }
  }
  func exportAPOFile() {
    do {
      let p = current
      let v = APOPresetValue(
        bands: p.bands.map {
          APOBandValue(
            type: $0.type, frequency: $0.frequency, gain: $0.gain, q: $0.q, enabled: $0.enabled,
            channel: $0.channel)
        }, preamp: p.preamp)
      let text = try exportAPO(v)
      exportFile(name: p.name + ".txt", data: Data(text.utf8))
    } catch { message = error.localizedDescription; operationError = message }
  }
  @discardableResult func normalizeLibraryPresetNames() -> Bool {
    var changed = false
    for uid in library.profiles.keys {
      if var profile = library.profiles[uid], normalizePresetNames(&profile) {
        library.profiles[uid] = profile
        changed = true
      }
    }
    return changed
  }
  func presetNamed(_ name: String) -> Preset? {
    current.presets.first { presetNameKey($0.name) == presetNameKey(name) }
  }
  func presetMatchesCurrent(_ preset: Preset) -> Bool {
    preset.bands == current.bands && preset.preamp == current.preamp
      && (preset.autoHeadroom ?? true) == current.autoHeadroom
      && (preset.metadata ?? [:]) == current.metadata && preset.curves == current.curves
      && preset.sourceCurves == current.sourceCurves
  }
  func canSavePreset(name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !selectedUID.isEmpty else { return false }
    guard let preset = presetNamed(trimmed) else { return true }
    return trimmed != preset.name || !presetMatchesCurrent(preset)
  }
  func deletePreset(id: UUID) {
    edit {
      $0.presets.removeAll { $0.id == id }
      if $0.activePresetID == id { $0.activePresetID = nil }
    }
  }
  func showProfilesInFinder() {
    if !FileManager.default.fileExists(atPath: storage.path) { save() }
    guard FileManager.default.fileExists(atPath: storage.path) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([storage])
  }
  func savePreset(name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSavePreset(name: name) else { return }
    edit {
      let index = $0.presets.firstIndex { presetNameKey($0.name) == presetNameKey(name) }
      let id = index == nil ? UUID() : $0.presets[index!].id
      let preset = Preset(id: id, name: name, bands: $0.bands, preamp: $0.preamp,
        autoHeadroom: $0.autoHeadroom, metadata: $0.metadata, curves: $0.curves, sourceCurves: $0.sourceCurves)
      if let index { $0.presets[index] = preset } else { $0.presets.append(preset) }
      $0.activePresetID = id
      $0.name = name
    }
  }
  func loadPreset(_ p: Preset) {
    edit {
      $0.activePresetID = p.id
      $0.bands = p.bands
      $0.preamp = p.preamp
      $0.autoHeadroom = p.autoHeadroom ?? true
      $0.name = p.name
      $0.metadata = p.metadata ?? [:]
      $0.curves = p.curves
      $0.sourceCurves = p.sourceCurves
    }
  }

}

func validate(_ p: DeviceProfile, rate: Double) -> Bool {
  guard p.bands.count <= 64,
    p.bands.allSatisfy({
      ["peak", "lowShelf", "highShelf", "highPass", "lowPass", "notch"].contains($0.type)
        && ["both", "left", "right"].contains($0.channel)
    }), Set(p.bands.map { $0.id }).count == p.bands.count
  else { return false }
  var c = configFor(p, rate: rate)
  guard DEQEffectivePreampDB(&c).isFinite else { return false }
  if let v = p.curves {
    let n = v.frequency.count
    guard n > 1,
      [v.measurement, v.target, v.desiredCorrection, v.correction, v.predicted].allSatisfy({
        $0.count == n && $0.allSatisfy { $0.isFinite }
      }), v.frequency.allSatisfy({ $0.isFinite && $0 > 0 }),
      zip(v.frequency, v.frequency.dropFirst()).allSatisfy({ $0 < $1 })
    else { return false }
  }
  return true
}
