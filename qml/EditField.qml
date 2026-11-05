import QtQuick
import QtQuick.Controls.Basic

// A text input bound to one saved value: shows `value` until the user
// types, and hands back what was typed (on Enter or when focus leaves)
// only then. Text the user did not touch is never written anywhere, so a
// field still focused when the editor switches controls cannot carry one
// control's text over to the next.
ThemeTextField {
    id: field
    property string value
    property bool edited: false
    signal committed(string text)

    text: value
    onValueChanged: if (!edited) text = value
    onTextEdited: edited = true
    onEditingFinished: {
        if (!edited) return
        edited = false
        if (text !== value) committed(text)
        text = Qt.binding(() => field.value)
    }
}
