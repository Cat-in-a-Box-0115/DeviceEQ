import AppKit
import Foundation

// Run only when explicitly requested by the developer/test command. Tone caps live
// in the standalone producer; normal app startup never produces a test signal.
@MainActor func verifyRouting(_ args: [String]) {
  guard args.count >= 2 else { return }
  let reportURL = URL(fileURLWithPath: args[0])
  let uids = Array(args.dropFirst())
  let originalDefault = consume(DEQDefaultOutputUID())
  var report = [String: Any]()
  var records = [[String: Any]]()
  var routes = [String: OpaquePointer]()
  report["before"] = consume(DEQDevicesJSON())
  report["cleanupRemoved"] = DEQCleanupStaleRoutes()
  func capture(_ physical: String, _ output: String, own: Bool = false) -> [String: Any] {
    guard
      let monitor = physical.withCString({
        own ? DEQMonitorStartOwnProcess($0, 997) : DEQMonitorStart($0, 997)
      })
    else {
      return ["error": consume(DEQRouteError())]
    }
    defer { DEQMonitorDestroy(monitor) }
    Thread.sleep(forTimeInterval: 0.15)
    let process = Process()
    process.executableURL = Bundle.main.resourceURL!.appendingPathComponent("route-tone")
    process.arguments = [output, "997", "2", "0.001"]
    do {
      try process.run()
      process.waitUntilExit()
      Thread.sleep(forTimeInterval: 0.1)
      let value = consume(DEQMonitorStatsJSON(monitor))
      var r = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] ?? [:]
      r["producerExit"] = process.terminationStatus
      return r
    } catch { return ["error": error.localizedDescription] }
  }
  var baselines = [String: [String: Any]]()
  for uid in uids { baselines[uid] = capture(uid, uid) }
  for (i, uid) in uids.enumerated() {
    var p = DeviceProfile(uid: uid, deviceName: uid)
    p.bands = [Band(frequency: 997, gain: i == 0 ? -12 : -6, q: 1)]
    p.preamp = 0
    p.autoHeadroom = false
    var c = configFor(p, rate: 48000)
    if let r = uid.withCString({ DEQRouteCreate($0, &c) }) {
      routes[uid] = r
    } else {
      records.append(["uid": uid, "error": consume(DEQRouteError())])
    }
  }
  for (i, uid) in uids.enumerated() {
    guard let route = routes[uid] else { continue }
    let endpoint = "org.deviceeq.endpoint." + uid
    let eq = capture(uid, endpoint, own: true)
    let direct = capture(uid, uid)
    let stats = consume(DEQRouteStatsJSON(route))
    var record: [String: Any] = [
      "uid": uid, "expectedGainDB": i == 0 ? -12 : -6, "baseline": baselines[uid] ?? [:], "eq": eq,
      "directWhileEQEnabled": direct, "routeStats": stats,
    ]
    if let b = baselines[uid]?["peak"] as? Double, b > 0, let e = eq["peak"] as? Double {
      record["measuredPeakGainDB"] = 20 * log10(max(e, 1e-15) / b)
    }
    if let b = baselines[uid]?["peak"] as? Double, b > 0, let d = direct["peak"] as? Double {
      record["directGainDB"] = 20 * log10(max(d, 1e-15) / b)
    }
    var p = DeviceProfile(uid: uid, deviceName: uid)
    p.bands = [Band(frequency: 997, gain: i == 0 ? -12 : -6, q: 1)]
    p.preamp = 0
    p.autoHeadroom = false
    p.bypass = true
    var c = configFor(p, rate: 48000)
    record["bypassAccepted"] = DEQRouteUpdate(route, &c)
    Thread.sleep(forTimeInterval: 0.1)
    record["bypass"] = capture(uid, endpoint, own: true)
    p.bypass = false
    p.bands = [Band(frequency: 997, gain: -18, q: 1)]
    p.preamp = 0
    c = configFor(p, rate: 48000)
    record["profileUpdateAccepted"] = DEQRouteUpdate(route, &c)
    Thread.sleep(forTimeInterval: 0.1)
    record["updated"] = capture(uid, endpoint, own: true)
    record["endpointSelectAccepted"] = DEQRouteSelect(route)
    record["selectedDefaultUID"] = consume(DEQDefaultOutputUID())
    record["restoreOriginalAccepted"] = originalDefault.withCString { DEQRestoreOutputUID($0) }
    records.append(record)
  }
  for route in routes.values { DEQRouteDestroy(route) }
  report["records"] = records
  report["defaultAfter"] = consume(DEQDefaultOutputUID())
  report["originalDefault"] = originalDefault
  report["after"] = consume(DEQDevicesJSON())
  report["date"] = ISO8601DateFormatter().string(from: Date())
  report["measurementScope"] =
    "Own-process digital physical stream for EQ, all-process for direct baseline; not analog loopback"
  do {
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: reportURL, options: .atomic)
  } catch { fputs("Report failed: \(error)\n", stderr) }
}
