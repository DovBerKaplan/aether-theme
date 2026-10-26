// aether-toasts: notification cards that drop from the top edge of the screen.
//
// A separate program from the island on purpose: it only *watches* org.freedesktop.Notifications
// (Plasma stays the notification server, so history and do-not-disturb keep working) and mutes
// Plasma's own banner while it runs. Quit it and Plasma's banners return.
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QCoreApplication>
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainterPath>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickView>
#include <QRegion>
#include <QScreen>
#include <QTimer>

#include <KWindowEffects>
#include <LayerShellQt/Window>

// Watches org.freedesktop.Notifications.Notify as a bus *monitor* (via busctl's JSON output),
// so Plasma keeps owning the notification server (history, do-not-disturb) while we only read.
class NotificationMonitor : public QObject
{
    Q_OBJECT
public:
    explicit NotificationMonitor(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_proc.setProgram(QStringLiteral("busctl"));
        m_proc.setArguments({QStringLiteral("--user"), QStringLiteral("monitor"), QStringLiteral("--json=short"),
                             QStringLiteral("--match"),
                             QStringLiteral("type='method_call',interface='org.freedesktop.Notifications',member='Notify'")});
        connect(&m_proc, &QProcess::readyReadStandardOutput, this, &NotificationMonitor::readLines);
        connect(&m_proc, &QProcess::finished, this, [this] { QTimer::singleShot(2000, this, [this] { m_proc.start(); }); });
        m_proc.start();

        // Plasma's own banner is muted by holding a do-not-disturb inhibition for as long as we
        // live; notifications still reach Plasma's history. The inhibition dies with Plasma's
        // notification server, so it is taken again whenever that server (re)appears.
        inhibit();
        auto *watcher = new QDBusServiceWatcher(QStringLiteral("org.freedesktop.Notifications"), QDBusConnection::sessionBus(),
                                                QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &, const QString &newOwner) {
            if (!newOwner.isEmpty()) {
                QTimer::singleShot(800, this, [this] { inhibit(); });
            }
        });
    }
    ~NotificationMonitor() override
    {
        m_proc.kill();
        m_proc.waitForFinished(500);
    }

Q_SIGNALS:
    void received(const QString &app, const QString &icon, const QString &summary, const QString &body, int urgency, int timeoutMs);

private:
    void inhibit()
    {
        QDBusInterface iface(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
                             QStringLiteral("org.freedesktop.Notifications"));
        QDBusReply<uint> cookie = iface.call(QStringLiteral("Inhibit"), QStringLiteral("aether-island"),
                                             QStringLiteral("The island shows notifications"), QVariantMap());
        if (cookie.isValid()) {
            m_cookie = cookie.value();
        }
    }
    void readLines()
    {
        m_buffer += m_proc.readAllStandardOutput();
        int nl;
        while ((nl = m_buffer.indexOf('\n')) >= 0) {
            const QByteArray line = m_buffer.left(nl).trimmed();
            m_buffer.remove(0, nl + 1);
            if (!line.isEmpty()) {
                handle(QJsonDocument::fromJson(line).object());
            }
        }
    }
    void handle(const QJsonObject &msg)
    {
        if (msg.value(QStringLiteral("member")).toString() != QLatin1String("Notify")) {
            return;
        }
        const QJsonArray d = msg.value(QStringLiteral("payload")).toObject().value(QStringLiteral("data")).toArray();
        if (d.size() < 8) {
            return;
        }
        const QJsonObject hints = d.at(6).toObject();
        QString icon = d.at(2).toString();
        if (icon.isEmpty()) {
            icon = hints.value(QStringLiteral("image-path")).toObject().value(QStringLiteral("data")).toString();
        }
        if (icon.isEmpty()) {
            icon = hints.value(QStringLiteral("desktop-entry")).toObject().value(QStringLiteral("data")).toString();
        }
        if (hints.value(QStringLiteral("transient")).toObject().value(QStringLiteral("data")).toBool()
            && d.at(1).toInt() != 0) {
            // progress-style updates (replaces_id set) would spam the stack; show only fresh ones
            return;
        }
        Q_EMIT received(d.at(0).toString(), icon, d.at(3).toString(), d.at(4).toString(),
                        hints.value(QStringLiteral("urgency")).toObject().value(QStringLiteral("data")).toInt(1),
                        d.at(7).toInt(-1));
    }

    QProcess m_proc;
    QByteArray m_buffer;
    uint m_cookie = 0;
};

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

class ToastsController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int screenWidth READ screenWidth CONSTANT)
    Q_PROPERTY(qreal bodyAlpha READ bodyAlpha CONSTANT)

public:
    explicit ToastsController(QQuickView *view)
        : QObject(view)
        , m_view(view)
    {
    }
    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    qreal bodyAlpha() const { return qEnvironmentVariableIsSet("AETHER_BODY_ALPHA") ? qEnvironmentVariable("AETHER_BODY_ALPHA").toDouble() : 0.75; }

    Q_INVOKABLE void setWindowHeight(int h)
    {
        if (h != m_view->height()) {
            m_view->resize(m_view->width(), h);
        }
    }
    // Cards as {x, y, w, h, r}: blur and input are limited to them, so clicks everywhere else
    // pass straight through to the windows below.
    Q_INVOKABLE void setCards(const QVariantList &cards)
    {
        QRegion region;
        for (const QVariant &c : cards) {
            const QVariantMap m = c.toMap();
            QPainterPath path;
            const QRectF r(m[QStringLiteral("x")].toReal(), m[QStringLiteral("y")].toReal(), m[QStringLiteral("w")].toReal(), m[QStringLiteral("h")].toReal());
            path.addRoundedRect(r, m[QStringLiteral("r")].toReal(), m[QStringLiteral("r")].toReal());
            region += QRegion(path.toFillPolygon().toPolygon());
        }
        if (region.isEmpty()) {
            KWindowEffects::enableBlurBehind(m_view, false);
            m_view->setMask(QRegion(0, 0, 1, 1));   // nothing to click
        } else {
            KWindowEffects::enableBlurBehind(m_view, true, region);
            m_view->setMask(region);
        }
    }

private:
    QQuickView *m_view;
};

// Installed copy first (~/.local/share/aether-toasts/qml next to ~/.local/bin), development tree as fallback.
static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-toasts/qml");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_QML_DIR);
}

// Shared QML module (AetherShared: Theme, card material, grain): installed next to the apps,
// development tree as fallback.
static QString sharedDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether/shared");
    return QDir(installed).exists() ? QDir(installed).canonicalPath() : QStringLiteral(AETHER_SHARED_DIR);
}

int main(int argc, char **argv)
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aether-toasts"));
    app.setDesktopFileName(QStringLiteral("aether-toasts"));

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint | Qt::WindowDoesNotAcceptFocus);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    const int w = view.screen() ? qMin(view.screen()->size().width(), 460) : 460;
    view.resize(w, 4);

    auto *ls = LayerShellQt::Window::get(&view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    ls->setAnchors(LayerShellQt::Window::AnchorTop);
    ls->setExclusiveZone(-1);
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(QStringLiteral("aether-toasts"));

    view.engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    ToastsController controller(&view);
    NotificationMonitor monitor;
    view.rootContext()->setContextProperty(QStringLiteral("toasts"), &controller);
    view.rootContext()->setContextProperty(QStringLiteral("notifications"), &monitor);

    view.engine()->addImportPath(sharedDir());
    view.setSource(QUrl::fromLocalFile(qmlDir() + QStringLiteral("/Toasts.qml")));
    if (view.status() == QQuickView::Error) {
        for (const auto &e : view.errors()) {
            fprintf(stderr, "%s\n", qPrintable(e.toString()));
        }
        return 1;
    }
    view.show();
    controller.setCards({});
    return app.exec();
}

#include "main.moc"
