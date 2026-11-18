#include "LensController.h"

#include <QBuffer>
#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusUnixFileDescriptor>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QQuickView>
#include <QRegularExpression>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

#include <fcntl.h>
#include <thread>
#include <unistd.h>

// Native size: doubling the frame halves the misreads but quadruples the time (~20 s here).
static constexpr qreal kOcrUpscale = 1.0;

LensController::LensController(QQuickView *view)
    : QObject(view), m_view(view), m_net(new QNetworkAccessManager(this))
{
    // Which tesseract languages exist decides whether text features are offered at all.
    QProcess p;
    p.start(QStringLiteral("tesseract"), { QStringLiteral("--list-langs") });
    if (!p.waitForFinished(3000) || p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        m_ocrAvailable = false;
    } else {
        const QString out = QString::fromUtf8(p.readAllStandardOutput());
        for (const char *l : { "heb", "eng" }) {
            if (out.contains(QRegularExpression(QStringLiteral("^%1$").arg(QLatin1String(l)),
                                                QRegularExpression::MultilineOption))) {
                m_ocrLangs << QLatin1String(l);
            }
        }
        m_ocrAvailable = !m_ocrLangs.isEmpty();
    }
}

QString LensController::runtimeDir() const
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (base.isEmpty()) {
        base = QDir::tempPath();
    }
    const QString dir = base + QStringLiteral("/aether-lens");
    QDir().mkpath(dir);
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    return dir;
}

QSizeF LensController::frameSize() const
{
    QMutexLocker l(&m_lock);
    return QSizeF(m_frame.width() / m_scale, m_frame.height() / m_scale);
}

QImage LensController::frame() const
{
    QMutexLocker l(&m_lock);
    return m_frame;
}

QImage LensController::crop() const
{
    QMutexLocker l(&m_lock);
    return m_cropPx.isValid() ? m_frame.copy(m_cropPx) : m_frame;
}

// ---- capture ------------------------------------------------------------------------------

bool LensController::captureKWin(QImage *out)
{
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        return false;
    }
    // KWin writes the pixels after it replies, from its own thread: read on ours meanwhile so a
    // full pipe can never stall either side.
    QByteArray data;
    std::thread reader([&data, fd = fds[0]] {
        char buf[1 << 16];
        for (;;) {
            const ssize_t n = ::read(fd, buf, sizeof buf);
            if (n > 0) {
                data.append(buf, n);
            } else if (n == 0 || errno != EINTR) {
                break;
            }
        }
        ::close(fd);
    });

    // The message holds a duplicate of the pipe's write end: it must be gone (like ours) before the
    // reader can see EOF, so the call lives in its own scope.
    QDBusMessage reply;
    {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
            QStringLiteral("/org/kde/KWin/ScreenShot2"), QStringLiteral("org.kde.KWin.ScreenShot2"),
            QStringLiteral("CaptureActiveScreen"));
        QVariantMap options{ { QStringLiteral("include-cursor"), false },
                             { QStringLiteral("native-resolution"), true } };
        call << options << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 4000);
    }
    ::close(fds[1]);
    reader.join();
    if (reply.type() != QDBusMessage::ReplyMessage) {
        qWarning("aether-lens: KWin screenshot refused: %s", qPrintable(reply.errorMessage()));
        return false;
    }

    const QVariantMap r = qdbus_cast<QVariantMap>(reply.arguments().value(0));
    const int w = r.value(QStringLiteral("width")).toInt();
    const int h = r.value(QStringLiteral("height")).toInt();
    const int stride = r.value(QStringLiteral("stride")).toInt();
    const auto fmt = static_cast<QImage::Format>(r.value(QStringLiteral("format")).toInt());
    if (w <= 0 || h <= 0 || data.size() < qsizetype(stride) * h) {
        return false;
    }
    *out = QImage(reinterpret_cast<const uchar *>(data.constData()), w, h, stride, fmt).copy();
    return !out->isNull();
}

bool LensController::captureSpectacle(QImage *out)
{
    const QString path = runtimeDir() + QStringLiteral("/spectacle.png");
    QFile::remove(path);
    QProcess p;
    p.start(QStringLiteral("spectacle"), { QStringLiteral("-b"), QStringLiteral("-n"), QStringLiteral("-m"),
                                           QStringLiteral("-o"), path });
    if (!p.waitForFinished(8000)) {
        p.kill();
        return false;
    }
    *out = QImage(path);
    QFile::remove(path);
    return !out->isNull();
}

void LensController::readPreferences()
{
    QSettings s(QDir::homePath() + QStringLiteral("/.config/aetherislandrc"), QSettings::IniFormat);
    m_lang = s.value(QStringLiteral("Interface/Language"), QStringLiteral("en")).toString();
    QColor c(Qt::transparent);
    if (s.value(QStringLiteral("Appearance/AccentSet")).toBool()) {
        const qreal hue = qBound(0, s.value(QStringLiteral("Appearance/AccentHue"), 183).toInt(), 359) / 360.0;
        const qreal light = qBound(0.25, s.value(QStringLiteral("Appearance/AccentLight"), 0.5).toDouble(), 0.8);
        const qreal sat = qBound(0.15, s.value(QStringLiteral("Appearance/AccentSat"), 1.0).toDouble(), 1.0);
        c = QColor::fromHslF(hue, sat, light);
    }
    m_accent = c;
    m_enabled = s.value(QStringLiteral("Lens/Enabled"), true).toBool();
    Q_EMIT langChanged();
}

void LensController::activate(const QString &edge, qreal frac)
{
    if (m_shown) {
        return;
    }
    readPreferences();
    if (!m_enabled) {
        // switched off from the island: stay quiet, and let go of the model's memory
        if (m_seg && m_seg->state() != QProcess::NotRunning) {
            m_seg->write("{\"cmd\":\"quit\"}\n");
        }
        return;
    }
    QImage img;
    if (!captureKWin(&img) && !captureSpectacle(&img)) {
        qWarning("aether-lens: no screenshot");
        return;
    }
    QScreen *screen = m_view->screen() ? m_view->screen() : QGuiApplication::primaryScreen();
    {
        QMutexLocker l(&m_lock);
        m_frame = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        m_scale = screen && screen->size().width() > 0 ? qreal(m_frame.width()) / screen->size().width() : 1.0;
        m_cropPx = QRect();
    }
    ++m_serial;
    m_words.clear();
    m_screenTranslation.clear();
    Q_EMIT frameChanged();
    Q_EMIT wordsChanged();
    Q_EMIT screenTranslationChanged();

    m_shown = true;
    if (screen) {
        m_view->setGeometry(screen->geometry());
        const QSizeF sz = screen->size();
        frac = qBound<qreal>(0, frac, 1);
        if (edge == QLatin1String("left")) {
            m_originX = 0; m_originY = sz.height() * frac;
        } else if (edge == QLatin1String("top")) {
            m_originX = sz.width() * frac; m_originY = 0;
        } else {
            m_originX = sz.width() * frac; m_originY = sz.height();
        }
        Q_EMIT originChanged();
    }
    m_view->show();
    m_view->requestActivate();
    Q_EMIT activated();
    startOcr();
    startSegmenter();
    // Ask the applications for their windows while the user looks at the frozen screen.
    if (!m_a11yBusy) {
        m_a11yBusy = true;
        std::thread([this] {
            m_a11y.refresh();
            QMetaObject::invokeMethod(this, [this] { m_a11yBusy = false; }, Qt::QueuedConnection);
        }).detach();
    }
}

void LensController::requestClose()
{
    if (m_shown) {
        Q_EMIT closeRequested();
    }
}

void LensController::finishClose()
{
    hideNow();
}

void LensController::hideNow()
{
    if (!m_shown) {
        return;
    }
    m_shown = false;
    m_view->hide();
    if (m_ocr) {
        m_ocr->kill();
    }
    QMutexLocker l(&m_lock);
    m_frame = QImage();   // a full-screen frame is ~8 MB; don't keep it while idle
}

void LensController::setSelection(const QRectF &logical)
{
    {
        QMutexLocker l(&m_lock);
        const QRect px = QRectF(logical.x() * m_scale, logical.y() * m_scale,
                                logical.width() * m_scale, logical.height() * m_scale).toAlignedRect();
        m_cropPx = logical.isEmpty() ? QRect() : px.intersected(m_frame.rect());
    }
    Q_EMIT cropChanged();
}

// ---- OCR ----------------------------------------------------------------------------------

void LensController::startOcr()
{
    if (!m_ocrAvailable) {
        return;
    }
    if (m_ocr) {
        m_ocr->kill();
        m_ocr->deleteLater();
    }
    const QString path = runtimeDir() + QStringLiteral("/frame.png");
    {
        QMutexLocker l(&m_lock);
        QImage g = m_frame.convertToFormat(QImage::Format_Grayscale8);
        g.scaled(g.size() * kOcrUpscale, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).save(path, "PNG", 10);
    }
    m_ocrBusy = true;
    Q_EMIT ocrBusyChanged();
    auto *p = new QProcess(this);
    m_ocr = p;
    // tesseract's own threads fight each other (11 s with four, under 5 s with one).
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("OMP_THREAD_LIMIT"), QStringLiteral("1"));
    p->setProcessEnvironment(env);
    const int serial = m_serial;
    connect(p, &QProcess::finished, this, [this, p, serial, path](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        QFile::remove(path);
        if (serial != m_serial || !m_shown) {
            return;
        }
        if (st == QProcess::NormalExit && code == 0) {
            parseTsv(p->readAllStandardOutput());
        }
        m_ocrBusy = false;
        Q_EMIT ocrBusyChanged();
    });
    p->start(QStringLiteral("tesseract"), { path, QStringLiteral("-"), QStringLiteral("-l"), m_ocrLangs.join(QLatin1Char('+')),
                                            QStringLiteral("--psm"), QStringLiteral("11"), QStringLiteral("tsv") });
}

void LensController::parseTsv(const QByteArray &tsv)
{
    // level page block par line word left top width height conf text
    const qreal k = 1.0 / (kOcrUpscale * m_scale);
    QVariantList words;
    const QList<QByteArray> rows = tsv.split('\n');
    for (int i = 1; i < rows.size(); ++i) {
        const QList<QByteArray> c = rows[i].split('\t');
        if (c.size() < 12 || c[0] != "5") {
            continue;
        }
        const QString text = QString::fromUtf8(c[11]).trimmed();
        const double conf = c[10].toDouble();
        if (text.isEmpty() || conf < 30) {
            continue;
        }
        QVariantMap w;
        w[QStringLiteral("text")] = text;
        w[QStringLiteral("x")] = c[6].toDouble() * k;
        w[QStringLiteral("y")] = c[7].toDouble() * k;
        w[QStringLiteral("w")] = c[8].toDouble() * k;
        w[QStringLiteral("h")] = c[9].toDouble() * k;
        w[QStringLiteral("line")] = c[2].toInt() * 1000000 + c[3].toInt() * 1000 + c[4].toInt();
        w[QStringLiteral("rtl")] = isRtlText(text);
        words.append(w);
    }
    m_words = words;
    Q_EMIT wordsChanged();
}

bool LensController::isRtlText(const QString &text)
{
    for (const QChar ch : text) {
        if (ch.direction() == QChar::DirR || ch.direction() == QChar::DirAL) {
            return true;
        }
        if (ch.direction() == QChar::DirL) {
            return false;
        }
    }
    return false;
}
