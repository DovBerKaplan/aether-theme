// aether-console: the connection shelf, a layer-shell column on the right edge of the screen.
//
//  at rest: only a small "ear" at the top-right corner is visible (and clickable)
//  open:    the 400px glass shelf slides out of the right edge; the window spans the whole
//           screen so a click anywhere outside can close it
//
// The shelf is the view; the sessions live on the servers (tmux) - closing, crashing or
// rebooting costs nothing. ConsoleController owns the surface, SessionStore/Discovery/Launcher
// the data.
#include <QDBusConnection>
#include <QDir>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQml>

#include "ConsoleController.h"
#include "Discovery.h"
#include "Launcher.h"
#include "LogStream.h"
#include "Metrics.h"
#include "SessionStore.h"
#include "Sftp.h"

static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-console/qml");
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
    app.setApplicationName(QStringLiteral("aether-console"));
    // KWin grants org_kde_kwin_blur by this desktop-file id (see org.aether.console.desktop.in).
    app.setDesktopFileName(QStringLiteral("org.aether.console"));

    auto *view = new QQuickView;
    view->setColor(Qt::transparent);
    view->setFlags(Qt::FramelessWindowHint);
    view->setResizeMode(QQuickView::SizeRootObjectToView);

    auto *ls = LayerShellQt::Window::get(view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    // this layer-shell-qt build declares Anchor without the QFlags operators: assemble explicitly
    ls->setAnchors(QFlags<LayerShellQt::Window::Anchor>(LayerShellQt::Window::AnchorRight
                                                        | LayerShellQt::Window::AnchorTop
                                                        | LayerShellQt::Window::AnchorBottom));
    ls->setExclusiveZone(0);   // never reserve edge space: apps keep the full screen
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(QStringLiteral("aether-console"));

    view->engine()->addImportPath(sharedDir());
    // "ctl", not "console": the QML engine already owns `console` as a JavaScript global.
    auto *controller = new ConsoleController(view);
    view->rootContext()->setContextProperty(QStringLiteral("ctl"), controller);
    auto *store = new SessionStore(controller);
    auto *discovery = new Discovery(store);
    auto *launcher = new Launcher(store);
    view->rootContext()->setContextProperty(QStringLiteral("store"), store);
    view->rootContext()->setContextProperty(QStringLiteral("discovery"), discovery);
    view->rootContext()->setContextProperty(QStringLiteral("launcher"), launcher);
    // One backend per view (every split pane polls, tails and browses on its own).
    qmlRegisterType<Metrics>("AetherConsole", 1, 0, "Metrics");
    qmlRegisterType<LogStream>("AetherConsole", 1, 0, "LogStream");
    qmlRegisterType<Sftp>("AetherConsole", 1, 0, "Sftp");
    // live-test fixture, like the island's AETHER_ISLAND_FAKE_BT: AETHER_CONSOLE_TEST_DETAIL=cont|session
    view->rootContext()->setContextProperty(QStringLiteral("testDetail"),
                                             qEnvironmentVariable("AETHER_CONSOLE_TEST_DETAIL"));
    view->setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Console.qml")));
    if (view->status() == QQuickView::Error) {
        for (const auto &e : view->errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return 1;
    }
    view->show();

    auto session = QDBusConnection::sessionBus();
    session.registerService(QStringLiteral("org.aether.Console"));
    session.registerObject(QStringLiteral("/Console"), controller, QDBusConnection::ExportAllSlots);
    return app.exec();
}

#include "main.moc"
