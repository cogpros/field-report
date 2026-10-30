#!/bin/bash
# Guard test: fresh template copy passes; stamp-stripped and old-version copies fail. Exit non-zero on any miss.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$HERE/references/canonical-template.html"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
exit $fail
