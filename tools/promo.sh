#!/usr/bin/env bash
# Staged co-op screenshots for the itch page and posts.
#
# Each variant runs a real 4-player run headless, screenshots one frame and
# quits. The names, the wave number and the money on the HUD are all set in
# main.lua under the `promo_` args -- edit them there, not here.
#
#   bash tools/promo.sh            # all four, into dist/promo/
#   bash tools/promo.sh fight      # just one
#   bash tools/promo.sh -- win2560x1440   # every shot at a bigger size
set -euo pipefail
cd "$(dirname "$0")/.."

SAVE="$HOME/Library/Application Support/LOVE/shooter-game"
[ -d "$SAVE" ] || SAVE="$HOME/.local/share/love/shooter-game"
OUT="dist/promo"
mkdir -p "$OUT"

SHOTS=(squad fight revive board)
EXTRA=()
if [ $# -gt 0 ]; then
    if [ "$1" = "--" ]; then shift; EXTRA=("$@")
    else SHOTS=("$1"); shift; EXTRA=("$@")
    fi
fi

# a stray `--` between the variant and the love args is a separator, not an arg
CLEAN=()
for e in ${EXTRA[@]+"${EXTRA[@]}"}; do [ "$e" = "--" ] || CLEAN+=("$e"); done
EXTRA=(${CLEAN[@]+"${CLEAN[@]}"})

for s in "${SHOTS[@]}"; do
    rm -f "$SAVE/autotest.png"
    love . "promo_$s" ${EXTRA[@]+"${EXTRA[@]}"} >/dev/null 2>&1
    if [ -f "$SAVE/autotest.png" ]; then
        cp "$SAVE/autotest.png" "$OUT/zombiechamber-coop-$s.png"
        echo "  ok   $OUT/zombiechamber-coop-$s.png"
    else
        echo "  FAIL $s produced no screenshot" >&2
        exit 1
    fi
done
echo "promo shots in $OUT"
