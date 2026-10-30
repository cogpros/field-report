#!/usr/bin/env node
// Disk-state test (v4.0.0): answers live on disk; the page is a renderer.
// Usage: node tests/test-disk-state.js [path-to-template.html]   (default: references/canonical-template.html)
//
// Every page here runs with the storage Lavish actually gives it: Lavish serves the report in an
// iframe sandboxed without allow-same-origin (lavish-axi 0.1.80 dist/cli.mjs:12024), where reading
// window.localStorage throws SecurityError. jsdom gets a getter that throws exactly that. The last
// case repeats the round trip in headless Chrome under Lavish's exact sandbox string, when Chrome
// is installed (SKIP otherwise). Forced reds run first: each proves its check can fail.
// jsdom is resolved from node_modules, $JSDOM_PATH, or a sibling hermes install.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

function loadJsdom() {
  const tries = [() => require("jsdom"), () => require(process.env.JSDOM_PATH),
    () => require(path.join(process.env.HOME || "", ".hermes/hermes-agent/node_modules/jsdom"))];
  for (const t of tries) { try { return t(); } catch (e) { /* next */ } }
  console.error("jsdom not found: npm i jsdom, or set JSDOM_PATH"); process.exit(2);
}
const { JSDOM } = loadJsdom();

const ROOT = path.join(__dirname, "..");
const TEMPLATE = path.resolve(process.argv[2] || path.join(ROOT, "references", "canonical-template.html"));
const HYDRATE = path.join(ROOT, "scripts", "fr-hydrate.sh");
const LAVISH_SANDBOX = "allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox allow-downloads";
const SANDBOX_ERR = "Failed to read the 'localStorage' property from 'Window': The document is sandboxed and lacks the 'allow-same-origin' flag.";
const tpl = fs.readFileSync(TEMPLATE, "utf8");
const SLUG = "disk-test";
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "fr-disk-"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// The v3.1.2 template (last storage-backed release), for the forced red. From git when available.
function oldTemplate() {
  try { return execFileSync("git", ["-C", ROOT, "show", "e891b04:references/canonical-template.html"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); }
  catch (e) { return null; }
}

// Build a report from a template: the one section block becomes N sections.
function page(src, { ids = ["a", "b", "c"], reopen = {}, slug = SLUG } = {}) {
  const m = src.match(/<section class="s" data-section="section-id">[\s\S]*?<\/section>/);
  if (!m) throw new Error("template has no section block");
  const secs = ids.map((id) => {
    let s = m[0].replace(/section-id/g, id).replace('data-q="section-notes"', `data-q="notes-${id}"`)
      .replace(/<div class="toggles" data-q="toggle-question">/, `<div class="toggles" data-q="tog-${id}">`);
    if (reopen[id]) s = s.replace('<section class="s"', `<section class="s" data-reopen="${reopen[id]}"`);
    return s;
  }).join("\n");
  return src.replace(m[0], secs).replace(/\{FILE_SLUG_PLACEHOLDER\}/g, slug)
    .replace(/\{REPORT_TITLE_PLACEHOLDER\}/g, "T").replace(/\{SESSION_ID_PLACEHOLDER\}/g, "s").replace(/\{REPORT_PATH_PLACEHOLDER\}/g, "/x.html");
}

// A tab inside the Lavish sandbox: touching localStorage throws, and every touch is counted.
function openTab(html, { lavish = null } = {}) {
  const touches = { n: 0 };
  const capture = { blobs: [] };
  const dom = new JSDOM(html, { runScripts: "dangerously", pretendToBeVisual: true, url: "http://localhost/r.html",
    beforeParse(w) {
      const deny = () => { touches.n++; throw new w.DOMException(SANDBOX_ERR, "SecurityError"); };
      for (const k of ["localStorage", "sessionStorage"]) Object.defineProperty(w, k, { get: deny, configurable: true });
      if (lavish) w.lavish = lavish;
      w.URL.createObjectURL = (b) => { capture.blobs.push(b); return "blob:x"; };
      w.URL.revokeObjectURL = () => {};
      w.HTMLAnchorElement.prototype.click = function () {};
      w.document.execCommand = () => true;
    } });
  const w = dom.window; w.__touches = touches; w.__capture = capture;
  return w;
}
const $ = (w, sel) => w.document.querySelector(sel);
const cb = (w, id) => $(w, `input[data-cb="${id}"]`);
const sec = (w, id) => $(w, `section[data-section="${id}"]`);
async function check(w, id, on = true) { const c = cb(w, id); c.checked = on; c.dispatchEvent(new w.Event("change", { bubbles: true })); await sleep(40); }
async function type(w, q, v) { const t = $(w, `textarea[data-q="${q}"]`); t.value = v; t.dispatchEvent(new w.Event("input", { bubbles: true })); await sleep(10); }
function pick(w, q, label) { [...w.document.querySelectorAll(`.toggles[data-q="${q}"] .toggle`)].find((t) => t.textContent.trim() === label).click(); }
const progress = (w) => $(w, "#progressLabel").textContent.trim();
const disk = (w) => $(w, "#diskText").textContent.trim();
const checked = (w, ids = ["a", "b", "c"]) => ids.filter((id) => cb(w, id).checked);
function hydrate(answers, html) { return spawnSync("bash", [HYDRATE, answers, html], { encoding: "utf8" }); }
function write(name, text) { const p = path.join(TMP, name); fs.writeFileSync(p, text); return p; }
// What harvest writes from a Lavish POST: the prompt minus its two header lines.
const harvestShape = (prompt) => prompt.split("\n").slice(3).join("\n").trim() + "\n";
// Code only: drop // and /* */ comments so a doc comment naming localStorage does not count.
function code(src) {
  return [...src.matchAll(/<script(?![^>]*application\/json)[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1])
    .join("\n").replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'\\])\/\/[^\n]*/g, "$1");
}
const STORAGE_RE = /localStorage|sessionStorage|indexedDB|addEventListener\(\s*["']storage["']|fetch\(/g;

// Fill a page the way the operator does and POST it through a fake Lavish; returns the prompt.
async function fillAndPost(html) {
  let prompt = null;
  const lavish = { queuePrompt(p) { prompt = p; }, async sendQueuedPrompts() {} };
  const A = openTab(html, { lavish });
  await check(A, "a"); await check(A, "c");
  await type(A, "notes-a", "answer A\nsecond line </script><script>window.pwned=1</script>");
  pick(A, "tog-b", "Defer option");
  const dirty = disk(A);
  $(A, "#postBtn").click(); await sleep(30);
  return { prompt, dirty, after: disk(A), A };
}

const cases = [];
const T = (name, fn) => cases.push([name, fn]);

T("forced red: the storage scan finds browser storage when it is there", async () => {
  const red = tpl.replace("function restore(){", "function restore(){try{localStorage.getItem('x')}catch(e){}");
  const hits = code(red).match(STORAGE_RE) || [];
  const old = oldTemplate();
  const oldHits = old ? (code(old).match(STORAGE_RE) || []).length : null;
  return [hits.length > 0 && (old === null || oldHits > 0), `injected=${hits.length} v3.1.2=${oldHits === null ? "SKIP(no git)" : oldHits}`];
});

T("template code has no browser storage, storage events, or fetch", async () => {
  const hits = code(tpl).match(STORAGE_RE) || [];
  return [hits.length === 0, `hits=${JSON.stringify(hits)}`];
});

T("forced red: v3.1.2 under the Lavish sandbox loses a checked box on reload", async () => {
  const old = oldTemplate();
  if (!old) return [true, "SKIP(no git history)"];
  const html = page(old);
  const A = openTab(html); await check(A, "a");
  const before = cb(A, "a").checked;
  const B = openTab(html); // reload: same sandbox, nothing was stored
  return [before && !cb(B, "a").checked && A.__touches.n > 0, `checked before reload=${before} after reload=${cb(B, "a").checked} storage touches=${A.__touches.n} (all threw)`];
});

T("fresh page under the sandbox: no storage touch, honest unsaved state", async () => {
  const A = openTab(page(tpl));
  const ok = A.__touches.n === 0 && disk(A) === "unsaved until POST" && progress(A).startsWith("0 /") && $(A, "#fr-state").textContent.trim() === "{}";
  return [ok, `touches=${A.__touches.n} answers="${disk(A)}" progress=${progress(A)}`];
});

T("without hydrate a reload shows nothing (the page stores nothing)", async () => {
  const html = page(tpl);
  const A = openTab(html); await check(A, "a"); await type(A, "notes-b", "typed");
  const B = openTab(html);
  return [checked(B).length === 0 && $(B, 'textarea[data-q="notes-b"]').value === "" && A.__touches.n + B.__touches.n === 0,
    `after reload checked=${JSON.stringify(checked(B))} touches=${A.__touches.n + B.__touches.n}`];
});

T("POST, harvest, hydrate, reload: boxes, answers, toggles come back from disk", async () => {
  const html = page(tpl); const file = write(SLUG + ".html", html);
  const { prompt, dirty, after, A } = await fillAndPost(html);
  if (!prompt) return [false, "POST queued no prompt"];
  const answers = write(SLUG + "-answers.md", harvestShape(prompt));
  const h = hydrate(answers, file);
  const B = openTab(fs.readFileSync(file, "utf8"));
  const note = $(B, 'textarea[data-q="notes-a"]').value;
  const tog = [...B.document.querySelectorAll('.toggles[data-q="tog-b"] .toggle.active')].map((t) => t.textContent.trim());
  const ok = h.status === 0 && JSON.stringify(checked(B)) === '["a","c"]' && sec(B, "a").classList.contains("done") && !sec(B, "b").classList.contains("done")
    && progress(B).startsWith("2 /") && note === "answer A\nsecond line </script><script>window.pwned=1</script>" && JSON.stringify(tog) === '["Defer option"]'
    && /^on disk /.test(disk(B)) && dirty === "unsaved · press POST" && /^sent /.test(after) && B.pwned === undefined
    && A.__touches.n + B.__touches.n === 0 && $(B, "#postedStamp").classList.contains("show");
  return [ok, `hydrate exit=${h.status} ${h.stdout.trim()} | checked=${JSON.stringify(checked(B))} progress=${progress(B)} toggle=${JSON.stringify(tog)} answers="${disk(B)}" dirty="${dirty}" after-post="${after}" injected-script-ran=${B.pwned !== undefined} touches=${A.__touches.n + B.__touches.n}`];
});

T("receipt path (nobody listening) hydrates the same state", async () => {
  const html = page(tpl); const file = write(SLUG + "-r.html", html);
  const A = openTab(html);
  await check(A, "b"); await type(A, "notes-b", "from the receipt");
  $(A, "#postBtn").click(); await sleep(30);
  const blob = A.__capture.blobs[0]; if (!blob) return [false, "no receipt download"];
  const md = await blob.text();
  const answers = write(SLUG + "-r-answers.md", md);
  const h = hydrate(answers, file);
  const B = openTab(fs.readFileSync(file, "utf8"));
  const st = JSON.parse($(B, "#fr-state").textContent);
  const ok = h.status === 0 && JSON.stringify(checked(B)) === '["b"]' && $(B, 'textarea[data-q="notes-b"]').value === "from the receipt" && /^receipt downloaded /.test(disk(A)) && typeof st.posted === "string";
  return [ok, `exit=${h.status} checked=${JSON.stringify(checked(B))} posted=${st.posted} receipt-head=${JSON.stringify(md.split("\n")[0].slice(0, 60))}`];
});

T("changed-since-last-POST diffs against the disk state", async () => {
  const file = path.join(TMP, SLUG + ".html"); // hydrated by the round-trip case
  let prompt = null; const lavish = { queuePrompt(p) { prompt = p; }, async sendQueuedPrompts() {} };
  const B = openTab(fs.readFileSync(file, "utf8"), { lavish });
  $(B, "#postBtn").click(); await sleep(20);
  const first = (prompt.match(/changed since last POST: ([^\n]*)/) || [])[1];
  await type(B, "notes-c", "new"); $(B, "#postBtn").click(); await sleep(20);
  const second = (prompt.match(/changed since last POST: ([^\n]*)/) || [])[1];
  return [first === "none" && second === "c", `unchanged repost="${first}" after editing c="${second}"`];
});

T("data-reopen unchecks a box posted before it, keeps one posted after", async () => {
  const html = page(tpl, { reopen: { a: "2000-01-01T00:00:00Z", c: "2999-01-01T00:00:00Z" } });
  const file = write(SLUG + "-reopen.html", html);
  const h = hydrate(path.join(TMP, SLUG + "-answers.md"), file);
  const B = openTab(fs.readFileSync(file, "utf8"));
  const note = (id) => !!sec(B, id).querySelector(".reopened");
  return [h.status === 0 && cb(B, "a").checked && !note("a") && !cb(B, "c").checked && note("c"), `a(reopen before post) checked=${cb(B, "a").checked} c(reopen after post) checked=${cb(B, "c").checked} REOPENED on c=${note("c")}`];
});

T("hydrate contract: refuses wrong slug and pre-4.0 HTML; idempotent; writes through a symlink", async () => {
  const answers = path.join(TMP, SLUG + "-answers.md");
  const other = write("other.html", page(tpl, { slug: "other-slug" }));
  const wrong = write("wrong-answers.md", "<!-- field-report receipt · slug=other-slug · answered=1/3 · posted=2026-10-30T00:00:00Z -->\n# T\n\n## sections-completed\n\na\n");
  const r1 = hydrate(wrong, write("mine.html", page(tpl))).status;
  const old = oldTemplate();
  const r2 = old ? hydrate(answers, write("old.html", page(old))).status : 2;
  const file = path.join(TMP, SLUG + ".html");
  const before = fs.readFileSync(file, "utf8");
  const again = hydrate(answers, file);
  const same = fs.readFileSync(file, "utf8") === before;
  const link = path.join(TMP, "link.html"); fs.symlinkSync(other, link);
  const r3 = hydrate(write("o-answers.md", "# T\n\n## sections-completed\n\nb\n"), link).status;
  const viaLink = fs.lstatSync(link).isSymbolicLink() && JSON.parse(fs.readFileSync(other, "utf8").match(/<script id="fr-state" type="application\/json">(.*?)<\/script>/)[1]).done[0] === "b";
  const ok = r1 === 2 && r2 === 2 && again.status === 0 && /already current/.test(again.stdout) && same && r3 === 0 && viaLink;
  return [ok, `wrong-slug exit=${r1} pre-4.0 exit=${r2}${old ? "" : "(SKIP)"} rerun="${again.stdout.trim().slice(0, 40)}" unchanged=${same} symlink exit=${r3} target-updated=${viaLink}`];
});

// The v4.1.0 template (last release whose presence cell said "listening"), for the forced red.
function prevTemplate() {
  try { return execFileSync("git", ["-C", ROOT, "show", "28168f3:references/canonical-template.html"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); }
  catch (e) { return null; }
}

T("presence cell says what the page can prove: Lavish wired / absent, never listening", async () => {
  const stub = { queuePrompt() {}, async sendQueuedPrompts() {} };
  const html = page(tpl);
  const wired = $(openTab(html, { lavish: stub }), "#presenceText").textContent;
  const absent = $(openTab(html), "#presenceText").textContent;
  const prev = prevTemplate();
  const red = prev ? $(openTab(page(prev), { lavish: stub }), "#presenceText").textContent : null;
  const ok = wired === "Lavish: wired" && absent === "Lavish: absent" && !/listening/i.test(wired + absent) && (prev === null || /listening/.test(red));
  return [ok, `wired="${wired}" absent="${absent}" v4.1.0-said="${red === null ? "SKIP(no git)" : red}"`];
});

T("real Chrome, Lavish's exact sandbox: storage throws, hydrated state renders", async () => {
  const chrome = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  if (!fs.existsSync(chrome)) return [true, "SKIP(no Chrome at " + chrome + ")"];
  const dir = fs.mkdtempSync(path.join(TMP, "chrome-"));
  const probe = `<script>(function(){var r={};try{localStorage.getItem("x");r.ls="OK"}catch(e){r.ls=e.name}
    r.checked=[].slice.call(document.querySelectorAll(".check input:checked")).map(function(c){return c.dataset.cb});
    r.disk=(document.getElementById("diskText")||{}).textContent;parent.postMessage(JSON.stringify(r),"*")})()</script></body>`;
  fs.writeFileSync(path.join(dir, "report.html"), fs.readFileSync(path.join(TMP, SLUG + ".html"), "utf8").replace("</body>", probe));
  fs.writeFileSync(path.join(dir, "parent.html"), `<!doctype html><body><pre id="out"></pre>
    <iframe sandbox="${LAVISH_SANDBOX}" src="report.html"></iframe>
    <script>addEventListener("message",function(e){document.getElementById("out").textContent="PROBE:"+e.data})</script></body>`);
  const r = spawnSync(chrome, ["--headless=new", "--disable-gpu", "--no-first-run", "--user-data-dir=" + path.join(dir, "profile"),
    "--virtual-time-budget=5000", "--dump-dom", "file://" + path.join(dir, "parent.html")], { encoding: "utf8", timeout: 60000 });
  const m = (r.stdout || "").match(/PROBE:(\{[^<]*\})/);
  if (!m) return [false, "no probe result; chrome exit=" + r.status + " " + (r.stderr || "").slice(0, 200)];
  const p = JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&"));
  return [p.ls === "SecurityError" && JSON.stringify(p.checked) === '["a","c"]' && /^on disk /.test(p.disk), `localStorage=${p.ls} checked=${JSON.stringify(p.checked)} answers="${p.disk}"`];
});

(async () => {
  let fail = 0;
  console.log("template: " + path.relative(process.cwd(), TEMPLATE));
  for (const [name, fn] of cases) {
    let ok, detail;
    try { [ok, detail] = await fn(); } catch (e) { ok = false; detail = "threw: " + (e && e.stack || e); }
    console.log((ok ? "ok   " : "FAIL ") + name + "\n       " + detail);
    if (!ok) fail = 1;
  }
  fs.rmSync(TMP, { recursive: true, force: true });
  console.log(fail ? "RESULT: FAIL" : "RESULT: PASS");
  process.exit(fail);
})();
