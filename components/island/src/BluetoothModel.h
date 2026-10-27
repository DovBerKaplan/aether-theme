// Bluetooth panel backend, straight over BlueZ's D-Bus API (system bus).
// While the panel is open it registers a pairing agent (KeyboardDisplay) and runs discovery;
// closed, both are gone and the island keeps no BlueZ state. The agent is NOT made the default,
// so pairing started elsewhere (BlueDevil) keeps working; BlueZ uses ours for pairings we start.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QHash>
#include <QMap>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QSettings>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

using BluezObjects = QMap<QDBusObjectPath, QMap<QString, QVariantMap>>;
Q_DECLARE_METATYPE(BluezObjects)

// org.bluez.Agent1. Requests that need the user answer later (delayed reply).
class BluezAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
public:
    using QObject::QObject;
    void answer(bool accept, const QVariant &value = {})
    {
        if (waiting()) {
            const QDBusMessage m = m_pending;
            m_pending = QDBusMessage();
            QDBusConnection::systemBus().send(accept ? (value.isValid() ? m.createReply(value) : m.createReply())
                                                     : m.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("Rejected")));
        }
    }
    bool waiting() const { return m_pending.type() != QDBusMessage::InvalidMessage; }

public Q_SLOTS:
    void Release() { Q_EMIT canceled(); }
    QString RequestPinCode(const QDBusObjectPath &device) { hold(); Q_EMIT pinRequested(device.path(), false); return {}; }
    void DisplayPinCode(const QDBusObjectPath &device, const QString &pin) { Q_EMIT displayCode(device.path(), pin); }
    uint RequestPasskey(const QDBusObjectPath &device) { hold(); Q_EMIT pinRequested(device.path(), true); return 0; }
    void DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort) { Q_EMIT displayCode(device.path(), QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0'))); }
    void RequestConfirmation(const QDBusObjectPath &device, uint passkey)
    {
        hold();
        Q_EMIT confirmRequested(device.path(), QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')));
    }
    void RequestAuthorization(const QDBusObjectPath &device) { hold(); Q_EMIT confirmRequested(device.path(), QString()); }
    void AuthorizeService(const QDBusObjectPath &, const QString &) {}   // only reached for paired devices
    void Cancel() { m_pending = QDBusMessage(); Q_EMIT canceled(); }

Q_SIGNALS:
    void confirmRequested(const QString &device, const QString &code);
    void pinRequested(const QString &device, bool numeric);
    void displayCode(const QString &device, const QString &code);
    void canceled();

private:
    void hold() { setDelayedReply(true); m_pending = message(); }
    QDBusMessage m_pending;
};

class BluetoothModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool powered READ powered NOTIFY changed)
    Q_PROPERTY(bool discovering READ discovering NOTIFY changed)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY changed)
    Q_PROPERTY(QString busy READ busy NOTIFY changed)                  // device path being connected/paired
    // [{path, name, address, icon, paired, connected, trusted, battery (-1 if unknown), rssi}]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    // {path, name, kind: "confirm"|"pin"|"passkey"|"display", code} or empty
    Q_PROPERTY(QVariantMap pairing READ pairing NOTIFY changed)

public:
    explicit BluetoothModel(QObject *parent = nullptr)
        : QObject(parent)
    {
        qDBusRegisterMetaType<BluezObjects>();
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(250);
        connect(&m_debounce, &QTimer::timeout, this, [this] { refresh(); });
        auto bus = QDBusConnection::systemBus();
        bus.connect(Service, QString(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this, SLOT(onSignal(QDBusMessage)));
        bus.connect(Service, QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("InterfacesAdded"), this, SLOT(onSignal(QDBusMessage)));
        bus.connect(Service, QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("InterfacesRemoved"), this, SLOT(onSignal(QDBusMessage)));
        // The auto-connect engine runs whether or not the panel is open.
        m_auto.setSingleShot(true);
        connect(&m_auto, &QTimer::timeout, this, [this] { autoTick(); });
        bus.connect(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"), QStringLiteral("org.freedesktop.login1.Manager"),
                    QStringLiteral("PrepareForSleep"), this, SLOT(onSleep(bool)));
        m_manual = QSet<QString>(m_prefs.value(QStringLiteral("Bluetooth/Manual")).toStringList().begin(), m_prefs.value(QStringLiteral("Bluetooth/Manual")).toStringList().end());
        QTimer::singleShot(4000, this, [this] { refresh(); });
        connect(&m_agent, &BluezAgent::confirmRequested, this, [this](const QString &dev, const QString &code) {
            setPairing(dev, code.isEmpty() ? QStringLiteral("authorize") : QStringLiteral("confirm"), code);
        });
        connect(&m_agent, &BluezAgent::pinRequested, this, [this](const QString &dev, bool numeric) {
            setPairing(dev, numeric ? QStringLiteral("passkey") : QStringLiteral("pin"), QString());
        });
        connect(&m_agent, &BluezAgent::displayCode, this, [this](const QString &dev, const QString &code) {
            setPairing(dev, QStringLiteral("display"), code);
        });
        connect(&m_agent, &BluezAgent::canceled, this, [this] { m_pairing.clear(); Q_EMIT changed(); });
    }
    ~BluetoothModel() override { setActive(false); }

    bool available() const { return !m_adapter.isEmpty(); }
    bool powered() const { return m_powered; }
    bool discovering() const { return m_discovering; }
    QString adapterName() const { return m_adapterName; }
    QString busy() const { return m_busy; }
    QVariantList devices() const { return m_devices; }
    QVariantMap pairing() const { return m_pairing; }

    Q_INVOKABLE void setActive(bool on)
    {
        if (m_active == on) {
            return;
        }
        m_active = on;
        m_askedDiscovery = false;
        auto bus = QDBusConnection::systemBus();
        if (on) {
            if (!bus.objectRegisteredAt(AgentPath)) {
                bus.registerObject(AgentPath, &m_agent, QDBusConnection::ExportAllSlots);
            }
            QDBusMessage m = QDBusMessage::createMethodCall(Service, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("RegisterAgent"));
            m << QVariant::fromValue(QDBusObjectPath(AgentPath)) << QStringLiteral("KeyboardDisplay");
            bus.asyncCall(m);
            refresh(true);
        } else {
            if (!m_adapter.isEmpty() && m_discovering) {
                call(m_adapter, QStringLiteral("org.bluez.Adapter1"), QStringLiteral("StopDiscovery"));
            }
            QDBusMessage m = QDBusMessage::createMethodCall(Service, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("UnregisterAgent"));
            m << QVariant::fromValue(QDBusObjectPath(AgentPath));
            bus.asyncCall(m);
            bus.unregisterObject(AgentPath);
            m_pairing.clear();
        }
    }
    Q_INVOKABLE void setPowered(bool on)
    {
        setProp(m_adapter, QStringLiteral("org.bluez.Adapter1"), QStringLiteral("Powered"), on);
        m_powered = on;
        Q_EMIT changed();
    }
    // Connect when disconnected, disconnect when connected.
    Q_INVOKABLE void toggleConnect(const QString &path)
    {
        if (!m_busy.isEmpty()) {
            return;
        }
        const QVariantMap d = find(path);
        if (d.isEmpty()) {
            return;
        }
        if (path == m_autoPath) {   // the engine is already connecting it
            return;
        }
        m_busy = path;
        Q_EMIT changed();
        const bool conn = d.value(QStringLiteral("connected")).toBool();
        const QString addr = d.value(QStringLiteral("address")).toString();
        if (conn) {
            m_userDisc.insert(addr);     // "off" means off, until the user connects it again
        } else {
            m_userDisc.remove(addr);
            m_fails.remove(addr);
            m_nextTry.remove(addr);
        }
        watch(QDBusConnection::systemBus().asyncCall(method(path, QStringLiteral("org.bluez.Device1"), conn ? QStringLiteral("Disconnect") : QStringLiteral("Connect")), 60000),
              path, conn ? QString() : QStringLiteral("Couldn't connect"));
    }
    Q_INVOKABLE void pair(const QString &path)
    {
        if (!m_busy.isEmpty()) {
            return;
        }
        m_busy = path;
        Q_EMIT changed();
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(method(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Pair")), 90000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, path](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            m_pairing.clear();
            if (err) {
                m_busy.clear();
                Q_EMIT opFailed(path, QStringLiteral("Pairing failed"));
            } else {
                setProp(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Trusted"), true);   // reconnects on its own next time
                watch(QDBusConnection::systemBus().asyncCall(method(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Connect")), 60000), path, QStringLiteral("Paired, but couldn't connect"));
            }
            Q_EMIT changed();
            m_debounce.start();
        });
    }
    // Per-device switch. On by default for every paired device; off is remembered.
    Q_INVOKABLE void setAutoConnect(const QString &path, bool on)
    {
        const QString addr = find(path).value(QStringLiteral("address")).toString();
        if (addr.isEmpty()) {
            return;
        }
        if (on) {
            m_manual.remove(addr);
            m_userDisc.remove(addr);
            m_fails.remove(addr);
            m_nextTry.remove(addr);
            m_auto.start(800);
        } else {
            m_manual.insert(addr);
        }
        if (m_manual.isEmpty()) {
            m_prefs.remove(QStringLiteral("Bluetooth/Manual"));
        } else {
            m_prefs.setValue(QStringLiteral("Bluetooth/Manual"), QStringList(m_manual.begin(), m_manual.end()));
        }
        m_prefs.sync();
        m_debounce.start();
    }
    Q_INVOKABLE void forget(const QString &path)
    {
        const QString addr = find(path).value(QStringLiteral("address")).toString();
        m_userDisc.remove(addr); m_fails.remove(addr); m_nextTry.remove(addr);
        QDBusMessage m = method(m_adapter, QStringLiteral("org.bluez.Adapter1"), QStringLiteral("RemoveDevice"));
        m << QVariant::fromValue(QDBusObjectPath(path));
        QDBusConnection::systemBus().asyncCall(m);
        m_debounce.start();
    }
    Q_INVOKABLE void rename(const QString &path, const QString &alias)
    {
        setProp(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Alias"), alias.trimmed());
        m_debounce.start();
    }
    Q_INVOKABLE void answerConfirm(bool accept) { m_agent.answer(accept); m_pairing.clear(); Q_EMIT changed(); }
    Q_INVOKABLE void answerPin(const QString &pin)
    {
        const bool numeric = m_pairing.value(QStringLiteral("kind")).toString() == QLatin1String("passkey");
        m_agent.answer(true, numeric ? QVariant(pin.toUInt()) : QVariant(pin));
        m_pairing.clear();
        Q_EMIT changed();
    }
    Q_INVOKABLE void cancelPairing()
    {
        m_agent.answer(false);
        m_pairing.clear();
        if (!m_busy.isEmpty()) {
            call(m_busy, QStringLiteral("org.bluez.Device1"), QStringLiteral("CancelPairing"));
        }
        Q_EMIT changed();
    }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_bluetooth")}); }

Q_SIGNALS:
    void changed();
    void devicesChanged();
    void opFailed(const QString &path, const QString &text);

private Q_SLOTS:
    void onSignal(const QDBusMessage &) { m_debounce.start(); }
    // Back from sleep: connections dropped, so try again soon with a clean slate.
    void onSleep(bool starting) { if (!starting) { m_fails.clear(); m_nextTry.clear(); m_auto.start(4000); } }

private:
    static inline const QString Service = QStringLiteral("org.bluez");
    static inline const QString AgentPath = QStringLiteral("/org/aether/island/agent");

    static QDBusMessage method(const QString &path, const QString &iface, const QString &name) { return QDBusMessage::createMethodCall(Service, path, iface, name); }
    static void call(const QString &path, const QString &iface, const QString &name) { QDBusConnection::systemBus().asyncCall(method(path, iface, name)); }
    static void setProp(const QString &path, const QString &iface, const QString &name, const QVariant &v)
    {
        QDBusMessage m = method(path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
        m << iface << name << QVariant::fromValue(QDBusVariant(v));
        QDBusConnection::systemBus().asyncCall(m);
    }
    QVariantMap find(const QString &path) const
    {
        for (const QVariant &v : m_devices) {
            if (v.toMap().value(QStringLiteral("path")).toString() == path) {
                return v.toMap();
            }
        }
        return {};
    }
    void setPairing(const QString &dev, const QString &kind, const QString &code)
    {
        m_pairing = {{QStringLiteral("path"), dev}, {QStringLiteral("name"), find(dev).value(QStringLiteral("name")).toString()},
                     {QStringLiteral("kind"), kind}, {QStringLiteral("code"), code}};
        Q_EMIT changed();
    }
    void watch(const QDBusPendingCall &c, const QString &path, const QString &failText)
    {
        auto *w = new QDBusPendingCallWatcher(c, this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, path, failText](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            m_busy.clear();
            Q_EMIT changed();
            if (err && !failText.isEmpty()) {
                Q_EMIT opFailed(path, failText);
            }
            m_debounce.start();
        });
    }
    void refresh(bool first = false)
    {
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(
            method(QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"))), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, first](QDBusPendingCallWatcher *self) {
            QDBusPendingReply<BluezObjects> r = *self;
            self->deleteLater();
            if (r.isError()) {
                m_adapter.clear();
                Q_EMIT changed();
                return;
            }
            apply(r.value());
            Q_UNUSED(first)
        });
    }
    void apply(const BluezObjects &objs)
    {
        QString adapter, adapterName;
        bool powered = false, discovering = false;
        QVariantList list;
        for (auto it = objs.cbegin(); it != objs.cend(); ++it) {
            const QString path = it.key().path();
            if (it->contains(QStringLiteral("org.bluez.Adapter1")) && adapter.isEmpty()) {
                const QVariantMap a = it->value(QStringLiteral("org.bluez.Adapter1"));
                adapter = path;
                adapterName = a.value(QStringLiteral("Alias")).toString();
                powered = a.value(QStringLiteral("Powered")).toBool();
                discovering = a.value(QStringLiteral("Discovering")).toBool();
            }
            if (it->contains(QStringLiteral("org.bluez.Device1"))) {
                const QVariantMap d = it->value(QStringLiteral("org.bluez.Device1"));
                const QString addr = d.value(QStringLiteral("Address")).toString();
                QString name = d.value(QStringLiteral("Alias")).toString();
                const bool paired = d.value(QStringLiteral("Paired")).toBool();
                // unnamed strangers ("4C-11-...") are noise: show only named or already-paired devices
                if (name.isEmpty() || (!paired && name == QString(addr).replace(QLatin1Char(':'), QLatin1Char('-')))) {
                    if (!paired) { continue; }
                    name = addr;
                }
                list << QVariantMap{{QStringLiteral("path"), path}, {QStringLiteral("name"), name}, {QStringLiteral("address"), addr},
                                    {QStringLiteral("icon"), d.value(QStringLiteral("Icon")).toString()},
                                    {QStringLiteral("paired"), paired},
                                    {QStringLiteral("connected"), d.value(QStringLiteral("Connected")).toBool()},
                                    {QStringLiteral("trusted"), d.value(QStringLiteral("Trusted")).toBool()},
                                    {QStringLiteral("blocked"), d.value(QStringLiteral("Blocked")).toBool()},
                                    {QStringLiteral("auto"), !m_manual.contains(addr)},
                                    {QStringLiteral("paused"), m_userDisc.contains(addr)},
                                    {QStringLiteral("battery"), it->contains(QStringLiteral("org.bluez.Battery1"))
                                         ? int(it->value(QStringLiteral("org.bluez.Battery1")).value(QStringLiteral("Percentage")).toUInt()) : -1}};
                // rssi is deliberately left out: it changes constantly and would re-render the list for nothing
            }
        }
        const bool wasPowered = m_powered, wasDisc = m_discovering;
        // a device that dropped by itself (not because the user disconnected it): try to get it back
        QSet<QString> nowConnected;
        for (const QVariant &v : std::as_const(list)) {
            if (v.toMap().value(QStringLiteral("connected")).toBool()) {
                nowConnected.insert(v.toMap().value(QStringLiteral("address")).toString());
            }
        }
        for (const QString &a : std::as_const(m_wasConnected)) {
            if (!nowConnected.contains(a) && !m_userDisc.contains(a)) {
                m_fails.remove(a); m_nextTry.remove(a);
                m_auto.start(5000);
            }
        }
        m_wasConnected = nowConnected;
        if ((powered && !wasPowered) || !m_engineStarted) {   // adapter switched on, or the first look after start
            m_engineStarted = true;
            m_fails.clear(); m_nextTry.clear();
            m_auto.start(2000);
        } else if (!m_auto.isActive()) {
            m_auto.start(5000);                              // a new device may have appeared
        }
        m_adapter = adapter; m_adapterName = adapterName; m_powered = powered; m_discovering = discovering;
        if (list != m_devices) {
            m_devices = list;
            Q_EMIT devicesChanged();
        }
        if (wasPowered != powered || wasDisc != discovering || true) {
            Q_EMIT changed();
        }
        // Open and powered: look for devices once (again after a power cycle).
        if (!powered || discovering) {
            m_askedDiscovery = discovering;
        }
        if (m_active && powered && !discovering && !m_askedDiscovery) {
            m_askedDiscovery = true;
            call(m_adapter, QStringLiteral("org.bluez.Adapter1"), QStringLiteral("StartDiscovery"));
        }
    }

    // ---- auto-connect engine -------------------------------------------------------------
    // Every paired device reconnects by itself, one at a time, unless its switch is off or the user
    // disconnected it (until they connect it again). A device that does not answer is retried after
    // 30 s, 1 min, 2 min, then every 5 min; powering the adapter, waking from sleep or a dropped link
    // start over. Connect() pages the device itself, so there is no background scanning.
    bool eligible(const QVariantMap &d) const
    {
        const QString addr = d.value(QStringLiteral("address")).toString();
        return d.value(QStringLiteral("paired")).toBool() && !d.value(QStringLiteral("connected")).toBool() && !d.value(QStringLiteral("blocked")).toBool()
               && !m_manual.contains(addr) && !m_userDisc.contains(addr);
    }
    void autoTick()
    {
        if (!m_powered || m_adapter.isEmpty()) {
            m_auto.start(5 * 60 * 1000);
            return;
        }
        if (!m_autoPath.isEmpty() || !m_busy.isEmpty() || !m_pairing.isEmpty()) {
            m_auto.start(10000);   // something else is in flight
            return;
        }
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        qint64 soonest = -1;
        for (const QVariant &v : std::as_const(m_devices)) {
            const QVariantMap d = v.toMap();
            if (!eligible(d)) {
                continue;
            }
            const qint64 due = m_nextTry.value(d.value(QStringLiteral("address")).toString(), 0);
            if (due <= now) {
                attempt(d);
                return;
            }
            soonest = soonest < 0 ? due : qMin(soonest, due);
        }
        m_auto.start(soonest < 0 ? 5 * 60 * 1000 : int(qMax<qint64>(2000, soonest - now)));
    }
    void attempt(const QVariantMap &d)
    {
        const QString path = d.value(QStringLiteral("path")).toString(), addr = d.value(QStringLiteral("address")).toString();
        m_autoPath = path;
        qInfo().noquote() << "bluetooth auto-connect: trying" << d.value(QStringLiteral("name")).toString();
        if (!d.value(QStringLiteral("trusted")).toBool()) {
            setProp(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Trusted"), true);
        }
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(method(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Connect")), 25000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, addr](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            m_autoPath.clear();
            qInfo().noquote() << "bluetooth auto-connect:" << addr << (err ? "no answer, will retry" : "connected");
            if (err) {
                static const int steps[] = {30, 60, 120, 300};
                const int n = m_fails.value(addr, 0) + 1;
                m_fails[addr] = n;
                m_nextTry[addr] = QDateTime::currentMSecsSinceEpoch() + steps[qMin(n - 1, 3)] * 1000LL;
            } else {
                m_fails.remove(addr);
                m_nextTry.remove(addr);
            }
            m_debounce.start();
            m_auto.start(err ? 3000 : 1500);   // the next device, if there is one
        });
    }

    QSettings m_prefs{QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat};
    QTimer m_auto;
    QSet<QString> m_manual, m_userDisc, m_wasConnected;
    QHash<QString, int> m_fails;
    QHash<QString, qint64> m_nextTry;
    QString m_autoPath;
    bool m_engineStarted = false;
    BluezAgent m_agent;
    QTimer m_debounce;
    bool m_askedDiscovery = false;
    bool m_active = false, m_powered = false, m_discovering = false;
    QString m_adapter, m_adapterName, m_busy;
    QVariantList m_devices;
    QVariantMap m_pairing;
};
