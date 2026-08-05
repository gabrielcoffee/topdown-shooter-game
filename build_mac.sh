#!/bin/sh
# Build CHAMBER9.love + fused CHAMBER9.app into dist/ (requires /Applications/love.app)
set -e
cd "$(dirname "$0")"

mkdir -p dist
rm -rf dist/CHAMBER9.love dist/CHAMBER9.app

zip -9 -r -q dist/CHAMBER9.love . \
    -x ".git/*" ".gitignore" "dist/*" "docs/*" "*.md" "*.DS_Store" "info.txt" "build_mac.sh"

cp -R /Applications/love.app dist/CHAMBER9.app
cp dist/CHAMBER9.love dist/CHAMBER9.app/Contents/Resources/
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleName CHAMBER 9" \
    -c "Set :CFBundleIdentifier com.gabrielcoffee.chamber9" \
    dist/CHAMBER9.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" \
    dist/CHAMBER9.app/Contents/Info.plist 2>/dev/null || true
codesign --force --deep --sign - dist/CHAMBER9.app

# zip of the .app for itch upload (ditto keeps signature + Finder metadata)
rm -f dist/CHAMBER9.zip
ditto -c -k --sequesterRsrc --keepParent dist/CHAMBER9.app dist/CHAMBER9.zip

echo "Built dist/CHAMBER9.app + dist/CHAMBER9.love + dist/CHAMBER9.zip"
