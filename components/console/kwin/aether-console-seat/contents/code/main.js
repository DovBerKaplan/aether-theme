// aether-console-seat: the one owner of the console shelf's terminal windows.
//
// Each terminal exists only inside the shelf's glass (a hole in a terminal pane; split
// view can seat several at once). Windows are matched BY PID - the console launches Konsole itself and
// answers ownsWindow(pid) over D-Bus - so the user's other Konsole windows are never
// touched. Several terminals can live concealed at once (one per connection); the wanted
// one is seated, the rest stay hidden. A window that disappears (ssh died, network drop)
// is reported to the console, which re-connects and re-seats.
//
// Console -> script: two keyless global shortcuts fired over kglobalaccel's DBus.
// Script -> console: org.aether.Console slots via callDBus.
//   Aether Console Seat Show   seat the window (pid+geometry asked from the console)
//   Aether Console Seat Hide   conceal the wanted window and give focus back
//   SeatReady(pid)             that window is seated and visible: the frost may clear
//   SeatFocused(pid)           the user clicked into that window: its pane takes focus
//   SeatClosed(pid)            a terminal window is gone (crash, user close): reconnect

const CONSOLE = ["org.aether.Console", "/Console", "org.aether.Console"];
// Squash (KWin's minimize effect) runs ~250 ms x the animation factor; the window stays
// transparent through it so the effect is never seen.
const REVEAL_MS = 420;

let wanted = {};        // pid -> {x, y, width, height} for every terminal on stage (split view: many)
let focusPid = 0;       // the pane that owns the keyboard
let prevActive = null;  // focus to give back on hide
let windows = {};       // pid -> our adopted windows (dressed; concealed unless wanted)
let reveals = {};       // pid -> the timer that unveils that window once its squash effect is over

function revealTimer(pid) {
    if (!reveals[pid]) {
        const t = new QTimer();
        t.singleShot = true;
        t.interval = REVEAL_MS;
        t.timeout.connect(function () {
            const w = windows[pid];
            if (!wanted[pid] || !w) return;
            w.opacity = 1;
            callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "SeatReady", String(pid));
        });
        reveals[pid] = t;
    }
    return reveals[pid];
}

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
    const seat = wanted[w.pid];
    if (!seat) return;
    const g = w.frameGeometry;
    if (g.x === seat.x && g.y === seat.y && g.width === seat.width && g.height === seat.height) return;
    w.frameGeometry = seat;
}

function present(pid) {
    const w = windows[pid];
    if (!wanted[pid] || !w) return;
    dress(w);
    w.opacity = 0;
    if (w.minimized) w.minimized = false;
    place(w);
    if (focusPid === pid || !workspace.activeWindow || !windows[workspace.activeWindow.pid]) workspace.activeWindow = w;
    revealTimer(pid).start();
}

function adopt(w) {
    if (!w || w.normalWindow === false) return;
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "ownsWindow", String(w.pid), function (owns) {
        if (!owns || windows[w.pid]) return;
        windows[w.pid] = w;
        dress(w);
        w.frameGeometryChanged.connect(function () {
            // Konsole restores its own saved bounds on show; while seated, the seat wins.
            if (wanted[w.pid] && !w.minimized) place(w);
        });
        if (wanted[w.pid]) {
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

// the user clicked into a terminal: its pane becomes the focused one
workspace.windowActivated.connect(function (w) {
    if (w && windows[w.pid] && wanted[w.pid]) {
        callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "SeatFocused", String(w.pid));
    }
});

registerShortcut("Aether Console Seat Show", "Aether: seat the console terminals in the shelf", "", function () {
    callDBus(CONSOLE[0], CONSOLE[1], CONSOLE[2], "seatRect", function (s) {
        const halves = String(s).split("|");
        const next = {};
        (halves[1] || "").split(";").forEach(function (part) {
            const p = part.split(",").map(Number);
            if (p.length !== 5 || !(p[3] > 0) || !(p[4] > 0)) return;
            next[p[0]] = { x: p[1], y: p[2], width: p[3], height: p[4] };
        });
        const prevFocus = focusPid;
        focusPid = Number(halves[0]) || 0;
        if (workspace.activeWindow && !prevActive && !windows[workspace.activeWindow.pid]) prevActive = workspace.activeWindow;
        // everyone leaving the stage is concealed before the rest is handed over
        for (const pid in wanted) {
            if (!next[pid] && windows[pid]) conceal(windows[pid]);
        }
        const before = wanted;
        wanted = next;
        for (const pid in next) {
            const w = windows[pid];
            if (!w) continue;   // a launch is in flight - windowAdded adopts and presents it
            // already seated and showing: the hole only moved - just follow it
            if (before[pid] && !w.minimized && w.opacity === 1) {
                place(w);
            } else {
                present(Number(pid));
            }
        }
        if (focusPid && focusPid !== prevFocus && windows[focusPid] && wanted[focusPid] && !windows[focusPid].minimized) {
            workspace.activeWindow = windows[focusPid];
        }
    });
});

registerShortcut("Aether Console Seat Hide", "Aether: hide the console terminals", "", function () {
    let hadFocus = false;
    for (const pid in wanted) {
        const w = windows[pid];
        if (!w) continue;
        if (w.active) hadFocus = true;
        conceal(w);
    }
    if (hadFocus && prevActive && workspace.windowList().indexOf(prevActive) >= 0 && !prevActive.minimized) {
        workspace.activeWindow = prevActive;
    }
    prevActive = null;
    wanted = {};
    focusPid = 0;
});
