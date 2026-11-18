import QtQuick
import AetherShared

// A status dot for sessions: accent while alive, a blinking orange while the window is
// down or the network is gone (the tmux on the server kept the work either way).
Rectangle {
    property bool down: false
    width: 6; height: 6; radius: 3
    color: down ? Tokens.role.island.attention : Theme.accent
    SequentialAnimation on opacity {
        running: down; loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: 480 }
        NumberAnimation { to: 1; duration: 480 }
    }
}
