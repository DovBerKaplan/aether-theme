// aether-island: frosted-glass capsule pinned to the top edge of the screen.
//
//  - hidden: an invisible 300x4 hot strip; nothing is drawn
//  - small:  the notch, merged into the top edge, when the pointer touches it
//  - large:  the full island after a click (the window then covers the screen so a
//            click anywhere outside the island can close it)
//
// The window is a layer-shell surface (overlay layer, anchored top). Its size follows the
// state so the input region always matches what is visible; KWin blurs behind the shape
// the QML side reports through setBlurShape().
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QIcon>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QFileSystemWatcher>
#include <QCoreApplication>
#include <QDir>
#include <QGuiApplication>
#include <QPainterPath>
#include <QQmlContext>
#include <QQuickView>
#include <QRegion>
#include <QTimer>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>

#include "MediaController.h"
#include "SystemInfo.h"

#include <KWindowEffects>
#include <LayerShellQt/Window>

static QRegion roundedRegion(const QRectF &r, qreal radius)
{
    QPainterPath path;
    path.addRoundedRect(r, radius, radius);
    return QRegion(path.toFillPolygon().toPolygon());
}

// image://icon/<theme-name or absolute path>
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
    }
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
                icon = QIcon::fromTheme(QStringLiteral("dialog-information"));
            }
            pm = icon.pixmap(px, px);
        }
        if (size) {
            *size = pm.size();
        }
        return pm;
    }
};

class IslandController : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Island")
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(int screenWidth READ screenWidth CONSTANT)
    Q_PROPERTY(int screenHeight READ screenHeight CONSTANT)
    Q_PROPERTY(qreal bodyAlpha READ bodyAlpha CONSTANT)

public:
    explicit IslandController(QQuickView *view)
        : QObject(view)
        , m_view(view)
    {
        m_kdeglobals = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
        m_watcher.addPath(m_kdeglobals);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
            m_watcher.addPath(path);   // editors replace the file, so re-arm the watch
            readScheme();
        });
        readScheme();
    }

    bool dark() const { return m_dark; }
    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }
    // AETHER_BODY_ALPHA lets us compare opacity levels while tuning the look.
    qreal bodyAlpha() const { return qEnvironmentVariableIsSet("AETHER_BODY_ALPHA") ? qEnvironmentVariable("AETHER_BODY_ALPHA").toDouble() : 0.75; }

    // Called from QML: resize the layer-shell surface.
    Q_INVOKABLE void setWindowSize(int w, int h)
    {
        if (QSize(w, h) != m_view->size()) {
            m_view->resize(w, h);
        }
    }

    // Called from QML whenever the shape changes. The silhouette arrives as path commands
    // (the same list NotchSurface.qml draws from), so blur, input and drawing can never disagree.
    //   cmds: [{t:"M"|"L"|"C", x, y, x1, y1, x2, y2}]   hot: invisible strip that still gets the pointer
    Q_INVOKABLE void setLayout(const QVariantList &cmds, bool fullInput, const QRectF &hot)
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
        if (shape.isEmpty()) {
            KWindowEffects::enableBlurBehind(m_view, false);
        } else {
            KWindowEffects::enableBlurBehind(m_view, true, shape);
        }
        // Input: only the visible shape (+ the hot strip), so clicks elsewhere reach other windows.
        // While the large island is open the whole window takes input, to catch click-outside.
        QRegion input = fullInput ? QRegion(QRect(QPoint(0, 0), m_view->size())) : shape;
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
    }

    // The two buttons in the notch. Search opens KRunner; power opens KDE's own shutdown screen
    // (shut down / restart / log out), which asks for confirmation instead of acting at once.
    Q_INVOKABLE void openSearch()
    {
        QDBusInterface i(QStringLiteral("org.kde.krunner"), QStringLiteral("/App"), QStringLiteral("org.kde.krunner.App"));
        i.asyncCall(QStringLiteral("toggleDisplay"));
    }
    Q_INVOKABLE void openPowerMenu()
    {
        QDBusInterface i(QStringLiteral("org.kde.LogoutPrompt"), QStringLiteral("/LogoutPrompt"), QStringLiteral("org.kde.LogoutPrompt"));
        i.asyncCall(QStringLiteral("promptAll"));
    }

    Q_INVOKABLE void setKeyboard(bool wanted)
    {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                : LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }

public Q_SLOTS:
    // org.aether.Island - also lets a keyboard shortcut or a script drive the island.
    void Peek() { Q_EMIT stateRequested(QStringLiteral("small")); }
    void Expand() { Q_EMIT stateRequested(QStringLiteral("large")); }
    void Hide() { Q_EMIT stateRequested(QStringLiteral("hidden")); }
    void Toggle() { Q_EMIT stateRequested(QStringLiteral("toggle")); }

Q_SIGNALS:
    void darkChanged();
    void stateRequested(const QString &state);

private:
    void readScheme()
    {
        QSettings kde(m_kdeglobals, QSettings::IniFormat);
        const QString scheme = kde.value(QStringLiteral("General/ColorScheme")).toString();
        // AetherSerenity is our light scheme; everything else counts as dark.
        const bool dark = !scheme.contains(QLatin1String("Serenity"), Qt::CaseInsensitive)
            && !scheme.contains(QLatin1String("Light"), Qt::CaseInsensitive);
        if (dark != m_dark) {
            m_dark = dark;
            Q_EMIT darkChanged();
        }
    }

    QQuickView *m_view;
    QFileSystemWatcher m_watcher;
    QString m_kdeglobals;
    bool m_dark = true;
};

// Installed copy first (~/.local/share/aether-island/qml next to ~/.local/bin), development tree as fallback.
static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-island/qml");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_QML_DIR);
}

int main(int argc, char **argv)
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aether-island"));
    app.setDesktopFileName(QStringLiteral("aether-island"));

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(300, 4);

    auto *ls = LayerShellQt::Window::get(&view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    ls->setAnchors(LayerShellQt::Window::AnchorTop);   // anchored to top only: centred horizontally
    ls->setExclusiveZone(-1);                          // never push other surfaces around
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(QStringLiteral("aether-island"));

    view.engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    MediaController media;
    view.rootContext()->setContextProperty(QStringLiteral("media"), &media);
    SystemInfo system;
    view.rootContext()->setContextProperty(QStringLiteral("system"), &system);
    IslandController controller(&view);
    view.rootContext()->setContextProperty(QStringLiteral("island"), &controller);

    auto bus = QDBusConnection::sessionBus();
    bus.registerService(QStringLiteral("org.aether.Island"));
    bus.registerObject(QStringLiteral("/Island"), &controller, QDBusConnection::ExportAllSlots);

    view.setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Island.qml")));
    if (view.status() == QQuickView::Error) {
        for (const auto &e : view.errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return 1;
    }
    view.show();
    return app.exec();
}

#include "main.moc"
