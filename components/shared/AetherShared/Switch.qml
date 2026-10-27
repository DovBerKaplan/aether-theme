import QtQuick
import AetherShared

// M3-style switch: accent track with a dark thumb when on, graphite track with a rim when off.
Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 44
    implicitHeight: 24
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.4

    function flip() { checked = !checked; toggled(checked) }
    Keys.onSpacePressed: flip()
    Keys.onReturnPressed: flip()

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.chip
        border { width: root.checked ? 0 : 1; color: Theme.rim }
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    Rectangle {            // hover halo behind the thumb
        width: 32; height: 32; radius: 16
        x: thumb.x + thumb.width / 2 - 16
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, Tokens.material.tintHover)
        visible: hover.hovered
    }
    Rectangle {
        id: thumb
        readonly property real d: tap.pressed ? 24 : root.checked ? 20 : 16
        width: d; height: d; radius: d / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (root.checked !== I18n.rtl ? root.width - 14 : 12) - d / 2
        color: root.checked ? Tokens.role.dark.textOnAccent : Theme.subtext
        Behavior on x { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
        Behavior on width { NumberAnimation { duration: Tokens.motion.duration.micro } }
        Behavior on height { NumberAnimation { duration: Tokens.motion.duration.micro } }
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: -3
        radius: height / 2; color: "transparent"
        border { width: 2; color: Theme.accent }
        visible: root.activeFocus
    }
    HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.flip() }
}
