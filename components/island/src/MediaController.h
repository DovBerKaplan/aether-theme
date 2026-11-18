// Now-playing state and transport controls from whichever MPRIS player is active
// (Spotify, a browser, VLC...). Polls once a second; the player that is Playing wins,
// otherwise the first one that exists.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <memory>

class MediaController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasPlayer READ hasPlayer NOTIFY changed)
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY changed)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)   // 0..1
    Q_PROPERTY(int lengthSec READ lengthSec NOTIFY changed)           // 0 = unknown (stream)
    Q_PROPERTY(int positionSec READ positionSec NOTIFY progressChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY changed)
    Q_PROPERTY(QString playerName READ playerName NOTIFY changed)
    Q_PROPERTY(QString playerIcon READ playerIcon NOTIFY changed)   // absolute path or empty
    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)     // false = the widget was removed: nothing runs

public:
    explicit MediaController(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_pollTimer.setInterval(1000);
        connect(&m_pollTimer, &QTimer::timeout, this, &MediaController::poll);
        m_pollTimer.start();
        QTimer::singleShot(200, this, &MediaController::poll);
    }

    bool enabled() const { return m_enabled; }
    // The YouTube Music widget on/off. Off means invisible AND not running: polling and audio capture
    // stop, the app is asked to quit and then stopped (whole process tree, so no window and no tray
    // icon is left), and its autostart is disabled. On brings the autostart back; `start` also launches
    // the app now (a user adding the widget back), while the startup call passes false because the
    // session's own autostart already did that.
    Q_INVOKABLE void setEnabled(bool on, bool start = false)
    {
        if (m_enabled == on && !start) {
            return;
        }
        m_enabled = on;
        setAutostart(on);
        if (on) {
            m_pollTimer.start();
            QTimer::singleShot(200, this, &MediaController::poll);
            if (start) {
                launch();
            }
        } else {
            m_pollTimer.stop();
            const QString svc = m_service;
            apply(QString(), QVariantMap());   // forget the player: the card and the bars see "no player"
            stopPear(svc);
        }
        Q_EMIT enabledChanged();
    }

    bool hasPlayer() const { return !m_service.isEmpty(); }
    bool playing() const { return m_playing; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString artUrl() const { return m_artUrl; }
    qreal progress() const { return m_progress; }
    int lengthSec() const { return m_lengthSec; }
    int positionSec() const { return m_positionSec; }
    bool canSeek() const { return m_canSeek; }
    QString playerName() const { return m_name; }
    QString playerIcon() const
    {
        const QString p = pearPath("usr/share/icons/hicolor/512x512/apps/youtube-music.png");
        return QFile::exists(p) ? p : QString();
    }

    Q_INVOKABLE void playPause() { call(QStringLiteral("PlayPause")); }
    Q_INVOKABLE void next() { call(QStringLiteral("Next")); }
    Q_INVOKABLE void previous() { call(QStringLiteral("Previous")); }

    // Jump to a fraction (0..1) of the track. Optimistic: the bar moves at once,
    // the next poll reconciles with whatever the player actually did.
    Q_INVOKABLE void seek(qreal fraction)
    {
        if (m_service.isEmpty() || m_trackId.isEmpty() || m_lengthUs <= 0) {
            return;
        }
        const qint64 us = qint64(qBound<qreal>(0, fraction, 1) * m_lengthUs);
        auto msg = mpris(m_service, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("SetPosition"));
        msg << QVariant::fromValue(QDBusObjectPath(m_trackId)) << us;
        QDBusConnection::sessionBus().asyncCall(msg);
        m_posUs = us;
        m_positionSec = int(us / 1000000);
        m_progress = qreal(us) / m_lengthUs;
        Q_EMIT progressChanged();
        QTimer::singleShot(300, this, &MediaController::poll);
    }

    Q_INVOKABLE void raise()
    {
        if (m_service.isEmpty()) {
            return;
        }
        QDBusConnection::sessionBus().asyncCall(mpris(m_service, QStringLiteral("org.mpris.MediaPlayer2"), QStringLiteral("Raise")));
    }

    // Start (or focus - it holds a single-instance lock) the preferred player.
    // Runs under XWayland: Chromium's native Wayland path (Vulkan + the color
    // manager protocol) is broken on this machine - blank white windows and
    // CHECK crashes (SIGILL). The log itself points to --ozone-platform=x11.
    Q_INVOKABLE void launch()
    {
        if (!m_enabled || !qEnvironmentVariable("AETHER_PEAR_PATTERN").isEmpty()) {   // the second is the test hook: never start the real app
            return;
        }
        const QString bin = pearPath("opt/YouTube Music/youtube-music");
        const QStringList cmd = { QFile::exists(bin) ? bin : QStringLiteral("pear-desktop"), QStringLiteral("--no-sandbox"), QStringLiteral("--ozone-platform=x11") };
        // In a scope of its own, not in aether-island.service: a restart of the island used to take
        // the app down with it (systemd stops the whole cgroup), and the next launch resumed a song.
        if (!QStandardPaths::findExecutable(QStringLiteral("systemd-run")).isEmpty()) {
            QProcess::startDetached(QStringLiteral("systemd-run"), QStringList{ QStringLiteral("--user"), QStringLiteral("--scope"), QStringLiteral("--collect"), QStringLiteral("--quiet"), QStringLiteral("--") } + cmd);
        } else {
            QProcess::startDetached(cmd.first(), cmd.mid(1));
        }
    }

Q_SIGNALS:
    void changed();
    void enabledChanged();
    void progressChanged();
    void playbackStarted();   // rising edge: a track began playing

private:
    // The processes that belong to the app: every Chromium child carries the install path.
    static QString pearPattern()
    {
        const QString o = qEnvironmentVariable("AETHER_PEAR_PATTERN");   // test hook: aim the stop at a stand-in process
        return o.isEmpty() ? QStringLiteral("/.local/opt/pear-desktop/opt/YouTube Music/") : o;
    }
    void stopPear(const QString &service)
    {
        if (!service.isEmpty()) {   // polite first: MPRIS Quit
            QDBusConnection::sessionBus().asyncCall(mpris(service, QStringLiteral("org.mpris.MediaPlayer2"), QStringLiteral("Quit")));
        }
        QTimer::singleShot(700, this, [] { QProcess::execute(QStringLiteral("pkill"), {QStringLiteral("-TERM"), QStringLiteral("-f"), pearPattern()}); });
        QTimer::singleShot(3700, this, [] { QProcess::execute(QStringLiteral("pkill"), {QStringLiteral("-KILL"), QStringLiteral("-f"), pearPattern()}); });
    }
    // XDG autostart: Hidden=true disables an entry without deleting it, so adding the widget back is one write.
    static void setAutostart(bool on)
    {
        const QString o = qEnvironmentVariable("AETHER_PEAR_AUTOSTART");   // test hook
        const QString path = o.isEmpty() ? QDir::homePath() + QStringLiteral("/.config/autostart/pear-desktop.desktop") : o;
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly)) {
            return;
        }
        QStringList out;
        for (const QString &line : QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("Hidden="))) {
                continue;
            }
            out << (line.startsWith(QLatin1String("X-GNOME-Autostart-enabled=")) ? QStringLiteral("X-GNOME-Autostart-enabled=") + (on ? QStringLiteral("true") : QStringLiteral("false")) : line);
        }
        f.close();
        while (!out.isEmpty() && out.last().isEmpty()) {
            out.removeLast();
        }
        if (!on) {
            out << QStringLiteral("Hidden=true");
        }
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write(out.join(QLatin1Char('\n')).toUtf8() + '\n');
        }
    }
    QTimer m_pollTimer;
    bool m_enabled = true;

    static QString pearPath(const char *rel)
    {
        return QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
               + QStringLiteral("/.local/opt/pear-desktop/") + QLatin1String(rel);
    }
    // Raw messages and async calls only: QDBusInterface introspects synchronously and a
    // blocking Get waits up to 25 s, so one busy or hung player used to freeze the island.
    static QDBusMessage mpris(const QString &service, const QString &iface, const QString &method)
    {
        return QDBusMessage::createMethodCall(service, QStringLiteral("/org/mpris/MediaPlayer2"), iface, method);
    }
    void call(const QString &method)
    {
        if (m_service.isEmpty()) {
            return;
        }
        QDBusConnection::sessionBus().asyncCall(mpris(m_service, QStringLiteral("org.mpris.MediaPlayer2.Player"), method));
        QTimer::singleShot(250, this, &MediaController::poll);
    }
    // mpris:trackid arrives either as a plain string or wrapped in an object path.
    static QString trackIdOf(const QVariant &v)
    {
        if (v.userType() == qMetaTypeId<QDBusArgument>()) {
            QDBusArgument a = v.value<QDBusArgument>();
            QDBusObjectPath p;
            a >> p;
            if (!p.path().isEmpty()) {
                return p.path();
            }
        }
        return v.toString();
    }
    // YouTube players do not always set mpris:artUrl, but the watch URL carries
    // the video id and i.ytimg.com serves its poster for it.
    static QString artFromUrl(const QString &url)
    {
        const QString id = url.contains(QLatin1String("youtu.be/"))
            ? url.section(QLatin1String("youtu.be/"), 1).section(u'&', 0, 0).section(u'?', 0, 0)
            : url.section(QLatin1String("v="), 1).section(u'&', 0, 0);
        if (id.length() < 8 || id.contains(u'/')) {
            return QString();
        }
        // mqdefault is 16:9 without the letterbox bars hqdefault carries
        return QStringLiteral("https://i.ytimg.com/vi/") + id + QStringLiteral("/mqdefault.jpg");
    }
    void poll()
    {
        if (!m_enabled || m_polling) {
            return;   // the previous round is still waiting on a slow player
        }
        const QStringList names = QDBusConnection::sessionBus().interface()->registeredServiceNames().value();
        QStringList candidates;
        for (const QString &n : names) {
            if (!n.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
                continue;
            }
            // The island's media ecosystem is YouTube Music only. Pear Desktop (Electron)
            // exposes MPRIS under Chromium's instance names, so those are accepted only
            // when the owning process is the ecosystem's own binary - a real Chrome
            // window playing media stays out.
            const bool ownName = n.contains(QLatin1String("youtube"), Qt::CaseInsensitive)
                || n.contains(QLatin1String("pear"), Qt::CaseInsensitive);
            if (!ownName) {
                if (!n.contains(QLatin1String("chromium"))) {
                    continue;
                }
                const uint pid = QDBusConnection::sessionBus().interface()->servicePid(n).value();
                const QString exe = QFileInfo(QStringLiteral("/proc/%1/exe").arg(pid)).symLinkTarget();
                if (!exe.contains(QLatin1String("pear-desktop"))
                    && !exe.endsWith(QLatin1String("/youtube-music"))) {
                    continue;
                }
            }
            candidates << n;
        }
        if (candidates.isEmpty()) {
            apply(QString(), QVariantMap());
            return;
        }
        // One GetAll per player, all in flight at once; the round is judged when the last
        // reply (or its 500 ms timeout) is in.
        m_polling = true;
        auto replies = std::make_shared<QHash<QString, QVariantMap>>();
        auto left = std::make_shared<int>(candidates.size());
        for (const QString &n : candidates) {
            auto msg = mpris(n, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
            msg << QStringLiteral("org.mpris.MediaPlayer2.Player");
            auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 500), this);
            connect(w, &QDBusPendingCallWatcher::finished, this, [this, n, candidates, replies, left](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                const QDBusPendingReply<QVariantMap> r = *w;
                if (r.isValid()) {
                    replies->insert(n, r.value());
                }
                if (--*left > 0) {
                    return;
                }
                m_polling = false;
                // The player that is Playing wins, otherwise the first one that answered.
                QString chosen;
                for (const QString &c : candidates) {
                    if (!replies->contains(c)) {
                        continue;
                    }
                    if (chosen.isEmpty()
                        || (replies->value(c).value(QStringLiteral("PlaybackStatus")).toString() == QLatin1String("Playing")
                            && replies->value(chosen).value(QStringLiteral("PlaybackStatus")).toString() != QLatin1String("Playing"))) {
                        chosen = c;
                    }
                }
                apply(chosen, replies->value(chosen));
            });
        }
    }
    // The player's display name, asked once per player (it never changes).
    void fetchIdentity(const QString &service)
    {
        auto msg = mpris(service, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        msg << QStringLiteral("org.mpris.MediaPlayer2") << QStringLiteral("Identity");
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 500), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, service](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            const QDBusPendingReply<QDBusVariant> r = *w;
            if (r.isValid() && service == m_service && r.value().variant().toString() != m_name) {
                m_name = r.value().variant().toString();
                Q_EMIT changed();
            }
        });
    }
    void apply(const QString &chosen, const QVariantMap &props)
    {
        const QString chosenStatus = props.value(QStringLiteral("PlaybackStatus")).toString();
        QString title, artist, art, name, trackId;
        bool playing = false;
        bool canSeek = true;
        qint64 lengthUs = 0;
        qint64 posUs = 0;
        qreal progress = 0;
        if (!chosen.isEmpty()) {
            playing = chosenStatus == QLatin1String("Playing");
            const QVariantMap meta = qdbus_cast<QVariantMap>(props.value(QStringLiteral("Metadata")));
            title = meta.value(QStringLiteral("xesam:title")).toString();
            artist = meta.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
            art = meta.value(QStringLiteral("mpris:artUrl")).toString();
            if (art.isEmpty()) {
                art = artFromUrl(meta.value(QStringLiteral("xesam:url")).toString());
            }
            trackId = trackIdOf(meta.value(QStringLiteral("mpris:trackid")));
            lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
            posUs = props.value(QStringLiteral("Position")).toLongLong();
            const QVariant seekable = props.value(QStringLiteral("CanSeek"));
            if (seekable.isValid()) {
                canSeek = seekable.toBool();
            }
            progress = lengthUs > 0 ? qBound<qreal>(0, qreal(posUs) / lengthUs, 1) : 0;
            name = chosen == m_service ? m_name : QString();
        }
        const bool same = chosen == m_service && playing == m_playing && title == m_title && artist == m_artist
            && art == m_artUrl && trackId == m_trackId && lengthUs == m_lengthUs && canSeek == m_canSeek;
        const bool justStarted = playing && !m_playing;
        m_service = chosen;
        m_playing = playing;
        m_title = title;
        m_artist = artist;
        m_artUrl = art;
        m_name = name;
        m_trackId = trackId;
        m_lengthUs = lengthUs;
        m_lengthSec = int((lengthUs + 500000) / 1000000);
        m_canSeek = canSeek;
        if (!same) {
            Q_EMIT changed();
        }
        if (!chosen.isEmpty() && m_name.isEmpty()) {
            fetchIdentity(chosen);
        }
        m_posUs = posUs;
        m_positionSec = int((posUs + 500000) / 1000000);
        if (!qFuzzyCompare(progress + 1, m_progress + 1)) {
            m_progress = progress;
            Q_EMIT progressChanged();
        }
        if (justStarted) {
            Q_EMIT playbackStarted();
        }
    }

    QString m_service, m_title, m_artist, m_artUrl, m_name, m_trackId;
    bool m_playing = false;
    bool m_canSeek = true;
    qint64 m_lengthUs = 0;
    int m_lengthSec = 0;
    qint64 m_posUs = 0;
    int m_positionSec = 0;
    qreal m_progress = 0;
    bool m_polling = false;
};
