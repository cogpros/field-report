---
name: field-report
triggers:
  - "/field-report"
  - "field report"
description: >
  Manually invoked when the user asks for a "field report" or says "use
  field-report for this". Generates an interactive HTML report (textareas after
  every question, three export buttons, light/dark, localStorage) from a
  canonical template — 17 baseline features + 2 optional patterns. Do NOT
  auto-fire on description match; manual invocation only. NOT for: read-only
  audit logs with no user input, non-HTML outputs.
version: 3.1.2
license: MIT
public_repo: https://github.com/cogpros/field-report
metadata:
  author: dustin-pollock
  template_path: references/canonical-template.html
  inventory_path: references/feature-inventory.md
  bus_event: field_report_generated
---

# Skill: field-report v3.1.2

## Purpose

Every field report comes out the same shape. The user opens a report and the surface is identical to the last one — done checkboxes at the bottom of each section, progress bar at top, Tab-to-fill on textareas, copy buttons bottom-right, light/dark toggle. Uniformity is the entire value. Hand-building from scratch is the failure mode this skill exists to prevent.

## Trigger conditions (manual invocation)

**This skill is invoked manually, not by description-matching.** Auto-invocation of skills is unreliable in both directions (skipped when the agent thinks it can wing the answer; over-fired on tangential work). The user invokes this skill explicitly — typically by saying `use field-report for this` or `run the field-report skill`. Do not auto-fire on description match. See the public README's *Why manual invocation* section for the full reasoning.

When the user has explicitly invoked the skill, all of these should be true before you generate the report:

1. You are generating an HTML file
2. The file goes to the user's reports directory (see *Reports directory* below)
3. The report contains at least one decision, question, callout, or open-ended section that asks the user for input

If the user invoked the skill but any of those is false (e.g. they want a read-only summary), surface the mismatch and ship the simpler artifact instead of forcing the canonical template.

## Reports directory

The skill writes every report into one directory the user chose at install time. Resolution order:

1. `CLAUDE_REPORTS_DIR` environment variable, if set
2. A `reports_dir:` line in the user's project `CLAUDE.md`
3. First-run prompt: agent asks the user where reports should save (common choices: `~/Desktop/claude-reports/`, `~/Documents/reports/`, a synced cloud folder, a custom dashboard directory). Agent appends `reports_dir: <path>` to project `CLAUDE.md` and creates the directory.

After first run, the agent does not pick a default and does not ask again. The variable `${REPORTS_DIR}` is used below to stand for whichever path resolved.

Optionally, `CLAUDE_REPORTS_URL` (or a `reports_url:` line in `CLAUDE.md`) names an HTTP base that serves the same directory, e.g. a local static server. `${REPORTS_URL}` below stands for it; when unset, the delivery step prints only the file path.

> **Note:** the three-step resolver is agent behavior, not a shipped script. Subsequent invocations read the `reports_dir:` line from `CLAUDE.md`. If you want it deterministic, drop a small wrapper in `~/.local/bin` that reads the env var first and falls back to a grep of CLAUDE.md.

## The procedure

```
1. cp <skill-install-dir>/references/canonical-template.html \
     ${REPORTS_DIR}/<your-report-slug>.html

2. Edit the copy: replace placeholders, add sections.

3. Save. Open it so an agent can listen (v2.3.0). If lavish-axi is available,
   serve the file through it and start the poll; otherwise open the file
   directly. Never steal focus (`open -g` on macOS).
   # with lavish-axi (recommended): one session per file, agent long-polls.
   # PIN THE VERSION and use the same pin everywhere on the machine: a client of a
   # different version makes the shared server restart "for upgrade", which kills
   # every poll any agent has running. (Observed 3x in one weekend with one seat
   # unpinned.) 0.1.80 is the version this skill was tested against (bumped from 0.1.76 on 2026-10-28 alongside the v3.0.0 design freeze; Lavish's capture-phase click handler skips `[data-lavish-action]`, which the template now stamps).
   npx -y lavish-axi@0.1.80 "${REPORTS_DIR}/<your-report-slug>.html" --no-open
   open -g "<session url printed above>"
   npx -y lavish-axi@0.1.80 poll "${REPORTS_DIR}/<your-report-slug>.html"   # blocks until the user sends; run it as a harness-tracked background job if your harness has one
   # without lavish-axi
   # macOS: open -g  |  Linux: xdg-open  |  Windows: start
   open -g "${REPORTS_DIR}/<your-report-slug>.html"

4. Emit a bus event (see Observability section) if your project has one.

4b. Do NOT publish a second copy (e.g. a hosted Artifact mirror). The local
   file is the only copy: localStorage does not sync across origins, so two
   copies split the user's answers. If you run a post-write guard hook, it
   only needs to check that the HTML matches the canonical template.

5. Deliver the report as the LAST lines of your chat reply, in a form the
   user can click or paste. No trailing prose, no follow-up question after
   it. Format (URL first, absolute path second):

       Report: <lavish session url, or ${REPORTS_URL}/<your-report-slug>.html>
       File:   ${REPORTS_DIR}/<your-report-slug>.html

   Deliver ONE url and always the same one. localStorage is per origin, so a
   report opened by file:// and later through lavish keeps two separate sets
   of answers. The lavish session url is reachable from a tablet over a
   tailnet; a bare filename is clickable nowhere. The user grep-scans the
   bottom of the chat to find it; anything after these lines pushes them out
   of view.
```

The canonical template at `references/canonical-template.html` is the single source of truth. Start from it for every report so the 17 baseline features (Section pattern below) land consistently. Hand-building from memory is the failure mode this skill exists to prevent — three drift-mismatched reports in one session before v2.1.0 shipped confirmed it.

**When to deviate:** the user may explicitly request a one-off shape (a read-only HTML, no textareas, for example). That is a different artifact — note it explicitly and ship the simpler file without this skill's enforcement.

## Placeholders to replace

All placeholders use `{NAME_PLACEHOLDER}` form. Replace every one before saving.

| Placeholder | Replace with |
|---|---|
| `{SESSION_ID_PLACEHOLDER}` | Either the current Claude Code session ID, or a descriptive kebab-case slug (e.g. `migration-audit-2026-05-17`) |
| `{REPORT_TITLE_PLACEHOLDER}` | Human-readable title (used in `<title>`, `<h1>`, and exported markdown header) |
| `{FILE_SLUG_PLACEHOLDER}` | Kebab-case slug matching the filename without `.html` (used as localStorage key) |
| `{TIMESTAMP_PLACEHOLDER}` | Compile timestamp `YYYY-MM-DD HH:MM` plus timezone (when you first wrote the file) |
| `{PATCH_TIMESTAMP_PLACEHOLDER}` | Same as compile on first write. Update to current time on every subsequent edit (and add a changelog row — see below). |
| `{REPORT_TYPE_PLACEHOLDER}` | One-line context (e.g. `architecture decision · 4 options`) |
| `{CHANGELOG_PLACEHOLDER}` | Empty on fresh reports (the changelog auto-hides). On each patch/reopen, **prepend** one row — `<div class="ml"><span class="mld">MM-DD HH:MM</span><span>what changed · terse</span></div>` — newest first. This is where updates go; never grow the status line into a ·-chain. |
| `{TOMORROW_BANNER_PLACEHOLDER}` | Optional, empty by default. Fill with the `#tomorrowBell` snippet (see template comment) to put ONE user-chosen next action at the very top — the cheapest/most time-critical open item. |
| `{REPORT_PATH_PLACEHOLDER}` | Absolute path of the saved report, e.g. `${REPORTS_DIR}/<slug>.html`. The agent wire prints it in the attach instruction; falls back to `location.pathname` if left unreplaced. |
| `{SUBTITLE_PLACEHOLDER}` | Sub-heading text under H1 |
| `{SESSION_NOTES_PLACEHOLDER}` | Short note about session context (e.g. `synthesizes 7 checkpointed sessions`) |
| `{LEDE_TEXT_PLACEHOLDER}` | First paragraph; sets up the report. 2-4 sentences. |

## The 17 baseline features + 2 optional patterns

All patterns are catalogued in `references/feature-inventory.md`. The canonical template ships with all of them wired correctly — copying the template inherits them automatically. The two optional patterns (five-lens panel, synthesis block) are included for synthesis-heavy reports; the 17 baseline features ship in every report.

Why baseline-not-optional: uniformity is the entire value of the skill. Mixed-shape reports interrupt the user's flow. Match the template; let downstream changes ride through the template, not per-report.

**Baseline (every report):**

1. **Section checkboxes (bottom of each section)** — `<label class="check"><span>done</span><input type="checkbox" data-cb="..."></label>` as the LAST element inside each `<section class="s">` (after the textarea and tab-hint). Never at the top; the guard fails a report where it is not last.
2. **Progress bar + label** — fixed top of viewport, updates live
3. **Tab-to-fill on textareas** — empty textarea + Tab key → placeholder drops in as editable
4. **Tier badges** (when sections are tiered — t0/t1/t2/t3)
5. **Flow blocks** (when showing multi-step sequences — `.flow` element)
6. **POSTED stamp animation** — slams in when Copy markdown / Download .md / Copy as Claude prompt fires
7. **Copy buttons + toast** — bottom-right bar. Export buttons are dots until hover. `#postBtn` is always the word POST, full size, with no hover reveal.
8. **Code-block copy icon** — every `<pre>` block gets a small copy button (top-right of the block)
9. **Lede block** — pink left-border intro paragraph
10. **Stat grid** — totals at top
11. **Session-ID in 3 places** — HTML comment top, `data-session-id` attribute on body, exported markdown header
12. **Toggle groups** — `.toggles` with `.toggle.go/.defer/.kill` colored states
13. **Light/Dark mode toggle (top-right)** — default dark, button text `→ Light` / `→ Dark`, persists to localStorage
14. **localStorage persistence + restore** — toggles, textareas, checkbox state, mode preference. Since v3.1.2: saves per key (a tab writes only the keys it changed, merged into the stored object, so a stale or second window cannot clobber a box another tab checked), listens to the `storage` event so other windows update live, records a done-time per box, and keeps every stored answer across a re-render of the same slug. **Reopen:** an agent that wants a section looked at again adds `data-reopen="<ISO time>"` to its `<section class="s">`; on load a box whose stored done-time is earlier than that value (or missing) is unchecked and shows a REOPENED note until the operator checks it again. Sections without the attribute never lose their state. Reopen only when your work genuinely invalidates a done box; otherwise leave the attribute off.
15. **Readable meta-header** — compact status line (Compiled · Patched · Opened-live) over an auto-hiding stacked changelog; on patch/reopen, prepend a changelog row (newest first) instead of extending the status line into a ·-chain
16. **Floating notes panel** — `#floatNotes`, a small fixed panel that follows the reader down the page, mirroring the open-notes textarea via the same localStorage slot; collapsible via its header; hidden while an agent is listening (lavish's Conversation panel replaces it)
17. **Agent wire (POST + presence), receipt first (v2.4.0)** — `#postBtn` (labeled POST at rest since v2.4.1) and the `Agent` cell in the meta row. When nobody is listening, POST first downloads `<slug>-answers.md` (the full export with a one-line receipt header: slug, answered count, ISO time), the marker file every scanner on this box already honours. Then it reads `window.lavish`: listening → the batch is queued (`queuePrompt`) and sent (`sendQueuedPrompts`) in one press, with no download (harvest writes the receipt beside the report); nobody listening → the batch is copied with an attach instruction. The record of the operator's answers never depends on an agent remembering to write it. See *Closing the loop* below.

**Optional (synthesis-heavy reports):**

- **Five-lens panel** — five `.lens-card` perspectives in a grid, each with its own textarea
- **Synthesis block** — italic serif summary of preceding section (use `.synthesis` element)
- **"DO THIS TOMORROW" banner** — `#tomorrowBell` at the very top naming ONE user-chosen next action (the cheapest/most time-critical open item). Fill `{TOMORROW_BANNER_PLACEHOLDER}`; empty renders nothing.

The canonical template has every one of these wired correctly. Do not reimplement — copy from the template.

## Design freeze and component kit (v3.0.0)

The look is frozen. `references/canonical-template.html` carries the pixel skin (Press Start 2P headings, VT323 body, 3px square borders, 4px hard shadows, scanline body) and a declared version stamp: `<meta name="field-report-version" content="3.0.0">`. Do not restyle per report. The skin is the operator's call, made once on `firstmate-fit-2026-10-28`; changing it means a new template version, not a one-off edit.

**Version stamp.** `scripts/field-report-guard.sh` reads the current version from the template and rejects any report in the reports dir that lacks the matching `field-report-version` meta. A report built from an older template fails the guard until it is re-rendered.

**Modular sections.** The CSS ships these optional blocks. Use what a report needs; delete the rest.

| Block | Markup | Use |
|---|---|---|
| `.hp` | `<div class="hp"><i style="width:70%"></i></div>`; add `.low` for warn color | pixel health/progress bar |
| `.px-grid` + `.px-card` | `<div class="px-grid"><div class="px-card c-eom"><div class="who">NAME <span class="vendor">vendor</span></div>...</div></div>` | one card per agent/lens/option; `.c-eom .c-euclid .c-odin .c-janus` set the border color |
| `.v-claude .v-codex .v-grok .v-google .v-agy` | `<span class="vote v-grok">GROK</span>` | vendor-colored vote chips |
| `.agree` / `.split` | `<span class="agree">AGREE</span>` | convergence markers: green agree, warn split |
| `.icheck` | `<ul class="checklist"><li><input type="checkbox" class="icheck" id="i-1"><span>item</span></li></ul>` | per-item checklist independent of the section-done machinery |
| `.blink` | `<span class="blink">` | stepped blink; disabled under reduced motion |

**Lavish stamps (Fix A).** Lavish's capture-phase click handler turns any click on a non-control element into an annotation box. The template stamps `data-lavish-action` on (1) the synthetic receipt anchor in `wire.receipt()`, (2) the synthetic download anchor behind `#downloadMdBtn`, and (3) every `a[href]` at init (also set to `target=_blank rel=noopener`). Do not remove these.

## Section pattern (use this every time)

Each section in the report follows this shape:

```html
<section class="s" data-section="short-slug">
  <h2>N · Human-readable section title</h2>

  <p>Section content. Tables, lists, paragraphs as needed.</p>

  <h4>Optional sub-heading for a question</h4>
  <div class="toggles" data-q="decision-key">
    <div class="toggle go">First option</div>
    <div class="toggle defer">Second option</div>
    <div class="toggle kill">Third option</div>
  </div>

  <textarea class="note" data-q="decision-notes" placeholder="A recommendation the user can accept or rewrite on Tab..."></textarea>
  <div class="tab-hint">▸ tab in empty textarea = drop placeholder as editable</div>

  <label class="check"><span>done</span><input type="checkbox" data-cb="short-slug"></label>
</section>
```

- The `.check` label is always the last element of its section (bottom, right-aligned, dashed rule above). Consistency across reports is the point.
- `data-section` and `data-cb` should match (used by progress + state)
- `data-q` on toggles and textareas: short, lowercase, hyphenated. Becomes the heading in exported markdown.
- Placeholder text on textareas is the agent's recommendation written so the user can accept it on Tab or rewrite freely. Pre-fill choices the user can reshape.

## Closing the loop (v2.3.0, receipt first since v2.4.0)

A report has two states and the page reads which one it is in; the user never picks.

- **Listening.** lavish-axi served the page, so `window.lavish` exists and an agent is blocked in `lavish-axi poll`. The meta row shows `Agent listening`; the button bar shows only POST, and the floating notes panel is hidden (lavish's Conversation panel replaces both the export buttons and the notes). POST queues one prompt: a batch header (sections answered, sections changed since the last POST) plus the full markdown export. The user presses lavish's **Send to Agent**; the poll returns the prompt to the agent.
- **Nobody listening.** Opened by file://, a static server, or a tablet with the lavish server idle. POST copies the same batch to the clipboard with an attach instruction: paste into any agent, it acts on the answers, then runs `npx -y lavish-axi@0.1.80 <path>` and `poll` (same pin as the rest of the machine), and the page flips to listening. "Copy as Claude prompt" carries the same instruction.

**Receipt before relay (v2.4.0, 2026-10-08; one-press since v3.1.0: the download now happens only when nobody is listening, because the lavish harvest writes the receipt beside the report).** The page writes its own receipt. POST downloads `<slug>-answers.md` into the browser's Downloads folder before anything is relayed. On this box a launchd watcher (`com.hugr.field-report-receipts`, script `~/1HUGR/code/scripts/field-report-receipts.sh`) moves that file beside the report in the reports directory, flips the delivery log to `answered` via `fr-log.sh`, emits `field_report_answered`, and regenerates the vault note `~/1HUGR/docs/field-reports.md` (OPEN and ANSWERED tables, one row per report). A page served from any http origin next to its receipt shows an ANSWERED stamp under the title on load (`wire.answeredStamp`). Why: for three weeks every report looked open because answers lived only in localStorage and the marker was in a second party's custody; fifty deliveries, two marked answered. The receipt is the operator's Sent folder.

**Receipt rule.** Every POST names section ids. The agent's reply gives each submitted id exactly one outcome: done with evidence, deferred with a reason, or rejected with a reason. Compare the submitted id set with the receipt before reporting completion, and surface every missing id. Then re-poll (`lavish-axi poll <file> --agent-reply "<one-line receipt>"`).

**End.** The user's **Send & End** or **End session** returns `ended` from the poll: stop polling, deliver anything left in chat, do not reopen uninvited. `browser_disconnected` means the tab closed: ask before reopening or ending.

**lavish settings worth fixing once, in the seat that launches your agent:** `LAVISH_AXI_TELEMETRY=0` (lavish reports command names, version and platform to its author by default) and `LAVISH_AXI_IDLE_TIMEOUT_MS=0` (keep the server resident so a half-filled report's link never goes dead). Pin the version you tested against, use ONE pin per machine (a mixed-version client forces a server restart that kills every running poll), and read lavish's release notes and VISION.md before bumping.

## Pre-save checklist

Run mentally before opening in the browser:

- [ ] Every placeholder replaced (search the file for `_PLACEHOLDER` — should return zero matches)
- [ ] Every section has a `data-section` and matching `data-cb`
- [ ] Every textarea has `data-q`
- [ ] Every toggle group has `data-q`
- [ ] `docTitle`, `fileSlug`, `sessionId` in the JS at the bottom match the placeholders
- [ ] Status-line timestamps real; each patch added a changelog row (newest first), not appended to the status line
- [ ] File saved to `${REPORTS_DIR}`
- [ ] `{REPORT_PATH_PLACEHOLDER}` is the real absolute path
- [ ] Opened through lavish-axi and the poll is running, or opened directly with `open -g` if lavish is unavailable

## Anti-patterns (user complaints these cause)

- **Reports come out different every time** → you skipped the `cp template` step and hand-built from memory. Always cp the template first.
- **Some have checkboxes, some don't** → you skipped features 1-3. Mandatory in every report.
- **Light/dark toggle missing** → you skipped feature 14. Mandatory.
- **Timestamp stale when I open it next day** → you skipped feature 17 (three-timestamp header). Mandatory.
- **Checkbox click freezes the page** → the freeze-fix CSS (no layout shift) + JS (try/catch + requestAnimationFrame) is in the template. Do not rewrite the JS.
- **Restart prompts run together** → use a `.restart-prompt` block when a section is a copy-paste prompt to launch a session.
- **"Which report did you make? I have to scroll up to find it"** → you skipped step 5 of the procedure. The filename MUST be the last line of your chat reply (no prose after, no follow-up question, no recommendation). User scans the bottom of the message for it.

## Updating the template

When the user names a new feature or a bug is fixed:

1. Patch the canonical template at `<skill-install-dir>/references/canonical-template.html`
2. Add the pattern to `references/feature-inventory.md` (number the feature, status, where it appeared first, what it does)
3. Bump skill version (2.1.0 → 2.1.1 for tweaks, 2.2.0 for new features, 3.0.0 for breaking changes). Bump the `field-report-version` meta in the template in the same commit; the guard keys off it.
4. If the change is public-shipping-relevant, note it in the README

## Dependencies

**Required files (bundled in this skill):**
- `references/canonical-template.html` — single source of truth template. Every report copies this.
- `references/feature-inventory.md` — 17-baseline + 2-optional catalogue with status, exemplar reports, implementation notes.
- `references/example.html` — AI-agent-decision worked example (self-referential: agent asks the developer which skills to install before scaffolding).
- `references/example-legacy-database.html` — earlier worked example (v2.0 pattern, "choose a database"). Kept for the textarea + export pattern at minimum surface area.
- `references/interactive-pattern-snippet.html` — paste-ready snippet (legacy v1 — kept for reference).

**Required tools:**
- `cp` (file copy)
- `open` (macOS — opens in the default browser, or `open -a "<browser>"` for a specific one). On Linux: `xdg-open`. On Windows: `start`.
- A text editor / Edit/Write tools (Claude Code)

## Observability

If your project has a bus or event log, emit one event per report so failures and drift are detectable. Example shape:

```bash
python3 -c "
import json, datetime, sys
event = {
  'event_type': 'field_report_generated',
  'source': 'skill:field-report',
  'ts': datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'subject': 'field_report_generated',
  'body': sys.argv[1],
  'category': 'workflow'
}
print(json.dumps(event))
" "<report-slug>.html · sections=<N> · template_version=2.3.0" >> "${BUS_LOG:-/dev/null}"
```

Set `BUS_LOG` to your project's bus file, or pipe to whatever event sink you use. If you have no bus, skip this step.

Drift detection: weekly scan for reports in `${REPORTS_DIR}` that lack one of the 17 features. Any report missing baseline features = drift event.

Health check:

```bash
grep -L "openedAt\|mode-toggle\|data-cb" "${REPORTS_DIR}"/*.html
```

Empty result = healthy. Listed files lack one of the newest baseline features.

## Autoresearch notes

**Q13 (empirical):** PARTIAL — ~13+ real reports generated over 48 hours of operator use during v2.1.x development, with iterative reshaping in response (light/dark toggle added back, 17→15+2 feature renumber, per-block code copy, manual-invocation reframe). Behavioral outcome signal: operator reports morning re-orientation working — closing a session with reports in the directory and opening the next day with state preserved and next-steps legible without re-loading context. That is the value the skill claims to enable, observed in practice.

To move PARTIAL → YES: three scored runs against the Pre-save checklist + 15-feature presence grep, ideally one of them by an adopter outside the author's own stack.

**Q14 (observability):** PARTIAL — bus event emission specified above. Drift detection grep specified. Not yet wired into automation by default; adopters do their own.

**Mutation candidates:**
1. Wire the drift-detection grep into a daily check, emitting `field_report_drift_detected` events.
2. Add an `assert-features` script that grep-counts each baseline feature in a given report file and exits non-zero on miss. Lets agents self-verify in step 4 of the procedure.
3. Build a `scorecard.md` listing the 17 features as binary checks for adopters who have not seen the pattern before.

## Roadmap

- **v2.4** — Adopter-facing scorecard + README walkthroughs of the 17 features.
- **v2.5** — Skill-doctor 14-Q pass to lock health ≥ 11/14.
- Dropped: File System Access sidecar (lavish is the wire; a disk sidecar would fork the answer store).

## Origin

The pattern was extracted from months of hand-built decision-doc HTML reports. It got skillified after three reports in one flow state came out three different shapes — checkboxes here, no checkboxes there, missing light toggle on the third — and that interrupted the work. Root cause: the canonical template existed but was not the loaded skill. v2.1.0 ships with the template wired and the procedure enforced. v2.1.1 (2026-05-17) added bus event emission, drift detection, the public-ship light/dark toggle requirement, and per-block code-copy buttons. v2.1.2 (2026-06) added responsive breakpoints for zoom and narrow viewports. v2.1.3 (2026-07-30) added the clipboard fallback for sandboxed and `file://` contexts. v2.2.0 (2026-09-07) added the floating notes panel (feature 16), the stacked header changelog, and the optional "do this tomorrow" banner. v2.3.0 (2026-09-17) closed the loop: feature 17, the agent wire (POST + presence) over lavish-axi, with a clipboard attach path when nobody is listening, and the per-id receipt rule. Design record: the operator's "now version / later version" brief and the ruling that the page reads its state rather than asking for a mode. v2.4.1 (2026-10-27) stamps `data-lavish-action="toggle"` on every `.toggle` so Lavish selects instead of annotating, and keeps the POST button labeled and visible without hover.
