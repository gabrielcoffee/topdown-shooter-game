#!/usr/bin/env bash
# Two-process LAN check: one copy of the game hosts, another joins over
# loopback, and both have to reach the run together.
#
# Covers the parts the in-process selftest cannot, because net/session.lua is
# a singleton: the beacon being seen by a separate process, the HELLO/WELCOME
# handshake, slot assignment, roster sync, ready, and START.
#
#   tools/lantest.sh          # run it
#   tools/lantest.sh -v       # also dump both logs

set -uo pipefail
cd "$(dirname "$0")/.."

LOVE="${LOVE:-$(command -v love || echo /Applications/love.app/Contents/MacOS/love)}"
[ -x "$LOVE" ] || { echo "love not found; set LOVE=/path/to/love"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; pkill -f "love \. lanhost" 2>/dev/null; pkill -f "love \. lanjoin" 2>/dev/null' EXIT

HOST_LOG="$TMP/host.log"
JOIN_LOG="$TMP/join.log"

echo "== starting host =="
"$LOVE" . lanhost 25 >"$HOST_LOG" 2>&1 &
HOST_PID=$!

# let the host bind its port and get a beacon out
sleep 2

if ! kill -0 "$HOST_PID" 2>/dev/null; then
    echo "FAIL: host exited early"
    cat "$HOST_LOG"
    exit 1
fi

echo "== starting client =="
"$LOVE" . lanjoin 127.0.0.1 >"$JOIN_LOG" 2>&1
JOIN_RC=$?

wait "$HOST_PID"
HOST_RC=$?

if [ "${1:-}" = "-v" ]; then
    echo "--- host log ---"; grep '^LAN' "$HOST_LOG"
    echo "--- client log ---"; grep '^LAN' "$JOIN_LOG"
fi

fail=0
check() { # check <label> <file> <pattern>
    if grep -q "$3" "$2"; then
        echo "  ok   $1"
    else
        echo "  FAIL $1"
        fail=1
    fi
}

echo "== results =="
check "host started listening"      "$HOST_LOG" '^LAN HOSTING'
check "client saw the LAN beacon"   "$JOIN_LOG" '^LAN DISCOVERED'
check "client was admitted"         "$JOIN_LOG" '^LAN ADMITTED slot=2'
check "client sees the host"        "$JOIN_LOG" '^LAN SAW_HOST true'
check "host saw the client ready"   "$HOST_LOG" '^LAN CLIENT_READY'
check "host started the run"        "$HOST_LOG" '^LAN STARTED state=playing'
check "client reached the run"      "$JOIN_LOG" '^LAN PLAYING'
check "host built a 2-player world" "$HOST_LOG" '^LAN HOST_WORLD players=2'
check "client world is a puppet"    "$JOIN_LOG" '^LAN CLIENT_WORLD authoritative=false'
check "host player replicated"      "$JOIN_LOG" '^LAN SYNCED_PLAYERS n=2'
check "zombies replicated"          "$JOIN_LOG" '^LAN SYNCED_ZOMBIES n=5 want=5'
check "movement keeps replicating"  "$JOIN_LOG" '^LAN SYNCED_MOVE'
check "host passed"                 "$HOST_LOG" '^LAN PASS host'
check "client passed"               "$JOIN_LOG" '^LAN PASS client'

if [ "$HOST_RC" -ne 0 ]; then echo "  FAIL host exit code $HOST_RC"; fail=1; fi
if [ "$JOIN_RC" -ne 0 ]; then echo "  FAIL client exit code $JOIN_RC"; fail=1; fi

if [ "$fail" -eq 0 ]; then
    echo "LANTEST PASS"
else
    echo "LANTEST FAIL"
    echo "--- host log ---"; grep '^LAN\|^CRASH\|Error' "$HOST_LOG" | head -20
    echo "--- client log ---"; grep '^LAN\|^CRASH\|Error' "$JOIN_LOG" | head -20
fi
exit "$fail"
