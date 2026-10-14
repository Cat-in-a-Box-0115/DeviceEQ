import Foundation
@main struct Tests {
 static func main() throws {
  let preset = try parseAPO("Preamp: -6.5 dB\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1.4\nFilter 2: ON LSC Fc 105 Hz Gain 5 dB Q 0.707\nChannel: R\nFilter 3: OFF HSC 6 dB Fc 3000 Hz Gain -6 dB\n")
  assert(preset.bands.count == 3 && preset.preamp == -6.5)
  assert(preset.bands[2].channel == "right" && !preset.bands[2].enabled)
  let roundtrip = try parseAPO(exportAPO(preset))
  for i in preset.bands.indices { assert(abs(roundtrip.bands[i].q-preset.bands[i].q)<1e-10) }
  let shelf = try parseAPO("Filter: ON LS Fc 100 Hz Gain 6 dB")
  assert(shelf.bands[0].frequency == 100 && abs(shelf.bands[0].q-0.669)<0.01)
  let corner = try parseAPO("Filter: ON LS 6 dB Fc 100 Hz Gain 6 dB")
  assert(abs(corner.bands[0].frequency-141.253754)<0.001)
  for bad in ["Include: other.txt", "Preamp: -2 dB\nChannel: L\nPreamp: -3 dB", "Filter: ON PK Fc 1000 Hz Gain 3 dB BW Oct 1", "Filter: ON PK Fc 1000 Hz Gain 3 dB", "Filter: ON AP Fc 1000 Hz Q 1", "Filter: ON LSC 6 dB Fc 100 Hz Gain 2 dB Q 1", "Filter: ON PK Fc NaN Hz Gain 3 dB Q 1"] {
    do { _ = try parseAPO(bad); fatalError("Accepted unsupported syntax: \(bad)") } catch { assert(error.localizedDescription.contains("Line ")) }
  }
  let squig = try parseAPO(String(contentsOfFile: "Tests/Import/Fixtures/synthetic-parametric-export.txt", encoding: .utf8))
  assert(squig.bands.count == 9 && squig.preamp == -5)
  assert(squig.bands[5].frequency == 3000 && squig.bands[5].gain == 4)
  do { _ = try parseAPO("Filter 1: ON PK Fc 0 Hz Gain 0 dB Q 0"); fatalError("Accepted invalid active row") } catch {}
  print("APO tests passed: AutoEq format, shelf Q/slope/corner conversions, channel/OFF roundtrip, strict errors.")
 }
}
