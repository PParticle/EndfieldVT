import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// What EndfieldDataBridge reports right now. Top: SP, and the controlled
// operator next to the locked target. Middle: the squad and the enemies,
// each unit with its own buffs. Bottom: the event log (one-off events, not
// live state).
PageFrame {
    id: page
    title: "调试控制台"
    subtitle: BridgeReader.status === "online"
              ? "EndfieldDataBridge " + BridgeReader.info.abi + " · 会话 " + BridgeReader.info.session
                + " · 采样率 " + BridgeReader.info.sampleIntervalMs + " ms"
              : "EndfieldDataBridge：" + BridgeReader.statusText

    readonly property bool live: BridgeReader.status === "online" || BridgeReader.status === "stale"

    // ---- formatting
    function num(v, digits) { return v === undefined || v < 0 ? "—" : Number(v).toFixed(digits === undefined ? 0 : digits) }
    function secs(v) { return v === undefined || v < 0 ? "—" : Number(v).toFixed(1) + " s" }
    function ratio(v, max) { return max > 0 ? Math.max(0, Math.min(1, v / max)) : 0 }

    // ---- building blocks
    component Card: Rectangle {
        id: card
        property string title
        property string note
        default property alias body: content.data
        color: Theme.surface
        border.color: Theme.line
        radius: Theme.radius
        Label {
            x: Theme.gap
            height: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            text: card.title
            font.weight: Font.DemiBold
        }
        Label {
            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            height: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            text: card.note
            color: Theme.textFaint
            font.pixelSize: Theme.caption
        }
        Rectangle { x: 1; y: Theme.rowH; width: card.width - 2; height: 1; color: Theme.line }
        Item {
            id: content
            x: Theme.gap
            y: Theme.rowH + Theme.unit
            width: card.width - 2 * Theme.gap
            height: card.height - y - Theme.unit
        }
    }
    // A thin labelled bar: label, value text, track.
    component Meter: Item {
        id: meter
        property string label
        property string text
        property real fraction: 0
        property color color: Theme.accent
        implicitHeight: 2 * Theme.unit + 6
        Label { text: meter.label; color: Theme.textDim; font.pixelSize: Theme.caption }
        Label { anchors.right: parent.right; text: meter.text; font.pixelSize: Theme.caption }
        Rectangle {
            y: 2 * Theme.unit
            width: parent.width
            height: 4
            color: Theme.lineStrong
            Rectangle { width: parent.width * meter.fraction; height: parent.height; color: meter.color }
        }
    }
    // A line of small key/value text.
    component Fact: Label {
        color: Theme.textDim
        font.pixelSize: Theme.caption
        elide: Text.ElideRight
    }
    // One unit (squad member or enemy): name, HP, poise, then its buffs.
    component UnitBlock: Rectangle {
        id: unit
        property var row: ({})
        property string heading
        property string badge
        property color badgeColor: Theme.accent
        readonly property bool hasHp: row.hp !== undefined && row.hp >= 0
        color: Theme.base
        border.color: unit.row.isMain || unit.row.isLocked ? Theme.accent : Theme.line
        implicitHeight: col.implicitHeight + 2 * Theme.unit
        opacity: row.fresh === false ? 0.55 : 1

        ColumnLayout {
            id: col
            x: Theme.unit + 4
            y: Theme.unit
            width: unit.width - 2 * (Theme.unit + 4)
            spacing: Theme.unit / 2
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.unit
                Label { text: unit.heading; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                Label {
                    visible: unit.badge !== ""
                    text: unit.badge
                    color: Theme.frame
                    font.pixelSize: Theme.caption
                    leftPadding: 6; rightPadding: 6
                    background: Rectangle { color: unit.badgeColor; radius: 2 }
                }
            }
            Meter {
                Layout.fillWidth: true
                visible: unit.hasHp
                label: "HP"
                text: unit.hasHp ? page.num(unit.row.hp) + " / " + page.num(unit.row.hpMax) : ""
                fraction: unit.hasHp ? page.ratio(unit.row.hp, unit.row.hpMax) : 0
                color: "#4caf7a"
            }
            Meter {
                Layout.fillWidth: true
                visible: unit.row.hasPoise === true
                label: unit.row.broken ? (unit.row.recovering ? "失衡恢复 " + page.secs(unit.row.recoveryLeft) : "失衡")
                                       : "失衡值"
                text: page.num(unit.row.poise) + " / " + page.num(unit.row.poiseMax)
                fraction: page.ratio(unit.row.poise, unit.row.poiseMax)
                color: unit.row.broken ? Theme.danger : Theme.textDim
            }
            // extra lines (squad: ultimate and combo)
            Loader {
                Layout.fillWidth: true
                active: unit.extra !== null
                sourceComponent: unit.extra
            }
            BuffList { Layout.fillWidth: true; ownerUid: unit.row.uid || 0 }
        }
        property Component extra: null
    }
    // The buffs a unit carries: the shared buff model filtered to this
    // owner, so each unit makes rows for its own buffs only (not one hidden
    // row per buff of every unit: thousands of items in a boss fight).
    component BuffList: Column {
        id: list
        property real ownerUid: 0   // a uint32: real keeps all of it (int would go negative)
        spacing: 2
        Label {
            visible: buffRepeater.count === 0
            text: "无 Buff"
            color: Theme.textFaint
            font.pixelSize: Theme.caption
        }
        Repeater {
            id: buffRepeater
            model: OwnerFilterModel { source: BridgeReader.buffs; ownerUid: list.ownerUid }
            delegate: Item {
                id: buff
                required property string buffId
                required property string parentBuffId
                required property string source
                required property string rootSource
                required property int isDebuff
                required property bool infinite
                required property int stacks
                required property real duration
                required property real timeLeft
                required property real dilation
                width: list.width
                height: 2 * Theme.unit + 2
                ToolTip.visible: hover.hovered
                ToolTip.delay: 300
                ToolTip.text: buffId + (parentBuffId ? "\n父 Buff: " + parentBuffId : "")
                              + "\n来源: " + source + (rootSource !== source ? "\n最初来源: " + rootSource : "")
                              + "\n时间速率: " + page.num(dilation, 2)
                HoverHandler { id: hover }
                Rectangle {   // remaining time behind the row
                    visible: !buff.infinite && buff.duration > 0
                    width: parent.width * page.ratio(buff.timeLeft, buff.duration)
                    height: parent.height
                    color: buff.isDebuff === 1 ? Qt.rgba(0.9, 0.28, 0.3, 0.18) : Qt.rgba(0.95, 0.79, 0.3, 0.14)
                }
                Label {
                    x: 4
                    width: parent.width - stackLabel.width - timeLabel.width - 16
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: buff.buffId
                    color: buff.isDebuff === 1 ? "#f08a8d" : Theme.text
                    font.pixelSize: Theme.caption
                    elide: Text.ElideMiddle
                }
                Label {
                    id: stackLabel
                    anchors.right: timeLabel.left
                    anchors.rightMargin: Theme.unit
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: buff.stacks > 1 ? "×" + buff.stacks : ""
                    color: Theme.accent
                    font.pixelSize: Theme.caption
                }
                Label {
                    id: timeLabel
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: buff.infinite ? "永久" : page.num(buff.timeLeft, 1) + " / " + page.num(buff.duration, 1)
                    color: Theme.textDim
                    font.pixelSize: Theme.caption
                }
            }
        }
    }

    // ---- not connected: one line in the middle
    Label {
        visible: !page.live
        anchors.centerIn: parent
        text: BridgeReader.statusText + "。请启动游戏并加载 EndfieldDataBridge 插件。"
        color: Theme.textFaint
    }

    ColumnLayout {
        id: board
        visible: page.live
        anchors.fill: parent
        spacing: Theme.gap
        // Below the fixed top row: units get 3 parts, events 2.
        readonly property real rest: height - topRow.height - 2 * spacing

        // ---- top row: SP | controlled operator + locked target
        RowLayout {
            id: topRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Theme.rowH + Theme.unit + 3 * Theme.rowH + Theme.unit
            spacing: Theme.gap

            Card {
                title: "技力"
                note: BridgeReader.team.fresh === false ? "未更新" : ""
                Layout.preferredWidth: 26 * Theme.unit
                Layout.fillHeight: true
                Column {
                    width: parent.width
                    spacing: Theme.unit
                    Label {
                        text: page.num(BridgeReader.team.atb) + " / " + page.num(BridgeReader.team.atbMax)
                        font.pixelSize: Theme.title
                        font.weight: Font.DemiBold
                    }
                    // One cell per atbPerCell, filled as SP allows.
                    Row {
                        id: cells
                        readonly property int count: BridgeReader.team.atbPerCell > 0
                            ? Math.max(1, Math.round(BridgeReader.team.atbMax / BridgeReader.team.atbPerCell)) : 1
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: cells.count
                            Rectangle {
                                required property int index
                                width: (cells.width - (cells.count - 1) * 4) / cells.count
                                height: 8
                                color: Theme.lineStrong
                                Rectangle {
                                    readonly property real per: BridgeReader.team.atbPerCell > 0 ? BridgeReader.team.atbPerCell : (BridgeReader.team.atbMax || 1)
                                    width: parent.width * page.ratio(BridgeReader.team.atb - parent.index * per, per)
                                    height: parent.height
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                    Fact { text: "单格 " + page.num(BridgeReader.team.atbPerCell) }
                }
            }

            Card {
                title: "主控与目标"
                Layout.fillWidth: true
                Layout.fillHeight: true
                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.gap
                    // controlled operator
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.unit / 2
                        readonly property var op: BridgeReader.mainOperator
                        Fact { text: "主控干员" }
                        Label {
                            text: parent.op.name ? (parent.op.slot + 1) + "号位 " + parent.op.name : "—"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Fact {
                            Layout.fillWidth: true
                            text: parent.op.name ? "终结技 " + page.num(parent.op.ultimate) + " / " + page.num(parent.op.ultimateMax)
                                  + "　连携技 " + (parent.op.hasCombo ? (parent.op.comboLeft > 0 ? page.secs(parent.op.comboLeft) : "就绪") : "无") : ""
                        }
                    }
                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.line }
                    // locked target
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.unit / 2
                        readonly property var target: BridgeReader.lockTarget
                        Fact {
                            text: !BridgeReader.team.lockUid ? "目标状态"
                                  : "目标状态 · " + (BridgeReader.team.lockMode ? "手动锁定" : BridgeReader.team.autoLock ? "自动锁定" : "已锁定")
                        }
                        Label {
                            text: parent.target.name || "无"
                            color: parent.target.name ? Theme.text : Theme.textFaint
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Fact {
                            Layout.fillWidth: true
                            text: parent.target.missing ? "目标不在单位列表中"
                                  : parent.target.hp !== undefined
                                    ? "HP " + page.num(parent.target.hp) + " / " + page.num(parent.target.hpMax)
                                      + (parent.target.hasPoise ? "　失衡值 " + page.num(parent.target.poise) + " / " + page.num(parent.target.poiseMax)
                                         + (parent.target.broken ? " (失衡)" : "") : "")
                                    : ""
                        }
                    }
                }
            }
        }

        // ---- middle row: squad | enemies
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false   // layouts fill by default; the events card takes the rest
            Layout.preferredHeight: Math.round(board.rest * 3 / 5)
            spacing: Theme.gap

            Card {
                title: "队伍状态"
                note: BridgeReader.info.buffsPartial ? "插件加载前已存在的 Buff 可能无法追溯" : ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollView {
                    id: squadScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Column {
                        width: squadScroll.availableWidth
                        spacing: Theme.unit
                        Repeater {
                            model: BridgeReader.squad
                            UnitBlock {
                                id: member
                                required property var model
                                width: parent.width
                                visible: model.present
                                row: model
                                heading: (model.slot + 1) + "号位 " + model.name
                                badge: model.isMain ? "控制中" : ""
                                extra: Component {
                                    Column {
                                        spacing: Theme.unit / 2
                                        Meter {
                                            width: parent.width
                                            label: "终结技"
                                            text: page.num(member.model.ultimate) + " / " + page.num(member.model.ultimateMax)
                                            fraction: page.ratio(member.model.ultimate, member.model.ultimateMax)
                                        }
                                        Meter {
                                            width: parent.width
                                            visible: member.model.hasCombo
                                            label: "连携技冷却"
                                            text: member.model.comboLeft > 0 ? page.secs(member.model.comboLeft) + " / " + page.secs(member.model.comboCooldown) : "就绪"
                                            fraction: page.ratio(member.model.comboLeft, member.model.comboCooldown)
                                            color: Theme.textDim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Card {
                title: "敌方状态"
                note: BridgeReader.info.headBarUnits === false ? "血条数据不可用" : BridgeReader.units.count + " 个"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Label {
                    visible: BridgeReader.units.count === 0
                    text: "视野内未检测到目标"
                    color: Theme.textFaint
                    font.pixelSize: Theme.caption
                }
                ScrollView {
                    id: enemyScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Column {
                        width: enemyScroll.availableWidth
                        spacing: Theme.unit
                        Repeater {
                            model: BridgeReader.units
                            UnitBlock {
                                required property var model
                                width: parent.width
                                row: model
                                heading: model.name
                                badge: model.isLocked ? "锁定" : model.faction !== 3 ? model.factionText : ""
                                badgeColor: model.isLocked ? Theme.accent : Theme.textDim
                            }
                        }
                    }
                }
            }
        }

        // ---- bottom: events
        Card {
            id: eventsCard
            title: "事件日志"
            note: (BridgeReader.lostEvents > 0 ? "丢失 " + BridgeReader.lostEvents + " 条　" : "")
                  + (BridgeReader.info.skillCasts === false ? "技能事件不可用" : "")
            Layout.fillWidth: true
            Layout.fillHeight: true
            property int tab: 0

            Row {
                parent: eventsCard
                x: 12 * Theme.unit
                height: Theme.rowH
                spacing: 0
                Repeater {
                    model: ["技能释放事件", "Buff 变更事件"]
                    AbstractButton {
                        required property int index
                        required property string modelData
                        height: Theme.rowH
                        width: tabLabel.implicitWidth + 2 * Theme.unit
                        onClicked: eventsCard.tab = index
                        contentItem: Label {
                            id: tabLabel
                            text: parent.modelData
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: eventsCard.tab === parent.index ? Theme.accent : Theme.textDim
                            font.pixelSize: Theme.caption
                        }
                        background: Rectangle {
                            color: "transparent"
                            Rectangle {
                                visible: eventsCard.tab === parent.parent.index
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: Theme.accent
                            }
                        }
                    }
                }
                AbstractButton {
                    height: Theme.rowH
                    width: clearLabel.implicitWidth + 2 * Theme.unit
                    onClicked: BridgeReader.clearEvents()
                    contentItem: Label {
                        id: clearLabel
                        text: "清空"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: parent.hovered ? Theme.text : Theme.textFaint
                        font.pixelSize: Theme.caption
                    }
                    background: Item {}
                }
            }

            // skill casts
            ListView {
                visible: eventsCard.tab === 0
                anchors.fill: parent
                clip: true
                model: BridgeReader.skillEvents
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: ev
                    required property real time
                    required property bool started
                    required property string caster
                    required property int casterSlot
                    required property string skillType
                    required property string skillId
                    required property string outcome
                    required property string interrupted
                    required property real castLength
                    width: ListView.view.width
                    height: 2 * Theme.unit + 4
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.gap
                        Fact { width: 7 * Theme.unit; text: page.num(ev.time, 2) + " s"; horizontalAlignment: Text.AlignRight }
                        Fact {
                            width: 5 * Theme.unit
                            text: ev.started ? "开始" : "结束"
                            color: ev.started ? Theme.accent : Theme.textDim
                        }
                        Fact { width: 20 * Theme.unit; text: ev.caster; color: ev.casterSlot >= 0 ? Theme.text : "#f08a8d" }
                        Fact { width: 8 * Theme.unit; text: ev.skillType }
                        Fact { width: 34 * Theme.unit; text: ev.skillId; color: Theme.text; elide: Text.ElideMiddle }
                        Fact {
                            text: ev.started ? "" : ev.outcome + (ev.interrupted ? "：" + ev.interrupted : "")
                                  + (ev.castLength >= 0 ? "　" + page.num(ev.castLength, 2) + " s" : "")
                            color: ev.interrupted ? "#f08a8d" : Theme.textDim
                        }
                    }
                }
                Label {
                    visible: parent.count === 0
                    text: "暂无技能事件"
                    color: Theme.textFaint
                    font.pixelSize: Theme.caption
                }
            }
            // buff changes
            ListView {
                visible: eventsCard.tab === 1
                anchors.fill: parent
                clip: true
                model: BridgeReader.buffEvents
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: bev
                    required property real time
                    required property string kind
                    required property string owner
                    required property string buffId
                    required property int stacks
                    required property string reason
                    width: ListView.view.width
                    height: 2 * Theme.unit + 4
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.gap
                        Fact { width: 7 * Theme.unit; text: page.num(bev.time, 2) + " s"; horizontalAlignment: Text.AlignRight }
                        Fact { width: 5 * Theme.unit; text: bev.kind; color: bev.kind === "移除" ? Theme.textDim : Theme.accent }
                        Fact { width: 20 * Theme.unit; text: bev.owner }
                        Fact { width: 40 * Theme.unit; text: bev.buffId; color: Theme.text; elide: Text.ElideMiddle }
                        Fact { text: (bev.stacks > 1 ? "×" + bev.stacks + "　" : "") + bev.reason }
                    }
                }
                Label {
                    visible: parent.count === 0
                    text: "暂无 Buff 事件"
                    color: Theme.textFaint
                    font.pixelSize: Theme.caption
                }
            }
        }
    }
}
