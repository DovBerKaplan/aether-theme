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
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class TileStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList order READ order NOTIFY orderChanged)
    Q_PROPERTY(QVariantList catalog READ catalog CONSTANT)           // every tile that can be shown
    Q_PROPERTY(bool hebrewDates READ hebrewDates WRITE setHebrewDates NOTIFY hebrewDatesChanged)   // Calendar panel
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
        QTimer::singleShot(0, this, [this] { refresh(); });
    }
    ~TileStore() override { release(); }

    QStringList order() const { return m_order; }
    QVariantList catalog() const { return m_catalog; }
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
    Q_INVOKABLE void setOrder(const QStringList &ids)
    {
        QStringList clean;
        for (const QString &id : ids) {
            if (known(id) && !clean.contains(id)) {
                clean << id;
            }
        }
        if (clean.isEmpty()) {
            clean = defaults();
        }
        if (clean == m_order) {
            return;
        }
        m_order = clean;
        m_settings.setValue(QStringLiteral("Tiles/Order"), m_order);
        m_settings.sync();
        Q_EMIT orderChanged();
    }
    Q_INVOKABLE void reset() { setOrder(defaults()); }
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
    void hebrewDatesChanged();
    void stateChanged();

private:
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
        tile("nightlight", "Night Light", "moon"), tile("darktheme", "Dark theme", "contrast"), tile("airplane", "Airplane mode", "plane"),
        tile("keepawake", "Keep awake", "coffee"), tile("micmute", "Microphone", "mic"), tile("powersaver", "Power saver", "leaf"),
        tile("screenshot", "Screenshot", "camera"), tile("record", "Screen record", "record")};
    QSettings m_settings;
    QStringList m_order;
    uint m_cookie = 0;
    bool m_micMuted = false, m_wifiBefore = true, m_btBefore = true;
};
