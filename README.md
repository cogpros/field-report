# field-report

> Your coding agent just asked you five things. You're typing answers into a Claude CLI prompt, into Discord, into a Telegram chat, and by question three you've lost which answer goes with which question. The agent has to re-correlate. Half the time it gets it wrong.

**There's a different way to do this.** Instead of answering an agent's questions in chat, you answer in a browser tab. Each question has its own textarea, in place, next to the question. When you're done you click one button and your structured answers paste right back into the agent's terminal — as markdown, as a downloaded `.md` file, or wrapped in a ready-to-paste `claude -p '...'` shell command.

This skill teaches Claude Code that pattern. Once installed, any time the agent would otherwise dump a wall of questions into chat — decision docs, audits, brainstorms, multi-section reviews — it writes an HTML field report instead. You answer in the browser. You copy your answers back. The agent acts on a clean, structured response.

**[See it live →](https://raw.githack.com/cogpros/field-report/main/references/example.html)** — a worked demo: your agent asking you five questions before scaffolding a new project. Open it, type into the textareas, hit the copy button. Zero clone, zero install.

## Why this is a different thing

Most Claude Code skills that generate HTML output focus on display — dashboards, `/insights`-style summaries, data viz. Useful, but the loop ends once the user reads the report.

Field-report focuses on input capture. The browser is the input surface. Textareas, toggle groups, and section checkboxes record your decisions in place. A single button bundles everything back to the agent as markdown or as a `claude -p '...'` shell command. The agent gets one structured response instead of a wall of paragraph answers.

If you have ever answered five agent questions in chat and watched it confuse your answer to #2 with the placeholder you typed for #4, this is for you. If you have not, you probably will soon.

## What's in the box

Every report the skill produces comes from one canonical template (`references/canonical-template.html`). Copying that template inherits **15 baseline features plus 2 optional patterns** wired correctly — no per-report re-implementation, no drift between reports.

**Interactive input (the core pattern):**
- A textarea after every question, answered in place
- **Tab-to-fill** — focus an empty textarea, press Tab, the agent's recommended answer drops in as editable text. Accept it, rewrite it, or delete it.
- Toggle groups for go / defer / kill style decisions (single-select or multi-select)
- An open-mic textarea at the bottom for anything else

**State that survives across sessions:**
- Section checkboxes (top-right) with a live progress bar at top of viewport
- `localStorage` persistence per file — close the tab, open it tomorrow, your answers are still there
- A **POSTED** stamp that slams in across the page after any export, dated and timed, so reopens show "this one is done"
- Three timestamps in the header — Compiled (when generated), Patched (when last edited), Opened (live, set by JS on every page load). Solves the "I closed the tab because it looked stale" trap.

**Export, surface, and polish:**
- Three export buttons fixed bottom-right, collapsed to dots on load, expand on hover:
  - **Copy markdown** — your answers as a clean markdown doc, straight to clipboard
  - **Download .md** — save the markdown to a file
  - **Copy as Claude prompt** — wraps your answers in `claude -p '...'` for terminal paste
- **Per-block copy icon on every `<pre>`** — every code block (e.g. `pip install ...`) gets a small copy button in the top-right corner of the block
- Toast feedback on copy
- Light / dark mode toggle (top-right), default dark, choice persists per report
- Lede block, stat grid, tier badges, flow blocks, optional five-lens panel + synthesis block for multi-perspective reports
- Session ID embedded in three places (HTML comment, `<body data-session-id>`, exported markdown header) so a downstream agent can route the answers back to the right session

The full catalogue lives in `references/feature-inventory.md`. No external dependencies. Pure HTML + CSS + vanilla JS. Works offline.

## Install

Drop the skill into your Claude Code skills directory:

```bash
git clone https://github.com/cogpros/field-report ~/.claude/skills/field-report
```

Or symlink from a clone elsewhere:

```bash
git clone https://github.com/cogpros/field-report ~/Work/skills/field-report
ln -s ~/Work/skills/field-report ~/.claude/skills/field-report
```

Restart Claude Code. The agent picks up the skill from its `SKILL.md` description and will invoke it automatically whenever you ask for a decision doc, audit, brainstorm, or anything else that would otherwise be a wall of questions in chat. You do not type a slash command. The skill triggers on the work shape.

## First-time setup

The first time Claude invokes the skill, it asks:

> Where should interactive reports save?

Pick a folder. Common choices:
- `~/Desktop/claude-reports/`
- `~/Documents/reports/`
- A synced Google Drive / Dropbox / iCloud folder
- A folder you have wired into your own dashboard

Claude writes the path into your `CLAUDE.md` as a one-line memory and creates the directory. Every future report saves there.

You can also pre-set the path via the `CLAUDE_REPORTS_DIR` environment variable, or by adding a `reports_dir:` line to your project `CLAUDE.md`.

## Demo

`references/example.html` is the worked example linked at the top of this README. Self-referential: the agent is asking the developer which Claude Code skills to install before scaffolding a new project. Field-report is option #1 on the list.

```bash
open references/example.html
```

[Live render via raw.githack →](https://raw.githack.com/cogpros/field-report/main/references/example.html)

For the canonical template (the one the skill copies into every new report), see `references/canonical-template.html`. An earlier worked example (choosing a database for a hypothetical project, v2.0 pattern) is kept at `references/example-legacy-database.html`.

## Bring your own dashboard

The skill saves reports to a directory you configure. It does NOT ship a dashboard or auto-index — that is intentional. How you surface and browse those reports depends on your setup.

A few patterns adopters have used:

**1. A static `index.html` in the reports directory.** Write a small script (Python, Node, shell) that scans the directory and rebuilds `index.html` as a card grid. Run on a cron, on a file-watcher, or after every save. ~50 lines of code; works offline.

**2. A built-in macOS file watcher** (`launchd` + `fswatch`). Fire your index-rebuild script every time a file changes in the reports directory.

**3. Hermes hooks** (if you use Hermes). Declare a hook in `~/.hermes/config.yaml` matching write events to the reports directory; action is your rebuild script.

**4. Nothing.** Open files directly from the directory in your file browser. Fine for low volume.

The shipped reports already carry their own state — the POSTED stamp persists per-file via localStorage, and each file's `<title>`, session ID, and three timestamps give any indexer what it needs.

## When to use it

**Good fits:**
- Decision docs ("which of these three options?")
- Audits ("here is what I found — what should we fix?")
- Brainstorms ("here are ten ideas — pick the ones to pursue")
- Multi-section walkthroughs with embedded questions
- Anything where your answer needs to come back to the agent structured

**Bad fits:**
- Read-only reports (no questions, no decisions)
- Generated dashboards (data display, no input)
- Anything non-HTML

## How to customize the palette

The pattern uses four CSS variables: `--bg`, `--ink`, `--accent`, `--toast`. Define these in your report's palette and the interactive elements pick them up. The canonical template ships with a dark palette and a paired light palette swapped via the `body.light` class. See `references/interactive-pattern-snippet.html` for the drop-in CSS / HTML / JS extracted to minimum surface area.

## How it works under the hood

Each `<textarea class="note" data-q="LABEL">` registers that section's input. The export script walks every non-empty textarea, uses `data-q` as the section label or JSON key, and emits one of three formats. The buttons are wired with `addEventListener` — no framework, no build step. Checkbox state, toggle state, and textarea contents are written to `localStorage` keyed by file slug, and rehydrated on every page load.

## License

MIT. See `LICENSE.txt`.

## Background

Read `DESIGN.md` for the full why. Short version: I kept getting walls of HTML decisions from Claude, answering them by hand in chat, and losing structure. The pattern was extracted from reports I had been hand-building, then enforced as a skill so I (and my agents) stopped forgetting parts of it.
