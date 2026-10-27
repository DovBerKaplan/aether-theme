// Now-playing state and transport controls from whichever MPRIS player is active
// (Spotify, a browser, VLC...). Polls once a second; the player that is Playing wins,
// otherwise the first one that exists.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QFile>
#include <QFileInfo>
#include <QObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

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

public:
    explicit MediaController(QObject *parent = nullptr)
        : QObject(parent)
    {
        auto *t = new QTimer(this);
        t->setInterval(1000);
        connect(t, &QTimer::timeout, this, &MediaController::poll);
        t->start();
        QTimer::singleShot(200, this, &MediaController::poll);
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
        QDBusInterface i(m_service, QStringLiteral("/org/mpris/MediaPlayer2"), QStringLiteral("org.mpris.MediaPlayer2.Player"));
        i.asyncCallWithArgumentList(QStringLiteral("SetPosition"),
                                    { QVariant::fromValue(QDBusObjectPath(m_trackId)), QVariant(us) });
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
        QDBusInterface i(m_service, QStringLiteral("/org/mpris/MediaPlayer2"), QStringLiteral("org.mpris.MediaPlayer2"));
        i.asyncCall(QStringLiteral("Raise"));
    }

    // Start (or focus - it holds a single-instance lock) the preferred player.
    // Runs under XWayland: Chromium's native Wayland path (Vulkan + the color
    // manager protocol) is broken on this machine - blank white windows and
    // CHECK crashes (SIGILL). The log itself points to --ozone-platform=x11.
    Q_INVOKABLE void launch()
    {
        const QString bin = pearPath("opt/YouTube Music/youtube-music");
        if (QFile::exists(bin)) {
            QProcess::startDetached(bin, { QStringLiteral("--no-sandbox"), QStringLiteral("--ozone-platform=x11") });
        } else {
            QProcess::startDetached(QStringLiteral("pear-desktop"), { QStringLiteral("--no-sandbox"), QStringLiteral("--ozone-platform=x11") });
        }
    }

Q_SIGNALS:
    void changed();
    void progressChanged();
    void playbackStarted();   // rising edge: a track began playing

private:
    static QString pearPath(const char *rel)
    {
        return QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
               + QStringLiteral("/.local/opt/pear-desktop/") + QLatin1String(rel);
    }
    static QVariant prop(const QString &service, const QString &iface, const QString &name)
    {
        QDBusInterface p(service, QStringLiteral("/org/mpris/MediaPlayer2"), QStringLiteral("org.freedesktop.DBus.Properties"));
        const QDBusReply<QDBusVariant> r = p.call(QStringLiteral("Get"), iface, name);
        return r.isValid() ? r.value().variant() : QVariant();
    }
    void call(const QString &method)
    {
        if (m_service.isEmpty()) {
            return;
        }
        QDBusInterface i(m_service, QStringLiteral("/org/mpris/MediaPlayer2"), QStringLiteral("org.mpris.MediaPlayer2.Player"));
        i.asyncCall(method);
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
        const QStringList names = QDBusConnection::sessionBus().interface()->registeredServiceNames().value();
        QString chosen;
        QString chosenStatus;
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
            const QString status = prop(n, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("PlaybackStatus")).toString();
            if (chosen.isEmpty() || (status == QLatin1String("Playing") && chosenStatus != QLatin1String("Playing"))) {
                chosen = n;
                chosenStatus = status;
            }
        }
        QString title, artist, art, name, trackId;
        bool playing = false;
        bool canSeek = true;
        qint64 lengthUs = 0;
        qint64 posUs = 0;
        qreal progress = 0;
        if (!chosen.isEmpty()) {
            playing = chosenStatus == QLatin1String("Playing");
            const QVariantMap meta = qdbus_cast<QVariantMap>(prop(chosen, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("Metadata")));
            title = meta.value(QStringLiteral("xesam:title")).toString();
            artist = meta.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
            art = meta.value(QStringLiteral("mpris:artUrl")).toString();
            if (art.isEmpty()) {
                art = artFromUrl(meta.value(QStringLiteral("xesam:url")).toString());
            }
            trackId = trackIdOf(meta.value(QStringLiteral("mpris:trackid")));
            lengthUs = meta.value(QStringLiteral("mpris:length")).toLongLong();
            posUs = prop(chosen, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("Position")).toLongLong();
            const QVariant seekable = prop(chosen, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("CanSeek"));
            if (seekable.isValid()) {
                canSeek = seekable.toBool();
            }
            progress = lengthUs > 0 ? qBound<qreal>(0, qreal(posUs) / lengthUs, 1) : 0;
            name = prop(chosen, QStringLiteral("org.mpris.MediaPlayer2"), QStringLiteral("Identity")).toString();
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
};
