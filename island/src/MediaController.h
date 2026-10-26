// Now-playing state and transport controls from whichever MPRIS player is active
// (Spotify, a browser, VLC...). Polls once a second; the player that is Playing wins,
// otherwise the first one that exists.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QObject>
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
    Q_PROPERTY(QString playerName READ playerName NOTIFY changed)

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
    QString playerName() const { return m_name; }

    Q_INVOKABLE void playPause() { call(QStringLiteral("PlayPause")); }
    Q_INVOKABLE void next() { call(QStringLiteral("Next")); }
    Q_INVOKABLE void previous() { call(QStringLiteral("Previous")); }

Q_SIGNALS:
    void changed();
    void progressChanged();

private:
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
    void poll()
    {
        const QStringList names = QDBusConnection::sessionBus().interface()->registeredServiceNames().value();
        QString chosen;
        QString chosenStatus;
        for (const QString &n : names) {
            if (!n.startsWith(QLatin1String("org.mpris.MediaPlayer2."))) {
                continue;
            }
            const QString status = prop(n, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("PlaybackStatus")).toString();
            if (chosen.isEmpty() || (status == QLatin1String("Playing") && chosenStatus != QLatin1String("Playing"))) {
                chosen = n;
                chosenStatus = status;
            }
        }
        QString title, artist, art, name;
        bool playing = false;
        qreal progress = 0;
        if (!chosen.isEmpty()) {
            playing = chosenStatus == QLatin1String("Playing");
            const QVariantMap meta = qdbus_cast<QVariantMap>(prop(chosen, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("Metadata")));
            title = meta.value(QStringLiteral("xesam:title")).toString();
            artist = meta.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
            art = meta.value(QStringLiteral("mpris:artUrl")).toString();
            const qlonglong len = meta.value(QStringLiteral("mpris:length")).toLongLong();
            const qlonglong pos = prop(chosen, QStringLiteral("org.mpris.MediaPlayer2.Player"), QStringLiteral("Position")).toLongLong();
            progress = len > 0 ? qBound<qreal>(0, qreal(pos) / len, 1) : 0;
            name = prop(chosen, QStringLiteral("org.mpris.MediaPlayer2"), QStringLiteral("Identity")).toString();
        }
        const bool same = chosen == m_service && playing == m_playing && title == m_title && artist == m_artist && art == m_artUrl;
        m_service = chosen;
        m_playing = playing;
        m_title = title;
        m_artist = artist;
        m_artUrl = art;
        m_name = name;
        if (!same) {
            Q_EMIT changed();
        }
        if (!qFuzzyCompare(progress + 1, m_progress + 1)) {
            m_progress = progress;
            Q_EMIT progressChanged();
        }
    }

    QString m_service, m_title, m_artist, m_artUrl, m_name;
    bool m_playing = false;
    qreal m_progress = 0;
};
