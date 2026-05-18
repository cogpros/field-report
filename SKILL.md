---
name: field-report
description: >
  Manually invoked when the user asks for a "field report" or says "use
  field-report for this". Generates an interactive HTML report (textareas after
  every question, three export buttons, light/dark, localStorage) from a
  canonical template — 15 baseline features + 2 optional patterns. Do NOT
  auto-fire on description match; manual invocation only. NOT for: read-only
  audit logs with no user input, non-HTML outputs.
version: 2.1.1
license: MIT
public_repo: https://github.com/cogpros/field-report
metadata:
  author: dustin-pollock
  template_path: references/canonical-template.html
  inventory_path: references/feature-inventory.md
  bus_event: field_report_generated
---

# Skill: field-report v2.1.1

## Purpose

Every field report comes out the same shape. The user opens a report and the surface is identical to the last one — checkboxes top-right, progress bar at top, Tab-to-fill on textareas, copy buttons bottom-right, light/dark toggle. Uniformity is the entire value. Hand-building from scratch is the failure mode this skill exists to prevent.

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

> **Note:** the three-step resolver is agent behavior, not a shipped script. Subsequent invocations read the `reports_dir:` line from `CLAUDE.md`. If you want it deterministic, drop a small wrapper in `~/.local/bin` that reads the env var first and falls back to a grep of CLAUDE.md.

## The procedure

```
1. cp <skill-install-dir>/references/canonical-template.html \
     ${REPORTS_DIR}/<your-report-slug>.html

2. Edit the copy: replace placeholders, add sections.

3. Save. Open in the browser:
   # macOS: open  |  Linux: xdg-open  |  Windows: start
   open "${REPORTS_DIR}/<your-report-slug>.html"

4. Emit a bus event (see Observability section) if your project has one.
```

The canonical template at `references/canonical-template.html` is the single source of truth. Start from it for every report so the 15 baseline features (Section pattern below) land consistently. Hand-building from memory is the failure mode this skill exists to prevent — three drift-mismatched reports in one session before v2.1.0 shipped confirmed it.

**When to deviate:** the user may explicitly request a one-off shape (a read-only HTML, no textareas, for example). That is a different artifact — note it explicitly and ship the simpler file without this skill's enforcement.

## Placeholders to replace

All placeholders use `{NAME_PLACEHOLDER}` form. Replace every one before saving.

| Placeholder | Replace with |
|---|---|
| `{SESSION_ID_PLACEHOLDER}` | Either the current Claude Code session ID, or a descriptive kebab-case slug (e.g. `migration-audit-2026-05-17`) |
| `{REPORT_TITLE_PLACEHOLDER}` | Human-readable title (used in `<title>`, `<h1>`, and exported markdown header) |
| `{FILE_SLUG_PLACEHOLDER}` | Kebab-case slug matching the filename without `.html` (used as localStorage key) |
| `{TIMESTAMP_PLACEHOLDER}` | Compile timestamp `YYYY-MM-DD HH:MM` plus timezone (when you first wrote the file) |
| `{PATCH_TIMESTAMP_PLACEHOLDER}` | Same as compile on first write. Update to current time on every subsequent edit. |
| `{REPORT_TYPE_PLACEHOLDER}` | One-line context (e.g. `architecture decision · 4 options`) |
| `{SUBTITLE_PLACEHOLDER}` | Sub-heading text under H1 |
| `{SESSION_NOTES_PLACEHOLDER}` | Short note about session context (e.g. `synthesizes 7 checkpointed sessions`) |
| `{LEDE_TEXT_PLACEHOLDER}` | First paragraph; sets up the report. 2-4 sentences. |

## The 15 baseline features + 2 optional patterns

All patterns are catalogued in `references/feature-inventory.md`. The canonical template ships with all of them wired correctly — copying the template inherits them automatically. The two optional patterns (five-lens panel, synthesis block) are included for synthesis-heavy reports; the 15 baseline features ship in every report.

Why baseline-not-optional: uniformity is the entire value of the skill. Mixed-shape reports interrupt the user's flow. Match the template; let downstream changes ride through the template, not per-report.

**Baseline (every report):**

1. **Section checkboxes (top-right)** — `<label class="check"><span>done</span><input type="checkbox" data-cb="..."></label>` inside each `<section class="s">`
2. **Progress bar + label** — fixed top of viewport, updates live
3. **Tab-to-fill on textareas** — empty textarea + Tab key → placeholder drops in as editable
4. **Tier badges** (when sections are tiered — t0/t1/t2/t3)
5. **Flow blocks** (when showing multi-step sequences — `.flow` element)
6. **POSTED stamp animation** — slams in when Copy markdown / Download .md / Copy as Claude prompt fires
7. **Copy buttons + toast** — bottom-right dots-on-hover bar
8. **Code-block copy icon** — every `<pre>` block gets a small copy button (top-right of the block)
9. **Lede block** — pink left-border intro paragraph
10. **Stat grid** — totals at top
11. **Session-ID in 3 places** — HTML comment top, `data-session-id` attribute on body, exported markdown header
12. **Toggle groups** — `.toggles` with `.toggle.go/.defer/.kill` colored states
13. **Light/Dark mode toggle (top-right)** — default dark, button text `→ Light` / `→ Dark`, persists to localStorage
14. **localStorage persistence + restore** — toggles, textareas, checkbox state, mode preference
15. **Three-timestamp header** — Compiled (static) · Patched (static, update on edit) · Opened (live via JS)

**Optional (synthesis-heavy reports):**

- **Five-lens panel** — five `.lens-card` perspectives in a grid, each with its own textarea
- **Synthesis block** — italic serif summary of preceding section (use `.synthesis` element)

The canonical template has every one of these wired correctly. Do not reimplement — copy from the template.

## Section pattern (use this every time)

Each section in the report follows this shape:

```html
<section class="s" data-section="short-slug">
  <label class="check"><span>done</span><input type="checkbox" data-cb="short-slug"></label>
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
</section>
```

- `data-section` and `data-cb` should match (used by progress + state)
- `data-q` on toggles and textareas: short, lowercase, hyphenated. Becomes the heading in exported markdown.
- Placeholder text on textareas is the agent's recommendation written so the user can accept it on Tab or rewrite freely. Pre-fill choices the user can reshape.

## Pre-save checklist

Run mentally before opening in the browser:

- [ ] Every placeholder replaced (search the file for `_PLACEHOLDER` — should return zero matches)
- [ ] Every section has a `data-section` and matching `data-cb`
- [ ] Every textarea has `data-q`
- [ ] Every toggle group has `data-q`
- [ ] `docTitle`, `fileSlug`, `sessionId` in the JS at the bottom match the placeholders
- [ ] Three timestamps in the row-time line are real
- [ ] File saved to `${REPORTS_DIR}`
- [ ] Opened in the browser (`open <path>` on macOS, equivalent elsewhere)

## Anti-patterns (user complaints these cause)

- **Reports come out different every time** → you skipped the `cp template` step and hand-built from memory. Always cp the template first.
- **Some have checkboxes, some don't** → you skipped features 1-3. Mandatory in every report.
- **Light/dark toggle missing** → you skipped feature 14. Mandatory.
- **Timestamp stale when I open it next day** → you skipped feature 17 (three-timestamp header). Mandatory.
- **Checkbox click freezes the page** → the freeze-fix CSS (no layout shift) + JS (try/catch + requestAnimationFrame) is in the template. Do not rewrite the JS.
- **Restart prompts run together** → use a `.restart-prompt` block when a section is a copy-paste prompt to launch a session.

## Updating the template

When the user names a new feature or a bug is fixed:

1. Patch the canonical template at `<skill-install-dir>/references/canonical-template.html`
2. Add the pattern to `references/feature-inventory.md` (number the feature, status, where it appeared first, what it does)
3. Bump skill version (2.1.0 → 2.1.1 for tweaks, 2.2.0 for new features, 3.0.0 for breaking changes)
4. If the change is public-shipping-relevant, note it in the README

## Dependencies

**Required files (bundled in this skill):**
- `references/canonical-template.html` — single source of truth template. Every report copies this.
- `references/feature-inventory.md` — 17-pattern catalogue with status, exemplar reports, implementation notes.
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
" "<report-slug>.html · sections=<N> · template_version=2.1.1" >> "${BUS_LOG:-/dev/null}"
```

Set `BUS_LOG` to your project's bus file, or pipe to whatever event sink you use. If you have no bus, skip this step.

Drift detection: weekly scan for reports in `${REPORTS_DIR}` that lack one of the 17 features. Any report missing baseline features = drift event.

Health check:

```bash
grep -L "openedAt\|mode-toggle\|data-cb" "${REPORTS_DIR}"/*.html
```

Empty result = healthy. Listed files lack one of the newest baseline features.

## Autoresearch notes

**Q13 (empirical):** NO — internal dogfooding only (~13 reports over 48 hours during v2.1.x development). External adoption runs needed before scoring this as PARTIAL or YES. Target: three scored runs against the Pre-save checklist + 15-feature presence grep.

**Q14 (observability):** PARTIAL — bus event emission specified above. Drift detection grep specified. Not yet wired into automation by default; adopters do their own.

**Mutation candidates:**
1. Wire the drift-detection grep into a daily check, emitting `field_report_drift_detected` events.
2. Add an `assert-features` script that grep-counts each baseline feature in a given report file and exits non-zero on miss. Lets agents self-verify in step 4 of the procedure.
3. Build a `scorecard.md` listing the 17 features as binary checks for adopters who have not seen the pattern before.

## Roadmap

- **v2.2** — File System Access API integration (browser-native file moves on POSTED).
- **v2.3** — Adopter-facing scorecard + README walkthroughs of the 17 features.
- **v2.4** — Skill-doctor 14-Q pass to lock health ≥ 11/14.

## Origin

The pattern was extracted from months of hand-built decision-doc HTML reports. It got skillified after three reports in one flow state came out three different shapes — checkboxes here, no checkboxes there, missing light toggle on the third — and that interrupted the work. Root cause: the canonical template existed but was not the loaded skill. v2.1.0 ships with the template wired and the procedure enforced. v2.1.1 (2026-05-17) added bus event emission, drift detection, the public-ship light/dark toggle requirement, and per-block code-copy buttons.
