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
sed 's/content="3.0.0"/content="2.1.2"/' "$T" > "$TMP/dash/reports/old.html"; chk old-stamp-fails "$(run "$TMP/dash/reports/old.html")" 2
exit $fail
