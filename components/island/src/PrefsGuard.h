// The island's preferences outlive whatever happens to their file. aetherislandrc gets rewritten
// by hand, by scripts and by test runs (one `printf ... > aetherislandrc` wiped every setting and
// the bar came back on its defaults: the YouTube Music widget on again, the app autostarting and
// resuming a song). So a copy of the last good state lives outside ~/.config, and any key that goes
// missing from the live file is put back from it - at start, before any store reads a value, and
// whenever the file changes while the island runs. Values edited from outside are kept (the copy
// follows them); only keys that disappear come back. The island itself never removes a key (it
// writes an empty list instead), so a vanished key is always damage.
#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QLockFile>
#include <QObject>
#include <QSaveFile>
#include <QTimer>

class PrefsGuard : public QObject
{
    Q_OBJECT

public:
    explicit PrefsGuard(QObject *parent = nullptr)
        : QObject(parent)
        , m_live(QDir::homePath() + QStringLiteral("/.config/aetherislandrc"))
        , m_copy(qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + QStringLiteral("/.local/state"))
                 + QStringLiteral("/aether-island/aetherislandrc"))
    {
        heal();
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(500);   // QSettings and editors write in steps: judge the file once it rests
        connect(&m_debounce, &QTimer::timeout, this, &PrefsGuard::heal);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
        // The watch is lost when the file is replaced or deleted; the poll re-arms it and catches those.
        m_poll.setInterval(3000);
        connect(&m_poll, &QTimer::timeout, this, [this] {
            if (stamp() != m_stamp) {
                m_debounce.start();
            }
        });
        m_poll.start();
    }

private:
    struct Group {
        QByteArray name;            // "[Name]" line as written; empty for keys above the first group
        QList<QByteArray> lines;    // "key=value" lines, raw (QSettings' own escaping is kept as is)
    };
    static QByteArray keyOf(const QByteArray &line) { return line.left(line.indexOf('=')).trimmed(); }
    static QList<Group> parse(const QByteArray &text)
    {
        QList<Group> out{Group{}};
        for (const QByteArray &raw : text.split('\n')) {
            const QByteArray line = raw.trimmed();
            if (line.startsWith('[') && line.endsWith(']')) {
                out << Group{line, {}};
            } else if (line.contains('=') && !line.startsWith(';') && !line.startsWith('#')) {
                out.last().lines << line;
            }
        }
        return out;
    }
    static QByteArray serialize(const QList<Group> &groups)
    {
        QByteArray out;
        for (const Group &g : groups) {
            if (g.lines.isEmpty()) {
                continue;
            }
            if (!g.name.isEmpty()) {
                out += (out.isEmpty() ? "" : "\n") + g.name + '\n';
            }
            for (const QByteArray &l : g.lines) {
                out += l + '\n';
            }
        }
        return out;
    }
    static Group *find(QList<Group> &groups, const QByteArray &name)
    {
        for (Group &g : groups) {
            if (g.name == name) {
                return &g;
            }
        }
        return nullptr;
    }
    static QByteArray read(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }
    static bool write(const QString &path, const QByteArray &data)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile f(path);   // atomic: a crash or power cut mid-write leaves the old file whole
        return f.open(QIODevice::WriteOnly) && f.write(data) == data.size() && f.commit();
    }
    QString stamp() const
    {
        const QFileInfo i(m_live);
        return i.exists() ? QString::number(i.size()) + QLatin1Char('@') + QString::number(i.lastModified().toMSecsSinceEpoch()) : QString();
    }

    void heal()
    {
        {
            QLockFile lock(m_live + QStringLiteral(".lock"));   // the same lock QSettings takes around its writes
            lock.tryLock(2000);
            QList<Group> live = parse(read(m_live));
            int restored = 0;
            for (const Group &g : parse(read(m_copy))) {
                for (const QByteArray &line : g.lines) {
                    Group *target = find(live, g.name);
                    bool present = false;
                    for (const QByteArray &l : target ? target->lines : QList<QByteArray>()) {
                        present = present || keyOf(l) == keyOf(line);
                    }
                    if (present) {
                        continue;
                    }
                    if (!target) {
                        live << Group{g.name, {}};
                        target = &live.last();
                    }
                    target->lines << line;
                    ++restored;
                }
            }
            const QByteArray healed = serialize(live);
            if (restored > 0 && write(m_live, healed)) {
                qInfo("aether-island: put back %d setting(s) that went missing from aetherislandrc", restored);
            }
            if (!healed.isEmpty() && healed != read(m_copy)) {
                write(m_copy, healed);
            }
        }
        if (QFile::exists(m_live) && !m_watcher.files().contains(m_live)) {
            m_watcher.addPath(m_live);
        }
        m_stamp = stamp();
    }

    const QString m_live;
    const QString m_copy;
    QString m_stamp;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_poll;
};
