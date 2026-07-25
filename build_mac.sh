#!/bin/sh
# Build DEADWAVE.love + fused DEADWAVE.app into dist/ (requires /Applications/love.app)
set -e
cd "$(dirname "$0")"

mkdir -p dist
rm -rf dist/DEADWAVE.love dist/DEADWAVE.app

zip -9 -r -q dist/DEADWAVE.love . \
    -x ".git/*" ".gitignore" "dist/*" "docs/*" "*.md" "*.DS_Store" "info.txt" "build_mac.sh"

cp -R /Applications/love.app dist/DEADWAVE.app
cp dist/DEADWAVE.love dist/DEADWAVE.app/Contents/Resources/
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleName DEADWAVE" \
    -c "Set :CFBundleIdentifier com.gabrielcoffee.deadwave" \
    dist/DEADWAVE.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations" \
    dist/DEADWAVE.app/Contents/Info.plist 2>/dev/null || true
codesign --force --deep --sign - dist/DEADWAVE.app

echo "Built dist/DEADWAVE.app + dist/DEADWAVE.love"
