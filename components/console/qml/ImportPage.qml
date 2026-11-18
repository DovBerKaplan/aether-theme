import QtQuick
import AetherShared

// One-tap setup: read the user's ~/.ssh/config and let them tick which hosts to keep.
PanelScaffold {
    id: root
    bottomInset: 14
    property var candidates: []
    property var picked: ({})

    function reload() {
        candidates = store.importCandidates()
        picked = {}
    }

    title: I18n.tr("Import hosts")
    subtitle: "~/.ssh/config"
    footerHeight: 48

    footer: Row {
        spacing: Tokens.space.sm
        anchors { left: parent.left; right: parent.right; leftMargin: Tokens.space.md; rightMargin: Tokens.space.md }
        Button {
            text: I18n.tr("Import")
            kind: "filled"
            enabled: Object.keys(root.picked).length > 0
            onClicked: {
                const rows = root.candidates.filter(c => root.picked[c.name])
                store.importSessions(rows)
                root.backRequested()
            }
        }
        Button {
            text: Object.keys(root.picked).length === root.candidates.length && root.candidates.length > 0
                  ? I18n.tr("Clear selection") : I18n.tr("Select all")
            onClicked: {
                const all = Object.keys(root.picked).length !== root.candidates.length
                const p = {}
                if (all) root.candidates.forEach(c => p[c.name] = true)
                root.picked = p
            }
        }
    }

    Column {
        width: parent.width
        spacing: Tokens.space.xs

        // candidates are already filtered against what is saved
        Text {
            visible: root.candidates.length === 0
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            topPadding: Tokens.space.lg
            text: I18n.tr("Nothing to import - no new hosts in ~/.ssh/config")
            wrapMode: Text.Wrap
            font { family: Theme.font; pixelSize: Tokens.type.body }
            color: Theme.subtext
        }
        Repeater {
            model: root.candidates
            delegate: ListRow {
                required property var modelData
                width: parent ? parent.width : 0
                title: modelData.name
                subtitle: I18n.ltr((modelData.user ? modelData.user + "@" : "") + modelData.host
                                   + (modelData.port && modelData.port !== "22" ? ":" + modelData.port : ""))
                leadingGlyphSource: "assets/glyphs/server.svg"
                onClicked: {
                    const p = Object.assign({}, root.picked)
                    if (p[modelData.name]) delete p[modelData.name]
                    else p[modelData.name] = true
                    root.picked = p
                }
                trailing: [
                    Rectangle {
                        width: 20; height: 20; radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.picked[modelData.name] ? Theme.accent : Theme.chip
                        border { width: root.picked[modelData.name] ? 0 : 1; color: Theme.rim }
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            visible: !!root.picked[modelData.name]
                            font.pixelSize: Tokens.type.label
                            color: Theme.onAccent
                        }
                    }
                ]
            }
        }
    }
}
