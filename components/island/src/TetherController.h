// Bluetooth tether failover - the "fallback router". One paired device is marked as the
// router (its Bluetooth tethering / NAP service); when NetworkManager says the internet is
// gone, the engine connects it and brings up the "phone-tether" NM profile (bluetooth/nap
// on bnep0). The profile's route metric (50) sits below the wifi's (600), so traffic moves
// the moment bnep0 is up - no route surgery, no root, nothing the user can feel. While
// riding, the non-tether upstream is probed; when it answers twice, the tether is dropped
// and the real route takes over by itself. Only successful transitions raise a card
// (Island.qml turns the signals into translated toasts); retries stay silent and are
// backed off 30 s / 1 min / 2 min / 5 min. All BlueZ and NM access is raw D-Bus (system bus).
#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDateTime>
#include <QDir>
#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "BluetoothModel.h"
#include "NetworkModel.h"

class TetherController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool engaged READ engaged NOTIFY changed)                 // riding the router right now
    Q_PROPERTY(QString state READ state NOTIFY changed)                  // idle | engaging | engaged | unavailable
    Q_PROPERTY(QString routerAddress READ routerAddress NOTIFY changed)  // the marked device's address, "" = none
    Q_PROPERTY(QString routerName READ routerName NOTIFY changed)

public:
    explicit TetherController(NetworkModel *net, BluetoothModel *bt, QObject *parent = nullptr)
        : QObject(parent), m_net(net), m_bt(bt)
    {
        m_router = m_prefs.value(QStringLiteral("Failover/Router")).toString();
        // AETHER_TETHER_FAKE=1 (test sandboxes): no D-Bus, no probing - engage/disengage are
        // simulated a couple of seconds after the call, so every screen can be shot offline.
        // AETHER_TETHER_FAKE_ENGAGED=1 engages by itself once a router is marked, mirroring
        // the other *_FAKE_* test hooks.
        if (qEnvironmentVariableIntValue("AETHER_TETHER_FAKE") != 0) {
            m_fake = true;
            if (!m_router.isEmpty() && qEnvironmentVariableIntValue("AETHER_TETHER_FAKE_ENGAGED") != 0) {
                QTimer::singleShot(2000, this, [this] { engage(); });
            }
            return;
        }
        m_sick.setSingleShot(true);
        m_sick.setInterval(5000);   // a momentary connectivity blip is not a dead line
        connect(&m_sick, &QTimer::timeout, this, [this] { if (sick() && m_state == QLatin1String("idle")) engage(); });
        m_backoff.setSingleShot(true);
        connect(&m_backoff, &QTimer::timeout, this, [this] { if (sick()) engage(); });
        m_stuck.setSingleShot(true);
        m_stuck.setInterval(2 * 60 * 1000);   // engaged but still no internet: recycle for a fresh lease
        connect(&m_stuck, &QTimer::timeout, this, [this] { if (sick()) disengage(true, false); });
        m_watchdog.setSingleShot(true);
        m_watchdog.setInterval(90 * 1000);
        connect(&m_watchdog, &QTimer::timeout, this, [this] { if (m_state == QLatin1String("engaging")) fail(); });
        m_probe.setInterval(30000);
        connect(&m_probe, &QTimer::timeout, this, [this] { probeWifi(); });
        connect(&m_ping, &QProcess::finished, this, [this](int code) {
            if (m_state != QLatin1String("engaged")) {
                return;
            }
            m_alive = code == 0 ? m_alive + 1 : 0;
            if (m_alive >= 2) {   // twice in a row: the real uplink is back for good
                disengage(false, false);
            }
        });
        connect(m_net, &NetworkModel::changed, this, [this] { evaluate(); });
        connect(m_bt, &BluetoothModel::devicesChanged, this, [this] { Q_EMIT changed(); });   // routerName follows the list
        QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                                              QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("PrepareForSleep"),
                                              this, SLOT(onSleep(bool)));
        every(15000, [this] { evaluate(); });   // safety net under the event-driven path
        QTimer::singleShot(8000, this, [this] { evaluate(); });   // after the models have spoken once
    }

    bool engaged() const { return m_engaged; }
    QString state() const { return m_state; }
    QString routerAddress() const { return m_router; }
    QString routerName() const
    {
        const QVariantMap d = dev(m_router);
        const QString n = d.value(QStringLiteral("name")).toString();
        return n.isEmpty() ? m_router : n;
    }

    Q_INVOKABLE void setRouter(const QString &address, bool on)
    {
        const QString addr = address.trimmed();
        if (on) {
            if (addr.isEmpty()) {
                return;
            }
            m_router = addr;
            m_fails = 0;
            ensureProfile(addr);
        } else {
            if (m_router != addr) {
                return;
            }
            m_router.clear();
            if (m_state == QLatin1String("engaged")) {
                disengage(false, true);   // the user said no: drop it quietly, no "recovered" card
            }
        }
        m_prefs.setValue(QStringLiteral("Failover/Router"), m_router);   // empty stays a key (PrefsGuard)
        m_prefs.sync();
        Q_EMIT changed();
    }

    // Sandbox only: flips the simulated state so both riding and idle screens can be shot.
    Q_INVOKABLE void fakeEngage()
    {
        if (!m_fake) {
            return;
        }
        if (m_engaged) {
            disengage(false, false);
        } else {
            engage();
        }
    }

Q_SIGNALS:
    void changed();
    void engaged(const QString &name);   // traffic now flows through the router (success only)
    void recovered();                    // a real uplink took over again

private Q_SLOTS:
    // Connections dropped while asleep: the wifi is usually back on its own; give the tether
    // a clean slate and let the normal evaluation re-engage if the internet is still gone.
    void onSleep(bool starting)
    {
        if (starting) {
            return;
        }
        m_fails = 0;
        m_backoff.stop();
        if (m_state == QLatin1String("engaged")) {
            m_probe.start();
            QTimer::singleShot(4000, this, [this] { probeWifi(); });
        } else {
            QTimer::singleShot(5000, this, [this] { evaluate(); });
        }
    }

private:
    template<typename F> void every(int ms, F f)
    {
        auto *t = new QTimer(this);
        t->setInterval(ms);
        connect(t, &QTimer::timeout, this, f);
        t->start();
        QTimer::singleShot(100, this, f);
    }
    static QDBusMessage bluezMethod(const QString &path, const QString &iface, const QString &name)
    {
        return QDBusMessage::createMethodCall(QStringLiteral("org.bluez"), path, iface, name);
    }
    bool sick() const { return m_net->connectivity() != QLatin1String("full"); }
    QVariantMap dev(const QString &addr) const
    {
        for (const QVariant &v : m_bt->devices()) {
            if (v.toMap().value(QStringLiteral("address")).toString() == addr) {
                return v.toMap();
            }
        }
        return {};
    }
    // A router the user disconnected from the row (or blocked) means "not now", even while sick.
    bool routerUsable() const
    {
        const QVariantMap d = dev(m_router);
        return d.isEmpty() || (!d.value(QStringLiteral("paused")).toBool() && !d.value(QStringLiteral("blocked")).toBool());
    }

    void setState(const QString &s)
    {
        if (m_state == s) {
            return;
        }
        m_state = s;
        Q_EMIT changed();
    }

    void evaluate()
    {
        if (m_fake) {
            return;   // the fake engine is driven by hand
        }
        const bool s = sick();
        if (m_state == QLatin1String("idle")) {
            if (s && !m_router.isEmpty() && routerUsable()) {
                if (!m_lastSick) {
                    m_sick.start();   // edge into sick: let it settle before moving traffic
                }
            } else {
                m_sick.stop();
            }
        } else if (m_state == QLatin1String("unavailable")) {
            if (!s) {
                setState(QStringLiteral("idle"));   // the internet came back on its own
                m_fails = 0;
            }
        } else if (m_state == QLatin1String("engaged")) {
            if (s && !m_stuck.isActive()) {
                m_stuck.start();
            } else if (!s) {
                m_stuck.stop();
            }
        }
        m_lastSick = s;
    }

    void engage()
    {
        if (m_router.isEmpty()) {
            return;
        }
        if (m_fake) {   // simulated success a beat later - the sandbox has no BlueZ behind it
            setState(QStringLiteral("engaging"));
            QTimer::singleShot(2000, this, [this] {
                if (m_state != QLatin1String("engaging")) {
                    return;
                }
                m_state = QStringLiteral("engaged");
                m_engaged = true;
                const QString name = routerName();
                Q_EMIT changed();
                Q_EMIT engaged(name);
            });
            return;
        }
        m_sick.stop();
        m_backoff.stop();
        m_watchdog.start();
        setState(QStringLiteral("engaging"));
        const QVariantMap d = dev(m_router);
        const QString path = d.value(QStringLiteral("path")).toString();
        qInfo().noquote() << "tether: internet is" << m_net->connectivity() << "- engaging" << routerName();
        if (path.isEmpty()) {
            fail();
            return;
        }
        if (d.value(QStringLiteral("connected")).toBool()) {
            connectNap(path);
            return;
        }
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(
            bluezMethod(path, QStringLiteral("org.bluez.Device1"), QStringLiteral("Connect")), 30000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, path](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            if (err) {
                fail();
            } else if (m_state == QLatin1String("engaging")) {
                connectNap(path);
            }
        });
    }

    // NAP over BlueZ: this is what creates bnep0. The NM profile activation follows.
    void connectNap(const QString &path)
    {
        QDBusMessage m = bluezMethod(path, QStringLiteral("org.bluez.Network1"), QStringLiteral("Connect"));
        m << QStringLiteral("nap");
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m, 30000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            const QString errName = self->isError() ? self->reply().errorName() : QString();
            self->deleteLater();
            if (err) {
                qInfo().noquote() << "tether: NAP refused -" << errName;
                fail();
            } else if (m_state == QLatin1String("engaging")) {
                findBnep(20);
            }
        });
    }

    void findBnep(int tries)
    {
        if (m_state != QLatin1String("engaging")) {
            return;
        }
        const QString path = nmDevicePath(QStringLiteral("bnep0"));
        if (!path.isEmpty()) {
            activate(path);
            return;
        }
        if (tries > 0) {
            QTimer::singleShot(500, this, [this, tries] { findBnep(tries - 1); });
        } else {
            fail();
        }
    }

    void activate(const QString &bnepPath)
    {
        const QString profile = profilePath();
        if (profile.isEmpty()) {
            fail();
            return;
        }
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
                                                        QStringLiteral("/org/freedesktop/NetworkManager"),
                                                        QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("ActivateConnection"));
        m << QVariant::fromValue(QDBusObjectPath(profile)) << QVariant::fromValue(QDBusObjectPath(bnepPath))
          << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, bnepPath](QDBusPendingCallWatcher *self) {
            const bool err = self->isError();
            self->deleteLater();
            if (err) {
                fail();
            } else if (m_state == QLatin1String("engaging")) {
                waitActive(bnepPath, 20);
            }
        });
    }

    void waitActive(const QString &bnepPath, int tries)
    {
        if (m_state != QLatin1String("engaging")) {
            return;
        }
        if (nmProp(bnepPath, QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("State")).toUInt() == 100) {
            succeed();
            return;
        }
        if (tries > 0) {
            QTimer::singleShot(1000, this, [this, bnepPath, tries] { waitActive(bnepPath, tries - 1); });
        } else {
            fail();
        }
    }

    void succeed()
    {
        m_watchdog.stop();
        m_fails = 0;
        m_alive = 0;
        m_wifiIf = upstreamInterface();
        m_state = QStringLiteral("engaged");
        m_engaged = true;
        m_probe.start();
        const QString name = routerName();
        qInfo().noquote() << "tether: riding" << name;
        Q_EMIT changed();
        Q_EMIT engaged(name);
    }

    void fail()
    {
        if (m_state != QLatin1String("engaging")) {
            return;
        }
        m_watchdog.stop();
        static const int steps[] = {30, 60, 120, 300};
        const int wait = steps[qMin(m_fails, 3)];
        m_fails = qMin(m_fails + 1, 3);
        setState(QStringLiteral("unavailable"));
        m_backoff.start(wait * 1000);
        qInfo().noquote() << "tether: router didn't answer, retry in" << wait << "s";
    }

    void disengage(bool recycle, bool quiet)
    {
        if (m_fake) {
            m_state = QStringLiteral("idle");
            m_engaged = false;
            Q_EMIT changed();
            if (!quiet) {
                Q_EMIT recovered();
            }
            return;
        }
        m_probe.stop();
        m_stuck.stop();
        m_alive = 0;
        const QString bnepPath = nmDevicePath(QStringLiteral("bnep0"));
        if (!bnepPath.isEmpty()) {
            const QString ac = nmProp(bnepPath, QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("ActiveConnection"))
                                   .value<QDBusObjectPath>().path();
            if (!ac.isEmpty() && ac != QLatin1String("/")) {
                QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
                                                                QStringLiteral("/org/freedesktop/NetworkManager"),
                                                                QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("DeactivateConnection"));
                m << QVariant::fromValue(QDBusObjectPath(ac));
                QDBusConnection::systemBus().asyncCall(m);
            }
        }
        const QVariantMap d = dev(m_router);
        if (!d.isEmpty() && d.value(QStringLiteral("connected")).toBool()) {
            QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(
                QStringLiteral("org.bluez"), d.value(QStringLiteral("path")).toString(),
                QStringLiteral("org.bluez.Device1"), QStringLiteral("Disconnect")));
        }
        m_state = QStringLiteral("idle");
        m_engaged = false;
        Q_EMIT changed();
        if (recycle) {
            qInfo().noquote() << "tether: tether is up but the internet is not - recycling";
            QTimer::singleShot(8000, this, [this] { if (m_state == QLatin1String("idle") && sick()) engage(); });
        } else if (!quiet) {
            qInfo().noquote() << "tether: real uplink is back";
            Q_EMIT recovered();
        }
    }

    // While riding: is the non-tether upstream alive again? Two answers in a row hand the
    // traffic back. ping binds itself to the interface, so the answer is about that path only.
    void probeWifi()
    {
        if (m_state != QLatin1String("engaged") || m_wifiIf.isEmpty()) {
            return;
        }
        if (m_ping.state() != QProcess::NotRunning) {
            return;
        }
        m_ping.start(QStringLiteral("ping"), {QStringLiteral("-I"), m_wifiIf, QStringLiteral("-c"), QStringLiteral("1"),
                                              QStringLiteral("-W"), QStringLiteral("2"), QStringLiteral("1.1.1.1")});
    }

    // ---- NM reads (blocking, 2 s ceiling - the same budget NetworkModel uses) -------------
    static QVariant nmProp(const QString &path, const QString &iface, const QString &name)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"), path,
                                                        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        m << iface << name;
        const QDBusMessage r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
                   ? r.arguments().first().value<QDBusVariant>().variant() : QVariant();
    }
    static QString nmDevicePath(const QString &iface)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
                                                        QStringLiteral("/org/freedesktop/NetworkManager"),
                                                        QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("GetDevices"));
        const QDBusReply<QList<QDBusObjectPath>> r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        if (!r.isValid()) {
            return QString();
        }
        for (const QDBusObjectPath &p : r.value()) {
            if (nmProp(p.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("Interface")).toString() == iface) {
                return p.path();
            }
        }
        return QString();
    }
    // The probe asks about the upstream that is not the tether itself - wifi or ethernet.
    static QString upstreamInterface()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
                                                        QStringLiteral("/org/freedesktop/NetworkManager"),
                                                        QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("GetDevices"));
        const QDBusReply<QList<QDBusObjectPath>> r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        if (!r.isValid()) {
            return QString();
        }
        for (const QDBusObjectPath &p : r.value()) {
            const uint type = nmProp(p.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("DeviceType")).toUInt();
            const QString iface = nmProp(p.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("Interface")).toString();
            if ((type == 1 || type == 2) && iface != QLatin1String("bnep0") && !iface.isEmpty()) {   // ethernet or wifi
                return iface;
            }
        }
        return QString();
    }
    static QString profilePath()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
                                                        QStringLiteral("/org/freedesktop/NetworkManager/Settings"),
                                                        QStringLiteral("org.freedesktop.NetworkManager.Settings"), QStringLiteral("ListConnections"));
        const QDBusReply<QList<QDBusObjectPath>> r = QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        if (!r.isValid()) {
            return QString();
        }
        for (const QDBusObjectPath &p : r.value()) {
            QDBusMessage g = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"), p.path(),
                                                            QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("GetSettings"));
            const QDBusMessage reply = QDBusConnection::systemBus().call(g, QDBus::Block, 2000);
            if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
                continue;
            }
            const NMSettings s = qdbus_cast<NMSettings>(reply.arguments().first().value<QDBusArgument>());
            const QVariantMap c = s.value(QStringLiteral("connection"));
            if (c.value(QStringLiteral("id")).toString() == QLatin1String("phone-tether")) {
                return p.path();
            }
        }
        return QString();
    }

    // The profile the engine activates. Created on demand (fresh machines) or re-pointed to
    // the marked router; metric 50 + dns-priority 50 are the whole reason this needs no root.
    void ensureProfile(const QString &addr)
    {
        if (m_fake) {
            return;
        }
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p, addr](int code) {
            p->deleteLater();
            const QString out = QString::fromUtf8(p->readAllStandardOutput()).remove(QLatin1Char('\\')).trimmed();
            if (code == 0 && out == addr) {
                return;   // already bound to this router
            }
            const QStringList extra = {QStringLiteral("ipv4.route-metric"), QStringLiteral("50"), QStringLiteral("ipv6.route-metric"), QStringLiteral("50"),
                                       QStringLiteral("ipv4.dns-priority"), QStringLiteral("50"), QStringLiteral("ipv6.dns-priority"), QStringLiteral("50"),
                                       QStringLiteral("connection.autoconnect"), QStringLiteral("no")};
            QStringList args;
            if (code == 0) {
                args << QStringLiteral("connection") << QStringLiteral("modify") << QStringLiteral("phone-tether") << QStringLiteral("bluetooth.bdaddr") << addr;
                args << extra;
                qInfo().noquote() << "tether: re-pointing the phone-tether profile to" << addr;
            } else {
                args << QStringLiteral("connection") << QStringLiteral("add") << QStringLiteral("type") << QStringLiteral("bluetooth")
                     << QStringLiteral("con-name") << QStringLiteral("phone-tether") << QStringLiteral("ifname") << QStringLiteral("bnep0")
                     << QStringLiteral("bluetooth.bdaddr") << addr << QStringLiteral("bluetooth.type") << QStringLiteral("nap");
                args << extra;
                qInfo().noquote() << "tether: creating the phone-tether profile for" << addr;
            }
            QProcess::startDetached(QStringLiteral("nmcli"), args);
        });
        p->start(QStringLiteral("nmcli"), {QStringLiteral("-g"), QStringLiteral("bluetooth.bdaddr"),
                                           QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("phone-tether")});
    }

    NetworkModel *m_net;
    BluetoothModel *m_bt;
    QSettings m_prefs{QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat};
    QTimer m_sick, m_backoff, m_stuck, m_watchdog, m_probe;
    QProcess m_ping;
    QString m_state = QStringLiteral("idle"), m_router, m_wifiIf;
    int m_fails = 0, m_alive = 0;
    bool m_engaged = false, m_lastSick = false, m_fake = false;
};
