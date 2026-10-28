#pragma once

#include <algorithm>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include "Launcher.h"

// The files view: the stock sftp client driven by batch files, multiplexed over the session's
// own ControlMaster - instant and silent once a connection exists. v1 is deliberately safe:
// browse, download to ~/Downloads, upload; no remote delete or rename (VS Code's remote-delete
// gotcha is not ours to repeat).
class Sftp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QString err READ err NOTIFY errChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit Sftp(QObject *parent = nullptr) : QObject(parent) {}

    QVariantList entries() const { return m_entries; }
    QString path() const { return m_path; }
    QString err() const { return m_err; }
    bool busy() const { return m_busy > 0; }

    Q_INVOKABLE void open(const QVariantMap &s)
    {
        m_session = s;
        m_path.clear();
        m_entries.clear();
        m_err.clear();
        Q_EMIT entriesChanged();
        Q_EMIT pathChanged();
        Q_EMIT errChanged();
        run({ QStringLiteral("pwd"), QStringLiteral("ls -la") });
    }
    Q_INVOKABLE void list(const QString &path)
    {
        if (path.isEmpty()) {
            return;
        }
        run({ QStringLiteral("cd ") + quotePath(path), QStringLiteral("pwd"), QStringLiteral("ls -la") });
    }
    Q_INVOKABLE void up() { list(m_path + QStringLiteral("/..")); }

    // A file of the current folder into ~/Downloads.
    Q_INVOKABLE void download(const QString &name)
    {
        if (m_path.isEmpty() || name.isEmpty()) {
            return;
        }
        const QString downloads = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        QDir().mkpath(downloads);
        run({ QStringLiteral("get %1 %2").arg(quotePath(m_path + QLatin1Char('/') + name),
                                              quotePath(downloads + QLatin1Char('/') + name)) },
            true);
    }
    // kdialog's picked files, one local path per line (the island's proven chooser).
    Q_INVOKABLE void chooseUpload()
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            const QStringList paths = QString::fromUtf8(p->readAllStandardOutput())
                                          .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            p->deleteLater();
            for (const QString &f : paths) {
                upload(QUrl::fromLocalFile(f.trimmed()));
            }
        });
        p->start(QStringLiteral("kdialog"), { QStringLiteral("--multiple"), QStringLiteral("--separate-output"),
                                              QStringLiteral("--getopenfilename"), QDir::homePath(),
                                              QStringLiteral("*|All files") });
    }
    Q_INVOKABLE void upload(const QUrl &url)
    {
        const QString local = url.isLocalFile() ? url.toLocalFile() : url.toString();
        if (local.isEmpty() || !QFileInfo::exists(local) || m_path.isEmpty()) {
            return;
        }
        run({ QStringLiteral("put %1 %2").arg(quotePath(local),
                                              quotePath(m_path + QLatin1Char('/') + QFileInfo(local).fileName())) },
            true);
    }

Q_SIGNALS:
    void entriesChanged();
    void pathChanged();
    void errChanged();
    void busyChanged();

private:
    static QString quotePath(QString p)
    {
        p.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('"'), QStringLiteral("\\\""));
        return QStringLiteral("\"") + p + QStringLiteral("\"");
    }
    // One sftp run over one batch file. transfers only notify; listings repaint the view.
    void run(const QStringList &commands, bool transfer = false)
    {
        const QString sftp = QStandardPaths::findExecutable(QStringLiteral("sftp"));
        if (sftp.isEmpty() || m_session.value(QStringLiteral("host")).toString().trimmed().isEmpty()) {
            return;
        }
        auto *batch = new QTemporaryFile(this);
        if (!batch->open()) {
            delete batch;
            return;
        }
        batch->write(commands.join(QLatin1Char('\n')).toUtf8());
        batch->close();

        m_busy++;
        Q_EMIT busyChanged();
        if (!transfer) {
            if (m_ls) {
                m_ls->kill();   // a newer navigation wins
            }
            m_err.clear();
            Q_EMIT errChanged();
        }
        auto *p = new QProcess(this);
        if (!transfer) {
            m_ls = p;
        }
        connect(p, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                [this, p, batch, transfer](int code, QProcess::ExitStatus st) {
                    const QString out = st == QProcess::NormalExit ? QString::fromUtf8(p->readAllStandardOutput()) : QString();
                    const QString errOut = QString::fromUtf8(p->readAllStandardError());
                    if (transfer) {
                        sendNotify(code == 0, errOut);
                    } else {
                        parse(out, errOut, code);
                    }
                    batch->deleteLater();
                    m_busy--;
                    Q_EMIT busyChanged();
                    p->deleteLater();
                    if (p == m_ls) {
                        m_ls = nullptr;
                    }
                });
        auto *t = new QTimer(p);
        t->setSingleShot(true);
        connect(t, &QTimer::timeout, p, [p] { p->kill(); });
        t->start(transfer ? 300000 : 20000);
        const QString host = m_session.value(QStringLiteral("host")).toString().trimmed();
        p->start(sftp, Launcher::sftpOpts() << QStringLiteral("-b") << batch->fileName() << host);
    }
    void parse(const QString &out, const QString &errOut, int code)
    {
        QVariantList rows;
        for (const QString &line : out.split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("sftp>")) || line.trimmed().isEmpty()) {
                continue;
            }
            if (line.contains(QLatin1String("working directory"))) {
                const QString p = line.section(QLatin1Char(':'), 1).trimmed();
                if (!p.isEmpty() && p != m_path) {
                    m_path = p;
                    Q_EMIT pathChanged();
                }
                continue;
            }
            // drwxr-xr-x    ? root     root         4096 Oct  8 22:17 name (the name may hold spaces)
            static const QRegularExpression re(QStringLiteral(
                "^(\\S+)\\s+\\S+\\s+(\\S+)\\s+(\\S+)\\s+(\\d+)\\s+(\\S+)\\s+(\\d+)\\s+([\\d:]+)\\s(.*)$"));
            const auto m = re.match(line);
            if (!m.hasMatch()) {
                continue;
            }
            const QString name = m.captured(8);
            if (name == QLatin1String(".") || name == QLatin1String("..")) {
                continue;
            }
            rows << QVariantMap{
                { QStringLiteral("name"), name },
                { QStringLiteral("dir"), m.captured(1).startsWith(QLatin1Char('d')) },
                { QStringLiteral("size"), m.captured(4).toLongLong() },
                { QStringLiteral("date"), m.captured(5) + QLatin1Char(' ') + m.captured(6) + QLatin1Char(' ') + m.captured(7) },
            };
        }
        QString errText;
        if (code != 0 || errOut.contains(QLatin1String("Can't"))) {
            errText = (errOut.isEmpty() ? QStringLiteral("sftp failed") : errOut.trimmed()).left(200);
        }
        std::sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
            const QVariantMap ma = a.toMap();
            const QVariantMap mb = b.toMap();
            if (ma.value(QStringLiteral("dir")).toBool() != mb.value(QStringLiteral("dir")).toBool()) {
                return ma.value(QStringLiteral("dir")).toBool();
            }
            return ma.value(QStringLiteral("name")).toString().compare(mb.value(QStringLiteral("name")).toString(),
                                                                       Qt::CaseInsensitive) < 0;
        });
        if (rows != m_entries) {
            m_entries = rows;
            Q_EMIT entriesChanged();
        }
        if (errText != m_err) {
            m_err = errText;
            Q_EMIT errChanged();
        }
    }
    // A plain freedesktop Notify: a toast card drops from the island's bar.
    void sendNotify(bool ok, const QString &errOut)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("/org/freedesktop/Notifications"), QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("Notify"));
        m << QStringLiteral("Aether Console") << 0u
          << (ok ? QStringLiteral("emblem-downloads") : QStringLiteral("dialog-error"))
          << (ok ? QStringLiteral("Transfer finished") : QStringLiteral("Transfer failed"))
          << (ok ? QStringLiteral("Check ~/Downloads") : errOut.left(200)) << QStringList()
          << QVariantMap() << 5000;
        QDBusConnection::sessionBus().asyncCall(m);
    }

    QVariantMap m_session;
    QVariantList m_entries;
    QString m_path;
    QString m_err;
    QProcess *m_ls = nullptr;
    int m_busy = 0;
};
