import QtQuick
import AetherShared
import "."

// The island's launcher view: the tab itself morphs into the query pill and the glass drops
// a ranked curtain below it (Island.qml's mode "search"). With no query the glass answers
// at once - a grid of the most-used apps and the freshest files and pages - and while typing
// one ranked list takes over: the machine's own usage analytics order it, and each row wears
// a small kind tag (app / file / page / calc / command / web).
Item {
    id: root
    property real maxHeight: 10000
    readonly property real contentHeight: Math.min(maxHeight, contentCol.implicitHeight + 26)
    property alias text: input.text
    property int sel: -1                 // selection index, counted over result rows only
    signal backRequested()
    signal closeRequested()
    signal pullStarted()
    signal pullMoved(real dy, real vy)
    signal pullEnded()

    function reset() {
        input.text = ""
        root.sel = -1
        search.setScope("all")
        search.clear()
        search.prime()
        root.refreshScopes()
    }

    function focusInput() { input.forceActiveFocus() }

    readonly property var scopeEntries: search.scopes.filter(s => s.ok)
    function refreshScopes() {
        scopeRow.entries = scopeEntries
        const i = scopeEntries.findIndex(s => s.key === search.scope)
        scopeRow.currentIndex = Math.max(0, i)
        scopeRow.model = scopeEntries.map(s => s.key === "all" ? I18n.tr("All")
                                                        : s.key === "apps" ? I18n.tr("Apps")
                                                        : s.key === "files" ? I18n.tr("Files")
                                                        : I18n.tr("Web"))
    }
    Connections {
        target: search
        function onMatchesChanged() { root.buildRows() }
        function onScopesChanged() { root.refreshScopes() }
    }

    function kindTag(kind) {
        return kind === "app" ? I18n.tr("App")
             : kind === "file" ? I18n.tr("File")
             : kind === "page" ? I18n.tr("Page")
             : kind === "calc" ? I18n.tr("Calc")
             : kind === "command" ? I18n.tr("Command")
             : I18n.tr("Web")
    }
    function kindGlyph(kind) {
        return kind === "app" ? "logo"
             : kind === "file" ? "folder"
             : kind === "page" ? "globe"
             : kind === "calc" ? "calc"
             : kind === "command" ? "keyboard"
             : "globe"
    }
    function iconSrc(m) {
        const ic = m.icon || ""
        if (ic === "") return ""
        return ic.indexOf("file://") === 0 ? ic : "image://icon/" + ic
    }
    // first strong directional character decides the input's alignment
    function rtlText(s) {
        for (let i = 0; i < s.length; ++i) {
            const c = s.charCodeAt(i)
            if (c >= 0x590 && c <= 0x8FF) return true      // Hebrew / Arabic blocks
            if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c <= 0x24F)) return false
        }
        return I18n.rtl
    }

    property var rows: []
    function buildRows() {
        root.rows = search.matches
        if (root.sel >= root.rows.length) root.sel = root.rows.length > 0 ? root.rows.length - 1 : -1
    }

    Timer { id: debounce; interval: 120; onTriggered: search.query(input.text) }
    onVisibleChanged: if (visible) root.focusInput()

    Keys.onDownPressed: root.moveSel(1)
    Keys.onUpPressed: root.moveSel(-1)
    function moveSel(d) {
        if (root.rows.length === 0) return
        root.sel = root.sel < 0 ? (d > 0 ? 0 : root.rows.length - 1)
                                : Math.max(0, Math.min(root.rows.length - 1, root.sel + d))
    }
    function runSel() {
        root.runAt(root.sel < 0 ? 0 : root.sel)
    }
    function runAt(flatIndex) {
        if (flatIndex >= 0 && flatIndex < root.rows.length) {
            search.run(flatIndex)
            root.closeRequested()      // the launch is the verdict: the glass folds back to the tab
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + 26
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: contentCol
            width: parent.width

            // ---- the query pill (the morphed tab) ------------------------------------------
            Item {
                width: parent.width; height: 64
                BackButton {
                    id: back
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    onActivated: root.backRequested()
                }
                Glyph {
                    id: mark
                    anchors { left: back.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    name: "search"; size: 18; color: input.activeFocus ? Theme.text : Theme.subtext
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
                TextInput {
                    id: input
                    anchors {
                        left: mark.right; leftMargin: 10
                        right: trail.left; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    cursorDelegate: Rectangle {
                        visible: parent ? parent.cursorVisible : false
                        width: 2; radius: 1
                        color: Theme.accent
                    }
                    clip: true
                    font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.Medium }
                    horizontalAlignment: root.rtlText(text) ? TextInput.AlignRight : TextInput.AlignLeft
                    onTextChanged: {
                        root.sel = -1
                        if (text !== "") debounce.restart()
                        else search.clear()
                    }
                    Keys.onReturnPressed: root.runSel()
                    Keys.onDownPressed: root.moveSel(1)
                    Keys.onUpPressed: root.moveSel(-1)
                    Text {
                        visible: input.text === "" && !input.activeFocus
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                        text: I18n.tr("Search apps, files, pages…")
                        font: input.font
                        color: Theme.subtext
                    }
                }
                Row {
                    id: trail
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Item {
                        visible: input.text !== ""
                        width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent; radius: 14
                            color: Theme.veil(clearTap.pressed ? Tokens.tint.strong : clearHover.hovered ? Tokens.tint.soft : 0)
                            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                        }
                        Glyph { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.text }
                        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: clearTap; onTapped: { input.text = ""; root.focusInput() } }
                    }
                    Keycap { label: "esc"; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            LinearProgress {
                width: parent.width
                running: search.busy && input.text !== ""
            }

            // hairline under the pill, inset like a panel's scrolled hairline
            Rectangle {
                width: parent.width - 32; height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.rim
            }

            // ---- scopes ---------------------------------------------------------------------
            Item {
                visible: input.text !== "" && scopeRow.model.length > 1
                width: parent.width; height: 48
                SegmentedControl {
                    id: scopeRow
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    width: Math.min(320, parent.width - 48)
                    property var entries: []
                    onActivated: (i) => {
                        if (i < 0 || i >= entries.length) return
                        search.setScope(entries[i].key)
                        debounce.restart()
                    }
                }
            }

            // ---- the empty query: the launcher answers before anything is typed --------------
            Item {
                visible: input.text === "" && search.suggestions.length > 0
                width: parent.width; height: 30 + gridRows * 74 + (gridRows - 1) * 14   // grid spacing between rows
                readonly property int gridRows: search.suggestions.length > 4 ? 2 : 1
                Text {
                    anchors { left: parent.left; leftMargin: 22; top: parent.top; topMargin: 8 }
                    text: I18n.tr("Suggested")
                    font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; letterSpacing: 0.4 }
                    color: Theme.subtext
                }
                Grid {
                    id: grid
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 30 }
                    columns: 4
                    horizontalItemAlignment: Grid.AlignHCenter
                    spacing: 14
                    Repeater {
                        model: search.suggestions
                        Item {
                            id: sugg
                            required property var modelData
                            required property int index
                            width: 96; height: 74
                            opacity: suggTap.pressed ? 0.85 : 1
                            scale: suggTap.pressed ? 0.94 : 1
                            Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }
                            Rectangle {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                                width: 52; height: 52; radius: 26
                                color: Theme.veil(suggTap.pressed ? Tokens.tint.strong : suggHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                                Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                                Item {
                                    anchors.centerIn: parent
                                    width: 30; height: 30
                                    Image {
                                        anchors.fill: parent
                                        visible: root.iconSrc(sugg.modelData) !== ""
                                        source: visible ? root.iconSrc(sugg.modelData) : ""
                                        sourceSize: Qt.size(60, 60)
                                        asynchronous: false
                                    }
                                    Glyph {
                                        anchors.centerIn: parent
                                        visible: root.iconSrc(sugg.modelData) === ""
                                        name: "logo"; size: 24; color: Theme.text
                                    }
                                }
                            }
                            Text {
                                anchors { top: parent.top; topMargin: 54; left: parent.left; right: parent.right }
                                horizontalAlignment: Text.AlignHCenter
                                text: sugg.modelData.text; textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: Tokens.type.caption }
                                color: Theme.subtext
                            }
                            HoverHandler { id: suggHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: suggTap; onTapped: { search.runSuggestion(sugg.index); root.closeRequested() } }
                        }
                    }
                }
            }

            // ---- results: one ranked list, every row wearing its kind ------------------------
            Column {
                visible: root.rows.length > 0 && (input.text !== "" || search.suggestions.length > 0)
                width: parent.width
                topPadding: 8
                spacing: 2
                Text {
                    visible: input.text === "" && root.rows.length > 0
                    anchors { left: parent.left; leftMargin: 22; bottomMargin: 4 }
                    text: I18n.tr("Recent")
                    font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; letterSpacing: 0.4 }
                    color: Theme.subtext
                }
                Repeater {
                    model: root.rows
                    delegate: Item {
                        id: dlg
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 52

                        Rectangle {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 1; bottomMargin: 1 }
                            radius: Tokens.radius.md
                            color: Theme.veil(root.sel === dlg.index ? Tokens.tint.soft
                                          : rowHover.hovered ? Tokens.tint.faint : 0)
                            border { width: root.sel === dlg.index ? 2 : 0; color: Theme.accent }
                            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
                        }
                        Rectangle {
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            width: 32; height: 32; radius: 16
                            color: Theme.chip
                            Item {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                Image {
                                    anchors.fill: parent
                                    visible: root.iconSrc(dlg.modelData) !== ""
                                    source: visible ? root.iconSrc(dlg.modelData) : ""
                                    sourceSize: Qt.size(36, 36)
                                    asynchronous: false
                                }
                                Glyph {
                                    anchors.centerIn: parent
                                    visible: root.iconSrc(dlg.modelData) === ""
                                    name: root.kindGlyph(dlg.modelData.kind)
                                    size: 16; color: Theme.text; stroke: 1.8
                                }
                            }
                        }
                        Text {
                            id: title
                            anchors { left: parent.left; leftMargin: 60; right: sub.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: dlg.modelData.text; textFormat: Text.PlainText
                            elide: Text.ElideRight
                            horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                            color: Theme.text
                        }
                        Text {
                            id: sub
                            anchors { right: tag.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: dlg.modelData.subtext; textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            width: Math.min(implicitWidth + 2, parent.width * 0.42)
                            horizontalAlignment: I18n.rtl ? Text.AlignLeft : Text.AlignRight
                            font { family: Theme.mono; pixelSize: Tokens.type.label }
                            color: Theme.subtext
                        }
                        // the kind tag: what this row is, quiet at the trailing edge
                        Text {
                            id: tag
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: root.kindTag(dlg.modelData.kind); textFormat: Text.PlainText
                            font { family: Theme.font; pixelSize: Tokens.type.caption }
                            color: Theme.subtext
                            opacity: 0.75
                        }
                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.runAt(dlg.index) }
                    }
                }
            }

            // ---- a quiet answer when nothing matched ------------------------------------------
            Item {
                visible: input.text !== "" && !search.busy && root.rows.length === 0
                width: parent.width; height: 96
                Text {
                    anchors.centerIn: parent
                    text: I18n.tr("Nothing found")
                    font { family: Theme.font; pixelSize: Tokens.type.body }
                    color: Theme.subtext
                }
            }

            Item { width: 1; height: 26 }
        }
    }

    // Handle: tap goes back, pulling it drives the island's curtain (same as the panels).
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

    component Keycap: Rectangle {
        property string label
        width: ktext.implicitWidth + 12; height: 18; radius: 6
        color: Theme.veil(Tokens.tint.faint)
        border { width: 1; color: Theme.rim }
        Text {
            id: ktext
            anchors.centerIn: parent
            text: parent.label; textFormat: Text.PlainText
            font { family: Theme.mono; pixelSize: 10; weight: Font.Medium }
            color: Theme.subtext
        }
    }
}
