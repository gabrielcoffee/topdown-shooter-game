#!/bin/sh
# Build Zombie Chamber into dist/, one folder per platform:
#   dist/ZombieChamber.love               universal LÖVE package (also the love.js input)
#   dist/mac/ZombieChamber.app + -mac.zip fused macOS app (requires /Applications/love.app)
#   dist/windows/ZombieChamber-win64/ + .zip  fused .exe + LÖVE 11.5 dlls
#   dist/linux/ZombieChamber.love + README + -linux.zip  (.love + how-to-run)
# The Windows LÖVE runtime is downloaded once into dist/.cache/.
set -e
cd "$(dirname "$0")"

NAME="ZombieChamber"
TITLE="Zombie Chamber"
LOVE_WIN_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip"

mkdir -p dist/mac dist/windows dist/linux dist/.cache
rm -rf "dist/$NAME.love" "dist/mac/$NAME.app" "dist/mac/$NAME-mac.zip" \
       "dist/windows/$NAME-win64" "dist/windows/$NAME-win64.zip" \
       "dist/linux/$NAME.love" "dist/linux/README.txt" "dist/linux/$NAME-linux.zip"

# ----------------------------------------------------------------- .love
zip -9 -r -q "dist/$NAME.love" . \
    -x ".git/*" ".gitignore" "dist/*" "docs/*" "*.md" "*.DS_Store" "info.txt" "*.sh" \
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
