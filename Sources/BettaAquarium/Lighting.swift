// The light over the water, from the settings, the time of day and the weather: shared by the
// wallpaper and the screen saver.

import Foundation

struct WaterLook {
    var brightness = 1.0, dawn = 0.0, rays = 0.0, caustics = 0.0
    var tint = V3(1, 1, 1), rayTint = V3(0.30, 0.50, 0.70)
}

enum Lighting {
    /// how the water looks now; `flash`: lightning this moment
    static func look(_ s: Settings, night: Double, dawn: Double, sky: Sky?, environment: Environment?, flash: Bool) -> WaterLook {
        let ws = s.weatherStrength
        let cloud = (sky?.cloud ?? 0) * ws
        let moon = s.nightLight ? night * s.nightLightStrength : 0
        var w = WaterLook()
        w.brightness = s.brightness * (1 - s.nightDim * night * (s.nightLight ? 0.45 : 1)) * (1 - 0.28 * cloud)
        if sky?.fog == true { w.brightness *= 1 - 0.12 * ws }
        if flash { w.brightness *= 1 + 0.9 * ws }
        var tint = environment?.tint ?? V3(1, 1, 1)
        if moon > 0 { tint *= V3(1, 1, 1) + (V3(0.62, 0.8, 1.2) - V3(1, 1, 1)) * R(min(moon, 1.2) * 0.7) }
        if sky?.snow == true { tint *= V3(0.95, 0.98, 1.05) }
        if cloud > 0 { tint *= V3(1, 1, 1) + (V3(0.9, 0.93, 0.98) - V3(1, 1, 1)) * R(cloud) }
        w.tint = tint
        var rayTint = V3(0.30, 0.50, 0.70) + (V3(0.80, 0.50, 0.28) - V3(0.30, 0.50, 0.70)) * R(min(dawn, 1))
        rayTint = rayTint + (V3(0.38, 0.48, 0.85) - rayTint) * R(min(moon, 1))
        w.rayTint = rayTint
        w.rays = s.rays * (1 - 0.88 * cloud)
        if s.nightLight { w.rays *= (1 - night) + night * 0.45 * s.nightLightStrength }      // moonbeams
        w.caustics = s.caustics * (1 - 0.7 * cloud) * (1 - 0.55 * night)
        w.dawn = min(dawn, 1.5)
        return w
    }

    static func apply(_ w: WaterLook, to r: Renderer) {
        r.brightness = Float(w.brightness)
        r.dawn = Float(w.dawn)
        r.tint = w.tint
        r.rayTint = w.rayTint
        r.rays = Float(w.rays)
        r.caustics = Float(w.caustics)
    }

    /// what the fish should know, apart from the mouse
    static func surroundings(_ s: Settings, night: Double, hungry: Bool, sky: Sky?) -> Surroundings {
        var r = Surroundings()
        r.mood = Mood(pace: s.pace, night: night, habits: s.habits, hungry: hungry)
        r.reaction = s.mouse
        r.now = Date()
        r.lastFed = s.lastFed
        r.moods = s.moods; r.memory = s.memory; r.territory = s.territory
        r.trustSpeed = s.trustSpeed; r.toleranceDays = s.toleranceDays; r.boredAfter = s.boredAfter
        r.rain = s.weather ? (sky?.rain ?? 0) * s.weatherStrength : 0
        return r
    }

    /// the tank's settings that need nothing rebuilt
    static func apply(_ s: Settings, to tank: Tank) {
        tank.fill = fillLetters(LETTER_SETS[min(max(s.letters, 0), LETTER_SETS.count - 1)].pools)
        tank.allowedFor = { p in { s.allowedPalettes(for: p) } }
        tank.colourEvery = s.colourEvery
        tank.environment = environment(s.environment)
        tank.surface = s.surface
        tank.company = s.company
        tank.tetraCount = s.tetras
        tank.bubbleAmount = s.bubbles
        for b in tank.bettas { b.allowedPalettes = tank.allowedFor(b.profile) }
    }
}
