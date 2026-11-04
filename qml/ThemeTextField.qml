import QtQuick
import QtQuick.Controls.Basic

// A one-line input on the dark theme: row height, surface fill, accent
// border while editing.
TextField {
    id: field
    implicitHeight: Theme.rowH
    leftPadding: Theme.unit
    rightPadding: Theme.unit
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: Theme.frame
    selectByMouse: true
    background: Rectangle {
        color: Theme.surface
        border.color: field.activeFocus ? Theme.accent : field.hovered ? Theme.lineStrong : Theme.line
    }
}
