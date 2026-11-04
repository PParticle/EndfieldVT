import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The main window: global actions in the title bar, the control tree on the
// left, and on the right whatever the user is doing (creating a control, the
// debug view, the properties of the selected control).
AppWindow {
    id: root

    // Right side: "" (the selected control, or a hint) , "new" or "debug".
    property string page: ""
    property PreviewWindow preview: null
    property string selectedId: ""
    // Re-read on any model change: a move keeps the count but shifts rows.
    readonly property int selectedIndex: { storeRevision; return indexOfId(selectedId) }
    property int nextNumber: 1
    property bool loaded: false
    // In-game overlay: on by default; saved with the controls.
    property bool overlayOn: true

    // All controls, top-level and in groups, in drawing order: the first row
    // is drawn on top. A member's parentId is its group's id; members follow
    // their group directly. The sidebar shows the same order as a tree.
    ListModel { id: store }

    readonly property var kindNames: ({ icon: "图标", bar: "进度条", text: "文本", group: "组" })

    function indexOfId(id) {
        if (id === "") return -1
        for (let i = 0; i < store.count; ++i)
            if (store.get(i).uid === id) return i
        return -1
    }
    function select(id) {
        selectedId = id
        page = ""
    }
    function togglePage(name) { page = page === name ? "" : name }

    // Every role a control has, with its starting value. New controls start
    // from these; older files get the ones they lack (Main.migrate).
    function defaults(kind) {
        return {
            // A bar starts as a 长条 (its box is fitted to it on creation).
            boxWidth: kind === "icon" ? 128 : kind === "bar" ? 240 : 160,
            boxHeight: kind === "icon" ? 128 : kind === "bar" ? 24 : 56,
            shape: "square", shapeAngle: 0, iconSize: 84,
            borderColor: "#f2c94c", borderWidth: 3, borderOpacity: 100,
            fillColor: "#f2c94c", fillOpacity: 22,
            showTimer: true, showStacks: true,
            // Bars: the frame (border + fill) and the progress drawn over it.
            // Sizes in design pixels; the box is fitted around the shape.
            barStyle: "rect", barDirection: "leftToRight", ringGap: 0,
            ringOuter: 56, ringInner: 44, barLength: 240, barThickness: 24, barRotation: 0,
            progressColor: "#f2c94c", progressOpacity: 100,
            // Bars: progress eased over barSmooth ms; barSegments cuts the
            // band into equal parts (-1: one per SP cell); ring end caps.
            barSmooth: 150, barSegments: 0, segmentGap: 2, ringCap: "butt",
            // The value (time left, SP...) on icons and bars: where (an
            // anchor in the box, then an offset), size and color.
            valueAnchor: "center", valueSize: 20, valueColor: "#e6e8eb", valueOffsetX: 0, valueOffsetY: 0,
            // Texts: what they say (qml/Triggers.qml, composeText) and how.
            textMode: "static", staticText: "文本", textSource: JSON.stringify(Triggers.makeTextSource("buff")),
            textColor: "#ffffff", textOpacity: 100, fontSize: 24, fontBold: true, textAlign: "center",
            textOutline: true, outlineColor: "#141518",
            // Groups: scale (around the group's origin, posX / posY) and
            // opacity, in %, applied to every member.
            groupScale: 100, groupOpacity: 100,
            // No triggers: drawn as styled (qml/Triggers.qml).
            triggers: JSON.stringify({ show: "always", list: [] })
        }
    }

    // New controls go on top. Groups start empty.
    function createControl(kind) {
        const number = nextNumber++
        const uid = kind + "-" + number
        const slot = store.count
        const control = Object.assign(defaults(kind), {
            uid: uid, kind: kind, name: kindNames[kind] + " " + number, parentId: "",
            posX: 128 + (slot % 4) * 176, posY: 112 + Math.floor(slot / 4) * 152
        })
        store.insert(0, control)
        if (kind === "bar") fitBarBox(0)
        select(uid)
        if (kind !== "group") showPreview()
    }

    // A group goes with its members.
    function removeControl(id) {
        const index = indexOfId(id)
        if (index < 0) return
        let count = 1
        if (store.get(index).kind === "group")
            while (index + count < store.count && store.get(index + count).parentId === id) ++count
        store.remove(index, count)
        if (indexOfId(selectedId) < 0) selectedId = ""
    }

    // Per group, by uid: scale and opacity as fractions, the scale origin
    // (ox, oy: the group's own posX / posY), the members' unscaled bounds
    // (left, top, right, bottom) and the drawn frame (bx, by, bw, bh).
    // Members keep unscaled positions; they are drawn at
    // origin + (pos - origin) * scale. Re-read whenever the model changes.
    property int storeRevision: 0
    readonly property var groups: {
        storeRevision
        const out = {}
        for (let i = 0; i < store.count; ++i) {
            const c = store.get(i)
            if (c.kind === "group")
                out[c.uid] = { scale: (c.groupScale || 100) / 100,
                               opacity: (c.groupOpacity === undefined ? 100 : c.groupOpacity) / 100,
                               ox: c.posX, oy: c.posY, n: 0, left: 0, top: 0, right: 0, bottom: 0 }
        }
        for (let i = 0; i < store.count; ++i) {
            const c = store.get(i)
            const g = out[c.parentId]
            if (!g) continue
            const r = c.posX + c.boxWidth, b = c.posY + c.boxHeight
            if (g.n++ === 0) { g.left = c.posX; g.top = c.posY; g.right = r; g.bottom = b }
            else {
                g.left = Math.min(g.left, c.posX); g.top = Math.min(g.top, c.posY)
                g.right = Math.max(g.right, r); g.bottom = Math.max(g.bottom, b)
            }
        }
        for (const id in out) {
            const g = out[id]
            g.bx = g.ox + (g.left - g.ox) * g.scale
            g.by = g.oy + (g.top - g.oy) * g.scale
            g.bw = g.n > 0 ? (g.right - g.left) * g.scale : 0
            g.bh = g.n > 0 ? (g.bottom - g.top) * g.scale : 0
        }
        return out
    }
    Connections {
        target: store
        function onDataChanged() { root.storeRevision++ }
        function onRowsInserted() { root.storeRevision++ }
        function onRowsRemoved() { root.storeRevision++ }
        function onRowsMoved() { root.storeRevision++ }
    }
    // Moves a group's drawn frame to (x, y), kept on the canvas: every member
    // and the scale origin shift by the same amount.
    function moveGroup(id, x, y) {
        const g = groups[id]
        if (!g || g.n === 0) return
        const nx = Math.max(0, Math.min(1280 - g.bw, x))
        const ny = Math.max(0, Math.min(720 - g.bh, y))
        // The origin moves with the members, so the frame moves by the same amount.
        const dx = Math.round(nx - g.bx), dy = Math.round(ny - g.by)
        if (dx === 0 && dy === 0) return
        for (let i = 0; i < store.count; ++i) {
            const c = store.get(i)
            if (c.parentId === id || c.uid === id) {
                store.setProperty(i, "posX", c.posX + dx)
                store.setProperty(i, "posY", c.posY + dy)
            }
        }
    }
    // A group's scale grows from its frame's top-left: starting from 100%,
    // the origin is put there first.
    function setGroupScale(index, value) {
        const c = store.get(index)
        const g = groups[c.uid]
        if (g && g.n > 0 && (c.groupScale || 100) === 100) {
            store.setProperty(index, "posX", g.left)
            store.setProperty(index, "posY", g.top)
        }
        store.setProperty(index, "groupScale", value)
    }

    // A copy of `id` right above it (drawn on top), in the same group, moved
    // 16 px down and right so it is not hidden under the original; named
    // "<name> 副本". A group is copied with all its members. The copy is
    // selected.
    // "名称" -> "名称 副本", then "名称 副本 2", 3...: the first free one.
    // A copy of a copy counts on from the same base name.
    function copyName(name) {
        const base = name.replace(/ 副本( \d+)?$/, "")
        const taken = new Set()
        for (let i = 0; i < store.count; ++i) taken.add(store.get(i).name)
        let n = base + " 副本"
        for (let k = 2; taken.has(n); ++k) n = base + " 副本 " + k
        return n
    }
    function duplicateControl(id) {
        const from = indexOfId(id)
        if (from < 0) return
        const source = store.get(from)
        let count = 1
        if (source.kind === "group")
            while (from + count < store.count && store.get(from + count).parentId === id) ++count
        const copies = []
        for (let i = 0; i < count; ++i) copies.push(JSON.parse(JSON.stringify(store.get(from + i))))
        const groupUid = source.kind + "-" + nextNumber++
        for (let i = 0; i < copies.length; ++i) {
            const c = copies[i]
            if (i === 0) {
                c.uid = groupUid
                c.name = copyName(c.name)
            } else {
                c.uid = c.kind + "-" + nextNumber++
                c.parentId = groupUid
            }
            // Every row by the same amount: a group's members and its scale
            // origin (the group's own posX / posY) keep their layout.
            c.posX += 16
            c.posY += 16
        }
        for (let i = 0; i < copies.length; ++i) store.insert(from + i, copies[i])
        select(groupUid)
    }

    function rename(id, name) {
        const index = indexOfId(id)
        const trimmed = name.trim()
        if (index >= 0 && trimmed !== "") store.setProperty(index, "name", trimmed)
    }

    // Sidebar drag: put `id` (with its members, if a group) before the row
    // `beforeId` ("" = at the end), into group `parentId` ("" = top level).
    // Groups do not nest.
    function moveControl(id, beforeId, parentId) {
        const from = indexOfId(id)
        if (from < 0 || id === beforeId) return
        const control = store.get(from)
        if (control.kind === "group") parentId = ""
        let count = 1
        if (control.kind === "group")
            while (from + count < store.count && store.get(from + count).parentId === id) ++count
        if (beforeId !== "") {
            const target = indexOfId(beforeId)
            if (target > from && target < from + count) return // into itself
        }
        store.setProperty(from, "parentId", parentId)
        // move() keeps the rows (and the sidebar's and preview's delegates);
        // `to` is where the block starts once it is out of the way.
        let to = store.count - count
        if (beforeId !== "") {
            const target = indexOfId(beforeId)
            if (target >= 0) to = target > from ? target - count : target
        }
        if (to !== from) store.move(from, to, count)
    }

    function setRole(id, role, value) {
        const index = indexOfId(id)
        if (index < 0) return
        if (role === "groupScale") return setGroupScale(index, value)
        store.setProperty(index, role, value)
        const c = store.get(index)
        if (c.kind !== "bar") return
        // The inner radius stays inside the outer one.
        if ((role === "ringOuter" || role === "ringInner") && c.ringInner >= c.ringOuter)
            store.setProperty(index, "ringInner", Math.max(0, c.ringOuter - 1))
        if (barSizeRoles.includes(role)) fitBarBox(index)
    }

    // A bar's box is its shape's rotated bounds plus the border, kept
    // centered where it was, so selecting and dragging match the drawing.
    readonly property var barSizeRoles: ["barStyle", "ringOuter", "barLength", "barThickness", "barRotation", "borderWidth"]
    function barBox(c) {
        const b = c.borderWidth || 0
        if (c.barStyle === "rect") {
            const a = (c.barRotation || 0) * Math.PI / 180
            const w = c.barLength + b, h = c.barThickness + b
            return { w: Math.abs(w * Math.cos(a)) + Math.abs(h * Math.sin(a)),
                     h: Math.abs(w * Math.sin(a)) + Math.abs(h * Math.cos(a)) }
        }
        const d = 2 * c.ringOuter + b
        return { w: d, h: d }
    }
    function fitBarBox(index) {
        const c = store.get(index)
        const box = barBox(c)
        const w = Math.max(4, Math.ceil(box.w)), h = Math.max(4, Math.ceil(box.h))
        const cx = c.posX + c.boxWidth / 2, cy = c.posY + c.boxHeight / 2
        store.setProperty(index, "boxWidth", w)
        store.setProperty(index, "boxHeight", h)
        store.setProperty(index, "posX", Math.round(Math.max(0, Math.min(1280 - w, cx - w / 2))))
        store.setProperty(index, "posY", Math.round(Math.max(0, Math.min(720 - h, cy - h / 2))))
    }

    // Older files: no `load`; `triggers` held show conditions
    // ({ mode, list: [condition] }). Those conditions become the load
    // conditions, and the icon's old effect becomes one trigger.
    function migrate(c) {
        // Roles added since the file was written: their defaults. Earlier
        // bar sizes and old triggers are converted below, before this fills
        // in the rest.
        const missing = defaults(c.kind)
        delete missing.triggers
        // Bars from before 长条 was the default, without a style, were rings.
        if (c.kind === "bar" && c.barStyle === undefined) c.barStyle = "ring"
        if (c.kind === "text" && c.staticText === undefined) c.staticText = c.name
        // Earlier bars were sized by their box (8 px inset) and a thickness in %.
        if (c.ringOuter === undefined) {
            const outer = Math.max(4, Math.min(c.boxWidth || 128, c.boxHeight || 128) / 2 - 8)
            c.ringOuter = Math.round(outer)
            c.ringInner = Math.round(Math.max(0, outer * (1 - (c.ringThickness || 14) / 100)))
        }
        if (c.barLength === undefined) {
            c.barLength = Math.max(4, (c.boxWidth || 256) - 16)
            c.barThickness = Math.max(2, (c.boxHeight || 40) - 16)
        }
        delete c.ringThickness
        for (const k in missing) if (c[k] === undefined) c[k] = missing[k]
        let old = null
        try { old = JSON.parse(c.triggers || "") } catch (e) {}
        // Current shape: { show, list: [{ conditions, ... }] }.
        if (old && typeof old.show === "string" && c.load === undefined) return c
        const isOldShape = old && Array.isArray(old.list) && old.list.some(t => t && t.type && !t.condition)
        if (typeof c.load !== "string") {
            const conditions = isOldShape ? old.list.filter(t => t.type !== "always") : []
            c.load = JSON.stringify({
                always: conditions.length === 0, combat: false, alive: false,
                mode: old && old.mode === "any" ? "any" : "all", list: conditions
            })
        }
        if (isOldShape || typeof c.triggers !== "string") {
            const list = []
            if (c.kind === "icon" && c.effect && c.effect !== "none")
                list.push({ condition: { type: "always" }, effect: c.effect, startAngle: 0, timing: "follow",
                            playSeconds: 0.4, after: "keep", reverse: false })
            c.triggers = JSON.stringify({ list: list })
        }
        if (typeof c.load === "string") mergeLoad(c)
        return c
    }
    // The 载入 tab is gone: when a control shows is part of its triggers.
    // A load that was not "always" becomes show "active" with one trigger
    // holding the load conditions (so loaded = shown); every old trigger
    // also gets them. The old load ANDed its presets (combat, alive) with
    // its list, the list combined by its own mode. A flat condition list
    // holds that exactly, except "any" with several entries: the load's
    // own trigger keeps "any" (when there is no preset), but an effect
    // trigger needs all of them (stricter than before, never looser).
    function mergeLoad(c) {
        let load = null, old = null
        try { load = JSON.parse(c.load) } catch (e) {}
        try { old = JSON.parse(c.triggers || "") } catch (e) {}
        delete c.load
        const list = (old && Array.isArray(old.list) ? old.list : []).filter(t => t && t.condition)
        const presets = [], extra = []
        if (load && load.always === false) {
            if (load.combat) presets.push({ type: "combat", show: "in" })
            if (load.alive) presets.push({ type: "hp", unit: "main", op: ">", value: 0 })
            for (const x of load.list || []) if (x && x.type) extra.push(x)
        }
        const loadConds = presets.concat(extra)
        const loadMode = presets.length === 0 && load && load.mode === "any" ? "any" : "all"
        const triggers = list.map(t => {
            const n = Object.assign({}, t)
            delete n.condition
            if (n.effect === "grow") { n.effect = "radial"; n.spread = "self" }
            n.conditions = [t.condition].concat(loadConds)
            n.mode = "all"
            return n
        })
        if (loadConds.length > 0)
            triggers.push({ conditions: loadConds, mode: loadMode, effect: "none", timing: "follow", reverse: false })
        c.triggers = JSON.stringify({ show: loadConds.length > 0 ? "active" : "always", list: triggers })
    }

    // ---- the config (<name>.json, src/configfile.h): read at start and on
    // a switch, written shortly after every change.
    function serialize() {
        const controls = []
        for (let i = 0; i < store.count; ++i) controls.push(JSON.parse(JSON.stringify(store.get(i))))
        return JSON.stringify({ version: 1, nextNumber: nextNumber, overlay: overlayOn, controls: controls }, null, 2) + "\n"
    }
    // An empty config, as a new one starts.
    function emptyConfig() {
        return JSON.stringify({ version: 1, nextNumber: 1, overlay: overlayOn, controls: [] }, null, 2) + "\n"
    }
    function load() {
        // Nothing is saved while loading; a failed read keeps it that way
        // until another config is opened, so a broken file is not overwritten.
        loaded = false
        selectedId = ""
        store.clear()
        nextNumber = 1
        if (!ConfigFile.exists()) {
            loaded = true
            return
        }
        const text = ConfigFile.read()
        try {
            const data = JSON.parse(text)
            if (!data || !Array.isArray(data.controls)) throw new Error("不是 EndfieldVT 的配置（没有 controls）")
            for (const c of data.controls) store.append(migrate(c))
            for (let i = 0; i < store.count; ++i) if (store.get(i).kind === "bar") fitBarBox(i)
            nextNumber = data.nextNumber || store.count + 1
            overlayOn = data.overlay !== false
            loaded = true
        } catch (e) {
            store.clear()
            status.flash(ConfigFile.name + ".json 读取失败，修改不会保存：" + (ConfigFile.lastError || e.message), 0)
        }
    }
    // Saves what is pending in the current config.
    function flush() {
        if (!saveTimer.running) return
        saveTimer.stop()
        if (loaded && !ConfigFile.write(serialize())) status.flash("保存失败：" + ConfigFile.lastError, 0)
    }
    function switchConfig(name) {
        if (name === ConfigFile.name) return
        flush()
        if (!ConfigFile.open(name)) { status.flash(ConfigFile.lastError, 0); return }
        load()
        if (loaded) status.flash("已切换到配置「" + name + "」")
    }
    // A new config: empty, or a copy of the current one. Opened right away.
    function createConfig(name, copy) {
        flush()
        const text = copy ? serialize() : emptyConfig()
        if (!ConfigFile.create(name, text)) { status.flash(ConfigFile.lastError, 0); return false }
        switchConfig(name)
        return true
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            if (!ConfigFile.write(root.serialize())) status.flash("保存失败：" + ConfigFile.lastError, 0)
        }
    }
    Connections {
        target: store
        enabled: root.loaded
        function onDataChanged() { saveTimer.restart() }
        function onRowsInserted() { saveTimer.restart() }
        function onRowsRemoved() { saveTimer.restart() }
        function onRowsMoved() { saveTimer.restart() }
    }
    onOverlayOnChanged: if (loaded) saveTimer.restart()
    Component.onCompleted: load()

    function showPreview() {
        // No transient parent: a window of its own that can sit beside or
        // behind this one.
        if (!preview) preview = previewWindow.createObject(null)
        preview.show()
        preview.raise()
        preview.requestActivate()
    }

    width: Theme.windowW
    height: Theme.windowH
    minimumWidth: Theme.windowW * 3 / 4
    minimumHeight: Theme.windowH * 3 / 4
    visible: true
    title: "EndfieldVT"
    onClosing: {
        flush()
        if (preview) preview.close() // closing the main window quits
        overlay.enabled = false
    }

    // Ctrl+D: copy the selected control (not while typing in a field).
    Shortcut {
        sequence: "Ctrl+D"
        enabled: root.selectedId !== "" && !(root.activeFocusItem instanceof TextInput)
        onActivated: root.duplicateControl(root.selectedId)
    }

    // The lead zone ends so that the first label sits on the content column
    // (sidebar + page padding).
    leadWidth: Theme.sidebarW + Theme.pagePad - Theme.gap
    actions: [
        TitleAction { text: "新建"; checked: root.page === "new"; onClicked: root.togglePage("new") },
        Item {
            width: 2 * Theme.unit + 1
            height: Theme.titleBarH - 1
            Rectangle {
                x: Theme.unit
                y: Math.round((parent.height - height) / 2)
                width: 1
                height: Theme.gap
                color: Theme.line
            }
        },
        TitleAction { text: "预览/编辑"; onClicked: root.showPreview() },
        TitleAction { text: "游戏内显示"; checked: root.overlayOn; onClicked: root.overlayOn = !root.overlayOn },
        TitleAction { text: "调试"; checked: root.page === "debug"; onClicked: root.togglePage("debug") }
    ]
    trailing: [
        ConfigMenu {
            objectName: "configMenu"
            onSwitchRequested: name => root.switchConfig(name)
            onCreateRequested: (name, copy) => root.createConfig(name, copy)
        }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            Sidebar {
                Layout.preferredWidth: Theme.sidebarW
                Layout.fillHeight: true
                model: store
                selectedId: root.selectedId
                onSelected: id => root.select(id)
                onRemoveRequested: id => root.removeControl(id)
                onDuplicateRequested: id => root.duplicateControl(id)
                onMoveRequested: (id, beforeId, parentId) => root.moveControl(id, beforeId, parentId)
            }
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.page === "new" ? 1 : root.page === "debug" ? 2 : root.selectedIndex >= 0 ? 3 : 0
                // Nothing chosen: one quiet line, a little above the middle.
                Item {
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((parent.height - height) * 2 / 5)
                        text: "从左侧选择一个控件，或点击「新建」"
                        color: Theme.textFaint
                    }
                }
                NewPage { onCreateRequested: kind => root.createControl(kind) }
                DebugPage {}
                WidgetEditor {
                    model: store
                    selectedIndex: root.selectedIndex
                    onRenameRequested: name => root.rename(root.selectedId, name)
                    onRoleChanged: (role, value) => root.setRole(root.selectedId, role, value)
                    groups: root.groups
                    onGroupMoveRequested: (x, y) => root.moveGroup(root.selectedId, x, y)
                }
            }
        }
        StatusBar {
            id: status
            gameText: !root.overlayOn ? "游戏内显示：关" : overlay.tracker.stateText
            gameActive: overlay.tracker.visible
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.statusBarH
        }
    }

    // Over the game; shows only while the game is in front (src/gamewindow.h).
    OverlayWindow {
        id: overlay
        model: store
        groups: root.groups
        enabled: root.overlayOn
    }

    Component {
        id: previewWindow
        PreviewWindow {
            model: store
            groups: root.groups
            selectedId: root.selectedId
            onGroupMoved: (id, x, y) => root.moveGroup(id, x, y)
            onSelected: id => root.select(id)
            onMoved: (id, x, y) => { root.setRole(id, "posX", x); root.setRole(id, "posY", y) }
        }
    }
}
