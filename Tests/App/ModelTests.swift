import Foundation

@main struct ModelTests {
  @MainActor static func main() throws {
    let suite = "DeviceEQ.Tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    assert(preferences.showMenuBar && preferences.keepRunning && !preferences.showDockInBackground)
    assert(!preferences.guideCompleted)
    preferences.guideCompleted = true
    preferences.showMenuBar = false
    preferences.showDockInBackground = true
    preferences.keepRunning = false
    let reloadedPreferences = AppPreferences(defaults: defaults)
    assert(reloadedPreferences.guideCompleted, "Completed or skipped setup must stay dismissed across launches")
    assert(!reloadedPreferences.showMenuBar && !reloadedPreferences.keepRunning && reloadedPreferences.showDockInBackground, "Settings must persist independently of device profiles")
    let cache = EQDisplayCache()
    var displayProfile = DeviceProfile(uid: "display-test", deviceName: "Display test")
    displayProfile.bands = (0..<64).map { Band(frequency: 20 * pow(900, Double($0) / 63), gain: Double($0 % 5) - 2) }
    let coldStart = Date()
    let initialHeadroom = cache.effectivePreamp(displayProfile, rate: 48000)
    let initialResponse = cache.response(displayProfile, rate: 48000, channel: 0)
    let coldMs = Date().timeIntervalSince(coldStart) * 1000
    let warmStart = Date()
    for _ in 0..<100 {
      assert(cache.effectivePreamp(displayProfile, rate: 48000) == initialHeadroom)
      assert(cache.response(displayProfile, rate: 48000, channel: 0).count == initialResponse.count)
    }
    let warmMs = Date().timeIntervalSince(warmStart) * 1000
    assert(cache.headroomCalculations == 1 && cache.responseCalculations == 1, "Repeated UI updates must reuse response/headroom calculations")
    var expectedConfig = configFor(displayProfile, rate: 48000)
    assert(initialHeadroom == DEQEffectivePreampDB(&expectedConfig))
    for point in initialResponse { assert(point.db == DEQResponseDB(&expectedConfig, point.frequency, 0)) }
    displayProfile.preamp = -20
    _ = cache.effectivePreamp(displayProfile, rate: 48000)
    _ = cache.response(displayProfile, rate: 48000, channel: 0)
    assert(cache.headroomCalculations == 2 && cache.responseCalculations == 1)
    displayProfile.bands[0].gain = 8
    _ = cache.effectivePreamp(displayProfile, rate: 48000)
    _ = cache.response(displayProfile, rate: 48000, channel: 0)
    _ = cache.response(displayProfile, rate: 44100, channel: 0)
    _ = cache.response(displayProfile, rate: 44100, channel: 1)
    assert(cache.headroomCalculations == 3 && cache.responseCalculations == 4, "EQ edits, sample-rate and channel changes must invalidate the appropriate cache")
    print(String(format: "64-band display: cold %.2f ms; 100 cached reads %.2f ms. Cached values match DSP exactly.", coldMs, warmMs))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    let uid = "test-speaker"
    store.devices = [OutputDevice(id: 1, uid: uid, name: "Test speaker", channels: 2,
      sampleRate: 48000, isDefault: true, isVirtual: false, managed: false)]
    store.selectedUID = uid
    store.library.profiles[uid] = DeviceProfile(uid: uid, deviceName: "Test speaker")
    store.library.profiles[uid]?.bypass = true
    store.toggleRoute()
    assert(store.current.routeEnabled && !store.current.bypass, "Explicit enable must resume EQ")
    store.edit { $0.preamp = -6 }
    store.toggleRoute()
    store.undo()
    assert(!store.current.routeEnabled && store.current.preamp == 0, "Undo must not re-enable audio")
    store.redo()
    assert(!store.current.routeEnabled && store.current.preamp == -6, "Redo must preserve route state")
    // An in-flight native construction must obey the most recent toggle intent.
    store.creatingRoutes.insert(uid)
    store.toggleRoute()
    assert(store.current.routeEnabled)
    store.toggleRoute()
    assert(!store.current.routeEnabled)
    store.toggleRoute()
    assert(store.current.routeEnabled, "Off/on during construction must keep the final on intent")
    store.markRouteStalled(uid: uid)
    assert(store.eqState(uid: uid) == .unavailable, "A stalled route must not stay Starting forever")
    assert(!store.isEQActive, "Unavailable routes must not animate as active")
    store.stalledRoutes.remove(uid)
    store.creatingRoutes.remove(uid)
    store.toggleRoute()
    store.savePreset(name: " Example ")
    let id = store.current.presets[0].id
    store.edit { $0.preamp = -4 }
    assert(store.activePreset == nil)
    store.savePreset(name: "Example")
    assert(store.current.presets.count == 1 && store.current.presets[0].id == id)
    assert(store.activePreset?.preamp == -4, "Re-saving a name updates it without duplicates")
    store.edit { $0.preamp = -2 }
    store.loadPreset(store.current.presets[0])
    assert(store.activePreset?.id == id && store.current.preamp == -4)
    let loaded = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    loaded.devices = store.devices; loaded.selectedUID = uid
    assert(loaded.activePreset?.id == id && !loaded.current.routeEnabled)
    store.library.profiles[uid]?.bypass = true
    store.save()
    let migrated = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    migrated.devices = store.devices; migrated.selectedUID = uid
    assert(!migrated.current.bypass && migrated.activePreset?.id == id, "Legacy comparison pause must clear without changing EQ presets")
    assert(!store.canSavePreset(name: "Example"), "Unchanged profiles cannot update")
    let savedCount = store.current.presets.count
    store.savePreset(name: "Example")
    assert(store.current.presets.count == savedCount)
    store.edit { $0.autoHeadroom = false }
    assert(store.canSavePreset(name: "Example") && store.activePreset == nil, "Headroom changes must count as edits")
    store.savePreset(name: "Example")
    assert(store.activePreset?.autoHeadroom == false && !store.canSavePreset(name: "Example"))
    store.edit { $0.autoHeadroom = true }
    store.loadPreset(store.current.presets[0])
    assert(!store.current.autoHeadroom, "Loading must restore saved headroom")
    store.edit { $0.autoHeadroom = true }
    store.savePreset(name: "Example")
    // Legacy ceiling flags must not be applied after removing the feature.
    var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.current)) as! [String: Any]
    legacyJSON["limiter"] = true
    let legacyCeiling = try JSONDecoder().decode(DeviceProfile.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
    assert(configFor(legacyCeiling, rate: 48000).limiter == 0)
    assert(legacyCeiling.preamp == store.current.preamp && legacyCeiling.bands == store.current.bands)
    // Existing names match despite case and surrounding whitespace.
    store.edit { $0.preamp = -7 }
    store.savePreset(name: "  eXaMpLe  ")
    assert(store.current.presets.count == 1 && store.current.presets[0].id == id)
    assert(store.presetNamed("EXAMPLE")?.preamp == -7)
    let enabledBefore = store.current.routeEnabled
    let bandsBefore = store.current.bands
    store.deletePreset(id: id)
    assert(store.current.presets.isEmpty && store.activePreset == nil)
    assert(store.current.preamp == -7 && store.current.bands == bandsBefore && store.current.routeEnabled == enabledBefore,
      "Deleting a saved entry must not alter currently playing EQ or routing")
    store.undo()
    assert(store.activePreset?.id == id && store.current.presets.count == 1)
    store.redo()
    assert(store.current.presets.isEmpty && store.current.preamp == -7)
    let deletedReload = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    deletedReload.selectedUID = uid
    assert(deletedReload.current.presets.isEmpty, "Deletion must persist")

    var legacy = DeviceProfile(uid: "legacy", deviceName: "Legacy")
    let first = Preset(name: "Reference", bands: [], preamp: -2)
    let active = Preset(name: "Reference", bands: [], preamp: -8)
    let reserved = Preset(name: "Reference (2)", bands: [], preamp: -5)
    let mixedCase = Preset(name: " reference ", bands: [], preamp: -4)
    legacy.presets = [first, active, reserved, mixedCase]
    legacy.activePresetID = active.id; legacy.name = active.name; legacy.preamp = active.preamp
    assert(normalizePresetNames(&legacy))
    assert(legacy.presets.count == 4 && legacy.presets.map { $0.id } == [first.id, active.id, reserved.id, mixedCase.id])
    assert(Set(legacy.presets.map { presetNameKey($0.name) }).count == 4)
    assert(legacy.presets[1].name == "Reference" && legacy.presets[2].name == "Reference (2)")
    assert(legacy.activePresetID == active.id && legacy.preamp == -8)
    assert(legacy.presets.map { $0.preamp } == [-2, -8, -5, -4], "Legacy duplicate EQ settings must all be preserved")
    assert(!normalizePresetNames(&legacy), "Name cleanup must be idempotent")
    legacy.name = "Unsaved imported EQ"
    assert(!normalizePresetNames(&legacy) && legacy.name == "Unsaved imported EQ")
    store.library.profiles[legacy.uid] = legacy
    // Exercise persisted startup cleanup, including fresh collisions.
    store.library.profiles[legacy.uid]?.presets[0].name = "REFERENCE"
    store.save()
    let cleanedReload = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    let cleaned = cleanedReload.library.profiles[legacy.uid]!
    assert(cleaned.presets.count == 4 && Set(cleaned.presets.map { presetNameKey($0.name) }).count == 4)
    assert(cleaned.name == "Unsaved imported EQ" && cleaned.activePresetID == active.id)
    store.forgetDevice(uid: uid)
    assert(store.library.profiles[uid] != nil, "Connected outputs must not be forgotten")
    store.library.profiles["old-headphones"] = DeviceProfile(uid: "old-headphones", deviceName: "Old headphones")
    store.selectedUID = "old-headphones"
    store.forgetDevice(uid: "old-headphones")
    assert(store.library.profiles["old-headphones"] == nil && store.selectedUID == uid, "Forgetting a disconnected output must remove it and select a connected one")
    let forgotReload = Store(storageURL: folder.appendingPathComponent("profiles.json"), observeAudio: false)
    assert(forgotReload.library.profiles["old-headphones"] == nil, "Forgetting must persist")
    print("Model regression checks passed: enable/bypass, Undo/Redo routing isolation, rapid toggle intent, named-profile replacement, active profile and reload, forgetting disconnected outputs. No audio capture or personal profiles used.")
  }
}
