import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import AetherShared

// The clean-desktop toggle. A round glass button at the bottom centre, above the dock: a folder
// while the desktop is clean, a broom while the files are out. Spreading throws a stand-in of
// every desktop entry out of the folder to the cell Folder View will draw it in, then hands over
// to the real icons; sweeping takes the real icons away under their stand-ins and draws those
// back into the button.
Item {
    id: root
    // The island's glass without its colour: Theme stays untinted (no accentOverride) and dark,
    // as the island always is.
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
    property bool broom                         // the face: broom while the files are out (set once,
    Component.onCompleted: broom = !desk.clean  // then by the animations, not bound to the filter)
    property string phase: "idle"               // "idle" | "spread" | "sweep"
    property int landed: 0
    property real open: 0                       // the folder's front flap, 0 shut .. 1 tipped open
    property real swish: 0                      // the broom's stroke, degrees
    property real jolt: 0                       // the stand-ins' shiver under a stroke, -1 .. 1
    property real pressScale: 1
    readonly property real glyphOpacity: 0.3   // the folder and the broom are mostly see-through, like the glass
    property real hoverScale: hover.containsMouse && phase === "idle" ? 1.06 : 1
    readonly property int count: ghosts.count
    readonly property int stagger: 18
    readonly property int flight: Tokens.motion.duration.morph + Tokens.motion.duration.fast
    // Where the stand-ins go in and come out: just under the flap's top edge.
    readonly property real mouthX: button.x + button.width / 2
    readonly property real mouthY: button.y + button.height / 2 + 3

    function toggle() {
        if (phase !== "idle")
            return;
        if (count === 0) {                       // nothing to throw: just flip
            broom = !broom;
            desk.setClean(!broom);
            return;
        }
        landed = 0;
        ghostLayer.opacity = 1;
        if (desk.clean) {
            phase = "spread";
            for (let i = 0; i < count; i++)
                ghosts.itemAt(i).t = 0;
            spread.start();
        } else {
            phase = "sweep";
            for (let i = 0; i < count; i++)
                ghosts.itemAt(i).t = 1;
            handOver.start();                    // let the stand-ins reach the screen before the icons go
            sweep.start();
        }
    }
    Connections {
        target: desk
        function onToggleRequested() { root.toggle(); }
    }
    function launchAll(out) {
        for (let i = 0; i < count; i++)
            ghosts.itemAt(i).launch(out ? 0 : 1, out ? 1 : 0, (out ? i : count - 1 - i) * stagger);
    }

    // Spread: the folder tips open, the files fly out, it shuts and turns into the broom.
    SequentialAnimation {
        id: spread
        NumberAnimation { target: root; property: "open"; to: 1; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
        ScriptAction { script: root.launchAll(true) }
        PauseAnimation { duration: (root.count - 1) * root.stagger + Tokens.motion.duration.slow }
        NumberAnimation { target: root; property: "open"; to: 0; duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.spring }
        ScriptAction { script: { root.broom = true; button.gulp(); } }
    }

    // Sweep: three strokes of the broom (the files shiver, dust flies), the broom becomes the folder,
    // it tips open, everything flies in, it shuts.
    Timer {
        id: handOver
        interval: 60
        onTriggered: desk.setClean(true)         // the stand-ins already cover the icons
    }
    component Stroke: ParallelAnimation {
        id: stroke
        property real to
        property int ms
        property int dir
        NumberAnimation { target: root; property: "swish"; to: stroke.to; duration: stroke.ms; easing.type: Easing.InOutQuad }
        SequentialAnimation {
            NumberAnimation { target: root; property: "jolt"; to: stroke.dir; duration: stroke.ms / 2; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "jolt"; to: 0; duration: stroke.ms / 2; easing.type: Easing.InQuad }
        }
        ScriptAction { script: dust.puff(stroke.dir) }
    }
    SequentialAnimation {
        id: sweep
        Stroke { to: 24; ms: 160; dir: 1 }
        Stroke { to: -24; ms: 220; dir: -1 }
        Stroke { to: 18; ms: 200; dir: 1 }
        NumberAnimation { target: root; property: "swish"; to: 0; duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.spring }
        ScriptAction { script: root.broom = false }
        PauseAnimation { duration: Tokens.motion.duration.base }
        NumberAnimation { target: root; property: "open"; to: 1; duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
        ScriptAction { script: root.launchAll(false) }
    }
    SequentialAnimation {
        id: shut
        PauseAnimation { duration: Tokens.motion.duration.micro }
        NumberAnimation { target: root; property: "open"; to: 0; duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.spring }
    }

    function arrived() {
        landed++;
        if (phase === "sweep") {
            button.gulp();
            if (landed === count) {
                phase = "idle";
                ghostLayer.opacity = 0;
                shut.start();
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

    // ---- The button's back: glass, the folder's back wall, the broom ---------------------------------------
    // (the stand-ins fly between this and the folder's front flap below them in the stacking order)
    component Face: Item {
        id: face
        property bool on
        property real tilt: -40
        anchors.centerIn: parent
        width: 30
        height: 30
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.6
        rotation: on ? 0 : tilt
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.spring } }
        Behavior on rotation { NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.spring } }
    }
    component ButtonScale: Scale {
        origin.x: button.width / 2; origin.y: button.height / 2
        xScale: root.pressScale * root.hoverScale; yScale: xScale
    }
    Behavior on hoverScale { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.spring } }

    Item {
        id: button
        readonly property int size: 60
        // Bottom centre, clear of the dock: its pill rests 14px off the bottom edge and is
        // icon + 2 cell insets + 2 pads tall (Dock.qml restD / thickness); keep one more 14 above it.
        readonly property int dockClear: 14 + Tokens.dock.icon + 2 * Tokens.dock.cellInset + 2 * Tokens.dock.pad + 14
        width: size
        height: size
        x: Math.round((root.width - size) / 2)
        y: root.height - size - dockClear
        onXChanged: report()
        onYChanged: report()
        Component.onCompleted: report()
        function report() { desk.setButtonRect(Qt.rect(x, y, width, height), size / 2); }
        transform: ButtonScale {}

        // A small swallow: squeezed in, sprung back out.
        function gulp() { squeeze.restart(); }
        SequentialAnimation {
            id: squeeze
            NumberAnimation { target: root; property: "pressScale"; to: 0.9; duration: Tokens.motion.duration.micro; easing.type: Tokens.motion.easing.exit }
            NumberAnimation { target: root; property: "pressScale"; to: 1; duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.spring }
        }

        // Frosted glass: no body at all, only KWin's blur of what lies behind (setButtonRect), a
        // rough grain over it and the hairline rim.
        Rectangle {
            id: glass
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Theme.rim
            Image {
                id: grain
                anchors.fill: parent
                source: Theme.grain
                fillMode: Image.Tile
                visible: false
            }
            Rectangle {
                id: mask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: grain
                maskEnabled: true
                maskSource: mask
                opacity: 0.04                        // a touch rougher than the notch's 0.022: frost
            }
            Rectangle {                              // hover / press veil
                anchors.fill: parent
                radius: width / 2
                color: Theme.veil(hover.pressed ? Tokens.tint.strong : Tokens.tint.soft)
                opacity: hover.pressed || hover.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
            }
        }

        Face {
            on: !root.broom
            FolderGlyph { part: "back"; open: root.open; opacity: root.glyphOpacity }
        }
        Face {
            on: root.broom
            tilt: 40
            BroomGlyph { id: broomGlyph; swish: root.swish; opacity: root.glyphOpacity }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
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
                property real t: 0                // 0 = inside the folder, 1 = in its cell
                readonly property point cell: root.cellOf(index)
                readonly property real fromX: root.mouthX - width / 2
                readonly property real fromY: root.mouthY - height / 2
                readonly property real dist: Math.hypot(cell.x - fromX, cell.y - fromY)
                readonly property real side: index % 2 ? 1 : -1
                width: root.cellW
                height: root.cellH
                visible: cell.y + root.cellH <= root.height
                // A thrown arc: straight in x, lifted in y by a share of the distance. Under a
                // broom stroke the parked ones shiver toward the stroke.
                x: fromX + (cell.x - fromX) * t + root.jolt * 5 * t
                y: fromY + (cell.y - fromY) * t - Math.sin(Math.PI * t) * dist * 0.18
                scale: 0.12 + 0.88 * t
                rotation: (1 - t) * -24 + root.jolt * 4 * side * t
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

    // ---- The folder's front flap, over the stand-ins: they go in and come out behind it -------------------
    Item {
        x: button.x
        y: button.y
        width: button.width
        height: button.height
        transform: ButtonScale {}
        Face {
            on: !root.broom
            FolderGlyph { part: "front"; open: root.open; opacity: root.glyphOpacity }
        }
    }

    // ---- Dust: a few motes kicked up by each stroke ---------------------------------------------------------
    Item {
        id: dust
        anchors.fill: parent
        function puff(dir) {
            const p = broomGlyph.tip();
            const at = broomGlyph.mapToItem(dust, p.x, p.y);
            for (let i = 0; i < motes.count; i++)
                motes.itemAt(i).kick(at.x, at.y, dir);
        }
        Repeater {
            id: motes
            model: 5
            delegate: Rectangle {
                id: mote
                required property int index
                width: 3 + (index % 3)
                height: width
                radius: width / 2
                color: Theme.text
                opacity: 0
                function kick(px, py, dir) {
                    life.stop();
                    x = px - width / 2;
                    y = py - height / 2;
                    dx.to = x + dir * (10 + index * 6);
                    dy.to = y - 4 - (index % 3) * 5;
                    life.start();
                }
                ParallelAnimation {
                    id: life
                    NumberAnimation { id: dx; target: mote; property: "x"; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.enter }
                    NumberAnimation { id: dy; target: mote; property: "y"; duration: Tokens.motion.duration.morph; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        NumberAnimation { target: mote; property: "opacity"; to: 0.55; duration: Tokens.motion.duration.micro }
                        NumberAnimation { target: mote; property: "opacity"; to: 0; duration: Tokens.motion.duration.morph - Tokens.motion.duration.micro; easing.type: Tokens.motion.easing.exit }
                    }
                    NumberAnimation { target: mote; property: "scale"; from: 0.6; to: 1.6; duration: Tokens.motion.duration.morph }
                }
            }
        }
    }
}
