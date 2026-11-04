import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A content page: title row (the height of a list row, so it lines up with
// the sidebar caption), subtitle, then the content.
Item {
    id: page
    property string title
    property string subtitle
    default property alias content: body.data

    ColumnLayout {
        anchors { fill: parent; margins: Theme.pagePad }
        spacing: 0
        Label {
            Layout.preferredHeight: Theme.rowH
            verticalAlignment: Text.AlignVCenter
            text: page.title
            font.pixelSize: Theme.title
            font.weight: Font.DemiBold
        }
        Label {
            Layout.preferredHeight: 3 * Theme.unit
            verticalAlignment: Text.AlignVCenter
            text: page.subtitle
            color: Theme.textDim
        }
        Item { Layout.preferredHeight: 3 * Theme.unit }
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
