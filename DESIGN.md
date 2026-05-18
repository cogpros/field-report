# Design: field-report

## The problem this solves

When an LLM produces a document that asks the user questions, the typical loop is:

1. Agent generates a wall of HTML or markdown in chat
2. User scrolls, reads, mentally tracks question 1, question 2, question 3
3. User types answers in chat — often losing which answer maps to which question
4. Agent has to re-correlate, sometimes ambiguously

The longer the doc, the worse this gets. By question 8 the user has either lost the thread or written a wall-of-text reply with no structure.

## The asset

The interactive textarea + export pattern fixes all four steps:

1. The report renders **outside the chat window** — full screen, room to think
2. Each question has its **own textarea** — no mental mapping
3. The user **answers in place** — at the spot the question was asked
4. **One button** copies the structured answers back into chat, ready for the agent to act on

## Why a skill, not just a template

If this were a template the agent had to remember to apply, the agent would forget parts of it. Forgetting one element breaks the loop: a report with textareas but no export button is worse than a report with no textareas, because it implies a capability that isn't there.

A skill enforces the full pattern. The checklist in `SKILL.md` is the gate.

## Design choices

### Three export formats

Different users want different things back:

- **Markdown** — the default; pastes cleanly back into chat, into a doc, into a notes app
- **Download .md** — for users who want to archive answers, not just paste them
- **Claude CLI prompt** — wraps the markdown in a `claude -p '...'` shell command so the user can pipe their answers straight back to a fresh Claude invocation from the terminal

JSON export was prototyped and dropped: markdown is what the receiving agent actually reads, and JSON-wrapped markdown adds noise without adding parseability. Three buttons covers the three real workflows. Don't trim further.

### `data-q` as the source of truth

Every textarea has a `data-q` attribute. That value is used as:
- The H2 heading in exported markdown
- The key in exported JSON
- The label in the Claude CLI prompt

This means **the export format is decided when the report is built**, not at export time. The agent that generates the report controls how the answers come out. Use short, structured labels (`Q1`, `palette-decision`, `blockers`) — they end up in your downstream pipeline.

### Pure vanilla JS, no CDN

The pattern was built to work offline, with no external dependencies, and to be a single self-contained file. This matters because:

- Reports get archived. CDN links rot.
- Reports get opened on planes, on bad hotel wifi, on machines behind firewalls.
- Adding a framework just to wire four buttons is gross.

The whole export script is ~40 lines. It doesn't need help.

### Configurable save path

The first version of this skill hardcoded the save path to my own dashboard directory. Useless for anyone else. The public version asks the user where to save on first invocation, writes the choice to `CLAUDE.md`, and never asks again.

The agent does not pick a default. Picking a default that doesn't match the user's setup is worse than asking once.

### No palette

The pattern uses four CSS variables (`--bg`, `--ink`, `--accent`, `--toast`). It doesn't ship a palette. Reports that use this pattern come in every color scheme — the pattern is the structure, not the look.

## When NOT to use this skill

If a report has no decisions, no questions, no requests for feedback — don't apply the pattern. The action bar with empty buttons confuses without purpose. Read-only output is a different artifact.

## Mutation candidates

Things that could improve in future versions:

1. **`data-q` naming convention guide.** Right now it's "use lowercase-with-hyphens." Worked examples would help.
2. **Multi-textarea sections.** Some decisions have follow-up sub-questions. Right now you stack textareas, but a `data-q-group` parent would let exports nest them.
3. **Server-side push.** Currently the user has to copy or download. A future version could POST answers to a configured endpoint — useful for headless workflows.
4. **Validation.** No way for the report to mark a question as "required." Could add a `data-required` attribute that the export script checks.

These are deferred until real adoption surfaces which one matters most.

## Origin

Extracted from a personal stack where I (Dustin Pollock) had been hand-building decision-doc HTML reports for months. The pattern was stable enough across reports that it deserved enforcement. First skillified as a private tool, then refined and stripped of personal anchors for public release.

The refinement itself was done using the pattern: the agent generated an HTML report listing every personal-anchor refinement, I answered in textareas, copied the markdown back, the agent applied the changes. Loop closed on its own asset.
