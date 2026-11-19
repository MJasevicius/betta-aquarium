# Betta Aquarium

An endless take on [THE BETTA FISH IN ASCII](https://github.com/dwcminh/ascii-art/tree/main/BETTA-FISH) by [@dwcminh.ascii](https://instagram.com/dwcminh.ascii) as your macOS desktop wallpaper, in Swift and Metal, using a fraction
of the CPU: fish with lives of their own.

Everything in [Betta Lite](https://github.com/MJasevicius/betta-lite) (one tank across your screens, up to six fish, tapping the
glass, hunger, the water surface, sunrise and sunset, caustics, light rays) and on top of it: fish
that are each their own fish (names, personalities, moods, memory, growing up, territory), a diary,
a card for each fish, seven environments, a night light, the weather where you are, a screen saver,
and a settings window where every value can be anything, with an ⓘ beside each setting saying what
it does.

## Install

```
git clone https://github.com/MJasevicius/betta-aquarium
cd betta-aquarium
./make-app.sh
```

This builds **Betta Aquarium.app** (with an icon the fish draws itself) and puts it in
`~/Applications`. Open it from there or with Spotlight. It needs macOS 14 or later and the Xcode Command Line Tools with Swift 5.9 or later
(`xcode-select --install`). The app is signed only for your own Mac (ad hoc), as it is built there. The first build
takes about half a minute.

The fish swims on the desktop, behind your icons and windows, on every Space. The **fish icon in the
menu bar** has what you use often; **Settings…** there has everything. To start it with your Mac, turn
on **Open at Login** (Settings ▸ Screens and Power).

### The screen saver

`make-app.sh` builds a screen saver of the same tank too (your fish, environment and look; the fish
swim on the main screen, the other screens show the water). To install it:

1. Fish icon in the menu bar ▸ **Settings…** ▸ **Screens and Power** ▸ **Install the Screen Saver**.
   That copies it to `~/Library/Screen Savers` and opens Screen Saver settings.
2. In **System Settings ▸ Screen Saver**, choose **Betta Aquarium** (under *Other*).

Or by hand: double-click `~/Applications/Betta Aquarium.app/Contents/Resources/Betta
Aquarium.saver` (in Finder: right-click the app ▸ Show Package Contents), or copy it into
`~/Library/Screen Savers`. After rebuilding the app, install it again to get the new one (and if
the old one keeps showing, log out and back in: macOS holds on to screen savers it has loaded).

Only one copy runs at a time. While working on the code, `swift run -c release` runs it straight from
here (with what it costs printed every 5 seconds).

## Your fish

Each fish is its own fish, kept between launches (in `~/Library/Application Support/Betta
Aquarium/life.json`), and time goes on while the Mac is off.

- **A name and a personality:** shy or bold, lazy or lively, picky or greedy, how keen a builder of
  bubble nests, how much of a show-off. It shows in how it swims, rests, flees, eats and flares.
- **Growing up** by the calendar: a small, drab juvenile with short fins; a young adult whose fins
  lengthen and colours come in, and which starts blowing nests; a grown adult; and, if you like, old
  age, slower and paler. When each comes is yours to set, or keep a fish at an age.
- **Moods,** from what happens to it, shown in its colours, fins and swimming: content, excited (fed,
  or you just came back), hungry, expecting food, curious, sleepy (at night), bored (glass surfing
  when nothing has happened for hours), stressed (taps on the glass: it goes pale and barred and
  hides, in the cave or among the plants if there are any).
- **Memory:**
  - it learns when you usually feed it, and waits at the top around then;
  - it comes to trust the cursor: at first a shy fish keeps away and a bold one watches from a
    distance, later it comes to see, and in the end it follows the cursor about (feeding it and
    moving the cursor gently near it build trust; taps set it back; a bold fish trusts sooner);
  - it has a favourite spot it keeps going back to;
  - it remembers where the glass was tapped and keeps away for a while.
- **Together** (up to six, all males, so no surprises): each keeps a home, flares at another that comes
  too near, and the other backs off, or a bold one flares back first. Over a few weeks they get used to
  each other.
- **Coming back:** when you wake or unlock the Mac, the fish that know you come to the front to see.
- **Its card:** rest the pointer on a fish (on bare desktop) for its name, age, mood, personality,
  when it was fed, how it takes the cursor, its feeding times and its favourite spot.
- **The diary** (menu ▸ Diary…) keeps what happened: new fish, growing up, first nests and record
  ones, learned feeding times, trust won, rivalries, making peace.

Everything about a fish can be changed in Settings ▸ Fish: name, colours (the tank's, every set,
chosen sets, one set, sets by time of day, or **its own colours** from colour pickers), how often they
change, personality, age, size, fin length, how it takes the cursor, and what it remembers.

## Settings

Every number takes any value: type it, drag its slider, or pick a ready-made one from the menu beside
it. Times (sunrise, sunset) take any minute.

- **Look:** fish size, font and fill letters, the tank's colours (and your own colour sets), how
  often colours change, glow, trail, brightness, darker edges.
- **Water and Light:**
  - **Environment:** Sand and Plants, Driftwood and Moss, River Stones, Rock Cave, Sunken Ruins,
    Blackwater Leaves (tea-coloured water) or Zen Garden, or a bare tank. Each screen gets its own
    arrangement, and they keep their size whatever the fish size.
  - water surface, background bubbles, neon tetras and how many, light rays, caustics
  - **Day and night:** sunrise and sunset at any time, or the sun's own times where you are;
    twilight, how dark the night, how golden the dawn, and a **night light** (soft blue moonlight).
  - **Weather where you are** (off unless you turn it on): find your town, or use Location
    Services, or type coordinates. Clouds dim the light and rays, rain falls on the surface, fog
    softens, thunderstorms flash. From [Open-Meteo](https://open-meteo.com), sent only the place's
    latitude and longitude.
- **Behaviour:** pace, betta habits, hunger and pellets, how the cursor is taken (depends on the fish,
  or always curious, shy, following, or ignored), how fast trust grows, tapping the glass, greeting,
  moods, memory, territory and how long to get used to each other, the ages of growing up, the card.
- **Screens and Power:** one tank across all screens, frames a second, pausing on battery or in Low
  Power Mode, open at login, the screen saver, and back to how it was made.

## How it works

- **Same fish:** the geometry, lighting and choice of letters are ported line by line from the
  Python. The first ~4 s, while it draws itself, match `betta_fish.py` cell for cell.
- **Endless:** after that it never loops. It rests, turns round if it has to and swims to a random
  spot, with its habits in between. It moves as the original does: the tail and veils run late, it
  tilts its nose as it climbs or dives, and it beats its tail harder when it goes faster. When
  something cuts in (food, the mouse), it carries on from where it is at the speed it has, so it
  never jerks.
- **One tank:** the screens are laid out as they are arranged, and the water spans all of them; the
  fish may roam from one to the next. Two grids of letters lie over it: the fish's, as fine as the
  fish size asks, and the scenery's, always the same.
- **Cheap:** about 0.7 ms of CPU per frame per fish at full clock speed. Live, on one screen, roughly
  7–12% of one core; each extra screen or fish adds about 5–10%. The Python needed 56% for a window a
  third of the size. How:
  - only the ~3,000 points in front, one per cell, are lit
  - each fin's wave is worked out per row and per column instead of per point
  - the pose is a table
  - the hot data lives in buffers that are allocated once
  - the GPU does all the drawing
  - frames come from a display link at the rate you set (30 a second unless you change it)
  - it stops drawing a screen that windows cover, and a fish that is only on such screens
  - what stands still in an environment is laid out once; only the plants are worked out each frame
  - time is kept as a Double, so it is still smooth after days

## Tools for checking

```
B=$(swift build -c release --show-bin-path)/BettaAquarium
$B --bench                                   # CPU time per frame
$B --snap 300,900 --out DIR [--fish 3 --env cave --surface --company --vignette --rays 1 --caustics 1
                             --dawn 1 --feed 270 --tap 600 --ages 1,8,60 --stressed]   # frames to PNGs
$B --path 10 [--fish 3 --feed --tap --hungry --night --surface --env ID]  # swim 10 minutes unseen: what did they do?
$B --selftest                                # feeding times, the sun, growing up, every environment
$B --ui DIR                                  # the settings window's pages, to PNGs
$B --dump 2.5 FILE                           # raw 113 x 103 grid, for diffing with the Python
$B --icon FILE                               # the app icon
python tools/compare.py                      # the first seconds against the Python, cell for cell*
```

`--seed N` picks the journey for the tools; `--here` lays the tank over the screens connected now
(`--two` over two made-up ones). The tools' fish are their own, never yours. The glitter on the fins
comes from the original's numpy random numbers, baked into `Sources/BettaAquarium/Tables.swift` by
`tools/export_tables.py`.

## The code

| File | What is in it |
|---|---|
| `Fish.swift` | the fish's shape, fins, colours and how it holds itself, ported from the Python |
| `Tables.swift` | the original's random numbers for the glitter on the fins |
| `Motion.swift` | where a fish goes: a chain of legs (rest, turn, swim, flare, gulp, nest, look) chosen by its mood and personality |
| `Betta.swift` | one fish: what it does each frame (food, cursor, taps, habits), growing up, mood colours, and placing its points |
| `Tank.swift` | the water over every screen, all the fish, moods and territory, food, ripples, taps, and the two grids of letters |
| `Scenery.swift` | the environments |
| `Life.swift` | who the fish are and what they remember (saved to disk), growing up, and the diary |
| `Settings.swift` | every setting, remembered |
| `Weather.swift` | sunrise and sunset where you are, the weather, finding a place |
| `Lighting.swift` | the light over the water from the time of day, night light and weather (shared with the screen saver) |
| `Renderer.swift` | Metal: the letters, glow, trails, rays, caustics |
| `Wallpaper.swift` | a desktop-level window per screen |
| `App.swift` | the app: screens, clock, menu, taps, coming back, the card |
| `Card.swift` | a fish's card |
| `SettingsView.swift`, `SettingInfo.swift` | the settings window, and what each setting does |
| `main.swift` | starting up, and the tools above |
| `Saver/SaverView.swift` | the screen saver (built with the sources above by `make-app.sh`) |


\* `tools/compare.py` and `tools/export_tables.py` need the original: clone
[dwcminh/ascii-art](https://github.com/dwcminh/ascii-art) beside this repository (or set `BETTA_FISH_PY`
to where `betta_fish.py` is), and `pip install numpy pygame-ce`.

## What it keeps on your Mac, and removing it

- its settings: `~/Library/Preferences/io.github.mjasevicius.betta-aquarium.plist`
- your fish, their memories and the diary: `~/Library/Application Support/Betta Aquarium/`
- a short log of why a fish's card didn't show, if it ever didn't: `~/Library/Logs/Betta Aquarium.log`
- with Open at Login: `~/Library/LaunchAgents/io.github.mjasevicius.betta-aquarium.plist`
- the screen saver, once installed: `~/Library/Screen Savers/Betta Aquarium.saver`

It only uses the network for the weather, and only while that is on: the place's latitude and
longitude go to [Open-Meteo](https://open-meteo.com) (weather data by Open-Meteo.com, CC BY 4.0), and
what you type into "Find a town or city" goes to its place search. Location Services are only asked
if you press "Use My Location". To remove it: quit it, turn off Open at Login, and delete the app and
the files above.

## Credits and terms

- The fish, its look and its motion are [THE BETTA FISH IN ASCII](https://github.com/dwcminh/ascii-art/tree/main/BETTA-FISH) by [@dwcminh.ascii](https://instagram.com/dwcminh.ascii) (`betta_fish.py`). This is a remix of it,
  published with @dwcminh.ascii's permission and under the same terms as the original
  ([LICENSE.txt](LICENSE.txt)): free for personal, non-commercial use; ask @dwcminh.ascii before any
  commercial use; never pass it off as your own.
- The caustics are adapted from the Shadertoy "Tileable Water Caustic" by Dave_Hoskins, after
  joltz0r (CC BY-NC-SA 3.0).
