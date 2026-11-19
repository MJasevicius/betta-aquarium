// The settings window: everything about the tank and each fish. Every number can be anything: the
// menu beside it has some ready-made choices, and the field takes your own.

import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case fish = "Fish", look = "Look", water = "Water and Light", behaviour = "Behaviour", screens = "Screens and Power", diary = "Diary"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .fish: "fish"
        case .look: "paintpalette"
        case .water: "sun.haze"
        case .behaviour: "brain.head.profile"
        case .screens: "display.2"
        case .diary: "book"
        }
    }
}

final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published var page: SettingsPage = .fish
    @Published var fish: String?
}

// MARK: - pieces

/// a number: a field for any value, and a menu of ready-made ones (and a slider, if given a range)
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    var presets: [(String, Double)] = []
    var unit = ""
    var range: ClosedRange<Double>? = nil
    var digits = 2
    var help = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                InfoLabel(title)
                Spacer()
                if let range {
                    Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }), in: range)
                        .frame(maxWidth: 180)
                }
                TextField("", value: $value, format: .number.precision(.fractionLength(0...digits)))
                    .frame(width: 64).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading) }
                if !presets.isEmpty {
                    Menu {
                        ForEach(presets.indices, id: \.self) { i in
                            Button { value = presets[i].1 } label: {
                                if abs(presets[i].1 - value) < 1e-9 { Label(presets[i].0, systemImage: "checkmark") } else { Text(presets[i].0) }
                            }
                        }
                    } label: { Image(systemName: "chevron.up.chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                    .help("Ready-made values")
                }
            }
            if !help.isEmpty { Text(help).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

/// a time of day, as hours (7.5: 7:30)
struct TimeRow: View {
    let title: String
    @Binding var hours: Double
    var body: some View {
        DatePicker(selection: Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(hours * 3600)
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            hours = h == 0 && title.lowercased().contains("set") ? 24 : h
        }), displayedComponents: .hourAndMinute) { InfoLabel(title) }
    }
}

/// a set of colours, as five dots
struct Swatch: View {
    let palette: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { j in
                let c = PALETTES[min(palette, PALETTES.count - 1)][j]
                Circle().fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))).frame(width: 11, height: 11)
            }
        }
    }
}

private func colourBinding(_ rgb: Binding<[Double]>) -> Binding<Color> {
    Binding(get: { Color(red: rgb.wrappedValue[0], green: rgb.wrappedValue[1], blue: rgb.wrappedValue[2]) }, set: { c in
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
        rgb.wrappedValue = [Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)]
    })
}

/// what a page keeps while it is open
final class UIState: ObservableObject {
    @Published var confirm = false
    @Published var search = ""
    @Published var found: [Weather.Place] = []
    @Published var searching = false
    @Published var note = ""
    @Published var login = false
    @Published var who = "all"
}

// MARK: - the window

struct SettingsView: View {
    let app: App
    @ObservedObject var model = SettingsModel.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: Binding(get: { model.page }, set: { if let p = $0 { model.page = p } })) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            switch model.page {
            case .fish: FishPage()
            case .look: LookPage()
            case .water: WaterPage()
            case .behaviour: BehaviourPage()
            case .screens: ScreensPage(app: app)
            case .diary: DiaryPage()
            }
        }
    }
}

// MARK: - fish

private struct FishPage: View {
    @ObservedObject var life = Life.shared
    @ObservedObject var model = SettingsModel.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding(get: { model.fish ?? life.fish.first?.id }, set: { model.fish = $0 })) {
                    ForEach(life.fish) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.headline)
                            Text("\(life.stage(f).name) · \(life.minds[f.id]?.mood.rawValue ?? "")").font(.caption).foregroundStyle(.secondary)
                        }.tag(f.id).padding(.vertical, 2)
                    }
                }
                HStack {
                    Button { life.addFish(); model.fish = life.fish.last?.id } label: { Image(systemName: "plus") }
                        .disabled(life.fish.count >= MAX_FISH).help(SETTING_INFO["Add a Fish"] ?? "")
                    Spacer()
                    Text("\(life.fish.count) of \(MAX_FISH)").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            .frame(width: 190)
            Divider()
            if let id = model.fish ?? life.fish.first?.id, let i = life.fish.firstIndex(where: { $0.id == id }) {
                FishEditor(index: i).id(id)
            } else {
                Text("No fish").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct FishEditor: View {
    let index: Int
    @ObservedObject var life = Life.shared
    @ObservedObject var s = Settings.shared
    @StateObject private var ui = UIState()

    private var f: Binding<FishProfile> { $life.fish[index] }

    var body: some View {
        let p = life.fish[index]
        Form {
            Section {
                TextField(text: f.name) { InfoLabel("Name") }
                LabeledContent("Age") { Text("\(Describe.age(life.age(p))) · \(life.stage(p).name)") }
                LabeledContent("Mood") { Text(life.minds[p.id]?.mood.rawValue ?? "") }
            }

            Section("Colours") {
                Picker(selection: f.colours.mode) {
                    Text("The Tank's Colours").tag(FishColours.Mode.tank)
                    Text("Every Set in Turn").tag(FishColours.Mode.all)
                    Text("Chosen Sets in Turn").tag(FishColours.Mode.chosen)
                    Text("One Set Always").tag(FishColours.Mode.one)
                    Text("Sets for the Time of Day").tag(FishColours.Mode.timeOfDay)
                } label: { InfoLabel("Wears") }
                if p.colours.mode == .chosen || p.colours.mode == .one {
                    ForEach(life.allPaletteKeys, id: \.self) { key in
                        let on = p.colours.mode == .one ? p.colours.sets.first == key : p.colours.sets.contains(key)
                        Button {
                            var c = p.colours
                            if c.mode == .one { c.sets = [key] } else if on { c.sets.removeAll { $0 == key } } else { c.sets.append(key) }
                            life.fish[index].colours = c
                        } label: {
                            HStack {
                                Image(systemName: on ? (p.colours.mode == .one ? "largecircle.fill.circle" : "checkmark.square.fill") : (p.colours.mode == .one ? "circle" : "square"))
                                Text(life.paletteName(key))
                                Spacer()
                                Swatch(palette: life.paletteIndex(key) ?? 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Button("Make Its Own Colours…") {
                    var c = CustomPalette()
                    c.name = "\(p.name)'s Colours"
                    let base = Settings.shared.allowedPalettes(for: p).first ?? 0
                    c.colours = PALETTES[base].map { [Double($0.x), Double($0.y), Double($0.z)] }
                    life.palettes.append(c)
                    life.fish[index].colours = FishColours(mode: .one, sets: [c.id], every: p.colours.every)
                }.help(SETTING_INFO["Make Its Own Colours…"] ?? "")
                if p.colours.mode == .one, let key = p.colours.sets.first, let ci = life.palettes.firstIndex(where: { $0.id == key }) {
                    PaletteEditor(index: ci)
                }
                Toggle(isOn: Binding(get: { p.colours.every != nil },
                                                                set: { life.fish[index].colours.every = $0 ? s.colourEvery : nil })) { InfoLabel("Its Own Pace of Change") }
                if p.colours.every != nil {
                    NumberRow(title: "New Colours Every", value: Binding(get: { p.colours.every ?? 8 }, set: { life.fish[index].colours.every = max($0, 0.5) }),
                              presets: [("2 Seconds", 2), ("8 Seconds", 8), ("30 Seconds", 30), ("2 Minutes", 120), ("10 Minutes", 600)], unit: "s", digits: 1)
                }
            }

            Section {
                ForEach(Personality.names.indices, id: \.self) { i in
                    let n = Personality.names[i]
                    HStack {
                        Text(n.low).font(.caption).frame(width: 90, alignment: .trailing)
                        Slider(value: f.personality[dynamicMember: n.key], in: 0...1)
                        Text(n.high).font(.caption).frame(width: 90, alignment: .leading)
                        if let i = SETTING_INFO[n.high] { InfoButton(text: i) }
                    }
                }
                Button("Shuffle Personality") {
                    var r = SplitMix(UInt64.random(in: 1...UInt64.max))
                    life.fish[index].personality = .random(&r)
                }.help(SETTING_INFO["Shuffle Personality"] ?? "")
            } header: { Text("Personality") } footer: {
                Text("Bold fish flee less far, trust the cursor sooner and come back to look after a tap. Lively ones swim more. Greedy ones go for food faster. Builders blow more bubble nests; show-offs flare more.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Age and Size") {
                Toggle(isOn: Binding(get: { p.fixedAge == nil }, set: { auto in
                    life.fish[index].fixedAge = auto ? nil : life.age(p)
                    if auto { life.fish[index].born = Date().addingTimeInterval(-life.age(p) * 86400) }
                })) { InfoLabel("Grows Up by the Calendar") }
                if p.fixedAge == nil {
                    DatePicker(selection: f.born, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) { InfoLabel("Born") }
                } else {
                    NumberRow(title: "Stays This Old", value: Binding(get: { p.fixedAge ?? 0 }, set: { life.fish[index].fixedAge = max($0, 0) }),
                              presets: [("Juvenile", 1), ("Young Adult", max(s.youngDays + 1, 1)), ("Adult", s.adultDays + 30),
                                        ("Old", s.oldDays + 120)], unit: "days", digits: 1)
                }
                NumberRow(title: "Size", value: f.size, presets: [("Smaller", 0.8), ("As It Grows", 1), ("Bigger", 1.2)], unit: "×",
                          range: 0.4...1.6)
                NumberRow(title: "Fin Length", value: f.finLength, presets: [("Shorter", 0.7), ("As It Grows", 1), ("Longer", 1.25)], unit: "×",
                          range: 0.3...1.6)
            }

            Section("The Cursor") {
                Picker(selection: Binding(get: { p.reaction.map { $0.rawValue } ?? -1 },
                                                               set: { life.fish[index].reaction = $0 < 0 ? nil : Reaction(rawValue: $0) })) {
                    Text("As Set for the Tank (\(s.mouse.name))").tag(-1)
                    ForEach(Reaction.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                } label: { InfoLabel("Takes the Cursor") }
                let trust = life.minds[p.id]?.memory.trust ?? 0
                NumberRow(title: "Trust", value: Binding(get: { trust }, set: { life.setTrust(p.id, $0) }), range: 0...1,
                          help: Describe.trust(trust) + ". It grows as you feed it and move the cursor gently near it; taps on the glass set it back.")
            }

            Section("What It Remembers") {
                let m = life.minds[p.id]?.memory ?? Memory()
                LabeledContent("Feeding Times") {
                    Text(m.learned.isEmpty ? "None learned yet" : m.learned.sorted().map(Describe.clock).joined(separator: ", "))
                }
                LabeledContent("Favourite Spot") { Text(life.minds[p.id]?.favourite == nil ? "None yet" : "Has one") }
                LabeledContent("Taps It Remembers") { Text("\(m.grudges.count)") }
                LabeledContent("Biggest Nest") { Text(m.nestRecord > 0 ? "\(m.nestRecord) bubbles" : "—") }
                Button("Forget Everything") { life.forget(p.id) }.help(SETTING_INFO["Forget Everything"] ?? "")
            }

            Section {
                Button("Rehome \(p.name)…", role: .destructive) { ui.confirm = true }.help(SETTING_INFO["Rehome"] ?? "")
                    .disabled(life.fish.count <= 1)
                    .confirmationDialog("Rehome \(p.name)?", isPresented: $ui.confirm) {
                        Button("Rehome", role: .destructive) { life.remove(p.id); SettingsModel.shared.fish = life.fish.first?.id }
                    } message: { Text("It leaves the tank, and everything about it is gone.") }
            }
        }
        .formStyle(.grouped)
    }
}


private struct PaletteEditor: View {
    let index: Int
    @ObservedObject var life = Life.shared
    var body: some View {
        if index < life.palettes.count {
            TextField(text: $life.palettes[index].name) { InfoLabel("Name of the Set") }
            ForEach(0..<5, id: \.self) { j in
                ColorPicker(selection: colourBinding($life.palettes[index].colours[j]), supportsOpacity: false) { InfoLabel(CustomPalette.parts[j]) }
            }
        }
    }
}

// MARK: - look

private struct LookPage: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var life = Life.shared

    var body: some View {
        Form {
            Section("Fish") {
                NumberRow(title: "Fish Size (rows of letters on a screen)", value: Binding(get: { Double(s.rows) }, set: { s.rows = Int($0) }),
                          presets: [("Tiny", 220), ("Small", 160), ("Medium", 128), ("Large", 104), ("Huge", 80)], digits: 0,
                          help: "More rows: smaller letters, so a smaller fish with more room to swim.")
                Picker(selection: $s.font) { ForEach(FONTS, id: \.self) { Text($0) } } label: { InfoLabel("Letters") }
                Picker(selection: $s.letters) { ForEach(LETTER_SETS.indices, id: \.self) { Text(LETTER_SETS[$0].name).tag($0) } } label: { InfoLabel("Fill") }
            }
            Section("The Tank's Colours") {
                Picker(selection: $s.colourMode) {
                    Text("Every Set in Turn").tag(ColourMode.all)
                    Text("Favourites in Turn").tag(ColourMode.favourites)
                    Text("Sets for the Time of Day").tag(ColourMode.timeOfDay)
                    Text("One Set Always").tag(ColourMode.fixed)
                } label: { InfoLabel("Fish Wear") }
                if s.colourMode == .favourites || s.colourMode == .fixed {
                    ForEach(life.allPaletteKeys, id: \.self) { key in
                        let on = s.colourMode == .fixed ? s.fixedKey == key : s.favouriteKeys.contains(key)
                        Button {
                            if s.colourMode == .fixed { s.fixedKey = key }
                            else if on { s.favouriteKeys.removeAll { $0 == key } } else { s.favouriteKeys.append(key) }
                        } label: {
                            HStack {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                Text(life.paletteName(key)); Spacer(); Swatch(palette: life.paletteIndex(key) ?? 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                NumberRow(title: "New Colours Every", value: $s.colourEvery,
                          presets: [("2 Seconds (Original)", 2), ("8 Seconds", 8), ("30 Seconds", 30), ("2 Minutes", 120), ("10 Minutes", 600)],
                          unit: "s", digits: 1, help: "Each fish can have its own, under Fish.")
            }
            Section {
                ForEach(life.palettes.indices, id: \.self) { i in
                    DisclosureGroup {
                        PaletteEditor(index: i)
                        Button("Delete This Set", role: .destructive) { life.palettes.remove(at: i) }.help(SETTING_INFO["Delete This Set"] ?? "")
                    } label: {
                        HStack { Text(life.palettes[i].name); Spacer(); Swatch(palette: BUILT_IN_PALETTES + i) }
                    }
                }
                Button("New Colour Set") { var c = CustomPalette(); c.name = "My Colours \(life.palettes.count + 1)"; life.palettes.append(c) }.help(SETTING_INFO["New Colour Set"] ?? "")
            } header: { Text("Your Own Colour Sets") } footer: {
                Text("Made here, they can be worn by any fish (choose them under Fish, or for the whole tank above).").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Glow and Light") {
                NumberRow(title: "Glow", value: $s.glow, presets: [("Off", 0), ("Soft", 0.5), ("Normal", 1), ("Strong", 1.6), ("Dazzling", 2.5)], range: 0...3)
                NumberRow(title: "Trail", value: $s.trail, presets: [("Off", 0), ("Short", 0.3), ("Normal", 0.5), ("Long", 0.75), ("Very Long", 0.9)], range: 0...0.95)
                NumberRow(title: "Brightness", value: $s.brightness, presets: [("Dim", 0.6), ("Normal", 1), ("Bright", 1.3)], range: 0.2...2)
                NumberRow(title: "Darker Edges", value: $s.vignette, presets: [("Off", 0), ("Soft", 0.5), ("Normal", 1), ("Strong", 1.5)], range: 0...2)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - water and light

private struct WaterPage: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var weather = Weather.shared
    @StateObject private var ui = UIState()

    var body: some View {
        Form {
            Section("Environment") {
                Picker(selection: $s.environment) {
                    Text("Bare Tank").tag("none")
                    ForEach(ENVIRONMENTS, id: \.id) { Text($0.name).tag($0.id) }
                } label: { InfoLabel("On the Bottom") }
                if let e = BettaAquarium.environment(s.environment) { Text(e.about).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                Toggle(isOn: $s.surface) { InfoLabel("Water Surface") }
                NumberRow(title: "Bubbles in the Water", value: $s.bubbles, presets: [("None", 0), ("Few", 0.4), ("Normal", 1), ("Lots", 2)], unit: "×", range: 0...4)
                Toggle(isOn: $s.company) { InfoLabel("Tank Mates (Neon Tetras)") }
                if s.company {
                    NumberRow(title: "How Many Tetras", value: Binding(get: { Double(s.tetras) }, set: { s.tetras = Int($0) }),
                              presets: [("A Few", 5), ("A School", 9), ("A Big School", 20), ("Lots", 40)], digits: 0)
                }
            }
            Section("Light in the Water") {
                NumberRow(title: "Light Rays", value: $s.rays, presets: [("Off", 0), ("Faint", 0.5), ("Normal", 1), ("Strong", 1.8), ("Very Strong", 3)], range: 0...5)
                NumberRow(title: "Caustics", value: $s.caustics, presets: [("Off", 0), ("Soft", 0.5), ("Normal", 1), ("Strong", 1.8)], range: 0...3)
            }
            Section("Day and Night") {
                Toggle(isOn: $s.dayNight) { InfoLabel("Sunrise and Sunset") }
                Toggle(isOn: $s.sunFromLocation) { InfoLabel("Sunrise and Sunset Where You Are") }.disabled(!s.hasPlace)
                if s.sunFromLocation && s.hasPlace {
                    let t = s.sunTimes()
                    LabeledContent("Today") { Text("Sunrise \(Describe.hours(t.rise)) · Sunset \(Describe.hours(t.set))") }
                } else {
                    TimeRow(title: "Sunrise", hours: $s.sunrise)
                    TimeRow(title: "Sunset", hours: $s.sunset)
                }
                NumberRow(title: "Twilight", value: $s.twilight, presets: [("Quick", 0.25), ("Half an Hour", 0.5), ("An Hour", 1), ("Two Hours", 2)], unit: "h", digits: 2)
                NumberRow(title: "Darker at Night", value: $s.nightDim, presets: [("Not at All", 0), ("A Little", 0.25), ("Normal", 0.45), ("Dark", 0.7)], range: 0...0.95)
                NumberRow(title: "Golden Light at Dawn and Dusk", value: $s.golden, presets: [("None", 0), ("Normal", 1), ("Strong", 1.5)], range: 0...2)
                Toggle(isOn: $s.nightLight) { InfoLabel("Night Light (Soft Blue Moonlight)") }
                if s.nightLight {
                    NumberRow(title: "Moonlight", value: $s.nightLightStrength, presets: [("Faint", 0.5), ("Normal", 1), ("Bright", 1.5)], range: 0...2)
                }
            }
            Section {
                Toggle(isOn: $s.weather) { InfoLabel("Weather Where You Are") }.disabled(!s.hasPlace)
                LabeledContent("Place") { Text(s.hasPlace ? (s.placeName.isEmpty ? String(format: "%.3f, %.3f", s.latitude, s.longitude) : s.placeName) : "Not set") }
                HStack {
                    TextField(text: $ui.search, prompt: Text("Find a town or city")) { InfoLabel("Find a town or city") }.onSubmit(find)
                    Button("Find", action: find).disabled(ui.search.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Use My Location") {
                        ui.note = "Asking Location Services…"
                        weather.locate { place, problem in
                            if let place { choose(place); ui.note = "" } else { ui.note = problem ?? "Couldn't find where this Mac is" }
                        }
                    }.help(SETTING_INFO["Use My Location"] ?? "")
                }
                if ui.searching { ProgressView().controlSize(.small) }
                ForEach(ui.found) { p in
                    Button { choose(p) } label: { HStack { Text(p.name); Spacer(); Text(String(format: "%.2f, %.2f", p.latitude, p.longitude)).foregroundStyle(.secondary) } }
                }
                HStack {
                    NumberRow(title: "Latitude", value: Binding(get: { s.latitude }, set: { s.latitude = min(max($0, -90), 90); s.placeName = "" }), digits: 4)
                    NumberRow(title: "Longitude", value: Binding(get: { s.longitude }, set: { s.longitude = min(max($0, -180), 180); s.placeName = "" }), digits: 4)
                }
                if !ui.note.isEmpty { Text(ui.note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                if s.weather {
                    if let sky = weather.sky {
                        LabeledContent("Now") { Text("\(sky.summary) · cloud \(Int(sky.cloud * 100))% · checked \(Describe.ago(sky.at))") }
                    }
                    if let problem = weather.problem { Text(problem).font(.caption).foregroundStyle(.red) }
                    NumberRow(title: "How Much It Shows", value: $s.weatherStrength, presets: [("A Little", 0.5), ("Normal", 1), ("A Lot", 1.5)], range: 0...2)
                    NumberRow(title: "Check Every", value: $s.weatherEvery, presets: [("10 Minutes", 10), ("20 Minutes", 20), ("An Hour", 60)], unit: "min", digits: 0)
                }
            } header: { Text("Weather") } footer: {
                Text("Clouds dim the light and the rays, rain falls on the surface, fog softens everything, and thunderstorms flash. The weather comes from Open-Meteo (open-meteo.com), sent only the place's latitude and longitude; finding a place sends what you type. Nothing is sent while this is off.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func find() {
        let q = ui.search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        ui.searching = true
        weather.search(q) { r in ui.found = r; ui.searching = false; ui.note = r.isEmpty ? "Nothing found called that" : "" }
    }

    private func choose(_ p: Weather.Place) {
        s.placeName = p.name
        s.latitude = p.latitude
        s.longitude = p.longitude
        ui.found = []
        ui.search = ""
    }
}

// MARK: - behaviour

private struct BehaviourPage: View {
    @ObservedObject var s = Settings.shared

    var body: some View {
        Form {
            Section("Swimming") {
                NumberRow(title: "Pace", value: $s.pace, presets: [("Very Calm", 0.7), ("Calm", 1), ("Lively", 1.35), ("Hyper", 2)], unit: "×", range: 0.2...3,
                          help: "Each fish's own personality makes it a little livelier or lazier than this.")
                Toggle(isOn: $s.habits) { InfoLabel("Betta Habits (Bubble Nests, Air, Flaring)") }
            }
            Section("Food") {
                NumberRow(title: "Gets Hungry After", value: $s.hunger, presets: [("Never", 0), ("6 Hours", 6), ("12 Hours", 12), ("A Day", 24), ("Two Days", 48)],
                          unit: "h", digits: 1, help: "Without food: 0 for never. Last fed \(Describe.ago(s.lastFed)).")
                NumberRow(title: "Pellets for Each Fish", value: Binding(get: { Double(s.pellets) }, set: { s.pellets = Int($0) }),
                          presets: [("A Few", 3), ("Normal", 4), ("A Feast", 8)], digits: 0)
            }
            Section("You and the Fish") {
                Picker(selection: $s.mouse) { ForEach(Reaction.allCases, id: \.self) { Text($0.name).tag($0) } } label: { InfoLabel("The Cursor") }
                Text("Depends on the Fish: a shy fish keeps away at first and a bold one comes to look; as it comes to trust you (feeding it, moving the cursor gently near it) it comes closer, and in the end follows the cursor about. Stressed, it keeps away; asleep, it takes no notice. Each fish can be set its own way, under Fish.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                NumberRow(title: "How Fast They Come to Trust You", value: $s.trustSpeed, presets: [("Slowly", 0.5), ("Normal (Weeks)", 1), ("Quickly (Days)", 4), ("Straight Away", 30)], unit: "×", digits: 1)
                Toggle(isOn: $s.tapGlass) { InfoLabel("Tap the Glass (Click the Desktop)") }
                Toggle(isOn: $s.greet) { InfoLabel("Come to Say Hello When You Come Back") }
            }
            Section("Minds of Their Own") {
                Toggle(isOn: $s.moods) { InfoLabel("Moods (Shown in Their Colours, Fins and Swimming)") }
                NumberRow(title: "Bored After Nothing Happens For", value: $s.boredAfter, presets: [("An Hour", 1), ("5 Hours", 5), ("A Day", 24)], unit: "h", digits: 1)
                Toggle(isOn: $s.memory) { InfoLabel("Memory (the Cursor, Feeding Times, Favourite Spots, Taps)") }
                Toggle(isOn: $s.territory) { InfoLabel("Territory (Flaring at Fish Near Their Home)") }
                NumberRow(title: "Days to Get Used to Each Other", value: $s.toleranceDays, presets: [("A Day", 1), ("A Week", 7), ("Three Weeks", 21), ("Never Quite", 9999)], unit: "days", digits: 1)
            }
            Section("Growing Up") {
                NumberRow(title: "Young Adult At", value: $s.youngDays, presets: [("An Hour", 1.0 / 24), ("A Day", 1), ("3 Days", 3), ("A Week", 7)], unit: "days", digits: 2)
                NumberRow(title: "Grown Up At", value: $s.adultDays, presets: [("A Day", 1), ("A Week", 7), ("3 Weeks", 21), ("2 Months", 60)], unit: "days", digits: 2)
                Toggle(isOn: $s.growsOld) { InfoLabel("Grows Old") }
                if s.growsOld {
                    NumberRow(title: "Old At", value: $s.oldDays, presets: [("A Month", 30), ("Half a Year", 182), ("A Year", 365), ("Two Years", 730)], unit: "days", digits: 0)
                }
            }
            Section("Its Card") {
                Toggle(isOn: $s.hoverCard) { InfoLabel("Show a Fish's Card When the Pointer Rests on It") }
                NumberRow(title: "After", value: $s.hoverDelay, presets: [("Straight Away", 0), ("A Moment", 0.6), ("A Second", 1), ("Two Seconds", 2)], unit: "s", digits: 1)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - screens and power

private struct ScreensPage: View {
    let app: App
    @ObservedObject var s = Settings.shared
    @StateObject private var ui = UIState()

    var body: some View {
        Form {
            Section("Screens") {
                Toggle(isOn: $s.allScreens) { InfoLabel("One Tank Across All Screens") }
                NumberRow(title: "Frames a Second", value: $s.fps, presets: [("15 (Saves Power)", 15), ("30", 30), ("60 (Smoothest)", 60)], digits: 0,
                          help: "More is smoother and uses more of the CPU.")
            }
            Section("Power") {
                Toggle(isOn: $s.pauseOnBattery) { InfoLabel("Pause on Battery") }
                Toggle(isOn: $s.pauseLowPower) { InfoLabel("Pause in Low Power Mode") }
                Toggle(isOn: Binding(get: { ui.login }, set: { app.setOpensAtLogin($0); ui.login = app.opensAtLogin })) { InfoLabel("Open at Login") }
                    .onAppear { ui.login = app.opensAtLogin }
            }
            Section {
                Button("Install the Screen Saver") { ui.note = app.installSaver() }.help(SETTING_INFO["Install the Screen Saver"] ?? "")
                if !ui.note.isEmpty { Text(ui.note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
            } header: { Text("Screen Saver") } footer: {
                Text("The same tank as a screen saver: your fish, environment and look. Choose it in System Settings ▸ Screen Saver.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Button("Back to How It Was Made…", role: .destructive) { ui.confirm = true }.help(SETTING_INFO["Back to How It Was Made…"] ?? "")
                    .confirmationDialog("Put every setting back as it was made?", isPresented: $ui.confirm) {
                        Button("Reset Settings", role: .destructive) { s.reset() }
                    } message: { Text("Your fish, their memories and the diary stay as they are.") }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - the diary

private struct DiaryPage: View {
    @ObservedObject var life = Life.shared
    @StateObject private var ui = UIState()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(selection: $ui.who) {
                    Text("Everything").tag("all")
                    Text("The Tank").tag("tank")
                    ForEach(life.fish) { Text($0.name).tag($0.id) }
                } label: { InfoLabel("Show") }.frame(maxWidth: 260)
                Spacer()
                Button("Clear…") { ui.confirm = true }.help(SETTING_INFO["Clear…"] ?? "")
                    .confirmationDialog("Clear the whole diary?", isPresented: $ui.confirm) {
                        Button("Clear", role: .destructive) { life.clearDiary() }
                    }
            }.padding(10)
            Divider()
            let entries = life.diary.reversed().filter { ui.who == "all" || (ui.who == "tank" ? $0.fish == nil : $0.fish == ui.who) }
            if entries.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.at, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        Text(e.text)
                    }
                }
            }
        }
    }
}
