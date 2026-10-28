// AetherOS panel + desktop widget layout. Run via:
//   qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat layout.js)"
// removes every panel (the top bar is the Aether Island, the dock is aether-dock), and clears desktop widgets.

// The dock is no Plasma panel any more: it is the aether-dock service (hidden at rest, revealed
// from the bottom or left edge; pins in ~/.config/aetherdockrc, defaults in components/dock). This
// script only clears old panels and desktop widgets.

var hasControlStation = false;
var hasAndromeda = false;

// Drop every panel (top bar = island, dock = aether-dock).
panels().forEach(function (p) { p.remove(); });

knownWidgetTypes.forEach(function (t) {
    if (t === "KdeControlStation") hasControlStation = true;
    if (t === "AndromedaLauncher") hasAndromeda = true;
});

// ---- Top bar: none ------------------------------------------------------
// The top bar is the Aether Island (aether-island service): a transparent bar with the notch
// that appears when the pointer touches the top edge. Plasma has no top panel any more.

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
