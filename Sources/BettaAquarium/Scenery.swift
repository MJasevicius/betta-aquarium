// What is on the bottom of the tank: a choice of environments, each made of letters on the scenery's
// layer (the one that keeps its size whatever the fish size). Each screen gets its own arrangement of
// it, made once when the screens are laid out: what stands still is worked out then and only copied
// each frame; only the plants sway.

import Foundation
import simd

/// a letter of the scenery, in a screen's own cells (0, 0 top left)
struct SceneCell { var x: Int, y: Int, g: Int16, rgb: V3 }

/// a clump of plant swaying in the current
struct Plant {
    var x: Int, height: Int, phase: Double, colour: V3
    var strands = 3
    var style = 0                           // 0 grass, 1 a tuft of moss, 2 a ribbon of leaves
    var sway = 2.4
}

/// one screen's arrangement of an environment
struct Setting {
    var ground: [Int] = []                  // rows of floor in each column
    var cells: [SceneCell] = []             // what stands still, front first
    var plants: [Plant] = []
    var cover: [(x: Double, y: Double)] = []    // cells where a fish can hide
}

struct Environment {
    let id: String, name: String, about: String
    let floor: Int                          // rows of the bottom the fish keep above
    let tint: V3                            // the water's colour (1, 1, 1: clear)
    let build: (_ cols: Int, _ rows: Int, _ rng: inout SplitMix) -> Setting
}

/// where letters go while an arrangement is made: the first put in a cell stays (so front first)
private struct Canvas {
    let cols: Int, rows: Int
    private var taken = Set<Int>()
    private(set) var cells: [SceneCell] = []
    init(_ cols: Int, _ rows: Int) { self.cols = cols; self.rows = rows }

    mutating func put(_ x: Int, _ y: Int, _ g: Unicode.Scalar, _ rgb: V3) {
        guard x >= 0, x < cols, y >= 0, y < rows, taken.insert(y * cols + x).inserted else { return }
        cells.append(SceneCell(x: x, y: y, g: C(g), rgb: rgb))
    }
    func has(_ x: Int, _ y: Int) -> Bool { taken.contains(y * cols + x) }
}

@inline(__always) private func hash2(_ x: Int, _ y: Int, _ s: Int = 0) -> Int {
    var h = UInt64(bitPattern: Int64(x &* 73856093 ^ y &* 19349663 ^ s &* 83492791))
    h = (h ^ (h >> 31)) &* 0x9E37_79B9_7F4A_7C15
    return Int(truncatingIfNeeded: (h ^ (h >> 29)) & 0x7FFF_FFFF)
}

/// long low dunes: rows of floor in each column, between lo and hi
private func dunes(_ cols: Int, _ lo: Int, _ hi: Int, _ rng: inout SplitMix) -> [Int] {
    let s1 = rng.range(0, 6), s2 = rng.range(0, 6), span = Double(hi - lo) + 0.99
    return (0..<cols).map { x in lo + Int(span * (0.5 + 0.25 * (sin(Double(x) * 0.07 + s1) + sin(Double(x) * 0.031 + s2)))) }
}

/// a floor of grains along the bottom
private func floor(_ c: inout Canvas, _ ground: [Int], grains: [Unicode.Scalar], colour: V3, seed: Int = 0) {
    for x in 0..<c.cols {
        for k in 0..<ground[x] {
            let y = c.rows - 1 - k, h = hash2(x, y, seed)
            c.put(x, y, grains[h % grains.count], colour * (0.30 + 0.14 * R(k) + 0.10 * R(h % 3)))
        }
    }
}

/// clumps of plants rooted here and there
private func plants(_ n: Int, _ cols: Int, _ rows: Int, _ rng: inout SplitMix, tall: ClosedRange<Double> = 0.08...0.21,
                    colours: (V3, V3) = (V3(0.20, 0.70, 0.34), V3(0.12, 0.62, 0.58)), style: Int = 0) -> [Plant] {
    (0..<n).map { _ in
        let tint = R(rng.unit())
        var p = Plant(x: Int(rng.range(3, Double(max(cols - 4, 4)))), height: Int(rng.range(tall.lowerBound, tall.upperBound) * Double(rows)),
                      phase: rng.range(0, 6.3), colour: colours.0 + (colours.1 - colours.0) * tint)
        p.strands = 2 + Int(p.phase * 7) % 3
        p.style = style
        return p
    }
}

/// a rounded stone, lit from the top left; `skip` leaves out cells (an opening)
private func stone(_ c: inout Canvas, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, colour: V3,
                   texture: [Unicode.Scalar] = ["@", "%", "#", "*", "+", "=", ":", "."], seed: Int = 0,
                   skip: (Int, Int) -> Bool = { _, _ in false }) {
    let x0 = Int(floor(cx - rx)), x1 = Int(ceil(cx + rx)), y0 = Int(floor(cy - ry)), y1 = Int(ceil(cy + ry))
    guard x1 >= x0, y1 >= y0 else { return }
    for y in y0...y1 {
        for x in x0...x1 {
            let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
            let d = dx * dx + dy * dy
            guard d <= 1, !skip(x, y) else { continue }
            let nz = (1 - d).squareRoot()
            let light = max(0, -0.45 * dx - 0.6 * dy + 0.65 * nz)             // facing up and to the left
            let h = hash2(x, y, seed)
            let edge = d > 0.78
            var g = texture[min(Int((1 - light) * Double(texture.count - 1) + Double(h % 3) * 0.5), texture.count - 1)]
            if edge { g = dy < -0.55 ? "_" : (dx < 0 ? "(" : ")") }
            if dy < -0.6 && !edge && h % 4 == 0 { g = "^" }
            c.put(x, y, g, colour * R(0.28 + 0.5 * light + 0.05 * Double(h % 3)))
        }
    }
}

/// a thick stroke from one point to another (driftwood): the letter follows the way it runs
private func stroke(_ c: inout Canvas, _ a: P2, _ b: P2, width w0: Double, _ w1: Double, colour: V3, seed: Int) {
    let d = b - a, len = max(simd_length(d), 1e-6)
    let steep = abs(d.y) * 1.43 > abs(d.x)                                  // cells are taller than wide
    let along: Unicode.Scalar = steep ? (d.x * d.y > 0 ? "\\" : "/") : "="
    let x0 = Int(min(a.x, b.x) - max(w0, w1) * 2) - 1, x1 = Int(max(a.x, b.x) + max(w0, w1) * 2) + 1
    let y0 = Int(min(a.y, b.y) - max(w0, w1)) - 1, y1 = Int(max(a.y, b.y) + max(w0, w1)) + 1
    for y in y0...y1 {
        for x in x0...x1 {
            let p = P2(Double(x), Double(y))
            let t = min(max(simd_dot(p - a, d) / (len * len), 0), 1)
            let q = a + d * t
            let off = (p - q) * P2(0.7, 1)                                  // in rows
            let w = w0 + (w1 - w0) * t, r = simd_length(off)
            guard r <= w else { continue }
            let h = hash2(x, y, seed)
            let top = off.y < 0 && r > w - 0.9
            let g: Unicode.Scalar = top ? (steep ? along : "_") : ["=", "-", "~", along, along][h % 5]
            let light = top ? 0.8 : 0.5 + 0.1 * Double(h % 3) - 0.22 * max(off.y, 0) / max(w, 0.5)
            c.put(x, y, g, colour * R(light))
        }
    }
}

// MARK: - the environments

let ENVIRONMENTS: [Environment] = [
    Environment(id: "planted", name: "Sand and Plants", about: "Sand in long low dunes, and clumps of plants swaying in the current.",
                floor: 6, tint: V3(1, 1, 1)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 1, 3, &rng)
        var c = Canvas(cols, rows)
        floor(&c, s.ground, grains: [".", ",", ":", "_", "~", "'"], colour: V3(0.70, 0.58, 0.40))
        s.cells = c.cells
        s.plants = plants(max(3, cols / 22), cols, rows, &rng)
        s.cover = s.plants.map { (Double($0.x), Double(rows - 3 - $0.height / 3)) }
        return s
    },
    Environment(id: "driftwood", name: "Driftwood and Moss", about: "A fallen branch of driftwood, furred with moss, and a few plants about it.",
                floor: 7, tint: V3(1.0, 0.97, 0.92)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 1, 3, &rng)
        var c = Canvas(cols, rows)
        let wood = V3(0.86, 0.60, 0.38), moss = V3(0.34, 0.78, 0.32)
        // the branch: from the sand up and across, forking twice
        let left = rng.unit() < 0.5
        let x0 = Double(cols) * (left ? rng.range(0.08, 0.2) : rng.range(0.8, 0.92))
        let dir = left ? 1.0 : -1.0
        let base = P2(x0, Double(rows - 1 - s.ground[min(Int(x0), cols - 1)]))
        let mid = base + P2(dir * Double(cols) * rng.range(0.18, 0.26), -Double(rows) * rng.range(0.14, 0.2))
        let tip = mid + P2(dir * Double(cols) * rng.range(0.12, 0.2), -Double(rows) * rng.range(0.08, 0.14))
        let fork1 = mid + P2(dir * Double(cols) * rng.range(0.05, 0.1), -Double(rows) * rng.range(0.13, 0.2))
        let fork2 = base + (mid - base) * 0.45 + P2(-dir * Double(cols) * rng.range(0.04, 0.08), -Double(rows) * rng.range(0.1, 0.16))
        let root = base + P2(-dir * Double(cols) * rng.range(0.03, 0.06), 0)
        let limbs: [(P2, P2, Double, Double)] = [(root, base, 4.6, 5.0), (base, mid, 5.0, 3.4), (mid, tip, 3.4, 1.0),
                                                 (mid, fork1, 2.4, 0.7), (base + (mid - base) * 0.45, fork2, 2.2, 0.7)]
        // moss first (it is in front): tufts along the top of the wood
        for (k, (a, b, w0, w1)) in limbs.enumerated() {
            let n = Int(simd_length(b - a) / 2.2)
            for i in 0..<max(n, 1) where rng.unit() < 0.85 {
                let t = Double(i) / Double(max(n, 1)), q = a + (b - a) * t, w = w0 + (w1 - w0) * t
                let y = Int(q.y - w) , x = Int(q.x)
                for dx in -3...3 where rng.unit() < 0.8 {
                    let h = hash2(x + dx, y, k)
                    for dy in 0...(abs(dx) < 2 ? 1 + h % 2 : h % 2) {
                        c.put(x + dx, y - dy + 1, ["%", "&", "*", "\"", "@", "#"][(h + dy) % 6], moss * R(0.5 + 0.4 * rng.unit()))
                    }
                }
            }
        }
        for (k, (a, b, w0, w1)) in limbs.enumerated() { stroke(&c, a, b, width: w0, w1, colour: wood, seed: k) }
        floor(&c, s.ground, grains: [".", ",", ":", "_", "~", "'"], colour: V3(0.70, 0.58, 0.40))
        s.cells = c.cells
        s.plants = plants(max(2, cols / 40), cols, rows, &rng, tall: 0.06...0.16)
        // under the branch is the place to hide
        s.cover = [0.3, 0.6].map { t in let q = base + (mid - base) * t; return (q.x, q.y + 3) }
        return s
    },
    Environment(id: "stones", name: "River Stones", about: "A bed of pebbles and a few big smooth stones, with tufts of grass between.",
                floor: 7, tint: V3(0.97, 1.0, 1.0)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 2, 4, &rng)
        var c = Canvas(cols, rows)
        // the big stones first (they are in front), sitting in the pebbles
        let n = max(2, cols / 80)
        var placed = [Double]()
        for i in 0..<n {
            var cx = 0.0
            for _ in 0..<10 {
                cx = rng.range(8, Double(cols - 8))
                if !placed.contains(where: { abs($0 - cx) < Double(cols) / Double(n + 2) }) { break }
            }
            placed.append(cx)
            let ry = Double(rows) * rng.range(0.05, 0.1), rx = ry * rng.range(1.9, 2.6)
            let ground = Double(rows - 1 - s.ground[min(max(Int(cx), 0), cols - 1)])
            let grey = rng.range(0.5, 0.75)
            let colour = V3(R(grey), R(grey * 0.97), R(grey * 0.92)) + (rng.unit() < 0.4 ? V3(0.12, 0.06, 0) : .zero)
            stone(&c, cx, ground - ry * 0.55, rx, ry, colour: colour * 1.25, seed: i)
            s.cover.append((cx + rx * 1.1, ground - 2))
        }
        // pebbles: each a little round letter of its own colour
        for x in 0..<cols {
            for k in 0..<s.ground[x] {
                let y = rows - 1 - k, h = hash2(x, y, 7)
                let g: Unicode.Scalar = ["o", "O", "0", "o", ".", "c", "@", "o"][h % 8]
                let tone = 0.35 + 0.1 * Double(h % 5) + 0.06 * Double(k)
                let warm = [V3(0.72, 0.70, 0.66), V3(0.78, 0.64, 0.48), V3(0.58, 0.64, 0.70), V3(0.70, 0.56, 0.50)][h / 8 % 4]
                c.put(x, y, g, warm * R(tone))
            }
        }
        s.cells = c.cells
        s.plants = plants(max(2, cols / 32), cols, rows, &rng, tall: 0.04...0.1)
        return s
    },
    Environment(id: "cave", name: "Rock Cave", about: "A great rock with a cave in it, for a fish to hide in, on a gravel floor.",
                floor: 6, tint: V3(0.96, 0.98, 1.0)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 1, 3, &rng)
        var c = Canvas(cols, rows)
        // the rock: one big mass with a dark arch in its foot, and a smaller one leaning on it
        let cx = Double(cols) * rng.range(0.3, 0.7), ry = Double(rows) * rng.range(0.2, 0.26), rx = ry * rng.range(2.4, 3.0)
        let ground = Double(rows - 1 - s.ground[min(max(Int(cx), 0), cols - 1)])
        let cy = ground - ry * 0.62
        let ax = cx + rx * rng.range(-0.25, 0.25), aw = rx * 0.32, ah = ry * 0.75       // the cave's mouth
        func inArch(_ x: Int, _ y: Int) -> Bool {
            let dx = (Double(x) - ax) / aw, dy = (Double(y) - ground) / ah
            return dx * dx + dy * dy < 1
        }
        let rock = V3(0.52, 0.52, 0.56)
        // the mouth's rim, lit faintly
        for a in stride(from: 0.0, through: Double.pi, by: 0.03) {
            let x = Int(ax + cos(a) * aw * 1.02), y = Int(ground - sin(a) * ah * 1.02)
            c.put(x, y, abs(cos(a)) > 0.75 ? (cos(a) > 0 ? ")" : "(") : "_", rock * 0.55)
        }
        stone(&c, cx, cy, rx, ry, colour: rock, texture: ["#", "%", "&", "8", "@", "*", "+", ":"], seed: 1, skip: inArch)
        let side = rng.unit() < 0.5 ? -1.0 : 1.0
        stone(&c, cx + side * rx * 0.95, ground - ry * 0.3, rx * 0.42, ry * 0.48, colour: rock * 0.95, seed: 2, skip: inArch)
        stone(&c, cx - side * rx * 1.05, ground - ry * 0.15, rx * 0.22, ry * 0.25, colour: rock * 0.9, seed: 3)
        floor(&c, s.ground, grains: [".", ":", "o", ",", "'", "."], colour: V3(0.66, 0.64, 0.6))
        s.cells = c.cells
        s.plants = plants(max(2, cols / 45), cols, rows, &rng, tall: 0.05...0.14)
        s.cover = [(ax, ground - ah * 0.4), (ax - aw * 0.4, ground - ah * 0.3), (ax + aw * 0.4, ground - ah * 0.3)]
        return s
    },
    Environment(id: "ruins", name: "Sunken Ruins", about: "Old stone columns, one standing, one broken, one fallen, and an arch half in the sand.",
                floor: 6, tint: V3(1.0, 0.99, 0.95)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 1, 3, &rng)
        var c = Canvas(cols, rows)
        let stoneCol = V3(0.88, 0.78, 0.6), moss = V3(0.36, 0.7, 0.34)
        func groundY(_ x: Int) -> Int { rows - 1 - s.ground[min(max(x, 0), cols - 1)] }
        /// a column: capital, fluted shaft, base; broken off at `broken` of its height if less than 1
        func column(_ x0: Int, _ height: Int, broken: Double) {
            let w = 11, g = groundY(x0 + w / 2), top = g - height
            let cut = broken < 1 ? Int(Double(height) * broken) : height
            for y in (g - cut)...g {
                let fromTop = y - top, h = hash2(x0, y, 5)
                for i in 0..<w {
                    let x = x0 + i
                    var ch: Unicode.Scalar = i == 0 || i == w - 1 ? "|" : (i % 2 == 0 ? ":" : (i < 4 ? "#" : "%"))
                    var k = i < 4 ? 0.7 : (i > w - 3 ? 0.38 : 0.52)                       // lit from the left
                    if broken < 1 && y == g - cut { ch = ["/", "\\", "_", "^", "/"][(h + i) % 5]; k = 0.6 }
                    if y >= g - 1 || (broken >= 1 && fromTop <= 1) { ch = fromTop <= 1 && y < g - 1 ? (fromTop == 0 ? "_" : "=") : "="; k = 0.6 }
                    if ch == " " { continue }
                    if hash2(x, y, 9) % 11 == 0 { c.put(x, y, "%", moss * 0.6); continue }
                    c.put(x, y, ch, stoneCol * R(k))
                }
                if broken >= 1 && fromTop <= 1 { c.put(x0 - 1, y, "[", stoneCol * 0.6); c.put(x0 + w, y, "]", stoneCol * 0.6) }
                if y >= g - 1 { c.put(x0 - 1, y, "[", stoneCol * 0.55); c.put(x0 + w, y, "]", stoneCol * 0.55) }
            }
        }
        let tall = Int(Double(rows) * 0.4)
        let xs = [0.12, 0.42, 0.72].map { Int(Double(cols) * ($0 + rng.range(-0.04, 0.04))) }.shuffled(using: &rng)
        column(xs[0], tall, broken: 1)
        column(xs[1], tall, broken: rng.range(0.35, 0.6))
        // the fallen one, lying in the sand
        let fx = xs[2], fl = Int(Double(cols) * 0.16), fg = groundY(fx + fl / 2)
        for y in (fg - 5)...(fg - 1) {
            for i in 0...fl {
                let ch: Unicode.Scalar = i == 0 ? "(" : i == fl ? ")" : (y == fg - 5 ? "_" : (y % 2 == 0 ? "=" : "-"))
                c.put(fx + i, y, ch, stoneCol * R(y <= fg - 4 ? 0.65 : 0.45))
            }
        }
        // a half-buried arch of blocks
        let acx = Double(Int(Double(cols) * rng.range(0.55, 0.9))), ar = Double(rows) * 0.14
        let ag = Double(groundY(Int(acx)))
        for a in stride(from: 0.0, through: Double.pi, by: 0.07) {
            let x = Int(acx + cos(a) * ar * 1.45), y = Int(ag - sin(a) * ar)
            for (dx, ch) in [(0, "["), (1, "#"), (2, "#"), (3, "]")] as [(Int, Unicode.Scalar)] {
                c.put(x + dx, y, ch, stoneCol * 0.6); c.put(x + dx, y + 1, ch == "#" ? "=" : ch, stoneCol * 0.45)
            }
        }
        floor(&c, s.ground, grains: [".", ",", ":", "_", "~", "'"], colour: V3(0.72, 0.62, 0.44))
        s.cells = c.cells
        s.plants = plants(max(2, cols / 40), cols, rows, &rng, tall: 0.06...0.18)
        s.cover = [(acx, ag - ar * 0.4), (Double(xs[1]) + 10, Double(groundY(xs[1])) - 3)]
        return s
    },
    Environment(id: "blackwater", name: "Blackwater Leaves", about: "Tea-coloured water over dark sand, almond leaves and twigs, as in the streams bettas come from.",
                floor: 4, tint: V3(1.0, 0.84, 0.6)) { cols, rows, rng in
        var s = Setting()
        s.ground = dunes(cols, 1, 2, &rng)
        var c = Canvas(cols, rows)
        // leaves lying on the bottom, curled at the edges, from fresh brown to old dark
        let leafColours = [V3(0.80, 0.45, 0.18), V3(0.66, 0.36, 0.14), V3(0.55, 0.30, 0.12), V3(0.82, 0.58, 0.22)]
        for i in 0..<max(8, cols / 10) {
            // a leaf: pointed at both ends, a midrib down it, two rows deep
            let len = Int(rng.range(9, 18)), x0 = Int(rng.range(0, Double(cols - len)))
            let y = rows - 1 - s.ground[min(x0 + len / 2, cols - 1)] - (rng.unit() < 0.35 ? 1 : 0)
            let col = leafColours[i % leafColours.count] * R(rng.range(0.75, 1.0))
            for k in 0...len {
                let edge = k == 0 || k == len
                c.put(x0 + k, y, edge ? (k == 0 ? "<" : ">") : (k == 1 || k == len - 1 ? "=" : "-"), col * (edge ? 0.8 : 0.95))
                if !edge && k > 1 && k < len - 1 { c.put(x0 + k, y - 1, k == 2 ? "/" : k == len - 2 ? "\\" : "_", col * 0.75) }
            }
        }
        // twigs
        for i in 0..<max(2, cols / 60) {
            let x = Double(rng.range(5, Double(cols - 5))), g = Double(rows - 1 - s.ground[min(Int(x), cols - 1)])
            let dir = rng.unit() < 0.5 ? -1.0 : 1.0, len = rng.range(8, 18)
            stroke(&c, P2(x, g), P2(x + dir * len, g - len * rng.range(0.2, 0.45)), width: 0.6, 0.4, colour: V3(0.55, 0.38, 0.22), seed: 20 + i)
        }
        floor(&c, s.ground, grains: [".", ",", ":", "'", "."], colour: V3(0.45, 0.33, 0.22))
        s.cells = c.cells
        s.plants = plants(max(2, cols / 50), cols, rows, &rng, tall: 0.1...0.24, colours: (V3(0.30, 0.55, 0.25), V3(0.45, 0.55, 0.2)), style: 2)
        s.cover = s.plants.map { (Double($0.x), Double(rows - 3)) }
        return s
    },
    Environment(id: "zen", name: "Zen Garden", about: "Raked sand in rings round three dark stones, and a single tuft of moss.",
                floor: 5, tint: V3(1, 1, 1)) { cols, rows, rng in
        var s = Setting()
        s.ground = Array(repeating: 1, count: cols)
        var c = Canvas(cols, rows)
        // three stones, big, middle, small, sat in the sand
        let sizes = [0.09, 0.065, 0.045].map { $0 * Double(rows) * rng.range(0.9, 1.15) }
        var spots = [P2]()
        for (i, r) in sizes.enumerated() {
            let x = Double(cols) * [0.25, 0.62, 0.8][i] + rng.range(-Double(cols) * 0.05, Double(cols) * 0.05)
            let y = Double(rows - 2) - r * 0.6
            spots.append(P2(x, Double(rows - 2)))
            stone(&c, x, y, r * 2.2, r, colour: V3(0.58, 0.56, 0.6), seed: 30 + i)
        }
        // the sand raked in long lines, bending into rings round each stone
        let depth = 10
        for x in 0..<cols {
            for k in 0..<depth {
                let y = rows - 1 - k
                var ring = Double(k) * 1.0, best = Double.infinity
                for (i, p) in spots.enumerated() {
                    let d = simd_length((P2(Double(x), Double(y)) - p) * P2(0.45, 1)) - sizes[i] * 1.2
                    if d < best { best = d }
                }
                if best < 6 { ring = best }
                let line = Int((ring * 1.0).rounded()) % 2 == 0
                c.put(x, y, line ? "~" : "-", V3(0.86, 0.82, 0.72) * R(line ? 0.55 : 0.3))
            }
        }
        s.ground = Array(repeating: depth, count: cols)
        s.cells = c.cells
        var moss = plants(1, cols, rows, &rng, tall: 0.03...0.05, colours: (V3(0.3, 0.7, 0.3), V3(0.4, 0.75, 0.35)), style: 1)
        moss[0].strands = 4
        s.plants = moss
        s.cover = spots.map { ($0.x + 8, $0.y - 4) }
        return s
    },
]

/// the environment called this (or bare water)
func environment(_ id: String) -> Environment? { ENVIRONMENTS.first { $0.id == id } }

extension SplitMix: RandomNumberGenerator {}
