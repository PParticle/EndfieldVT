import QtQuick
import QtQuick.Controls.Basic

// A typed number with an optional unit after it. Commits on Enter or when
// focus leaves; out-of-range input is clamped, anything else is reverted.
// Until the user types, the text follows `value` even while focused (the
// field keeps focus after Enter while the editor switches controls).
ThemeTextField {
    id: field
    property real value: 0
    property real from: 0
    property real to: 100
    property int decimals: 0
    property string unit
    signal committed(real value)
    property bool edited: false

    function format(v) { return decimals > 0 ? Number(v).toFixed(decimals) : String(Math.round(v)) }
    function commit() {
        if (!edited) {
            text = format(value)
            return
        }
        edited = false
        const parsed = Number(text.trim())
        if (text.trim() === "" || isNaN(parsed)) {
            text = format(value)
            return
        }
        const factor = Math.pow(10, decimals)
        const clamped = Math.max(from, Math.min(to, Math.round(parsed * factor) / factor))
        text = format(clamped)
        if (clamped !== value) committed(clamped)
    }

    implicitWidth: 12 * Theme.unit
    rightPadding: Theme.unit + (unit !== "" ? unitLabel.implicitWidth + Theme.unit / 2 : 0)
    horizontalAlignment: TextInput.AlignRight
    inputMethodHints: Qt.ImhFormattedNumbersOnly
    validator: RegularExpressionValidator { regularExpression: /-?\d*(\.\d*)?/ }
    text: format(value)
    onTextEdited: edited = true
    onValueChanged: if (!edited) text = format(value)
    onEditingFinished: commit()
    onActiveFocusChanged: if (!activeFocus) commit()

    Label {
        id: unitLabel
        visible: field.unit !== ""
        anchors { right: parent.right; rightMargin: Theme.unit; verticalCenter: parent.verticalCenter }
        text: field.unit
        color: Theme.textDim
        font.pixelSize: Theme.caption
    }
}
