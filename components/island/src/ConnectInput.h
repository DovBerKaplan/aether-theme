// Typing to the phone from the island: the remote keyboard and sending a text message.
// Kept apart from ConnectModel (device state) because this part only acts when asked, and the
// contact cache it reads is private: it is loaded when the Messages page opens, used for recipient
// suggestions only, never logged and dropped from memory when the page closes.
//
// AETHER_CONNECT_FAKE=1: nothing is sent; the actions record what they would have done.
#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QVariantList>
#include <QVariantMap>

class ConnectInput : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool keyboardReady READ keyboardReady NOTIFY keyboardChanged)   // the phone has the KDE Connect keyboard switched on
    Q_PROPERTY(QVariantMap lastAction READ lastAction NOTIFY lastActionChanged)

public:
    explicit ConnectInput(QObject *parent = nullptr)
        : QObject(parent)
        , m_fake(qEnvironmentVariableIntValue("AETHER_CONNECT_FAKE") != 0)
    {
        if (!m_fake) {
            QDBusConnection::sessionBus().connect(Service, QString(), QStringLiteral("org.kde.kdeconnect.device.remotekeyboard"), QStringLiteral("remoteStateChanged"),
                                                  this, SLOT(onKeyboardState(QDBusMessage)));
        }
    }
    bool keyboardReady() const { return m_ready; }
    QVariantMap lastAction() const { return m_last; }

    // ---- remote keyboard -----------------------------------------------------------------
    Q_INVOKABLE void watchKeyboard(const QString &id, bool on)
    {
        m_watchId = on ? id : QString();
        if (on) {
            readKeyboard();
        }
    }
    // Type text on the phone, one key press per character (Enter for a new line). Only when asked.
    Q_INVOKABLE void typeText(const QString &id, const QString &name, const QString &text)
    {
        const QString t = text.left(500);
        if (t.isEmpty()) {
            return;
        }
        note(QStringLiteral("typed"), name);
        if (m_fake) {
            return;
        }
        for (const QChar &c : t) {
            if (c == QLatin1Char('\n')) {
                sendSpecial(id, 16777220);   // Qt::Key_Return
            } else {
                key(id, QString(c), -1);
            }
        }
    }
    // A key that is not a character: Qt key codes (Backspace 16777219, Tab 16777217, arrows 16777234..37, Return 16777220).
    Q_INVOKABLE void sendKey(const QString &id, int qtKey)
    {
        if (!m_fake) {
            sendSpecial(id, qtKey);
        }
    }

    // ---- messages ------------------------------------------------------------------------
    // Send a text from the phone's own number. The number is checked; nothing but the device name is logged.
    Q_INVOKABLE bool sendSms(const QString &id, const QString &name, const QString &number, const QString &text)
    {
        static const QRegularExpression ok(QStringLiteral("^[+0-9 ()\\-]{3,24}$"));
        const QString n = number.trimmed(), t = text.trimmed();
        if (!ok.match(n).hasMatch() || t.isEmpty() || t.size() > 1000) {
            return false;
        }
        note(QStringLiteral("sms"), name);
        if (!m_fake) {
            QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/sms"), QStringLiteral("org.kde.kdeconnect.device.sms"), QStringLiteral("sendSms"));
            m << QVariant::fromValue(QVariantList{n}) << t << QVariant::fromValue(QVariantList());
            QDBusConnection::sessionBus().asyncCall(m);
        }
        return true;
    }
    // Reading conversations is not something the daemon offers over D-Bus (checked: no signals, no objects), so
    // reading is handed to KDE Connect's own SMS app, which the daemon launches for this device.
    Q_INVOKABLE void openMessagesApp(const QString &id, const QString &name)
    {
        note(QStringLiteral("sms-app"), name);
        if (!m_fake) {
            QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/sms"), QStringLiteral("org.kde.kdeconnect.device.sms"), QStringLiteral("launchApp")));
        }
    }
    // Recipient suggestions from the phone's contact cache: [{name, number}], at most 6.
    Q_INVOKABLE QVariantList suggest(const QString &id, const QString &query)
    {
        const QString q = query.trimmed().toLower();
        QString digits;
        for (const QChar &c : q) {
            if (c.isDigit()) {
                digits += c;
            }
        }
        if (q.size() < 2) {
            return {};
        }
        if (m_contactsFor != id) {
            loadContacts(id);
        }
        QVariantList out;
        for (const Contact &c : std::as_const(m_contacts)) {
            if (c.name.toLower().contains(q) || (digits.size() >= 3 && c.digits.contains(digits))) {
                out << QVariantMap{{QStringLiteral("name"), c.name}, {QStringLiteral("number"), c.number}};
                if (out.size() >= 6) {
                    break;
                }
            }
        }
        return out;
    }
    Q_INVOKABLE void closeContacts() { m_contacts.clear(); m_contactsFor.clear(); }

Q_SIGNALS:
    void keyboardChanged();
    void lastActionChanged();

private Q_SLOTS:
    void onKeyboardState(const QDBusMessage &) { readKeyboard(); }

private:
    struct Contact { QString name, number, digits; };
    static inline const QString Service = QStringLiteral("org.kde.kdeconnect");
    static QString devPath(const QString &id) { return QStringLiteral("/modules/kdeconnect/devices/") + id; }

    void note(const QString &kind, const QString &device)
    {
        m_last = {{QStringLiteral("kind"), kind}, {QStringLiteral("device"), device}};
        qInfo().noquote() << "kdeconnect:" << kind << device << (m_fake ? "(fake: nothing sent)" : "");
        Q_EMIT lastActionChanged();
    }
    void readKeyboard()
    {
        bool ready = m_fake;
        if (!m_fake && !m_watchId.isEmpty()) {
            QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(m_watchId) + QStringLiteral("/remotekeyboard"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
            m << QStringLiteral("org.kde.kdeconnect.device.remotekeyboard") << QStringLiteral("remoteState");
            const QDBusMessage r = QDBusConnection::sessionBus().call(m, QDBus::Block, 1000);
            ready = r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty() && r.arguments().first().value<QDBusVariant>().variant().toBool();
        }
        if (ready != m_ready) {
            m_ready = ready;
            Q_EMIT keyboardChanged();
        }
    }
    void key(const QString &id, const QString &k, int special)
    {
        QDBusMessage m = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/remotekeyboard"), QStringLiteral("org.kde.kdeconnect.device.remotekeyboard"), QStringLiteral("sendKeyPress"));
        m << k;
        if (special >= 0) {
            m << special;
        }
        QDBusConnection::sessionBus().asyncCall(m);
    }
    void sendSpecial(const QString &id, int qtKey)
    {
        QDBusMessage t = QDBusMessage::createMethodCall(Service, devPath(id) + QStringLiteral("/remotekeyboard"), QStringLiteral("org.kde.kdeconnect.device.remotekeyboard"), QStringLiteral("translateQtKey"));
        t << qtKey;
        const QDBusReply<int> r = QDBusConnection::sessionBus().call(t, QDBus::Block, 800);
        if (r.isValid() && r.value() > 0) {
            key(id, QString(), r.value());
        }
    }
    // vCards the daemon syncs per device. FN and TEL only; quoted-printable (non-Latin names) is decoded.
    void loadContacts(const QString &id)
    {
        m_contacts.clear();
        m_contactsFor = id;
        if (m_fake) {
            for (const auto &p : {std::pair{"Dana Levi", "+1 555 0100"}, std::pair{"Noa Cohen", "+1 555 0111"}, std::pair{"Ori Katz", "+1 555 0122"}, std::pair{"Tom Bar", "+1 555 0133"}}) {
                m_contacts.append({QString::fromLatin1(p.first), QString::fromLatin1(p.second), QString::fromLatin1(p.second).remove(QRegularExpression(QStringLiteral("\\D")))});
            }
            return;
        }
        const QDir dir(QDir::homePath() + QStringLiteral("/.local/share/kpeoplevcard/kdeconnect-") + id);
        for (const QString &f : dir.entryList({QStringLiteral("*.vcard"), QStringLiteral("*.vcf")}, QDir::Files)) {
            QFile file(dir.filePath(f));
            if (!file.open(QIODevice::ReadOnly)) {
                continue;
            }
            QString name;
            QStringList numbers;
            for (const QByteArray &line : file.readAll().split('\n')) {
                const int colon = line.indexOf(':');
                if (colon < 0) {
                    continue;
                }
                const QByteArray head = line.left(colon).toUpper();
                QByteArray value = line.mid(colon + 1).trimmed();
                if (head.contains("QUOTED-PRINTABLE")) {
                    value = QByteArray::fromPercentEncoding(value, '=');
                }
                if (head == "FN" || head.startsWith("FN;")) {
                    name = QString::fromUtf8(value);
                } else if (head == "TEL" || head.startsWith("TEL;")) {
                    numbers << QString::fromUtf8(value);
                }
            }
            for (const QString &n : std::as_const(numbers)) {
                QString d = n;
                m_contacts.append({name.isEmpty() ? n : name, n, d.remove(QRegularExpression(QStringLiteral("\\D")))});
            }
        }
    }

    const bool m_fake;
    bool m_ready = false;
    QString m_watchId, m_contactsFor;
    QVariantMap m_last;
    QList<Contact> m_contacts;
};
