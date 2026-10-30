#!/bin/bash
# fr-listen.sh — the owning session's listener for one PFR (field-report v4.2.0).
#
#   fr-listen.sh <slug.html> [--open] [--agent-reply "<text>" | --agent-reply-file <path>]
#                            [--owner <label>] [--no-probe]
#
# Run this in the session that will ACT on the operator's answers, through that
# harness's tracked background facility (Claude Code: Bash run_in_background),
# so its exit resumes that same session with everything below on stdout. Run
# detached (`&`, nohup, stdout on /dev/null) it refuses or releases the poll, exit
# 2 or 6, because nothing could act on what it hears. One
# invocation = one Lavish round:
#
#   1. open    `lavish-axi <file> --no-open` (reopened once if the operator ended
#              it); the session url is printed on stderr as `session: <url>`.
#   2. probe   the url must answer 200; otherwise the 127.0.0.1 url on the same
#              port is probed. The url that answered is printed as `url: <url>`.
#              With --open (FIRST serve only, never on a re-arm) the proven url
#              is then opened in the operator's browser, in front: serving a PFR
#              IS opening it (operator, 2026-10-29). darwin: `osascript -e 'open
#              location "<url>"'`; elsewhere `xdg-open`. Printed as `opened: <url>`.
#   3. poll    `lavish-axi poll <file> --owner <label> [--agent-reply ...]`.
#              The reply, when given, is posted before the long-poll, so the
#              re-arm after a round IS the agent's reply to that round. The exact
#              two-line "poll response was interrupted / SERVER_ERROR" response
#              is retried up to 12 times, 5 s apart; everything else returns.
#   4. keep    the raw response is written to <reports>/.fr-listen/<slug>.<utc>.result
#              BEFORE it is read, so a crash past this point loses nothing.
#   5. act     a field-report POST row is written to <reports>/<slug>-answers.md
#              (a differing older file is kept as <slug>-answers.<utc>.md), the
#              delivery log is flipped (FR_LOG_BIN, default ~/1HUGR/bin/fr-log.sh,
#              skipped when absent), and the page is hydrated (fr-hydrate.sh
#              beside this script). Every other row (a freeform message, an
#              annotation) is appended to <reports>/<slug>-messages.md.
#   6. report  stdout: the lifecycle, every message verbatim, the POST summary,
#              a one-line `receipt:` for the POST, and the `next:` command, whose
#              --agent-reply already carries that receipt. The agent reads it,
#              acts, and re-arms with the receipt plus its own reply. Nothing is
#              posted to the panel from here: `lavish-axi reply` clears Lavish's
#              "working" state, and with no poll attached the panel then shows
#              "Your agent is not listening" until the re-arm (the 2026-10-29
#              flash). Carried on the re-arm, the receipt lands as the poll
#              claims the listener slot, so the panel goes Working -> listening.
#
# Exit codes: 0 feedback captured and recorded (re-arm after acting);
#             3 session ended (Send & End / End session: do NOT re-arm);
#             4 browser_disconnected (ask the operator before reopening);
#             5 waiting (another poller holds the session; do not fight it);
#             2 usage or contract error; 1 Lavish or write failure.
#
# This script never stops or restarts the Lavish server, opens a browser only
# when told to (--open), and touches no Firstmate state. It is the single
# delivery path the skill promises: the poll that wakes the session that will
# act. A poll held by a supervisor runner that wakes some OTHER session (the
# 2026-10-29 fm-pfr-open.sh design) is exactly the listener that goes deaf.
set -u

usage() { sed -n '2,/^set -u$/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
die() { printf 'fr-listen: error: %s\n' "$1" >&2; exit "${2:-1}"; }
note() { printf 'fr-listen: %s\n' "$1" >&2; }

# A listener nobody can hear is worse than none: it holds the slot, so the panel
# says the agent is listening while the operator's Send wakes no one. Both checks
# below stop that. FR_LISTEN_ALLOW_DETACHED=1 is for a supervisor that really does
# read this script's stdout and act on it.
allow_detached=${FR_LISTEN_ALLOW_DETACHED:-0}
if [ "$allow_detached" != 1 ] && [ /dev/fd/1 -ef /dev/null ]; then
  die "stdout is /dev/null, so no session can read the round. Run this through the harness's tracked background facility (Claude Code: Bash run_in_background), never \`&\`, nohup or a redirect." 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYDRATE="${FR_HYDRATE_BIN:-$SCRIPT_DIR/fr-hydrate.sh}"
LOGBIN="${FR_LOG_BIN:-$HOME/1HUGR/bin/fr-log.sh}"
OWNER="${FR_LISTEN_OWNER:-fr-listen}"
RETRY_LIMIT=12
RETRY_DELAY="${FR_LISTEN_RETRY_DELAY:-5}"

report='' reply='' reply_file='' probe=1 do_open=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent-reply) [ "$#" -ge 2 ] || usage; reply=$2; shift 2 ;;
    --agent-reply-file) [ "$#" -ge 2 ] || usage; reply_file=$2; shift 2 ;;
    --owner) [ "$#" -ge 2 ] || usage; OWNER=$2; shift 2 ;;
    --open) do_open=1; shift ;;
    --no-probe) probe=0; shift ;;
    -h|--help) usage ;;
    --*) usage ;;
    *) [ -z "$report" ] || usage; report=$1; shift ;;
  esac
done
[ -n "$report" ] || usage
[ -z "$reply" ] || [ -z "$reply_file" ] || die "pass --agent-reply or --agent-reply-file, not both" 2
case "$report" in *.html|*.htm) ;; *) die "not an HTML report: $report" 2 ;; esac
[ -f "$report" ] || die "report does not exist: $report" 2
real=$(perl -MCwd=realpath -e 'my $p = realpath($ARGV[0]); defined $p or exit 1; print "$p\n"' "$report") \
  || die "cannot resolve the report path: $report" 2
grep -q 'id="fr-state"' "$real" || die "not a v4 PFR (no fr-state block): $real" 2
command -v lavish-axi >/dev/null 2>&1 || die "lavish-axi is not on PATH (expected the machine's pinned shim)"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
reports=$(dirname "$real")
slug=$(basename "$real"); slug=${slug%.*}
keep_dir="$reports/.fr-listen"

field() { printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -1 | tr -d '"'; }
http_code() { curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$1" 2>/dev/null || true; }

# 1. open
out=$(lavish-axi "$real" --no-open) || die "lavish-axi could not open $real"
status=$(field "$out" status)
if [ "$status" = user-ended ]; then
  out=$(lavish-axi "$real" --no-open --reopen) || die "lavish-axi could not reopen $real"
  status=$(field "$out" status)
  [ "$status" != user-ended ] || die "the session for $real stays ended after --reopen"
  note "session: reopened"
fi
url=$(field "$out" url)
[ -n "$url" ] || die "lavish-axi printed no session url for $real"
note "session: $status $url"

# 2. probe
chosen=$url
if [ "$probe" -eq 1 ]; then
  code=$(http_code "$url")
  if [ "$code" != 200 ]; then
    loopback=$(printf '%s\n' "$url" | sed -E 's#^https?://[^/:]+#http://127.0.0.1#')
    [ "$loopback" != "$url" ] || die "the session url answered ${code:-no response}: $url"
    code=$(http_code "$loopback")
    [ "$code" = 200 ] || die "neither session url answered 200 ($url, $loopback answered ${code:-no response})"
    chosen=$loopback
  fi
fi
note "url: $chosen"

# 2b. --open: first serve only. The url has just answered 200, so what opens is
# the live page. A re-arm never passes --open (it would raise the window again).
if [ "$do_open" -eq 1 ]; then
  case "$(uname -s)" in
    Darwin) osascript -e "open location \"$chosen\"" >/dev/null 2>&1 ;;
    *) xdg-open "$chosen" >/dev/null 2>&1 ;;
  esac && note "opened: $chosen" || note "warning: could not open the browser; the operator must open $chosen"
fi

# 3. poll, 4. keep
mkdir -p "$keep_dir" || die "cannot create $keep_dir"
chmod 700 "$keep_dir" 2>/dev/null || true
stamp=$(date -u +%Y%m%dT%H%M%SZ)
result="$keep_dir/$slug.$stamp.$$.result"
poll_args=(poll "$real" --owner "$OWNER")
if [ -n "$reply_file" ]; then
  [ -f "$reply_file" ] || die "reply file does not exist: $reply_file" 2
  poll_args+=(--agent-reply-file "$reply_file")
elif [ -n "$reply" ]; then
  poll_args+=(--agent-reply "$reply")
fi
WATCH_INTERVAL="${FR_LISTEN_WATCH_INTERVAL:-1}"
poll_pid=''
# The poll runs through the shim (npx, then node), so stop its whole subtree. Only
# this script's own descendants: never a pattern match, never the shared server.
kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
kill_poll() { [ -z "$poll_pid" ] || kill_tree "$poll_pid"; }
trap 'kill_poll; exit 143' TERM
trap 'kill_poll; exit 130' INT
trap 'kill_poll; exit 129' HUP
interrupted=$'error: Lavish Editor poll response was interrupted\ncode: SERVER_ERROR'
attempt=0
while :; do
  note "polling (owner=$OWNER) $(date -u +%H:%M:%SZ)"
  lavish-axi "${poll_args[@]}" > "$result" 2>&1 &
  poll_pid=$!
  while kill -0 "$poll_pid" 2>/dev/null; do
    if [ "$allow_detached" != 1 ] && [ "$(ps -o ppid= -p $$ | tr -d '[:space:]')" = 1 ]; then
      # The shell that started this is gone: `&`, nohup, or the session ended.
      # Let go of the slot so the panel tells the truth. Feedback stays queued.
      kill_poll
      trap - TERM INT HUP
      die "orphaned: the session that started this listener is gone, so nobody can act on a round. Released the poll; feedback stays queued. Re-arm through the harness's tracked background facility." 6
    fi
    sleep "$WATCH_INTERVAL"
  done
  wait "$poll_pid"
  rc=$?
  if [ "$(cat "$result")" = "$interrupted" ] && [ "$attempt" -lt "$RETRY_LIMIT" ]; then
    attempt=$((attempt + 1))
    note "poll interrupted by the server; retry $attempt/$RETRY_LIMIT in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
    # A reply already posted must not be posted twice.
    poll_args=(poll "$real" --owner "$OWNER")
    continue
  fi
  break
done
[ -s "$result" ] || die "poll exited $rc with no response (kept: $result)"
note "result: $result (poll rc=$rc)"

# 5. act, 6. report
FR_RESULT="$result" FR_REAL="$real" FR_REPORTS="$reports" FR_SLUG="$slug" \
FR_HYDRATE="$HYDRATE" FR_LOGBIN="$LOGBIN" FR_SCRIPT="$0" FR_URL="$chosen" \
python3 -I - <<'PY'
import datetime, json, os, re, shlex, subprocess, sys

R = os.environ
result, real, reports, slug = R["FR_RESULT"], R["FR_REAL"], R["FR_REPORTS"], R["FR_SLUG"]
with open(result, encoding="utf-8", errors="replace") as fh:
    raw = fh.read()
lines = raw.split("\n")

# --- session block -----------------------------------------------------------
session = {}
in_s = False
for ln in lines:
    if ln == "session:":
        in_s = True; continue
    if in_s:
        if not ln.startswith((" ", "\t")):
            break
        m = re.match(r"\s+([A-Za-z_]+):\s*(.*)$", ln)
        if m:
            session[m.group(1)] = m.group(2).strip()
status = session.get("status", "")
ended = session.get("session_ended", "").lower() == "true"
first = lines[0] if lines else ""
err_code = ""
if first.startswith("error:"):
    for ln in lines[1:3]:
        m = re.match(r"code:\s*([A-Z_]+)\s*$", ln)
        if m: err_code = m.group(1)

# --- queued content (TOON table or list form) --------------------------------
def unescape(v):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)), v)

def parse_table(fields, rows):
    items = []
    for row in rows:
        row = row.lstrip()
        vals = []
        while row:
            m = re.match(r'"((?:[^"\\]|\\.)*)"', row)
            if m:
                vals.append(m.group(1)); row = row[m.end():]
            else:
                m = re.match(r"[^,]*", row)
                vals.append(m.group(0)); row = row[m.end():]
            if row.startswith(","): row = row[1:]
            else: break
        if len(vals) > len(fields):
            keep = fields.index("prompt") if "prompt" in fields else (fields.index("text") if "text" in fields else None)
            if keep is not None:
                n = len(vals) - len(fields) + 1
                vals[keep:keep + n] = [",".join(vals[keep:keep + n])]
        if len(vals) != len(fields):
            continue
        items.append({f: unescape(v) for f, v in zip(fields, vals)})
    return items

def parse_list(body):
    items, cur, unit, nested = [], None, None, False
    def field(s):
        nonlocal nested
        m = re.match(r'"((?:[^"\\]|\\.)*)"|([A-Za-z_][A-Za-z0-9_.]*)', s)
        if not m: return
        key = unescape(m.group(1)) if m.group(1) is not None else m.group(2)
        rest = s[m.end():]
        nested = False
        if re.match(r"^(?::|\[\d+\](?:\{[^}]*\})?:)\s*$", rest):
            nested = True
        elif rest.startswith(": "):
            v = rest[2:]
            if v.startswith('"'):
                mm = re.match(r'"((?:[^"\\]|\\.)*)"\s*$', v)
                if mm: cur[key] = unescape(mm.group(1))
            else:
                cur[key] = v.rstrip()
    for ln in body:
        m = re.match(r"^( *)(.*)$", ln, re.S)
        ind, rest = len(m.group(1)), m.group(2)
        if unit is None and ind > 0 and re.match(r"^-( |$)", rest):
            unit = ind
        if unit is not None and ind == unit and re.match(r"^-( |$)", rest):
            if cur: items.append(cur)
            cur = {}
            if len(rest) > 2: field(rest[2:])
        elif cur is not None and ind == 2 * unit:
            field(rest)
    if cur: items.append(cur)
    return items

items = []
i = 0
while i < len(lines):
    ln = lines[i]
    m = re.match(r"^(prompts|feedback)\[(\d+)\](?:\{([^}]*)\})?:\s*$", ln)
    if m:
        body = []
        j = i + 1
        while j < len(lines) and re.match(r"^\s", lines[j]):
            body.append(lines[j]); j += 1
        if m.group(3) is not None:
            items = parse_table(m.group(3).split(","), body[: int(m.group(2))])
        else:
            items = parse_list(body)
        break
    i += 1

# --- lifecycle ---------------------------------------------------------------
if status == "feedback": lifecycle = "feedback"
elif status == "ended": lifecycle = "ended"
elif status == "waiting": lifecycle = "waiting"
elif status == "browser_disconnected": lifecycle = "disconnected"
elif err_code == "NOT_FOUND" or first.startswith("error: No active Lavish Editor session"): lifecycle = "missing"
else: lifecycle = "unknown"

now = datetime.datetime.now(datetime.timezone.utc)
utc = now.strftime("%Y-%m-%dT%H:%M:%SZ")
cst = (now - datetime.timedelta(hours=6)).strftime("%Y-%m-%d %H:%M CST")
stamp = now.strftime("%Y%m%dT%H%M%SZ")

print("fr-listen: %s %s" % (lifecycle, real))
print("result: %s" % result)
if lifecycle == "unknown":
    print("RAW RESPONSE (unclassified):")
    for ln in lines[:40]: print("| " + ln)

# --- split rows --------------------------------------------------------------
FR_HEAD = re.compile(r'\AField report "([^"\n]*)" \(([A-Za-z0-9._-]{1,128})\)([^\n]*)\n')
posts, others = [], []
for it in items:
    text = it.get("prompt") if it.get("prompt") else it.get("text", "")
    m = FR_HEAD.match(text or "")
    if m: posts.append((it, m, text))
    else: others.append(it)

# --- messages / annotations -> <slug>-messages.md ----------------------------
msgs_path = os.path.join(reports, slug + "-messages.md")
if others:
    with open(msgs_path, "a", encoding="utf-8") as fh:
        if fh.tell() == 0:
            fh.write("# %s — messages from the report panel\n\nAppended by fr-listen.sh, newest last. Raw rounds: %s\n" % (slug, os.path.dirname(result)))
        for it in others:
            tag = it.get("tag", "") or "annotation"
            sel = it.get("selector", "")
            text = it.get("text", "")
            prompt = it.get("prompt", "")
            head = "## %s (%s) · %s" % (utc, cst, tag)
            if sel: head += " " + sel
            if ended: head += " · session ended"
            fh.write("\n" + head + "\n\n")
            body = prompt if tag == "message" else (text or prompt)
            fh.write((body or "").rstrip() + "\n")
            if tag != "message" and prompt and prompt != text:
                fh.write("\n> comment: " + prompt.rstrip().replace("\n", "\n> ") + "\n")
label = "SESSION-ENDING MESSAGE" if ended else "MESSAGE"
n_msgs = sum(1 for it in others if (it.get("tag") or "") == "message")
k = 0
for it in others:
    k += 1
    tag = it.get("tag", "") or "annotation"
    body = it.get("prompt") if tag == "message" else (it.get("text") or it.get("prompt") or "")
    print("%s %d of %d (%s%s):" % (label if tag == "message" else "ANNOTATION", k, len(others), tag,
                                   (" " + it["selector"]) if it.get("selector") else ""))
    for bl in (body or "").rstrip().split("\n"): print("| " + bl)
    if tag != "message" and it.get("prompt") and it.get("prompt") != it.get("text"):
        for bl in it["prompt"].rstrip().split("\n"): print("| comment: " + bl)
if others:
    print("recorded: %s (%d message%s, %d other)" % (msgs_path, n_msgs, "" if n_msgs == 1 else "s", len(others) - n_msgs))
else:
    print("messages: (none)")

# --- POST -> <slug>-answers.md, log, hydrate, receipt -----------------------
post_line = "post: (none)"
receipt = None
if posts:
    it, m, text = posts[-1]                     # newest field-report row wins
    title, pslug, tail = m.group(1), m.group(2), m.group(3)
    if pslug != slug:
        print("post: REFUSED — payload slug %r is not this report (%r); kept raw at %s" % (pslug, slug, result))
    else:
        body = text
        ctx = ""
        mm = re.search(r"\n\nContext data:\n(\{.*\})\s*\Z", body, re.S)
        if mm:
            ctx = mm.group(1); body = body[: mm.start()]
        body = body[m.end():]
        body = re.sub(r"\A\n+", "", body)
        # The page prefixes its export with a one-paragraph instruction to the
        # agent ("Act on the answers below..."); the record keeps the export.
        body = re.sub(r"\A(?!#)[^\n]+\n\n", "", body).rstrip() + "\n"
        n = None
        mm = re.search(r"(\d+)/(\d+) sections answered", tail)
        total = mm.group(2) if mm else "?"
        if mm: n = mm.group(1)
        elif ctx:
            try:
                data = json.loads(ctx)
                n = str(sum(1 for x in data.get("items", []) if isinstance(x, dict) and x.get("answered")))
            except ValueError:
                pass
        dest = os.path.join(reports, slug + "-answers.md")
        wrote = True
        if os.path.exists(dest):
            with open(dest, encoding="utf-8", errors="replace") as fh:
                prev = fh.read()
            if prev == body:
                wrote = False
            else:
                keep = os.path.join(reports, "%s-answers.%s.md" % (slug, stamp))
                os.replace(dest, keep)
                print("kept previous answers: %s" % keep)
        if wrote:
            tmp = dest + ".fr-listen.%d" % os.getpid()
            with open(tmp, "w", encoding="utf-8") as fh:
                fh.write(body)
            os.replace(tmp, dest)
        logged = "skipped"
        logbin = R["FR_LOGBIN"]
        if wrote and n is not None and os.access(logbin, os.X_OK):
            r = subprocess.run([logbin, "state", slug, "answered", n], capture_output=True, text=True)
            logged = "ok" if r.returncode == 0 else "failed(%d)" % r.returncode
        hyd = "skipped"
        if os.access(R["FR_HYDRATE"], os.X_OK):
            r = subprocess.run([R["FR_HYDRATE"], dest, real], capture_output=True, text=True)
            hyd = "ok" if r.returncode == 0 else "FAILED: " + (r.stderr or r.stdout).strip()
        post_line = "post: slug=%s answered=%s/%s answers=%s written=%s log=%s hydrate=%s" % (
            slug, n if n is not None else "?", total, dest, "yes" if wrote else "unchanged", logged, hyd)
        if hyd == "ok":
            receipt = "Saved %s/%s answers to %s and hydrated the page: a reload keeps them." % (
                n if n is not None else "?", total, os.path.basename(dest))
        else:
            receipt = "Received the POST (%s/%s). Answers at %s; hydrate %s." % (
                n if n is not None else "?", total, os.path.basename(dest), hyd)
print(post_line)

# The receipt is NOT posted from here. `lavish-axi reply` clears Lavish's
# "working" state, and with no poll attached the panel flashes "Your agent is
# not listening" until the re-arm. The receipt rides the re-arm's --agent-reply
# instead (printed below and pre-filled in `next:`), so the panel stays
# Working... until the poll posts receipt + reply and claims the listener slot.
# The answers are already on disk above, so a slow agent loses nothing.
if receipt and not ended and lifecycle == "feedback":
    print("receipt: %s" % receipt)

print("session: %s%s" % (status or "?", " session_ended" if ended else ""))
print("url: %s" % R["FR_URL"])
me = R["FR_SCRIPT"]
if lifecycle == "feedback" and not ended:
    lead = (receipt + " ") if receipt else ""
    print('next: %s %s --agent-reply %s   # run through the tracked background facility (Claude Code: Bash run_in_background=true), never shell & / nohup / a redirect, never --open; the reply posts before the poll' % (
        shlex.quote(me), shlex.quote(real), shlex.quote(lead + "<your reply to the operator>")))
    sys.exit(0)
if lifecycle == "ended" or ended:
    print("next: ENDED by the operator. Deliver anything left in chat. Do not re-arm or reopen uninvited.")
    sys.exit(3)
if lifecycle == "disconnected":
    print("next: the review window stayed disconnected past the grace period; ask the operator before reopening or ending.")
    sys.exit(4)
if lifecycle == "waiting":
    print("next: another poller holds this session; do not start a second one.")
    sys.exit(5)
if lifecycle == "missing":
    print("next: Lavish has no session for this file; re-run %s %s to open one." % (shlex.quote(me), shlex.quote(real)))
    sys.exit(1)
print("next: unclassified response; read the raw result above before acting.")
sys.exit(1)
PY
