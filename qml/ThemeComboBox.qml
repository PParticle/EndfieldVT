import QtQuick
import QtQuick.Controls.Basic

// A drop-down on the dark theme. Models are arrays of { label, value }.
ComboBox {
    id: box
    implicitWidth: 28 * Theme.unit
    implicitHeight: Theme.rowH
    textRole: "label"
    valueRole: "value"

    function select(value) {
        for (let i = 0; i < count; ++i)
            if (valueAt(i) === value) { currentIndex = i; return }
        currentIndex = 0
    }

    background: Rectangle {
        color: Theme.surface
        border.color: box.visualFocus || box.popup.visible ? Theme.accent : box.hovered ? Theme.lineStrong : Theme.line
    }
    contentItem: Label {
        leftPadding: Theme.unit
        rightPadding: box.indicator.width
        verticalAlignment: Text.AlignVCenter
        text: box.displayText
        elide: Text.ElideRight
    }
    indicator: Item {
        x: box.width - width
        width: Theme.rowH
        height: box.height
        // A small chevron from two 1 px strokes.
        Repeater {
            model: [45, -45]
            Rectangle {
                required property int modelData
                required property int index
                x: Math.round(parent.width / 2 - 3 + index * 4) - 1
                y: Math.round(parent.height / 2) - 1
                width: 6
                height: 1
                rotation: modelData
                antialiasing: true
                color: Theme.textDim
            }
        }
    }
    delegate: ItemDelegate {
        id: option
        required property var model
        required property int index
        width: ListView.view.width
        height: Theme.rowH
        highlighted: box.highlightedIndex === index
        background: Rectangle { color: option.highlighted ? Theme.raised : "transparent" }
        contentItem: Label {
            leftPadding: Theme.unit - option.leftPadding
            verticalAlignment: Text.AlignVCenter
            text: option.model[box.textRole]
            color: box.currentIndex === option.index ? Theme.accent : Theme.text
        }
    }
    popup: Popup {
        y: box.height
        width: box.width
        implicitHeight: Math.min(contentItem.implicitHeight, 8 * Theme.rowH) + 2
        padding: 1
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: box.popup.visible ? box.delegateModel : null
            currentIndex: box.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }
        background: Rectangle { color: Theme.surface; border.color: Theme.lineStrong }
    }
}
