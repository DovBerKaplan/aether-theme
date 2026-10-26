import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "components"

// Aether Lock - SDDM greeter.
// Flow: resting lock screen (big clock) -> click / swipe up / any key -> auth
// panel slides up, wallpaper blurs, clock shrinks to the corner -> login.
Item {
    id: root
    width: 1920
    height: 1080

    // ---------- configuration ----------
    readonly property string fontFamily: config.font || "Inter"
    readonly property int idleTimeout: parseInt(config.idleTimeout || "30")
    property date now: new Date()
    readonly property bool dark: {
        if (config.mode === "dark") return true
        if (config.mode === "light") return false
        const h = now.getHours()
        return h < parseInt(config.dayStart || "7") || h >= parseInt(config.nightStart || "19")
    }
    readonly property string bgSet: config.background === "pearl" ? "pearl" : "aether"

    readonly property var palette: dark ? ({
        text: "#e1e2eb", subtext: "#b9cacb", accent: "#00f2fe", onAccent: "#00373a",
        glass: Qt.rgba(0.04, 0.05, 0.08, 0.45), glassHover: Qt.rgba(0.15, 0.17, 0.21, 0.6),
        glassBorder: Qt.rgba(1, 1, 1, 0.12), menu: Qt.rgba(0.07, 0.08, 0.11, 0.92),
        error: "#ffb4ab", scrim: Qt.rgba(0.04, 0.05, 0.08, 0.35)
    }) : ({
        text: "#191c1d", subtext: "#595f65", accent: "#1a1d20", onAccent: "#ffffff",
        glass: Qt.rgba(1, 1, 1, 0.55), glassHover: Qt.rgba(1, 1, 1, 0.78),
        glassBorder: Qt.rgba(1, 1, 1, 0.7), menu: Qt.rgba(0.98, 0.98, 0.99, 0.94),
        error: "#ba1a1a", scrim: Qt.rgba(1, 1, 1, 0.15)
    })

    // ---------- state ----------
    property bool authOpen: false
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property string message: ""

    function openAuth(initialText) {
        idleTimer.restart()
        if (!authOpen) authOpen = true
        if (initialText) password.text += initialText
        password.forceActiveFocus()
    }
    function closeAuth() {
        authOpen = false
        password.text = ""
        message = ""
        powerMenu.visible = false
        sessionMenu.visible = false
        lockFocus.forceActiveFocus()
    }
    function login() {
        if (busy) return
        busy = true
        message = ""
        sddm.login(userName(), password.text, sessionIndex)
    }
    function userName() {
        return userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1) || userModel.lastUser
    }
    function userRole(i, role) { return userModel.data(userModel.index(i, 0), Qt.UserRole + role) }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    Timer { id: idleTimer; interval: root.idleTimeout * 1000; onTriggered: if (password.text === "") root.closeAuth() }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.message = "Wrong password"
            password.selectAll()
            shake.restart()
        }
        function onLoginSucceeded() { exitAnim.start() }
    }

    // ---------- background ----------
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "backgrounds/" + root.bgSet + (root.dark ? "-night.png" : "-day.png")
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        visible: false
    }
    MultiEffect {
        id: wallFx
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.authOpen ? 1.0 : 0.0
        saturation: root.authOpen ? 0.15 : 0.0
        scale: root.authOpen ? 1.06 : 1.0
        Behavior on blur { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        color: root.palette.scrim
        opacity: root.authOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    // Everything that zooms away on successful login.
    Item {
        id: stage
        anchors.fill: parent

        // ---------- clock ----------
        Column {
            id: clock
            spacing: -6
            // Resting: big, left-aligned like an iPad lock screen. Auth: tucked top-left, smaller.
            x: root.authOpen ? 48 : 72
            y: root.authOpen ? 40 : root.height * 0.12
            scale: root.authOpen ? 0.55 : 1.0
            transformOrigin: Item.TopLeft
            Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }

            Text {
                text: Qt.formatDate(root.now, config.dateFormat || "dddd, MMMM d")
                color: root.palette.text
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: 28
                font.weight: Font.Medium
                leftPadding: 6
            }
            Text {
                text: Qt.formatTime(root.now, config.clockFormat || "HH:mm")
                color: root.palette.text
                font.family: root.fontFamily
                font.pixelSize: 168
                font.weight: Font.DemiBold
                font.letterSpacing: -6
            }
        }

        // Top-right status: host name + keyboard layout.
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 32
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: sddm.hostName
                color: root.palette.subtext
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Rectangle {
                visible: keyboard.layouts.length > 1
                width: kbText.implicitWidth + 40; height: 30; radius: 15
                color: root.palette.glass
                border.width: 1; border.color: root.palette.glassBorder
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: "keyboard"; size: 14; color: root.palette.text; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        id: kbText
                        text: keyboard.layouts.length ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
                        color: root.palette.text
                        font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
                }
            }
        }

        // ---------- resting hint ----------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 56
            spacing: 10
            opacity: root.authOpen ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Icon {
                id: hintLock
                anchors.horizontalCenter: parent.horizontalCenter
                name: "lock"; size: 20; color: root.palette.text
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: !root.authOpen
                    NumberAnimation { from: 0; to: -6; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: -6; to: 0; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            Rectangle {   // home-indicator style bar
                anchors.horizontalCenter: parent.horizontalCenter
                width: 140; height: 5; radius: 3
                color: root.palette.text
                opacity: 0.55
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Swipe up or start typing to unlock"
                color: root.palette.subtext
                font.family: root.fontFamily
                font.pixelSize: 13
            }
        }

        // ---------- auth panel ----------
        Column {
            id: auth
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.authOpen ? root.height - height - 120 : root.height + 40
            opacity: root.authOpen ? 1 : 0
            spacing: 14
            Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 300 } }

            // Users: current avatar large, others small beside it.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Repeater {
                    model: userModel
                    delegate: Item {
                        required property int index
                        required property string name
                        required property string realName
                        required property string icon
                        readonly property bool current: index === root.userIndex
                        width: current ? 96 : 56
                        height: 96
                        Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                        Rectangle {
                            id: avatarFrame
                            anchors.centerIn: parent
                            width: parent.width; height: width; radius: width / 2
                            color: root.palette.glass
                            border.width: current ? 2 : 1
                            border.color: current ? root.palette.accent : root.palette.glassBorder
                            opacity: current ? 1 : 0.7
                            Image {
                                id: face
                                anchors.fill: parent
                                anchors.margins: 3
                                source: icon
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }
                            Rectangle { id: faceMask; anchors.fill: face; radius: width / 2; visible: false; layer.enabled: true }
                            MultiEffect {
                                anchors.fill: face
                                source: face
                                maskEnabled: true
                                maskSource: faceMask
                                visible: face.status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: face.status !== Image.Ready
                                text: (realName || name).charAt(0).toUpperCase()
                                color: root.palette.text
                                font.family: root.fontFamily
                                font.pixelSize: parent.width * 0.42
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.userIndex = index; password.text = ""; root.message = ""; root.openAuth() }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userRole(root.userIndex, 2) || root.userName()   // RealNameRole
                color: root.palette.text
                font.family: root.fontFamily
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }

            // Password pill
            Item {
                id: pillWrap
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                height: 52

                SequentialAnimation {
                    id: shake
                    loops: 1
                    NumberAnimation { target: pill; property: "x"; to: -14; duration: 50 }
                    NumberAnimation { target: pill; property: "x"; to: 12; duration: 70 }
                    NumberAnimation { target: pill; property: "x"; to: -8; duration: 60 }
                    NumberAnimation { target: pill; property: "x"; to: 5; duration: 60 }
                    NumberAnimation { target: pill; property: "x"; to: 0; duration: 60 }
                }

                Rectangle {
                    id: pill
                    width: parent.width; height: parent.height
                    radius: height / 2
                    color: root.palette.glass
                    border.width: password.activeFocus ? 2 : 1
                    border.color: root.message ? root.palette.error
                                 : password.activeFocus ? root.palette.accent : root.palette.glassBorder
                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    TextField {
                        id: password
                        anchors.left: parent.left
                        anchors.right: actions.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 22
                        background: null
                        echoMode: reveal.checked ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        placeholderText: root.busy ? "Signing in…" : "Enter password"
                        placeholderTextColor: root.palette.subtext
                        color: root.palette.text
                        selectionColor: root.palette.accent
                        selectedTextColor: root.palette.onAccent
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        font.letterSpacing: reveal.checked ? 0 : 2
                        enabled: !root.busy
                        onTextEdited: { root.message = ""; idleTimer.restart() }
                        onAccepted: if (text.length) root.login()
                        Keys.onEscapePressed: root.closeAuth()
                    }

                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        GlassButton {
                            id: reveal
                            property bool checked: false
                            width: 40; height: 40
                            palette: root.palette
                            color: "transparent"; border.width: 0
                            icon: checked ? "eye-off" : "eye"
                            iconSize: 18
                            visible: password.text.length > 0
                            onClicked: { checked = !checked; password.forceActiveFocus() }
                        }
                        GlassButton {
                            width: 40; height: 40
                            palette: root.palette
                            accent: true
                            icon: "arrow"
                            iconSize: 18
                            opacity: password.text.length > 0 ? 1 : 0
                            scale: password.text.length > 0 ? 1 : 0.6
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                            onClicked: root.login()
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 18
                text: root.message ? root.message
                     : (keyboard.capsLock ? "Caps Lock is on" : "")
                color: root.message ? root.palette.error : root.palette.subtext
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        // ---------- corner buttons ----------
        GlassButton {
            id: sessionBtn
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 32
            palette: root.palette
            icon: "session"
            onClicked: { powerMenu.visible = false; sessionMenu.visible = !sessionMenu.visible; idleTimer.restart() }
        }
        Text {
            anchors.left: sessionBtn.right
            anchors.leftMargin: 12
            anchors.verticalCenter: sessionBtn.verticalCenter
            text: sessionModel.data(sessionModel.index(root.sessionIndex, 0), Qt.UserRole + 4) || ""  // NameRole
            color: root.palette.subtext
            font.family: root.fontFamily
            font.pixelSize: 13
            opacity: root.authOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        GlassButton {
            id: powerBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 32
            palette: root.palette
            icon: "power"
            onClicked: { sessionMenu.visible = false; powerMenu.visible = !powerMenu.visible; idleTimer.restart() }
        }

        GlassMenu {
            id: sessionMenu
            visible: false
            anchors.left: sessionBtn.left
            anchors.bottom: sessionBtn.top
            anchors.bottomMargin: 12
            palette: root.palette
            fontFamily: root.fontFamily
            current: root.sessionIndex
            items: {
                const out = []
                for (let i = 0; i < sessionModel.rowCount(); i++)
                    out.push({ text: sessionModel.data(sessionModel.index(i, 0), Qt.UserRole + 4) })
                return out
            }
            onPicked: (i) => { root.sessionIndex = i; visible = false }
        }
        GlassMenu {
            id: powerMenu
            visible: false
            anchors.right: powerBtn.right
            anchors.bottom: powerBtn.top
            anchors.bottomMargin: 12
            palette: root.palette
            fontFamily: root.fontFamily
            items: [
                { text: "Sleep", icon: "sleep", enabled: sddm.canSuspend },
                { text: "Restart", icon: "restart", enabled: sddm.canReboot },
                { text: "Shut down", icon: "power", enabled: sddm.canPowerOff }
            ]
            onPicked: (i) => {
                visible = false
                if (i === 0) sddm.suspend()
                else if (i === 1) sddm.reboot()
                else sddm.powerOff()
            }
        }
    }

    // ---------- input on the resting screen ----------
    Item {
        id: lockFocus
        anchors.fill: parent
        z: -1
        focus: true
        Keys.onPressed: (event) => {
            const ignored = [Qt.Key_Escape, Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta,
                             Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_unknown]
            if (ignored.indexOf(event.key) >= 0) return
            root.openAuth(event.text && event.text.trim().length ? event.text : "")
            event.accepted = true
        }
    }
    // Click or swipe up anywhere on the resting screen opens the auth panel.
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: !root.authOpen
        property real startY: 0
        onPressed: (m) => startY = m.y
        onClicked: root.openAuth()
        onReleased: (m) => { if (startY - m.y > 80) root.openAuth() }   // swipe up
        onWheel: (w) => { if (w.angleDelta.y < 0) root.openAuth() }
    }
    // Clicking empty space while auth is open closes menus.
    MouseArea {
        anchors.fill: parent
        z: -2
        enabled: root.authOpen
        onClicked: { powerMenu.visible = false; sessionMenu.visible = false; password.forceActiveFocus() }
    }

    // ---------- success transition ----------
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 350 }
        NumberAnimation { target: stage; property: "scale"; to: 1.08; duration: 450; easing.type: Easing.InCubic }
    }

    Component.onCompleted: lockFocus.forceActiveFocus()
}
