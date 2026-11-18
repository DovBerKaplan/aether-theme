import QtQuick
import AetherShared

// Frame shared by every panel: pinned header (back, title, subtitle, trailing slot), a
// scrolling body and an optional pinned footer. `contentHeight` is what the island sizes its
// glass to; the body scrolls when the screen cannot fit it.
Item {
    id: root
    property string title
    property string subtitle
    property bool showBack: true
    property real maxHeight: 10000
    property bool busy: false
    default property alias body: bodyColumn.data
    property alias headerTrailing: trailingRow.data
    property alias footer: footerSlot.data
    property real footerHeight: 0
    property real bottomInset: 34          // room under the footer (the island's grab line); a window that owns its edge sets less
    signal backRequested()

    readonly property real headerHeight: subtitle.length > 0 ? 64 : 56
    readonly property real contentHeight: Math.min(maxHeight,
        headerHeight + bodyColumn.implicitHeight + Tokens.space.md + footerHeight + bottomInset)
    readonly property bool scrolled: flick.contentY > 0

    Item {
        id: header
        width: parent.width; height: root.headerHeight
        BackButton {
            id: back
            visible: root.showBack
            anchors.left: parent.left; anchors.leftMargin: Tokens.space.sm
            anchors.verticalCenter: parent.verticalCenter
            onActivated: root.backRequested()
        }
        Column {
            anchors {
                left: root.showBack ? back.right : parent.left; leftMargin: Tokens.space.sm
                right: trailingRow.left; rightMargin: Tokens.space.md
                verticalCenter: parent.verticalCenter
            }
            Text {
                width: parent.width; text: root.title; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.DemiBold }
                color: Theme.text
            }
            Text {
                visible: root.subtitle.length > 0
                width: parent.width; text: root.subtitle; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
        }
        Row {
            id: trailingRow
            anchors { right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            spacing: Tokens.space.sm
        }
    }
    LinearProgress {
        anchors { left: parent.left; right: parent.right; top: header.bottom }
        running: root.busy
    }
    Rectangle {          // hairline, only once the body has scrolled under the header
        anchors { left: parent.left; right: parent.right; top: header.bottom }
        height: 1; color: Theme.rim
        opacity: root.scrolled ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
    }
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footerSlot.top }
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight + Tokens.space.md
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: bodyColumn
            width: parent.width
        }
    }
    Item {
        id: footerSlot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: root.bottomInset }
        height: root.footerHeight
    }
}
