// What each setting does: shown when the pointer rests on the ⓘ beside its name.

import SwiftUI

let SETTING_INFO: [String: String] = [
    // a fish
    "Name": "What the fish is called: on its card, in the menu and in the diary.",
    "Wears": "Which colours this fish changes through. The Tank's Colours follows Settings ▸ Look; the others are just for this fish: every set in turn, the sets you tick, one set always, or sets that suit the time of day.",
    "New Colours Every": "Seconds between colour changes. Each change runs over the fish as a wave from the gills to the tips of the fins. The original changed every 2 seconds.",
    "Its Own Pace of Change": "Lets this fish change colours at its own pace instead of the tank's.",
    "Make Its Own Colours…": "Makes a colour set just for this fish, starting from what it wears now, with a colour picker for each part of it.",
    "Name of the Set": "What this colour set is called in the lists.",
    "Body": "The main colour of the body.",
    "Belly and Face": "The paler colour of the belly, the face and the shining scales.",
    "Fin Roots": "The colour of the fins where they spring from the body.",
    "Fin Middles": "The colour halfway out along the fins (also the little fins under the belly).",
    "Fin Hems": "The colour at the edges of the fins.",
    "Bold": "Bold fish flee less far and calm down sooner after a tap, come back sooner to see what it was, trust the cursor faster, and may flare back at a rival. Shy fish do the opposite, and hide more.",
    "Lively": "How much it swims: lively fish swim faster and rest less; lazy ones drift and rest longer.",
    "Greedy": "How keen it is on food: greedy fish rush the pellets; picky ones take their time.",
    "Keen Builder": "How often it goes up to blow bubbles into its nest, so how big its nests get.",
    "Show-Off": "How often it flares its fins, at nothing in particular or at another fish near its home.",
    "Shuffle Personality": "Gives the fish a new personality at random.",
    "Grows Up by the Calendar": "On: it ages with real time from the day it was born: juvenile, young adult, adult (and old, if fish grow old). Off: it stays the age you set.",
    "Born": "When it was born. Set it earlier to make it older straight away.",
    "Stays This Old": "The age it is kept at, in days. Settings ▸ Behaviour ▸ Growing Up says at what ages each stage begins.",
    "Size": "Bigger or smaller than its age would make it (1: as it grows).",
    "Fin Length": "Longer or shorter fins than its age would give it (1: as it grows).",
    "Takes the Cursor": "How this fish reacts to the cursor: as set for the whole tank, or its own way. Depends on the Fish goes by how bold it is and how far it trusts you.",
    "Trust": "How far it trusts the cursor: 0 wary … 1 follows it about. It grows when you feed it and when you move the cursor gently near it (a little each day), and taps on the glass set it back. With the cursor set to Depends on the Fish, a fish that trusts little keeps away, then watches from a distance, then comes to look, and at about 0.7 follows.",
    "Forget Everything": "Clears what it has learned: trust, feeding times, its favourite spot, the taps it remembers. Its milestones in the diary stay.",
    "Rehome": "Takes this fish out of the tank for good, with everything it remembers.",
    "Add a Fish": "A new fish joins the tank, as a tiny juvenile with a personality of its own. Up to six.",

    // look
    "Fish Size (rows of letters on a screen)": "How many rows of letters fill the main screen. More rows: smaller letters, so a smaller fish with more room to swim. Fewer: a bigger fish. The scenery keeps its size.",
    "Letters": "The font the fish is drawn in (Courier, as in the original, Menlo, Monaco or SF Mono).",
    "Fill": "Which letters fill the fish, from its dark folds to its bright highlights.",
    "Fish Wear": "Which colours the fish change through, unless a fish has its own (under Fish): every set in turn, your favourites, sets that suit the time of day, or one set always.",
    "New Colour Set": "Makes a new set of five colours to pick yourself. Any fish can wear it.",
    "Delete This Set": "Deletes this colour set; fish wearing it go back to the others.",
    "Glow": "How much the letters glow, as light spreading in water. 0: no glow.",
    "Trail": "How much of each frame lingers into the next, leaving soft trails behind the moving fins. 0: none.",
    "Brightness": "How bright everything is drawn (1: as made).",
    "Darker Edges": "Darkens each screen towards its edges, like looking into a tank. 0: off.",

    // water and light
    "On the Bottom": "What lies on the bottom of the tank. Each screen gets its own arrangement of it. Upset fish hide in the cave, among plants, or under the wood.",
    "Water Surface": "Draws the water's surface near the top. It ripples where a fish takes air, where food lands, and where rain falls (with the weather on). Fish take air at it, and their nests float under it.",
    "Bubbles in the Water": "How many bubbles rise through the background, against the original (1). 0: none.",
    "Tank Mates (Neon Tetras)": "A small school of neon tetras swimming far behind the bettas, on each screen.",
    "How Many Tetras": "How many tetras on each screen.",
    "Light Rays": "Shafts of light slanting down from the surface. 0: off. They turn golden at sunrise and sunset, blue under the night light, and fade under clouds.",
    "Caustics": "The rippling net of light a wavy surface throws over the fish, the sand and the plants. 0: off.",
    "Sunrise and Sunset": "Makes the light follow the clock: golden at sunrise and sunset, dimmer at night, when the fish get sleepy and settle low.",
    "Sunrise and Sunset Where You Are": "Uses the real times of sunrise and sunset at the place set under Weather, worked out on this Mac each day (nothing is sent anywhere for this).",
    "Sunrise": "When the lights come up: any time you like.",
    "Sunset": "When the lights go down: any time you like (0:00 is midnight).",
    "Twilight": "How long the light takes to come up or go down, in hours.",
    "Darker at Night": "How dim the tank gets at night: 0 not at all … 0.95 almost dark.",
    "Golden Light at Dawn and Dusk": "How warm and golden the light turns around sunrise and sunset. 0: not at all.",
    "Night Light (Soft Blue Moonlight)": "At night, a soft blue moonlight with faint moonbeams, instead of only darkness, so you can still see the fish.",
    "Moonlight": "How strong the night light is.",
    "Weather Where You Are": "Shows the weather at the place below: clouds dim the light and the rays, rain falls on the surface, fog softens everything, thunderstorms flash, snow cools the light. It asks Open-Meteo every so often, sending only the place's latitude and longitude.",
    "Find a town or city": "Type a place and press Find, then choose it from the list. What you typed is sent to Open-Meteo's place search.",
    "Use My Location": "Asks Location Services where this Mac is (macOS asks for your permission the first time).",
    "Latitude": "The place's latitude, if you'd rather type it (north is positive).",
    "Longitude": "The place's longitude, if you'd rather type it (east is positive).",
    "How Much It Shows": "How strongly the weather shows in the tank (1: normal).",
    "Check Every": "Minutes between asking for the weather.",

    // behaviour
    "Pace": "How fast all the fish swim, against calm (1); faster fish also rest less. Each fish's liveliness makes it a little quicker or slower than this.",
    "Betta Habits (Bubble Nests, Air, Flaring)": "Real betta habits: now and then darting up for a gulp of air, blowing bubbles into a nest at the top, and flaring every fin.",
    "Gets Hungry After": "Hours without food before they get hungry and wait at the front, looking out at you, until fed. 0: never.",
    "Pellets for Each Fish": "How many pellets drop for each fish when you feed them.",
    "The Cursor": "How the fish take the cursor, unless a fish has its own way (under Fish). Depends on the Fish: by its boldness and trust, from keeping away to following it about. Or always curious (comes to look), shy (keeps away), following it, or ignoring it.",
    "How Fast They Come to Trust You": "Makes trust grow faster or slower. At 1 it takes a few weeks of feeding and gentle cursor time before a fish follows the cursor.",
    "Tap the Glass (Click the Desktop)": "Clicking bare desktop taps the glass: the fish on that screen dart away, get a little upset and remember the spot, and one of them comes back later to look.",
    "Come to Say Hello When You Come Back": "When you wake or unlock the Mac, or come back after 20 minutes away, the fish that trust you swim to the front of the glass.",
    "Moods (Shown in Their Colours, Fins and Swimming)": "Lets moods show: excited, curious, bored, stressed, each in their colours, fins and the way they swim. Off: they are only ever content, hungry or sleepy.",
    "Bored After Nothing Happens For": "Hours with no food, cursor or taps before a fish gets bored and swims up and down the glass.",
    "Memory (the Cursor, Feeding Times, Favourite Spots, Taps)": "Lets the fish learn: when you usually feed them, how far to trust the cursor, a favourite spot to rest, and where the glass was tapped. Off: they learn nothing new, and trust doesn't count.",
    "Territory (Flaring at Fish Near Their Home)": "With more than one fish: each keeps a home (its favourite spot or its nest) and flares at another that comes too near, which backs off.",
    "Days to Get Used to Each Other": "How long two fish take to stop flaring at each other, counted from when the newer one joined.",
    "Young Adult At": "The age (in days) when a juvenile becomes a young adult: its fins lengthen, its colours come in, and it starts blowing nests.",
    "Grown Up At": "The age (in days) when it is fully grown: full size, full fins, full colour.",
    "Grows Old": "Lets the fish grow old: slowly a little slower and paler, with drooping fins. They never die.",
    "Old At": "The age (in days) when old age begins; it comes on over the months after.",
    "Show a Fish's Card When the Pointer Rests on It": "Rest the pointer on a fish on bare desktop (not behind a window, widget or the Dock) to see its card: name, age, mood, personality, and what it remembers.",
    "After": "How long the pointer must rest on a fish before its card shows, in seconds.",

    // screens and power
    "One Tank Across All Screens": "One tank across every screen, laid out as they are arranged in Displays settings, so the fish swim from one to the next. Off: only the main screen.",
    "Frames a Second": "How often the tank is drawn. More is smoother but uses more of the CPU; 30 is plenty for a slow fish.",
    "Pause on Battery": "Stops the animation while the Mac runs on battery, to save power.",
    "Pause in Low Power Mode": "Stops the animation while Low Power Mode is on.",
    "Open at Login": "Starts Betta Aquarium when you log in.",
    "Install the Screen Saver": "Copies the screen saver to ~/Library/Screen Savers and opens Screen Saver settings, where you choose “Betta Aquarium”. It shows your fish, environment and look.",
    "Back to How It Was Made…": "Puts every setting back as it was made. Your fish, their memories and the diary stay as they are.",

    // the diary
    "Show": "Everything, only what happened to the tank (feeding, fish leaving), or one fish's story.",
    "Clear…": "Deletes every entry in the diary.",
]

final class HoverState: ObservableObject { @Published var on = false }

/// ⓘ: what a setting does, while the pointer is on it
struct InfoButton: View {
    let text: String
    @StateObject private var hover = HoverState()
    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(hover.on ? Color.accentColor : Color.secondary)
            .onHover { hover.on = $0 }
            .popover(isPresented: $hover.on, arrowEdge: .bottom) {
                Text(text).font(.callout).padding(12).frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel(text)
    }
}

/// a setting's name, with its ⓘ
struct InfoLabel: View {
    let title: String
    let info: String?
    init(_ title: String, info: String? = nil) { self.title = title; self.info = info }
    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            if let i = info ?? SETTING_INFO[title] { InfoButton(text: i) }
        }
    }
}
