// Who the fish are: each one's name, personality, colours and age, what it remembers (how far it
// trusts the cursor, when it is usually fed, where it likes to rest, where the glass was tapped),
// and a diary of what has happened in the tank. Kept on disk, so the fish are the same fish after a
// restart, and time goes on while the Mac is off: they grow up by the calendar.

import Foundation
import simd

// MARK: - personality

/// each from 0 to 1
struct Personality: Codable, Equatable {
    var bold = 0.5          // 0 shy ... 1 bold: how far it flees, how soon it trusts, how it takes the cursor
    var active = 0.5        // 0 lazy ... 1 lively: how fast and how often it swims, how long it rests
    var greedy = 0.5        // 0 picky ... 1 greedy: how fast it goes for food, and from how far
    var builder = 0.5       // how often it blows a bubble nest, and for how long
    var showOff = 0.5       // how often it flares its fins

    static func random(_ rng: inout SplitMix) -> Personality {
        func one() -> Double { 0.08 + 0.84 * (rng.unit() + rng.unit()) / 2 }     // most near the middle
        return Personality(bold: one(), active: one(), greedy: one(), builder: one(), showOff: one())
    }

    static let names: [(key: WritableKeyPath<Personality, Double>, low: String, high: String)] = [
        (\.bold, "Shy", "Bold"), (\.active, "Lazy", "Lively"), (\.greedy, "Picky", "Greedy"),
        (\.builder, "Rarely Builds", "Keen Builder"), (\.showOff, "Modest", "Show-Off"),
    ]

    /// a few words for it: only what stands out
    var words: [String] {
        Personality.names.compactMap { n in
            let v = self[keyPath: n.key]
            return v >= 0.65 ? n.high.lowercased() : v <= 0.35 ? n.low.lowercased() : nil
        }
    }
}

// MARK: - colours

/// a set of colours of your own: body, belly and face, fin roots, fin middles, fin hems
struct CustomPalette: Codable, Identifiable, Equatable {
    var id = "c" + UUID().uuidString.prefix(8)
    var name = "My Colours"
    var colours: [[Double]] = [[0.10, 0.36, 1.00], [0.30, 0.86, 1.00], [0.40, 0.30, 1.00], [0.90, 0.26, 0.92], [1.00, 0.30, 0.55]]
    static let parts = ["Body", "Belly and Face", "Fin Roots", "Fin Middles", "Fin Hems"]
}

let BUILT_IN_PALETTES = PALETTES_BUILT_IN.count
/// the key of a built-in set
func paletteKey(_ i: Int) -> String { "b\(i)" }

struct FishColours: Codable, Equatable {
    enum Mode: Int, Codable, CaseIterable { case tank, all, chosen, one, timeOfDay }
    var mode = Mode.tank
    var sets: [String] = []                 // palette keys: chosen sets, or the first is the one set
    var every: Double? = nil                // seconds between new colours (nil: the tank's)
}

// MARK: - one fish

struct FishProfile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var seed: UInt64
    var born: Date                          // its age runs from here
    var joined = Date()                     // when it came into the tank
    var personality: Personality
    var colours = FishColours()
    var fixedAge: Double? = nil             // in days: it stays this age (nil: it grows by the calendar)
    var reaction: Reaction? = nil           // to the cursor (nil: the tank's setting)
    var size = 1.0                          // on top of what its age gives it
    var finLength = 1.0
}

struct Grudge: Codable { var x: Double, y: Double, at: Date, strength: Double }

/// what a fish remembers
struct Memory: Codable {
    var trust = 0.15                        // of the cursor: 0 wary ... 1 follows it about
    var feeds: [Double] = []                // when it was fed lately, in minutes into the day
    var learned: [Double] = []              // feeding times it has come to expect
    var spots: [String: Double] = [:]       // where it rests ("x,y" in the water, rounded): minutes there
    var grudges: [Grudge] = []
    var stress = 0.0, stressAt = Date()
    var attention = Date()                  // when something last happened to it (food, the cursor, a tap)
    var nestRecord = 0
    var milestones: [String] = []
    var cursorDay = "", cursorTrustToday = 0.0
    var logged: [String: Date] = [:]        // when some kinds of diary entry were last written for it
}

enum Stage: Int, Comparable {
    case juvenile, young, adult, old
    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["Juvenile", "Young Adult", "Adult", "Old"][rawValue] }
}

enum MoodName: String {
    case content = "Content", excited = "Excited", hungry = "Hungry", sleepy = "Sleepy", stressed = "Stressed"
    case curious = "Curious", bored = "Bored", expecting = "Expecting Food"
}

/// how it looks, from its age and mood: each 1 for a content adult
struct Looks: Equatable {
    var size = 1.0, fins = 1.0, colour = 1.0, bright = 1.0, stripes = 0.0
    func eased(to b: Looks, _ k: Double) -> Looks {
        Looks(size: size + (b.size - size) * k, fins: fins + (b.fins - fins) * k, colour: colour + (b.colour - colour) * k,
              bright: bright + (b.bright - bright) * k, stripes: stripes + (b.stripes - stripes) * k)
    }
}

/// a fish's memory and what it is going through now
final class FishMind {
    var memory: Memory
    var excitedUntil = Date.distantPast
    var curiousUntil = Date.distantPast
    var mood = MoodName.content
    init(_ m: Memory) { memory = m }

    func stress(_ now: Date, bold: Double) -> Double {
        let minutes = now.timeIntervalSince(memory.stressAt) / 60
        return memory.stress * pow(0.5, minutes / (8 + 14 * bold))
    }

    func addStress(_ k: Double, _ now: Date, bold: Double) {
        memory.stress = min(stress(now, bold: bold) + k, 2)
        memory.stressAt = now
    }

    /// fed: it remembers when, comes to trust you a little more, and is excited for a while
    func fed(_ now: Date, _ p: FishProfile, trustSpeed: Double) {
        memory.trust = min(memory.trust + 0.03 * (0.6 + p.personality.bold) * trustSpeed, 1)
        memory.attention = now
        excitedUntil = now.addingTimeInterval(180)
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        memory.feeds.append(Double((c.hour ?? 0) * 60 + (c.minute ?? 0)))
        if memory.feeds.count > 14 { memory.feeds.removeFirst(memory.feeds.count - 14) }
        // a time it has been fed at, give or take 40 minutes, three times or more: it comes to expect it
        func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 1440); return min(d, 1440 - d) }
        var slots = [Double]()
        for f in memory.feeds {
            let near = memory.feeds.filter { apart($0, f) <= 40 }
            guard near.count >= 3 else { continue }
            let mean = near.reduce(0, +) / Double(near.count)
            if !slots.contains(where: { apart($0, mean) < 60 }) { slots.append(mean) }
        }
        for s in slots where !memory.learned.contains(where: { apart($0, s) < 60 }) {
            Life.shared.log(p.id, String(format: "%@ has learned you usually feed around %d:%02d.", p.name, Int(s) / 60, Int(s) % 60))
        }
        memory.learned = slots
    }

    /// the glass tapped at p: a fright it remembers (a shy fish more)
    func tapped(_ p: P2, _ now: Date, _ f: FishProfile) {
        let bold = f.personality.bold
        addStress(0.35 * (1.3 - bold), now, bold: bold)
        memory.trust = max(memory.trust - 0.02 * (1.4 - bold), 0)
        memory.grudges.append(Grudge(x: p.x, y: p.y, at: now, strength: 1))
        if memory.grudges.count > 12 { memory.grudges.removeFirst() }
        memory.attention = now
        Life.shared.logNow(f.id, kind: "tap", every: 3 * 3600, "\(f.name) got a fright from a tap on the glass.")
    }

    /// about when it is usually fed (from a quarter of an hour before), and not fed yet
    func expectsFood(_ now: Date, lastFed: Date) -> Bool {
        guard !memory.learned.isEmpty else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        for s in memory.learned {
            var d = m - s
            if d < -720 { d += 1440 } else if d > 720 { d -= 1440 }
            if d >= -15 && d <= 30 && now.timeIntervalSince(lastFed) > (d + 60) * 60 { return true }
        }
        return false
    }

    /// where it likes to rest most, if anywhere much
    var favourite: P2? {
        guard let best = memory.spots.max(by: { $0.value < $1.value }), best.value > 8 else { return nil }
        let c = best.key.split(separator: ",").compactMap { Double($0) }
        return c.count == 2 ? P2(c[0], c[1]) : nil
    }

    func rested(at p: P2, minutes: Double) {
        let key = String(format: "%.1f,%.1f", (p.x / 0.6).rounded() * 0.6, (p.y / 0.6).rounded() * 0.6)
        memory.spots[key, default: 0] += minutes
        if memory.spots.count > 60 {                       // forget the least liked
            for k in memory.spots.sorted(by: { $0.value < $1.value }).prefix(20).map(\.key) { memory.spots[k] = nil }
        }
    }

    /// the grudges it still holds, as places to keep away from and how much
    func grudges(_ now: Date, bold: Double) -> [(P2, Double)] {
        memory.grudges.removeAll { now.timeIntervalSince($0.at) > 3 * 86400 }
        return memory.grudges.map { g in
            let hours = now.timeIntervalSince(g.at) / 3600
            return (P2(g.x, g.y), g.strength * exp(-hours / (2 + 10 * (1 - bold))))
        }.filter { $0.1 > 0.08 }
    }
}

struct DiaryEntry: Codable, Identifiable {
    var id = UUID().uuidString
    var at: Date
    var fish: String?                       // its id, or nil for the tank
    var text: String
}

// MARK: - everyone

final class Life: ObservableObject {
    static let shared = Life()

    @Published var fish: [FishProfile] = [] { didSet { if fish != oldValue { changed() } } }
    @Published var palettes: [CustomPalette] = [] { didSet { if palettes != oldValue { refreshPalettes(); changed() } } }
    @Published private(set) var diary: [DiaryEntry] = []
    private(set) var minds: [String: FishMind] = [:]
    var onChange: (() -> Void)?
    private var loading = false

    private var file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Betta Aquarium", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("life.json")
    }()

    private struct Saved: Codable {
        var fish: [FishProfile]
        var memories: [String: Memory]
        var palettes: [CustomPalette]
        var diary: [DiaryEntry]
    }

    /// from disk; or, the first time, as many fish as there were (the first one grown up already)
    func load(count: Int, adultDays: Double, from: URL? = nil) {
        if let from { file = from }
        else if !FileManager.default.fileExists(atPath: file.path) {
            // the first time: the fish it had before it had this name (as ASCII Betta Fish)
            let old = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ASCII Betta Fish/life.json")
            try? FileManager.default.copyItem(at: old, to: file)
        }
        loading = true
        defer { loading = false }
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            palettes = s.palettes
            fish = s.fish
            minds = Dictionary(uniqueKeysWithValues: s.fish.map { ($0.id, FishMind(s.memories[$0.id] ?? Memory())) })
            diary = s.diary
        } else {
            for i in 0..<max(count, 1) {
                var p = newProfile()
                p.born = Date().addingTimeInterval(-(adultDays + 5) * 86400)
                if i == 0 { p.colours = FishColours() }
                add(p, note: "\(p.name) was already in the tank when the diary began.")
            }
            loading = false
            save()
        }
        refreshPalettes()
    }

    /// kept on disk only by the app (the tools have fish of their own)
    var persist = false

    func save() {
        guard persist else { return }
        let s = Saved(fish: fish, memories: minds.mapValues(\.memory), palettes: palettes, diary: diary)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: file, options: .atomic) }
    }

    private func changed() {
        guard !loading else { return }
        for f in fish where minds[f.id] == nil { minds[f.id] = FishMind(Memory()) }
        onChange?()
        saveSoon()
    }

    /// saved a moment later (a slider being dragged changes things many times a second)
    private var pending: DispatchWorkItem?
    func saveSoon() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    /// what it remembers, set from the settings (trust), or forgotten
    func setTrust(_ id: String, _ v: Double) { objectWillChange.send(); minds[id]?.memory.trust = min(max(v, 0), 1); saveSoon() }
    func forget(_ id: String) {
        objectWillChange.send()
        guard let m = minds[id] else { return }
        let milestones = m.memory.milestones
        m.memory = Memory()
        m.memory.milestones = milestones
        if let p = profile(id) { log(id, "\(p.name) has forgotten everything it knew.") }
        saveSoon()
    }

    // MARK: fish coming and going

    func newProfile() -> FishProfile {
        var rng = SplitMix(UInt64.random(in: 1...UInt64.max))
        let taken = Set(fish.map(\.name))
        let name = FISH_NAMES.filter { !taken.contains($0) }.randomElement() ?? "Fish \(fish.count + 1)"
        return FishProfile(name: name, seed: rng.next() | 1, born: Date(), personality: .random(&rng))
    }

    func add(_ p: FishProfile, note: String? = nil) {
        let m = FishMind(Memory())
        // already this old: none of the growing up to write about
        let st = stage(p)
        m.memory.milestones = ["stage1", "stage2", "stage3"].prefix(st.rawValue).map { $0 }
        minds[p.id] = m
        fish.append(p)
        log(p.id, note ?? "\(p.name) joined the tank, a tiny juvenile.")
    }

    func addFish() {
        guard fish.count < MAX_FISH else { return }
        add(newProfile())
    }

    func remove(_ id: String) {
        guard fish.count > 1, let p = fish.first(where: { $0.id == id }) else { return }
        log(nil, "\(p.name) went to a new home.")
        fish.removeAll { $0.id == id }
        minds[id] = nil
    }

    /// as many fish as asked for: new ones join as juveniles, the newest leave first
    func setCount(_ n: Int) {
        let n = min(max(n, 1), MAX_FISH)
        while fish.count < n { addFish() }
        while fish.count > n, let last = fish.last { remove(last.id) }
    }

    func profile(_ id: String) -> FishProfile? { fish.first { $0.id == id } }
    func update(_ p: FishProfile) { if let i = fish.firstIndex(where: { $0.id == p.id }) { fish[i] = p } }

    // MARK: growing up

    /// how old it is, in days (the calendar's, or the one it is kept at)
    func age(_ p: FishProfile, _ now: Date = Date()) -> Double {
        p.fixedAge ?? max(now.timeIntervalSince(p.born) / 86400, 0)
    }

    func stage(_ p: FishProfile, _ s: Settings = .shared, _ now: Date = Date()) -> Stage {
        let d = age(p, now)
        if s.growsOld && d >= s.oldDays { return .old }
        return d >= s.adultDays ? .adult : d >= s.youngDays ? .young : .juvenile
    }

    /// how grown it looks, from its age: size, fins, colour (and how slow it is, when old)
    func growth(_ p: FishProfile, _ s: Settings = .shared, _ now: Date = Date()) -> (size: Double, fins: Double, colour: Double, slow: Double) {
        let d = age(p, now)
        func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * smoothD(k) }
        let young = max(s.youngDays, 0.01), adult = max(s.adultDays, young + 0.01)
        var g: (size: Double, fins: Double, colour: Double, slow: Double)
        if d < young {
            let k = d / young
            g = (lerp(0.5, 0.72, k), lerp(0.3, 0.6, k), lerp(0.3, 0.68, k), 1)
        } else {
            let k = (d - young) / (adult - young)
            g = (lerp(0.72, 1, k), lerp(0.6, 1, k), lerp(0.68, 1, k), 1)
        }
        if s.growsOld && d > s.oldDays {
            let k = min((d - s.oldDays) / max(s.oldDays * 0.5, 1), 1)             // the year after: slowly
            g = (lerp(1, 0.96, k), lerp(1, 0.86, k), lerp(1, 0.62, k), lerp(1, 0.68, k))
        }
        return (g.size * p.size, g.fins * p.finLength, g.colour, g.slow)
    }

    // MARK: the diary

    func log(_ fish: String?, _ text: String, at: Date = Date()) {
        diary.append(DiaryEntry(at: at, fish: fish, text: text))
        if diary.count > 1500 { diary.removeFirst(diary.count - 1500) }
        if !loading { saveSoon() }
    }

    /// write it unless one of its kind was written for this fish less than `every` ago
    func logNow(_ fish: String, kind: String, every: TimeInterval, _ text: String) {
        guard let m = minds[fish] else { return }
        let now = Date()
        if let last = m.memory.logged[kind], now.timeIntervalSince(last) < every { return }
        m.memory.logged[kind] = now
        log(fish, text)
    }

    /// write it once in the fish's life
    func milestone(_ fish: String, _ key: String, _ text: String) {
        guard let m = minds[fish], !m.memory.milestones.contains(key) else { return }
        m.memory.milestones.append(key)
        log(fish, text)
    }

    func clearDiary() { diary.removeAll(); save() }

    // MARK: colours

    /// PALETTES: the built-in sets, then yours
    func refreshPalettes() {
        PALETTES = PALETTES_BUILT_IN + palettes.map { $0.colours.map { V3(R($0[0]), R($0[1]), R($0[2])) } }
        Shape.shared.palettesChanged()
    }

    func paletteIndex(_ key: String) -> Int? {
        if key.hasPrefix("b"), let i = Int(key.dropFirst()), i < BUILT_IN_PALETTES { return i }
        return palettes.firstIndex { $0.id == key }.map { BUILT_IN_PALETTES + $0 }
    }

    func paletteName(_ key: String) -> String {
        if let i = paletteIndex(key) { return i < BUILT_IN_PALETTES ? PALETTE_NAMES[i] : palettes[i - BUILT_IN_PALETTES].name }
        return "?"
    }

    var allPaletteKeys: [String] { (0..<BUILT_IN_PALETTES).map(paletteKey) + palettes.map(\.id) }
}

let FISH_NAMES = [
    "Mango", "Pip", "Indigo", "Ember", "Koi", "Nori", "Basil", "Juniper", "Comet", "Saffron", "Pebble", "Ziggy", "Biscuit",
    "Sapphire", "Rooibos", "Figaro", "Mochi", "Tango", "Cosmo", "Velvet", "Marble", "Rumi", "Opal", "Pepper", "Sable",
    "Kiwi", "Lapis", "Bramble", "Clementine", "Nimbus", "Cinder", "Fennel", "Quill", "Echo", "Taffy", "Atlas", "Plum",
    "Ripple", "Sunny", "Bonsai", "Gizmo", "Lumen", "Paprika", "Ruby", "Sprout", "Wasabi", "Yuzu", "Zephyr", "Domino",
    "Flint", "Gatsby", "Hazel", "Ink", "Jasper", "Kelp", "Loki", "Mercury", "Nova", "Orca", "Poppy", "Rascal",
]
