// AetherOS panel + desktop widget layout. Run via:
//   qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat layout.js)"
// Keeps the user's pinned launchers, replaces existing panels with a floating
// bottom dock (the top bar is the Aether Island), and adds glass widgets to the desktop.

var launchers = "preferred://filemanager,applications:org.kde.konsole.desktop,preferred://browser,applications:code.desktop,applications:systemsettings.desktop";
var hasControlStation = false;
var hasAndromeda = false;

// Remember the pinned apps from the current task manager, then drop old panels.
panels().forEach(function (p) {
    p.widgets().forEach(function (w) {
        if (w.type === "org.kde.plasma.icontasks" || w.type === "org.kde.plasma.taskmanager") {
            w.currentConfigGroup = ["General"];
            var l = w.readConfig("launchers", "");
            if (l && l.length > 0) launchers = String(l);
        }
    });
    p.remove();
});

knownWidgetTypes.forEach(function (t) {
    if (t === "KdeControlStation") hasControlStation = true;
    if (t === "AndromedaLauncher") hasAndromeda = true;
});

// ---- Top bar: none ------------------------------------------------------
// The top bar is the Aether Island (aether-island service): a transparent bar with the notch
// that appears when the pointer touches the top edge. Plasma has no top panel any more.

// ---- Bottom dock --------------------------------------------------------
var dock = new Panel("org.kde.panel");
dock.location = "bottom";
dock.height = 64;
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "autohide";   // hidden until the pointer touches the screen edge
dock.opacity = "translucent";

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", launchers);
tasks.writeConfig("showOnlyCurrentDesktop", false);
tasks.writeConfig("indicateAudioStreams", true);
tasks.writeConfig("iconSpacing", 2);

// ---- Desktop widgets (first desktop of the current activity) --------------
var desk = desktopsForActivity(currentActivity())[0];
if (desk) {
    desk.widgets().forEach(function (w) {
        if (w.type.indexOf("org.kde.plasma.systemmonitor") === 0 ||
            w.type === "org.kde.plasma.weather" || w.type === "org.kde.plasma.notes") {
            w.remove();
        }
    });
    // Quiet by default: no telemetry, weather or notes widgets on the desktop.
}
