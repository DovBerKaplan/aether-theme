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
    Q_PROPERTY(QStringList wide READ wide NOTIFY orderChanged)               // tiles drawn 2 cells wide (the rest are 1)
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
        if (m_settings.value(QStringLiteral("Tiles/WideSet")).toBool()) {
            for (const QString &id : m_settings.value(QStringLiteral("Tiles/Wide")).toStringList()) {
                if (known(id) && !m_wide.contains(id)) {
                    m_wide << id;
                }
            }
        } else {
            m_wide = defaultWide();
        }
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
    QStringList order() const { return m_order; }
    QStringList wide() const { return m_wide; }
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
    Q_INVOKABLE void setOrder(const QStringList &ids) { setLayout(ids, m_wide); }
    Q_INVOKABLE void setLayout(const QStringList &ids, const QStringList &wideIds)
    {
        QStringList clean, wide;
        for (const QString &id : ids) {
            if (known(id) && !clean.contains(id)) {
                clean << id;
            }
        }
        if (clean.isEmpty()) {
            clean = defaults();
        }
        for (const QString &id : wideIds) {
            if (clean.contains(id) && !wide.contains(id)) {
                wide << id;
            }
        }
        if (clean == m_order && wide == m_wide) {
            return;
        }
        m_order = clean;
        m_wide = wide;
        m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
        m_settings.setValue(QStringLiteral("Tiles/WideSet"), true);          // an empty list is "none are wide", not "never set"
        if (m_wide.isEmpty()) {
            m_settings.remove(QStringLiteral("Tiles/Wide"));
        } else {
            m_settings.setValue(QStringLiteral("Tiles/Wide"), m_wide);
        }
        m_settings.sync();
        Q_EMIT orderChanged();
    }
    Q_INVOKABLE void reset() { setLayout(defaults(), defaultWide()); }
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
                QStringLiteral("airplane"), QStringLiteral("keepawake"), QStringLiteral("micmute"), QStringLiteral("powersaver")};
    }
    static QStringList defaultWide() { return {}; }
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
        tile("screenshot", "Screenshot", "camera"), tile("record", "Screen record", "record")};
    const QVariantList m_widgetCatalog = connectInstalled() ? QVariantList{tile("media", "YouTube Music", "logo"), tile("connect", "KDE Connect", "phone")} : QVariantList{tile("media", "YouTube Music", "logo")};
    QSettings m_settings;
    QStringList m_order, m_wide;
    uint m_cookie = 0;
    bool m_micMuted = false, m_wifiBefore = true, m_btBefore = true;
};
