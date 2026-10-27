import QtQuick
import QtQuick.Controls
import AetherShared
import "."

// The notification section of the expanded island: header row + scrollable history.
// Height is assigned by LargeIsland (whatever is left between the controls and the handle).
// The store's QVariantList is mirrored into a ListModel key-by-key so a new notification
// slides in on its own - replacing the whole model would re-animate every card and jump
// the scroll position.
Item {
    id: root
    property date now: new Date()
    readonly property alias atTop: list.atTop

    ListModel { id: cards }

    function syncFromStore() {
        const fresh = notifStore.list
        for (let i = cards.count - 1; i >= 0; --i) {
            const k = cards.get(i).key
            if (!fresh.some(function (n) { return n.key === k })) cards.remove(i)
        }
        for (let i = 0; i < fresh.length; ++i) {
            if (i < cards.count && cards.get(i).key === fresh[i].key) continue
            cards.insert(i, fresh[i])
        }
    }
    Component.onCompleted: syncFromStore()
    Connections {
        target: notifStore
        function onListChanged() { root.syncFromStore() }
    }
    // Called by LargeIsland when the island closes: the next open starts at the newest
    // notification, not wherever the list was left scrolled.
    function resetScroll() {
        list.cancelFlick()
        list.contentY = 0
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 30

        Text {
            anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
            text: I18n.tr("NOTIFICATIONS")
            font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
            color: Theme.subtext
        }
        Rectangle {                          // Clear
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: clearLabel.implicitWidth + 22; height: 26; radius: Tokens.radius.md
            color: Theme.chip
            Text {
                id: clearLabel
                anchors.centerIn: parent
                text: I18n.tr("Clear")
                font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
                color: clearHover.hovered ? Theme.accent : Theme.subtext
                Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
            }
            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: notifStore.clearAll() }
        }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: header.bottom; topMargin: 8; bottom: parent.bottom }
        property bool atTop: contentY <= 1
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: cards
        displaced: Transition { SpringAnimation { properties: "y"; spring: 3.0; damping: 0.35; epsilon: 0.3 } }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
        }
        delegate: NotificationCard {
            width: ListView.view.width
            app: model.app
            icon: model.icon
            summary: model.summary
            body: model.body
            urgency: model.urgency
            ts: model.ts
            now: root.now
            onDismissed: notifStore.dismiss(model.key)
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: 3
            contentItem: Rectangle { radius: Tokens.radius.hair; color: Theme.rim }
        }
        // Empty state
        Column {
            anchors { top: parent.top; topMargin: 14; horizontalCenter: parent.horizontalCenter }
            visible: list.count === 0
            spacing: 8
            Glyph { name: "bell"; size: 22; color: Theme.subtext; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("No notifications")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
        }
    }
}
