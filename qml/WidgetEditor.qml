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
    readonly property bool tabbed: kind === "icon" || kind === "bar" || kind === "text"
    readonly property var kindNames: ({ icon: "图标", bar: "进度条", text: "文本", group: "组" })
    readonly property int labelW: 14 * Theme.unit
    property int tab: 0

    title: value("name", "控件")
    subtitle: (kindNames[kind] || "控件") + "属性"

    // ---- triggers, kept as JSON in their role (qml/Triggers.qml)
    readonly property var triggers: Triggers.parseTriggers(value("triggers", ""))
    function saveTriggers(list, show) {
        roleChanged("triggers", JSON.stringify({ show: show !== undefined ? show : triggers.show, list: list }))
    }
    function addTrigger(type) {
        const t = kind === "bar" ? Triggers.makeBarTrigger(type) : kind === "text" ? Triggers.makeTextTrigger(type)
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
    // Live state, refreshed with every bridge read.
    property var runState: ({})
    readonly property var triggerState: {
        BridgeReader.tick
        return kind === "bar" ? Triggers.runBar(BridgeReader, value("triggers", ""))
             : kind === "text" ? Triggers.runText(BridgeReader, value("triggers", ""))
             : Triggers.run(BridgeReader, value("triggers", ""), runState, Date.now())
    }
    // Tab names per kind; `tab` indexes into them.
    readonly property var tabNames: kind === "text" ? ["内容", "触发器", "外观"] : ["触发器", "外观"]
    readonly property string tabName: tabNames[tab] || ""
    readonly property var textSource: Triggers.parseTextSource(value("textSource", ""))
    function setTextSource(field, v) {
        const next = Object.assign({}, textSource)
        next[field] = v
        roleChanged("textSource", JSON.stringify(next))
    }
    readonly property var textState: {
        BridgeReader.tick
        return Triggers.composeText(BridgeReader, value("textMode", "static"), value("staticText", ""),
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
    // The value number's place, size and color (icons and bars).
    component ValueStyle: ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.unit
        FieldRow {
            label: "位置"
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
        Hint { Layout.leftMargin: editor.labelW; text: "位置是控件框里的锚点，X / Y 再从那里偏移（设计像素）。" }
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
            ThemeTextField {
                Layout.preferredWidth: 36 * Theme.unit
                text: editor.value("name", "")
                onEditingFinished: editor.renameRequested(text)
                onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => editor.value("name", ""))
            }
            Item { Layout.fillWidth: true }
            // Loaded, and which trigger drives it.
            Label {
                visible: editor.tabbed
                readonly property bool hidden: editor.triggerState.hidden === true
                                               || (editor.kind === "text" && editor.textState.hidden)
                text: hidden ? "○ 当前不显示"
                    : editor.kind === "text" ? "● 显示：" + editor.textState.text
                    : editor.kind === "bar"
                      ? (editor.triggerState.driving >= 0
                         ? "● 触发器 " + (editor.triggerState.driving + 1) + "：进度 " + Math.round(editor.triggerState.progress * 100) + "%"
                         : editor.triggers.list.length === 0 ? "● 没有触发器（显示为满）" : "● 没有满足的触发器（显示为空）")
                    : editor.triggerState.driving >= 0 ? "● 触发器 " + (editor.triggerState.driving + 1) + "：" + Triggers.effectLabel(editor.triggerState.effect)
                    : "● 显示，无触发效果"
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
                                         textLooksTab.implicitHeight, groupTab.implicitHeight)

                // ---- 触发器
                ColumnLayout {
                    id: triggerTab
                    visible: editor.tabbed && editor.tabName === "触发器"
                    width: parent.width
                    spacing: Theme.unit

                    // When the control shows at all.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.preferredWidth: editor.labelW
                            Layout.preferredHeight: Theme.rowH
                            verticalAlignment: Text.AlignVCenter
                            text: "显示"
                            color: Theme.textDim
                        }
                        ThemeComboBox {
                            id: triggerShowBox
                            Layout.preferredWidth: 36 * Theme.unit
                            model: [
                                { label: "始终显示，触发器只加效果", value: "always" },
                                { label: "只在有触发器满足时显示", value: "active" }
                            ]
                            Component.onCompleted: select(editor.triggers.show)
                            Connections { target: editor; function onTriggersChanged() { triggerShowBox.select(editor.triggers.show) } }
                            onActivated: editor.saveTriggers(editor.triggers.list, currentValue)
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: editor.triggers.show === "always"
                              ? "控件一直按外观显示；满足的触发器在上面播放效果。"
                              : "没有触发器满足时整个控件隐藏。例：连携技冷却完毕 + 中心扩散（图标本身从无变大）+ 播放一次 + 播放完消失 = 冷却转好时从无扩散出来，播完消失。"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.unit
                        spacing: Theme.unit
                        Label {
                            text: editor.triggers.list.length === 0
                                  ? (editor.kind === "bar" ? "没有触发器：显示为满" : "没有触发器：按外观静态显示")
                                  : "触发器"
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
                            forText: editor.kind === "text"
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
                        text: "按顺序检查：第一个满足的触发器给出进度（标黄的那个）。没有满足的就显示为空。例：连携技（勾「反向」）= 冷却转好时填满；Buff = 剩余时间。"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: editor.triggers.list.length > 0 && editor.kind === "icon"
                        text: "按顺序检查：第一个满足、且设了效果的触发器驱动图标（标黄的那个）。例：连携技 + 顺时针填充 = 连携技冷却转圈；终结技充满 + 中心扩散（图标本身从无变大）+ 播放一次 = 充满时的提示动画。"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                        visible: BridgeReader.status !== "online" && BridgeReader.status !== "stale"
                        text: "Bridge " + BridgeReader.statusText + "：条件暂时无法判断，都按不满足处理。"
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
                            text: "旋转"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: 359; unit: "°"
                            value: editor.value("shapeAngle", 0)
                            onCommitted: v => editor.roleChanged("shapeAngle", v)
                        }
                    }
                    FieldRow {
                        label: "图形大小"
                        NumberField {
                            from: 1; to: 100; decimals: 1; unit: "%"
                            value: editor.value("iconSize", 84)
                            onCommitted: v => editor.roleChanged("iconSize", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "控件框较短一边的百分比（1–100）"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }

                    Section { text: "边框" }
                    ColorRow { label: "颜色"; colorRole: "borderColor"; opacityRole: "borderOpacity" }
                    FieldRow {
                        label: "宽度"
                        NumberField {
                            from: 0; to: 16; unit: "px"
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
                    Hint { Layout.leftMargin: editor.labelW; text: "按 1280×720 的设计坐标，游戏里按实际分辨率等比缩放。" }

                    Section { text: "文字" }
                    FieldRow {
                        label: "显示"
                        CheckRow { text: "剩余时间"; role: "showTimer"; fallback: true }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "层数"; role: "showStacks"; fallback: true }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "数字取自正在驱动图标的触发器；层数大于 1 时才显示。" }
                    ValueStyle { visible: editor.value("showTimer", true) }
                }

                // ---- 外观 (bar)
                ColumnLayout {
                    id: barLooksTab
                    visible: editor.kind === "bar" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property bool ring: editor.value("barStyle", "ring") === "ring"

                    Section { text: "类型"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "形状"
                        Choice {
                            role: "barStyle"; fallback: "ring"
                            model: [{ label: "圆环", value: "ring" }, { label: "长方形", value: "rect" }]
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "旋转"
                            color: Theme.textDim
                        }
                        NumberField {
                            from: 0; to: 359; unit: "°"
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
                    Hint { visible: barLooksTab.ring; Layout.leftMargin: editor.labelW; text: "内圆半径为 0 就是实心圆。" }
                    FieldRow {
                        visible: barLooksTab.ring
                        label: "缺口"
                        NumberField {
                            from: 0; to: 359; unit: "°"
                            value: editor.value("ringGap", 0)
                            onCommitted: v => editor.roleChanged("ringGap", v)
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "削掉的角度，旋转为 0° 时在底部：0° 是整圆，90° 是 3/4 圆弧"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }
                    FieldRow {
                        visible: !barLooksTab.ring
                        label: "长度"
                        NumberField {
                            from: 4; to: 1280; unit: "px"
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
                            value: editor.value("barThickness", 24)
                            onCommitted: v => editor.roleChanged("barThickness", v)
                        }
                    }

                    Section { text: "进度" }
                    FieldRow {
                        label: "方向"
                        Choice {
                            id: dirBox
                            role: "barDirection"; fallback: "leftToRight"
                            // A ring only goes two ways; the rect has all four.
                            model: barLooksTab.ring
                                ? [{ label: "顺时针（从缺口左端）", value: "leftToRight" }, { label: "逆时针（从缺口右端）", value: "rightToLeft" }]
                                : [{ label: "左到右", value: "leftToRight" }, { label: "右到左", value: "rightToLeft" },
                                   { label: "下到上", value: "bottomToTop" }, { label: "上到下", value: "topToBottom" }]
                            onModelChanged: select(editor.value("barDirection", "leftToRight"))
                        }
                    }
                    ColorRow { label: "颜色"; colorRole: "progressColor"; opacityRole: "progressOpacity" }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "进度单独画在内部填充上面，有自己的颜色和不透明度。"
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
                            text: "进度变化时用这么久滑到新值；0 = 直接跳"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }
                    FieldRow {
                        label: "分段"
                        ThemeComboBox {
                            id: segBox
                            model: [{ label: "不分段", value: "none" }, { label: "按技力格", value: "cells" }, { label: "固定段数", value: "fixed" }]
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
                        text: "段数 = 技力上限 / 每格技力，随游戏里的上限变化（当前 " + (BridgeReader.team.atbPerCell > 0
                              ? Math.round(BridgeReader.team.atbMax / BridgeReader.team.atbPerCell) + " 格）" : "未知）")
                    }
                    FieldRow {
                        visible: barLooksTab.ring
                        label: "端点"
                        Choice {
                            role: "ringCap"; fallback: "butt"
                            model: [{ label: "平头", value: "butt" }, { label: "圆头", value: "round" }]
                        }
                        Label {
                            Layout.leftMargin: Theme.unit
                            text: "圆环有缺口或未满时，进度和填充两端的形状"
                            color: Theme.textFaint
                            font.pixelSize: Theme.caption
                        }
                    }

                    Section { text: "边框" }
                    ColorRow { label: "颜色"; colorRole: "borderColor"; opacityRole: "borderOpacity" }
                    FieldRow {
                        label: "宽度"
                        NumberField {
                            from: 0; to: 16; unit: "px"
                            value: editor.value("borderWidth", 3)
                            onCommitted: v => editor.roleChanged("borderWidth", v)
                        }
                    }

                    Section { text: "内部填充" }
                    ColorRow { label: "颜色"; colorRole: "fillColor"; opacityRole: "fillOpacity" }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "进度没有走到的部分。不透明度设为 0% 就只剩边框；边框宽度也设为 0 就只有进度。"
                    }

                    Section { text: "文字" }
                    FieldRow {
                        label: "显示"
                        CheckRow { text: "数值"; role: "showTimer"; fallback: true }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "层数"; role: "showStacks"; fallback: true }
                    }
                    Hint { Layout.leftMargin: editor.labelW; text: "数值取自决定进度的触发器（技力、剩余时间等）；层数大于 1 时才显示。" }
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
                        text: "控件框跟着形状、尺寸、旋转和边框自动算，旋转后取外接矩形；位置是控件框的左上角。"
                    }
                }

                // ---- 内容 (text)
                ColumnLayout {
                    id: textContentTab
                    visible: editor.kind === "text" && editor.tabName === "内容"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property string mode: editor.value("textMode", "static")

                    Section { text: "类型"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "内容"
                        Choice {
                            role: "textMode"; fallback: "static"
                            model: [
                                { label: "静态文字", value: "static" }, { label: "动态文字", value: "dynamic" },
                                { label: "静态 + 动态", value: "both" }
                            ]
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: textContentTab.mode === "static" ? "固定的文字。"
                            : textContentTab.mode === "dynamic" ? "游戏里的一个数值，随数据刷新。"
                            : "固定文字后面接一个数值，例如「某 Buff：」+ 这个 Buff 的剩余时间。"
                    }
                    FieldRow {
                        visible: textContentTab.mode !== "dynamic"
                        label: "静态文字"
                        ThemeTextField {
                            Layout.fillWidth: true
                            placeholderText: textContentTab.mode === "both" ? "例：某 Buff：" : "要显示的文字"
                            text: editor.value("staticText", "")
                            onEditingFinished: editor.roleChanged("staticText", text)
                            onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => editor.value("staticText", ""))
                        }
                    }
                    Section { visible: textContentTab.mode !== "static"; text: "动态内容" }
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
                        label: "显示"
                        ThemeComboBox {
                            id: showBox
                            model: Triggers.textShows
                            Component.onCompleted: select(editor.textSource.show)
                            Connections { target: editor; function onTextSourceChanged() { showBox.select(editor.textSource.show) } }
                            onActivated: editor.setTextSource("show", currentValue)
                        }
                        Label {
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            visible: editor.textSource.show !== "auto" && editor.textSource.show !== "stacks"
                            text: "小数位"
                            color: Theme.textDim
                        }
                        NumberField {
                            visible: editor.textSource.show !== "auto" && editor.textSource.show !== "stacks"
                            from: 0; to: 3
                            value: editor.textSource.decimals
                            onCommitted: v => editor.setTextSource("decimals", v)
                        }
                    }
                    Hint {
                        visible: textContentTab.mode !== "static"
                        Layout.leftMargin: editor.labelW
                        text: "自动：Buff / 技能 / 连携技显示剩余秒数，技力、终结技显示数值，HP、失衡显示百分比。数值：剩余秒数或当前值。"
                    }
                    FieldRow {
                        visible: textContentTab.mode !== "static"
                        label: "没有数值时"
                        CheckRow {
                            text: "隐藏整个文本"
                            on: editor.textSource.hideEmpty
                            onClicked: editor.setTextSource("hideEmpty", !editor.textSource.hideEmpty)
                        }
                        Label {
                            visible: !editor.textSource.hideEmpty
                            Layout.leftMargin: Theme.gap
                            Layout.preferredWidth: 8 * Theme.unit
                            text: "改显示"
                            color: Theme.textDim
                        }
                        ThemeTextField {
                            visible: !editor.textSource.hideEmpty
                            Layout.preferredWidth: 16 * Theme.unit
                            placeholderText: "留空"
                            text: editor.textSource.empty
                            onEditingFinished: editor.setTextSource("empty", text)
                        }
                    }
                    Hint {
                        visible: textContentTab.mode !== "static"
                        Layout.leftMargin: editor.labelW
                        text: "没有数值：未连接、Buff 不在、没有锁定目标等。预览关掉「按触发器显示」时显示为 --，方便摆放。"
                    }
                }
                // ---- 外观 (text)
                ColumnLayout {
                    id: textLooksTab
                    visible: editor.kind === "text" && editor.tabName === "外观"
                    width: parent.width
                    spacing: Theme.unit

                    Section { text: "文字"; Layout.topMargin: 0 }
                    ColorRow { label: "颜色"; colorRole: "textColor"; opacityRole: "textOpacity" }
                    FieldRow {
                        label: "字号"
                        NumberField {
                            from: 6; to: 200; unit: "px"
                            value: editor.value("fontSize", 24)
                            onCommitted: v => editor.roleChanged("fontSize", v)
                        }
                        CheckRow { Layout.leftMargin: Theme.gap; text: "粗体"; role: "fontBold"; fallback: true }
                    }
                    FieldRow {
                        label: "对齐"
                        Choice {
                            role: "textAlign"; fallback: "center"
                            model: [{ label: "居左", value: "left" }, { label: "居中", value: "center" }, { label: "居右", value: "right" }]
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
                    Hint { Layout.leftMargin: editor.labelW; text: "文字在框里垂直居中，按「对齐」靠左、居中或靠右；超出框的部分照常画出。" }
                }

                // ---- group
                ColumnLayout {
                    id: groupTab
                    visible: editor.kind === "group"
                    width: parent.width
                    spacing: Theme.unit
                    readonly property var g: editor.groupInfo
                    readonly property bool empty: !g || g.n === 0

                    Hint {
                        visible: groupTab.empty
                        text: "组还是空的：在左侧把控件拖到组那一行的中间即可加入。"
                    }
                    Section { text: "整体"; Layout.topMargin: 0 }
                    FieldRow {
                        label: "不透明度"
                        SliderField { role: "groupOpacity"; fallback: 100 }
                    }
                    FieldRow {
                        label: "缩放"
                        SliderField { role: "groupScale"; from: 10; to: 300; fallback: 100 }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "作用于组内所有控件，和它们自己的设置相乘。缩放以组的左上角为原点。"
                    }
                    Section { text: "位置" }
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
                        label: "范围"
                        Label {
                            text: groupTab.empty ? "—" : Math.round(groupTab.g.bw) + " × " + Math.round(groupTab.g.bh)
                                  + "（" + groupTab.g.n + " 个控件）"
                            color: Theme.text
                        }
                    }
                    Hint {
                        Layout.leftMargin: editor.labelW
                        text: "组内所有控件的外接矩形（缩放后）。改位置会把所有成员一起移动；在预览窗口里选中组后也可以直接拖动。"
                    }
                }
            }
        }
    }
}
