import QtQuick
import QtQuick.Controls.Basic

// Half the title bar's height; text on the x = gap column.
Rectangle {
    id: bar
    property string gameText
    property bool gameActive: false
    color: Theme.frame

    // Shows `message` for `ms` milliseconds (default 3 s); 0 keeps it.
    function flash(message, ms) {
        status.text = message
        reset.stop()
        if (ms === undefined) ms = 3000
        if (ms > 0) {
            reset.interval = ms
            reset.start()
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Theme.line
    }
    Label {
        id: status
        x: Theme.gap
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: "就绪"
        color: Theme.textDim
        font.pixelSize: Theme.caption
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        height: parent.height
        spacing: Theme.gap
        Label {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: bar.gameText
            color: bar.gameActive ? Theme.textDim : Theme.textFaint
            font.pixelSize: Theme.caption
        }
        Rectangle { width: 1; height: Theme.unit + 4; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
        Label {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: "Bridge " + BridgeReader.statusText
            color: BridgeReader.status === "online" ? Theme.textDim : Theme.textFaint
            font.pixelSize: Theme.caption
        }
    }
    Timer {
        id: reset
        interval: 3000
        onTriggered: status.text = "就绪"
    }
}
