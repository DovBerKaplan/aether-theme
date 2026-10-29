// aether-dock: the app dock as two layer-shell surfaces, one on the bottom edge and one on the
// left edge. Both are hidden at rest (a 2px invisible strip that listens for the pointer);
// touching an edge springs that edge's glass pill out, leaving retracts it. Only one is open at
// a time. The pill is drawn by Dock.qml in the island's material; blur and input follow the
// shape QML reports through setLayout().
#include <QColor>
#include <QCoreApplication>
#include <QDebug>
#include <QDBusConnection>
#include <QDir>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QTimer>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QIcon>
#include <QPainterPath>
#include <QProcess>
#include <QLocale>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickView>
#include <QRegion>
#include <QRegularExpression>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>

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
        }
        if (pm.isNull()) {
            QIcon icon = QIcon::fromTheme(id);
            if (icon.isNull()) {
                icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
            }
            pm = icon.pixmap(px, px);
        }
        if (size) {
            *size = pm.size();
        }
        return pm;
    }
};

class DockController : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Dock")
    Q_PROPERTY(QString edge READ edge CONSTANT)
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(QColor accentOverride READ accentOverride NOTIFY accentChanged)
    Q_PROPERTY(int screenWidth READ screenWidth CONSTANT)
    Q_PROPERTY(int screenHeight READ screenHeight CONSTANT)
    Q_PROPERTY(QStringList launchers READ launchers WRITE setLaunchers NOTIFY launchersChanged)
    Q_PROPERTY(bool allAtStart READ allAtStart WRITE setAllAtStart NOTIFY allAtStartChanged)

public:
    DockController(QQuickView *view, const QString &edge)
        : QObject(view), m_view(view), m_edge(edge)
    {
        m_kdeglobals = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
        m_islandRc = QDir::homePath() + QStringLiteral("/.config/aetherislandrc");
        m_watcher.addPath(m_kdeglobals);
        m_watcher.addPath(m_islandRc);
        // A scheme switch rewrites kdeglobals in several steps (and KDE replaces the file), so the
        // change is read once things have settled, and the watch is re-armed afterwards. A slow poll
        // is the safety net for a watch that got lost with the replaced file.
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] {
            for (const QString &f : { m_kdeglobals, m_islandRc }) {
                if (!m_watcher.files().contains(f)) {
                    m_watcher.addPath(f);
                }
            }
            readScheme();
            readAccent();
        });
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
        m_poll.setInterval(2000);
        connect(&m_poll, &QTimer::timeout, this, [this] {
            const QDateTime t = qMax(QFileInfo(m_kdeglobals).lastModified(), QFileInfo(m_islandRc).lastModified());
            if (t != m_lastModified) {
                m_lastModified = t;
                m_debounce.start();
            }
        });
        m_poll.start();
        m_lastModified = qMax(QFileInfo(m_kdeglobals).lastModified(), QFileInfo(m_islandRc).lastModified());
        readScheme();
        readAccent();
    }
    bool dark() const { return m_dark; }
    QColor accentOverride() const { return m_accent; }
    QString edge() const { return m_edge; }
    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }

    // Pinned apps live in ~/.config/aetherdockrc (shared by both edges).
    QStringList launchers() const
    {
        QSettings s(configPath(), QSettings::IniFormat);
        const QStringList l = s.value(QStringLiteral("General/launchers")).toStringList();
        return l.isEmpty() ? defaults() : l;
    }
    void setLaunchers(const QStringList &l)
    {
        QSettings s(configPath(), QSettings::IniFormat);
        s.setValue(QStringLiteral("General/launchers"), l);
        Q_EMIT launchersChanged();
    }

    // Which end of the row carries the show-desktop dots (dragged there with a long press).
    bool allAtStart() const
    {
        return QSettings(configPath(), QSettings::IniFormat).value(QStringLiteral("General/allAtStart"), false).toBool();
    }
    void setAllAtStart(bool v)
    {
        QSettings(configPath(), QSettings::IniFormat).setValue(QStringLiteral("General/allAtStart"), v);
        Q_EMIT allAtStartChanged();
    }

    Q_INVOKABLE void setWindowSize(int w, int h)
    {
        if (QSize(w, h) != m_view->size()) {
            m_view->resize(w, h);
        }
    }

    // The silhouette arrives as path commands (the same list Dock.qml draws from), so blur, input and
    // drawing cannot disagree. hot: invisible strip that still gets the pointer.
    //   cmds: [{t:"M"|"L"|"C", x, y, x1, y1, x2, y2}]
    Q_INVOKABLE void setLayout(const QVariantList &cmds, const QRectF &hot, const QVariantList &popups)
    {
        QPainterPath p;
        for (const QVariant &v : cmds) {
            const QVariantMap c = v.toMap();
            const QString t = c.value(QStringLiteral("t")).toString();
            if (t == QLatin1String("M")) {
                p.moveTo(c[QStringLiteral("x")].toReal(), c[QStringLiteral("y")].toReal());
            } else if (t == QLatin1String("L")) {
                p.lineTo(c[QStringLiteral("x")].toReal(), c[QStringLiteral("y")].toReal());
            } else if (t == QLatin1String("C")) {
                p.cubicTo(c[QStringLiteral("x1")].toReal(), c[QStringLiteral("y1")].toReal(), c[QStringLiteral("x2")].toReal(),
                          c[QStringLiteral("y2")].toReal(), c[QStringLiteral("x")].toReal(), c[QStringLiteral("y")].toReal());
            }
        }
        p.closeSubpath();
        QRegion shape;
        if (!cmds.isEmpty()) {
            shape = QRegion(p.toFillPolygon().toPolygon());
        }
        // Tooltip and menu cards: blurred like the glass and live for the pointer.
        for (const QVariant &v : popups) {
            const QVariantMap m = v.toMap();
            QPainterPath pp;
            const qreal r = m.value(QStringLiteral("r")).toReal();
            pp.addRoundedRect(QRectF(m.value(QStringLiteral("x")).toReal(), m.value(QStringLiteral("y")).toReal(),
                                     m.value(QStringLiteral("w")).toReal(), m.value(QStringLiteral("h")).toReal()), r, r);
            shape += QRegion(pp.toFillPolygon().toPolygon());
        }
        KWindowEffects::enableBlurBehind(m_view, !shape.isEmpty(), shape);
        QRegion input = shape;
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
    }

    // The app's own quick actions (a desktop file's [Desktop Action ...] groups: "New Private Window" ...).
    Q_INVOKABLE QVariantList appActions(const QString &desktopId) const
    {
        QVariantList out;
        const QString path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, desktopId);
        if (path.isEmpty()) {
            return out;
        }
        QSettings f(path, QSettings::IniFormat);
        const QStringList ids = f.value(QStringLiteral("Desktop Entry/Actions")).toString().split(QLatin1Char(';'), Qt::SkipEmptyParts);
        const QString lang = QLocale().name().section(QLatin1Char('_'), 0, 0);
        for (const QString &id : ids.mid(0, 4)) {
            const QString g = QStringLiteral("Desktop Action ") + id + QLatin1Char('/');
            QString name = f.value(g + QStringLiteral("Name[") + lang + QLatin1Char(']')).toString();
            if (name.isEmpty()) {
                name = f.value(g + QStringLiteral("Name")).toString();
            }
            const QString exec = f.value(g + QStringLiteral("Exec")).toString();
            if (!name.isEmpty() && !exec.isEmpty()) {
                out << QVariantMap{ { QStringLiteral("name"), name }, { QStringLiteral("exec"), exec } };
            }
        }
        return out;
    }
    Q_INVOKABLE void runExec(const QString &exec)
    {
        QString cmd = exec;
        cmd.remove(QRegularExpression(QStringLiteral("%[a-zA-Z]")));   // field codes (%U, %F ...) mean "no files"
        QStringList parts = QProcess::splitCommand(cmd.trimmed());
        if (!parts.isEmpty()) {
            const QString prog = parts.takeFirst();
            QProcess::startDetached(prog, parts);
        }
    }

    // Opening one edge closes the other.
    Q_INVOKABLE void notifyShown() { Q_EMIT shownOnEdge(m_edge); }

public Q_SLOTS:
    void Show() { Q_EMIT stateRequested(QStringLiteral("shown")); }
    void Hide() { Q_EMIT stateRequested(QStringLiteral("hidden")); }

Q_SIGNALS:
    void launchersChanged();
    void allAtStartChanged();
    void darkChanged();
    void accentChanged();
    void stateRequested(const QString &state);
    void shownOnEdge(const QString &edge);

private:
    static QString configPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aetherdockrc");
    }
    static QStringList defaults()
    {
        return { QStringLiteral("applications:zcode.desktop"), QStringLiteral("applications:com.anthropic.Claude.desktop"),
                 QStringLiteral("applications:google-chrome.desktop"), QStringLiteral("applications:com.microsoft.VSCode.desktop"),
                 QStringLiteral("applications:org.kde.dolphin.desktop"), QStringLiteral("applications:org.kde.konsole.desktop") };
    }

    // The colour the user picked in the island's colour panel (~/.config/aetherislandrc [Appearance]).
    // Transparent means "none chosen": Theme falls back to the theme's own accent.
    void readAccent()
    {
        QSettings s(m_islandRc, QSettings::IniFormat);
        QColor c(Qt::transparent);
        if (s.value(QStringLiteral("Appearance/AccentSet")).toBool()) {
            const qreal hue = qBound(0, s.value(QStringLiteral("Appearance/AccentHue"), 183).toInt(), 359) / 360.0;
            const qreal light = qBound(0.25, s.value(QStringLiteral("Appearance/AccentLight"), 0.5).toDouble(), 0.8);
            const qreal sat = qBound(0.15, s.value(QStringLiteral("Appearance/AccentSat"), 1.0).toDouble(), 1.0);
            c = QColor::fromHslF(hue, sat, light);
        }
        if (c != m_accent) {
            m_accent = c;
            Q_EMIT accentChanged();
        }
    }

    void readScheme()
    {
        // kdeglobals is read by hand (QSettings finds nothing in it). The scheme *name* is not always
        // written (it is omitted when it equals the theme's default), so light or dark is judged from
        // the window background colour the scheme actually installed.
        bool dark = true;
        QFile f(m_kdeglobals);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool inWindow = false;
            while (!f.atEnd()) {
                const QString line = QString::fromUtf8(f.readLine()).trimmed();
                if (line.startsWith(QLatin1Char('['))) {
                    inWindow = line == QLatin1String("[Colors:Window]");
                } else if (inWindow && line.startsWith(QLatin1String("BackgroundNormal="))) {
                    const QStringList c = line.mid(17).split(QLatin1Char(','));
                    if (c.size() >= 3) {
                        dark = (0.299 * c[0].toInt() + 0.587 * c[1].toInt() + 0.114 * c[2].toInt()) < 128;
                    }
                    break;
                }
            }
        }
        if (dark != m_dark) {
            m_dark = dark;
            Q_EMIT darkChanged();
        }
    }

    QQuickView *m_view;
    QString m_edge;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_poll;
    QDateTime m_lastModified;
    QString m_kdeglobals;
    QString m_islandRc;
    QColor m_accent = QColor(Qt::transparent);
    bool m_dark = true;
};

// Exported as org.aether.Dock so a shortcut or script can drive the dock:
//   qdbus6 org.aether.Dock /Dock org.aether.Dock.Show bottom
class DockBus : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Dock")
public:
    DockBus(DockController *bottom, DockController *left) : m_bottom(bottom), m_left(left) {}
public Q_SLOTS:
    void Show(const QString &edge) { (edge == QLatin1String("left") ? m_left : m_bottom)->Show(); }
    void Hide() { m_bottom->Hide(); m_left->Hide(); }
    void Toggle() { m_bottom->Show(); }
private:
    DockController *m_bottom;
    DockController *m_left;
};

static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-dock/qml");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_QML_DIR);
}
static QString sharedDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether/shared");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_SHARED_DIR);
}

static DockController *makeView(const QString &edge)
{
    auto *view = new QQuickView;
    view->setColor(Qt::transparent);
    view->setFlags(Qt::FramelessWindowHint);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    const bool left = edge == QLatin1String("left");
    view->resize(left ? 10 : 1920, left ? 1080 : 10);

    auto *ls = LayerShellQt::Window::get(view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    ls->setAnchors(left ? LayerShellQt::Window::AnchorLeft : LayerShellQt::Window::AnchorBottom);
    ls->setExclusiveZone(0);   // never reserve edge space: apps keep the full screen
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(QStringLiteral("aether-dock-") + edge);

    view->engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    view->engine()->addImportPath(sharedDir());
    auto *controller = new DockController(view, edge);
    view->rootContext()->setContextProperty(QStringLiteral("dock"), controller);
    view->setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Dock.qml")));
    if (view->status() == QQuickView::Error) {
        for (const auto &e : view->errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return nullptr;
    }
    view->show();
    return controller;
}

int main(int argc, char **argv)
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aether-dock"));
    // KWin grants org_kde_plasma_window_management by this desktop-file id (see org.aether.dock.desktop.in).
    app.setDesktopFileName(QStringLiteral("org.aether.dock"));

    auto *bottom = makeView(QStringLiteral("bottom"));
    auto *left = makeView(QStringLiteral("left"));
    if (!bottom || !left) {
        return 1;
    }
    QObject::connect(bottom, &DockController::shownOnEdge, left, &DockController::Hide);
    QObject::connect(left, &DockController::shownOnEdge, bottom, &DockController::Hide);
    // Pins and the dots' side edited on one edge reach the other. The guard keeps the two
    // forwards from echoing each other forever.
    static bool forwarding = false;
    auto link = [](DockController *a, DockController *b, void (DockController::*sig)()) {
        QObject::connect(a, sig, b, [b, sig] {
            if (forwarding) {
                return;
            }
            forwarding = true;
            Q_EMIT (b->*sig)();
            forwarding = false;
        });
    };
    link(bottom, left, &DockController::launchersChanged);
    link(left, bottom, &DockController::launchersChanged);
    link(bottom, left, &DockController::allAtStartChanged);
    link(left, bottom, &DockController::allAtStartChanged);

    DockBus bus(bottom, left);
    auto session = QDBusConnection::sessionBus();
    session.registerService(QStringLiteral("org.aether.Dock"));
    session.registerObject(QStringLiteral("/Dock"), &bus, QDBusConnection::ExportAllSlots);
    return app.exec();
}

#include "main.moc"
