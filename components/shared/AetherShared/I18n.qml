pragma Singleton
import QtQuick
import "strings_he.js" as He

// Interface language. `tr("English text")` returns the text in the current language (the English
// text is the key, and also the fallback); `f("%1 connected", n)` fills placeholders after
// translating, so word order can differ. Both read `lang`, so every binding that calls them
// re-evaluates the moment the language changes - no restart, no reload.
QtObject {
    property string lang: "en"                       // set from the saved preference by the island
    readonly property bool rtl: lang === "he"
    readonly property var locale: Qt.locale(lang === "he" ? "he_IL" : "en_US")
    // [{code, short, name}] - the bar button cycles through these
    readonly property var languages: [
        { code: "en", short: "EN", name: "English" },
        { code: "he", short: "עב", name: "עברית" }
    ]
    function tr(s) {
        const t = lang === "he" ? He.dict[s] : undefined
        return t !== undefined ? t : s
    }
    function f(s) {
        let t = tr(s)
        for (let i = 1; i < arguments.length; ++i) t = t.split("%" + i).join(arguments[i])
        return t
    }
    function next() {
        for (let i = 0; i < languages.length; ++i)
            if (languages[i].code === lang) return languages[(i + 1) % languages.length].code
        return "en"
    }
}
