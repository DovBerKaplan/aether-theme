import QtQuick
import AetherShared
import "."

// The island's panel mode: one page at a time, slid in on the shared X axis.
//   panelId  which panel (wifi, bluetooth, sound, display, battery, calendar, power)
//   page     "" for the list, "detail:<key>" for a deeper level
// Phase 1 ships the frame; each panel replaces its PlaceholderPanel as it is built.
Item {
    id: root
    property string panelId: ""
    property string page: ""
    property real maxHeight: 10000
    readonly property real contentHeight: current.contentHeight
    readonly property bool onList: page === ""
    signal backRequested()
    signal pullStarted()
    signal pullMoved(real dy, real vy)
    signal pullEnded()

    readonly property var titles: ({
        wifi: "Wi‑Fi", bluetooth: "Bluetooth", sound: "Sound", display: "Display",
        battery: "Battery", calendar: "Calendar", power: "Power"
    })

    clip: true
    // Page changes: the old content leaves 32 px one way, the new arrives from the other.
    property int dir: 1
    onPageChanged: { dir = page === "" ? -1 : 1; swap.restart() }
    onPanelIdChanged: { dir = 1; swap.restart() }
    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: current; property: "opacity"; to: 0; duration: Tokens.motion.duration.micro; easing.type: Tokens.motion.easing.exit }
            NumberAnimation { target: current; property: "x"; to: -32 * root.dir; duration: Tokens.motion.duration.micro; easing.type: Tokens.motion.easing.exit }
        }
        ScriptAction { script: { current.x = 32 * root.dir } }
        ParallelAnimation {
            NumberAnimation { target: current; property: "opacity"; to: 1; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
            NumberAnimation { target: current; property: "x"; to: 0; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
        }
    }

    PlaceholderPanel {
        id: current
        width: parent.width; height: parent.height
        panelId: root.panelId
        title: root.titles[root.panelId] || root.panelId
        page: root.page
        maxHeight: root.maxHeight
        onBackRequested: root.backRequested()
    }

    // Handle: tap goes back one level, pulling it drives the island's curtain.
    Item {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
        width: 64; height: 20
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Rectangle {
            anchors.centerIn: parent
            width: 44; height: 5; radius: Tokens.radius.xs
            color: handleTap.pressed || handleDrag.active ? Theme.text : Theme.subtext
            opacity: 0.8
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        }
        TapHandler { id: handleTap; onTapped: root.backRequested() }
        DragHandler {
            id: handleDrag
            target: null
            onActiveChanged: if (active) root.pullStarted(); else root.pullEnded()
            onTranslationChanged: if (active) root.pullMoved(translation.y, centroid.velocity.y)
        }
    }
}
