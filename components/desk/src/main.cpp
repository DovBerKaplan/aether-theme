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
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QDirIterator>
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
#include <QtMath>

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <BackdropSampler.h>

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

// Folder View draws every desktop label white with a black shadow, on any wallpaper. A local copy
// of its package (KPackage prefers ~/.local/share over /usr/share) swaps the label for
// AetherInkLabel, which inks it black or white for the wallpaper under it. The copy is rebuilt
// whenever the system package or our label changes (a Plasma update), and taken away when the
// label it patches is no longer there, so the desktop falls back to Plasma's own and never breaks.
// plasmashell reads the package when it starts.
static void ensureInkLabels(const QString &assets)
{
    const QString system = QStringLiteral("/usr/share/plasma/plasmoids/org.kde.desktopcontainment");
    const QString local = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/plasma/plasmoids/org.kde.desktopcontainment");
    const QString stampPath = local + QStringLiteral("/.aether-ink");
    const QStringList ours{ QStringLiteral("AetherInkLabel.qml"), QStringLiteral("ink.frag.qsb") };
    const QString delegate = QStringLiteral("/contents/ui/FolderItemDelegate.qml");
    if (QFileInfo::exists(local) && !QFileInfo::exists(stampPath)) {
        qInfo() << "ink labels: a desktop containment override that is not ours is in place; leaving it";
        return;
    }
    if (!QFileInfo::exists(system + delegate)) {
        return;
    }

    QCryptographicHash hash(QCryptographicHash::Sha1);
    QStringList files;
    QDirIterator it(system, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        files << it.next().mid(system.size());
    }
    files.sort();
    for (const QString &f : files) {
        QFile in(system + f);
        if (in.open(QIODevice::ReadOnly)) {
            hash.addData(f.toUtf8());
            hash.addData(in.readAll());
        }
    }
    for (const QString &f : ours) {
        QFile in(assets + QLatin1Char('/') + f);
        if (!in.open(QIODevice::ReadOnly)) {
            qWarning() << "ink labels: missing" << in.fileName();
            return;
        }
        hash.addData(in.readAll());
    }
    const QByteArray stamp = hash.result().toHex();
    QFile old(stampPath);
    if (old.open(QIODevice::ReadOnly) && old.readAll().trimmed() == stamp) {
        return;   // current
    }

    QFile src(system + delegate);
    src.open(QIODevice::ReadOnly);
    QString qml = QString::fromUtf8(src.readAll());
    const QString from = QStringLiteral("PlasmaExtras.ShadowedLabel {");
    if (qml.count(from) != 1) {
        qWarning() << "ink labels: Folder View's label is not where it was; using Plasma's own";
        QDir(local).removeRecursively();
        return;
    }
    qml.replace(from, QStringLiteral("AetherInkLabel {"));

    QDir(local).removeRecursively();
    for (const QString &f : files) {
        QDir().mkpath(QFileInfo(local + f).path());
        QFile::copy(system + f, local + f);
    }
    QFile out(local + delegate);
    out.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        QDir(local).removeRecursively();
        return;
    }
    out.write(qml.toUtf8());
    out.close();
    for (const QString &f : ours) {
        QFile::copy(assets + QLatin1Char('/') + f, local + QStringLiteral("/contents/ui/") + f);
    }
    QFile st(stampPath);
    st.open(QIODevice::WriteOnly);
    st.write(stamp + '\n');
    qInfo() << "ink labels: desktop containment written to" << local << "(plasmashell picks it up when it starts)";
}

class DeskController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantMap grid READ grid NOTIFY itemsChanged)
    Q_PROPERTY(bool clean READ clean NOTIFY cleanChanged)
    // Per stand-in, in `items` order: true where the desktop under its label is bright, so it
    // takes black ink like the real label (AetherInkLabel) will.
    Q_PROPERTY(QVariantList ink READ ink NOTIFY inkChanged)

public:
    explicit DeskController(QQuickView *view)
        : QObject(view), m_view(view)
    {
        m_desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        m_appletsRc = QDir::homePath() + QStringLiteral("/.config/plasma-org.kde.plasma.desktop-appletsrc");
        m_clean = QSettings(configPath(), QSettings::IniFormat).value(QStringLiteral("Desk/Clean"), false).toBool();

        // The desktop folder is watched for files coming and going (debounced, re-armed).
        m_watcher.addPath(m_desktopDir);
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] {
            if (QFileInfo::exists(m_desktopDir) && !m_watcher.directories().contains(m_desktopDir)) {
                m_watcher.addPath(m_desktopDir);
            }
            readItems();
        });
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });

        m_retry.setSingleShot(true);
        m_retry.setInterval(2000);
        connect(&m_retry, &QTimer::timeout, this, [this] { applyFilter(); });

        readItems();
        applyFilter();   // bring Folder View in line with the remembered state (plasmashell may still be starting)
    }

    QVariantList items() const { return m_items; }
    QVariantMap grid() const { return m_grid; }
    bool clean() const { return m_clean; }
    QVariantList ink() const { return m_ink; }

    // One shot of the desktop over all the labels' rects (this window's coordinates), a luma for
    // each. Asked when the pointer comes to the button, so the answer is in by the click. Text
    // pixels are left out of the mean: the real labels may be showing in those rects.
    Q_INVOKABLE void sampleInk(const QVariantList &rects)
    {
        if (m_inkBusy || rects.isEmpty()) {
            return;
        }
        const QPoint origin = m_view->screen() ? m_view->screen()->geometry().topLeft() : QPoint();
        QList<QRect> rs;
        QRect all;
        for (const QVariant &v : rects) {
            const QRect r = v.toRectF().toAlignedRect().translated(origin);
            rs << r;
            all |= r;
        }
        m_inkBusy = BackdropSampler::capture(this, all, [this, rs, all](const QImage &img) {
            m_inkBusy = false;
            if (img.isNull()) {
                return;
            }
            const double sx = double(img.width()) / all.width(), sy = double(img.height()) / all.height();
            QVariantList out;
            for (const QRect &r : rs) {
                const QRect local = r.translated(-all.topLeft());
                const QRect px(qFloor(local.x() * sx), qFloor(local.y() * sy), qCeil(local.width() * sx), qCeil(local.height() * sy));
                out << (BackdropSampler::meanLuma(img, px, true) > 0.56);   // the label shader's midpoint
            }
            if (out != m_ink) {
                m_ink = out;
                Q_EMIT inkChanged();
            }
        });
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

    // The button's glass: blurred behind and the only part of the surface that takes the pointer.
    Q_INVOKABLE void setButtonRect(const QRectF &r, qreal radius)
    {
        QPainterPath p;
        p.addRoundedRect(r, radius, radius);
        const QRegion shape(p.toFillPolygon().toPolygon());
        KWindowEffects::enableBlurBehind(m_view, !shape.isEmpty(), shape);
        m_view->setMask(shape.isEmpty() ? QRegion(0, 0, 1, 1) : shape);
    }

public Q_SLOTS:
    void Toggle() { Q_EMIT toggleRequested(); }

Q_SIGNALS:
    void itemsChanged();
    void cleanChanged();
    void inkChanged();
    void toggleRequested();

private:
    static QString configPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aetherdeskrc");
    }

    void applyFilter()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                                                        QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
        m << QString::fromLatin1(m_clean ? kHideScript : kShowScript);
        const bool wanted = m_clean;
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(m), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, wanted] {
            w->deleteLater();
            if (w->isError() && wanted == m_clean && ++m_attempts < 30) {
                m_retry.start();   // plasmashell not up yet (login) or restarting
            }
        });
    }

    // The desktop's entries in Folder View's default order: folders first, then a natural,
    // case-insensitive sort by the shown name (a .desktop file shows its Name=).
    void readItems()
    {
        struct Entry { QString name, icon; bool dir; };
        QList<Entry> entries;
        const QString lang = QLocale().name().section(QLatin1Char('_'), 0, 0);
        QMimeDatabase mimes;
        const QFileInfoList list = QDir(m_desktopDir).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
        for (const QFileInfo &fi : list) {
            Entry e{ fi.fileName(), QString(), fi.isDir() };
            if (fi.isDir()) {
                e.icon = QStringLiteral("folder");
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
            } else {
                const QMimeType mt = mimes.mimeTypeForFile(fi);
                e.icon = QIcon::hasThemeIcon(mt.iconName()) ? mt.iconName() : mt.genericIconName();
            }
            entries << e;
        }
        QCollator coll;
        coll.setNumericMode(true);
        coll.setCaseSensitivity(Qt::CaseInsensitive);
        std::stable_sort(entries.begin(), entries.end(), [&coll](const Entry &a, const Entry &b) {
            if (a.dir != b.dir) {
                return a.dir;
            }
            return coll.compare(a.name, b.name) < 0;
        });
        QVariantList out;
        for (const Entry &e : entries) {
            out << QVariantMap{ { QStringLiteral("name"), wrapPoints(e.name) }, { QStringLiteral("icon"), e.icon } };
        }
        const QVariantMap g = readGrid();
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
                       { QStringLiteral("arrangement"), 0 }, { QStringLiteral("alignment"), 0 } };
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
            if (conf.contains(it.key())) {
                it.value() = conf.value(it.key()).toInt();
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
    QVariantList m_ink;
    bool m_inkBusy = false;
    bool m_clean = false;
};

static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-desk/qml");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_QML_DIR);
}
static QString folderviewDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-desk/folderview");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_FOLDERVIEW_DIR);
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
    ensureInkLabels(folderviewDir());

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
