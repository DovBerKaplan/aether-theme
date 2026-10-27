// Wi-Fi for the island's panel, straight over NetworkManager's D-Bus API (system bus).
// Event-driven where NM offers signals (device state, property changes, new/removed profiles);
// while the panel is open (setActive) it also re-reads the access points every 3 s and asks
// for a scan every 10 s. Closed, it only follows the signals - an idle island costs nothing.
//
// Secrets: a new network's password goes into the settings map of AddAndActivateConnection
// with psk-flags 0 (system-owned), so no secret agent or wallet prompt is involved. It is
// never logged and never stored by the island.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDesktopServices>
#include <QMap>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

using NMSettings = QMap<QString, QVariantMap>;
Q_DECLARE_METATYPE(NMSettings)

class NetworkModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)           // a Wi-Fi device exists
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
    Q_PROPERTY(QString connectivity READ connectivity NOTIFY changed)  // full | portal | limited | none
    Q_PROPERTY(QString activeSsid READ activeSsid NOTIFY changed)      // connected network, or ""
    Q_PROPERTY(QString connecting READ connecting NOTIFY changed)      // ssid being joined, or ""
    Q_PROPERTY(QString step READ step NOTIFY changed)                  // what the join is doing now
    Q_PROPERTY(bool scanning READ scanning NOTIFY changed)
    // [{ssid, signal 0-100, level 0-4, secure, security, band, saved, connected, inRange, supported}]
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)

public:
    explicit NetworkModel(QObject *parent = nullptr)
        : QObject(parent)
    {
        qDBusRegisterMetaType<NMSettings>();
        m_refresh.setSingleShot(true);
        m_refresh.setInterval(250);
        connect(&m_refresh, &QTimer::timeout, this, [this] { refresh(m_active); });
        m_poll.setInterval(3000);
        connect(&m_poll, &QTimer::timeout, this, [this] { refresh(true); });
        m_scanTimer.setInterval(10000);
        connect(&m_scanTimer, &QTimer::timeout, this, [this] { requestScan(); });
        m_scanDone.setSingleShot(true);
        m_scanDone.setInterval(4000);
        connect(&m_scanDone, &QTimer::timeout, this, [this] { m_scanning = false; Q_EMIT changed(); });
        m_joinTimeout.setSingleShot(true);
        m_joinTimeout.setInterval(45000);
        connect(&m_joinTimeout, &QTimer::timeout, this, [this] { failJoin(QStringLiteral("failed"), QStringLiteral("Network didn't respond")); });

        auto bus = QDBusConnection::systemBus();
        bus.connect(NMService, NMPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"),
                    this, SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        bus.connect(NMService, SettingsPath, SettingsIface, QStringLiteral("NewConnection"), this, SLOT(onProfilesChanged(QDBusObjectPath)));
        bus.connect(NMService, SettingsPath, SettingsIface, QStringLiteral("ConnectionRemoved"), this, SLOT(onProfilesChanged(QDBusObjectPath)));
        QTimer::singleShot(0, this, [this] { refresh(false); });
    }

    bool available() const { return !m_dev.isEmpty(); }
    bool wifiEnabled() const { return m_enabled; }
    QString connectivity() const { return m_connectivity; }
    QString activeSsid() const { return m_activeSsid; }
    QString connecting() const { return m_connecting; }
    QString step() const { return m_step; }
    bool scanning() const { return m_scanning; }
    QVariantList networks() const { return m_networks; }

    // The panel is open: read access points, scan now and every 10 s.
    Q_INVOKABLE void setActive(bool on)
    {
        if (m_active == on) {
            return;
        }
        m_active = on;
        if (on) {
            m_savedDirty = true;
            refresh(true);
            requestScan();
            m_poll.start();
            m_scanTimer.start();
        } else {
            m_poll.stop();
            m_scanTimer.stop();
        }
    }
    Q_INVOKABLE void requestScan()
    {
        if (m_dev.isEmpty() || !m_enabled) {
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, m_dev, WirelessIface, QStringLiteral("RequestScan"));
        m << QVariantMap();
        QDBusConnection::systemBus().asyncCall(m);   // NM rate-limits; a refusal is harmless
        m_scanning = true;
        m_scanDone.start();
        Q_EMIT changed();
    }
    Q_INVOKABLE void setEnabled(bool on)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, NMPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
        m << QStringLiteral("org.freedesktop.NetworkManager") << QStringLiteral("WirelessEnabled") << QVariant::fromValue(QDBusVariant(on));
        QDBusConnection::systemBus().asyncCall(m);
        m_enabled = on;   // optimistic; NM's PropertiesChanged corrects it
        Q_EMIT changed();
    }
    // Join a network. Saved or open: psk may be empty. Otherwise psk is the new password.
    Q_INVOKABLE void connectTo(const QString &ssid, const QString &psk, bool autoconnect = true)
    {
        if (m_dev.isEmpty() || !m_connecting.isEmpty()) {
            return;
        }
        const QVariantMap net = find(ssid);
        if (net.isEmpty()) {
            return;
        }
        if (!net.value(QStringLiteral("supported")).toBool()) {
            Q_EMIT connectFailed(ssid, QStringLiteral("unsupported"), QStringLiteral("This network type needs the system settings"));
            return;
        }
        m_createdConn.clear();
        const QString savedPath = m_saved.value(ssid).path;
        if (!psk.isEmpty() && !savedPath.isEmpty()) {
            deleteProfile(savedPath);   // replacing a stale password: start from a clean profile
        }
        m_usedPsk = !psk.isEmpty();
        beginJoin(ssid);
        if (!savedPath.isEmpty() && psk.isEmpty()) {
            QDBusMessage m = QDBusMessage::createMethodCall(NMService, NMPath, QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("ActivateConnection"));
            m << QVariant::fromValue(QDBusObjectPath(savedPath)) << QVariant::fromValue(QDBusObjectPath(m_dev)) << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));
            watchCall(QDBusConnection::systemBus().asyncCall(m));
            return;
        }
        const QString security = net.value(QStringLiteral("security")).toString();
        const bool open = security == QLatin1String("Open");
        if (!open && psk.isEmpty()) {
            m_connecting.clear();
            Q_EMIT connectFailed(ssid, QStringLiteral("password"), QStringLiteral("Enter the password"));
            Q_EMIT changed();
            return;
        }
        NMSettings s;
        s[QStringLiteral("connection")] = {{QStringLiteral("type"), QStringLiteral("802-11-wireless")},
                                           {QStringLiteral("id"), ssid},
                                           {QStringLiteral("autoconnect"), autoconnect}};
        s[QStringLiteral("802-11-wireless")] = {{QStringLiteral("ssid"), ssid.toUtf8()},
                                                {QStringLiteral("mode"), QStringLiteral("infrastructure")}};
        if (!open) {
            s[QStringLiteral("802-11-wireless-security")] = {
                {QStringLiteral("key-mgmt"), security == QLatin1String("WPA3") ? QStringLiteral("sae") : QStringLiteral("wpa-psk")},
                {QStringLiteral("psk"), psk},
                {QStringLiteral("psk-flags"), 0u}};   // 0 = stored by NetworkManager, no agent needed
        }
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, NMPath, QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("AddAndActivateConnection"));
        m << QVariant::fromValue(s) << QVariant::fromValue(QDBusObjectPath(m_dev))
          << QVariant::fromValue(QDBusObjectPath(net.value(QStringLiteral("apPath")).toString().isEmpty() ? QStringLiteral("/") : net.value(QStringLiteral("apPath")).toString()));
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *self) {
            QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> r = *self;
            self->deleteLater();
            if (r.isError()) {
                failJoin(QStringLiteral("failed"), QStringLiteral("Couldn't start the connection"));
            } else {
                m_createdConn = r.argumentAt<0>().path();
            }
        });
    }
    Q_INVOKABLE void cancel()
    {
        if (m_connecting.isEmpty()) {
            return;
        }
        const QString ac = devProp(DeviceIface, QStringLiteral("ActiveConnection")).value<QDBusObjectPath>().path();
        if (!ac.isEmpty() && ac != QLatin1String("/")) {
            QDBusMessage m = QDBusMessage::createMethodCall(NMService, NMPath, QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("DeactivateConnection"));
            m << QVariant::fromValue(QDBusObjectPath(ac));
            QDBusConnection::systemBus().asyncCall(m);
        }
        if (!m_createdConn.isEmpty()) {
            deleteProfile(m_createdConn);
        }
        endJoin();
    }
    Q_INVOKABLE void disconnectActive()
    {
        if (!m_dev.isEmpty()) {
            QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(NMService, m_dev, DeviceIface, QStringLiteral("Disconnect")));
        }
    }
    Q_INVOKABLE void forget(const QString &ssid)
    {
        for (const Saved &p : m_saved.values(ssid)) {
            deleteProfile(p.path);
        }
        m_savedDirty = true;
        scheduleRefresh();
    }
    // [{key, value}] for the detail page; the network-level lines exist for any network,
    // the address lines only while connected.
    Q_INVOKABLE QVariantList details(const QString &ssid)
    {
        QVariantList out;
        auto add = [&out](const QString &k, const QString &v) {
            if (!v.isEmpty()) {
                out << QVariantMap{{QStringLiteral("key"), k}, {QStringLiteral("value"), v}};
            }
        };
        const QVariantMap net = find(ssid);
        add(QStringLiteral("Security"), net.value(QStringLiteral("security")).toString());
        if (!net.value(QStringLiteral("connected")).toBool()) {
            return out;
        }
        add(QStringLiteral("Signal"), QString::number(net.value(QStringLiteral("signal")).toInt()) + QStringLiteral(" %"));
        const QString band = net.value(QStringLiteral("band")).toString();
        add(QStringLiteral("Frequency"), band.isEmpty() ? QString() : band + QStringLiteral(" GHz"));
        const uint rate = devProp(WirelessIface, QStringLiteral("Bitrate")).toUInt();   // kbit/s
        add(QStringLiteral("Link speed"), rate ? QString::number(rate / 1000) + QStringLiteral(" Mb/s") : QString());
        const QString ac = devProp(DeviceIface, QStringLiteral("ActiveConnection")).value<QDBusObjectPath>().path();
        const QString ip4 = ac.isEmpty() ? QString() : propOf(ac, QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"), QStringLiteral("Ip4Config")).value<QDBusObjectPath>().path();
        if (!ip4.isEmpty() && ip4 != QLatin1String("/")) {
            const QVariantMap c = getAll(ip4, QStringLiteral("org.freedesktop.NetworkManager.IP4Config"));
            const auto addrs = cast<QList<QVariantMap>>(c.value(QStringLiteral("AddressData")));
            if (!addrs.isEmpty()) {
                add(QStringLiteral("IP address"), addrs.first().value(QStringLiteral("address")).toString());
            }
            add(QStringLiteral("Gateway"), c.value(QStringLiteral("Gateway")).toString());
            QStringList dns;
            for (const QVariantMap &d : cast<QList<QVariantMap>>(c.value(QStringLiteral("NameserverData")))) {
                dns << d.value(QStringLiteral("address")).toString();
            }
            add(QStringLiteral("DNS"), dns.join(QStringLiteral(", ")));
        }
        add(QStringLiteral("MAC address"), devProp(DeviceIface, QStringLiteral("HwAddress")).toString());
        return out;
    }
    // Captive portal: open NetworkManager's own connectivity-check URI (the portal intercepts it).
    Q_INVOKABLE void openPortal()
    {
        const QString uri = propOf(NMPath, QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("ConnectivityCheckUri")).toString();
        QDesktopServices::openUrl(QUrl(uri.isEmpty() ? QStringLiteral("http://nmcheck.gnome.org/check_network_status.txt") : uri));
    }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_networkmanagement")}); }

Q_SIGNALS:
    void changed();
    void networksChanged();
    // kind: "password" | "unsupported" | "failed"
    void connectFailed(const QString &ssid, const QString &kind, const QString &text);
    void connected(const QString &ssid);

private Q_SLOTS:
    void onPropertiesChanged(const QString &, const QVariantMap &, const QStringList &) { scheduleRefresh(); }
    void onProfilesChanged(const QDBusObjectPath &) { m_savedDirty = true; scheduleRefresh(); }
    void onDeviceState(uint state, uint old, uint reason)
    {
        if (!m_connecting.isEmpty()) {
            switch (state) {
            case 40: case 50: m_step = QStringLiteral("Connecting…"); break;
            case 60: m_step = QStringLiteral("Authenticating…"); break;
            case 70: m_step = QStringLiteral("Getting address…"); break;
            case 80: case 90: m_step = QStringLiteral("Checking internet…"); break;
            default: break;
            }
            if (state == 100) {
                const QString ssid = m_connecting;
                endJoin();
                Q_EMIT connected(ssid);
            } else if (state == 120 || (state == 30 && old >= 40 && old <= 90)) {
                // 7 no secrets, 8-11 supplicant: the password was refused. 5/6: no address.
                if (reason >= 7 && reason <= 11) {
                    failJoin(QStringLiteral("password"), QStringLiteral("Wrong password. Try again."));
                } else if (reason == 5 || reason == 6) {
                    failJoin(QStringLiteral("failed"), QStringLiteral("No IP address — try again or move closer"));
                } else if (reason == 53) {
                    failJoin(QStringLiteral("failed"), QStringLiteral("Network not found"));
                } else {
                    failJoin(QStringLiteral("failed"), QStringLiteral("Couldn't connect"));
                }
            }
            Q_EMIT changed();
        }
        scheduleRefresh();
    }

private:
    struct Saved { QString path; QString uuid; };

    static inline const QString NMService = QStringLiteral("org.freedesktop.NetworkManager");
    static inline const QString NMPath = QStringLiteral("/org/freedesktop/NetworkManager");
    static inline const QString SettingsPath = QStringLiteral("/org/freedesktop/NetworkManager/Settings");
    static inline const QString SettingsIface = QStringLiteral("org.freedesktop.NetworkManager.Settings");
    static inline const QString DeviceIface = QStringLiteral("org.freedesktop.NetworkManager.Device");
    static inline const QString WirelessIface = QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless");
    static inline const QString ApIface = QStringLiteral("org.freedesktop.NetworkManager.AccessPoint");

    template<typename T> static T cast(const QVariant &v)
    {
        return v.canConvert<QDBusArgument>() ? qdbus_cast<T>(v.value<QDBusArgument>()) : v.value<T>();
    }
    static QDBusMessage blockingCall(QDBusMessage m) { return QDBusConnection::systemBus().call(m, QDBus::Block, 2000); }
    QVariantMap getAll(const QString &path, const QString &iface) const
    {
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
        m << iface;
        const QDBusMessage r = blockingCall(m);
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
                   ? qdbus_cast<QVariantMap>(r.arguments().first().value<QDBusArgument>()) : QVariantMap();
    }
    QVariant propOf(const QString &path, const QString &iface, const QString &name) const
    {
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        m << iface << name;
        const QDBusMessage r = blockingCall(m);
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
                   ? r.arguments().first().value<QDBusVariant>().variant() : QVariant();
    }
    QVariant devProp(const QString &iface, const QString &name) const { return m_dev.isEmpty() ? QVariant() : propOf(m_dev, iface, name); }
    void scheduleRefresh() { m_refresh.start(); }
    QVariantMap find(const QString &ssid) const
    {
        for (const QVariant &v : m_networks) {
            if (v.toMap().value(QStringLiteral("ssid")).toString() == ssid) {
                return v.toMap();
            }
        }
        return {};
    }
    void deleteProfile(const QString &path)
    {
        QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(NMService, path, QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("Delete")));
    }
    void beginJoin(const QString &ssid)
    {
        m_connecting = ssid;
        m_step = QStringLiteral("Connecting…");
        m_joinTimeout.start();
        Q_EMIT changed();
    }
    void endJoin()
    {
        m_connecting.clear();
        m_step.clear();
        m_createdConn.clear();
        m_usedPsk = false;
        m_joinTimeout.stop();
        Q_EMIT changed();
        scheduleRefresh();
    }
    void failJoin(const QString &kind, const QString &text)
    {
        if (m_connecting.isEmpty()) {
            return;
        }
        const QString ssid = m_connecting;
        // A profile made for this attempt must not outlive a failed one (a wrong password is never saved).
        if (!m_createdConn.isEmpty()) {
            deleteProfile(m_createdConn);
            m_savedDirty = true;
        }
        endJoin();
        Q_EMIT connectFailed(ssid, kind, text);
    }
    void watchCall(const QDBusPendingCall &call)
    {
        auto *w = new QDBusPendingCallWatcher(call, this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            if (err) {
                failJoin(QStringLiteral("failed"), QStringLiteral("Couldn't start the connection"));
            }
        });
    }
    void ensureDevice()
    {
        if (!m_dev.isEmpty()) {
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, NMPath, QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("GetDevices"));
        const QDBusReply<QList<QDBusObjectPath>> r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        if (!r.isValid()) {
            return;
        }
        for (const QDBusObjectPath &p : r.value()) {
            if (propOf(p.path(), DeviceIface, QStringLiteral("DeviceType")).toUInt() == 2) {   // NM_DEVICE_TYPE_WIFI
                m_dev = p.path();
                QDBusConnection::systemBus().connect(NMService, m_dev, DeviceIface, QStringLiteral("StateChanged"), this, SLOT(onDeviceState(uint, uint, uint)));
                break;
            }
        }
    }
    void loadSaved()
    {
        m_saved.clear();
        QDBusMessage m = QDBusMessage::createMethodCall(NMService, SettingsPath, SettingsIface, QStringLiteral("ListConnections"));
        const QDBusReply<QList<QDBusObjectPath>> r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        if (!r.isValid()) {
            return;
        }
        for (const QDBusObjectPath &p : r.value()) {
            QDBusMessage g = QDBusMessage::createMethodCall(NMService, p.path(), QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("GetSettings"));
            const QDBusMessage reply = blockingCall(g);
            if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
                continue;
            }
            const NMSettings s = qdbus_cast<NMSettings>(reply.arguments().first().value<QDBusArgument>());
            if (!s.contains(QStringLiteral("802-11-wireless"))) {
                continue;
            }
            const QString ssid = QString::fromUtf8(s.value(QStringLiteral("802-11-wireless")).value(QStringLiteral("ssid")).toByteArray());
            if (!ssid.isEmpty()) {
                m_saved.insert(ssid, {p.path(), s.value(QStringLiteral("connection")).value(QStringLiteral("uuid")).toString()});
            }
        }
        m_savedDirty = false;
    }
    static QString securityOf(uint flags, uint wpa, uint rsn)
    {
        if ((wpa | rsn) & 0x200) {
            return QStringLiteral("Enterprise");   // 802.1X: needs certificates, left to the KDE settings
        }
        if (rsn & 0x400) {
            return QStringLiteral("WPA3");
        }
        if (rsn & 0x100) {
            return QStringLiteral("WPA2");
        }
        if (wpa & 0x100) {
            return QStringLiteral("WPA");
        }
        return (flags & 1) ? QStringLiteral("WEP") : QStringLiteral("Open");
    }

    void refresh(bool full)
    {
        const QVariantMap nm = getAll(NMPath, QStringLiteral("org.freedesktop.NetworkManager"));
        const bool had = !m_dev.isEmpty();
        if (nm.isEmpty()) {
            m_dev.clear();
            if (had) { Q_EMIT changed(); }
            return;
        }
        ensureDevice();
        m_enabled = nm.value(QStringLiteral("WirelessEnabled")).toBool();
        switch (nm.value(QStringLiteral("Connectivity")).toUInt()) {
        case 4: m_connectivity = QStringLiteral("full"); break;
        case 2: m_connectivity = QStringLiteral("portal"); break;
        case 3: m_connectivity = QStringLiteral("limited"); break;
        default: m_connectivity = QStringLiteral("none"); break;
        }
        QString activeAp;
        uint devState = 0;
        if (!m_dev.isEmpty()) {
            devState = devProp(DeviceIface, QStringLiteral("State")).toUInt();
            activeAp = devProp(WirelessIface, QStringLiteral("ActiveAccessPoint")).value<QDBusObjectPath>().path();
        }
        if (full || m_active) {
            if (m_savedDirty) {
                loadSaved();
            }
            QMap<QString, QVariantMap> best;
            QSet<QString> connectedSsids;
            if (!m_dev.isEmpty() && m_enabled) {
                QDBusMessage m = QDBusMessage::createMethodCall(NMService, m_dev, WirelessIface, QStringLiteral("GetAccessPoints"));
                const QDBusReply<QList<QDBusObjectPath>> aps = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
                for (const QDBusObjectPath &ap : aps.isValid() ? aps.value() : QList<QDBusObjectPath>()) {
                    const QVariantMap p = getAll(ap.path(), ApIface);
                    const QString ssid = QString::fromUtf8(p.value(QStringLiteral("Ssid")).toByteArray()).trimmed();
                    if (ssid.isEmpty()) {
                        continue;   // hidden: the "Add hidden network" row covers those
                    }
                    const int sig = p.value(QStringLiteral("Strength")).toInt();
                    if (ap.path() == activeAp && devState == 100) {
                        connectedSsids.insert(ssid);
                    }
                    if (best.contains(ssid) && best.value(ssid).value(QStringLiteral("signal")).toInt() >= sig) {
                        continue;
                    }
                    const uint freq = p.value(QStringLiteral("Frequency")).toUInt();
                    const QString sec = securityOf(p.value(QStringLiteral("Flags")).toUInt(), p.value(QStringLiteral("WpaFlags")).toUInt(), p.value(QStringLiteral("RsnFlags")).toUInt());
                    best[ssid] = {{QStringLiteral("ssid"), ssid},
                                  {QStringLiteral("signal"), sig},
                                  {QStringLiteral("level"), sig > 75 ? 4 : sig > 50 ? 3 : sig > 25 ? 2 : 1},
                                  {QStringLiteral("secure"), sec != QLatin1String("Open")},
                                  {QStringLiteral("security"), sec},
                                  {QStringLiteral("band"), freq >= 5925 ? QStringLiteral("6") : freq >= 4900 ? QStringLiteral("5") : QStringLiteral("2.4")},
                                  {QStringLiteral("inRange"), true},
                                  {QStringLiteral("supported"), sec != QLatin1String("Enterprise") && sec != QLatin1String("WEP")},
                                  {QStringLiteral("apPath"), ap.path()}};
                }
            }
            for (auto it = m_saved.cbegin(); it != m_saved.cend(); ++it) {   // saved but out of range
                if (!best.contains(it.key())) {
                    best[it.key()] = {{QStringLiteral("ssid"), it.key()}, {QStringLiteral("signal"), 0}, {QStringLiteral("level"), 0},
                                      {QStringLiteral("secure"), true}, {QStringLiteral("security"), QStringLiteral("WPA2")}, {QStringLiteral("band"), QString()},
                                      {QStringLiteral("inRange"), false}, {QStringLiteral("supported"), true}, {QStringLiteral("apPath"), QString()}};
                }
            }
            QList<QVariantMap> list;
            for (QVariantMap n : std::as_const(best)) {
                const QString ssid = n.value(QStringLiteral("ssid")).toString();
                n[QStringLiteral("saved")] = m_saved.contains(ssid);
                n[QStringLiteral("connected")] = connectedSsids.contains(ssid);
                list << n;
            }
            std::sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
                if (a.value(QStringLiteral("connected")).toBool() != b.value(QStringLiteral("connected")).toBool()) {
                    return a.value(QStringLiteral("connected")).toBool();
                }
                if (a.value(QStringLiteral("inRange")).toBool() != b.value(QStringLiteral("inRange")).toBool()) {
                    return a.value(QStringLiteral("inRange")).toBool();
                }
                const int sa = a.value(QStringLiteral("signal")).toInt(), sb = b.value(QStringLiteral("signal")).toInt();
                return sa != sb ? sa > sb : a.value(QStringLiteral("ssid")).toString() < b.value(QStringLiteral("ssid")).toString();
            });
            QVariantList out;
            for (const QVariantMap &n : list) {
                out << n;
            }
            if (out != m_networks) {
                m_networks = out;
                Q_EMIT networksChanged();
            }
            m_activeSsid = connectedSsids.isEmpty() ? QString() : *connectedSsids.cbegin();
        } else {
            // Closed panel: only the bar/chip need the connected name - one read, no scan data.
            m_activeSsid = (devState == 100 && !activeAp.isEmpty() && activeAp != QLatin1String("/"))
                ? QString::fromUtf8(propOf(activeAp, ApIface, QStringLiteral("Ssid")).toByteArray()).trimmed() : QString();
        }
        Q_EMIT changed();
    }

    QTimer m_refresh, m_poll, m_scanTimer, m_scanDone, m_joinTimeout;
    QString m_dev, m_connectivity = QStringLiteral("none"), m_activeSsid, m_connecting, m_step, m_createdConn;
    bool m_enabled = false, m_active = false, m_scanning = false, m_savedDirty = true, m_usedPsk = false;
    QVariantList m_networks;
    QMultiMap<QString, Saved> m_saved;
};
