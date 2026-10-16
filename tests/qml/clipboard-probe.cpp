#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QQmlExtensionPlugin>
#include <qqml.h>

// Used only with QT_QPA_PLATFORM=offscreen: never touches the user's clipboard.
// Like a foreign Wayland offer, advertising a format does not read its payload.
class ClipboardProbe : public QObject
{
    Q_OBJECT
    int payloadReads = 0;

    class ForeignText : public QMimeData
    {
        int *reads;
    public:
        explicit ForeignText(int *count) : reads(count) {}
        QStringList formats() const override { return {QStringLiteral("text/plain")}; }
        QVariant retrieveData(const QString &, QMetaType) const override
        {
            ++*reads;
            return QStringLiteral("foreign clipboard text");
        }
    };

public:
    ~ClipboardProbe() override { QGuiApplication::clipboard()->clear(); }
    Q_INVOKABLE void offerText()
    {
        payloadReads = 0;
        QGuiApplication::clipboard()->setMimeData(new ForeignText(&payloadReads));
    }
    Q_INVOKABLE int reads() const { return payloadReads; }
    Q_INVOKABLE QString text() const { return QGuiApplication::clipboard()->text(); }
};

class ProbePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterSingletonType<ClipboardProbe>(uri, 1, 0, "ClipboardProbe",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new ClipboardProbe; });
    }
};

#include "clipboard-probe.moc"
