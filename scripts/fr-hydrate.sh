#!/bin/bash
# fr-hydrate.sh — bake a report's on-disk answers into its HTML (field-report v4.0.0).
#
#   fr-hydrate.sh <slug-answers.md> <slug.html>
#
# The answers file is the record: <slug>-answers.md as the supervisor's harvest writes
# it from a Lavish POST, or as the page's receipt download lands when nobody listened.
# Both carry the gather() export. This script parses it and rewrites the single
# <script id="fr-state" type="application/json"> block in the HTML, so the page's
# restore() renders those answers on every load. The browser stores nothing.
#
# Only headings that name a data-q key in the HTML, plus "sections-completed", are read;
# anything else (a prompt header, an attach instruction) is ignored. The write is an
# atomic rename onto the real path, so a reader (Lavish reads the file on every load)
# never sees half a file and the path Lavish keys its session on never changes.
#
# Exit: 0 hydrated or already current; 2 usage or contract error (no fr-state block,
# slug mismatch, missing file); 1 write failure.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <slug-answers.md> <slug.html>" >&2
  exit 2
fi

exec python3 -I - "$1" "$2" <<'PY'
import datetime, json, os, re, sys, tempfile

answers_path, html_path = sys.argv[1], sys.argv[2]

def die(msg, code=2):
    print("fr-hydrate: " + msg, file=sys.stderr)
    sys.exit(code)

for p in (answers_path, html_path):
    if not os.path.isfile(p):
        die("not a file: " + p)

real = os.path.realpath(html_path)
with open(real, encoding="utf-8") as fh:
    html = fh.read()
with open(answers_path, encoding="utf-8", errors="replace") as fh:
    md = fh.read().replace("\r\n", "\n")

BLOCK = re.compile(r'(<script id="fr-state" type="application/json">)(.*?)(</script>)', re.S)
blocks = BLOCK.findall(html)
if len(blocks) != 1:
    die("%s has %d fr-state blocks, needs exactly 1 (render it from template v4.0.0 or later)"
        % (html_path, len(blocks)))

m = re.search(r'const fileSlug="([^"]*)"', html)
slug = m.group(1) if m else ""
for pat in (r"field-report receipt · slug=([^\s·>]+)", r'\AField report "[^"\n]*" \(([^)\s]+)\)'):
    mm = re.search(pat, md)
    if mm and slug and mm.group(1) != slug:
        die("answers are for slug %r, the report is %r; refusing to cross-wire" % (mm.group(1), slug))

# Keys the page can render: every data-q, plus the done list.
keys = set(re.findall(r'data-q="([^"]+)"', html))
DONE = "sections-completed"

# Drop the clipboard attach instruction if a pasted prompt was filed as the answers.
md = re.split(r"\n---\nTo attach a live agent to this report", md, maxsplit=1)[0]

sections, cur, buf = {}, None, []
def flush():
    if cur is not None:
        sections[cur] = "\n".join(buf).strip()
for line in md.split("\n"):
    h = re.match(r"^## (.+?)\s*$", line)
    if h and (h.group(1) in keys or h.group(1) == DONE):
        flush()
        cur, buf = h.group(1), []
    elif cur is not None:
        buf.append(line)
flush()

done = [s.strip() for s in sections.pop(DONE, "").split(",") if s.strip()]
posted = None
for pat in (r"posted=([0-9T:.\-]+Z?)", r"^_Exported ([0-9T:.\-]+Z?)_\s*$"):
    mm = re.search(pat, md, re.M)
    if mm:
        posted = mm.group(1)
        break

state = {
    "v": 1,
    "slug": slug,
    "source": os.path.basename(answers_path),
    "hydrated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "posted": posted,
    "done": done,
    "answers": sections,
}

def same(old_text):
    try:
        old = json.loads(old_text)
    except ValueError:
        return False
    if not isinstance(old, dict):
        return False
    a = {k: v for k, v in old.items() if k != "hydrated"}
    b = {k: v for k, v in state.items() if k != "hydrated"}
    return a == b

summary = "done=%d answers=%d posted=%s" % (len(done), len(sections), posted or "none")
if same(blocks[0][1]):
    print("fr-hydrate: already current: %s %s" % (html_path, summary))
    sys.exit(0)

# "<" is escaped so no answer can close the script element or open a comment.
payload = json.dumps(state, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
out = BLOCK.sub(lambda m: m.group(1) + payload + m.group(3), html, count=1)

d = os.path.dirname(real)
try:
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(real) + ".hydrate.", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(out)
    os.chmod(tmp, os.stat(real).st_mode & 0o7777)
    os.replace(tmp, real)
except OSError as e:
    try:
        os.unlink(tmp)
    except Exception:
        pass
    die("cannot write %s: %s" % (real, e), 1)
print("fr-hydrate: hydrated %s %s" % (html_path, summary))
PY
