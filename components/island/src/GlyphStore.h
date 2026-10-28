// One stroke width for every icon, whatever its size. The glyph files are drawn on a 16-unit grid with a
// fixed stroke in grid units, so they would thicken and thin with the icon. file() writes (once, into the
// cache) a copy whose stroke is the wanted number of *screen pixels* for the size it will be drawn at, and
// returns that file; filled glyphs (no stroke) are returned as they are.
#pragma once

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

class GlyphStore : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE QUrl file(const QUrl &source, int size, qreal strokePx)
    {
        const QString path = source.toLocalFile();
        QFile in(path);
        if (path.isEmpty() || size <= 0 || !in.open(QIODevice::ReadOnly)) {
            return source;
        }
        QString svg = QString::fromUtf8(in.readAll());
        in.close();
        static const QRegularExpression stroke(QStringLiteral("stroke-width=\"[0-9.]+\""));
        if (!svg.contains(stroke)) {
            return source;
        }
        const QFileInfo info(path);
        const qreal units = strokePx * 16.0 / size;          // the grid is 16 units wide
        const QByteArray key = (info.absoluteFilePath() + QString::number(info.lastModified().toMSecsSinceEpoch()) + QLatin1Char('|')
                                + QString::number(size) + QLatin1Char('|') + QString::number(units, 'f', 3)).toUtf8();
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/glyphs");
        const QString out = dir + QLatin1Char('/') + info.completeBaseName() + QLatin1Char('-')
                            + QString::fromLatin1(QCryptographicHash::hash(key, QCryptographicHash::Sha1).toHex().left(10)) + QStringLiteral(".svg");
        if (!QFileInfo::exists(out)) {
            QDir().mkpath(dir);
            svg.replace(stroke, QStringLiteral("stroke-width=\"%1\"").arg(units, 0, 'f', 3));
            QFile f(out);
            if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                return source;
            }
            f.write(svg.toUtf8());
        }
        return QUrl::fromLocalFile(out);
    }
};
