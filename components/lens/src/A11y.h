// A11y: the exact bounds of whatever is under a point, asked of the application itself over AT-SPI
// (the accessibility bus). Toolkits that publish their widgets - GTK, Qt, Chrome and Electron once
// accessibility is on - answer with the real rectangle of the button, picture or paragraph.
#pragma once

#include <QList>
#include <QMutex>
#include <QPoint>
#include <QRect>
#include <QString>

typedef struct _AtspiAccessible AtspiAccessible;

class A11yIndex
{
public:
    ~A11yIndex();
    // Collect the visible top-level windows (called off the UI thread when the overlay opens).
    void refresh();
    // The smallest accessible rectangle (screen px) under the point, or an empty rect.
    QRect objectAt(const QPoint &screenPoint);
    bool ready() const;

private:
    struct Frame
    {
        QRect rect;
        QString app;
        bool active = false;
        AtspiAccessible *acc = nullptr;
    };
    void clear();

    mutable QMutex m_lock;
    QList<Frame> m_frames;
    bool m_ready = false;
};
