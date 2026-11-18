import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import AetherShared

// Circle to search. The screen is frozen under a faint dim; a coloured glow sweeps its edge.
// Draw around something (or tap a word) to select it; the sheet below offers search, Lens,
// translate and copy. The top-right button translates every line of the screen in place.
Item {
    id: root
    focus: true
    LayoutMirroring.enabled: I18n.rtl
    LayoutMirroring.childrenInherit: true

    Binding { target: I18n; property: "lang"; value: lens.lang }
    Binding { target: Theme; property: "dark"; value: true }
    Binding { target: Theme; property: "accentOverride"; value: lens.accentOverride }

    // ---- state ----------------------------------------------------------------------------
    property real enter: 0                       // 0 hidden .. 1 fully shown
    property bool closing: false
    property rect sel: Qt.rect(0, 0, 0, 0)
    property bool hasSel: false
    property var selWords: []
    property string selText: ""
    property int cropSerial: 0
    property bool translated: false
    property string toastText: ""
    property var points: []                      // freehand stroke while drawing
    property bool drawing: false

    Behavior on enter { NumberAnimation { duration: root.closing ? 320 : 450; easing.type: root.closing ? Easing.InCubic : Easing.OutCubic } }

    Connections {
        target: lens
        function onActivated() {
            root.closing = false; root.clear(); root.translated = false
            root.enter = 0; root.enter = 1
            glow.originX = lens.originX; glow.originY = lens.originY
            glow.reveal = 0; glow.strength = 0
            openGlow.restart()
            root.forceActiveFocus()
        }
        function onCloseRequested() { root.close() }
        function onTranslateRequested() { root.translated = true; root.clear(); lens.translateScreen() }
        function onWordsChanged() { if (root.hasSel) root.refreshText() }
        function onToast(m) { root.toastText = I18n.tr(m); toastAnim.restart() }
    }

    function clear() {
        hasSel = false; sel = Qt.rect(0, 0, 0, 0); selWords = []; selText = ""; points = []; drawing = false
        lens.setSelection(Qt.rect(0, 0, 0, 0))
    }
    function close() {
        if (closing) return
        closing = true; enter = 0
        openGlow.stop()
        closeGlow.restart()
        finish.restart()
    }
    Timer { id: finish; interval: 380; onTriggered: lens.finishClose() }

    function refreshText() {
        const ws = lens.words, r = sel, hit = []
        for (let i = 0; i < ws.length; ++i) {
            const cx = ws[i].x + ws[i].w / 2, cy = ws[i].y + ws[i].h / 2
            if (cx >= r.x && cx <= r.x + r.width && cy >= r.y && cy <= r.y + r.height) hit.push(ws[i])
        }
        // reading order: line by line, left to right (right to left for Hebrew lines)
        const lines = {}
        const keys = []
        for (const w of hit) { if (!(w.line in lines)) { lines[w.line] = []; keys.push(w.line) } lines[w.line].push(w) }
        keys.sort((a, b) => lines[a][0].y - lines[b][0].y)
        const out = []
        for (const k of keys) {
            const l = lines[k]
            const rtl = l.filter(w => w.rtl).length * 2 > l.length
            l.sort((a, b) => rtl ? b.x - a.x : a.x - b.x)
            out.push(l.map(w => w.text).join(" "))
        }
        selWords = hit
        selText = out.join("\n")
    }
    function select(r) {
        sel = r; hasSel = true; cropSerial += 1
        lens.setSelection(r)
        refreshText()
    }
    function commitStroke() {
        const p = points
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const q of p) { x0 = Math.min(x0, q.x); y0 = Math.min(y0, q.y); x1 = Math.max(x1, q.x); y1 = Math.max(y1, q.y) }
        const pad = 12
        let w = Math.max(48, x1 - x0 + 2 * pad), h = Math.max(48, y1 - y0 + 2 * pad)
        select(frame.fit(Qt.rect(x0 - pad - (w - (x1 - x0 + 2 * pad)) / 2, y0 - pad - (h - (y1 - y0 + 2 * pad)) / 2, w, h)))
    }
    function tapAt(x, y) {
        const ws = lens.words
        for (let i = 0; i < ws.length; ++i) {
            const w = ws[i]
            if (x >= w.x - 4 && x <= w.x + w.w + 4 && y >= w.y - 4 && y <= w.y + w.h + 4) {
                let r = Qt.rect(w.x, w.y, w.w, w.h)
                for (const o of ws) if (o.line === w.line) {
                    const nx = Math.min(r.x, o.x), ny = Math.min(r.y, o.y)
                    r = Qt.rect(nx, ny, Math.max(r.x + r.width, o.x + o.w) - nx, Math.max(r.y + r.height, o.y + o.h) - ny)
                }
                select(frame.fit(Qt.rect(r.x - 8, r.y - 6, r.width + 16, r.height + 12)))
                return
            }
        }
        // not a word: whatever object is under the tap (a picture, an icon, a card), bounds and all
        const o = lens.objectAt(x, y)
        if (o.width > 0 && o.height > 0)
            select(frame.fit(Qt.rect(o.x - 8, o.y - 8, o.width + 16, o.height + 16)))
        else
            select(frame.fit(Qt.rect(x - 120, y - 120, 240, 240)))
        // The application's own answer is exact; anything else is refined by the segmentation model
        // (it answers a moment later and the selection eases to its bounds).
        if (lens.lastObjectSource() !== "a11y")
            segToken = lens.segmentAt(x, y)
    }
    property int segToken: 0
    Connections {
        target: lens
        function onObjectRefined(token, r) {
            if (token !== root.segToken || !root.hasSel || r.width < 8 || r.height < 8) return
            root.select(frame.fit(Qt.rect(r.x - 8, r.y - 8, r.width + 16, r.height + 16)))
        }
    }

    Keys.onEscapePressed: { if (hasSel) clear(); else close() }

    // ---- the frozen screen ------------------------------------------------------------------
    Item {
        id: frame
        anchors.fill: parent
        opacity: root.enter > 0.001 || !root.closing ? 1 : 0
        scale: 1 - 0.015 * root.enter
        function fit(r) {
            const w = Math.min(r.width, width), h = Math.min(r.height, height)
            return Qt.rect(Math.max(0, Math.min(r.x, width - w)), Math.max(0, Math.min(r.y, height - h)), w, h)
        }

        Image {
            id: shot
            anchors.fill: parent
            source: lens.serial > 0 ? "image://lens/frame/" + lens.serial : ""
            cache: false
            asynchronous: false
            smooth: true
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.18 * root.enter }

        // the rest of the screen dims further around the selection
        Shape {
            anchors.fill: parent
            opacity: root.hasSel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillRule: ShapePath.OddEvenFill
                fillColor: Qt.rgba(0, 0, 0, 0.45)
                strokeColor: "transparent"
                PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height }
                PathRectangle { x: root.sel.x; y: root.sel.y; width: root.sel.width; height: root.sel.height; radius: 14 }
            }
        }

        // recognised words inside the selection
        Repeater {
            model: root.hasSel ? root.selWords : []
            Rectangle {
                required property var modelData
                x: modelData.x - 3; y: modelData.y - 2; width: modelData.w + 6; height: modelData.h + 4
                radius: 5
                color: Qt.rgba(Tokens.role.lens.selection.r, Tokens.role.lens.selection.g, Tokens.role.lens.selection.b, 0.35)
            }
        }

        TranslateLayer {
            anchors.fill: parent
            visible: root.translated
            lines: lens.screenTranslation
        }
    }

    // Glow around the screen edge. Opening: the colour grows out of the dock's grab line and runs
    // around the screen edge (reveal), brightening as it goes (strength), then settles to a
    // shimmer. Closing: it pulls back into the same point. Selecting something quiets it.
    GlowBorder {
        id: glow
        anchors.fill: parent
        thickness: 3
        halo: 14
        radius: 30
        reveal: 0
        strength: 0
        property real level: 0                   // 0..1, how bright the ring is overall
        property real quiet: root.hasSel ? 0 : 1
        Behavior on quiet { NumberAnimation { duration: 400 } }
        // brightness: full during the opening, resting at a shimmer
        property real settle: 1
        onLevelChanged: strength = level * quiet * (0.9 + 0.1 * settle)
        onQuietChanged: strength = level * quiet * (0.9 + 0.1 * settle)
        onSettleChanged: strength = level * quiet * (0.9 + 0.1 * settle)
        NumberAnimation on angle { from: 0; to: 360; duration: 5000; loops: Animation.Infinite; running: root.enter > 0 }
        ParallelAnimation {
            id: openGlow
            NumberAnimation { target: glow; property: "reveal"; from: 0; to: 1; duration: 950; easing.type: Easing.OutCubic }
            NumberAnimation { target: glow; property: "level"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutQuad }
            SequentialAnimation {
                PropertyAction { target: glow; property: "settle"; value: 1 }
                PauseAnimation { duration: 1100 }
                NumberAnimation { target: glow; property: "settle"; to: 0; duration: 1100 }
            }
        }
        ParallelAnimation {
            id: closeGlow
            NumberAnimation { target: glow; property: "reveal"; to: 0; duration: 340; easing.type: Easing.InCubic }
            NumberAnimation { target: glow; property: "level"; to: 0; duration: 340; easing.type: Easing.InQuad }
        }
    }

    // ---- drawing ----------------------------------------------------------------------------
    MouseArea {
        id: pad
        anchors.fill: parent
        enabled: !root.closing
        property point start
        property real travelled: 0
        property bool began: false     // a press that started here (the dock's hold ends over us as a bare release)
        onPressed: (m) => {
            began = true
            root.segToken = 0
            start = Qt.point(m.x, m.y); travelled = 0
            root.points = [Qt.point(m.x, m.y)]
            root.drawing = true
            if (root.hasSel) { root.hasSel = false; root.translated = false }
        }
        onPositionChanged: (m) => {
            if (!pressed) return
            travelled = Math.max(travelled, Math.hypot(m.x - start.x, m.y - start.y))
            const p = root.points
            p.push(Qt.point(m.x, m.y))
            root.points = p
        }
        onReleased: (m) => {
            if (!began) return
            began = false
            root.drawing = false
            if (travelled < 12) root.tapAt(m.x, m.y)
            else root.commitStroke()
            root.points = []
        }
    }

    // the stroke: a soft halo under a white line
    Item {
        anchors.fill: parent
        visible: root.drawing
        Shape {
            id: strokeShape
            anchors.fill: parent
            layer.enabled: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "white"; strokeWidth: 12; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathPolyline { path: root.points }
            }
        }
        MultiEffect { anchors.fill: strokeShape; source: strokeShape; blurEnabled: true; blur: 0.6; blurMax: 24; opacity: 0.7; z: -1 }
    }

    SelectionFrame {
        rect: root.sel
        bounds: Qt.size(root.width, root.height)
        shown: root.hasSel && !root.closing
        onEdited: (r) => { root.segToken = 0; root.select(r) }
    }

    // ---- chrome -----------------------------------------------------------------------------
    opacity: 1
    GlassButton {
        id: closeBtn
        anchors { top: parent.top; topMargin: 24; left: parent.left; leftMargin: 24 }
        icon: "window-close"
        opacity: root.enter; scale: 0.8 + 0.2 * root.enter
        onClicked: root.close()
    }
    GlassButton {
        id: trBtn
        anchors { top: parent.top; topMargin: 24; right: parent.right; rightMargin: 24 }
        TranslateGlyph { anchors.centerIn: parent; size: 22; color: trBtn.active ? Tokens.role.lens.textOnPrimary : Theme.text; cut: trBtn.color }
        active: root.translated
        opacity: root.enter; scale: 0.8 + 0.2 * root.enter
        onClicked: {
            root.translated = !root.translated
            if (root.translated) { root.clear(); lens.translateScreen() }
        }
    }
    Rectangle {
        visible: root.translated
        anchors { top: parent.top; topMargin: 30; horizontalCenter: parent.horizontalCenter }
        height: 32; radius: 16; width: tl.implicitWidth + 28
        color: Qt.rgba(Theme.bodyTop.r, Theme.bodyTop.g, Theme.bodyTop.b, 0.88); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Text {
            id: tl; anchors.centerIn: parent
            text: lens.translatingScreen ? I18n.tr("Translating…") : I18n.tr("Translated · Hebrew ↔ English")
            font.family: Theme.font; font.pixelSize: Tokens.type.body; color: Theme.text
        }
    }

    Rectangle {   // the hint, on dark glass so it reads over a white screen too
        anchors { horizontalCenter: parent.horizontalCenter; bottom: pill.top; bottomMargin: 14 }
        visible: !root.hasSel && !root.drawing && !root.translated
        opacity: root.enter
        height: 30; radius: 15; width: hint.implicitWidth + 28
        color: Qt.rgba(0.11, 0.12, 0.15, 0.86); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Text {
            id: hint
            anchors.centerIn: parent
            text: I18n.tr("Circle or tap to search")
            font.family: Theme.font; font.pixelSize: Tokens.type.body; font.weight: Font.Medium
            color: Theme.text
        }
    }

    ResultsSheet {
        id: sheet
        width: Math.min(640, root.width - 32)
        anchors { horizontalCenter: parent.horizontalCenter; bottom: pill.top; bottomMargin: 12 }
        open: root.hasSel && !root.closing
        text: root.selText
        busy: lens.ocrBusy
        ocrAvailable: lens.ocrAvailable
        cropSerial: root.cropSerial
    }

    SearchPill {
        id: pill
        width: Math.min(720, root.width - 32)
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
        opacity: root.enter
        transform: Translate { y: (1 - root.enter) * 40 }
    }

    Rectangle {
        id: toastPill
        anchors { top: parent.top; topMargin: 32; horizontalCenter: parent.horizontalCenter }
        height: 36; radius: 18; width: tt.implicitWidth + 36
        color: Qt.rgba(Theme.bodyTop.r, Theme.bodyTop.g, Theme.bodyTop.b, 0.94); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
        opacity: 0
        Text { id: tt; anchors.centerIn: parent; text: root.toastText; font.family: Theme.font; font.pixelSize: 14; color: Theme.text }
        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toastPill; property: "opacity"; to: 1; duration: 140 }
            PauseAnimation { duration: 1500 }
            NumberAnimation { target: toastPill; property: "opacity"; to: 0; duration: 300 }
        }
    }
}
