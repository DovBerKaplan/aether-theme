#!/usr/bin/env node
// zcode-rtl-inject: resident injector. Runs as a systemd --user service,
// waits for a ZCode DevTools endpoint (launched via zcode-rtl) and keeps the
// RTL state alive in every renderer: documentElement dir=rtl plus the
// refinement CSS from rtl.css, re-applied on every navigation through
// Page.addScriptToEvaluateOnNewDocument. Follows new page targets, backs off
// while no app is running, exits when the port owner goes away.
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";

const PORT = Number(process.env.ZCODE_CDP_PORT || 9223);
const BASE = `http://127.0.0.1:${PORT}`;
const attached = new Set();
let css = "";

function send(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++seq;
    ws.addEventListener("message", function onmsg(ev) {
      const m = JSON.parse(ev.data);
      if (m.id !== id) return;
      ws.removeEventListener("message", onmsg);
      m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result);
    });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
let seq = 0;

const connect = (wsUrl) => new Promise((resolve, reject) => {
  const ws = new WebSocket(wsUrl);
  ws.onopen = () => resolve(ws);
  ws.onerror = () => reject(new Error("refused"));
});

async function up() {
  try {
    const r = await fetch(`${BASE}/json/version`, { signal: AbortSignal.timeout(1500) });
    return r.ok;
  } catch { return false; }
}

async function attach(target) {
  if (attached.has(target.id) || target.type !== "page" || target.url.startsWith("devtools")) return;
  attached.add(target.id);
  try {
    const ws = await connect(target.webSocketDebuggerUrl);
    ws.addEventListener("close", () => attached.delete(target.id));
    await send(ws, "Runtime.enable");
    // css text rides in the bootstrap: rewrite it per-attach
    const boot = `(function(cssText){
      const apply = () => {
        document.documentElement.setAttribute("dir", "rtl");
        let s = document.getElementById("aether-rtl");
        if (!s) {
          s = document.createElement("style");
          s.id = "aether-rtl";
          (document.head || document.documentElement).appendChild(s);
        }
        s.textContent = cssText;
      };
      apply();
      window.__aetherRtlApply = apply;
      const mo = new MutationObserver(() => {
        const s = document.getElementById("aether-rtl");
        if (document.documentElement.getAttribute("dir") !== "rtl" || !s || s.textContent !== cssText) apply();
      });
      mo.observe(document.documentElement, { childList: true });
      if (document.head) mo.observe(document.head, { childList: true });
    })`;
    await send(ws, "Page.enable");
    await send(ws, "Page.addScriptToEvaluateOnNewDocument", { source: `(${boot})(${JSON.stringify(css)})` });
    await send(ws, "Runtime.evaluate", { expression: `(${boot})(${JSON.stringify(css)})` });
    console.log(new Date().toISOString(), `attached: ${target.id.slice(0, 8)} ${target.url.slice(0, 60)}`);
    // keep the socket open; per-target lifecycle only
  } catch (e) {
    attached.delete(target.id);
  }
}

async function sweep() {
  try {
    const list = await (await fetch(`${BASE}/json/list`, { signal: AbortSignal.timeout(1500) })).json();
    for (const t of list) attach(t);
  } catch { attached.clear(); }
}

async function main() {
  // CSS order: env override, user config (installer default, user-editable),
  // sibling file (running from the repo).
  const candidates = [
    process.env.ZCODE_RTL_CSS,
    homedir() + "/.config/aether/zcode-rtl.css",
    new URL("./rtl.css", import.meta.url),
  ].filter(Boolean);
  for (const c of candidates) {
    try { css = await readFile(c, "utf8"); break; } catch {}
  }
  if (!css) css = "";
  console.log(new Date().toISOString(), `zcode-rtl-inject waiting on ${BASE}`);
  while (true) {
    if (await up()) await sweep();
    await new Promise((r) => setTimeout(r, 2000));
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
