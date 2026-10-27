import QtQuick
import AetherShared

// Drop files, a link or text onto its parent to send them to the phone. Whether another app's drag
// reaches a layer-shell surface depends on the compositor; the panel's "Choose files" is the sure way.
Item {
    id: root
    property string deviceId
    readonly property bool dragging: area.containsDrag
    anchors.fill: parent
    DropArea {
        id: area
        anchors.fill: parent
        onEntered: (drag) => { drag.accepted = (drag.hasUrls || drag.hasText) && root.deviceId.length > 0 }
        onDropped: (drop) => {
            if (drop.hasUrls) connectModel.sendFiles(root.deviceId, drop.urls.map(u => u.toString()))
            else if (drop.hasText) connectModel.sendDropped(root.deviceId, drop.text)
            drop.accept()
        }
    }
}
