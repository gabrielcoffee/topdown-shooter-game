#!/bin/sh
# Build Zombie Chamber into dist/, one folder per platform:
#   dist/ZombieChamber.love               universal LÖVE package (also the love.js input)
#   dist/mac/ZombieChamber.app + -mac.zip fused macOS app (requires /Applications/love.app)
#   dist/windows/ZombieChamber-win64/ + .zip  fused .exe + LÖVE 11.5 dlls
#   dist/linux/ZombieChamber.love + README + -linux.zip  (.love + how-to-run)
# The Windows LÖVE runtime is downloaded once into dist/.cache/.
#
#   ./build.sh          desktop builds (the above)
#   ./build.sh web      dist/web/ -- the browser build, itch.io's html5 upload
#
# The web target is a SEPARATE package, not a repack of the desktop one: every
# sound is re-encoded to ogg and the long tracks are cut to loops, because
# love.js has no threads, so nothing can stream and every source is decoded
# into RAM whole. See docs/web-build-plan.md.
set -e
cd "$(dirname "$0")"

NAME="ZombieChamber"
TITLE="Zombie Chamber"
LOVE_WIN_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip"

# ------------------------------------------------------------------- web knobs
WEB_MEMORY=268435456     # emscripten heap, bytes. Static audio lives in here.
WEB_MUSIC_START=0        # secs into no_birds.mp3 the menu loop is cut from
WEB_MUSIC_LEN=60         # menu music loop length, secs
WEB_BED_LEN=40           # ambience bed loop length, secs
WEB_XFADE=2              # crossfade used to make those cuts loop seamlessly

# Homebrew's ffmpeg ships without libvorbis, so ffmpeg cuts/decodes and oggenc
# (the reference encoder) does the vorbis encoding. $1 in  $2 out  $3 quality
to_ogg() {
    ffmpeg -v error -y -i "$1" -f wav - | oggenc -Q -q "$3" -o "$2" -
}

# Cut a seamless loop: the tail is crossfaded over the head, so the file's end
# and its start are contiguous audio in the original and the seam is inaudible.
# $1 in  $2 out  $3 start  $4 length  $5 quality
loop_cut() {
    _a=$(echo "$3 + $4 - $WEB_XFADE" | bc)   # body:  start .. start+len-xfade
    ffmpeg -v error -y -i "$1" -filter_complex \
        "[0:a]atrim=start=$_a:end=$(echo "$3 + $4" | bc),asetpts=PTS-STARTPTS[tail];\
         [0:a]atrim=start=$3:end=$_a,asetpts=PTS-STARTPTS[body];\
         [tail][body]acrossfade=d=$WEB_XFADE:c1=tri:c2=tri[out]" \
        -map "[out]" -f wav - | oggenc -Q -q "$5" -o "$2" -
}

build_web() {
    command -v ffmpeg >/dev/null || { echo "web build needs ffmpeg (brew install ffmpeg)"; exit 1; }
    command -v love.js >/dev/null || { echo "web build needs love.js (npm i -g love.js)"; exit 1; }

    ROOT="$(pwd)"
    SRC="dist/.cache/web-src"
    rm -rf "$SRC" dist/web
    mkdir -p "$SRC" dist/.cache

    # ---------------------------------------------------------------- stage
    rsync -a --quiet \
        --exclude '.git' --exclude '.gitignore' --exclude '.vscode' \
        --exclude 'dist' --exclude 'distribution' --exclude 'docs' \
        --exclude '*.md' --exclude '*.sh' --exclude '.DS_Store' \
        --exclude 'info.txt' --exclude '*.ase' \
        --exclude 'assets/(outdated)' \
        --exclude 'node_modules' --exclude 'package.json' --exclude 'package-lock.json' \
        --exclude 'web' \
        ./ "$SRC/"

    # core/web.lua looks for this, and nothing else tells the two builds apart
    echo "browser build -- see docs/web-build-plan.md" > "$SRC/WEB_BUILD"

    # ------------------------------------------------------------ transcode
    # Re-encoding 110 files takes over a minute, and assets change far less
    # often than code does, so the encoded set is cached and reused until
    # something under assets/ is newer than the cache.
    CACHE="dist/.cache/web-audio"
    NEWEST=$(find assets -type f -newer "$CACHE/.stamp" -print -quit 2>/dev/null || true)
    if [ -f "$CACHE/.stamp" ] && [ -z "$NEWEST" ]; then
        echo "  reusing cached audio (delete $CACHE to force a re-encode)"
        rm -rf "$SRC/assets/music" "$SRC/assets/sounds"
        cp -R "$CACHE/music" "$SRC/assets/music"
        cp -R "$CACHE/sounds" "$SRC/assets/sounds"
        transcode_audio=false
    else
        transcode_audio=true
    fi

    if [ "$transcode_audio" = true ]; then
    echo "  transcoding audio..."

    # menu music: 12.8min @320kbps -> one short loop. Cannot stream in a tab,
    # and the full track as a static source is ~135MB of decoded PCM.
    if [ -f "$SRC/assets/music/no_birds.mp3" ]; then
        loop_cut "$SRC/assets/music/no_birds.mp3" "$SRC/assets/music/no_birds.ogg" \
                 "$WEB_MUSIC_START" "$WEB_MUSIC_LEN" 3
        rm -f "$SRC/assets/music/no_birds.mp3"
    fi

    # ambience beds: 77-94s, also streamed on desktop -> shorter loops
    for bed in "$SRC"/assets/sounds/ambient/*_bed.ogg; do
        [ -f "$bed" ] || continue
        loop_cut "$bed" "$bed.loop.ogg" 0 "$WEB_BED_LEN" 2
        mv "$bed.loop.ogg" "$bed"
    done

    # everything else -> ogg, keeping channel count (world sounds must stay
    # mono to pan). core/audio.lua falls back from .wav/.mp3 to .ogg by itself,
    # so no path in the registry has to change.
    find "$SRC/assets" \( -name '*.wav' -o -name '*.mp3' \) -print | while read -r f; do
        to_ogg "$f" "${f%.*}.ogg" 2
        rm -f "$f"
    done

    rm -rf "$CACHE"
    mkdir -p "$CACHE"
    cp -R "$SRC/assets/music" "$CACHE/music"
    cp -R "$SRC/assets/sounds" "$CACHE/sounds"
    touch "$CACHE/.stamp"
    fi

    # ---------------------------------------------------------------- .love
    LOVEFILE="dist/.cache/$NAME-web.love"
    rm -f "$LOVEFILE"
    (cd "$SRC" && zip -9 -r -q "$ROOT/$LOVEFILE" .)

    # ---------------------------------------------------------------- love.js
    echo "  running love.js..."
    love.js -c -t "$TITLE" -m "$WEB_MEMORY" "$LOVEFILE" dist/web >/dev/null

    # love.js keeps FS inside its own closure and only flushes the save dir to
    # IndexedDB on beforeunload -- an event browsers are free to skip, and
    # Safari usually does. Expose FS so index.html can sync on a timer too;
    # without this a browser player silently loses every run and setting.
    sed -i '' 's|FS.mount(IDBFS,{},"/home/web_user/love");|&Module["FS"]=FS;|' dist/web/love.js
    grep -q 'Module\["FS"\]=FS;' dist/web/love.js || {
        echo "!! love.js changed shape: save-sync hook NOT applied, saves would be lost"
        exit 1
    }

    cp web/index.html dist/web/index.html          # our loader, not the stock one
    cp assets/fonts/PressStart2P-Regular.ttf dist/web/  # the loading screen's font

    echo "Built:"
    echo "  dist/web/  ($(du -sh dist/web | cut -f1)) -- serve it, or:"
    echo "  butler push dist/web coffeebreak1/zombiechamber:html5 --userversion X.Y.Z"
}

if [ "$1" = "web" ]; then
    build_web
    exit 0
fi

mkdir -p dist/mac dist/windows dist/linux dist/.cache
rm -rf "dist/$NAME.love" "dist/mac/$NAME.app" "dist/mac/$NAME-mac.zip" \
       "dist/windows/$NAME-win64" "dist/windows/$NAME-win64.zip" \
       "dist/linux/$NAME.love" "dist/linux/README.txt" "dist/linux/$NAME-linux.zip"

# ----------------------------------------------------------------- .love
zip -9 -r -q "dist/$NAME.love" . \
    -x ".git/*" ".gitignore" "dist/*" "distribution/*" "docs/*" "*.md" "*.DS_Store" "info.txt" "*.sh" \
    -x "assets/(outdated)/*"

# ----------------------------------------------------------------- macOS
cp -R /Applications/love.app "dist/mac/$NAME.app"
cp "dist/$NAME.love" "dist/mac/$NAME.app/Contents/Resources/"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleName $TITLE" \
    -c "Set :CFBundleIdentifier com.gabrielcoffee.zombiechamber" \
    "dist/mac/$NAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" \
    "dist/mac/$NAME.app/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "dist/mac/$NAME.app"
ditto -c -k --sequesterRsrc --keepParent "dist/mac/$NAME.app" "dist/mac/$NAME-mac.zip"

# --------------------------------------------------------------- windows
WINZIP="dist/.cache/love-11.5-win64.zip"
[ -f "$WINZIP" ] || curl -sL -o "$WINZIP" "$LOVE_WIN_URL"
rm -rf dist/.cache/win64
unzip -q "$WINZIP" -d dist/.cache/win64
SRC="dist/.cache/win64/love-11.5-win64"
STAGE="dist/windows/$NAME-win64"
mkdir -p "$STAGE"
cat "$SRC/love.exe" "dist/$NAME.love" > "$STAGE/$NAME.exe"
cp "$SRC"/*.dll "$STAGE/"
cp "$SRC/license.txt" "$STAGE/love-license.txt"
(cd dist/windows && zip -9 -r -q "$NAME-win64.zip" "$NAME-win64")

# ----------------------------------------------------------------- linux
cp "dist/$NAME.love" "dist/linux/$NAME.love"
cat > dist/linux/README.txt <<EOF
$TITLE — Linux

Needs the LOVE 11.5 runtime (https://love2d.org):
  Ubuntu/Debian:  sudo apt install love
  Arch:           sudo pacman -S love
  Or the AppImage from love2d.org

Run:
  love $NAME.love
EOF
(cd dist/linux && zip -9 -q "$NAME-linux.zip" "$NAME.love" README.txt)

echo "Built:"
echo "  dist/$NAME.love"
echo "  dist/mac/$NAME.app  dist/mac/$NAME-mac.zip"
echo "  dist/windows/$NAME-win64/  dist/windows/$NAME-win64.zip"
echo "  dist/linux/$NAME.love  dist/linux/$NAME-linux.zip"
