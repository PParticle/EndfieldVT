import QtQuick
import QtQuick.Controls.Basic

// A small text button: outlined, or filled with the accent for the main one.
AbstractButton {
    id: button
    property bool accent: false
    property bool danger: false
    implicitWidth: Math.max(8 * Theme.unit, Math.ceil(label.implicitWidth) + 2 * Theme.gap)
    implicitHeight: Theme.rowH
    hoverEnabled: true
    background: Rectangle {
        color: button.accent ? (button.pressed ? Qt.darker(Theme.accent, 1.15) : button.hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
                             : (button.pressed ? Theme.raised : button.hovered ? Theme.raised : "transparent")
        border.color: button.accent ? "transparent" : button.visualFocus ? Theme.accent : Theme.lineStrong
    }
    contentItem: Label {
        id: label
        text: button.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: button.accent ? Theme.frame : button.danger ? Theme.danger : Theme.text
        opacity: button.enabled ? 1 : 0.4
    }
}
