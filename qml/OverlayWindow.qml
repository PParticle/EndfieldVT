import QtQuick

// The in-game overlay: a transparent, click-through window over the game's
// client area (src/gamewindow.h places and stacks it). Controls are drawn
// as in the preview window, with the 1280 x 720 design canvas scaled to the
// game's height and centered across its width, so a 21:9 or 16:10 screen
// keeps the layout's proportions.
Window {
    id: overlay
    property ListModel model
    property ListModel copies        // slots 2-4 of expanded controls (Main.copyStore)
    property var groups: ({})
    property var groupStates: ({})
    property alias showInBackground: tracker.showInBackground
    property alias enabled: tracker.enabled
    readonly property alias tracker: tracker

    title: "EndfieldVT 覆盖层"
    // Its own top-level window: declared inside the main window it would be
    // owned by it (minimized with it, kept above it).
    transientParent: null
    color: "transparent"
    // Frameless, no shadow, never focused, clicks pass through to the game.
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint
           | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    visible: false

    GameWindow {
        id: tracker
        overlay: overlay
    }

    Item {
        id: canvas
        // 16:9 in the middle of the client area, as tall as the game.
        readonly property real designScale: Math.min(overlay.width / 1280, overlay.height / 720)
        width: 1280 * designScale
        height: 720 * designScale
        anchors.centerIn: parent

        Repeater {
            // Kept while hidden: a "play once" effect must not replay on Alt+Tab.
            model: overlay.model
            delegate: ControlView {
                designScale: canvas.designScale
                groups: overlay.groups
                groupStates: overlay.groupStates
                live: true
                count: overlay.model ? overlay.model.count : 0
            }
        }
        Repeater {
            model: overlay.copies
            delegate: ControlView {
                required property int slotOfCopy
                required property int copyOf
                copySlot: slotOfCopy
                designScale: canvas.designScale
                groups: overlay.groups
                groupStates: overlay.groupStates
                live: true
                count: overlay.model ? overlay.model.count : 0
                z: count - copyOf
            }
        }
    }
}
