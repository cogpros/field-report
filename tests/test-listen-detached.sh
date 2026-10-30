#!/bin/bash
# fr-listen.sh must not hold the Lavish slot when nobody can act on the round.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
L="$HERE/scripts/fr-listen.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin" "$T/r"
cat > "$T/bin/lavish-axi" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
if [ "$1" = poll ]; then
  echo $$ > "$STUB_POLL_PID"
  [ -n "${STUB_POLL_SLEEP:-}" ] && sleep "$STUB_POLL_SLEEP" &
  [ -n "${STUB_POLL_SLEEP:-}" ] && wait $!
  echo "session:"; echo "  status: open"
  exit 0
fi
printf 'status: open\nurl: http://127.0.0.1:1/session/x\n'
STUB
chmod +x "$T/bin/lavish-axi"
H="$T/r/p.html"; echo '<script id="fr-state" type="application/json">{}</script>' > "$H"
export PATH="$T/bin:$PATH" STUB_LOG="$T/log" STUB_POLL_PID="$T/pid" FR_LISTEN_WATCH_INTERVAL=0.2
fail=0; ok() { echo "ok   $1"; }; no() { echo "FAIL $1"; fail=1; }

# RED: stdout on /dev/null is refused before Lavish is touched
: > "$STUB_LOG"
bash "$L" "$H" --no-probe >/dev/null 2>"$T/e"; rc=$?
{ [ "$rc" = 2 ] && [ ! -s "$STUB_LOG" ] && grep -q 'stdout is /dev/null' "$T/e"; } && ok devnull-refused || no "devnull-refused rc=$rc"

# RED: started with & from a shell that exits: the poll is released
rm -f "$STUB_POLL_PID"
STUB_POLL_SLEEP=60 bash -c "bash '$L' '$H' --no-probe >'$T/o' 2>'$T/e2' & echo \$! > '$T/lp'"
lp=$(cat "$T/lp")
for _ in $(seq 1 50); do kill -0 "$lp" 2>/dev/null || break; sleep 0.2; done
if kill -0 "$lp" 2>/dev/null; then no orphan-exits; kill "$lp"; else ok orphan-exits; fi
grep -q 'orphaned:' "$T/e2" && ok orphan-says-why || no orphan-says-why
pp=$(cat "$STUB_POLL_PID" 2>/dev/null); if [ -n "$pp" ] && kill -0 "$pp" 2>/dev/null; then no orphan-poll-gone; kill "$pp"; else ok orphan-poll-gone; fi

# GREEN: a live parent keeps the poll, and its round comes back on stdout
bash "$L" "$H" --no-probe >"$T/o3" 2>"$T/e3"; rc=$?
grep -q '^result: ' "$T/o3" && ok tracked-round-returns || no "tracked-round-returns rc=$rc"
grep -q orphaned "$T/e3" && no tracked-not-orphaned || ok tracked-not-orphaned

# GREEN: the escape hatch for a real supervisor
: > "$STUB_LOG"
FR_LISTEN_ALLOW_DETACHED=1 bash "$L" "$H" --no-probe >/dev/null 2>/dev/null
grep -q '^poll' "$STUB_LOG" && ok allow-detached || no allow-detached

# TERM on the listener takes the poll with it
rm -f "$STUB_POLL_PID"
STUB_POLL_SLEEP=60 bash "$L" "$H" --no-probe >"$T/o4" 2>"$T/e4" &
p4=$!
for _ in $(seq 1 25); do [ -s "$STUB_POLL_PID" ] && break; sleep 0.2; done
kill "$p4"; wait "$p4" 2>/dev/null; rc=$?
sleep 0.3; pp=$(cat "$STUB_POLL_PID"); if kill -0 "$pp" 2>/dev/null; then no term-takes-poll; kill "$pp"; else ok term-takes-poll; fi
exit $fail
