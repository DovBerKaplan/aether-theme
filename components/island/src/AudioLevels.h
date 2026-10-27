// Five loudness bands (bass .. treble, 0..1) of whatever the speakers are playing, for the
// music bars. Cheap by design: parec streams the default output's monitor as 8 kHz mono,
// five one-pole filters split it, one RMS per band per 50 ms chunk (~20 updates/s). The
// capture only runs while something holds it (bars on screen AND music playing) - idle cost is zero.
#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <algorithm>
#include <array>
#include <cmath>

class AudioLevels : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList bands READ bands NOTIFY bandsChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)   // false until real samples arrive
public:
    explicit AudioLevels(QObject *parent = nullptr) : QObject(parent)
    {
        m_proc.setProgram(QStringLiteral("parec"));
        m_proc.setArguments({QStringLiteral("-d"), QStringLiteral("@DEFAULT_MONITOR@"),
                             QStringLiteral("--rate=8000"), QStringLiteral("--channels=1"),
                             QStringLiteral("--format=s16le"), QStringLiteral("--latency-msec=50")});
        connect(&m_proc, &QProcess::readyReadStandardOutput, this, &AudioLevels::onData);
        connect(&m_proc, &QProcess::finished, this, [this] { reset(); });
        connect(&m_proc, &QProcess::errorOccurred, this, [this] { reset(); });
        reset();
    }
    ~AudioLevels() override { m_proc.kill(); m_proc.waitForFinished(500); }

    QVariantList bands() const { return m_out; }
    bool available() const { return m_available; }

    // Reference-counted: the bars call acquire() when they start dancing and release() when they stop.
    Q_INVOKABLE void acquire()
    {
        if (m_holders++ == 0)
            m_proc.start();
    }
    Q_INVOKABLE void release()
    {
        if (m_holders > 0 && --m_holders == 0) {
            m_proc.kill();
            reset();
        }
    }

signals:
    void bandsChanged();
    void availableChanged();

private:
    static constexpr int N = 5;
    static constexpr double Rate = 8000.0;
    // Band edges in Hz: the signal is split by differences of low-passes at these cut-offs.
    static constexpr std::array<double, N - 1> Cut = {120, 350, 900, 2000};

    void reset()
    {
        m_lp.fill({});
        m_peak.fill(1e-4);
        m_smooth.fill(0);
        m_buf.clear();
        m_out = QVariantList(N, 0.0);
        if (m_available) { m_available = false; emit availableChanged(); }
        emit bandsChanged();
    }

    void onData()
    {
        m_buf += m_proc.readAllStandardOutput();
        constexpr int chunk = 400 * 2;                          // 400 samples = 50 ms
        while (m_buf.size() >= chunk) {
            const auto *s = reinterpret_cast<const qint16 *>(m_buf.constData());
            std::array<double, N> energy{};
            for (int i = 0; i < chunk / 2; ++i) {
                const double x = s[i] / 32768.0;
                for (int k = 0; k < N - 1; ++k) {
                    const double a = 1.0 - std::exp(-2.0 * M_PI * Cut[k] / Rate);
                    m_lp[k] += a * (x - m_lp[k]);
                }
                // Band 0 = below Cut[0]; band k = between Cut[k-1] and Cut[k]; band N-1 = above the last.
                energy[0] += m_lp[0] * m_lp[0];
                for (int k = 1; k < N - 1; ++k) { const double d = m_lp[k] - m_lp[k - 1]; energy[k] += d * d; }
                const double top = x - m_lp[N - 2]; energy[N - 1] += top * top;
            }
            m_buf.remove(0, chunk);

            double total = 0;
            std::array<double, N> rms{};
            for (int k = 0; k < N; ++k) { rms[k] = std::sqrt(energy[k] / (chunk / 2)); total += rms[k]; }
            const bool silent = total < 0.002;
            for (int k = 0; k < N; ++k) {
                // Per-band auto-gain: the peak follower falls slowly, so each band fills its own range.
                m_peak[k] = std::max({rms[k], m_peak[k] * 0.985, 0.004});
                double v = silent ? 0.0 : std::clamp(rms[k] / m_peak[k], 0.0, 1.0);
                v = std::pow(v, 1.4);                           // quiet detail stays low, hits stand out
                m_smooth[k] = v > m_smooth[k] ? v : m_smooth[k] * 0.72 + v * 0.28;   // fast attack, soft release
                m_out[k] = m_smooth[k];
            }
            if (!m_available) { m_available = true; emit availableChanged(); }
            emit bandsChanged();
        }
    }

    QProcess m_proc;
    int m_holders = 0;
    bool m_available = false;
    QByteArray m_buf;
    std::array<double, N - 1> m_lp{};
    std::array<double, N> m_peak{};
    std::array<double, N> m_smooth{};
    QVariantList m_out;
};
