// The app: one tank across the main screen (or every screen), a wallpaper on each, the fish in the
// menu bar, and the settings window. It keeps the tank's clock and tells the fish what is going on
// around them (the light, the weather, the mouse, whether they are hungry, a tap on the glass, you
// coming back to the Mac), shows a fish's card when the pointer rests on it, and pauses when told to.

import AppKit
import IOKit.ps
import MetalKit
import SwiftUI

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var device: MTLDevice!
    private(set) var tank: Tank!
    private var walls: [Wallpaper] = []
    private var shape: [CGRect] = [], shapeRows = 0      // the screens and fish size the tank was laid out for
    private var status: NSStatusItem!
    private let settings = Settings.shared, life = Life.shared, weather = Weather.shared
    private var t: Time = 0, lastFrame = CACurrentMediaTime()
    private var lastMouse = NSPoint(x: -1, y: -1), mouseMovedAt = 0.0, stillSince = CACurrentMediaTime()
    private var light = (night: 0.0, dawn: 0.0), hungry = false, clockCheckedAt = -1e9
    private var flashUntil = 0.0, nextFlash = 0.0
    private var timer: Timer?, tapMonitor: Any?
    private var card: Card?
    private var settingsWindow: NSWindow?
    var printStats = true
    private var statFrames = 0, statFish = 0.0, statWall = CACurrentMediaTime(), statCPU = cpuSeconds()

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
        self.device = device
        settings.start()
        life.persist = true
        let oldCount = UserDefaults(suiteName: "io.github.mjasevicius.betta-aquarium")?.object(forKey: "fishCount") as? Int ?? 1
        life.load(count: oldCount, adultDays: settings.adultDays)
        arrange()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let fish = NSImage(systemSymbolName: "fish", accessibilityDescription: "Betta Aquarium") {
            fish.isTemplate = true
            status.button?.image = fish
        } else {
            status.button?.title = "🐟"
        }
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        settings.onChange = { [weak self] key in self?.changed(key) }
        life.onChange = { [weak self] in self?.fishChanged() }
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.arrange() }
        nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.checkPower() }
        // you coming back: the Mac waking, or the screen unlocked
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.cameBack() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                                            queue: .main) { [weak self] _ in self?.cameBack() }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkPower()
            self?.weather.refresh()
        }
        timer?.tolerance = 5
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.life.save() }.tolerance = 10
        checkPower()
        weather.refresh(now: true)
        // a click on the desktop is a tap on the glass
        tapMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.tapped() }
        if printStats { print("Betta Aquarium · quit from the fish in the menu bar") }
    }

    func applicationWillTerminate(_ note: Notification) { life.save() }

    // MARK: screens

    /// one tank over the screens it should be on, and a wallpaper on each
    private func arrange() {
        let wanted = settings.allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        guard !wanted.isEmpty else { return }
        let frames = wanted.map(\.frame), rows = settings.rows
        if tank == nil {
            tank = Tank(layout: Layout(screens: frames, fishRows: rows), seed: UInt64.random(in: 1...UInt64(UInt32.max)), fish: 0)
            apply()
            fishChanged()
            if printStats { print("seed \(tank.seed)") }
        } else if frames != shape || rows != shapeRows {
            tank.relayout(Layout(screens: frames, fishRows: rows))
        }
        shape = frames; shapeRows = rows
        if printStats {
            let f = tank.layout.fish
            print("\(wanted.count) screen(s): \(f.regions.map { "\($0.cols) x \($0.rows)" }.joined(separator: ", ")) letters")
        }

        let ids = wanted.map(\.displayID)
        for w in walls where !ids.contains(w.screenID) { w.close() }
        walls.removeAll { !ids.contains($0.screenID) }
        for (i, screen) in wanted.enumerated() {
            if let w = walls.first(where: { $0.screenID == screen.displayID }) {
                w.renderer.screen = i
                w.fit()
            } else {
                let w = Wallpaper(screen: screen, device: device, tank: tank, index: i)
                w.onTick = { [weak self] in self?.tick() }
                walls.append(w)
            }
        }
        apply()
        checkPower()
    }

    /// take on the settings that need nothing rebuilt
    private func apply() {
        let s = settings
        Lighting.apply(s, to: tank)
        for w in walls {
            let r = w.renderer
            r.glow = Float(s.glow)
            r.trail = Float(s.trail)
            r.font = s.font
            r.vignette = Float(s.vignette)
            w.setFPS(s.fps)
        }
        clockCheckedAt = -1e9
    }

    private func fishChanged() {
        tank.setFish(life.fish, minds: life.minds)
        tank.bettas.forEach { $0.recolour() }
    }

    private func changed(_ key: String) {
        switch key {
        case "allScreens", "rows": arrange()
        case "paused", "pauseOnBattery", "pauseLowPower": checkPower()
        case "colourMode", "favouriteKeys", "fixedKey": apply(); tank.bettas.forEach { $0.recolour() }
        case "weather", "latitude", "longitude":
            weather.forget()
            weather.refresh(now: true)
            apply()
        case "all": arrange(); fishChanged()
        default: apply()
        }
    }

    // MARK: the tank's clock

    /// bring the tank up to the present: once for all the screens, however many ask
    private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastFrame > 0.7 / max(settings.fps, 5) else { return }
        t += min(now - lastFrame, 1.0 / 15)
        lastFrame = now
        surround(now)
        tank.seen = (0..<tank.layout.screens.count).map { i in walls.first { $0.renderer.screen == i }?.visible ?? false }
        let c0 = threadSeconds()
        tank.frame(t)
        statFish += threadSeconds() - c0
        lighting(now)
        hover(now)

        statFrames += 1
        let wall = now - statWall
        if wall >= 5 {
            let cpu = cpuSeconds()
            if printStats {
                print(String(format: "%.0f fps · fish %.2f ms/frame · whole app %.1f%% of one CPU core",
                             Double(statFrames) / wall, statFish / Double(max(statFrames, 1)) * 1000, (cpu - statCPU) / wall * 100))
            }
            statFrames = 0; statFish = 0; statWall = now; statCPU = cpu
        }
    }

    /// the light over the water: the time of day, the night light, the weather, the environment's water
    private func lighting(_ now: Double) {
        let sky = settings.weather ? weather.sky : nil
        // a thunderstorm: now and then the water lights up for a moment, twice
        var flash = false
        if sky?.thunder == true {
            if now > nextFlash { flashUntil = now + 0.09; nextFlash = now + Double.random(in: 12...50) }
            flash = now < flashUntil || (now > flashUntil + 0.12 && now < flashUntil + 0.2)
        }
        let look = Lighting.look(settings, night: light.night, dawn: light.dawn, sky: sky, environment: tank.environment, flash: flash)
        for w in walls {
            w.renderer.time = Float(t.truncatingRemainder(dividingBy: 10_000))
            Lighting.apply(look, to: w.renderer)
        }
    }

    /// what is going on around the fish
    private func surround(_ now: Double) {
        if now - clockCheckedAt > 30 {
            light = settings.light()
            hungry = settings.hungry() && light.night < 0.5             // asleep, it does not beg
            clockCheckedAt = now
        }
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            // back after a long while away from the Mac: they come to see
            if now - mouseMovedAt > 20 * 60 && mouseMovedAt > 0 { cameBack() }
            lastMouse = mouse; mouseMovedAt = now; stillSince = now
        }
        var r = Lighting.surroundings(settings, night: light.night, hungry: hungry, sky: settings.weather ? weather.sky : nil)
        r.mouse = tank.water(at: mouse)?.p
        r.mouseMoving = now - mouseMovedAt < 1.5
        tank.surroundings = r
    }

    private var cameBackAt = 0.0
    private func cameBack() {
        let now = CACurrentMediaTime()
        guard settings.greet, now - cameBackAt > 60, tank != nil else { return }
        cameBackAt = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.tank.greet() }
    }

    func feed() {
        tank.feed(pellets: settings.pellets)
        settings.lastFed = Date()
        life.log(nil, "You fed the fish.")
        clockCheckedAt = -1e9
    }

    // MARK: a tap on the glass

    private func tapped() {
        guard settings.tapGlass, let tank, walls.contains(where: { !$0.held && $0.visible }) else { return }
        let p = NSEvent.mouseLocation
        guard let at = tank.water(at: p), onDesktop(p) else { return }
        tank.tap(at: at.p, screen: at.screen)
    }

    /// whether a point of the screens is bare desktop: not in the menu bar or the Dock, nor on any window
    /// or widget (desktop icons are fine: they are on the glass)
    func onDesktop(_ p: NSPoint) -> Bool { whatCovers(p) == nil }

    /// what covers a point of the screens, if anything does
    func whatCovers(_ p: NSPoint) -> String? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { return "no screen" }
        guard screen.visibleFrame.contains(p) else { return "the menu bar or the Dock" }
        let q = CGPoint(x: p.x, y: NSScreen.screens[0].frame.maxY - p.y)            // the window list's corner is top left
        let me = Int(getpid())
        // the system's own layers over the desktop (when a click on the wallpaper moves the windows
        // aside, say) are not windows in the way
        let system: Set<String> = ["WindowManager", "Dock", "Window Server", "Control Center", "SystemUIServer"]
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            // the Dock, menus and overlays are higher; of ours, only the settings window counts (not the
            // wallpaper, nor a fish's card)
            guard let layer = w[kCGWindowLayer as String] as? Int, layer < 20,
                  (w[kCGWindowOwnerPID as String] as? Int) != me || layer == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  !system.contains(w[kCGWindowOwnerName as String] as? String ?? ""),
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { continue }
            if r.contains(q) {
                return "\(w[kCGWindowOwnerName as String] as? String ?? "?") “\(w[kCGWindowName as String] as? String ?? "")” layer \(layer) at \(r)"
            }
        }
        return nil
    }

    // MARK: a fish's card, when the pointer rests on it

    private var hoverFish: String?, hoverSince = 0.0, hoverChecked = 0.0, hoverOK = false

    private func hover(_ now: Double) {
        guard settings.hoverCard, let m = tank.surroundings.mouse else { hideCard(); return }
        guard let b = fishUnder(m) else { hideCard(); hoverFish = nil; return }
        if b.id != hoverFish { hoverFish = b.id; hoverSince = now; hoverOK = false; hoverChecked = 0 }
        guard now - hoverSince >= settings.hoverDelay else { return }
        if now - hoverChecked > 0.5 {
            let cover = whatCovers(NSEvent.mouseLocation)
            hoverOK = cover == nil
            hoverChecked = now
            if let cover { note("card for \(b.profile.name) not shown: covered by \(cover)") }
        }
        guard hoverOK else { hideCard(); return }
        if card == nil { card = Card() }
        card?.show(b, at: NSEvent.mouseLocation, settings: settings, app: self)
    }

    private func hideCard() { card?.hide() }

    /// a line in ~/Library/Logs/Betta Aquarium.log (for when something doesn't happen that should)
    private var noted = [String: Double]()
    private func note(_ line: String) {
        let now = CACurrentMediaTime()
        if let last = noted[line], now - last < 10 { return }
        noted[line] = now
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Betta Aquarium.log")
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// the fish under a point of the water, if any (the nearest)
    private func fishUnder(_ m: P2) -> Betta? {
        var best: Betta?, bestD = Double.infinity
        for b in tank.bettas where b.swimming {
            let d = (m - b.anchor) / max(b.looks.size, 0.3)
            let r = (d.x / 1.15) * (d.x / 1.15) + (d.y / 0.65) * (d.y / 0.65)
            if r < 1 && r < bestD { bestD = r; best = b }
        }
        return best
    }

    // MARK: power

    private func checkPower() {
        var hold = settings.paused
        if settings.pauseLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled { hold = true }
        if settings.pauseOnBattery && onBattery() { hold = true }
        walls.forEach { $0.held = hold }
    }

    private func onBattery() -> Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (source as String) == kIOPMBatteryPowerKey
    }

    // MARK: open at login

    private var agent: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/io.github.mjasevicius.betta-aquarium.plist")
    }
    var opensAtLogin: Bool { FileManager.default.fileExists(atPath: agent.path) }

    func setOpensAtLogin(_ on: Bool) {
        if on {
            let me = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": "io.github.mjasevicius.betta-aquarium",
                "ProgramArguments": [me],
                "RunAtLoad": true,
                "KeepAlive": ["SuccessfulExit": false],
                "LimitLoadToSessionType": "Aqua",
            ]
            try? FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: agent, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: agent)
        }
    }

    // MARK: the screen saver

    /// put the screen saver (made with the app) where macOS looks for them, and open its settings
    func installSaver() -> String {
        guard let saver = Bundle.main.url(forResource: "Betta Aquarium", withExtension: "saver") else {
            return "The screen saver isn't in this copy of the app (build it with make-app.sh)."
        }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")
        let dest = dir.appendingPathComponent("Betta Aquarium.saver")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: saver, to: dest)
        } catch {
            return "Couldn't install it: \(error.localizedDescription)"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
        return "Installed. Choose “Betta Aquarium” in Screen Saver settings."
    }

    // MARK: the settings window

    @objc func openSettings() { openSettings(page: nil) }

    func openSettings(page: SettingsPage?, fish: String? = nil) {
        if let page { SettingsModel.shared.page = page }
        if let fish { SettingsModel.shared.fish = fish }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Betta Aquarium"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(app: self))
            w.setContentSize(NSSize(width: 860, height: 640))
            w.minSize = NSSize(width: 760, height: 520)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: the menu

    private final class Action: NSMenuItem {
        var run: () -> Void = {}
        @objc func fire() { run() }
    }

    private func item(_ title: String, on: Bool = false, key: String = "", tip: String? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let i = Action(title: title, action: #selector(Action.fire), keyEquivalent: key)
        i.toolTip = tip.flatMap { SETTING_INFO[$0] } ?? SETTING_INFO[title]
        i.target = i
        i.run = run
        i.state = on ? .on : .off
        return i
    }

    private func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu()
        items.forEach { m.addItem($0) }
        i.submenu = m
        return i
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = settings
        menu.removeAllItems()
        menu.addItem(header("Betta Aquarium"))
        menu.addItem(item(s.paused ? "Resume" : "Pause") { s.paused.toggle() })
        let starving = s.hungry()
        menu.addItem(item(starving ? (life.fish.count > 1 ? "Feed (They're Hungry)" : "Feed (It's Hungry)") : "Feed") { [weak self] in
            self?.feed()
        })

        menu.addItem(.separator())
        menu.addItem(header("Fish"))
        for b in tank.bettas {
            let p = b.profile
            let line = "\(p.name) — \(life.stage(p).name), \(b.mind.mood.rawValue.lowercased())"
            menu.addItem(item(line) { [weak self] in self?.openSettings(page: .fish, fish: p.id) })
        }
        if life.fish.count < MAX_FISH {
            menu.addItem(item("Add a Fish") { [weak self] in self?.life.addFish() })
        }

        menu.addItem(.separator())
        menu.addItem(sub("Environment", [item("Bare Tank", on: tank.environment == nil) { s.environment = "none" }]
                         + ENVIRONMENTS.map { e in item(e.name, on: tank.environment?.id == e.id) { s.environment = e.id } }))
        menu.addItem(item("Water Surface", on: s.surface) { s.surface.toggle() })
        menu.addItem(item("Sunrise and Sunset", on: s.dayNight, tip: "Sunrise and Sunset") { s.dayNight.toggle() })
        menu.addItem(item("Night Light", on: s.nightLight, tip: "Night Light (Soft Blue Moonlight)") { s.nightLight.toggle() })
        let sky = weather.sky.map { " (\($0.summary))" } ?? ""
        menu.addItem(item("Weather" + (s.weather ? sky : ""), on: s.weather, tip: "Weather Where You Are") { [weak self] in
            if !s.hasPlace { self?.openSettings(page: .water); return }
            s.weather.toggle()
        })
        menu.addItem(item("One Tank Across All Screens", on: s.allScreens) { s.allScreens.toggle() })

        menu.addItem(.separator())
        let recent = life.diary.suffix(4).reversed()
        if !recent.isEmpty {
            menu.addItem(header("Lately"))
            for e in recent {
                let text = e.text.count > 70 ? String(e.text.prefix(68)) + "…" : e.text
                menu.addItem(header("  " + text))
            }
        }
        menu.addItem(item("Diary…") { [weak self] in self?.openSettings(page: .diary) })
        menu.addItem(item("Settings…", key: ",") { [weak self] in self?.openSettings(page: nil) })

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Betta Aquarium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
