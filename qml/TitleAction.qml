import QtQuick
import QtQuick.Controls.Basic

// A full-height text button for the title bar. The label is exactly `gap`
// from each side; checked shows the accent underline.
AbstractButton {
    id: control
    implicitWidth: Math.ceil(label.implicitWidth) + 2 * Theme.gap
    implicitHeight: Theme.titleBarH - 1
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        color: control.pressed ? Theme.raised : control.hovered ? Theme.surface : "transparent"
        Rectangle {
            visible: control.checked
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 2
            color: Theme.accent
        }
    }
    Label {
        id: label
        x: Theme.gap
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: control.text
        color: control.checked ? Theme.accent : control.hovered ? Theme.text : Theme.textDim
    }
}
