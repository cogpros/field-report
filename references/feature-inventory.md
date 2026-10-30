# Field Report UI Feature Inventory

Last updated: 2026-09-17 (v2.3.0) · Originally audited from 13 field reports over 48 hours (2026-05-17)

## Patterns (18 baseline + 2 optional + 3 foundational)

### 1. Section Checkboxes (Bottom)
**Status:** Canonical
**What it does:** Each section ends with a done checkbox, right-aligned at the bottom, the last element of the section (dashed rule above it). Toggle to mark done. Section dims and text strikes through when complete.
**Notes:** New pattern, replacing an older tier-badge approach.

### 2. Progress Bar + Label
**Status:** Canonical
**What it does:** Fixed progress bar at top of viewport. Shows "X / Y sections completed". Updates live as checkboxes toggle.

### 3. Tab-to-Fill on Textareas
**Status:** Canonical
**What it does:** Focus an empty textarea, hit Tab. The placeholder text drops in as editable, pre-selected. The reader can keep it, edit it, or delete it.
**Notes:** Lets the writing agent pre-fill its recommendation as a draft answer the user can accept or rewrite.

### 4. Tier Badges (Colored Labels)
**Status:** Canonical
**What it does:** Tier blocks (`.tier.t0/t1/t2/t3`) with colored left borders and badge labels (e.g. Architecture lock, Sub-decisions).
**Notes:** Older pattern; still valuable for tier organization alongside section checkboxes.

### 5. Flow Blocks (Code-like Flow Visualization)
**Status:** Canonical
**What it does:** `.flow` elements. Monospace, pre-formatted, shows multi-step sequences with arrows / visual flow.
**Notes:** Used for architectural flows and command sequences.

### 6. POSTED Stamp Animation
**Status:** Canonical
**What it does:** Large "POSTED" watermark that slams in when POST, "Copy markdown" or "Copy as Claude prompt" is clicked. Shows the timestamp. Since v4.0.0 the slam lives in this tab only; on load the stamp shows the posted time from the disk state (`fr-state.posted`), so it appears exactly when the answers are on disk. The v3 localStorage stamp and its stale-stamp guard are gone.
**Notes:** Critical UX signal that the report was captured — when the user reopens later, the stamp tells them this one is done.

### 7. Copy Buttons + Toast Feedback
**Status:** Canonical
**What it does:** Three export buttons fixed bottom-right. "Copy markdown" pink, "Download .md" brown, "Copy as Claude prompt" amber. Toast notification on success. Those export buttons collapse to dots on page load and expand on hover. The POST button stays the word POST at full size with no hover reveal (v2.4.1).

### 8. Per-Block Code Copy Icon
**Status:** Canonical (added 2026-05-17, public-ship v2.1.1)
**What it does:** Every `<pre>` block gets a small "copy" button in the top-right corner of the block. Hover the block to reveal it; click to copy the block's text content. Button flashes green and reads "copied" on success.
**Why:** Reports often include shell commands (`pip install ...`, `git clone ...`). Selecting and copying without an icon is friction. Per-block copy makes it zero-click.

### 9. Lede Block (Pink Intro Box)
**Status:** Canonical
**What it does:** Introductory box with pink left border, italic text. Explains the report's purpose. First thing after title / tags.

### 10. Stat Grid (Totals)
**Status:** Canonical
**What it does:** Grid of stat cards below the lede. Key numbers (sections, items, timings). Auto-wraps to fit screen.

### 11. Session-ID Embedding (Three Places)
**Status:** Canonical
**What it does:** Session ID appears in (a) HTML comment at top, (b) `data-session-id` attribute on `<body>`, (c) exported markdown header.
**Notes:** Lets a downstream agent recognize which session produced the report when answers come back.

### 12. Toggle Groups (Go/Defer/Kill Color States)
**Status:** Canonical
**What it does:** `.toggles` containers with `.toggle` buttons. `go` = green, `defer` = amber, `kill` = red when active. Single-select by default; multi-select when the container has the `multi` class.
**Notes (v2.4.1, 2026-10-27):** the init script stamps `data-lavish-action` on every `.toggle`. Without it, Lavish treats a click on a non-native element as "annotate this" and opens a comment box instead of selecting (operator report, devcon-models-2026-10-27). Reports built before v2.4.1 keep the bug under Lavish; checkboxes always worked because native inputs pass through.

### 13. Light/Dark Mode Toggle (Top-Right)
**Status:** Canonical (added for public ship 2026-05-17)
**What it does:** Small button fixed top-right (`right:160px` to clear the progress label). Toggles `body.light` class which swaps the entire CSS variable palette. Default is dark. Button text is `→ Light` (dark mode) or `→ Dark` (light mode). This tab only since v4.0.0 (the page stores nothing in the browser).
**Notes:** Default dark suits long sessions; the toggle is mandatory because some adopters strongly prefer light. Light palette mirrors the dark variables; headings need explicit `body.light h1/h2/h3` rules where the dark theme used hardcoded light values.

### 14. Disk state + restore (v4.0.0; replaces localStorage persistence)
**Status:** Canonical
**What it does:** The answers live in `<slug>-answers.md` on disk. `scripts/fr-hydrate.sh <answers.md> <html>` bakes them into the page's `<script id="fr-state" type="application/json">` block by atomic rename; `restore()` reads that block and nothing else. Toggles, textareas and done boxes render from it; an unanswered textarea shows its authored text. The `Answers` meta cell reads `on disk <time>` once hydrated and `unsaved · press POST` after any edit. **Agent reopen:** `<section class="s" data-reopen="<ISO time>">` unchecks on load a done box whose answers were posted before that time (`fr-state.posted`) and shows a REOPENED note; sections without the attribute never lose state.
**Why:** Operator, 2026-10-29: "every box i have checked done, needs to remain done when i come back, unless your work opens it back up." The v3.1.2 fix (per-key localStorage merge, `storage` event sync) could not deliver that: Lavish serves the page in an iframe sandboxed without `allow-same-origin` (lavish-axi 0.1.80 `dist/cli.mjs:12024`), where `localStorage` throws `SecurityError`, and every save was swallowed by a `try/catch`. Reloads under Lavish were empty by construction. Decision D-2026-10-30-9: the page is not the record. Test: `node tests/test-disk-state.js` (forced reds first; jsdom with a throwing storage getter; headless Chrome under Lavish's exact sandbox string).

### 15. Three-Timestamp Header (Compiled · Patched · Opened)
**Status:** Canonical (added 2026-05-17 after a stale-timestamp incident)
**What it does:** Header row shows three timestamps: `Compiled` (original generation, static), `Patched` (last write, static, updated on edit), `Opened` (live, rendered by JS on each page load via `<span id="openedAt">`). Solves the "I closed the tab because it looked stale" problem — the Opened timestamp always reads current.
**Notes:** Mandatory going forward. A single timestamp misleads when a report is generated once and viewed later.

### 16. Floating Notes Panel
**Status:** Canonical (added 2026-09-07, template v2.2.0)
**What it does:** A small fixed panel (`#floatNotes`) anchored bottom-right that follows the reader down the page. Contains a header (click to collapse/expand, this tab only) and a textarea mirroring the report's open-notes textarea — typing in either updates the other in real time. The mirror holds no state of its own (no `data-q` on purpose; it pushes into the real textarea and dispatches `input`, so the export and the unsaved marker see it).
**Origin:** user request, 2026-09-07: "is there a way to have the open notes section as a floating section that follows me the whole way down?"
**v2.3.0 note:** hidden while an agent is listening (lavish present); lavish's Conversation panel takes its place. Operator, 2026-09-17, annotating the panel inside lavish: "this notes section is no longer needed". Still shown on direct opens.

### 17. Agent wire (POST + presence)
**Status:** Canonical (added 2026-09-17, template v2.3.0)
**What it does:** A `POST` button (first in the button bar) and an `Agent` presence cell in the meta-status row. The page reads whether `window.lavish` exists, i.e. whether lavish-axi served it and an agent is polling. Listening: POST queues one prompt carrying the full markdown export plus a batch header (sections answered, sections changed since last POST) via `window.lavish.queuePrompt`, and the user presses lavish's Send to Agent. Nobody listening (file://, static server, tablet): POST copies the identical batch to the clipboard with an attach instruction (`npx -y lavish-axi@0.1.80 <path>` then `poll`; one pin per machine), so pasting it into any agent both delivers the answers and tells that agent how to start listening. "Copy as Claude prompt" carries the same instruction. Changed-since-last-POST diffs each section against what the page loaded from disk, then against this tab's last POST (in memory; v4.0.0).
**Why:** NOW and LATER are a fact the page reads, never a mode the user picks. Origin: operator, 2026-09-17: "i want a choice about whether to run the now version or the later version… and the later version needs to have a copy command to put back into an agent to turn it into the now version."
**Button bar while listening:** only POST is shown; Copy markdown, Download .md and Copy as Claude prompt are the LATER path and reappear when nobody is listening. POST reads POST and stays visible without hover (v2.4.1). Operator, 2026-09-17, via lavish: "remove all buttons but post if it works. the other buttons are only needed if a field report stays for later." The floating notes panel hides on the same condition.
**Transport:** lavish-axi (github.com/kunchenguid/lavish-axi). Field-report ships no server. lavish stays optional: without it the page behaves exactly as v2.2.0 plus the attach instruction.

## Optional patterns (synthesis-heavy reports)

### O1. Five-Lens Panel (Parallel Reframes)
**Status:** Optional
**What it does:** `.lens-grid` with five `.lens-card` elements. Each card is a named perspective (Marie Kondo, Sun Tzu, Philip K. Dick, Buffett, Bugs Bunny in the source pattern) with its own textarea. Often followed by a synthesis block.

### O2. Synthesis Block (Italic Summary)
**Status:** Optional
**What it does:** `.synthesis` element. Italic serif text with a "synthesis · 3 lines" label. Summarizes findings from the preceding section.

## Implicit baseline (dots-on-hover button bar)

The button bar's collapse-to-dots / expand-on-hover behavior is part of feature 7. Counts as a single feature with the export buttons, not a separate baseline number.

## Feature Count
- **Baseline (every report):** 17 numbered patterns
- **Optional (synthesis-heavy reports):** 2 patterns (five-lens panel, synthesis block)
- **Foundational (color scheme, fonts, spacing — not numbered above):** 3

## Design preferences baked into the canonical template

1. Dark mode default, light toggle available
2. Section checkboxes + progress bar (preferred over older tier-only patterns)
3. Tab-to-fill on textareas
4. POSTED stamp on copy (UX signal)
5. Session-ID embedded in three places (multi-session continuity)
6. Answers on disk, page as renderer (`fr-state` + `fr-hydrate.sh`; no browser storage)
7. Portable template (no hardcoded user paths in the template body)

## Clipboard sandbox fallback (v2.1.3, 2026-07-30)

**Status:** baseline — folded into feature 7 (copy buttons) and feature 8 (per-block code copy). Not a new number.

**What it does:** all three export buttons and every code-block copy icon route through a shared
`copyText(text)` helper instead of calling `navigator.clipboard.writeText` directly. The helper
tries `navigator.clipboard` only when `window.isSecureContext` is true, and otherwise falls back
to a hidden `<textarea>` + `document.execCommand("copy")`, which still succeeds inside a
user-gesture handler in restricted contexts.

**Why it exists:** reports were briefly mirrored as hosted Artifacts (2026-07-06 to
2026-08-02). That mirror runs in a **sandboxed iframe** where `navigator.clipboard` is
unavailable and localStorage is partitioned. Result: on the mirror, all copy buttons failed
with "Copy failed", the POSTED stamp never fired, and checkbox/textarea state did not persist.
The same failure hits some `file://` origins.

**Origin:** 2026-07-30. The user worked in the mirror copy — because that was the copy open in
front of them — and every button died. Two rounds of debugging were spent on the local file,
which was never the broken one.

**Standing lesson for the agent:** the local file is the only operable copy. Mirrors were
dropped on 2026-08-02 (see SKILL.md step 4b). State never syncs between origins.

**Residual limitation (closed in v4.0.0):** the fallback fixed copy but not persistence in a
sandboxed frame. That limitation turned out to cover Lavish itself, which sandboxes every
report without same-origin; v4.0.0 removed browser storage and moved the answers to disk
(feature 14). The fallback stays because `file://` origins hit the same clipboard restriction.

### 18. Receipt before relay (v2.4.0; ANSWERED fetch removed in v4.0.0)

When nobody is listening, POST downloads `<slug>-answers.md` (receipt header line + full export) before copying to the clipboard; when an agent listens, the supervisor's harvest writes the same file. Added 2026-10-08 after the operator found that POST had never left a mark on disk. Until v4.0.0 the page also fetched its own `<slug>-answers.md` to show an ANSWERED stamp; from Lavish's opaque sandbox origin that fetch is cross-origin and Lavish sends no CORS header, so it always failed silently. The answered state now arrives through hydrate: the POSTED stamp with the posted time and `Answers: on disk`.
