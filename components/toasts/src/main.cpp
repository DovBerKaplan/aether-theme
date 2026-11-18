// aether-toasts: notification cards that drop from the top edge of the screen.
//
// A separate program from the island on purpose: it only *watches* org.freedesktop.Notifications
// (Plasma stays the notification server, so history and do-not-disturb keep working) and mutes
// Plasma's own banner while it runs. Quit it and Plasma's banners return.
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
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
#include <QRegularExpression>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <BackdropSampler.h>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <NotificationIcon.h>

// ---- phone (KDE Connect) notifications -----------------------------------------------
// The daemon forwards a phone notification as a normal one from app "kdeconnect": the
// phone's title and text travel, but the phone app's icon never does. The daemon's own
// notification objects do have it (appName plus iconPath, the icon downloaded from the
// phone), so find the object matching what was forwarded and take its app name and icon.

struct PhoneMatch
{
    QString app;
    QString icon;
};

static bool isPhoneApp(const QString &app)
{
    const QString a = app.simplified().remove(QLatin1Char(' ')).toLower();
    return a.startsWith(QLatin1String("kdeconnect")) || a.startsWith(QLatin1String("org.kde.kdeconnect"));
}

static QString cleanPhoneText(QString s)
{
    s = s.simplified();
    QString out;
    out.reserve(s.size());
    for (const QChar c : s) {
        if (c.category() == QChar::Other_Format || c.category() == QChar::Mark_NonSpacing
            || c.category() == QChar::Mark_Enclosing) {
            continue;   // direction and joining marks: phones sprinkle them per field
        }
        out.append(c);
    }
    // Tag stripping and entity unescaping: one side of the pair may arrive HTML-escaped.
    out.replace(QRegularExpression(QStringLiteral("<[^>]*>")), QStringLiteral(" "));
    const struct { const char *entity; const char *ch; } entities[] = {
        { "&quot;", "\"" }, { "&apos;", "'" }, { "&#39;", "'" }, { "&lt;", "<" },
        { "&gt;", ">" }, { "&nbsp;", " " }, { "&amp;", "&" } };
    for (const auto &e : entities) {
        out.replace(QLatin1String(e.entity), QLatin1String(e.ch));
    }
    return out.trimmed();
}

static PhoneMatch phoneMatch(const QString &summary, const QString &body)
{
    const QString sum = cleanPhoneText(summary).toLower();
    const QString bod = cleanPhoneText(body).toLower();
    if (sum.isEmpty() && bod.isEmpty()) {
        return {};
    }
    auto eq = [](const QString &a, const QString &b) { return !a.isEmpty() && a == b; };
    PhoneMatch best;
    int bestScore = 0;
    QDBusMessage devs = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kdeconnect"), QStringLiteral("/modules/kdeconnect"),
                                                       QStringLiteral("org.kde.kdeconnect.daemon"), QStringLiteral("devices"));
    devs << false << false;
    const QDBusReply<QStringList> devReply = QDBusConnection::sessionBus().call(devs, QDBus::Block, 800);
    for (const QString &id : devReply.value()) {
        const QString base = QStringLiteral("/modules/kdeconnect/devices/") + id + QStringLiteral("/notifications");
        QDBusMessage list = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kdeconnect"), base,
                                                           QStringLiteral("org.kde.kdeconnect.device.notifications"),
                                                           QStringLiteral("activeNotifications"));
        const QDBusReply<QStringList> ids = QDBusConnection::sessionBus().call(list, QDBus::Block, 800);
        for (const QString &nid : ids.value()) {
            QDBusMessage get = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kdeconnect"), base + QLatin1Char('/') + nid,
                                                              QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
            get << QStringLiteral("org.kde.kdeconnect.device.notifications.notification");
            const QDBusMessage r = QDBusConnection::sessionBus().call(get, QDBus::Block, 800);
            if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty()) {
                continue;
            }
            const QVariantMap p = qdbus_cast<QVariantMap>(r.arguments().first().value<QDBusArgument>());
            const QString app = cleanPhoneText(p.value(QStringLiteral("appName")).toString()).toLower();
            const QString title = cleanPhoneText(p.value(QStringLiteral("title")).toString()).toLower();
            const QString ticker = cleanPhoneText(p.value(QStringLiteral("ticker")).toString()).toLower();
            const QString text = cleanPhoneText(p.value(QStringLiteral("text")).toString()).toLower();
            int score = 0;
            if (eq(title, sum) || eq(ticker, bod)) {
                score += 4;   // the forwarded title is the phone title, or its body the ticker
            }
            if (eq(app, sum)) {
                score += 3;   // or the title is the phone app name (KNotifications without the appname hint)
            }
            if (eq(text, bod)) {
                score += 3;
            }
            if (eq(title, bod)) {
                score += 2;
            }
            if (!sum.isEmpty() && ticker.startsWith(sum)) {
                score += 1;
            }
            if (!app.isEmpty() && sum.startsWith(app)) {
                score += 1;
            }
            if (score > bestScore) {
                bestScore = score;
                best.app = p.value(QStringLiteral("appName")).toString();
                best.icon = p.value(QStringLiteral("hasIcon")).toBool() ? p.value(QStringLiteral("iconPath")).toString() : QString();
            }
            if (bestScore >= 6) {   // an exact title/text pair cannot be beaten
                return best;
            }
        }
    }
    return bestScore >= 2 ? best : PhoneMatch{};
}

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
    void received(const QString &app, const QString &icon, const QString &summary, const QString &body,
                  int urgency, int timeoutMs, bool islandOpen,
                  const QString &desktop, bool phone);

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
        if (hints.value(QStringLiteral("transient")).toObject().value(QStringLiteral("data")).toBool()
            && d.at(1).toInt() != 0) {
            // progress-style updates (replaces_id set) would spam the stack; show only fresh ones
            return;
        }
        QString app = d.at(0).toString();
        QString summary = d.at(3).toString();
        QString body = d.at(4).toString();
        QString icon = NotificationIcon::resolve(app, d.at(2).toString(), hints);
        // The desktop-entry hint names the .desktop file of the app that sent this; clicking the
        // card uses it to find (or launch) that app. Phone cards have no desktop app - the island's
        // KDE Connect page is their home.
        QString desktop = hints.value(QStringLiteral("desktop-entry")).toObject().value(QStringLiteral("data")).toString();
        const bool phone = isPhoneApp(app);
        if (phone) {
            desktop.clear();
            const PhoneMatch phoneMatchFound = phoneMatch(summary, body);
            if (!phoneMatchFound.app.isEmpty()) {
                app = phoneMatchFound.app;   // the card speaks the phone app's name, with its icon
            }
            if (!phoneMatchFound.icon.isEmpty()) {
                icon = phoneMatchFound.icon;
            }
        }
        // The island owns the top of the screen: while its double bar (expanded) is open, the
        // history list shows the notification there and no card is spawned at all. Where the
        // cards sit is not decided here - the stack follows the island's glass live.
        bool islandOpen = false;
        QDBusInterface island(QStringLiteral("org.aether.Island"), QStringLiteral("/Island"),
                              QStringLiteral("org.aether.Island"));
        const QDBusReply<QString> islandMode = island.call(QStringLiteral("mode"));
        if (islandMode.isValid() && islandMode.value() == QLatin1String("expanded")) {
            islandOpen = true;
        }
        Q_EMIT received(app, icon, summary, body,
                        hints.value(QStringLiteral("urgency")).toObject().value(QStringLiteral("data")).toInt(1),
                        d.at(7).toInt(-1), islandOpen, desktop, phone);
    }

    QProcess m_proc;
    QByteArray m_buffer;
    uint m_cookie = 0;
};

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

class ToastsController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int screenWidth READ screenWidth CONSTANT)
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(qreal bodyAlpha READ bodyAlpha NOTIFY darkChanged)
    Q_PROPERTY(QColor accentOverride READ accentOverride NOTIFY accentChanged)
    Q_PROPERTY(int islandBottom READ islandBottom NOTIFY islandChanged)    // where the island's glass ends right now
    Q_PROPERTY(QString islandMode READ islandMode NOTIFY islandChanged)

public:
    explicit ToastsController(QQuickView *view)
        : QObject(view)
        , m_view(view)
    {
        m_kdeglobals = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
        m_islandRc = QDir::homePath() + QStringLiteral("/.config/aetherislandrc");
        m_watcher.addPath(m_kdeglobals);
        m_watcher.addPath(m_islandRc);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
            m_watcher.addPath(path);   // editors replace the file, so re-arm the watch
            readScheme();
            readAccent();
        });
        readScheme();
        readAccent();

        // The island announces every move of its glass; the cards ride along under it.
        auto bus = QDBusConnection::sessionBus();
        bus.connect(QStringLiteral("org.aether.Island"), QStringLiteral("/Island"), QStringLiteral("org.aether.Island"),
                    QStringLiteral("UiState"), this, SLOT(onIslandState(QString, int)));
        auto *islandWatch = new QDBusServiceWatcher(QStringLiteral("org.aether.Island"), bus,
                                                    QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(islandWatch, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &, const QString &newOwner) {
            if (newOwner.isEmpty()) {
                onIslandState(QString(), 0);
            } else {
                QTimer::singleShot(500, this, [this] { pullIsland(); });
            }
        });
        pullIsland();

        // A strip of the desktop just to the side of the cards, level with the stack.
        connect(&m_sampler, &BackdropSampler::lightChanged, this, &ToastsController::darkChanged);
        m_sample.setInterval(1000);
        connect(&m_sample, &QTimer::timeout, this, [this] {
            if (!m_view->screen()) {
                return;
            }
            const QRect g = m_view->screen()->geometry();
            m_sampler.sample(QRect(g.center().x() + 190 + 24, g.y() + qMax(10, m_islandBottom + 10), 10, 150));
        });
        m_sample.start();
    }
    QColor accentOverride() const { return m_accent; }
    int islandBottom() const { return m_islandBottom; }
    QString islandMode() const { return m_islandMode; }
    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    // Light or dark follows what the desktop shows beside the stack (sampled); the system scheme
    // only stands in until the first sample arrives or where sampling is not allowed.
    bool dark() const { return m_sampler.valid() ? !m_sampler.light() : m_dark; }
    // Light mode is the dock's white-veil alpha; dark keeps the island glass (or the env override).
    qreal bodyAlpha() const
    {
        if (!dark()) {
            return 0.50;
        }
        return qEnvironmentVariableIsSet("AETHER_BODY_ALPHA") ? qEnvironmentVariable("AETHER_BODY_ALPHA").toDouble() : 0.75;
    }

    Q_INVOKABLE void setWindowHeight(int h)
    {
        if (h != m_view->height()) {
            m_view->resize(m_view->width(), h);
        }
    }
    // A card was clicked and its app is not running: launch it by desktop-entry id. kioclient
    // carries KDE startup notification (single-instance apps just come forward); gio is the fallback.
    Q_INVOKABLE void launchDesktop(const QString &desktop)
    {
        if (desktop.isEmpty()) {
            return;
        }
        const QString id = desktop + QStringLiteral(".desktop");
        const QStringList roots = {
            QDir::homePath() + QStringLiteral("/.local/share/applications"),
            QStringLiteral("/usr/share/applications"),
            QStringLiteral("/usr/local/share/applications"),
            QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications"),
            QStringLiteral("/var/lib/flatpak/exports/share/applications"),
        };
        QString path;
        for (const QString &r : roots) {
            const QFileInfo fi(r + QLatin1Char('/') + id);
            if (fi.isFile()) {
                path = fi.absoluteFilePath();
                break;
            }
        }
        if (path.isEmpty()) {
            return;
        }
        if (!QProcess::startDetached(QStringLiteral("kioclient"), {QStringLiteral("exec"), path})) {
            QProcess::startDetached(QStringLiteral("gio"), {QStringLiteral("launch"), path});
        }
    }
    // A phone notification's "app" (WhatsApp, the phone's messenger) lives on the phone: the
    // island's KDE Connect notifications page is the closest thing to opening it.
    Q_INVOKABLE void openConnectPanel()
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.aether.Island"), QStringLiteral("/Island"),
                                                        QStringLiteral("org.aether.Island"), QStringLiteral("OpenPanel"));
        m << QStringLiteral("connect:notifications");
        QDBusConnection::sessionBus().asyncCall(m);
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

public Q_SLOTS:
    void onIslandState(const QString &mode, int bottom)
    {
        if (mode == m_islandMode && bottom == m_islandBottom) {
            return;
        }
        m_islandMode = mode;
        m_islandBottom = bottom;
        Q_EMIT islandChanged();
    }

Q_SIGNALS:
    void darkChanged();
    void accentChanged();
    void islandChanged();

private:
    // One-off read of where the island is now (startup, or the island restarted).
    void pullIsland()
    {
        auto call = [](const char *member) {
            QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.aether.Island"), QStringLiteral("/Island"),
                                                            QStringLiteral("org.aether.Island"), QString::fromLatin1(member));
            return QDBusConnection::sessionBus().call(m, QDBus::Block, 800);
        };
        const QDBusMessage mode = call("mode");
        const QDBusMessage bottom = call("bottom");
        if (mode.type() == QDBusMessage::ReplyMessage && bottom.type() == QDBusMessage::ReplyMessage
            && !mode.arguments().isEmpty() && !bottom.arguments().isEmpty()) {
            onIslandState(mode.arguments().first().toString(), bottom.arguments().first().toInt());
        }
    }
    // The colour the user picked in the island's colour panel (read-only here): transparent
    // means none chosen and the theme's own accent applies. Same reading as the dock's.
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

    // Same rule as the island: AetherSerenity is our light scheme, everything else is dark.
    // The key sits at the top level: QSettings maps an INI [General] section to the root.
    void readScheme()
    {
        QSettings kde(m_kdeglobals, QSettings::IniFormat);
        const QString scheme = kde.value(QStringLiteral("ColorScheme")).toString();
        const bool dark = !scheme.contains(QLatin1String("Serenity"), Qt::CaseInsensitive)
            && !scheme.contains(QLatin1String("Light"), Qt::CaseInsensitive);
        if (dark != m_dark) {
            qInfo().noquote() << "scheme:" << scheme << "dark:" << dark;
            m_dark = dark;
            Q_EMIT darkChanged();
        }
    }

    QQuickView *m_view;
    QFileSystemWatcher m_watcher;
    QString m_kdeglobals;
    QString m_islandRc;
    QTimer m_sample;
    BackdropSampler m_sampler;
    QColor m_accent = Qt::transparent;
    QString m_islandMode;
    int m_islandBottom = 0;
    bool m_dark = true;
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
    app.setDesktopFileName(QStringLiteral("org.aether.toasts"));

    QQuickView view;
    view.setColor(Qt::transparent);
    view.setFlags(Qt::FramelessWindowHint | Qt::WindowDoesNotAcceptFocus);
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    const int w = view.screen() ? qMin(view.screen()->size().width(), 460) : 460;
    view.resize(w, 4);

    auto *ls = LayerShellQt::Window::get(&view);
    ls->setLayer(LayerShellQt::Window::LayerOverlay);
    ls->setAnchors(LayerShellQt::Window::AnchorTop);
    ls->setExclusiveZone(0);
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
