import QtQuick
import AetherShared
import "."

// Live-test fixtures (AETHER_CONSOLE_TEST_DETAIL): cont | session | split | splitlocal.
// They drive the shelf the way a user would, so screenshots can be taken without a mouse.
Item {
    id: fx
    property var shell
    Timer {
        id: detailTimer
        interval: 2000
        onTriggered: {
            if (testDetail === "cont" && discovery.containers.length > 0) {
                fx.shell.openDetail("cont", discovery.containers[0])
                logsTimer.restart()
            }
            else if (testDetail === "splitlocal") {
                fx.shell.openTab("local", "local:1", I18n.tr("Local terminal"), {}, "")
                splitTimer.restart()
            }
            else if (testDetail === "session" || testDetail === "split") {
                // the fixture host resolves through ~/.ssh/config - no saved session needed
                fx.shell.openDetail("session", { id: "fixture", name: "kot-prod", host: "kot-prod" })
                logsTimer.restart()
            }
        }
    }
    Timer {
        id: logsTimer
        interval: 3000
        onTriggered: {
            const host = { id: "fixture", name: "kot-prod", host: "kot-prod" }
            if (testDetail === "cont") {
                fx.shell.openTab("files", "files:fixture0", "go2rtc · " + I18n.tr("Files"),
                    { id: "fixture", name: discovery.containers[0].name, host: discovery.containers[0].name }, "session")
            } else if (testDetail === "session") {
                fx.shell.openTab("term", "term:fixture", "kot-prod · " + I18n.tr("Terminal"), host, "session")
            } else if (testDetail === "split") {
                fx.shell.openTab("term", "term:fixture", "kot-prod · " + I18n.tr("Terminal"), host, "session")
                splitTimer.restart()
            }
        }
    }
    Timer {
        id: splitTimer
        interval: 2500
        property int step: 0
        repeat: true
        onTriggered: {
            const host = { id: "fixture", name: "kot-prod", host: "kot-prod" }
            step++
            if (testDetail === "splitlocal") {   // three local terminals: right, then below the right one
                fx.shell.openTab("local", "local:" + (step + 1), I18n.tr("Local terminal") + " " + (step + 1), {}, "")
                fx.shell.dropTab("local:" + (step + 1), step === 1 ? "g1" : fx.shell.groupIds[fx.shell.groupIds.length - 1], step === 1 ? "right" : "bottom")
                if (step >= 2) stop()
                return
            }
            if (step === 1) {   // a files tab, dropped on the terminal pane's right edge
                fx.shell.openTab("files", "files:fixture", "kot-prod · " + I18n.tr("Files"), host, "session")
                fx.shell.dropTab("files:fixture", fx.shell.focusGroup, "right")
            } else if (step === 2) {   // a second terminal under the files
                fx.shell.openTab("term", "term:fixture:2", "kot-prod · " + I18n.tr("Terminal") + " 2", host, "session")
                fx.shell.dropTab("term:fixture:2", fx.shell.focusGroup, "bottom")
            } else stop()
        }
    }
    Component.onCompleted: if (testDetail.length > 0) detailTimer.restart()
}
