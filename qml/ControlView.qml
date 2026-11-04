import QtQuick
import QtQuick.Controls.Basic

// One control drawn on a design canvas (1280 x 720 units, `designScale`
// pixels per unit): the preview window and the in-game overlay both use it, as a
// Repeater delegate over the control model. `live`: follow load and
// triggers; off draws every control as styled (for arranging). `selected`
// keeps a hidden control faintly visible and outlined.
Item {
    id: object
    property real designScale: 1   // not `scale`: that is Item's own transform
    // Main.groups: each group's scale, opacity and scale origin, by uid.
    property var groups: ({})
    // The preview window: a selected group shows its frame and can be dragged.
    property bool editing: false
    property bool live: true
    property bool selected: false
    property int count: 1          // controls in the model, for stacking order
    required property int index
    required property string uid
    required property string kind
    required property string parentId
    required property real posX
    required property real posY
    required property real boxWidth
    required property real boxHeight
    required property string shape
    required property real shapeAngle
    required property real iconSize
    required property string borderColor
    required property real borderWidth
    required property real borderOpacity
    required property string fillColor
    required property real fillOpacity
    required property string triggers
    required property bool showTimer
    required property bool showStacks
    required property string barStyle        // "ring" | "rect"
    required property string barDirection    // rect: "leftToRight" | "rightToLeft" | "bottomToTop" | "topToBottom"; ring: "leftToRight" = clockwise
    required property real ringGap           // degrees cut out of the ring, centered at the bottom (before rotation)
    required property real ringOuter         // ring radii, design px
    required property real ringInner
    required property real barLength         // rect size, design px
    required property real barThickness
    required property real barRotation       // degrees clockwise, both styles
    required property string progressColor
    required property real progressOpacity
    required property real barSmooth         // ms to ease the progress to a new value, 0 = jump
    required property real barSegments       // equal parts, 0 = none, -1 = one per SP cell
    required property real segmentGap        // design px between parts
    required property string ringCap         // "butt" | "round"
    required property string valueAnchor     // "center" | "top" | "bottom" | "left" | "right" | corners ("topLeft"...)
    required property real valueSize         // design px
    required property string valueColor
    required property real valueOffsetX
    required property real valueOffsetY
    required property string textMode        // "static" | "dynamic" | "both" (qml/Triggers.qml, composeText)
    required property string staticText
    required property string textSource
    required property string textColor
    required property real textOpacity
    required property real fontSize          // design px
    required property bool fontBold
    required property string textAlign       // "left" | "center" | "right"
    required property bool textOutline
    required property string outlineColor
    // A member is scaled around its group's origin; a group's own frame too.
    readonly property var group: groups[kind === "group" ? uid : parentId] || null
    readonly property real groupScale: group ? group.scale : 1
    readonly property real drawScale: designScale * groupScale
    // What the triggers draw, and whether they hide it (qml/Triggers.qml).
    property var runState: ({})
    readonly property bool usesTriggers: kind === "icon" || kind === "bar" || kind === "text"

    readonly property var state: {
        BridgeReader.tick
        return kind === "icon" ? Triggers.run(BridgeReader, triggers, runState, Date.now())
             : kind === "bar" ? Triggers.runBar(BridgeReader, triggers)
             : kind === "text" ? textState()
             : ({ effect: "none", progress: 1, startAngle: 0, hidden: false, playing: false, stacks: 0 })
    }
    // A text: hidden by its triggers or by a missing value.
    function textState() {
        const t = Triggers.composeText(BridgeReader, textMode, staticText, textSource, !live)
        const r = Triggers.runText(BridgeReader, triggers)
        return { effect: "none", progress: 1, startAngle: 0, playing: false, stacks: 0, text: t.text,
                 hidden: t.hidden || r.hidden }
    }
    // Animations need frames between bridge reads.
    FrameAnimation { running: object.state.playing === true; onTriggered: object.runState = object.runState }
    readonly property bool follows: live && usesTriggers
    readonly property bool shown: !follows || state.hidden !== true || selected
    // Hidden by its triggers, but selected: drawn faint so it can be found.
    // Bars' state has no effect / angle / hidden: default each.
    readonly property bool ghost: follows && state.hidden === true
    readonly property string drawEffect: follows ? (state.effect || "none") : "none"
    readonly property real drawProgress: follows ? state.progress : 1
    readonly property real drawStart: follows ? (Number(state.startAngle) || 0) : 0
    readonly property string drawSpread: follows ? (state.spread || "overlay") : "overlay"
    readonly property string drawSpreadColor: follows ? (state.spreadColor || "#ffffff") : "#ffffff"
    readonly property real drawSpreadOpacity: follows && state.spreadOpacity !== undefined ? state.spreadOpacity : 70
    // A group draws only its frame (its members' bounds, Main.groups), in
    // the preview, while selected.
    readonly property bool isGroup: kind === "group"
    visible: isGroup ? editing && selected && group !== null && group.bw > 0 : shown
    opacity: (ghost ? 0.35 : 1) * (group && !isGroup ? group.opacity : 1)
    x: (isGroup ? (group ? group.bx : 0) : group ? group.ox + (posX - group.ox) * groupScale : posX) * designScale
    y: (isGroup ? (group ? group.by : 0) : group ? group.oy + (posY - group.oy) * groupScale : posY) * designScale
    width: (isGroup ? (group ? group.bw : 0) : boxWidth * groupScale) * designScale
    height: (isGroup ? (group ? group.bh : 0) : boxHeight * groupScale) * designScale
    // The sidebar's top row on top; a group's frame under its members (all
    // above 0), so they stay clickable inside it.
    z: isGroup ? 0 : count - index

    Canvas {
        id: iconCanvas
        anchors.fill: parent; anchors.margins: 8 * object.drawScale
        visible: object.kind === "icon"; antialiasing: true
        property string shape: object.shape
        property real iconRotation: object.shapeAngle
        property real iconSize: object.iconSize
        property string iconBorderColor: object.borderColor
        property real iconBorderWidth: object.borderWidth
        property real iconBorderOpacity: object.borderOpacity
        property string iconFillColor: object.fillColor
        property real iconFillOpacity: object.fillOpacity
        property string iconEffect: object.drawEffect
        property real iconEffectProgress: object.drawProgress
        property real iconStartAngle: object.drawStart
        property string iconSpread: object.drawSpread
        property string iconSpreadColor: object.drawSpreadColor
        property real iconSpreadOpacity: object.drawSpreadOpacity
        onShapeChanged: requestPaint()
        onIconRotationChanged: requestPaint()
        onIconSizeChanged: requestPaint()
        onIconBorderColorChanged: requestPaint()
        onIconBorderWidthChanged: requestPaint()
        onIconBorderOpacityChanged: requestPaint()
        onIconFillColorChanged: requestPaint()
        onIconFillOpacityChanged: requestPaint()
        onIconEffectChanged: requestPaint()
        onIconEffectProgressChanged: requestPaint()
        onIconStartAngleChanged: requestPaint()
        onIconSpreadChanged: requestPaint()
        onIconSpreadColorChanged: requestPaint()
        onIconSpreadOpacityChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function traceShape(context, name, radius) {
            context.beginPath()
            if (name === "circle") {
                context.arc(0, 0, radius, 0, Math.PI * 2, false)
            } else {
                var sides = name === "triangle" ? 3 : name === "hexagon" ? 6 : 4
                var start = sides === 4 ? -Math.PI / 4 : -Math.PI / 2
                for (var i = 0; i < sides; ++i) {
                    var angle = start + Math.PI * 2 * i / sides
                    var vertexRadius = name === "square" ? radius * Math.SQRT2 : radius
                    var px = Math.cos(angle) * vertexRadius, py = Math.sin(angle) * vertexRadius
                    if (i === 0) context.moveTo(px, py)
                    else context.lineTo(px, py)
                }
                context.closePath()
            }
        }
        // Effects, at progress p (0-1):
        //   clockwise / counterclockwise: the fill sweeps from the start angle
        //     (the rest of the fill is drawn faint, so the shape stays readable)
        //   radial, spread "overlay": the icon as styled, with a copy of its
        //     shape in the spread color growing from the center over it
        //   radial, spread "self": the icon itself grows from nothing
        onPaint: {
            const g = getContext("2d")
            g.reset()
            g.clearRect(0, 0, width, height)
            const p = Math.max(0, Math.min(1, iconEffectProgress))
            const full = Math.min(width, height) * iconSize / 100 / 2
            const selfGrow = iconEffect === "radial" && iconSpread === "self"
            const radius = selfGrow ? full * p : full
            if (radius <= 0.25) return
            const sweep = iconEffect === "clockwise" || iconEffect === "counterclockwise"
            const fillAlpha = iconFillOpacity / 100
            g.save()
            g.translate(width / 2, height / 2)
            g.rotate(iconRotation * Math.PI / 180)

            // Fill
            traceShape(g, shape, radius)
            g.save()
            g.clip()
            g.fillStyle = iconFillColor
            g.globalAlpha = fillAlpha * (sweep ? 0.18 : 1)
            g.fillRect(-radius * 2, -radius * 2, radius * 4, radius * 4)
            if (sweep && p > 0) {
                g.globalAlpha = fillAlpha
                // Undo the shape's rotation so 0 deg is straight up on screen.
                g.rotate(-iconRotation * Math.PI / 180)
                const start = (iconStartAngle - 90) * Math.PI / 180
                const turn = Math.PI * 2 * p * (iconEffect === "counterclockwise" ? -1 : 1)
                g.beginPath()
                g.moveTo(0, 0)
                g.arc(0, 0, radius * 3, start, start + turn, turn < 0)
                g.closePath()
                g.fill()
            }
            if (iconEffect === "radial" && iconSpread === "overlay" && p > 0) {
                // The same shape, scaled from the center, in its own color.
                g.fillStyle = iconSpreadColor
                g.globalAlpha = iconSpreadOpacity / 100
                traceShape(g, shape, radius * p)
                g.fill()
            }
            g.restore()

            // Border, thinned with the shape while it grows from nothing.
            traceShape(g, shape, radius)
            g.lineWidth = iconBorderWidth * object.drawScale * (selfGrow ? Math.max(p, 0.15) : 1)
            g.strokeStyle = iconBorderColor
            g.globalAlpha = iconBorderOpacity / 100
            if (g.lineWidth > 0) g.stroke()
            g.restore()
        }
    }
    // The value (time left, SP...) and stacks (bottom right), from the
    // driving trigger; each can be turned off in 外观. Above both canvases.
    // The value sits at its anchor in the box, moved by its offset.
    Label {
        id: valueLabel
        z: 1
        visible: object.kind !== "text" && object.follows && object.showTimer && (object.state.text || "") !== ""
        readonly property string a: object.valueAnchor
        readonly property real pad: 4 * object.drawScale
        x: (a.endsWith("Left") || a === "left" ? pad
            : a.endsWith("Right") || a === "right" ? parent.width - width - pad
            : (parent.width - width) / 2) + object.valueOffsetX * object.drawScale
        y: (a.startsWith("top") ? pad
            : a.startsWith("bottom") ? parent.height - height - pad
            : (parent.height - height) / 2) + object.valueOffsetY * object.drawScale
        text: object.state.text || ""
        color: object.valueColor
        style: Text.Outline
        styleColor: Theme.frame
        font.pixelSize: Math.max(6, object.valueSize * object.drawScale)
        font.weight: Font.DemiBold
    }
    Label {
        z: 1
        visible: object.follows && object.showStacks && object.state.stacks > 1
        anchors { right: parent.right; bottom: parent.bottom; margins: 10 * object.drawScale }
        text: object.state.stacks
        color: Theme.text
        style: Text.Outline
        styleColor: Theme.frame
        font.pixelSize: Math.max(10, Theme.heading * object.drawScale)
        font.weight: Font.DemiBold
    }
    // A bar: its frame (fill + border) and, separately, the progress over
    // the fill area. Progress off (live off): drawn at 62% for arranging.
    Canvas {
        id: barCanvas
        anchors.fill: parent
        visible: object.kind === "bar"
        antialiasing: true
        // Eased toward each new reading (bridge reads come every 100 ms).
        readonly property real target: object.follows ? object.state.progress : 0.62
        property real progress: target
        Behavior on progress {
            enabled: object.barSmooth > 0
            NumberAnimation { duration: object.barSmooth; easing.type: Easing.OutQuad }
        }
        // Parts: a fixed count, or one per SP cell (from the bridge).
        readonly property int parts: {
            if (object.barSegments >= 0) return Math.round(object.barSegments)
            const t = BridgeReader.team
            return t.atbPerCell > 0 ? Math.round(t.atbMax / t.atbPerCell) : 0
        }
        property var look: [object.barStyle, object.barDirection, object.ringGap, object.ringOuter, object.ringInner,
                            object.barLength, object.barThickness, object.barRotation,
                            object.progressColor, object.progressOpacity, object.borderColor, object.borderWidth,
                            object.borderOpacity, object.fillColor, object.fillOpacity, object.drawScale,
                            parts, object.segmentGap, object.ringCap]
        onProgressChanged: requestPaint()
        onLookChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const g = getContext("2d")
            g.reset()
            g.clearRect(0, 0, width, height)
            const p = Math.max(0, Math.min(1, progress))
            const s = object.drawScale
            const border = object.borderWidth * s
            // The box is fitted around the rotated shape (Main.fitBarBox):
            // draw from its center, turned by the rotation. The border sits
            // on the shape's outline, half inside and half outside.
            g.translate(width / 2, height / 2)
            g.rotate((object.barRotation || 0) * Math.PI / 180)
            if (object.barStyle === "rect") {
                // Progress grows from the start edge of the direction.
                const dir = object.barDirection
                const horizontal = dir === "leftToRight" || dir === "rightToLeft"
                const L = object.barLength * s, T = object.barThickness * s
                const w = Math.max(0, L - border), h = Math.max(0, T - border)
                const x0 = -w / 2, y0 = -h / 2
                g.globalAlpha = object.fillOpacity / 100
                g.fillStyle = object.fillColor
                g.fillRect(x0, y0, w, h)
                if (p > 0) {
                    g.globalAlpha = object.progressOpacity / 100
                    g.fillStyle = object.progressColor
                    if (horizontal) {
                        const pw = w * p
                        g.fillRect(dir === "leftToRight" ? x0 : x0 + w - pw, y0, pw, h)
                    } else {
                        const ph = h * p
                        g.fillRect(x0, dir === "topToBottom" ? y0 : y0 + h - ph, w, ph)
                    }
                }
                // Parts: cut gaps across the band, inside the border.
                const n = parts, cut = object.segmentGap * s
                if (n > 1 && cut > 0) {
                    g.globalCompositeOperation = "destination-out"
                    g.globalAlpha = 1
                    for (let i = 1; i < n; ++i) {
                        if (horizontal) g.fillRect(x0 + w * i / n - cut / 2, y0, cut, h)
                        else g.fillRect(x0, y0 + h * i / n - cut / 2, w, cut)
                    }
                    g.globalCompositeOperation = "source-over"
                }
                if (border > 0) {
                    g.globalAlpha = object.borderOpacity / 100
                    g.strokeStyle = object.borderColor
                    g.lineWidth = border
                    g.strokeRect(-L / 2, -T / 2, L, T)
                }
                return
            }
            // Ring: the band between the inner and outer radius, an open arc
            // with the gap centered at the bottom (before rotation). Progress
            // runs from the gap's left end (clockwise) or right end.
            const R = object.ringOuter * s
            const r = Math.max(0, Math.min(object.ringInner * s, R - 1))
            const thick = R - r, mid = (R + r) / 2
            if (mid <= 0) return
            const gap = Math.max(0, Math.min(359, object.ringGap)) * Math.PI / 180
            const bottom = Math.PI / 2
            const start = bottom + gap / 2, span = Math.PI * 2 - gap
            // Round caps: an open arc is shortened by half its width at each
            // end, so the rounded end reaches where the flat end was.
            const round = object.ringCap === "round"
            const ring = (from, length, lineWidth, color, alpha) => {
                if (length <= 0 || lineWidth <= 0 || alpha <= 0) return
                let a = from, b = from + length
                const open = length < Math.PI * 2 - 1e-4
                if (round && open) {
                    const c = lineWidth / 2 / mid
                    if (length > 2 * c) { a += c; b -= c }
                    else { a = b = from + length / 2 } // too short: a dot
                }
                g.beginPath()
                g.arc(0, 0, mid, a, Math.max(b, a + 1e-4), false)
                g.lineWidth = lineWidth
                g.strokeStyle = color
                g.globalAlpha = alpha
                g.lineCap = round && open ? "round" : "butt"
                g.stroke()
            }
            // Inside the border: the band shrunk by half a border on every side
            // (the arc ends too, when there is a gap).
            const cap = gap > 0 ? border / 2 / mid : 0
            const inStart = start + cap, inSpan = span - 2 * cap, inThick = thick - border
            // Border: only the band's outline. Draw a wider, slightly longer
            // band, then cut the inside out, so a 0% fill leaves a hollow outline.
            if (border > 0) {
                ring(start - cap, span + 2 * cap, thick + border, object.borderColor, object.borderOpacity / 100)
                if (inThick > 0 && inSpan > 0) {
                    g.globalCompositeOperation = "destination-out"
                    ring(inStart, inSpan, inThick, "#000000", 1)
                    g.globalCompositeOperation = "source-over"
                }
            }
            if (inThick <= 0 || inSpan <= 0) return
            ring(inStart, inSpan, inThick, object.fillColor, object.fillOpacity / 100)
            if (p > 0) {
                const clockwise = object.barDirection !== "rightToLeft"
                const length = inSpan * p
                ring(clockwise ? inStart : inStart + inSpan - length, length, inThick, object.progressColor, object.progressOpacity / 100)
            }
            // Parts: radial gaps through the band, inside the border.
            const n = parts, cut = object.segmentGap * s
            if (n > 1 && cut > 0) {
                g.globalCompositeOperation = "destination-out"
                g.globalAlpha = 1
                g.lineWidth = cut
                g.lineCap = "butt"
                const closed = gap === 0
                for (let i = closed ? 0 : 1; i < n; ++i) {
                    const t = inStart + inSpan * i / n
                    g.beginPath()
                    g.moveTo(Math.cos(t) * (mid - inThick / 2 - 1), Math.sin(t) * (mid - inThick / 2 - 1))
                    g.lineTo(Math.cos(t) * (mid + inThick / 2 + 1), Math.sin(t) * (mid + inThick / 2 + 1))
                    g.stroke()
                }
                g.globalCompositeOperation = "source-over"
            }
        }
    }
    // A text: its static part and / or a live value, in the box,
    // vertically centered. Long text runs over the box rather than wrapping.
    Text {
        visible: object.kind === "text"
        anchors.fill: parent
        horizontalAlignment: object.textAlign === "left" ? Text.AlignLeft
                           : object.textAlign === "right" ? Text.AlignRight : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: object.kind === "text" ? object.state.text : ""
        color: object.textColor
        opacity: object.textOpacity / 100
        style: object.textOutline ? Text.Outline : Text.Normal
        styleColor: object.outlineColor
        font.pixelSize: Math.max(1, object.fontSize * object.drawScale)
        font.bold: object.fontBold
    }
    // A selected group in the preview: the bounds of its members.
    Rectangle {
        visible: object.isGroup
        anchors.fill: parent
        anchors.margins: -4
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
        border.width: 1
        border.color: Theme.accent
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        visible: object.selected && !object.isGroup
        color: "transparent"
        border.width: 1
        border.color: Theme.accent
    }
}
