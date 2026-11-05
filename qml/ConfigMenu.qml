import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The title bar's config switch: shows the current config; the menu lists
// every config in the program's folder (src/configfile.h), then makes a
// new one (empty or a copy of the current) or opens the folder. A new
// config asks for its name in a small popup under the button.
TitleAction {
    id: button
    signal switchRequested(string name)
    signal createRequested(string name, bool copy)   // the receiver opens it
    text: "配置：" + ConfigFile.name + "  ▾"
    checked: menu.visible

    onClicked: {
        configs = ConfigFile.list()   // files may have been added outside
        menu.popup(button, 0, button.height)
    }
    property var configs: []

    // ---- the menu: configs, a line, then the commands. Built as one list:
    // a Menu puts Repeater items after its static ones, whatever the order.
    readonly property var entries: configs.map(n => ({ kind: "config", name: n }))
        .concat([{ kind: "line" }, { kind: "new", name: "新建配置..." }, { kind: "copy", name: "复制当前配置..." },
                 { kind: "folder", name: "打开配置文件夹" }])
    Popup {
        id: menu
        function popup(parentItem, x, y) { menu.x = x; menu.y = y; open() }
        padding: 1
        background: Rectangle { color: Theme.surface; border.color: Theme.lineStrong }
        contentItem: Column {
            width: 28 * Theme.unit
            Repeater {
                model: button.entries
                Item {
                    id: entry
                    required property var modelData
                    readonly property bool line: modelData.kind === "line"
                    readonly property bool current: modelData.kind === "config" && modelData.name === ConfigFile.name
                    width: parent.width
                    height: line ? Theme.unit + 1 : Theme.rowH
                    Rectangle {
                        visible: entry.line
                        y: Theme.unit / 2
                        width: parent.width
                        height: 1
                        color: Theme.line
                    }
                    AbstractButton {
                        id: hit
                        visible: !entry.line
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            menu.close()
                            const k = entry.modelData.kind
                            if (k === "config") button.switchRequested(entry.modelData.name)
                            else if (k === "new") namePopup.ask(false)
                            else if (k === "copy") namePopup.ask(true)
                            else ConfigFile.openFolder()
                        }
                        background: Rectangle { color: hit.hovered ? Theme.raised : "transparent" }
                        contentItem: Label {
                            leftPadding: Theme.unit
                            verticalAlignment: Text.AlignVCenter
                            text: (entry.current ? "● " : "    ") + (entry.modelData.name || "")
                            color: entry.current ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // ---- the name of a new config
    Popup {
        id: namePopup
        property bool copy: false
        property string error: ""
        function ask(asCopy) {
            copy = asCopy
            error = ""
            nameField.text = asCopy ? ConfigFile.name + " 副本" : ""
            open()
            nameField.forceActiveFocus()
            nameField.selectAll()
        }
        function accept() {
            const name = nameField.text.trim()
            if (!ConfigFile.validName(name)) { error = "配置名称不能为空，且不能包含字符 \\ / : * ? \" < > |"; return }
            if (button.configs.includes(name)) { error = "已存在名为「" + name + "」的配置文件"; return }
            close()
            button.createRequested(name, copy)
        }
        y: button.height
        padding: Theme.gap
        modal: true
        dim: false
        background: Rectangle { color: Theme.surface; border.color: Theme.lineStrong }
        contentItem: ColumnLayout {
            spacing: Theme.unit
            Label { text: namePopup.copy ? "复制当前配置" : "创建新配置"; font.weight: Font.DemiBold }
            RowLayout {
                spacing: Theme.unit
                ThemeTextField {
                    id: nameField
                    Layout.preferredWidth: 28 * Theme.unit
                    placeholderText: "配置文件名"
                    onAccepted: namePopup.accept()
                }
                Label { text: ".json"; color: Theme.textDim }
            }
            Label {
                visible: namePopup.error !== ""
                text: namePopup.error
                color: Theme.danger
                font.pixelSize: Theme.caption
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.unit
                FlatButton { text: "取消"; onClicked: namePopup.close() }
                FlatButton { text: namePopup.copy ? "复制并加载" : "创建并加载"; accent: true; onClicked: namePopup.accept() }
            }
        }
    }
}
