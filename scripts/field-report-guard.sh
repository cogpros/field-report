#!/bin/bash
# field-report-guard.sh — PostToolUse hook (matcher: Write|Edit). v3.0.0.
# Canonical copy lives in the field-report skill (scripts/); install over
# ~/1HUGR/bin/field-report-guard.sh. Differences from the pre-3.0.0 guard:
#   * a report must carry <meta name="field-report-version" content="X">
#     matching the CURRENT template, read live from references/canonical-template.html.
#     Reports from an older template fail until re-rendered.
# Reads the PostToolUse JSON on stdin, extracts file_path. Env overrides (tests):
#   FR_REPORTS_DIR, FR_TEMPLATE.

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
for marker in "openedAt" "mode-toggle" 'data-cb' "copyMdBtn" "downloadMdBtn" "claudeBtn"; do
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

if [ "${#missing[@]}" -gt 0 ]; then
  cat >&2 <<MSG
[field-report-guard] NON-CANONICAL REPORT: $(basename "$FP")
Missing field-report markers: ${missing[*]}
This report is not built from the current canonical field-report template
(hand-built or an older version). Old forks lose the operator's work and miss
the frozen look.
ACTION: re-render via the field-report skill (cp references/canonical-template.html).
MSG
  exit 2
fi

# Delivery-log reminder: one per slug, never a block.
FR_LOG="$HOME/1HUGR/.runtime/state/field-reports/log.jsonl"
SLUG="$(basename "$FP" .html)"
STAMP_DIR="$HOME/1HUGR/.runtime/state/field-reports/.reminded"
if [ -z "${FR_REPORTS_DIR:-}" ]; then
  mkdir -p "$STAMP_DIR" 2>/dev/null || true
  if ! grep -q "\"slug\": \"$SLUG\"" "$FR_LOG" 2>/dev/null && [ ! -e "$STAMP_DIR/$SLUG" ]; then
    : > "$STAMP_DIR/$SLUG" 2>/dev/null || true
    python3 - "$SLUG" "$FP" <<'PY'
import json, sys
slug, fp = sys.argv[1], sys.argv[2]
msg = ("[field-report-guard] no delivery-log line for %s yet. After lavish prints the url, run: "
       "~/1HUGR/bin/fr-log.sh delivered %s \"<title>\" %s \"<url>\" eom <sections>  "
       "(url \"\" if nobody is listening). On the POST receipt: fr-log.sh state %s answered <n>. "
       "Section 0 of tomorrow's wake plan reads this log." % (slug, slug, fp, slug))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
PY
  fi
fi
exit 0
