// The wallpaper's page in Plasma's wallpaper dialog. The accent itself comes from the island's Color
// panel (aether-accent-sync writes it here), so only the mode is a choice.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property string cfg_Mode: "auto"
    property string cfg_AccentColor

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.color", "Mode:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: "Follow the colour scheme", value: "auto" },
            { text: "Dark", value: "dark" },
            { text: "Light", value: "light" }
        ]
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_Mode))
        onActivated: cfg_Mode = currentValue
    }
}
