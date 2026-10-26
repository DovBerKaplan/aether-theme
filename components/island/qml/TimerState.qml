import QtQuick

// A single countdown timer shared by the large island (controls) and the notch (display).
Item {
    id: root
    visible: false
    property int total: 0
    property int remaining: 0
    property bool running: false
    property bool done: false            // true for a few seconds after reaching zero
    readonly property bool active: running || remaining > 0
    readonly property real progress: total > 0 ? remaining / total : 0
    readonly property string text: {
        const m = Math.floor(remaining / 60), s = remaining % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function start(seconds) { total = seconds; remaining = seconds; running = true; done = false }
    function toggle() { if (remaining > 0) running = !running }
    function cancel() { running = false; remaining = 0; total = 0; done = false }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            root.remaining -= 1
            if (root.remaining <= 0) {
                root.remaining = 0
                root.running = false
                root.done = true
                doneReset.restart()
            }
        }
    }
    Timer { id: doneReset; interval: 6000; onTriggered: { root.done = false; root.total = 0 } }
}
