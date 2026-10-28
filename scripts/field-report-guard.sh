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
