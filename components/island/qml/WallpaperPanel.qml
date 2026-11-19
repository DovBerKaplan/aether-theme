import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import AetherShared
import "."

// Wallpaper panel: the aether fields, each preview wearing its real shader on the same 10 Hz tick the
// desktops run - so the choice is made on the living thing, in the accent in play. Every card is the
// screen in miniature (16:9, the mark at its centre); the signature field leads at full width, the
// other four sit under it two by two. Under them the mark itself is chosen: the distribution's logo,
// any logo the wallpapers know, an image of one's own, or none. A tap moves every desktop over at once (TileStore rides
// plasmashell's scripting API and the sync oneshots hand the new field its accent and mode); the
// footer's switch lets it rest.
PanelScaffold {
    id: root
    property string page: ""
    title: I18n.tr("Wallpaper")
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 10
                Switch { checked: tiles.wallpaperAnimate; onToggled: (c) => tiles.setWallpaperAnimate(c) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Let it live")
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
        }
    ]

    // One clock for every preview: 10 Hz, like the wallpapers themselves; nothing repaints faster,
    // and the whole panel is torn down shortly after the island closes anyway. The previews hold
    // still while the footer's switch rests the desktop.
    property real time: 0
    property real startedAt: Date.now()
    Timer {
        interval: 100
        repeat: true
        running: root.visible && tiles.wallpaperAnimate
        onTriggered: root.time = ((Date.now() - root.startedAt) / 1000) % 100000
    }

    // The mark as the wallpapers draw it (plasmoids/org.aether.ribbons/contents/ui/Mark.qml), for a
    // given spec: "" the distribution's logo, "none", "aether", "logo:<slug>", "file:<path>".
    readonly property string crescent: "M7.2 1.5a6.5 6.5 0 1 0 7.3 7.9A5.2 5.2 0 0 1 7.2 1.5zM12 1.2l.55 1.65L14.2 3.4l-1.65.55L12 5.6l-.55-1.65L9.8 3.4l1.65-.55z"
    readonly property var logoMap: {
        const m = {}
        for (const l of tiles.markLogos) m[l.slug] = l.path
        return m
    }
    function pathFor(spec) {
        if (spec === "none" || spec.indexOf("file:") === 0) return ""
        if (spec === "aether") return crescent
        if (spec.indexOf("logo:") === 0) return logoMap[spec.slice(5)] || crescent
        return tiles.distroLogo || crescent
    }
    component MarkGlyph: Item {
        id: glyph
        property string spec: ""
        property color color: "white"
        readonly property string path: root.pathFor(spec)
        readonly property string file: spec.indexOf("file:") === 0 ? spec.slice(5) : ""
        readonly property real units: path === root.crescent ? 16 : 24
        visible: spec !== "none"
        Shape {
            visible: glyph.path !== ""
            width: glyph.units; height: glyph.units
            scale: glyph.width / glyph.units
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.WindingFill
                fillColor: glyph.color
                PathSvg { path: glyph.path }
            }
        }
        Image {
            visible: glyph.file !== ""
            anchors.fill: parent
            source: glyph.file ? "file://" + glyph.file : ""
            sourceSize { width: Math.round(glyph.width * 2); height: Math.round(glyph.height * 2) }
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true; asynchronous: true
        }
    }

    // One preview card: the field, its mark, its name on a pill, and the ring of the choice.
    component WallCard: Item {
        id: entry
        required property var field
        property bool featured: false
        readonly property bool chosen: tiles.wallpaperStyle === field.id
        readonly property real corner: featured ? Tokens.radius.xl : Tokens.radius.lg
        height: Math.round(width * 9 / 16)

        Rectangle {      // the ring: the accent around the choice, a whisper around the hovered one
            anchors { fill: parent; margins: -4 }
            radius: entry.corner + 4
            color: "transparent"
            border { width: 2; color: entry.chosen ? Theme.accent : Theme.rim }
            opacity: entry.chosen ? 1 : hover.hovered ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        }

        Item {
            id: card
            anchors.fill: parent
            scale: tap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }

            // clip only cuts the square bounds; the field is masked to the rounded corners.
            Rectangle { id: mask; anchors.fill: parent; radius: entry.corner; visible: false; layer.enabled: true }
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }

                ShaderEffect {
                    anchors.fill: parent
                    fragmentShader: Qt.resolvedUrl("assets/wallpapers/" + entry.field.shader + ".frag.qsb")
                    property color accent: Theme.accent
                    property real dark: displaySettings.dark ? 1 : 0
                    property real aspect: width / Math.max(1, height)
                    property real px: 1 / Math.max(1, height)
                    property real time: root.time
                }
                // The mark, as the desktop wears it.
                MarkGlyph {
                    width: Math.round(entry.height * 0.15); height: width
                    anchors.centerIn: parent
                    spec: tiles.wallpaperMark
                    color: displaySettings.dark ? Theme.accent : Qt.darker(Theme.accent, 1.3)
                    opacity: displaySettings.dark ? 1 : 0.85
                }
            }
            Rectangle {          // a hairline rim, so the glass edge of the card stays crisp
                anchors.fill: parent
                radius: entry.corner
                color: "transparent"
                border { width: 1; color: displaySettings.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08) }
            }

            Rectangle {          // the name on a pill of glass that suits the field: dark on the night, milk on the day
                anchors { left: parent.left; leftMargin: entry.featured ? 12 : 8; bottom: parent.bottom; bottomMargin: entry.featured ? 12 : 8 }
                width: name.implicitWidth + (entry.featured ? 20 : 14); height: name.implicitHeight + (entry.featured ? 8 : 6)
                radius: height / 2
                color: displaySettings.dark ? Qt.rgba(0, 0, 0, 0.38) : Qt.rgba(1, 1, 1, 0.72)
                border { width: 1; color: displaySettings.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06) }
                Text {
                    id: name
                    anchors.centerIn: parent
                    text: I18n.tr(entry.field.title)
                    font { family: Theme.font; pixelSize: entry.featured ? Tokens.type.label + 1 : Tokens.type.caption + 1; weight: Font.DemiBold }
                    color: displaySettings.dark ? "white" : Qt.rgba(0.08, 0.12, 0.11, 0.88)
                }
            }
            Rectangle {          // the check on the choice
                anchors { right: parent.right; rightMargin: 8; top: parent.top; topMargin: 8 }
                width: 22; height: 22; radius: 11
                color: Theme.accent
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.25) }
                opacity: entry.chosen ? 1 : 0
                scale: entry.chosen ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Easing.OutBack } }
                Shape {
                    anchors.centerIn: parent
                    width: 12; height: 12
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.onAccent; strokeWidth: 2; fillColor: "transparent"
                        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M2 6.5L5 9.5L10 3" }
                    }
                }
            }
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; onTapped: tiles.setWallpaper(entry.field.id) }
    }

    Column {
        x: 22; width: parent.width - 44
        spacing: 14
        topPadding: 4

        WallCard {
            width: parent.width
            featured: true
            field: tiles.wallpapers[0]
        }
        Grid {
            columns: 2
            columnSpacing: 12; rowSpacing: 14
            width: parent.width
            Repeater {
                model: tiles.wallpapers.slice(1)
                delegate: WallCard {
                    required property var modelData
                    width: (parent.width - parent.columnSpacing) / 2
                    field: modelData
                }
            }
        }
        // The mark: which kind, then (for a logo) which one, or (for an image) which file.
        Item { width: 1; height: Tokens.space.xs }
        SectionLabel { width: parent.width; text: I18n.tr("Mark") }
        SegmentedControl {
            id: kind
            width: parent.width
            readonly property string spec: tiles.wallpaperMark
            readonly property int shown: spec === "" ? 0 : spec === "none" ? 3 : spec.indexOf("file:") === 0 ? 2 : 1
            model: [I18n.tr("Distribution"), I18n.tr("Logo"), I18n.tr("Image"), I18n.tr("None")]
            currentIndex: shown
            onActivated: (i) => {
                if (i === 0) tiles.setWallpaperMark("")
                else if (i === 1) tiles.setWallpaperMark("aether")
                else if (i === 2) tiles.importWallpaperMark()     // stays as it was until a file is picked
                else tiles.setWallpaperMark("none")
                currentIndex = Qt.binding(() => kind.shown)
            }
        }
        Grid {           // every logo the wallpapers know, the Aether mark first
            visible: kind.shown === 1
            width: parent.width
            columns: 8
            spacing: 8
            readonly property real cell: (width - 7 * spacing) / 8
            Repeater {
                model: [{ slug: "aether", path: root.crescent }].concat(tiles.markLogos)
                delegate: Rectangle {
                    id: logoTile
                    required property var modelData
                    readonly property string spec: modelData.slug === "aether" ? "aether" : "logo:" + modelData.slug
                    readonly property bool chosen: tiles.wallpaperMark === spec
                    width: parent.cell; height: width
                    radius: Tokens.radius.md
                    color: chosen ? Theme.accent : logoHover.hovered ? Theme.rim : Theme.chip
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                    scale: logoTap.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                    MarkGlyph {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.52); height: width
                        spec: logoTile.spec
                        color: logoTile.chosen ? Theme.onAccent : Theme.text
                    }
                    HoverHandler { id: logoHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: logoTap; onTapped: tiles.setWallpaperMark(logoTile.spec) }
                }
            }
        }
        Row {            // the image of one's own, and a way to another
            visible: kind.shown === 2
            spacing: Tokens.space.md
            Rectangle {
                width: 44; height: 44; radius: Tokens.radius.md
                color: Theme.chip
                MarkGlyph { anchors { fill: parent; margins: 6 } spec: tiles.wallpaperMark }
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Another image…")
                enabled: tiles.canImportMark
                onClicked: tiles.importWallpaperMark()
            }
        }
        Item { width: 1; height: Tokens.space.xs }
    }
}
