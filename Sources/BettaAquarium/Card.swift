// A fish's card: when the pointer rests on a fish (on bare desktop), a small card beside it with its
// name, age, mood, personality, and what it remembers.

import AppKit
import SwiftUI

/// words for things about a fish, for the card and the settings
enum Describe {
    static func age(_ days: Double) -> String {
        if days < 1 { let h = Int(days * 24); return h < 1 ? "just arrived" : "\(h) hour\(h == 1 ? "" : "s")" }
        if days < 14 { let d = Int(days); return "\(d) day\(d == 1 ? "" : "s")" }
        if days < 61 { let w = Int(days / 7); return "\(w) weeks" }
        if days < 365 { let m = Int(days / 30.4); return "\(m) months" }
        let y = Int(days / 365), m = Int((days - Double(y) * 365) / 30.4)
        return "\(y) year\(y == 1 ? "" : "s")" + (m > 0 ? " \(m) month\(m == 1 ? "" : "s")" : "")
    }

    static func ago(_ date: Date) -> String {
        let m = Int(Date().timeIntervalSince(date) / 60)
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) minute\(m == 1 ? "" : "s") ago" }
        let h = m / 60
        if h < 48 { return "\(h) hour\(h == 1 ? "" : "s") ago" }
        return "\(h / 24) days ago"
    }

    static func clock(_ minutes: Double) -> String { String(format: "%d:%02d", Int(minutes) / 60 % 24, Int(minutes) % 60) }

    static func hours(_ h: Double) -> String { clock((h * 60).rounded()) }

    static func trust(_ t: Double) -> String {
        t < 0.2 ? "Wary of the cursor" : t < 0.45 ? "Getting used to the cursor" : t < 0.72 ? "Comes to see the cursor" : "Follows the cursor"
    }

    static func reaction(_ r: Reaction) -> String {
        switch r {
        case .ignore: "Takes no notice of the cursor"
        case .curious: "Curious about the cursor"
        case .shy: "Keeps away from the cursor"
        case .dynamic: "Watches the cursor from a distance"
        case .follow: "Follows the cursor"
        }
    }

    /// where in the tank a point is, roughly
    static func place(_ p: P2, in tank: Tank) -> String {
        let i = tank.layout.screens.count > 1 ? tank.areas.firstIndex { p.x >= $0.left && p.x <= $0.right } : nil
        let a = tank.areas[i ?? 0]
        let fx = (p.x - a.left) / max(a.right - a.left, 0.01), fy = (p.y - a.bottom) / max(a.top - a.bottom, 0.01)
        let across = fx < 0.33 ? "left" : fx > 0.67 ? "right" : "middle"
        let up = fy < 0.33 ? "low down" : fy > 0.67 ? "up high" : ""
        var s = up.isEmpty ? (across == "middle" ? "the middle" : "the \(across) side") : "\(up) on the \(across == "middle" ? "middle" : across + " side")"
        if let i { s += " of \(["the main screen", "the second screen", "the third screen", "screen 4", "screen 5", "screen 6"][min(i, 5)])" }
        return s
    }
}

struct CardInfo: Equatable {
    var name = "", stage = "", age = "", mood = "", traits = "", fed = "", cursor = "", favourite = "", learned = ""
    var trust = 0.0
    var colours: [Color] = []
}

private struct CardView: View {
    let info: CardInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.name).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 12)
                HStack(spacing: 2) { ForEach(0..<info.colours.count, id: \.self) { Circle().fill(info.colours[$0]).frame(width: 8, height: 8) } }
            }
            Text("\(info.stage) · \(info.age)").font(.system(size: 11)).foregroundStyle(.secondary)
            Divider().padding(.vertical, 2)
            row("face.smiling", info.mood)
            if !info.traits.isEmpty { row("sparkles", info.traits) }
            row("fork.knife", info.fed)
            row("cursorarrow", info.cursor)
            if !info.learned.isEmpty { row("clock", info.learned) }
            if !info.favourite.isEmpty { row("mappin", info.favourite) }
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).frame(width: 14).foregroundStyle(.secondary)
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class Card {
    private let panel: NSPanel
    private let host: NSHostingView<CardView>
    private var info = CardInfo()
    private var updated = 0.0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 160), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        host = NSHostingView(rootView: CardView(info: info))
        panel.contentView = host
    }

    /// what a fish's card says now
    static func info(for b: Betta, tank: Tank, settings: Settings) -> CardInfo {
            let life = Life.shared, p = b.profile
            var i = CardInfo()
            i.name = p.name
            i.stage = life.stage(p).name
            i.age = Describe.age(life.age(p))
            i.mood = b.mind.mood.rawValue
            i.traits = p.personality.words.joined(separator: ", ").capitalizedFirst
            i.fed = "Fed \(Describe.ago(settings.lastFed))"
            let r = b.howItTakesTheCursor(tank.surroundings)
            i.cursor = (p.reaction ?? settings.mouse) == .dynamic ? Describe.trust(b.mind.memory.trust) : Describe.reaction(r)
            if settings.memory {
                if let f = b.mind.favourite { i.favourite = "Likes \(Describe.place(f, in: tank))" }
                if !b.mind.memory.learned.isEmpty {
                    i.learned = "Expects food at " + b.mind.memory.learned.sorted().map(Describe.clock).joined(separator: " and ")
                }
            }
            i.trust = b.mind.memory.trust
            i.colours = PALETTES[min(b.wearing, PALETTES.count - 1)].map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
            return i
    }

    /// a card as a picture, `scale` pixels to a point (for the README)
    static func picture(_ info: CardInfo, scale: CGFloat = 2) -> CGImage? {
        let v = NSHostingView(rootView: CardView(info: info))
        v.frame = NSRect(origin: .zero, size: v.fittingSize)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * scale), pixelsHigh: Int(v.bounds.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = v.bounds.size
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.cgImage
    }

    func show(_ b: Betta, at mouse: NSPoint, settings: Settings, app: App) {
        let now = CACurrentMediaTime()
        if now - updated > 0.4 || !panel.isVisible {
            updated = now
            let i = Card.info(for: b, tank: app.tank, settings: settings)
            if i != info { info = i; host.rootView = CardView(info: i) }
        }
        let size = host.fittingSize
        var origin = NSPoint(x: mouse.x + 18, y: mouse.y - 18 - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let f = screen.visibleFrame
            if origin.x + size.width > f.maxX { origin.x = mouse.x - 18 - size.width }
            if origin.y < f.minY { origin.y = mouse.y + 18 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    var visible: Bool { panel.isVisible }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
