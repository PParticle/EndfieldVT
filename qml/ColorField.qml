import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A swatch and its hex code; clicking asks for a new color.
AbstractButton {
    id: field
    property color color
    implicitWidth: 23 * Theme.unit
    implicitHeight: Theme.rowH
    hoverEnabled: true
    background: Rectangle {
        color: Theme.surface
        border.color: field.visualFocus ? Theme.accent : field.hovered ? Theme.lineStrong : Theme.line
    }
    contentItem: RowLayout {
        spacing: Theme.unit
        Rectangle {
            Layout.leftMargin: Theme.unit - field.leftPadding
            Layout.preferredWidth: 2 * Theme.unit
            Layout.preferredHeight: 2 * Theme.unit
            color: field.color
            border.color: Theme.lineStrong
        }
        Label {
            Layout.fillWidth: true
            text: field.color.toString().toUpperCase()
            color: Theme.textDim
            font.pixelSize: Theme.caption
        }
    }
}
