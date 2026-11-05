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
    // Main.groupStates: what each group's triggers say now, by uid.
    property var groupStates: ({})
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
    required property bool barTrail          // 扣血残影: a drop leaves the lost part for a while
    required property string trailColor
    required property real trailOpacity
    required property real trailHold         // ms the lost part stays
    required property real trailShrink       // ms it then takes to shrink away
    required property string valueAnchor     // "center" | "top" | "bottom" | "left" | "right" | corners ("topLeft"...)
    required property real valueSize         // design px
    required property string valueColor
    required property real valueOffsetX
    required property real valueOffsetY
    required property string buffUnit        // a buff list (BridgeReader.buffList)
    required property string buffKind
    required property string buffSource
    required property string buffOnly
    required property string buffExclude
    required property real buffMax
    required property real buffCell          // design px, square
    required property real buffSpacing
    required property string buffGrow        // "right" | "left" | "down" | "up": where new ones go
    required property string buffLabel       // "short" | "full" | "none": the buff id in the cell
    required property string debuffColor
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
    required property string expandDir       // 每个小队成员: "down" | "up" | "right" | "left"
    required property real expandGap
    // A copy of an expanded control (Main.copyStore): squad slot 2-4; 0 = the
    // control itself, which is slot 1 when expanded.
    property int copySlot: 0
    readonly property bool expanded: Triggers.usesEach({ kind: kind, buffUnit: buffUnit, triggers: triggers, textSource: textSource })
    readonly property int slot: expanded ? Math.max(1, copySlot) : 0
    // What the triggers read: the bridge, or with "each" this copy's slot.
    readonly property var reader: slot > 0 ? Triggers.slotReader(slot) : BridgeReader
    readonly property var copyOffset: slot > 1 ? Triggers.expandOffset({ expandDir: expandDir, expandGap: expandGap,
                                                                         boxWidth: boxWidth, boxHeight: boxHeight }, slot)
                                               : ({ x: 0, y: 0 })
    // An expanded copy whose slot has no operator (a squad of 3) is not drawn.
    readonly property bool slotEmpty: {
        BridgeReader.tick
        return slot > 0 && (BridgeReader.status === "online" || BridgeReader.status === "stale")
               && !BridgeReader.evaluate({ type: "hp", unit: "slot" + slot, op: "any", value: 0 }).available
    }
    // A member is scaled around its group's origin; a group's own frame too.
    readonly property var group: groups[kind === "group" ? uid : parentId] || null
    readonly property real groupScale: group ? group.scale : 1
    readonly property real drawScale: designScale * groupScale
    // What the triggers draw, and whether they hide it (qml/Triggers.qml).
    property var runState: ({})
    readonly property bool usesTriggers: kind !== "group"

    readonly property var state: {
        BridgeReader.tick
        return kind === "icon" ? Triggers.run(reader, triggers, runState, Date.now())
             : kind === "bar" ? Triggers.runBar(reader, triggers)
             : kind === "text" ? textState()
             : kind === "buffs" ? Object.assign({ effect: "none", progress: 1, startAngle: 0, playing: false, stacks: 0 },
                                                Triggers.runText(reader, triggers))
             : ({ effect: "none", progress: 1, startAngle: 0, hidden: false, playing: false, stacks: 0 })
    }
    // A text: hidden by its triggers or by a missing value.
    function textState() {
        const t = Triggers.composeText(reader, textMode, staticText, textSource, !live)
        const r = Triggers.runText(reader, triggers)
        return { effect: "none", progress: 1, startAngle: 0, playing: false, stacks: 0, text: t.text,
                 hidden: t.hidden || r.hidden, style: r.style }
    }
    // Animations need frames between bridge reads.
    FrameAnimation { running: object.state.playing === true; onTriggered: object.runState = object.runState }
    readonly property bool follows: live && usesTriggers
    // The group's triggers, for a member: they can hide it, and an icon with
    // no active effect of its own plays the group's.
    readonly property var groupState: follows && parentId !== "" ? groupStates[parentId] || null : null
    readonly property bool hiddenNow: state.hidden === true || (groupState !== null && groupState.hidden === true) || slotEmpty
    readonly property bool shown: !follows || !hiddenNow || selected
    // How it comes and goes (Triggers.parseMotion): its own, else its group's.
    readonly property var motion: {
        const own = Triggers.parseTriggers(triggers).motion
        return Triggers.hasMotion(own) || !group || !group.motion ? own : group.motion
    }
    // 1 = fully there, 0 = gone: animated when the triggers show / hide it,
    // by the appear / disappear motion. Arranging (live off): always 1.
    readonly property bool wanted: !follows || !hiddenNow
    property real presence: 1          // set on completion, then only by onWantedChanged
    readonly property string motionNow: wanted ? motion.appear : motion.disappear
    NumberAnimation {
        id: presenceAnim
        target: object; property: "presence"
    }
    onWantedChanged: {
        presenceAnim.stop()
        const to = wanted ? 1 : 0
        if (!follows || motionNow === "none" || motion.ms <= 0) { presence = to; return }
        presenceAnim.to = to
        // Partway (shown again while going): the rest of the way, in proportion.
        presenceAnim.duration = Math.max(1, motion.ms * Math.abs(to - presence))
        presenceAnim.easing.type = motionNow === "pop" ? (wanted ? Easing.OutBack : Easing.InBack)
                                 : wanted ? Easing.OutCubic : Easing.InCubic
        presenceAnim.start()
    }
    // Selected while hidden: drawn faint, not animated away.
    readonly property real drawPresence: selected && ghost ? 1 : presence
    // Hidden by triggers, but selected: drawn faint so it can be found.
    readonly property bool ghost: follows && hiddenNow
    // Where the effect comes from. Bars' state has no effect / angle: default each.
    readonly property var fx: kind === "icon" && (state.effect || "none") === "none" && groupState !== null
                              && (groupState.effect || "none") !== "none" ? groupState : state
    readonly property string drawEffect: follows ? (fx.effect || "none") : "none"
    readonly property real drawProgress: follows ? fx.progress : 1
    readonly property real drawStart: follows ? (Number(fx.startAngle) || 0) : 0
    readonly property string drawSpread: follows ? (fx.spread || "overlay") : "overlay"
    readonly property string drawSpreadColor: follows ? (fx.spreadColor || "#ffffff") : "#ffffff"
    readonly property real drawSpreadOpacity: follows && fx.spreadOpacity !== undefined ? fx.spreadOpacity : 70
    // Trigger styles (Triggers.styleOf): the group's, the member's own on top.
    // Arranging (live off) shows the control as styled.
    readonly property var style: follows ? Triggers.mergeStyle(groupState ? groupState.style : null, state.style) : ({})
    readonly property bool tinted: style.tint !== undefined
    readonly property string barColor: tinted ? String(style.tint) : progressColor
    readonly property color tint: tinted ? style.tint : "transparent"
    readonly property real styleAlpha: style.alpha !== undefined ? style.alpha / 100 : 1
    readonly property string glowType: style.glow || "none"
    readonly property bool glowOn: glowType !== "none" && !isGroup
    readonly property color glowColor: style.glowColor || "#ffd166"
    readonly property real glowSize: style.glowSize || 8          // design px
    readonly property string loopType: style.loop || "none"
    // 0 -> 1 over loopSeconds, repeating, while a loop or a moving glow runs.
    property real loopPhase: 0
    NumberAnimation on loopPhase {
        id: loopAnim
        from: 0; to: 1
        loops: Animation.Infinite
        duration: Math.max(100, (object.style.loopSeconds || 1) * 1000)
        running: object.visible && object.loopType !== "none"
        onRunningChanged: if (!running) object.loopPhase = 0
        onDurationChanged: if (running) restart()
    }
    // A moving glow goes round once every 2 s, whatever the loop's own time.
    property real glowPhase: 0
    NumberAnimation on glowPhase {
        from: 0; to: 1
        loops: Animation.Infinite
        duration: 2000
        running: object.visible && (object.glowType === "flow" || object.glowType === "pixel")
    }
    // A group draws only its frame (its members' bounds, Main.groups), in
    // the preview, while selected.
    readonly property bool isGroup: kind === "group"
    visible: isGroup ? editing && selected && group !== null && group.bw > 0 : shown || presence > 0.001
    opacity: (ghost && selected ? 0.35 : 1) * (group && !isGroup ? group.opacity : 1)
    readonly property real atX: posX + copyOffset.x
    readonly property real atY: posY + copyOffset.y
    x: (isGroup ? (group ? group.bx : 0) : group ? group.ox + (atX - group.ox) * groupScale : atX) * designScale
    y: (isGroup ? (group ? group.by : 0) : group ? group.oy + (atY - group.oy) * groupScale : atY) * designScale
    width: (isGroup ? (group ? group.bw : 0) : boxWidth * groupScale) * designScale
    height: (isGroup ? (group ? group.bh : 0) : boxHeight * groupScale) * designScale
    // The sidebar's top row on top; a group's frame under its members (all
    // above 0), so they stay clickable inside it.
    z: isGroup ? 0 : count - index

    ListModel { id: buffCells }
    readonly property var buffSpec: ({ unit: buffUnit, kind: buffKind, source: buffSource, only: buffOnly,
                                       exclude: buffExclude, max: buffMax })
    readonly property var buffSamples: [
        { key: -1, buffId: "buff_sample_atk_up", isDebuff: false, stacks: 3, timeLeft: 8.2, duration: 12, progress: 0.68 },
        { key: -2, buffId: "buff_sample_shield", isDebuff: false, stacks: 1, timeLeft: -1, duration: -1, progress: 1 },
        { key: -3, buffId: "debuff_sample_burn", isDebuff: true, stacks: 1, timeLeft: 2.4, duration: 6, progress: 0.4 }
    ]
    function syncBuffs() {
        if (kind !== "buffs") return
        const list = live ? reader.buffList(buffSpec) : buffSamples.slice(0, Math.max(1, buffMax))
        const keys = list.map(b => b.key)
        for (let i = buffCells.count - 1; i >= 0; --i)
            if (!keys.includes(buffCells.get(i).key)) buffCells.remove(i)
        for (let i = 0; i < list.length; ++i) {
            const b = list[i]
            const row = { key: b.key, buffId: b.buffId, isDebuff: b.isDebuff, stacks: b.stacks, timeLeft: b.timeLeft, progress: b.progress }
            if (i < buffCells.count && buffCells.get(i).key === b.key) buffCells.set(i, row)
            else buffCells.insert(i, row)
        }
        while (buffCells.count > list.length) buffCells.remove(buffCells.count - 1)
    }
    Connections { target: BridgeReader; enabled: object.kind === "buffs"; function onTicked() { object.syncBuffs() } }
    onBuffSpecChanged: syncBuffs()
    onLiveChanged: syncBuffs()
    Component.onCompleted: {
        presence = wanted ? 1 : 0
        syncBuffs()
    }
    // Everything a control draws, in one item: a trigger's loop animation
    // (Triggers.loops) turns, scales and shakes it here, so the control's own
    // box, which the preview drags, and the selection outline stay put.
    Item {
        id: body
        anchors.fill: parent
        visible: !object.isGroup
        readonly property real wave: (1 - Math.cos(2 * Math.PI * object.loopPhase)) / 2   // 0 -> 1 -> 0
        readonly property string loop: object.loopType
        // Appearing / disappearing: p 0 -> 1 (pop overshoots past 1 a little).
        readonly property real p: object.drawPresence
        readonly property string m: object.motionNow
        readonly property real slide: m === "slide" ? (1 - p) * 24 * object.drawScale : 0
        readonly property string from: object.motion.from
        scale: (loop === "pulse" ? 1 + 0.12 * wave : 1) * (m === "pop" ? Math.max(0, p) : 1)
        rotation: loop === "spin" ? 360 * object.loopPhase : 0
        opacity: object.styleAlpha * (loop === "breathe" ? 1 - 0.75 * wave
                                     : loop === "blink" ? (object.loopPhase < 0.5 ? 1 : 0.1) : 1)
                 * (m === "none" ? 1 : Math.max(0, Math.min(1, m === "pop" ? p * 2 : p)))
        transform: Translate {
            x: (body.loop === "shake" ? Math.sin(2 * Math.PI * 4 * object.loopPhase) * 3 * object.drawScale : 0)
               + (body.from === "left" ? -body.slide : body.from === "right" ? body.slide : 0)
            y: body.from === "down" ? body.slide : body.from === "up" ? -body.slide : 0
        }

        // Glow (a trigger's style), behind everything the control draws, out
        // past its box by `pad`. It follows the control's outline: the icon's
        // shape, a bar's band, the text's glyphs or box, the buff cells.
        //   soft:  a blurred halo in glowColor outside the outline
        //   flow:  a bright dash running round the outline, over a faint line
        //   pixel: short dashes round it, marching along
        Canvas {
            id: glowCanvas
            readonly property real pad: (object.glowSize * 2 + 4) * object.drawScale
            x: -pad; y: -pad
            width: parent.width + 2 * pad; height: parent.height + 2 * pad
            visible: object.glowOn
            antialiasing: true
            property var look: [object.glowType, object.glowColor, object.glowSize, object.drawScale, object.kind,
                                object.shape, object.shapeAngle, object.iconSize, object.drawProgress, object.drawEffect,
                                object.drawSpread, object.borderWidth,
                                object.barStyle, object.barLength, object.barThickness, object.barRotation,
                                object.ringOuter, object.ringInner, object.ringGap, textItem.text, textItem.font.pixelSize,
                                textItem.contentWidth, textItem.contentHeight, buffCells.count, object.buffCell,
                                object.buffSpacing, object.buffGrow, object.width, object.height]
            readonly property real phase: object.glowPhase
            onLookChanged: if (visible) requestPaint()
            onPhaseChanged: if (visible && object.glowType !== "soft") requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            // Traces the control's outline, `grow` px out from it, in this
            // canvas; returns its length (for the dashes). Leaves the context
            // turned as the outline is, for the stroke that follows.
            function outline(g, grow) {
                const s = object.drawScale
                const cx = width / 2, cy = height / 2
                g.translate(cx, cy)
                if (object.kind === "icon") {
                    const full = (Math.min(object.width, object.height) - 16 * s) * object.iconSize / 100 / 2
                    const selfGrow = object.drawEffect === "radial" && object.drawSpread === "self"
                    const r0 = (selfGrow ? full * Math.max(0, Math.min(1, object.drawProgress)) : full)
                               + object.borderWidth * s / 2
                    g.rotate(object.shapeAngle * Math.PI / 180)
                    const sh = object.shape
                    // traceShape's radius: a circle's radius, a square's inner
                    // radius, a triangle's / hexagon's outer radius.
                    const r = sh === "triangle" ? r0 + grow * 2 : sh === "hexagon" ? r0 + grow / Math.cos(Math.PI / 6) : r0 + grow
                    iconCanvas.traceShape(g, sh, r)
                    return sh === "circle" ? 2 * Math.PI * r : sh === "triangle" ? 3 * Math.sqrt(3) * r
                         : sh === "hexagon" ? 6 * r : 8 * r
                }
                if (object.kind === "bar" && object.barStyle !== "rect") {
                    g.rotate((object.barRotation || 0) * Math.PI / 180)
                    const R = object.ringOuter * s + grow
                    const r = Math.max(0, object.ringInner * s - grow)
                    const gap = Math.max(0, Math.min(359, object.ringGap)) * Math.PI / 180
                    g.beginPath()
                    if (gap <= 0) {
                        g.arc(0, 0, R, 0, Math.PI * 2, false)
                        g.closePath()
                        g.moveTo(r, 0)
                        g.arc(0, 0, r, Math.PI * 2, 0, true)
                        g.closePath()
                        return 2 * Math.PI * (R + r)
                    }
                    const a = Math.PI / 2 + gap / 2, b = a + Math.PI * 2 - gap
                    g.arc(0, 0, R, a, b, false)
                    g.lineTo(Math.cos(b) * r, Math.sin(b) * r)
                    g.arc(0, 0, r, b, a, true)
                    g.closePath()
                    return (R + r) * (Math.PI * 2 - gap) + 2 * (R - r)
                }
                let w, h, x0, y0
                if (object.kind === "bar") {
                    g.rotate((object.barRotation || 0) * Math.PI / 180)
                    w = object.barLength * s; h = object.barThickness * s
                    x0 = -w / 2; y0 = -h / 2
                } else if (object.kind === "text") {
                    w = Math.min(object.width, textItem.contentWidth); h = Math.min(object.height, textItem.contentHeight)
                    const al = object.textAlign
                    x0 = al === "left" ? -object.width / 2 : al === "right" ? object.width / 2 - w : -w / 2
                    y0 = -h / 2
                } else if (object.kind === "buffs") {
                    const n = Math.max(1, buffCells.count)
                    const cell = object.buffCell * s, step = (object.buffCell + object.buffSpacing) * s
                    const along = cell + (n - 1) * step
                    const gw = object.buffGrow
                    const across = gw === "right" || gw === "left"
                    w = across ? along : cell; h = across ? cell : along
                    x0 = gw === "left" ? object.width / 2 - w : -object.width / 2
                    y0 = gw === "up" ? object.height / 2 - h : -object.height / 2
                } else {
                    w = object.width; h = object.height; x0 = -w / 2; y0 = -h / 2
                }
                g.beginPath()
                g.rect(x0 - grow, y0 - grow, w + 2 * grow, h + 2 * grow)
                return 2 * (w + h + 4 * grow)
            }
            onPaint: {
                const g = getContext("2d")
                g.reset()
                g.clearRect(0, 0, width, height)
                const s = object.drawScale, size = object.glowSize * s
                g.save()
                if (object.glowType === "soft") {
                    // The silhouette with a blurred shadow, then the silhouette cut
                    // out: only the halo outside it is left.
                    g.shadowColor = object.glowColor
                    g.shadowBlur = size * 1.5
                    g.fillStyle = object.glowColor
                    if (object.kind === "text") {
                        // The glyphs themselves: the halo hugs the letters.
                        g.font = (textItem.font.bold ? "bold " : "") + textItem.font.pixelSize + "px \"" + textItem.font.family + "\""
                        g.textBaseline = "middle"
                        g.textAlign = object.textAlign
                        const tx = object.textAlign === "left" ? glowCanvas.pad : object.textAlign === "right"
                                   ? width - glowCanvas.pad : width / 2
                        // Stroked thick under the shadow: thin glyphs alone give a weak halo.
                        g.strokeStyle = object.glowColor
                        g.lineWidth = Math.max(1, size / 3)
                        g.lineJoin = "round"
                        for (let i = 0; i < 3; ++i) { g.strokeText(textItem.text, tx, height / 2); g.fillText(textItem.text, tx, height / 2) }
                        // The letters cut out, as for shapes: the text's own
                        // opacity shows what is under it, not the glow color.
                        g.shadowBlur = 0
                        g.globalCompositeOperation = "destination-out"
                        g.strokeText(textItem.text, tx, height / 2)
                        g.fillText(textItem.text, tx, height / 2)
                        g.restore()
                        return
                    }
                    outline(g, 0)
                    for (let i = 0; i < 2; ++i) g.fill()   // twice: a stronger halo
                    g.shadowBlur = 0
                    g.globalCompositeOperation = "destination-out"
                    g.fill()
                    g.restore()
                    return
                }
                const pixel = object.glowType === "pixel"
                // Out past the border, so the control's own border does not cover it.
                const length = outline(g, (object.kind === "bar" ? object.borderWidth * s / 2 : 0) + Math.max(2, size * 0.6))
                g.strokeStyle = object.glowColor
                g.lineJoin = "round"
                if (pixel) {
                    // About one dash per 12 design px, a whole number of them so
                    // the pattern closes on itself.
                    const n = Math.max(4, Math.round(length / (12 * s)))
                    const step = length / n
                    g.lineWidth = Math.max(1.5, size / 3)
                    g.setLineDash([step * 0.55 / g.lineWidth, step * 0.45 / g.lineWidth])
                    g.lineDashOffset = -glowCanvas.phase * step * 2 / g.lineWidth
                    g.stroke()
                } else {
                    g.lineWidth = Math.max(1, size / 4)
                    g.globalAlpha = 0.3
                    g.stroke()
                    // The dash: a quarter of the way round, bright.
                    g.globalAlpha = 1
                    g.lineWidth = Math.max(1.5, size / 2.5)
                    g.shadowColor = object.glowColor
                    g.shadowBlur = size
                    g.lineCap = "round"
                    const dash = length / 4
                    g.setLineDash([dash / g.lineWidth, (length - dash) / g.lineWidth])
                    g.lineDashOffset = -glowCanvas.phase * length / g.lineWidth
                    g.stroke()
                }
                g.restore()
            }
        }
        Canvas {
            id: iconCanvas
            anchors.fill: parent; anchors.margins: 8 * object.drawScale
            visible: object.kind === "icon"; antialiasing: true
            property string shape: object.shape
            property real iconRotation: object.shapeAngle
            property real iconSize: object.iconSize
            property string iconBorderColor: object.tinted ? object.tint : object.borderColor
            property real iconBorderWidth: object.borderWidth
            property real iconBorderOpacity: object.borderOpacity
            property string iconFillColor: object.tinted ? object.tint : object.fillColor
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
            // 扣血残影: `trail` stays where the progress was when it drops, holds
            // for trailHold ms, then shrinks to it; on a rise it is drawn only
            // where it is above the (eased) progress, so it never leads it.
            // `trailing`: a drop is being shown; otherwise the trail just rides on
            // the progress (a rise eases up with it, never ahead).
            property real trail: target
            property bool trailing: false
            onTargetChanged: {
                if (object.barTrail && target < progress - 1e-6) {
                    if (!trailing) { trail = progress; trailing = true }
                    if (!trailAnim.running) trailHold.restart()
                } else if (target >= trail) {
                    trailAnim.stop()
                    trailHold.stop()
                    trailing = false
                }
            }

            Timer {
                id: trailHold
                interval: Math.max(0, object.trailHold)
                onTriggered: { trailAnim.to = barCanvas.target; trailAnim.restart() }
            }
            NumberAnimation {
                id: trailAnim
                target: barCanvas; property: "trail"
                duration: Math.max(1, object.trailShrink)
                easing.type: Easing.InOutQuad
                // A drop during the shrink: hold again, then shrink to the new value.
                onFinished: {
                    if (barCanvas.trail > barCanvas.target + 1e-6) trailHold.restart()
                    else barCanvas.trailing = false
                }
            }
            onTrailChanged: requestPaint()
            // Parts: a fixed count, or one per SP cell (from the bridge).
            readonly property int parts: {
                if (object.barSegments >= 0) return Math.round(object.barSegments)
                const t = BridgeReader.team
                return t.atbPerCell > 0 ? Math.round(t.atbMax / t.atbPerCell) : 0
            }
            property var look: [object.barStyle, object.barDirection, object.ringGap, object.ringOuter, object.ringInner,
                                object.barLength, object.barThickness, object.barRotation,
                                object.barColor, object.progressOpacity, object.borderColor, object.borderWidth,
                                object.borderOpacity, object.fillColor, object.fillOpacity, object.drawScale,
                                parts, object.segmentGap, object.ringCap, object.barTrail, object.trailColor, object.trailOpacity]
            onProgressChanged: {
                if (!trailing) trail = progress
                requestPaint()
            }
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
                    // The lost part, between the progress and the trail.
                    const tp = object.barTrail ? Math.max(p, Math.min(1, trail)) : p
                    if (tp > p) {
                        g.globalAlpha = object.trailOpacity / 100
                        g.fillStyle = object.trailColor
                        if (horizontal) {
                            const tw = w * tp
                            g.fillRect(dir === "leftToRight" ? x0 : x0 + w - tw, y0, tw, h)
                        } else {
                            const th = h * tp
                            g.fillRect(x0, dir === "topToBottom" ? y0 : y0 + h - th, w, th)
                        }
                    }
                    if (p > 0) {
                        g.globalAlpha = object.progressOpacity / 100
                        g.fillStyle = object.barColor
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
                const clockwise = object.barDirection !== "rightToLeft"
                const tp = object.barTrail ? Math.max(p, Math.min(1, trail)) : p
                if (tp > p) {
                    const length = inSpan * tp
                    ring(clockwise ? inStart : inStart + inSpan - length, length, inThick, object.trailColor, object.trailOpacity / 100)
                }
                if (p > 0) {
                    const length = inSpan * p
                    ring(clockwise ? inStart : inStart + inSpan - length, length, inThick, object.barColor, object.progressOpacity / 100)
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
        // A buff list: one cell per buff on the unit, oldest first; a new buff
        // goes at the end, a finished one leaves and the rest slide up. The
        // cells live in their own model, matched by the bridge's buff key, so a
        // cell keeps its place (and slides) instead of being rebuilt every read.
        // Arranging (live off): three sample cells.
        Item {
            visible: object.kind === "buffs"
            anchors.fill: parent
            Repeater {
                model: buffCells
                Item {
                    id: cell
                    required property int index
                    required property string buffId
                    required property bool isDebuff
                    required property int stacks
                    required property real timeLeft
                    required property real progress
                    readonly property real size: object.buffCell * object.drawScale
                    readonly property real step: (object.buffCell + object.buffSpacing) * object.drawScale
                    readonly property string g: object.buffGrow
                    width: size; height: size
                    x: g === "right" ? index * step : g === "left" ? parent.width - size - index * step : 0
                    y: g === "down" ? index * step : g === "up" ? parent.height - size - index * step : 0
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    readonly property color tint: object.tinted ? object.tint : isDebuff ? object.debuffColor : object.borderColor
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(cell.tint.r, cell.tint.g, cell.tint.b, object.fillOpacity / 100)
                        border.width: object.borderWidth * object.drawScale
                        border.color: Qt.rgba(cell.tint.r, cell.tint.g, cell.tint.b, object.borderOpacity / 100)
                    }
                    // Time passed: a dark curtain from the top, down to what is left.
                    Rectangle {
                        x: object.borderWidth * object.drawScale
                        y: x
                        width: parent.width - 2 * x
                        height: Math.max(0, (parent.height - 2 * x) * (1 - shown))
                        color: "#000000"
                        opacity: 0.45
                        property real shown: cell.progress
                        Behavior on shown { NumberAnimation { duration: 120 } }
                    }
                    Label {
                        visible: object.buffLabel !== "none"
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 2 * object.drawScale }
                        text: object.buffLabel === "full" ? cell.buffId
                              : cell.buffId.replace(/^(buff|debuff)_/, "").split("_").slice(-2).join("_")
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.text
                        style: Text.Outline; styleColor: Theme.frame
                        font.pixelSize: Math.max(6, 9 * object.drawScale)
                    }
                    Label {
                        visible: object.showTimer && cell.timeLeft >= 0
                        anchors.centerIn: parent
                        text: cell.timeLeft >= 10 ? Math.round(cell.timeLeft) : cell.timeLeft.toFixed(1)
                        color: object.valueColor
                        style: Text.Outline; styleColor: Theme.frame
                        font.pixelSize: Math.max(6, object.valueSize * object.drawScale)
                        font.weight: Font.DemiBold
                    }
                    Label {
                        visible: object.showStacks && cell.stacks > 1
                        anchors { right: parent.right; bottom: parent.bottom; margins: 2 * object.drawScale }
                        text: cell.stacks
                        color: Theme.text
                        style: Text.Outline; styleColor: Theme.frame
                        font.pixelSize: Math.max(6, 11 * object.drawScale)
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
        // A text: its static part and / or a live value, in the box,
        // vertically centered. Long text runs over the box rather than wrapping.
        Text {
            id: textItem
            visible: object.kind === "text"
            anchors.fill: parent
            horizontalAlignment: object.textAlign === "left" ? Text.AlignLeft
                               : object.textAlign === "right" ? Text.AlignRight : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: object.kind === "text" ? object.state.text : ""
            color: object.tinted ? object.tint : object.textColor
            opacity: object.textOpacity / 100
            style: object.textOutline ? Text.Outline : Text.Normal
            styleColor: object.outlineColor
            font.pixelSize: Math.max(1, object.fontSize * object.drawScale)
            font.bold: object.fontBold
        }
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
