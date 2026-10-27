// KDE Connect for the island's widget and panel, straight over the daemon's D-Bus API
// (session bus, org.kde.kdeconnect). No KDE Connect library: the daemon's introspection has a
// duplicate-method bug, so every call is a plain QDBusMessage, never a QDBusInterface.
//
// Event-driven: the daemon's own signals (devices, pairing, battery, notifications, property
// changes) schedule one debounced refresh; nothing polls. Actions are fire-and-forget; whether a
// phone rings or buzzes is the UI's business (two-tap for the loud ones).
//
// AETHER_CONNECT_FAKE=1 swaps the daemon for a fixture, so every screen can be built and shot
// without touching a real phone; actions then only record what they would have done.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDateTime>
#include <QFile>
#include <QHash>
#include <QDir>
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class ConnectModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)             // the daemon is running (or the fixture is on)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)
    Q_PROPERTY(QString selectedId READ selectedId NOTIFY changed)
    Q_PROPERTY(QVariantMap selected READ selected NOTIFY changed)        // the device the card shows, or {}
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)   // the selected phone's, newest first; filled only while watched
    Q_PROPERTY(QVariantMap lastAction READ lastAction NOTIFY lastActionChanged)   // {kind, device} of the latest action

public:
    explicit ConnectModel(QObject *parent = nullptr)
        : QObject(parent)
        , m_fake(qEnvironmentVariableIntValue("AETHER_CONNECT_FAKE") != 0)
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] { refresh(); });
        if (!m_fake) {
            auto bus = QDBusConnection::sessionBus();
            const QString daemon = QStringLiteral("org.kde.kdeconnect.daemon");
            for (const char *sig : {"deviceAdded", "deviceRemoved", "deviceVisibilityChanged", "deviceListChanged", "pairingRequestsChanged"}) {
                bus.connect(Service, DaemonPath, daemon, QLatin1String(sig), this, SLOT(onAny(QDBusMessage)));
            }
            bus.connect(Service, QString(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this, SLOT(onAny(QDBusMessage)));
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.battery"), QStringLiteral("refreshed"), this, SLOT(onAny(QDBusMessage)));
            for (const char *sig : {"notificationPosted", "notificationRemoved", "notificationUpdated", "allNotificationsRemoved"}) {
                bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.notifications"), QLatin1String(sig), this, SLOT(onAny(QDBusMessage)));
            }
            // the daemon may start after us (or restart)
            auto *w = new QDBusServiceWatcher(Service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
            connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] { m_debounce.start(); });
        }
        QTimer::singleShot(0, this, [this] { refresh(); });
    }

    bool available() const { return m_available; }
    QVariantList devices() const { return m_devices; }
    QString selectedId() const { return m_selectedId; }
    QVariantMap selected() const { return find(m_selectedId); }
    QVariantMap lastAction() const { return m_lastAction; }
    QVariantList notifications() const { return m_notifs; }

    // The Notifications page is open: read the full list (and keep it fresh from the daemon's signals).
    // Closed, only the count is read - a phone can hold dozens of notifications.
    Q_INVOKABLE void watchNotifications(bool on)
    {
        if (m_watchNotifs == on) {
            return;
        }
        m_watchNotifs = on;
        if (on) {
            m_debounce.start();
        } else {
            m_notifs.clear();
            Q_EMIT notificationsChanged();
        }
    }
    Q_INVOKABLE void dismissNotification(const QString &id, const QString &notifId)
    {
        if (m_fake) {
            for (int i = 0; i < m_notifs.size(); ++i) {
                if (m_notifs.at(i).toMap().value(QStringLiteral("id")).toString() == notifId) {
                    m_notifs.removeAt(i);
                    break;
                }
            }
            bumpCount(id, m_notifs.size());
            Q_EMIT notificationsChanged();
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/notifications/") + notifId,
                                                        QStringLiteral("org.kde.kdeconnect.device.notifications.notification"), QStringLiteral("dismiss"));
        QDBusConnection::sessionBus().asyncCall(m);
        m_debounce.start();
    }
    Q_INVOKABLE void clearNotifications(const QString &id)
    {
        record(QStringLiteral("dismiss-all"), id);
        const QVariantList all = m_notifs;
        for (const QVariant &v : all) {
            if (v.toMap().value(QStringLiteral("dismissable")).toBool()) {
                dismissNotification(id, v.toMap().value(QStringLiteral("id")).toString());
            }
        }
    }
    // Answer a notification that offers a reply (a message app): the phone sends it from its own app.
    Q_INVOKABLE void replyToNotification(const QString &id, const QString &replyId, const QString &text)
    {
        if (!replyId.isEmpty() && !text.trimmed().isEmpty()) {
            plugin(id, QStringLiteral("notifications"), QStringLiteral("sendReply"), {replyId, text}, QStringLiteral("reply"));
        }
    }
    // A button the notification itself carries (Archive, Mark as read...).
    Q_INVOKABLE void notificationAction(const QString &id, const QString &internalId, const QString &action)
    {
        plugin(id, QStringLiteral("notifications"), QStringLiteral("sendAction"), {internalId, action}, QStringLiteral("action"));
    }

    // The card follows this device from now on (saved).
    Q_INVOKABLE void select(const QString &id)
    {
        m_prefs.setValue(QStringLiteral("Connect/Device"), id);
        m_prefs.sync();
        pickSelected();
        Q_EMIT changed();
    }
    // Next paired device after the selected one (reachable ones first, as listed).
    Q_INVOKABLE void selectNext()
    {
        QStringList paired;
        for (const QVariant &v : std::as_const(m_devices)) {
            if (v.toMap().value(QStringLiteral("paired")).toBool()) {
                paired << v.toMap().value(QStringLiteral("id")).toString();
            }
        }
        if (paired.size() > 1) {
            select(paired.at((paired.indexOf(m_selectedId) + 1) % paired.size()));
        }
    }

    // ---- actions: the loud ones are gated in the UI, not here --------------------------------
    Q_INVOKABLE void ring(const QString &id) { plugin(id, QStringLiteral("findmyphone"), QStringLiteral("ring"), {}, QStringLiteral("ring")); }
    Q_INVOKABLE void ping(const QString &id) { plugin(id, QStringLiteral("ping"), QStringLiteral("sendPing"), {}, QStringLiteral("ping")); }
    Q_INVOKABLE void sendClipboard(const QString &id) { plugin(id, QStringLiteral("clipboard"), QStringLiteral("sendClipboard"), {}, QStringLiteral("clipboard")); }
    Q_INVOKABLE void shareText(const QString &id, const QString &text)
    {
        if (!text.trimmed().isEmpty()) {
            plugin(id, QStringLiteral("share"), QStringLiteral("shareText"), {text}, QStringLiteral("share"));
        }
    }
    Q_INVOKABLE void shareUrl(const QString &id, const QString &url)
    {
        if (!url.trimmed().isEmpty()) {
            plugin(id, QStringLiteral("share"), QStringLiteral("shareUrl"), {url}, QStringLiteral("share"));
        }
    }
    Q_INVOKABLE void requestPairing(const QString &id) { deviceCall(id, QStringLiteral("requestPairing"), {}, QStringLiteral("pairing")); }
    Q_INVOKABLE void acceptPairing(const QString &id) { deviceCall(id, QStringLiteral("acceptPairing"), {}, QStringLiteral("paired")); }
    Q_INVOKABLE void cancelPairing(const QString &id) { deviceCall(id, QStringLiteral("cancelPairing"), {}, QStringLiteral("pairing-cancelled")); }
    Q_INVOKABLE void unpair(const QString &id) { deviceCall(id, QStringLiteral("unpair"), {}, QStringLiteral("unpaired")); }
    Q_INVOKABLE void setPluginEnabled(const QString &id, const QString &key, bool on)
    {
        deviceCall(id, QStringLiteral("setPluginEnabled"), {key, on}, QString());
        if (m_fake) {
            for (QVariant &v : m_devices) {
                QVariantMap d = v.toMap();
                if (d.value(QStringLiteral("id")).toString() == id) {
                    QVariantMap p = d.value(QStringLiteral("pluginState")).toMap();
                    p[key] = on;
                    d[QStringLiteral("pluginState")] = p;
                    v = d;
                }
            }
            Q_EMIT changed();
        }
    }
    // [{key, enabled}] for the features the Settings section offers; unsupported ones are left out.
    Q_INVOKABLE QVariantList plugins(const QString &id) const
    {
        static const QStringList wanted = {QStringLiteral("kdeconnect_notifications"), QStringLiteral("kdeconnect_clipboard"), QStringLiteral("kdeconnect_battery"),
                                           QStringLiteral("kdeconnect_share"), QStringLiteral("kdeconnect_sftp"), QStringLiteral("kdeconnect_findmyphone"),
                                           QStringLiteral("kdeconnect_ping"), QStringLiteral("kdeconnect_sms"), QStringLiteral("kdeconnect_mprisremote"),
                                           QStringLiteral("kdeconnect_telephony"), QStringLiteral("kdeconnect_contacts"), QStringLiteral("kdeconnect_remotekeyboard")};
        const QVariantMap d = find(id);
        const QStringList supported = d.value(QStringLiteral("supported")).toStringList();
        QVariantList out;
        for (const QString &k : wanted) {
            if (supported.contains(k)) {
                out << QVariantMap{{QStringLiteral("key"), k}, {QStringLiteral("enabled"), d.value(QStringLiteral("pluginState")).toMap().value(k).toBool()}};
            }
        }
        return out;
    }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kdeconnect")}); }

Q_SIGNALS:
    void changed();
    void lastActionChanged();
    void notificationsChanged();

private Q_SLOTS:
    void onAny(const QDBusMessage &) { m_debounce.start(); }

private:
    static inline const QString Service = QStringLiteral("org.kde.kdeconnect");
    static inline const QString DaemonPath = QStringLiteral("/modules/kdeconnect");
    static QString devPath(const QString &id) { return DaemonPath + QStringLiteral("/devices/") + id; }

    QVariantMap find(const QString &id) const
    {
        for (const QVariant &v : m_devices) {
            if (v.toMap().value(QStringLiteral("id")).toString() == id) {
                return v.toMap();
            }
        }
        return {};
    }
    static QDBusMessage blocking(QDBusMessage m) { return QDBusConnection::sessionBus().call(m, QDBus::Block, 1500); }
    static QVariantMap getAll(const QString &path, const QString &iface)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(Service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
        m << iface;
        const QDBusMessage r = blocking(m);
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
                   ? qdbus_cast<QVariantMap>(r.arguments().first().value<QDBusArgument>()) : QVariantMap();
    }
    static QStringList stringList(const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
    {
        QDBusMessage m = QDBusMessage::createMethodCall(Service, path, iface, method);
        m.setArguments(args);
        const QDBusReply<QStringList> r = QDBusConnection::sessionBus().call(m, QDBus::Block, 1500);
        return r.isValid() ? r.value() : QStringList();
    }
    void record(const QString &kind, const QString &id)
    {
        m_lastAction = {{QStringLiteral("kind"), kind}, {QStringLiteral("device"), find(id).value(QStringLiteral("name")).toString()}};
        qInfo().noquote() << "kdeconnect:" << kind << find(id).value(QStringLiteral("name")).toString() << (m_fake ? "(fake: nothing sent)" : "");
        Q_EMIT lastActionChanged();
    }
    void plugin(const QString &id, const QString &object, const QString &method, const QVariantList &args, const QString &kind)
    {
        record(kind, id);
        if (m_fake) {
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QLatin1Char('/') + object,
                                                        QStringLiteral("org.kde.kdeconnect.device.") + object, method);
        m.setArguments(args);
        QDBusConnection::sessionBus().asyncCall(m);
    }
    void deviceCall(const QString &id, const QString &method, const QVariantList &args, const QString &kind)
    {
        if (!kind.isEmpty()) {
            record(kind, id);
        }
        if (m_fake) {
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id), QStringLiteral("org.kde.kdeconnect.device"), method);
        m.setArguments(args);
        QDBusConnection::sessionBus().asyncCall(m);
        m_debounce.start();
    }
    void pickSelected()
    {
        const QString saved = m_prefs.value(QStringLiteral("Connect/Device")).toString();
        QString pick;
        if (!saved.isEmpty() && !find(saved).isEmpty() && find(saved).value(QStringLiteral("paired")).toBool()) {
            pick = saved;
        }
        // the saved one is only a preference: if another paired device is reachable and the saved one is not, follow reachability
        if (pick.isEmpty() || !find(pick).value(QStringLiteral("reachable")).toBool()) {
            for (const QVariant &v : std::as_const(m_devices)) {
                const QVariantMap d = v.toMap();
                if (d.value(QStringLiteral("paired")).toBool() && d.value(QStringLiteral("reachable")).toBool()) {
                    pick = d.value(QStringLiteral("id")).toString();
                    break;
                }
            }
        }
        if (pick.isEmpty()) {
            for (const QVariant &v : std::as_const(m_devices)) {
                if (v.toMap().value(QStringLiteral("paired")).toBool()) {
                    pick = v.toMap().value(QStringLiteral("id")).toString();
                    break;
                }
            }
        }
        m_selectedId = pick;
    }

    void refresh()
    {
        if (m_fake) {
            m_available = true;
            if (m_devices.isEmpty()) {
                m_devices = fixture();
            }
            pickSelected();
            if (m_watchNotifs && m_notifs.isEmpty() && m_selectedId == QLatin1String("fake-phone") && !m_fakeNotifsServed) {
                m_fakeNotifsServed = true;
                m_notifs = fixtureNotifications();
                Q_EMIT notificationsChanged();
            }
            Q_EMIT changed();
            return;
        }
        auto *bus = QDBusConnection::sessionBus().interface();
        m_available = bus && bus->isServiceRegistered(Service).value();
        QVariantList list;
        if (m_available) {
            const QStringList ids = stringList(DaemonPath, QStringLiteral("org.kde.kdeconnect.daemon"), QStringLiteral("devices"), {false, false});
            for (const QString &id : ids) {
                const QString p = devPath(id);
                const QVariantMap dp = getAll(p, QStringLiteral("org.kde.kdeconnect.device"));
                if (dp.isEmpty()) {
                    continue;
                }
                const bool paired = dp.value(QStringLiteral("isPaired")).toBool(), reachable = dp.value(QStringLiteral("isReachable")).toBool();
                const QStringList loaded = paired && reachable ? stringList(p, QStringLiteral("org.kde.kdeconnect.device"), QStringLiteral("loadedPlugins")) : QStringList();
                const QStringList supported = dp.value(QStringLiteral("supportedPlugins")).toStringList();
                int charge = -1, strength = -1, notifs = 0;
                bool charging = false;
                QString net;
                if (loaded.contains(QStringLiteral("kdeconnect_battery"))) {
                    const QVariantMap b = getAll(p + QStringLiteral("/battery"), QStringLiteral("org.kde.kdeconnect.device.battery"));
                    if (b.value(QStringLiteral("hasBattery")).toBool()) {
                        charge = b.value(QStringLiteral("charge")).toInt();
                        charging = b.value(QStringLiteral("isCharging")).toBool();
                    }
                }
                if (loaded.contains(QStringLiteral("kdeconnect_connectivity_report"))) {
                    const QVariantMap c = getAll(p + QStringLiteral("/connectivity_report"), QStringLiteral("org.kde.kdeconnect.device.connectivity_report"));
                    net = c.value(QStringLiteral("cellularNetworkType")).toString();
                    strength = c.value(QStringLiteral("cellularNetworkStrength")).toInt();
                }
                if (loaded.contains(QStringLiteral("kdeconnect_notifications"))) {
                    notifs = stringList(p + QStringLiteral("/notifications"), QStringLiteral("org.kde.kdeconnect.device.notifications"), QStringLiteral("activeNotifications")).size();
                }
                QVariantMap pluginState;
                for (const QString &k : supported) {
                    pluginState[k] = !paired ? false : loaded.contains(k) || !reachable ? loaded.contains(k) : false;
                }
                if (paired && !reachable) {   // not loaded because offline: ask the daemon what is switched on
                    for (const QString &k : supported) {
                        QDBusMessage q = QDBusMessage::createMethodCall(Service, p, QStringLiteral("org.kde.kdeconnect.device"), QStringLiteral("isPluginEnabled"));
                        q << k;
                        const QDBusReply<bool> r = QDBusConnection::sessionBus().call(q, QDBus::Block, 800);
                        pluginState[k] = r.isValid() && r.value();
                    }
                }
                const QStringList addrs = dp.value(QStringLiteral("reachableAddresses")).toStringList();
                list << QVariantMap{{QStringLiteral("id"), id},
                                    {QStringLiteral("name"), dp.value(QStringLiteral("name")).toString()},
                                    {QStringLiteral("type"), dp.value(QStringLiteral("type")).toString()},     // phone | tablet | desktop | laptop | tv
                                    {QStringLiteral("paired"), paired},
                                    {QStringLiteral("reachable"), reachable},
                                    {QStringLiteral("pairRequested"), dp.value(QStringLiteral("isPairRequested")).toBool()},
                                    {QStringLiteral("pairRequestedByPeer"), dp.value(QStringLiteral("isPairRequestedByPeer")).toBool()},
                                    {QStringLiteral("verificationKey"), dp.value(QStringLiteral("verificationKey")).toString()},
                                    {QStringLiteral("link"), addrs.isEmpty() ? QString() : addrs.first().startsWith(QLatin1String("bluetooth"), Qt::CaseInsensitive) ? QStringLiteral("bluetooth") : QStringLiteral("wifi")},
                                    {QStringLiteral("battery"), charge},
                                    {QStringLiteral("charging"), charging},
                                    {QStringLiteral("network"), net},
                                    {QStringLiteral("signal"), strength},
                                    {QStringLiteral("notifications"), notifs},
                                    {QStringLiteral("supported"), supported},
                                    {QStringLiteral("pluginState"), pluginState}};
            }
            // reachable and paired first, then the rest of the paired, then strangers
            std::stable_sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
                auto rank = [](const QVariantMap &d) { return d.value(QStringLiteral("paired")).toBool() ? (d.value(QStringLiteral("reachable")).toBool() ? 0 : 1) : 2; };
                return rank(a.toMap()) < rank(b.toMap());
            });
        }
        if (list != m_devices) {
            m_devices = list;
        }
        pickSelected();
        Q_EMIT changed();
        loadNotifications();
    }

    void bumpCount(const QString &id, int n)
    {
        for (QVariant &v : m_devices) {
            QVariantMap d = v.toMap();
            if (d.value(QStringLiteral("id")).toString() == id) {
                d[QStringLiteral("notifications")] = n;
                v = d;
            }
        }
        Q_EMIT changed();
    }
    // The selected phone's notifications, read property by property. The object's property names are
    // read defensively (everything the daemon offers is fetched, the known ones are mapped) because
    // the plugin objects are KDE-internal.
    void loadNotifications()
    {
        if (!m_watchNotifs || m_fake) {
            return;
        }
        QVariantList out;
        const QVariantMap d = find(m_selectedId);
        if (!d.isEmpty() && d.value(QStringLiteral("reachable")).toBool()) {
            const QString base = devPath(m_selectedId) + QStringLiteral("/notifications");
            const qint64 now = QDateTime::currentMSecsSinceEpoch();
            const QStringList ids = stringList(base, QStringLiteral("org.kde.kdeconnect.device.notifications"), QStringLiteral("activeNotifications"));
            QHash<QString, qint64> seen;
            for (const QString &nid : ids) {
                const QVariantMap p = getAll(base + QLatin1Char('/') + nid, QStringLiteral("org.kde.kdeconnect.device.notifications.notification"));
                if (p.isEmpty()) {
                    continue;
                }
                seen.insert(nid, m_firstSeen.value(nid, now));
                const QString text = p.value(QStringLiteral("text")).toString();
                out << QVariantMap{{QStringLiteral("id"), nid},
                                   {QStringLiteral("internalId"), p.value(QStringLiteral("internalId"), nid).toString()},
                                   {QStringLiteral("appName"), p.value(QStringLiteral("appName")).toString()},
                                   {QStringLiteral("title"), p.value(QStringLiteral("title")).toString()},
                                   {QStringLiteral("text"), text.isEmpty() ? p.value(QStringLiteral("ticker")).toString() : text},
                                   {QStringLiteral("dismissable"), p.value(QStringLiteral("dismissable"), true).toBool()},
                                   {QStringLiteral("silent"), p.value(QStringLiteral("silent")).toBool()},
                                   {QStringLiteral("iconPath"), p.value(QStringLiteral("hasIcon")).toBool() ? p.value(QStringLiteral("iconPath")).toString() : QString()},
                                   {QStringLiteral("replyId"), p.value(QStringLiteral("replyId")).toString()},
                                   {QStringLiteral("actions"), p.value(QStringLiteral("actions")).toStringList()},
                                   {QStringLiteral("ts"), double(seen.value(nid))}};
            }
            m_firstSeen = seen;   // forget what is gone
            std::stable_sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) { return a.toMap().value(QStringLiteral("ts")).toDouble() > b.toMap().value(QStringLiteral("ts")).toDouble(); });
        }
        if (out != m_notifs) {
            m_notifs = out;
            Q_EMIT notificationsChanged();
        }
    }

    // Three devices like the owner's, with invented values; used only when AETHER_CONNECT_FAKE=1.
    static QVariantList fixture()
    {
        auto dev = [](const char *id, const char *name, const char *type, bool paired, bool reach, int battery, bool charging, const char *net, int sig, int notifs) {
            QVariantMap on;
            for (const char *k : {"kdeconnect_notifications", "kdeconnect_clipboard", "kdeconnect_battery", "kdeconnect_share", "kdeconnect_sftp", "kdeconnect_findmyphone", "kdeconnect_ping", "kdeconnect_sms", "kdeconnect_mprisremote", "kdeconnect_telephony", "kdeconnect_contacts", "kdeconnect_remotekeyboard"}) {
                on[QString::fromLatin1(k)] = paired;
            }
            return QVariantMap{{QStringLiteral("id"), QString::fromLatin1(id)}, {QStringLiteral("name"), QString::fromLatin1(name)}, {QStringLiteral("type"), QString::fromLatin1(type)},
                               {QStringLiteral("paired"), paired}, {QStringLiteral("reachable"), reach}, {QStringLiteral("pairRequested"), false}, {QStringLiteral("pairRequestedByPeer"), !paired && reach},
                               {QStringLiteral("verificationKey"), QStringLiteral("1512E695")}, {QStringLiteral("link"), reach ? QStringLiteral("wifi") : QString()},
                               {QStringLiteral("battery"), battery}, {QStringLiteral("charging"), charging}, {QStringLiteral("network"), QString::fromLatin1(net)}, {QStringLiteral("signal"), sig},
                               {QStringLiteral("notifications"), notifs}, {QStringLiteral("supported"), QStringList(on.keys())}, {QStringLiteral("pluginState"), on}};
        };
        return {dev("fake-phone", "Pixel 9 (fake)", "phone", true, true, 64, false, "5G", 3, 5),
                dev("fake-tablet", "Tab S9 (fake)", "tablet", true, false, -1, false, "", -1, 0),
                dev("fake-new", "Nokia 3310 (fake)", "phone", false, true, -1, false, "", -1, 0)};
    }

    // Invented, harmless phone notifications for AETHER_CONNECT_FAKE=1.
    static QVariantList fixtureNotifications()
    {
        const double now = double(QDateTime::currentMSecsSinceEpoch());
        auto n = [now](const char *id, const char *app, const char *title, const char *text, bool dismissable, const char *reply, QStringList actions, int minutesAgo) {
            return QVariantMap{{QStringLiteral("id"), QString::fromLatin1(id)}, {QStringLiteral("internalId"), QString::fromLatin1(id)}, {QStringLiteral("appName"), QString::fromLatin1(app)},
                               {QStringLiteral("title"), QString::fromUtf8(title)}, {QStringLiteral("text"), QString::fromUtf8(text)}, {QStringLiteral("dismissable"), dismissable},
                               {QStringLiteral("silent"), false}, {QStringLiteral("iconPath"), QString()}, {QStringLiteral("replyId"), QString::fromLatin1(reply)},
                               {QStringLiteral("actions"), actions}, {QStringLiteral("ts"), now - minutesAgo * 60000.0}};
        };
        return {n("f1", "Messages", "Dana", "Are we still on for 6? I can bring the cables.", true, "reply-f1", {}, 2),
                n("f2", "Mail", "Weekly report", "The report is ready: 3 items need your review before Thursday.", true, "", {QStringLiteral("Archive"), QStringLiteral("Mark as read")}, 9),
                n("f3", "Calendar", "Design review in 15 minutes", "Room 4B, with the whole team", true, "", {}, 14),
                n("f4", "Chat", "Group: Weekend", "Noa: sending the photos now", true, "reply-f4", {}, 31),
                n("f5", "Downloads", "Download complete", "map-2026.pdf (4.2 MB)", false, "", {}, 55)};
    }
    QSettings m_prefs{QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat};
    QTimer m_debounce;
    const bool m_fake;
    bool m_available = false;
    QVariantList m_devices;
    QString m_selectedId;
    QVariantMap m_lastAction;
    QVariantList m_notifs;
    QHash<QString, qint64> m_firstSeen;
    bool m_watchNotifs = false, m_fakeNotifsServed = false;
};
