#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QSet>
#include <QObject>
#include <QPainterPath>
#include <QQuickView>
#include <QRegion>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#include <KWindowEffects>
#include <LayerShellQt/Window>

// The console's window: one layer-shell surface pinned to the right edge (top+bottom anchored,
// so it is always the full screen height). The window itself never resizes - it spans the whole
// screen so a click outside the open panel can close it - and QML reports what is visible and
// clickable through setLayout(). The user's island settings (accent colour, language) are read
// from aetherislandrc so the shelf always matches the bar.
class ConsoleController : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aether.Console")
    Q_PROPERTY(int screenWidth READ screenWidth CONSTANT)
    Q_PROPERTY(int screenHeight READ screenHeight CONSTANT)
    Q_PROPERTY(QColor accent READ accent NOTIFY accentChanged)   // "transparent" = the theme's own
    Q_PROPERTY(QString lang READ lang NOTIFY langChanged)
    // Where the resting tab sits along the right edge, as a fraction of the usable height
    // (0 = top edge, 1 = bottom) - the phone's Smart-Sidebar handle, dragged and saved.
    Q_PROPERTY(qreal tabRatio READ tabRatio WRITE setTabRatio NOTIFY tabRatioChanged)
    // The system colour scheme (kdeglobals, the dock's heuristic). The shelf glass is always
    // the island's dark object, but the little tab lives directly on the desktop and should
    // rim itself against what is actually behind it.
    Q_PROPERTY(bool systemDark READ systemDark NOTIFY systemDarkChanged)
    // NetworkManager's reachability: when the machine loses the network, every open session's
    // dot goes orange (the tmux on the server kept the work); back online, they return green.
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)

public:
    explicit ConsoleController(QQuickView *view)
        : QObject(view), m_view(view)
    {
        m_cfg = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                + QStringLiteral("/aetherislandrc");
        m_kdeglobals = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, &ConsoleController::reread);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
        m_poll.setInterval(4000);
        connect(&m_poll, &QTimer::timeout, this, [this] {
            if (!m_watcher.files().contains(m_cfg)) {
                m_watcher.addPath(m_cfg);   // the island rewrites the file: re-arm and read
            }
            const QDateTime t = QFileInfo(m_cfg).lastModified();
            if (t != m_lastModified) {
                m_lastModified = t;
                m_debounce.start();
            }
        });
        m_poll.start();
        reread();
        nmWatch();
    }

    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }
    QColor accent() const { return m_accent; }
    QString lang() const { return m_lang; }
    bool systemDark() const { return m_systemDark; }
    bool online() const { return m_online; }

    // Every launched terminal registers its pid, so the KWin script can ask (synchronously,
    // from its windowAdded) whether a mapping window is one of ours.
    Q_INVOKABLE void registerSeat(int pid) { m_seatPids.insert(pid); }
    qreal tabRatio() const
    {
        QSettings s(consoleCfg(), QSettings::IniFormat);
        return qBound(0.0, s.value(QStringLiteral("General/ConsoleTabY"), 0.18).toReal(), 1.0);
    }
    void setTabRatio(qreal r)
    {
        r = qBound(0.0, r, 1.0);
        if (qFuzzyCompare(r, tabRatio())) {
            return;
        }
        QSettings s(consoleCfg(), QSettings::IniFormat);
        s.setValue(QStringLiteral("General/ConsoleTabY"), r);
        s.sync();
        Q_EMIT tabRatioChanged();
    }

    Q_INVOKABLE void setWindowSize(int w, int h)
    {
        if (QSize(w, h) != m_view->size()) {
            m_view->resize(w, h);
        }
    }

    // The silhouette arrives as path commands (the same list QML draws from), so blur, input and
    // drawing cannot disagree. hot: an invisible strip that still gets the pointer (the resting
    // ear). hole: a rounded cut-out whose clicks and keyboard belong to the seated terminal
    // window beneath the glass (OddEvenFill cuts it from both blur and input).
    Q_INVOKABLE void setLayout(const QVariantList &cmds, const QRectF &hot, bool fullInput,
                               const QVariantMap &hole = QVariantMap())
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
        QRectF holeRect(hole.value(QStringLiteral("x")).toReal(), hole.value(QStringLiteral("y")).toReal(),
                        hole.value(QStringLiteral("w")).toReal(), hole.value(QStringLiteral("h")).toReal());
        if (holeRect.width() > 0 && holeRect.height() > 0) {
            p.addRoundedRect(holeRect, 12, 12);   // OddEvenFill (QPainterPath default) cuts it out
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
        // While the panel is open the whole window takes input, to catch click-outside; at rest
        // only the ear listens, so nothing else on screen loses a single click.
        QRegion input = fullInput ? QRegion(QRect(QPoint(0, 0), m_view->size())) : shape;
        if (holeRect.width() > 0 && holeRect.height() > 0) {
            // The seated terminal's window keeps its own clicks and keys.
            input -= QRegion(holeRect.toRect());
        }
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
    }

    // The terminal seat: pid + geometry travel together to the aether-console-seat KWin
    // script through these keyless global shortcuts (the media-seat handshake).
    Q_INVOKABLE void showSeat(int pid, int x, int y, int w, int h)
    {
        m_seatPid = pid;
        m_seatRect = QRect(x, y, w, h);
        invokeKwinShortcut(QStringLiteral("Aether Console Seat Show"));
    }
    Q_INVOKABLE void hideSeat() { invokeKwinShortcut(QStringLiteral("Aether Console Seat Hide")); }

    Q_INVOKABLE void setKeyboard(bool wanted)
    {
        if (auto *ls = LayerShellQt::Window::get(m_view)) {
            ls->setKeyboardInteractivity(wanted ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                                                : LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }

public Q_SLOTS:
    // org.aether.Console - a shortcut or a script drives the shelf:
    //   qdbus6 org.aether.Console /Console org.aether.Console.Toggle
    void Show() { Q_EMIT stateRequested(QStringLiteral("shown")); }
    void Hide() { Q_EMIT stateRequested(QStringLiteral("hidden")); }
    void Toggle() { Q_EMIT stateRequested(QStringLiteral("toggle")); }
    // Called by the aether-console-seat KWin script.
    QString seatRect() const   // "pid,x,y,w,h" in screen coordinates
    {
        return QStringLiteral("%1,%2,%3,%4,%5").arg(m_seatPid).arg(m_seatRect.x()).arg(m_seatRect.y())
            .arg(m_seatRect.width()).arg(m_seatRect.height());
    }
    void SeatReady() { Q_EMIT seatReady(); }   // seated and visible: the frost may clear
    bool ownsWindow(const QString &pid) { return m_seatPids.contains(pid.toInt()); }
    void SeatClosed(const QString &pid)       // a terminal window is gone (ssh died, user closed)
    {
        qWarning("SEATCLOSED %s (registered: %d)", qPrintable(pid), m_seatPids.contains(pid.toInt()));
        m_seatPids.remove(pid.toInt());
        Q_EMIT seatClosed(pid.toInt());
    }

Q_SIGNALS:
    void stateRequested(const QString &state);
    void accentChanged();
    void langChanged();
    void tabRatioChanged();
    void systemDarkChanged();
    void seatReady();
    void seatClosed(int pid);
    void onlineChanged();

private:
    void nmWatch()
    {
        QDBusConnection::systemBus().connect(QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager"), QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("StateChanged"), this, SLOT(nmStateChanged(quint32)));
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("/org/freedesktop/NetworkManager"), QStringLiteral("org.freedesktop.NetworkManager"),
            QStringLiteral("state"));
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            QDBusPendingReply<uint> r = *watcher;
            if (!r.isError()) {
                setOnline(r.value() == 70);
            }
            watcher->deleteLater();
        });
    }
    void setOnline(bool on)
    {
        if (on != m_online) {
            m_online = on;
            Q_EMIT onlineChanged();
        }
    }
    static void invokeKwinShortcut(const QString &name)
    {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"),
                                                  QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
        msg << name;
        QDBusConnection::sessionBus().asyncCall(msg);
    }
    static QString consoleCfg()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
               + QStringLiteral("/aetherconsolerc");
    }
    void reread()
    {
        m_lastModified = QFileInfo(m_cfg).lastModified();
        if (!m_watcher.files().contains(m_cfg)) {
            m_watcher.addPath(m_cfg);
        }
        if (!m_kdeglobals.isEmpty() && !m_watcher.files().contains(m_kdeglobals)) {
            m_watcher.addPath(m_kdeglobals);   // a scheme switch replaces the file
        }
        QSettings s(m_cfg, QSettings::IniFormat);
        QColor accent = Qt::transparent;
        if (s.value(QStringLiteral("Appearance/AccentSet"), false).toBool()) {
            const qreal h = s.value(QStringLiteral("Appearance/AccentHue"), 183).toInt() / 360.0;
            const qreal sat = qBound(0.0, s.value(QStringLiteral("Appearance/AccentSat"), 1.0).toReal(), 1.0);
            const qreal lig = qBound(0.0, s.value(QStringLiteral("Appearance/AccentLight"), 0.5).toReal(), 1.0);
            accent = QColor::fromHslF(qBound<qreal>(0.0, h, 1.0), sat, lig);
            if (!accent.isValid()) {
                accent = Qt::transparent;
            }
        }
        const QString lang = s.value(QStringLiteral("Interface/Language"), QStringLiteral("en")).toString();
        if (accent != m_accent) {
            m_accent = accent;
            Q_EMIT accentChanged();
        }
        if (lang != m_lang) {
            m_lang = lang;
            Q_EMIT langChanged();
        }
        readScheme();
    }
    // The scheme *name* is not always written to kdeglobals; light or dark is judged from the
    // window background colour the scheme actually installed (the dock's proven heuristic).
    void readScheme()
    {
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
        if (dark != m_systemDark) {
            m_systemDark = dark;
            Q_EMIT systemDarkChanged();
        }
    }

    QQuickView *m_view;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_poll;
    QDateTime m_lastModified;
    QString m_cfg;
    QString m_kdeglobals;
    QColor m_accent = Qt::transparent;
    QString m_lang = QStringLiteral("en");
    bool m_systemDark = true;
    int m_seatPid = 0;
    QRect m_seatRect;
    QSet<int> m_seatPids;
    bool m_online = true;

private Q_SLOTS:
    void nmStateChanged(quint32 state)
    {
        setOnline(state == 70);   // NM_STATE_CONNECTED_GLOBAL
    }
};
