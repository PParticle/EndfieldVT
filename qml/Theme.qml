pragma Singleton
import QtQuick

// Design tokens. Every size is a multiple of the 4 px unit and nearly all
// of the 8 px grid; colors are the only place a hex value appears.
QtObject {
    // Spacing
    readonly property int unit: 8
    readonly property int gap: 16          // between related blocks, list inset
    readonly property int pagePad: 32      // content padding: 2 x gap
    readonly property int radius: 4

    // Frame
    readonly property int titleBarH: 48    // 6 units
    readonly property int statusBarH: 24   // half the title bar
    readonly property int sidebarW: 320    // 1/4 of the default 1280 width
    readonly property int windowW: 1280
    readonly property int windowH: 800     // 16:10
    readonly property int rowH: 32         // list rows, inputs

    // Type scale (px), ratio ~1.25: caption, body, heading, title
    readonly property int caption: 12
    readonly property int body: 14
    readonly property int heading: 16
    readonly property int title: 20

    // Colors: three surface steps from the darkest (frame) to the lightest
    // (raised cards), one accent.
    readonly property color frame: "#141518"     // title bar, status bar
    readonly property color base: "#1a1c20"      // content area
    readonly property color surface: "#202328"   // sidebar, panels
    readonly property color raised: "#272b31"    // cards, hover
    readonly property color line: "#2e3238"      // 1 px dividers
    readonly property color lineStrong: "#3a3f47"
    readonly property color text: "#e6e8eb"
    readonly property color textDim: "#9aa1ab"
    readonly property color textFaint: "#636a74"
    readonly property color accent: "#f2c94c"    // Endfield yellow
    readonly property color danger: "#e5484d"    // close button
}
