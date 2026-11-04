#pragma once

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QSaveFile>
#include <QSettings>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

// The configs: <name>.json files next to the executable, each a whole set
// of controls (default.json is the first one). QML turns the controls into
// JSON text and back; this reads and writes the current file, lists the
// others and remembers which one was in use (EndfieldVT.ini, same folder).
class ConfigFile : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)          // current config, without ".json"
    Q_PROPERTY(QString path READ path NOTIFY nameChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit ConfigFile(QObject* parent = nullptr) : QObject(parent)
    {
        // The last one used, if it is still there.
        const QString last = settings().value("config").toString();
        if (validName(last) && QFile::exists(fileOf(last))) m_name = last;
    }

    QString name() const { return m_name; }
    QString path() const { return fileOf(m_name); }
    QString lastError() const { return m_error; }

    Q_INVOKABLE bool exists() const { return QFile::exists(path()); }

    // The file's text; empty, with lastError set, when it cannot be read.
    Q_INVOKABLE QString read()
    {
        QFile file(path());
        if (!file.open(QIODevice::ReadOnly)) {
            setError(file.errorString());
            return {};
        }
        setError({});
        return QString::fromUtf8(file.readAll());
    }

    // Replaces the file in one step: a crash mid-write keeps the old one.
    Q_INVOKABLE bool write(const QString& text) { return writeTo(path(), text); }

    // Config names in the folder, sorted, default first: every *.json that
    // is a JSON object with a "controls" array (other JSON files are not
    // configs and are left out).
    Q_INVOKABLE QStringList list() const
    {
        QStringList names;
        const QFileInfoList files = QDir(dir()).entryInfoList({"*.json"}, QDir::Files, QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo& f : files) {
            const QString n = f.completeBaseName();
            if (n == m_name || isConfig(f.filePath())) names << n;
        }
        if (!names.contains(m_name)) names << m_name; // current, not saved yet
        names.removeAll("default");
        names.prepend("default");
        return names;
    }

    // Makes `name` current (the caller has saved the old one and reads the
    // new one after). False, with lastError, when the name is not usable.
    Q_INVOKABLE bool open(const QString& name)
    {
        if (!validName(name)) return fail("名称不能为空，也不能含 \\ / : * ? \" < > |");
        if (name != m_name) {
            m_name = name;
            settings().setValue("config", m_name);
            emit nameChanged();
        }
        setError({});
        return true;
    }

    // A new config file with `text`; refuses to overwrite one that exists.
    Q_INVOKABLE bool create(const QString& name, const QString& text)
    {
        if (!validName(name)) return fail("名称不能为空，也不能含 \\ / : * ? \" < > |");
        if (QFile::exists(fileOf(name))) return fail("已经有叫「" + name + "」的配置");
        return writeTo(fileOf(name), text);
    }

    Q_INVOKABLE void openFolder() const { QDesktopServices::openUrl(QUrl::fromLocalFile(dir())); }

    Q_INVOKABLE bool validName(const QString& name) const
    {
        static const QString bad = QStringLiteral("\\/:*?\"<>|");
        if (name.trimmed().isEmpty() || name != name.trimmed() || name.endsWith('.')) return false;
        for (QChar c : name)
            if (bad.contains(c) || c < QChar(32)) return false;
        return true;
    }

signals:
    void nameChanged();
    void lastErrorChanged();

private:
    static QString dir() { return QCoreApplication::applicationDirPath(); }
    static QString fileOf(const QString& name) { return QDir(dir()).filePath(name + ".json"); }
    static QSettings settings() { return QSettings(QDir(dir()).filePath("EndfieldVT.ini"), QSettings::IniFormat); }

    static bool isConfig(const QString& file)
    {
        QFile f(file);
        if (!f.open(QIODevice::ReadOnly)) return false;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        return doc.isObject() && doc.object().value("controls").isArray();
    }

    bool writeTo(const QString& file, const QString& text)
    {
        QSaveFile out(file);
        if (!out.open(QIODevice::WriteOnly) || out.write(text.toUtf8()) < 0 || !out.commit())
            return fail(out.errorString());
        setError({});
        return true;
    }
    bool fail(const QString& error)
    {
        setError(error);
        return false;
    }
    void setError(const QString& error)
    {
        if (error == m_error) return;
        m_error = error;
        emit lastErrorChanged();
    }

    QString m_name = QStringLiteral("default");
    QString m_error;
};
