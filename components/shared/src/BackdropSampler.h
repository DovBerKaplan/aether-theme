#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QImage>
#include <QObject>
#include <QRect>

#include <functional>

#include <fcntl.h>
#include <unistd.h>

// Looks at what the desktop shows in a small area (KWin's ScreenShot2 hands the raw pixels back
// through a pipe) and says whether it is bright. The caller picks an area that lies beside its own
// window, never under it, so the answer is about the backdrop and not about itself. The mean luma
// flips `light` with hysteresis, so a mid-grey does not make the UI flicker. The calling program's
// desktop file must list org.kde.KWin.ScreenShot2 in X-KDE-DBUS-Restricted-Interfaces; without it
// the call fails once (logged) and `light` stays false.
class BackdropSampler : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    bool light() const { return m_light; }
    bool valid() const { return m_valid; }   // at least one sample came back: the answer is a measurement

    // `area` is in compositor (global) coordinates.
    void sample(const QRect &area)
    {
        if (m_busy) {
            return;
        }
        m_busy = capture(this, area, [this](const QImage &img) {
            m_busy = false;
            if (img.isNull()) {
                return;
            }
            const double luma = meanLuma(img, img.rect());
            if (!m_valid) {
                m_valid = true;
                Q_EMIT lightChanged();
            }
            const bool light = m_light ? luma > 0.45 : luma > 0.62;
            if (light != m_light) {
                m_light = light;
                qInfo().noquote() << "backdrop is now" << (light ? "light" : "dark") << "luma" << luma;
                Q_EMIT lightChanged();
            }
        });
    }

    // Mean luma (0..1) of `r` within `img`. With `skipInk`, pixels near pure white or pure black are
    // left out: those are text and its shadow over the backdrop, not the backdrop itself.
    static double meanLuma(const QImage &img, const QRect &r, bool skipInk = false)
    {
        const QRect a = r.intersected(img.rect());
        double sum = 0;
        qint64 n = 0;
        for (int y = a.top(); y <= a.bottom(); ++y) {
            for (int x = a.left(); x <= a.right(); ++x) {
                const QRgb c = img.pixel(x, y);
                const double l = (0.299 * qRed(c) + 0.587 * qGreen(c) + 0.114 * qBlue(c)) / 255.0;
                if (skipInk && (l > 0.96 || l < 0.04)) {
                    continue;
                }
                sum += l;
                ++n;
            }
        }
        return n ? sum / n : -1;
    }

    // One shot of `area` (global coordinates); `done` gets the pixels, or a null image when KWin
    // refused. Returns false when nothing was asked (empty area, no pipe) - `done` is not called then.
    static bool capture(QObject *ctx, const QRect &area, std::function<void(const QImage &)> done)
    {
        if (area.width() < 1 || area.height() < 1) {
            return false;
        }
        int fds[2];
        if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
            return false;
        }
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                           QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("CaptureArea"));
        call << area.x() << area.y() << uint(area.width()) << uint(area.height())
             << QVariantMap{{QStringLiteral("native-resolution"), true}}
             << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        ::close(fds[1]);   // KWin has its own copy; ours must go so the reader sees the end
        const int rfd = fds[0];
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 1500), ctx);
        QObject::connect(w, &QDBusPendingCallWatcher::finished, ctx, [rfd, done](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            const QDBusPendingReply<QVariantMap> reply = *w;
            QByteArray data;
            char buf[8192];
            for (;;) {
                const ssize_t n = ::read(rfd, buf, sizeof buf);
                if (n <= 0) {
                    break;   // end, or EAGAIN: KWin wrote the little it has at once
                }
                data.append(buf, int(n));
            }
            ::close(rfd);
            if (!reply.isValid()) {
                static bool warned = false;
                if (!warned) {
                    warned = true;
                    qWarning() << "backdrop sampling unavailable:" << reply.error().message();
                }
                done(QImage());
                return;
            }
            const QVariantMap meta = reply.value();
            const int iw = meta.value(QStringLiteral("width")).toInt();
            const int ih = meta.value(QStringLiteral("height")).toInt();
            const int stride = meta.value(QStringLiteral("stride")).toInt();
            const auto fmt = QImage::Format(meta.value(QStringLiteral("format")).toInt());
            if (iw <= 0 || ih <= 0 || data.size() < qsizetype(stride) * ih) {
                done(QImage());
                return;
            }
            done(QImage(reinterpret_cast<const uchar *>(data.constData()), iw, ih, stride, fmt).copy());
        });
        return true;
    }

Q_SIGNALS:
    void lightChanged();

private:
    bool m_light = false;
    bool m_valid = false;
    bool m_busy = false;
};
