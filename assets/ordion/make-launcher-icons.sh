#!/usr/bin/env bash
#
# Regenerate the "Ordion SMS" launcher icons from the Ordion wordmark.
#
# The mark is the word "Ordion" set in Cormorant Garamond SemiBold (the site
# display face, next/font weight 600) in Ordion ink over the paper background,
# with a short teal accent rule above it - the same lockup as the marketing
# open-graph card (app/opengraph-image.tsx in the ordion repo).
#
# The font is Cormorant Garamond (SIL Open Font License 1.1). Google ships it
# as a variable font, so this script downloads that variable TTF and instances
# it at wght=600 with fonttools (in a throwaway venv). Nothing font-related is
# committed to the repo; only the rendered PNGs are.
#
# Requirements: bash, curl, python3 (for a venv + fonttools), ImageMagick 7
# (the `magick` command).
#
# Usage: assets/ordion/make-launcher-icons.sh
#
set -euo pipefail

# --- Brand palette (Ordion) ------------------------------------------------
INK="#121214"    # wordmark
PAPER="#F7FAF9"  # legacy-icon background (adaptive bg is set in values/ic_launcher_background.xml)
TEAL="#2E8F88"   # accent rule

WORD="Ordion"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RES_DIR="$REPO_ROOT/app/src/main/res"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ordion-fonts"
FONT="$CACHE_DIR/CormorantGaramond-SemiBold.ttf"
VAR_URL="https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond%5Bwght%5D.ttf"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- 1. Obtain a static weight-600 instance of Cormorant Garamond ----------
if [[ ! -f "$FONT" ]]; then
    echo "Fetching + instancing Cormorant Garamond (wght=600)..."
    mkdir -p "$CACHE_DIR"
    curl -sL "$VAR_URL" -o "$WORK/CG-var.ttf"
    python3 -m venv "$WORK/venv"
    "$WORK/venv/bin/pip" -q install fonttools >/dev/null
    "$WORK/venv/bin/fonttools" varLib.instancer "$WORK/CG-var.ttf" wght=600 -o "$FONT" >/dev/null
fi
echo "Font: $FONT"

# --- 2. Render the wordmark master (high-res, trimmed) ---------------------
magick -background none -fill "$INK" -font "$FONT" -pointsize 900 label:"$WORD" \
    -trim +repage "$WORK/word.png"

round() { awk "BEGIN{printf \"%d\", ($1)+0.5}"; }
max()   { [ "$1" -ge "$2" ] && echo "$1" || echo "$2"; }

# Build a centred lockup (accent rule above the wordmark) of a given wordmark
# width, on a transparent canvas exactly as tall as the stack.
#   $1 wordmark width px, $2 out file
make_lockup() {
    local w="$1" out="$2"
    magick "$WORK/word.png" -resize "${w}x" "$WORK/w.png"
    local wh; wh="$(magick identify -format '%h' "$WORK/w.png")"
    local rw rh gap gh
    rw="$(round "$w*0.30")"
    rh="$(max "$(round "$w*0.045")" 3)"
    gap="$(round "$w*0.12")"
    gh=$(( rh + gap + wh ))
    magick -size "${rw}x${rh}" xc:"$TEAL" "$WORK/rule.png"
    magick -size "${w}x${gh}" xc:none \
        "$WORK/rule.png" -gravity North -geometry +0+0 -composite \
        "$WORK/w.png"   -gravity South -geometry +0+0 -composite \
        "$out"
}

# --- 3. Emit the per-density icons -----------------------------------------
# density : adaptive-foreground size : legacy-icon size (both square, px)
DENSITIES="mdpi:108:48 hdpi:162:72 xhdpi:216:96 xxhdpi:324:144 xxxhdpi:432:192"

for d in $DENSITIES; do
    IFS=: read -r name fg leg <<<"$d"
    dir="$RES_DIR/mipmap-$name"
    mkdir -p "$dir"

    # Adaptive foreground: transparent, content well inside the 66dp safe zone.
    make_lockup "$(round "$fg*0.52")" "$WORK/lockup_fg.png"
    magick -size "${fg}x${fg}" xc:none "$WORK/lockup_fg.png" -gravity center -composite \
        "$dir/ic_launcher_foreground.png"

    # Legacy square icon (rounded) + round icon, paper background, for API < 26.
    make_lockup "$(round "$leg*0.60")" "$WORK/lockup_leg.png"
    r="$(round "$leg*0.18")"
    magick -size "${leg}x${leg}" xc:none -fill "$PAPER" \
        -draw "roundrectangle 0,0,$((leg-1)),$((leg-1)),$r,$r" "$WORK/bg_sq.png"
    magick "$WORK/bg_sq.png" "$WORK/lockup_leg.png" -gravity center -composite \
        "$dir/ic_launcher.png"
    magick -size "${leg}x${leg}" xc:none -fill "$PAPER" \
        -draw "circle $((leg/2)),$((leg/2)) $((leg/2)),0" "$WORK/bg_rd.png"
    magick "$WORK/bg_rd.png" "$WORK/lockup_leg.png" -gravity center -composite \
        "$dir/ic_launcher_round.png"

    echo "  mipmap-$name: foreground ${fg}px, legacy ${leg}px"
done

echo "Done. Remember: delete the old *.webp icons so each resource has one file."
