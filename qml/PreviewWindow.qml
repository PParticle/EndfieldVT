import QtQuick
import QtQuick.Controls.Basic

// The 1280 x 720 design canvas, scaled to the window. Controls are drawn in
// the sidebar's order (its top row on top) and moved by dragging. A
// selected group shows a frame around its members; dragging it moves them all.
AppWindow {
    id: preview
    property ListModel model
    property ListModel copies        // slots 2-4 of expanded controls (Main.copyStore)
    property var groups: ({})
    property var groupStates: ({})
    property string selectedId
    signal selected(string id)
    signal moved(string id, real x, real y)
    signal groupMoved(string id, real x, real y)   // the group's frame, drawn position
    subtitle: "预览与编辑"
    title: "EndfieldVT 预览与编辑"
    width: 1280 + 2 * frameWidth
    height: 720 + Theme.titleBarH + 2 * frameWidth
    minimumWidth: 800 + 2 * frameWidth
    minimumHeight: 450 + Theme.titleBarH + 2 * frameWidth

    WindowAspectRatio {
        window: preview; ratio: 16 / 9
        insets: Qt.size(2 * preview.frameWidth, Theme.titleBarH + 2 * preview.frameWidth)
    }
    // Off: every control shows, for arranging. On: icons show only while
    // their triggers are active, with the trigger's progress and stacks.
    property bool live: true
    actions: [
        TitleAction {
            text: preview.live ? "仅显示满足项" : "显示全部控件"
            checked: preview.live
            onClicked: preview.live = !preview.live
        },
        Item { width: Theme.unit; height: 1 },
        Row {
            height: Theme.titleBarH - 1; spacing: Theme.unit
            Label { text: "网格"; height: parent.height; verticalAlignment: Text.AlignVCenter; color: Theme.textDim }
            Slider {
                id: density; objectName: "gridDensity"; width: 20 * Theme.unit; height: parent.height
                from: 0; to: 100; stepSize: 1; value: 40
                Accessible.name: "网格密度"; Accessible.description: "0% 隐藏，100% 最密；仅供对齐参考，无吸附功能。"
                background: Rectangle {
                    x: density.leftPadding
                    y: Math.round(density.topPadding + (density.availableHeight - height) / 2)
                    width: density.availableWidth; height: 2; color: Theme.lineStrong
                    Rectangle { width: density.visualPosition * parent.width; height: parent.height; color: Theme.accent }
                }
                handle: Rectangle {
                    x: Math.round(density.leftPadding + density.visualPosition * (density.availableWidth - width))
                    y: Math.round(density.topPadding + (density.availableHeight - height) / 2)
                    width: Theme.unit; height: 2 * Theme.unit
                    color: density.pressed ? Theme.text : Theme.accent
                    border.color: density.visualFocus ? Theme.text : color
                }
            }
            Label {
                text: Math.round(density.value) + "%"; width: 5 * Theme.unit; height: parent.height
                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                color: Theme.textDim; font.pixelSize: Theme.caption
            }
        }
    ]

    Rectangle {
        anchors.fill: parent; color: Theme.frame
        Rectangle {
            id: canvas; objectName: "previewCanvas"
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * 16 / 9); height: width * 9 / 16
            color: Theme.base; clip: true
            readonly property real designScale: width / 1280
            // Click the empty canvas to clear the selection.
            TapHandler { onTapped: preview.selected("") }
            readonly property real gridSpacing: Math.max(16, Math.round(160 * Math.pow(0.1, density.value / 100) / 4) * 4)
            readonly property real gridStep: gridSpacing * designScale
            readonly property int halfColumns: gridStep > 0 ? Math.floor(width / (2 * gridStep)) : 0
            readonly property int halfRows: gridStep > 0 ? Math.floor(height / (2 * gridStep)) : 0

            Repeater {
                model: density.value > 0 ? 2 * canvas.halfColumns + 1 : 0
                Rectangle {
                    required property int index
                    x: Math.round(canvas.width / 2 + (index - canvas.halfColumns) * canvas.gridStep)
                    width: 1; height: canvas.height
                    color: index === canvas.halfColumns ? Theme.lineStrong : Theme.line
                    opacity: index === canvas.halfColumns ? 1 : 0.6
                }
            }
            Repeater {
                model: density.value > 0 ? 2 * canvas.halfRows + 1 : 0
                Rectangle {
                    required property int index
                    y: Math.round(canvas.height / 2 + (index - canvas.halfRows) * canvas.gridStep)
                    width: canvas.width; height: 1
                    color: index === canvas.halfRows ? Theme.lineStrong : Theme.line
                    opacity: index === canvas.halfRows ? 1 : 0.6
                }
            }

            Repeater {
                model: preview.model || 0
                delegate: ControlView {
                    id: object
                    designScale: canvas.designScale
                    groups: preview.groups
                groupStates: preview.groupStates
                    editing: true
                    live: preview.live
                    selected: preview.selectedId === uid
                    count: preview.model ? preview.model.count : 0
                    property real dragOriginX: 0
                    property real dragOriginY: 0
                    TapHandler { onTapped: preview.selected(object.uid) }
                    DragHandler {
                        target: null
                        onActiveChanged: {
                            if (active) {
                                // A group's frame moves from where it is drawn.
                                object.dragOriginX = object.isGroup ? object.x / canvas.designScale : object.posX
                                object.dragOriginY = object.isGroup ? object.y / canvas.designScale : object.posY
                                preview.selected(object.uid)
                            }
                        }
                        onActiveTranslationChanged: {
                            if (!active) return
                            if (object.isGroup) {
                                preview.groupMoved(object.uid,
                                    object.dragOriginX + activeTranslation.x / canvas.designScale,
                                    object.dragOriginY + activeTranslation.y / canvas.designScale)
                                return
                            }
                            // A scaled group's member moves by drawn px / its scale.
                            const nx = object.dragOriginX + activeTranslation.x / object.drawScale
                            const ny = object.dragOriginY + activeTranslation.y / object.drawScale
                            preview.moved(object.uid,
                                Math.round(Math.max(0, Math.min(1280 - object.boxWidth, nx))),
                                Math.round(Math.max(0, Math.min(720 - object.boxHeight, ny))))
                        }
                    }
                }
            }
            // Slots 2-4 of an expanded control: selecting or dragging one is
            // selecting or dragging the control (they share its uid and position).
            Repeater {
                model: preview.copies || 0
                delegate: ControlView {
                    id: copy
                    required property int slotOfCopy
                    required property int copyOf
                    copySlot: slotOfCopy
                    designScale: canvas.designScale
                    groups: preview.groups
                    groupStates: preview.groupStates
                    editing: true
                    live: preview.live
                    selected: preview.selectedId === uid
                    count: preview.model ? preview.model.count : 0
                    z: count - copyOf
                    property real dragOriginX: 0
                    property real dragOriginY: 0
                    TapHandler { onTapped: preview.selected(copy.uid) }
                    DragHandler {
                        target: null
                        onActiveChanged: {
                            if (!active) return
                            copy.dragOriginX = copy.posX
                            copy.dragOriginY = copy.posY
                            preview.selected(copy.uid)
                        }
                        onActiveTranslationChanged: {
                            if (!active) return
                            const nx = copy.dragOriginX + activeTranslation.x / copy.drawScale
                            const ny = copy.dragOriginY + activeTranslation.y / copy.drawScale
                            preview.moved(copy.uid,
                                Math.round(Math.max(0, Math.min(1280 - copy.boxWidth, nx))),
                                Math.round(Math.max(0, Math.min(720 - copy.boxHeight, ny))))
                        }
                    }
                }
            }
        }
    }
}
