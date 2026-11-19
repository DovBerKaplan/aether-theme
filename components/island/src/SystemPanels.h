// Backends for the Battery, Display and Power panels. All plain D-Bus or the tools Plasma already
// ships; nothing here polls - they read when a panel opens and follow signals where there are any.
//   PowerModel      UPower (battery) + power-profiles-daemon
//   DisplayModel    KWin Night Light (through kwinrc) + the two Aether global themes
//   SessionActions  lock / sleep / restart / shut down / log out
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

namespace PanelDbus {
inline QVariantMap getAll(const QDBusConnection &bus, const QString &service, const QString &path, const QString &iface)
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    m << iface;
    const QDBusMessage r = bus.call(m, QDBus::Block, 1500);
    return r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty()
               ? qdbus_cast<QVariantMap>(r.arguments().first().value<QDBusArgument>()) : QVariantMap();
}
inline QString readText(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}
inline QString tool(const QString &program, const QStringList &args)
{
    QProcess p;
    p.start(program, args);
    p.waitForFinished(1500);
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}
}

class PowerModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY changed)
    Q_PROPERTY(int percent READ percent NOTIFY changed)
    Q_PROPERTY(QString state READ state NOTIFY changed)           // charging | discharging | full | empty | unknown
    Q_PROPERTY(QString timeKind READ timeKind NOTIFY changed)     // charging | discharging | full | "" - the panel words it
    Q_PROPERTY(int timeMinutes READ timeMinutes NOTIFY changed)
    Q_PROPERTY(double watts READ watts NOTIFY changed)
    Q_PROPERTY(int health READ health NOTIFY changed)             // full vs design capacity, -1 unknown
    Q_PROPERTY(QString profile READ profile NOTIFY changed)       // power-saver | balanced | performance
    Q_PROPERTY(QStringList profiles READ profiles NOTIFY changed)
    Q_PROPERTY(bool degraded READ degraded NOTIFY changed)        // the firmware is throttling the performance profile

public:
    explicit PowerModel(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(200);
        connect(&m_debounce, &QTimer::timeout, this, [this] { refresh(); });
        auto sys = QDBusConnection::systemBus();
        sys.connect(QStringLiteral("org.freedesktop.UPower"), DisplayDevice, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this, SLOT(onSignal(QString, QVariantMap, QStringList)));
        sys.connect(QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this, SLOT(onSignal(QString, QVariantMap, QStringList)));
        QTimer::singleShot(0, this, [this] { refresh(); });
    }
    bool hasBattery() const { return m_has; }
    int percent() const { return m_percent; }
    QString state() const { return m_state; }
    QString timeKind() const { return m_timeKind; }
    int timeMinutes() const { return m_timeMins; }
    double watts() const { return m_watts; }
    int health() const { return m_health; }
    QString profile() const { return m_profile; }
    QStringList profiles() const { return m_profiles; }
    bool degraded() const { return m_degraded; }

    Q_INVOKABLE void setProfile(const QString &name)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"),
                                                        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
        m << QStringLiteral("net.hadess.PowerProfiles") << QStringLiteral("ActiveProfile") << QVariant::fromValue(QDBusVariant(name));
        QDBusConnection::systemBus().asyncCall(m);
        m_profile = name;   // optimistic; the daemon's signal corrects it
        Q_EMIT changed();
    }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_powerdevilprofilesconfig")}); }
    Q_INVOKABLE void refresh()
    {
        auto sys = QDBusConnection::systemBus();
        const QVariantMap b = PanelDbus::getAll(sys, QStringLiteral("org.freedesktop.UPower"), DisplayDevice, QStringLiteral("org.freedesktop.UPower.Device"));
        m_has = b.value(QStringLiteral("IsPresent")).toBool();
        m_percent = qRound(b.value(QStringLiteral("Percentage")).toDouble());
        m_watts = b.value(QStringLiteral("EnergyRate")).toDouble();
        switch (b.value(QStringLiteral("State")).toUInt()) {
        case 1: case 5: m_state = QStringLiteral("charging"); break;      // 5: pending charge
        case 2: case 6: m_state = QStringLiteral("discharging"); break;   // 6: pending discharge
        case 3: m_state = QStringLiteral("empty"); break;
        case 4: m_state = QStringLiteral("full"); break;
        default: m_state = QStringLiteral("unknown"); break;
        }
        const qint64 secs = m_state == QLatin1String("charging") ? b.value(QStringLiteral("TimeToFull")).toLongLong()
                                                                  : b.value(QStringLiteral("TimeToEmpty")).toLongLong();
        m_timeMins = secs > 0 ? int((secs + 30) / 60) : 0;
        m_timeKind = m_state == QLatin1String("full") ? QStringLiteral("full")
                   : (m_timeMins > 0 && (m_state == QLatin1String("charging") || m_state == QLatin1String("discharging"))) ? m_state : QString();
        const double full = PanelDbus::readText(QStringLiteral("/sys/class/power_supply/BAT0/energy_full")).toDouble();
        const double design = PanelDbus::readText(QStringLiteral("/sys/class/power_supply/BAT0/energy_full_design")).toDouble();
        m_health = design > 0 && full > 0 ? qMin(100, qRound(100.0 * full / design)) : -1;
        const QVariantMap pp = PanelDbus::getAll(sys, QStringLiteral("net.hadess.PowerProfiles"), QStringLiteral("/net/hadess/PowerProfiles"), QStringLiteral("net.hadess.PowerProfiles"));
        m_profile = pp.value(QStringLiteral("ActiveProfile")).toString();
        m_degraded = !pp.value(QStringLiteral("PerformanceDegraded")).toString().isEmpty();
        m_profiles.clear();
        for (const QVariantMap &p : qdbus_cast<QList<QVariantMap>>(pp.value(QStringLiteral("Profiles")).value<QDBusArgument>())) {
            m_profiles << p.value(QStringLiteral("Profile")).toString();
        }
        Q_EMIT changed();
    }

Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void onSignal(const QString &, const QVariantMap &, const QStringList &) { m_debounce.start(); }

private:
    static inline const QString DisplayDevice = QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice");
    QTimer m_debounce;
    bool m_has = false, m_degraded = false;
    int m_percent = 0, m_health = -1;
    double m_watts = 0;
    QString m_state = QStringLiteral("unknown"), m_timeKind, m_profile;
    int m_timeMins = 0;
    QStringList m_profiles;
};

class DisplayModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool nightAvailable READ nightAvailable NOTIFY changed)
    Q_PROPERTY(bool nightEnabled READ nightEnabled NOTIFY changed)
    Q_PROPERTY(int nightTemperature READ nightTemperature NOTIFY changed)   // Kelvin used at night, 1000-6500
    Q_PROPERTY(bool dark READ dark NOTIFY changed)                          // the dark Aether theme is active
    Q_PROPERTY(bool autoTheme READ autoTheme NOTIFY changed)                // KDE switches dark/light by time of day

public:
    explicit DisplayModel(QObject *parent = nullptr) : QObject(parent)
    {
        // The tile follows System Settings and automatic day/night too: any change to kdeglobals re-reads the mode.
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] {
            if (!m_watch.files().contains(m_globals)) {      // the file is replaced on every write: watch the new one
                m_watch.addPath(m_globals);
            }
            const bool was = m_dark, wasAuto = m_auto;
            readMode();
            if (was != m_dark || wasAuto != m_auto) {
                Q_EMIT changed();
            }
        });
        connect(&m_watch, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
        m_watch.addPath(m_globals);
        readMode();
    }
    bool nightAvailable() const { return m_available; }
    bool nightEnabled() const { return m_enabled; }
    int nightTemperature() const { return m_temp; }
    bool dark() const { return m_dark; }
    bool autoTheme() const { return m_auto; }

    Q_INVOKABLE void refresh()
    {
        const QVariantMap nl = PanelDbus::getAll(QDBusConnection::sessionBus(), QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/NightLight"), QStringLiteral("org.kde.KWin.NightLight"));
        m_available = nl.value(QStringLiteral("available")).toBool();
        m_enabled = PanelDbus::tool(QStringLiteral("kreadconfig6"), {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"), QStringLiteral("--key"), QStringLiteral("Active")}) == QLatin1String("true");
        const int t = PanelDbus::tool(QStringLiteral("kreadconfig6"), {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"), QStringLiteral("--key"), QStringLiteral("NightTemperature"), QStringLiteral("--default"), QStringLiteral("4500")}).toInt();
        m_temp = qBound(1000, t, 6500);
        readMode();
        Q_EMIT changed();
    }
    Q_INVOKABLE void setNightEnabled(bool on) { writeNight(QStringLiteral("Active"), on ? QStringLiteral("true") : QStringLiteral("false")); m_enabled = on; Q_EMIT changed(); }
    Q_INVOKABLE void setNightTemperature(int kelvin)
    {
        m_temp = qBound(1000, kelvin, 6500);
        writeNight(QStringLiteral("NightTemperature"), QString::number(m_temp));
        Q_EMIT changed();
    }
    Q_INVOKABLE void setDark(bool dark)
    {
        // A mode picked by hand is deliberate: automatic switching must not override it later in the day.
        if (m_auto) {
            writeGlobal(QStringLiteral("KDE"), QStringLiteral("AutomaticLookAndFeel"), QStringLiteral("false"));
            m_auto = false;
        }
        applyTheme(dark);
    }
    Q_INVOKABLE void setAutoTheme(bool on)
    {
        writeGlobal(QStringLiteral("KDE"), QStringLiteral("DefaultDarkLookAndFeel"), QStringLiteral("org.aether.glass.desktop"));
        writeGlobal(QStringLiteral("KDE"), QStringLiteral("DefaultLightLookAndFeel"), QStringLiteral("org.aether.serenity.desktop"));
        writeGlobal(QStringLiteral("KDE"), QStringLiteral("AutomaticLookAndFeel"), on ? QStringLiteral("true") : QStringLiteral("false"));
        m_auto = on;
        if (on) {
            // KDE re-evaluates the pair only at its next transition (verified: the key alone flips
            // nothing, even after a reconfigure), so honor the hour right now. Night Color's fixed
            // times when set (HHMM as hundredths), otherwise dusk 18:00 / dawn 06:00.
            const auto kr = [](const char *key, const char *fallback) {
                return PanelDbus::tool(QStringLiteral("kreadconfig6"),
                                       {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
                                        QStringLiteral("NightColor"), QStringLiteral("--key"), QLatin1String(key),
                                        QStringLiteral("--default"), QLatin1String(fallback)}).toInt();
            };
            const int evening = kr("EveningBeginFixed", "1800");
            const int morning = kr("MorningBeginFixed", "600");
            const int now = QTime::currentTime().hour() * 100 + QTime::currentTime().minute();
            applyTheme(now >= evening || now < morning, /*reassertAuto=*/true, /*lnf=*/false);
        }
        Q_EMIT changed();
        QTimer::singleShot(2500, this, [this] { refresh(); });      // if the switch did not happen, the tile must not keep lying
    }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kscreen")}); }

Q_SIGNALS:
    void changed();

private:
    // plasma-apply-colorscheme is the only path that both writes the scheme and notifies every
    // running app (KConfigWatcher over D-Bus), so open windows repaint live. It must run FIRST:
    // lookandfeeltool switches the identity (wallpaper, icons) but leaves the live colors alone,
    // and a stale ColorScheme in kdedefaults once made both tools believe the scheme was already
    // active - the toggle flipped nothing and apps kept their old palette until restart.
    void applyTheme(bool dark, bool reassertAuto = false, bool lnf = true)
    {
        QProcess::startDetached(QStringLiteral("plasma-apply-colorscheme"),
                                {dark ? QStringLiteral("AetherGlass") : QStringLiteral("AetherSerenity")});
        // lookandfeeltool is what makes a hand-picked mode full (wallpaper, icons) - but it also
        // DELETES KDE/AutomaticLookAndFeel from kdeglobals (Plasma reads its apply as a manual
        // theme choice) and leaks ColorScheme into kdedefaults, both long after it was launched
        // (it can take seconds). The by-hours nudge therefore skips it: colors are the visible
        // part of the hour, and KDE's own transitions apply the registered pair anyway.
        if (lnf) {
            QProcess::startDetached(QStringLiteral("lookandfeeltool"),
                                    {QStringLiteral("-a"), dark ? QStringLiteral("org.aether.glass.desktop")
                                                                : QStringLiteral("org.aether.serenity.desktop")});
        }
        m_dark = dark;
        Q_EMIT changed();
        if (reassertAuto) {
            QTimer::singleShot(2500, this, [this] {       // belt and suspenders: nothing in this path deletes the key anymore
                if (!m_auto) {
                    return;
                }
                writeGlobal(QStringLiteral("KDE"), QStringLiteral("AutomaticLookAndFeel"), QStringLiteral("true"));
                refresh();
            });
        }
        QTimer::singleShot(2500, this, [this] { refresh(); });      // if the switch did not happen, the tile must not keep lying
    }
    void writeGlobal(const QString &group, const QString &key, const QString &value)
    {
        QProcess::execute(QStringLiteral("kwriteconfig6"),
                          {QStringLiteral("--file"), QStringLiteral("kdeglobals"), QStringLiteral("--group"), group,
                           QStringLiteral("--key"), key, value});
    }
    void writeNight(const QString &key, const QString &value)
    {
        QProcess::execute(QStringLiteral("kwriteconfig6"), {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"), QStringLiteral("--key"), key, value});
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure")));
    }
    // The color scheme decides: ours by name, any other by how light its window color is.
    void readMode()
    {
        const auto kr = [](const QStringList &a) { return PanelDbus::tool(QStringLiteral("kreadconfig6"), a); };
        const QString scheme = kr({QStringLiteral("--file"), QStringLiteral("kdeglobals"), QStringLiteral("--group"), QStringLiteral("General"), QStringLiteral("--key"), QStringLiteral("ColorScheme")});
        if (scheme == QLatin1String("AetherSerenity")) {
            m_dark = false;
        } else if (scheme == QLatin1String("AetherGlass")) {
            m_dark = true;
        } else {
            const QStringList rgb = kr({QStringLiteral("--file"), QStringLiteral("kdeglobals"), QStringLiteral("--group"), QStringLiteral("Colors:Window"), QStringLiteral("--key"), QStringLiteral("BackgroundNormal")}).split(QLatin1Char(','));
            // r,g,b - or r,g,b,a: the glass schemes carry an alpha, and a strict "three" read every
            // one of them as light (the tile said Light while the desktop was dark).
            m_dark = rgb.size() >= 3 && (0.299 * rgb[0].toInt() + 0.587 * rgb[1].toInt() + 0.114 * rgb[2].toInt()) < 128;
        }
        m_auto = kr({QStringLiteral("--file"), QStringLiteral("kdeglobals"), QStringLiteral("--group"), QStringLiteral("KDE"), QStringLiteral("--key"), QStringLiteral("AutomaticLookAndFeel")}) == QLatin1String("true");
    }
    const QString m_globals = QDir::homePath() + QStringLiteral("/.config/kdeglobals");
    QFileSystemWatcher m_watch;
    QTimer m_debounce;
    bool m_available = false, m_enabled = false, m_dark = true, m_auto = false;
    int m_temp = 4500;
};

class SessionActions : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool canSleep READ canSleep CONSTANT)
    Q_PROPERTY(bool canFirmware READ canFirmware CONSTANT)

public:
    explicit SessionActions(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_canSleep = can(QStringLiteral("CanSuspend"));
        m_canFirmware = can(QStringLiteral("CanRebootToFirmwareSetup"));
    }
    bool canSleep() const { return m_canSleep; }
    bool canFirmware() const { return m_canFirmware; }

    Q_INVOKABLE void lock() { QProcess::startDetached(QStringLiteral("loginctl"), {QStringLiteral("lock-session")}); }
    Q_INVOKABLE void sleep()
    {
        QDBusMessage m = login(QStringLiteral("Suspend"));
        m << true;
        QDBusConnection::systemBus().asyncCall(m);
    }
    // These three go through Plasma's session manager, so apps get to save first.
    Q_INVOKABLE void logout() { shutdown(QStringLiteral("logout")); }
    Q_INVOKABLE void restart() { shutdown(QStringLiteral("logoutAndReboot")); }
    Q_INVOKABLE void shutDown() { shutdown(QStringLiteral("logoutAndShutdown")); }
    Q_INVOKABLE void restartToFirmware()
    {
        QDBusMessage m = login(QStringLiteral("SetRebootToFirmwareSetup"));
        m << true;
        QDBusConnection::systemBus().call(m, QDBus::Block, 2000);
        restart();
    }

private:
    static QDBusMessage login(const QString &method)
    {
        return QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"), QStringLiteral("org.freedesktop.login1.Manager"), method);
    }
    static bool can(const QString &method)
    {
        const QDBusReply<QString> r = QDBusConnection::systemBus().call(login(method), QDBus::Block, 1500);
        return r.isValid() && (r.value() == QLatin1String("yes") || r.value() == QLatin1String("challenge"));
    }
    static void shutdown(const QString &method)
    {
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), method));
    }
    bool m_canSleep = false, m_canFirmware = false;
};
