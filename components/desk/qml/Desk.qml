import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import AetherShared

// The clean-desktop toggle. A glass button in the bottom-right corner: a folder while the desktop
// is clean, a broom while the files are out. Spreading throws a stand-in of every desktop entry
// out of the folder to the cell Folder View will draw it in, then hands over to the real icons;
// sweeping takes the real icons away under their stand-ins and draws those back into the button.
Item {
    id: root
    Binding { target: Theme; property: "accentOverride"; value: desk.accentOverride }
    Binding { target: Theme; property: "dark"; value: desk.dark }
    // Folder View's grid is laid out by its own settings, not by this program's locale.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // ---- Folder View's grid (FolderView.qml cellWidth / cellHeight, same units) ---------------------
    readonly property real gu: Kirigami.Units.gridUnit
    readonly property real sp: Kirigami.Units.smallSpacing
    readonly property var iconSizes: [Kirigami.Units.iconSizes.smallMedium, Kirigami.Units.iconSizes.medium,
        Kirigami.Units.iconSizes.large, Kirigami.Units.iconSizes.huge, Kirigami.Units.iconSizes.large * 2,
        Kirigami.Units.iconSizes.enormous, Kirigami.Units.iconSizes.enormous * 2]
    readonly property int iconSize: iconSizes[Math.max(0, Math.min(6, desk.grid.iconSize))]
    readonly property int textLines: desk.grid.textLines
    function extraSpacing(cell, size) {
        const n = Math.floor(size / cell);
        return n > 0 ? Math.floor(Math.max(size - n * cell, 0) / n) : 0;
    }
    readonly property int cellW: {
        const w = Math.max(iconSize + 2 * gu + 2 * sp, Kirigami.Units.iconSizes.small * (desk.grid.labelWidth * 2 + 4));
        return w + extraSpacing(w, width);
    }
    readonly property int cellH: {
        const h = iconSize + gu * textLines + sp * 3;
        return h + extraSpacing(h, height);
    }
    readonly property bool rows: desk.grid.arrangement === 0
    readonly property bool rtl: desk.grid.alignment === 1
    readonly property int perStripe: Math.max(1, rows ? Math.floor(width / cellW) : Math.floor(height / cellH))
    function cellOf(i) {
        const a = i % perStripe, b = Math.floor(i / perStripe);
        const col = rows ? a : b, row = rows ? b : a;
        return Qt.point(rtl ? width - (col + 1) * cellW : col * cellW, row * cellH);
    }

    // ---- State ------------------------------------------------------------------------------------------
    property bool broom: !desk.clean            // the glyph: broom while the files are out
    property string phase: "idle"               // "idle" | "spread" | "sweep"
    property int landed: 0
    readonly property int count: ghosts.count
    readonly property int stagger: 18
    readonly property int flight: Tokens.motion.duration.morph + Tokens.motion.duration.fast

    function toggle() {
        if (phase !== "idle")
            return;
        if (count === 0) {                       // nothing to throw: just flip
            broom = !broom;
            desk.setClean(!broom);
            return;
        }
        landed = 0;
        if (desk.clean) {
            phase = "spread";
            ghostLayer.opacity = 1;
            for (let i = 0; i < count; i++)
                ghosts.itemAt(i).launch(0, 1, i * stagger);
            broom = true;
            button.gulp();
        } else {
            phase = "sweep";
            ghostLayer.opacity = 1;
            for (let i = 0; i < count; i++)
                ghosts.itemAt(i).t = 1;
            handOver.start();                    // let the stand-ins reach the screen before the icons go
        }
    }
    Connections {
        target: desk
        function onToggleRequested() { root.toggle(); }
    }

    // Sweep, step 2: the stand-ins cover the icons; Folder View hides them, then the flight starts.
    Timer {
        id: handOver
        interval: 60
        onTriggered: {
            desk.setClean(true);
            sweepStart.start();
        }
    }
    Timer {
        id: sweepStart
        interval: Tokens.motion.duration.base   // Folder View's filter lands in about one frame; leave room
        onTriggered: {
            for (let i = 0; i < root.count; i++)
                ghosts.itemAt(i).launch(1, 0, (root.count - 1 - i) * root.stagger);
        }
    }
    function arrived() {
        landed++;
        if (phase === "sweep") {
            button.gulp();
            if (landed === count) {
                broom = false;
                phase = "idle";
                ghostLayer.opacity = 0;
            }
        } else if (phase === "spread" && landed === count) {
            desk.setClean(false);                // the real icons return under their stand-ins
            fadeOut.start();
        }
    }
    SequentialAnimation {
        id: fadeOut
        PauseAnimation { duration: Tokens.motion.duration.slow }
        NumberAnimation { target: ghostLayer; property: "opacity"; to: 0; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.exit }
        ScriptAction { script: root.phase = "idle" }
    }

    // ---- Stand-ins ----------------------------------------------------------------------------------------
    Item {
        id: ghostLayer
        anchors.fill: parent
        opacity: 0
        visible: root.phase !== "idle"

        Repeater {
            id: ghosts
            model: desk.items
            delegate: Item {
                id: g
                required property var modelData
                required property int index
                property real t: 0                // 0 = inside the button, 1 = in its cell
                readonly property point cell: root.cellOf(index)
                readonly property real fromX: button.x + button.width / 2 - width / 2
                readonly property real fromY: button.y + button.height / 2 - height / 2
                readonly property real dist: Math.hypot(cell.x - fromX, cell.y - fromY)
                width: root.cellW
                height: root.cellH
                visible: cell.y + root.cellH <= root.height
                // A thrown arc: straight in x, lifted in y by a share of the distance.
                x: fromX + (cell.x - fromX) * t
                y: fromY + (cell.y - fromY) * t - Math.sin(Math.PI * t) * dist * 0.18
                scale: 0.2 + 0.8 * t
                rotation: (1 - t) * -24
                opacity: Math.min(1, t * 4)

                function launch(from, to, delay) {
                    fly.stop();
                    t = from;
                    move.from = from;
                    move.to = to;
                    move.easing.type = to > from ? Tokens.motion.easing.enter : Tokens.motion.easing.exit;
                    move.duration = root.flight + Math.min(dist / 12, Tokens.motion.duration.base);
                    wait.duration = delay;
                    fly.start();
                }
                SequentialAnimation {
                    id: fly
                    PauseAnimation { id: wait }
                    NumberAnimation { id: move; target: g; property: "t" }
                    ScriptAction { script: root.arrived() }
                }

                // Folder View's delegate: the icon on top, the label under it.
                Image {
                    id: icon
                    x: (parent.width - root.iconSize) / 2
                    y: 2 * root.sp
                    width: root.iconSize
                    height: root.iconSize
                    sourceSize: Qt.size(root.iconSize, root.iconSize)
                    source: "image://icon/" + g.modelData.icon
                    smooth: true
                }
                Text {
                    anchors.top: icon.bottom
                    anchors.topMargin: root.sp
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 3 * root.sp      // Folder View: frame (cell - 2 spacing) minus one spacing
                    text: g.modelData.name
                    color: "white"
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.35)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: root.textLines
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Folder and broom trade places: the outgoing glyph tips away and fades, the new one swings in.
    component Face: Item {
        id: face
        property string name
        property bool on
        anchors.centerIn: parent
        width: 22
        height: 22
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.6
        rotation: on ? 0 : (name === "broom" ? 40 : -40)
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.spring } }
        Behavior on rotation { NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.spring } }
        Image {
            id: img
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/" + face.name + ".svg")
            sourceSize: Qt.size(66, 66)
            visible: false
        }
        MultiEffect {
            anchors.fill: img
            source: img
            colorization: 1.0
            colorizationColor: Theme.text
        }
    }
    // ---- The button ---------------------------------------------------------------------------------------
    Item {
        id: button
        readonly property int size: 48
        readonly property int radius: 16
        readonly property int margin: 24
        width: size
        height: size
        x: root.width - size - margin
        y: root.height - size - margin
        onXChanged: report()
        onYChanged: report()
        Component.onCompleted: report()
        function report() { desk.setButtonRect(Qt.rect(x, y, width, height), radius); }

        // A small swallow: squeezed in, sprung back out.
        function gulp() { squeeze.restart(); }
        transform: Scale { id: bs; origin.x: button.width / 2; origin.y: button.height / 2 }
        SequentialAnimation {
            id: squeeze
            NumberAnimation { target: bs; properties: "xScale,yScale"; to: 0.88; duration: Tokens.motion.duration.micro; easing.type: Tokens.motion.easing.exit }
            NumberAnimation { target: bs; properties: "xScale,yScale"; to: 1; duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.spring }
        }

        // The island's glass: gradient body, hairline rim, grain.
        Rectangle {
            anchors.fill: parent
            radius: button.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.bodyTop }
                GradientStop { position: 1; color: Theme.bodyBottom }
            }
            border.width: 1
            border.color: Theme.rim
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: Theme.grain
                fillMode: Image.Tile
                opacity: Theme.dark ? Tokens.material.dockGrainDark : Tokens.material.dockGrainLight
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: mask
                }
            }
            Rectangle {
                id: mask
                anchors.fill: parent
                radius: button.radius
                visible: false
                layer.enabled: true
            }
            Rectangle {                              // hover / press veil
                anchors.fill: parent
                radius: button.radius
                color: Theme.chip
                opacity: hover.pressed ? 1 : hover.containsMouse ? 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
            }
        }

        Face { name: "folder"; on: !root.broom }
        Face { name: "broom"; on: root.broom }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }
}
