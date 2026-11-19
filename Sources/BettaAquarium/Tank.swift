// The tank: one body of water across every screen, the fish in it, and what else is in the water.
// It is drawn as two layers of letters over the same screens:
//   - the fish's layer, as fine as the fish size asks for: the fish (only the point in front of each
//     cell is lit), their bubbles and nests, the pellets, the flares
//   - the scenery's layer, always the same size, so that the plants keep theirs whatever the fish
//     size: sand and plants, the background bubbles, the tank mates, the surface, taps on the glass
// The GPU puts the fish's layer over the scenery's.

import CoreGraphics
import Foundation
import simd

let SCENERY_ROWS = 128                                  // rows of scenery letters on the main screen
let SURFACE_ROW = 6                                     // rows of air above the water, when the surface is drawn
let MAX_FISH = 6

/// what the app tells the tank each frame
struct Surroundings {
    var mood = Mood()
    var mouse: P2? = nil                // where the pointer is, in the water (nil: on no screen of the tank)
    var mouseMoving = false             // and whether it has just moved
    var reaction: Reaction = .ignore
    var now = Date()                    // the wall clock, for what the fish remember
    var lastFed = Date()
    var moods = true, memory = true, territory = true
    var trustSpeed = 1.0, toleranceDays = 21.0, boredAfter = 5.0
    var rain = 0.0                      // 0 dry ... 1 pouring: drops on the surface
}

/// a screen's part of a grid, in cells
struct Region { var x0, y0, cols, rows: Int }

/// letters laid over every screen, all the same size
struct Grid {
    var cellW: Double, cellH: Double                    // in points
    var cols: Int, rows: Int
    var regions: [Region]

    init(world: CGRect, screens: [CGRect], cellH: Double) {
        self.cellH = cellH
        cellW = cellH * Double(CELL_W) / Double(CELL_H)
        let cols = max(Int((world.width / cellW).rounded()), 1), rows = max(Int((world.height / cellH).rounded()), 1)
        self.cols = cols; self.rows = rows
        let w = cellW, h = cellH
        regions = screens.map { f in
            let x0 = Int(((f.minX - world.minX) / w).rounded()), x1 = Int(((f.maxX - world.minX) / w).rounded())
            let y0 = Int(((world.maxY - f.maxY) / h).rounded()), y1 = Int(((world.maxY - f.minY) / h).rounded())
            return Region(x0: x0, y0: y0, cols: max(min(x1, cols) - x0, 1), rows: max(min(y1, rows) - y0, 1))
        }
    }
}

/// how the screens lie (in points, y up, the main screen first) and the two grids over them
struct Layout {
    var world: CGRect
    var screens: [CGRect]
    var fish: Grid, scenery: Grid

    init(screens: [CGRect], fishRows: Int, sceneryRows: Int = SCENERY_ROWS) {
        self.screens = screens
        world = screens.dropFirst().reduce(screens[0]) { $0.union($1) }
        fish = Grid(world: world, screens: screens, cellH: screens[0].height / Double(fishRows))
        scenery = Grid(world: world, screens: screens, cellH: screens[0].height / Double(sceneryRows))
    }

    /// one screen of cols x rows letters the size of the original's (for the tools)
    static func single(cols: Int, rows: Int) -> Layout {
        Layout(screens: [CGRect(x: 0, y: 0, width: cols * CELL_W, height: rows * CELL_H)], fishRows: rows)
    }
}

final class Tank {
    // scratch for the fins' points, shared by every fish
    static let pos = Buf<V3>(.zero), lag = Buf<R>(0)

    let seed: UInt64
    private let withBubbles: Bool
    private(set) var layout: Layout
    private(set) var version = 0                        // goes up whenever the layout changes
    var surroundings = Surroundings()
    var fill = fillLetters(LETTER_SETS[0].pools)

    // what is in the water besides the fish (the menu decides)
    var environment: Environment? { didSet { if environment?.id != oldValue?.id { arrangeScenery(); reshape() } } }
    var bubbleAmount = 1.0 { didSet { if bubbleAmount != oldValue { arrangeScenery() } } }
    var tetraCount = 9
    var surface = false { didSet { if surface != oldValue { reshape() } } }
    var company = false
    var colourEvery: Time = 8 { didSet { bettas.forEach { $0.setColourEvery($0.profile.colours.every ?? colourEvery) } } }

    private(set) var bettas: [Betta] = []
    private(set) var areas: [Area] = []
    /// which screens can be seen (empty: all): a fish only on screens covered by windows is not drawn
    var seen: [Bool] = []

    // the fish's layer: one character and one colour per cell, and how near the fish is there
    private(set) var cols = 0, rows = 0
    private(set) var originX: R = 0, originY: R = 0     // where the water's middle is: the main screen's
    let char = Buf<Int16>(0), col = Buf<V3>(.zero)
    private let dep = Buf<R>(.infinity), best = Buf<Int32>(-1), cover = Buf<R>(0)
    private var hash = [Int]()

    // the scenery's layer
    private(set) var scols = 0, srows = 0
    let schar = Buf<Int16>(0), scol = Buf<V3>(.zero)
    private var shash = [Int]()
    private struct Scenery {
        var r: Region
        var setting: Setting
        var bubbles: [[Double]]
        var tetras: [[Double]]
    }
    private var scenes = [Scenery]()
    /// where a fish can hide, in the water
    private(set) var hideouts: [P2] = []

    // every point the fish placed this frame
    let points = Points()

    // what has happened in the water
    struct Pellet { var x: Double; var y0: Double; var floor: Double; var t0: Time; var phase: Double; var eaten = false }
    var pellets = [Pellet]()
    private var ripples = [(x: Double, t0: Time, k: Double)]()
    private var taps = [(p: P2, t0: Time)]()
    private var rng: SplitMix
    private(set) var lastT: Time = 0
    private var mindsAt: Time = -1e9, rivalsAt: Time = -1e9

    init(layout: Layout, seed: UInt64 = 1, fish: Int = 1, bubbles: Bool = true) {
        self.seed = seed
        self.layout = layout
        withBubbles = bubbles
        rng = SplitMix(seed, 7)
        relayout(layout)
        // fish of its own, for the tools: one grown up, the rest new to the tank
        var r = SplitMix(seed, 11)
        setFish((0..<fish).map { i in
            var p = FishProfile(name: "Fish \(i + 1)", seed: seed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15, born: Date(),
                                personality: i == 0 ? Personality() : .random(&r))
            p.fixedAge = Settings.shared.adultDays + 1                  // grown up, and not old
            return p
        }, minds: [:])
    }

    /// the screens changed, or the fish size: everything on the new grids, the fish carrying on where they were
    func relayout(_ layout: Layout) {
        self.layout = layout
        let f = layout.fish, s = layout.scenery, main = layout.screens[0]
        cols = f.cols; rows = f.rows
        originX = R((main.midX - layout.world.minX) / f.cellW)
        originY = R((layout.world.maxY - main.midY) / f.cellH)
        for b in [dep, cover] { b.resize(cols * rows) }
        char.resize(cols * rows); col.resize(cols * rows); best.resize(cols * rows)
        let c = cols
        hash = (0..<rows * cols).map { ((($0 / c) * 7919 + ($0 % c) * 104729) % 9973) }

        scols = s.cols; srows = s.rows
        schar.resize(scols * srows); scol.resize(scols * srows)
        let sc = scols
        shash = (0..<srows * scols).map { ((($0 / sc) * 7919 + ($0 % sc) * 104729) % 9973) }
        arrangeScenery()
        reshape()
        version += 1
    }

    /// each screen's own arrangement of what is in the water
    private func arrangeScenery() {
        scenes = layout.scenery.regions.enumerated().map { i, r in
            // as many bubbles in the water as the original had for its window, for the room there is; a
            // small school of neon tetras; and the environment, laid out for this screen
            var water = SplitMix(seed, 2, UInt64(i))
            let count = withBubbles ? Int((70.0 * bubbleAmount * Double(r.cols * r.rows) / Double(113 * 103)).rounded()) : 0
            let bubbles = (0..<count).map { _ in (0..<5).map { _ in water.unit() } }
            let tetras = (0..<60).map { _ in (0..<6).map { _ in water.unit() } }
            var build = SplitMix(seed, 3, UInt64(i))
            let setting = environment?.build(r.cols, r.rows, &build) ?? Setting()
            return Scenery(r: r, setting: setting, bubbles: bubbles, tetras: tetras)
        }
        hideouts = scenes.flatMap { s in s.setting.cover.map { waterOfScenery(Double(s.r.x0) + $0.x, Double(s.r.y0) + $0.y) } }
    }

    /// where the fish may go, now that the screens, the sand or the surface changed
    private func reshape() {
        let su = layout.scenery.cellH / layout.fish.cellH * Water.depth / Double(Water.scaleY)   // a scenery row, in the water
        areas = layout.screens.map { f in
            let lo = water(CGPoint(x: f.minX, y: f.minY)), hi = water(CGPoint(x: f.maxX, y: f.maxY))
            var a = Area(xs: 0...0, ys: 0...0)
            a.left = lo.x; a.right = hi.x; a.bottom = lo.y; a.top = hi.y
            a.surface = surface ? hi.y - (Double(SURFACE_ROW) + 0.5) * su : hi.y
            let x0 = lo.x + Water.marginX, x1 = hi.x - Water.marginX
            a.xs = x0 <= x1 ? x0...x1 : (lo.x + hi.x) / 2...(lo.x + hi.x) / 2
            let y0 = lo.y + Water.marginDown + Double(environment?.floor ?? 0) * su, y1 = a.surface - Water.marginUp
            a.ys = y0 <= y1 ? y0...y1 : (lo.y + hi.y) / 2...(lo.y + hi.y) / 2
            a.gulpY = surface ? a.surface - Water.mouthRise : a.ys.upperBound + 0.25
            a.floor = a.ys.lowerBound + 0.12
            return a
        }
        bettas.forEach { $0.motion.bound(areas) }
    }

    // MARK: where things are

    /// a point of the screens (y up) in the water
    func water(_ p: CGPoint) -> P2 {
        let f = layout.fish, w = layout.world
        let cx = (p.x - w.minX) / f.cellW, cy = (w.maxY - p.y) / f.cellH
        return P2((cx - Double(originX)) * Water.depth / Double(Water.scaleX),
                  -(cy - Double(originY)) * Water.depth / Double(Water.scaleY))
    }

    /// a point of the water on the screens (y up)
    func screenPoint(_ q: P2) -> CGPoint {
        let f = layout.fish, w = layout.world
        let cx = q.x * Double(Water.scaleX) / Water.depth + Double(originX), cy = Double(originY) - q.y * Double(Water.scaleY) / Water.depth
        return CGPoint(x: cx * f.cellW + w.minX, y: w.maxY - cy * f.cellH)
    }

    /// the same, if it is on one of the tank's screens (and which)
    func water(at p: CGPoint) -> (p: P2, screen: Int)? {
        guard let i = layout.screens.firstIndex(where: { $0.contains(p) }) else { return nil }
        return (water(p), i)
    }

    /// a cell of the scenery's grid in the water
    private func waterOfScenery(_ x: Double, _ y: Double) -> P2 {
        let fx = x * layout.scenery.cellW / layout.fish.cellW, fy = y * layout.scenery.cellH / layout.fish.cellH
        return P2((fx - Double(originX)) * Water.depth / Double(Water.scaleX), -(fy - Double(originY)) * Water.depth / Double(Water.scaleY))
    }

    /// a point of the water on the fish's grid (as the camera would place it, near enough)
    @inline(__always) private func fishCell(_ p: P2) -> (R, R) {
        (originX + R(p.x) * Water.scaleX / R(Water.depth), originY - R(p.y) * Water.scaleY / R(Water.depth))
    }

    /// and on the scenery's
    private func sceneryCell(_ p: P2) -> (Double, Double) {
        let (x, y) = fishCell(p)
        return (Double(x) * layout.fish.cellW / layout.scenery.cellW, Double(y) * layout.fish.cellH / layout.scenery.cellH)
    }

    /// whether a fish with its middle at p would show on a screen that can be seen
    func shows(_ p: P2) -> Bool {
        guard seen.contains(false) else { return true }
        for (i, a) in areas.enumerated() where i < seen.count && seen[i] {
            if p.x + 1.4 > a.left && p.x - 1.4 < a.right && p.y + 1.1 > a.bottom && p.y - 1.1 < a.top { return true }
        }
        return false
    }

    // MARK: the fish

    /// these fish (as they are now): new ones draw themselves wherever there is room, one after another;
    /// the ones that are no longer here leave
    func setFish(_ profiles: [FishProfile], minds: [String: FishMind]) {
        let ids = Set(profiles.map(\.id))
        bettas.removeAll { !ids.contains($0.id) }
        var k = 0
        for (i, p) in profiles.prefix(MAX_FISH).enumerated() {
            if let b = bettas.first(where: { $0.id == p.id }) {
                let wasColours = b.profile.colours
                b.profile = p
                if p.colours != wasColours { b.recolour() }
                continue
            }
            let first = bettas.isEmpty && lastT == 0
            let start = first ? clampStart(.zero) : room()
            let born = first ? 0 : lastT + 0.4 + 1.3 * Double(k)
            let allowed = allowedFor(p)
            let b = Betta(index: i, profile: p, mind: minds[p.id] ?? FishMind(Memory()),
                          motion: Motion(seed: p.seed, areas: areas, start: start), born: born,
                          points: points, colourEvery: p.colours.every ?? colourEvery, allowed: allowed())
            b.allowedPalettes = allowed
            bettas.insert(b, at: min(i, bettas.count))
            k += 1
        }
        // in the order given
        bettas.sort { a, b in (profiles.firstIndex { $0.id == a.id } ?? 0) < (profiles.firstIndex { $0.id == b.id } ?? 0) }
        for (i, b) in bettas.enumerated() {
            b.setIndex(i)
            b.allowedPalettes = allowedFor(b.profile)
            b.setColourEvery(b.profile.colours.every ?? colourEvery)
        }
        mindsAt = -1e9
    }

    /// the sets a fish may wear: its own choice, or the tank's
    var allowedFor: (FishProfile) -> () -> [Int] = { _ in { Array(0..<PALETTES.count) } }

    private func clampStart(_ p: P2) -> P2 {
        guard let a = areas.first else { return p }
        return P2(min(max(p.x, a.xs.lowerBound), a.xs.upperBound), min(max(p.y, a.ys.lowerBound), a.ys.upperBound))
    }

    /// somewhere in the water well away from the other fish
    private func room() -> P2 {
        var best = P2.zero, bestD = -1.0
        for _ in 0..<16 {
            let a = areas[Int(rng.next() % UInt64(areas.count))]
            let p = P2(rng.range(a.xs.lowerBound, a.xs.upperBound), rng.range(a.ys.lowerBound, a.ys.upperBound))
            let d = bettas.map { simd_length($0.anchor - p) }.min() ?? 9
            if d > bestD { bestD = d; best = p }
        }
        return best
    }

    /// drop a few pellets near each fish, from the top
    func feed(pellets per: Int? = nil) {
        let t = lastT
        let n = per ?? (bettas.count == 1 ? 5 : 4)
        let now = surroundings.now
        for b in bettas { b.mind.fed(now, b.profile, trustSpeed: surroundings.trustSpeed) }
        for b in bettas where b.alive {
            let a = areas[b.motion.area(b.anchor)]
            let here = b.anchor.x
            for i in 0..<n {
                let x = min(max(here + rng.range(-0.8, 0.8), a.left + 0.15), a.right - 0.15)
                let t0 = t + Double(i) * 0.35
                pellets.append(Pellet(x: x, y0: a.surface - 0.04, floor: a.floor, t0: t0, phase: rng.range(0, 6.3)))
                if surface { ripples.append((x, t0, 0.5)) }
            }
        }
    }

    func pelletAt(_ p: Pellet, _ t: Time) -> P2 {
        P2(p.x + 0.035 * sin(1.1 * (t - p.t0) + p.phase), max(p.floor, p.y0 - 0.09 * (t - p.t0)))
    }

    /// something broke the surface here (a gulp of air)
    func ripple(at x: Double, _ t: Time) {
        if surface { ripples.append((x, t, 1)) }
    }

    /// a tap on the glass of one screen: every fish on that screen takes fright, and one of them comes
    /// back a little later to see what it was
    func tap(at p: P2, screen: Int) {
        taps.append((p, lastT))
        let near = bettas.filter { $0.swimming && $0.motion.area($0.anchor) == screen }
        guard !near.isEmpty else { return }
        for b in near {
            b.startle(from: p)
            if surroundings.memory { b.mind.tapped(p, surroundings.now, b.profile) }
        }
        // the boldest is likeliest to come back and look
        let w = near.map { 0.2 + $0.profile.personality.bold }
        var r = rng.unit() * w.reduce(0, +), pick = near[0]
        for (b, x) in zip(near, w) { r -= x; if r < 0 { pick = b; break } }
        pick.inspect(p, at: lastT + rng.range(4, 7) + 4 * (1 - pick.profile.personality.bold))
        mindsAt = -1e9
    }

    /// you came back to the Mac: the fish that know you come to the front of the glass to see
    func greet() {
        for b in bettas where b.swimming && b.motion.mood.night < 0.5 {
            let p = b.profile.personality
            let keen = 0.3 * p.bold + 0.7 * (surroundings.memory ? b.mind.memory.trust : 0.3)
            guard keen > 0.32 else { continue }
            let a = areas[b.motion.area(b.anchor)]
            let x = min(max(b.anchor.x * 0.5 + (a.xs.lowerBound + a.xs.upperBound) * 0.25 + rng.range(-0.5, 0.5), a.xs.lowerBound), a.xs.upperBound)
            let y = a.ys.lowerBound + (a.ys.upperBound - a.ys.lowerBound) * rng.range(0.45, 0.7)
            b.greet(P2(x, y))
            b.mind.excitedUntil = surroundings.now.addingTimeInterval(120)
            Life.shared.logNow(b.id, kind: "greet", every: 6 * 3600, "\(b.profile.name) came to the glass to say hello when you came back.")
        }
        mindsAt = -1e9
    }

    // MARK: what goes on in their heads (once a second)

    /// each fish's mood from what has happened to it, and from that and its personality and age how it
    /// goes about things and how it looks
    private func minds() {
        let s = surroundings, now = s.now, life = Life.shared, settings = Settings.shared
        for b in bettas {
            let p = b.profile, m = b.mind, P = p.personality
            let stage = life.stage(p, settings, now), g = life.growth(p, settings, now)
            let stress = s.memory ? m.stress(now, bold: P.bold) : 0
            let expecting = s.memory && !s.mood.hungry && m.expectsFood(now, lastFed: s.lastFed)
            var mood = MoodName.content
            if s.mood.night > 0.5 { mood = .sleepy }
            else if s.moods && stress > 0.55 { mood = .stressed }
            else if s.mood.hungry { mood = .hungry }
            else if s.moods && now < m.excitedUntil { mood = .excited }
            else if expecting { mood = .expecting }
            else if s.moods && now < m.curiousUntil { mood = .curious }
            else if s.moods && now.timeIntervalSince(m.memory.attention) > s.boredAfter * 3600 { mood = .bored }
            if mood != m.mood {
                if mood == .stressed { life.logNow(b.id, kind: "stressed", every: 6 * 3600, "\(p.name) got upset and went to hide.") }
                if mood == .bored { life.logNow(b.id, kind: "bored", every: 12 * 3600, "\(p.name) is bored, swimming up and down the glass.") }
                if mood == .expecting { life.logNow(b.id, kind: "expecting", every: 10 * 3600, "\(p.name) is waiting at the top: it is about feeding time.") }
            }
            m.mood = mood

            var md = s.mood
            md.expecting = expecting
            md.excited = mood == .excited
            md.stressed = mood == .stressed
            md.bored = mood == .bored
            b.motion.mood = md

            let juvenile = stage == .juvenile
            var tr = Traits()
            tr.speed = (0.8 + 0.4 * P.active) * g.slow * (juvenile ? 1.1 : 1)
            tr.rest = (1.4 - 0.8 * P.active) / g.slow
            tr.flare = (0.4 + 1.2 * P.showOff) * (juvenile ? 0.15 : 1)
            tr.nest = (0.3 + 1.4 * P.builder) * (juvenile ? 0 : stage == .young ? 0.5 : 1)
            tr.flee = (1.25 - 0.5 * P.bold) * (juvenile ? 1.15 : 1)
            tr.favourite = s.memory ? m.favourite : nil
            tr.grudges = s.memory ? m.grudges(now, bold: P.bold) : []
            tr.cover = hideouts
            b.motion.traits = tr

            var L = Looks(size: g.size, fins: g.fins, colour: g.colour, bright: 1, stripes: 0)
            if s.moods {
                switch mood {
                case .excited: L.colour *= 1.15; L.bright = 1.08; L.fins *= 1.04
                case .sleepy: L.colour *= 0.72; L.bright = 0.86; L.fins *= 0.93
                case .stressed: L.colour *= 0.78; L.stripes = min(stress, 1); L.fins *= 0.86
                case .hungry: L.colour *= 0.9
                case .bored: L.colour *= 0.94
                default: break
                }
            }
            b.targetLooks = L

            // milestones for the diary
            if stage >= .young { life.milestone(b.id, "stage1", "\(p.name) has grown into a young adult: longer fins, and its colours are coming in.") }
            if stage >= .adult { life.milestone(b.id, "stage2", "\(p.name) is all grown up, in full fin and colour.") }
            if stage >= .old { life.milestone(b.id, "stage3", "\(p.name) is getting old: a little slower, its colours softer.") }
            if s.memory && m.memory.trust >= 0.45 { life.milestone(b.id, "trust1", "\(p.name) has started coming over to see the cursor.") }
            if s.memory && m.memory.trust >= 0.72 { life.milestone(b.id, "trust2", "\(p.name) follows the cursor around now: it knows you.") }
            if b.nestSize > 0 { life.milestone(b.id, "nest", "\(p.name) blew its first bubble nest.") }
            if b.nestSize >= 25 && b.nestSize > m.memory.nestRecord + 5 {
                m.memory.nestRecord = b.nestSize
                life.logNow(b.id, kind: "nestRecord", every: 86400, "\(p.name) built its biggest bubble nest yet (\(b.nestSize) bubbles).")
            }
        }
    }

    /// a fish near its home flares at another that comes too close, and the other backs off, unless they
    /// have long got used to each other
    private func rivals(_ t: Time) {
        let now = surroundings.now, life = Life.shared
        for a in bettas where a.swimming && t - a.confrontedAt > 25 && a.motion.mood.night < 0.5 && !a.motion.mood.stressed {
            guard life.stage(a.profile) >= .young, let home = a.mind.favourite ?? a.motion.nest,
                  simd_length(a.anchor - home) < 1.8 else { continue }
            for b in bettas where b !== a && b.swimming {
                let near = simd_length(b.anchor - home), apart = simd_length(b.anchor - a.anchor)
                guard near < 1.3, apart < 2.2, t - b.confrontedAt > 4 else { continue }
                let together = now.timeIntervalSince(max(a.profile.joined, b.profile.joined)) / 86400
                let used = min(max(together / surroundings.toleranceDays, 0), 1)
                if used >= 1 { life.milestone(a.id, "peace-\(b.id)", "\(a.profile.name) and \(b.profile.name) have got used to each other.") }
                let P = a.profile.personality
                let chance = 0.3 * (0.5 + P.showOff) * (0.5 + P.bold) * (1 - 0.85 * used)
                guard rng.unit() < chance else { a.confrontedAt = max(a.confrontedAt, t - 20); continue }
                a.confront(b.anchor, t)
                // a bold one flares back first, then gives way
                if rng.unit() < 0.5 * b.profile.personality.bold * (1 - used) {
                    b.confront(a.anchor, t)
                    b.backOff(from: home, at: t + 3.2)
                } else {
                    b.backOff(from: home, at: t + 0.9)
                }
                life.logNow(a.id, kind: "rival-\(b.id)", every: 12 * 3600, "\(a.profile.name) flared at \(b.profile.name) for coming too near its home.")
                break
            }
        }
    }

    // MARK: frame()

    func frame(_ t: Time) {
        let dt = t - lastT
        lastT = t
        let s = surroundings
        if t - mindsAt > 1 { mindsAt = t; minds() }
        if s.territory && bettas.count > 1 && t - rivalsAt > 0.5 { rivalsAt = t; rivals(t) }
        if surface && s.rain > 0 && dt > 0 && dt < 1 {
            // rain on the surface
            for a in areas where rng.unit() < s.rain * dt * 6 * (a.right - a.left) / 4 {
                ripples.append((rng.range(a.left, a.right), t, 0.3 + 0.2 * rng.unit()))
            }
        }
        points.removeAll()
        if bettas.count > 1 {
            let at = bettas.map { $0.anchor }
            for (i, b) in bettas.enumerated() { b.motion.others = at.enumerated().filter { $0.offset != i }.map(\.element) }
        }
        for b in bettas { b.place(t, s, in: self) }
        bodies(t)
        for b in bettas { b.bubbles(in: self) }
        pellets.removeAll { $0.eaten || t - $0.t0 > ($0.y0 - $0.floor) / 0.09 + 25 }
        food(t)
        for b in bettas { b.flare(in: self) }
        scenery(t)
    }

    // MARK: bodies(): nearest point per cell, outlines, letters by brightness

    private func bodies(_ t: Time) {
        best.fill(-1); cover.fill(0); dep.fill(.infinity); char.fill(0); col.fill(.zero)
        let fc = R(cols), fr = R(rows), cols = self.cols, rows = self.rows
        let P = points
        let X = P.SX.p, Y = P.SY.p, ZZ = P.Z.p, A = P.AREA.p, PRT = P.PRT.p, SRC = P.SRC.p
        let B = best.p, CV = cover.p, D = dep.p
        // only round each fish, one at a time
        var boxes = [(x0: Int, x1: Int, y0: Int, y1: Int)]()
        for b in bettas where b.pointsTo > b.pointsFrom {
            var x0 = cols, x1 = -1, y0 = rows, y1 = -1
            for i in b.pointsFrom..<b.pointsTo {
                let x = X[i], y = Y[i], z = ZZ[i]
                guard x >= 0, x < fc, y >= 0, y < fr, z > 0.3 else { continue }
                let ix = Int(x), iy = Int(y)
                let c = iy * cols + ix
                CV[c] += A[i]
                if z <= D[c] { D[c] = z; B[c] = Int32(i) }
                x0 = min(x0, ix); x1 = max(x1, ix); y0 = min(y0, iy); y1 = max(y1, iy)
            }
            if x1 >= 0 { boxes.append((x0, x1, y0, y1)) }
        }
        let tick = t * 4
        let fill = self.fill
        let bettas = self.bettas
        for (k, box) in boxes.enumerated() {
          // where it overlaps a box already done, those cells are done
          let earlier = boxes[0..<k].filter { $0.x0 <= box.x1 && box.x0 <= $0.x1 && $0.y0 <= box.y1 && box.y0 <= $0.y1 }
          for y in box.y0...box.y1 {
            for x in box.x0...box.x1 {
                let c = y * cols + x
                let gi = Int(B[c])
                if gi < 0 { continue }
                if !earlier.isEmpty && earlier.contains(where: { x >= $0.x0 && x <= $0.x1 && y >= $0.y0 && y <= $0.y1 }) { continue }
                let prt = PRT[gi], d = ZZ[gi]
                let src = SRC[gi]
                let (lum, rgb, own) = bettas[Int(src >> 27)].shade(Int((src >> 24) & 7), Int(src & 0xFF_FFFF))
                var gx = 0, gy = 0, edge = false
                if own < 0 {
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let ny = y + dy, nx = x + dx
                            var nb: Int8 = -1, nz: R = .infinity
                            if ny >= 0 && ny < rows && nx >= 0 && nx < cols {
                                let j = Int(B[ny * cols + nx])
                                if j >= 0 { nb = PRT[j]; nz = ZZ[j] }
                            }
                            let other = nb >= 0 && nb != prt
                            let seam = other && prt % PARTS != MARK && nb % PARTS != MARK && prt / PARTS == nb / PARTS && prt < nb
                            if nb < 0 || (other && nz > d + 0.035) || seam {
                                gx += dx; gy += dy
                                if dx == 0 || dy == 0 { edge = true }
                            }
                        }
                    }
                }
                let h = hash[c]
                let level = min(max(Int((lum - 0.42) * 4.6), 0), 3)
                let inside = fill[level * 12 + (h + Int(tick + Double(h % 11))) % 12]
                char[c] = own >= 0 ? own : (edge ? outlineLetter(gx, gy) : inside)
                var bright = own >= 0 ? lum : (edge ? max(0.85, lum) : clamp(0.45 + 0.55 * lum / 0.9, 0.45, 1.0))
                if own < 0 { bright *= 0.30 + 0.70 * pow(min(CV[c], 1), 0.7) }
                col[c] = rgb * min(bright, 1.4)
            }
          }
        }
    }

    // MARK: lights in the fish's layer

    /// dots at points already placed on the fish's grid: hidden where a fish is in front of them; the
    /// brightest drawn last
    func dots(_ at: [(R, R, R)], _ glyph: [Int16], _ rgb: [V3], _ k: [R]) {
        var ok = [(Int, Int)]()
        for i in 0..<at.count where k[i] > 0.05 {
            let (x, y, z) = at[i]
            guard x >= 0, x < R(cols), y >= 0, y < R(rows) else { continue }
            let c = Int(y) * cols + Int(x)
            if z < dep[c] { ok.append((i, c)) }
        }
        ok.sort { k[$0.0] < k[$1.0] }
        for (i, c) in ok { char[c] = glyph[i]; col[c] = rgb[i] * k[i] }
    }

    private func put(_ y: Int, _ x: Int, _ ch: Unicode.Scalar, _ rgb: V3) {
        if y >= 0 && y < rows && x >= 0 && x < cols { char[y * cols + x] = C(ch); col[y * cols + x] = rgb }
    }

    /// a flare at a point placed on the fish's grid, unless a fish is in front of it
    func flare(_ x: R, _ y: R, _ z: R, _ f: Flare) {
        guard y > -1, y < R(rows), x > -1, x < R(cols) else { return }
        let iy = Int(y), ix = Int(x)
        if f.always || z <= dep[iy * cols + ix] + 0.08 { rays(iy, ix, f.reach, f.rgb, f.strength) }
    }

    private func rays(_ cy: Int, _ cx: Int, _ reach: Int, _ rgb: V3, _ strength: R) {
        // a four-pointed flare: long arms sideways and up/down, short diagonals
        if reach >= 1 {
            for dist in 1...reach {
                let fade = (1 - R(dist) / R(reach + 1)) * strength
                var arms: [(Int, Int, Unicode.Scalar)] = [(0, 1, "-"), (0, -1, "-"), (1, 0, "|"), (-1, 0, "|")]
                if dist <= reach / 2 { arms += [(1, 1, "\\"), (-1, -1, "\\"), (1, -1, "/"), (-1, 1, "/")] }
                for (dy, dx, ch) in arms {
                    let yy = cy + dy * dist, xx = cx + dx * dist * (dy == 0 ? 2 : 1)
                    let k = fade * (dx != 0 && dy != 0 ? 0.7 : 1.0)
                    if yy >= 0 && yy < rows && xx >= 0 && xx < cols && col[yy * cols + xx].max() < k {
                        char[yy * cols + xx] = C(ch); col[yy * cols + xx] = rgb * k
                    }
                }
            }
        }
        put(cy, cx, "*", rgb * (1.3 * strength))
    }

    private func food(_ t: Time) {
        let shown = pellets.filter { t >= $0.t0 }
        guard !shown.isEmpty else { return }
        let ink = V3(0.85, 0.55, 0.25)
        let at = shown.map { q -> (R, R, R) in let (x, y) = fishCell(pelletAt(q, t)); return (x, y, R(Water.depth)) }
        let fade = shown.map { q -> R in R(1 - smoothD((t - q.t0 - (q.y0 - q.floor) / 0.09 - 20) / 5)) }
        dots(at, shown.map { _ in C("*") }, shown.map { _ in ink }, fade.map { 0.9 * $0 })
    }

    // MARK: the scenery's layer

    /// a letter where the scenery is still empty (the first drawn is in front)
    @inline(__always) private func behind(_ y: Int, _ x: Int, _ g: Int16, _ rgb: V3) {
        guard y >= 0 && y < srows && x >= 0 && x < scols else { return }
        let c = y * scols + x
        if schar[c] == 0 { schar[c] = g; scol[c] = rgb }
    }

    private func scenery(_ t: Time) {
        schar.fill(0); scol.fill(.zero)
        glass(t)
        for s in scenes {
            if surface { waterline(s, t) }
            if environment != nil { seabed(s, t) }
            bubbles(s, t)
            if company { tetras(s, t) }
        }
    }

    private func glass(_ t: Time) {
        // a tap on the glass: a ring spreading from where it landed, gone in a moment
        taps.removeAll { t - $0.t0 > 1 }
        for tap in taps {
            let age = t - tap.t0
            guard age >= 0, age < 0.7 else { continue }
            let (cx, cy) = sceneryCell(tap.p)
            let radius = 1.0 + age * 16, fade = R(1 - age / 0.7)
            let n = 12 + Int(radius * 3)
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi
                behind(Int(cy + sin(a) * radius), Int(cx + cos(a) * radius * Double(Water.cellAspect)),
                       age < 0.25 ? C("o") : C("."), pale(BUBBLE, 0.6) * (0.75 * fade))
            }
            if age < 0.15 { behind(Int(cy), Int(cx), C("*"), WHITE) }
        }
    }

    private func waterline(_ s: Scenery, _ t: Time) {
        // the surface: a line of water rippling gently, and rings running out from where it was broken
        let r = s.r, y = r.y0 + SURFACE_ROW
        ripples.removeAll { t - $0.t0 > 4 }
        let fronts = ripples.compactMap { rp -> (x: Double, age: Double, k: Double)? in
            let age = t - rp.t0
            guard age >= 0 else { return nil }
            let (x, _) = sceneryCell(P2(rp.x, 0))
            return x >= Double(r.x0) - 40 && x <= Double(r.x0 + r.cols) + 40 ? (x, age, rp.k) : nil
        }
        for i in 0..<r.cols {
            let x = Double(r.x0 + i)
            let w = sin(x * 0.29 + t * 0.9) + 0.6 * sin(x * 0.11 - t * 0.55 + 1.3)
            var g = w > 1.0 ? C("~") : (w < -1.1 ? C("_") : C("-"))
            var k = R(0.42 + 0.08 * w)
            for f in fronts {
                let d = abs(abs(x - f.x) - f.age * 15), amp = R(f.k * exp(-f.age * 1.1))
                if d < 2.5 {
                    k += 0.55 * amp * R(1 - d / 2.5)
                    if amp > 0.2 { g = d < 1 ? C("^") : C("~") }
                }
            }
            behind(y, r.x0 + i, g, V3(0.55, 0.78, 1.0) * k)
        }
        // a few drops thrown up where it was broken
        for f in fronts where f.age < 0.45 && f.k >= 1 {
            let up = Int(f.age * 9)
            for (dx, dy) in [(-2, 1), (0, 2), (2, 1)] {
                behind(y - dy - up / 2, Int(f.x) + dx * (1 + up / 2), C("'"), pale(BUBBLE, 0.5) * R(0.8 - f.age))
            }
        }
    }

    private func seabed(_ s: Scenery, _ t: Time) {
        // the environment: plants swaying in the current, in front of what stands still
        let r = s.r, bottom = r.y0 + r.rows - 1, ground = s.setting.ground
        for plant in s.setting.plants {
            let floor = bottom - (ground.isEmpty ? 0 : ground[min(max(plant.x, 0), r.cols - 1)])
            // a clump of strands, each its own height, swaying a little out of step with the others
            let strands = plant.strands
            for k in 0..<strands {
                let height = Int(Double(plant.height) * (0.55 + 0.45 * fracD(plant.phase * Double(k + 3) * 1.7)))
                let root = r.x0 + plant.x + (k * 2 - strands + 1)
                for j in 0..<height {
                    let up = Double(j) / Double(max(height, 1))
                    let wave = t * 0.6 + plant.phase + Double(k) * 0.9 + Double(j) * 0.25
                    let sway = plant.sway * sin(wave) * pow(up, 1.3)
                    let g: Int16
                    switch plant.style {
                    case 1: g = [C("%"), C("&"), C("*"), C("\"")][(j + k) % 4]                        // moss
                    case 2: g = j == height - 1 ? C("o") : (j % 3 == 2 ? (cos(wave) > 0 ? C(">") : C("<")) : C("|"))   // ribbon
                    default: g = j == height - 1 ? C("'") : (cos(wave) > 0 ? C(")") : C("("))         // grass
                    }
                    behind(ground.isEmpty ? floor - j : floor - j, root + Int(sway.rounded()), g, plant.colour * R(0.38 + 0.42 * up))
                }
            }
        }
        for c in s.setting.cells { behind(r.y0 + c.y, r.x0 + c.x, c.g, c.rgb) }
    }

    private func bubbles(_ s: Scenery, _ t: Time) {
        // bubbles rising through the water (and gone at the surface)
        let r = s.r, top = surface ? SURFACE_ROW + 1 : 0, h = max(r.rows - top, 1)
        let glyphs: [Int16] = [C("."), C("."), C("."), C("o"), C("O")]
        for b in s.bubbles {
            let size = b[4]
            let ix = r.x0 + min(Int(fracD(b[0] + 0.012 * sin(t * (1 + 2 * b[2]) + b[3] * 40)) * Double(r.cols)), r.cols - 1)
            let iy = r.y0 + top + min(Int(fracD(b[1] - t * (0.02 + 0.06 * size)) * Double(h)), h - 1)
            let tw = 0.6 + 0.4 * sin(t * (0.8 + 2.4 * b[2]) + b[3] * 40)
            behind(iy, ix, glyphs[min(max(Int(size * 5), 0), 4)], BUBBLE * R((0.14 + 0.36 * size) * tw))
        }
    }

    private func tetras(_ s: Scenery, _ t: Time) {
        // a small school of neon tetras far behind, drifting about the screen together
        let r = s.r, phase = Double(r.x0) * 0.01
        func centre(_ t: Time) -> P2 {
            P2(Double(r.x0) + Double(r.cols) * (0.5 + 0.36 * sin(t * 0.021 + 1.3 + phase) * cos(t * 0.013 + 0.4)),
               Double(r.y0) + Double(r.rows) * (0.42 + 0.26 * sin(t * 0.017 + 2.1 + phase)))
        }
        for f in s.tetras.prefix(tetraCount) {
            func at(_ t: Time) -> P2 {
                centre(t) + P2(10 * (f[0] - 0.5) + 6 * sin(t * (0.3 + 0.2 * f[2]) + 6 * f[3]),
                               5 * (f[1] - 0.5) + 2.5 * cos(t * (0.25 + 0.2 * f[4]) + 6 * f[5]))
            }
            let p = at(t), ahead = at(t + 0.3)
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            let red = V3(0.95, 0.25, 0.35) * 0.65, neon = V3(0.25, 0.75, 1.0) * 0.75, head = V3(0.55, 0.9, 1.0) * 0.75
            if ahead.x >= p.x {                                 // ><> swimming right
                behind(y, x - 1, C(">"), red); behind(y, x, C("<"), neon); behind(y, x + 1, C(">"), head)
            } else {                                            // <>< swimming left
                behind(y, x - 1, C("<"), head); behind(y, x, C(">"), neon); behind(y, x + 1, C("<"), red)
            }
        }
    }

    // MARK: for checking

    /// whether any of a fish was off every screen this frame
    func offScreen() -> Bool {
        let regions = layout.fish.regions
        for i in 0..<points.count {
            let x = Int(floor(points.SX[i])), y = Int(floor(points.SY[i]))
            if !regions.contains(where: { x >= $0.x0 && x < $0.x0 + $0.cols && y >= $0.y0 && y < $0.y0 + $0.rows }) { return true }
        }
        return false
    }
}
