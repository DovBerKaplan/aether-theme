#include "A11y.h"

#include <atspi/atspi.h>

#include <QMutexLocker>

namespace {

QRect extentsOf(AtspiAccessible *acc)
{
    AtspiComponent *comp = atspi_accessible_get_component_iface(acc);
    if (!comp) {
        return QRect();
    }
    GError *err = nullptr;
    AtspiRect *r = atspi_component_get_extents(comp, ATSPI_COORD_TYPE_SCREEN, &err);
    g_object_unref(comp);
    if (err) {
        g_error_free(err);
    }
    if (!r) {
        return QRect();
    }
    const QRect out(r->x, r->y, r->width, r->height);
    g_free(r);
    return out;
}

bool hasState(AtspiAccessible *acc, AtspiStateType s)
{
    AtspiStateSet *set = atspi_accessible_get_state_set(acc);
    if (!set) {
        return false;
    }
    const bool on = atspi_state_set_contains(set, s);
    g_object_unref(set);
    return on;
}

} // namespace

A11yIndex::~A11yIndex()
{
    clear();
}

void A11yIndex::clear()
{
    QMutexLocker l(&m_lock);
    for (const Frame &f : std::as_const(m_frames)) {
        g_object_unref(f.acc);
    }
    m_frames.clear();
    m_ready = false;
}

bool A11yIndex::ready() const
{
    QMutexLocker l(&m_lock);
    return m_ready;
}

void A11yIndex::refresh()
{
    clear();
    atspi_init();
    atspi_set_timeout(600, 4000);
    AtspiAccessible *desktop = atspi_get_desktop(0);
    if (!desktop) {
        return;
    }
    QList<Frame> frames;
    GError *err = nullptr;
    const int apps = atspi_accessible_get_child_count(desktop, &err);
    if (err) {
        g_error_free(err);
        err = nullptr;
    }
    for (int i = 0; i < apps; ++i) {
        AtspiAccessible *app = atspi_accessible_get_child_at_index(desktop, i, &err);
        if (err) {
            g_error_free(err);
            err = nullptr;
        }
        if (!app) {
            continue;
        }
        gchar *nm = atspi_accessible_get_name(app, nullptr);
        const QString name = QString::fromUtf8(nm ? nm : "");
        g_free(nm);
        // Our own overlays and the compositor/shell span the whole screen and say nothing useful.
        if (name.startsWith(QLatin1String("aether-")) || name == QLatin1String("kwin") || name == QLatin1String("plasmashell")) {
            g_object_unref(app);
            continue;
        }
        const int kids = atspi_accessible_get_child_count(app, nullptr);
        for (int j = 0; j < kids; ++j) {
            AtspiAccessible *w = atspi_accessible_get_child_at_index(app, j, nullptr);
            if (!w) {
                continue;
            }
            const QRect r = extentsOf(w);
            if (r.width() > 8 && r.height() > 8 && hasState(w, ATSPI_STATE_SHOWING)) {
                frames.append({ r, name, hasState(w, ATSPI_STATE_ACTIVE), w });
            } else {
                g_object_unref(w);
            }
        }
        g_object_unref(app);
    }
    g_object_unref(desktop);
    QMutexLocker l(&m_lock);
    m_frames = frames;
    m_ready = true;
}

QRect A11yIndex::objectAt(const QPoint &p)
{
    AtspiAccessible *frame = nullptr;
    {
        QMutexLocker l(&m_lock);
        // Of the windows under the point: the focused one (it is on top), else the smallest.
        int bestArea = 0;
        bool bestActive = false;
        for (const Frame &f : std::as_const(m_frames)) {
            if (!f.rect.contains(p)) {
                continue;
            }
            const int area = f.rect.width() * f.rect.height();
            if (!frame || (f.active && !bestActive) || (f.active == bestActive && area < bestArea)) {
                frame = f.acc;
                bestArea = area;
                bestActive = f.active;
            }
        }
        if (frame) {
            g_object_ref(frame);
        }
    }
    if (!frame) {
        return QRect();
    }
    // Descend to the deepest object at the point: each toolkit answers for its own children.
    AtspiAccessible *cur = frame;
    for (int depth = 0; depth < 48; ++depth) {
        AtspiComponent *comp = atspi_accessible_get_component_iface(cur);
        if (!comp) {
            break;
        }
        GError *err = nullptr;
        AtspiAccessible *child = atspi_component_get_accessible_at_point(comp, p.x(), p.y(), ATSPI_COORD_TYPE_SCREEN, &err);
        g_object_unref(comp);
        if (err) {
            g_error_free(err);
        }
        if (!child || child == cur) {
            if (child) {
                g_object_unref(child);
            }
            break;
        }
        g_object_unref(cur);
        cur = child;
    }
    // A node without a usable box (a grouping element): climb to the nearest one that has it.
    QRect r = extentsOf(cur);
    for (int up = 0; up < 8 && (r.width() < 4 || r.height() < 4 || !r.contains(p)); ++up) {
        AtspiAccessible *parent = atspi_accessible_get_parent(cur, nullptr);
        g_object_unref(cur);
        cur = parent;
        if (!cur) {
            return QRect();
        }
        r = extentsOf(cur);
    }
    g_object_unref(cur);
    return r.contains(p) ? r : QRect();
}
