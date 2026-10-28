import QtQuick
import AetherShared
import QtQuick.Effects

// Now-playing card: framed artwork over an ambient colour wash, track info with a
// live equalizer, ghost skip buttons around a hero play button, and a slim seek bar.
Item {
    id: root
    signal searchRequested()
    readonly property bool hasTimeline: media.lengthSec > 0
    height: 12 + 72 + (hasTimeline ? 8 + 20 : 0) + 12

    // artwork crossfade state: the new art loads into the hidden slot, the flip
    // happens only once it is ready, so the image never blinks empty.
    property string artA: ""
    property string artB: ""
    property string activeArtUrl: ""
    property string lastRequested: ""
    property string lastTitle: ""
    property bool showA: true

    // Two-finger sideways swipe on the card: next / previous track, one per gesture.
    WheelHandler {
        id: swipe
        orientation: Qt.Horizontal
        enabled: media.hasPlayer
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        property bool cooling: false
        onWheel: (e) => {
            const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : 0
            if (d === 0) return
            if (cooling) { cool.restart(); return }
            acc += d
            if (Math.abs(acc) < 90) return
            if (acc < 0) media.next(); else media.previous()
            acc = 0; cooling = true; cool.restart()
        }
    }
    Timer { id: cool; interval: 280; onTriggered: { swipe.cooling = false; swipe.acc = 0 } }

    Component.onCompleted: {
        root.lastTitle = media.title
        root.lastRequested = media.artUrl
        root.artA = media.artUrl
    }
    Connections {
        target: media
        function onChanged() {
            if (media.title !== root.lastTitle) {
                root.lastTitle = media.title
                reveal.restart()
            }
            if (media.artUrl === root.lastRequested) {
                return
            }
            root.lastRequested = media.artUrl
            if (media.artUrl.length === 0) {
                root.artA = ""
                root.artB = ""
                root.activeArtUrl = ""
            } else if (root.showA) {
                root.artB = media.artUrl
            } else {
                root.artA = media.artUrl
            }
        }
    }

    Rectangle {                                 // card surface + machined hairline
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: Qt.rgba(1, 1, 1, Tokens.tint.faint)
        border.width: 1
        border.color: Theme.rim
    }

    Item {                                      // ambient wash: blurred artwork colours
        anchors.fill: parent
        opacity: root.activeArtUrl.length > 0 ? 0.2 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.enter } }
        Image {
            id: washSource
            anchors.fill: parent
            source: root.activeArtUrl
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
        }
        MultiEffect {
            anchors.fill: washSource
            source: washSource
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 1.4
            brightness: -0.1
        }
    }

    Item {                                      // top row: artwork / info / transport
        id: top
        x: 12; y: 12
        width: parent.width - 24
        height: 72

        Rectangle {
            id: art
            width: 72; height: 72; radius: Tokens.radius.md
            color: Theme.chip
            opacity: artTap.pressed ? 0.82 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
            // The poster is the one way into the media view - it should feel alive.
            scale: artHover.hovered ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }

            // clip only cuts the square bounds; the poster is masked to the rounded corners.
            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: art.radius
                visible: false
                layer.enabled: true
            }
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Image {
                    id: slotA
                    anchors.fill: parent
                    source: root.artA
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: root.showA && status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.enter } }
                    onStatusChanged: if (status === Image.Ready && root.lastRequested === root.artA) {
                        root.showA = true
                        root.activeArtUrl = root.artA
                    }
                }
                Image {
                    id: slotB
                    anchors.fill: parent
                    source: root.artB
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: !root.showA && status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.enter } }
                    onStatusChanged: if (status === Image.Ready && root.lastRequested === root.artB) {
                        root.showA = false
                        root.activeArtUrl = root.artB
                    }
                }
            }
            Rectangle {                         // the rim, above the artwork
                anchors.fill: parent
                radius: art.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
            }
            EqBars {                            // no artwork: the eq is the artwork
                anchors.centerIn: parent
                active: media.playing
                barWidth: 4; minHeight: 4; maxHeight: 20
                opacity: root.activeArtUrl.length === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.slow } }
            }
            HoverHandler { id: artHover; cursorShape: Qt.PointingHandCursor }
            // WithinBounds = the press belongs to the poster alone; without it the
            // full-window close MouseArea also sees the release and folds the island
            // the same instant the media view opens.
            TapHandler { id: artTap; gesturePolicy: TapHandler.WithinBounds; onTapped: root.searchRequested() }
        }

        Item {
            id: info
            anchors { left: art.right; leftMargin: 14; right: controls.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 44
            transform: Translate { id: infoShift; y: 0 }
            ParallelAnimation {
                id: reveal
                NumberAnimation { target: infoShift; property: "y"; from: 4; to: 0; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
                NumberAnimation { target: info; property: "opacity"; from: 0; to: 1; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
            }
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                Text {
                    width: parent.width
                    text: media.hasPlayer ? (media.title || media.playerName) : "YouTube Music"
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.DemiBold }
                    color: Theme.text
                }
                Row {
                    spacing: 6
                    EqBars {
                        id: rowEq
                        anchors.verticalCenter: parent.verticalCenter
                        active: media.playing
                        opacity: media.playing ? 1 : 0.55
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }
                    }
                    Text {
                        width: parent.width - rowEq.width - 6
                        text: media.hasPlayer ? (media.artist || media.playerName) : I18n.tr("Nothing playing")
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        font { family: Theme.font; pixelSize: Tokens.type.label }
                        color: Theme.subtext
                    }
                }
            }
        }

        Row {
            id: controls
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8

            Item {                               // ghost: previous
                width: 32; height: 32
                opacity: media.hasPlayer ? 1 : 0.4
                Rectangle {
                    anchors.fill: parent; radius: Tokens.radius.lg
                    color: Qt.rgba(1, 1, 1, prevTap.pressed ? Tokens.tint.strong : prevHover.hovered ? Tokens.tint.soft : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
                Glyph {
                    anchors.centerIn: parent
                    name: "prev"; size: 16
                    scale: prevTap.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                }
                HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: prevTap; enabled: media.hasPlayer; onTapped: media.previous() }
            }

            Item {                               // hero: play / pause
                width: 36; height: 36
                opacity: media.hasPlayer ? 1 : 0.4
                Rectangle {
                    anchors.fill: parent; radius: Tokens.radius.lg
                    color: heroTap.pressed ? Tokens.role.island.heroPressed : Tokens.role.island.hero
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
                Item {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    scale: heroTap.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                    Glyph { anchors.centerIn: parent; name: "play"; size: 16; color: Tokens.role.dark.surface; opacity: media.playing ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } } }
                    Glyph { anchors.centerIn: parent; name: "pause"; size: 16; color: Tokens.role.dark.surface; opacity: media.playing ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } } }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: heroTap; enabled: media.hasPlayer; onTapped: media.playPause() }
            }

            Item {                               // ghost: next
                width: 32; height: 32
                opacity: media.hasPlayer ? 1 : 0.4
                Rectangle {
                    anchors.fill: parent; radius: Tokens.radius.lg
                    color: Qt.rgba(1, 1, 1, nextTap.pressed ? Tokens.tint.strong : nextHover.hovered ? Tokens.tint.soft : 0)
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
                Glyph {
                    anchors.centerIn: parent
                    name: "next"; size: 16
                    scale: nextTap.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                }
                HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: nextTap; enabled: media.hasPlayer; onTapped: media.next() }
            }
        }
    }

    MediaProgress {
        visible: root.hasTimeline
        x: 12
        y: top.y + top.height + 8
        width: parent.width - 24
        fraction: media.progress
        lengthSec: media.lengthSec
        playing: media.playing
        canSeek: media.canSeek
        onSeekRequested: (f) => media.seek(f)
    }
}
