import QtQuick
import QtQuick.Controls.Basic

// The four kinds of control; clicking one creates it.
PageFrame {
    id: newPage
    signal createRequested(string kind)

    title: "新建"
    subtitle: "请选择创建的控件类型："

    ScrollView {
        id: choicesView
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        contentHeight: choices.height
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            id: choices
            width: choicesView.availableWidth
            spacing: Theme.unit * 3 / 2

            Repeater {
                model: [
                    { kind: "icon", title: "图标", desc: "自定义图形与动画提示" },
                    { kind: "bar", title: "进度条", desc: "展示时间、资源与冷却状态" },
                    { kind: "text", title: "文本", desc: "展示动态数值或自定义文字" },
                    { kind: "buffs", title: "Buff列表", desc: "监控目标的 Buff/Debuff 状态列表" },
                    { kind: "group", title: "组", desc: "用于批量管理与控制子控件" },
                ]
                KindRow {
                    required property var modelData
                    kind: modelData.kind
                    text: modelData.title
                    desc: modelData.desc
                    width: choices.width
                    height: 10 * Theme.unit
                }
            }
        }
    }

    // A fixed illustration column keeps the four labels aligned.
    component KindRow: AbstractButton {
        id: card
        property string kind
        property string desc
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        onClicked: newPage.createRequested(card.kind)
        Accessible.description: desc

        background: Rectangle {
            color: card.down || card.hovered ? Theme.raised : Theme.surface
            border.color: card.down || card.visualFocus ? Theme.accent
                        : card.hovered ? Theme.lineStrong : Theme.line
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        contentItem: Item {
            Item {
                id: art
                width: 18 * Theme.unit
                height: parent.height
                Loader {
                    anchors.centerIn: parent
                    sourceComponent: card.kind === "icon" ? iconArt : card.kind === "bar" ? barArt
                                   : card.kind === "text" ? textArt : card.kind === "buffs" ? buffsArt : groupArt
                }
            }
            Rectangle {
                x: art.width - 1
                y: Theme.gap
                width: 1
                height: parent.height - 2 * Theme.gap
                color: Theme.line
            }
            Column {
                x: art.width + 3 * Theme.unit
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x - 3 * Theme.unit)
                spacing: Theme.unit / 2
                Label {
                    width: parent.width
                    height: 3 * Theme.unit
                    verticalAlignment: Text.AlignVCenter
                    text: card.text
                    font.pixelSize: Theme.heading
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    height: 2 * Theme.unit
                    verticalAlignment: Text.AlignVCenter
                    text: card.desc
                    color: Theme.textDim
                    font.pixelSize: Theme.caption
                    elide: Text.ElideRight
                }
            }
        }

        // A 40 px icon, the elapsed part of its cooldown darkened.
        Component {
            id: iconArt
            Canvas {
                width: 40
                height: 40
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    g.fillStyle = Theme.accent
                    g.fillRect(0, 0, width, height)
                    g.fillStyle = Qt.rgba(0, 0, 0, 150 / 255)
                    g.beginPath()
                    g.moveTo(width / 2, height / 2)
                    g.arc(width / 2, height / 2, width, -Math.PI / 2, -Math.PI / 2 - Math.PI * 2 / 3, true)
                    g.closePath()
                    g.fill()
                }
            }
        }
        // A 120 px bar, 5/8 full, in three cells.
        Component {
            id: barArt
            Item {
                width: 120
                height: 12
                Rectangle { anchors.fill: parent; color: Theme.lineStrong }
                Rectangle { width: parent.width * 5 / 8; height: parent.height; color: Theme.accent }        
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        x: Math.round(120 * (index + 1) / 3) - 1
                        width: 2
                        height: 12
                        color: Theme.base
                    }
                }
            }
        }
        Component {
            id: textArt
            Label {
                text: "3.25"
                color: Theme.accent
                font.pixelSize: 2 * Theme.title
                font.weight: Font.DemiBold
            }
        }
        // Four buff cells, the first two with time running out.
        Component {
            id: buffsArt
            Row {
                spacing: Theme.unit / 2
                Repeater {
                    model: [0.7, 0.35, 1, 1]
                    Rectangle {
                        required property real modelData
                        required property int index
                        width: 3 * Theme.unit; height: width
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                        border.color: index === 2 ? Theme.danger : Theme.accent
                        Rectangle { x: 1; y: 1; width: parent.width - 2; height: (parent.height - 2) * (1 - parent.modelData); color: "#000000"; opacity: 0.45 }
                    }
                }
            }
        }
        // Three 24 px squares, 8 apart.
        Component {
            id: groupArt
            Row {
                spacing: Theme.unit
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 24
                        height: 24
                        color: index === 0 ? Theme.accent : Theme.lineStrong
                    }
                }
            }
        }
    }
}
