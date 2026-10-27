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
#include <QDateTime>
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
#include <QGuiApplication>
#include <QPainterPath>
#include <QQmlContext>
#include <QQuickView>
#include <QRegion>
#include <QTimer>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>

#include "AudioLevels.h"
#include "MediaController.h"
#include "NotificationStore.h"
#include "AudioModel.h"
#include "BluetoothModel.h"
#include "NetworkModel.h"
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
        // Pear autostarts with its window; the ecosystem keeps it invisible except
        // inside the island. A few seconds of slack cover its cold start - but never
        // hide it out from under an open media view.
        QTimer::singleShot(6000, this, [this] { if (!m_mediaActive) hideMediaWindow(); });
        QTimer::singleShot(12000, this, [this] { if (!m_mediaActive) hideMediaWindow(); });
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

    // The YouTube Music window lives *inside* the island: shown exactly in the media
    // panel's hole, hidden again when the island folds. KWin only loads scripts from
    // files, so each run goes through a fresh temp file. Retries cover a cold start
    // (seconds before the window exists) but are cancelled the moment media mode ends,
    // so a late retry can never resurrect a floating window.
    Q_INVOKABLE void showMediaWindow(int x, int y, int w, int h)
    {
        m_mediaActive = true;
        ++m_showGeneration;
        const int gen = m_showGeneration;
        m_mediaRect = QRect(x, y, w, h);
        // Seat the window full-size but transparent, then fade it in on the same
        // ease-out curve as the glass spring (~225 ms): one synchronized materialise.
        // (No staged resizes: Chromium under XWayland renders them poorly.)
        runKwinScript(mediaStepScript(x, y, w, h, 0.0, true));
        for (int i = 1; i <= 5; ++i) {
            const qreal eased = 1.0 - (1.0 - i / 5.0) * (1.0 - i / 5.0);
            QTimer::singleShot(i * 45, this, [this, gen, x, y, w, h, eased] {
                if (m_mediaActive && gen == m_showGeneration) {
                    runKwinScript(mediaStepScript(x, y, w, h, eased, false));
                }
            });
        }
        auto retry = [this, gen, x, y, w, h] {
            if (m_mediaActive && gen == m_showGeneration) {
                runKwinScript(showScript(x, y, w, h));
            }
        };
        QTimer::singleShot(800, this, retry);
        QTimer::singleShot(2500, this, retry);
        QTimer::singleShot(5000, this, retry);
        QTimer::singleShot(8000, this, retry);   // a cold Electron start can outlast 5s
        QTimer::singleShot(12000, this, retry);
    }
    // Ride the glass: QML pushes the spring's geometry every frame while the media
    // panel opens or folds, and the app window tracks it in BOTH axes - shrinking
    // with the collapsing glass (a true swallow) instead of fading on its own.
    Q_INVOKABLE void syncMediaWindow(int glassLeft, int glassW, int bottom)
    {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastWindowSync < 35 || m_mediaRect.height() <= 0) {
            return;
        }
        m_lastWindowSync = now;
        const int w = qMax(2, qMin(m_mediaRect.width(), glassW - 40));   // 2x bezel
        const int h = qMax(2, qMin(m_mediaRect.height(), bottom - 24));
        const int x = glassLeft + (glassW - w) / 2;
        runKwinScript(QStringLiteral(
                          "var ws = workspace.windowList();"
                          "for (var i = 0; i < ws.length; i++) {"
                          "  var w = ws[i];"
                          "  if (String(w.resourceClass).indexOf('youtube-music') >= 0) {"
                          "    w.frameGeometry = { x: %1, y: %2, width: %3, height: %4 };"
                          "  }"
                          "}")
                          .arg(x)
                          .arg(m_mediaRect.y())
                          .arg(w)
                          .arg(h));
    }

    Q_INVOKABLE void hideMediaWindow()
    {
        m_mediaActive = false;
        ++m_showGeneration;
        // The glass springs shut over ~750 ms while QML syncs the window down with
        // it; only when it has settled does the window actually vanish.
        QTimer::singleShot(950, this, [this] {
            if (!m_mediaActive) {
                runKwinScript(QStringLiteral(
                    "var ws = workspace.windowList();"
                    "for (var i = 0; i < ws.length; i++) {"
                    "  var w = ws[i];"
                    "  if (String(w.resourceClass).indexOf('youtube-music') >= 0) {"
                    "    w.minimized = true; w.skipTaskbar = true; w.opacity = 1.0;"
                    "  }"
                    "}"));
            }
        });
    }


public Q_SLOTS:
    // org.aether.Island - also lets a keyboard shortcut or a script drive the island.
    void Peek() { Q_EMIT stateRequested(QStringLiteral("small")); }
    void Expand() { Q_EMIT stateRequested(QStringLiteral("large")); }
    void Pull() { Q_EMIT stateRequested(QStringLiteral("expanded")); }
    void Media() { Q_EMIT stateRequested(QStringLiteral("media")); }
    void Hide() { Q_EMIT stateRequested(QStringLiteral("hidden")); }
    void Toggle() { Q_EMIT stateRequested(QStringLiteral("toggle")); }
    // Detail panels: wifi, bluetooth, sound, display, battery, calendar, power.
    void OpenPanel(const QString &id) { Q_EMIT panelRequested(id); }
    void ClosePanel() { Q_EMIT stateRequested(QStringLiteral("close")); }
    // Where the island's glass currently ends, and in which mode - aether-toasts asks this
    // for every notification: cards drop just below the glass, and while the double bar
    // (expanded) is open no card is shown at all (the history list takes it).
    QString mode() const { return m_uiMode; }
    int bottom() const { return m_uiBottom; }
    void setUiState(const QString &mode, int bottom)
    {
        m_uiMode = mode;
        m_uiBottom = bottom;
    }

Q_SIGNALS:
    void darkChanged();
    void stateRequested(const QString &state);
    void panelRequested(const QString &id);

private:
    // One synchronized step of the app window: it grows downward (and fades in)
    // following the glass spring's easing, so window and bar move as one.
    static QString mediaStepScript(int x, int y, int w, int h, qreal v, bool decorate)
    {
        QString extra = decorate
            ? QStringLiteral("    w.noBorder = true; w.skipTaskbar = false; w.keepAbove = true; w.minimized = false;")
            : QString();
        return QStringLiteral(
                   "var ws = workspace.windowList();"
                   "for (var i = 0; i < ws.length; i++) {"
                   "  var w = ws[i];"
                   "  if (String(w.resourceClass).indexOf('youtube-music') >= 0) {"
                   "%1"
                   "    w.frameGeometry = { x: %2, y: %3, width: %4, height: %5 };"
                   "    w.opacity = %6;"
                   "  }"
                   "}")
                   .arg(extra)
                   .arg(x)
                   .arg(y)
                   .arg(w)
                   .arg(h)
                   .arg(v, 0, 'f', 2);
    }
    QString showScript(int x, int y, int w, int h) const
    {
        return QStringLiteral(
            "var prev = workspace.activeWindow;"
            "var ws = workspace.windowList();"
            "for (var i = 0; i < ws.length; i++) {"
            "  var w = ws[i];"
            "  if (String(w.resourceClass).indexOf('youtube-music') >= 0) {"
            "    w.noBorder = true; w.skipTaskbar = false; w.keepAbove = true;"
            "    w.minimized = false;"
            "    w.frameGeometry = { x: %1, y: %2, width: %3, height: %4 };"
            "    w.opacity = 1.0;"
            "  }"
            "}"
            // Restoring must not steal focus: the app counts as in use (and the media
            // view stays open on pointer-leave) only after a real click inside it.
            "if (prev && prev !== workspace.activeWindow && String(prev.resourceClass).indexOf('youtube-music') < 0)"
            "  workspace.activeWindow = prev;")
            .arg(x)
            .arg(y)
            .arg(w)
            .arg(h);
    }
    // Raw DBus messages, never QDBusInterface: its constructor introspects the target
    // synchronously, and building one per tick (or on a busy compositor) blocks the
    // island's event loop for up to the full DBus timeout.
    static int kwinLoadScript(const QString &path)
    {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"),
                                                  QStringLiteral("org.kde.kwin.Scripting"), QStringLiteral("loadScript"));
        msg << path;
        const QDBusReply<int> id = QDBusConnection::sessionBus().call(msg, QDBus::Block, 500);
        return id.isValid() ? id.value() : -1;
    }
    static void kwinCall(const QString &path, const QString &method, const QVariant &arg = {})
    {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), path,
                                                  QStringLiteral("org.kde.kwin.Script"), method);
        if (arg.isValid()) {
            msg << arg;
        }
        QDBusConnection::sessionBus().asyncCall(msg);
    }
    static void runKwinScript(const QString &js)
    {
        static int counter = 0;
        const QString path = QDir::temp().absoluteFilePath(QStringLiteral("aether-kwin-%1.js").arg(++counter));
        QFile f(path);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(js.toUtf8());
            f.close();
        }
        const int id = kwinLoadScript(path);
        if (id > 0) {
            kwinCall(QStringLiteral("/Scripting/Script") + QString::number(id), QStringLiteral("run"));
            // One-shot: unload shortly after, so scripts never accumulate in KWin.
            QTimer::singleShot(1500, [path] {
                auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"),
                                                          QStringLiteral("org.kde.kwin.Scripting"), QStringLiteral("unloadScript"));
                msg << path;
                QDBusConnection::sessionBus().asyncCall(msg);
                QFile::remove(path);
            });
        }
    }
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
    QString m_uiMode = QStringLiteral("hidden");
    int m_uiBottom = 2;
    bool m_mediaActive = false;
    int m_showGeneration = 0;
    QRect m_mediaRect;
    qint64 m_lastWindowSync = 0;
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
    ls->setExclusiveZone(0);                           // 0 = never reserve edge space (-1 would make maximized windows stop short of the edge, like a Windows taskbar)
    ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    ls->setScope(QStringLiteral("aether-island"));

    view.engine()->addImageProvider(QStringLiteral("icon"), new IconProvider);
    MediaController media;
    view.rootContext()->setContextProperty(QStringLiteral("media"), &media);
    AudioLevels audio;
    view.rootContext()->setContextProperty(QStringLiteral("audioLevels"), &audio);
    NotificationStore notifStore;
    view.rootContext()->setContextProperty(QStringLiteral("notifStore"), &notifStore);
    SystemInfo system;
    view.rootContext()->setContextProperty(QStringLiteral("system"), &system);
    NetworkModel network;
    view.rootContext()->setContextProperty(QStringLiteral("network"), &network);
    BluetoothModel bluetooth;
    view.rootContext()->setContextProperty(QStringLiteral("bluetooth"), &bluetooth);
    AudioModel audio_;
    view.rootContext()->setContextProperty(QStringLiteral("sound"), &audio_);
    IslandController controller(&view);
    view.rootContext()->setContextProperty(QStringLiteral("island"), &controller);
    NotificationSink sink;

    auto bus = QDBusConnection::sessionBus();
    bus.registerService(QStringLiteral("org.aether.Island"));
    bus.registerObject(QStringLiteral("/Island"), &controller, QDBusConnection::ExportAllSlots);

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
