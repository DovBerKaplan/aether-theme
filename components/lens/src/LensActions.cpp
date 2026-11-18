// What the overlay does with a selection: web search, Google Lens, translation, clipboard.
#include "LensController.h"

#include <QBuffer>
#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMap>
#include <algorithm>
#include <memory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

void LensController::openUrl(const QString &url)
{
    QProcess::startDetached(QStringLiteral("xdg-open"), { url });
}

void LensController::searchText(const QString &text)
{
    const QString q = text.simplified();
    if (q.isEmpty()) {
        return;
    }
    QUrl url(QStringLiteral("https://www.google.com/search"));
    url.setQuery(QUrlQuery{ { QStringLiteral("q"), q } });
    openUrl(url.toString(QUrl::FullyEncoded));
    requestClose();
}

// Google Lens takes an upload only as a multipart form post, so the crop goes into a small local
// page that builds the file in the browser and submits the form on load: the results open in a
// normal tab, signed in like any other search.
void LensController::searchImage(bool wholeScreen)
{
    QImage img = wholeScreen ? frame() : crop();
    if (img.isNull()) {
        return;
    }
    if (qMax(img.width(), img.height()) > 2000) {
        img = img.scaled(2000, 2000, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    QByteArray bytes;
    QBuffer buf(&bytes);
    buf.open(QIODevice::WriteOnly);
    img.convertToFormat(QImage::Format_RGB32).save(&buf, "JPEG", 92);

    const QString hl = m_lang == QLatin1String("he") ? QStringLiteral("iw") : QStringLiteral("en");
    const QString action = QStringLiteral("https://lens.google.com/v3/upload?hl=%1&re=df&ep=gsbubb&st=%2")
                               .arg(hl).arg(QDateTime::currentMSecsSinceEpoch());
    const QString html = QStringLiteral(
        "<!doctype html><meta charset=utf-8><title>Google Lens</title>"
        "<body style=\"background:#1f1f1f\">"
        "<form id=f method=post enctype=multipart/form-data action=\"%1\">"
        "<input type=file name=encoded_image id=i hidden></form><script>"
        "const b=atob('%2');const u=new Uint8Array(b.length);for(let k=0;k<b.length;++k)u[k]=b.charCodeAt(k);"
        "const d=new DataTransfer();d.items.add(new File([u],'screen.jpg',{type:'image/jpeg'}));"
        "document.getElementById('i').files=d.files;document.getElementById('f').submit();"
        "</script>").arg(action, QString::fromLatin1(bytes.toBase64()));

    const QString path = runtimeDir() + QStringLiteral("/lens-%1.html").arg(m_serial);
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    f.write(html.toUtf8());
    f.close();
    openUrl(QUrl::fromLocalFile(path).toString());
    QTimer::singleShot(120000, this, [path] { QFile::remove(path); });   // the browser has posted it by then
    requestClose();
}

static void wlCopy(QObject *parent, const QByteArray &data, const QString &mime)
{
    auto *p = new QProcess(parent);
    QObject::connect(p, &QProcess::finished, p, &QObject::deleteLater);
    QObject::connect(p, &QProcess::errorOccurred, p, &QObject::deleteLater);
    QStringList args;
    if (!mime.isEmpty()) {
        args << QStringLiteral("--type") << mime;
    }
    p->start(QStringLiteral("wl-copy"), args);
    if (p->waitForStarted(1000)) {
        p->write(data);
        p->closeWriteChannel();
    }
}

void LensController::copyText(const QString &text)
{
    if (text.isEmpty()) {
        return;
    }
    wlCopy(this, text.toUtf8(), QString());
    Q_EMIT toast(QStringLiteral("Copied"));
}

void LensController::copyImage()
{
    QByteArray bytes;
    QBuffer buf(&bytes);
    buf.open(QIODevice::WriteOnly);
    crop().save(&buf, "PNG");
    wlCopy(this, bytes, QStringLiteral("image/png"));
    Q_EMIT toast(QStringLiteral("Image copied"));
}

static QString targetFor(const QString &text)
{
    return LensController::isRtlText(text) ? QStringLiteral("en") : QStringLiteral("he");
}

void LensController::openTranslateWeb(const QString &text)
{
    QUrl url(QStringLiteral("https://translate.google.com/"));
    url.setQuery(QUrlQuery{ { QStringLiteral("sl"), QStringLiteral("auto") }, { QStringLiteral("tl"), targetFor(text) },
                            { QStringLiteral("text"), text }, { QStringLiteral("op"), QStringLiteral("translate") } });
    openUrl(url.toString(QUrl::FullyEncoded));
    requestClose();
}

// Google Translate's public web endpoint (the one the translate.google.com widget uses): no key,
// auto-detects the source; the answer is a nested array of [translated, original, ...] segments.
void LensController::fetchTranslation(const QString &text, const QString &target,
                                      std::function<void(bool, const QString &, const QString &)> done)
{
    QUrl url(QStringLiteral("https://translate.googleapis.com/translate_a/single"));
    url.setQuery(QUrlQuery{ { QStringLiteral("client"), QStringLiteral("gtx") }, { QStringLiteral("sl"), QStringLiteral("auto") },
                            { QStringLiteral("tl"), target }, { QStringLiteral("dt"), QStringLiteral("t") } });
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded;charset=utf-8"));
    req.setTransferTimeout(10000);
    QUrlQuery body{ { QStringLiteral("q"), text } };
    QNetworkReply *reply = m_net->post(req, body.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        reply->deleteLater();
        const QJsonArray root = QJsonDocument::fromJson(reply->readAll()).array();
        if (reply->error() != QNetworkReply::NoError || root.isEmpty()) {
            done(false, QString(), QString());
            return;
        }
        QString out;
        for (const QJsonValue &seg : root.at(0).toArray()) {
            out += seg.toArray().at(0).toString();
        }
        done(true, out, root.at(2).toString());
    });
}

void LensController::translate(int requestId, const QString &text)
{
    const QString target = targetFor(text);
    fetchTranslation(text, target, [this, requestId, target](bool ok, const QString &out, const QString &src) {
        if (ok) {
            Q_EMIT translated(requestId, out, src, target);
        } else {
            Q_EMIT translateFailed(requestId);
        }
    });
}

// The colour just outside a line of text: the mean of a 2 px ring around its box, so the
// translated text can be laid over the original as if printed on the same background.
static QColor ringColor(const QImage &img, const QRect &r)
{
    const QRect ring = r.adjusted(-3, -3, 3, 3).intersected(img.rect());
    qint64 sr = 0, sg = 0, sb = 0, n = 0;
    auto add = [&](int x, int y) {
        const QRgb p = img.pixel(x, y);
        sr += qRed(p); sg += qGreen(p); sb += qBlue(p); ++n;
    };
    for (int x = ring.left(); x <= ring.right(); x += 2) {
        add(x, ring.top()); add(x, ring.bottom());
    }
    for (int y = ring.top(); y <= ring.bottom(); y += 2) {
        add(ring.left(), y); add(ring.right(), y);
    }
    return n ? QColor(int(sr / n), int(sg / n), int(sb / n)) : QColor(Qt::white);
}

namespace {

struct Unit
{
    QRectF rect;
    QStringList lines;      // logical text of each line, top to bottom
    qreal lineH = 0;
    qreal lastW = 0;        // width of the paragraph's last line
    bool rtl = false;       // source script
    QString text() const { return lines.join(QLatin1Char(' ')); }
};

// File names, paths, identifiers: not prose, and a translation would only damage them.
bool looksLikeCode(const QString &t)
{
    const QStringList words = t.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (words.isEmpty()) {
        return true;
    }
    int code = 0;
    for (const QString &w : words) {
        static const QRegularExpression re(QStringLiteral("[_/\\\\@=]|\\.[A-Za-z0-9]{1,5}$|^[A-Za-z0-9]{24,}$"));
        code += re.match(w).hasMatch() ? 1 : 0;
    }
    return code * 2 >= words.size();
}

bool hasLetters(const QString &t)
{
    int n = 0;
    for (const QChar c : t) {
        n += c.isLetter() ? 1 : 0;
    }
    return n >= 2;
}

} // namespace

// Translate the whole screen in place. Text is translated by paragraph, not by fragment: lines of one
// paragraph (same script, stacked closely, aligned to the same edge) are joined so a sentence is
// translated whole, and the translation is laid back over the paragraph's box, wrapped. Each unit goes
// to the opposite language of its own script (Hebrew -> English, anything else -> Hebrew).
void LensController::translateScreen()
{
    if (m_translatingScreen || m_words.isEmpty()) {
        return;
    }
    // 1. words -> lines (visual order by x; an RTL line is reversed into logical order)
    struct Line { QRectF rect; QStringList words; int rtlWords = 0; };
    QMap<int, QList<QVariantMap>> byLine;
    for (const QVariant &v : std::as_const(m_words)) {
        const QVariantMap w = v.toMap();
        byLine[w.value(QStringLiteral("line")).toInt()].append(w);
    }
    QList<Unit> lines;
    for (auto it = byLine.begin(); it != byLine.end(); ++it) {
        QList<QVariantMap> ws = it.value();
        std::sort(ws.begin(), ws.end(), [](const QVariantMap &a, const QVariantMap &b) { return a[QStringLiteral("x")].toReal() < b[QStringLiteral("x")].toReal(); });
        Unit u;
        int rtlWords = 0;
        QStringList words;
        for (const QVariantMap &w : ws) {
            const QRectF r(w[QStringLiteral("x")].toReal(), w[QStringLiteral("y")].toReal(), w[QStringLiteral("w")].toReal(), w[QStringLiteral("h")].toReal());
            u.rect = u.rect.isNull() ? r : u.rect.united(r);
            words << w[QStringLiteral("text")].toString();
            rtlWords += w[QStringLiteral("rtl")].toBool() ? 1 : 0;
        }
        u.rtl = rtlWords * 2 > ws.size();
        if (u.rtl) {
            std::reverse(words.begin(), words.end());
        }
        const QString t = words.join(QLatin1Char(' '));
        if (!hasLetters(t) || looksLikeCode(t) || u.rect.height() < 7) {
            continue;
        }
        u.lines << t;
        u.lineH = u.rect.height();
        u.lastW = u.rect.width();
        lines << u;
    }
    std::sort(lines.begin(), lines.end(), [](const Unit &a, const Unit &b) { return a.rect.y() < b.rect.y(); });

    // 2. lines -> paragraphs
    QList<Unit> units;
    for (const Unit &l : std::as_const(lines)) {
        bool joined = false;
        for (Unit &p : units) {
            const qreal gap = l.rect.top() - p.rect.bottom();
            const bool sameSide = l.rtl ? qAbs(l.rect.right() - p.rect.right()) < 14 : qAbs(l.rect.left() - p.rect.left()) < 14;
            const qreal ov = qMin(l.rect.right(), p.rect.right()) - qMax(l.rect.left(), p.rect.left());
            // Wrapped prose fills its lines: the line above must run nearly as wide as the paragraph, or this
            // is a list (menu items, file names, short labels) and each line stands alone.
            const bool prevFull = p.lastW >= 0.8 * p.rect.width() && p.rect.width() > 12 * p.lineH;
            if (p.rtl == l.rtl && gap > -2 && gap < 0.7 * p.lineH && sameSide && ov > 0.3 * qMin(l.rect.width(), p.rect.width())
                && qAbs(l.rect.height() - p.lineH) < 0.5 * p.lineH && prevFull && p.lines.size() < 14) {
                p.rect = p.rect.united(l.rect);
                p.lines << l.lines.first();
                p.lastW = l.rect.width();
                joined = true;
                break;
            }
        }
        if (!joined) {
            units << l;
        }
    }

    // 3. the boxes' colours, and what each will be translated to
    QVariantList result;
    QList<int> toHe, toEn;
    {
        QMutexLocker lk(&m_lock);
        for (int i = 0; i < units.size(); ++i) {
            const Unit &u = units[i];
            const QRect px = QRectF(u.rect.x() * m_scale, u.rect.y() * m_scale, u.rect.width() * m_scale, u.rect.height() * m_scale).toAlignedRect();
            const QColor bg = ringColor(m_frame, px);
            const bool lightBg = 0.299 * bg.redF() + 0.587 * bg.greenF() + 0.114 * bg.blueF() > 0.55;
            result.append(QVariantMap{ { QStringLiteral("x"), u.rect.x() }, { QStringLiteral("y"), u.rect.y() },
                                       { QStringLiteral("w"), u.rect.width() }, { QStringLiteral("h"), u.rect.height() },
                                       { QStringLiteral("bg"), bg }, { QStringLiteral("fg"), QColor(lightBg ? Qt::black : Qt::white) },
                                       { QStringLiteral("rtl"), u.rtl }, { QStringLiteral("fs"), u.lineH * 0.78 },
                                       { QStringLiteral("text"), QString() } });
            (u.rtl ? toEn : toHe).append(i);
        }
    }
    m_screenTranslation = result;
    m_translatingScreen = true;
    Q_EMIT translatingScreenChanged();
    if (units.isEmpty()) {
        m_translatingScreen = false;
        Q_EMIT translatingScreenChanged();
        return;
    }

    // 4. one request per chunk of whole paragraphs and per target language
    auto pending = std::make_shared<int>(0);
    auto finishOne = [this, pending] {
        if (--*pending == 0) {
            m_translatingScreen = false;
            Q_EMIT screenTranslationChanged();
            Q_EMIT translatingScreenChanged();
        }
    };
    const int serial = m_serial;
    auto run = [&](const QList<int> &idx, const QString &target) {
        int start = 0;
        while (start < idx.size()) {
            int end = start, chars = 0;
            QStringList texts;
            while (end < idx.size() && (end == start || chars + units[idx[end]].text().size() < 1500)) {
                texts << units[idx[end]].text().simplified();
                chars += texts.last().size() + 1;
                ++end;
            }
            const QList<int> chunk = idx.mid(start, end - start);
            ++*pending;
            fetchTranslation(texts.join(QLatin1Char('\n')), target, [this, chunk, serial, finishOne](bool ok, const QString &out, const QString &) {
                if (serial == m_serial && ok) {
                    const QStringList back = out.split(QLatin1Char('\n'));
                    for (int i = 0; i < chunk.size(); ++i) {
                        QVariantMap e = m_screenTranslation[chunk[i]].toMap();
                        // If paragraphs came back merged, only the first keeps text (better than a wrong one)
                        e[QStringLiteral("text")] = back.size() == chunk.size() ? back[i].trimmed() : (i == 0 ? out.simplified() : QString());
                        m_screenTranslation[chunk[i]] = e;
                    }
                }
                if (serial == m_serial) {
                    finishOne();
                }
            });
            start = end;
        }
    };
    run(toEn, QStringLiteral("en"));
    run(toHe, QStringLiteral("he"));
    if (*pending == 0) {
        m_translatingScreen = false;
        Q_EMIT translatingScreenChanged();
    }
}

QImage LensImageProvider::requestImage(const QString &id, QSize *size, const QSize &requested)
{
    QImage img = id.startsWith(QLatin1String("crop")) ? m_c->crop() : m_c->frame();
    if (requested.isValid() && !img.isNull()) {
        img = img.scaled(requested, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (size) {
        *size = img.size();
    }
    return img;
}
