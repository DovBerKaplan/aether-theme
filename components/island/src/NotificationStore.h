// Recent notifications for the island's expanded ("double bar") view.
//
// The island only *watches* org.freedesktop.Notifications.Notify as a bus monitor (same trick
// as aether-toasts, but without the do-not-disturb inhibition - the toasts service owns that),
// keeps the last 30 in memory and mirrors them to a small JSON file so the history survives
// restarts. Plasma remains the notification server, so its own history is untouched.
#pragma once

#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>

#include <NotificationIcon.h>

class NotificationStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList list READ list NOTIFY listChanged)
    // Apps whose notifications are shown somewhere better (the KDE Connect widget shows the phone's, with
    // reply and actions): they are not added to the history, and what is already there is dropped - so their
    // text is never written to disk either.
    Q_PROPERTY(QStringList ignoredApps READ ignoredApps WRITE setIgnoredApps NOTIFY ignoredAppsChanged)

public:
    explicit NotificationStore(QObject *parent = nullptr)
        : QObject(parent)
    {
        load();
        m_save.setSingleShot(true);
        connect(&m_save, &QTimer::timeout, this, [this] { save(); });
        m_proc.setProgram(QStringLiteral("busctl"));
        m_proc.setArguments({QStringLiteral("--user"), QStringLiteral("monitor"), QStringLiteral("--json=short"),
                             QStringLiteral("--match"),
                             QStringLiteral("type='method_call',interface='org.freedesktop.Notifications',member='Notify'")});
        connect(&m_proc, &QProcess::readyReadStandardOutput, this, &NotificationStore::readLines);
        connect(&m_proc, &QProcess::finished, this, [this] { QTimer::singleShot(2000, this, [this] { m_proc.start(); }); });
        m_proc.start();
    }
    ~NotificationStore() override
    {
        m_proc.kill();
        m_proc.waitForFinished(500);
    }

    QStringList ignoredApps() const { return m_ignored; }
    void setIgnoredApps(const QStringList &apps)
    {
        if (apps == m_ignored) {
            return;
        }
        m_ignored = apps;
        bool removed = false;
        for (int i = m_items.size() - 1; i >= 0; --i) {
            if (isIgnored(m_items.at(i).toObject().value(QStringLiteral("app")).toString())) {
                m_items.removeAt(i);
                removed = true;
            }
        }
        if (removed) {
            changed();
        }
        Q_EMIT ignoredAppsChanged();
    }

    QVariantList list() const
    {
        QVariantList out;
        out.reserve(m_items.size());
        for (const auto &v : m_items) {
            out.append(v.toObject().toVariantMap());
        }
        return out;
    }

    Q_INVOKABLE void dismiss(qint64 key)
    {
        for (int i = 0; i < m_items.size(); ++i) {
            if (m_items.at(i).toObject().value(QStringLiteral("key")).toInteger() == key) {
                m_items.removeAt(i);
                changed();
                return;
            }
        }
    }
    Q_INVOKABLE void clearAll()
    {
        if (!m_items.isEmpty()) {
            m_items = QJsonArray();
            changed();
        }
    }

Q_SIGNALS:
    void listChanged();
    void ignoredAppsChanged();

private:
    void changed()
    {
        Q_EMIT listChanged();
        m_save.stop();
        m_save.start(500);
    }
    void readLines()
    {
        m_buffer += m_proc.readAllStandardOutput();
        int nl;
        while ((nl = m_buffer.indexOf('\n')) >= 0) {
            const QByteArray line = m_buffer.left(nl).trimmed();
            m_buffer.remove(0, nl + 1);
            if (!line.isEmpty()) {
                handle(QJsonDocument::fromJson(line).object());
            }
        }
    }
    void handle(const QJsonObject &msg)
    {
        if (msg.value(QStringLiteral("member")).toString() != QLatin1String("Notify")) {
            return;
        }
        const QJsonArray d = msg.value(QStringLiteral("payload")).toObject().value(QStringLiteral("data")).toArray();
        if (d.size() < 8) {
            return;
        }
        const QJsonObject hints = d.at(6).toObject();
        if (hints.value(QStringLiteral("transient")).toObject().value(QStringLiteral("data")).toBool()
            && d.at(1).toInt() != 0) {
            return;   // progress-style updates (replaces_id set) would spam the list
        }
        const QString app = d.at(0).toString();
        if (isIgnored(app)) {
            return;
        }
        const QString icon = NotificationIcon::resolve(app, d.at(2).toString(), hints);
        const QString summary = d.at(3).toString();
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        // replaces_id refers to ids Plasma handed out, which we never see; update the most
        // recent entry from the same app with the same title as a best-effort match.
        if (d.at(1).toInt() != 0) {
            for (int i = 0; i < m_items.size(); ++i) {
                const QJsonObject o = m_items.at(i).toObject();
                if (o.value(QStringLiteral("app")).toString() == app
                    && o.value(QStringLiteral("summary")).toString() == summary) {
                    QJsonObject updated = o;
                    updated.insert(QStringLiteral("body"), d.at(4).toString());
                    updated.insert(QStringLiteral("ts"), double(now));
                    m_items.replace(i, updated);
                    changed();
                    return;
                }
            }
        }
        QJsonObject o;
        o.insert(QStringLiteral("key"), double(++m_topKey));
        o.insert(QStringLiteral("app"), app.isEmpty() ? QStringLiteral("System") : app);
        o.insert(QStringLiteral("icon"), icon);
        o.insert(QStringLiteral("summary"), summary);
        o.insert(QStringLiteral("body"), d.at(4).toString());
        o.insert(QStringLiteral("urgency"), hints.value(QStringLiteral("urgency")).toObject().value(QStringLiteral("data")).toInt(1));
        o.insert(QStringLiteral("ts"), double(now));
        m_items.prepend(o);
        while (m_items.size() > 30) {
            m_items.removeLast();
        }
        changed();
    }
    QString path() const
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)
               + QStringLiteral("/notifications.json");
    }
    void load()
    {
        QFile f(path());
        if (!f.open(QIODevice::ReadOnly)) {
            return;
        }
        const QJsonArray a = QJsonDocument::fromJson(f.readAll()).array();
        for (const auto &v : a) {
            const QJsonObject o = v.toObject();
            m_topKey = qMax(m_topKey, o.value(QStringLiteral("key")).toInteger());
            m_items.append(o);
        }
    }
    void save() const
    {
        QFile f(path());
        if (!f.open(QIODevice::WriteOnly)) {
            return;
        }
        f.write(QJsonDocument(m_items).toJson(QJsonDocument::Compact));
    }

    QProcess m_proc;
    QByteArray m_buffer;
    QTimer m_save{this};
    bool isIgnored(const QString &app) const
    {
        // forwarded phone notifications come from "KDE Connect" (matched loosely: case and spacing)
        const QString a = app.simplified().remove(QLatin1Char(' ')).toLower();
        for (const QString &x : m_ignored) {
            if (a == x.simplified().remove(QLatin1Char(' ')).toLower()) {
                return true;
            }
        }
        return false;
    }
    QStringList m_ignored;
    QJsonArray m_items;          // newest first
    qint64 m_topKey = 0;
};
