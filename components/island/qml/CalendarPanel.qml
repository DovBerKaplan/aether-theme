import QtQuick
import AetherShared
import "."

// Calendar & timer (docs/PANELS-SPEC.md section 10): a month grid with today ringed in accent
// (a ring, not a fill), and the island's countdown timer. Events and world clocks are later.
PanelScaffold {
    id: root
    property string page: ""
    property var timer: null
    signal pageRequested(string page)
    signal closeRequested()

    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    readonly property int first: Qt.locale().firstDayOfWeek % 7   // Qt: 1 Mon..7 Sun -> 0 Sun..6 Sat
    readonly property int lead: (new Date(year, month, 1).getDay() - first + 7) % 7
    readonly property int days: new Date(year, month + 1, 0).getDate()
    function step(d) { const n = new Date(year, month + d, 1); year = n.getFullYear(); month = n.getMonth() }

    title: Qt.formatDate(today, "dddd, MMMM d")
    subtitle: Qt.formatDate(today, "yyyy")
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.today = new Date() }

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.xs
        Row {
            width: parent.width; height: 40
            Item {
                width: 40; height: 40
                Text { anchors.centerIn: parent; text: "‹"; font { family: Theme.font; pixelSize: Tokens.type.heading } color: Theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.step(-1) }
            }
            Text {
                width: parent.width - 80; height: 40
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: Qt.locale().monthName(root.month) + " " + root.year
                font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                color: Theme.text
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.year = root.today.getFullYear(); root.month = root.today.getMonth() } }
            }
            Item {
                width: 40; height: 40
                Text { anchors.centerIn: parent; text: "›"; font { family: Theme.font; pixelSize: Tokens.type.heading } color: Theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.step(1) }
            }
        }
        Grid {
            id: grid
            columns: 7
            width: parent.width
            readonly property real cell: width / 7
            Repeater {   // weekday names
                model: 7
                delegate: Text {
                    required property int index
                    width: grid.cell; height: 28
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().dayName((root.first + index) % 7, Locale.NarrowFormat)
                    font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
                    color: Theme.subtext
                }
            }
            Repeater {
                model: 42
                delegate: Item {
                    required property int index
                    readonly property int day: index - root.lead + 1
                    readonly property bool valid: day >= 1 && day <= root.days
                    readonly property bool isToday: valid && day === root.today.getDate() && root.month === root.today.getMonth() && root.year === root.today.getFullYear()
                    width: grid.cell; height: 36
                    visible: index < root.lead + root.days || index < 35
                    Rectangle {
                        anchors.centerIn: parent
                        width: 32; height: 32; radius: 16
                        color: "transparent"
                        border { width: isToday ? 1.5 : 0; color: Theme.accent }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: valid ? day : ""
                        font { family: Theme.mono; pixelSize: Tokens.type.label; weight: isToday ? Font.DemiBold : Font.Normal }
                        color: isToday ? Theme.accent : Theme.text
                    }
                }
            }
        }
        SectionLabel { width: parent.width; text: "Timer" }
        TimerRow { visible: root.timer !== null; width: parent.width; timer: root.timer }
        Item { width: 1; height: Tokens.space.sm }
    }
}
