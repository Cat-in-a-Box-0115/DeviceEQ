import Foundation

/// UI-only calculations. Audio processing always uses its own DSP configuration.
@MainActor final class EQDisplayCache {
  struct ResponseKey: Equatable {
    var bands: [Band]
    var rate: Double
    var channel: Int32
  }
  struct HeadroomKey: Equatable {
    var bands: [Band]
    var rate: Double
    var preamp: Double
    var automatic: Bool
  }
  struct Point { var frequency: Double; var db: Double }
  private var headroom: (HeadroomKey, Double)?
  private var responses: [(ResponseKey, [Point])] = []
  private(set) var headroomCalculations = 0
  private(set) var responseCalculations = 0

  func effectivePreamp(_ profile: DeviceProfile, rate: Double) -> Double {
    let key = HeadroomKey(bands: profile.bands, rate: rate, preamp: profile.preamp, automatic: profile.autoHeadroom)
    if let cached = headroom, cached.0 == key { return cached.1 }
    var config = configFor(profile, rate: rate)
    let value = DEQEffectivePreampDB(&config)
    headroom = (key, value)
    headroomCalculations += 1
    return value
  }

  func response(_ profile: DeviceProfile, rate: Double, channel: Int32) -> [Point] {
    let key = ResponseKey(bands: profile.bands, rate: rate, channel: channel)
    if let cached = responses.first(where: { $0.0 == key }) { return cached.1 }
    var config = configFor(profile, rate: rate)
    var frequencies = (0...720).map { 20 * pow(1000, Double($0) / 720) }
    for band in profile.bands where band.enabled {
      for offset in -12...12 {
        let f = band.frequency * exp(Double(offset) / (12 * max(0.05, band.q)))
        if f >= 20 && f <= 20000 { frequencies.append(f) }
      }
    }
    frequencies.sort()
    let values = frequencies.filter { $0 < rate / 2 }.compactMap { frequency -> Point? in
      let db = DEQResponseDB(&config, frequency, channel)
      return db.isFinite ? Point(frequency: frequency, db: db) : nil
    }
    responses.append((key, values))
    if responses.count > 4 { responses.removeFirst() }
    responseCalculations += 1
    return values
  }
}
