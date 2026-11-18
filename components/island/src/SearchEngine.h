#pragma once

// The island's launcher engine. Two worlds merged into one ranked list:
//   local  - UsageIndex: the machine's own analytics (kamd app/file scores, Chrome pages),
//            tiered text match, usage ordered within tiers, dock pins demoted
//   KRunner- the live runners the user enabled (calculator, unitconverter, shell,
//            webshortcuts) for everything that isn't a resource: math, units, commands
// With no query the engine answers at once with suggestions - the most-used apps and the
// freshest files/pages - so the glass is useful the moment it opens.

#include <QDesktopServices>
#include <QTimer>
#include <QProcess>
#include <QUrl>
#include <QVariantList>

#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/RunnerManager>

#include "UsageIndex.h"

class SearchEngine : public QObject
{
    Q_OBJECT
    // Flat ranked list for QML: {text, subtext, icon, kind}
    Q_PROPERTY(QVariantList matches READ matches NOTIFY matchesChanged)
    // The empty-query world: 8 frequent apps for the grid
    Q_PROPERTY(QVariantList suggestions READ suggestions NOTIFY suggestionsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool localReady READ localReady NOTIFY suggestionsChanged)
    // [{key, ok}] in display order: all, apps, files, web
    Q_PROPERTY(QVariantList scopes READ scopes NOTIFY scopesChanged)
    Q_PROPERTY(QString scope READ scope NOTIFY scopeChanged)

public:
    explicit SearchEngine(QObject *parent = nullptr)
        : QObject(parent)
    {
        krunnerTimer.setSingleShot(true);
        krunnerTimer.setInterval(280);
        connect(&krunnerTimer, &QTimer::timeout, this, [this] {
            if (m_term.isEmpty())
                return;
            const QStringList runners = runnersForScope(m_scope);
            m_manager.setAllowedRunners(runners);       // only this scope's runners ever load or run
            if (runners.size() > 1)
                m_manager.launchQuery(m_term);          // the whole whitelist queries together
            else
                m_manager.launchQuery(m_term, runners.first());
        });
        m_index.ensureStarted();    // warm the index while the desktop comes up
        connect(&m_index, &UsageIndex::loaded, this, [this] {
            Q_EMIT suggestionsChanged();
            rebuildLocal(m_term);
        });
        // Every runner reports separately; rebuilding the whole QML model per report churns
        // all rows five times per keystroke. Coalesce into one rebuild 60 ms after the last.
        m_coalesce.setSingleShot(true);
        m_coalesce.setInterval(60);
        connect(&m_coalesce, &QTimer::timeout, this, [this] { rebuild(); });
        connect(&m_manager, &KRunner::RunnerManager::matchesChanged, this,
                [this](const QList<KRunner::QueryMatch> &matches) {
                    m_raw = matches;
                    m_busy = false;
                    Q_EMIT busyChanged();
                    m_coalesce.stop();
                    m_coalesce.start();
                });
    }

    QVariantList matches() const { return m_matches; }
    QVariantList suggestions() const { return m_suggestions; }
    bool busy() const { return m_busy; }
    bool localReady() const { return m_index.ready(); }
    QString scope() const { return m_scope; }

    QVariantList scopes() const
    {
        return {
            QVariantMap { { QStringLiteral("key"), QStringLiteral("all") }, { QStringLiteral("ok"), true } },
            QVariantMap { { QStringLiteral("key"), QStringLiteral("apps") }, { QStringLiteral("ok"), true } },
            QVariantMap { { QStringLiteral("key"), QStringLiteral("files") }, { QStringLiteral("ok"), true } },
            QVariantMap { { QStringLiteral("key"), QStringLiteral("web") }, { QStringLiteral("ok"), true } }
        };
    }

    Q_INVOKABLE void query(const QString &text)
    {
        m_term = text.simplified();
        if (m_term.isEmpty()) {
            m_manager.reset();
            m_raw.clear();
            m_busy = false;
            Q_EMIT busyChanged();
            rebuildLocal({});
            return;
        }
        m_busy = true;
        Q_EMIT busyChanged();
        // local answers land first (the index is in-process); KRunner follows only when its
        // scope needs it, and late enough that a fast typist never pays for idle keystrokes
        rebuildLocal(m_term);
        if (runnersForScope(m_scope).isEmpty()) {
            m_manager.reset();
            m_raw.clear();
            m_busy = false;
            Q_EMIT busyChanged();
            rebuild();
            return;
        }
        krunnerTimer.stop(); krunnerTimer.start();
    }

    Q_INVOKABLE void run(int index)
    {
        if (index < 0 || index >= m_entries.size())
            return;
        const Entry e = m_entries.at(index);
        if (e.local) {
            const UsageCandidate &c = *e.candidate;
            switch (c.kind) {
            case UsageCandidate::App:
                if (c.path.endsWith(QLatin1String(".AppImage"), Qt::CaseInsensitive)) {
                    // downloads usually arrive without the executable bit
                    QFile f(c.path);
                    f.setPermissions(f.permissions() | QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther);
                    QProcess::startDetached(c.path, {});
                } else {
                    QProcess::startDetached(QStringLiteral("gio"), { QStringLiteral("launch"), c.path });
                }
                break;
            case UsageCandidate::File:
                QDesktopServices::openUrl(QUrl::fromLocalFile(c.key));
                break;
            case UsageCandidate::Page:
                QDesktopServices::openUrl(QUrl(c.key));
                break;
            }
        } else if (e.match) {
            m_manager.run(*e.match);
        }
        clear();
    }

    // A tile on the suggestions grid: same dispatch, its own entry list.
    Q_INVOKABLE void runSuggestion(int index)
    {
        if (index < 0 || index >= m_suggestionEntries.size())
            return;
        const Entry e = m_suggestionEntries.at(index);
        if (!e.local || !e.candidate)
            return;
        const UsageCandidate &c = *e.candidate;
        switch (c.kind) {
        case UsageCandidate::App:
            if (c.path.endsWith(QLatin1String(".AppImage"), Qt::CaseInsensitive)) {
                QFile f(c.path);
                f.setPermissions(f.permissions() | QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther);
                QProcess::startDetached(c.path, {});
            } else {
                QProcess::startDetached(QStringLiteral("gio"), { QStringLiteral("launch"), c.path });
            }
            break;
        case UsageCandidate::File:
            QDesktopServices::openUrl(QUrl::fromLocalFile(c.key));
            break;
        case UsageCandidate::Page:
            QDesktopServices::openUrl(QUrl(c.key));
            break;
        }
        clear();
    }

    Q_INVOKABLE void clear()
    {
        m_manager.reset();
        m_raw.clear();
        m_term.clear();
        m_busy = false;
        Q_EMIT busyChanged();
        rebuildLocal({});
    }

    // Loads the plugin list once and starts the usage index. The runner whitelist is the
    // whole optimization: without it RunnerManager loads every KRunner plugin on the disk
    // (appstream alone parses tens of MB) and runs them on every keystroke. We want math,
    // units, shell and web - that is all.
    Q_INVOKABLE void prime()
    {
        m_index.maybeRefresh();     // a newly downloaded app shows up on the next open
        // The whitelist is the whole optimization: without it RunnerManager loads every
        // KRunner plugin on the disk (appstream alone parses tens of MB) and runs them on
        // every keystroke. We want math, units, shell and web - that is all. The ids are the
        // real plugin ids (probed live: krunner_shell, krunner_webshortcuts, ...).
        m_manager.setAllowedRunners({ QStringLiteral("calculator"), QStringLiteral("unitconverter"),
                                      QStringLiteral("krunner_shell"), QStringLiteral("krunner_webshortcuts"),
                                      QStringLiteral("krunner_konsoleprofiles"), QStringLiteral("krunner_bookmarksrunner"),
                                      QStringLiteral("krunner_systemsettings"), QStringLiteral("baloosearch") });
        m_manager.runners();
        Q_EMIT scopesChanged();
    }

public Q_SLOTS:
    void setScope(const QString &scope)
    {
        if (m_scope == scope)
            return;
        m_scope = scope;
        Q_EMIT scopeChanged();
        if (!m_term.isEmpty())
            query(m_term);      // re-rank what is on the glass
    }

Q_SIGNALS:
    void matchesChanged();
    void suggestionsChanged();
    void busyChanged();
    void scopeChanged();
    void scopesChanged();

private:
    struct Entry
    {
        bool local = false;
        const UsageCandidate *candidate = nullptr;   // local results
        const KRunner::QueryMatch *match = nullptr;  // KRunner results
    };

    static QStringList runnersForScope(const QString &scope)
    {
        // apps: our catalog is the complete app list - KRunner's services runner would only
        // burn CPU re-finding what we already ranked. The open scope wants math, units,
        // shell and web - and must NOT sweep baloo in: an index query per keystroke is the
        // expensive thing this whitelist exists to prevent.
        if (scope == QStringLiteral("apps"))
            return {};                 // the catalog is the whole app list: no KRunner at all
        if (scope == QStringLiteral("files"))
            return { QStringLiteral("baloosearch") };
        if (scope == QStringLiteral("web"))
            return { QStringLiteral("krunner_webshortcuts") };
        return { QStringLiteral("calculator"), QStringLiteral("unitconverter"),
                 QStringLiteral("krunner_shell"), QStringLiteral("krunner_webshortcuts"),
                 QStringLiteral("krunner_konsoleprofiles"), QStringLiteral("krunner_bookmarksrunner"),
                 QStringLiteral("krunner_systemsettings") };
    }

    // KRunner's runner is woven into the match id ("runner:match..."); app matches are ours
    // now, so the services/appstream rows get dropped to avoid doubles.
    static bool isAppMatch(const KRunner::QueryMatch &m)
    {
        const QString id = m.id();
        return id.contains(QLatin1String("services")) || id.contains(QLatin1String("appstream")) || id.contains(QLatin1String(".desktop"));
    }

    void rebuildLocal(const QString &term)
    {
        m_localEntries.clear();
        m_suggestionEntries.clear();
        m_suggestions.clear();
        // the entries below point into this snapshot, so the engine owns a reference for
        // as long as they live - a background refresh swaps in a new snapshot harmlessly
        m_indexData = m_index.snapshot();
        if (!m_indexData)
            return;

        if (term.isEmpty()) {
            // these buffers are members: the entries below keep pointers into them, so a
            // local vector here would dangle the moment this function returns
            m_suggApps.clear();
            m_suggRecent.clear();
            m_index.suggestions(m_suggApps, m_suggRecent);
            for (const UsageCandidate &c : m_suggApps) {
                m_suggestionEntries.append({ true, &c, nullptr });
                m_suggestions.append(QVariantMap {
                    { QStringLiteral("text"), c.title },
                    { QStringLiteral("icon"), c.icon }
                });
            }
            for (const UsageCandidate &c : m_suggRecent)
                m_localEntries.append({ true, &c, nullptr });
            Q_EMIT suggestionsChanged();
            rebuild();          // the recent rows flow through the same glass as matches
            return;
        }

        m_ranked = m_index.rank(term, m_scope, 12);   // member: entries point into it
        for (const UsageCandidate &c : m_ranked)
            m_localEntries.append({ true, &c, nullptr });
        rebuild();
    }

    void rebuild()
    {
        QVariantList out;
        m_entries.clear();

        if (m_term.isEmpty()) {
            // the suggestions stay on the grid; the recent rows are the list
            for (const Entry &e : m_localEntries) {
                const UsageCandidate &c = *e.candidate;
                const QString kind = c.kind == UsageCandidate::File ? QStringLiteral("file") : QStringLiteral("page");
                out.append(QVariantMap {
                    { QStringLiteral("text"), c.title },
                    { QStringLiteral("subtext"), kind == QStringLiteral("file") ? c.key : QUrl(c.key).host() },
                    { QStringLiteral("icon"), QString() },
                    { QStringLiteral("kind"), kind }
                });
                m_entries.append(e);
            }
            m_matches = out;
            Q_EMIT matchesChanged();
            return;
        }

        for (const Entry &e : m_localEntries) {
            const UsageCandidate &c = *e.candidate;
            const QString kind = c.kind == UsageCandidate::App ? QStringLiteral("app")
                : c.kind == UsageCandidate::File ? QStringLiteral("file") : QStringLiteral("page");
            out.append(QVariantMap {
                { QStringLiteral("text"), c.title },
                { QStringLiteral("subtext"), c.kind == UsageCandidate::File ? c.key
                    : c.kind == UsageCandidate::Page ? QUrl(c.key).host()
                    : !c.heName.isEmpty() ? c.heName
                    : c.path.endsWith(QLatin1String(".AppImage"), Qt::CaseInsensitive)
                        ? QFileInfo(c.path).dir().path() : QString() },
                { QStringLiteral("icon"), c.kind == UsageCandidate::App ? c.icon : QString() },
                { QStringLiteral("kind"), kind }
            });
            m_entries.append(e);
        }
        for (const auto &m : m_raw) {
            if (isAppMatch(m))
                continue;
            const QString id = m.id();
            const QString kind = id.contains(QLatin1String("calculator")) || id.contains(QLatin1String("unitconverter"))
                ? QStringLiteral("calc")
                : id.contains(QLatin1String("webshortcuts")) || id.contains(QLatin1String("bookmarks"))
                    ? QStringLiteral("web") : QStringLiteral("command");
            QVariantMap row {
                { QStringLiteral("text"), m.text() },
                { QStringLiteral("subtext"), m.subtext() },
                { QStringLiteral("icon"), QString() },
                { QStringLiteral("kind"), kind }
            };
            if (kind == QStringLiteral("calc") && !m.subtext().isEmpty())
                row[QStringLiteral("subtext")] = m.subtext();
            out.append(row);
            m_entries.append({ false, nullptr, &m });
        }
        m_matches = out;
        Q_EMIT matchesChanged();
    }

    QTimer krunnerTimer;                   // the typed query reaches KRunner only once typing rests
    QTimer m_coalesce;                     // one QML rebuild per query burst, not one per runner
    KRunner::RunnerManager m_manager;
    UsageIndex m_index;
    QVariantList m_matches;
    QVariantList m_suggestions;
    QList<KRunner::QueryMatch> m_raw;
    std::shared_ptr<const UsageIndexData> m_indexData;   // keeps candidate memory alive
    QVector<UsageCandidate> m_ranked;      // buffers the entries point into
    QVector<UsageCandidate> m_suggApps;
    QVector<UsageCandidate> m_suggRecent;
    QVector<Entry> m_entries;              // rows of the current list
    QVector<Entry> m_localEntries;         // local rows (recent or ranked)
    QVector<Entry> m_suggestionEntries;    // the grid
    bool m_busy = false;
    QString m_scope = QStringLiteral("all");
    QString m_term;
};
