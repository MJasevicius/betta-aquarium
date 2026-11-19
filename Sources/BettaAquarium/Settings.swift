// Everything you can change about the tank, remembered between launches. Every value can be any
// value (the settings window offers some ready-made ones, and fields for your own). What is about
// one fish (its name, colours, personality) is in Life instead.

import Combine
import Foundation

let PALETTE_NAMES = ["Blue", "Fire", "Mustard", "Lotus", "Ice", "Koi", "Aurora", "Pearl"]

/// the letters that fill the fish, from its darkest folds to its brightest
let LETTER_SETS: [(name: String, pools: [String])] = [
    ("Classic", ["1il!;:", "rtfjcvxz=+", "aeoun0{}[]<>", "08B$#&%Q"]),
    ("Dense", [":;!il1", "tfjxz=+*", "aeounO0{}[]", "08B$#&%Q@M"]),
    ("Blocky", [".:", "+=*", "#%&", "@MW#"]),
    ("Minimal", [".", ":", "-=", "+*"]),
]

let FONTS = ["Courier", "Menlo", "Monaco", "SF Mono"]

enum ColourMode: Int { case all, favourites, timeOfDay, fixed }
/// how a fish takes the cursor: as its personality and its trust have it, or always the same way
enum Reaction: Int, Codable, CaseIterable {
    case ignore, curious, shy, dynamic, follow
    var name: String { ["Ignore It", "Curious", "Shy", "Depends on the Fish", "Follows It"][rawValue] }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let store = UserDefaults(suiteName: "io.github.mjasevicius.betta-aquarium") ?? .standard
    var onChange: ((String) -> Void)?                // told which setting changed

    private func get<T>(_ key: String, _ fallback: T) -> T { store.object(forKey: key) as? T ?? fallback }
    func has(_ key: String) -> Bool { store.object(forKey: key) != nil }
    private func set(_ key: String, _ value: Any) {
        objectWillChange.send()
        store.set(value, forKey: key)
        onChange?(key)
    }
    private func num(_ key: String, _ fallback: Double) -> Double {
        (store.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
    }

    // MARK: how it looks
    /// rows of letters on a screen: more rows, a smaller fish with more room
    var rows: Int { get { Int(num("rows", 128)) } set { set("rows", min(max(newValue, 40), 400)) } }
    var colourMode: ColourMode {
        get { ColourMode(rawValue: get("colourMode", 0)) ?? .all }
        set { set("colourMode", newValue.rawValue) }
    }
    /// the sets it changes through in favourites mode, and the one it keeps (keys: see Life)
    var favouriteKeys: [String] {
        get { get("favouriteKeys", (get("favourites", Array(0..<PALETTE_NAMES.count)) as [Int]).map(paletteKey)) }
        set { set("favouriteKeys", newValue) }
    }
    var fixedKey: String {
        get { get("fixedKey", paletteKey(get("fixedSet", 0))) }
        set { set("fixedKey", newValue) }
    }
    /// seconds between new sets of colours (the original: 2)
    var colourEvery: Double { get { num("colourEvery", 8.0) } set { set("colourEvery", max(newValue, 0.5)) } }
    var glow: Double { get { num("glow", 1.0) } set { set("glow", newValue) } }
    /// how much of the last frame stays behind
    var trail: Double { get { num("trail", 0.5) } set { set("trail", min(max(newValue, 0), 0.95)) } }
    var font: String { get { get("font", "Courier") } set { set("font", newValue) } }
    var letters: Int { get { get("letters", 0) } set { set("letters", newValue) } }
    /// darker towards the edges: 0 not at all
    var vignette: Double {
        get { has("vignetteAmount") ? num("vignetteAmount", 0) : (get("vignette", false) ? 1 : 0) }
        set { set("vignetteAmount", newValue) }
    }
    /// brightness of everything (1: as made)
    var brightness: Double { get { num("brightness", 1.0) } set { set("brightness", newValue) } }

    // MARK: the water
    /// light rays coming down through the water: 0 none, 1 normal (once a switch: on was 1)
    var rays: Double {
        get { has("rays") ? num("rays", 0.0) : (get("lightRays", false) ? 1 : 0) }
        set { set("rays", newValue) }
    }
    /// light playing over the fish, the sand and the plants: 0 none, 1 normal
    var caustics: Double { get { num("caustics", 0.0) } set { set("caustics", newValue) } }
    var surface: Bool { get { get("surface", false) } set { set("surface", newValue) } }
    /// what is on the bottom of the tank (see ENVIRONMENTS); "none" for bare water
    var environment: String {
        get { get("environment", get("seabed", false) ? "planted" : "none") }
        set { set("environment", newValue) }
    }
    /// background bubbles rising through the water: how many, against the original (1)
    var bubbles: Double { get { num("bubbles", 1.0) } set { set("bubbles", newValue) } }
    var company: Bool { get { get("company", false) } set { set("company", newValue) } }
    var tetras: Int { get { Int(num("tetras", 9)) } set { set("tetras", min(max(newValue, 1), 60)) } }

    // MARK: light through the day
    /// lights that come up at sunrise and go down at sunset, and a sleepy fish at night (once "sleepyAtNight")
    var dayNight: Bool {
        get { has("dayNight") ? get("dayNight", false) : get("sleepyAtNight", false) }
        set { set("dayNight", newValue) }
    }
    var sunrise: Double { get { num("sunrise", 7.0) } set { set("sunrise", newValue) } }     // hours (7.5: 7:30)
    var sunset: Double { get { num("sunset", 22.0) } set { set("sunset", newValue) } }       // up to 24 (midnight)
    /// sunrise and sunset where you are (from the location below), instead of the times above
    var sunFromLocation: Bool { get { get("sunFromLocation", false) } set { set("sunFromLocation", newValue) } }
    /// how long the light takes to come up or go down, in hours
    var twilight: Double { get { num("twilight", 1.0) } set { set("twilight", max(newValue, 0.05)) } }
    /// how dim it gets at night: 0 not at all, 1 dark
    var nightDim: Double { get { num("nightDim", 0.45) } set { set("nightDim", min(max(newValue, 0), 0.95)) } }
    /// how golden the light gets at sunrise and sunset: 0 not at all
    var golden: Double { get { num("golden", 1.0) } set { set("golden", newValue) } }
    /// a soft blue moonlight at night, instead of only dimming
    var nightLight: Bool { get { get("nightLight", false) } set { set("nightLight", newValue) } }
    var nightLightStrength: Double { get { num("nightLightStrength", 1.0) } set { set("nightLightStrength", newValue) } }

    // MARK: the weather where you are
    var weather: Bool { get { get("weather", false) } set { set("weather", newValue) } }
    var weatherStrength: Double { get { num("weatherStrength", 1.0) } set { set("weatherStrength", newValue) } }
    var placeName: String { get { get("placeName", "") } set { set("placeName", newValue) } }
    var latitude: Double { get { num("latitude", 0) } set { set("latitude", newValue) } }
    var longitude: Double { get { num("longitude", 0) } set { set("longitude", newValue) } }
    var hasPlace: Bool { has("latitude") && has("longitude") }
    /// minutes between asking for the weather
    var weatherEvery: Double { get { num("weatherEvery", 20) } set { set("weatherEvery", max(newValue, 5)) } }

    // MARK: how they behave
    var habits: Bool { get { get("habits", true) } set { set("habits", newValue) } }
    /// how fast they swim, against calm (1); they rest for less long the faster they go
    var pace: Double {
        get { has("paceSpeed") ? num("paceSpeed", 1) : [1.35, 1.0, 0.7][min(max(get("pace", 1), 0), 2)] }
        set { set("paceSpeed", min(max(newValue, 0.2), 3)) }
    }
    /// hours without food before it is hungry (0: never)
    var hunger: Double { get { num("hunger", 24.0) } set { set("hunger", max(newValue, 0)) } }
    var lastFed: Date {
        get { Date(timeIntervalSince1970: num("lastFed", Date().timeIntervalSince1970)) }
        set { set("lastFed", newValue.timeIntervalSince1970) }
    }
    /// pellets dropped for each fish at a feeding
    var pellets: Int { get { Int(num("pellets", 4)) } set { set("pellets", min(max(newValue, 1), 30)) } }
    var tapGlass: Bool { get { get("tapGlass", true) } set { set("tapGlass", newValue) } }
    /// how the fish take the cursor (each fish can have its own way, too)
    var mouse: Reaction {
        get { Reaction(rawValue: get("cursor", Reaction.dynamic.rawValue)) ?? .dynamic }
        set { set("cursor", newValue.rawValue) }
    }
    /// moods that show in their colours and the way they swim
    var moods: Bool { get { get("moods", true) } set { set("moods", newValue) } }
    /// remembering: the cursor, feeding times, favourite spots, taps on the glass
    var memory: Bool { get { get("memory", true) } set { set("memory", newValue) } }
    /// how fast they come to trust the cursor (1: over a few weeks)
    var trustSpeed: Double { get { num("trustSpeed", 1.0) } set { set("trustSpeed", max(newValue, 0)) } }
    /// a fish keeps a home and flares at others that come near it
    var territory: Bool { get { get("territory", true) } set { set("territory", newValue) } }
    /// days for two fish to get used to each other
    var toleranceDays: Double { get { num("toleranceDays", 21) } set { set("toleranceDays", max(newValue, 0.1)) } }
    /// coming to the front of the glass when you come back to the Mac
    var greet: Bool { get { get("greet", true) } set { set("greet", newValue) } }
    /// hours with nothing happening before a fish gets bored
    var boredAfter: Double { get { num("boredAfter", 5) } set { set("boredAfter", max(newValue, 0.1)) } }

    // MARK: growing up (in days)
    var youngDays: Double { get { num("youngDays", 3) } set { set("youngDays", max(newValue, 0)) } }
    var adultDays: Double { get { num("adultDays", 21) } set { set("adultDays", max(newValue, 0)) } }
    var growsOld: Bool { get { get("growsOld", true) } set { set("growsOld", newValue) } }
    var oldDays: Double { get { num("oldDays", 365) } set { set("oldDays", max(newValue, 1)) } }

    // MARK: seeing them
    var hoverCard: Bool { get { get("hoverCard", true) } set { set("hoverCard", newValue) } }
    /// seconds the pointer rests on a fish before its card shows
    var hoverDelay: Double { get { num("hoverDelay", 0.6) } set { set("hoverDelay", max(newValue, 0)) } }

    // MARK: practical
    var allScreens: Bool { get { get("allScreens", false) } set { set("allScreens", newValue) } }
    /// frames a second
    var fps: Double { get { num("fps", 30) } set { set("fps", min(max(newValue, 5), 120)) } }
    var pauseOnBattery: Bool { get { get("pauseOnBattery", false) } set { set("pauseOnBattery", newValue) } }
    var pauseLowPower: Bool { get { get("pauseLowPower", true) } set { set("pauseLowPower", newValue) } }
    /// not remembered: a paused fish wakes up again with the next launch
    var paused = false { didSet { objectWillChange.send(); onChange?("paused") } }

    /// the screen saver: the app's settings, as read from its file (a screen saver has defaults of its own)
    func adopt(_ dict: [String: Any]) { store.register(defaults: dict) }

    /// the first time it runs, it has just been fed
    func start() {
        // the first time: the settings it had before it had this name (as ASCII Betta Fish)
        if !has("adopted"), let old = UserDefaults.standard.persistentDomain(forName: "local.bettafish") {
            for (k, v) in old where store.object(forKey: k) == nil { store.set(v, forKey: k) }
        }
        store.set(true, forKey: "adopted")
        if !has("lastFed") { store.set(Date().timeIntervalSince1970, forKey: "lastFed") }
    }

    /// back to how it was made (only the settings: not the fish)
    func reset() {
        objectWillChange.send()
        for k in store.dictionaryRepresentation().keys where k != "lastFed" && k != "adopted" { store.removeObject(forKey: k) }
        onChange?("all")
    }

    /// sunrise and sunset today: the ones set, or the sun's where you are
    func sunTimes(on date: Date = Date()) -> (rise: Double, set: Double) {
        if sunFromLocation && hasPlace, let s = Sun.times(on: date, latitude: latitude, longitude: longitude) { return s }
        return (sunrise, sunset)
    }

    /// how deep into the night it is by the clock (0 day, 1 night, fading over the twilight around sunset
    /// and sunrise), and how golden the light is (most at sunrise and sunset themselves); both always 0
    /// unless the lights follow the clock
    func light(at date: Date = Date()) -> (night: Double, dawn: Double) {
        guard dayNight else { return (0, 0) }
        let (rise, down) = sunTimes(on: date)
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        var h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let half = twilight / 2
        if h < rise - half { h += 24 }                                      // past midnight: still the night before
        let set = down <= rise ? down + 24 : down
        func ramp(_ x: Double) -> Double { let x = min(max(x, 0), 1); return x * x * (3 - 2 * x) }
        let day = ramp((h - rise + half) / twilight) * (1 - ramp((h - set + half) / twilight))
        return (1 - day, golden * 4 * day * (1 - day))
    }

    /// whether it is hungry: not fed for as long as it can go
    func hungry(at date: Date = Date()) -> Bool {
        hunger > 0 && date.timeIntervalSince(lastFed) > hunger * 3600
    }

    /// the sets the tank's fish may wear now (indices into PALETTES)
    func allowedPalettes(at date: Date = Date()) -> [Int] {
        let life = Life.shared, all = Array(0..<PALETTES.count)
        switch colourMode {
        case .all: return all
        case .favourites:
            let f = favouriteKeys.compactMap(life.paletteIndex)
            return f.isEmpty ? all : f
        case .fixed: return [life.paletteIndex(fixedKey) ?? 0]
        case .timeOfDay: return Settings.timeOfDay(date)
        }
    }

    static func timeOfDay(_ date: Date) -> [Int] {
        switch Calendar.current.component(.hour, from: date) {
        case 6..<11: return [3, 2, 7]       // morning: lotus, mustard, pearl
        case 11..<17: return [5, 0, 2]      // day: koi, blue, mustard
        case 17..<22: return [1, 7, 3]      // evening: fire, pearl, lotus
        default: return [4, 0, 6]           // night: ice, blue, aurora
        }
    }

    /// the sets one fish may wear now
    func allowedPalettes(for p: FishProfile, at date: Date = Date()) -> [Int] {
        let life = Life.shared
        switch p.colours.mode {
        case .tank: return allowedPalettes(at: date)
        case .all: return Array(0..<PALETTES.count)
        case .chosen:
            let f = p.colours.sets.compactMap(life.paletteIndex)
            return f.isEmpty ? allowedPalettes(at: date) : f
        case .one: return [p.colours.sets.first.flatMap(life.paletteIndex) ?? 0]
        case .timeOfDay: return Settings.timeOfDay(date)
        }
    }
}
