#pragma once

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QObject>
#include <QSaveFile>
#include <QtQml/qqmlregistration.h>

// default.json next to the executable, where the controls are kept. QML
// turns the controls into JSON text and back; this only reads and writes.
class ConfigFile : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit ConfigFile(QObject* parent = nullptr) : QObject(parent) {}

    QString path() const { return QDir(QCoreApplication::applicationDirPath()).filePath("default.json"); }
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
    Q_INVOKABLE bool write(const QString& text)
    {
        QSaveFile file(path());
        if (!file.open(QIODevice::WriteOnly) || file.write(text.toUtf8()) < 0 || !file.commit()) {
            setError(file.errorString());
            return false;
        }
        setError({});
        return true;
    }

signals:
    void lastErrorChanged();

private:
    void setError(const QString& error)
    {
        if (error == m_error) return;
        m_error = error;
        emit lastErrorChanged();
    }

    QString m_error;
};
