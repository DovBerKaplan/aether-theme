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
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDesktopServices>
#include <QFileInfo>
#include <QUrl>
#include <QDateTime>
#include <QFile>
#include <QImage>
#include <QMimeDatabase>
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
    Q_PROPERTY(QVariantMap files READ files NOTIFY filesChanged)                 // {mounted, mountPoint, busy} of the selected phone's storage
    Q_PROPERTY(QVariantList received READ received NOTIFY receivedChanged)       // the last few files that arrived: {name, url, device, ts}
    Q_PROPERTY(bool canChooseFiles READ canChooseFiles CONSTANT)
    Q_PROPERTY(QVariantMap call READ call NOTIFY callChanged)                     // {event, name, device} while a call is ringing/going/just missed, else {}
    Q_PROPERTY(QVariantMap phoneMedia READ phoneMedia NOTIFY phoneMediaChanged)   // what the selected phone plays; filled only while the Media page is open
    Q_PROPERTY(bool lowBatteryAlert READ lowBatteryAlert WRITE setLowBatteryAlert NOTIFY lowBatteryAlertChanged)   // opt-in: tell me when a phone is below 20 %
    Q_PROPERTY(QVariantMap lastAction READ lastAction NOTIFY lastActionChanged)   // {kind, device} of the latest action

public:
    explicit ConnectModel(QObject *parent = nullptr)
        : QObject(parent)
        , m_fake(qEnvironmentVariableIntValue("AETHER_CONNECT_FAKE") != 0)
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        m_callClear.setSingleShot(true);
        connect(&m_callClear, &QTimer::timeout, this, [this] { m_call.clear(); Q_EMIT callChanged(); });
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
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.telephony"), QStringLiteral("callReceived"), this, SLOT(onCall(QDBusMessage)));
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.mprisremote"), QStringLiteral("propertiesChanged"), this, SLOT(onMediaChanged(QDBusMessage)));
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.share"), QStringLiteral("shareReceived"), this, SLOT(onShareReceived(QDBusMessage)));
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.sftp"), QStringLiteral("mounted"), this, SLOT(onSftpChanged(QDBusMessage)));
            bus.connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.sftp"), QStringLiteral("unmounted"), this, SLOT(onSftpChanged(QDBusMessage)));
            // the daemon may start after us (or restart)
            auto *w = new QDBusServiceWatcher(Service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
            connect(w, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] { m_debounce.start(); });
        }
        QTimer::singleShot(0, this, [this] { refresh(); });
        if (m_fake) {   // test hook: `touch /tmp/aether-connect-fake-<ringing|talking|missedCall|lowbattery>` acts that out (no restart needed)
            auto *c = new QTimer(this);
            c->setInterval(1000);
            connect(c, &QTimer::timeout, this, [this] {
                for (const char *e : {"ringing", "talking", "missedCall"}) {
                    if (QFile::remove(QStringLiteral("/tmp/aether-connect-fake-") + QLatin1String(e))) {
                        debugCall(QLatin1String(e));
                    }
                }
                if (QFile::remove(QStringLiteral("/tmp/aether-connect-fake-lowbattery"))) {
                    debugLowBattery();
                }
            });
            c->start();
        }
        if (m_fake) {   // test hook: `touch /tmp/aether-connect-fake-receive` makes a fake file arrive (no restart needed)
            auto *t = new QTimer(this);
            t->setInterval(1000);
            connect(t, &QTimer::timeout, this, [this] {
                if (QFile::remove(QStringLiteral("/tmp/aether-connect-fake-receive"))) {
                    debugReceive();
                }
            });
            t->start();
        }
        const int fakeIn = qEnvironmentVariableIntValue("AETHER_CONNECT_FAKE_RECEIVE");   // test hook: a fake file arrives after N seconds
        if (m_fake && fakeIn > 0) {
            QTimer::singleShot(fakeIn * 1000, this, [this] { debugReceive(); });
        }
    }

    bool available() const { return m_available; }
    QVariantList devices() const { return m_devices; }
    QString selectedId() const { return m_selectedId; }
    QVariantMap selected() const { return find(m_selectedId); }
    QVariantMap lastAction() const { return m_lastAction; }
    QVariantList notifications() const { return m_notifs; }
    QVariantMap files() const { return m_files; }
    QVariantMap call() const { return m_call; }
    QVariantMap phoneMedia() const { return m_media; }
    bool lowBatteryAlert() const { return m_prefs.value(QStringLiteral("Connect/LowBatteryAlert"), false).toBool(); }
    void setLowBatteryAlert(bool on)
    {
        if (on == lowBatteryAlert()) {
            return;
        }
        m_prefs.setValue(QStringLiteral("Connect/LowBatteryAlert"), on);
        m_prefs.sync();
        Q_EMIT lowBatteryAlertChanged();
    }

    // The Media page is open: read what the phone plays, and keep it fresh from the daemon's signal.
    Q_INVOKABLE void watchMedia(bool on)
    {
        m_watchMedia = on;
        if (on) {
            if (!m_fake && !m_selectedId.isEmpty()) {
                plugin(m_selectedId, QStringLiteral("mprisremote"), QStringLiteral("requestPlayerList"), {}, QString());   // asks the phone, no side effect
            }
            readMedia();
        } else {
            m_media.clear();
            Q_EMIT phoneMediaChanged();
        }
    }
    // Play, Pause, PlayPause, Stop, Next, Previous.
    Q_INVOKABLE void mediaAction(const QString &id, const QString &action)
    {
        record(QStringLiteral("media"), id);
        if (m_fake) {
            if (action == QLatin1String("PlayPause") || action == QLatin1String("Play") || action == QLatin1String("Pause")) {
                m_media[QStringLiteral("playing")] = action == QLatin1String("Play") ? true : action == QLatin1String("Pause") ? false : !m_media.value(QStringLiteral("playing")).toBool();
                Q_EMIT phoneMediaChanged();
            }
            return;
        }
        plugin(id, QStringLiteral("mprisremote"), QStringLiteral("sendAction"), {action}, QString());
        QTimer::singleShot(400, this, [this] { readMedia(); });
    }
    // fraction 0..1 of the track
    Q_INVOKABLE void mediaSeek(const QString &id, qreal fraction)
    {
        const int len = m_media.value(QStringLiteral("length")).toInt();
        if (len <= 0) {
            return;
        }
        const int pos = int(qBound<qreal>(0, fraction, 1) * len);
        m_media[QStringLiteral("position")] = pos;
        Q_EMIT phoneMediaChanged();
        if (!m_fake) {
            setRemoteProp(id, QStringLiteral("position"), pos);
        }
    }
    Q_INVOKABLE void mediaVolume(const QString &id, int percent)
    {
        m_media[QStringLiteral("volume")] = qBound(0, percent, 100);
        Q_EMIT phoneMediaChanged();
        if (!m_fake) {
            setRemoteProp(id, QStringLiteral("volume"), qBound(0, percent, 100));
        }
    }
    Q_INVOKABLE void mediaPlayer(const QString &id, const QString &player)
    {
        if (!m_fake) {
            setRemoteProp(id, QStringLiteral("player"), player);
            QTimer::singleShot(500, this, [this] { readMedia(); });
        }
    }
    // Fake mode only: act out a call event (ringing, talking, missedCall) or a low battery.
    Q_INVOKABLE void debugCall(const QString &event)
    {
        if (m_fake) {
            noteCall(QStringLiteral("fake-phone"), event, QStringLiteral("+1 555 0100"), QStringLiteral("Dana Levi"));
        }
    }
    Q_INVOKABLE void debugLowBattery()
    {
        if (m_fake) {
            Q_EMIT lowBattery(find(QStringLiteral("fake-phone")).value(QStringLiteral("name")).toString(), 14);
        }
    }
    QVariantList received() const { return m_received; }
    bool canChooseFiles() const { return !QStandardPaths::findExecutable(QStringLiteral("kdialog")).isEmpty(); }

    // The Files page is open: know whether the phone's storage is mounted (the daemon tells us when that changes).
    Q_INVOKABLE void watchFiles(bool on)
    {
        m_watchFiles = on;
        if (on) {
            readFiles();
        }
    }
    // Mount the phone's storage and open it in the file manager (the daemon does both).
    Q_INVOKABLE void browseFiles(const QString &id)
    {
        record(QStringLiteral("browse"), id);
        if (m_fake) {
            m_files = {{QStringLiteral("mounted"), true}, {QStringLiteral("mountPoint"), QStringLiteral("/run/user/1000/kdeconnect/fake")}, {QStringLiteral("busy"), false}};
            Q_EMIT filesChanged();
            return;
        }
        m_files[QStringLiteral("busy")] = true;
        Q_EMIT filesChanged();
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/sftp"), QStringLiteral("org.kde.kdeconnect.device.sftp"), QStringLiteral("startBrowsing"));
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m, 30000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *self) {
            self->deleteLater();
            readFiles();
        });
    }
    Q_INVOKABLE void unmountFiles(const QString &id)
    {
        record(QStringLiteral("unmount"), id);
        if (m_fake) {
            m_files = {{QStringLiteral("mounted"), false}, {QStringLiteral("mountPoint"), QString()}, {QStringLiteral("busy"), false}};
            Q_EMIT filesChanged();
            return;
        }
        plugin(id, QStringLiteral("sftp"), QStringLiteral("unmount"), {}, QStringLiteral("unmount"));
        QTimer::singleShot(600, this, [this] { readFiles(); });
    }
    // Send files (file:// urls or plain paths) to the phone. The daemon streams them itself.
    Q_INVOKABLE void sendFiles(const QString &id, const QStringList &urls)
    {
        QStringList clean;
        for (const QString &u : urls) {
            const QUrl q = QUrl::fromUserInput(u);
            if (q.isLocalFile() && QFileInfo(q.toLocalFile()).isFile()) {   // files only: no folders, no remote urls through this door
                clean << q.toString();
            }
        }
        if (clean.isEmpty()) {
            return;
        }
        QVariantMap a{{QStringLiteral("kind"), QStringLiteral("files")}, {QStringLiteral("device"), find(id).value(QStringLiteral("name")).toString()}, {QStringLiteral("count"), clean.size()}};
        m_lastAction = a;
        qInfo().noquote() << "kdeconnect: send" << clean.size() << "file(s) to" << a.value(QStringLiteral("device")).toString() << (m_fake ? "(fake: nothing sent)" : "");
        Q_EMIT lastActionChanged();
        if (!m_fake) {
            QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/share"), QStringLiteral("org.kde.kdeconnect.device.share"), QStringLiteral("shareUrls"));
            m << clean;
            QDBusConnection::sessionBus().asyncCall(m);
        }
    }
    // A text or link dropped on the card goes through the same door as the field in the panel.
    Q_INVOKABLE void sendDropped(const QString &id, const QString &text)
    {
        const QString t = text.trimmed();
        if (QUrl::fromUserInput(t).scheme().startsWith(QLatin1String("http")) && !t.contains(QLatin1Char(' '))) {
            shareUrl(id, t);
        } else {
            shareText(id, t);
        }
    }
    // The system file chooser (kdialog); whatever is picked is sent. Nothing happens if it is cancelled.
    Q_INVOKABLE void chooseFiles(const QString &id)
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p, id] {
            const QStringList paths = QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            p->deleteLater();
            sendFiles(id, paths);
        });
        p->start(QStringLiteral("kdialog"), {QStringLiteral("--multiple"), QStringLiteral("--separate-output"), QStringLiteral("--getopenfilename"), QDir::homePath(), QStringLiteral("*|All files")});
    }
    Q_INVOKABLE void openReceived(const QString &url) { QDesktopServices::openUrl(QUrl(url)); }
    Q_INVOKABLE void showReceived(const QString &url)
    {
        const QUrl q(url);
        QProcess::startDetached(QStringLiteral("xdg-open"), {q.isLocalFile() ? QFileInfo(q.toLocalFile()).absolutePath() : url});
    }
    // Fake mode only: pretend a file arrived (the island's file-received card can then be seen).
    Q_INVOKABLE void debugReceive()
    {
        if (m_fake) {
            noteReceived(QStringLiteral("fake-phone"), QUrl::fromLocalFile(QDir::homePath() + QStringLiteral("/Downloads/holiday-photo-2026.jpg")).toString());
        }
    }

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
    Q_INVOKABLE void selectNext() { selectStep(1); }
    Q_INVOKABLE void selectStep(int dir)
    {
        QStringList paired;
        for (const QVariant &v : std::as_const(m_devices)) {
            if (v.toMap().value(QStringLiteral("paired")).toBool()) {
                paired << v.toMap().value(QStringLiteral("id")).toString();
            }
        }
        if (paired.size() > 1) {
            select(paired.at((paired.indexOf(m_selectedId) + (dir < 0 ? paired.size() - 1 : 1)) % paired.size()));
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
    void callChanged();
    void phoneMediaChanged();
    void lowBatteryAlertChanged();
    void callEvent(const QString &device, const QString &event, const QString &who);   // who: contact name, or the number
    void lowBattery(const QString &device, int percent);
    void filesChanged();
    void receivedChanged();
    void fileReceived(const QString &device, const QString &name, const QString &url, bool copied);
    void notificationsChanged();

private Q_SLOTS:
    void onAny(const QDBusMessage &) { m_debounce.start(); }
    void onMediaChanged(const QDBusMessage &) { if (m_watchMedia) { QTimer::singleShot(150, this, [this] { readMedia(); }); } }
    void onCall(const QDBusMessage &msg)
    {
        const QVariantList a = msg.arguments();
        const QStringList parts = msg.path().split(QLatin1Char('/'));
        const int i = parts.indexOf(QStringLiteral("devices"));
        if (a.size() >= 3 && i >= 0 && i + 1 < parts.size()) {
            noteCall(parts.at(i + 1), a.at(0).toString(), a.at(1).toString(), a.at(2).toString());
        }
    }
    void onShareReceived(const QDBusMessage &msg)
    {
        const QString url = msg.arguments().isEmpty() ? QString() : msg.arguments().first().toString();
        const QStringList parts = msg.path().split(QLatin1Char('/'));
        const int i = parts.indexOf(QStringLiteral("devices"));
        if (i >= 0 && i + 1 < parts.size()) {
            noteReceived(parts.at(i + 1), url);
        }
    }
    void onSftpChanged(const QDBusMessage &) { if (m_watchFiles) { QTimer::singleShot(300, this, [this] { readFiles(); }); } }

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
        if (!kind.isEmpty()) {
            record(kind, id);
        }
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
    void setRemoteProp(const QString &id, const QString &name, const QVariant &v)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/mprisremote"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
        m << QStringLiteral("org.kde.kdeconnect.device.mprisremote") << name << QVariant::fromValue(QDBusVariant(v));
        QDBusConnection::sessionBus().asyncCall(m);
    }
    void readMedia()
    {
        QVariantMap out;
        if (m_fake) {
            if (m_media.isEmpty()) {
                m_media = {{QStringLiteral("title"), QStringLiteral("Blue in Green")}, {QStringLiteral("artist"), QStringLiteral("Miles Davis")}, {QStringLiteral("album"), QStringLiteral("Kind of Blue")},
                           {QStringLiteral("playing"), true}, {QStringLiteral("position"), 84000}, {QStringLiteral("length"), 337000}, {QStringLiteral("volume"), 60}, {QStringLiteral("canSeek"), true},
                           {QStringLiteral("player"), QStringLiteral("Music")}, {QStringLiteral("players"), QStringList{QStringLiteral("Music"), QStringLiteral("Podcasts")}}, {QStringLiteral("available"), true}};
                Q_EMIT phoneMediaChanged();
            }
            return;
        }
        const QVariantMap d = find(m_selectedId);
        if (!d.isEmpty() && d.value(QStringLiteral("reachable")).toBool() && d.value(QStringLiteral("pluginState")).toMap().value(QStringLiteral("kdeconnect_mprisremote")).toBool()) {
            const QVariantMap p = getAll(devPath(m_selectedId) + QStringLiteral("/mprisremote"), QStringLiteral("org.kde.kdeconnect.device.mprisremote"));
            const QString title = p.value(QStringLiteral("title")).toString();
            out = {{QStringLiteral("title"), title}, {QStringLiteral("artist"), p.value(QStringLiteral("artist")).toString()}, {QStringLiteral("album"), p.value(QStringLiteral("album")).toString()},
                   {QStringLiteral("playing"), p.value(QStringLiteral("isPlaying")).toBool()}, {QStringLiteral("position"), p.value(QStringLiteral("position")).toInt()},   // ms
                   {QStringLiteral("length"), p.value(QStringLiteral("length")).toInt()}, {QStringLiteral("volume"), p.value(QStringLiteral("volume")).toInt()},
                   {QStringLiteral("canSeek"), p.value(QStringLiteral("canSeek")).toBool()}, {QStringLiteral("player"), p.value(QStringLiteral("player")).toString()},
                   {QStringLiteral("players"), p.value(QStringLiteral("playerList")).toStringList()}, {QStringLiteral("available"), !title.isEmpty()}};
        }
        if (out != m_media) {
            m_media = out;
            Q_EMIT phoneMediaChanged();
        }
    }
    // A call changed state. The card shows it; nothing about it is logged (names and numbers are private).
    void noteCall(const QString &deviceId, const QString &event, const QString &number, const QString &name)
    {
        if (event != QLatin1String("ringing") && event != QLatin1String("talking") && event != QLatin1String("missedCall")) {
            return;   // "sms" is a message: the Notifications page has it
        }
        const QString device = find(deviceId).value(QStringLiteral("name")).toString();
        const QString who = name.isEmpty() || name == number ? number : name;
        m_call = {{QStringLiteral("event"), event}, {QStringLiteral("who"), who}, {QStringLiteral("device"), device}, {QStringLiteral("id"), deviceId}};
        m_callClear.start(event == QLatin1String("ringing") ? 45000 : event == QLatin1String("talking") ? 8000 : 15000);   // the daemon sends no "ended"
        Q_EMIT callChanged();
        Q_EMIT callEvent(device, event, who);
    }
    // Phones below 20 % and not charging, at most once every 6 hours each; only when the owner opted in.
    void checkLowBattery()
    {
        if (!lowBatteryAlert()) {
            return;
        }
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        for (const QVariant &v : std::as_const(m_devices)) {
            const QVariantMap d = v.toMap();
            const int b = d.value(QStringLiteral("battery")).toInt();
            const QString key = QStringLiteral("Connect/LowAlert/") + d.value(QStringLiteral("id")).toString();
            if (d.value(QStringLiteral("paired")).toBool() && d.value(QStringLiteral("reachable")).toBool() && b >= 0 && b <= 20 && !d.value(QStringLiteral("charging")).toBool()
                && now - m_prefs.value(key, 0).toLongLong() > 6 * 3600) {
                m_prefs.setValue(key, now);
                m_prefs.sync();
                Q_EMIT lowBattery(d.value(QStringLiteral("name")).toString(), b);
            }
        }
    }
    // A picture sent from the phone goes onto the clipboard too (as PNG, which every app accepts), so
    // "paste" anywhere puts it in. Only pictures: other files never touch the clipboard. wl-copy uses the
    // data-control protocol, so it works without the island having keyboard focus; where it is missing,
    // xclip serves X11 apps only (KWin does not carry an X11 image selection over to Wayland apps).
    bool copyImage(const QString &path)
    {
        const QString wlCopy = QStandardPaths::findExecutable(QStringLiteral("wl-copy"));
        const QString xclip = QStandardPaths::findExecutable(QStringLiteral("xclip"));
        if (m_fake || (wlCopy.isEmpty() && xclip.isEmpty()) || !QMimeDatabase().mimeTypeForFile(path).name().startsWith(QLatin1String("image/"))) {
            return false;
        }
        const QImage img(path);
        const QString png = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/clipboard-image.png");
        QDir().mkpath(QFileInfo(png).absolutePath());
        if (img.isNull() || !img.save(png, "PNG")) {
            return false;
        }
        if (!wlCopy.isEmpty()) {
            return QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), QStringLiteral("exec \"$1\" --type image/png < \"$2\""), QStringLiteral("sh"), wlCopy, png});
        }
        return QProcess::startDetached(xclip, {QStringLiteral("-selection"), QStringLiteral("clipboard"), QStringLiteral("-t"), QStringLiteral("image/png"), QStringLiteral("-i"), png});
    }
    void noteReceived(const QString &deviceId, const QString &url)
    {
        const QUrl q(url);
        if (!q.isLocalFile()) {   // links and text are not files
            return;
        }
        const QString name = QFileInfo(q.toLocalFile()).fileName();
        const QString device = find(deviceId).value(QStringLiteral("name")).toString();
        m_received.prepend(QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("url"), url}, {QStringLiteral("device"), device}, {QStringLiteral("ts"), double(QDateTime::currentMSecsSinceEpoch())}});
        while (m_received.size() > 5) {
            m_received.removeLast();
        }
        qInfo().noquote() << "kdeconnect: file received from" << device;   // never the name: file names can be private
        Q_EMIT receivedChanged();
        Q_EMIT fileReceived(device, name, url, copyImage(q.toLocalFile()));
    }
    void readFiles()
    {
        QVariantMap f{{QStringLiteral("mounted"), false}, {QStringLiteral("mountPoint"), QString()}, {QStringLiteral("busy"), false}};
        if (!m_fake && !m_selectedId.isEmpty() && find(m_selectedId).value(QStringLiteral("reachable")).toBool()) {
            const QString p = devPath(m_selectedId) + QStringLiteral("/sftp");
            QDBusMessage q = QDBusMessage::createMethodCall(Service, p, QStringLiteral("org.kde.kdeconnect.device.sftp"), QStringLiteral("isMounted"));
            const QDBusReply<bool> r = QDBusConnection::sessionBus().call(q, QDBus::Block, 1000);
            if (r.isValid() && r.value()) {
                QDBusMessage mp = QDBusMessage::createMethodCall(Service, p, QStringLiteral("org.kde.kdeconnect.device.sftp"), QStringLiteral("mountPoint"));
                const QDBusReply<QString> mr = QDBusConnection::sessionBus().call(mp, QDBus::Block, 1000);
                f[QStringLiteral("mounted")] = true;
                f[QStringLiteral("mountPoint")] = mr.isValid() ? mr.value() : QString();
            }
        } else if (m_fake) {
            f = m_files.isEmpty() ? f : m_files;
        }
        if (f != m_files) {
            m_files = f;
            Q_EMIT filesChanged();
        }
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
        checkLowBattery();
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
    QVariantList m_notifs, m_received;
    QVariantMap m_files, m_call, m_media;
    QTimer m_callClear;
    bool m_watchMedia = false;
    bool m_watchFiles = false;
    QHash<QString, qint64> m_firstSeen;
    bool m_watchNotifs = false, m_fakeNotifsServed = false;
};
