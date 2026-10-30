# PROOF — field-report v3.0.0 (design freeze + Lavish Fix A)

Generated 2026-10-28 from this branch. Reproduce with the commands shown.

## Fix A: three `data-lavish-action` stamps (references/canonical-template.html)

```
$ grep -n 'data-lavish-action' references/canonical-template.html | cut -c1-110
385:  // Lavish Fix A (v3.0.0): Lavish's capture-phase click handler turns any non-control click into an annot
387:    if(!a.hasAttribute("data-lavish-action")) a.setAttribute("data-lavish-action","link");
395:      t.setAttribute("data-lavish-action","toggle");
554:      const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=fileSl
586:  document.getElementById("downloadMdBtn").addEventListener("click",()=>{const md=gather();const blob=new 
```

1. `a[href]` stamp at init (`data-lavish-action="link"`, `target=_blank rel=noopener`)
2. `wire.receipt()` synthetic anchor (`data-lavish-action="download"`)
3. `#downloadMdBtn` synthetic anchor (`data-lavish-action="download"`)

(Line 395 is the pre-existing v2.4.1 toggle stamp, unchanged.) Fix B (state persistence rewrite) is NOT included.

## Version marker

```
$ grep -n 'field-report-version\|field-report-template v' references/canonical-template.html | cut -c1-110
3:<!-- field-report-template v3.0.0 (design frozen 2026-10-28: pixel skin, Press Start 2P + VT323). Do not edi
7:<meta name="field-report-version" content="3.0.0">
$ grep -n '^version:' SKILL.md
13:version: 3.0.0
```

## Guard (red then green)

```
$ tests/test-guard.sh
ok   fresh-passes (exit 0)
ok   missing-stamp-fails (exit 2)
ok   old-stamp-fails (exit 2)
```

Red cases (missing stamp, stale 2.1.2 stamp) exit 2 before the fresh copy is trusted.
The guard is `scripts/field-report-guard.sh`; install over `~/1HUGR/bin/field-report-guard.sh` (the live hook is outside this repo).

## Pin

```
$ grep -rn 'lavish-axi@0\.1\.76' . --exclude-dir=.git | wc -l
       0
```
(One prose mention of 0.1.76 remains in SKILL.md as the 'bumped from' history note.)

## PFR-only hardening (identity, Lavish-only delivery)

Template stamp is unchanged (3.1.2); only a comment about the Daily Pulse banner changed, so existing reports still pass the version check.

```
$ tests/test-guard.sh | grep -c '^ok'; echo exit=$?
```
Red cases (all exit 2 before the clean template is trusted): filled `#tomorrowBell`, Daily Pulse title, `daily-pulse-*` filename, static-server url, unpinned `lavish-axi`, mismatched pin (`0.1.76`). Green: fresh template, empty banner. Skill-text assertions cover the PFR trigger, Daily Pulse prohibition, mandatory Lavish, 127.0.0.1 fallback, Working-spin and owning-session poll notes, and the absence of an `open -g` fallback.
