import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A color picker on the dark theme, in place of the system dialog: a
// saturation / value square, a hue strip, an opacity strip, a hex field and
// the recently used colors. Changes apply live; Esc or a click outside keeps
// them, 「还原」 goes back to the color it opened with.
Popup {
    id: picker
    property color initial: "white"
    property bool withAlpha: true
    signal picked(color value)

    // HSV of the current color, with alpha; kept apart so hue survives grey.
    property real hue: 0
    property real sat: 0
    property real val: 1
    property real alpha: 1
    readonly property color current: Qt.hsva(hue, sat, val, withAlpha ? alpha : 1)

    // Recently picked colors, shared by every picker in the app.
    property var recent: []
    readonly property int swatch: 2 * Theme.unit + 4

    function openWith(c) {
        initial = c
        setFrom(c)
        open()
    }
    function setFrom(c) {
        const col = Qt.color(c)
        // Keep hue when the color has none (grey) so the square does not jump.
        if (col.hsvSaturation > 0 && col.hsvValue > 0) hue = Math.max(0, col.hsvHue)
        sat = col.hsvSaturation
        val = col.hsvValue
        alpha = col.a
    }
    function hex(c) {
        const col = Qt.color(c)
        const h = n => ("0" + Math.round(n * 255).toString(16)).slice(-2)
        return ("#" + (withAlpha && col.a < 1 ? h(col.a) : "") + h(col.r) + h(col.g) + h(col.b)).toUpperCase()
    }
    function emitCurrent() { picked(current) }
    function remember() {
        const code = hex(current)
        const list = recent.filter(c => c !== code)
        list.unshift(code)
        recent = list.slice(0, 8)
    }
    onClosed: remember()

    width: 32 * Theme.unit
    padding: Theme.gap
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: Theme.surface; border.color: Theme.lineStrong; radius: Theme.radius }

    contentItem: ColumnLayout {
        spacing: Theme.unit

        // Saturation (x) / value (y) for the current hue.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 20 * Theme.unit
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "white" }
                    GradientStop { position: 1; color: Qt.hsva(picker.hue, 1, 1, 1) }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "black" }
                }
            }
            Rectangle {   // the marker: a ring that reads on any color
                x: picker.sat * parent.width - width / 2
                y: (1 - picker.val) * parent.height - height / 2
                width: 12; height: 12; radius: 6
                color: "transparent"
                border.color: picker.val > 0.5 && picker.sat < 0.5 ? "black" : "white"
                border.width: 2
            }
            MouseArea {
                anchors.fill: parent
                function pick(m) {
                    picker.sat = Math.max(0, Math.min(1, m.x / width))
                    picker.val = 1 - Math.max(0, Math.min(1, m.y / height))
                    picker.emitCurrent()
                }
                onPressed: m => pick(m)
                onPositionChanged: m => { if (pressed) pick(m) }
            }
        }

        // Hue
        Strip {
            Layout.fillWidth: true
            position: picker.hue
            onMoved: p => { picker.hue = p; picker.emitCurrent() }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0 / 6; color: "#ff0000" }
                    GradientStop { position: 1 / 6; color: "#ffff00" }
                    GradientStop { position: 2 / 6; color: "#00ff00" }
                    GradientStop { position: 3 / 6; color: "#00ffff" }
                    GradientStop { position: 4 / 6; color: "#0000ff" }
                    GradientStop { position: 5 / 6; color: "#ff00ff" }
                    GradientStop { position: 6 / 6; color: "#ff0000" }
                }
            }
        }

        // Opacity, over a checkerboard so transparency shows.
        Strip {
            visible: picker.withAlpha
            Layout.fillWidth: true
            position: picker.alpha
            onMoved: p => { picker.alpha = p; picker.emitCurrent() }
            Grid {
                anchors.fill: parent
                clip: true
                columns: Math.ceil(width / 6)
                Repeater {
                    model: Math.ceil(parent.width / 6) * 2
                    Rectangle {
                        required property int index
                        width: 6; height: 6
                        readonly property int col: index % Math.ceil(parent.width / 6)
                        readonly property int row: Math.floor(index / Math.ceil(parent.width / 6))
                        color: (col + row) % 2 ? "#5a5f66" : "#3a3f47"
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsva(picker.hue, picker.sat, picker.val, 0) }
                    GradientStop { position: 1; color: Qt.hsva(picker.hue, picker.sat, picker.val, 1) }
                }
            }
        }

        // Before / after and the hex code.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.unit
            Rectangle {
                Layout.preferredWidth: 2 * picker.swatch
                Layout.preferredHeight: Theme.rowH
                border.color: Theme.lineStrong
                color: "transparent"
                Rectangle { x: 1; y: 1; width: picker.swatch - 1; height: parent.height - 2; color: picker.initial }
                Rectangle { x: picker.swatch; y: 1; width: picker.swatch - 1; height: parent.height - 2; color: picker.current }
            }
            ThemeTextField {
                id: hexField
                Layout.fillWidth: true
                font.family: "Consolas"
                text: picker.hex(picker.current)
                validator: RegularExpressionValidator { regularExpression: /#?[0-9A-Fa-f]{0,8}/ }
                onEditingFinished: {
                    let t = text.trim()
                    if (!t.startsWith("#")) t = "#" + t
                    if (/^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(t)) {
                        picker.setFrom(t)
                        picker.emitCurrent()
                    }
                    text = Qt.binding(() => picker.hex(picker.current))
                }
            }
        }

        // Recent
        Flow {
            visible: picker.recent.length > 0
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: picker.recent
                AbstractButton {
                    required property string modelData
                    width: picker.swatch
                    height: picker.swatch
                    hoverEnabled: true
                    onClicked: { picker.setFrom(modelData); picker.emitCurrent() }
                    background: Rectangle { color: parent.modelData; border.color: parent.hovered ? Theme.text : Theme.lineStrong }
                    ToolTip.visible: hovered
                    ToolTip.text: modelData
                    ToolTip.delay: 400
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.unit
            Item { Layout.fillWidth: true }
            FlatButton { text: "还原"; onClicked: { picker.setFrom(picker.initial); picker.emitCurrent() } }
            FlatButton { text: "完成"; accent: true; onClicked: picker.close() }
        }
    }

    // A horizontal strip with a position marker, dragged to set 0-1.
    component Strip: Item {
        id: strip
        property real position: 0
        signal moved(real position)
        implicitHeight: 2 * Theme.unit
        Rectangle {   // marker
            z: 2
            x: Math.round(strip.position * (strip.width - width))
            y: -2
            width: 6
            height: strip.height + 4
            color: "transparent"
            border.color: "white"
            border.width: 2
        }
        MouseArea {
            z: 3
            anchors.fill: parent
            function pick(m) { strip.moved(Math.max(0, Math.min(1, m.x / width))) }
            onPressed: m => pick(m)
            onPositionChanged: m => { if (pressed) pick(m) }
        }
    }
}
