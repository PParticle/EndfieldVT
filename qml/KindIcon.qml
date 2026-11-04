import QtQuick

// 16 px glyph for a control kind, used in the sidebar tree.
Item {
    id: glyph
    property string kind
    property color color: Theme.textDim
    implicitWidth: 2 * Theme.unit
    implicitHeight: 2 * Theme.unit

    // icon: a square with its top-left quarter lit, as a cooldown sweep
    Item {
        anchors.fill: parent
        visible: glyph.kind === "icon"
        Rectangle { x: 2; y: 2; width: 12; height: 12; color: "transparent"; border.color: glyph.color }
        Rectangle { x: 4; y: 4; width: 4; height: 4; color: glyph.color }
    }
    // bar: a track, two thirds full
    Item {
        anchors.fill: parent
        visible: glyph.kind === "bar"
        Rectangle { x: 1; y: 6; width: 14; height: 4; color: "transparent"; border.color: glyph.color }
        Rectangle { x: 1; y: 6; width: 9; height: 4; color: glyph.color }
    }
    // text: a capital T
    Item {
        anchors.fill: parent
        visible: glyph.kind === "text"
        Rectangle { x: 3; y: 3; width: 10; height: 2; color: glyph.color }
        Rectangle { x: 7; y: 3; width: 2; height: 10; color: glyph.color }
    }
    // group: a folder
    Item {
        anchors.fill: parent
        visible: glyph.kind === "group"
        Rectangle { x: 1; y: 3; width: 6; height: 2; color: glyph.color }
        Rectangle { x: 1; y: 4; width: 14; height: 9; color: "transparent"; border.color: glyph.color }
    }
}
