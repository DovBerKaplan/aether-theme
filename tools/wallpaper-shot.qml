// Render one aether wallpaper shader to a PNG, off the live desktop:
//
//     QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl qml6 tools/wallpaper-shot.qml -- SHADER.qsb OUT.png \
//         [accent=#3584e4] [dark=1] [time=0] [width=1920] [height=1080] [bench=0]
//
// bench=N instead renders the field over and over for N seconds (each grab forces a real render,
// read back included), advancing time, and prints the renders per second - a rough cost to
// compare the fields by.
// The uniforms match the wallpapers' ShaderEffect in plasmoids/org.aether.*/contents/ui/main.qml.
import QtQuick
import QtQuick.Window

Window {
    id: win

    readonly property var args: {
        const a = Qt.application.arguments
        const i = a.indexOf("--")
        return i < 0 ? [] : a.slice(i + 1)
    }
    function opt(name, fallback) {
        for (const s of args.slice(2))
            if (s.startsWith(name + "=")) return s.slice(name.length + 1)
        return fallback
    }

    width: Number(opt("width", 1920))
    height: Number(opt("height", 1080))
    visible: true
    color: "black"

    ShaderEffect {
        id: fx
        anchors.fill: parent
        fragmentShader: "file://" + win.args[0]
        property color accent: win.opt("accent", "#3584e4")
        property real dark: Number(win.opt("dark", 1))
        property real aspect: width / Math.max(1, height)
        property real px: 1 / Math.max(1, height)
        property real time: Number(win.opt("time", 0))
    }

    readonly property real bench: Number(opt("bench", 0))
    property int frames: 0
    property real started: 0
    function benchStep() {
        if (win.frames === 0) win.started = Date.now()
        const sec = (Date.now() - win.started) / 1000
        if (win.frames > 0 && sec >= win.bench) { console.log("fps", (win.frames / sec).toFixed(1)); Qt.quit(); return }
        win.frames++
        fx.time += 0.1
        fx.grabToImage(() => win.benchStep())   // each grab forces a real render of the field
    }

    Timer {
        interval: 300
        running: true
        onTriggered: win.bench > 0 ? win.benchStep()
                                   : fx.grabToImage(r => { r.saveToFile(win.args[1]); Qt.quit() })
    }
}
