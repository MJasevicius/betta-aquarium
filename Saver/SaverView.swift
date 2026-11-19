// The screen saver: the same tank, with your fish, environment and look, read from the app's own
// files (the screen saver runs apart from the app, and can only read them). The fish swim on the
// main screen; the others show the water and what is in it.

import AppKit
import MetalKit
import ScreenSaver

@objc(BettaSaverView)
final class SaverView: ScreenSaverView, MTKViewDelegate {
    private var mtk: MTKView?
    private var renderer: Renderer?
    private var tank: Tank?
    private var t: Time = 0, last = CACurrentMediaTime()
    private var light = (night: 0.0, dawn: 0.0), checked = -1e9
    private static var loaded = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// the app's settings and fish, from where the app keeps them
    private static func loadTheApps() {
        guard !loaded else { return }
        loaded = true
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        if let d = NSDictionary(contentsOfFile: home + "/Library/Preferences/io.github.mjasevicius.betta-aquarium.plist") as? [String: Any] {
            Settings.shared.adopt(d)
        }
        Life.shared.load(count: 1, adultDays: Settings.shared.adultDays,
                         from: URL(fileURLWithPath: home + "/Library/Application Support/Betta Aquarium/life.json"))
    }

    private func build() {
        guard tank == nil, let device = MTLCreateSystemDefaultDevice(), bounds.width > 0 else { return }
        SaverView.loadTheApps()
        let s = Settings.shared
        // the main screen has the fish (or a preview); the others only the water
        let main = isPreview || window?.screen == nil || window?.screen == NSScreen.screens.first
        let rows = isPreview ? max(Int(Double(s.rows) * 0.45), 40) : s.rows
        let tank = Tank(layout: Layout(screens: [CGRect(origin: .zero, size: bounds.size)], fishRows: rows),
                        seed: UInt64.random(in: 1...UInt64(UInt32.max)), fish: 0)
        Lighting.apply(s, to: tank)
        tank.setFish(main ? Life.shared.fish : [], minds: Life.shared.minds)
        self.tank = tank
        let v = MTKView(frame: bounds, device: device)
        v.colorPixelFormat = .bgra8Unorm
        v.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        v.isPaused = true
        v.enableSetNeedsDisplay = false
        v.autoresizingMask = [.width, .height]
        v.delegate = self
        addSubview(v)
        mtk = v
        guard let r = try? Renderer(device: device, targetFormat: v.colorPixelFormat, tank: tank, screen: 0) else { return }
        r.glow = Float(s.glow)
        r.trail = Float(s.trail)
        r.font = s.font
        r.vignette = Float(s.vignette)
        renderer = r
        r.resize(Int(v.drawableSize.width), Int(v.drawableSize.height))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        build()
    }

    override func startAnimation() {
        super.startAnimation()
        last = CACurrentMediaTime()
        build()
    }

    override func animateOneFrame() {
        build()
        guard let tank, let renderer, let mtk else { return }
        let now = CACurrentMediaTime()
        t += min(now - last, 1.0 / 15)
        last = now
        let s = Settings.shared
        if now - checked > 30 {
            light = s.light()
            checked = now
        }
        tank.surroundings = Lighting.surroundings(s, night: light.night, hungry: false, sky: nil)
        tank.frame(t)
        renderer.time = Float(t.truncatingRemainder(dividingBy: 10_000))
        Lighting.apply(Lighting.look(s, night: light.night, dawn: light.dawn, sky: nil, environment: tank.environment, flash: false), to: renderer)
        mtk.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.resize(Int(size.width), Int(size.height))
    }

    func draw(in view: MTKView) {
        guard let renderer, let drawable = view.currentDrawable, let cmd = renderer.queue.makeCommandBuffer() else { return }
        renderer.draw(into: drawable.texture, cmd)
        cmd.present(drawable)
        cmd.commit()
    }

    override var hasConfigureSheet: Bool { false }
}
