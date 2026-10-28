#pragma once

#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// A minimal reader for ~/.ssh/config: concrete Host entries with their HostName/User/Port and
// the first IdentityFile. Patterns (*, ?), Match blocks and Include are skipped - the import
// offers only hosts that can be connected to as they are. Saved sessions win: a host that is
// already in the store is not offered again.
namespace SshConfig {

inline QString configPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + QStringLiteral("/.ssh/config");
}

inline QVariantList candidates(const QVariantList &alreadySaved = QVariantList())
{
    QVariantList out;
    QFile f(configPath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return out;
    }
    auto hasHost = [&alreadySaved](const QString &name, const QString &host, const QString &user) {
        for (const QVariant &v : alreadySaved) {
            const QVariantMap s = v.toMap();
            if (s.value(QStringLiteral("name")).toString().compare(name, Qt::CaseInsensitive) == 0) {
                return true;
            }
            if (s.value(QStringLiteral("host")).toString().compare(host, Qt::CaseInsensitive) == 0
                && s.value(QStringLiteral("user")).toString() == user) {
                return true;
            }
        }
        return false;
    };

    QString name, host, user, port, identity;
    bool inMatch = false;
    auto flush = [&]() {
        if (name.isEmpty() || inMatch || name.contains(QLatin1Char('*')) || name.contains(QLatin1Char('?'))) {
            return;
        }
        if (hasHost(name, host.isEmpty() ? name : host, user)) {
            return;
        }
        out << QVariantMap{
            { QStringLiteral("name"), name },
            { QStringLiteral("host"), host.isEmpty() ? name : host },
            { QStringLiteral("user"), user },
            { QStringLiteral("port"), port },
            { QStringLiteral("identity"), identity },
        };
    };
    while (!f.atEnd()) {
        QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        line = line.replace(QLatin1Char('='), QLatin1Char(' '));   // "Key=Value" is legal ssh_config
        const int sp = line.indexOf(QLatin1Char(' '));
        if (sp <= 0) {
            continue;
        }
        const QString key = line.left(sp).toLower();
        const QString val = line.mid(sp + 1).trimmed();
        if (key == QLatin1String("host")) {
            flush();
            inMatch = false;
            // multi-pattern lines ("Host a b") import the first concrete name only
            const QStringList patterns = val.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
            name = patterns.value(0);
            host.clear(); user.clear(); port.clear(); identity.clear();
        } else if (key == QLatin1String("match")) {
            flush();
            inMatch = true;
            name.clear();
        } else if (!name.isEmpty() && !inMatch) {
            if (key == QLatin1String("hostname")) host = val;
            else if (key == QLatin1String("user")) user = val;
            else if (key == QLatin1String("port")) port = val;
            else if (key == QLatin1String("identityfile") && identity.isEmpty()) identity = val;
        }
    }
    flush();
    return out;
}

} // namespace SshConfig
