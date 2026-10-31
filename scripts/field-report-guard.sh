#!/bin/bash
# field-report-guard.sh — PostToolUse hook (matcher: Write|Edit). Template stamp 4.0.0.
# Canonical copy lives in the field-report skill (scripts/); install over
# ~/1HUGR/bin/field-report-guard.sh. Differences from the pre-3.0.0 guard:
#   * a report must carry <meta name="field-report-version" content="X">
#     matching the CURRENT template, read live from references/canonical-template.html.
#     Reports from an older template fail until re-rendered.
#   * PFR-only identity and Lavish-only delivery: a report that is a Daily
#     Pulse / wake-up plan / morning report, carries a filled #tomorrowBell banner,
#     points at a static :8989 url, or names an unpinned / mismatched lavish-axi is # commit-leak-scan: allow
#     rejected. HTML comments and <style> are ignored, so the template passes.
#   * disk state (4.0.0): a report must carry the <script id="fr-state"> block that
#     fr-hydrate.sh writes, and its scripts must not touch browser storage. Lavish
#     sandboxes the page without allow-same-origin, so storage throws and every
#     answer kept there is lost on reload; the answers file on disk is the record.
# Reads the PostToolUse JSON on stdin, extracts file_path. Env overrides (tests):
#   FR_REPORTS_DIR, FR_TEMPLATE, FR_STATE_DIR (default $HOME/1HUGR/.runtime/state/field-reports),
#   FR_DELIVER_BIN (default $HOME/1HUGR/bin/field-report-deliver.sh).

set -euo pipefail

REPORTS_DIR="${FR_REPORTS_DIR:-$HOME/1HUGR/.runtime/dashboards/reports}"
DASH_DIR="$(dirname "$REPORTS_DIR")"
TEMPLATE="${FR_TEMPLATE:-$HOME/.claude/skills/field-report/references/canonical-template.html}"
INPUT="$(cat 2>/dev/null || true)"

FP="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get("tool_input",{}).get("file_path",""))
except Exception:
    print("")' 2>/dev/null || true)"

case "$FP" in
  *.pre-nav-inject) exit 0 ;;
  "$DASH_DIR"/_*) exit 0 ;;
  "$DASH_DIR"/*.html) : ;;
  *) exit 0 ;;
esac

[ -f "$FP" ] || exit 0

case "$FP" in
  "$REPORTS_DIR"/buzz-day-*.html) exit 0 ;;
  "$REPORTS_DIR"/*.html) : ;;
  *) exit 0 ;;
esac

missing=()
for marker in "openedAt" "mode-toggle" 'data-cb' "copyMdBtn" "downloadMdBtn" "claudeBtn" 'id="fr-state"'; do
  grep -q "$marker" "$FP" 2>/dev/null || missing+=("$marker")
done

ver_re='<meta name="field-report-version" content="([^"]+)"'
CURRENT="$(grep -Eo "$ver_re" "$TEMPLATE" 2>/dev/null | head -1 | sed -E 's/.*content="([^"]+)"/\1/' || true)"
if [ -n "$CURRENT" ]; then
  if ! grep -Fq "<meta name=\"field-report-version\" content=\"$CURRENT\"" "$FP" 2>/dev/null; then
    HAVE="$(grep -Eo "$ver_re" "$FP" 2>/dev/null | head -1 | sed -E 's/.*content="([^"]+)"/\1/' || true)"
    missing+=("field-report-version=$CURRENT (report has: ${HAVE:-none})")
  fi
fi

# The done checkbox (label.check) must be the last element of its section.
if ! python3 - "$FP" <<'PY' 2>/dev/null
import sys
from html.parser import HTMLParser
VOID = {"input","br","img","hr","meta","link","source","col","wbr"}
class P(HTMLParser):
    # Per open section.s: depth below it, and whether its check label has closed.
    def __init__(s):
        super().__init__(); s.st=[]; s.bad=False
    def handle_starttag(s, tag, attrs):
        cls = (dict(attrs).get("class") or "").split()
        if tag == "section" and "s" in cls:
            s.st.append({"d":0,"in_label":False,"closed":False}); return
        if not s.st: return
        t = s.st[-1]
        if t["closed"] and t["d"] == 0: s.bad = True  # element after the check label
        if tag in VOID: return
        if tag == "label" and "check" in cls and t["d"] == 0: t["in_label"] = True
        t["d"] += 1
    def handle_endtag(s, tag):
        if not s.st or tag in VOID: return
        t = s.st[-1]
        if tag == "section" and t["d"] == 0: s.st.pop(); return
        t["d"] -= 1
        if tag == "label" and t["in_label"] and t["d"] == 0: t["in_label"]=False; t["closed"]=True
p = P(); p.feed(open(sys.argv[1]).read())
sys.exit(1 if p.bad else 0)
PY
then
  missing+=("done-checkbox-not-last-in-section")
fi

# PFR identity and Lavish-only delivery. Findings print one per line on stdout.
PIN="$(grep -Eo 'npx -y lavish-axi@[0-9][0-9.]*' "$TEMPLATE" 2>/dev/null | head -1 | sed -E 's/.*@//' || true)"
FTMP="$(mktemp)"
python3 - "$FP" "$PIN" > "$FTMP" 2>/dev/null <<'PY' || true
import os, re, sys
fp, pin = sys.argv[1], sys.argv[2]
src = open(fp, encoding="utf-8", errors="replace").read()
body = re.sub(r"<!--.*?-->", "", src, flags=re.S)
body = re.sub(r"<style\b.*?</style>", "", body, flags=re.S | re.I)
out = []
name = os.path.basename(fp).lower()
if re.match(r"(daily[-_ ]?pulse|wake[-_ ]?up|morning[-_ ]?report)", name):
    out.append("not-a-PFR(daily-pulse/wake-up/morning filename)")
head = " ".join(re.findall(r"<(?:title|h1)\b[^>]*>(.*?)</(?:title|h1)>", body, flags=re.S | re.I))
if re.search(r"daily\s+pulse|wake[- ]?up\s+plan|morning\s+report", head, flags=re.I):
    out.append("not-a-PFR(title/h1 names the Daily Pulse; this skill is PFR only)")
if re.search(r"""id\s*=\s*["']tomorrowBell["']""", body):
    out.append("tomorrowBell-banner-in-PFR(Daily Pulse only)")
if re.search(r":8989\b", body):  # commit-leak-scan: allow
    out.append("static-:8989-url(PFR is delivered through lavish-axi, never a static server)")  # commit-leak-scan: allow
if re.search(r"npx\s+-y\s+lavish-axi(?![@\w-])", body):
    out.append("unpinned-lavish-axi(use lavish-axi@" + (pin or "PIN") + ")")
if pin:
    bad = sorted({v for v in re.findall(r"lavish-axi@([0-9][0-9.]*)", body) if v != pin})
    if bad:
        out.append("lavish-axi-pin-mismatch(%s; template pin is %s)" % (",".join(bad), pin))
code = "\n".join(re.findall(r"<script\b(?![^>]*application/json)[^>]*>(.*?)</script>", body, flags=re.S | re.I))
code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
code = re.sub(r"(^|[^:\"'\\])//[^\n]*", r"\1", code)
if re.search(r"localStorage|sessionStorage|indexedDB", code):
    out.append("browser-storage-in-PFR(answers live on disk: fr-hydrate.sh writes #fr-state; Lavish's sandbox throws on storage)")
print("\n".join(out))
PY
while IFS= read -r finding; do
  [ -n "$finding" ] && missing+=("$finding")
done < "$FTMP"
rm -f "$FTMP"

if [ "${#missing[@]}" -gt 0 ]; then
  cat >&2 <<MSG
[field-report-guard] NON-CANONICAL REPORT: $(basename "$FP")
Missing field-report markers: ${missing[*]}
This report is not built from the current canonical field-report template
(hand-built or an older version). Old forks lose the operator's work and miss
the frozen look.
ACTION: re-render via the field-report skill (cp references/canonical-template.html).
This skill is PFR only: it never produces the Daily Pulse, and a PFR is delivered
through lavish-axi (pinned), never a static url or file://.
MSG
  exit 2
fi

# Delivery reminder: one per slug, never a block. Keyed on the link record, not the
# log row: the link record is what the morning run reads. No-op without the binary.
FR_STATE="${FR_STATE_DIR:-$HOME/1HUGR/.runtime/state/field-reports}"
DELIVER="${FR_DELIVER_BIN:-$HOME/1HUGR/bin/field-report-deliver.sh}"
SLUG="$(basename "$FP" .html)"
STAMP_DIR="$FR_STATE/.reminded"
if [ -z "${FR_REPORTS_DIR:-}" ] && [ -x "$DELIVER" ]; then
  mkdir -p "$STAMP_DIR" 2>/dev/null || true
  if [ ! -e "$FR_STATE/cards/$SLUG.json" ] && [ ! -e "$STAMP_DIR/$SLUG" ]; then
    : > "$STAMP_DIR/$SLUG" 2>/dev/null || true
    python3 - "$SLUG" "$FP" "$DELIVER" <<'PY'
import json, shlex, sys
slug, fp, deliver = sys.argv[1:4]
msg = ("[field-report-guard] %s is not linked yet. After lavish prints the url, run: "
       "%s %s \"<title>\" %s \"<url>\" <seat> <sections> --stop \"<where you stopped>\" "
       "[--pick \"<reversible action>\" --by <YYYY-MM-DD> --undo \"<reversal>\"]  "
       "(url \"\" if nobody is listening). The link record lets the morning run find the report and act on its PICK."
       % (slug, shlex.quote(deliver), shlex.quote(slug), shlex.quote(fp)))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
PY
  fi
fi
exit 0
