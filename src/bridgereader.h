#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QSortFilterProxyModel>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <memory>

// Rows of named values for QML, updated in place by a key column so that
// delegates survive refreshes: changed rows get dataChanged, new rows are
// inserted, missing rows removed, reordered rows moved.
class KeyedListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    KeyedListModel(const QByteArrayList& roles, const QByteArray& key, QObject* parent = nullptr);

    int count() const { return int(m_rows.size()); }
    int rowCount(const QModelIndex& parent = {}) const override { return parent.isValid() ? 0 : count(); }
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    const QList<QVariantMap>& rows() const { return m_rows; }
    // `rows` become the content, in this order. Every row has every role.
    void sync(const QList<QVariantMap>& rows);
    // Newest first, at most `cap` rows.
    void prepend(const QVariantMap& row, int cap);
    void clear();

signals:
    void countChanged();

private:
    QByteArrayList m_roles;
    QByteArray m_key;
    QList<QVariantMap> m_rows;
};

// The rows of a KeyedListModel whose ownerUid is `ownerUid` (the 调试 page:
// one unit's buffs). Plain C++ filtering: a refresh changes every buff's
// time, and only the changed rows are looked at again.
class OwnerFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(KeyedListModel* source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(uint ownerUid READ ownerUid WRITE setOwnerUid NOTIFY ownerUidChanged)

public:
    explicit OwnerFilterModel(QObject* parent = nullptr) : QSortFilterProxyModel(parent) { setDynamicSortFilter(true); }

    KeyedListModel* source() const { return m_source; }
    void setSource(KeyedListModel* model)
    {
        if (model == m_source) return;
        m_source = model;
        setSourceModel(model);
        emit sourceChanged();
    }
    uint ownerUid() const { return m_owner; }
    void setOwnerUid(uint uid)
    {
        if (uid == m_owner) return;
        beginFilterChange();
        m_owner = uid;
        endFilterChange(Direction::Rows);
        emit ownerUidChanged();
    }

signals:
    void sourceChanged();
    void ownerUidChanged();

protected:
    bool filterAcceptsRow(int row, const QModelIndex&) const override
    {
        return m_owner != 0 && m_source && row < m_source->count()
               && m_source->rows()[row].value(QStringLiteral("ownerUid")).toUInt() == m_owner;
    }

private:
    KeyedListModel* m_source = nullptr;
    uint m_owner = 0;
};

// What EndfieldDataBridge currently reports, read from its shared memory
// ten times a second (include/endfield_bridge_reader.h does the reading).
class BridgeReader : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // "offline", "incompatible", "gone", "disabled", "stale" or "online"
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    // abi, session, sampleIntervalMs, headBarUnits, skillCasts, buffsPartial, buffsDropped
    Q_PROPERTY(QVariantMap info READ info NOTIFY changed)
    // atb, atbMax, atbPerCell, valid, fresh, lockUid, lockMode, autoLock
    Q_PROPERTY(QVariantMap team READ team NOTIFY changed)
    Q_PROPERTY(QVariantMap mainOperator READ mainOperator NOTIFY changed) // a squad row, or empty
    Q_PROPERTY(QVariantMap lockTarget READ lockTarget NOTIFY changed)     // a unit row, or empty
    Q_PROPERTY(KeyedListModel* squad READ squad CONSTANT)        // one row per slot
    Q_PROPERTY(KeyedListModel* units READ units CONSTANT)        // units not in the squad
    Q_PROPERTY(KeyedListModel* buffs READ buffs CONSTANT)
    Q_PROPERTY(KeyedListModel* skillEvents READ skillEvents CONSTANT) // newest first
    Q_PROPERTY(KeyedListModel* buffEvents READ buffEvents CONSTANT)   // newest first
    Q_PROPERTY(int lostEvents READ lostEvents NOTIFY changed)
    // Bumped after every read; bind to it to re-run evaluate() as data moves.
    Q_PROPERTY(int tick READ tick NOTIFY ticked)

public:
    explicit BridgeReader(QObject* parent = nullptr);
    ~BridgeReader() override;

    QString status() const { return m_status; }
    QString statusText() const;
    QVariantMap info() const { return m_info; }
    QVariantMap team() const { return m_team; }
    QVariantMap mainOperator() const { return m_main; }
    QVariantMap lockTarget() const { return m_lock; }
    KeyedListModel* squad() const { return m_squad; }
    KeyedListModel* units() const { return m_units; }
    KeyedListModel* buffs() const { return m_buffs; }
    KeyedListModel* skillEvents() const { return m_skillEvents; }
    KeyedListModel* buffEvents() const { return m_buffEvents; }
    int lostEvents() const { return m_lostEvents; }
    int tick() const { return m_tick; }

    Q_INVOKABLE void clearEvents();

    // One trigger against the latest data. `spec` is a trigger as stored in a
    // control (qml/Triggers.qml lists the types and their fields). Returns
    // available (there is data to judge by), active, progress (0-1), value,
    // max, stacks, timeLeft (-1 = none), infinite, text and note (a short
    // description of what was found, for the editor).
    Q_INVOKABLE QVariantMap evaluate(const QVariantMap& spec) const;
    // Distinct buff ids present now, and skill ids cast recently: for
    // picking ids in the trigger editor.
    Q_INVOKABLE QStringList buffIds() const;
    // A buff list control: the buffs on one unit (`unit` as in a buff
    // condition: main, slot1..4, target), filtered by `kind` (all | buff |
    // debuff), `source` (any | squad | enemy | self), `only` / `exclude`
    // (buff ids, comma separated). Oldest first (the bridge's key grows as
    // buffs are added and stays through refreshes), at most `max`. Each:
    // key, buffId, isDebuff, stacks, timeLeft (-1 = permanent), duration,
    // progress (time left / duration, 1 when permanent).
    Q_INVOKABLE QVariantList buffList(const QVariantMap& spec) const;
    Q_INVOKABLE QStringList skillIds() const;

signals:
    void changed();
    void ticked();

private:
    void poll();
    void disconnectWith(const QString& status);
    void publish(const QString& status, const QVariantMap& info, const QVariantMap& team,
                 const QVariantMap& main, const QVariantMap& lock);

    struct Impl;
    std::unique_ptr<Impl> d; // keeps windows.h out of this header
    QTimer m_timer;
    QString m_status = "offline";
    QVariantMap m_info, m_team, m_main, m_lock;
    KeyedListModel* m_squad;
    KeyedListModel* m_units;
    KeyedListModel* m_buffs;
    KeyedListModel* m_skillEvents;
    KeyedListModel* m_buffEvents;
    int m_lostEvents = 0;
    int m_tick = 0;
};
