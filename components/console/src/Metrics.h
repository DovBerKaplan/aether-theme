#pragma once

#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "Launcher.h"

// Live numbers for the detail card: over ssh (loadavg/free/df/ps) for servers, docker stats for
// containers. BatchMode everywhere, so a background poller can never sit waiting for a password -
// it fails visibly instead and the card offers the interactive connect. Polls only while a card
// with a metrics view is open.
class Metrics : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap data READ data NOTIFY dataChanged)
    Q_PROPERTY(QVariantList processes READ processes NOTIFY dataChanged)

public:
    explicit Metrics(QObject *parent = nullptr) : QObject(parent)
    {
        m_timer.setInterval(4000);
        connect(&m_timer, &QTimer::timeout, this, &Metrics::poll);
    }

    QVariantMap data() const { return m_data; }
    QVariantList processes() const { return m_processes; }

    Q_INVOKABLE void watchSession(const QVariantMap &s)
    {
        m_session = s;
        m_container.clear();
        m_data.clear();
        m_processes.clear();
        restart();
    }
    Q_INVOKABLE void watchContainer(const QString &name)
    {
        m_container = name;
        m_session.clear();
        m_data.clear();
        m_processes.clear();
        restart();
    }
    Q_INVOKABLE void stop()
    {
        m_timer.stop();
        m_session.clear();
        m_container.clear();
    }

Q_SIGNALS:
    void dataChanged();

private:
    void restart()
    {
        m_timer.start();
        poll();
    }
    void poll()
    {
        if (!m_session.isEmpty()) {
            // one round trip; ssh joins the words on the far side
            const QString remote = QStringLiteral(
                "nproc; cat /proc/loadavg; free -b | sed -n 2p; df -P / | tail -1; "
                "ps -eo pcpu,comm --sort=-pcpu --no-headers | head -7");
            run(QStringLiteral("ssh"), Launcher::sshArgs(m_session, remote, false, true), true);
        } else if (!m_container.isEmpty()) {
            const QString docker = QStandardPaths::findExecutable(QStringLiteral("docker")).isEmpty()
                ? QStringLiteral("podman") : QStringLiteral("docker");
            run(docker, { QStringLiteral("stats"), QStringLiteral("--no-stream"),
                          QStringLiteral("--format"), QStringLiteral("{{.CPUPerc}}\t{{.MemUsage}}"),
                          m_container }, false);
        }
    }
    void run(const QString &prog, const QStringList &args, bool ssh)
    {
        auto *p = new QProcess(this);
        connect(p, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), p,
                [this, p, ssh](int code, QProcess::ExitStatus st) {
                    const QString out = st == QProcess::NormalExit && code == 0
                        ? QString::fromUtf8(p->readAllStandardOutput()) : QString();
                    if (ssh) {
                        parseSession(out);
                    } else {
                        parseContainer(out);
                    }
                    p->deleteLater();
                });
        auto *t = new QTimer(p);
        t->setSingleShot(true);
        connect(t, &QTimer::timeout, p, [p] { p->kill(); });
        t->start(9000);
        p->start(prog, args);
    }
    void parseSession(const QString &out)
    {
        const QStringList lines = out.split(QLatin1Char('\n'));
        if (lines.size() < 4) {
            m_data = QVariantMap{ { QStringLiteral("err"), QStringLiteral("ssh") } };
            Q_EMIT dataChanged();
            return;
        }
        bool okCores = false;
        const int cores = lines[0].trimmed().toInt(&okCores);
        if (!okCores || cores <= 0) {
            m_data = QVariantMap{ { QStringLiteral("err"), QStringLiteral("ssh") } };
            Q_EMIT dataChanged();
            return;
        }
        const double load = lines[1].section(QLatin1Char(' '), 0, 0).toDouble();
        const QStringList mem = lines[2].split(QLatin1Char(' '), Qt::SkipEmptyParts);   // Mem: total used ...
        const QStringList disk = lines[3].split(QLatin1Char(' '), Qt::SkipEmptyParts);  // dev total used free % mount
        QVariantList procs;
        for (int i = 4; i < lines.size(); ++i) {
            const QString line = lines[i].trimmed();
            if (line.isEmpty()) {
                continue;
            }
            const int sp = line.indexOf(QLatin1Char(' '));
            if (sp <= 0) {
                continue;
            }
            procs << QVariantMap{
                { QStringLiteral("cpu"), line.left(sp).toDouble() },
                { QStringLiteral("cmd"), line.mid(sp + 1).trimmed() },
            };
        }
        m_data = QVariantMap{
            { QStringLiteral("err"), QString() },
            { QStringLiteral("cpu"), qBound(0.0, load / cores, 1.0) },
            { QStringLiteral("load"), load },
            { QStringLiteral("cores"), cores },
            { QStringLiteral("memUsed"), mem.value(2).toLongLong() },
            { QStringLiteral("memTotal"), mem.value(1).toLongLong() },
            { QStringLiteral("diskUsed"), disk.value(2).toLongLong() },
            { QStringLiteral("diskTotal"), disk.value(1).toLongLong() },
        };
        m_processes = procs;
        Q_EMIT dataChanged();
    }
    void parseContainer(const QString &out)
    {
        // "12.34%\t456MiB / 1.944GiB"
        const QStringList f = out.trimmed().split(QLatin1Char('\t'));
        if (f.size() < 2 || !f[0].endsWith(QLatin1Char('%'))) {
            m_data = QVariantMap{ { QStringLiteral("err"), QStringLiteral("docker") } };
            Q_EMIT dataChanged();
            return;
        }
        m_data = QVariantMap{
            { QStringLiteral("err"), QString() },
            { QStringLiteral("cpu"), f[0].chopped(1).toDouble() / 100.0 },
            { QStringLiteral("memText"), f[1].trimmed() },
        };
        Q_EMIT dataChanged();
    }

    QTimer m_timer;
    QVariantMap m_session;
    QString m_container;
    QVariantMap m_data;
    QVariantList m_processes;
};
