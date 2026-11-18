#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QImage>
#include <QObject>
#include <QRect>

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
        if (m_busy || area.width() < 1 || area.height() < 1) {
            return;
        }
        int fds[2];
        if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) != 0) {
            return;
        }
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                           QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("CaptureArea"));
        call << area.x() << area.y() << uint(area.width()) << uint(area.height())
             << QVariantMap{{QStringLiteral("native-resolution"), true}}
             << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        ::close(fds[1]);   // KWin has its own copy; ours must go so the reader sees the end
        m_busy = true;
        const int rfd = fds[0];
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, 1500), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, rfd](QDBusPendingCallWatcher *w) {
            w->deleteLater();
            m_busy = false;
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
                if (!m_warned) {
                    m_warned = true;
                    qWarning() << "backdrop sampling unavailable:" << reply.error().message();
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
            for (int y = 0; y < ih; ++y) {
                for (int x = 0; x < iw; ++x) {
                    const QRgb c = img.pixel(x, y);
                    sum += 0.299 * qRed(c) + 0.587 * qGreen(c) + 0.114 * qBlue(c);
                }
            }
            const double luma = sum / (double(iw) * ih * 255.0);
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

Q_SIGNALS:
    void lightChanged();

private:
    bool m_light = false;
    bool m_valid = false;
    bool m_busy = false;
    bool m_warned = false;
};
