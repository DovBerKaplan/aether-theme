#pragma once

#include <QColor>
#include <QDateTime>
#include <QFileInfo>
#include <QFileSystemWatcher>
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

public:
    explicit ConsoleController(QQuickView *view)
        : QObject(view), m_view(view)
    {
        m_cfg = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                + QStringLiteral("/aetherislandrc");
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
    }

    int screenWidth() const { return m_view->screen() ? m_view->screen()->size().width() : 1920; }
    int screenHeight() const { return m_view->screen() ? m_view->screen()->size().height() : 1080; }
    QColor accent() const { return m_accent; }
    QString lang() const { return m_lang; }

    Q_INVOKABLE void setWindowSize(int w, int h)
    {
        if (QSize(w, h) != m_view->size()) {
            m_view->resize(w, h);
        }
    }

    // The silhouette arrives as path commands (the same list QML draws from), so blur, input and
    // drawing cannot disagree. hot: an invisible strip that still gets the pointer (the resting ear).
    Q_INVOKABLE void setLayout(const QVariantList &cmds, const QRectF &hot, bool fullInput)
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
        // While the panel is open the whole window takes input, to catch click-outside; at rest
        // only the ear listens, so nothing else on screen loses a single click.
        QRegion input = fullInput ? QRegion(QRect(QPoint(0, 0), m_view->size())) : shape;
        if (!hot.isEmpty()) {
            input += QRegion(hot.toRect());
        }
        m_view->setMask(input.isEmpty() ? QRegion(0, 0, 1, 1) : input);
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

Q_SIGNALS:
    void stateRequested(const QString &state);
    void accentChanged();
    void langChanged();

private:
    void reread()
    {
        m_lastModified = QFileInfo(m_cfg).lastModified();
        if (!m_watcher.files().contains(m_cfg)) {
            m_watcher.addPath(m_cfg);
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
    }

    QQuickView *m_view;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_poll;
    QDateTime m_lastModified;
    QString m_cfg;
    QColor m_accent = Qt::transparent;
    QString m_lang = QStringLiteral("en");
};
