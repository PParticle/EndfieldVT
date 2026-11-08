import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The fields of one condition (a test against the game data), for the 载入
// and 触发器 tabs: a type picker, then what that type needs. Edits go out as
// a whole new condition through `changed`.
ColumnLayout {
    id: card
    property var spec: ({ type: "always" })
    property var types: Triggers.types
    property int labelW: 14 * Theme.unit
    // Picking a value to show (a text's 动态内容): the comparison and the
    // buff's present / missing choice do not apply.
    property bool valueOnly: false
    signal changed(var spec)

    function set(field, value) {
        const next = Object.assign({}, spec)
        next[field] = value
        changed(next)
    }
    function field(name, fallback) { return spec[name] !== undefined ? spec[name] : fallback }
    readonly property string type: spec.type || "always"

    spacing: Theme.unit

    component Row_: RowLayout {
        property alias label: l.text
        Layout.fillWidth: true
        spacing: 0
        Label {
            id: l
            Layout.preferredWidth: card.labelW
            Layout.preferredHeight: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            color: Theme.textDim
        }
    }
    // A combo box bound to one field of the condition.
    component Choice: ThemeComboBox {
        id: choice
        property string field
        property string fallback
        Component.onCompleted: select(card.field(field, fallback))
        Connections { target: card; function onSpecChanged() { choice.select(card.field(choice.field, choice.fallback)) } }
        onActivated: card.set(field, currentValue)
    }

    Row_ {
        label: "类型"
        ThemeComboBox {
            id: typeBox
            Layout.preferredWidth: 24 * Theme.unit
            model: card.types
            Component.onCompleted: select(card.type)
            Connections { target: card; function onSpecChanged() { typeBox.select(card.type) } }
            // A new type starts from its defaults.
            onActivated: if (currentValue !== card.type) card.changed(Triggers.makeCondition(currentValue))
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.unit
            text: { const t = card.types.find(t => t.value === card.type); return t ? t.desc : "" }
            color: Theme.textFaint
            font.pixelSize: Theme.caption
            elide: Text.ElideRight
        }
    }

    Row_ {
        label: "监控目标"
        visible: ["buff", "ultimate", "combo", "hp", "poise", "skillCast"].includes(card.type)
        Choice {
            field: "unit"
            fallback: card.type === "poise" ? "target" : "main"
            model: card.type === "buff" ? Triggers.buffUnits
                 : card.type === "hp" || card.type === "poise" ? Triggers.hpUnits
                 : card.type === "skillCast" ? Triggers.castUnits : Triggers.squadUnits
        }
    }

    // buff
    Row_ {
        label: "Buff ID"
        visible: card.type === "buff"
        EditField {
            id: buffIds
            Layout.fillWidth: true
            placeholderText: "多个 ID 使用逗号分隔"
            value: card.field("buffIds", "")
            onCommitted: t => card.set("buffIds", t.trim())
        }
        FlatButton {
            Layout.leftMargin: Theme.unit
            text: "从当前 Buff 选择"
            enabled: { BridgeReader.tick; return BridgeReader.buffIds().length > 0 }
            onClicked: idMenu.popupFor(BridgeReader.buffIds(), "buffIds")
        }
    }
    Row_ {
        label: "来源"
        visible: card.type === "buff"
        Choice {
            field: "source"; fallback: "any"
            model: [
                { label: "任意来源", value: "any" }, { label: "我方单位", value: "squad" },
                { label: "敌方单位", value: "enemy" }, { label: "仅限自身", value: "self" }
            ]
        }
    }
    Row_ {
        label: "状态"
        visible: card.type === "buff" && !card.valueOnly
        Choice {
            field: "show"; fallback: "present"
            model: [{ label: "存在", value: "present" }, { label: "不存在", value: "missing" }]
        }
    }

    // buff (present) and combo (cooling): optional tests on stacks / time left
    component OpValue: RowLayout {
        id: ov
        property string label
        property string opField
        property string valueField
        property real fallback: 0
        property string unit
        property int decimals: 0
        Layout.fillWidth: true
        spacing: 0
        Label {
            Layout.preferredWidth: card.labelW
            Layout.preferredHeight: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            text: ov.label
            color: Theme.textDim
        }
        Choice {
            Layout.preferredWidth: 15 * Theme.unit
            field: ov.opField; fallback: "any"
            model: Triggers.compareOps
        }
        NumberField {
            visible: card.field(ov.opField, "any") !== "any"
            Layout.leftMargin: Theme.unit
            from: 0; to: 100000; decimals: ov.decimals; unit: ov.unit
            value: card.field(ov.valueField, ov.fallback)
            onCommitted: v => card.set(ov.valueField, v)
        }
        Item { Layout.fillWidth: true }
    }
    OpValue {
        visible: card.type === "buff" && !card.valueOnly && card.field("show", "present") === "present"
        label: "层数"; opField: "stacksOp"; valueField: "stacksValue"; fallback: 1; unit: "层"
    }
    OpValue {
        visible: card.type === "buff" && !card.valueOnly && card.field("show", "present") === "present"
        label: "剩余时间"; opField: "leftOp"; valueField: "leftValue"; fallback: 3; unit: "s"; decimals: 1
    }
    OpValue {
        visible: card.type === "combo" && !card.valueOnly && card.field("show", "cooling") === "cooling"
        label: "剩余冷却"; opField: "leftOp"; valueField: "leftValue"; fallback: 2; unit: "s"; decimals: 1
    }
    Label {
        visible: card.type === "buff" && !card.valueOnly && card.field("show", "present") === "present"
                 && (card.field("stacksOp", "any") !== "any" || card.field("leftOp", "any") !== "any")
        Layout.leftMargin: card.labelW
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "需同时满足 Buff 存在及层数/剩余时间条件。永久 Buff 剩余时间按无限大计算。"
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }

    // atb
    Row_ {
        label: "计量方式"
        visible: card.type === "atb"
        Choice {
            field: "measure"; fallback: "sp"
            model: [{ label: "技力数值 (0–上限)", value: "sp" }, { label: "可用格数 (0–3格)", value: "cells" }]
        }
    }
    // ultimate
    Row_ {
        label: "状态"
        visible: card.type === "ultimate" && !card.valueOnly
        Choice {
            field: "measure"; fallback: "ready"
            model: [{ label: "已就绪 (充满)", value: "ready" }, { label: "充能值", value: "value" }]
        }
    }
    // combo
    Row_ {
        label: "状态"
        visible: card.type === "combo" && !card.valueOnly
        Choice {
            field: "show"; fallback: "cooling"
            model: [{ label: "冷却中", value: "cooling" }, { label: "冷却完毕 (就绪)", value: "ready" }]
        }
    }
    // poise
    Row_ {
        label: "状态"
        visible: card.type === "poise"
        Choice {
            field: "show"; fallback: "broken"
            model: [{ label: "处于失衡状态", value: "broken" }, { label: "失衡值百分比", value: "value" }]
        }
    }
    // lock
    Row_ {
        label: "状态"
        visible: card.type === "lock"
        Choice {
            field: "show"; fallback: "locked"
            model: [
                { label: "存在锁定目标", value: "locked" }, { label: "手动锁定", value: "manual" },
                { label: "无锁定目标", value: "none" }
            ]
        }
    }

    // combat
    Row_ {
        label: "状态"
        visible: card.type === "combat"
        Choice {
            field: "show"; fallback: "in"
            model: [{ label: "战斗中", value: "in" }, { label: "非战斗状态", value: "out" }]
        }
    }
    Label {
        visible: card.type === "combat"
        Layout.leftMargin: card.labelW
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: BridgeReader.info.inFight ? "基于游戏内部战斗状态判定：波次刷新间隔期间仍判定为战斗中。"
                                        : "当前 Bridge 未提供战斗状态接口，基于目标锁定、血条显示或近期技能释放情况综合估算。"
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }

    // threshold: atb, ultimate (value), hp, poise (value). "不比较" only
    // reads the value (for a bar's progress or a text's number).
    readonly property bool hasThreshold: !valueOnly && (type === "atb" || type === "hp"
                 || (type === "ultimate" && field("measure", "ready") === "value")
                 || (type === "poise" && field("show", "broken") === "value"))
    Row_ {
        label: "比较运算符"
        visible: card.hasThreshold
        Choice {
            Layout.preferredWidth: 15 * Theme.unit
            field: "op"; fallback: ">="
            model: Triggers.compareOps
        }
        NumberField {
            visible: card.field("op", ">=") !== "any"
            Layout.leftMargin: Theme.unit
            from: 0; to: 100000
            unit: card.type === "hp" || card.type === "poise" ? "%" : card.type === "atb" && card.field("measure", "sp") === "cells" ? "格" : ""
            value: card.field("value", 0)
            onCommitted: v => card.set("value", v)
        }
        Label {
            Layout.leftMargin: Theme.unit
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: Theme.caption
            text: card.field("op", ">=") === "any"
                  ? "仅读取数值供文本/进度条使用，结果始终满足"
                  : card.type === "hp" ? "按 HP 百分比判定（例如：≤ 30% 提示残血）"
                  : card.type === "poise" ? "按失衡条百分比判定"
                  : card.type === "atb" && card.field("measure", "sp") === "cells" ? "按可释放次数判定（例如：≥ 2 格）"
                  : card.type === "atb" ? "按具体技力值判定"
                  : "按充能数值判定"
        }
    }

    // skill cast
    Row_ {
        label: "技能类型"
        visible: card.type === "skillCast"
        Choice {
            field: "skillType"; fallback: "any"
            model: [
                { label: "任意类型", value: "any" }, { label: "战技", value: "normal" },
                { label: "连携技", value: "combo" }, { label: "终结技", value: "ultimate" }
            ]
        }
    }
    Row_ {
        label: "技能 ID"
        visible: card.type === "skillCast"
        EditField {
            Layout.fillWidth: true
            placeholderText: "留空表示任意技能；多个 ID 使用逗号分隔"
            value: card.field("skillId", "")
            onCommitted: t => card.set("skillId", t.trim())
        }
        FlatButton {
            Layout.leftMargin: Theme.unit
            text: "从最近释放选择"
            // re-checked on every read
            enabled: { BridgeReader.tick; return BridgeReader.skillIds().length > 0 }
            onClicked: idMenu.popupFor(BridgeReader.skillIds(), "skillId")
        }
    }
    // bar full
    Row_ {
        label: "持续时间"
        visible: card.type === "barFull"
        NumberField {
            from: 0.05; to: 60; decimals: 2; unit: "s"
            value: card.field("hold", 0.5)
            onCommitted: v => card.set("hold", v)
        }
    }
    Label {
        visible: card.type === "barFull"
        Layout.leftMargin: card.labelW
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "按本进度条其他触发器给出的进度判定：达到 100%，或冷却、Buff 等倒计时走完时视为填满。回落到 97% 以下后才会再次触发。"
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }
    Row_ {
        label: "显示时长"
        visible: card.type === "skillCast"
        NumberField {
            from: 0.1; to: 600; decimals: 1; unit: "s"
            value: card.field("duration", 3)
            onCommitted: v => card.set("duration", v)
        }
    }

    // Live ids to pick from: adds the chosen one to the field.
    Menu {
        id: idMenu
        property string target
        function popupFor(ids, field) {
            target = field
            while (count > 0) takeItem(0).destroy()
            for (const id of ids) addItem(entry.createObject(idMenu, { text: id }))
            if (ids.length === 0) addItem(entry.createObject(idMenu, { text: "（当前无可选数据）", enabled: false }))
            popup()
        }
        topPadding: 1
        bottomPadding: 1
        background: Rectangle { implicitWidth: 36 * Theme.unit; color: Theme.surface; border.color: Theme.lineStrong }
    }
    Component {
        id: entry
        MenuItem {
            id: item
            implicitHeight: Theme.rowH
            background: Rectangle { color: item.highlighted ? Theme.raised : "transparent" }
            contentItem: Label {
                leftPadding: Theme.unit - item.leftPadding
                verticalAlignment: Text.AlignVCenter
                text: item.text
                color: item.enabled ? Theme.text : Theme.textFaint
                elide: Text.ElideRight
            }
            onTriggered: {
                const ids = String(card.field(idMenu.target, "")).split(/[,，\s]+/).filter(s => s !== "")
                if (!ids.includes(text)) ids.push(text)
                card.set(idMenu.target, ids.join(", "))
            }
        }
    }
}
