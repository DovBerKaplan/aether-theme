// aether-console-seat: the one owner of the console shelf's terminal windows.
//
// Each terminal exists only inside the shelf's glass (a hole in the detail card's
// "Terminal" view). Windows are matched BY PID - the console launches Konsole itself and
// answers ownsWindow(pid) over D-Bus - so the user's other Konsole windows are never
// touched. Several terminals can live concealed at once (one per connection); the wanted
// one is seated, the rest stay hidden. A window that disappears (ssh died, network drop)
// is reported to the console, which re-connects and re-seats.
//
// Console -> script: two keyless global shortcuts fired over kglobalaccel's DBus.
// Script -> console: org.aether.Console slots via callDBus.
//   Aether Console Seat Show   seat the window (pid+geometry asked from the console)
//   Aether Console Seat Hide   conceal the wanted window and give focus back
//   SeatReady                  the wanted window is seated and visible: the frost may clear
//   SeatClosed(pid)            a terminal window is gone (crash, user close): reconnect

const CONSOLE = ["org.aether.Console", "/Console", "org.aether.Console"];
// Squash (KWin's minimize effect) runs ~250 ms x the animation factor; the window stays
// transparent through it so the effect is never seen.
const REVEAL_MS = 420;

let wantedPid = 0;      // the terminal the shelf wants on screen right now
let seat = null;        // {x, y, width, height} in screen coordinates
let prevActive = null;  // focus to give back on hide
let windows = {};       // pid -> our adopted windows (dressed; concealed unless wanted)

const revealTimer = new QTimer();
revealTimer.singleShot = true;
revealTimer.interval = REVEAL_MS;
revealTimer.timeout.connect(function () {
    const w = windows[wantedPid];
    if (!wantedPid || !w) return;
    w.opacity = 1;
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "SeatReady");
});

function dress(w) {
    w.noBorder = true;
    w.skipTaskbar = true;
    w.skipSwitcher = true;
    w.skipPager = true;
    w.keepAbove = true;
}

function conceal(w) {
    w.opacity = 0;
    if (!w.minimized) w.minimized = true;
}

function place(w) {
    if (!seat) return;
    const g = w.frameGeometry;
    if (g.x === seat.x && g.y === seat.y && g.width === seat.width && g.height === seat.height) return;
    w.frameGeometry = seat;
}

function present(pid) {
    const w = windows[pid];
    if (!wantedPid || !w || !seat) return;
    dress(w);
    w.opacity = 0;
    if (w.minimized) w.minimized = false;
    place(w);
    workspace.activeWindow = w;
    revealTimer.start();
}

function adopt(w) {
    if (!w || w.normalWindow === false) return;
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "ownsWindow", String(w.pid), function (owns) {
        if (!owns || windows[w.pid]) return;
        windows[w.pid] = w;
        dress(w);
        w.frameGeometryChanged.connect(function () {
            // Konsole restores its own saved bounds on show; while seated, the seat wins.
            if (wantedPid === w.pid && !w.minimized) place(w);
        });
        if (w.pid === wantedPid) {
            present(w.pid);
        } else {
            conceal(w);
        }
    });
}

workspace.windowAdded.connect(function (w) {
    adopt(w);
});
workspace.windowRemoved.connect(function (w) {
    print("AETHERSEAT removed pid=", w.pid, "tracked:", Object.keys(windows).join(","));
    for (const pid in windows) {
        if (windows[pid] === w) {
            delete windows[pid];
            callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "SeatClosed", pid);
            return;
        }
    }
});

registerShortcut("Aether Console Seat Show", "Aether: seat the console terminal in the shelf", "", function () {
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "seatRect", function (s) {
        const p = String(s).split(",").map(Number);
        if (p.length !== 5 || p[1] <= 0 || p[2] <= 0 || p[3] <= 0 || p[4] <= 0) return;
        const pid = p[0];
        seat = { x: p[1], y: p[2], width: p[3], height: p[4] };
        if (wantedPid !== pid) {
            // conceal whoever is on stage before handing it over
            const prev = windows[wantedPid];
            if (prev) conceal(prev);
            if (workspace.activeWindow === prev) {
                const a = workspace.activeWindow;
                prevActive = a && a !== prev ? a : null;
            }
        }
        // already seated and showing: the hole only moved (the glass settled) - just follow it
        const cur = windows[pid];
        if (wantedPid === pid && cur && !cur.minimized && cur.opacity === 1) {
            place(cur);
            return;
        }
        wantedPid = pid;
        if (windows[pid]) {
            present(pid);
        }   // else: a launch is in flight - windowAdded adopts and presents it
    });
});

registerShortcut("Aether Console Seat Hide", "Aether: hide the console terminal", "", function () {
    if (!wantedPid) return;
    const w = windows[wantedPid];
    const hadFocus = w && w.active;
    if (w) conceal(w);
    if (hadFocus && prevActive && workspace.windowList().indexOf(prevActive) >= 0 && !prevActive.minimized) {
        workspace.activeWindow = prevActive;
    }
    prevActive = null;
    wantedPid = 0;
});
