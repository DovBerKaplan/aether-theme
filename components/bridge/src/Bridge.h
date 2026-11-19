// AetherBridge: the one-plumbing QML module the patched Folder View imports. The desktop's
// empty-area right click hands its point to the desk's glass arrange panel over the session
// bus; nothing else lives here. Installed into the system Qt qml dir by
// install/install-desktop-menu.sh - remove it together with the patch.
#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QObject>
#include <QtQml/qqml.h>

class AetherBridge : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit AetherBridge(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    // From Folder View: the right click on the desktop's empty area, in its own coordinates
    // (the desk's surface spans the same screen, so they carry over). Fire and forget: the
    // panel opening is the desk's business.
    Q_INVOKABLE void openArrange(int x, int y)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.aether.Desk"),
            QStringLiteral("/Desk"), QStringLiteral("org.aether.Desk"), QStringLiteral("OpenArrange"));
        m << x << y;
        QDBusConnection::sessionBus().asyncCall(m);
    }
};
