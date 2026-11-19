// aether-desk: the clean-desktop toggle. A transparent layer-shell surface over the desktop (layer
// Bottom: above the wallpaper and its icons, below every window) holds a small glass button at the
// bottom centre, above the dock. Folder: the desktop is clean; a click spreads the files out of
// it to their places and the folder turns into a broom. Broom: a click sweeps them all back in.
//
// The real icons stay Plasma's Folder View; this program only switches its filter (hide "*") and
// draws stand-ins for the flight. The files themselves are never touched. Only the button's rect
// takes input, so the rest of the desktop works as before.
#include <QCollator>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QIcon>
#include <QLocale>
#include <QMimeDatabase>
#include <QPainterPath>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickView>
#include <QRegion>
#include <QRegularExpression>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#include <KWindowEffects>
#include <LayerShellQt/Window>

// image://icon/<theme-name or absolute path>
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requested) override
    {
        const int px = requested.width() > 0 ? requested.width() : 64;
        QPixmap pm;
        if (id.startsWith(QLatin1Char('/'))) {
            pm.load(id);
            if (!pm.isNull()) {
                pm = pm.scaled(px, px, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            }
        }
        if (pm.isNull()) {
            QIcon icon = QIcon::fromTheme(id);
            if (icon.isNull()) {
                icon = QIcon::fromTheme(QStringLiteral("unknown"));
            }
            pm = icon.pixmap(px, px);
        }
        if (size) {
            *size = pm.size();
        }
        return pm;
    }
};

// Plasma desktop scripts. The hide script stashes each containment's own filter the first time
// (aetherClean marks that it holds ours), the show script puts it back, so a filter the user set
// in Folder View's settings survives a clean/show round trip, a crash or an uninstall.
static const char *kHideScript = R"JS(
desktops().forEach(function (d) {
    d.currentConfigGroup = ["General"];
    if (String(d.readConfig("aetherClean", "false")) !== "true") {
        d.writeConfig("aetherFilterMode", d.readConfig("filterMode", 0));
        d.writeConfig("aetherFilterPattern", d.readConfig("filterPattern", "*"));
        d.writeConfig("aetherClean", "true");
    }
    d.writeConfig("filterMode", 2);
    d.writeConfig("filterPattern", "*");
});
)JS";
static const char *kShowScript = R"JS(
desktops().forEach(function (d) {
    d.currentConfigGroup = ["General"];
    if (String(d.readConfig("aetherClean", "false")) === "true") {
        d.writeConfig("filterMode", parseInt(d.readConfig("aetherFilterMode", 0)) || 0);
        d.writeConfig("filterPattern", String(d.readConfig("aetherFilterPattern", "*")) || "*");
        d.writeConfig("aetherClean", "false");
    }
});
)JS";

class DeskController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantMap grid READ grid NOTIFY itemsChanged)
    Q_PROPERTY(bool clean READ clean NOTIFY cleanChanged)
    Q_PROPERTY(QString language READ language CONSTANT)   // the island's interface language (aetherislandrc)

public:
    explicit DeskController(QQuickView *view)
        : QObject(view), m_view(view)
    {
        m_desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        m_appletsRc = QDir::homePath() + QStringLiteral("/.config/plasma-org.kde.plasma.desktop-appletsrc");
        m_clean = QSettings(configPath(), QSettings::IniFormat).value(QStringLiteral("Desk/Clean"), false).toBool();

        // The desktop folder is watched for files coming and going (debounced, re-armed);
        // appletsrc is watched too - the panel's state must follow sorts made elsewhere
        // (Plasma's own settings UI). Plasma replaces the file on save, which drops the
        // watch, so every pass re-arms it.
        m_watcher.addPath(m_desktopDir);
        if (QFileInfo::exists(m_appletsRc)) {
            m_watcher.addPath(m_appletsRc);
        }
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] {
            if (QFileInfo::exists(m_desktopDir) && !m_watcher.directories().contains(m_desktopDir)) {
                m_watcher.addPath(m_desktopDir);
            }
            if (QFileInfo::exists(m_appletsRc) && !m_watcher.files().contains(m_appletsRc)) {
                m_watcher.addPath(m_appletsRc);
            }
            readItems();
        });
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });

        m_retry.setSingleShot(true);
        m_retry.setInterval(2000);
        connect(&m_retry, &QTimer::timeout, this, [this] { applyFilter(); });

        readItems();
        applyFilter();   // bring Folder View in line with the remembered state (plasmashell may still be starting)
    }

    QVariantList items() const { return m_items; }
    QVariantMap grid() const { return m_grid; }
    bool clean() const { return m_clean; }
    QString language() const
    {
        return QSettings(QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat)
            .value(QStringLiteral("Interface/Language"), QStringLiteral("en")).toString();
    }

    // Clean hides Folder View's icons, not clean shows them; remembered across logins.
    Q_INVOKABLE void setClean(bool clean)
    {
        if (clean != m_clean) {
            m_clean = clean;
            QSettings(configPath(), QSettings::IniFormat).setValue(QStringLiteral("Desk/Clean"), clean);
            Q_EMIT cleanChanged();
        }
        m_attempts = 0;
        applyFilter();
    }

    // Arrange: Folder View's own knobs, written through Plasma's desktop scripting so they land
    // live and persist in appletsrc. Flow packs every icon into one direction: 0 rows from the
    // top, 1 columns hugging the left edge, 2 columns hugging the right edge. A flow only shows
    // while the icons are sorted (sortMode -1 = manual placement), so a manual desktop is given
    // the name sort; the manual positions themselves are kept and come back with "free".
    Q_INVOKABLE void arrange(int flow)
    {
        const int arrangement = flow == 0 ? 0 : 1;
        const int alignment = flow == 2 ? 1 : 0;
        sendArrange(QStringLiteral(
            "desktops().forEach(function (d) {\n"
            "    d.currentConfigGroup = [\"General\"];\n"
            "    if (parseInt(d.readConfig(\"sortMode\", \"-1\")) === -1) d.writeConfig(\"sortMode\", 0);\n"
            "    d.writeConfig(\"arrangement\", %1);\n"
            "    d.writeConfig(\"alignment\", %2);\n"
            "});").arg(arrangement).arg(alignment));
    }

    // Sort key 0..3 (name, size, type, date) - Folder View stores KDirModel's column numbers:
    // name 0, size 1, date 2, type 6. -1 is manual placement (freeSort).
    Q_INVOKABLE void sort(int key, bool desc, bool dirsFirst)
    {
        static const int column[4] = { 0, 1, 6, 2 };
        const int mode = (key >= 0 && key < 4) ? column[key] : 0;
        sendArrange(QStringLiteral(
            "desktops().forEach(function (d) {\n"
            "    d.currentConfigGroup = [\"General\"];\n"
            "    d.writeConfig(\"sortMode\", %1);\n"
            "    d.writeConfig(\"sortDesc\", %2);\n"
            "    d.writeConfig(\"sortDirsFirst\", %3);\n"
            "});").arg(mode).arg(desc ? QStringLiteral("true") : QStringLiteral("false"))
                .arg(dirsFirst ? QStringLiteral("true") : QStringLiteral("false")));
    }

    Q_INVOKABLE void freeSort()
    {
        sendArrange(QStringLiteral(
            "desktops().forEach(function (d) {\n"
            "    d.currentConfigGroup = [\"General\"];\n"
            "    d.writeConfig(\"sortMode\", -1);\n"
            "});"));
    }

    // The glass parts of the surface: blurred behind, and the only parts that take the pointer.
    // Each entry is {x, y, w, h, r}; while the arrange panel is open its rect joins the button's.
    Q_INVOKABLE void setGlassRects(const QVariantList &rects)
    {
        QPainterPath p;
        for (const QVariant &v : rects) {
            const QVariantMap r = v.toMap();
            const qreal rad = r.value(QStringLiteral("r")).toReal();
            p.addRoundedRect(r.value(QStringLiteral("x")).toReal(), r.value(QStringLiteral("y")).toReal(),
                             r.value(QStringLiteral("w")).toReal(), r.value(QStringLiteral("h")).toReal(), rad, rad);
        }
        const QRegion shape(p.toFillPolygon().toPolygon());
        KWindowEffects::enableBlurBehind(m_view, !shape.isEmpty(), shape);
        m_view->setMask(shape.isEmpty() ? QRegion(0, 0, 1, 1) : shape);
    }

    Q_INVOKABLE void setButtonRect(const QRectF &r, qreal radius)
    {
        setGlassRects({ QVariantMap{ { QStringLiteral("x"), r.x() }, { QStringLiteral("y"), r.y() },
                                      { QStringLiteral("w"), r.width() }, { QStringLiteral("h"), r.height() },
                                      { QStringLiteral("r"), radius } } });
    }

public Q_SLOTS:
    void Toggle() { Q_EMIT toggleRequested(); }
    // From AetherBridge (plasmashell's Folder View): the empty-desktop right click, in
    // Folder View's coordinates - the desk's surface spans the same screen.
    void OpenArrange(int x, int y) { Q_EMIT arrangeRequested(x, y); }

Q_SIGNALS:
    void itemsChanged();
    void cleanChanged();
    void toggleRequested();
    void arrangeRequested(int x, int y);

private:
    static QString configPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aetherdeskrc");
    }

    // A Plasma desktop script against the live plasmashell: how the filter and every arrange
    // write land (live and persisted).
    QDBusPendingCall runScript(const QString &script)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                        QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
        m << script;
        return QDBusConnection::sessionBus().asyncCall(m);
    }

    // After an arrange write: plasmashell saves appletsrc on its own schedule, so read twice,
    // early and late; readItems only signals when something actually moved.
    void arrangeWritten()
    {
        QTimer::singleShot(400, this, [this] { readItems(); });
        QTimer::singleShot(1500, this, [this] { readItems(); });
    }

    void sendArrange(const QString &script)
    {
        auto *w = new QDBusPendingCallWatcher(runScript(script), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, w] {
            w->deleteLater();
            if (w->isError()) {
                qWarning().noquote() << "aether-desk: arrange script failed:" << w->error().message();
            }
            arrangeWritten();
        });
    }

    void applyFilter()
    {
        const bool wanted = m_clean;
        auto *w = new QDBusPendingCallWatcher(runScript(QString::fromLatin1(m_clean ? kHideScript : kShowScript)), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, wanted] {
            w->deleteLater();
            if (w->isError() && wanted == m_clean && ++m_attempts < 30) {
                m_retry.start();   // plasmashell not up yet (login) or restarting
            }
        });
    }

    // The desktop's entries in Folder View's current order (readGrid's sort), so the stand-ins
    // land in the cells the real icons will occupy: folders lead when sortDirsFirst says so,
    // then the key the panel picked - a natural, case-insensitive name (a .desktop file shows
    // its Name=), size, type or modified time.
    void readItems()
    {
        // Plasma replaced appletsrc on its last save and the watch died: re-arm.
        if (QFileInfo::exists(m_appletsRc) && !m_watcher.files().contains(m_appletsRc)) {
            m_watcher.addPath(m_appletsRc);
        }
        const QVariantMap g = readGrid();
        struct Entry { QString name, icon, type; bool dir; qint64 size; qint64 mtime; };
        QList<Entry> entries;
        const QString lang = QLocale().name().section(QLatin1Char('_'), 0, 0);
        QMimeDatabase mimes;
        const QFileInfoList list = QDir(m_desktopDir).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
        for (const QFileInfo &fi : list) {
            Entry e{ fi.fileName(), QString(), QString(), fi.isDir(), fi.size(), fi.lastModified().toSecsSinceEpoch() };
            if (fi.isDir()) {
                e.icon = QStringLiteral("folder");
                e.type = QStringLiteral("inode/directory");
                const QString dot = fi.absoluteFilePath() + QStringLiteral("/.directory");
                if (QFileInfo::exists(dot)) {
                    const QString ic = QSettings(dot, QSettings::IniFormat).value(QStringLiteral("Desktop Entry/Icon")).toString();
                    if (!ic.isEmpty()) {
                        e.icon = ic;
                    }
                }
            } else if (fi.suffix() == QLatin1String("desktop")) {
                QSettings d(fi.absoluteFilePath(), QSettings::IniFormat);
                d.beginGroup(QStringLiteral("Desktop Entry"));
                const QString n = d.value(QStringLiteral("Name[") + lang + QLatin1Char(']'), d.value(QStringLiteral("Name"))).toString();
                if (!n.isEmpty()) {
                    e.name = n;
                }
                e.icon = d.value(QStringLiteral("Icon"), QStringLiteral("application-x-executable")).toString();
                e.type = QStringLiteral("application/x-desktop");
            } else {
                const QMimeType mt = mimes.mimeTypeForFile(fi);
                e.type = mt.name();
                e.icon = QIcon::hasThemeIcon(mt.iconName()) ? mt.iconName() : mt.genericIconName();
            }
            entries << e;
        }
        QCollator coll;
        coll.setNumericMode(true);
        coll.setCaseSensitivity(Qt::CaseInsensitive);
        const int mode = g.value(QStringLiteral("sortMode")).toInt();   // KDirModel column: 0 name, 1 size, 2 date, 6 type; -1 manual
        const bool desc = g.value(QStringLiteral("sortDesc")).toBool();
        const bool dirsFirst = g.value(QStringLiteral("sortDirsFirst")).toBool() && mode != -1;
        std::stable_sort(entries.begin(), entries.end(), [&](const Entry &a, const Entry &b) {
            if (dirsFirst && a.dir != b.dir) {
                return a.dir;
            }
            bool eq, less;
            switch (mode) {
            case 1:  eq = a.size == b.size; less = a.size < b.size; break;
            case 6:  eq = a.type == b.type; less = coll.compare(a.type, b.type) < 0; break;
            case 2:  eq = a.mtime == b.mtime; less = a.mtime < b.mtime; break;
            default: eq = a.name == b.name; less = coll.compare(a.name, b.name) < 0; break;
            }
            return desc ? !eq && !less : less;   // ties keep the folder's own order
        });
        QVariantList out;
        for (const Entry &e : entries) {
            out << QVariantMap{ { QStringLiteral("name"), wrapPoints(e.name) }, { QStringLiteral("icon"), e.icon } };
        }
        if (out != m_items || g != m_grid) {
            m_items = out;
            m_grid = g;
            Q_EMIT itemsChanged();
        }
    }

    // Folder View shows names with break points (KStringHandler::preProcessWrap): a zero-width space
    // after punctuation and symbols, and between a lower-case letter and a capital, so the stand-ins'
    // labels wrap exactly where the real ones do.
    static QString wrapPoints(const QString &text)
    {
        const QChar zwsp(0x200B);
        QString out;
        for (int i = 0; i < text.length(); ++i) {
            const QChar c = text[i];
            const bool opening = c == QLatin1Char('(') || c == QLatin1Char('{') || c == QLatin1Char('[');
            const bool quote = c == QLatin1Char('\'');
            const bool last = i == text.length() - 1;
            if ((opening || quote) && i > 0) {
                out += zwsp;
            }
            out += c;
            const bool after = !opening && !quote && (c.isPunct() || c.isSymbol());
            if (!last && (after || (c.isLower() && text[i + 1].isUpper()))) {
                out += zwsp;
            }
        }
        return out;
    }

    // Folder View's icon settings for the primary screen's desktop, Plasma's defaults when unset.
    // appletsrc nests groups as [Containments][N][General], which QSettings cannot read, so by hand.
    QVariantMap readGrid() const
    {
        QVariantMap g{ { QStringLiteral("iconSize"), 3 }, { QStringLiteral("labelWidth"), 1 }, { QStringLiteral("textLines"), 2 },
                       { QStringLiteral("arrangement"), 0 }, { QStringLiteral("alignment"), 0 },
                       { QStringLiteral("sortMode"), -1 }, { QStringLiteral("sortDesc"), false },
                       { QStringLiteral("sortDirsFirst"), true } };
        QFile f(m_appletsRc);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return g;
        }
        static const QRegularExpression head(QStringLiteral("^\\[Containments\\]\\[(\\d+)\\](\\[General\\])?$"));
        QHash<QString, QHash<QString, QString>> top, general;
        QString id;
        bool inGeneral = false, inGroup = false;
        while (!f.atEnd()) {
            const QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (line.startsWith(QLatin1Char('['))) {
                const auto m = head.match(line);
                inGroup = m.hasMatch();
                id = m.captured(1);
                inGeneral = !m.captured(2).isEmpty();
                continue;
            }
            const int eq = line.indexOf(QLatin1Char('='));
            if (inGroup && eq > 0) {
                (inGeneral ? general : top)[id][line.left(eq)] = line.mid(eq + 1);
            }
        }
        QString pick;
        for (auto it = top.cbegin(); it != top.cend(); ++it) {
            if (it->value(QStringLiteral("plugin")) != QLatin1String("org.kde.plasma.folder")) {
                continue;
            }
            if (pick.isEmpty() || it->value(QStringLiteral("lastScreen")) == QLatin1String("0")) {
                pick = it.key();
            }
        }
        const auto conf = general.value(pick);
        for (auto it = g.begin(); it != g.end(); ++it) {
            if (!conf.contains(it.key())) {
                continue;
            }
            const QString v = conf.value(it.key());
            // KConfig writes bools as true/false in the ini, everything else as plain integers
            if (it.value().typeId() == QMetaType::Bool) {
                it.value() = (v == QLatin1String("true") || v == QLatin1String("1"));
            } else {
                it.value() = v.toInt();
            }
        }
        return g;
    }

    QQuickView *m_view;
    QString m_desktopDir, m_appletsRc;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce, m_retry;
    int m_attempts = 0;
    QVariantList m_items;
    QVariantMap m_grid;
    bool m_clean = false;
};

static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-desk/qml");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_QML_DIR);
}
static QString sharedDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether/shared");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_SHARED_DIR);
}

int main(int argc, char **argv)
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aether-desk"));

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    QScreen *screen = QGuiApplication::primaryScreen();
    view.setScreen(screen);
    view.resize(screen ? screen->size() : QSize(1920, 1080));

    auto *ls = LayerShellQt::Window::get(&view);
    ls->setLayer(LayerShellQt::Window::LayerBottom);   // over the desktop's icons, under every window
    ls->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                 | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    ls->setExclusiveZone(-1);   // the whole screen, like Folder View's grid
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    // KWin types this window by the scope (layershellv1window.cpp): "desktop" keeps it up through
    // Show Desktop, but KWin's blur refuses desktop-typed windows — "dock" keeps both: a dock also
    // shows through Show Desktop, and blur applies behind it.
    ls->setScope(QStringLiteral("dock"));

    view.engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    view.engine()->addImportPath(sharedDir());
    auto *desk = new DeskController(&view);
    view.rootContext()->setContextProperty(QStringLiteral("desk"), desk);
    view.setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Desk.qml")));
    if (view.status() == QQuickView::Error) {
        for (const auto &e : view.errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return 1;
    }
    view.show();

    // qdbus6 org.aether.Desk /Desk org.aether.Desk.Toggle
    auto session = QDBusConnection::sessionBus();
    session.registerService(QStringLiteral("org.aether.Desk"));
    session.registerObject(QStringLiteral("/Desk"), QStringLiteral("org.aether.Desk"), desk, QDBusConnection::ExportAllSlots);
    return app.exec();
}

#include "main.moc"
