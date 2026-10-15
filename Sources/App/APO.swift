import Foundation

struct APOBandValue {
    var type: String
    var frequency: Double
    var gain: Double
    var q: Double
    var enabled: Bool
    var channel: String
}
struct APOPresetValue { var bands: [APOBandValue]; var preamp: Double }
struct APOError: LocalizedError { let message: String; var errorDescription: String? { message } }

// Conventions checked against Equalizer APO's configuration reference and BiQuadFilterFactory/
// BiQuadFilter: https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/
// Center shelves LSC/HSC use RBJ Q. Explicit LS/HS Q or dB/oct slopes specify
// corner frequency, requiring a center-frequency conversion. Bare LS/HS default
// to a center shelf with S=0.9 (not Q=0.9). BW Oct needs stream sample rate and
// is deliberately rejected instead of applying an approximate conversion.
// Equalizer APO configs saved by Windows Notepad as "Unicode" are UTF-16 with a byte-order mark.
func readPresetText(_ data: Data) throws -> String {
    // Some Foundation versions keep the byte-order mark as U+FEFF, which would corrupt the first directive.
    func dropBOM(_ text: String) -> String { text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text }
    let bytes = [UInt8](data.prefix(2))
    if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF], let text = String(data: data, encoding: .utf16) { return dropBOM(text) }
    if let text = String(data: data, encoding: .utf8) { return dropBOM(text) }
    throw APOError(message: "The preset is not UTF-8 or UTF-16 text. Re-save it as UTF-8 and try again.")
}

func parseAPO(_ text: String) throws -> APOPresetValue {
    var result = APOPresetValue(bands: [], preamp: 0)
    var channel = "both"
    var sawDirective = false
    for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
        let lineNumber = index + 1
        let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        func fail(_ reason: String) -> APOError { APOError(message: "Line \(lineNumber): \(reason)") }
        guard let colon = line.firstIndex(of: ":") else { throw fail("Expected an APO directive followed by ':'") }
        let command = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let tokens = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func number(_ token: String) throws -> Double {
            guard token.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", options: .regularExpression) != nil,
                  let n = Double(token), n.isFinite else { throw fail("Invalid numeric value '\(token)'; use decimal points") }
            return n
        }
        switch command {
        case "CHANNEL":
            switch tokens.joined(separator: " ").uppercased() {
            case "ALL", "L R", "R L", "1 2", "2 1": channel = "both"
            case "L", "1": channel = "left"
            case "R", "2": channel = "right"
            default: throw fail("Only stereo Channel: ALL, L, R, 1, or 2 is supported")
            }
            sawDirective = true
        case "PREAMP":
            guard channel == "both" else { throw fail("Per-channel preamp cannot be represented by this preset") }
            guard tokens.count == 2, tokens[1].uppercased() == "DB" else { throw fail("Expected Preamp: <number> dB") }
            result.preamp += try number(tokens[0]); sawDirective = true
            guard (-120...48).contains(result.preamp) else { throw fail("Combined preamp must be between -120 and +48 dB") }
        default:
            guard command.range(of: "^FILTER(?:\\s+[0-9]+)?$", options: .regularExpression) != nil else { throw fail("Unsupported directive '\(command)'") }
            guard tokens.count >= 5, ["ON", "OFF"].contains(tokens[0].uppercased()) else { throw fail("Expected Filter: ON/OFF <type> Fc <number> Hz ...") }
            let kind = tokens[1].uppercased()
            let types = ["PK":"peak", "PEQ":"peak", "LS":"lowShelf", "LSC":"lowShelf", "HS":"highShelf", "HSC":"highShelf", "HP":"highPass", "HPQ":"highPass", "LP":"lowPass", "LPQ":"lowPass", "NO":"notch"]
            guard let type = types[kind] else { throw fail("Unsupported filter type '\(kind)'") }
            let shelf = ["LS", "LSC", "HS", "HSC"].contains(kind)
            var position = 2
            var slopeDB: Double?
            if shelf, tokens[position].uppercased() != "FC" {
                slopeDB = try number(tokens[position]); position += 1
                guard position < tokens.count, tokens[position].uppercased() == "DB" else { throw fail("Shelf slope must have the form LSC 6 dB Fc ...") }
                position += 1
            }
            guard position + 2 < tokens.count, tokens[position].uppercased() == "FC", tokens[position+2].uppercased() == "HZ" else { throw fail("Expected Fc <number> Hz") }
            var frequency = try number(tokens[position+1]); position += 3
            var gain = 0.0
            if type == "peak" || shelf {
                guard position+2 < tokens.count, tokens[position].uppercased() == "GAIN", tokens[position+2].uppercased() == "DB" else { throw fail("This filter requires Gain <number> dB") }
                gain = try number(tokens[position+1]); position += 3
            }
            var explicitQ: Double?
            if position < tokens.count {
                guard position+1 < tokens.count, tokens[position].uppercased() == "Q" else { throw fail("Unsupported trailing parameters (BW Oct requires sample-rate-aware conversion)") }
                explicitQ = try number(tokens[position+1]); position += 2
            }
            guard position == tokens.count else { throw fail("Unexpected trailing parameters") }
            guard !(slopeDB != nil && explicitQ != nil) else { throw fail("Specify shelf slope or Q, not both") }
            // Squiglink exports unused rows as OFF PK Fc 0 Hz Gain 0 dB Q 0.
            // They carry no filter and must not become a zero-frequency biquad.
            if tokens[0].uppercased() == "OFF", frequency == 0, gain == 0,
               explicitQ == 0, slopeDB == nil { continue }
            var q = explicitQ ?? (type == "notch" ? 30 : sqrt(0.5))
            if type == "peak", explicitQ == nil { throw fail("Peaking filters require Q") }
            if shelf {
                let a = pow(10, gain/40)
                let s: Double
                if let explicitQ {
                    guard explicitQ > 0 else { throw fail("Q must be positive") }
                    s = 1 / ((1/(explicitQ*explicitQ)-2)/(a+1/a)+1)
                } else {
                    s = slopeDB.map { $0/12 } ?? 0.9
                    guard s > 0 else { throw fail("Shelf slope must be positive") }
                    let denominator = (a+1/a)*(1/s-1)+2
                    guard denominator > 0 else { throw fail("Shelf slope does not yield a stable finite Q") }
                    q = 1/sqrt(denominator)
                }
                // Explicit LS/HS parameters use corner rather than center frequency.
                if (kind == "LS" || kind == "HS"), explicitQ != nil || slopeDB != nil {
                    guard s.isFinite, s > 0 else { throw fail("Unsupported LS/HS corner-frequency conversion; use LSC/HSC with Q") }
                    let factor = pow(10, abs(gain)/80/s)
                    frequency = kind == "LS" ? frequency*factor : frequency/factor
                }
            }
            guard frequency.isFinite, frequency > 0, frequency < 192000,
                  gain.isFinite, abs(gain) <= 48, q.isFinite, (0.05...100).contains(q) else { throw fail("Filter outside supported limits: positive frequency below 192kHz, gain ±48dB, Q 0.05–100") }
            guard result.bands.count < 64 else { throw fail("At most 64 filters are supported") }
            result.bands.append(APOBandValue(type: type, frequency: frequency, gain: gain, q: q, enabled: tokens[0].uppercased() == "ON", channel: channel))
            sawDirective = true
        }
    }
    guard sawDirective else { throw APOError(message: "No APO directives found") }
    return result
}

func exportAPO(_ preset: APOPresetValue) throws -> String {
    guard preset.preamp.isFinite, (-120...48).contains(preset.preamp), preset.bands.count <= 64 else { throw APOError(message: "Invalid preset preamp or band count") }
    func numeric(_ n: Double) -> String { String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), n) }
    var lines = ["# DeviceEQ parametric preset — RBJ Q; center-frequency shelves", "Channel: ALL", "Preamp: \(numeric(preset.preamp)) dB"]
    let kinds = ["peak":"PK", "lowShelf":"LSC", "highShelf":"HSC", "highPass":"HPQ", "lowPass":"LPQ", "notch":"NO"]
    var previousChannel = "both"
    for (i, band) in preset.bands.enumerated() {
        guard let kind = kinds[band.type], ["both", "left", "right"].contains(band.channel),
              band.frequency.isFinite, band.frequency > 0, band.frequency < 192000,
              band.gain.isFinite, abs(band.gain) <= 48, band.q.isFinite, (0.05...100).contains(band.q) else { throw APOError(message: "Band \(i+1): invalid type, channel, or parameters") }
        if band.channel != previousChannel {
            lines.append("Channel: \(band.channel == "left" ? "L" : band.channel == "right" ? "R" : "ALL")")
            previousChannel = band.channel
        }
        var filter = "Filter \(i+1): \(band.enabled ? "ON" : "OFF") \(kind) Fc \(numeric(band.frequency)) Hz"
        if ["peak", "lowShelf", "highShelf"].contains(band.type) { filter += " Gain \(numeric(band.gain)) dB" }
        filter += " Q \(numeric(band.q))"
        lines.append(filter)
    }
    return lines.joined(separator: "\n") + "\n"
}
