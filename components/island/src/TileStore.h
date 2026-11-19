// The large island's tile set: which tiles exist, which are shown and in what order (saved in
// ~/.config/aetherislandrc, [Tiles] Order), and the few tile actions that have no home of
// their own (keep awake, microphone mute, screenshot, screen recording, airplane memory).
// What a tile *shows* is decided in QML (Tile.qml) from the models that already exist.
#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QFile>
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <signal.h>         // ::kill - the vibe session's pid liveness

class TileStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList order READ order NOTIFY orderChanged)
    Q_PROPERTY(QStringList sizes READ sizes NOTIFY orderChanged)             // "id:2" / "id:3" for tiles wider than the default one cell
    Q_PROPERTY(bool accentCustom READ accentCustom NOTIFY accentChanged)      // a colour was chosen; otherwise the theme's own
    Q_PROPERTY(int accentHue READ accentHue NOTIFY accentChanged)             // 0..359
    Q_PROPERTY(qreal accentLight READ accentLight NOTIFY accentChanged)       // HSL lightness, 0.25..0.80 (darker .. lighter)
    Q_PROPERTY(qreal accentSat READ accentSat NOTIFY accentChanged)           // HSL saturation, 0.15..1 (faded .. vivid)
    Q_PROPERTY(QVariantList catalog READ catalog CONSTANT)           // every tile that can be shown
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)   // interface language: "en" | "he"
    Q_PROPERTY(bool hebrewDates READ hebrewDates WRITE setHebrewDates NOTIFY hebrewDatesChanged)   // Calendar panel
    Q_PROPERTY(QStringList widgets READ widgets NOTIFY widgetsChanged)         // large-island widgets that are on, in order
    Q_PROPERTY(QVariantList widgetCatalog READ widgetCatalog CONSTANT)          // every widget that can be on
    Q_PROPERTY(bool keepAwake READ keepAwake NOTIFY stateChanged)
    Q_PROPERTY(bool consoleEarOn READ consoleEarOn NOTIFY stateChanged)   // the console's resting tab is shown ([Console] EarShown; aether-console reads it)
    Q_PROPERTY(bool lensOn READ lensOn NOTIFY stateChanged)     // Circle to Search is enabled ([Lens] Enabled; aether-lens and the dock read it)
    Q_PROPERTY(bool vibeOn READ vibeOn NOTIFY stateChanged)     // the aether-vibe session (lid-safe agents) is running
    Q_PROPERTY(bool micMuted READ micMuted NOTIFY stateChanged)
    Q_PROPERTY(bool wifiBefore READ wifiBefore NOTIFY stateChanged)  // radios as they were before airplane mode
    Q_PROPERTY(bool bluetoothBefore READ bluetoothBefore NOTIFY stateChanged)
    Q_PROPERTY(QString wallpaperStyle READ wallpaperStyle NOTIFY wallpaperChanged)   // the active aether wallpaper ([Wallpaper] Style)
    Q_PROPERTY(bool wallpaperAnimate READ wallpaperAnimate NOTIFY wallpaperChanged)  // its Animate key ([Wallpaper] Animate)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers CONSTANT)   // the family: id + English title for the picker
    Q_PROPERTY(QString wallpaperMark READ wallpaperMark NOTIFY wallpaperChanged)   // what the centre wears ([Wallpaper] Mark; see Mark.qml)
    Q_PROPERTY(QVariantList markLogos READ markLogos CONSTANT)      // every logo the wallpapers know: {slug, path} (logos.js)
    Q_PROPERTY(QString distroLogo READ distroLogo CONSTANT)         // this distribution's logo path, "" if none is known
    Q_PROPERTY(bool canImportMark READ canImportMark CONSTANT)      // kdialog is there to choose an image with

public:
    explicit TileStore(QObject *parent = nullptr)
        : QObject(parent)
        , m_settings(QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat)
    {
        for (const QString &id : m_settings.value(QStringLiteral("Tiles/Order")).toStringList()) {
            if (known(id) && !m_order.contains(id)) {
                m_order << id;
            }
        }
        if (m_order.isEmpty()) {
            m_order = defaults();
        }
        if (!m_settings.contains(QStringLiteral("Tiles/VibeAdded"))) {        // one-time: surface the new tile to existing setups
            m_settings.setValue(QStringLiteral("Tiles/VibeAdded"), true);
            if (!m_order.contains(QLatin1String("vibe"))) {
                m_order << QStringLiteral("vibe");
                m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
            }
            m_settings.sync();
        }
        m_lensOn = m_settings.value(QStringLiteral("Lens/Enabled"), true).toBool();
        m_consoleEarOn = m_settings.value(QStringLiteral("Console/EarShown"), true).toBool();
        if (!m_settings.contains(QStringLiteral("Tiles/LensAdded"))) {        // one-time: surface the Circle to Search tile
            m_settings.setValue(QStringLiteral("Tiles/LensAdded"), true);
            if (!m_order.contains(QLatin1String("lens"))) {
                m_order << QStringLiteral("lens");
                m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
            }
            m_settings.sync();
        }
        if (!m_settings.contains(QStringLiteral("Tiles/WallpaperAdded"))) {   // one-time: surface the wallpaper picker tile
            m_settings.setValue(QStringLiteral("Tiles/WallpaperAdded"), true);
            if (!m_order.contains(QLatin1String("wallpaper"))) {
                m_order << QStringLiteral("wallpaper");
                m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
            }
            m_settings.sync();
        }
        m_wallpaper = m_settings.value(QStringLiteral("Wallpaper/Style"), QStringLiteral("org.aether.ribbons")).toString();
        if (!wallpaperIds().contains(m_wallpaper)) {
            m_wallpaper = QStringLiteral("org.aether.ribbons");
        }
        m_wallpaperAnimate = m_settings.value(QStringLiteral("Wallpaper/Animate"), true).toBool();
        m_wallpaperMark = m_settings.value(QStringLiteral("Wallpaper/Mark")).toString();
        loadLogos();
        if (m_settings.value(QStringLiteral("Tiles/SizesSet")).toBool()) {
            for (const QString &e : m_settings.value(QStringLiteral("Tiles/Sizes")).toStringList()) {
                if (validSize(e) && !m_sizes.contains(e)) {
                    m_sizes << e;
                }
            }
        } else {
            m_sizes = defaultSizes();
        }
        m_accentCustom = m_settings.value(QStringLiteral("Appearance/AccentSet")).toBool();
        m_hue = qBound(0, m_settings.value(QStringLiteral("Appearance/AccentHue"), 183).toInt(), 359);
        m_light = qBound(0.25, m_settings.value(QStringLiteral("Appearance/AccentLight"), 0.5).toDouble(), 0.8);
        m_sat = qBound(0.15, m_settings.value(QStringLiteral("Appearance/AccentSat"), 1.0).toDouble(), 1.0);
        m_saveAccent.setSingleShot(true);
        m_saveAccent.setInterval(400);          // dragging a slider changes it many times a second: write once it settles
        connect(&m_saveAccent, &QTimer::timeout, this, [this] {
            m_settings.setValue(QStringLiteral("Appearance/AccentSet"), m_accentCustom);
            m_settings.setValue(QStringLiteral("Appearance/AccentHue"), m_hue);
            m_settings.setValue(QStringLiteral("Appearance/AccentLight"), m_light);
            m_settings.setValue(QStringLiteral("Appearance/AccentSat"), m_sat);
            m_settings.sync();
        });
        m_vibePoll.setInterval(2000);           // a vibe session can end by itself (the lid opened): follow it
        connect(&m_vibePoll, &QTimer::timeout, this, [this] { readVibe(); });
        QTimer::singleShot(0, this, [this] {
            refresh();
            readVibe();
            m_vibePoll.start();
        });
    }
    ~TileStore() override { release(); }

    QStringList widgets() const
    {
        // Never configured: today's behavior (the YouTube Music card). Configured (even to nothing): as saved.
        if (!m_settings.contains(QStringLiteral("Widgets/Configured"))) {
            return connectInstalled() ? QStringList{QStringLiteral("media"), QStringLiteral("connect")} : QStringList{QStringLiteral("media")};
        }
        QStringList out;
        for (const QString &id : m_settings.value(QStringLiteral("Widgets/Order")).toStringList()) {
            if (knownWidget(id) && !out.contains(id)) {
                out << id;
            }
        }
        return out;
    }
    QVariantList widgetCatalog() const { return m_widgetCatalog; }
    Q_INVOKABLE void setWidgets(const QStringList &ids)
    {
        QStringList clean;
        for (const QString &id : ids) {
            if (knownWidget(id) && !clean.contains(id)) {
                clean << id;
            }
        }
        if (clean == widgets()) {
            return;
        }
        m_settings.setValue(QStringLiteral("Widgets/Configured"), true);
        m_settings.setValue(QStringLiteral("Widgets/Order"), clean);   // empty stays a key: PrefsGuard puts back keys that vanish
        m_settings.sync();
        Q_EMIT widgetsChanged();
    }
    bool accentCustom() const { return m_accentCustom; }
    int accentHue() const { return m_hue; }
    qreal accentLight() const { return m_light; }
    qreal accentSat() const { return m_sat; }
    Q_INVOKABLE void setAccent(int hue, qreal light, qreal sat)
    {
        m_hue = qBound(0, hue, 359);
        m_light = qBound(0.25, light, 0.8);
        m_sat = qBound(0.15, sat, 1.0);
        m_accentCustom = true;
        m_saveAccent.start();
        Q_EMIT accentChanged();
    }
    Q_INVOKABLE void resetAccent()
    {
        m_accentCustom = false;
        m_hue = 183;
        m_light = 0.5;
        m_sat = 1.0;
        m_saveAccent.start();
        Q_EMIT accentChanged();
    }
    // Bake the accent into the system color scheme (plasma-apply-colorscheme rewrites the
    // scheme colors in kdeglobals): selections, focus rings, sliders and Kirigami apps all
    // follow the bar's picker. Passing the theme's own accent restores the scheme's default.
    Q_INVOKABLE void applySystemAccent(const QColor &color)
    {
        const QString hex = color.toRgb().name(QColor::HexRgb);
        if (!color.alpha() || hex == m_systemAccent) {
            return;
        }
        m_systemAccent = hex;
        QSettings kde(QDir::homePath() + QStringLiteral("/.config/kdeglobals"), QSettings::IniFormat);
        const QString scheme = kde.value(QStringLiteral("ColorScheme")).toString();     // INI [General] keys sit at the root
        QProcess::startDetached(QStringLiteral("plasma-apply-colorscheme"),
                                {scheme.isEmpty() ? QStringLiteral("AetherGlass") : scheme, QStringLiteral("--accent-color"), hex});
    }

    // The wallpaper family and the pick. Everything lives in ~/.config/aetherislandrc ([Wallpaper]);
    // a style switch rides plasmashell's scripting API - the desktops repaint at once - and the two
    // sync oneshots then hand the new wallpaper the accent, the mode and the distribution.
    QVariantList wallpapers() const
    {
        return {QVariantMap{{QStringLiteral("id"), QStringLiteral("org.aether.ribbons")}, {QStringLiteral("title"), QStringLiteral("Ribbons")}, {QStringLiteral("shader"), QStringLiteral("ribbons")}},
                QVariantMap{{QStringLiteral("id"), QStringLiteral("org.aether.mist")}, {QStringLiteral("title"), QStringLiteral("Mist")}, {QStringLiteral("shader"), QStringLiteral("mist")}},
                QVariantMap{{QStringLiteral("id"), QStringLiteral("org.aether.aurora")}, {QStringLiteral("title"), QStringLiteral("Aurora")}, {QStringLiteral("shader"), QStringLiteral("aurora")}},
                QVariantMap{{QStringLiteral("id"), QStringLiteral("org.aether.ink")}, {QStringLiteral("title"), QStringLiteral("Ink")}, {QStringLiteral("shader"), QStringLiteral("ink")}},
                QVariantMap{{QStringLiteral("id"), QStringLiteral("org.aether.dune")}, {QStringLiteral("title"), QStringLiteral("Dune")}, {QStringLiteral("shader"), QStringLiteral("dune")}}};
    }
    QString wallpaperStyle() const { return m_wallpaper; }
    bool wallpaperAnimate() const { return m_wallpaperAnimate; }
    Q_INVOKABLE void setWallpaper(const QString &id)
    {
        if (!wallpaperIds().contains(id) || id == m_wallpaper) {
            return;
        }
        m_wallpaper = id;
        m_settings.setValue(QStringLiteral("Wallpaper/Style"), id);
        m_settings.sync();
        const QString js = QStringLiteral("desktops().forEach(function(d){d.wallpaperPlugin='%1';});").arg(id);
        QProcess::startDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                           QStringLiteral("org.kde.PlasmaShell.evaluateScript"), js});
        // A moment later, once the switch has landed, the oneshots push accent and mode into it, and
        // the new field takes the mark and the motion the old one wore.
        QTimer::singleShot(800, this, [this] {
            wallpaperConfig(QStringLiteral("Mark"), m_wallpaperMark);
            wallpaperConfig(QStringLiteral("Animate"), m_wallpaperAnimate ? QStringLiteral("true") : QStringLiteral("false"));
            QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("start"),
                                                                  QStringLiteral("aether-accent-sync.service"), QStringLiteral("aether-mode-sync.service")});
        });
        Q_EMIT wallpaperChanged();
    }
    Q_INVOKABLE void setWallpaperAnimate(bool on)
    {
        if (on == m_wallpaperAnimate) {
            return;
        }
        m_wallpaperAnimate = on;
        m_settings.setValue(QStringLiteral("Wallpaper/Animate"), on);
        m_settings.sync();
        wallpaperConfig(QStringLiteral("Animate"), on ? QStringLiteral("true") : QStringLiteral("false"));
        Q_EMIT wallpaperChanged();
    }
    // The mark at the wallpaper's centre: "" (the distribution's logo), "none", "aether", "logo:<slug>"
    // or "file:<path>" - written into whichever aether wallpaper the desktops wear.
    QString wallpaperMark() const { return m_wallpaperMark; }
    QVariantList markLogos() const { return m_markLogos; }
    QString distroLogo() const { return m_distroLogo; }
    Q_INVOKABLE void setWallpaperMark(const QString &spec)
    {
        const bool ok = spec.isEmpty() || spec == QLatin1String("none") || spec == QLatin1String("aether")
            || (spec.startsWith(QLatin1String("logo:")) && m_logoPaths.contains(spec.mid(5)))
            || (spec.startsWith(QLatin1String("file:")) && QFileInfo::exists(spec.mid(5)));
        if (!ok || spec == m_wallpaperMark) {
            return;
        }
        m_wallpaperMark = spec;
        m_settings.setValue(QStringLiteral("Wallpaper/Mark"), spec);
        m_settings.sync();
        wallpaperConfig(QStringLiteral("Mark"), spec);
        Q_EMIT wallpaperChanged();
    }
    bool canImportMark() const { return !QStandardPaths::findExecutable(QStringLiteral("kdialog")).isEmpty(); }
    // The system file chooser (kdialog) for an image of one's own. The pick is copied under
    // ~/.local/share/aether/marks - the wallpaper keeps it if the original moves - under a fresh name,
    // so the wallpaper's image cache never serves the previous one. Nothing happens if it is cancelled.
    Q_INVOKABLE void importWallpaperMark()
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            const QString src = QString::fromUtf8(p->readAllStandardOutput()).trimmed();
            p->deleteLater();
            if (src.isEmpty() || !QFileInfo(src).isFile()) {
                return;
            }
            const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aether/marks");
            QDir().mkpath(dir);
            const QString dest = QStringLiteral("%1/mark-%2.%3").arg(dir).arg(QDateTime::currentMSecsSinceEpoch()).arg(QFileInfo(src).suffix().toLower());
            if (!QFile::copy(src, dest)) {
                return;
            }
            for (const QFileInfo &old : QDir(dir).entryInfoList(QDir::Files)) {
                if (old.absoluteFilePath() != dest) {
                    QFile::remove(old.absoluteFilePath());
                }
            }
            setWallpaperMark(QStringLiteral("file:") + dest);
        });
        p->start(QStringLiteral("kdialog"), {QStringLiteral("--getopenfilename"), QDir::homePath(),
                                            QStringLiteral("*.svg *.png *.jpg *.jpeg *.webp|Images")});
    }
    QStringList order() const { return m_order; }
    QStringList sizes() const { return m_sizes; }
    QVariantList catalog() const { return m_catalog; }
    QString language() const { return m_settings.value(QStringLiteral("Interface/Language"), QStringLiteral("en")).toString(); }
    void setLanguage(const QString &code)
    {
        if (code == language() || (code != QLatin1String("en") && code != QLatin1String("he"))) {
            return;
        }
        m_settings.setValue(QStringLiteral("Interface/Language"), code);
        m_settings.sync();
        Q_EMIT languageChanged();
    }
    bool hebrewDates() const { return m_settings.value(QStringLiteral("Calendar/Hebrew"), true).toBool(); }
    void setHebrewDates(bool on)
    {
        if (on == hebrewDates()) {
            return;
        }
        m_settings.setValue(QStringLiteral("Calendar/Hebrew"), on);
        m_settings.sync();
        Q_EMIT hebrewDatesChanged();
    }
    bool keepAwake() const { return m_cookie != 0; }
    bool vibeOn() const { return m_vibeOn; }
    bool lensOn() const { return m_lensOn; }
    bool consoleEarOn() const { return m_consoleEarOn; }
    bool micMuted() const { return m_micMuted; }
    bool wifiBefore() const { return m_wifiBefore; }
    bool bluetoothBefore() const { return m_btBefore; }

    // Unknown and repeated ids are dropped; an empty list falls back to the default set.
    Q_INVOKABLE void setOrder(const QStringList &ids) { setLayout(ids, m_sizes); }
    Q_INVOKABLE void setLayout(const QStringList &ids, const QStringList &sizeList)
    {
        QStringList clean, sizes;
        for (const QString &id : ids) {
            if (known(id) && !clean.contains(id)) {
                clean << id;
            }
        }
        if (clean.isEmpty()) {
            clean = defaults();
        }
        for (const QString &e : sizeList) {
            if (validSize(e) && clean.contains(e.section(QLatin1Char(':'), 0, 0)) && !sizes.contains(e)) {
                sizes << e;
            }
        }
        if (clean == m_order && sizes == m_sizes) {
            return;
        }
        m_order = clean;
        m_sizes = sizes;
        m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
        m_settings.remove(QStringLiteral("Tiles/Wide"));
        m_settings.remove(QStringLiteral("Tiles/WideSet"));
        m_settings.setValue(QStringLiteral("Tiles/SizesSet"), true);       // an empty list is "all one cell", not "never set"
        m_settings.setValue(QStringLiteral("Tiles/Sizes"), m_sizes);
        m_settings.sync();
        Q_EMIT orderChanged();
    }
    Q_INVOKABLE void reset() { setLayout(defaults(), defaultSizes()); }
    Q_INVOKABLE void refresh() { readMic(); }

    Q_INVOKABLE void toggleKeepAwake()
    {
        if (m_cookie != 0) {
            release();
        } else {
            QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                            QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("Inhibit"));
            m << QStringLiteral("Aether Island") << QStringLiteral("Keep awake");
            const QDBusReply<uint> r = QDBusConnection::sessionBus().call(m, QDBus::Block, 1500);
            m_cookie = r.isValid() ? r.value() : 0;
        }
        Q_EMIT stateChanged();
    }
    // The console's access strip on the screen edge, shown or hidden. Hidden, the console is still
    // there (Win+C and the bar open it); only its resting tab is gone.
    Q_INVOKABLE void toggleConsoleEar()
    {
        m_consoleEarOn = !m_consoleEarOn;
        m_settings.setValue(QStringLiteral("Console/EarShown"), m_consoleEarOn);
        m_settings.sync();
        Q_EMIT stateChanged();
    }
    // Circle to Search on or off. The flag lives in aetherislandrc; the dock stops offering the hold on
    // its grab line and aether-lens ignores Win+G (and lets go of its model's memory) while it is off.
    Q_INVOKABLE void toggleLens()
    {
        m_lensOn = !m_lensOn;
        m_settings.setValue(QStringLiteral("Lens/Enabled"), m_lensOn);
        m_settings.sync();
        Q_EMIT stateChanged();
    }
    // Vibe coding: aether-vibe holds the logind inhibitors and manages the panel's DPMS;
    // the tile only flips it and follows the state file, since the session can end by itself.
    Q_INVOKABLE void toggleVibe()
    {
        QProcess::execute(vibeTool(), {QStringLiteral("toggle")});
        readVibe();
    }
    Q_INVOKABLE void toggleMic()
    {
        m_micMuted = !m_micMuted;
        QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-source-mute"), QStringLiteral("@DEFAULT_SOURCE@"), m_micMuted ? QStringLiteral("1") : QStringLiteral("0")});
        Q_EMIT stateChanged();
    }
    Q_INVOKABLE void rememberRadios(bool wifi, bool bluetooth) { m_wifiBefore = wifi; m_btBefore = bluetooth; Q_EMIT stateChanged(); }
    // The island has to be gone before the capture starts, or it ends up in the picture.
    Q_INVOKABLE void screenshot() { later({QStringLiteral("-r")}); }
    Q_INVOKABLE void record() { later({QStringLiteral("-R"), QStringLiteral("r")}); }

Q_SIGNALS:
    void orderChanged();
    void widgetsChanged();
    void hebrewDatesChanged();
    void accentChanged();
    void languageChanged();
    void wallpaperChanged();
    void stateChanged();

private:
    static bool connectInstalled()
    {
        return qEnvironmentVariableIntValue("AETHER_CONNECT_FAKE") != 0 || !QStandardPaths::findExecutable(QStringLiteral("kdeconnect-cli")).isEmpty();
    }
    bool knownWidget(const QString &id) const
    {
        if (id == QLatin1String("connect")) {
            return connectInstalled();
        }
        for (const QVariant &c : m_widgetCatalog) {
            if (c.toMap().value(QStringLiteral("id")).toString() == id) {
                return true;
            }
        }
        return false;
    }
    bool known(const QString &id) const
    {
        for (const QVariant &c : m_catalog) {
            if (c.toMap().value(QStringLiteral("id")).toString() == id) {
                return true;
            }
        }
        return false;
    }
    static QStringList defaults()
    {
        return {QStringLiteral("wifi"), QStringLiteral("bluetooth"), QStringLiteral("nightlight"), QStringLiteral("darktheme"),
                QStringLiteral("airplane"), QStringLiteral("keepawake"), QStringLiteral("micmute"), QStringLiteral("powersaver"), QStringLiteral("accent")};
    }
    static QStringList defaultSizes() { return {QStringLiteral("wifi:2"), QStringLiteral("bluetooth:2")}; }   // the two that carry words
    // "id:2" or "id:3": a known tile at two or three cells wide
    bool validSize(const QString &e) const
    {
        const QString size = e.section(QLatin1Char(':'), 1, 1);
        return known(e.section(QLatin1Char(':'), 0, 0)) && (size == QLatin1String("2") || size == QLatin1String("3"));
    }
    void release()
    {
        if (m_cookie != 0) {
            QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("/org/freedesktop/PowerManagement/Inhibit"),
                                                            QStringLiteral("org.freedesktop.PowerManagement.Inhibit"), QStringLiteral("UnInhibit"));
            m << m_cookie;
            QDBusConnection::sessionBus().call(m, QDBus::Block, 1000);
            m_cookie = 0;
        }
    }
    void readMic()
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            const bool muted = QString::fromUtf8(p->readAllStandardOutput()).contains(QLatin1String("yes"));
            p->deleteLater();
            if (muted != m_micMuted) {
                m_micMuted = muted;
                Q_EMIT stateChanged();
            }
        });
        p->start(QStringLiteral("pactl"), {QStringLiteral("get-source-mute"), QStringLiteral("@DEFAULT_SOURCE@")});
    }
    void later(const QStringList &args)
    {
        QTimer::singleShot(450, this, [args] { QProcess::startDetached(QStringLiteral("spectacle"), args); });
    }
    // The systemd user service has no ~/.local/bin on PATH, so the tool is addressed absolutely.
    static QString vibeTool()
    {
        const QString local = QDir::homePath() + QStringLiteral("/.local/bin/aether-vibe");
        return QFile::exists(local) ? local : QStandardPaths::findExecutable(QStringLiteral("aether-vibe"));
    }
    void readVibe()
    {
        QFile f(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/aether-vibe.state"));
        bool on = false;
        if (f.open(QIODevice::ReadOnly)) {
            const long long pid = f.readAll().trimmed().toLongLong();
            on = pid > 0 && ::kill(static_cast<pid_t>(pid), 0) == 0;
        }
        if (on != m_vibeOn) {
            m_vibeOn = on;
            Q_EMIT stateChanged();
        }
    }

    static QVariantMap tile(const char *id, const char *label, const char *glyph) {
        return {{QStringLiteral("id"), QString::fromLatin1(id)}, {QStringLiteral("label"), QString::fromLatin1(label)}, {QStringLiteral("glyph"), QString::fromLatin1(glyph)}};
    }
    QStringList wallpaperIds() const
    {
        return {QStringLiteral("org.aether.ribbons"), QStringLiteral("org.aether.mist"), QStringLiteral("org.aether.aurora"),
                QStringLiteral("org.aether.ink"), QStringLiteral("org.aether.dune")};
    }
    // The wallpapers' logos, read from the one logos.js they all wear (the installed ribbons, else
    // the development tree): `"slug": "path"` lines under `var paths`, `"os-release id": "slug"`
    // under `var ids`. This distribution's logo is the first of its ID, then ID_LIKE, that has one.
    void loadLogos()
    {
        QString file = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("plasma/wallpapers/org.aether.ribbons/contents/ui/logos.js"));
        if (file.isEmpty()) {
            file = QStringLiteral(AETHER_QML_DIR "/../../../plasmoids/org.aether.ribbons/contents/ui/logos.js");
        }
        QFile f(file);
        if (!f.open(QIODevice::ReadOnly)) {
            return;
        }
        static const QRegularExpression entry(QStringLiteral("^\\s*\"([^\"]+)\"\\s*:\\s*\"([^\"]*)\""));
        QHash<QString, QString> ids;
        bool inIds = false;
        for (const QString &line : QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("var ids"))) {
                inIds = true;
            }
            const auto m = entry.match(line);
            if (!m.hasMatch()) {
                continue;
            }
            if (inIds) {
                ids.insert(m.captured(1), m.captured(2));
            } else {
                m_logoPaths.insert(m.captured(1), m.captured(2));
                m_markLogos << QVariantMap{{QStringLiteral("slug"), m.captured(1)}, {QStringLiteral("path"), m.captured(2)}};
            }
        }
        QFile osr(QStringLiteral("/etc/os-release"));
        if (osr.open(QIODevice::ReadOnly)) {
            QStringList list;
            for (const QString &line : QString::fromUtf8(osr.readAll()).split(QLatin1Char('\n'))) {
                if (line.startsWith(QLatin1String("ID=")) || line.startsWith(QLatin1String("ID_LIKE="))) {
                    list << line.mid(line.indexOf(QLatin1Char('=')) + 1).remove(QLatin1Char('"')).split(QLatin1Char(' '), Qt::SkipEmptyParts);
                }
            }
            for (const QString &id : std::as_const(list)) {
                if (ids.contains(id.toLower())) {
                    m_distroLogo = m_logoPaths.value(ids.value(id.toLower()));
                    break;
                }
            }
        }
    }
    // Write one key into whichever aether wallpaper each desktop wears; plasmashell repaints at once.
    void wallpaperConfig(const QString &key, const QString &rawValue)
    {
        QString value = rawValue;   // the value rides inside a JS string: keep it one
        value.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('\''), QStringLiteral("\\'"));
        const QString js = QStringLiteral("var n = 0; desktops().forEach(function (d) { if (d.wallpaperPlugin.indexOf('org.aether.') != 0) return;"
                                          " d.currentConfigGroup = ['Wallpaper', d.wallpaperPlugin, 'General'];"
                                          " if (d.readConfig('%1') != '%2') { d.writeConfig('%1', '%2'); n++; } }); print(n);")
                               .arg(key, value);
        QProcess::startDetached(QStringLiteral("qdbus6"), {QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                           QStringLiteral("org.kde.PlasmaShell.evaluateScript"), js});
    }
    const QVariantList m_catalog = {
        tile("wifi", "Wi‑Fi", "wifi-3"), tile("bluetooth", "Bluetooth", "bluetooth"),
        tile("nightlight", "Night Light", "moon"), tile("darktheme", "Theme", "contrast"), tile("airplane", "Airplane mode", "plane"),
        tile("keepawake", "Keep awake", "coffee"), tile("vibe", "Vibe coding", "vibe"), tile("micmute", "Microphone", "mic"), tile("powersaver", "Power saver", "leaf"),
        tile("lens", "Circle to Search", "lens"), tile("screenshot", "Screenshot", "camera"), tile("record", "Screen record", "record"), tile("accent", "Color", "palette"), tile("wallpaper", "Wallpaper", "wallpaper"), tile("console", "Console", "terminal")};
    const QVariantList m_widgetCatalog = connectInstalled() ? QVariantList{tile("media", "YouTube Music", "logo"), tile("connect", "KDE Connect", "phone")} : QVariantList{tile("media", "YouTube Music", "logo")};
    QSettings m_settings;
    QTimer m_saveAccent;
    QString m_systemAccent;                 // the accent last pushed into the color scheme, to skip identical pushes
    QString m_wallpaper;                    // the active aether wallpaper id
    bool m_wallpaperAnimate = true;
    QString m_wallpaperMark;                // [Wallpaper] Mark
    QHash<QString, QString> m_logoPaths;    // logos.js: slug -> SVG path
    QVariantList m_markLogos;
    QString m_distroLogo;
    bool m_accentCustom = false;
    int m_hue = 183;
    qreal m_light = 0.5, m_sat = 1.0;
    QStringList m_order, m_sizes;
    QTimer m_vibePoll;
    bool m_vibeOn = false;
    bool m_lensOn = true;
    bool m_consoleEarOn = true;
    uint m_cookie = 0;
    bool m_micMuted = false, m_wifiBefore = true, m_btBefore = true;
};
