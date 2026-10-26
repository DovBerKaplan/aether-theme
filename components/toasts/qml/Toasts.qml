import QtQuick
import "."

// Notification cards: they drop from the top edge, stack up to three, and slide back up.
// The window is only as tall as the stack; blur and input cover just the cards.
Item {
    id: root
    readonly property int cardW: 380
    readonly property int step: 86
    readonly property int topGap: 10
    property int nextUid: 1

    Binding { target: Theme; property: "bodyAlpha"; value: toasts.bodyAlpha }
    ListModel { id: cards }

    Connections {
        target: notifications
        function onReceived(app, icon, summary, body, urgency, timeoutMs) {
            while (cards.count >= 3) {                       // oldest goes first
                const old = repeater.itemAt(0)
                if (old) old.close()
                cards.remove(0)
            }
            cards.append({ uid: root.nextUid++, app: app, icon: icon, summary: summary, body: body, urgency: urgency })
            root.resize()
        }
    }

    // Grow the window right away, shrink it once the cards have slid out.
    property int curHeight: 4
    function targetHeight() { return cards.count > 0 ? topGap + cards.count * step + 8 : 4 }
    function resize() {
        const h = targetHeight()
        if (h > curHeight) { shrink.stop(); curHeight = h; toasts.setWindowHeight(h) } else shrink.restart()
    }
    Timer { id: shrink; interval: 420; onTriggered: { root.curHeight = root.targetHeight(); toasts.setWindowHeight(root.curHeight) } }

    Repeater {
        id: repeater
        model: cards
        delegate: ToastCard {
            app: model.app
            icon: model.icon
            summary: model.summary
            body: model.body
            urgency: model.urgency
            x: (root.width - width) / 2
            slotY: root.topGap + index * root.step
            onDismissed: {
                for (let i = 0; i < cards.count; i++) {
                    if (cards.get(i).uid === model.uid) { cards.remove(i); break }
                }
                root.resize()
            }
        }
    }

    property string lastKey: ""
    function sync() {
        const cards = []
        for (let i = 0; i < cards.count; i++) {
            const it = repeater.itemAt(i)
            if (it && it.opacity > 0.05) cards.push({ x: it.x, y: it.y, w: it.width, h: it.height, r: 24 })
        }
        const key = cards.map(c => [c.x, c.y, c.w, c.h].map(Math.round).join(",")).join(";")
        if (key === lastKey) return
        lastKey = key
        toasts.setCards(cards)
    }
    Timer { interval: 16; repeat: true; running: cards.count > 0; onTriggered: root.sync() }
}
