import QtQuick
import QtQuick.Controls
import AetherShared

// The bottom sheet after a selection: thumbnail, recognised text, and what to do with them.
Item {
    id: root
    property bool open: false
    property string text: ""
    property bool busy: false
    property bool ocrAvailable: true
    property int cropSerial: 0

    property string translation: ""
    property string translationNote: ""
    property bool translating: false
    property int reqId: 0

    implicitWidth: 640
    implicitHeight: col.implicitHeight + 36
    height: implicitHeight
    opacity: open ? 1 : 0
    visible: opacity > 0.01
    transform: Translate { y: root.open ? 0 : 40; Behavior on y { SpringAnimation { spring: 3.6; damping: 0.4 } } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    onTextChanged: { translation = ""; translationNote = "" }
    Connections {
        target: lens
        function onTranslated(id, out, src, tgt) {
            if (id !== root.reqId) return
            root.translating = false
            root.translation = out
            root.translationNote = src.toUpperCase() + " → " + tgt.toUpperCase()
        }
        function onTranslateFailed(id) { if (id === root.reqId) { root.translating = false; root.translation = I18n.tr("Couldn't translate"); root.translationNote = "" } }
    }

    CardSurface { anchors.fill: parent; radius: Tokens.radius.card }

    Column {
        id: col
        x: 18; y: 18
        width: parent.width - 36
        spacing: Tokens.space.md

        Row {
            width: parent.width
            spacing: 14
            Rectangle {
                width: 84; height: 84; radius: 14; clip: true
                color: Qt.rgba(1, 1, 1, 0.06)
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: root.open ? "image://lens/crop/" + root.cropSerial : ""
                    cache: false
                    sourceSize.width: 168
                    sourceSize.height: 168
                }
            }
            Column {
                width: parent.width - 98
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {   // skeleton while OCR runs
                    visible: root.busy && root.text === ""
                    width: parent.width * 0.8; height: 14; radius: 7
                    color: Qt.rgba(1, 1, 1, 0.12)
                    SequentialAnimation on opacity {
                        running: parent.visible; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Text {
                    visible: root.text !== ""
                    width: parent.width
                    text: root.text
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: Tokens.type.title
                    color: Theme.text
                    horizontalAlignment: lens.isRtlText(root.text) ? Text.AlignRight : Text.AlignLeft
                    LayoutMirroring.enabled: false
                }
                Text {
                    visible: !root.busy && root.text === "" && root.ocrAvailable
                    text: I18n.tr("No text in this area")
                    font.family: Theme.font; font.pixelSize: 14; color: Theme.subtext
                }
                Text {
                    visible: !root.ocrAvailable
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: I18n.tr("Install tesseract for text") + ":  sudo apt install tesseract-ocr tesseract-ocr-heb"
                    font.family: Theme.font; font.pixelSize: Tokens.type.label; color: Theme.subtext
                }
            }
        }

        Column {
            visible: root.translation !== "" || root.translating
            width: parent.width
            spacing: Tokens.space.xs
            Text {
                text: root.translating ? I18n.tr("Translating…") : root.translationNote
                font.family: Theme.font; font.pixelSize: Tokens.type.caption; color: Theme.subtext
            }
            Text {
                visible: root.translation !== ""
                width: parent.width
                text: root.translation
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: Tokens.type.title; color: Tokens.role.lens.primary
                horizontalAlignment: lens.isRtlText(root.translation) ? Text.AlignRight : Text.AlignLeft
                LayoutMirroring.enabled: false
            }
        }

        Flow {
            width: parent.width
            spacing: Tokens.space.sm
            Chip {
                primary: true
                text: I18n.tr("Search with Lens")
                lensMark: true
                onClicked: lens.searchImage(false)
            }
            Chip { visible: root.text !== ""; text: I18n.tr("Search"); icon: "edit-find"; onClicked: lens.searchText(root.text) }
            Chip {
                visible: root.text !== ""
                text: I18n.tr("Translate"); translateMark: true
                onClicked: { root.translating = true; root.reqId += 1; lens.translate(root.reqId, root.text) }
            }
            Chip { visible: root.translation !== "" && root.translationNote !== ""; text: I18n.tr("Open in Translate"); icon: "internet-web-browser"; onClicked: lens.openTranslateWeb(root.text) }
            Chip { visible: root.text !== ""; text: I18n.tr("Copy text"); icon: "edit-copy"; onClicked: lens.copyText(root.text) }
            Chip { text: I18n.tr("Copy image"); icon: "image-x-generic"; onClicked: lens.copyImage() }
        }
    }
}
