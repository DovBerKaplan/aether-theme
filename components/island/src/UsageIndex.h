#pragma once

// The launcher's memory. Everything here comes from analytics that already run on this
// machine - nothing is tracked by us:
//   kactivitymanagerd  -> apps and files, with Plasma's own frecency score (exp(-days/32))
//   Chrome history     -> pages (visited titles + visit counts), read via a copy so a live
//                         checkpoint can never tear the read
//   recently-used.xbel -> files GTK apps opened (a thin fallback behind kamd)
//   aetherdockrc       -> the dock's pinned launchers, which get DEMOTED in ranking (-200,
//                         one tier down), because they are already visible on the dock
// Plus a plain XDG application catalog so typed queries can reach apps that were never
// launched yet. Reads are async (QtConcurrent) and cached; refreshes are lazy and small.

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QObject>
#include <QRegularExpression>
#include <QSettings>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QXmlStreamReader>
#include <QtConcurrent/QtConcurrentRun>
#include <QtMath>

#include <QSet>
#include <algorithm>
#include <functional>
#include <memory>

struct UsageCandidate
{
    enum Kind { App, File, Page };
    Kind kind = App;
    QString key;            // desktop id | absolute path | url
    QString title;          // what the eye reads
    QString heName;         // apps: Name[he], matched as well
    QString icon;           // apps: theme icon name
    QString path;           // apps: .desktop file path (gio launch)
    double usage = 0;       // normalized 0..1 usage credit
    qint64 lastUsed = 0;    // epoch seconds, tie-breaker
    bool pinned = false;    // dock pinned: -200 in the final score
};

struct UsageIndexData
{
    QVector<UsageCandidate> candidates;
    QStringList pinnedIds;
    bool ready = false;
};

class UsageIndex : public QObject
{
    Q_OBJECT

public:
    explicit UsageIndex(QObject *parent = nullptr)
        : QObject(parent)
    {
        connect(&m_watcher, &QFutureWatcher<std::shared_ptr<const UsageIndexData>>::finished,
                this, [this] {
                    if (m_watcher.isCanceled() || !m_watcher.result())
                        return;
                    m_data = m_watcher.result();
                    Q_EMIT loaded();
                });
    }

    // Kicks the first background load; later refreshes stay lazy and small.
    void ensureStarted()
    {
        if (m_pending)
            return;
        m_pending = true;
        QFuture<std::shared_ptr<const UsageIndexData>> f = QtConcurrent::run(loadAll);
        m_watcher.setFuture(f);
    }

    // Called on every search open: a freshly downloaded app must appear without restarting
    // the island, so the application folders' newest mtime decides whether to reload.
    void maybeRefresh()
    {
        const qint64 stamp = catalogStamp();
        if (stamp == m_seenCatalogStamp)
            return;
        m_seenCatalogStamp = stamp;
        m_pending = false;          // the one-shot guard must not block a refresh after the first load
        ensureStarted();
    }

    bool ready() const { return m_data && m_data->ready; }
    std::shared_ptr<const UsageIndexData> snapshot() const { return m_data; }

Q_SIGNALS:
    void loaded();

private:
    // ---- normalization & text tiers ----------------------------------------------------
    static QString normalize(QString s)
    {
        s = s.toLower();
        QString out;
        out.reserve(s.size());
        for (const QChar ch : s) {
            const ushort u = ch.unicode();
            if (u >= 0x0591 && u <= 0x05C7)
                continue;                                    // Hebrew niqqud / cantillation
            switch (u) {                                     // Hebrew final letters fold to base
            case 0x05DA: out.append(QChar(0x05DB)); continue;
            case 0x05DD: out.append(QChar(0x05DE)); continue;
            case 0x05DF: out.append(QChar(0x05E0)); continue;
            case 0x05E3: out.append(QChar(0x05E4)); continue;
            case 0x05E5: out.append(QChar(0x05E6)); continue;
            }
            out.append(ch);
        }
        return out;
    }

    static bool isBoundary(ushort u)
    {
        return u == ' ' || u == '-' || u == '_' || u == '/' || u == '.' || u == ':' || u == '(' || u == '[';
    }

    // 4 exact · 3 prefix · 2 word-prefix · 1 substring · 0.5 subsequence · -1 none
    static int textTier(const QString &normField, const QString &normQuery)
    {
        if (normQuery.isEmpty())
            return -1;
        if (normField == normQuery)
            return 4;
        const int idx = normField.indexOf(normQuery);
        if (idx == 0)
            return 3;
        if (idx > 0 && isBoundary(normField.at(idx - 1).unicode()))
            return 2;
        if (idx > 0)
            return 1;
        // subsequence with a floor: gaps cost, boundaries and runs pay (fzf-lite)
        int score = 0, prev = -2;
        int qi = 0;
        for (int i = 0; i < normField.size() && qi < normQuery.size(); ++i) {
            if (normField.at(i) != normQuery.at(qi))
                continue;
            score += 16 + (prev == i - 1 ? 4 : isBoundary(i > 0 ? normField.at(i - 1).unicode() : ' ') ? 8 : 0);
            if (i == 0)
                score += 8;
            prev = i;
            ++qi;
        }
        return (qi == normQuery.size() && score >= 24) ? 0 : -1;
    }

    static int bestTier(const UsageCandidate &c, const QString &normQuery)
    {
        int t = textTier(normalize(c.title), normQuery);
        if (!c.heName.isEmpty())
            t = qMax(t, textTier(normalize(c.heName), normQuery));
        if (c.kind == UsageCandidate::App) {
            t = qMax(t, textTier(normalize(c.key), normQuery));
            // the id without its extension too ("org.kde.konsole" reads better half-typed)
            t = qMax(t, textTier(normalize(c.key.section('.', 0, -2).isEmpty() ? c.key : c.key.section('.', 0, -2)), normQuery));
        } else {
            t = qMax(t, textTier(normalize(c.key.section('/', -1)), normQuery));
        }
        // pages and files only answer real substrings: a loose subsequence on a page title
        // or a long URL drags half the browser history onto the glass
        if (c.kind != UsageCandidate::App && t == 0)
            t = -1;
        return t;
    }

public:
    // The ranked world for a typed query. Tier first, usage within the tier, pins demoted.
    QVector<UsageCandidate> rank(const QString &query, const QString &scope, int limit = 12) const
    {
        QVector<UsageCandidate> out;
        const auto data = snapshot();
        if (!data)
            return out;
        const QString nq = normalize(query.simplified());
        if (nq.isEmpty())
            return out;
        QVector<QPair<double, const UsageCandidate *>> ranked;
        for (const UsageCandidate &c : data->candidates) {
            if (scope == QStringLiteral("apps") && c.kind != UsageCandidate::App)
                continue;
            if (scope == QStringLiteral("files") && c.kind != UsageCandidate::File)
                continue;
            if (scope == QStringLiteral("web") && c.kind != UsageCandidate::Page)
                continue;
            const int t = bestTier(c, nq);
            if (t < 0)
                continue;
            const double final = t * 1000.0 + (c.pinned ? -200.0 : 0.0) + 100.0 * c.usage;
            ranked.append({ final, &c });
        }
        std::stable_sort(ranked.begin(), ranked.end(),
                         [](const auto &a, const auto &b) { return a.first > b.first; });
        for (int i = 0; i < limit && i < ranked.size(); ++i)
            out.append(*ranked[i].second);
        return out;
    }

    // The empty-query world: the most-used apps, then the freshest files and pages.
    void suggestions(QVector<UsageCandidate> &apps, QVector<UsageCandidate> &recent) const
    {
        const auto data = snapshot();
        if (!data)
            return;
        QList<QPair<double, const UsageCandidate *>> usedApps;
        QList<QPair<qint64, const UsageCandidate *>> fresh;
        for (const UsageCandidate &c : data->candidates) {
            if (c.kind == UsageCandidate::App) {
                if (c.usage > 0)
                    usedApps.append({ c.usage, &c });
            } else if (c.lastUsed > 0) {
                fresh.append({ c.lastUsed, &c });
            }
        }
        std::sort(usedApps.begin(), usedApps.end(), [](auto &a, auto &b) { return a.first > b.first; });
        std::stable_sort(fresh.begin(), fresh.end(), [](auto &a, auto &b) { return a.first > b.first; });
        for (int i = 0; i < usedApps.size() && apps.size() < 8; ++i)
            apps.append(*usedApps[i].second);
        QSet<QString> seenTitles;
        for (int i = 0; i < fresh.size() && recent.size() < 5; ++i) {
            if (seenTitles.contains(fresh[i].second->title))
                continue;
            seenTitles.insert(fresh[i].second->title);
            recent.append(*fresh[i].second);
        }
    }

private:
    // ---- loaders (all static, running on the concurrent pool) ---------------------------

    static double kamdToUsage(double score)
    {
        return qBound(0.0, score / (score + 16.0), 1.0);
    }

    // A downloaded .AppImage is an application: launch it, name it, tag it.
    static void promoteAppImage(UsageCandidate &c)
    {
        if (!c.title.endsWith(QLatin1String(".AppImage"), Qt::CaseInsensitive))
            return;
        c.kind = UsageCandidate::App;
        c.path = c.key;
        c.title = c.title.left(c.title.size() - 9);
        // "TjFlix-1.0.52-linux-x86_64" reads as "TjFlix": a version tail drops
        const int dash = c.title.indexOf(QLatin1Char('-'));
        if (dash > 0 && dash + 1 < c.title.size() && c.title.at(dash + 1).isDigit())
            c.title = c.title.left(dash);
    }

    static void loadKamd(QVector<UsageCandidate> &out, QHash<QString, QPair<double, qint64>> &appUsage)
    {
        const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
            + QStringLiteral("/kactivitymanagerd/resources/database");
        if (!QFileInfo::exists(path))
            return;
        QSqlDatabase::removeDatabase(QStringLiteral("kamd"));
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("kamd"));
        db.setDatabaseName(QStringLiteral("file:") + path + QStringLiteral("?mode=ro"));
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_URI"));
        if (!db.open())
            return;
        {
            QSqlQuery q(db);
            q.exec(QStringLiteral("SELECT targettedResource, cachedScore, lastUpdate FROM ResourceScoreCache"));
            while (q.next()) {
                const QString res = q.value(0).toString();
                const double score = q.value(1).toDouble();
                const qint64 last = q.value(2).toLongLong();
                if (res.startsWith(QLatin1String("applications:"))) {
                    appUsage.insert(res.mid(13), { score, last });
                } else if (res.startsWith(QLatin1Char('/'))) {
                    UsageCandidate c;
                    c.kind = UsageCandidate::File;
                    c.key = res;
                    c.title = QFileInfo(res).fileName();
                    promoteAppImage(c);
                    c.usage = kamdToUsage(score);
                    c.lastUsed = last;
                    out.append(c);
                }
                // kamd's https rows are thin (score <= 1); Chrome history is the page source
            }
        }
        db.close();
        QSqlDatabase::removeDatabase(QStringLiteral("kamd"));
    }

    static void loadXbel(QVector<UsageCandidate> &out, const QHash<QString, QPair<double, qint64>> &appUsage)
    {
        Q_UNUSED(appUsage)
        QFile f(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/recently-used.xbel"));
        if (!f.open(QIODevice::ReadOnly))
            return;
        QXmlStreamReader xml(&f);
        UsageCandidate cur;
        bool in = false;
        while (!xml.atEnd()) {
            xml.readNext();
            if (xml.isStartElement() && xml.name() == QStringLiteral("bookmark")) {
                const QString href = xml.attributes().value(QStringLiteral("href")).toString();
                if (href.startsWith(QLatin1String("file://"))) {
                    cur = UsageCandidate();
                    cur.kind = UsageCandidate::File;
                    cur.key = QUrl(href).toLocalFile();
                    cur.title = QFileInfo(cur.key).fileName();
                    promoteAppImage(cur);
                    cur.usage = 0.35;                        // behind any kamd-scored file
                    const QString iso = xml.attributes().value(QStringLiteral("modified")).toString();
                    cur.lastUsed = QDateTime::fromString(iso, Qt::ISODate).toSecsSinceEpoch();
                    in = true;
                }
            } else if (in && xml.isEndElement() && xml.name() == QStringLiteral("bookmark")) {
                if (!cur.key.isEmpty())
                    out.append(cur);
                in = false;
            }
        }
    }

    static QString chromeHistoryPath()
    {
        // the freshest History among the profile dirs wins
        QString best;
        QDateTime bestTime;
        const QStringList roots = {
            QDir::homePath() + QStringLiteral("/.config/google-chrome"),
            QDir::homePath() + QStringLiteral("/.config/chromium")
        };
        for (const QString &root : roots) {
            const QFileInfoList profiles = QDir(root).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QFileInfo &p : profiles) {
                const QFileInfo h(p.filePath() + QStringLiteral("/History"));
                if (h.exists() && h.lastModified() > bestTime) {
                    bestTime = h.lastModified();
                    best = h.filePath();
                }
            }
        }
        return best;
    }

    static void loadChrome(QVector<UsageCandidate> &out)
    {
        const QString src = chromeHistoryPath();
        if (src.isEmpty())
            return;
        const QString cache = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
            + QStringLiteral("/aether-chrome-history");
        QFile::remove(cache);
        if (!QFile::copy(src, cache))
            return;
        QSqlDatabase::removeDatabase(QStringLiteral("chrome"));
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("chrome"));
        db.setDatabaseName(cache);
        if (!db.open())
            return;
        QSqlQuery q(db);
        q.exec(QStringLiteral("SELECT url, title, visit_count, last_visit_time FROM urls "
                              "ORDER BY last_visit_time DESC LIMIT 1200"));
        while (q.next()) {
            const QString url = q.value(0).toString();
            if (url.startsWith(QLatin1String("chrome://")) || url.startsWith(QLatin1String("about:"))
                || (url.contains(QLatin1String("google.")) && url.contains(QLatin1String("/search"))) || url.isEmpty())
                continue;
            UsageCandidate c;
            c.kind = UsageCandidate::Page;
            c.key = url;
            c.title = q.value(1).toString();
            if (c.title.isEmpty())
                c.title = QUrl(url).host();
            const int visits = q.value(2).toInt();
            const qint64 chromeEpoch = q.value(3).toLongLong() / 1000000 - 11644473600LL;
            const double days = QDateTime::currentSecsSinceEpoch() - chromeEpoch > 0
                ? (QDateTime::currentSecsSinceEpoch() - chromeEpoch) / 86400.0 : 0.0;
            c.usage = qBound(0.0, (visits / (visits + 5.0)) * std::exp(-days / 32.0), 1.0);
            c.lastUsed = chromeEpoch;
            if (c.title.size() > 1)
                out.append(c);
        }
        db.close();
        QSqlDatabase::removeDatabase(QStringLiteral("chrome"));
        QFile::remove(cache);
    }

    static void loadCatalog(QVector<UsageCandidate> &out, const QHash<QString, QPair<double, qint64>> &appUsage,
                            const QStringList &pinned)
    {
        QStringList dirs = {
            QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation),
            QStringLiteral("/usr/share/applications"),
            QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
            QStringLiteral("/var/lib/flatpak/exports/share/applications")
        };
        QHash<QString, int> seen;
        for (const QString &dir : dirs) {
            const QFileInfoList files = QDir(dir).entryInfoList({ QStringLiteral("*.desktop") }, QDir::Files);
            for (const QFileInfo &fi : files) {
                if (seen.contains(fi.fileName()))
                    continue;                                // user applications shadow system ones
                QFile f(fi.filePath());
                if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
                    continue;
                bool inEntry = false, keep = true;
                QString name, heName, icon;
                QTextStream in(&f);
                while (!in.atEnd()) {
                    const QString line = in.readLine().trimmed();
                    if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
                        continue;
                    if (line.startsWith(QLatin1Char('['))) {
                        if (inEntry)
                            break;                           // next group: Desktop Entry is done
                        inEntry = (line.compare(QLatin1String("[Desktop Entry]"), Qt::CaseInsensitive) == 0);
                        continue;
                    }
                    if (!inEntry || !line.contains(QLatin1Char('=')))
                        continue;
                    const int eq = line.indexOf(QLatin1Char('='));
                    const QString k = line.left(eq).trimmed();
                    const QString v = line.mid(eq + 1).trimmed();
                    if (k == QLatin1String("Name"))
                        name = v;
                    else if (k == QLatin1String("Name[he]"))
                        heName = v;
                    else if (k == QLatin1String("Icon"))
                        icon = v;
                    else if ((k == QLatin1String("NoDisplay") || k == QLatin1String("Hidden")) && v == QLatin1String("true"))
                        keep = false;
                    else if (k == QLatin1String("Type") && v != QLatin1String("Application"))
                        keep = false;
                }
                if (!keep || name.isEmpty())
                    continue;
                UsageCandidate c;
                c.kind = UsageCandidate::App;
                c.key = fi.fileName();
                c.title = name;
                c.heName = heName;
                c.icon = icon;
                c.path = fi.filePath();
                if (appUsage.contains(c.key)) {
                    c.usage = kamdToUsage(appUsage.value(c.key).first);
                    c.lastUsed = appUsage.value(c.key).second;
                }
                c.pinned = pinned.contains(c.key);
                seen.insert(fi.fileName(), out.size());
                out.append(c);
            }
        }
    }

    // Downloads is the launcher's blind spot otherwise: Telegram, browsers and messengers
    // drop files there without ever touching a KDE-tracked app, so kamd and the xbel never
    // learn about them. Two levels deep, the newest 300 files, modest base usage.
    static void loadDownloads(QVector<UsageCandidate> &out)
    {
        const QStringList roots = {
            QDir::homePath() + QStringLiteral("/Downloads"),
            QDir::homePath() + QStringLiteral("/Desktop")
        };
        QVector<QPair<qint64, UsageCandidate>> found;
        for (const QString &root : roots) {
            QDir dir(root);
            if (!dir.exists())
                continue;
            QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
            const QFileInfoList subdirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QFileInfo &sub : subdirs)
                entries += QDir(sub.filePath()).entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
            for (const QFileInfo &fi : entries) {
                if (fi.fileName().startsWith(QLatin1Char('.')))
                    continue;
                UsageCandidate c;
                c.kind = UsageCandidate::File;
                c.key = fi.filePath();
                c.title = fi.fileName();
                promoteAppImage(c);
                c.usage = 0.15;                          // below anything actually opened
                c.lastUsed = fi.lastModified().toSecsSinceEpoch();
                found.append({ c.lastUsed, c });
            }
        }
        std::stable_sort(found.begin(), found.end(),
                         [](const auto &a, const auto &b) { return a.first > b.first; });
        for (int i = 0; i < found.size() && out.size() < 300; ++i)
            out.append(found[i].second);
    }

    static QStringList loadPinned()
    {
        QSettings rc(QDir::homePath() + QStringLiteral("/.config/aetherdockrc"), QSettings::IniFormat);
        const QStringList urls = rc.value(QStringLiteral("General/launchers")).toStringList();
        QStringList ids;
        for (const QString &u : urls) {
            if (u.startsWith(QLatin1String("applications:")))
                ids.append(u.mid(13));
            else if (u.startsWith(QLatin1String("file://")))
                ids.append(QFileInfo(QUrl(u).toLocalFile()).fileName());
        }
        return ids;
    }

    static qint64 catalogStamp()
    {
        qint64 newest = 0;
        const QStringList dirs = {
            QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation),
            QStringLiteral("/usr/share/applications"),
            QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
            QStringLiteral("/var/lib/flatpak/exports/share/applications")
        };
        for (const QString &dir : dirs) {
            const QFileInfoList files = QDir(dir).entryInfoList({ QStringLiteral("*.desktop") }, QDir::Files);
            for (const QFileInfo &fi : files)
                newest = qMax(newest, fi.lastModified().toSecsSinceEpoch());
        }
        return newest;
    }

    static std::shared_ptr<const UsageIndexData> loadAll()
    {
        auto data = std::make_shared<UsageIndexData>();
        data->pinnedIds = loadPinned();

        QHash<QString, QPair<double, qint64>> appUsage;
        QVector<UsageCandidate> files;
        loadKamd(files, appUsage);

        QVector<UsageCandidate> pages;
        loadChrome(pages);
        QVector<UsageCandidate> xbelFiles;
        loadXbel(xbelFiles, appUsage);

        // files: kamd wins where both know a path; xbel adds what kamd never saw
        QHash<QString, int> byPath;
        for (int i = 0; i < files.size(); ++i)
            byPath.insert(files[i].key, i);
        for (const UsageCandidate &x : xbelFiles) {
            const int i = byPath.value(x.key, -1);
            if (i >= 0) {
                files[i].usage = qMax(files[i].usage, x.usage);
                files[i].lastUsed = qMax(files[i].lastUsed, x.lastUsed);
            } else {
                files.append(x);
            }
        }
        std::stable_sort(files.begin(), files.end(), [](const UsageCandidate &a, const UsageCandidate &b) {
            return a.usage > b.usage;
        });
        if (files.size() > 300)
            files.resize(300);
        std::stable_sort(pages.begin(), pages.end(), [](const UsageCandidate &a, const UsageCandidate &b) {
            return a.usage > b.usage;
        });
        if (pages.size() > 600)
            pages.resize(600);

        loadDownloads(files);
        loadCatalog(data->candidates, appUsage, data->pinnedIds);
        // the same app often ships twice (konsole.desktop + org.kde.konsole.desktop):
        // one row per normalized title, the more-used and Hebrew-named copy winning
        QVector<UsageCandidate> apps;
        QHash<QString, int> byTitle;
        for (const UsageCandidate &c : data->candidates) {
            if (c.kind != UsageCandidate::App) {
                apps.append(c);
                continue;
            }
            const QString t = normalize(c.title);
            const int i = byTitle.value(t, -1);
            if (i < 0) {
                byTitle.insert(t, apps.size());
                apps.append(c);
                continue;
            }
            UsageCandidate &keep = apps[i];
            const bool better = c.usage > keep.usage
                || (c.usage == keep.usage && (!keep.heName.isEmpty() ? false : !c.heName.isEmpty()));
            if (better)
                keep = c;
        }
        data->candidates = apps;
        data->candidates += files;
        data->candidates += pages;
        data->ready = true;
        return data;
    }

    QFutureWatcher<std::shared_ptr<const UsageIndexData>> m_watcher;
    std::shared_ptr<const UsageIndexData> m_data;
    bool m_pending = false;
    qint64 m_seenCatalogStamp = -1;
};
