// aether-console-seat: the one owner of the console shelf's terminal window.
//
// The terminal exists only inside the shelf's glass (a hole in the detail card's
// "Terminal" view). Matched by PID - Konsole runs one process per window, and the
// console launches it with --unique and hands the pid over with the seat rect -
// so the user's other Konsole windows are never touched.
//
// Console -> script: two keyless global shortcuts fired over kglobalaccel's DBus.
// Script -> console: org.aether.Console slots via callDBus.
//   Aether Console Seat Show   seat the window (pid+geometry asked from the console)
//   Aether Console Seat Hide   conceal it and give focus back
//   SeatReady                  the window is seated and visible: the frost may clear

const CONSOLE = ["org.aether.Console", "/Console", "org.aether.Console"];
// Squash (KWin's minimize effect) runs ~250 ms x the animation factor; the window stays
// transparent through it so the effect is never seen.
const REVEAL_MS = 420;

let main = null;        // the seated terminal window
let targetPid = 0;      // the pid the console launched (0 = nobody asked yet)
let wanted = false;     // the shelf asked for the terminal to be shown
let seat = null;        // {x, y, width, height} in screen coordinates
let prevActive = null;  // focus to give back on hide
let seating = false;    // our own geometry writes, so frameGeometryChanged doesn't re-enter

const revealTimer = new QTimer();
revealTimer.singleShot = true;
revealTimer.interval = REVEAL_MS;
revealTimer.timeout.connect(function () {
    if (!wanted || !main) return;
    main.opacity = 1;
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "SeatReady");
});

function isOurs(w) {
    return w && w.normalWindow && targetPid > 0 && w.pid === targetPid;
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
    if (main || !isOurs(w)) return;
    main = w;
    dress(w);
    w.frameGeometryChanged.connect(function () {
        // Konsole restores its own saved bounds on show; while seated, the seat wins.
        if (w === main && wanted && !seating && !w.minimized) place(w);
    });
    if (wanted) {
        present();
    } else {
        conceal(w);
    }
}

workspace.windowAdded.connect(function (w) {
    adopt(w);
});
workspace.windowRemoved.connect(function (w) {
    if (w === main) main = null;   // closed by the user; the next Show re-launches
});

registerShortcut("Aether Console Seat Show", "Aether: seat the console terminal in the shelf", "", function () {
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "seatRect", function (s) {
        const p = String(s).split(",").map(Number);
        if (p.length !== 5 || p[2] <= 0 || p[3] <= 0 || p[4] <= 0) return;
        targetPid = p[0];
        seat = { x: p[1], y: p[2], width: p[3], height: p[4] };
        if (!wanted) {
            const a = workspace.activeWindow;
            prevActive = a && a !== main ? a : null;
        }
        wanted = true;
        // Re-seat first (the konsole of this card may still be alive, concealed); a launch
        // in flight is adopted by windowAdded the moment it maps.
        const ws = workspace.windowList();
        for (let i = 0; i < ws.length; i++) {
            if (isOurs(ws[i]) && !main) adopt(ws[i]);
        }
        if (main) present();
    });
});

registerShortcut("Aether Console Seat Hide", "Aether: hide the console terminal", "", function () {
    if (!wanted) return;
    wanted = false;
    const hadFocus = main && main.active;
    if (main) conceal(main);
    if (hadFocus && prevActive && workspace.windowList().indexOf(prevActive) >= 0 && !prevActive.minimized) {
        workspace.activeWindow = prevActive;
    }
    prevActive = null;
});
