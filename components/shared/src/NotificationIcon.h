// Resolving a notification's app icon — shared verbatim between aether-toasts and the
// island's history. Senders vary wildly: an app_icon that is a theme name or a path,
// Chromium/Electron image-path values that are file:// URLs, raw image-data pixels,
// or nothing but a desktop-entry whose name differs from its icon ("code" → "vscode").
// This mirrors what real notification daemons do; only when everything fails does the
// caller fall back to the generic icon.
#pragma once

#include <QFile>
#include <QHash>
#include <QIcon>
#include <QImage>
#include <QJsonArray>
#include <QJsonObject>
#include <QPixmap>
#include <QStandardPaths>
#include <QUrl>

namespace NotificationIcon {

// Raw-pixel hints cannot travel to QML as a string, so decoded pixmaps are parked here
// and the id "data:<n>" refers to them.
inline QHash<QString, QPixmap> &decoded()
{
    static QHash<QString, QPixmap> cache;
    return cache;
}

// The freedesktop "(iiibiiay)" hint value: width, height, rowstride, has-alpha, bits,
// channels, then the sample bytes in RGBA order.
inline QString fromPixels(const QJsonObject &hint)
{
    const QJsonArray d = hint.value(QStringLiteral("data")).toArray();
    if (d.size() < 7 || d.at(4).toInt() != 8) {
        return {};
    }
    const int w = d.at(0).toInt(), h = d.at(1).toInt(), rowstride = d.at(2).toInt();
    const int channels = d.at(5).toInt();
    if (w <= 0 || w > 2048 || h <= 0 || h > 2048 || (channels != 3 && channels != 4)) {
        return {};
    }
    const QJsonArray bytes = d.at(6).toArray();
    if (bytes.size() < (h - 1) * rowstride + w * channels) {
        return {};
    }
    QByteArray raw;
    raw.resize(bytes.size());
    for (int i = 0; i < bytes.size(); ++i) {
        raw[i] = static_cast<char>(bytes.at(i).toInt(0));
    }
    const QImage::Format fmt = channels == 4 ? QImage::Format_RGBA8888 : QImage::Format_RGB888;
    const QImage img(reinterpret_cast<const uchar *>(raw.constData()), w, h, rowstride, fmt);
    if (img.isNull()) {
        return {};
    }
    static int n = 0;
    const QString id = QStringLiteral("data:%1").arg(++n);
    decoded().insert(id, QPixmap::fromImage(img.copy()));   // copy detaches from the line buffer
    return id;
}

// Icon= of an installed .desktop file; the desktop-entry name and the icon name often differ.
inline QString iconOfDesktopEntry(const QString &entry)
{
    if (entry.isEmpty() || entry.contains(QLatin1Char('/'))) {
        return {};
    }
    const QStringList dirs = QStandardPaths::locateAll(QStandardPaths::GenericDataLocation,
                                                       QStringLiteral("applications"),
                                                       QStandardPaths::LocateDirectory);
    for (const QString &dir : dirs) {
        QFile f(dir + QLatin1Char('/') + entry + QStringLiteral(".desktop"));
        if (!f.open(QIODevice::ReadOnly)) {
            continue;
        }
        while (!f.atEnd()) {
            const QByteArray line = f.readLine();
            if (line.startsWith("Icon=")) {
                return QString::fromUtf8(line.mid(5)).trimmed();
            }
        }
    }
    return {};
}

// Whatever a hint / app_icon value means (file:// URL, plain path or theme name) as an
// IconProvider id.
inline QString asIconId(const QString &value)
{
    if (value.isEmpty()) {
        return {};
    }
    const QUrl url(value);
    if (url.isLocalFile()) {
        return url.toLocalFile();
    }
    return value;
}

// An id the IconProvider can turn into the sender's icon; empty means generic fallback.
inline QString resolve(const QString &app, const QString &appIcon, const QJsonObject &hints)
{
    auto str = [&hints](const char *name) {
        return hints.value(QLatin1String(name)).toObject().value(QStringLiteral("data")).toString();
    };
    for (const char *name : {"image-data", "image_data", "icon-data", "icon_data"}) {
        const QJsonObject hint = hints.value(QLatin1String(name)).toObject();
        if (!hint.isEmpty()) {
            const QString id = fromPixels(hint);
            if (!id.isEmpty()) {
                return id;
            }
        }
    }
    for (const char *name : {"image-path", "image_path"}) {
        const QString id = asIconId(str(name));
        if (!id.isEmpty()) {
            return id;
        }
    }
    const QString fromParam = asIconId(appIcon);
    if (!fromParam.isEmpty()) {
        return fromParam;
    }
    for (const char *name : {"desktop-entry", "desktop_entry"}) {
        const QString entry = str(name);
        if (!entry.isEmpty()) {
            const QString icon = iconOfDesktopEntry(entry);
            if (!icon.isEmpty()) {
                return icon;
            }
            return entry;   // entries are often named after their icon anyway
        }
    }
    if (!app.isEmpty() && QIcon::hasThemeIcon(app.toLower())) {
        return app.toLower();
    }
    return {};
}

}   // namespace NotificationIcon
