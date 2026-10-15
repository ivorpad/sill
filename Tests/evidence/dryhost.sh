#!/bin/bash
# A dry-run host for evidence sessions (Tests/evidence/README.md): SillHost --synthetic with
# SILL_TEST_INPUT_LOG=1, so every event a device's input would make the Mac post is printed
# ("Test input: left mouse down (none) at 756,474") and none is posted; the Desktop is a test
# pattern, not the screen. Its stdout goes to .build/evidence/dryhost-<time>.log.
#
#   Tests/evidence/dryhost.sh start [SillHost flags...]   build (swift build --product SillHost), start, print the port
#   Tests/evidence/dryhost.sh port                        the running host's port
#   Tests/evidence/dryhost.sh stop                        stop it
#
# The port: the home door listens on a free port the system picks (never Sill.app's 7455), read here
# with lsof. A --synthetic host is off Bonjour, so a real iPhone does not find it by itself; give it
# the address and port, or start with --pairing or --remote and use the code or link the log prints.
# Scripts/sillclient.py PORT drives it from this Mac. Only one at a time (.build/evidence/dryhost.pid).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/evidence"
pidfile="$out/dryhost.pid"
mkdir -p "$out"

port_of() { { lsof -nP -iTCP -sTCP:LISTEN -a -p "$1" 2>/dev/null || true; } | awk 'NR>1 {n=split($9,a,":"); print a[n]; exit}'; }
running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

case "${1:-}" in
start)
    shift
    if running; then echo "dryhost: already running, pid $(cat "$pidfile"), port $(port_of "$(cat "$pidfile")")"; exit 1; fi
    (cd "$root" && swift build --product SillHost)
    bin="$(cd "$root" && swift build --product SillHost --show-bin-path)/SillHost"
    log="$out/dryhost-$(date +%Y%m%d-%H%M%S).log"
    SILL_TEST_INPUT_LOG=1 nohup "$bin" --synthetic "$@" > "$log" 2>&1 &
    echo $! > "$pidfile"
    port=""
    for _ in $(seq 1 100); do port="$(port_of "$(cat "$pidfile")")"; [ -n "$port" ] && break; sleep 0.1; done
    [ -n "$port" ] || { echo "dryhost: no listening port after 10 s; see $log" >&2; exit 1; }
    echo "dryhost: pid $(cat "$pidfile"), port $port, log $log"
    ;;
port)
    running || { echo "dryhost: not running" >&2; exit 1; }
    port_of "$(cat "$pidfile")"
    ;;
stop)
    running || { echo "dryhost: not running"; rm -f "$pidfile"; exit 0; }
    pid="$(cat "$pidfile")"
    kill "$pid"
    for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid"
    rm -f "$pidfile"
    echo "dryhost: stopped $pid"
    ;;
*)
    echo "usage: Tests/evidence/dryhost.sh start [SillHost flags...] | port | stop" >&2; exit 2 ;;
esac
