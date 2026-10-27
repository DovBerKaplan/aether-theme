import QtQuick
import AetherShared
import org.kde.taskmanager as TaskManager
import "."

// Aether Island - replaces the top bar with a compact notch tab.
//   hidden    nothing visible; an invisible strip along the top edge listens for the pointer
//   bar       just the notch tab hanging from the top edge: search, clock (or timer), power
//   large     the tab grows into the island: media, toggles, sliders, timer
//   expanded  the island grows again ("double bar") and the notification history appears
//
// The three visible levels are one continuous curtain: dragging the handle (or the tab)
// tracks the pointer 1:1 and snaps to the nearest stop on release, velocity permitting.
// Open:  touch the top edge (tab), click / scroll down / drag (large), pull the handle down
//        or hold it (expanded), or Win+N
// Close: click outside, Esc, scroll up, the handle, move the pointer away, or drag up.
Item {
    id: root

    readonly property real shoulder: 10
    // Interface language (saved in aetherislandrc). Right-to-left languages mirror every
    // layout below; the media card and the battery icon opt out (they stay left-to-right).
    Binding { target: I18n; property: "lang"; value: tiles.language }
    // The YouTube Music widget: on = the card, the "bar becomes the app" mode and the app itself;
    // off = none of it exists (no card, no mode, no app process, no tray icon, no autostart).
    readonly property bool mediaOn: tiles.widgets.indexOf("media") >= 0
    // With the KDE Connect widget on, the phone's notifications live there (with reply and actions); the
    // plain forwarded copies are kept out of the history list and off disk.
    Binding { target: notifStore; property: "ignoredApps"; value: tiles.widgets.indexOf("connect") >= 0 ? ["KDE Connect"] : [] }
    onMediaOnChanged: {
        if (!mediaOn && mode === "media") setMode("large")
        media.setEnabled(mediaOn, true)
    }
    LayoutMirroring.enabled: I18n.rtl
    LayoutMirroring.childrenInherit: true
    readonly property real screenW: island.screenWidth
    readonly property real screenH: island.screenHeight
    readonly property bool big: mode === "large" || mode === "expanded" || mode === "panel" || mode === "activity"
    // Media mode: the whole bar becomes YouTube Music - nothing above the app but a
    // thin uniform glass bezel. It closes only deliberately: click outside, the handle,
    // wheel up, Win+N, or another window taking focus - never on pointer-leave.
    // One set of numbers feeds surface, input mask and the app's seat.
    readonly property int mediaAppW: Math.floor(Math.min(800, screenW - 160))
    readonly property int mediaAppH: Math.floor(Math.min(600, screenH - 220))
    readonly property int mediaBezel: 20      // top + sides
    // The app window never moves: it sits still in the seat (the aether-media KWin script
    // holds it there) while the glass does all the motion. The seat opens as solid frosted
    // glass and clears only once the window is really there AND the spring has landed;
    // leaving, the frost covers the app before anything folds.
    property bool mediaReady: false           // the script reported the window seated and visible
    property bool mediaSeated: false          // the glass reached the media stop since it opened
    property bool mediaCovered: true          // the app window is hidden (no hole needed)
    property string mediaPending: ""          // where to go once the frost has covered the app
    property bool mediaCovering: false
    readonly property bool mediaSettled: mode === "media" && interactiveBottom < 0 && !bottomSpring.running && !widthSpring.running
        && Math.abs(surface.notchBottom - shapes.media.nb) < 4 && Math.abs(surface.notchW - shapes.media.nw) < 4
    onMediaSettledChanged: if (mediaSettled) mediaSeated = true
    readonly property bool mediaClear: mode === "media" && mediaReady && mediaSeated && !dragging && !mediaCovering
    property real frost: mediaClear ? 0 : 1
    Behavior on frost { NumberAnimation { duration: root.mediaClear ? 260 : 140; easing.type: Easing.OutCubic } }
    readonly property int mediaGrip: 34       // bottom: room for the pull handle
    property var shapes: ({
        // sw = strip width, sh = strip height, nw = notch width, nb = notch bottom, r = notch corner radius
        "hidden":    { sw: 0, sh: 0, nw: 120, nb: 2,   r: 1,  win: Qt.size(screenW, 10) },
        "bar":       { sw: 0, sh: 0, nw: Math.max(124, Math.round(tabRow.implicitWidth) + 34), nb: 42, r: 15, win: Qt.size(screenW, 42) },
        "large":     { sw: 0, sh: 0, nw: 480, nb: Math.max(170, largeContent.contentHeight), r: 30, win: Qt.size(screenW, screenH) },
        "expanded":  { sw: 0, sh: 0, nw: 480, nb: Math.min(largeContent.expandedHeight, screenH - 80), r: 30, win: Qt.size(screenW, screenH) },
        "activity":  { sw: 0, sh: 0, nw: 440, nb: 112, r: 26, win: Qt.size(screenW, screenH) },
        "panel":     { sw: 0, sh: 0, nw: 480, nb: Math.max(170, largeContent.contentHeight, Math.min(panelHost.contentHeight, screenH - 120)), r: 30, win: Qt.size(screenW, screenH) },
        "media":     { sw: 0, sh: 0, nw: mediaAppW + 2 * mediaBezel, nb: mediaBezel + mediaAppH + mediaGrip, r: 30, win: Qt.size(screenW, screenH) }
    })

    property string mode: "hidden"
    // Panels: which one is open, and where Back returns to ("large", or "bar" when opened from the bar).
    property string panelFrom: "large"
    // Activities: a compact card for something that just happened (a file arrived). Only while the island is
    // out of the way (hidden or the small bar); if you are already in it, the panels show the news.
    property var activity: ({})
    property string activityFrom: "hidden"
    function showActivity(a) {
        // the same activity again (a call going from ringing to talking) just updates the card
        const same = mode === "activity" && a.key !== undefined && activity.key === a.key
        if (!same && mode !== "hidden" && mode !== "bar") return
        activity = a
        if (!same) {
            activityFrom = mode
            setMode("activity")
        }
        activityTimer.interval = a.duration || 9000
        activityTimer.restart()
    }
    function dismissActivity() {
        activityTimer.stop()
        if (mode === "activity") setMode(activityFrom)
    }
    Timer { id: activityTimer; interval: 9000; onTriggered: if (activityHost.hovered) restart(); else root.dismissActivity() }
    function activityAction(what) {
        const a = activity
        dismissActivity()
        if (what === "open" && a.url) connectModel.openReceived(a.url)
        else if (what === "folder" && a.url) connectModel.showReceived(a.url)
        else if (what === "tap" && a.panel) openPanel(a.panel)
    }
    Connections {
        target: connectModel
        // The daemon sends no "call ended": each state has its own time on screen, and the Connect card shows it too.
        function onCallEvent(device, event, who) {
            if (event === "ringing")
                root.showActivity({ key: "call", glyph: "phone", accent: true, pulse: true, title: I18n.f("Incoming call · %1", device), text: who, panel: "connect", duration: 45000,
                                    buttons: [{ id: "dismiss", label: I18n.tr("Dismiss"), kind: "tonal" }] })
            else if (event === "talking")
                root.showActivity({ key: "call", glyph: "phone", accent: true, title: I18n.f("In a call · %1", device), text: who, panel: "connect", duration: 6000,
                                    buttons: [{ id: "dismiss", label: I18n.tr("Dismiss"), kind: "tonal" }] })
            else
                root.showActivity({ key: "call", glyph: "phone", title: I18n.f("Missed call · %1", device), text: who, panel: "connect:notifications", duration: 12000,
                                    buttons: [{ id: "dismiss", label: I18n.tr("Dismiss"), kind: "tonal" }] })
        }
        function onLowBattery(device, percent) {
            root.showActivity({ glyph: "bolt", title: I18n.tr("Phone battery low"), text: I18n.f("%1 · %2%", device, percent), panel: "connect", duration: 8000 })
        }
    }
    Connections {
        target: connectModel
        function onFileReceived(device, name, url) {
            root.showActivity({ glyph: "folder", title: I18n.f("File received from %1", device), text: name, url: url, panel: "connect:files",
                                buttons: [{ id: "open", label: I18n.tr("Open file") }, { id: "folder", glyph: "folder" }] })
        }
    }
    function openPanel(id) {
        if (!id) return
        const parts = id.split(":")          // "connect:notifications" opens that page directly
        panelHost.panelId = parts[0]
        panelHost.page = parts.length > 1 ? parts[1] : ""
        panelFrom = (mode === "bar" || mode === "hidden" || mode === "activity") ? "bar" : "large"
        setMode("panel")
    }
    function panelBack() {
        if (panelHost.page !== "") panelHost.page = ""
        else setMode(panelFrom)
    }
    readonly property var shape: shapes[mode]
    property date now: new Date()

    // True while entering media mode, and for a short grace period after leaving it, so
    // the width keeps its own spring during those transitions (in the curtain modes it
    // otherwise rides on the height and must not oscillate separately).
    property bool mediaWidth: mode === "media"
    property bool activityWidth: mode === "activity"      // keeps its own width spring a moment after leaving, like media

    // How far the curtain stands between the bar stop and the large stop (0..1). Every
    // interior fade derives from it, so the content always animates *with* the glass's
    // spring instead of on its own timer - one motion, not several.
    readonly property real openT: Math.max(0, Math.min(1,
        (surface.notchBottom - shapes.bar.nb) / Math.max(1, shapes.large.nb - shapes.bar.nb)))

    // The pull curtain: while dragging, these override the shape so the surface follows the
    // pointer directly (the spring is disabled); on release the mode snaps and springs settle.
    // dy/velocity are cached on every move - a DragHandler's translation resets to 0 the
    // moment it deactivates, so reading them at release would look like "no movement".
    property bool dragging: false
    property real pullFrom: 0
    property real pullDy: 0
    property real pullVy: 0
    property real interactiveBottom: -1
    property real interactiveW: -1
    property real interactiveR: -1

    Binding { target: Theme; property: "bodyAlpha"; value: island.bodyAlpha }
    TimerState { id: timerState }
    Timer { interval: 1000; running: root.mode !== "hidden"; repeat: true; onTriggered: root.now = new Date() }

    // ---- active app name (shown in the large island's header) ------------------------
    TaskManager.TasksModel { id: tasks; groupMode: TaskManager.TasksModel.GroupDisabled }
    property string appName: ""
    function refreshApp() {
        const idx = tasks.activeTask
        const n = idx.valid ? tasks.data(idx, TaskManager.AbstractTasksModel.AppName) : ""
        appName = n && n.length ? n : I18n.tr("Desktop")
    }
    Connections {
        target: tasks
        function onActiveTaskChanged() { root.refreshApp() }
        function onDataChanged() { root.refreshApp() }
        function onCountChanged() { root.refreshApp() }
    }
    // NOTE: a track starting NEVER folds the media view anymore (user's call):
    // in YouTube Music almost every card click starts playback, so the old
    // auto-collapse kept shutting the bar mid-browsing. Closing is deliberate -
    // handle, wheel, outside click, Win+N, or pointer-leave when idle.
    Component.onCompleted: { media.setEnabled(mediaOn); refreshApp(); island.setWindowSize(curWin.width, curWin.height); syncLayout() }

    // ---- window sizing: grow before the shape animates, shrink after ----------------
    property size curWin: Qt.size(screenW, 10)
    // A Wayland window resize lands a few frames AFTER it is requested; if the opening
    // animation started immediately the glass would be clipped to the old window edge and
    // then pop into view - the glitch at the start of every open. So the shape is FROZEN
    // (via interactiveBottom) until the window has really grown, and only then released.
    property bool awaitResize: false
    function applyWindow() {
        const t = shapes[mode].win
        const grows = t.width * t.height > curWin.width * curWin.height
        if (t.width === curWin.width && t.height === curWin.height) return
        if (grows) {
            shrinkTimer.stop()
            const needsWait = t.height > root.height + 1
            curWin = t
            island.setWindowSize(t.width, t.height)
            if (needsWait && !dragging) {
                awaitResize = true
                interactiveBottom = surface.notchBottom   // hold the shape where it is
                resizeRelease.restart()
            }
        } else {
            shrinkTimer.restart()
        }
    }
    // The window caught up (or gave up waiting): let the shape animate inside the
    // now-fullscreen surface.
    onHeightChanged: {
        syncLayout()
        if (awaitResize && height >= curWin.height - 1) {
            awaitResize = false
            resizeRelease.stop()
            interactiveBottom = -1
        }
    }
    Timer {
        id: resizeRelease
        interval: 250
        onTriggered: { root.awaitResize = false; root.interactiveBottom = -1 }
    }
    Timer {
        id: shrinkTimer
        // Long enough for the closing spring (from the expanded height) to settle; a shorter
        // window would clip the glass mid-animation.
        interval: 850
        onTriggered: {
            root.curWin = root.shapes[root.mode].win
            island.setWindowSize(curWin.width, curWin.height)
        }
    }

    // Frost first, then hide the app, then fold: by the time the glass moves, the seat is
    // solid glass with nothing behind it.
    function coverMedia(then) {
        mediaPending = then
        if (mediaCovering) return
        mediaCovering = true
        coverTimer.restart()
    }
    function seatMedia() {
        mediaCovered = false
        mediaReady = false
        mediaSeated = mediaSettled
        island.showMediaWindow((screenW - mediaAppW) / 2, mediaBezel, mediaAppW, mediaAppH)
    }
    Timer {
        id: coverTimer
        interval: 150   // the frost's 140 ms rise
        onTriggered: {
            island.hideMediaWindow()
            root.mediaCovered = true
            root.mediaReady = false
            root.mediaCovering = false
            const next = root.mediaPending
            root.mediaPending = ""
            if (next !== "") root.setMode(next)
        }
    }
    Connections {
        target: island
        function onMediaWindowReady() { if (root.mode === "media" && !root.mediaCovered) root.mediaReady = true }
        // Nothing to seat: the app isn't running, or sits hidden in the tray. Launching it
        // starts it - or, as a second instance, makes it map its window, which the script
        // then seats and reports ready.
        function onMediaWindowMissing() { if (root.mode === "media") media.launch() }
        function onMediaFocusLost() { if (root.mode === "media" && !root.dragging) root.setMode("bar") }
    }

    // ---- state changes ---------------------------------------------------------------
    function setMode(next) {
        if (next === "media" && !mediaOn) return
        if (next === "toggle") next = (root.big || mode === "media") ? "bar" : "large"
        if (mediaCovering) {
            // Already frosting over to leave: a second request only changes the destination.
            if (next === "media") { coverTimer.stop(); mediaCovering = false; mediaPending = "" }
            else mediaPending = next
            return
        }
        if (next === mode) return
        const wasMedia = mode === "media"
        const wasBig = root.big
        // The app window exists only inside the media panel - never as a floating window.
        if (wasMedia && next !== "media" && !mediaCovered) {
            coverMedia(next)
            return
        }
        mode = next
        island.setKeyboard(root.big && mode !== "activity")
        leaveTimer.stop()
        if (next !== "hidden") now = new Date()
        // Fully (or mostly) closed: reset the panel so the next open starts fresh.
        if (next === "bar" || next === "hidden") largeContent.resetUi()
        if (next === "media") seatMedia()
        applyWindow()
    }
    Connections {
        target: island
        function onPanelRequested(id) { root.openPanel(id) }
        function onStateRequested(state) {
            if (state === "close") { if (root.mode !== "hidden") root.setMode("bar"); return }
            if (state === "small") state = "bar"
            if (state === "bar" && root.big) return
            root.setMode(state)
        }
    }

    // ---- the pull curtain -------------------------------------------------------------
    function stopHeights() {
        // On very short screens the expanded stop can be squeezed below the large one; keep
        // the ladder monotonic so nearest-stop maths stays sane.
        const top = Math.max(shapes.large.nb, Math.min(shapes.expanded.nb, screenH - 80))
        return [shapes.bar.nb, shapes.large.nb, top]
    }
    function clampH(h) {
        const s = stopHeights()
        return Math.max(s[0], Math.min(s[2], h))
    }
    // Rubber band past the end stops: the pointer may pull the curtain beyond the top
    // (or below the tab) against resistance, so releasing there still has somewhere to
    // spring back FROM - a hard clamp would land dead, with no bounce at all.
    function rubberH(raw) {
        const s = stopHeights()
        if (raw > s[2]) return s[2] + (raw - s[2]) * 0.28
        if (raw < s[0]) return s[0] + (raw - s[0]) * 0.28
        return raw
    }
    function pullBegin() {
        dragging = true
        leaveTimer.stop()
        shrinkTimer.stop()
        kickTimer.stop()
        pullFrom = surface.notchBottom
        pullDy = 0
        pullVy = 0
        // The window must cover the screen before the shape can grow past its current edge.
        curWin = Qt.size(screenW, screenH)
        island.setWindowSize(screenW, screenH)
    }
    function pullMove(dy, vy) {
        pullDy = dy
        pullVy = vy
        const s = stopHeights()
        // Decisions (pullEnd) use the logical height; only the visuals rubber-band.
        const logical = clampH(pullFrom + dy)
        interactiveBottom = rubberH(pullFrom + dy)
        const t = Math.max(0, Math.min(1, (logical - s[0]) / Math.max(1, s[1] - s[0])))
        interactiveW = shapes.bar.nw + (480 - shapes.bar.nw) * t
        interactiveR = 15 + 15 * t
    }
    function pullEnd() {
        const dy = pullDy
        const vy = pullVy
        const s = stopHeights()
        const h = clampH(pullFrom + dy)
        // Where the gesture started and where the pointer let go.
        let startIdx = 0
        for (let i = 1; i < 3; ++i)
            if (Math.abs(pullFrom - s[i]) < Math.abs(pullFrom - s[startIdx])) startIdx = i
        let nearest = 0
        for (let i = 1; i < 3; ++i)
            if (Math.abs(h - s[i]) < Math.abs(h - s[nearest])) nearest = i
        const dir = h > pullFrom ? 1 : h < pullFrom ? -1 : 0
        let idx = nearest
        // Completion: released before reaching the next stop, but 30% of the way there -
        // finish the job. A stop actually reached (nearest) is never overridden.
        if (dir !== 0 && idx === startIdx) {
            const to = Math.max(0, Math.min(2, startIdx + dir))
            if (to !== startIdx) {
                const covered = (h - s[startIdx]) * dir
                const seg = (s[to] - s[startIdx]) * dir
                if (seg > 0 && covered / seg >= 0.3) idx = to
            }
        }
        // A flick advances exactly one stop beyond where the drag got to - never a
        // two-stop jump, which reads as the curtain running away from the pointer.
        if (vy > 300) idx = Math.min(idx + 1, 2)
        else if (vy < -300) idx = Math.max(idx - 1, 0)
        const target = s[idx]
        setMode(["bar", "large", "expanded"][idx])
        // A cancelled pull can land on the mode it started from (setMode then no-ops), and
        // the window must still shrink back from the fullscreen size the pull needed.
        applyWindow()
        dragging = false
        // Momentum kick: releasing close to the stop leaves the spring almost no distance,
        // so the settle would land dead. Carry the motion past the stop on purpose (scaled
        // with the release velocity), then let the spring wobble it back - the jelly.
        const heading = target !== surface.notchBottom ? Math.sign(target - surface.notchBottom)
                                                       : (vy > 0 ? 1 : -1)
        const bounce = Math.max(26, Math.min(85, 26 + Math.abs(vy) * 0.06))
        interactiveBottom = Math.max(8, target + heading * bounce)
        interactiveW = -1
        interactiveR = -1
        kickTimer.restart()
    }
    // Ends the deliberate overshoot: back to the binding, where the spring takes over and
    // wobbles the glass into its stop.
    Timer { id: kickTimer; interval: 240; onTriggered: root.interactiveBottom = -1 }

    // ---- the media panel's own pull ----------------------------------------------------
    // The handle at the panel's bottom edge folds the app back into the regular (large)
    // island: the frost covers the app with the first move (the glass holds still until
    // it has), then tracks the pointer between the media and large stops and snaps on
    // release, velocity permitting.
    function mediaPullBegin() {
        pullBegin()
        if (!mediaCovered) coverMedia("")
    }
    function mediaPullMove(dy, vy) {
        pullDy = dy
        pullVy = vy
        if (!mediaCovered) { interactiveBottom = shapes.media.nb; interactiveW = shapes.media.nw; interactiveR = 30; return }
        const h = Math.max(shapes.large.nb, Math.min(shapes.media.nb, pullFrom + dy))
        interactiveBottom = h
        const t = Math.max(0, Math.min(1, (h - shapes.large.nb) / Math.max(1, shapes.media.nb - shapes.large.nb)))
        interactiveW = shapes.large.nw + (shapes.media.nw - shapes.large.nw) * t
        interactiveR = 30
    }
    function mediaPullEnd() {
        const up = pullDy < -50 || pullVy < -300
        if (up) {
            setMode("large")
        } else if (mediaCovering) {
            // Let go before the frost finished covering: nothing was hidden yet, keep it.
            coverTimer.stop()
            mediaCovering = false
            mediaPending = ""
        } else if (mediaCovered) {
            // Settled back into media mode: seat the app window in the panel again.
            seatMedia()
            applyWindow()
        }
        dragging = false
        interactiveBottom = -1
        interactiveW = -1
        interactiveR = -1
    }

    // Safety net: if a drag ever ends without its pullEnd running (grab lost, handler
    // canceled), the override would stick the island at a mid-curtain height forever.
    // Any end of dragging snaps the shape back to the current mode's stop - except while
    // the deliberate momentum kick (pullEnd's overshoot) is still in flight.
    onDraggingChanged: {
        if (!dragging && !kickTimer.running && !awaitResize && (interactiveBottom >= 0 || interactiveW >= 0)) {
            interactiveBottom = -1
            interactiveW = -1
            interactiveR = -1
            applyWindow()
        }
    }

    // ---- pointer ----------------------------------------------------------------------
    // windowHover covers the whole (masked) window; while big the window is the full
    // screen, so the auto-close keys off actually leaving the notch instead. A drag in
    // progress suspends all of it - the curtain must not be closed from under the pointer.
    HoverHandler { id: windowHover }
    readonly property bool pointerIn: windowHover.hovered
    onPointerInChanged: {
        if (dragging) return
        if (pointerIn) {
            leaveTimer.stop()
            if (mode === "hidden") peekTimer.restart()
        } else {
            peekTimer.stop()
            if (mode === "bar") leaveTimer.restart()
        }
    }
    // Reveal needs a deliberate touch (240 ms): a fast swipe across the top edge on the
    // way elsewhere must not flash the tab open and closed again.
    Timer { id: peekTimer; interval: 240; onTriggered: if (root.pointerIn) root.setMode("bar") }
    Timer {
        id: leaveTimer
        // The revealed tab lingers 1.5 s after the pointer leaves its mask: travelling
        // from the top edge down to the tab briefly exits the input area, and a short
        // timeout made the tab collapse and re-open - the flicker.
        interval: root.big ? 2000 : 1500
        onTriggered: {
            if (root.mode === "media") {
                // never closes by itself: the user is working inside the app
            } else if (root.mode === "panel" || root.mode === "activity") {
                // never closes by itself: someone may be typing a password
            } else if (root.big) {
                root.setMode("bar")
            } else if (!root.pointerIn) {
                root.setMode("hidden")
            }
        }
    }

    focus: true
    Keys.onEscapePressed: root.mode === "activity" ? root.dismissActivity()
                          : root.mode === "panel" ? root.panelBack()
                          : root.setMode(root.mode === "expanded" ? "large" : root.mode === "large" ? "bar" : "hidden")

    // Click outside the island (only reachable while the window covers the screen).
    // Suspended while the media handle is pressed: the handle's own tap must be the
    // only verdict of that click, not followed by this area's fold to the tab.
    MouseArea {
        anchors.fill: parent
        enabled: (root.big || root.mode === "media") && !root.dragging && !mediaHandleTap.pressed
        onClicked: root.setMode("bar")
    }

    // ---- the shape ----------------------------------------------------------------------
    NotchSurface {
        id: surface
        x: 0; y: 0
        winW: root.width
        stripW: root.shape.sw
        stripH: root.shape.sh
        // Width and corners derive from the SAME animated height (openT) in the curtain
        // modes: one oscillator moves the whole silhouette coherently. A separate width
        // spring would oscillate out of phase with the height and the glass would shear
        // horizontally mid-animation. Media mode keeps its own geometry.
        notchW: root.interactiveW >= 0 ? root.interactiveW
               : root.mode === "media" || root.mode === "activity" ? root.shape.nw
               : root.shapes.bar.nw + (480 - root.shapes.bar.nw) * root.openT
        notchBottom: root.interactiveBottom >= 0 ? root.interactiveBottom : root.shape.nb
        cornerR: root.interactiveR >= 0 ? root.interactiveR
                : root.mode === "media" || root.mode === "activity" ? root.shape.r
                : 15 + 15 * root.openT
        shoulder: root.shoulder
        holeX: (root.width - root.mediaAppW) / 2
        holeY: root.mediaBezel
        // The seat exists as long as the app window may be behind it; frost fills it while
        // the app loads or is being covered, so the glass never shrinks with a hole in it.
        holeW: root.mode === "media" && !root.mediaCovered ? root.mediaAppW : 0
        holeH: root.mode === "media" && !root.mediaCovered ? root.mediaAppH : 0
        holeFrost: root.frost
        opacity: root.mode === "hidden" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on stripW { SpringAnimation { spring: 3.0; damping: 0.34; epsilon: 0.5 } }
        Behavior on stripH { SpringAnimation { spring: 3.4; damping: 0.30; epsilon: 0.3 } }
        // The automatic completion is a liquid ball: it travels fast, overshoots ~17%,
        // then wobbles back into place (~750 ms total, on open and on close alike).
        // Values calibrated by measuring the height curve frame-by-frame: damping ~0.45
        // kills the bounce entirely, ~0.9 crawls; epsilon 3 px ends the tail invisibly.
        // (While dragging, the shape follows the pointer directly.)
        Behavior on notchBottom {
            enabled: !root.dragging
            // A long descent with the full-jelly damping undershoots by ~17% of the
            // travel - from the large island that dives off-screen and reads as a
            // flicker. Damp harder while far above the target; the last stretch keeps
            // the wobble.
            SpringAnimation { id: bottomSpring; spring: 3.6; damping: shapes[mode].nb < surface.notchBottom - 200 ? 0.36 : 0.22; epsilon: 3.0 }
        }
        // Only the media panel springs its own width/corners; in the curtain modes they
        // ride on the height (see the bindings above) and must not animate separately.
        Behavior on notchW { enabled: (root.mediaWidth || root.activityWidth) && !root.dragging; SpringAnimation { id: widthSpring; spring: 3.6; damping: 0.22; epsilon: 3.0 } }
        Behavior on cornerR { enabled: (root.mediaWidth || root.activityWidth) && !root.dragging; SpringAnimation { spring: 3.6; damping: 0.22; epsilon: 3.0 } }
        onSegmentsChanged: root.syncLayout()
        onOpacityChanged: root.syncLayout()
    }

    // The notch's own area: the tab in bar mode, the island when big. Dragging the tab
    // itself pulls the curtain open.
    Item {
        id: notchArea
        readonly property alias hovered: notchHover.hovered
        x: (root.width - surface.notchW) / 2
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        HoverHandler { id: notchHover }
        // Leaving the notch while the island is open starts the close countdown.
        // Entering it again cancels; opening with the pointer elsewhere leaves it alone.
        onHoveredChanged: {
            if (root.big && !root.dragging)
                hovered ? leaveTimer.stop() : leaveTimer.restart()
        }
        // Clicking the tab (outside its buttons) opens the large island; in media mode
        // the same gesture is the way back to the regular bar.
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: (point) => {
                // A tap on one of the tab's own buttons (search, language, power) is theirs.
                const p = tabRow.mapFromItem(notchArea, point.position)
                if (tabRow.visible && tabRow.childAt(p.x, p.y)) return
                if (root.mode === "bar") root.setMode("large")
                // The bezel folds the media view; the seat itself (frosted while the app
                // loads) is not a close target.
                else if (root.mode === "media" && !(surface.hasHole
                         && point.position.x + notchArea.x >= surface.holeX && point.position.x + notchArea.x <= surface.holeX + surface.holeW
                         && point.position.y >= surface.holeY && point.position.y <= surface.holeY + surface.holeH))
                    root.setMode("bar")
            }
        }
        DragHandler {
            enabled: root.mode === "bar"
            target: null
            onActiveChanged: {
                if (active) root.pullBegin()
                else root.pullEnd()
            }
            onTranslationChanged: if (active) root.pullMove(translation.y, centroid.velocity.y)
        }
        // The tab row: search, clock (a running timer takes its place, a finished one
        // pulses), power. Hidden entirely in media mode - the app owns the panel.
        Row {
            id: tabRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 - 3
            spacing: 12
            opacity: (root.mode === "media" || root.mode === "activity" ? 0 : Math.max(0, Math.min(1, (0.4 - root.openT) / 0.3))) * surface.opacity
            visible: opacity > 0
            NotchButton {
                glyph: "search"
                onTapped: island.openSearch()
            }
            Text {
                text: timerState.done ? I18n.tr("Time's up") : (timerState.active ? timerState.text : Qt.formatTime(root.now, "H:mm"))
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.mono; pixelSize: Tokens.type.body; weight: Font.Medium }
                color: timerState.done || timerState.active ? Theme.accent : Theme.text
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.openPanel("calendar") }
                SequentialAnimation on scale {
                    running: timerState.done
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.1; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
                    NumberAnimation { to: 1.0; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
                }
            }
            // Language: shows the current one, a tap moves to the next
            Item {
                width: 30; height: 30
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    color: Qt.rgba(1, 1, 1, langTap.pressed ? Tokens.tint.strong : langHover.hovered ? Tokens.tint.soft : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
                Text {
                    anchors.centerIn: parent
                    text: I18n.languages.find(l => l.code === I18n.lang).short
                    font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.DemiBold }
                    color: Theme.text
                }
                HoverHandler { id: langHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: langTap; onTapped: tiles.language = I18n.next() }
            }
            NotchButton { glyph: "power"; onTapped: root.openPanel("power") }
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                if (e.angleDelta.y < 0) {
                    if (root.mode === "bar") root.setMode("large")
                    else if (root.mode === "large") root.setMode("expanded")
                } else {
                    if (root.mode === "media") root.setMode("large")
                    else if (root.mode === "large") root.setMode("bar")
                    else if (root.mode === "expanded" && largeContent.notifAtTop) root.setMode("large")
                }
            }
        }
    }

    // The pull handle. One pill for every state of the bar: a faint hint on the top edge while the
    // bar is hidden, then the same line slides down with the tab's bottom edge and grows into the
    // handle; it fades out as the curtain opens (the large island's own handle takes over).
    Rectangle {
        id: edgeHint
        readonly property bool resting: root.mode === "hidden"
        x: (root.width - width) / 2
        y: resting ? 6 : Math.max(6, surface.notchBottom - 12)    // 6 = inset from the edge; input stays on the 2 px strip
        width: resting ? 22 : 32
        height: resting ? 2 : 4
        radius: height / 2
        color: resting ? "white" : Theme.subtext
        opacity: resting ? 0.22 : 0.7 * (root.mode === "media" || root.mode === "activity" ? 0 : Math.max(0, Math.min(1, (0.4 - root.openT) / 0.3))) * surface.opacity
        visible: opacity > 0
        Behavior on width { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on height { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.base } }
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    }

    // Scrolling down anywhere over the tab also opens the large island.
    WheelHandler {
        enabled: root.mode === "bar"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => { if (e.angleDelta.y < 0) root.setMode("large") }
    }

    // ---- large content ----------------------------------------------------------------
    // 0 -> 1 while a panel is open: the large content slides 32 px left and fades out
    // (shared-axis X); the panel arrives from the right.
    property real panelSlide: mode === "panel" ? 1 : 0
    Behavior on panelSlide { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.exit } }

    LargeIsland {
        id: largeContent
        x: (root.width - surface.notchW) / 2 - 32 * root.panelSlide
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        timer: timerState
        now: root.now
        appName: root.appName
        // Folding from the media panel straight to the tab passes through the large
        // island's height: its content must not flash up on the way.
        opacity: (root.mode === "activity" || (root.mediaWidth && !root.big) ? 0 : Math.max(0, Math.min(1, (root.openT - 0.2) / 0.5))) * surface.opacity * (1 - root.panelSlide)
        // Stay mounted while the curtain moves: the handle must keep its grab even after
        // its visuals fade out (the island passing below the fade band while dragged shut).
        // Hidden entirely in media mode - the app window owns the panel's middle.
        visible: (opacity > 0 || root.dragging) && root.mode !== "media"
        onCloseRequested: root.setMode("bar")
        onMediaRequested: root.setMode("media")
        onPanelRequested: (id) => root.openPanel(id)
        onPullStarted: root.pullBegin()
        onPullMoved: (dy, vy) => root.pullMove(dy, vy)
        onPullEnded: root.pullEnd()
        onHoldDetected: root.setMode("expanded")
    }

    ActivityHost {
        id: activityHost
        x: (root.width - surface.notchW) / 2
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        a: root.activity
        opacity: root.mode === "activity" ? Math.max(0, Math.min(1, (surface.notchBottom - 50) / 50)) * surface.opacity : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        onActivated: (what) => root.activityAction(what)
    }

    PanelHost {
        id: panelHost
        x: (root.width - surface.notchW) / 2
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        maxHeight: root.screenH - 120
        opacity: root.mode === "panel" ? Math.max(0, Math.min(1, (root.openT - 0.5) / 0.4)) * surface.opacity : 0
        visible: opacity > 0 || root.dragging && root.mode === "panel"
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        open: root.mode === "panel"
        onBackRequested: root.panelBack()
        onCloseRequested: root.setMode("bar")
        onPullStarted: root.pullBegin()
        onPullMoved: (dy, vy) => root.pullMove(dy, vy)
        onPullEnded: root.pullEnd()
    }

    // The frosted seat while the app is on its way (cold start, or the window mapping):
    // its icon breathes in the middle until the window reports ready.
    Image {
        id: mediaLoading
        readonly property bool waiting: root.mode === "media" && !root.mediaReady && !root.mediaCovering
        source: media.playerIcon !== "" ? "file://" + media.playerIcon : ""
        visible: source !== "" && opacity > 0
        width: 56; height: 56
        sourceSize: Qt.size(112, 112)
        x: surface.holeX + (root.mediaAppW - width) / 2
        y: surface.holeY + (root.mediaAppH - height) / 2
        opacity: waiting && root.mediaSeated ? 0.55 * root.frost : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }
        SequentialAnimation on scale {
            running: mediaLoading.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1.06; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
            NumberAnimation { to: 1.0; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
        }
    }

    // Media panel handle: pull up (or click) to fold the app back into the regular island.
    Item {
        id: mediaHandle
        visible: root.mode === "media"
        anchors.horizontalCenter: parent.horizontalCenter
        y: surface.notchBottom - 22
        width: 72; height: 24
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Rectangle {
            anchors.centerIn: parent
            width: 44; height: 5; radius: Tokens.radius.xs
            color: mediaHandleTap.pressed || mediaHandleDrag.active ? Theme.text : Theme.subtext
            opacity: 0.8
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        }
        TapHandler { id: mediaHandleTap; onTapped: root.setMode("large") }
        DragHandler {
            id: mediaHandleDrag
            target: null
            onActiveChanged: if (active) root.mediaPullBegin(); else root.mediaPullEnd()
            onTranslationChanged: if (active) root.mediaPullMove(translation.y, centroid.velocity.y)
        }
    }

    // ---- keep KWin's blur + the input region glued to the animated shape ---------------
    // Event-driven: the surface, the mode and the window size push updates themselves -
    // no polling timer, so an idle island costs nothing.
    property string lastKey: ""
    function syncLayout() {
        const key = [surface.sw, surface.stripH, surface.notchW, surface.notchBottom, surface.rb, surface.hasHole, root.mediaClear, surface.opacity > 0.05, root.mode, root.width]
                    .map(function (v) { return typeof v === "number" ? Math.round(v) : v }).join("|")
        if (key === lastKey) return
        lastKey = key
        const visible = surface.opacity > 0.05
        // Tell the world where the glass ends right now - aether-toasts asks on every
        // notification so its cards drop just below the island (or not at all while the
        // double bar is showing them in its history list).
        island.setUiState(root.mode, Math.round(surface.notchBottom))
        // The 2px top strip stays live in every mode so resting the pointer on the top
        // edge keeps the tab around instead of oscillating between hidden and bar.
        // Media mode takes input over the whole window too (minus the hole): a click
        // anywhere outside the panel must reach the island's close area, not fall
        // through to the desktop. The seat is cut out of blur and input only once it is
        // clear: frosted, it is glass like the rest and takes the pointer itself.
        island.setLayout(visible ? surface.segments : [], root.big || root.mode === "media",
                         Qt.rect(0, 0, root.width, 2),
                         surface.hasHole && root.mediaClear ? Qt.rect(surface.holeX, surface.holeY, surface.holeW, surface.holeH) : Qt.rect(0, 0, 0, 0))
    }
    onMediaClearChanged: syncLayout()
    onModeChanged: {
        syncLayout()
        if (mode === "media") mediaWidth = true
        else mediaExitTimer.restart()
        if (mode === "activity") activityWidth = true
        else activityExitTimer.restart()
    }
    Timer { id: activityExitTimer; interval: 800; onTriggered: root.activityWidth = false }
    Timer { id: mediaExitTimer; interval: 800; onTriggered: root.mediaWidth = false }
    onWidthChanged: syncLayout()
}
