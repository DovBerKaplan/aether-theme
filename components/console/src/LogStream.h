#pragma once

#include <QProcess>
#include <QTimer>
#include <QVariantMap>

#include "Launcher.h"

// A live log tail for the detail card: docker logs / kubectl logs / journalctl over ssh.
// The process streams while the logs view is open; lines are ring-buffered (the tail is what
// matters) and flushed to QML every 200 ms so a chatty stream cannot flood the scene graph.
class LogStream : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList lines READ lines NOTIFY linesChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString err READ err NOTIFY errChanged)

public:
    explicit LogStream(QObject *parent = nullptr) : QObject(parent)
    {
        m_flush.setSingleShot(true);
        m_flush.setInterval(200);
        connect(&m_flush, &QTimer::timeout, this, &LogStream::flush);
    }

    QStringList lines() const { return m_lines; }
    bool running() const { return m_proc != nullptr; }
    QString err() const { return m_err; }

    Q_INVOKABLE void startSession(const QVariantMap &s)
    {
        start(QStringLiteral("ssh"),
              Launcher::sshArgs(s, QStringLiteral("journalctl -n 300 -f -q --no-pager"), false, true));
    }
    Q_INVOKABLE void startContainer(const QString &name)
    {
        const QString docker = QStandardPaths::findExecutable(QStringLiteral("docker")).isEmpty()
            ? QStringLiteral("podman") : QStringLiteral("docker");
        start(docker, { QStringLiteral("logs"), QStringLiteral("--tail"), QStringLiteral("300"),
                        QStringLiteral("-f"), name });
    }
    Q_INVOKABLE void startPod(const QString &name, const QString &ns, const QString &context)
    {
        QStringList args{ QStringLiteral("logs"), QStringLiteral("--tail=300"), QStringLiteral("-f"),
                          name, QStringLiteral("-n"), ns };
        if (!context.isEmpty()) {
            args << QStringLiteral("--context") << context;
        }
        start(QStringLiteral("kubectl"), args);
    }
    Q_INVOKABLE void stop()
    {
        if (m_proc) {
            m_stopping = true;
            m_proc->kill();
        }
    }
    Q_INVOKABLE void clear()
    {
        m_lines.clear();
        m_pending.clear();
        m_buf.clear();
        Q_EMIT linesChanged();
    }

Q_SIGNALS:
    void linesChanged();
    void runningChanged();
    void errChanged();

private:
    void start(const QString &prog, const QStringList &args)
    {
        stop();
        m_err.clear();
        Q_EMIT errChanged();
        m_stopping = false;
        m_buf.clear();
        m_proc = new QProcess(this);
        connect(m_proc, &QProcess::readyReadStandardOutput, this, [this] {
            m_buf += QString::fromUtf8(m_proc->readAllStandardOutput());
            int nl;
            while ((nl = m_buf.indexOf(QLatin1Char('\n'))) >= 0) {
                m_pending << m_buf.left(nl);
                m_buf.remove(0, nl + 1);
            }
            if (!m_pending.isEmpty()) {
                m_flush.start();
            }
        });
        connect(m_proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                [this](int code, QProcess::ExitStatus st) {
                    // A short-lived stream (an exited container, a denied journalctl) may
                    // deliver everything before readyRead ever fires - drain stdout here too.
                    m_buf += QString::fromUtf8(m_proc->readAllStandardOutput());
                    if (!m_buf.isEmpty()) {
                        m_pending << m_buf;
                        m_buf.clear();
                    }
                    flush();
                    const bool failed = !m_stopping && st == QProcess::NormalExit && code != 0 && m_lines.isEmpty();
                    if (failed) {
                        const QString e = QString::fromUtf8(m_proc->readAllStandardError().trimmed());
                        m_err = e.isEmpty() ? QStringLiteral("stream failed") : e.left(300);
                        Q_EMIT errChanged();
                    }
                    m_proc->deleteLater();
                    m_proc = nullptr;
                    m_stopping = false;
                    Q_EMIT runningChanged();
                });
        connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
            if (m_proc && m_proc->state() == QProcess::NotRunning && !m_stopping && m_lines.isEmpty()) {
                m_err = QStringLiteral("command not found");
                Q_EMIT errChanged();
            }
        });
        m_proc->start(prog, args);
        Q_EMIT runningChanged();
    }
    void flush()
    {
        if (m_pending.isEmpty()) {
            return;
        }
        m_lines += m_pending;
        m_pending.clear();
        if (m_lines.size() > 1500) {
            m_lines.remove(0, m_lines.size() - 1200);   // drop in chunks, not per line
        }
        Q_EMIT linesChanged();
    }

    QTimer m_flush;
    QProcess *m_proc = nullptr;
    QStringList m_lines;
    QStringList m_pending;
    QString m_buf;
    QString m_err;
    bool m_stopping = false;
};
