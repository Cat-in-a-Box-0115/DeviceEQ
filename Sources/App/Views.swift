import AppKit
import SwiftUI

let filterTypes = [
  ("peak", "Peak"), ("lowShelf", "Low shelf"), ("highShelf", "High shelf"),
  ("highPass", "High pass"), ("lowPass", "Low pass"), ("notch", "Notch"),
]
struct ContentView: View {
  @EnvironmentObject var store: Store
  @State private var tab = 0
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var presetName = ""
  @State private var showingProfiles = false
  @State private var showingGuide = false
  @State private var guideStep = 0
  @State private var pendingUpdate: String?
  @State private var pendingDelete: Preset?
  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(selection: $store.selectedUID) {
        Section("Physical outputs") {
          ForEach(store.physical) { d in
            HStack(alignment: .top, spacing: 8) {
              VStack(alignment: .leading, spacing: 5) {
                Text(d.name).font(.headline).lineLimit(1)
                Text("\(Int(d.sampleRate)) Hz · \(d.channels) channels")
                  .font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer(minLength: 0)
              let state = store.eqState(uid: d.uid)
              VStack(spacing: 1) {
                Image(nsImage: BrandMark.statusImage(active: state == .active))
                Text(state.label).font(.caption2)
              }.foregroundStyle(.primary).help("EQ \(state.label.lowercased())")
            }.padding(.vertical, 6).tag(d.uid)
          }
        }
        Section("Saved / disconnected") {
          ForEach(
            store.library.profiles.values.filter { p in !store.physical.contains { $0.uid == p.uid }
            }.sorted { $0.deviceName < $1.deviceName }, id: \.uid
          ) { p in Text(p.deviceName).foregroundStyle(.secondary).tag(p.uid) }
        }
      }.navigationTitle("DeviceEQ").frame(minWidth: 220).help("Choose output to edit").tourTarget(.devices)
    } detail: {
      GeometryReader { viewport in
      VStack(alignment: .leading, spacing: 10) {
        header.tourTarget(.output)
        HStack {
          Picker("View", selection: $tab) {
            Text("Parametric EQ").tag(0)
            Text("Routing & status").tag(2)
          }.pickerStyle(.segmented).help("Editor or routing details")
          Spacer()
        }
        if tab == 0 { editor(graphHeight: viewport.size.width < 700 ? 140 : 200) } else { status }
      }.padding(16).frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
      }
      .navigationTitle(store.current.deviceName)
    }.frame(minWidth: 820, minHeight: 780)
      .alert("Couldn’t complete action", isPresented: Binding(
        get: { store.operationError != nil },
        set: { if !$0 { store.operationError = nil } }
      )) {
        Button("OK") { store.operationError = nil }
      } message: { Text(store.operationError ?? "") }
      .alert("Update saved profile?", isPresented: Binding(get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }), presenting: pendingUpdate) { name in
        Button("Cancel", role: .cancel) { pendingUpdate = nil }
        Button("Update") {
          store.savePreset(name: name)
          pendingUpdate = nil
        }
      } message: { name in Text("Replace the saved settings for “\(name)”? Undo can restore the previous version.") }
      .alert("Delete saved profile?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { preset in
        Button("Cancel", role: .cancel) { pendingDelete = nil }
        Button("Delete", role: .destructive) {
          store.deletePreset(id: preset.id)
          pendingDelete = nil
        }
      } message: { preset in Text("Delete “\(preset.name)”? Current EQ keeps playing. Undo can restore the profile.") }
      .overlayPreferenceValue(TourAnchors.self) { anchors in
        GeometryReader { geometry in
          if showingGuide {
            let target = anchors[TourStep.all[guideStep].target].map { geometry[$0].insetBy(dx: -4, dy: -4) }
              ?? CGRect(x: 8, y: 8, width: max(0, geometry.size.width - 16), height: 80)
            EditorTour(step: $guideStep, target: target.intersection(CGRect(origin: .zero, size: geometry.size)), size: geometry.size) {
              showingGuide = false
              AppPreferences.shared.guideCompleted = true
            }
          }
        }.allowsHitTesting(showingGuide)
      }
      .onAppear { if !AppPreferences.shared.guideCompleted { startTour() } }
      .onReceive(NotificationCenter.default.publisher(for: .showDeviceEQGuide)) { _ in startTour() }
      .onChange(of: store.selectedUID) { _, _ in presetName = ""; showingProfiles = false; pendingUpdate = nil; pendingDelete = nil; store.selectedBand = nil }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          SettingsLink { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .navigation) {
          HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
            Text("DeviceEQ").font(.headline)
          }.fixedSize().padding(.horizontal, 8).padding(.vertical, 4)
            .accessibilityLabel("DeviceEQ")
        }
      }
  }
  func startTour() {
    tab = 0; columnVisibility = .all; showingProfiles = false; guideStep = 0; showingGuide = true
    NSApp.keyWindow?.makeFirstResponder(nil)
  }
  var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .center, spacing: 10) {
          Text(store.current.deviceName).font(.title.bold()).lineLimit(2)
          Text("EQ " + store.eqState(uid: store.selectedUID).label.lowercased())
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule()).fixedSize()
            .help(store.selectedStatus).accessibilityLabel(store.selectedStatus)
        }
        Text(store.profileLabel).foregroundStyle(.secondary).help("Profile belongs to this output only")
      }
      Spacer()
      VStack(alignment: .trailing) {
        Toggle("EQ for this device", isOn: Binding(
          get: { store.current.routeEnabled },
          set: { value in if value != store.current.routeEnabled { store.toggleRoute() } }
        )).help("Enable EQ for this output").fixedSize().disabled(store.selectedUID.isEmpty || !store.physical.contains { $0.uid == store.selectedUID })

      }
    }
  }
  func editor(graphHeight: CGFloat) -> some View {
    VStack(spacing: 10) {
      ResponseGraph().frame(height: graphHeight).help("EQ frequency changes").tourTarget(.graph)
      WrappingControls {
        HStack {
        Text("Preamp")
        numeric(
          Binding(
            get: { store.current.preamp },
            set: { v in store.edit { $0.preamp = max(-60, min(24, v)) } }), width: 65)
          .disabled(store.current.autoHeadroom)
          .help("Manual gain; disable Auto headroom")
        Text("dB").foregroundStyle(.secondary)
        }
        Toggle(
          "Auto headroom",
          isOn: Binding(
            get: { store.current.autoHeadroom }, set: { v in store.edit { $0.autoHeadroom = v } })).help("Reduce gain to prevent clipping")
        let effective = effectivePreamp
        Text("Effective \(effective,specifier:"%.1f") dB").monospacedDigit().foregroundStyle(
          effective < store.current.preamp ? .orange : .secondary).help("Gain actually applied")
      }.fixedSize(horizontal: false, vertical: true).tourTarget(.headroom)
      GeometryReader { bandArea in
      ScrollView(.horizontal) {
        VStack(spacing: 8) {
      HStack {
        Text("On").frame(width: 26)
        Text("Filter").frame(width: 110, alignment: .leading)
        Text("Channel").frame(width: 75)
        Text("Frequency · Hz").frame(width: 100, alignment: .trailing)
        Text("Gain · dB").frame(width: 85, alignment: .trailing)
        Text("Q").frame(width: 75, alignment: .trailing)
        Spacer()
        Text("\(store.current.bands.count)/64 bands").foregroundStyle(.secondary)
      }.font(.caption).padding(.horizontal, 5)
      ScrollView {
        VStack(spacing: 6) { ForEach(store.current.bands) { band in BandRow(band: band) } }
      }.frame(height: max(30, bandArea.size.height - 26))
        }.frame(width: max(680, bandArea.size.width), height: bandArea.size.height)
      }
      }.frame(minHeight: 90, maxHeight: .infinity).tourTarget(.bands)
      WrappingControls {
        Button("Add band", systemImage: "plus") { store.edit { $0.bands.append(Band()) } }.disabled(
          store.current.bands.count >= 64).help("Add an EQ filter")
        Button("Undo", systemImage: "arrow.uturn.backward") { store.undo() }.labelStyle(.iconOnly).keyboardShortcut("z").help("Undo last edit")
        Button("Redo", systemImage: "arrow.uturn.forward") { store.redo() }.labelStyle(.iconOnly).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo last edit")
        Button("Reset") {
          store.edit {
            $0.bands = []
            $0.preamp = 0
            $0.metadata = [:]
            $0.name = "Manual"
            $0.curves = nil
          }
        }
        .help("Clear current EQ")
        Button("Import") { store.importAPO() }.help("Load parametric EQ file")
        Button("Export") { store.exportAPOFile() }.help("Save parametric EQ file")
      }.fixedSize(horizontal: false, vertical: true).tourTarget(.actions)
      Divider()
      WrappingControls {
        TextField("Profile name", text: $presetName).frame(width: 180).help("Name this device’s profile")
        Button(store.presetNamed(presetName) == nil ? "Save profile" : "Update profile") {
          if store.presetNamed(presetName) != nil { pendingUpdate = presetName.trimmingCharacters(in: .whitespacesAndNewlines) }
          else { store.savePreset(name: presetName) }
        }.disabled(!store.canSavePreset(name: presetName))
          .help(store.presetNamed(presetName) == nil ? "Save current EQ" : "Replace saved EQ")
        Button {
          showingProfiles.toggle()
        } label: {
          HStack(spacing: 8) {
            Text(store.current.presets.isEmpty ? "No saved profiles" : "Choose profile")
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
          }
        }.disabled(store.current.presets.isEmpty).help("Load or manage profiles")
          .popover(isPresented: $showingProfiles, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
              Text("Saved profiles").font(.headline)
              if store.activePreset == nil {
                Text("Current EQ is unsaved").font(.caption).foregroundStyle(.secondary)
              }
              Divider()
              ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(store.current.presets) { p in
                    HStack(spacing: 8) {
                      Button {
                        store.loadPreset(p)
                        presetName = p.name
                        showingProfiles = false
                      } label: {
                        HStack(spacing: 8) {
                          Image(systemName: "checkmark")
                            .opacity(store.activePreset?.id == p.id ? 1 : 0).frame(width: 14)
                          Text(p.name).lineLimit(2)
                          Spacer(minLength: 0)
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                          .contentShape(Rectangle())
                      }.buttonStyle(.plain)
                      Button {
                        showingProfiles = false
                        pendingDelete = p
                      } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete saved profile")
                        .accessibilityLabel("Delete profile \(p.name)")
                    }
                  }
                }
              }.frame(height: min(240, CGFloat(store.current.presets.count) * 40))
            }.padding(12).frame(width: 260)
          }
        Button("Show in Finder") { store.showProfilesInFinder() }
          .help("Reveal saved profile file")
      }.fixedSize(horizontal: false, vertical: true).tourTarget(.profiles)
    }.frame(maxHeight: .infinity, alignment: .top)
  }
  var effectivePreamp: Double {
    store.displayCache.effectivePreamp(store.current, rate: store.rate)
  }
  var status: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Sound output menu").font(.title2.bold())
        Text(
          "Turn on EQ for the devices you want to correct. Select their normal macOS sound output as usual; their saved EQ applies automatically. Devices with EQ off play normally. Native volume controls stay on the physical device."
        )
        Text("Actual destination: \(store.current.deviceName)").font(.headline)
        Text("Device UID: \(store.selectedUID)").font(.caption).textSelection(.enabled)
        if let stats = store.stats[store.selectedUID] {
          HStack {
            Text(
              "Input peak: \(20*log10(max(0.0000001,stats["inputPeak"] ?? 0)),specifier:"%.1f") dBFS"
            )
            Text(
              "Output peak: \(20*log10(max(0.0000001,stats["outputPeak"] ?? 0)),specifier:"%.1f") dBFS"
            )
          }.foregroundStyle((stats["outputPeak"] ?? 0) >= 1 ? .red : .secondary)
          ForEach(stats.keys.sorted(), id: \.self) { key in
            HStack {
              Text(key)
              Spacer()
              Text("\(stats[key] ?? 0,specifier:"%.3f")").monospacedDigit()
            }
          }
        }
        Divider()
        Text(
          "No custom audio driver is installed. System-audio permission lets DeviceEQ process this output locally. Audio is never uploaded."
        )
        Text(
          "Turning EQ off returns this device to normal playback. Quitting DeviceEQ stops all processing. A disconnected device’s profile stays saved for its next connection; another device never inherits its filters."
        )
        Text(
          "An analog headphone plugged into a DAC cannot normally be identified by macOS. Save named headphone presets for that DAC and switch them manually."
        )
        if !store.current.metadata.isEmpty {
          Divider()
          Text("Correction provenance").font(.headline)
          ForEach(store.current.metadata.keys.sorted(), id: \.self) { k in
            Text("\(k): \(store.current.metadata[k] ?? "")").font(.caption).textSelection(.enabled)
          }
        }
      }
    }
  }
}
func numeric(_ binding: Binding<Double>, width: CGFloat) -> some View {
  TextField("", value: binding, format: .number.precision(.fractionLength(0...3))).textFieldStyle(
    .roundedBorder
  ).frame(width: width).monospacedDigit().multilineTextAlignment(.trailing)
}
struct BandRow: View {
  @EnvironmentObject var store: Store
  let band: Band
  func bind<T>(_ key: WritableKeyPath<Band, T>) -> Binding<T> {
    Binding(
      get: { store.current.bands.first { $0.id == band.id }?[keyPath: key] ?? band[keyPath: key] },
      set: { v in
        store.edit { p in
          if let i = p.bands.firstIndex(where: { $0.id == band.id }) {
            p.bands[i][keyPath: key] = v
          }
        }
      })
  }
  var body: some View {
    HStack {
      Toggle("", isOn: bind(\.enabled)).labelsHidden().frame(width: 26).help("Enable this band")
      Picker("Filter", selection: bind(\.type)) {
        ForEach(filterTypes, id: \.0) { t in Text(t.1).tag(t.0) }
      }.labelsHidden().frame(width: 110).help("Filter shape")
      Picker("Channel", selection: bind(\.channel)) {
        Text("L + R").tag("both")
        Text("Left").tag("left")
        Text("Right").tag("right")
      }.labelsHidden().frame(width: 75).help("Channels to process")
      numeric(bind(\.frequency), width: 100).help("Center or cutoff frequency")
      numeric(bind(\.gain), width: 85).help("Boost or cut decibels").disabled(
        ["highPass", "lowPass", "notch"].contains(band.type))
      numeric(bind(\.q), width: 75).help("Bandwidth; higher is narrower")
      Button {
        store.selectedBand = store.selectedBand == band.id ? nil : band.id
      } label: {
        Image(systemName: "scope")
      }.help(store.selectedBand == band.id ? "Deselect band" : "Select band on graph")
      Spacer()
      Button {
        if store.selectedBand == band.id { store.selectedBand = nil }
        store.edit { $0.bands.removeAll { $0.id == band.id } }
      } label: {
        Image(systemName: "trash")
      }.help("Remove this band")
    }.padding(5).background(
      store.selectedBand == band.id ? Color.accentColor.opacity(0.12) : Color.clear,
      in: RoundedRectangle(cornerRadius: 6))
  }
}
struct ResponseGraph: View {
  @EnvironmentObject var store: Store
  @State private var trackingDrag = false
  @State private var draggedBand: UUID?
  private func hitBand(at point: CGPoint, size: CGSize) -> UUID? {
    let w = max(1, size.width - 66), h = max(1, size.height - 44)
    return store.current.bands.map { band -> (UUID, CGFloat) in
      let x = 42 + CGFloat(log10(max(20, min(20000, band.frequency)) / 20) / 3) * w
      let y = 20 + CGFloat((24 - max(-24, min(24, band.gain))) / 48) * h
      return (band.id, hypot(x - point.x, y - point.y))
    }.filter { $0.1 <= 12 }.min(by: { $0.1 < $1.1 })?.0
  }
  var body: some View {
    let profile = store.current
    let rate = store.rate
    let leftResponse = store.displayCache.response(profile, rate: rate, channel: 0)
    let rightResponse = profile.bands.contains(where: { $0.channel != "both" })
      ? store.displayCache.response(profile, rate: rate, channel: 1) : []
    let selected = profile.bands.first(where: { $0.id == store.selectedBand })
    let selectedResponse: [EQDisplayCache.Point] = {
      guard let selected else { return [] }
      var single = profile
      single.bands = [selected]
      return store.displayCache.response(single, rate: rate, channel: 0)
    }()
    return GeometryReader { geo in
      Canvas { ctx, size in
        let inset = CGSize(width: 42, height: 20)
        let w = size.width - inset.width - 24
        let h = size.height - 44
        func xy(_ f: Double, _ db: Double) -> CGPoint {
          CGPoint(
            x: inset.width + CGFloat(log10(max(20, min(20000, f)) / 20) / 3) * w,
            y: inset.height + CGFloat((24 - max(-24, min(24, db))) / 48) * h)
        }
        // Logarithmic minor divisions retain the familiar APO response-plot scale.
        let labeledFrequencies: [Double] = w >= 650
          ? [20, 30, 50, 100, 200, 300, 500, 1000, 2000, 3000, 5000, 10000, 20000]
          : [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        for decade in [10.0, 100, 1000, 10000] {
          for division in 1...9 {
            let f = decade * Double(division)
            guard f >= 20 && f <= 20000 else { continue }
            let x = xy(f, 0).x
            let major = division == 1 || labeledFrequencies.contains(f)
            var p = Path()
            p.move(to: CGPoint(x: x, y: 20))
            p.addLine(to: CGPoint(x: x, y: h + 20))
            ctx.stroke(p, with: .color(.secondary.opacity(major ? 0.24 : 0.12)),
              lineWidth: major ? 0.8 : 0.5)
          }
        }
        for f in labeledFrequencies {
          let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
          ctx.draw(Text(label).font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary), at: CGPoint(x: xy(f, 0).x, y: h + 32))
        }
        for db in stride(from: -24, through: 24, by: 3) {
          let y = xy(20, Double(db)).y
          var p = Path()
          p.move(to: CGPoint(x: 42, y: y))
          p.addLine(to: CGPoint(x: w + 42, y: y))
          let major = db % 6 == 0
          ctx.stroke(p, with: .color(.secondary.opacity(db == 0 ? 0.65 : major ? 0.24 : 0.12)),
            lineWidth: db == 0 ? 1 : major ? 0.8 : 0.5)
          if major {
            ctx.draw(Text(db > 0 ? "+\(db)" : "\(db)")
              .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
              at: CGPoint(x: 19, y: y))
          }
        }
        func plot(_ points: [EQDisplayCache.Point], _ color: Color) {
          var p = Path()
          var started = false
          for point in points {
            let f = point.frequency
            let db = point.db
            let v = xy(f, db)
            if !started { p.move(to: v); started = true } else { p.addLine(to: v) }
          }
          ctx.stroke(p, with: .color(color), lineWidth: 2)
        }
        plot(leftResponse, .mint)
        if !rightResponse.isEmpty { plot(rightResponse, .orange) }
        if let b = selected {
          plot(selectedResponse, .blue)
          let point = xy(b.frequency, b.gain)
          ctx.fill(
            Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
            with: .color(.blue))
        }
      }
        .contentShape(Rectangle()).gesture(
        DragGesture(minimumDistance: 3).onChanged { v in
          let w = max(1, geo.size.width - 66)
          let h = max(1, geo.size.height - 44)
          if !trackingDrag {
            trackingDrag = true
            // Hit-test in screen points so clicking empty space only clears selection.
            draggedBand = hitBand(at: v.startLocation, size: geo.size)
            store.selectedBand = draggedBand
          }
          guard let id = draggedBand,
            hypot(v.translation.width, v.translation.height) >= 3 else { return }
          let x = max(0, min(1, (v.location.x - 42) / w))
          let y = max(0, min(1, (v.location.y - 20) / h))
          let f = 20 * pow(1000, Double(x))
          let gain = 24 - 48 * Double(y)
          store.edit { p in
            if let i = p.bands.firstIndex(where: { $0.id == id }) {
              p.bands[i].frequency = min(f, store.rate * 0.49)
              if !["highPass", "lowPass", "notch"].contains(p.bands[i].type) {
                p.bands[i].gain = gain
              }
            }
          }
        }.onEnded { _ in
          trackingDrag = false
          draggedBand = nil
        }).simultaneousGesture(SpatialTapGesture().onEnded { v in
          store.selectedBand = hitBand(at: v.location, size: geo.size)
        })
    }.accessibilityLabel("EQ frequency response. Select a band to drag its frequency and gain. Click empty graph space to deselect.")
  }
}
