// Live system state for the bar glyphs and (later) the large island's controls.
// Plain polling of sysfs and the tools every KDE/PipeWire desktop already has; each probe is
// small and cheap, and a missing tool simply leaves its glyph hidden.
#pragma once

#include <QDBusInterface>
#include <QFile>
#include <QObject>
#include <QProcess>
#include <QTimer>

class SystemInfo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY batteryChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)          // 0..100
    Q_PROPERTY(bool muted READ muted NOTIFY volumeChanged)
    Q_PROPERTY(QString network READ network NOTIFY networkChanged)   // "wifi" | "ethernet" | "offline"
    Q_PROPERTY(int wifiSignal READ wifiSignal NOTIFY networkChanged) // 0..100
    Q_PROPERTY(bool bluetoothOn READ bluetoothOn NOTIFY bluetoothChanged)
    Q_PROPERTY(int bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY networkChanged)
    Q_PROPERTY(QString wifiName READ wifiName NOTIFY networkChanged)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged)    // 0..100, -1 if unavailable

public:
    explicit SystemInfo(QObject *parent = nullptr)
        : QObject(parent)
    {
        every(5000, [this] { readBattery(); });
        every(1500, [this] { run(m_volume, {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, QStringLiteral("wpctl")); });
        every(5000, [this] { run(m_net, {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE"), QStringLiteral("dev")}, QStringLiteral("nmcli")); });
        every(5000, [this] { run(m_wifi, {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SIGNAL"), QStringLiteral("dev"), QStringLiteral("wifi")}, QStringLiteral("nmcli")); });
        every(4000, [this] { run(m_radio, {QStringLiteral("radio"), QStringLiteral("wifi")}, QStringLiteral("nmcli")); });
        every(6000, [this] { run(m_ssid, {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME,TYPE"), QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("--active")}, QStringLiteral("nmcli")); });
        every(3000, [this] { readBrightness(); });
        every(8000, [this] { run(m_bt, {QStringLiteral("show")}, QStringLiteral("bluetoothctl")); });
        every(8000, [this] { run(m_btDev, {QStringLiteral("devices"), QStringLiteral("Connected")}, QStringLiteral("bluetoothctl")); });

        connect(&m_volume, &QProcess::finished, this, [this] { parseVolume(); });
        connect(&m_radio, &QProcess::finished, this, [this] {
            const bool on = QString::fromUtf8(m_radio.readAllStandardOutput()).trimmed() == QLatin1String("enabled");
            if (on != m_wifiEnabled) { m_wifiEnabled = on; Q_EMIT networkChanged(); }
        });
        connect(&m_ssid, &QProcess::finished, this, [this] {
            QString name;
            for (const QString &line : QString::fromUtf8(m_ssid.readAllStandardOutput()).split(QLatin1Char('\n'))) {
                const QStringList f = line.split(QLatin1Char(':'));
                if (f.size() >= 2 && f.at(1).contains(QLatin1String("wireless"))) { name = f.at(0); break; }
            }
            if (name != m_wifiName) { m_wifiName = name; Q_EMIT networkChanged(); }
        });
        // QObject::sender() is not available for functor connections, so each probe stores its
        // own output before the shared parser runs.
        connect(&m_net, &QProcess::finished, this, [this] { m_netOut = QString::fromUtf8(m_net.readAllStandardOutput()); parseNetwork(); });
        connect(&m_wifi, &QProcess::finished, this, [this] { m_wifiOut = QString::fromUtf8(m_wifi.readAllStandardOutput()); parseNetwork(); });
        connect(&m_bt, &QProcess::finished, this, [this] { m_btOn = QString::fromUtf8(m_bt.readAllStandardOutput()).contains(QLatin1String("Powered: yes")); Q_EMIT bluetoothChanged(); });
        connect(&m_btDev, &QProcess::finished, this, [this] { m_btDevices = QString::fromUtf8(m_btDev.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts).size(); Q_EMIT bluetoothChanged(); });
    }

    bool hasBattery() const { return m_hasBattery; }
    int batteryPercent() const { return m_batteryPercent; }
    bool charging() const { return m_charging; }
    int volume() const { return m_volumePercent; }
    bool muted() const { return m_muted; }
    QString network() const { return m_network; }
    int wifiSignal() const { return m_wifiSignal; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    QString wifiName() const { return m_wifiName; }
    int brightness() const { return m_brightness; }
    bool bluetoothOn() const { return m_btOn; }
    int bluetoothDevices() const { return m_btDevices; }

    // ---- controls (fire and forget; the next poll picks up the real state) ----
    Q_INVOKABLE void setVolume(int percent)
    {
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                                                           QString::number(qBound(0, percent, 100) / 100.0, 'f', 2)});
        m_volumePercent = qBound(0, percent, 100);
        Q_EMIT volumeChanged();
    }
    Q_INVOKABLE void toggleMute()
    {
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")});
        m_muted = !m_muted;
        Q_EMIT volumeChanged();
    }
    Q_INVOKABLE void setBrightness(int percent)
    {
        if (m_brightnessMax <= 0) {
            return;
        }
        const int value = qRound(qBound(1, percent, 100) / 100.0 * m_brightnessMax);
        QDBusInterface i(QStringLiteral("org.kde.Solid.PowerManagement"), QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
                         QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl"));
        i.asyncCall(QStringLiteral("setBrightness"), value);
        m_brightness = qBound(1, percent, 100);
        Q_EMIT brightnessChanged();
    }
    Q_INVOKABLE void toggleWifi()
    {
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), m_wifiEnabled ? QStringLiteral("off") : QStringLiteral("on")});
        m_wifiEnabled = !m_wifiEnabled;
        Q_EMIT networkChanged();
    }
    Q_INVOKABLE void toggleBluetooth()
    {
        QProcess::startDetached(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), m_btOn ? QStringLiteral("off") : QStringLiteral("on")});
        m_btOn = !m_btOn;
        Q_EMIT bluetoothChanged();
    }

Q_SIGNALS:
    void brightnessChanged();
    void batteryChanged();
    void volumeChanged();
    void networkChanged();
    void bluetoothChanged();

private:
    template<typename F> void every(int ms, F f)
    {
        auto *t = new QTimer(this);
        t->setInterval(ms);
        connect(t, &QTimer::timeout, this, f);
        t->start();
        QTimer::singleShot(100, this, f);
    }
    void run(QProcess &p, const QStringList &args, const QString &program)
    {
        if (p.state() == QProcess::NotRunning) {
            p.start(program, args);
        }
    }
    static QString readFile(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
    }

    void readBrightness()
    {
        // PowerDevil owns the scale (0..brightnessMax, not sysfs's raw range), for reading and writing.
        QDBusInterface i(QStringLiteral("org.kde.Solid.PowerManagement"), QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl"),
                         QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl"));
        const QDBusReply<int> max = i.call(QStringLiteral("brightnessMax"));
        const QDBusReply<int> cur = i.call(QStringLiteral("brightness"));
        if (!max.isValid() || !cur.isValid() || max.value() <= 0) {
            return;
        }
        m_brightnessMax = max.value();
        const int pct = qRound(100.0 * cur.value() / m_brightnessMax);
        if (pct != m_brightness) {
            m_brightness = pct;
            Q_EMIT brightnessChanged();
        }
    }
    void readBattery()
    {
        const QString base = QStringLiteral("/sys/class/power_supply/BAT0/");
        const QString cap = readFile(base + QStringLiteral("capacity"));
        const bool has = !cap.isEmpty();
        const int pct = cap.toInt();
        const bool chg = readFile(base + QStringLiteral("status")) == QLatin1String("Charging");
        if (has != m_hasBattery || pct != m_batteryPercent || chg != m_charging) {
            m_hasBattery = has;
            m_batteryPercent = pct;
            m_charging = chg;
            Q_EMIT batteryChanged();
        }
    }
    void parseVolume()
    {
        const QString out = QString::fromUtf8(m_volume.readAllStandardOutput());   // "Volume: 0.40 [MUTED]"
        const QStringList parts = out.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() >= 2) {
            const int v = qRound(parts.at(1).toDouble() * 100);
            const bool m = out.contains(QLatin1String("[MUTED]"));
            if (v != m_volumePercent || m != m_muted) {
                m_volumePercent = v;
                m_muted = m;
                Q_EMIT volumeChanged();
            }
        }
    }
    void parseNetwork()
    {
        QString network = QStringLiteral("offline");
        for (const QString &line : m_netOut.split(QLatin1Char('\n'))) {
            const QStringList f = line.split(QLatin1Char(':'));
            if (f.size() >= 2 && f.at(1) == QLatin1String("connected")) {
                if (f.at(0) == QLatin1String("wifi")) {
                    network = QStringLiteral("wifi");
                    break;
                }
                if (f.at(0) == QLatin1String("ethernet")) {
                    network = QStringLiteral("ethernet");
                }
            }
        }
        int signal = 0;
        for (const QString &line : m_wifiOut.split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("*:"))) {
                signal = line.mid(2).toInt();
            }
        }
        if (network == QLatin1String("wifi") && signal == 0) {
            signal = 80;   // connected, but NetworkManager flags no scanned AP as in use: show full strength
        }
        if (network != m_network || signal != m_wifiSignal) {
            m_network = network;
            m_wifiSignal = signal;
            Q_EMIT networkChanged();
        }
    }
    QProcess m_volume, m_net, m_wifi, m_bt, m_btDev, m_radio, m_ssid;
    QString m_wifiName;
    bool m_wifiEnabled = true;
    int m_brightness = -1, m_brightnessMax = 0;
    QString m_netOut, m_wifiOut;
    bool m_hasBattery = false, m_charging = false, m_muted = false, m_btOn = false;
    int m_batteryPercent = 0, m_volumePercent = 0, m_wifiSignal = 0, m_btDevices = 0;
    QString m_network = QStringLiteral("offline");
};
