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
ROOTDIR="$(pwd)"

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
        --exclude '*.ase' \
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

# One payload folder per platform -- that folder, and nothing else, is what
# butler pushes. The zips go in dist/ rather than inside those folders: a zip
# sitting next to the app is a zip that gets uploaded inside the upload.
MAC="dist/mac/$NAME-mac"
WIN="dist/windows/$NAME-win64"
LIN="dist/linux/$NAME-linux"

rm -rf dist/mac dist/windows dist/linux \
       "dist/$NAME.love" "dist/$NAME-mac.zip" "dist/$NAME-win64.zip" \
       "dist/$NAME-linux.zip"
mkdir -p "$MAC" "$WIN" "$LIN" dist/.cache

# ----------------------------------------------------------------- .love
zip -9 -r -q "dist/$NAME.love" . \
    -x ".git/*" ".gitignore" "dist/*" "distribution/*" "docs/*" "*.md" "*.DS_Store" "*.sh" \
    -x "assets/(outdated)/*"

# ----------------------------------------------------------------- macOS
cp -R /Applications/love.app "$MAC/$NAME.app"
cp "dist/$NAME.love" "$MAC/$NAME.app/Contents/Resources/"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleName $TITLE" \
    -c "Set :CFBundleIdentifier com.gabrielcoffee.zombiechamber" \
    "$MAC/$NAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" \
    "$MAC/$NAME.app/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$MAC/$NAME.app"

# The app is ad-hoc signed, never notarized (that needs a paid Apple Developer
# ID). Gatekeeper therefore refuses it on first open, and since macOS 15 the
# old right-click -> Open shortcut is gone: Privacy & Security is the only
# route left. Nobody reads a store page after downloading, so the instructions
# ship inside the zip.
cat > "$MAC/README.txt" <<EOF
$TITLE — macOS

FIRST LAUNCH: macOS WILL REFUSE TO OPEN IT

You will see "Apple could not verify $TITLE is free of malware" or
"$TITLE cannot be opened". This is not a problem with the game. It happens to
every app not signed with a paid Apple Developer certificate (\$99/year), and
this one is not.

To let it through, once:

  1. Double-click $TITLE. Let macOS refuse, and click Done.
  2. Open the Apple menu -> System Settings -> Privacy & Security.
  3. Scroll down. There is a line saying "$TITLE was blocked to protect
     your Mac", with an "Open Anyway" button. Click it.
  4. Double-click $TITLE again, and click Open.

macOS remembers after that, and it opens normally forever.

If you prefer the terminal, this does the same thing in one line:

  xattr -dr com.apple.quarantine "/path/to/$NAME.app"

INSTALLING THROUGH THE ITCH.IO APP SKIPS ALL OF THIS.

---

Requires macOS 10.13 or newer, Intel or Apple Silicon.
Multiplayer is local network (LAN) co-op for up to 4 players.
EOF

# ditto, not zip: a plain zip mangles the bundle and its ad-hoc signature
ditto -c -k --sequesterRsrc --keepParent "$MAC" "dist/$NAME-mac.zip"

# --------------------------------------------------------------- windows
WINZIP="dist/.cache/love-11.5-win64.zip"
[ -f "$WINZIP" ] || curl -sL -o "$WINZIP" "$LOVE_WIN_URL"
rm -rf dist/.cache/win64
unzip -q "$WINZIP" -d dist/.cache/win64
SRC="dist/.cache/win64/love-11.5-win64"
cat "$SRC/love.exe" "dist/$NAME.love" > "$WIN/$NAME.exe"
cp "$SRC"/*.dll "$WIN/"
cp "$SRC/license.txt" "$WIN/love-license.txt"

# The .exe is unsigned (a code-signing certificate is a paid, per-year thing),
# so SmartScreen throws a full-screen warning the first time. Same reasoning as
# the macOS note: the person who needs this has already left the store page.
cat > "$WIN/README.txt" <<EOF
$TITLE — Windows

FIRST LAUNCH: WINDOWS WILL WARN YOU

You will see a blue box saying "Windows protected your PC". This is not a
problem with the game. SmartScreen shows it for any program without a paid
code-signing certificate, and this one does not have one.

To run it:

  Click "More info", then "Run anyway".

You can avoid the warning entirely by unblocking the download BEFORE you
extract it: right-click the .zip -> Properties -> tick "Unblock" -> OK.

INSTALLING THROUGH THE ITCH.IO APP SKIPS ALL OF THIS.

---

Requires 64-bit Windows. Everything needed is in this folder -- keep the DLLs
next to $NAME.exe.
Multiplayer is local network (LAN) co-op for up to 4 players.
EOF

(cd dist/windows && zip -9 -r -q "$ROOTDIR/dist/$NAME-win64.zip" "$NAME-win64")

# ----------------------------------------------------------------- linux
cp "dist/$NAME.love" "$LIN/$NAME.love"

# No Gatekeeper equivalent here -- the only thing a Linux player can be
# missing is the runtime itself.
cat > "$LIN/README.txt" <<EOF
$TITLE — Linux

Needs the LOVE 11.5 runtime (https://love2d.org):
  Ubuntu/Debian:  sudo apt install love
  Arch:           sudo pacman -S love
  Or the AppImage from love2d.org

Run:
  love $NAME.love

Multiplayer is local network (LAN) co-op for up to 4 players.
EOF
(cd dist/linux && zip -9 -r -q "$ROOTDIR/dist/$NAME-linux.zip" "$NAME-linux")

echo "Built:"
echo "  dist/$NAME.love"
echo "  $MAC/  -> dist/$NAME-mac.zip"
echo "  $WIN/  -> dist/$NAME-win64.zip"
echo "  $LIN/  -> dist/$NAME-linux.zip"
