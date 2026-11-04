import QtQuick
import QtQuick.Controls.Basic

// A thin track with an accent fill and a small square handle, as in the
// preview window's title bar.
Slider {
    id: slider
    implicitHeight: Theme.rowH
    background: Rectangle {
        x: slider.leftPadding
        y: Math.round(slider.topPadding + (slider.availableHeight - height) / 2)
        width: slider.availableWidth
        height: 2
        color: Theme.lineStrong
        Rectangle { width: slider.visualPosition * parent.width; height: parent.height; color: Theme.accent }
    }
    handle: Rectangle {
        x: Math.round(slider.leftPadding + slider.visualPosition * (slider.availableWidth - width))
        y: Math.round(slider.topPadding + (slider.availableHeight - height) / 2)
        width: Theme.unit
        height: 2 * Theme.unit
        color: slider.pressed ? Theme.text : Theme.accent
        border.color: slider.visualFocus ? Theme.text : color
    }
}
