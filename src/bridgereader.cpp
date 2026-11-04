#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include "bridgereader.h"

#include <QHash>
#include <QRegularExpression>

#include <algorithm>
#include <cmath>

#include "endfield_bridge_reader.h"

// ---- KeyedListModel ----

KeyedListModel::KeyedListModel(const QByteArrayList& roles, const QByteArray& key, QObject* parent)
    : QAbstractListModel(parent), m_roles(roles), m_key(key)
{
}

QVariant KeyedListModel::data(const QModelIndex& index, int role) const
{
    const int r = role - Qt::UserRole;
    if (!index.isValid() || index.row() >= count() || r < 0 || r >= m_roles.size()) return {};
    return m_rows[index.row()].value(QString::fromLatin1(m_roles[r]));
}

QHash<int, QByteArray> KeyedListModel::roleNames() const
{
    QHash<int, QByteArray> names;
    for (int i = 0; i < m_roles.size(); ++i) names.insert(Qt::UserRole + i, m_roles[i]);
    return names;
}

void KeyedListModel::sync(const QList<QVariantMap>& rows)
{
    const QString key = QString::fromLatin1(m_key);
    const int before = count();
    // Drop rows whose key is gone.
    // Keys are numbers; their text form is a fine hash key.
    QSet<QString> wanted;
    for (const QVariantMap& row : rows) wanted.insert(row.value(key).toString());
    for (int i = count() - 1; i >= 0; --i) {
        if (wanted.contains(m_rows[i].value(key).toString())) continue;
        beginRemoveRows({}, i, i);
        m_rows.removeAt(i);
        endRemoveRows();
    }
    // Walk the wanted order: move, insert or update each row into place.
    for (int i = 0; i < rows.size(); ++i) {
        const QVariant k = rows[i].value(key);
        int at = -1;
        for (int j = i; j < count(); ++j)
            if (m_rows[j].value(key) == k) { at = j; break; }
        if (at < 0) {
            beginInsertRows({}, i, i);
            m_rows.insert(i, rows[i]);
            endInsertRows();
            continue;
        }
        if (at != i) {
            beginMoveRows({}, at, at, {}, i);
            m_rows.move(at, i);
            endMoveRows();
        }
        if (m_rows[i] != rows[i]) {
            m_rows[i] = rows[i];
            emit dataChanged(index(i), index(i));
        }
    }
    if (count() != before) emit countChanged();
}

void KeyedListModel::prepend(const QVariantMap& row, int cap)
{
    beginInsertRows({}, 0, 0);
    m_rows.prepend(row);
    endInsertRows();
    if (count() > cap) {
        beginRemoveRows({}, cap, count() - 1);
        m_rows.erase(m_rows.begin() + cap, m_rows.end());
        endRemoveRows();
    }
    emit countChanged();
}

void KeyedListModel::clear()
{
    if (m_rows.isEmpty()) return;
    beginResetModel();
    m_rows.clear();
    endResetModel();
    emit countChanged();
}

// ---- reading ----

namespace {

constexpr int kEventCap = 200;
constexpr int kCastCap = 64;

// "chr_0007_ikut_4616825702491504642" -> "chr_0007_ikut": the trailing
// instance number repeats the uid and only gets in the way.
QString ShortName(const char* entity)
{
    static const QRegularExpression tail("_\\d{6,}$");
    QString name = QString::fromUtf8(entity);
    name.remove(tail);
    return name;
}

QString FactionText(int faction)
{
    switch (faction) {
    case EFB_FACTION_GOOD: return "我方";
    case EFB_FACTION_BAD: return "敌方";
    case EFB_FACTION_NEUTRAL: return "中立";
    default: return "未知";
    }
}

QString SkillTypeText(int type)
{
    switch (type) {
    case EFB_SKILL_NORMAL: return "战技";
    case EFB_SKILL_ATTACH: return "附着";
    case EFB_SKILL_COMBO: return "连携技";
    case EFB_SKILL_ULTIMATE: return "终结技";
    case EFB_SKILL_EXTRA_ACTIVE: return "额外主动";
    case EFB_SKILL_PASSIVE: return "被动";
    case EFB_SKILL_ATTACK: return "普攻";
    case EFB_SKILL_BREAKING_ATTACK: return "重击";
    case EFB_SKILL_DODGE: return "闪避";
    default: return QString("类型 %1").arg(type);
    }
}

// Values seen in game (EndfieldDataBridge run8); others shown as numbers.
QString FinishTypeText(int type)
{
    switch (type) {
    case 0: return "完成";
    case 1: return "打断";
    default: return QString("结束 %1").arg(type);
    }
}
QString InterruptText(int reason)
{
    switch (reason) {
    case 2: return "AI";
    case 5: return "被动作打断";
    case 7: return "下一技能";
    case 9: return "剧情";
    default: return QString("原因 %1").arg(reason);
    }
}
QString FinishReasonText(int reason)
{
    switch (reason) {
    case EFB_FINISH_LIFETIME: return "到期";
    case EFB_FINISH_IGNITE: return "引爆";
    case EFB_FINISH_EARLY: return "提前结束";
    case EFB_FINISH_DISPELLED: return "驱散";
    case EFB_FINISH_ABSORBED: return "吸收";
    case EFB_FINISH_LOST: return "未收到结束通知";
    case EFB_FINISH_OTHER: return "其他";
    default: return QString("原因 %1").arg(reason);
    }
}

QString UnitLabel(const EFB_Unit& u, const QHash<uint32_t, QString>& names)
{
    if (!u.instance_uid) return "（已消失）";
    if (u.char_index >= 0) return QString("%1号位 %2").arg(u.char_index + 1).arg(names.value(u.instance_uid, ShortName(u.entity_name)));
    return names.value(u.instance_uid, ShortName(u.entity_name));
}

} // namespace

struct BridgeReader::Impl {
    // A skill cast start, for skill triggers.
    struct Cast {
        double time;   // seconds since session start
        uint32_t uid;
        int slot;
        int faction;
        int type;
        QString id;
    };
    efb::Mapping mapping;
    efb::EventCursor cursor;
    bool open = false;
    int retryIn = 0;                    // polls until the next OpenFileMapping attempt
    QHash<uint32_t, QString> names;     // uid -> display name, kept for units that left
    QHash<uint32_t, double> castStart;  // skill_cast_id -> seconds since session start
    QList<Cast> casts;                  // recent starts, oldest first, at most kCastCap
    uint32_t session = 0;
    int64_t sessionStartedAt = 0;
    int64_t qpcFrequency = 0;
};

BridgeReader::BridgeReader(QObject* parent)
    : QObject(parent), d(std::make_unique<Impl>())
{
    m_squad = new KeyedListModel({"slot", "uid", "name", "present", "isMain", "ultimate", "ultimateMax",
                                  "comboLeft", "comboCooldown", "hasCombo", "hp", "hpMax", "hasPoise",
                                  "poise", "poiseMax", "broken", "recovering", "recoveryLeft", "fresh",
                                  "buffCount"}, "slot", this);
    m_units = new KeyedListModel({"uid", "name", "faction", "factionText", "onHeadBar", "isLocked",
                                  "hp", "hpMax", "hasPoise", "poise", "poiseMax", "broken", "recovering",
                                  "recoveryLeft", "fresh", "buffCount"}, "uid", this);
    m_buffs = new KeyedListModel({"key", "buffId", "parentBuffId", "ownerUid", "ownerSlot", "ownerFaction",
                                  "source", "rootSource", "isDebuff", "infinite", "stacks", "duration",
                                  "timeLeft", "passed", "dilation", "addedAgo", "refreshedAgo", "sourceFaction",
                                  "sourceSlot"}, "key", this);
    m_skillEvents = new KeyedListModel({"serial", "time", "started", "caster", "casterSlot", "faction",
                                        "skillType", "skillId", "castId", "outcome", "interrupted",
                                        "castLength"}, "serial", this);
    m_buffEvents = new KeyedListModel({"serial", "time", "kind", "owner", "buffId", "stacks", "reason"},
                                      "serial", this);
    connect(&m_timer, &QTimer::timeout, this, &BridgeReader::poll);
    m_timer.start(100);
    poll();
}

BridgeReader::~BridgeReader() = default;

QString BridgeReader::statusText() const
{
    if (m_status == "online") return "已连接";
    if (m_status == "stale") return "已连接，数据未更新";
    if (m_status == "disabled") return "插件已停用";
    if (m_status == "gone") return "游戏已退出";
    if (m_status == "incompatible") return "Bridge 版本不兼容";
    return "未连接";
}

void BridgeReader::clearEvents()
{
    m_skillEvents->clear();
    m_buffEvents->clear();
    m_lostEvents = 0;
    emit changed();
}

void BridgeReader::disconnectWith(const QString& status)
{
    d->mapping.Close();
    d->open = false;
    d->cursor = efb::EventCursor{};
    d->casts.clear();
    d->retryIn = 10; // try again in a second
    m_squad->sync({});
    m_units->sync({});
    m_buffs->sync({});
    publish(status, {}, {}, {}, {});
    ++m_tick;
    emit ticked();
}

void BridgeReader::publish(const QString& status, const QVariantMap& info, const QVariantMap& team,
                           const QVariantMap& main, const QVariantMap& lock)
{
    if (status == m_status && info == m_info && team == m_team && main == m_main && lock == m_lock) return;
    m_status = status;
    m_info = info;
    m_team = team;
    m_main = main;
    m_lock = lock;
    emit changed();
}

void BridgeReader::poll()
{
    if (!d->open) {
        if (d->retryIn-- > 0) return;
        if (!d->mapping.Open()) {
            d->retryIn = 10;
            publish("offline", {}, {}, {}, {});
            return;
        }
        d->open = true;
    }

    efb::Header h;
    const efb::Result hr = efb::ReadHeader(d->mapping, h);
    if (hr == efb::Result::Incompatible) return disconnectWith("incompatible");
    if (hr != efb::Result::Ok) return; // writer busy: keep what is shown
    // The mapping outlives a crashed game while we hold it: let go of it.
    if (!efb::WriterAlive(h.fields)) return disconnectWith("gone");

    efb::Section team, ops, buffs, units;
    const auto read = [&](uint32_t id, efb::Section& out) {
        const efb::Result r = efb::ReadSection(d->mapping, h, id, out);
        return r == efb::Result::Ok ? 1 : r == efb::Result::Missing ? 0 : -1;
    };
    const int hasTeam = read(EFB_SECTION_TEAM, team);
    const int hasOps = read(EFB_SECTION_OPERATORS, ops);
    const int hasBuffs = read(EFB_SECTION_BUFFS, buffs);
    const int hasUnits = read(EFB_SECTION_UNITS, units);
    if (hasTeam < 0 || hasOps < 0 || hasBuffs < 0 || hasUnits < 0) return; // retry next poll
    efb::EventBatch batch;
    const bool events = d->cursor.Poll(d->mapping, h, batch) == efb::Result::Ok;

    const int64_t now = efb::Now();
    const EFB_Header& hf = h.fields;
    if (hf.session != d->session) {
        d->session = hf.session;
        d->casts.clear();
        d->castStart.clear();
    }
    d->sessionStartedAt = hf.session_started_at;
    d->qpcFrequency = hf.qpc_frequency;
    const auto fresh = [&](int64_t at) { return efb::Fresh(hf, at, now); };
    const auto secondsAgo = [&](int64_t at) { return at ? efb::SecondsSince(hf, at, now) : -1.0; };
    const auto sessionTime = [&](int64_t at) {
        return hf.qpc_frequency && at ? double(at - hf.session_started_at) / double(hf.qpc_frequency) : 0.0;
    };
    int64_t newest = 0;

    // ---- team
    QVariantMap teamMap;
    uint32_t lockUid = 0;
    if (hasTeam && team.capacity()) {
        const EFB_Team t = team.Element<EFB_Team>(0);
        newest = std::max(newest, t.sampled_at);
        lockUid = t.lock_target_uid;
        teamMap = {{"valid", t.sampled_at != 0}, {"fresh", fresh(t.sampled_at)},
                   {"atb", double(t.atb)}, {"atbMax", double(t.atb_max)}, {"atbPerCell", t.atb_per_cell},
                   {"lockUid", lockUid}, {"lockMode", t.lock_mode != 0}, {"autoLock", t.auto_lock != 0},
                   {"inFight", t.in_fight != 0}};
    }

    // ---- units (HP / poise), squad and enemies
    QHash<uint32_t, EFB_UnitState> unitByUid;
    QHash<int, EFB_UnitState> unitBySlot;
    if (hasUnits) {
        for (uint32_t i = 0; i < units.capacity(); ++i) {
            const EFB_UnitState u = units.Element<EFB_UnitState>(i);
            if (!u.instance_uid) continue;
            unitByUid.insert(u.instance_uid, u);
            if (u.char_index >= 0) unitBySlot.insert(u.char_index, u);
            if (u.char_index < 0) d->names.insert(u.instance_uid, ShortName(u.entity_name));
        }
    }

    // ---- buffs, counted per owner
    QHash<uint32_t, int> buffsPerOwner;
    QList<QVariantMap> buffRows;
    if (hasBuffs) {
        const bool online = hf.active && fresh(newest ? newest : now);
        for (uint32_t i = 0; i < buffs.capacity(); ++i) {
            const EFB_Buff b = buffs.Element<EFB_Buff>(i);
            if (!b.key) continue;
            buffsPerOwner[b.owner.instance_uid]++;
            const bool infinite = b.life_type == EFB_LIFE_INFINITY;
            buffRows.push_back({
                {"key", b.key}, {"buffId", QString::fromUtf8(b.buff_id)},
                {"parentBuffId", QString::fromUtf8(b.parent_buff_id)},
                {"ownerUid", b.owner.instance_uid}, {"ownerSlot", int(b.owner.char_index)},
                {"ownerFaction", int(b.owner.faction)},
                {"source", UnitLabel(b.source, d->names)}, {"rootSource", UnitLabel(b.root_source, d->names)},
                {"isDebuff", int(b.is_debuff)}, {"infinite", infinite}, {"stacks", b.enhance_cnt},
                {"duration", infinite ? -1.0 : double(b.duration)},
                {"timeLeft", efb::LifeLeft(hf, b, now, online)},
                {"passed", double(b.passed_time)}, {"dilation", double(b.time_dilation)},
                {"addedAgo", secondsAgo(b.added_at)}, {"refreshedAgo", secondsAgo(b.refreshed_at)},
                {"sourceFaction", int(b.root_source.faction)}, {"sourceSlot", int(b.root_source.char_index)},
            });
        }
        // Stable order: owner, then the buff that has lasted longest.
        std::stable_sort(buffRows.begin(), buffRows.end(), [](const QVariantMap& a, const QVariantMap& b) {
            if (a["ownerUid"] != b["ownerUid"]) return a["ownerUid"].toUInt() < b["ownerUid"].toUInt();
            return a["key"].toUInt() < b["key"].toUInt();
        });
    }

    // ---- squad: operator slot + its unit row
    QList<QVariantMap> squadRows;
    QVariantMap mainRow;
    if (hasOps) {
        for (uint32_t i = 0; i < ops.capacity() && i < 4; ++i) {
            const EFB_Operator o = ops.Element<EFB_Operator>(i);
            newest = std::max(newest, o.sampled_at);
            const QString name = o.present ? ShortName(o.entity_name) : QString();
            if (o.present && o.instance_uid) d->names.insert(o.instance_uid, name);
            const EFB_UnitState u = unitBySlot.value(int(i), EFB_UnitState{});
            QVariantMap row = {
                {"slot", int(i)}, {"uid", o.instance_uid}, {"name", name}, {"present", o.present != 0},
                {"isMain", o.present && o.is_main_character}, {"fresh", fresh(o.sampled_at)},
                {"ultimate", double(o.ultimate_sp)}, {"ultimateMax", double(o.max_ultimate_sp)},
                {"hasCombo", o.combo_cd_remaining >= 0}, {"comboLeft", double(std::max(0.0f, o.combo_cd_remaining))},
                {"comboCooldown", double(o.combo_cooldown)},
                {"hp", u.instance_uid ? u.hp : -1.0}, {"hpMax", u.instance_uid ? u.max_hp : -1.0},
                {"hasPoise", u.has_poise != 0}, {"poise", double(u.poise)}, {"poiseMax", double(u.max_poise)},
                {"broken", u.is_zero_poise != 0}, {"recovering", u.in_poise_recovery != 0},
                {"recoveryLeft", double(u.poise_recovery_left)},
                {"buffCount", buffsPerOwner.value(o.instance_uid)},
            };
            if (row["isMain"].toBool()) mainRow = row;
            squadRows.push_back(row);
        }
    }

    // ---- enemies and other units: locked target first, then by uid
    QList<QVariantMap> unitRows;
    QVariantMap lockRow;
    for (auto it = unitByUid.cbegin(); it != unitByUid.cend(); ++it) {
        const EFB_UnitState& u = it.value();
        if (u.char_index >= 0) continue;
        QVariantMap row = {
            {"uid", u.instance_uid}, {"name", ShortName(u.entity_name)}, {"faction", int(u.faction)},
            {"factionText", FactionText(u.faction)}, {"onHeadBar", u.on_head_bar != 0},
            {"isLocked", u.instance_uid == lockUid}, {"fresh", fresh(u.sampled_at)},
            {"hp", u.hp}, {"hpMax", u.max_hp}, {"hasPoise", u.has_poise != 0},
            {"poise", double(u.poise)}, {"poiseMax", double(u.max_poise)},
            {"broken", u.is_zero_poise != 0}, {"recovering", u.in_poise_recovery != 0},
            {"recoveryLeft", double(u.poise_recovery_left)},
            {"buffCount", buffsPerOwner.value(u.instance_uid)},
        };
        if (row["isLocked"].toBool()) lockRow = row;
        unitRows.push_back(row);
    }
    std::sort(unitRows.begin(), unitRows.end(), [](const QVariantMap& a, const QVariantMap& b) {
        if (a["isLocked"] != b["isLocked"]) return a["isLocked"].toBool();
        return a["uid"].toUInt() < b["uid"].toUInt();
    });
    if (lockUid && lockRow.isEmpty()) // locked, but its unit row is not in the table (yet)
        lockRow = {{"uid", lockUid}, {"name", d->names.value(lockUid, QString("uid %1").arg(lockUid))}, {"missing", true}};

    m_squad->sync(squadRows);
    m_units->sync(unitRows);
    m_buffs->sync(buffRows);

    // ---- events: skill casts and buff changes, newest first
    if (events) {
        for (const EFB_Event& e : batch.events) {
            const double t = sessionTime(e.at);
            if (e.type == EFB_EVENT_SKILL_CAST_STARTED || e.type == EFB_EVENT_SKILL_CAST_ENDED) {
                const auto p = efb::Payload<EFB_SkillEventPayload>(e);
                const bool started = e.type == EFB_EVENT_SKILL_CAST_STARTED;
                double length = -1;
                if (started) {
                    if (d->castStart.size() > 256) d->castStart.clear(); // ends that never came
                    d->castStart.insert(p.skill_cast_id, t);
                    d->casts.push_back({t, p.caster_uid, int(p.char_index), int(p.faction), p.skill_type,
                                        QString::fromUtf8(p.skill_id)});
                    if (d->casts.size() > kCastCap) d->casts.removeFirst();
                } else if (d->castStart.contains(p.skill_cast_id)) {
                    length = t - d->castStart.take(p.skill_cast_id);
                }
                QString caster = p.char_index >= 0
                    ? QString("%1号位 %2").arg(p.char_index + 1).arg(d->names.value(p.caster_uid, QString("uid %1").arg(p.caster_uid)))
                    : d->names.value(p.caster_uid, QString("uid %1").arg(p.caster_uid));
                m_skillEvents->prepend({
                    {"serial", qulonglong(e.serial)}, {"time", t}, {"started", started}, {"caster", caster},
                    {"casterSlot", int(p.char_index)}, {"faction", int(p.faction)},
                    {"skillType", SkillTypeText(p.skill_type)}, {"skillId", QString::fromUtf8(p.skill_id)},
                    {"castId", p.skill_cast_id},
                    {"outcome", started ? QString() : FinishTypeText(p.finish_type)},
                    {"interrupted", started || p.finish_type == 0 ? QString() : InterruptText(p.interrupt_reason)},
                    {"castLength", length},
                }, kEventCap);
            } else if (e.type >= EFB_EVENT_BUFF_ADDED && e.type <= EFB_EVENT_BUFF_FINISHED) {
                const auto p = efb::Payload<EFB_BuffEventPayload>(e);
                static const char* const kinds[] = {"", "添加", "刷新", "层数", "结束"};
                QString owner = d->names.value(e.subject_uid, QString("uid %1").arg(e.subject_uid));
                m_buffEvents->prepend({
                    {"serial", qulonglong(e.serial)}, {"time", t}, {"kind", QString(kinds[e.type])},
                    {"owner", owner}, {"buffId", QString::fromUtf8(p.buff_id)}, {"stacks", p.enhance_cnt},
                    {"reason", e.type == EFB_EVENT_BUFF_FINISHED ? FinishReasonText(p.finish_reason) : QString()},
                }, kEventCap);
            }
        }
        // Overwritten before we read them (the ring wrapped).
        if (batch.lost) {
            m_lostEvents += int(batch.lost);
            emit changed();
        }
    }

    // ---- header and status
    const efb::Status s = efb::Check(hf, true, newest, now);
    QString status = s == efb::Status::Online ? "online" : s == efb::Status::Disabled ? "disabled" : "stale";
    QVariantMap info;
    if (hasBuffs) {
        const auto bh = buffs.Head<EFB_BuffsHeader>();
        info = {{"buffsPartial", (bh.flags & EFB_BUFFS_PARTIAL) != 0}, {"buffsDropped", int(bh.dropped)}};
    }
    info.insert("abi", QString("%1.%2").arg(hf.abi_major).arg(hf.abi_minor));
    info.insert("session", hf.session);
    info.insert("sampleIntervalMs", hf.sample_interval_ms);
    info.insert("headBarUnits", (hf.provides & EFB_PROVIDES_HEAD_BAR_UNITS) != 0);
    info.insert("skillCasts", (hf.provides & EFB_PROVIDES_SKILL_CASTS) != 0);
#ifdef EFB_PROVIDES_IN_FIGHT
    info.insert("inFight", (hf.provides & EFB_PROVIDES_IN_FIGHT) != 0);
#endif
    publish(status, info, teamMap, mainRow, lockRow);
    ++m_tick;
    emit ticked();
}

// ---- triggers

namespace {

// Comparison for the threshold triggers.
bool Compare(double a, const QString& op, double b)
{
    if (op == "<") return a < b;
    if (op == "<=") return a <= b;
    if (op == ">") return a > b;
    if (op == "==") return std::abs(a - b) < 1e-6;
    if (op == "!=") return std::abs(a - b) >= 1e-6;
    return a >= b; // ">="
}

QVariantMap Result(bool available, bool active, double progress, const QString& note)
{
    return {{"available", available}, {"active", active},
            {"progress", std::clamp(progress, 0.0, 1.0)}, {"value", 0.0}, {"max", 0.0},
            {"stacks", 0}, {"timeLeft", -1.0}, {"infinite", false}, {"text", QString()}, {"note", note}};
}

QStringList SplitIds(const QString& text)
{
    QStringList out;
    for (const QString& part : text.split(QRegularExpression("[,，\\s]+"), Qt::SkipEmptyParts)) out << part;
    return out;
}

} // namespace

QStringList BridgeReader::buffIds() const
{
    QStringList ids;
    for (const QVariantMap& b : m_buffs->rows()) {
        const QString id = b.value("buffId").toString();
        if (!ids.contains(id)) ids << id;
    }
    ids.sort();
    return ids;
}

QStringList BridgeReader::skillIds() const
{
    QStringList ids;
    for (auto it = d->casts.crbegin(); it != d->casts.crend(); ++it)
        if (!ids.contains(it->id)) ids << it->id;
    return ids;
}

QVariantMap BridgeReader::evaluate(const QVariantMap& spec) const
{
    const QString type = spec.value("type").toString();
    const bool online = m_status == "online" || m_status == "stale";
    if (type.isEmpty() || type == "always") return Result(true, true, 1, "始终显示");
    if (!online) return Result(false, false, 0, "未连接");

    // Which squad slot a unit choice means: "main", "slot1".."slot4".
    const QString unit = spec.value("unit", "main").toString();
    const int mainSlot = m_main.value("slot", -1).toInt();
    const auto slotOf = [&](const QString& u) {
        if (u == "main") return mainSlot;
        if (u.startsWith("slot")) return u.mid(4).toInt() - 1;
        return -1;
    };
    const auto squadRow = [&](int slot) {
        for (const QVariantMap& r : m_squad->rows())
            if (r.value("slot").toInt() == slot && r.value("present").toBool()) return r;
        return QVariantMap{};
    };

    // ---- buff: present (or missing) on a unit
    if (type == "buff") {
        const QStringList ids = SplitIds(spec.value("buffIds").toString());
        if (ids.isEmpty()) return Result(true, false, 0, "未填写 Buff id");
        const QString source = spec.value("source", "any").toString();
        const bool wantMissing = spec.value("show", "present").toString() == "missing";
        const uint32_t lockUid = m_team.value("lockUid").toUInt();
        // The match that lasts longest wins (infinite counts as longest).
        QVariantMap best;
        double bestLeft = -2;
        int count = 0;
        for (const QVariantMap& b : m_buffs->rows()) {
            if (!ids.contains(b.value("buffId").toString())) continue;
            const int ownerSlot = b.value("ownerSlot").toInt();
            const uint32_t ownerUid = b.value("ownerUid").toUInt();
            bool ownerOk = false;
            if (unit == "target") ownerOk = lockUid && ownerUid == lockUid;
            else if (unit == "anySquad") ownerOk = ownerSlot >= 0;
            else if (unit == "anyEnemy") ownerOk = b.value("ownerFaction").toInt() == EFB_FACTION_BAD;
            else ownerOk = ownerSlot >= 0 && ownerSlot == slotOf(unit);
            if (!ownerOk) continue;
            const int srcFaction = b.value("sourceFaction").toInt();
            if (source == "squad" && srcFaction != EFB_FACTION_GOOD) continue;
            if (source == "enemy" && srcFaction != EFB_FACTION_BAD) continue;
            if (source == "self" && b.value("sourceSlot").toInt() != ownerSlot) continue;
            ++count;
            const double left = b.value("infinite").toBool() ? 1e18 : b.value("timeLeft").toDouble();
            if (left > bestLeft) {
                bestLeft = left;
                best = b;
            }
        }
        if (wantMissing) {
            QVariantMap r = Result(true, count == 0, count == 0 ? 1 : 0, count == 0 ? "未找到，显示" : QString("找到 %1 个，隐藏").arg(count));
            return r;
        }
        if (best.isEmpty()) return Result(true, false, 0, "未找到");
        const bool infinite = best.value("infinite").toBool();
        const double duration = best.value("duration").toDouble();
        const double left = best.value("timeLeft").toDouble();
        QVariantMap r = Result(true, true, infinite || duration <= 0 ? 1 : left / duration,
                               QString("%1 · %2").arg(best.value("buffId").toString(),
                                                     infinite ? QString("永久") : QString::number(left, 'f', 1) + " s"));
        r["stacks"] = best.value("stacks");
        r["timeLeft"] = infinite ? -1.0 : left;
        r["infinite"] = infinite;
        r["value"] = infinite ? 0.0 : left;
        r["max"] = infinite ? 0.0 : duration;
        r["text"] = infinite ? QString() : QString::number(left, 'f', 1);
        return r;
    }

    // ---- skill cast: shown for `duration` seconds after a matching start
    if (type == "skillCast") {
        const QString wantType = spec.value("skillType", "any").toString();
        const QStringList ids = SplitIds(spec.value("skillId").toString());
        const double duration = std::max(0.1, spec.value("duration", 3.0).toDouble());
        const double now = d->qpcFrequency ? double(efb::Now() - d->sessionStartedAt) / double(d->qpcFrequency) : 0;
        const int slot = slotOf(unit);
        for (auto it = d->casts.crbegin(); it != d->casts.crend(); ++it) {
            const double age = now - it->time;
            if (age > duration) break; // older ones are older still
            if (unit == "anySquad" ? it->slot < 0 : unit == "anyEnemy" ? it->faction != EFB_FACTION_BAD
                                                                       : it->slot != slot) continue;
            const QHash<QString, int> types = {{"normal", EFB_SKILL_NORMAL}, {"combo", EFB_SKILL_COMBO},
                                               {"ultimate", EFB_SKILL_ULTIMATE}};
            if (wantType != "any" && it->type != types.value(wantType, -99)) continue;
            if (!ids.isEmpty() && !ids.contains(it->id)) continue;
            const double left = duration - age;
            QVariantMap r = Result(true, true, left / duration, QString("%1 · %2 s 前").arg(it->id).arg(age, 0, 'f', 1));
            r["timeLeft"] = left;
            r["value"] = left;
            r["max"] = duration;
            r["text"] = QString::number(left, 'f', 1);
            return r;
        }
        return Result(true, false, 0, "最近没有释放");
    }

    // ---- thresholds: a number against `value`
    const QString op = spec.value("op", ">=").toString();
    const double threshold = spec.value("value", 0).toDouble();
    const auto whole = [](double v) { return QString::number(v, 'f', 0); };
    // `value` / `max` are the real numbers (HP 5595 / 5950); `compared` is
    // what the threshold is judged on (HP and poise: their percentage).
    // `note` is for the editor; the shown text is the bare number.
    const auto threshold_ = [&](double v, double max, const QString& what, const QString& note, double compared,
                                const QString& shown) {
        QVariantMap r = Result(true, Compare(compared, op, threshold), max > 0 ? v / max : 0,
                               QString("%1 %2").arg(what, note));
        r["value"] = v;
        r["max"] = max;
        r["text"] = shown;
        return r;
    };


    if (type == "atb") {
        if (!m_team.value("valid").toBool()) return Result(false, false, 0, "无技力数据");
        const double atb = m_team.value("atb").toDouble(), max = m_team.value("atbMax").toDouble();
        const int perCell = m_team.value("atbPerCell").toInt();
        // Measured in cells when asked and known; otherwise in SP.
        if (spec.value("measure", "sp").toString() == "cells" && perCell > 0) {
            const double cells = std::floor(atb / perCell);
            QVariantMap r = threshold_(cells, std::floor(max / perCell), "技力", QString("%1 格").arg(cells), cells, whole(cells));
            r["stacks"] = int(cells);
            return r;
        }
        return threshold_(atb, max, "技力", whole(atb), atb, whole(atb));
    }

    // Squad member values.
    if (type == "ultimate" || type == "combo") {
        const int slot = slotOf(unit);
        const QVariantMap op_ = squadRow(slot);
        if (op_.isEmpty()) return Result(false, false, 0, slot < 0 ? "没有主控干员" : "该位置没有干员");
        if (type == "ultimate") {
            const double v = op_.value("ultimate").toDouble(), max = op_.value("ultimateMax").toDouble();
            if (spec.value("measure", "value").toString() == "ready") {
                const bool ready = max > 0 && v >= max;
                QVariantMap r = Result(true, ready, max > 0 ? v / max : 0, ready ? "终结技就绪" : QString("终结技 %1 / %2").arg(v, 0, 'f', 0).arg(max, 0, 'f', 0));
                r["value"] = v;
                r["max"] = max;
                r["text"] = QString::number(v, 'f', 0);
                return r;
            }
            return threshold_(v, max, "终结技", whole(v), v, whole(v));
        }
        if (!op_.value("hasCombo").toBool()) return Result(false, false, 0, "该干员没有连携技");
        const double left = op_.value("comboLeft").toDouble(), cd = op_.value("comboCooldown").toDouble();
        // "ready": active when the cooldown is over; progress counts down while cooling.
        const bool ready = left <= 0;
        const bool wantCooling = spec.value("show", "ready").toString() == "cooling";
        QVariantMap r = Result(true, wantCooling ? !ready : ready, cd > 0 ? left / cd : 0,
                               ready ? "连携技就绪" : QString("连携技冷却 %1 s").arg(left, 0, 'f', 1));
        r["timeLeft"] = ready ? -1.0 : left;
        r["value"] = left;
        r["max"] = cd;
        r["text"] = ready ? QString() : QString::number(left, 'f', 1);
        return r;
    }

    // Unit HP / poise: a squad slot, the main operator or the locked target.
    if (type == "hp" || type == "poise") {
        QVariantMap u;
        if (unit == "target") u = m_lock.value("missing").toBool() ? QVariantMap{} : m_lock;
        else u = squadRow(slotOf(unit));
        if (u.isEmpty() || u.value("hp").toDouble() < 0)
            return Result(false, false, 0, unit == "target" ? "没有锁定目标" : "没有该单位的数据");
        if (type == "hp") {
            const double hp = u.value("hp").toDouble(), max = u.value("hpMax").toDouble();
            // HP is compared in percent ("HP below 30%"), shown as the number.
            const double pct = max > 0 ? hp / max * 100 : 0;
            return threshold_(hp, max, "HP", QString("%1 / %2（%3%）").arg(whole(hp), whole(max), whole(pct)), pct, whole(hp));
        }
        if (!u.value("hasPoise").toBool()) return Result(false, false, 0, "该单位没有失衡条");
        const QString show = spec.value("show", "broken").toString();
        const bool broken = u.value("broken").toBool();
        if (show == "broken") {
            QVariantMap r = Result(true, broken, broken ? 1 : 0, broken ? "失衡中" : "未失衡");
            const double rec = u.value("recoveryLeft").toDouble();
            if (broken && rec >= 0) {
                r["timeLeft"] = rec;
                r["text"] = QString::number(rec, 'f', 1);
                r["note"] = QString("失衡中 · 恢复 %1 s").arg(rec, 0, 'f', 1);
            }
            return r;
        }
        const double poise = u.value("poise").toDouble(), max = u.value("poiseMax").toDouble();
        const double pct = max > 0 ? poise / max * 100 : 0;
        return threshold_(poise, max, "失衡值", QString("%1 / %2（%3%）").arg(whole(poise), whole(max), whole(pct)), pct, whole(poise));
    }

    // In combat: the game's own flag (BattleManager.m_isSquadInFight, Bridge
    // ABI 1.3), which also holds between waves. Older Bridges: approximated
    // from a locked target, an enemy head bar, or a squad skill in the last 5 s.
    if (type == "combat") {
        // "out": active while not in combat.
        const bool wantOut = spec.value("show", "in").toString() == "out";
        if (m_info.value("inFight").toBool()) {
            const bool inFight = m_team.value("inFight").toBool();
            const bool active = inFight != wantOut;
            return Result(true, active, active ? 1 : 0, inFight ? "战斗中" : "非战斗");
        }
        const bool locked = m_team.value("lockUid").toUInt() != 0;
        bool headBar = false;
        for (const QVariantMap& u : m_units->rows())
            if (u.value("onHeadBar").toBool() && u.value("faction").toInt() == EFB_FACTION_BAD
                && u.value("hp").toDouble() > 0) { headBar = true; break; }
        bool recentCast = false;
        const double now = d->qpcFrequency ? double(efb::Now() - d->sessionStartedAt) / double(d->qpcFrequency) : 0;
        for (auto it = d->casts.crbegin(); it != d->casts.crend() && now - it->time <= 5; ++it)
            if (it->slot >= 0) { recentCast = true; break; }
        const bool inFight = locked || headBar || recentCast;
        const bool active = inFight != wantOut;
        return Result(true, active, active ? 1 : 0,
                      inFight ? (locked ? "战斗中（有锁定目标）" : headBar ? "战斗中（有敌人血条）" : "战斗中（刚释放技能）")
                             : "非战斗（估算）");
    }

    if (type == "lock") {
        const bool locked = m_team.value("lockUid").toUInt() != 0;
        const QString show = spec.value("show", "locked").toString();
        const bool manual = m_team.value("lockMode").toBool();
        const bool active = show == "manual" ? locked && manual : show == "none" ? !locked : locked;
        return Result(true, active, active ? 1 : 0,
                      !locked ? "没有锁定目标" : QString("已锁定 %1 · %2").arg(m_lock.value("name").toString(), manual ? "手动" : "自动"));
    }

    return Result(false, false, 0, "未知的触发器类型 " + type);
}
