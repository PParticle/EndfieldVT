import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Brand on the left (its zone can be given a width so the actions line up
// with a column below), actions, trailing items (right aligned), then
// minimize / maximize / close.
Rectangle {
    id: bar

    property string subtitle
    property int leadWidth: -1      // -1: as wide as the brand needs
    property alias actions: actionRow.data
    property alias trailing: trailingRow.data
    // The window this bar is in. Pointer handlers are not Items, so they
    // cannot use the Window attached property themselves.
    readonly property var win: Window.window

    implicitHeight: Theme.titleBarH
    color: Theme.frame

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.line
    }

    // Behind the buttons: drag the empty bar to move, double click to maximize.
    // The system move starts on press, as the edge resize does: started
    // later (a DragHandler activating after the drag threshold) Windows
    // ignores it. Windows then also restores a maximized window and snaps.
    MouseArea {
        anchors.fill: parent
        onPressed: bar.win.startSystemMove()
        onDoubleClicked: bar.win.toggleMaximized()
    }

    RowLayout {
        anchors { fill: parent; bottomMargin: 1 }
        spacing: 0

        // Brand: an accent square on the window's text column (x = gap).
        Item {
            Layout.fillHeight: true
            Layout.preferredWidth: bar.leadWidth >= 0 ? bar.leadWidth : brand.implicitWidth + 2 * Theme.gap
            Row {
                id: brand
                x: Theme.gap
                height: parent.height
                spacing: Theme.unit
                Rectangle {
                    width: Theme.unit
                    height: Theme.unit
                    y: Math.round((parent.height - height) / 2)
                    color: Theme.accent
                }
                Label {
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "EndfieldVT"
                    font.weight: Font.DemiBold
                }
                Label {
                    visible: bar.subtitle !== ""
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.unit / 2
                    text: bar.subtitle
                    color: Theme.textDim
                    font.pixelSize: Theme.caption
                }
            }
        }

        Row {
            id: actionRow
            Layout.fillHeight: true
        }
        Item { Layout.fillWidth: true }
        Row {
            id: trailingRow
            Layout.fillHeight: true
        }

        WindowButton {
            id: minButton
            onClicked: bar.win.showMinimized()
            Rectangle {
                x: Math.floor((parent.width - 10) / 2)
                y: Math.floor(parent.height / 2)
                width: 10
                height: 1
                color: minButton.fg
            }
        }
        WindowButton {
            id: maxButton
            onClicked: bar.win.toggleMaximized()
            readonly property int x0: Math.floor((width - 10) / 2)
            readonly property int y0: Math.floor((height - 10) / 2)
            Rectangle {   // maximize: one square; restore: two, the front one filled
                x: maxButton.x0 + (bar.win.maximized ? 2 : 0)
                y: maxButton.y0
                width: bar.win.maximized ? 8 : 10
                height: width
                color: "transparent"
                border.color: maxButton.fg
            }
            Rectangle {
                visible: bar.win.maximized
                x: maxButton.x0
                y: maxButton.y0 + 2
                width: 8
                height: 8
                color: maxButton.bg
                border.color: maxButton.fg
            }
        }
        WindowButton {
            id: closeButton
            danger: true
            onClicked: bar.win.close()
            Repeater {
                model: [45, -45]
                Rectangle {
                    required property int modelData
                    x: Math.floor((closeButton.width - width) / 2)
                    y: Math.floor(closeButton.height / 2)
                    width: 14
                    height: 1
                    rotation: modelData
                    antialiasing: true
                    color: closeButton.fg
                }
            }
        }
    }

    // A square the height of the bar, a 10 px line icon in the middle.
    component WindowButton: AbstractButton {
        id: button
        property bool danger: false
        readonly property bool hot: hovered || pressed
        readonly property color bg: danger && hot ? (pressed ? Qt.darker(Theme.danger, 1.15) : Theme.danger)
                                  : pressed ? Theme.raised : hovered ? Theme.surface : Theme.frame
        readonly property color fg: danger && hot ? "white" : hot ? Theme.text : Theme.textDim
        implicitWidth: Theme.titleBarH
        Layout.fillHeight: true
        focusPolicy: Qt.NoFocus
        background: Rectangle { color: button.bg }
    }
}
