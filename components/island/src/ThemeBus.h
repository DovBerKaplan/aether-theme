// The desktop's theme on the session bus (docs/THEME-BUS.md): org.aether.Theme /Theme, interface
// org.aether.Theme1. Get() hands out the accent, the light/dark mode, the wallpaper style and the
// interface language; Changed(a{sv}) follows every real change of any of them; SetAccent,
// ResetAccent and SetMode let a client ask for one. The island owns the state (TileStore for the
// accent, wallpaper and language, DisplayModel for the mode); this is only its voice.
#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusError>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QRegularExpression>
#include <QSettings>
#include <QTimer>
#include <QVariantMap>

#include "SystemPanels.h"
#include "TileStore.h"

class ThemeBus : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Theme1")

public:
    ThemeBus(TileStore *tiles, DisplayModel *display, QObject *parent = nullptr)
        : QObject(parent)
        , m_tiles(tiles)
        , m_display(display)
    {
        // Debounced: a slider drag changes the accent dozens of times a second, and a scheme switch
        // rewrites kdeglobals several times over - clients hear the state once it rests.
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(150);
        connect(&m_debounce, &QTimer::timeout, this, &ThemeBus::publish);
        connect(tiles, &TileStore::accentChanged, &m_debounce, qOverload<>(&QTimer::start));
        connect(tiles, &TileStore::wallpaperChanged, &m_debounce, qOverload<>(&QTimer::start));
        connect(tiles, &TileStore::languageChanged, &m_debounce, qOverload<>(&QTimer::start));
        connect(&m_watch, &QFileSystemWatcher::fileChanged, this, [this] {
            m_debounce.start();
            QTimer::singleShot(200, this, &ThemeBus::rewatch);   // an atomic replace drops the watch: take the new file
        });
        m_rewatch.setInterval(2000);                             // a file that is not there (yet): look again now and then
        connect(&m_rewatch, &QTimer::timeout, this, &ThemeBus::rewatch);
        rewatch();
        m_last = snapshot();
    }

public Q_SLOTS:
    Q_SCRIPTABLE QVariantMap Get() const { return snapshot(); }

    // "#rrggbb" -> the island's own picker coordinates (hue, HSL lightness, HSL saturation), clamped to
    // the picker's range like a slider would; the resolved colour can therefore differ a little.
    Q_SCRIPTABLE void SetAccent(const QString &hex)
    {
        static const QRegularExpression re(QStringLiteral("^#[0-9A-Fa-f]{6}$"));
        if (!re.match(hex).hasMatch()) {
            sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("SetAccent wants a colour as \"#rrggbb\", got \"%1\"").arg(hex.left(32)));
            return;
        }
        const QColor c = QColor::fromString(hex).toHsl();
        m_tiles->setAccent(qMax(0, c.hslHue()), c.lightnessF(), c.hslSaturationF());
    }
    Q_SCRIPTABLE void ResetAccent() { m_tiles->resetAccent(); }
    // "dark" | "light": the island's Display panel switch (colour scheme + look-and-feel).
    Q_SCRIPTABLE void SetMode(const QString &mode)
    {
        if (mode != QLatin1String("dark") && mode != QLatin1String("light")) {
            sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("SetMode wants \"dark\" or \"light\", got \"%1\"").arg(mode.left(32)));
            return;
        }
        if ((mode == QLatin1String("light")) != modeIsLight()) {
            m_display->setDark(mode == QLatin1String("dark"));
        }
    }

Q_SIGNALS:
    Q_SCRIPTABLE void Changed(const QVariantMap &state);

private:
    static QString configFile(const char *name) { return QDir::homePath() + QStringLiteral("/.config/") + QLatin1String(name); }

    void rewatch()
    {
        bool missing = false;
        for (const QString &f : {configFile("kdeglobals"), configFile("plasma-org.kde.plasma.desktop-appletsrc")}) {
            if (!m_watch.files().contains(f) && !(QFileInfo::exists(f) && m_watch.addPath(f))) {
                missing = true;
            }
        }
        if (missing) {
            m_rewatch.start();
        } else {
            m_rewatch.stop();
        }
    }

    void publish()
    {
        const QVariantMap now = snapshot();
        if (now == m_last) {
            return;
        }
        m_last = now;
        Q_EMIT Changed(now);
    }

    QVariantMap snapshot() const
    {
        const bool light = modeIsLight();
        const bool set = m_tiles->accentCustom();
        // The theme's own accent when nothing was chosen: Theme.qml's rule (tokens role.island /
        // role.light accent), by the system mode.
        const QColor accent = set ? QColor::fromHslF(m_tiles->accentHue() / 360.0, m_tiles->accentSat(), m_tiles->accentLight())
                                  : QColor(light ? QStringLiteral("#1a1d20") : QStringLiteral("#00f2fe"));
        return {
            {QStringLiteral("version"), 1},
            {QStringLiteral("accent"), accent.name(QColor::HexRgb)},
            {QStringLiteral("accentHue"), m_tiles->accentHue()},
            {QStringLiteral("accentSat"), double(m_tiles->accentSat())},
            {QStringLiteral("accentLight"), double(m_tiles->accentLight())},
            {QStringLiteral("accentSet"), set},
            {QStringLiteral("mode"), light ? QStringLiteral("light") : QStringLiteral("dark")},
            {QStringLiteral("wallpaper"), wallpaper()},
            {QStringLiteral("language"), m_tiles->language()},
        };
    }

    // system/aether-accent-sync's mode_is_light(): the scheme's name; with none written and an aether
    // look-and-feel in charge, the window background's plain average.
    static bool modeIsLight()
    {
        QSettings kde(configFile("kdeglobals"), QSettings::IniFormat);   // INI [General] keys sit at the root
        const QString scheme = kde.value(QStringLiteral("ColorScheme")).toString();
        if (scheme.isEmpty() && kde.value(QStringLiteral("KDE/LookAndFeelPackage")).toString().startsWith(QLatin1String("org.aether."))) {
            const QStringList c = kde.value(QStringLiteral("Colors:Window/BackgroundNormal"), QStringLiteral("0,0,0")).toStringList();
            int sum = 0, n = 0;
            for (int i = 0; i < qMin<qsizetype>(3, c.size()); ++i) {
                bool ok = false;
                const int v = c[i].trimmed().toInt(&ok);
                if (ok) {
                    sum += v;
                    ++n;
                }
            }
            return sum / double(qMax(n, 1)) >= 128;
        }
        return scheme == QLatin1String("AetherSerenity");
    }

    // The style id the island picked ([Wallpaper] Style); with none saved, what the primary screen's
    // desktop actually wears in appletsrc: an aether wallpaper by its short name, a plain image as
    // "static", anything else "neutral".
    QString wallpaper() const
    {
        static const QString prefix = QStringLiteral("org.aether.");
        if (m_tiles->wallpaperChosen()) {
            return m_tiles->wallpaperStyle().mid(prefix.size());
        }
        // appletsrc nests groups as [Containments][N][General], which QSettings cannot read, so by hand
        // (the desk's readGrid()).
        QFile f(configFile("plasma-org.kde.plasma.desktop-appletsrc"));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return QStringLiteral("neutral");
        }
        static const QRegularExpression head(QStringLiteral("^\\[Containments\\]\\[(\\d+)\\]$"));
        QHash<QString, QHash<QString, QString>> top;
        QString id;
        bool inGroup = false;
        while (!f.atEnd()) {
            const QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (line.startsWith(QLatin1Char('['))) {
                const auto m = head.match(line);
                inGroup = m.hasMatch();
                id = m.captured(1);
                continue;
            }
            const int eq = line.indexOf(QLatin1Char('='));
            if (inGroup && eq > 0) {
                top[id][line.left(eq)] = line.mid(eq + 1);
            }
        }
        QString plugin;
        for (auto it = top.cbegin(); it != top.cend(); ++it) {
            const QString p = it->value(QStringLiteral("wallpaperplugin"));
            if (p.isEmpty() || it->value(QStringLiteral("activityId")).isEmpty()) {   // panels carry no activity: desktops only
                continue;
            }
            if (plugin.isEmpty() || it->value(QStringLiteral("lastScreen")) == QLatin1String("0")) {
                plugin = p;
            }
        }
        if (plugin.startsWith(prefix) && plugin.size() > prefix.size()) {
            return plugin.mid(prefix.size());
        }
        return plugin == QLatin1String("org.kde.image") ? QStringLiteral("static") : QStringLiteral("neutral");
    }

    TileStore *m_tiles;
    DisplayModel *m_display;
    QFileSystemWatcher m_watch;
    QTimer m_debounce, m_rewatch;
    QVariantMap m_last;                     // what clients last heard
};
