// aether-lens: circle to search for the desktop.
//
// A resident program that stays hidden until asked (Win+G, a long press on the dock's glass, or
// DBus org.aether.Lens /Lens Activate). Then it freezes the screen into a full-screen overlay:
// circle or tap something to search it on Google, send it to Google Lens, translate or copy it.
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFont>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QUrl>

#include <LayerShellQt/Window>

#include "LensController.h"

class LensBus : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Lens")
public:
    explicit LensBus(LensController *c) : QObject(c), m_c(c) {}
public Q_SLOTS:
    // Queued: the caller's DBus call returns at once, the capture runs on the next turn.
    void Activate() { ActivateFrom(QString(), 0.5); }
    // The dock's grab line: edge ('bottom' | 'left') and the fraction along it where it sits.
    void ActivateFrom(const QString &edge, double frac)
    {
        QMetaObject::invokeMethod(m_c, [c = m_c, edge, frac] { c->activate(edge, frac); }, Qt::QueuedConnection);
    }
    void Hide() { m_c->requestClose(); }
    // Translate the whole screen in place (what the top-right button does), for scripting and tests.
    void TranslateScreen() { m_c->requestTranslate(); }
    void Toggle()
    {
        if (m_c->isShown()) {
            m_c->requestClose();
        } else {
            Activate();
        }
    }
private:
    LensController *m_c;
};

// Installed copy first (~/.local/share/aether-lens/qml next to ~/.local/bin), development tree as fallback.
static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-lens/qml");
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
    app.setApplicationName(QStringLiteral("aether-lens"));
    // KWin hands out screenshots only to clients whose desktop file asks (org.aether.lens.desktop.in).
    app.setDesktopFileName(QStringLiteral("org.aether.lens"));
    app.setQuitOnLastWindowClosed(false);
    // Inter has no Hebrew: fall back to Noto Sans Hebrew, as the island does.
    QFont::insertSubstitution(QStringLiteral("Inter"), QStringLiteral("Noto Sans Hebrew"));

    auto session = QDBusConnection::sessionBus();
    const bool activateNow = app.arguments().contains(QStringLiteral("--activate"));
    if (session.interface()->isServiceRegistered(QStringLiteral("org.aether.Lens"))) {
        // Already running: hand the request over and leave.
        session.call(QDBusMessage::createMethodCall(QStringLiteral("org.aether.Lens"), QStringLiteral("/Lens"),
                                                    QStringLiteral("org.aether.Lens"), QStringLiteral("Activate")));
        return 0;
    }

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);

    auto *ls = LayerShellQt::Window::get(&view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    ls->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                 | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    ls->setExclusiveZone(-1);   // over everything, panels included
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    ls->setScope(QStringLiteral("aether-lens"));

    auto *controller = new LensController(&view);
    view.engine()->addImageProvider(QStringLiteral("lens"), new LensImageProvider(controller));
    view.engine()->addImportPath(sharedDir());
    view.rootContext()->setContextProperty(QStringLiteral("lens"), controller);
    view.setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Lens.qml")));
    if (view.status() == QQuickView::Error) {
        for (const auto &e : view.errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return 1;
    }

    LensBus bus(controller);
    session.registerService(QStringLiteral("org.aether.Lens"));
    session.registerObject(QStringLiteral("/Lens"), &bus, QDBusConnection::ExportAllSlots);
    if (activateNow) {
        bus.Activate();
    }
    return app.exec();
}

#include "main.moc"
