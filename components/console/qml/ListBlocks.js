.pragma library
// The home list as one flat block list: labels, sessions, containers, pods, the k8s context row.
// `discovery` is the Discovery object; tr / ltr are I18n's functions.
function build(sessions, discovery, filter, tr, ltr) {
    var f = filter.trim().toLowerCase();
    function has(v) { return (v || "").toLowerCase().indexOf(f) >= 0; }
    var hit = function (s) { return !f || has(s.name) || has(s.host) || has(s.group); };
    var out = [];
    var act = sessions.filter(function (s) { return s.open && hit(s); });
    if (act.length > 0) {
        out.push({ t: "label", text: tr("Active now") });
        act.forEach(function (s) { out.push({ t: "session", s: s, active: true }); });
    }
    var saved = sessions.filter(function (s) { return !s.open && hit(s); });
    var names = [];
    saved.forEach(function (s) { var g = s.group || tr("General"); if (names.indexOf(g) < 0) names.push(g); });
    names.sort(function (a, b) { return a.localeCompare(b); });
    names.forEach(function (g) {
        out.push({ t: "label", text: g });
        saved.filter(function (s) { return (s.group || tr("General")) === g; })
             .forEach(function (s) { out.push({ t: "session", s: s }); });
    });
    if (discovery.hasContainers) {
        var labeled = false;
        discovery.containers.filter(function (c) { return !f || has(c.name) || has(c.image); })
            .forEach(function (c) {
                if (!labeled) { out.push({ t: "label", text: tr("Containers") }); labeled = true; }
                out.push({ t: "cont", c: c });
            });
    }
    if (discovery.hasKubectl && discovery.context.length > 0) {
        var ps = discovery.pods.filter(function (p) { return !f || has(p.name) || has(p.ns); });
        if (ps.length > 0 || (discovery.contexts.length > 1 && !f)) {
            if (discovery.contexts.length > 1 && !f) out.push({ t: "ctx" });
            if (ps.length > 0) {
                out.push({ t: "label", text: tr("Pods") + " · " + ltr(discovery.context) });
                ps.forEach(function (p) { out.push({ t: "pod", p: p }); });
            }
        }
    }
    return out;
}
