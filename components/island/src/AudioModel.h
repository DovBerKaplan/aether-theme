// Sound panel backend: outputs, inputs and per-app streams from PipeWire's PulseAudio layer.
// No library needed - `pactl -f json list ...` for state, `pactl subscribe` for events. While
// the panel is closed nothing runs (the chips' own volume readout stays in SystemInfo).
#pragma once

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class AudioModel : public QObject
{
    Q_OBJECT
    // [{name, description, isDefault, volume 0-100, muted, bluetooth}]
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY changed)
    Q_PROPERTY(QVariantList inputs READ inputs NOTIFY changed)
    // [{index, name, icon, volume, muted, paused}]
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)

public:
    explicit AudioModel(QObject *parent = nullptr)
        : QObject(parent)
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(150);
        connect(&m_debounce, &QTimer::timeout, this, [this] { refresh(); });
        connect(&m_subscribe, &QProcess::readyReadStandardOutput, this, [this] {
            // "Event 'change' on sink #51" - anything about sinks, sources, streams or the server
            const QString out = QString::fromUtf8(m_subscribe.readAllStandardOutput());
            if (out.contains(QLatin1String("sink")) || out.contains(QLatin1String("source")) || out.contains(QLatin1String("server"))) {
                m_debounce.start();
            }
        });
        connect(&m_subscribe, &QProcess::finished, this, [this] {
            if (m_active) {
                QTimer::singleShot(1000, this, [this] { if (m_active) startSubscribe(); });   // pipewire-pulse restarted
            }
        });
    }
    ~AudioModel() override { m_subscribe.kill(); m_subscribe.waitForFinished(300); }

    QVariantList outputs() const { return m_outputs; }
    QVariantList inputs() const { return m_inputs; }
    QVariantList apps() const { return m_apps; }

    Q_INVOKABLE void setActive(bool on)
    {
        if (m_active == on) {
            return;
        }
        m_active = on;
        if (on) {
            refresh();
            startSubscribe();
        } else {
            m_subscribe.kill();
        }
    }
    // Make `sink` the default output and move every playing stream to it.
    Q_INVOKABLE void setDefaultOutput(const QString &sink)
    {
        pactl({QStringLiteral("set-default-sink"), sink});
        for (const QVariant &a : std::as_const(m_apps)) {
            pactl({QStringLiteral("move-sink-input"), QString::number(a.toMap().value(QStringLiteral("index")).toInt()), sink});
        }
        m_debounce.start();
    }
    Q_INVOKABLE void setOutputVolume(const QString &sink, int pct) { pactl({QStringLiteral("set-sink-volume"), sink, percent(pct)}); }
    Q_INVOKABLE void setOutputMuted(const QString &sink, bool muted) { pactl({QStringLiteral("set-sink-mute"), sink, muted ? QStringLiteral("1") : QStringLiteral("0")}); m_debounce.start(); }
    Q_INVOKABLE void setInputVolume(const QString &source, int pct) { pactl({QStringLiteral("set-source-volume"), source, percent(pct)}); }
    Q_INVOKABLE void setInputMuted(const QString &source, bool muted) { pactl({QStringLiteral("set-source-mute"), source, muted ? QStringLiteral("1") : QStringLiteral("0")}); m_debounce.start(); }
    Q_INVOKABLE void setAppVolume(int index, int pct) { pactl({QStringLiteral("set-sink-input-volume"), QString::number(index), percent(pct)}); }
    Q_INVOKABLE void setAppMuted(int index, bool muted) { pactl({QStringLiteral("set-sink-input-mute"), QString::number(index), muted ? QStringLiteral("1") : QStringLiteral("0")}); m_debounce.start(); }
    Q_INVOKABLE void openSettings() { QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_pulseaudio")}); }

Q_SIGNALS:
    void changed();

private:
    static QString percent(int pct) { return QString::number(qBound(0, pct, 100)) + QLatin1Char('%'); }
    static void pactl(const QStringList &args) { QProcess::startDetached(QStringLiteral("pactl"), args); }
    void startSubscribe()
    {
        if (m_subscribe.state() == QProcess::NotRunning) {
            m_subscribe.start(QStringLiteral("pactl"), {QStringLiteral("subscribe")});
        }
    }
    static int volumeOf(const QJsonObject &o)
    {
        const QJsonObject v = o.value(QStringLiteral("volume")).toObject();
        if (v.isEmpty()) {
            return 0;
        }
        return qRound(v.begin().value().toObject().value(QStringLiteral("value")).toDouble() / 65536.0 * 100.0);
    }

    // Three listings, run in parallel; the model is rebuilt when the last one lands.
    void refresh()
    {
        if (m_pending > 0) {
            m_again = true;
            return;
        }
        m_pending = 4;
        m_again = false;
        list(QStringLiteral("sinks"), [this](const QJsonArray &a) { m_rawSinks = a; });
        list(QStringLiteral("sources"), [this](const QJsonArray &a) { m_rawSources = a; });
        list(QStringLiteral("sink-inputs"), [this](const QJsonArray &a) { m_rawInputs = a; });
        auto *info = new QProcess(this);
        connect(info, &QProcess::finished, this, [this, info] {
            for (const QString &l : QString::fromUtf8(info->readAllStandardOutput()).split(QLatin1Char('\n'))) {
                if (l.startsWith(QLatin1String("Default Sink:"))) { m_defaultSink = l.mid(13).trimmed(); }
            }
            info->deleteLater();
            done();
        });
        info->start(QStringLiteral("pactl"), {QStringLiteral("info")});
    }
    template<typename F> void list(const QString &what, F store)
    {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p, store] {
            store(QJsonDocument::fromJson(p->readAllStandardOutput()).array());
            p->deleteLater();
            done();
        });
        p->start(QStringLiteral("pactl"), {QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), what});
    }
    void done()
    {
        if (--m_pending > 0) {
            return;
        }
        rebuild();
        if (m_again) {
            refresh();
        }
    }
    void rebuild()
    {
        QVariantList outs, ins, apps;
        for (const QJsonValue &v : std::as_const(m_rawSinks)) {
            const QJsonObject o = v.toObject();
            const QString name = o.value(QStringLiteral("name")).toString();
            outs << QVariantMap{{QStringLiteral("name"), name},
                                {QStringLiteral("description"), o.value(QStringLiteral("description")).toString()},
                                {QStringLiteral("isDefault"), name == m_defaultSink},
                                {QStringLiteral("volume"), volumeOf(o)},
                                {QStringLiteral("muted"), o.value(QStringLiteral("mute")).toBool()},
                                {QStringLiteral("bluetooth"), o.value(QStringLiteral("properties")).toObject().value(QStringLiteral("device.bus")).toString() == QLatin1String("bluetooth")
                                                                  || name.startsWith(QLatin1String("bluez_"))}};
        }
        for (const QJsonValue &v : std::as_const(m_rawSources)) {
            const QJsonObject o = v.toObject();
            const QString name = o.value(QStringLiteral("name")).toString();
            if (name.endsWith(QLatin1String(".monitor"))) {
                continue;   // a sink's loopback, not a microphone
            }
            ins << QVariantMap{{QStringLiteral("name"), name},
                               {QStringLiteral("description"), o.value(QStringLiteral("description")).toString()},
                               {QStringLiteral("volume"), volumeOf(o)},
                               {QStringLiteral("muted"), o.value(QStringLiteral("mute")).toBool()}};
        }
        for (const QJsonValue &v : std::as_const(m_rawInputs)) {
            const QJsonObject o = v.toObject();
            const QJsonObject p = o.value(QStringLiteral("properties")).toObject();
            QString name = p.value(QStringLiteral("application.name")).toString();
            if (name.isEmpty()) {
                name = p.value(QStringLiteral("media.name")).toString();
            }
            apps << QVariantMap{{QStringLiteral("index"), o.value(QStringLiteral("index")).toInt()},
                                {QStringLiteral("name"), name},
                                {QStringLiteral("detail"), p.value(QStringLiteral("media.name")).toString()},
                                {QStringLiteral("volume"), volumeOf(o)},
                                {QStringLiteral("muted"), o.value(QStringLiteral("mute")).toBool()},
                                {QStringLiteral("paused"), o.value(QStringLiteral("corked")).toBool()}};
        }
        if (outs != m_outputs || ins != m_inputs || apps != m_apps) {
            m_outputs = outs;
            m_inputs = ins;
            m_apps = apps;
            Q_EMIT changed();
        }
    }

    QProcess m_subscribe;
    QTimer m_debounce;
    bool m_active = false, m_again = false;
    int m_pending = 0;
    QString m_defaultSink;
    QJsonArray m_rawSinks, m_rawSources, m_rawInputs;
    QVariantList m_outputs, m_inputs, m_apps;
};
