import QtQuick
import AetherShared
import AetherConsole
import "."

// A files tab: the sftp browser, one backend per view. Each tab remembers its folder.
Item {
    id: view
    property var shell
    property var tab
    property string gid
    property bool active: true

    Sftp { id: sftp }
    property bool opened: false

    function hsize(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return Math.round(b / 1024) + " KB"
        return b + " B"
    }
    // KIO resolves the host through ~/.ssh/config, so a bare alias works too
    function sftpUrl(path) {
        const d = tab.data
        const auth = d.user ? encodeURIComponent(d.user) + "@" : ""
        const port = d.port && d.port !== "22" ? ":" + d.port : ""
        return "sftp://" + auth + d.host + port + path
    }
    function navigate(path) {
        sftp.list(path)
        shell.setTabPath(tab.id, path)
    }
    // connects on first use; afterwards the folder the tab remembers is restored
    function sync() {
        if (!active || !shell.open) return
        if (!opened) { sftp.open(tab.data); opened = true }
        if (tab.path && tab.path !== sftp.path) sftp.list(tab.path)
    }
    onActiveChanged: sync()
    Connections { target: view.shell; function onOpenChanged() { view.sync() } }
    Component.onCompleted: sync()


    // a tab owns the whole glass: path bar on top, the listing fills the rest,
    // the upload bar is pinned to the bottom
    Column {
        id: filesTop
        width: parent.width
        spacing: Tokens.space.xs
        Row {
            x: Tokens.space.md
            width: parent.width - 2 * Tokens.space.md
            height: 34
            spacing: Tokens.space.xs
            ActionGlyph { glyph: "up"; anchors.verticalCenter: parent.verticalCenter; onAct: view.navigate(sftp.path + "/..") }
            ActionGlyph { glyph: "folder"; anchors.verticalCenter: parent.verticalCenter; onAct: launcher.browseRemote(view.sftpUrl(sftp.path)) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                text: I18n.ltr(sftp.path)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                font { family: Theme.mono; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
        }
        LinearProgress {
            x: Tokens.space.md
            width: parent.width - 2 * Tokens.space.md
            running: sftp.busy
        }
        Text {
            visible: sftp.err.length > 0
            x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
            text: sftp.err
            wrapMode: Text.WrapAnywhere
            font { family: Theme.mono; pixelSize: Tokens.type.caption }
            color: Tokens.role.island.negative
        }
    }
    Item {
        anchors { top: filesTop.bottom; topMargin: Tokens.space.xs; bottom: filesBar.top; bottomMargin: Tokens.space.sm
                  left: parent.left; right: parent.right; leftMargin: Tokens.space.sm; rightMargin: Tokens.space.sm }
        ListView {
            id: fileList
            anchors.fill: parent
            clip: true
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            LayoutMirroring.enabled: false
            model: sftp.entries
            delegate: ListRow {
                required property var modelData
                width: fileList.width
                title: modelData.name
                subtitle: modelData.dir ? I18n.tr("Folder") + " · " + I18n.ltr(modelData.date)
                                        : I18n.ltr(view.hsize(modelData.size) + "  ·  " + modelData.date)
                leadingGlyphSource: Qt.resolvedUrl(modelData.dir ? "assets/glyphs/folder.svg"
                                                                 : "assets/glyphs/file.svg")
                onClicked: if (modelData.dir) view.navigate(sftp.path + "/" + modelData.name)
                trailing: [
                    ActionGlyph {
                        glyph: "edit"
                        visible: !modelData.dir
                        onAct: launcher.editRemote(view.sftpUrl(sftp.path + "/" + modelData.name))
                    },
                    ActionGlyph {
                        glyph: "download"
                        visible: !modelData.dir
                        onAct: sftp.download(modelData.name)
                    }
                ]
            }
        }
        DropArea {
            id: fileDrop
            anchors.fill: parent
            onEntered: (d) => d.accepted = d.hasUrls
            onDropped: (d) => { if (d.hasUrls) d.urls.forEach(u => sftp.upload(u)); d.accept() }
        }
        Text {
            anchors.centerIn: parent
            visible: fileDrop.containsDrag
            text: I18n.tr("Drop to upload here")
            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
            color: Theme.accent
        }
        Text {
            anchors.centerIn: parent
            visible: sftp.entries.length === 0 && !sftp.busy && sftp.err.length === 0
            text: I18n.tr("Empty folder")
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
    }
    Row {
        id: filesBar
        anchors { left: parent.left; leftMargin: Tokens.space.md; bottom: parent.bottom; bottomMargin: Tokens.space.md }
        spacing: Tokens.space.sm
        Button { text: I18n.tr("Upload…"); onClicked: sftp.chooseUpload() }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("or drop files here")
            font { family: Theme.font; pixelSize: Tokens.type.caption }
            color: Theme.subtext
        }
    }
}
