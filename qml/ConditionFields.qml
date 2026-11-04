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
        label: "单位"
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
        label: "Buff id"
        visible: card.type === "buff"
        ThemeTextField {
            id: buffIds
            Layout.fillWidth: true
            placeholderText: "多个 id 用逗号分开"
            text: card.field("buffIds", "")
            onEditingFinished: card.set("buffIds", text.trim())
        }
        FlatButton {
            Layout.leftMargin: Theme.unit
            text: "从当前选择"
            enabled: { BridgeReader.tick; return BridgeReader.buffIds().length > 0 }
            onClicked: idMenu.popupFor(BridgeReader.buffIds(), "buffIds")
        }
    }
    Row_ {
        label: "施加者"
        visible: card.type === "buff"
        Choice {
            field: "source"; fallback: "any"
            model: [
                { label: "任意", value: "any" }, { label: "我方", value: "squad" },
                { label: "敌方", value: "enemy" }, { label: "持有者自己", value: "self" }
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

    // atb
    Row_ {
        label: "计量"
        visible: card.type === "atb"
        Choice {
            field: "measure"; fallback: "sp"
            model: [{ label: "技力值（0–上限）", value: "sp" }, { label: "满格数（0–3 格）", value: "cells" }]
        }
    }
    // ultimate
    Row_ {
        label: "状态"
        visible: card.type === "ultimate" && !card.valueOnly
        Choice {
            field: "measure"; fallback: "ready"
            model: [{ label: "充满（就绪）", value: "ready" }, { label: "充能值比较", value: "value" }]
        }
    }
    // combo
    Row_ {
        label: "状态"
        visible: card.type === "combo" && !card.valueOnly
        Choice {
            field: "show"; fallback: "cooling"
            model: [{ label: "冷却中（释放后）", value: "cooling" }, { label: "冷却完毕", value: "ready" }]
        }
    }
    // poise
    Row_ {
        label: "状态"
        visible: card.type === "poise"
        Choice {
            field: "show"; fallback: "broken"
            model: [{ label: "处于失衡", value: "broken" }, { label: "失衡值比较（%）", value: "value" }]
        }
    }
    // lock
    Row_ {
        label: "状态"
        visible: card.type === "lock"
        Choice {
            field: "show"; fallback: "locked"
            model: [
                { label: "有锁定目标", value: "locked" }, { label: "手动锁定", value: "manual" },
                { label: "没有锁定目标", value: "none" }
            ]
        }
    }

    // combat
    Row_ {
        label: "状态"
        visible: card.type === "combat"
        Choice {
            field: "show"; fallback: "in"
            model: [{ label: "战斗中", value: "in" }, { label: "不在战斗", value: "out" }]
        }
    }
    Label {
        visible: card.type === "combat"
        Layout.leftMargin: card.labelW
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: BridgeReader.info.inFight ? "取自游戏自己的战斗状态：按波次刷怪时，下一波出来前也算战斗中。"
                                        : "当前的 Bridge 没有战斗状态（需要 ABI 1.3），暂按「有锁定目标、有敌人血条、或 5 秒内小队放过技能」估算。"
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }

    // threshold: atb, ultimate (value), hp, poise (value). "不比较" only
    // reads the value (for a bar's progress or a text's number).
    readonly property bool hasThreshold: !valueOnly && (type === "atb" || type === "hp"
                 || (type === "ultimate" && field("measure", "ready") === "value")
                 || (type === "poise" && field("show", "broken") === "value"))
    Row_ {
        label: "比较"
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
                  ? "只读数值，总是满足：给进度条的进度、文本的数字用"
                  : card.type === "hp" ? "按 HP 占上限的百分比判断，例：≤ 30% = 残血提示"
                  : card.type === "poise" ? "按失衡值占上限的百分比判断"
                  : card.type === "atb" && card.field("measure", "sp") === "cells" ? "按满格数判断（每格 = 技力上限 / 格数），例：≥ 2 格 = 够放两次战技"
                  : card.type === "atb" ? "按技力值判断，例：≥ 100"
                  : "按充能值判断"
        }
    }

    // skill cast
    Row_ {
        label: "技能类型"
        visible: card.type === "skillCast"
        Choice {
            field: "skillType"; fallback: "any"
            model: [
                { label: "任意", value: "any" }, { label: "战技", value: "normal" },
                { label: "连携技", value: "combo" }, { label: "终结技", value: "ultimate" }
            ]
        }
    }
    Row_ {
        label: "技能 id"
        visible: card.type === "skillCast"
        ThemeTextField {
            Layout.fillWidth: true
            placeholderText: "留空 = 任意技能；多个用逗号分开"
            text: card.field("skillId", "")
            onEditingFinished: card.set("skillId", text.trim())
        }
        FlatButton {
            Layout.leftMargin: Theme.unit
            text: "从最近释放"
            // re-checked on every read
            enabled: { BridgeReader.tick; return BridgeReader.skillIds().length > 0 }
            onClicked: idMenu.popupFor(BridgeReader.skillIds(), "skillId")
        }
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
            if (ids.length === 0) addItem(entry.createObject(idMenu, { text: "（当前没有）", enabled: false }))
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
