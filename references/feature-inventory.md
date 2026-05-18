# Field Report UI Feature Inventory

Last updated: 2026-05-17 · Audited from 13 field reports over 48 hours

## Patterns (15 baseline + 2 optional + 3 foundational)

### 1. Section Checkboxes (Top-Right)
**Status:** Canonical
**What it does:** Each section has a checkbox in the top-right corner. Toggle to mark done. Section dims and text strikes through when complete.
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
**What it does:** Large "POSTED" watermark that slams in when "Copy markdown" or "Copy as Claude prompt" is clicked. Shows the timestamp. Persists to localStorage.
**Notes:** Critical UX signal that the report was captured — when the user reopens later, the stamp tells them this one is done.

### 7. Copy Buttons + Toast Feedback
**Status:** Canonical
**What it does:** Three export buttons fixed bottom-right. "Copy markdown" pink, "Download .md" brown, "Copy as Claude prompt" amber. Toast notification on success. Buttons collapse to dots on page load, expand on hover.

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

### 13. Light/Dark Mode Toggle (Top-Right)
**Status:** Canonical (added for public ship 2026-05-17)
**What it does:** Small button fixed top-right (`right:160px` to clear the progress label). Toggles `body.light` class which swaps the entire CSS variable palette. Default is dark. Button text is `→ Light` (dark mode) or `→ Dark` (light mode). Persists to localStorage per-report.
**Notes:** Default dark suits long sessions; the toggle is mandatory because some adopters strongly prefer light. Light palette mirrors the dark variables; headings need explicit `body.light h1/h2/h3` rules where the dark theme used hardcoded light values.

### 14. localStorage Persistence
**Status:** Canonical
**What it does:** Toggles, textareas, checkbox state, and mode preference are saved to localStorage and restored on page load.

### 15. Three-Timestamp Header (Compiled · Patched · Opened)
**Status:** Canonical (added 2026-05-17 after a stale-timestamp incident)
**What it does:** Header row shows three timestamps: `Compiled` (original generation, static), `Patched` (last write, static, updated on edit), `Opened` (live, rendered by JS on each page load via `<span id="openedAt">`). Solves the "I closed the tab because it looked stale" problem — the Opened timestamp always reads current.
**Notes:** Mandatory going forward. A single timestamp misleads when a report is generated once and viewed later.

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
- **Baseline (every report):** 15 numbered patterns
- **Optional (synthesis-heavy reports):** 2 patterns (five-lens panel, synthesis block)
- **Foundational (color scheme, fonts, spacing — not numbered above):** 3

## Design preferences baked into the canonical template

1. Dark mode default, light toggle available
2. Section checkboxes + progress bar (preferred over older tier-only patterns)
3. Tab-to-fill on textareas
4. POSTED stamp on copy (UX signal)
5. Session-ID embedded in three places (multi-session continuity)
6. localStorage persistence (no server dependency)
7. Portable template (no hardcoded user paths in the template body)
