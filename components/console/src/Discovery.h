#pragma once

#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

// Live discovery of what can be connected to right now: local containers (docker, falling back
// to podman) and Kubernetes pods. Runs only while the shelf is open - a refresh when it opens
// and a slow poll afterwards. Nothing is written to the user's kubeconfig: the chosen context
// travels as --context on our own commands and is stored in aetherconsolerc.
class Discovery : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList containers READ containers NOTIFY containersChanged)
    Q_PROPERTY(QVariantList pods READ pods NOTIFY podsChanged)
    Q_PROPERTY(QStringList contexts READ contexts NOTIFY contextsChanged)
    Q_PROPERTY(QString context READ context WRITE setContext NOTIFY contextChanged)
    Q_PROPERTY(bool hasContainers READ hasContainers NOTIFY containersChanged)
    Q_PROPERTY(bool hasKubectl READ hasKubectl CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit Discovery(QObject *parent = nullptr)
        : QObject(parent)
        , m_settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                     + QStringLiteral("/aetherconsolerc"), QSettings::IniFormat)
    {
        m_docker = QStandardPaths::findExecutable(QStringLiteral("docker"));
        if (m_docker.isEmpty()) {
            m_docker = QStandardPaths::findExecutable(QStringLiteral("podman"));
        }
        m_kubectl = QStandardPaths::findExecutable(QStringLiteral("kubectl"));
        m_context = m_settings.value(QStringLiteral("Discovery/context")).toString();
        m_poll.setInterval(20000);
        connect(&m_poll, &QTimer::timeout, this, &Discovery::refresh);
    }

    QVariantList containers() const { return m_containers; }
    QVariantList pods() const { return m_pods; }
    QStringList contexts() const { return m_contexts; }
    QString context() const { return m_context; }
    bool hasContainers() const { return !m_docker.isEmpty(); }
    bool hasKubectl() const { return !m_kubectl.isEmpty(); }
    bool busy() const { return m_busy > 0; }

    void setContext(const QString &c)
    {
        if (c == m_context) {
            return;
        }
        m_context = c;
        m_settings.setValue(QStringLiteral("Discovery/context"), c);
        Q_EMIT contextChanged();
        refreshPods();
    }

    Q_INVOKABLE void setPolling(bool on)
    {
        if (on) {
            refresh();
            m_poll.start();
        } else {
            m_poll.stop();
        }
    }

    Q_INVOKABLE void refresh()
    {
        refreshContainers();
        refreshContexts();
    }

Q_SIGNALS:
    void containersChanged();
    void podsChanged();
    void contextsChanged();
    void contextChanged();
    void busyChanged();

private:
    // One short-lived QProcess with a kill timer; the callback gets stdout (empty on failure).
    void run(const QString &prog, const QStringList &args, const std::function<void(const QString &)> &done)
    {
        auto *p = new QProcess(this);
        m_busy++;
        Q_EMIT busyChanged();
        auto finish = [this, p, done](const std::function<void(const QString &)> &cb) {
            cb(QString::fromUtf8(p->readAllStandardOutput()));
            m_busy--;
            Q_EMIT busyChanged();
            p->deleteLater();
        };
        connect(p, &QProcess::errorOccurred, p, [finish, done, p](QProcess::ProcessError) { finish(done); });
        connect(p, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), p,
                [finish, done, p](int, QProcess::ExitStatus st) {
                    if (st != QProcess::NormalExit) {
                        p->setReadChannel(QProcess::StandardOutput);   // kill path: read what arrived
                    }
                    finish(done);
                });
        auto *t = new QTimer(p);
        t->setSingleShot(true);
        connect(t, &QTimer::timeout, p, [p] { p->kill(); });
        t->start(8000);
        p->start(prog, args);
    }

    void refreshContainers()
    {
        if (m_docker.isEmpty()) {
            if (!m_containers.isEmpty()) {
                m_containers.clear();
                Q_EMIT containersChanged();
            }
            return;
        }
        run(m_docker, { QStringLiteral("ps"), QStringLiteral("-a"),
                        QStringLiteral("--format"), QStringLiteral("{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}") },
            [this](const QString &out) {
                QVariantList rows;
                const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                for (const QString &line : lines) {
                    const QStringList f = line.split(QLatin1Char('\t'));
                    if (f.isEmpty() || f[0].isEmpty()) {
                        continue;
                    }
                    rows << QVariantMap{
                        { QStringLiteral("name"), f[0] },
                        { QStringLiteral("image"), f.value(1) },
                        { QStringLiteral("running"), f.value(2).startsWith(QLatin1String("Up")) },
                        { QStringLiteral("ports"), f.value(3) },
                    };
                }
                if (rows != m_containers) {
                    m_containers = rows;
                    Q_EMIT containersChanged();
                }
            });
    }

    void refreshContexts()
    {
        if (m_kubectl.isEmpty()) {
            return;
        }
        run(m_kubectl, { QStringLiteral("config"), QStringLiteral("get-contexts"), QStringLiteral("-o"), QStringLiteral("name") },
            [this](const QString &out) {
                QStringList ctx;
                for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    ctx << line.trimmed();
                }
                if (ctx != m_contexts) {
                    m_contexts = ctx;
                    if (m_context.isEmpty() && !ctx.isEmpty()) {
                        m_context = ctx.first();
                    }
                    Q_EMIT contextsChanged();
                }
                refreshPods();
            });
    }

    void refreshPods()
    {
        if (m_kubectl.isEmpty() || m_context.isEmpty()) {
            if (!m_pods.isEmpty()) {
                m_pods.clear();
                Q_EMIT podsChanged();
            }
            return;
        }
        QStringList args{ QStringLiteral("get"), QStringLiteral("pods"), QStringLiteral("-A"),
                          QStringLiteral("--context"), m_context, QStringLiteral("--no-headers"),
                          QStringLiteral("-o"),
                          QStringLiteral("custom-columns=N:.metadata.name,S:.metadata.namespace,P:.status.phase,R:.status.containerStatuses[*].restartCount") };
        run(m_kubectl, args, [this](const QString &out) {
            QVariantList rows;
            const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                // custom-columns pads with spaces; names/namespaces have none of their own
                const QRegularExpression re(QStringLiteral("^(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(.*)$"));
                const auto m = re.match(line.trimmed());
                if (!m.hasMatch()) {
                    continue;
                }
                const QStringList rs = m.captured(4).split(QLatin1Char(','), Qt::SkipEmptyParts);
                int restarts = 0;
                for (const QString &r : rs) {
                    restarts += r.trimmed().toInt();
                }
                rows << QVariantMap{
                    { QStringLiteral("name"), m.captured(1) },
                    { QStringLiteral("ns"), m.captured(2) },
                    { QStringLiteral("phase"), m.captured(3) },
                    { QStringLiteral("restarts"), restarts },
                };
            }
            if (rows != m_pods) {
                m_pods = rows;
                Q_EMIT podsChanged();
            }
        });
    }

    QSettings m_settings;
    QTimer m_poll;
    QString m_docker;
    QString m_kubectl;
    QString m_context;
    QStringList m_contexts;
    QVariantList m_containers;
    QVariantList m_pods;
    int m_busy = 0;
};
