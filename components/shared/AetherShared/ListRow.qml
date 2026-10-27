import QtQuick
import QtQuick.Effects
import AetherShared

// One row of a panel list: optional glyph, title/subtitle, free trailing slot, optional chevron.
// Clicks on trailing items (a Switch, a button) never reach the row.
Item {
    id: root
    property string title
    property string subtitle
    property url leadingGlyphSource
    property bool showChevron: false
    property bool highlighted: false
    default property alias trailing: trailingRow.data
    signal clicked()

    implicitWidth: 360
    implicitHeight: subtitle.length > 0 ? 64 : 56
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.4
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.md
        color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.material.tintAttention
                              : root.highlighted ? Tokens.material.tintAttention
                              : hover.hovered ? Tokens.material.tintHover : 0)
        border { width: root.activeFocus ? 2 : 0; color: Theme.accent }
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
    }
    Item {
        id: lead
        visible: root.leadingGlyphSource.toString().length > 0
        anchors.left: parent.left; anchors.leftMargin: Tokens.space.md; width: visible ? 36 : 0; height: 36
        anchors.verticalCenter: parent.verticalCenter
        Rectangle { anchors.fill: parent; radius: 18; color: Theme.chip }
        Image {
            id: img
            anchors.centerIn: parent; width: 20; height: 20
            source: root.leadingGlyphSource
            sourceSize: Qt.size(60, 60)
            visible: false
        }
        MultiEffect { anchors.fill: img; source: img; colorization: 1.0; colorizationColor: Theme.text }
    }
    Column {
        anchors {
            left: lead.right; leftMargin: lead.visible ? Tokens.space.md : Tokens.space.md
            right: trailingRow.left; rightMargin: Tokens.space.sm
            verticalCenter: parent.verticalCenter
        }
        Text {
            width: parent.width; text: root.title; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
            color: Theme.text
        }
        Text {
            visible: root.subtitle.length > 0
            width: parent.width; text: root.subtitle; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
    }
    Row {
        id: trailingRow
        anchors { right: root.showChevron ? chevron.left : parent.right; rightMargin: root.showChevron ? Tokens.space.xs : Tokens.space.md; verticalCenter: parent.verticalCenter }
        spacing: Tokens.space.sm
    }
    Text {
        id: chevron
        visible: root.showChevron
        anchors { right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
        text: I18n.rtl ? "‹" : "›"
        font { family: Theme.font; pixelSize: Tokens.type.title }
        color: Theme.subtext
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    // Only the area left of the trailing slot is the row's own tap target.
    Item {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: trailingRow.width > 0 ? trailingRow.x : parent.width
        TapHandler { id: tap; onTapped: root.clicked() }
    }
}
