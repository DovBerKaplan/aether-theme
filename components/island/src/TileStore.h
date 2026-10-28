// The large island's tile set: which tiles exist, which are shown and in what order (saved in
// ~/.config/aetherislandrc, [Tiles] Order), and the few tile actions that have no home of
// their own (keep awake, microphone mute, screenshot, screen recording, airplane memory).
// What a tile *shows* is decided in QML (Tile.qml) from the models that already exist.
#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class TileStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList order READ order NOTIFY orderChanged)
    Q_PROPERTY(QStringList sizes READ sizes NOTIFY orderChanged)             // "id:2" / "id:3" for tiles wider than the default one cell
    Q_PROPERTY(bool accentCustom READ accentCustom NOTIFY accentChanged)      // a colour was chosen; otherwise the theme's own
    Q_PROPERTY(int accentHue READ accentHue NOTIFY accentChanged)             // 0..359
    Q_PROPERTY(qreal accentLight READ accentLight NOTIFY accentChanged)       // HSL lightness, 0.45..0.80
    Q_PROPERTY(QVariantList catalog READ catalog CONSTANT)           // every tile that can be shown
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)   // interface language: "en" | "he"
    Q_PROPERTY(bool hebrewDates READ hebrewDates WRITE setHebrewDates NOTIFY hebrewDatesChanged)   // Calendar panel
    Q_PROPERTY(QStringList widgets READ widgets NOTIFY widgetsChanged)         // large-island widgets that are on, in order
    Q_PROPERTY(QVariantList widgetCatalog READ widgetCatalog CONSTANT)          // every widget that can be on
    Q_PROPERTY(bool keepAwake READ keepAwake NOTIFY stateChanged)
    Q_PROPERTY(bool micMuted READ micMuted NOTIFY stateChanged)
    Q_PROPERTY(bool wifiBefore READ wifiBefore NOTIFY stateChanged)  // radios as they were before airplane mode
    Q_PROPERTY(bool bluetoothBefore READ bluetoothBefore NOTIFY stateChanged)

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
        m_light = qBound(0.45, m_settings.value(QStringLiteral("Appearance/AccentLight"), 0.5).toDouble(), 0.8);
        m_saveAccent.setSingleShot(true);
        m_saveAccent.setInterval(400);          // dragging a slider changes it many times a second: write once it settles
        connect(&m_saveAccent, &QTimer::timeout, this, [this] {
            m_settings.setValue(QStringLiteral("Appearance/AccentSet"), m_accentCustom);
            m_settings.setValue(QStringLiteral("Appearance/AccentHue"), m_hue);
            m_settings.setValue(QStringLiteral("Appearance/AccentLight"), m_light);
            m_settings.sync();
        });
        QTimer::singleShot(0, this, [this] { refresh(); });
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
        if (clean.isEmpty()) {
            m_settings.remove(QStringLiteral("Widgets/Order"));
        } else {
            m_settings.setValue(QStringLiteral("Widgets/Order"), clean);
        }
        m_settings.sync();
        Q_EMIT widgetsChanged();
    }
    bool accentCustom() const { return m_accentCustom; }
    int accentHue() const { return m_hue; }
    qreal accentLight() const { return m_light; }
    Q_INVOKABLE void setAccent(int hue, qreal light)
    {
        m_hue = qBound(0, hue, 359);
        m_light = qBound(0.45, light, 0.8);
        m_accentCustom = true;
        m_saveAccent.start();
        Q_EMIT accentChanged();
    }
    Q_INVOKABLE void resetAccent()
    {
        m_accentCustom = false;
        m_hue = 183;
        m_light = 0.5;
        m_saveAccent.start();
        Q_EMIT accentChanged();
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
        if (m_sizes.isEmpty()) {
            m_settings.remove(QStringLiteral("Tiles/Sizes"));
        } else {
            m_settings.setValue(QStringLiteral("Tiles/Sizes"), m_sizes);
        }
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

    static QVariantMap tile(const char *id, const char *label, const char *glyph) {
        return {{QStringLiteral("id"), QString::fromLatin1(id)}, {QStringLiteral("label"), QString::fromLatin1(label)}, {QStringLiteral("glyph"), QString::fromLatin1(glyph)}};
    }
    const QVariantList m_catalog = {
        tile("wifi", "Wi‑Fi", "wifi-3"), tile("bluetooth", "Bluetooth", "bluetooth"),
        tile("nightlight", "Night Light", "moon"), tile("darktheme", "Theme", "contrast"), tile("airplane", "Airplane mode", "plane"),
        tile("keepawake", "Keep awake", "coffee"), tile("micmute", "Microphone", "mic"), tile("powersaver", "Power saver", "leaf"),
        tile("screenshot", "Screenshot", "camera"), tile("record", "Screen record", "record"), tile("accent", "Color", "palette")};
    const QVariantList m_widgetCatalog = connectInstalled() ? QVariantList{tile("media", "YouTube Music", "logo"), tile("connect", "KDE Connect", "phone")} : QVariantList{tile("media", "YouTube Music", "logo")};
    QSettings m_settings;
    QTimer m_saveAccent;
    bool m_accentCustom = false;
    int m_hue = 183;
    qreal m_light = 0.5;
    QStringList m_order, m_sizes;
    uint m_cookie = 0;
    bool m_micMuted = false, m_wifiBefore = true, m_btBefore = true;
};
