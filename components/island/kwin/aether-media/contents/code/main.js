// aether-media: the one owner of the YouTube Music (Pear Desktop) window.
//
// The app exists only inside the island's media panel. This script runs for the whole
// session, so the window is held from the moment it maps - no floating flash at login,
// from the tray icon or from a second launch - and it never moves or resizes while
// shown: the island's glass does all the motion and frosts over / clears the seat.
//
// Island -> script: two global shortcuts without keys, fired over kglobalaccel's DBus
// (invokeShortcut). Script -> island: org.aether.Island slots via callDBus.
//   Aether Media Show   seat the window (geometry asked from the island) and activate it
//   Aether Media Hide   conceal it and give focus back
//   MediaWindowReady    the window is seated and visible: the island may clear the frost
//   MediaWindowMissing  no window to seat (app not running / hidden to tray): launch it
//   MediaFocusLost      another window was activated while the app was shown
//   Media               the app tried to show itself (tray, second instance): open the panel

const ISLAND = ["org.aether.Island", "/Island", "org.aether.Island"];
// Squash (KWin's minimize effect) runs ~250 ms x the animation factor; the window stays
// transparent through it so the effect is never seen.
const REVEAL_MS = 420;

let main = null;        // the app's main window (popups such as Google sign-in are left alone)
let wanted = false;     // the island asked for the app to be shown
let seat = null;        // {x, y, width, height} in screen coordinates
let prevActive = null;  // focus to give back on hide
let seating = false;    // our own geometry writes, so frameGeometryChanged doesn't re-enter
// Pear autostarts with the session; a window it maps then is concealed quietly instead of
// opening the panel (only a later, user-made launch should do that).
const loadedAt = Date.now();

const revealTimer = new QTimer();
revealTimer.singleShot = true;
revealTimer.interval = REVEAL_MS;
revealTimer.timeout.connect(function () {
    if (!wanted || !main) return;
    main.opacity = 1;
    island("MediaWindowReady");
});

function island(method, cb) {
    if (cb) callDBus(ISLAND[0], ISLAND[1], ISLAND[2], method, cb);
    else callDBus(ISLAND[0], ISLAND[1], ISLAND[2], method);
}

function isApp(w) {
    return w && w.normalWindow && String(w.resourceClass).indexOf("youtube-music") >= 0;
}

function dress(w) {
    w.noBorder = true;
    w.skipTaskbar = true;
    w.skipSwitcher = true;
    w.skipPager = true;
    w.keepAbove = true;
}

function conceal(w) {
    revealTimer.stop();
    w.opacity = 0;
    if (!w.minimized) w.minimized = true;
}

function place(w) {
    if (!seat) return;
    const g = w.frameGeometry;
    if (g.x === seat.x && g.y === seat.y && g.width === seat.width && g.height === seat.height) return;
    seating = true;
    w.frameGeometry = seat;
    seating = false;
}

function present() {
    if (!wanted || !main || !seat) return;
    dress(main);
    main.opacity = 0;
    if (main.minimized) main.minimized = false;
    place(main);
    workspace.activeWindow = main;
    revealTimer.start();
}

function adopt(w) {
    if (main || !isApp(w)) return;
    main = w;
    dress(w);
    w.minimizedChanged.connect(function () {
        // Shown by someone other than the island (tray icon, second instance, a launcher):
        // hide it at once and open the panel instead, which seats it properly.
        if (w === main && !w.minimized && !wanted) {
            conceal(w);
            island("Media");
        }
    });
    w.frameGeometryChanged.connect(function () {
        // The app restores its own saved bounds on show; while seated, the seat wins.
        if (w === main && wanted && !seating && !w.minimized) place(w);
    });
    if (wanted) {
        present();
    } else {
        conceal(w);
    }
}

workspace.windowAdded.connect(function (w) {
    // Mapped while nobody asked (startup with appVisible, tray, second instance).
    const fresh = !main && isApp(w);
    adopt(w);
    if (fresh && !wanted && Date.now() - loadedAt > 20000) island("Media");
});
workspace.windowRemoved.connect(function (w) {
    if (w !== main) return;
    main = null;
    revealTimer.stop();
    // The app hid itself to the tray (or quit): adopt the next one that maps.
    const ws = workspace.windowList();
    for (let i = 0; i < ws.length; i++) {
        if (ws[i] !== w) adopt(ws[i]);
    }
});
workspace.windowActivated.connect(function (w) {
    // Any other window, the app's own popups (Google sign-in) included: they can't be used
    // under the island, so the panel folds and leaves them to the user.
    // A freshly mapped app window is activated before windowAdded adopts it: that one is
    // the main window arriving, not something else taking focus.
    if (wanted && w && w !== main && w.normalWindow && !(isApp(w) && !main)) island("MediaFocusLost");
});

registerShortcut("Aether Media Show", "Aether: seat YouTube Music in the island", "", function () {
    island("mediaSeat", function (s) {
        const p = String(s).split(",").map(Number);
        if (p.length !== 4 || p[2] <= 0 || p[3] <= 0) return;
        seat = { x: p[0], y: p[1], width: p[2], height: p[3] };
        if (!wanted) {
            const a = workspace.activeWindow;
            prevActive = a && a !== main ? a : null;
        }
        wanted = true;
        if (main) present();
        else island("MediaWindowMissing");
    });
});

registerShortcut("Aether Media Hide", "Aether: hide YouTube Music", "", function () {
    if (!wanted) return;
    wanted = false;
    const hadFocus = main && main.active;
    if (main) conceal(main);
    if (hadFocus && prevActive && workspace.windowList().indexOf(prevActive) >= 0 && !prevActive.minimized) {
        workspace.activeWindow = prevActive;
    }
    prevActive = null;
});

// Loaded mid-session (install, KWin restart): take over whatever is already mapped.
(function () {
    const ws = workspace.windowList();
    for (let i = 0; i < ws.length; i++) adopt(ws[i]);
})();
