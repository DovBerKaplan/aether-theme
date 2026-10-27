import QtQuick
import AetherShared
import "."
import "HebrewCalendar.js" as Heb

// Calendar (docs/PANELS-SPEC.md section 10): a month grid with today ringed in accent
// (a ring, not a fill). Events and world clocks are later.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()

    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    readonly property int first: I18n.locale.firstDayOfWeek % 7   // Qt: 1 Mon..7 Sun -> 0 Sun..6 Sat
    readonly property int lead: (new Date(year, month, 1).getDay() - first + 7) % 7
    readonly property int days: new Date(year, month + 1, 0).getDate()
    function step(d) { const n = new Date(year, month + d, 1); year = n.getFullYear(); month = n.getMonth() }

    title: I18n.lang === "he" ? I18n.locale.toString(today, "dddd, d MMMM") : Qt.formatDate(today, "dddd, MMMM d")
    readonly property bool heb: tiles.hebrewDates
    // Hebrew months this Gregorian month touches, e.g. "חשוון – כסלו תשפ״ז"
    readonly property string hebMonth: {
        const a = Heb.fromGregorian(year, month, 1), b = Heb.fromGregorian(year, month, days)
        const na = Heb.monthName(a.year, a.month), nb = Heb.monthName(b.year, b.month)
        return (na === nb ? na : na + " – " + nb) + " " + Heb.yearLetters(b.year)
    }
    subtitle: heb ? Heb.format(Heb.fromGregorian(today.getFullYear(), today.getMonth(), today.getDate())) : Qt.formatDate(today, "yyyy")
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.f("Hebrew dates: %1", root.heb ? I18n.tr("On") : I18n.tr("Off")); anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: tiles.hebrewDates = !tiles.hebrewDates }
        }
    ]
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.today = new Date() }

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.xs
        Row {
            width: parent.width; height: 40
            Item {
                width: 40; height: 40
                Text { anchors.centerIn: parent; text: I18n.rtl ? "›" : "‹"; font { family: Theme.font; pixelSize: Tokens.type.heading } color: Theme.text }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.step(-1) }
            }
            Column {
                width: parent.width - 80; height: 40
                anchors.verticalCenter: undefined
                Text {
                    width: parent.width; height: root.heb ? 22 : 40
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: root.heb ? Text.AlignBottom : Text.AlignVCenter
                    text: I18n.locale.monthName(root.month) + " " + root.year
                    font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                    color: Theme.text
                }
                Text {
                    visible: root.heb
                    width: parent.width; height: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hebMonth
                    font { family: Theme.font; pixelSize: Tokens.type.caption }
                    color: Theme.subtext
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.year = root.today.getFullYear(); root.month = root.today.getMonth() } }
            }
            Item {
                width: 40; height: 40
                Text { anchors.centerIn: parent; text: I18n.rtl ? "‹" : "›"; font { family: Theme.font; pixelSize: Tokens.type.heading } color: Theme.text }
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
                    text: I18n.locale.dayName((root.first + index) % 7, Locale.NarrowFormat)
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
                    readonly property var h: valid && root.heb ? Heb.fromGregorian(root.year, root.month, day) : null
                    width: grid.cell; height: root.heb ? 46 : 36
                    visible: index < root.lead + root.days || index < 35
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: root.heb ? -6 : 0 }
                        width: 32; height: 32; radius: 16
                        color: "transparent"
                        border { width: isToday ? 1.5 : 0; color: Theme.accent }
                    }
                    Text {   // Hebrew day under the number; the first of a Hebrew month shows its name
                        visible: valid && root.heb
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                        text: h ? (h.day === 1 ? Heb.monthName(h.year, h.month) : Heb.dayLetters(h.day)) : ""
                        font { family: Theme.font; pixelSize: Tokens.type.caption }
                        color: h && h.day === 1 ? Theme.accent : Theme.subtext
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: root.heb ? -6 : 0 }
                        text: valid ? day : ""
                        font { family: Theme.mono; pixelSize: Tokens.type.label; weight: isToday ? Font.DemiBold : Font.Normal }
                        color: isToday ? Theme.accent : Theme.text
                    }
                }
            }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
