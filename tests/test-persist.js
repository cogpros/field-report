#!/usr/bin/env node
// Persistence test (v3.1.2): done boxes and answers survive reload, a second window,
// and a re-render of the file; data-reopen reopens a section on purpose.
// Usage: node tests/test-persist.js [path-to-template.html]   (default: references/canonical-template.html)
// Each case drives the template's real <script> in jsdom. Two "tabs" share one
// storage object, the way two windows on one origin share localStorage; the
// shared store dispatches `storage` events to the OTHER tabs, as a browser does.
// jsdom is resolved from node_modules, $JSDOM_PATH, or a sibling hermes install.
"use strict";
const fs = require("fs");
const path = require("path");

function loadJsdom() {
  const tries = [() => require("jsdom"), () => require(process.env.JSDOM_PATH),
    () => require(path.join(process.env.HOME || "", ".hermes/hermes-agent/node_modules/jsdom"))];
  for (const t of tries) { try { return t(); } catch (e) { /* next */ } }
  console.error("jsdom not found: npm i jsdom, or set JSDOM_PATH"); process.exit(2);
}
const { JSDOM } = loadJsdom();

const TEMPLATE = path.resolve(process.argv[2] || path.join(__dirname, "..", "references", "canonical-template.html"));
const tpl = fs.readFileSync(TEMPLATE, "utf8");
const SLUG = "persist-test";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Build a report from the template: one section block becomes N sections.
function page({ ids = ["a", "b", "c"], reopen = {}, prefill = {}, title = "T" } = {}) {
  const m = tpl.match(/<section class="s" data-section="section-id">[\s\S]*?<\/section>/);
  if (!m) throw new Error("template has no section block");
  const secs = ids.map((id) => {
    let s = m[0].replace(/section-id/g, id).replace('data-q="section-notes"', `data-q="notes-${id}"`)
      .replace(/<div class="toggles" data-q="toggle-question">/, `<div class="toggles" data-q="tog-${id}">`);
    if (reopen[id]) s = s.replace('<section class="s"', `<section class="s" data-reopen="${reopen[id]}"`);
    if (prefill[id] !== undefined) s = s.replace(`data-q="notes-${id}" placeholder`, `data-q="notes-${id}" placeholder`).replace(/(<textarea class="note"[^>]*>)(<\/textarea>)/, `$1${prefill[id]}$2`);
    return s;
  }).join("\n");
  return tpl.replace(m[0], secs).replace(/\{FILE_SLUG_PLACEHOLDER\}/g, SLUG)
    .replace(/\{REPORT_TITLE_PLACEHOLDER\}/g, title).replace(/\{SESSION_ID_PLACEHOLDER\}/g, "s").replace(/\{REPORT_PATH_PLACEHOLDER\}/g, "/x.html");
}

// One shared localStorage for every tab in a case.
function makeStore(seed = {}) {
  const m = new Map(Object.entries(seed)); const tabs = new Set();
  const api = {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem(k, v) { const old = api.getItem(k); m.set(k, String(v));
      for (const t of tabs) if (t !== api._origin) t.dispatchEvent(new t.StorageEvent("storage", { key: k, newValue: String(v), oldValue: old })); },
    removeItem: (k) => m.delete(k), clear: () => m.clear(), key: (i) => [...m.keys()][i], get length() { return m.size; },
  };
  return { api, tabs, raw: () => JSON.parse(m.get(SLUG) || "{}") };
}
function openTab(store, html, { notify = true } = {}) {
  const dom = new JSDOM(html, { runScripts: "dangerously", pretendToBeVisual: true, url: "http://localhost/r.html",
    beforeParse(w) {
      const wrapped = Object.assign(Object.create(null), store.api);
      wrapped.setItem = (k, v) => { store.api._origin = notify ? w : null; store.api.setItem(k, v); };
      Object.defineProperty(w, "localStorage", { value: wrapped, configurable: true });
    } });
  store.tabs.add(dom.window);
  return dom.window;
}
const $ = (w, sel) => w.document.querySelector(sel);
const cb = (w, id) => $(w, `input[data-cb="${id}"]`);
const sec = (w, id) => $(w, `section[data-section="${id}"]`);
async function check(w, id, on = true) { const c = cb(w, id); c.checked = on; c.dispatchEvent(new w.Event("change", { bubbles: true })); await sleep(80); }
async function type(w, q, v) { const t = $(w, `textarea[data-q="${q}"]`); t.value = v; t.dispatchEvent(new w.Event("input", { bubbles: true })); await sleep(20); }
const progress = (w) => $(w, "#progressLabel").textContent.trim();

const cases = [];
const T = (name, fn) => cases.push([name, fn]);

// 1. Per-key save: a stale tab must not clobber a box another tab checked.
T("per-key save: stale tab cannot clobber another tab's box", async () => {
  const st = makeStore(); const A = openTab(st, page(), { notify: false }); const B = openTab(st, page(), { notify: false });
  await check(A, "a");
  await type(B, "notes-c", "typed in the stale tab");
  const A2 = openTab(st, page(), { notify: false });
  return [cb(A2, "a").checked && sec(A2, "a").classList.contains("done"), `reloaded box a checked=${cb(A2, "a").checked}; stored=${JSON.stringify(st.raw()).slice(0, 120)}`];
});

// 2. storage event: a second open window updates live.
T("storage event: second window updates live", async () => {
  const st = makeStore(); const A = openTab(st, page()); const B = openTab(st, page());
  await check(A, "a"); await type(A, "notes-b", "hello"); await sleep(30);
  return [cb(B, "a").checked && sec(B, "a").classList.contains("done") && $(B, 'textarea[data-q="notes-b"]').value === "hello" && progress(B).startsWith("1 /"),
    `B box a=${cb(B, "a").checked} note=${JSON.stringify($(B, 'textarea[data-q="notes-b"]').value)} progress=${progress(B)}`];
});

// 3. Reopen: data-reopen unchecks only boxes done before that time; others never lose state.
T("reopen: data-reopen unchecks earlier-done boxes only, shows REOPENED", async () => {
  const R = "2026-10-29T12:00:00Z";
  const seed = { [SLUG]: JSON.stringify({ check__a: "1", done__a: "2026-10-29T10:00:00Z", check__b: "1", done__b: "2026-10-29T13:00:00Z", check__c: "1", done__c: "2026-10-29T10:00:00Z" }) };
  const st = makeStore(seed); const html = page({ reopen: { a: R, b: R } }); // c has no attribute
  const A = openTab(st, html, { notify: false });
  const note = (w, id) => sec(w, id).querySelector(".reopened");
  const ok1 = !cb(A, "a").checked && !sec(A, "a").classList.contains("done") && !!note(A, "a");
  const ok2 = cb(A, "b").checked && !note(A, "b");
  const ok3 = cb(A, "c").checked && !note(A, "c");
  const A2 = openTab(st, html, { notify: false }); // reload: still open, not re-closed, still noted
  const ok4 = !cb(A2, "a").checked && !!note(A2, "a");
  await check(A2, "a"); // operator closes it again after the agent's work
  const A3 = openTab(st, html, { notify: false });
  const ok5 = cb(A3, "a").checked && !note(A3, "a");
  return [ok1 && ok2 && ok3 && ok4 && ok5, `a reopened=${ok1} b kept=${ok2} c kept=${ok3} reload still open=${ok4} re-closed survives=${ok5}`];
});

// 4. Re-render of the same slug keeps every stored answer and box.
T("re-render: same slug keeps answers and boxes (prefill, dropped section)", async () => {
  const seed = { [SLUG]: JSON.stringify({ "notes-a": "operator answer A", "notes-b": "operator answer B", "notes-c": "operator answer C", check__a: "1", check__b: "1", check__c: "1" }) };
  const st = makeStore(seed);
  // new render: section c dropped, section a's textarea pre-filled by the agent
  const html = page({ ids: ["a", "b"], prefill: { a: "agent default text" }, title: "T2" });
  const A = openTab(st, html, { notify: false });
  const shown = $(A, 'textarea[data-q="notes-a"]').value === "operator answer A" && cb(A, "a").checked && cb(A, "b").checked;
  await type(A, "notes-b", "operator answer B edited");
  const s = st.raw();
  const kept = s["notes-a"] === "operator answer A" && s["notes-c"] === "operator answer C" && s.check__c === "1" && s.check__a === "1";
  const A2 = openTab(st, page({ ids: ["a", "b", "c"] }), { notify: false }); // section c comes back
  const back = $(A2, 'textarea[data-q="notes-c"]').value === "operator answer C" && cb(A2, "c").checked;
  return [shown && kept && back, `shown=${shown} stored-kept=${kept} section-c-returns=${back}`];
});

(async () => {
  let fail = 0;
  console.log("template: " + path.relative(process.cwd(), TEMPLATE));
  for (const [name, fn] of cases) {
    let ok, detail;
    try { [ok, detail] = await fn(); } catch (e) { ok = false; detail = "threw: " + (e && e.message); }
    console.log((ok ? "ok   " : "FAIL ") + name + "\n       " + detail);
    if (!ok) fail = 1;
  }
  console.log(fail ? "RESULT: FAIL" : "RESULT: PASS");
  process.exit(fail);
})();
