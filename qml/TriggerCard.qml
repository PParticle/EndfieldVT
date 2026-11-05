import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// One trigger: when (one or more conditions, all or any), what (an icon's
// effect, a bar's progress), and how an effect runs: following the first
// condition's own progress (a buff's time left, a cooldown), or playing
// once over a set time when the trigger starts. Then a style while it
// holds (Triggers.styleOf): recolor, opacity, glow, a loop animation.
Rectangle {
    id: card
    property var trigger: ({})
    property int number: 1
    property int count: 1          // triggers in the list, for the move buttons
    property var result: ({})      // Triggers.evaluateTrigger(): active, parts
    property bool driving: false   // this trigger is the one drawing the icon
    property int labelW: 14 * Theme.unit
    // A bar's trigger only gives the progress: no effect, always "follow".
    property bool forBar: false
    // A text's trigger only decides when it shows.
    property bool forText: false
    property string kind: ""       // the control's kind, for the hints
    signal changed(var trigger)
    signal removeRequested()
    signal moveRequested(int by)
    signal duplicateRequested()
    // The editor owns the one color picker; it calls back with the color.
    signal colorRequested(string field, Item anchor, color current)
    function pickColor(f, anchor) { colorRequested(f, anchor, field(f, "#ffffff")) }

    function set(field, value) {
        const next = Object.assign({}, trigger)
        next[field] = value
        changed(next)
    }
    function field(name, fallback) { return trigger[name] !== undefined ? trigger[name] : fallback }
    readonly property string effect: card.forBar || card.forText ? "none" : field("effect", "none")
    readonly property string spread: field("spread", "overlay")
    readonly property var conditions: trigger.conditions || []
    function setCondition(i, c) {
        const list = conditions.slice()
        list[i] = c
        set("conditions", list)
    }
    function removeCondition(i) {
        const list = conditions.slice()
        list.splice(i, 1)
        set("conditions", list)
    }
    readonly property string timing: field("timing", "follow")
    readonly property bool sweep: effect === "clockwise" || effect === "counterclockwise"

    color: Theme.base
    border.color: driving ? Theme.accent : Theme.line
    radius: Theme.radius
    implicitHeight: col.implicitHeight + 2 * Theme.gap

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
    component Choice: ThemeComboBox {
        id: choice
        property string field
        property string fallback
        Component.onCompleted: select(card.field(field, fallback))
        Connections { target: card; function onTriggerChanged() { choice.select(card.field(choice.field, choice.fallback)) } }
        onActivated: card.set(field, currentValue)
    }
    // A check box bound to one boolean field.
    component Toggle: AbstractButton {
        id: tg
        property string field
        property bool fallback: false
        property alias label: tgLabel.text
        readonly property bool on: card.field(field, fallback) === true
        implicitHeight: Theme.rowH
        implicitWidth: tgBox.width + Theme.unit + tgLabel.implicitWidth
        hoverEnabled: true
        onClicked: card.set(field, !on)
        Rectangle {
            id: tgBox
            anchors.verticalCenter: parent.verticalCenter
            width: 2 * Theme.unit; height: width
            color: tg.on ? Theme.accent : Theme.surface
            border.color: tg.on ? Theme.accent : tg.hovered ? Theme.text : Theme.lineStrong
            Label {
                anchors.centerIn: parent
                visible: tg.on
                text: "✓"
                color: Theme.frame
                font.pixelSize: Theme.caption
                font.weight: Font.Bold
            }
        }
        Label {
            id: tgLabel
            x: tgBox.width + Theme.unit
            height: parent.height
            verticalAlignment: Text.AlignVCenter
        }
    }
    component Section_: Label {
        Layout.topMargin: Theme.unit / 2
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }

    ColumnLayout {
        id: col
        x: Theme.gap
        y: Theme.gap
        width: card.width - 2 * Theme.gap
        spacing: Theme.unit

        // Header: number, a one-line summary, remove.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.unit
            Rectangle {
                Layout.preferredWidth: 3 * Theme.unit
                Layout.preferredHeight: 3 * Theme.unit
                radius: 2
                color: card.driving ? Theme.accent : card.result.active ? Theme.lineStrong : Theme.raised
                Label {
                    anchors.centerIn: parent
                    text: card.number
                    color: card.driving ? Theme.frame : Theme.textDim
                    font.pixelSize: Theme.caption
                    font.weight: Font.DemiBold
                }
            }
            Label {
                Layout.fillWidth: true
                text: card.conditions.map(c => Triggers.label(c.type)).join(card.field("mode", "all") === "any" ? " 或 " : " + ")
                      + (card.forBar ? (card.field("drives", true) ? "  →  进度" : "") : card.forText ? "  →  显示"
                         : card.effect !== "none" || !Triggers.hasStyle(card.trigger) ? "  →  " + Triggers.effectLabel(card.effect) : "")
                      + (Triggers.hasStyle(card.trigger) ? "  →  样式" : "")
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            FlatButton { text: "↑"; enabled: card.number > 1; onClicked: card.moveRequested(-1) }
            FlatButton { text: "↓"; enabled: card.number < card.count; onClicked: card.moveRequested(1) }
            FlatButton { text: "复制"; onClicked: card.duplicateRequested() }
            FlatButton { text: "删除"; danger: true; onClicked: card.removeRequested() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.unit / 2
            spacing: Theme.unit
            Label { text: "触发条件"; color: Theme.textFaint; font.pixelSize: Theme.caption }
            ThemeComboBox {
                id: modeBox
                visible: card.conditions.length > 1
                Layout.preferredWidth: 20 * Theme.unit
                model: [{ label: "全部满足", value: "all" }, { label: "任一满足", value: "any" }]
                Component.onCompleted: select(card.field("mode", "all"))
                Connections { target: card; function onTriggerChanged() { modeBox.select(card.field("mode", "all")) } }
                onActivated: card.set("mode", currentValue)
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                text: "＋ 条件"
                onClicked: card.set("conditions", card.conditions.concat([Triggers.makeCondition("combat")]))
            }
        }
        // One block per condition; the first gives the progress and numbers.
        Repeater {
            model: card.conditions.length
            ColumnLayout {
                id: condBlock
                required property int index
                readonly property var part: (card.result.parts || [])[index] || ({})
                Layout.fillWidth: true
                spacing: Theme.unit
                Rectangle {
                    visible: condBlock.index > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: card.labelW
                    implicitHeight: 1
                    color: Theme.line
                }
                ConditionFields {
                    Layout.fillWidth: true
                    labelW: card.labelW
                    spec: card.conditions[condBlock.index]
                    onChanged: c => card.setCondition(condBlock.index, c)
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.labelW
                    Label {
                        Layout.fillWidth: true
                        text: (condBlock.part.active ? "● 满足  " : "○ 不满足  ") + (condBlock.part.note || "")
                              + (condBlock.index === 0 && card.conditions.length > 1 && !card.forText ? "（进度和数字取自这一条）" : "")
                        color: condBlock.part.active ? Theme.accent : condBlock.part.available === false ? Theme.textFaint : Theme.textDim
                        font.pixelSize: Theme.caption
                        elide: Text.ElideRight
                    }
                    FlatButton {
                        visible: card.conditions.length > 1
                        text: "移除"
                        danger: true
                        onClicked: card.removeCondition(condBlock.index)
                    }
                }
            }
        }

        Rectangle { visible: !card.forText; Layout.fillWidth: true; Layout.topMargin: Theme.unit / 2; implicitHeight: 1; color: Theme.line }
        Section_ { visible: !card.forText; text: card.forBar ? "进度" : "触发效果" }
        Row_ {
            label: "效果"
            visible: !card.forBar && !card.forText
            Choice { field: "effect"; fallback: "none"; model: Triggers.effects }
        }
        Row_ {
            label: "扩散方式"
            visible: card.effect === "radial"
            ThemeComboBox {
                id: spreadBox
                Layout.preferredWidth: 30 * Theme.unit
                model: [
                    { label: "图标保持，叠加扩散一层颜色", value: "overlay" },
                    { label: "图标本身从无变大", value: "self" }
                ]
                Component.onCompleted: select(card.spread)
                Connections { target: card; function onTriggerChanged() { spreadBox.select(card.spread) } }
                onActivated: card.set("spread", currentValue)
            }
        }
        Row_ {
            label: "扩散颜色"
            visible: card.effect === "radial" && card.spread === "overlay"
            ColorField {
                id: spreadSwatch
                color: card.field("spreadColor", "#ffffff")
                onClicked: card.pickColor("spreadColor", spreadSwatch)
            }
            Label {
                Layout.leftMargin: Theme.gap
                Layout.preferredWidth: 8 * Theme.unit
                text: "不透明度"
                color: Theme.textDim
            }
            NumberField {
                from: 0; to: 100; unit: "%"
                value: card.field("spreadOpacity", 70)
                onCommitted: v => card.set("spreadOpacity", v)
            }
        }
        Row_ {
            label: "起点"
            visible: card.sweep
            NumberField {
                from: 0; to: 359; unit: "°"
                value: card.field("startAngle", 0)
                onCommitted: v => card.set("startAngle", v)
            }
            Label {
                Layout.leftMargin: Theme.unit
                text: "0° 为正上方，顺时针增加"
                color: Theme.textFaint
                font.pixelSize: Theme.caption
            }
        }
        Row_ {
            label: "进度"
            visible: !card.forBar && card.effect !== "none"
            Choice {
                field: "timing"; fallback: "follow"
                model: [
                    { label: "跟随条件（剩余时间、冷却、充能）", value: "follow" },
                    { label: "满足时播放一次动画", value: "play" }
                ]
            }
        }
        // A bar shows the whole 0..max, or one part of it: three bars at
        // 0-100, 100-200, 200-300 SP make one cell each.
        Row_ {
            label: "给出进度"
            visible: card.forBar
            Toggle { field: "drives"; fallback: true; label: "用这个触发器的数值填充进度条" }
        }
        Row_ {
            label: "进度范围"
            visible: card.forBar && card.field("drives", true)
            Choice {
                field: "range"; fallback: "full"
                model: [{ label: "0 到上限", value: "full" }, { label: "自定范围", value: "part" }]
            }
            NumberField {
                visible: card.field("range", "full") === "part"
                Layout.leftMargin: Theme.unit
                from: -100000; to: 100000; unit: "从"
                value: card.field("rangeFrom", 0)
                onCommitted: v => card.set("rangeFrom", v)
            }
            NumberField {
                visible: card.field("range", "full") === "part"
                Layout.leftMargin: Theme.unit
                from: -100000; to: 100000; unit: "到"
                value: card.field("rangeTo", 100)
                onCommitted: v => card.set("rangeTo", v)
            }
        }
        Label {
            visible: card.forBar && card.field("drives", true) && card.field("range", "full") === "part"
            Layout.fillWidth: true
            Layout.leftMargin: card.labelW
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: Theme.caption
            text: "第一条条件的数值（技力、HP、剩余秒数…）在这个范围里时按比例填充，低于「从」为空，高于「到」为满。"
                  + " 当前数值 " + (card.result.value !== undefined ? Math.round(card.result.value * 10) / 10 : "-")
                  + " → " + Math.round(Math.max(0, Math.min(1, Triggers.barProgress(card.trigger, card.result))) * 100) + "%"
        }
        Row_ {
            label: "反向"
            visible: (card.forBar && card.field("drives", true)) || (card.effect !== "none" && card.timing === "follow")
            AbstractButton {
                id: rev
                readonly property bool on: card.field("reverse", false)
                implicitHeight: Theme.rowH
                implicitWidth: box.width + Theme.unit + revLabel.implicitWidth
                hoverEnabled: true
                onClicked: card.set("reverse", !on)
                Rectangle {
                    id: box
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2 * Theme.unit; height: width
                    color: rev.on ? Theme.accent : Theme.surface
                    border.color: rev.on ? Theme.accent : rev.hovered ? Theme.text : Theme.lineStrong
                    Label {
                        anchors.centerIn: parent
                        visible: rev.on
                        text: "✓"
                        color: Theme.frame
                        font.pixelSize: Theme.caption
                        font.weight: Font.Bold
                    }
                }
                Label {
                    id: revLabel
                    x: box.width + Theme.unit
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "随剩余时间增加（冷却转好时填满）"
                }
            }
        }
        Row_ {
            label: "动画时长"
            visible: card.effect !== "none" && card.timing === "play"
            NumberField {
                from: 0.05; to: 60; decimals: 2; unit: "s"
                value: card.field("playSeconds", 0.4)
                onCommitted: v => card.set("playSeconds", v)
            }
        }
        Row_ {
            label: "播放完"
            visible: card.effect !== "none" && card.timing === "play"
            Choice {
                field: "after"; fallback: "keep"
                model: [{ label: "保持显示", value: "keep" }, { label: "消失", value: "hide" }]
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: card.labelW
            visible: !card.forText && ((card.forBar && card.field("drives", true)) || card.effect !== "none")
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: Theme.caption
            text: card.forBar
                ? "条件满足时，进度条显示它的进度：Buff 和技能释放是剩余时间比例，连携技是剩余冷却比例，其余是当前值 / 上限。"
                : card.timing === "play"
                ? "条件从不满足变为满足时，" + Triggers.effectLabel(card.effect)
                  + (card.effect === "radial" ? (card.spread === "self" ? "（图标从无变大）" : "（叠加一层扩散）") : "") + "在 "
                  + card.field("playSeconds", 0.4) + " 秒内从 0 播放到完整，之后"
                  + (card.field("after", "keep") === "hide" ? "图标消失，直到触发器再次满足。" : "保持完整显示。")
                : "进度取自条件：Buff 和技能释放是剩余时间比例，连携技是剩余冷却比例，其余是当前值 / 上限。"
        }

        // Style while the trigger holds.
        Rectangle { Layout.fillWidth: true; Layout.topMargin: Theme.unit / 2; implicitHeight: 1; color: Theme.line }
        Section_ { text: "满足时样式" }
        Row_ {
            label: "改颜色"
            Toggle {
                field: "tint"
                label: card.kind === "icon" ? "边框和填充" : card.kind === "bar" ? "进度颜色"
                     : card.kind === "text" ? "文字颜色" : card.kind === "buffs" ? "格子颜色" : "成员的颜色"
            }
            ColorField {
                id: tintSwatch
                visible: card.field("tint", false) === true
                Layout.leftMargin: Theme.gap
                color: card.field("tintColor", "#e5484d")
                onClicked: card.colorRequested("tintColor", tintSwatch, card.field("tintColor", "#e5484d"))
            }
        }
        Row_ {
            label: "不透明度"
            NumberField {
                from: 0; to: 100; unit: "%"
                value: card.field("alpha", 100)
                onCommitted: v => card.set("alpha", v)
            }
            Label {
                Layout.leftMargin: Theme.unit
                text: "100% 为不变"
                color: Theme.textFaint
                font.pixelSize: Theme.caption
            }
        }
        Row_ {
            label: "发光"
            Choice { field: "glow"; fallback: "none"; model: Triggers.glows }
            ColorField {
                id: glowSwatch
                visible: card.field("glow", "none") !== "none"
                Layout.leftMargin: Theme.gap
                color: card.field("glowColor", "#ffd166")
                onClicked: card.colorRequested("glowColor", glowSwatch, card.field("glowColor", "#ffd166"))
            }
            NumberField {
                visible: card.field("glow", "none") !== "none"
                Layout.leftMargin: Theme.unit
                from: 1; to: 40; unit: "px"
                value: card.field("glowSize", 8)
                onCommitted: v => card.set("glowSize", v)
            }
        }
        Row_ {
            label: "循环动画"
            Choice { field: "loop"; fallback: "none"; model: Triggers.loops }
            NumberField {
                visible: card.field("loop", "none") !== "none"
                Layout.leftMargin: Theme.unit
                from: 0.1; to: 10; decimals: 1; unit: "s"
                value: card.field("loopSeconds", 1)
                onCommitted: v => card.set("loopSeconds", v)
            }
            Label {
                visible: card.field("loop", "none") !== "none"
                Layout.leftMargin: Theme.unit
                text: "一个周期"
                color: Theme.textFaint
                font.pixelSize: Theme.caption
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.leftMargin: card.labelW
            wrapMode: Text.WordWrap
            color: Theme.textFaint
            font.pixelSize: Theme.caption
            text: "只在这个触发器满足时生效；多个满足时，后面的覆盖前面的。"
                  + (card.kind === "group" ? "组的样式作用到每个成员上，成员自己的样式优先。"
                     : card.forBar ? "只改样式、不想影响进度时，把「给出进度」关掉。" : "")
        }
    }
}
