#!/usr/bin/env node
// zcode-rtl-inspect: read-only DOM survey of the running ZCode renderer over
// the Chromium DevTools Protocol. Reports which elements hold Hebrew text and
// what direction Chromium gave them, so the RTL CSS can target real selectors.
// Usage: node zcode-rtl-inspect.mjs [port]      (default 9223)

const PORT = Number(process.argv[2] || 9223);

const SURVEY = `(() => {
  const HEBREW = /[\\u0590-\\u05FF]/;
  const groups = new Map();
  const els = document.body ? document.body.querySelectorAll("*") : [];
  let scanned = 0, hebrew = 0;
  for (const el of els) {
    if (scanned++ > 30000) break;
    if (el.childElementCount === 0 && el.textContent && HEBREW.test(el.textContent)) {
      hebrew++;
      const cls = typeof el.className === "string"
        ? el.className.trim().split(/\\s+/).slice(0, 2).join(".") : "";
      const key = el.tagName.toLowerCase() + (cls ? "." + cls : "");
      const g = groups.get(key) || { n: 0, dirs: {} };
      g.n++;
      const d = getComputedStyle(el).direction;
      g.dirs[d] = (g.dirs[d] || 0) + 1;
      groups.set(key, g);
    }
  }
  const top = [...groups.entries()].sort((a, b) => b[1].n - a[1].n).slice(0, 25)
    .map(([k, g]) => "  " + k + ": n=" + g.n + " dirs=" + JSON.stringify(g.dirs));
  return [
    "html dir=" + document.documentElement.dir + " lang=" + document.documentElement.lang,
    "body direction=" + (document.body ? getComputedStyle(document.body).direction : "?"),
    "explicit [dir] attributes=" + document.querySelectorAll("[dir]").length,
    "hebrew leaf elements=" + hebrew,
    "groups:",
    ...top,
  ].join("\\n");
})()`;

let seq = 0;
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

const connect = (wsUrl) => new Promise((resolve, reject) => {
  const ws = new WebSocket(wsUrl);
  ws.onopen = () => resolve(ws);
  ws.onerror = () => reject(new Error("websocket refused"));
});

async function main() {
  let list;
  try {
    list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  } catch (e) {
    console.error(`no DevTools endpoint on 127.0.0.1:${PORT} (${e.message}).`);
    console.error("Start ZCode through the kit (quit it first — it is single-instance):");
    console.error("  ~/.local/bin/zcode-rtl     (or relaunch from the dock/launcher)");
    process.exit(1);
  }
  const pages = list.filter((t) => t.type === "page" && !t.url.startsWith("devtools"));
  console.log(`CDP targets: ${list.length}, page windows: ${pages.length}`);
  for (const p of pages) {
    console.log(`\n== ${p.title.slice(0, 60)}  |  ${p.url.slice(0, 80)}`);
    try {
      const ws = await connect(p.webSocketDebuggerUrl);
      const r = await send(ws, "Runtime.evaluate", { expression: SURVEY, returnByValue: true });
      console.log(r.result?.value ?? "(empty result)");
      ws.close();
    } catch (e) {
      console.log(`  survey failed: ${e.message}`);
    }
  }
}

main();
