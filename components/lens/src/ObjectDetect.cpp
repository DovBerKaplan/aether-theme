// Tap-to-select: find the object under a point in the frozen frame, so one tap marks its bounds.
//
// No accessibility tree is needed (and Wayland offers none): the frame itself says where things
// are. Around the tap the dominant colour is taken for the background, then
//   - a tap ON the background grows a flat-colour region (a card, a button's fill, a panel) and
//     answers with its bounds, unless it is the whole page;
//   - a tap on CONTENT (a picture, an icon, a glyph) takes everything that differs from the
//     background and touches it, closed up by a few pixels so a picture's parts hold together.
#include "LensController.h"

#include <algorithm>
#include <cstdlib>
#include <queue>
#include <vector>

namespace {

struct Img
{
    int w = 0, h = 0;
    std::vector<QRgb> p;
    QRgb at(int x, int y) const { return p[size_t(y) * w + x]; }
};

int dist(QRgb a, QRgb b)
{
    return std::abs(qRed(a) - qRed(b)) + std::abs(qGreen(a) - qGreen(b)) + std::abs(qBlue(a) - qBlue(b));
}

// Box dilation by r, separable: two passes of a sliding "any" over the row and column.
std::vector<uint8_t> dilate(const std::vector<uint8_t> &m, int w, int h, int r)
{
    std::vector<uint8_t> a(m.size(), 0), b(m.size(), 0);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            if (!m[size_t(y) * w + x]) {
                continue;
            }
            const int x0 = std::max(0, x - r), x1 = std::min(w - 1, x + r);
            for (int i = x0; i <= x1; ++i) {
                a[size_t(y) * w + i] = 1;
            }
        }
    }
    for (int x = 0; x < w; ++x) {
        for (int y = 0; y < h; ++y) {
            if (!a[size_t(y) * w + x]) {
                continue;
            }
            const int y0 = std::max(0, y - r), y1 = std::min(h - 1, y + r);
            for (int i = y0; i <= y1; ++i) {
                b[size_t(i) * w + x] = 1;
            }
        }
    }
    return b;
}

} // namespace

QRectF LensController::objectAt(qreal lx, qreal ly)
{
    QImage frame;
    qreal scale = 1;
    {
        QMutexLocker l(&m_lock);
        frame = m_frame;
        scale = m_scale;
    }
    if (frame.isNull()) {
        return QRectF();
    }
    // First choice: the application's own answer (exact), unless it is just "the whole window".
    if (m_a11y.ready()) {
        const QRect a = m_a11y.objectAt(QPoint(int(lx), int(ly)));
        const QSizeF screen = frameSize();
        if (a.width() >= 8 && a.height() >= 8 && a.width() * a.height() < 0.5 * screen.width() * screen.height()) {
            m_lastSource = QStringLiteral("a11y");
            return QRectF(a);
        }
    }
    m_lastSource = QStringLiteral("pixel");
    constexpr int step = 2;   // work at half size: plenty for bounds, four times quicker
    const QImage small = frame.scaled(frame.width() / step, frame.height() / step, Qt::IgnoreAspectRatio,
                                      Qt::FastTransformation).convertToFormat(QImage::Format_RGB32);
    Img im;
    im.w = small.width();
    im.h = small.height();
    im.p.resize(size_t(im.w) * im.h);
    for (int y = 0; y < im.h; ++y) {
        std::copy_n(reinterpret_cast<const QRgb *>(small.constScanLine(y)), im.w, im.p.begin() + size_t(y) * im.w);
    }
    const int sx = std::clamp(int(lx * scale / step), 0, im.w - 1);
    const int sy = std::clamp(int(ly * scale / step), 0, im.h - 1);
    const QRgb seed = im.at(sx, sy);

    // the background around the tap: the most common colour (4 bits a channel) in a window
    constexpr int bgR = 90;
    std::vector<int> bins(4096, 0);
    std::vector<QRgb> sample(4096, 0);
    for (int y = std::max(0, sy - bgR); y <= std::min(im.h - 1, sy + bgR); y += 2) {
        for (int x = std::max(0, sx - bgR); x <= std::min(im.w - 1, sx + bgR); x += 2) {
            const QRgb c = im.at(x, y);
            const int k = ((qRed(c) >> 4) << 8) | ((qGreen(c) >> 4) << 4) | (qBlue(c) >> 4);
            if (bins[k]++ == 0) {
                sample[k] = c;
            }
        }
    }
    const int best = int(std::max_element(bins.begin(), bins.end()) - bins.begin());
    const QRgb bg = sample[best];

    constexpr int tolBg = 36;      // L1 distance: ~12 a channel
    const size_t total = size_t(im.w) * im.h;
    int x0 = sx, x1 = sx, y0 = sy, y1 = sy;
    std::queue<int> q;

    if (dist(seed, bg) < tolBg) {
        // On the background: the flat region around the tap (4-connected, near the seed's colour).
        constexpr int tol = 30;
        std::vector<uint8_t> seen(total, 0);
        size_t area = 0;
        q.push(sy * im.w + sx);
        seen[size_t(sy) * im.w + sx] = 1;
        while (!q.empty()) {
            const int i = q.front();
            q.pop();
            const int x = i % im.w, y = i / im.w;
            if (++area > total * 4 / 10) {
                return QRectF();   // the page itself, not an object
            }
            x0 = std::min(x0, x); x1 = std::max(x1, x); y0 = std::min(y0, y); y1 = std::max(y1, y);
            const int nx[4] = { x - 1, x + 1, x, x }, ny[4] = { y, y, y - 1, y + 1 };
            for (int d = 0; d < 4; ++d) {
                if (nx[d] < 0 || ny[d] < 0 || nx[d] >= im.w || ny[d] >= im.h) {
                    continue;
                }
                const size_t j = size_t(ny[d]) * im.w + nx[d];
                if (!seen[j] && dist(im.p[j], seed) < tol) {
                    seen[j] = 1;
                    q.push(int(j));
                }
            }
        }
        if (x1 - x0 < 24 || y1 - y0 < 24) {
            return QRectF();
        }
    } else {
        // On content: everything unlike the background that touches the tap, within a window.
        constexpr int win = 360;
        const int wx0 = std::max(0, sx - win), wy0 = std::max(0, sy - win);
        const int ww = std::min(im.w, sx + win) - wx0, wh = std::min(im.h, sy + win) - wy0;
        std::vector<uint8_t> mask(size_t(ww) * wh, 0);
        for (int y = 0; y < wh; ++y) {
            for (int x = 0; x < ww; ++x) {
                mask[size_t(y) * ww + x] = dist(im.at(wx0 + x, wy0 + y), bg) >= tolBg;
            }
        }
        const std::vector<uint8_t> closed = dilate(mask, ww, wh, 4);
        std::vector<uint8_t> seen(mask.size(), 0);
        const int cx = sx - wx0, cy = sy - wy0;
        q.push(cy * ww + cx);
        seen[size_t(cy) * ww + cx] = 1;
        x0 = x1 = cx; y0 = y1 = cy;
        while (!q.empty()) {
            const int i = q.front();
            q.pop();
            const int x = i % ww, y = i / ww;
            if (mask[size_t(i)]) {   // bounds from real content, not from the closing
                x0 = std::min(x0, x); x1 = std::max(x1, x); y0 = std::min(y0, y); y1 = std::max(y1, y);
            }
            const int nx[4] = { x - 1, x + 1, x, x }, ny[4] = { y, y, y - 1, y + 1 };
            for (int d = 0; d < 4; ++d) {
                if (nx[d] < 0 || ny[d] < 0 || nx[d] >= ww || ny[d] >= wh) {
                    continue;
                }
                const size_t j = size_t(ny[d]) * ww + nx[d];
                if (!seen[j] && closed[j]) {
                    seen[j] = 1;
                    q.push(int(j));
                }
            }
        }
        x0 += wx0; x1 += wx0; y0 += wy0; y1 += wy0;
        if (x1 - x0 > im.w * 85 / 100 && y1 - y0 > im.h * 85 / 100) {
            return QRectF();
        }
    }
    const qreal k = step / scale;   // small px -> logical px
    return QRectF(x0 * k, y0 * k, (x1 - x0 + 1) * k, (y1 - y0 + 1) * k);
}
