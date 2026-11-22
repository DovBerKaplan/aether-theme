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
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QFile>
#include <QIcon>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QFileSystemWatcher>
#include <QCoreApplication>
#include <QDir>
#include <QFont>
#include <QGuiApplication>
#include <QPainterPath>
#include <QQmlContext>
#include <QQuickView>
#include <QRegion>
#include <QTimer>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#include "AudioLevels.h"
#include "MediaController.h"
#include "PrefsGuard.h"
#include "NotificationStore.h"
#include "AudioModel.h"
#include "ConnectInput.h"
#include "ConnectModel.h"
#include "BluetoothModel.h"
#include "NetworkModel.h"
#include "TetherController.h"
#include "SystemPanels.h"
#include "TileStore.h"
#include "ThemeBus.h"
#include "GlyphStore.h"
#include "SystemInfo.h"
#include "SearchEngine.h"

#include <BackdropSampler.h>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <NotificationIcon.h>

static QRegion roundedRegion(const QRectF &r, qreal radius)
{
    QPainterPath path;
    path.addRoundedRect(r, radius, radius);
    return QRegion(path.toFillPolygon().toPolygon());
}

// image://icon/<theme-name or absolute path or data:<n> decoded by NotificationIcon>
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
        const QString key = QUrl::fromPercentEncoding(id.toUtf8());
        QPixmap pm;
        if (key.startsWith(QLatin1String("data:"))) {
            pm = NotificationIcon::decoded().value(key);
        } else if (key.startsWith(QLatin1Char('/'))) {
            pm.load(key);
        }
        if (pm.isNull()) {
            QIcon icon = QIcon::fromTheme(key);
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
    Q_PROPERTY(bool backdropLight READ backdropLight NOTIFY backdropChanged)   // the desktop under the bar is bright
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
        ensureMediaScript();

        // A strip of the desktop just under the glass (it follows the glass's edge), so the bar
        // dresses light or dark for what it sits on.
        connect(&m_sampler, &BackdropSampler::lightChanged, this, &IslandController::backdropChanged);
        m_sample.setInterval(800);
        connect(&m_sample, &QTimer::timeout, this, [this] {
            if (!m_view->screen()) {
                return;
            }
            const QRect g = m_view->screen()->geometry();
            m_sampler.sample(QRect(g.center().x() - 120, g.y() + m_uiBottom + 8, 240, 10));
        });
        m_sample.start();
    }

    bool dark() const { return m_dark; }
    bool backdropLight() const { return m_sampler.valid() && m_sampler.light(); }
    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }
    // AETHER_BODY_ALPHA lets us compare opacity levels while tuning the look.
    qreal bodyAlpha() const { return qEnvironmentVariableIsSet("AETHER_BODY_ALPHA") ? qEnvironmentVariable("AETHER_BODY_ALPHA").toDouble() : 0.32; }

    // Called from QML: resize the layer-shell surface.
    Q_INVOKABLE void setWindowSize(int w, int h)
    {
        if (QSize(w, h) != m_view->size()) {
            m_view->resize(w, h);
        }
    }

    // Called from QML whenever the shape changes. The silhouette arrives as path commands
    // (the same list NotchSurface.qml draws from), so blur, input and drawing can never agree
    // to disagree. `hole` (media mode) punches a rounded window out of the middle: the YouTube
    // Music window shows through it and receives the pointer there.
    //   cmds: [{t:"M"|"L"|"C", x, y, x1, y1, x2, y2}]   hot: invisible strip that still gets the pointer
    Q_INVOKABLE void setLayout(const QVariantList &cmds, bool fullInput, const QRectF &hot, const QRectF &hole)
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
        if (hole.width() > 0 && hole.height() > 0) {
            p.addRoundedRect(hole, 18, 18);   // OddEvenFill (QPainterPath default) cuts it out
        }
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
        if (!hole.isEmpty()) {
            // The app window's seat stays clickable - the island must not swallow it.
            input -= QRegion(QRect(QPoint(hole.topLeft().toPoint()), hole.size().toSize()));
        }
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
    }

    // Search and power live inside the island now (SearchHost / PowerBar): the tab's buttons
    // open them as modes, and org.aether.Island.Search() lets a shortcut open the search too.
    Q_INVOKABLE void setKeyboard(bool wanted)
    {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                : LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }

    // The YouTube Music window lives *inside* the island, owned by the persistent KWin
    // script aether-media (components/island/kwin). The window never moves, resizes or
    // fades while shown: it sits still in the media panel's seat and the island's glass
    // does all the motion, frosting over it and clearing again. Island -> script is two
    // keyless global shortcuts; script -> island is the Media* slots below.
    Q_INVOKABLE void showMediaWindow(int x, int y, int w, int h)
    {
        const QPoint origin = m_view->screen() ? m_view->screen()->geometry().topLeft() : QPoint();
        m_mediaRect = QRect(x, y, w, h).translated(origin);
        invokeKwinShortcut(QStringLiteral("Aether Media Show"));
    }
    // The bar's console button: show the console shelf, or fold it back to its resting tab.
    Q_INVOKABLE void toggleConsole()
    {
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
            QStringLiteral("org.aether.Console"), QStringLiteral("/Console"), QStringLiteral("org.aether.Console"), QStringLiteral("Toggle")));
    }
    Q_INVOKABLE void hideMediaWindow() { invokeKwinShortcut(QStringLiteral("Aether Media Hide")); }


public Q_SLOTS:
    // org.aether.Island - also lets a keyboard shortcut or a script drive the island.
    void Peek() { Q_EMIT stateRequested(QStringLiteral("small")); }
    void Expand() { Q_EMIT stateRequested(QStringLiteral("large")); }
    void Pull() { Q_EMIT stateRequested(QStringLiteral("expanded")); }
    void Media() { Q_EMIT stateRequested(QStringLiteral("media")); }
    void Hide() { Q_EMIT stateRequested(QStringLiteral("hidden")); }
    void Toggle() { Q_EMIT stateRequested(QStringLiteral("toggle")); }
    // Called back by the aether-media KWin script.
    QString mediaSeat() const   // "x,y,w,h" in screen coordinates
    {
        return QStringLiteral("%1,%2,%3,%4").arg(m_mediaRect.x()).arg(m_mediaRect.y()).arg(m_mediaRect.width()).arg(m_mediaRect.height());
    }
    void MediaWindowReady() { Q_EMIT mediaWindowReady(); }       // seated and visible: clear the frost
    void MediaWindowMissing() { Q_EMIT mediaWindowMissing(); }   // nothing to seat: launch the app
    void MediaFocusLost() { Q_EMIT mediaFocusLost(); }           // another window was activated
    // Detail panels: wifi, bluetooth, sound, display, battery, calendar, power.
    void OpenPanel(const QString &id) { Q_EMIT panelRequested(id); }
    void ClosePanel() { Q_EMIT stateRequested(QStringLiteral("close")); }
    // The island-native search (the tab's morphing pill). SearchWithQuery opens it with the
    // query already typed - scripts and shortcuts can drop a search straight onto the glass.
    void Search() { Q_EMIT searchRequested(QString()); }
    void SearchWithQuery(const QString &query) { Q_EMIT searchRequested(query); }
    // Where the island's glass currently ends, and in which mode - aether-toasts asks this
    // for every notification: cards drop just below the glass, and while the double bar
    // (expanded) is open no card is shown at all (the history list takes it).
    QString mode() const { return m_uiMode; }
    int bottom() const { return m_uiBottom; }
    void setUiState(const QString &mode, int bottom)
    {
        if (mode == m_uiMode && bottom == m_uiBottom) {
            return;
        }
        m_uiMode = mode;
        m_uiBottom = bottom;
        Q_EMIT UiState(mode, bottom);
    }

Q_SIGNALS:
    void UiState(const QString &mode, int bottom);   // on the bus: aether-toasts follows the glass live
    void darkChanged();
    void backdropChanged();
    void stateRequested(const QString &state);
    void mediaWindowReady();
    void mediaWindowMissing();
    void mediaFocusLost();
    void panelRequested(const QString &id);
    void searchRequested(const QString &query);

private:
    // Raw DBus messages, never QDBusInterface: its constructor introspects the target
    // synchronously and would block the island's event loop on a busy compositor.
    static QDBusMessage kwinScripting(const QString &method)
    {
        return QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"),
                                              QStringLiteral("org.kde.kwin.Scripting"), method);
    }
    static void invokeKwinShortcut(const QString &name)
    {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"),
                                                  QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
        msg << name;
        QDBusConnection::sessionBus().asyncCall(msg);
    }
    // The installer enables aether-media as a KWin package; this covers running from the
    // source tree (or a KWin that started before the package existed). Fully async.
    void ensureMediaScript()
    {
        auto bus = QDBusConnection::sessionBus();
        auto query = kwinScripting(QStringLiteral("isScriptLoaded"));
        query << QStringLiteral("aether-media");
        auto *w = new QDBusPendingCallWatcher(bus.asyncCall(query), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            const QDBusPendingReply<bool> loaded = *w;
            if (loaded.isValid() && loaded.value()) {
                return;
            }
            const QString rel = QStringLiteral("/aether-media/contents/code/main.js");
            const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-island/kwin") + rel;
            auto load = kwinScripting(QStringLiteral("loadScript"));
            load << (QFile::exists(installed) ? installed : QStringLiteral(AETHER_KWIN_DIR) + rel) << QStringLiteral("aether-media");
            auto *lw = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(load), this);
            connect(lw, &QDBusPendingCallWatcher::finished, this, [](QDBusPendingCallWatcher *lw) {
                lw->deleteLater();
                const QDBusPendingReply<int> id = *lw;
                if (id.isValid() && id.value() >= 0) {
                    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                        QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting/Script") + QString::number(id.value()),
                        QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run")));
                }
            });
        });
    }
    void readScheme()
    {
        QSettings kde(m_kdeglobals, QSettings::IniFormat);
        // The key sits at the top level: QSettings maps an INI [General] section to the root.
        const QString scheme = kde.value(QStringLiteral("ColorScheme")).toString();
        // AetherSerenity is our light scheme. A look-and-feel apply can leave the name out: then
        // judge by the window colour the scheme installed (r,g,b or r,g,b,a), as the dock does -
        // an unnamed scheme is not necessarily dark.
        bool dark = !scheme.contains(QLatin1String("Serenity"), Qt::CaseInsensitive)
            && !scheme.contains(QLatin1String("Light"), Qt::CaseInsensitive);
        if (scheme.isEmpty()) {
            const QStringList c = kde.value(QStringLiteral("Colors:Window/BackgroundNormal")).toStringList();
            if (c.size() >= 3) {
                dark = (0.299 * c[0].toInt() + 0.587 * c[1].toInt() + 0.114 * c[2].toInt()) < 128;
            }
        }
        if (dark != m_dark) {
            m_dark = dark;
            Q_EMIT darkChanged();
        }
    }

    QQuickView *m_view;
    QTimer m_sample;
    BackdropSampler m_sampler;
    QFileSystemWatcher m_watcher;
    QString m_kdeglobals;
    bool m_dark = true;
    QString m_uiMode = QStringLiteral("hidden");
    int m_uiBottom = 2;
    QRect m_mediaRect;
};

// Installed copy first (~/.local/share/aether-island/qml next to ~/.local/bin), development tree as fallback.
// The island IS the notification server: org.freedesktop.Notifications is served by this
// silent sink. Notify() returns an id and shows nothing - aether-toasts (styled cards) and
// the island's own history list are the display. This keeps third-party banners out for
// good while every client's call still succeeds.
class NotificationSink : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
public:
    using QObject::QObject;

public Q_SLOTS:
    uint Notify(const QString & /*app*/, uint /*replacesId*/, const QString & /*icon*/,
                const QString & /*summary*/, const QString & /*body*/,
                const QStringList & /*actions*/, const QVariantMap & /*hints*/, int /*timeout*/)
    {
        return ++m_id;
    }
    void CloseNotification(uint /*id*/) {}
    QStringList GetCapabilities() const
    {
        return { QStringLiteral("body"), QStringLiteral("body-markup"), QStringLiteral("actions") };
    }
    QString GetServerInformation(QString &vendor, QString &version, QString &specVersion) const
    {
        vendor = QStringLiteral("aether");
        version = QStringLiteral("1.0");
        specVersion = QStringLiteral("1.2");
        return QStringLiteral("aether-island");
    }
    // The do-not-disturb extension KDE exposes: answered so callers don't error. The sink
    // never displays anything anyway, so the cookie is cosmetic.
    uint Inhibit(const QString &, const QString &, const QVariantMap &) { return ++m_id; }
    void UnInhibit(uint) {}

private:
    uint m_id = 0;
};

static QString qmlDir()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-island/qml");
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
    // Inter has no Hebrew; borrow it from Noto Sans Hebrew so mixed text keeps one weight and size.
    QFont::insertSubstitution(QStringLiteral("Inter"), QStringLiteral("Noto Sans Hebrew"));
    app.setApplicationName(QStringLiteral("aether-island"));
    app.setDesktopFileName(QStringLiteral("aether-island"));

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.resize(300, 4);

    // AETHER_NO_LAYER=1 skips the layer-shell attach outright - test sandboxes on X11, where
    // even LayerShellQt::Window::get aborts without a Wayland platform.
    auto *ls = qEnvironmentVariableIsSet("AETHER_NO_LAYER") ? nullptr : LayerShellQt::Window::get(&view);
    if (ls) {                                          // null on X11 (test sandboxes): a plain window then
        ls->setLayer(LayerShellQt::Window::LayerOverlay);
        ls->setAnchors(LayerShellQt::Window::AnchorTop);   // anchored to top only: centred horizontally
        ls->setExclusiveZone(0);                           // 0 = never reserve edge space (-1 would make maximized windows stop short of the edge, like a Windows taskbar)
        ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        ls->setScope(QStringLiteral("aether-island"));
    }

    view.engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    PrefsGuard prefsGuard;   // first: lost settings are back in the file before any store reads it
    MediaController media;
    view.rootContext()->setContextProperty(QStringLiteral("media"), &media);
    AudioLevels audio;
    view.rootContext()->setContextProperty(QStringLiteral("audioLevels"), &audio);
    GlyphStore glyphStore;
    view.rootContext()->setContextProperty(QStringLiteral("glyphs"), &glyphStore);
    NotificationStore notifStore;
    view.rootContext()->setContextProperty(QStringLiteral("notifStore"), &notifStore);
    SystemInfo system;
    view.rootContext()->setContextProperty(QStringLiteral("system"), &system);
    NetworkModel network;
    view.rootContext()->setContextProperty(QStringLiteral("network"), &network);
    BluetoothModel bluetooth;
    view.rootContext()->setContextProperty(QStringLiteral("bluetooth"), &bluetooth);
    TetherController tether(&network, &bluetooth);
    view.rootContext()->setContextProperty(QStringLiteral("tether"), &tether);
    AudioModel audio_;
    view.rootContext()->setContextProperty(QStringLiteral("sound"), &audio_);
    PowerModel power;
    view.rootContext()->setContextProperty(QStringLiteral("power"), &power);
    DisplayModel displayModel;
    view.rootContext()->setContextProperty(QStringLiteral("displaySettings"), &displayModel);
    SessionActions session;
    view.rootContext()->setContextProperty(QStringLiteral("session"), &session);
    TileStore tiles;
    view.rootContext()->setContextProperty(QStringLiteral("tiles"), &tiles);
    ConnectModel connectModel;
    view.rootContext()->setContextProperty(QStringLiteral("connectModel"), &connectModel);
    ConnectInput connectInput;
    view.rootContext()->setContextProperty(QStringLiteral("connectInput"), &connectInput);
    SearchEngine search;
    view.rootContext()->setContextProperty(QStringLiteral("search"), &search);
    IslandController controller(&view);
    view.rootContext()->setContextProperty(QStringLiteral("island"), &controller);
    NotificationSink sink;

    auto bus = QDBusConnection::sessionBus();
    bus.registerService(QStringLiteral("org.aether.Island"));
    bus.registerObject(QStringLiteral("/Island"), &controller, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);

    // The desktop's theme for every client that wants to dress like it (docs/THEME-BUS.md).
    ThemeBus themeBus(&tiles, &displayModel);
    bus.registerService(QStringLiteral("org.aether.Theme"));
    bus.registerObject(QStringLiteral("/Theme"), &themeBus, QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals);

    // The island also owns org.freedesktop.Notifications: every Notify is accepted (so
    // clients succeed and the bus monitors see the traffic) and nothing is shown by the
    // server itself - aether-toasts and the island's history are the only notification
    // UI. If another server already owns the name, we stay a silent monitor alongside it.
    if (bus.registerService(QStringLiteral("org.freedesktop.Notifications"))) {
        bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"), &sink,
                           QDBusConnection::ExportAllSlots);
    }

    view.engine()->addImportPath(sharedDir());
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
