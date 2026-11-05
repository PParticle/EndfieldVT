import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The selected control's properties. Icons and bars get three tabs: 载入
// (when the control exists), 触发器 (icons: what plays an effect; bars: what
// gives the progress) and 外观. The row is re-read whenever the model changes, so edits
// made elsewhere (the preview window, the sidebar) show up here at once.
PageFrame {
    id: editor
    property ListModel model
    property int selectedIndex: -1
    signal renameRequested(string name)
    signal roleChanged(string role, var value)
    signal groupMoveRequested(real x, real y)
    // Main.groups: for a selected group, its members' bounds.
    property var groups: ({})
    // Main.groupStates: a member's group decides with it.
    property var groupStates: ({})
    readonly property var parentState: { const p = value("parentId", ""); return p !== "" ? groupStates[p] || null : null }
    // The group's 显示 setting, for the status line.
    readonly property string parentShow: {
        revision
        const p = value("parentId", "")
        if (p === "" || !model) return ""
        for (let i = 0; i < model.count; ++i)
            if (model.get(i).uid === p) return Triggers.parseTriggers(model.get(i).triggers).show
        return ""
    }
    readonly property var groupInfo: kind === "group" ? groups[value("uid", "")] || null : null

    // model.get() is a snapshot; bumping `revision` on any model change makes
    // `row` re-read it.
    property int revision: 0
    Connections {
        target: editor.model
        function onDataChanged() { editor.revision++ }
        function onRowsRemoved() { editor.revision++ }
        function onRowsInserted() { editor.revision++ }
        function onRowsMoved() { editor.revision++ }
    }
    readonly property var row: {
        revision
        return model && selectedIndex >= 0 && selectedIndex < model.count ? model.get(selectedIndex) : null
    }
    function value(role, fallback) { return row && row[role] !== undefined ? row[role] : fallback }

    readonly property string kind: value("kind", "")
    readonly property bool tabbed: kind !== ""
    readonly property var kindNames: ({ icon: "图标", bar: "进度条", text: "文本", buffs: "Buff列表", group: "组" })
    readonly property int labelW: 14 * Theme.unit
    property int tab: 0

    title: value("name", "控件")
    subtitle: (kindNames[kind] || "控件") + " 属性"

    // ---- triggers, kept as JSON in their role (qml/Triggers.qml)
    readonly property var triggers: Triggers.parseTriggers(value("triggers", ""))
    function saveTriggers(list, show, motion) {
        const out = { show: show !== undefined ? show : triggers.show, list: list }
        const m = motion !== undefined ? motion : triggers.motion
        if (Triggers.hasMotion(m)) out.motion = m
        roleChanged("triggers", JSON.stringify(out))
    }
    function setMotion(field, v) {
        const m = Object.assign({}, triggers.motion)
        m[field] = v
        saveTriggers(triggers.list, undefined, m)
    }
    function addTrigger(type) {
        const t = kind === "bar" ? Triggers.makeBarTrigger(type) : kind === "text" || kind === "buffs" ? Triggers.makeTextTrigger(type)
                                                                                  : Triggers.makeTrigger(type)
        saveTriggers(triggers.list.concat([t]))
    }
    function moveTrigger(i, by) {
        const j = i + by
        if (j < 0 || j >= triggers.list.length) return
        const list = triggers.list.slice()
        const t = list[i]; list[i] = list[j]; list[j] = t
        saveTriggers(list)
    }
    function duplicateTrigger(i) {
        const list = triggers.list.slice()
        list.splice(i + 1, 0, JSON.parse(JSON.stringify(list[i])))
        saveTriggers(list)
    }
    function replaceTrigger(i, t) {
        const list = triggers.list.slice()
        list[i] = t
        saveTriggers(list)
    }
    function removeTrigger(i) {
        const list = triggers.list.slice()
        list.splice(i, 1)
        saveTriggers(list)
    }
    // 每个小队成员 (Triggers.usesEach): drawn once per squad slot; the
    // states here are slot 1's.
    readonly property bool expanded: row !== null && Triggers.usesEach(row)
    readonly property var reader: expanded ? Triggers.slotReader(1) : BridgeReader
    // Live state, refreshed with every bridge read.
    property var runState: ({})
    readonly property var triggerState: {
        BridgeReader.tick
        return kind === "bar" ? Triggers.runBar(reader, value("triggers", ""))
             : kind === "text" || kind === "buffs" ? Triggers.runText(reader, value("triggers", ""))
             : Triggers.run(reader, value("triggers", ""), runState, Date.now())
    }
    // Tab names per kind; `tab` indexes into them.
    readonly property var tabNames: kind === "text" || kind === "buffs" ? ["内容", "触发器", "外观"] : kind === "group" ? ["触发器", "整体"]
                                                                                 : ["触发器", "外观"]
    readonly property string tabName: tabNames[tab] || ""
    readonly property var textSource: Triggers.parseTextSource(value("textSource", ""))
    // A buff list: what it shows now (for the status line and the hint).
    readonly property var buffNow: {
        BridgeReader.tick
        return kind !== "buffs" ? [] : reader.buffList({ unit: value("buffUnit", "main"), kind: value("buffKind", "all"),
            source: value("buffSource", "any"), only: value("buffOnly", ""), exclude: value("buffExclude", ""), max: value("buffMax", 8) })
    }
    function setTextSource(field, v) {
        const next = Object.assign({}, textSource)
        next[field] = v
        roleChanged("textSource", JSON.stringify(next))
    }
    readonly property var textState: {
        BridgeReader.tick
        return Triggers.composeText(reader, value("textMode", "static"), value("staticText", ""),
                                    value("textSource", ""), false)
    }
    // Another control or tab starts at the top.
    onTabChanged: scroll.contentItem.contentY = 0
    onSelectedIndexChanged: {
        scroll.contentItem.contentY = 0
        tab = 0
        runState = ({})
    }

    // One color picker for the page: a control role, or a field of a trigger.
    ColorPicker {
        id: picker
        property string role
        property int triggerIndex: -1
        parent: Overlay.overlay
        onPicked: c => {
            if (triggerIndex < 0) {
                editor.roleChanged(role, c.toString())
            } else {
                const t = Object.assign({}, editor.triggers.list[triggerIndex])
                t[role] = c.toString()
                editor.replaceTrigger(triggerIndex, t)
            }
        }
    }
    function openPicker(anchor, current) {
        // Next to the swatch, kept on screen.
        const p = anchor.mapToItem(Overlay.overlay, 0, anchor.height + 4)
        picker.x = Math.min(p.x, Overlay.overlay.width - picker.width - Theme.unit)
        picker.y = Math.min(p.y, Overlay.overlay.height - picker.implicitHeight - Theme.unit)
        picker.openWith(current)
    }
    function pickColor(role, field) {
        picker.role = role
        picker.triggerIndex = -1
        openPicker(field, value(role, "#ffffff"))
    }
    function pickTriggerColor(index, field, anchor, current) {
        picker.role = field
        picker.triggerIndex = index
        openPicker(anchor, current)
    }

    component Section: Label {
        Layout.topMargin: Theme.unit
        font.pixelSize: Theme.heading
        font.weight: Font.DemiBold
    }
    component Hint: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.textFaint
        font.pixelSize: Theme.caption
    }
    component FieldRow: RowLayout {
        property alias label: l.text
        Layout.fillWidth: true
        spacing: 0
        Label {
            id: l
            Layout.preferredWidth: editor.labelW
            Layout.preferredHeight: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            color: Theme.textDim
        }
    }
    // A slider and the same number as a typed field, kept in step.
    component SliderField: RowLayout {
        id: sf
        property string role
        property real from: 0
        property real to: 100
        property string unit: "%"
        property real fallback: 0
        Layout.fillWidth: true
        spacing: Theme.gap
        ThemeSlider {
            Layout.fillWidth: true
            from: sf.from
            to: sf.to
            stepSize: 1
            value: editor.value(sf.role, sf.fallback)
            onMoved: editor.roleChanged(sf.role, Math.round(value))
        }
        NumberField {
            from: sf.from
            to: sf.to
            unit: sf.unit
            value: editor.value(sf.role, sf.fallback)
            onCommitted: v => editor.roleChanged(sf.role, v)
        }
    }
    // A color swatch, its opacity, side by side.
    component ColorRow: FieldRow {
        id: cr
        property string colorRole
        property string opacityRole
        property real opacityFallback: 100
        ColorField {
            id: swatch
            color: editor.value(cr.colorRole, "#ffffff")
            onClicked: editor.pickColor(cr.colorRole, swatch)
        }
        Label {
            visible: cr.opacityRole !== ""
            Layout.leftMargin: Theme.gap
            Layout.preferredWidth: 8 * Theme.unit
            text: "不透明度"
            color: Theme.textDim
        }
        SliderField {
            visible: cr.opacityRole !== ""
            role: cr.opacityRole
            fallback: cr.opacityFallback
        }
    }
    component CheckRow: AbstractButton {
        id: check
        // Bound to a role; without one, set `on` and handle clicked.
        property string role
        property bool fallback: true
        property bool on: role !== "" ? editor.value(role, fallback) : false
        implicitHeight: Theme.rowH
        implicitWidth: box.width + Theme.unit + checkLabel.implicitWidth
        hoverEnabled: true
        onClicked: if (role !== "") editor.roleChanged(role, !on)
        Rectangle {
            id: box
            anchors.verticalCenter: parent.verticalCenter
            width: 2 * Theme.unit; height: width
            color: check.on ? Theme.accent : Theme.surface
            border.color: check.on ? Theme.accent : check.hovered ? Theme.text : Theme.lineStrong
            Label {
                anchors.centerIn: parent
                visible: check.on
                text: "✓"
                color: Theme.frame
                font.pixelSize: Theme.caption
                font.weight: Font.Bold
            }
        }
        Label {
            id: checkLabel
            x: box.width + Theme.unit
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: check.text
        }
    }
    // 每个小队成员: where the 4 copies go.
    component ExpandRows: ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.unit
        FieldRow {
            label: "展开方向"
            Choice {
                role: "expandDir"; fallback: "down"
                model: [{ label: "向下", value: "down" }, { label: "向右", value: "right" },
                        { label: "向上", value: "up" }, { label: "向左", value: "left" }]
            }
            Label {
                Layout.leftMargin: Theme.gap
                Layout.preferredWidth: 8 * Theme.unit
                text: "间距"
                color: Theme.textDim
            }
            NumberField {
                from: -1280; to: 1280; unit: "px"
                value: editor.value("expandGap", 8)
                onCommitted: v => editor.roleChanged("expandGap", v)
            }
        }
        Hint {
            Layout.leftMargin: editor.labelW
            text: "按队伍 1–4 号位展开生成 4 份实例，共享外观与触发器逻辑。无干员位置不显示，此处显示的是 1 号位的状态。"
        }
    }
    // The value number's place, size and color (icons and bars).
    component ValueStyle: ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.unit
        FieldRow {
            label: "锚点位置"
            Choice {
                role: "valueAnchor"; fallback: "center"
                model: [
                    { label: "中央", value: "center" }, { label: "上", value: "top" }, { label: "下", value: "bottom" },
                    { label: "左", value: "left" }, { label: "右", value: "right" },
                    { label: "左上", value: "topLeft" }, { label: "右上", value: "topRight" },
                    { label: "左下", value: "bottomLeft" }, { label: "右下", value: "bottomRight" }
                ]
            }
            NumberField {
                Layout.leftMargin: Theme.unit
                from: -640; to: 640; unit: "X"
                value: editor.value("valueOffsetX", 0)
                onCommitted: v => editor.roleChanged("valueOffsetX", v)
            }
            NumberField {
                Layout.leftMargin: Theme.unit
                from: -360; to: 360; unit: "Y"
                value: editor.value("valueOffsetY", 0)
                onCommitted: v => editor.roleChanged("valueOffsetY", v)
            }
        }
        FieldRow {
            label: "字号"
            NumberField {
                from: 6; to: 200; unit: "px"
                value: editor.value("valueSize", 20)
                onCommitted: v => editor.roleChanged("valueSize", v)
            }
            Label {
                Layout.leftMargin: Theme.gap
                Layout.preferredWidth: 8 * Theme.unit
                text: "颜色"
                color: Theme.textDim
            }
            ColorField {
                id: valueSwatch
                color: editor.value("valueColor", "#e6e8eb")
                onClicked: editor.pickColor("valueColor", valueSwatch)
            }
        }
        Hint { Layout.leftMargin: editor.labelW; text: "锚点位置基于控件框，X/Y 相对锚点偏移（设计像素）。" }
    }
    component Choice: ThemeComboBox {
        id: choice
        property string role
        property string fallback
        Component.onCompleted: select(editor.value(role, fallback))
        Connections { target: editor; function onRowChanged() { choice.select(editor.value(choice.role, choice.fallback)) } }
        onActivated: editor.roleChanged(role, currentValue)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Name: every kind, always on top. Renaming lives only here.
        FieldRow {
            label: "名称"
            EditField {
                objectName: "nameField"
                Layout.preferredWidth: 36 * Theme.unit
                value: editor.value("name", "")
                onCommitted: t => editor.renameRequested(t)
            }
            Item { Layout.fillWidth: true }
            // Loaded, and which trigger drives it.
            Label {
                visible: editor.tabbed
                readonly property bool byGroup: editor.parentState !== null && editor.parentState.hidden === true
                readonly property bool hidden: editor.triggerState.hidden === true || byGroup
                                               || (editor.kind === "text" && editor.textState.hidden)
                text: editor.triggers.show === "never" ? "○ 始终隐藏"
                    : byGroup ? (editor.parentShow === "never" ? "○ 始终隐藏（继承自组）" : "○ 当前隐藏（组触发器未满足）")
                    : hidden ? (editor.kind === "group" ? "○ 当前整组隐藏"
                                : editor.kind === "text" && editor.triggerState.hidden !== true ? "○ 当前隐藏（无数据）"
                                : "○ 当前隐藏（触发器未满足）")
                    : editor.kind === "group"
                      ? (editor.triggerState.driving >= 0 ? "● 组触发器 " + (editor.triggerState.driving + 1) + "：" + Triggers.effectLabel(editor.triggerState.effect)
                                                         : "● 组内控件按各自触发器显示")
                    : editor.kind === "text" ? "● 当前显示：" + editor.textState.text
                    : editor.kind === "buffs" ? "● 当前显示 " + editor.buffNow.length + " 项"
                    : editor.kind === "bar"
                      ? (editor.triggerState.driving >= 0
                         ? "● 触发器 " + (editor.triggerState.driving + 1) + "：进度 " + Math.round(editor.triggerState.progress * 100) + "%"
                         : editor.triggers.list.length === 0 ? "● 无触发器（显示为满）" : "● 无满足的触发器（显示为空）")
                    : editor.triggerState.driving >= 0 ? "● 触发器 " + (editor.triggerState.driving + 1) + "：" + Triggers.effectLabel(editor.triggerState.effect)
                    : "● 当前显示（无触发效果）"
                color: hidden ? Theme.textFaint : Theme.accent
                font.pixelSize: Theme.caption
            }
        }

        // Tabs (icons and bars).
        Item {
            visible: editor.tabbed
            Layout.fillWidth: true
            Layout.topMargin: Theme.gap
            Layout.preferredHeight: Theme.rowH + 1
            Row {
                height: Theme.rowH
                Repeater {
                    model: editor.tabNames
                    AbstractButton {
                        required property int index
                        required property string modelData
                        height: Theme.rowH
                        width: tabLabel.implicitWidth + 2 * Theme.gap
                        hoverEnabled: true
                        onClicked: editor.tab = index
                        contentItem: Label {
                            id: tabLabel
                            text: parent.modelData
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: editor.tab === parent.index ? Theme.accent : parent.hovered ? Theme.text : Theme.textDim
                        }
                        background: Item {
                            Rectangle {
                                visible: editor.tab === parent.parent.index
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: Theme.accent
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        ScrollView {
            id: scroll
            objectName: "editorScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Theme.gap
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Item {
                width: scroll.availableWidth - Theme.gap  // room for the scroll bar
                implicitHeight: Math.max(triggerTab.implicitHeight, looksTab.implicitHeight,
                                         barLooksTab.implicitHeight, textContentTab.implicitHeight,
                                         textLooksTab.implicitHeight, groupTab.implicitHeight,
                                         buffContentTab.implicitHeight, buffLooksTab.implicitHeight)

                // ---- 触发器
                ColumnLayout {
                    id: triggerTab
                    visible: editor.tabbed && editor.tabName === "触发器"
                    width: parent.width
                    spacing: Theme.unit

                    ExpandRows { visible: editor.expanded && editor.kind !== "buffs" }

                    // When the control shows at all.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.preferredWidth: editor.labelW
                            Layout.preferredHeight: Theme.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: "显示模式"
                            color: Theme.textDim
                        }
                        ThemeComboBox {
                            id: triggerShowBox
                            Layout.preferredWidth: 36 * Theme.unit
                            model: [
                                { label: "始终显示（仅叠加效果）", value: "always" },
                                { label: "仅当触发器满足时显示", value: "active" },
                                { label: "始终隐藏", value: "never" }
                            ]
                            Component.onCompleted: select(editor.triggers.show)
                            Connections { target: editor; function onTriggersChanged() { triggerShowBox.select(editor.triggers.show) } }
                            onActivated: editor.saveTriggers(editor.triggers.list, currentValue)
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: editor.triggers.show === "never"
                              ? (editor.kind === "group" ? "隐藏整组（包含游戏内与预览模式），保留配置项。"
                                                         : "隐藏控件（包含游戏内与预览模式），保留配置项。选中时在预览区半透明显示。")
                              : editor.kind === "group"
                              ? (editor.triggers.show === "always" ? "组内控件正常显示，满足条件的组触发器将应用效果至全组。"
                                                                   : "无组触发器满足时隐藏整组。例如：战斗状态 = 战斗中 → 仅在战斗中显示该组。")
                              : editor.triggers.show === "always"
                              ? "控件始终按基础外观显示，满足条件的触发器叠加播放效果。"
                              : "无触发器满足时隐藏控件。例如：连携技就绪 + 中心扩散动画 + 播放一次 = 冷却完毕时扩散提示并自动消失。"
                    }
                    // How it comes and goes when the triggers show / hide it.
                    component MotionBox: ThemeComboBox {
                        id: mb
                        property string field
                        Layout.preferredWidth: 24 * Theme.unit
                        model: field === "from" ? Triggers.slideFroms : Triggers.motions
                        Component.onCompleted: select(editor.triggers.motion[field])
                        Connections { target: editor; function onTriggersChanged() { mb.select(editor.triggers.motion[mb.field]) } }
                        onActivated: editor.setMotion(field, currentValue)
                    }
                    FieldRow {
                        visible: editor.triggers.show !== "never"
                        label: "出现动画"
                        MotionBox { field: "appear" }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "消失动画"
                            color: Theme.textDim
                        }
                        MotionBox { field: "disappear" }
                    }
                    FieldRow {
                        visible: editor.triggers.show !== "never" && Triggers.hasMotion(editor.triggers.motion)
                        label: "动画时长"
                        NumberField {
                            from: 0; to: 5000; unit: "ms"
                            value: editor.triggers.motion.ms
                            onCommitted: v => editor.setMotion("ms", v)
                        }
                        Label {
                            visible: editor.triggers.motion.appear === "slide" || editor.triggers.motion.disappear === "slide"
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "滑动方向"
                            color: Theme.textDim
                        }
                        MotionBox {
                            visible: editor.triggers.motion.appear === "slide" || editor.triggers.motion.disappear === "slide"
                            field: "from"
                        }
                    }
                    Hint {
                        visible: editor.triggers.show !== "never"
                        Layout.leftMargin: editor.labelW
                        text: (editor.kind === "group" ? "设置组显示/隐藏时的过渡动画。若子控件独立设置，则优先使用子控件设置。"
                               : "设置控件显示/隐藏时的过渡动画（适用于「仅当触发器满足时显示」、播放完毕消失、动态文本无数据等场景）。")
                              + (editor.kind !== "group" && editor.value("parentId", "") !== "" && !Triggers.hasMotion(editor.triggers.motion)
                                 ? "继承所在组的动画设置。" : "")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.unit
                        spacing: Theme.unit
                        Label {
                            text: editor.triggers.list.length === 0
                                  ? (editor.kind === "bar" ? "无触发器（默认满进度）"
                                   : editor.kind === "group" ? "无触发器（子控件按各自触发器显示）"
                                   : "无触发器（按基础外观静态显示）")
                                  : "触发器列表"
                            color: Theme.textDim
                        }
                        Item { Layout.fillWidth: true }
                        FlatButton {
                            text: "＋ 添加触发器"
                            accent: true
                            onClicked: typeMenu.popup()
                        }
                    }

                    Repeater {
                        model: editor.triggers.list.length
                        TriggerCard {
                            required property int index
                            Layout.fillWidth: true
                            number: index + 1
                            count: editor.triggers.list.length
                            trigger: editor.triggers.list[index]
                            result: editor.triggerState.results[index] || ({})
                            driving: editor.triggerState.driving === index
                            labelW: editor.labelW
                            forBar: editor.kind === "bar"
                            forText: editor.kind === "text" || editor.kind === "buffs"
                            kind: editor.kind
                            onChanged: t => editor.replaceTrigger(index, t)
                            onRemoveRequested: editor.removeTrigger(index)
                            onMoveRequested: by => editor.moveTrigger(index, by)
                            onDuplicateRequested: editor.duplicateTrigger(index)
                            onColorRequested: (field, anchor, current) => editor.pickTriggerColor(index, field, anchor, current)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: editor.triggers.list.length > 0 && editor.kind === "bar"
                        text: "按顺序检查：首个满足且勾选「给出进度」的触发器驱动进度条（高亮标记）。无满足时显示为空。样式效果（变色、发光等）将叠加所有满足条件的触发器。"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: editor.triggers.list.length > 0 && editor.kind === "icon"
                        text: "按顺序检查：首个满足且设有效果的触发器驱动图标（高亮标记）。例如：连携技 + 顺时针冷却转圈；终结技就绪 + 中心扩散动画。"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: editor.kind === "group"
                        text: "组触发器作用于全组控件且不覆盖各控件独立设置：选「仅当触发器满足时显示」时，无满足则整组隐藏；满足触发效果时，组内无独立动画的图标将播放组效果。"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: BridgeReader.status !== "online" && BridgeReader.status !== "stale"
                        text: "Bridge " + BridgeReader.statusText + "：数据不可用，判定为不满足。"
                    }

                    Menu {
                        id: typeMenu
                        topPadding: 1
                        bottomPadding: 1
                        background: Rectangle { implicitWidth: 40 * Theme.unit; color: Theme.surface; border.color: Theme.lineStrong }
                        Repeater {
                            model: Triggers.types
                            MenuItem {
                                id: typeItem
                                required property var modelData
                                implicitHeight: Theme.rowH + Theme.unit
                                onTriggered: editor.addTrigger(modelData.value)
                                background: Rectangle { color: typeItem.highlighted ? Theme.raised : "transparent" }
                                contentItem: Column {
                                    leftPadding: Theme.unit - typeItem.leftPadding
                                    topPadding: 2
                                    Label { text: typeItem.modelData.label }
                                    Label { text: typeItem.modelData.desc; color: Theme.textFaint; font.pixelSize: Theme.caption }
                                }
                            }
                        }
                    }
                }

                // ---- 外观
                ColumnLayout {
                    id: looksTab
                    visible: editor.kind === "icon" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit

                    Section { text: "形状"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "图形"
                        Choice {
                            role: "shape"; fallback: "square"
                            model: [
                                { label: "正方形", value: "square" }, { label: "圆形", value: "circle" },
                                { label: "正三角形", value: "triangle" }, { label: "正六边形", value: "hexagon" }
                            ]
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "旋转角度"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: 359; unit: "°"
                            value: editor.value("shapeAngle", 0)
                            onCommitted: v => editor.roleChanged("shapeAngle", v)
                        }
                    }
                    FieldRow {
                        label: "图标尺寸"
                        NumberField {
                            from: 1; to: 100; decimals: 1; unit: "%"
                            value: editor.value("iconSize", 84)
                            onCommitted: v => editor.roleChanged("iconSize", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "控件框短边比例（1–100%）。"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }

                    Section { text: "边框" }
                    ColorRow { label: "颜色"; colorRole: "borderColor"; opacityRole: "borderOpacity" }
                    FieldRow {
                        label: "线宽"
                        NumberField {
                            from: 0; to: 16; decimals: 1; unit: "px"
                            value: editor.value("borderWidth", 3)
                            onCommitted: v => editor.roleChanged("borderWidth", v)
                        }
                    }

                    Section { text: "填充" }
                    ColorRow { label: "颜色"; colorRole: "fillColor"; opacityRole: "fillOpacity"; opacityFallback: 22 }

                    Section { text: "位置与尺寸" }
                    FieldRow {
                        label: "位置"
                        NumberField {
                            from: 0; to: 1280; unit: "X"
                            value: editor.value("posX", 0)
                            onCommitted: v => editor.roleChanged("posX", Math.min(v, 1280 - editor.value("boxWidth", 128)))
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 720; unit: "Y"
                            value: editor.value("posY", 0)
                            onCommitted: v => editor.roleChanged("posY", Math.min(v, 720 - editor.value("boxHeight", 128)))
                        }
                    }
                    FieldRow {
                        label: "控件框"
                        NumberField {
                            from: 16; to: 720; unit: "宽"
                            value: editor.value("boxWidth", 128)
                            onCommitted: v => editor.roleChanged("boxWidth", v)
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 16; to: 720; unit: "高"
                            value: editor.value("boxHeight", 128)
                            onCommitted: v => editor.roleChanged("boxHeight", v)
                        }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "基于 1280×720 基准分辨率，游戏内自动按比例缩放。" }

                    Section { text: "文本" }
                    FieldRow {
                        label: "文本显示"
                        CheckRow { text: "剩余时间"; role: "showTimer"; fallback: true }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "层数"; role: "showStacks"; fallback: true }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "数值取自当前驱动图标的触发器；层数大于 1 时显示。" }
                    ValueStyle { visible: editor.value("showTimer", true) }
                }

                // ---- 外观 (bar)
                ColumnLayout {
                    id: barLooksTab
                    visible: editor.kind === "bar" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property bool ring: editor.value("barStyle", "rect") === "ring"

                    Section { text: "样式类型"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "形状"
                        Choice {
                            role: "barStyle"; fallback: "rect"
                            model: [{ label: "矩形条", value: "rect" }, { label: "圆环", value: "ring" }]
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "旋转角度"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: 359; unit: "°"
                            objectName: "barRotation"
                            value: editor.value("barRotation", 0)
                            onCommitted: v => editor.roleChanged("barRotation", v)
                        }
                    }
                    FieldRow {
                        visible: barLooksTab.ring
                        label: "外圆半径"
                        NumberField {
                            from: 4; to: 360; unit: "px"
                            value: editor.value("ringOuter", 56)
                            onCommitted: v => editor.roleChanged("ringOuter", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "内圆半径"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: Math.max(0, editor.value("ringOuter", 56) - 1); unit: "px"
                            value: editor.value("ringInner", 44)
                            onCommitted: v => editor.roleChanged("ringInner", v)
                        }
                    }
                    Hint { visible: barLooksTab.ring; Layout.leftMargin: editor.labelW; text: "内圆半径设为 0 时为实心饼图。" }
                    FieldRow {
                        visible: barLooksTab.ring
                        label: "缺口角度"
                        NumberField {
                            from: 0; to: 359; unit: "°"
                            value: editor.value("ringGap", 0)
                            onCommitted: v => editor.roleChanged("ringGap", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "裁剪角度，旋转 0° 时缺口位于底部：0° 为完整圆环，90° 为 3/4 弧线。"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }
                    FieldRow {
                        visible: !barLooksTab.ring
                        label: "长度"
                        NumberField {
                            from: 4; to: 1280; unit: "px"
                            objectName: "barLength"
                            value: editor.value("barLength", 240)
                            onCommitted: v => editor.roleChanged("barLength", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "宽度"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 2; to: 720; unit: "px"
                            objectName: "barThickness"
                            value: editor.value("barThickness", 24)
                            onCommitted: v => editor.roleChanged("barThickness", v)
                        }
                    }

                    Section { text: "进度样式" }
                    FieldRow {
                        label: "方向"
                        Choice {
                            id: dirBox
                            role: "barDirection"; fallback: "leftToRight"
                            // A ring only goes two ways; the rect has all four.
                            model: barLooksTab.ring
                                ? [{ label: "顺时针", value: "leftToRight" }, { label: "逆时针", value: "rightToLeft" }]
                                : [{ label: "左至右", value: "leftToRight" }, { label: "右至左", value: "rightToLeft" },
                                   { label: "下至上", value: "bottomToTop" }, { label: "上至下", value: "topToBottom" }]
                            onModelChanged: select(editor.value("barDirection", "leftToRight"))
                        }
                    }
                    ColorRow { label: "颜色"; colorRole: "progressColor"; opacityRole: "progressOpacity" }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "进度层独立绘制于背景填充上方，包含独立的颜色与不透明度。"
                    }
                    FieldRow {
                        label: "平滑过渡"
                        NumberField {
                            from: 0; to: 2000; unit: "ms"
                            value: editor.value("barSmooth", 150)
                            onCommitted: v => editor.roleChanged("barSmooth", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "数值平滑变更的时长；0 表示立即变更。"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }
                    FieldRow {
                        label: "消耗残影"
                        CheckRow { text: "启用"; role: "barTrail"; fallback: false }
                        ColorField {
                            id: trailSwatch
                            visible: editor.value("barTrail", false)
                            Layout.leftMargin: Theme.gap
                            color: editor.value("trailColor", "#ffffff")
                            onClicked: editor.pickColor("trailColor", trailSwatch)
                        }
                        NumberField {
                            visible: editor.value("barTrail", false)
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 100; unit: "%"
                            value: editor.value("trailOpacity", 70)
                            onCommitted: v => editor.roleChanged("trailOpacity", v)
                        }
                    }
                    FieldRow {
                        visible: editor.value("barTrail", false)
                        label: ""
                        NumberField {
                            from: 0; to: 5000; unit: "停留 ms"
                            implicitWidth: 16 * Theme.unit
                            value: editor.value("trailHold", 400)
                            onCommitted: v => editor.roleChanged("trailHold", v)
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 5000; unit: "缩回 ms"
                            implicitWidth: 16 * Theme.unit
                            value: editor.value("trailShrink", 300)
                            onCommitted: v => editor.roleChanged("trailShrink", v)
                        }
                    }
                    Hint {
                        visible: editor.value("barTrail", false)
                        Layout.leftMargin: editor.labelW
                        text: "进度下降时留存残影段，停留设定时间后缩回；连续下降时重置停留计时。进度上升时实时更新。"
                    }
                    FieldRow {
                        label: "进度分段"
                        ThemeComboBox {
                            id: segBox
                            model: [{ label: "不分段", value: "none" }, { label: "按战技格数", value: "cells" }, { label: "固定段数", value: "fixed" }]
                            readonly property real v: editor.value("barSegments", 0)
                            Component.onCompleted: select(v < 0 ? "cells" : v > 1 ? "fixed" : "none")
                            onVChanged: select(v < 0 ? "cells" : v > 1 ? "fixed" : "none")
                            onActivated: editor.roleChanged("barSegments", currentValue === "cells" ? -1 : currentValue === "fixed" ? 4 : 0)
                        }
                        NumberField {
                            visible: editor.value("barSegments", 0) > 1
                            Layout.leftMargin: Theme.unit
                            from: 2; to: 100; unit: "段"
                            value: editor.value("barSegments", 0)
                            onCommitted: v => editor.roleChanged("barSegments", v)
                        }
                        Label {
                            visible: editor.value("barSegments", 0) !== 0
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 6 * Theme.unit
                            text: "间隔"
                            color: Theme.textDim
                        }
                        NumberField {
                            visible: editor.value("barSegments", 0) !== 0
                            from: 1; to: 32; unit: "px"
                            value: editor.value("segmentGap", 2)
                            onCommitted: v => editor.roleChanged("segmentGap", v)
                        }
                    }
                    Hint {
                        visible: editor.value("barSegments", 0) < 0
                        Layout.leftMargin: editor.labelW
                        text: "分段数 = 技力上限 / 单格技力，跟随游戏数据动态更新（当前 " + (BridgeReader.team.atbPerCell > 0
                              ? Math.round(BridgeReader.team.atbMax / BridgeReader.team.atbPerCell) + " 格）。" : "未知）。")
                    }
                    FieldRow {
                        visible: barLooksTab.ring
                        label: "端点样式"
                        Choice {
                            role: "ringCap"; fallback: "butt"
                            model: [{ label: "平头", value: "butt" }, { label: "圆头", value: "round" }]
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "进度条与背景两端的边缘形状（平头/圆头）。"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }

                    Section { text: "边框" }
                    ColorRow { label: "颜色"; colorRole: "borderColor"; opacityRole: "borderOpacity" }
                    FieldRow {
                        label: "线宽"
                        NumberField {
                            from: 0; to: 16; decimals: 1; unit: "px"
                            value: editor.value("borderWidth", 3)
                            onCommitted: v => editor.roleChanged("borderWidth", v)
                        }
                    }

                    Section { text: "背景填充" }
                    ColorRow { label: "颜色"; colorRole: "fillColor"; opacityRole: "fillOpacity" }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "未填充区域外观。不透明度设为 0% 时仅保留边框。"
                    }

                    Section { text: "文本" }
                    FieldRow {
                        label: "文本显示"
                        CheckRow { text: "数值"; role: "showTimer"; fallback: true }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "层数"; role: "showStacks"; fallback: true }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "数值取自当前驱动进度的触发器；层数大于 1 时显示。" }
                    ValueStyle { visible: editor.value("showTimer", true) }

                    Section { text: "位置与尺寸" }
                    FieldRow {
                        label: "位置"
                        NumberField {
                            from: 0; to: 1280; unit: "X"
                            value: editor.value("posX", 0)
                            onCommitted: v => editor.roleChanged("posX", Math.min(v, 1280 - editor.value("boxWidth", 128)))
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 720; unit: "Y"
                            value: editor.value("posY", 0)
                            onCommitted: v => editor.roleChanged("posY", Math.min(v, 720 - editor.value("boxHeight", 128)))
                        }
                    }
                    FieldRow {
                        label: "控件框"
                        Label {
                            text: editor.value("boxWidth", 0) + " × " + editor.value("boxHeight", 0)
                            color: Theme.text
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "控件包围盒随形状、旋转与边框自动计算；位置基于外接矩形左上角。"
                    }
                }

                // ---- 内容 (text)
                ColumnLayout {
                    id: textContentTab
                    visible: editor.kind === "text" && editor.tabName === "内容"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property string mode: editor.value("textMode", "static")

                    Section { text: "模式选择"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "模式"
                        ThemeComboBox {
                            id: textModeBox
                            model: [
                                { label: "静态文本", value: "static" }, { label: "动态文本", value: "dynamic" },
                                { label: "静态 + 动态", value: "both" }, { label: "模板 (占位符)", value: "template" }
                            ]
                            Component.onCompleted: select(textContentTab.mode)
                            Connections { target: editor; function onRowChanged() { textModeBox.select(textContentTab.mode) } }
                            // Into a template: a text with no placeholder gets {1}, so
                            // the value it showed is still there.
                            onActivated: {
                                const t = editor.value("staticText", "")
                                if (currentValue === "template" && !/\{[^{}]+\}/.test(t))
                                    editor.roleChanged("staticText", textContentTab.mode === "dynamic" ? "{1}" : t + "{1}")
                                editor.roleChanged("textMode", currentValue)
                            }
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: textContentTab.mode === "static" ? "固定显示指定文本"
                            : textContentTab.mode === "dynamic" ? "跟随游戏数据实时更新的单项数值"
                            : textContentTab.mode === "both" ? "固定前缀组合单项数值（如：「Buff名称: 」+ 剩余时间）"
                            : "使用 {…} 占位符组合多项数据（如：「{技力}/{上限}」、「{层数}层」）"
                    }
                    FieldRow {
                        visible: textContentTab.mode !== "dynamic"
                        label: textContentTab.mode === "template" ? "模板" : "静态文本"
                        EditField {
                            Layout.fillWidth: true
                            placeholderText: textContentTab.mode === "both" ? "如：攻击力提升: "
                                           : textContentTab.mode === "template" ? "如：{技力} / {上限}" : "显示文本内容"
                            value: editor.value("staticText", "")
                            onCommitted: t => editor.roleChanged("staticText", t)
                        }
                    }
                    Hint {
                        visible: textContentTab.mode === "template"
                        Layout.leftMargin: editor.labelW
                        textFormat: Text.PlainText
                        text: "占位符：{数值}（或 {技力} {HP} {终结技} {失衡}）、{上限}、{百分比}、{层数}、{剩余}、{自动}。"
                              + "支持多数据源后缀（如 {数值2}）及格式化（如 {剩余:mm:ss}、{数值:0.0}）。"
                              + "\n当前预览：" + (editor.textState.hidden ? "（无数据时隐藏）" : editor.textState.text)
                    }
                    Section {
                        visible: textContentTab.mode !== "static"
                        text: textContentTab.mode === "template" ? "动态数据源 1" : "动态数据源"
                    }
                    ConditionFields {
                        visible: textContentTab.mode !== "static"
                        Layout.fillWidth: true
                        labelW: editor.labelW
                        types: Triggers.textTypes
                        valueOnly: true
                        spec: editor.textSource.condition
                        onChanged: c => editor.setTextSource("condition", c)
                    }
                    FieldRow {
                        visible: textContentTab.mode !== "static"
                        label: textContentTab.mode === "template" ? "小数位数" : "显示格式"
                        ThemeComboBox {
                            id: showBox
                            visible: textContentTab.mode !== "template"
                            model: Triggers.textShows
                            Component.onCompleted: select(editor.textSource.show)
                            Connections { target: editor; function onTextSourceChanged() { showBox.select(editor.textSource.show) } }
                            onActivated: editor.setTextSource("show", currentValue)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            visible: textContentTab.mode !== "template" && editor.textSource.show !== "auto" && editor.textSource.show !== "stacks"
                            text: "小数位数"
                            color: Theme.textDim
                        }
                        NumberField {
                            visible: textContentTab.mode === "template" || (editor.textSource.show !== "auto" && editor.textSource.show !== "stacks")
                            from: 0; to: 3
                            value: editor.textSource.decimals
                            onCommitted: v => editor.setTextSource("decimals", v)
                        }
                    }
                    // A template's sources 2, 3...
                    Repeater {
                        model: textContentTab.mode === "template" ? editor.textSource.more.length : 0
                        ColumnLayout {
                            id: moreBlock
                            required property int index
                            Layout.fillWidth: true
                            spacing: Theme.unit
                            RowLayout {
                                Layout.fillWidth: true
                                Section { text: "动态数据源 " + (moreBlock.index + 2) }
                                Item { Layout.fillWidth: true }
                                FlatButton {
                                    text: "移除"
                                    danger: true
                                    onClicked: {
                                        const list = editor.textSource.more.slice()
                                        list.splice(moreBlock.index, 1)
                                        editor.setTextSource("more", list)
                                    }
                                }
                            }
                            ConditionFields {
                                Layout.fillWidth: true
                                labelW: editor.labelW
                                types: Triggers.textTypes
                                valueOnly: true
                                spec: editor.textSource.more[moreBlock.index]
                                onChanged: c => {
                                    const list = editor.textSource.more.slice()
                                    list[moreBlock.index] = c
                                    editor.setTextSource("more", list)
                                }
                            }
                        }
                    }
                    FlatButton {
                        visible: textContentTab.mode === "template"
                        Layout.leftMargin: editor.labelW
                        text: "＋ 添加数据源"
                        onClicked: editor.setTextSource("more", editor.textSource.more.concat([Triggers.makeCondition("hp")]))
                    }
                    Hint {
                        visible: textContentTab.mode !== "static" && textContentTab.mode !== "template"
                        Layout.leftMargin: editor.labelW
                        text: "自动/数值：Buff/技能显示剩余秒数，其他显示当前值。「数值与上限」显示具体比例；「百分比」显示如 94%。"
                    }
                    FieldRow {
                        visible: textContentTab.mode !== "static"
                        label: "无数据处理"
                        CheckRow {
                            text: textContentTab.mode === "template" ? "任一占位符缺少数据时隐藏整个文本" : "无数据时隐藏整个文本"
                            on: editor.textSource.hideEmpty
                            onClicked: editor.setTextSource("hideEmpty", !editor.textSource.hideEmpty)
                        }
                        Label {
                            visible: !editor.textSource.hideEmpty
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "回退文本"
                            color: Theme.textDim
                        }
                        EditField {
                            visible: !editor.textSource.hideEmpty
                            Layout.preferredWidth: 16 * Theme.unit
                            placeholderText: "留空"
                            value: editor.textSource.empty
                            ToolTip.visible: hovered
                            ToolTip.text: "占位符无数据时替换显示的占位文本（留空表示不显示）。"
                            onCommitted: t => editor.setTextSource("empty", t)
                        }
                    }
                    Hint {
                        visible: textContentTab.mode !== "static"
                        Layout.leftMargin: editor.labelW
                        text: "未连接 Bridge、Buff 不存在或无锁定目标时触发无数据状态。预览「显示全部控件」时统一显示为 --。"
                    }
                }
                // ---- 内容 (buff list)
                ColumnLayout {
                    id: buffContentTab
                    visible: editor.kind === "buffs" && editor.tabName === "内容"
                    width: parent.width
                    spacing: Theme.unit

                    Section { text: "监控目标"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "目标"
                        Choice {
                            role: "buffUnit"; fallback: "main"
                            model: Triggers.squadUnits.concat([{ label: "锁定目标", value: "target" }])
                        }
                    }
                    ExpandRows { visible: editor.expanded }
                    FieldRow {
                        label: "类型"
                        Choice {
                            role: "buffKind"; fallback: "all"
                            model: [{ label: "全部", value: "all" }, { label: "仅 Buff (增益)", value: "buff" },
                                    { label: "仅 Debuff (减益)", value: "debuff" }]
                        }
                    }
                    FieldRow {
                        label: "来源"
                        Choice {
                            role: "buffSource"; fallback: "any"
                            model: [{ label: "任意来源", value: "any" }, { label: "我方单位", value: "squad" },
                                    { label: "敌方单位", value: "enemy" }, { label: "仅限自身", value: "self" }]
                        }
                    }
                    FieldRow {
                        label: "最大显示数量"
                        NumberField {
                            from: 1; to: 32; unit: "个"
                            value: editor.value("buffMax", 8)
                            onCommitted: v => editor.roleChanged("buffMax", v)
                        }
                    }
                    Section { text: "条件过滤" }
                    FieldRow {
                        label: "白名单 (仅显示)"
                        EditField {
                            id: buffOnlyField
                            Layout.fillWidth: true
                            placeholderText: "留空表示不过滤；多个 Buff ID 使用逗号分隔。"
                            value: editor.value("buffOnly", "")
                            onCommitted: t => editor.roleChanged("buffOnly", t.trim())
                        }
                    }
                    FieldRow {
                        label: "黑名单 (忽略)"
                        EditField {
                            Layout.fillWidth: true
                            placeholderText: "留空表示不过滤；多个 Buff ID 使用逗号分隔。"
                            value: editor.value("buffExclude", "")
                            onCommitted: t => editor.roleChanged("buffExclude", t.trim())
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "按获取时间排序：新 Buff 顺延排列，失效 Buff 移除后自动补位。"
                              + (editor.buffNow.length > 0 ? "当前：" + editor.buffNow.map(b => b.buffId).join("、")
                                 : BridgeReader.status === "online" || BridgeReader.status === "stale" ? "当前无匹配 Buff"
                                 : "Bridge 未连接")
                    }
                }

                // ---- 外观 (buff list)
                ColumnLayout {
                    id: buffLooksTab
                    visible: editor.kind === "buffs" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit

                    Section { text: "布局排列"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "方向"
                        Choice {
                            role: "buffGrow"; fallback: "right"
                            model: [{ label: "向右", value: "right" }, { label: "向左", value: "left" },
                                    { label: "向下", value: "down" }, { label: "向上", value: "up" }]
                        }
                    }
                    FieldRow {
                        label: "单元格尺寸"
                        NumberField {
                            from: 12; to: 200; unit: "px"
                            value: editor.value("buffCell", 40)
                            onCommitted: v => editor.roleChanged("buffCell", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "间距"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: 64; unit: "px"
                            value: editor.value("buffSpacing", 4)
                            onCommitted: v => editor.roleChanged("buffSpacing", v)
                        }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "自动根据「最大显示数量」计算控件框尺寸。" }

                    Section { text: "颜色样式" }
                    ColorRow { label: "Buff 颜色"; colorRole: "borderColor"; opacityRole: "borderOpacity" }
                    FieldRow {
                        label: "Debuff 颜色"
                        ColorField {
                            id: debuffSwatch
                            color: editor.value("debuffColor", "#e5484d")
                            onClicked: editor.pickColor("debuffColor", debuffSwatch)
                        }
                    }
                    FieldRow {
                        label: "背景填充"
                        SliderField { role: "fillOpacity"; fallback: 22 }
                    }
                    FieldRow {
                        label: "边框宽度"
                        NumberField {
                            from: 0; to: 16; decimals: 1; unit: "px"
                            value: editor.value("borderWidth", 3)
                            onCommitted: v => editor.roleChanged("borderWidth", v)
                        }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "单元格边框与填充色按 Buff/Debuff 类型区分；已消耗时间以遮罩形式覆盖。" }

                    Section { text: "文本显示" }
                    FieldRow {
                        label: "显示"
                        CheckRow { text: "剩余时间"; role: "showTimer"; fallback: true }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "层数"; role: "showStacks"; fallback: true }
                    }
                    FieldRow {
                        label: "Buff 名称"
                        Choice {
                            role: "buffLabel"; fallback: "none"
                            model: [{ label: "简写 ID", value: "short" }, { label: "完整 ID", value: "full" },
                                    { label: "不显示", value: "none" }]
                        }
                    }
                    FieldRow {
                        label: "倒计时字号"
                        NumberField {
                            from: 6; to: 200; unit: "px"
                            value: editor.value("valueSize", 20)
                            onCommitted: v => editor.roleChanged("valueSize", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "颜色"
                            color: Theme.textDim
                        }
                        ColorField {
                            id: buffValueSwatch
                            color: editor.value("valueColor", "#e6e8eb")
                            onClicked: editor.pickColor("valueColor", buffValueSwatch)
                        }
                    }

                    Section { text: "位置" }
                    FieldRow {
                        label: "位置"
                        NumberField {
                            from: 0; to: 1280; unit: "X"
                            value: editor.value("posX", 0)
                            onCommitted: v => editor.roleChanged("posX", Math.min(v, 1280 - editor.value("boxWidth", 64)))
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 720; unit: "Y"
                            value: editor.value("posY", 0)
                            onCommitted: v => editor.roleChanged("posY", Math.min(v, 720 - editor.value("boxHeight", 64)))
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            text: editor.value("boxWidth", 0) + " × " + editor.value("boxHeight", 0)
                            color: Theme.textDim
                        }
                    }
                }

                // ---- 外观 (text)
                ColumnLayout {
                    id: textLooksTab
                    visible: editor.kind === "text" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit

                    Section { text: "文本样式"; Layout.topMargin: 0 }
                    ColorRow { label: "颜色"; colorRole: "textColor"; opacityRole: "textOpacity" }
                    FieldRow {
                        label: "字号"
                        NumberField {
                            from: 6; to: 200; unit: "px"
                            value: editor.value("fontSize", 24)
                            onCommitted: v => editor.roleChanged("fontSize", v)
                        }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "加粗"; role: "fontBold"; fallback: true }
                    }
                    FieldRow {
                        label: "对齐方式"
                        Choice {
                            role: "textAlign"; fallback: "center"
                            model: [{ label: "靠左", value: "left" }, { label: "居中", value: "center" }, { label: "靠右", value: "right" }]
                        }
                    }
                    FieldRow {
                        label: "描边"
                        CheckRow { text: "显示"; role: "textOutline"; fallback: true }
                        ColorField {
                            id: outlineSwatch
                            visible: editor.value("textOutline", true)
                            Layout.leftMargin: Theme.gap
                            color: editor.value("outlineColor", "#141518")
                            onClicked: editor.pickColor("outlineColor", outlineSwatch)
                        }
                    }

                    Section { text: "位置与尺寸" }
                    FieldRow {
                        label: "位置"
                        NumberField {
                            from: 0; to: 1280; unit: "X"
                            value: editor.value("posX", 0)
                            onCommitted: v => editor.roleChanged("posX", Math.min(v, 1280 - editor.value("boxWidth", 160)))
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 720; unit: "Y"
                            value: editor.value("posY", 0)
                            onCommitted: v => editor.roleChanged("posY", Math.min(v, 720 - editor.value("boxHeight", 56)))
                        }
                    }
                    FieldRow {
                        label: "控件框"
                        NumberField {
                            from: 8; to: 1280; unit: "宽"
                            value: editor.value("boxWidth", 160)
                            onCommitted: v => editor.roleChanged("boxWidth", v)
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 8; to: 720; unit: "高"
                            value: editor.value("boxHeight", 56)
                            onCommitted: v => editor.roleChanged("boxHeight", v)
                        }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "文本在控件框内垂直居中，水平按「对齐方式」对齐；超出控件框部分正常绘制。" }
                }

                // ---- group
                ColumnLayout {
                    id: groupTab
                    visible: editor.kind === "group" && editor.tabName === "整体"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property var g: editor.groupInfo
                    readonly property bool empty: !g || g.n === 0

                    Hint {
                        visible: groupTab.empty
                        text: "当前组为空：请在左侧列表中将控件拖入本组。"
                    }
                    Section { text: "全局变换"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "不透明度"
                        SliderField { role: "groupOpacity"; fallback: 100 }
                    }
                    FieldRow {
                        label: "全局缩放"
                        SliderField { role: "groupScale"; from: 10; to: 300; fallback: 100 }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "全局缩放与透明度调整，与子控件独立参数叠加。缩放原点为组左上角。"
                    }
                    Section { text: "组位置" }
                    FieldRow {
                        label: "位置"
                        enabled: !groupTab.empty
                        NumberField {
                            from: 0; to: 1280; unit: "X"
                            value: groupTab.g ? Math.round(groupTab.g.bx) : 0
                            onCommitted: v => editor.groupMoveRequested(v, groupTab.g.by)
                        }
                        NumberField {
                            Layout.leftMargin: Theme.unit
                            from: 0; to: 720; unit: "Y"
                            value: groupTab.g ? Math.round(groupTab.g.by) : 0
                            onCommitted: v => editor.groupMoveRequested(groupTab.g.bx, v)
                        }
                    }
                    FieldRow {
                        label: "组外接边界"
                        Label {
                            text: groupTab.empty ? "—" : Math.round(groupTab.g.bw) + " × " + Math.round(groupTab.g.bh)
                                  + "（" + groupTab.g.n + " 个控件）"
                            color: Theme.text
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "包含组内所有子控件的外接矩形。移动组将同步移动所有子控件。"
                    }
                }
            }
        }
    }
}
