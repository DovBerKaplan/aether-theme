#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QImage>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHash>
#include <QMap>
#include <QSet>
#include <QObject>
#include <QPainterPath>
#include <QQuickView>
#include <QRegion>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

#include <fcntl.h>
#include <unistd.h>

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <BackdropSampler.h>

#include <algorithm>

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
    Q_PROPERTY(bool earShown READ earShown NOTIFY earShownChanged)   // [Console] EarShown in aetherislandrc: the resting tab
    Q_PROPERTY(bool underLight READ underLight NOTIFY underLightChanged)   // the desktop beside the resting tab is bright
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

        // The seated terminals' ink follows what shows through their glass (sampleInk).
        m_inkReady = writeInkProfiles();
        m_inkLight = !m_systemDark;   // until the first sample: the glass the system mode wears
        m_inkTimer.setInterval(1500);
        connect(&m_inkTimer, &QTimer::timeout, this, &ConsoleController::sampleInk);
        m_inkTimer.start();
    }

    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }
    QColor accent() const { return m_accent; }
    QString lang() const { return m_lang; }
    bool systemDark() const { return m_systemDark; }
    bool underLight() const { return m_underLight; }
    bool earShown() const { return m_earShown; }

    // What is on screen right beside the resting tab (a strip just inside it, never the tab itself):
    // KWin's ScreenShot2 hands back the raw pixels of a tiny area through a pipe. The mean luma
    // flips underLight with hysteresis, so a mid-grey does not make the tab flicker.
    Q_INVOKABLE void sampleUnder(int y, int h)
    {
        if (m_sampleBusy || !m_view->screen()) {
            return;
        }
        int fds[2];
        if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
            return;
        }
        const QRect geo = m_view->screen()->geometry();
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                           QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("CaptureArea"));
        call << geo.right() - 23 << geo.y() + y << 8u << uint(qMax(1, h))
             << QVariantMap{{QStringLiteral("native-resolution"), true}}
             << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        ::close(fds[1]);   // KWin has its own copy; ours must go so the reader sees the end
        m_sampleBusy = true;
        const int rfd = fds[0];
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 1500), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, rfd](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            m_sampleBusy = false;
            const QDBusPendingReply<QVariantMap> reply = *w;
            QByteArray data;
            char buf[8192];
            for (int tries = 0; tries < 40; ++tries) {
                const ssize_t n = ::read(rfd, buf, sizeof buf);
                if (n > 0) {
                    data.append(buf, int(n));
                } else if (n == 0) {
                    break;
                } else {
                    break;   // EAGAIN: KWin writes the little it has at once; nothing more is coming
                }
            }
            ::close(rfd);
            if (!reply.isValid()) {
                if (!m_sampleWarned) {
                    m_sampleWarned = true;
                    qWarning() << "tab sampling unavailable:" << reply.error().message();
                }
                return;
            }
            const QVariantMap meta = reply.value();
            const int iw = meta.value(QStringLiteral("width")).toInt();
            const int ih = meta.value(QStringLiteral("height")).toInt();
            const int stride = meta.value(QStringLiteral("stride")).toInt();
            const auto fmt = QImage::Format(meta.value(QStringLiteral("format")).toInt());
            if (iw <= 0 || ih <= 0 || data.size() < qsizetype(stride) * ih) {
                return;
            }
            const QImage img(reinterpret_cast<const uchar *>(data.constData()), iw, ih, stride, fmt);
            double sum = 0;
            for (int yy = 0; yy < ih; ++yy) {
                for (int xx = 0; xx < iw; ++xx) {
                    const QRgb c = img.pixel(xx, yy);
                    sum += 0.299 * qRed(c) + 0.587 * qGreen(c) + 0.114 * qBlue(c);
                }
            }
            const double luma = sum / (double(iw) * ih * 255.0);
            const bool light = m_underLight ? luma > 0.45 : luma > 0.62;
            if (light != m_underLight) {
                m_underLight = light;
                qInfo().noquote() << "tab: desktop beside it is" << (light ? "light" : "dark") << "luma" << luma;
                Q_EMIT underLightChanged();
            }
        });
    }
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
    // window beneath the glass (OddEvenFill cuts it from both blur and input; holesTakeInput
    // gives the clicks back to us while an overlay sits above the terminals).
    Q_INVOKABLE void setLayout(const QVariantList &cmds, const QRectF &hot, bool fullInput,
                               const QVariantList &holes = QVariantList(), bool holesTakeInput = false)
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
        const QPainterPath outline = p;   // the silhouette before any hole is cut
        QVector<QRectF> holeRects;
        for (const QVariant &hv : holes) {
            const QVariantMap hole = hv.toMap();
            const QRectF r(hole.value(QStringLiteral("x")).toReal(), hole.value(QStringLiteral("y")).toReal(),
                           hole.value(QStringLiteral("w")).toReal(), hole.value(QStringLiteral("h")).toReal());
            if (r.width() > 0 && r.height() > 0) {
                holeRects.append(r);
                p.addRoundedRect(r, 12, 12);   // OddEvenFill (QPainterPath default) cuts it out
            }
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
        // A seated terminal's window keeps its own clicks and keys (its hole is cut from the input
        // too) - unless something of ours (a menu) is drawn over it: then the whole silhouette takes
        // the clicks, while blur still skips the hole.
        QRegion input = fullInput ? QRegion(QRect(QPoint(0, 0), m_view->size()))
                                  : (holesTakeInput && !cmds.isEmpty() ? QRegion(outline.toFillPolygon().toPolygon()) : shape);
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
    }

    // The terminal seat: pid + geometry travel together to the aether-console-seat KWin
    // script through these keyless global shortcuts (the media-seat handshake).
    // Several terminals can be on stage at once (split view): every pid with a rect is wanted,
    // every other window stays concealed. "Show" re-syncs the script with the whole table.
    Q_INVOKABLE void showSeat(int pid, int x, int y, int w, int h)
    {
        // local (window) coordinates -> screen: the window is anchored right+top, full height
        m_seats.insert(pid, QRect(screenWidth() - m_view->width() + x, y, w, h));
        invokeKwinShortcut(QStringLiteral("Aether Console Seat Show"));
    }
    Q_INVOKABLE void hideSeat(int pid)
    {
        if (m_seats.remove(pid) > 0) {
            if (m_focusPid == pid) {
                m_focusPid = 0;
            }
            invokeKwinShortcut(m_seats.isEmpty() ? QStringLiteral("Aether Console Seat Hide")
                                                 : QStringLiteral("Aether Console Seat Show"));
        }
    }
    // The terminal that should own the keyboard (the focused pane's).
    Q_INVOKABLE void focusSeat(int pid)
    {
        if (m_focusPid != pid) {
            m_focusPid = pid;
            if (m_seats.contains(pid)) {
                invokeKwinShortcut(QStringLiteral("Aether Console Seat Show"));
            }
        }
    }

    // Small persisted preferences (shelf width, split layout) next to the tab position.
    Q_INVOKABLE QString setting(const QString &key) const
    {
        QSettings s(consoleCfg(), QSettings::IniFormat);
        return s.value(QStringLiteral("General/") + key).toString();
    }
    Q_INVOKABLE void setSetting(const QString &key, const QString &value)
    {
        QSettings s(consoleCfg(), QSettings::IniFormat);
        s.setValue(QStringLiteral("General/") + key, value);
        s.sync();
    }

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
    QString seatRect() const   // "focusPid|pid,x,y,w,h;pid,x,y,w,h" in screen coordinates
    {
        QStringList parts;
        for (auto it = m_seats.cbegin(); it != m_seats.cend(); ++it) {
            parts << QStringLiteral("%1,%2,%3,%4,%5").arg(it.key()).arg(it.value().x()).arg(it.value().y())
                         .arg(it.value().width()).arg(it.value().height());
        }
        return QString::number(m_focusPid) + QLatin1Char('|') + parts.join(QLatin1Char(';'));
    }
    void SeatReady(const QString &pid) { Q_EMIT seatReady(pid.toInt()); }   // seated and visible
    void SeatFocused(const QString &pid) { Q_EMIT seatFocused(pid.toInt()); }   // the user clicked into it
    bool ownsWindow(const QString &pid) { return m_seatPids.contains(pid.toInt()); }
    void SeatClosed(const QString &pid)       // a terminal window is gone (ssh died, user closed)
    {
        qWarning("SEATCLOSED %s (registered: %d)", qPrintable(pid), m_seatPids.contains(pid.toInt()));
        m_seatPids.remove(pid.toInt());
        m_seats.remove(pid.toInt());
        if (m_focusPid == pid.toInt()) {
            m_focusPid = 0;
        }
        Q_EMIT seatClosed(pid.toInt());
    }

Q_SIGNALS:
    void stateRequested(const QString &state);
    void accentChanged();
    void langChanged();
    void tabRatioChanged();
    void systemDarkChanged();
    void underLightChanged();
    void earShownChanged();
    void seatReady(int pid);
    void seatFocused(int pid);
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
        const bool ear = s.value(QStringLiteral("Console/EarShown"), true).toBool();
        if (ear != m_earShown) {
            m_earShown = ear;
            Q_EMIT earShownChanged();
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

    // ---- Terminal ink ----------------------------------------------------------------------------
    // A seated terminal is Konsole on clear glass: over a bright window its white text washes out.
    // Every 1.5 s, while terminals are seated, a thin strip of the screen just left of the shelf is
    // captured - what lies behind the shelf, seen where nothing covers it (KWin's capture draws a
    // translucent window over black, so the glass itself cannot be read). Its median luma picks the
    // profile for every seated terminal: AetherDark (light text on the dark glass) or AetherLight
    // (dark text on the Serenity glass), switched over Konsole's DBus, with hysteresis: light past
    // 0.55, dark again below 0.40.

    // AetherDark / AetherLight: the user's Aether profile (font, margins, cursor) with the dark or
    // the light scheme. Rewritten only when they differ.
    static bool writeInkProfiles()
    {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/konsole");
        QFile base(dir + QStringLiteral("/Aether.profile"));
        if (!base.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return false;
        }
        const QStringList lines = QString::fromUtf8(base.readAll()).split(QLatin1Char('\n'));
        const QList<std::pair<QString, QString>> variants{ { QStringLiteral("AetherDark"), QStringLiteral("AetherGlass") },
                                                           { QStringLiteral("AetherLight"), QStringLiteral("AetherSerenity") } };
        for (const auto &[name, scheme] : variants) {
            QStringList out;
            QString group;
            bool schemeSet = false;
            for (const QString &l : lines) {
                if (l.startsWith(QLatin1Char('['))) {
                    if (group == QLatin1String("[Appearance]") && !schemeSet) {
                        out << QStringLiteral("ColorScheme=") + scheme;
                        schemeSet = true;
                    }
                    group = l.trimmed();
                }
                if (group == QLatin1String("[Appearance]") && l.startsWith(QLatin1String("ColorScheme="))) {
                    out << QStringLiteral("ColorScheme=") + scheme;
                    schemeSet = true;
                } else if (group == QLatin1String("[General]") && l.startsWith(QLatin1String("Name="))) {
                    out << QStringLiteral("Name=") + name;
                } else {
                    out << l;
                }
            }
            if (!schemeSet) {
                out.prepend(QStringLiteral("[Appearance]\nColorScheme=") + scheme + QLatin1Char('\n'));
            }
            const QByteArray text = out.join(QLatin1Char('\n')).toUtf8();
            QFile f(dir + QLatin1Char('/') + name + QStringLiteral(".profile"));
            if (f.open(QIODevice::ReadOnly) && f.readAll() == text) {
                continue;
            }
            f.close();
            if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                return false;
            }
            f.write(text);
        }
        return true;
    }

    void setTermProfile(int pid, bool light)
    {
        m_termLight[pid] = light;
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.kde.konsole-%1").arg(pid), QStringLiteral("/Sessions/1"),
                                                        QStringLiteral("org.kde.konsole.Session"), QStringLiteral("setProfile"));
        m << (light ? QStringLiteral("AetherLight") : QStringLiteral("AetherDark"));
        // Konsole applies the profile and still answers AccessDenied ("security sensitive DBus API
        // is disabled"), so the reply is not looked at.
        QDBusConnection::sessionBus().asyncCall(m);
        qInfo().noquote() << "terminal" << pid << "ink:" << (light ? "dark on light glass" : "light on dark glass");
    }

    void sampleInk()
    {
        if (!m_inkReady) {
            return;
        }
        for (auto it = m_termLight.begin(); it != m_termLight.end();) {   // forget closed terminals
            if (!m_seatPids.contains(it.key())) {
                it = m_termLight.erase(it);
            } else {
                ++it;
            }
        }
        if (m_seats.isEmpty() || m_inkBusy) {
            return;
        }
        QRect span;
        for (auto it = m_seats.cbegin(); it != m_seats.cend(); ++it) {
            span |= it.value();
            if (!m_termLight.contains(it.key())) {
                setTermProfile(it.key(), m_inkLight);   // a new terminal joins the others' ink
            }
        }
        // The shelf's glass reaches a little past its terminals; the strip starts beyond that.
        const QRect strip(span.left() - 48, span.top(), 8, span.height());
        if (strip.left() < 0) {
            return;
        }
        m_inkBusy = BackdropSampler::capture(this, strip, [this](const QImage &img) {
            m_inkBusy = false;
            QList<double> lumas;
            for (int y = 0; y < img.height(); y += 2) {
                for (int x = 0; x < img.width(); ++x) {
                    const QRgb c = img.pixel(x, y);
                    lumas.append((0.299 * qRed(c) + 0.587 * qGreen(c) + 0.114 * qBlue(c)) / 255.0);
                }
            }
            if (lumas.size() < 16) {
                return;
            }
            auto mid = lumas.begin() + lumas.size() / 2;
            std::nth_element(lumas.begin(), mid, lumas.end());
            const bool light = m_inkLight ? *mid > 0.40 : *mid > 0.55;
            if (light != m_inkLight) {
                m_inkLight = light;
                qInfo().noquote() << "terminals: the backdrop is" << (light ? "light" : "dark") << "luma" << *mid;
                for (auto it = m_seats.cbegin(); it != m_seats.cend(); ++it) {
                    setTermProfile(it.key(), light);
                }
            }
        });
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
    bool m_underLight = false;
    bool m_earShown = true;
    bool m_sampleBusy = false;
    bool m_sampleWarned = false;
    QMap<int, QRect> m_seats;   // pid -> where its terminal window is wanted (screen coordinates)
    int m_focusPid = 0;
    QSet<int> m_seatPids;
    bool m_online = true;
    QTimer m_inkTimer;
    bool m_inkReady = false;
    QHash<int, bool> m_termLight;   // pid -> on AetherLight (dark text)
    bool m_inkLight = false;        // the backdrop beside the shelf is bright
    bool m_inkBusy = false;

private Q_SLOTS:
    void nmStateChanged(quint32 state)
    {
        setOnline(state == 70);   // NM_STATE_CONNECTED_GLOBAL
    }
};
