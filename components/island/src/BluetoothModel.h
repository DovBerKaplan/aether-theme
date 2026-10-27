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
#include <QMap>
#include <QObject>
#include <QProcess>
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
        m_busy = path;
        Q_EMIT changed();
        const bool conn = d.value(QStringLiteral("connected")).toBool();
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
    Q_INVOKABLE void forget(const QString &path)
    {
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
    void onSignal(const QDBusMessage &) { if (m_active) { m_debounce.start(); } }

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
                                    {QStringLiteral("battery"), it->contains(QStringLiteral("org.bluez.Battery1"))
                                         ? int(it->value(QStringLiteral("org.bluez.Battery1")).value(QStringLiteral("Percentage")).toUInt()) : -1}};
                // rssi is deliberately left out: it changes constantly and would re-render the list for nothing
            }
        }
        const bool wasPowered = m_powered, wasDisc = m_discovering;
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

    BluezAgent m_agent;
    QTimer m_debounce;
    bool m_askedDiscovery = false;
    bool m_active = false, m_powered = false, m_discovering = false;
    QString m_adapter, m_adapterName, m_busy;
    QVariantList m_devices;
    QVariantMap m_pairing;
};
