#!/usr/bin/env node
// zcode-rtl-apply: live CSS/JS injection into the ZCode renderer over CDP.
//   node zcode-rtl-apply.mjs css <file>   inject (or replace) <style id=aether-rtl>
//   node zcode-rtl-apply.mjs flip         html dir=rtl on (experiment)
//   node zcode-rtl-apply.mjs revert       remove our style tag, restore dir=""
//   node zcode-rtl-apply.mjs js '<expr>'  evaluate an expression
// No dependencies (Node 20+).

const PORT = Number(process.env.ZCODE_CDP_PORT || 9223);
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

async function pageTarget() {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const page = list.find((t) => t.type === "page" && !t.url.startsWith("devtools"));
  if (!page) throw new Error("no ZCode page window on the DevTools endpoint");
  return page;
}

function cssPayload(css) {
  return `(function(){
    let s = document.getElementById("aether-rtl");
    if (!s) { s = document.createElement("style"); s.id = "aether-rtl"; document.head.appendChild(s); }
    s.textContent = ${JSON.stringify(css)};
    return "style applied, " + ${JSON.stringify(css)}.length + " bytes";
  })()`;
}

const FLIP = `(function(){
  document.documentElement.setAttribute("data-aether-dir-was", document.documentElement.dir || "");
  document.documentElement.setAttribute("dir", "rtl");
  return "documentElement dir=rtl";
})()`;

const REVERT = `(function(){
  const s = document.getElementById("aether-rtl");
  if (s) s.remove();
  const was = document.documentElement.getAttribute("data-aether-dir-was");
  if (was !== null) { was ? document.documentElement.setAttribute("dir", was) : document.documentElement.removeAttribute("dir"); document.documentElement.removeAttribute("data-aether-dir-was"); }
  return "reverted";
})()`;

const [cmd, arg] = process.argv.slice(2);
const expr =
  cmd === "css" ? cssPayload(await (await import("node:fs/promises")).readFile(arg, "utf8")) :
  cmd === "flip" ? FLIP :
  cmd === "revert" ? REVERT :
  cmd === "js" ? arg : null;
if (!expr) { console.error("usage: zcode-rtl-apply.mjs css <file> | flip | revert | js '<expr>'"); process.exit(2); }

const target = await pageTarget();
const ws = await connect(target.webSocketDebuggerUrl);
const r = await send(ws, "Runtime.evaluate", { expression: expr, returnByValue: true });
console.log(r.result?.value ?? JSON.stringify(r));
ws.close();
