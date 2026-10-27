import QtQuick
import AetherShared
import "."

// The large island's widget stack (YouTube Music today, more later).
// Normal: the widgets that are ON, in order - each in a Loader, so a removed widget is destroyed and
// nothing of it keeps running. Editing: compact rows instead of the widgets - drag a row to reorder,
// minus to remove, tap a pill under "Available widgets" to add. Every change is saved at once, and
// the island reacts to the saved list (Island.qml starts or stops the media backend).
Item {
    id: root
    property bool editing: false
    signal mediaRequested()

    readonly property int rowH: 56
    readonly property int gap: Tokens.space.sm
    readonly property int count: work.count
    readonly property var available: {
        const used = {}
        for (let i = 0; i < work.count; ++i) used[work.get(i).wid] = true
        return tiles.widgetCatalog.filter(c => !used[c.id])
    }
    function entry(id) { return tiles.widgetCatalog.find(c => c.id === id) || { id: id, label: id, glyph: "" } }

    visible: editing || count > 0
    implicitHeight: !visible ? 0 : editing ? editCol.implicitHeight : normalCol.implicitHeight
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

    ListModel { id: work }
    function load() {
        work.clear()
        for (const id of tiles.widgets) work.append({ wid: id })
    }
    function save() {
        const ids = []
        for (let i = 0; i < work.count; ++i) ids.push(work.get(i).wid)
        tiles.setWidgets(ids)
    }
    // Removing a row destroys the delegate that asked for it, so the follow-up (save) must run from
    // here, not from the delegate's own handler - code after work.remove() in there never runs.
    function removeAt(i) { work.remove(i); save() }
    function addId(id) { work.append({ wid: id }); save() }      // the tapped pill leaves the tray when this runs
    Component.onCompleted: load()
    Connections { target: tiles; function onWidgetsChanged() { if (!root.editing) root.load() } }
    onEditingChanged: if (!editing) load()

    // ---- normal -------------------------------------------------------------------------
    Column {
        id: normalCol
        visible: !root.editing
        width: parent.width
        spacing: Tokens.space.md
        Repeater {
            model: work
            delegate: Loader {
                required property string wid
                width: normalCol.width
                active: wid === "media"
                sourceComponent: MediaCard {
                    LayoutMirroring.enabled: false      // player controls and the progress bar keep their direction
                    LayoutMirroring.childrenInherit: true
                    onSearchRequested: root.mediaRequested()
                }
            }
        }
    }

    // ---- editing ------------------------------------------------------------------------
    MouseArea { visible: root.editing; anchors.fill: parent }    // nothing falls through to close-outside
    Column {
        id: editCol
        visible: root.editing
        width: parent.width
        spacing: Tokens.space.md
        Item {
            id: rows
            width: parent.width
            height: root.count > 0 ? root.count * root.rowH + (root.count - 1) * root.gap : 0
            property int target: -1
            function slotAt(py) { return Math.max(0, Math.min(root.count - 1, Math.round(py / (root.rowH + root.gap)))) }
            Rectangle {     // where the dragged row will land
                visible: rows.target >= 0
                y: rows.target * (root.rowH + root.gap)
                width: parent.width; height: root.rowH; radius: Tokens.radius.xl
                color: "transparent"
                border { width: 2; color: Theme.accent }
                Behavior on y { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
            }
            Repeater {
                model: work
                delegate: Item {
                    id: slot
                    required property int index
                    required property string wid
                    readonly property var info: root.entry(wid)
                    y: index * (root.rowH + root.gap)
                    width: rows.width; height: root.rowH
                    z: held.dragging ? 10 : 0
                    Behavior on y { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                    Item {
                        id: held
                        property bool dragging: drag.active
                        width: parent.width; height: parent.height
                        scale: dragging ? 1.03 : 1
                        opacity: dragging ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                        Behavior on y { enabled: !held.dragging; NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                        Rectangle { anchors.fill: parent; radius: Tokens.radius.xl; color: Theme.chip }
                        Glyph {
                            id: g
                            anchors { left: parent.left; leftMargin: Tokens.space.lg; verticalCenter: parent.verticalCenter }
                            name: slot.info.glyph; size: 20
                        }
                        Text {
                            anchors { left: g.right; leftMargin: Tokens.space.md; right: parent.right; rightMargin: Tokens.space.xl + 20; verticalCenter: parent.verticalCenter }
                            text: slot.info.label; textFormat: Text.PlainText; elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                            color: Theme.text
                        }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton }
                        DragHandler {
                            id: drag
                            target: held
                            yAxis.enabled: true
                            xAxis.enabled: false
                            onActiveChanged: {
                                if (active) return
                                const to = rows.target
                                rows.target = -1
                                held.y = 0
                                if (to >= 0 && to !== slot.index) { work.move(slot.index, to, 1); root.save() }
                            }
                            onTranslationChanged: if (active) rows.target = rows.slotAt(slot.y + held.y)
                        }
                        HoverHandler { cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                    }
                    Rectangle {      // remove badge
                        visible: !held.dragging
                        anchors { right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
                        width: 24; height: 24; radius: 12
                        color: Qt.rgba(1, 1, 1, rmTap.pressed ? Tokens.tint.strong : rmHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                        Glyph { anchors.centerIn: parent; name: "minus"; size: 12 }
                        HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: rmTap; onTapped: root.removeAt(slot.index) }
                    }
                }
            }
        }
        SectionLabel { visible: root.available.length > 0; width: parent.width; text: I18n.tr("Available widgets") }
        Flow {
            visible: root.available.length > 0
            width: parent.width
            spacing: Tokens.space.sm
            Repeater {
                model: root.available
                delegate: Rectangle {
                    required property var modelData
                    height: 34; width: pill.width + 2 * Tokens.space.md; radius: height / 2
                    color: Qt.rgba(1, 1, 1, addTap.pressed ? Tokens.tint.strong : addHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Row {
                        id: pill
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Glyph { name: "plus"; size: 12; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: modelData.label; textFormat: Text.PlainText
                            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                            color: Theme.text; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: addTap; onTapped: root.addId(modelData.id) }
                }
            }
        }
    }
}
