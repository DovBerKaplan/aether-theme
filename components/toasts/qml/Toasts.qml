import QtQuick
import org.kde.taskmanager as TaskManager
import AetherShared
import "."

// Notification cards: they drop in just below the aether island, stack up to three, and
// slide back up. While the island's double bar is open no card spawns at all - the history
// list inside the island shows it there instead. The window is only as tall as the stack;
// blur and input cover just the cards.
Item {
    id: stack
    readonly property int cardW: 380
    readonly property int step: 86
    // Right under the island's glass, wherever it is now: the stack follows it open and shut.
    readonly property int topGap: Math.max(10, toasts.islandBottom + 10)
    onTopGapChanged: resize()
    property int nextUid: 1

    Binding { target: Theme; property: "dark"; value: toasts.dark }
    Binding { target: Theme; property: "bodyAlpha"; value: toasts.bodyAlpha }
    // The user's colour from the island's colour panel, tinting the glass like the bar's.
    Binding { target: Theme; property: "accentOverride"; value: toasts.accentOverride }
    Binding { target: Theme; property: "accentTint"; value: 0.07 }
    ListModel { id: cards }

    // Clicking a card opens what sent it. A desktop app: its running window comes forward
    // (matched by desktop-entry id, else by app name), and if it is not running it is launched.
    // A phone card has no desktop app - the island's KDE Connect page is its home.
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterHidden: false
        filterMinimized: false
        filterByVirtualDesktop: false
        separateLaunchers: false
    }
    function baseOf(u) { const s = String(u); return s.slice(Math.max(s.lastIndexOf("/"), s.lastIndexOf(":")) + 1) }
    function activateCard(desktop, phone, app) {
        if (phone) { console.log("toast click: phone -> connect panel"); toasts.openConnectPanel(); return }
        const key = String(desktop).toLowerCase()
        const name = String(app).toLowerCase()
        for (let i = 0; i < tasks.count; i++) {
            const idx = tasks.index(i, 0)
            if (!idx.valid) continue
            const base = baseOf(tasks.data(idx, TaskManager.AbstractTasksModel.LauncherUrl)).replace(/\.desktop$/, "").toLowerCase()
            const appName = String(tasks.data(idx, TaskManager.AbstractTasksModel.AppName)).toLowerCase()
            if ((key !== "" && base === key) || (appName !== "" && appName === name)) {
                console.log("toast click: activate", base)
                tasks.requestActivate(idx)
                return
            }
        }
        console.log("toast click: no task for", desktop, "-> launch")
        if (key !== "") toasts.launchDesktop(desktop)
    }

    // The double bar opening takes the notifications into its history: cards on screen fold away.
    Connections {
        target: toasts
        function onIslandChanged() {
            if (toasts.islandMode !== "expanded") return
            for (let i = 0; i < cards.count; i++) {
                const c = repeater.itemAt(i)
                if (c && c.shown) c.close()
            }
        }
    }

    Connections {
        target: notifications
        function onReceived(app, icon, summary, body, urgency, timeoutMs, islandOpen, desktop, phone) {
            if (islandOpen) return                           // the island's list takes it
            while (cards.count >= 3) {                       // oldest goes first
                const old = repeater.itemAt(0)
                if (old) { old.close(); break }               // removes itself via onDismissed
            }
            cards.append({ uid: stack.nextUid++, app: app, icon: icon, summary: summary, body: body, urgency: urgency,
                           desktop: desktop, phone: phone })
            stack.resize()
        }
    }

    // Grow the window right away, shrink it once the cards have slid out.
    property int curHeight: 4
    function targetHeight() { return cards.count > 0 ? topGap + cards.count * step + 8 : 4 }
    function resize() {
        const h = targetHeight()
        if (h > curHeight) { shrink.stop(); curHeight = h; toasts.setWindowHeight(h) } else shrink.restart()
    }
    Timer { id: shrink; interval: 420; onTriggered: { stack.curHeight = stack.targetHeight(); toasts.setWindowHeight(stack.curHeight) } }

    Repeater {
        id: repeater
        model: cards
        delegate: ToastCard {
            // Everything through `parent` (the stack Item) - outer-file ids are unreliable
            // inside delegates under Qt 6.11's stricter scoping (ToastCard.qml has its own
            // `id: root`, which is exactly how this broke before).
            app: model.app
            icon: model.icon
            summary: model.summary
            body: model.body
            urgency: model.urgency
            x: (parent.width - width) / 2
            slotY: parent.topGap + index * parent.step
            onDismissed: {
                for (let i = 0; i < cards.count; i++) {
                    if (cards.get(i).uid === model.uid) { cards.remove(i); break }
                }
                if (parent) parent.resize()
            }
            onActivated: if (parent) parent.activateCard(model.desktop, model.phone, model.app)
        }
    }

    property string lastKey: ""
    function sync() {
        // A local named anything-but-`cards`: shadowing the ListModel id silently skipped
        // this loop, so cards never got their blur/input region and the whole window
        // rectangle ate clicks.
        const rects = []
        for (let i = 0; i < cards.count; i++) {
            const it = repeater.itemAt(i)
            if (it && it.opacity > 0.05) rects.push({ x: it.x, y: it.y, w: it.width, h: it.height, r: 24 })
        }
        const key = rects.map(c => [c.x, c.y, c.w, c.h].map(Math.round).join(",")).join(";")
        if (key === lastKey) return
        lastKey = key
        toasts.setCards(rects)
    }
    Timer { interval: 16; repeat: true; running: cards.count > 0; onTriggered: stack.sync() }
}
