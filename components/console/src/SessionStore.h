#pragma once

#include <QDateTime>
#include <QDir>
#include <QObject>
#include <QSettings>
#include <QStandardPaths>
#include <QVariantList>
#include <QVariantMap>

#include "SshConfig.h"

// Saved connections, in ~/.config/aetherconsolerc. A session is a flat map:
//   id, name, group, host, port, user, identity, keyDeployed, open (listed under "active"),
//   lastUsed (ms epoch). `open` survives restarts on purpose: after a reboot the shelf offers
//   the same sessions again and connecting is a tmux re-attach - the server kept everything.
class SessionStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sessions READ sessions NOTIFY sessionsChanged)

public:
    explicit SessionStore(QObject *parent = nullptr)
        : QObject(parent)
        , m_settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                     + QStringLiteral("/aetherconsolerc"), QSettings::IniFormat)
    {
        load();
    }

    QVariantList sessions() const { return m_rows; }

    Q_INVOKABLE QVariantMap get(const QString &id) const
    {
        for (const QVariant &v : m_rows) {
            if (v.toMap().value(QStringLiteral("id")).toString() == id) {
                return v.toMap();
            }
        }
        return {};
    }

    // Insert or update; returns the id. An empty id inserts.
    Q_INVOKABLE QString save(QVariantMap s)
    {
        const QString id = s.value(QStringLiteral("id")).toString().isEmpty()
            ? QStringLiteral("s%1").arg(QDateTime::currentMSecsSinceEpoch())
            : s.value(QStringLiteral("id")).toString();
        s.insert(QStringLiteral("id"), id);
        if (!s.contains(QStringLiteral("open"))) {
            s.insert(QStringLiteral("open"), false);
        }
        bool replaced = false;
        for (int i = 0; i < m_rows.size(); ++i) {
            if (m_rows[i].toMap().value(QStringLiteral("id")).toString() == id) {
                QVariantMap old = m_rows[i].toMap();
                // fields the editor does not touch must survive
                for (const QString &k : { QStringLiteral("open"), QStringLiteral("lastUsed"), QStringLiteral("keyDeployed") }) {
                    if (!s.contains(k)) {
                        s.insert(k, old.value(k, false));
                    }
                }
                m_rows[i] = s;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            m_rows << s;
        }
        persist();
        return id;
    }

    Q_INVOKABLE void remove(const QString &id)
    {
        for (int i = 0; i < m_rows.size(); ++i) {
            if (m_rows[i].toMap().value(QStringLiteral("id")).toString() == id) {
                m_rows.removeAt(i);
                persist();
                return;
            }
        }
    }

    Q_INVOKABLE void markLaunched(const QString &id)
    {
        for (int i = 0; i < m_rows.size(); ++i) {
            QVariantMap s = m_rows[i].toMap();
            if (s.value(QStringLiteral("id")).toString() == id) {
                s.insert(QStringLiteral("open"), true);
                s.insert(QStringLiteral("lastUsed"), QDateTime::currentMSecsSinceEpoch());
                m_rows[i] = s;
                persist();
                return;
            }
        }
    }

    Q_INVOKABLE void clearActive()
    {
        bool changed = false;
        for (int i = 0; i < m_rows.size(); ++i) {
            QVariantMap s = m_rows[i].toMap();
            if (s.value(QStringLiteral("open")).toBool()) {
                s.insert(QStringLiteral("open"), false);
                m_rows[i] = s;
                changed = true;
            }
        }
        if (changed) {
            persist();
        }
    }

    // Hosts from ~/.ssh/config that are not saved yet (the import page).
    Q_INVOKABLE QVariantList importCandidates() const { return SshConfig::candidates(m_rows); }

    Q_INVOKABLE int importSessions(const QVariantList &rows)
    {
        int n = 0;
        for (const QVariant &v : rows) {
            QVariantMap s = v.toMap();
            s[QStringLiteral("group")] = s.value(QStringLiteral("group"), QStringLiteral("ssh")).toString();
            save(s);
            ++n;
        }
        return n;
    }

    // Private key candidates in ~/.ssh (files that look like keys, with their .pub twin).
    Q_INVOKABLE QStringList sshKeys() const
    {
        QStringList out;
        QDir dir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + QStringLiteral("/.ssh"));
        const QRegularExpression bad(QStringLiteral("^(known_hosts|authorized_keys|config|environment|cm-|prv-)"));
        const QStringList files = dir.entryList(QDir::Files);
        for (const QString &f : files) {
            if (f.endsWith(QLatin1String(".pub")) || bad.match(f).hasMatch()) {
                continue;
            }
            out << dir.absoluteFilePath(f);
        }
        return out;
    }

Q_SIGNALS:
    void sessionsChanged();

private:
    void load()
    {
        m_rows.clear();
        const int n = m_settings.beginReadArray(QStringLiteral("Sessions"));
        for (int i = 0; i < n; ++i) {
            m_settings.setArrayIndex(i);
            QVariantMap s;
            for (const QString &k : m_settings.childKeys()) {
                s.insert(k, m_settings.value(k));
            }
            if (!s.value(QStringLiteral("id")).toString().isEmpty()) {
                m_rows << s;
            }
        }
        m_settings.endArray();
    }
    void persist()
    {
        m_settings.beginWriteArray(QStringLiteral("Sessions"), m_rows.size());
        for (int i = 0; i < m_rows.size(); ++i) {
            m_settings.setArrayIndex(i);
            const QVariantMap s = m_rows[i].toMap();
            for (auto it = s.constBegin(); it != s.constEnd(); ++it) {
                m_settings.setValue(it.key(), it.value());
            }
        }
        m_settings.endArray();
        m_settings.sync();
        Q_EMIT sessionsChanged();
    }

    QSettings m_settings;
    QVariantList m_rows;
};
