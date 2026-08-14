#!/bin/sh
# Ship Zombie Chamber to itch.io (coffeebreak1/zombiechamber).
#
#   ./deploy.sh web             browser build  -> :html5  (smoke tests first)
#   ./deploy.sh desktop         win/mac/linux  -> :windows :osx :linux
#   ./deploy.sh all             both
#   ./deploy.sh install-butler  fetch the itch.io CLI (once, see below)
#
# Version comes from the current git tag, else the short commit hash. Pushing
# to a channel replaces that upload in place, so the page needs no clicking
# after the first time.
#
# One-time setup:
#   ./deploy.sh install-butler && butler login
#   itch.io -> Edit game -> Kind of project: HTML
#   after the first web push, tick "This file will be played in the browser"
#   on that upload, set the embed to 960x720, fullscreen button on, mobile off
set -e
cd "$(dirname "$0")"

TARGET="${1:-}"
ITCH="coffeebreak1/zombiechamber"
NAME="ZombieChamber"

case "$TARGET" in
    web|desktop|all|install-butler) ;;
    *) echo "usage: ./deploy.sh web|desktop|all|install-butler"; exit 1 ;;
esac

# There is no homebrew formula for itch's butler -- `brew install butler` gets
# Many Tricks' Butler.app, a completely unrelated macOS task launcher. The only
# supported source is broth, itch's own permanent-URL build server. butler needs
# libc7zip next to the binary, so it lives in its own directory with a symlink
# onto PATH rather than a loose binary in /opt/homebrew/bin.
BUTLER_DIR="$HOME/.local/share/itch-butler"
install_butler() {
    arch=$(uname -m)
    case "$arch" in
        arm64)  ch=darwin-arm64 ;;
        x86_64) ch=darwin-amd64 ;;
        *) echo "unsupported arch $arch -- see https://itch.io/docs/butler/installing.html"; exit 1 ;;
    esac
    tmp=$(mktemp -d)
    echo "fetching butler ($ch)..."
    curl -fL "https://broth.itch.zone/butler/$ch/LATEST/archive/default" -o "$tmp/butler.zip"
    mkdir -p "$BUTLER_DIR"
    unzip -o -q "$tmp/butler.zip" -d "$BUTLER_DIR"
    chmod +x "$BUTLER_DIR/butler"
    xattr -d com.apple.quarantine "$BUTLER_DIR"/* 2>/dev/null || true
    rm -rf "$tmp"

    for d in /opt/homebrew/bin "$HOME/.local/bin"; do
        if [ -d "$d" ] && [ -w "$d" ]; then
            ln -sf "$BUTLER_DIR/butler" "$d/butler"
            echo "linked -> $d/butler"
            "$BUTLER_DIR/butler" version
            echo "now run:  butler login"
            return
        fi
    done
    echo "installed to $BUTLER_DIR but no writable dir on PATH -- add it yourself"
    exit 1
}

if [ "$TARGET" = "install-butler" ]; then
    install_butler
    exit 0
fi

command -v butler >/dev/null || {
    echo "butler not installed:  ./deploy.sh install-butler"; exit 1; }
butler status "$ITCH" >/dev/null 2>&1 || {
    echo "butler is not logged in (or cannot see $ITCH):  butler login"; exit 1; }

VERSION=$(git describe --tags --exact-match 2>/dev/null \
          || git describe --tags 2>/dev/null \
          || git rev-parse --short HEAD)
echo "version: $VERSION"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "WARNING: uncommitted changes -- $VERSION does not describe what is being pushed"
fi

push_web() {
    ./build.sh web

    # A love.js build that fails to compile a shader is a silent black canvas:
    # no error, nothing on the itch page to tell you it is dead. Never push one
    # that has not been seen to draw.
    echo "  smoke testing..."
    if [ -d node_modules ]; then
        node web/smoke.js || { echo "!! smoke test failed -- NOT pushing"; exit 1; }
    else
        echo "  (skipped: run 'npm install' to enable the pre-push smoke test)"
    fi

    butler push dist/web "$ITCH:html5" --userversion "$VERSION"
}

push_desktop() {
    ./build.sh
    butler push "dist/windows/$NAME-win64" "$ITCH:windows" --userversion "$VERSION"
    butler push "dist/mac/$NAME.app"       "$ITCH:osx"     --userversion "$VERSION"
    butler push "dist/linux"               "$ITCH:linux"   --userversion "$VERSION"
}

case "$TARGET" in
    web)     push_web ;;
    desktop) push_desktop ;;
    all)     push_web; push_desktop ;;
esac

echo
echo "pushed $VERSION -- https://coffeebreak1.itch.io/zombiechamber"
butler status "$ITCH"
