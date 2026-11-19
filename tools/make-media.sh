#!/bin/zsh
# Renders the README's pictures into media/, and the demo video into dist/ (for the release), all
# offscreen, from the tools in the app itself.
#
#   tools/make-media.sh

set -e
cd "$(dirname "$0")/.."
swift build -c release
B="$(swift build -c release --show-bin-path)/BettaAquarium"
W=.build/media
rm -rf $W media
mkdir -p $W media dist

# the fish drawing itself in the cave; three fish of three ages
$B --gif media/drawing.gif --seconds 8 --fps 15 --width 560 --cols 150 --rows 104 --env cave --caustics 0.6 --seed 3
$B --gif media/ages.gif --from 14 --seconds 8 --fps 15 --width 640 --fish 3 --ages 1,8,90 --env driftwood --rows 150 \
    --rays 0.8 --caustics 0.5 --seed 4

# every environment, and the night light
for e in planted driftwood stones cave ruins blackwater zen; do
    $B --snap 450 --out $W/$e --env $e --rays 0.8 --caustics 0.5 --seed 3 >/dev/null &
done
$B --snap 450 --out $W/night --env planted --surface --nightlight --night 1 --rays 1 --seed 3 >/dev/null &
# a fish's card, and two upset fish hiding
$B --snap 700 --out $W/card --env driftwood --rays 1 --caustics 0.8 --card --seed 3 >/dev/null &
$B --snap 900 --out $W/stressed --fish 2 --stressed --env cave --seed 3 >/dev/null &
wait
f() { echo "$W/$1/swift_$(printf %05d $2).png" }
swift tools/grid.swift media/environments.png 2 800 "Sand and Plants=$(f planted 450)" "Driftwood and Moss=$(f driftwood 450)" \
    "River Stones=$(f stones 450)" "Rock Cave=$(f cave 450)" "Sunken Ruins=$(f ruins 450)" "Blackwater Leaves=$(f blackwater 450)" \
    "Zen Garden=$(f zen 450)" "Night Light=$(f night 450)"
sips -Z 1600 $(f card 700) --out media/card.png >/dev/null
sips -Z 1600 $(f stressed 900) --out media/stressed.png >/dev/null

# the settings window, with made-up settings and fish (nothing of yours)
$B --ui $W/ui --demo --height 900 >/dev/null
cp "$W/ui/Fish.png" media/settings-fish.png
cp "$W/ui/Water and Light.png" media/settings-water.png

# 40 seconds: two fish draw themselves, swim, are fed (15 s), and the glass is tapped (30 s)
$B --video dist/betta-aquarium-demo.mp4 --seconds 40 --width 1280 --fish 2 --env driftwood --surface --company --rays 1 \
    --caustics 0.6 --feed 450 --tap 900 --seed 6
ls -la media dist/*.mp4
