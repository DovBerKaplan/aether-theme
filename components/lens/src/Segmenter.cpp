// The segmentation helper: a resident Python process (segmenter/lens_segment.py, MobileSAM) that
// embeds the frozen screen in the background and answers "what object is at this point?" in ~50 ms.
// It is optional: without the model file the overlay simply keeps the other ways of finding bounds.
#include "LensController.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>

static QString modelPath()
{
    return QDir::homePath() + QStringLiteral("/.local/share/aether-lens/models/mobile_sam.pt");
}

static QString scriptPath()
{
    const QString installed = QCoreApplication::applicationDirPath() + QStringLiteral("/../share/aether-lens/segmenter/lens_segment.py");
    return QFile::exists(installed) ? QDir::cleanPath(installed) : QStringLiteral(AETHER_SEGMENTER_DIR "/lens_segment.py");
}

static void sendLine(QProcess *p, const QJsonObject &o)
{
    p->write(QJsonDocument(o).toJson(QJsonDocument::Compact) + '\n');
}

void LensController::startSegmenter()
{
    if (!QFile::exists(modelPath()) || !QFile::exists(scriptPath())) {
        return;
    }
    m_segReady = false;
    if (m_seg && m_seg->state() != QProcess::NotRunning) {
        if (m_segLoaded) {
            sendSegmenterImage();   // already warm: just embed the new frame
        }
        return;
    }
    m_segLoaded = false;
    m_segBuf.clear();
    auto *p = new QProcess(this);
    m_seg = p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("YOLO_OFFLINE"), QStringLiteral("1"));   // no network, no analytics
    env.insert(QStringLiteral("YOLO_CONFIG_DIR"), QDir::homePath() + QStringLiteral("/.local/share/aether-lens/ultralytics"));
    p->setProcessEnvironment(env);
    p->setProcessChannelMode(QProcess::SeparateChannels);
    connect(p, &QProcess::readyReadStandardOutput, this, [this, p] {
        m_segBuf += p->readAllStandardOutput();
        int nl;
        while ((nl = m_segBuf.indexOf('\n')) >= 0) {
            const QByteArray line = m_segBuf.left(nl);
            m_segBuf.remove(0, nl + 1);
            onSegmenterLine(line);
        }
    });
    connect(p, &QProcess::finished, this, [this, p] {
        p->deleteLater();
        m_segLoaded = m_segReady = false;
    });
    p->start(QStringLiteral("python3"), { scriptPath() });
}

void LensController::sendSegmenterImage()
{
    if (!m_seg || !m_segLoaded) {
        return;
    }
    const QString path = runtimeDir() + QStringLiteral("/seg-frame.bmp");
    {
        QMutexLocker l(&m_lock);
        if (m_frame.isNull() || !m_frame.save(path, "BMP")) {
            return;
        }
    }
    m_segReady = false;
    sendLine(m_seg, { { QStringLiteral("cmd"), QStringLiteral("image") }, { QStringLiteral("path"), path } });
}

void LensController::onSegmenterLine(const QByteArray &line)
{
    const QJsonObject o = QJsonDocument::fromJson(line).object();
    const QString ev = o.value(QStringLiteral("event")).toString();
    if (ev == QLatin1String("loaded")) {
        m_segLoaded = true;
        if (m_shown) {
            sendSegmenterImage();
        }
    } else if (ev == QLatin1String("ready")) {
        m_segReady = true;
        if (m_segPendingToken == m_segToken && m_segPendingToken != 0 && m_shown) {
            sendLine(m_seg, { { QStringLiteral("cmd"), QStringLiteral("point") }, { QStringLiteral("id"), m_segPendingToken },
                              { QStringLiteral("x"), m_segPending.x() }, { QStringLiteral("y"), m_segPending.y() } });
            m_segPendingToken = 0;
        }
    } else if (o.contains(QStringLiteral("id"))) {
        const int token = o.value(QStringLiteral("id")).toInt();
        if (token != m_segToken || !m_shown) {
            return;   // a newer tap, or the overlay is gone
        }
        const QJsonArray r = o.value(QStringLiteral("rect")).toArray();
        QRectF rect;
        if (r.size() == 4) {
            rect = QRectF(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble());
            rect = QRectF(rect.x() / m_scale, rect.y() / m_scale, rect.width() / m_scale, rect.height() / m_scale);
        }
        Q_EMIT objectRefined(token, rect);
    }
}

int LensController::segmentAt(qreal x, qreal y)
{
    const int token = ++m_segToken;
    if (!m_seg || !m_segLoaded) {
        return token;   // no model: the caller keeps what it has
    }
    const QPointF px(x * m_scale, y * m_scale);
    if (!m_segReady) {
        m_segPending = px;
        m_segPendingToken = token;   // sent as soon as the embedding is ready
        return token;
    }
    sendLine(m_seg, { { QStringLiteral("cmd"), QStringLiteral("point") }, { QStringLiteral("id"), token },
                      { QStringLiteral("x"), px.x() }, { QStringLiteral("y"), px.y() } });
    return token;
}
