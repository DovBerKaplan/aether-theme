.pragma library

// BlueZ "Icon" strings (org.bluez.Device1) mapped onto the island's glyph set, plus the family
// name for a friendly label. Anything unknown falls back to the plain bluetooth mark.
var glyphs = {
    "audio-headset": "headphones", "audio-headphone": "headphones", "audio-earbuds": "headphones",
    "audio-speaker": "speaker", "audio-card": "speaker",
    "audio-input-microphone": "mic",
    "input-keyboard": "keyboard",
    "input-mouse": "mouse",
    "input-gamepad": "gamepad",
    "input-tablet": "tablet", "input-drawing-tablet": "tablet", "graphics-tablet": "tablet",
    "phone": "phone",
    "watch": "watch",
    "printer": "printer", "scanner": "printer",
    "computer": "desktop", "video-display": "desktop",
    "camera-photo": "camera", "camera-video": "camera"
}

// English label per glyph family; translated through I18n at the call site.
var labels = {
    headphones: "Headphones", speaker: "Speaker", mic: "Microphone", keyboard: "Keyboard",
    mouse: "Mouse", gamepad: "Gamepad", tablet: "Tablet", phone: "Phone", watch: "Watch",
    printer: "Printer", desktop: "Computer", camera: "Camera", bluetooth: "Device"
}

function glyph(icon) { return glyphs[icon] || "bluetooth" }
function label(icon) { return labels[glyph(icon)] }
