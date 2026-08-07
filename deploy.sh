#!/bin/sh
# Ship Zombie Chamber to itch.io (coffeebreak1/zombiechamber).
#
#   ./deploy.sh web        browser build  -> :html5   (runs the smoke test first)
#   ./deploy.sh desktop    win/mac/linux  -> :windows :osx :linux
#   ./deploy.sh all        both
#
# Version comes from the current git tag, else the short commit hash. Pushing
# to a channel replaces that upload in place, so the page needs no clicking
# after the first time.
#
# One-time setup:
#   brew install butler && butler login
#   itch.io -> Edit game -> Kind of project: HTML
#   after the first web push, tick "This file will be played in the browser"
#   on that upload, set the embed to 960x720, fullscreen button on, mobile off
set -e
cd "$(dirname "$0")"

TARGET="${1:-}"
ITCH="coffeebreak1/zombiechamber"
NAME="ZombieChamber"

case "$TARGET" in
    web|desktop|all) ;;
    *) echo "usage: ./deploy.sh web|desktop|all"; exit 1 ;;
esac

command -v butler >/dev/null || {
    echo "butler not installed:  brew install butler && butler login"; exit 1; }
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
