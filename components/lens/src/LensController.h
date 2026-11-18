// LensController: the frozen frame, its words, and everything the overlay can do with a selection.
//
// Activate() captures the screen through KWin (ScreenShot2, granted by org.aether.lens.desktop),
// or Spectacle when KWin refuses, then shows the overlay over a still copy of the screen. OCR
// (tesseract, Hebrew + English) starts at once in the background so a tap on a word is instant.
#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQuickImageProvider>
#include <QRectF>
#include <QVariantList>

#include "A11y.h"

class QNetworkAccessManager;
class QQuickView;

class LensController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int serial READ serial NOTIFY frameChanged)
    Q_PROPERTY(QSizeF frameSize READ frameSize NOTIFY frameChanged)
    Q_PROPERTY(QVariantList words READ words NOTIFY wordsChanged)
    Q_PROPERTY(bool ocrBusy READ ocrBusy NOTIFY ocrBusyChanged)
    Q_PROPERTY(bool ocrAvailable READ ocrAvailable NOTIFY ocrAvailableChanged)
    Q_PROPERTY(QVariantList screenTranslation READ screenTranslation NOTIFY screenTranslationChanged)
    Q_PROPERTY(bool translatingScreen READ translatingScreen NOTIFY translatingScreenChanged)
    Q_PROPERTY(QString lang READ lang NOTIFY langChanged)
    Q_PROPERTY(qreal originX READ originX NOTIFY originChanged)
    Q_PROPERTY(qreal originY READ originY NOTIFY originChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY langChanged)
    Q_PROPERTY(QColor accentOverride READ accentOverride NOTIFY langChanged)

public:
    explicit LensController(QQuickView *view);

    int serial() const { return m_serial; }
    QSizeF frameSize() const;
    QVariantList words() const { return m_words; }
    bool ocrBusy() const { return m_ocrBusy; }
    bool ocrAvailable() const { return m_ocrAvailable; }
    QVariantList screenTranslation() const { return m_screenTranslation; }
    bool translatingScreen() const { return m_translatingScreen; }
    QString lang() const { return m_lang; }
    bool dark() const { return m_dark; }
    QColor accentOverride() const { return m_accent; }

    // For the image provider (any thread).
    QImage frame() const;
    QImage crop() const;

    // Where the opening starts: a point on the screen edge ('bottom'/'left' + fraction along it), or
    // empty for the bottom middle. The glow grows out of it and pulls back into it on close.
    void activate(const QString &edge = QString(), qreal frac = 0.5);
    qreal originX() const { return m_originX; }
    qreal originY() const { return m_originY; }
    void requestClose();
    void requestTranslate() { if (m_shown) Q_EMIT translateRequested(); }
    bool isShown() const { return m_shown; }

    Q_INVOKABLE void setSelection(const QRectF &logical);
    // The bounds of the object under a point (logical px), or an empty rect when there is none.
    Q_INVOKABLE QRectF objectAt(qreal x, qreal y);
    // Source of the last objectAt answer: "a11y" (exact), "pixel" (colour guess) or empty.
    Q_INVOKABLE QString lastObjectSource() const { return m_lastSource; }
    // Ask the segmentation model for the object at a point; the answer comes as objectRefined().
    Q_INVOKABLE int segmentAt(qreal x, qreal y);
    Q_INVOKABLE void finishClose();
    Q_INVOKABLE void searchText(const QString &text);
    Q_INVOKABLE void searchImage(bool wholeScreen);
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void copyImage();
    Q_INVOKABLE void openTranslateWeb(const QString &text);
    Q_INVOKABLE void translate(int requestId, const QString &text);
    Q_INVOKABLE void translateScreen();
    Q_INVOKABLE static bool isRtlText(const QString &text);

Q_SIGNALS:
    void frameChanged();
    void wordsChanged();
    void ocrBusyChanged();
    void ocrAvailableChanged();
    void screenTranslationChanged();
    void translatingScreenChanged();
    void langChanged();
    void originChanged();
    void objectRefined(int token, const QRectF &rect);
    void translateRequested();
    void activated();
    void closeRequested();
    void cropChanged();
    void translated(int requestId, const QString &text, const QString &source, const QString &target);
    void translateFailed(int requestId);
    void toast(const QString &message);

private:
    bool captureKWin(QImage *out);
    bool captureSpectacle(QImage *out);
    void readPreferences();
    void startOcr();
    void startSegmenter();
    void sendSegmenterImage();
    void onSegmenterLine(const QByteArray &line);
    void parseTsv(const QByteArray &tsv);
    void openUrl(const QString &url);
    void hideNow();
    void fetchTranslation(const QString &text, const QString &target,
                          std::function<void(bool, const QString &, const QString &)> done);
    QString runtimeDir() const;

    QQuickView *m_view;
    QNetworkAccessManager *m_net;
    mutable QMutex m_lock;
    QImage m_frame;           // physical pixels
    QRect m_cropPx;           // selection, physical pixels
    qreal m_scale = 1;        // physical / logical
    int m_serial = 0;
    QString m_lastSource;
    QPointer<QProcess> m_seg;
    bool m_segLoaded = false;
    bool m_segReady = false;     // the current frame is embedded
    int m_segToken = 0;
    QPointF m_segPending;        // a tap that came before the embedding was ready
    int m_segPendingToken = 0;
    QByteArray m_segBuf;
    A11yIndex m_a11y;
    bool m_a11yBusy = false;
    bool m_shown = false;
    QVariantList m_words;
    bool m_ocrBusy = false;
    bool m_ocrAvailable = true;
    QStringList m_ocrLangs;
    QPointer<QProcess> m_ocr;
    QVariantList m_screenTranslation;
    bool m_translatingScreen = false;
    QString m_lang = QStringLiteral("en");
    qreal m_originX = 0, m_originY = 0;
    bool m_enabled = true;
    bool m_dark = true;
    QColor m_accent = Qt::transparent;
};

class LensImageProvider : public QQuickImageProvider
{
public:
    explicit LensImageProvider(LensController *c)
        : QQuickImageProvider(QQuickImageProvider::Image), m_c(c) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;
private:
    LensController *m_c;
};
