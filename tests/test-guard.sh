#!/bin/bash
# Guard test: fresh template copy passes; stamp-stripped and old-version copies fail. Exit non-zero on any miss.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$HERE/references/canonical-template.html"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Isolation: the delivery log and the guard's defaults live under $HOME. Nothing here may
# reach the real one, so HOME moves first and the real log's line count is checked at exit.
LIVE_LOG="$HOME/1HUGR/.runtime/state/field-reports/log.jsonl"
live_lines(){ if [ -e "$LIVE_LOG" ]; then wc -l < "$LIVE_LOG" | tr -d ' '; else echo absent; fi; }
LIVE_BEFORE="$(live_lines)"
export HOME="$TMP/home"; mkdir -p "$HOME"
mkdir -p "$TMP/dash/reports"
export FR_REPORTS_DIR="$TMP/dash/reports" FR_TEMPLATE="$T"
run(){ printf '{"tool_input":{"file_path":"%s"}}' "$1" | "$HERE/scripts/field-report-guard.sh" >/dev/null 2>&1; echo $?; }
fail=0; chk(){ if [ "$2" != "$3" ]; then echo "FAIL $1: got $2 want $3"; fail=1; else echo "ok   $1 (exit $2)"; fi; }
cp "$T" "$TMP/dash/reports/fresh.html";               chk fresh-passes        "$(run "$TMP/dash/reports/fresh.html")" 0
sed '/field-report-version/d' "$T" > "$TMP/dash/reports/nostamp.html"; chk missing-stamp-fails "$(run "$TMP/dash/reports/nostamp.html")" 2
sed 's/content="4.2.0"/content="3.1.2"/' "$T" > "$TMP/dash/reports/old.html"; chk old-stamp-fails "$(run "$TMP/dash/reports/old.html")" 2
# done box must be the LAST element of its section: old (top) layout fails, template layout passes
python3 - "$T" "$TMP/dash/reports/top.html" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
lab = re.search(r'\n[ \t]*<label class="check">.*?</label>', s).group(0)
s = s.replace(lab, '', 1)
s = re.sub(r'(<section class="s"[^>]*>)', lambda m: m.group(1) + lab, s, count=1)
open(sys.argv[2], 'w').write(s)
PY
chk done-at-top-fails "$(run "$TMP/dash/reports/top.html")" 2

# PFR identity + Lavish-only delivery (v3.2.0): each of these must be rejected
R="$TMP/dash/reports"
sed 's|{TOMORROW_BANNER_PLACEHOLDER}|<div id="tomorrowBell"><span class="big">DO THIS TOMORROW</span></div>|' "$T" > "$R/bell.html"
chk tomorrowbell-filled-fails "$(run "$R/bell.html")" 2
sed 's|<title>Field report — |<title>Daily Pulse — |' "$T" > "$R/titled.html"
chk daily-pulse-title-fails "$(run "$R/titled.html")" 2
cp "$T" "$R/daily-pulse-2026-10-30.html"
chk daily-pulse-filename-fails "$(run "$R/daily-pulse-2026-10-30.html")" 2
sed 's|</body>|<p>Report: http://report-host:8989/x.html</p></body>|' "$T" > "$R/static.html" # commit-leak-scan: allow
chk static-8989-url-fails "$(run "$R/static.html")" 2
sed 's|</body>|<pre>npx -y lavish-axi x.html</pre></body>|' "$T" > "$R/unpinned.html"
chk unpinned-lavish-fails "$(run "$R/unpinned.html")" 2
sed 's|</body>|<pre>npx -y lavish-axi@0.1.76 x.html</pre></body>|' "$T" > "$R/pinbad.html"
chk pin-mismatch-fails "$(run "$R/pinbad.html")" 2
# Disk state (v4.0.0): the fr-state block is required and browser storage is rejected
sed '/<script id="fr-state"/d' "$T" > "$R/nostate.html"
chk missing-fr-state-fails "$(run "$R/nostate.html")" 2
sed 's|function restore(){|function restore(){try{localStorage.setItem("k","v")}catch(e){}|' "$T" > "$R/storage.html"
chk browser-storage-fails "$(run "$R/storage.html")" 2
sed 's|</body>|<script>sessionStorage.getItem("seed")</script></body>|' "$T" > "$R/seed.html"
chk injected-storage-seed-fails "$(run "$R/seed.html")" 2
# the placeholder-stripped banner path and the shipped example still pass
sed 's|{TOMORROW_BANNER_PLACEHOLDER}||' "$T" > "$R/empty-banner.html"
chk empty-banner-passes "$(run "$R/empty-banner.html")" 0
# the shipped example predates the version stamp (pre-existing guard failure), but the new PFR rules must not add to it
cp "$HERE/references/example.html" "$R/example.html"
ex="$(printf '{"tool_input":{"file_path":"%s"}}' "$R/example.html" | "$HERE/scripts/field-report-guard.sh" 2>&1 >/dev/null)"
if printf '%s' "$ex" | grep '^Missing' | grep -Eq 'not-a-PFR|tomorrowBell-banner|static-:8989|lavish-axi'; then echo "FAIL shipped-example-new-rules: $ex"; fail=1; else echo "ok   shipped-example-no-pfr-rule-findings"; fi # commit-leak-scan: allow

# Skill text: PFR-only identity, Lavish mandatory, no static/file fallback as delivery
S="$HERE/SKILL.md"; RD="$HERE/README.md"
has(){ if grep -Eqi -- "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1: /$2/ not in $(basename "$3")"; fail=1; fi; }
lacks(){ if grep -Eqi -- "$2" "$3"; then echo "FAIL $1: /$2/ found in $(basename "$3")"; fail=1; else echo "ok   $1"; fi; }
has skill-pfr-trigger        '^  - "PFR"' "$S"
has skill-forbids-pulse      'never produces the Daily Pulse' "$S"
has skill-lavish-mandatory   'Lavish is mandatory' "$S"
# v4.1.0 replaced the hand-typed `npx -y lavish-axi@0.1.80 poll` with scripts/fr-listen.sh; the pin itself stays named.
has skill-pinned-lavish      'npx -y lavish-axi@0\.1\.80' "$S"
has skill-listener-script    'scripts/fr-listen\.sh "\$\{REPORTS_DIR\}/<your-report-slug>\.html"' "$S"
has skill-127-fallback       '127\.0\.0\.1' "$S"
has skill-never-static       'NEVER the delivery' "$S"
has skill-working-spin       'Working spin' "$S"
has skill-poll-owning        'Poll lives in the owning session' "$S"
has readme-pfr-vs-pulse      '^## PFR vs Daily Pulse' "$RD"
has skill-answers-on-disk    'answers live on disk' "$S"
has skill-harvest-hydrate    'harvest.*then.*hydrate' "$S"
has skill-never-browser-truth 'never treat browser storage as' "$S"
has skill-never-stop-lavish  'never stop the Lavish server' "$S"
lacks skill-no-storage-promise 'persists to localStorage|localStorage persistence' "$S"
lacks skill-no-open-fallback '^   open -g "\$\{REPORTS_DIR\}' "$S"
lacks skill-no-without-lavish 'otherwise open the file' "$S"

# v4.2.0: the first serve opens in front through fr-listen.sh --open; no bare `open` in the procedure
L="$HERE/scripts/fr-listen.sh"
has skill-open-flag          'fr-listen\.sh "\$\{REPORTS_DIR\}/<your-report-slug>\.html" --open' "$S"
has skill-open-first-only    '--open is for the FIRST' "$S"
lacks skill-no-bare-open     '^   open "<session url' "$S"
has listen-open-flag         '^    --open\) do_open=1' "$L"
has listen-osascript-open    'osascript -e "open location' "$L"
has listen-open-after-probe  '^# 2b\. --open: first serve only' "$L"
# v4.2.0: the receipt rides the re-arm, never `lavish-axi reply` from inside the round
lacks listen-no-reply-receipt '"lavish-axi", "reply"' "$L"
has listen-receipt-line      'print\("receipt: %s" % receipt\)' "$L"
has listen-receipt-in-next   'lead \+ "<your reply to the operator>"' "$L"
# v4.2.0: the presence cell says what the page can prove
has template-presence-wired  '"Lavish: wired":"Lavish: absent"' "$T"
lacks template-no-listening  '"listening":"nobody listening"' "$T"
has readme-presence-wired    'Lavish: wired' "$RD"
has inventory-presence-wired 'Lavish: wired' "$HERE/references/feature-inventory.md"
lacks readme-no-agent-listening 'Agent listening' "$RD"
lacks skill-no-agent-listening 'Agent listening' "$S"
# A listener nobody can hear must not hold the slot
has listen-refuses-devnull   '/dev/fd/1 -ef /dev/null' "$L"
has listen-orphan-check      'orphaned: the session that started' "$L"
has listen-next-tracked      'run_in_background=true' "$L"
has skill-stat-placeholders  'STAT_n_NUM' "$S"

# v4.3.0: a delivery goes through the deliver binary; the old call must never come back
G="$HERE/scripts/field-report-guard.sh"
lacks skill-no-old-delivered 'fr-log\.sh delivered' "$S"
lacks guard-no-old-delivered 'fr-log\.sh delivered' "$G"
lacks guard-no-old-delivered-fmt 'fr-log.sh delivered %s' "$G"
has   skill-deliver-call 'FR_DELIVER_BIN' "$S"
has   guard-deliver-call 'FR_DELIVER_BIN' "$G"
has   readme-deliver-optional 'FR_DELIVER_BIN' "$RD"
# Step 4: a re-render is not delivered again, and every exit 1 is named by its stderr text
lacks skill-no-new-slug-recovery 're-serve under a new slug' "$S"
has   skill-rerender-not-delivered 'is not delivered again' "$S"
has   skill-new-slug-different-report 'new slug is only for a genuinely different report' "$S"
has   skill-names-invalid-slug '"invalid report slug": fix the slug' "$S"
has   skill-names-producer-busy '"producer busy; bounded lock wait expired": wait and re-run the identical command' "$S"
has   skill-names-card-failure '"card create failed"' "$S"
has   skill-link-record-purpose 'find the report and act on its PICK' "$S"
lacks skill-no-section-0-claim 'section 0[^.]*link record' "$S"
lacks guard-no-section-0-claim 'section 0[^.]*link record' "$G"
# The skill states one version: the heading and the history follow the frontmatter
VER="$(sed -n 's/^version: //p' "$S" | head -1)"; VER_RE="${VER//./\\.}"
has   skill-heading-version "^# Skill: field-report \\(PFR\\) v$VER_RE\$" "$S"
has   skill-history-version "^v$VER_RE \\(" "$S"

# v4.3.0: the reminder. The block above never reaches it (FR_REPORTS_DIR is set), so unset it here.
RR="$HOME/1HUGR/.runtime/dashboards/reports"; DEF_STATE="$HOME/1HUGR/.runtime/state/field-reports"
ST="$TMP/state"; BIN="$TMP/bin/deliver"
mkdir -p "$RR" "$ST" "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$BIN"; chmod +x "$BIN"
report(){ cp "$T" "$RR/$1.html"; echo "$RR/$1.html"; }
# guard <file> [VAR=value ...]: the guard's stdout; the caller reads its exit code from $?
guard(){ local f="$1"; shift
  printf '{"tool_input":{"file_path":"%s"}}' "$f" \
    | env -u FR_REPORTS_DIR FR_TEMPLATE="$T" "$@" "$HERE/scripts/field-report-guard.sh" 2>/dev/null; }
yes_no(){ if "$@"; then echo 1; else echo 0; fi; }
names(){ printf '%s' "$1" | grep -Fq -- "$2"; }
says(){ printf '%s' "$1" | grep -Eqi -- "$2"; }
# The reminder shell-quotes what it interpolates, so expect the quoted form on any TMPDIR.
sq(){ python3 -c 'import shlex,sys; print(shlex.quote(sys.argv[1]))' "$1"; }

# 1. reminder fires, names the deliver binary and the slug, never the old call
f="$(report remind-me)"
out="$(guard "$f" FR_STATE_DIR="$ST" FR_DELIVER_BIN="$BIN")"; rc=$?
chk reminder-exit-0            "$rc" 0
chk reminder-names-binary      "$(yes_no names "$out" "$(sq "$BIN") remind-me")" 1
chk reminder-link-record-purpose "$(yes_no names "$out" 'find the report and act on its PICK')" 1
chk reminder-no-section-0-claim "$(yes_no says "$out" 'section 0[^.]*link record')" 0
chk reminder-not-old-call      "$(yes_no names "$out" 'fr-log.sh delivered')" 0
chk reminder-is-hook-json      "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])' 2>/dev/null)" PostToolUse
# 2. the stamp lands in the state dir it was given, not the default one
chk reminder-stamp-in-state    "$(yes_no test -e "$ST/.reminded/remind-me")" 1
chk reminder-no-default-stamp  "$(yes_no test -e "$DEF_STATE/.reminded/remind-me")" 0
# 3. second write of the same slug: stamped, so silent
out="$(guard "$f" FR_STATE_DIR="$ST" FR_DELIVER_BIN="$BIN")"; rc=$?
chk reminder-once-exit-0       "$rc" 0
chk reminder-once-silent       "$out" ""
# 4. a link record and no stamp: silent, and no stamp is spent
f="$(report linked)"; mkdir -p "$ST/cards"; echo '{}' > "$ST/cards/linked.json"
out="$(guard "$f" FR_STATE_DIR="$ST" FR_DELIVER_BIN="$BIN")"; rc=$?
chk linked-exit-0              "$rc" 0
chk linked-silent              "$out" ""
chk linked-no-stamp            "$(yes_no test -e "$ST/.reminded/linked")" 0
# 5. binary absent: silent, exit 0, and no stamp, so installing it later still reminds
f="$(report no-binary)"
out="$(guard "$f" FR_STATE_DIR="$ST" FR_DELIVER_BIN="$TMP/bin/missing")"; rc=$?
chk no-binary-exit-0           "$rc" 0
chk no-binary-silent           "$out" ""
chk no-binary-no-stamp         "$(yes_no test -e "$ST/.reminded/no-binary")" 0
# 6. logged but not linked: silent while the default binary is absent, reminds once it exists
f="$(report logged-only)"; mkdir -p "$DEF_STATE" "$HOME/1HUGR/bin"
printf '{"slug": "logged-only", "state": "delivered"}\n' > "$DEF_STATE/log.jsonl"
out="$(guard "$f")"; rc=$?
chk default-binary-absent-exit-0 "$rc" 0
chk default-binary-absent-silent "$out" ""
cp "$BIN" "$HOME/1HUGR/bin/field-report-deliver.sh"
out="$(guard "$f")"; rc=$?
chk logged-only-exit-0         "$rc" 0
chk logged-only-reminds        "$(yes_no names "$out" "$(sq "$HOME/1HUGR/bin/field-report-deliver.sh") logged-only")" 1
chk logged-only-default-stamp  "$(yes_no test -e "$DEF_STATE/.reminded/logged-only")" 1
# 7. a test harness with FR_REPORTS_DIR set never gets the reminder
cp "$T" "$R/harness.html"
out="$(printf '{"tool_input":{"file_path":"%s"}}' "$R/harness.html" | FR_STATE_DIR="$ST" FR_DELIVER_BIN="$BIN" "$HERE/scripts/field-report-guard.sh" 2>/dev/null)"
chk harness-no-reminder        "$out" ""
# 8. the suggested command runs as printed when the binary, the report path, and the slug need quoting
QH="$TMP/home with space"; QR="$QH/1HUGR/.runtime/dashboards/reports"; QB="$TMP/it's delivery tools"
mkdir -p "$QR" "$QB"
cat > "$QB/deliver" <<'SH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_ARGS"
SH
chmod +x "$QB/deliver"
f="$QR/spaced slug.html"; cp "$T" "$f"
out="$(guard "$f" HOME="$QH" FR_STATE_DIR="$TMP/qstate" FR_DELIVER_BIN="$QB/deliver")"; rc=$?
chk quoted-reminder-exit-0     "$rc" 0
cmd="$(printf '%s' "$out" | python3 -c '
import json, sys
c = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"].split("run: ", 1)[1].split(" [--pick", 1)[0]
for k, v in (("<title>", "A title"), ("<url>", "http://u"), ("<seat>", "s"), ("<sections>", "2"), ("<where you stopped>", "right here")):
    c = c.replace(k, v)
print(c)' 2>/dev/null)"
STUB_ARGS="$TMP/stub-args" bash -c "$cmd" >/dev/null 2>&1; rc=$?
chk quoted-command-reaches-stub "$rc" 0
want="$(printf '%s\n' 'spaced slug' 'A title' "$f" 'http://u' s 2 --stop 'right here')"
got="$(cat "$TMP/stub-args" 2>/dev/null)"
chk quoted-command-args-intact "$(yes_no test "$got" = "$want")" 1

chk live-log-untouched "$(live_lines)" "$LIVE_BEFORE"
exit $fail
