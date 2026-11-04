import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A window without the system frame: our title bar on top, a 1 px border,
// moved by dragging the title bar, resized from any edge. What a window puts
// inside goes below the title bar.
ApplicationWindow {
    id: window

    default property alias content: body.data
    property alias subtitle: bar.subtitle
    property alias leadWidth: bar.leadWidth
    property alias actions: bar.actions
    readonly property bool maximized: visibility === Window.Maximized
    readonly property int frameWidth: maximized ? 0 : 1

    function toggleMaximized() {
        if (maximized) showNormal()
        else showMaximized()
    }

    // Frameless, but keep the system's minimize / maximize behavior
    // (taskbar click, Win+Down).
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint
    color: Theme.base
    font.pixelSize: Theme.body
    palette.window: Theme.base
    palette.windowText: Theme.text
    palette.text: Theme.text

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: window.frameWidth
        spacing: 0
        TitleBar {
            id: bar
            Layout.fillWidth: true
        }
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !window.maximized
        color: "transparent"
        border.color: Theme.lineStrong
        z: 1
    }

    // Edge bands that resize; corners on top of the edges.
    component Edge: MouseArea {
        required property int edges
        z: 2
        enabled: !Window.window.maximized
        onPressed: Window.window.startSystemResize(edges)
    }
    readonly property int grip: 6
    Edge { edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor; width: window.grip; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } }
    Edge { edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor; width: window.grip; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } }
    Edge { edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor; height: window.grip; anchors { left: parent.left; right: parent.right; top: parent.top } }
    Edge { edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor; height: window.grip; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } }
    Edge { edges: Qt.LeftEdge | Qt.TopEdge; cursorShape: Qt.SizeFDiagCursor; width: window.grip; height: window.grip; anchors { left: parent.left; top: parent.top } }
    Edge { edges: Qt.RightEdge | Qt.BottomEdge; cursorShape: Qt.SizeFDiagCursor; width: window.grip; height: window.grip; anchors { right: parent.right; bottom: parent.bottom } }
    Edge { edges: Qt.RightEdge | Qt.TopEdge; cursorShape: Qt.SizeBDiagCursor; width: window.grip; height: window.grip; anchors { right: parent.right; top: parent.top } }
    Edge { edges: Qt.LeftEdge | Qt.BottomEdge; cursorShape: Qt.SizeBDiagCursor; width: window.grip; height: window.grip; anchors { left: parent.left; bottom: parent.bottom } }
}
