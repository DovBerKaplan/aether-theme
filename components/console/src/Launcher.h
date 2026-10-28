#pragma once

#include <QFile>
#include <QObject>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QVariantMap>

// Builds and starts the session commands. Every SSH session is wrapped in a tmux session on
// the server (created or re-attached with `tmux new -A`), so a dead network, a crashed Konsole
// or a reboot of this machine never loses work: connecting again is attaching again. SSH options
// keep the pipe healthy (keepalives) and share one authenticated socket per host (ControlMaster),
// so every further connection to the same server opens instantly without re-authenticating.
class Launcher : public QObject
{
    Q_OBJECT

public:
    explicit Launcher(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE bool sshSession(const QVariantMap &s)
    {
        const QString host = s.value(QStringLiteral("host")).toString().trimmed();
        if (host.isEmpty() || konsole().isEmpty()) {
            return false;
        }
        QStringList opts{
            QStringLiteral("-o"), QStringLiteral("ControlMaster=auto"),
            QStringLiteral("-o"), QStringLiteral("ControlPath=%1/.ssh/cm-%r@%h-%p")
                                      .arg(QStandardPaths::writableLocation(QStandardPaths::HomeLocation)),
            QStringLiteral("-o"), QStringLiteral("ControlPersist=10m"),
            QStringLiteral("-o"), QStringLiteral("ServerAliveInterval=15"),
            QStringLiteral("-o"), QStringLiteral("ServerAliveCountMax=3"),
        };
        const QString identity = expanded(s.value(QStringLiteral("identity")).toString());
        if (!identity.isEmpty()) {
            opts << QStringLiteral("-i") << identity;
        }
        const QString port = s.value(QStringLiteral("port")).toString().trimmed();
        if (!port.isEmpty() && port != QLatin1String("22")) {
            opts << QStringLiteral("-p") << port;
        }
        const QString user = s.value(QStringLiteral("user")).toString().trimmed();
        const QString target = user.isEmpty() ? host : user + QLatin1Char('@') + host;
        const QString sess = QStringLiteral("aether_") + sanitize(host);

        // Self-healing: without tmux the server still gives a login shell (and the row keeps a
        // ready-made install command). The string travels as one argv element, so $SHELL stays
        // untouched until the remote shell reads it.
        const QString remote = QStringLiteral(
            "if command -v tmux >/dev/null 2>&1; then exec tmux new -A -s %1; "
            "else echo \"tmux not found - plain shell (sessions will not survive disconnects)\"; exec $SHELL; fi").arg(sess);

        QStringList args{ QStringLiteral("-e"), QStringLiteral("ssh"), QStringLiteral("-t") };
        for (const QString &o : opts) {
            args << o;
        }
        args << target << remote;
        return launch(args);
    }

    // The row's fallback when a server turns out to have no tmux: copy, ssh, paste, done.
    Q_INVOKABLE QString tmuxInstallCommand(const QVariantMap &s) const
    {
        const QString user = s.value(QStringLiteral("user")).toString().trimmed();
        const QString host = s.value(QStringLiteral("host")).toString().trimmed();
        const QString target = user.isEmpty() ? host : user + QLatin1Char('@') + host;
        return QStringLiteral("ssh %1 \"command -v tmux >/dev/null || sudo apt install -y tmux\"").arg(target);
    }

    Q_INVOKABLE bool container(const QString &name)
    {
        const QString docker = QStandardPaths::findExecutable(QStringLiteral("docker")).isEmpty()
            ? QStringLiteral("podman") : QStringLiteral("docker");
        if (konsole().isEmpty() || name.isEmpty()) {
            return false;
        }
        return launch({ QStringLiteral("-e"), QStringLiteral("sh"), QStringLiteral("-c"),
                        QStringLiteral("%1 exec -it %2 bash || %1 exec -it %2 sh").arg(docker, name) });
    }

    Q_INVOKABLE bool pod(const QString &name, const QString &ns, const QString &context)
    {
        if (konsole().isEmpty() || name.isEmpty()) {
            return false;
        }
        const QString ctx = context.isEmpty() ? QString() : QStringLiteral("--context ") + context + QLatin1Char(' ');
        const QString base = QStringLiteral("kubectl %1exec -it %2 -n %3").arg(ctx, name, ns);
        return launch({ QStringLiteral("-e"), QStringLiteral("sh"), QStringLiteral("-c"),
                        base + QStringLiteral(" -- bash -l || ") + base + QStringLiteral(" -- sh") });
    }

    // One-time key deployment. The password (if one is needed) is typed once, inside the visible
    // Konsole window - nothing is captured, nothing is stored. Afterwards agent + ControlMaster
    // make every further connection silent.
    Q_INVOKABLE bool deployKey(const QVariantMap &s)
    {
        const QString host = s.value(QStringLiteral("host")).toString().trimmed();
        if (host.isEmpty() || konsole().isEmpty()) {
            return false;
        }
        const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        const QString key = expanded(s.value(QStringLiteral("identity")).toString().isEmpty()
            ? home + QStringLiteral("/.ssh/id_ed25519")
            : s.value(QStringLiteral("identity")).toString());
        const QString port = s.value(QStringLiteral("port")).toString().trimmed();
        const QString user = s.value(QStringLiteral("user")).toString().trimmed();
        const QString target = user.isEmpty() ? host : user + QLatin1Char('@') + host;
        const QString portArg = port.isEmpty() || port == QLatin1String("22")
            ? QString() : QStringLiteral("-p %1 ").arg(port);
        const QString inner = QStringLiteral(
            "test -f %1 || ssh-keygen -t ed25519 -f %1; "
            "ssh-copy-id %2-i %3 %4; echo; echo \"key deployed - safe to close\"; read x")
            .arg(key, portArg, key, target);
        return launch({ QStringLiteral("-e"), QStringLiteral("sh"), QStringLiteral("-c"), inner });
    }

Q_SIGNALS:
    void launched(const QString &kind, const QString &id);

private:
    QString konsole() const
    {
        static QString k = QStandardPaths::findExecutable(QStringLiteral("konsole"));
        return k;
    }
    static QString expanded(QString path)
    {
        if (path.startsWith(QLatin1Char('~'))) {
            path.replace(0, 1, QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
        }
        return path.trimmed();
    }
    static QString sanitize(QString host)
    {
        host.replace(QRegularExpression(QStringLiteral("[^a-zA-Z0-9._-]")), QStringLiteral("_"));
        return host;
    }
    bool launch(const QStringList &konsoleArgs)
    {
        QStringList args;
        const QString profile = QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
            + QStringLiteral("/.local/share/konsole/Aether.profile");
        if (QFile::exists(profile)) {
            args << QStringLiteral("--profile") << QStringLiteral("Aether");
        }
        args << konsoleArgs;
        const bool ok = QProcess::startDetached(konsole(), args);
        if (ok) {
            Q_EMIT launched(QStringLiteral("session"), QString());
        }
        return ok;
    }
};
