import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The controls as a tree in drawing order: higher rows are drawn on top.
// Groups fold with the arrow in front of them. Drag a row to restack it:
// the row lifts and follows the pointer, the others slide apart where it
// would land; drop it in the middle of a group to put it inside. Right click
// copies (also Ctrl+D) or deletes (renaming is only in the properties page,
// so a right click is never a slip of the hand). Caption row as tall as the
// page title row and on the same line; text on the x = gap column, like the
// brand and the status bar.
Rectangle {
    id: side
    property ListModel model
    property string selectedId
    signal selected(string id)
    signal removeRequested(string id)
    signal duplicateRequested(string id)
    signal moveRequested(string id, string beforeId, string parentId)

    // Folded groups, by uid (not saved: every start shows everything).
    property var collapsed: ({})
    function isCollapsed(groupId) { return collapsed[groupId] === true }
    function toggle(groupId) {
        const c = Object.assign({}, collapsed)
        if (c[groupId]) delete c[groupId]
        else c[groupId] = true
        collapsed = c
    }

    // ---- dragging
    property string dragId: ""
    property bool dragGroup: false
    property real dragY: 0            // top of the lifted row, in list content coordinates
    property real grabOffset: 0       // pointer y within the dragged row
    // Where it would land: before model row `dropBeforeId` ("" = end), into
    // `dropParentId`. `gapSlot`: where the rows open up (slot among the rows
    // that stay), -1 = none. `intoSlot`: the group row it would drop into.
    property string dropBeforeId: ""
    property string dropParentId: ""
    property int gapSlot: -1
    property int intoSlot: -1
    property int gapRows: 1           // rows the lifted block takes

    color: Theme.surface

    // model.count does not change on moves or parentId edits: re-read the
    // rows on any model change.
    property int revision: 0
    Connections {
        target: side.model
        function onDataChanged() { side.revision++ }
        function onRowsMoved() { side.revision++ }
        function onRowsInserted() { side.revision++ }
        function onRowsRemoved() { side.revision++ }
    }

    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
        color: Theme.line
    }

    // The rows that stay in the list, in order: folded members are left out,
    // and so is the lifted block while dragging.
    readonly property var restRows: {
        const out = []
        if (!model) return out
        revision
        collapsed
        for (let i = 0; i < model.count; ++i) {
            const r = model.get(i)
            if (r.parentId !== "" && isCollapsed(r.parentId)) continue
            if (dragId !== "" && (r.uid === dragId || (dragGroup && r.parentId === dragId))) continue
            out.push({ index: i, uid: r.uid, kind: r.kind, parentId: r.parentId })
        }
        return out
    }
    function restSlotOf(uid) {
        for (let i = 0; i < restRows.length; ++i) if (restRows[i].uid === uid) return i
        return -1
    }
    // Drop: move first (rows are kept, the gap stays open where the row
    // lands), then end the drag so the row settles from where it was let go.
    function finishDrag() {
        const id = dragId, before = dropBeforeId, parent = dropParentId
        const drop = gapSlot >= 0 || intoSlot >= 0
        if (drop && id !== "") moveRequested(id, before, parent)
        dragId = ""
        gapSlot = -1
        intoSlot = -1
    }
    // Pointer y in the list's viewport while dragging, for auto scroll.
    property real dragViewY: 0
    function dragTo(viewY) {
        dragViewY = viewY
        const y = viewY + list.contentY
        dragY = Math.max(0, Math.min(list.contentHeight - Theme.rowH, y - grabOffset))
        updateDrop(y)
    }
    function membersOf(groupId) {
        const out = []
        for (let i = 0; i < model.count; ++i) if (model.get(i).parentId === groupId) out.push(model.get(i).uid)
        return out
    }

    ColumnLayout {
        anchors { fill: parent; topMargin: Theme.pagePad; rightMargin: 1 }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.rowH
            Layout.leftMargin: Theme.gap
            Layout.rightMargin: Theme.gap
            Label { text: "控件"; color: Theme.textDim; font.pixelSize: Theme.caption }
            Item { Layout.fillWidth: true }
            Label { text: side.model ? side.model.count : 0; color: Theme.textDim; font.pixelSize: Theme.caption }
        }
        Item { Layout.preferredHeight: Theme.unit }

        Label {
            visible: !side.model || side.model.count === 0
            Layout.preferredHeight: Theme.rowH
            leftPadding: Theme.gap
            verticalAlignment: Text.AlignVCenter
            text: "还没有控件"
            color: Theme.textFaint
        }

        // Rows are placed by hand from their slot, so they can slide (a
        // ListView jumps on every model move).
        Flickable {
            id: list
            objectName: "controlList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: side.dragId === ""
            contentHeight: (side.restRows.length + (side.dragId !== "" ? side.gapRows : 0)) * Theme.rowH
            readonly property ListModel model: side.model   // for tests and tools
            ScrollBar.vertical: ScrollBar {}

            // While dragging near the top or bottom edge, scroll; faster
            // the closer to (or past) the edge.
            Timer {
                interval: 16
                repeat: true
                running: side.dragId !== "" && list.contentHeight > list.height
                         && (side.dragViewY < Theme.rowH || side.dragViewY > list.height - Theme.rowH)
                onTriggered: {
                    const edge = side.dragViewY < Theme.rowH ? side.dragViewY - Theme.rowH
                                                            : side.dragViewY - (list.height - Theme.rowH)
                    const step = Math.max(-24, Math.min(24, edge / 3))
                    const y = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + step))
                    if (y === list.contentY) return
                    list.contentY = y
                    side.dragTo(side.dragViewY)
                }
            }

            Repeater {
                id: rows
                model: side.model || 0
                delegate: Item {
                    id: row
                    required property int index
                    required property string uid
                    required property string kind
                    required property string name
                    required property string parentId
                    readonly property bool isGroup: kind === "group"
                    readonly property bool isMember: parentId !== ""
                    readonly property bool isSelected: uid === side.selectedId
                    readonly property bool folded: isMember && side.isCollapsed(parentId)
                    readonly property bool lifted: side.dragId !== "" && (uid === side.dragId || (side.dragGroup && parentId === side.dragId))
                    readonly property int indent: Theme.gap + (isMember ? 3 * Theme.unit : 0)
                    readonly property int memberCount: { side.revision; return isGroup ? side.membersOf(uid).length : 0 }
                    readonly property bool showCount: isGroup && side.isCollapsed(uid) && memberCount > 0

                    // Where it sits: its slot among the rows that stay, pushed
                    // down past the gap; a lifted row follows the pointer.
                    readonly property int restSlot: { side.restRows; return side.restSlotOf(uid) }
                    readonly property real restY: (restSlot + (side.gapSlot >= 0 && restSlot >= side.gapSlot ? side.gapRows : 0)) * Theme.rowH
                    readonly property int liftedOffset: {
                        // An open group's members ride along under it, in order.
                        if (!lifted || uid === side.dragId) return 0
                        const m = side.membersOf(side.dragId)
                        return (m.indexOf(uid) + 1) * Theme.rowH
                    }

                    width: list.width
                    height: Theme.rowH
                    visible: !folded && (restSlot >= 0 || lifted)
                    y: lifted ? side.dragY + liftedOffset : restY
                    z: lifted ? 10 : 0
                    // Slide into place; a lifted row tracks the pointer directly.
                    Behavior on y {
                        enabled: !row.lifted
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        id: plate
                        anchors.fill: parent
                        color: row.lifted ? Theme.raised
                             : row.isSelected ? Theme.raised
                             : hover.hovered && side.dragId === "" ? Qt.lighter(Theme.surface, 1.08) : "transparent"
                        border.width: row.lifted ? 1 : 0
                        border.color: Theme.lineStrong
                        scale: row.lifted ? 1.02 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        // A soft shadow under the lifted row.
                        Rectangle {
                            visible: row.lifted
                            z: -1
                            anchors { fill: parent; topMargin: 3; leftMargin: 2; rightMargin: -2; bottomMargin: -3 }
                            color: "#000000"
                            opacity: 0.35
                            radius: 2
                        }
                    }
                    Rectangle {   // into-group outline
                        anchors.fill: parent
                        visible: side.intoSlot >= 0 && row.isGroup && row.restSlot === side.intoSlot
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                        border.color: Theme.accent
                    }
                    Rectangle {   // the selected row's accent edge
                        visible: row.isSelected && !row.lifted
                        width: 2
                        height: parent.height
                        color: Theme.accent
                    }
                    // Fold arrow, in the gap left of a group's icon. Clicks are
                    // taken by the row's TapHandler below (it is handled there).
                    Item {
                        id: fold
                        visible: row.isGroup
                        x: 0
                        width: row.indent
                        height: parent.height
                        readonly property bool hovered: foldHover.hovered
                        HoverHandler { id: foldHover; cursorShape: Qt.PointingHandCursor }
                        Canvas {
                            anchors.fill: parent
                            id: chevron
                            // Points right when folded, down when open.
                            property real turn: side.isCollapsed(row.uid) ? 0 : 90
                            property color ink: fold.hovered ? Theme.text : Theme.textDim
                            Behavior on turn { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            onTurnChanged: requestPaint()
                            onInkChanged: requestPaint()
                            onPaint: {
                                const g = getContext("2d")
                                g.reset()
                                g.translate(width / 2 + 2, height / 2)
                                g.rotate(turn * Math.PI / 180)
                                g.strokeStyle = ink
                                g.lineWidth = 1.5
                                g.lineCap = "round"
                                g.lineJoin = "round"
                                g.beginPath()
                                g.moveTo(-2, -4)
                                g.lineTo(2, 0)
                                g.lineTo(-2, 4)
                                g.stroke()
                            }
                        }
                    }
                    KindIcon {
                        x: row.indent
                        anchors.verticalCenter: parent.verticalCenter
                        kind: row.kind
                        color: row.isSelected || row.lifted ? Theme.accent : Theme.textDim
                    }
                    Label {
                        x: row.indent + 3 * Theme.unit
                        width: parent.width - x - Theme.gap - (row.showCount ? countLabel.implicitWidth + Theme.unit : 0)
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: row.name
                    }
                    Label {   // folded groups show how many they hold
                        id: countLabel
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.gap
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        visible: row.showCount
                        text: row.memberCount
                        color: Theme.textFaint
                        font.pixelSize: Theme.caption
                    }

                    HoverHandler { id: hover }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        // The arrow folds; anywhere else selects (double click a group folds too).
                        onTapped: (point) => {
                            if (row.isGroup && point.position.x < row.indent) side.toggle(row.uid)
                            else side.selected(row.uid)
                        }
                        onDoubleTapped: (point) => { if (row.isGroup && point.position.x >= row.indent) side.toggle(row.uid) }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: {
                            side.selected(row.uid)
                            menu.targetId = row.uid
                            menu.popup()
                        }
                    }
                    DragHandler {
                        target: null
                        xAxis.enabled: false
                        onActiveChanged: {
                            if (active) {
                                side.grabOffset = centroid.pressPosition.y
                                side.dragGroup = row.isGroup
                                // A group carries its members (folded ones too).
                                side.gapRows = row.isGroup && !side.isCollapsed(row.uid) ? 1 + side.membersOf(row.uid).length : 1
                                side.dragY = row.y
                                side.dragId = row.uid
                                side.dragViewY = row.y + side.grabOffset - list.contentY
                                side.updateDrop(row.y + side.grabOffset)
                            } else {
                                side.finishDrag()
                            }
                        }
                        onCentroidChanged: {
                            if (!active) return
                            side.dragTo(row.mapToItem(list, centroid.position).y)
                        }
                    }
                }
            }
        }
    }

    // Where a row dragged to pointer y (list content coordinates) would land,
    // judged against the rows that stay. A row's upper half means "before
    // it", the lower half "after it"; the middle of a group row means "into
    // the group, at its top". Before a member means in that member's group;
    // in the lower half of a group's last visible member: the third quarter
    // keeps it in the group, the last quarter puts it after the group.
    function updateDrop(y) {
        const rest = restRows
        const n = rest.length
        gapSlot = -1
        intoSlot = -1
        if (n === 0) {
            dropBeforeId = ""
            dropParentId = ""
            gapSlot = 0
            return
        }
        const at = Math.max(0, Math.min(n - 1, Math.floor(y / Theme.rowH)))
        const within = y - at * Theme.rowH
        const target = rest[at]

        if (!dragGroup && target.kind === "group" && within > Theme.rowH / 4 && within < Theme.rowH * 3 / 4) {
            // Into the group, as its first member: right after the group row
            // (skipping the dragged row itself if it sits there).
            dropParentId = target.uid
            let i = target.index + 1
            if (i < model.count && model.get(i).uid === dragId) ++i
            dropBeforeId = i < model.count ? model.get(i).uid : ""
            intoSlot = at
            return
        }
        let before = within < Theme.rowH / 2 ? at : at + 1
        // A group cannot land between a group and its members.
        if (dragGroup) while (before < n && rest[before].parentId !== "") ++before
        const next = before < n ? rest[before] : null
        let parentId = ""
        if (!dragGroup && next && next.parentId !== "") parentId = next.parentId
        if (!dragGroup && parentId === "" && before === at + 1 && target.parentId !== "" && within < Theme.rowH * 3 / 4)
            parentId = target.parentId
        // The model row it goes before. After a folded group, skip its hidden
        // members so it does not land among them.
        let beforeIndex = next ? next.index : model.count
        if (before > 0 && parentId === "") {
            const prev = rest[before - 1]
            if (prev.kind === "group" && isCollapsed(prev.uid)) {
                let i = prev.index + 1
                while (i < model.count && model.get(i).parentId === prev.uid) ++i
                beforeIndex = i
            }
        }
        while (beforeIndex < model.count && model.get(beforeIndex).uid === dragId) ++beforeIndex
        dropBeforeId = beforeIndex < model.count ? model.get(beforeIndex).uid : ""
        dropParentId = parentId
        gapSlot = before
    }

    Menu {
        id: menu
        property string targetId
        topPadding: 1
        bottomPadding: 1
        background: Rectangle { implicitWidth: 16 * Theme.unit; color: Theme.surface; border.color: Theme.lineStrong }
        delegate: MenuItem {
            id: entry
            implicitHeight: Theme.rowH
            background: Rectangle { color: entry.highlighted ? Theme.raised : "transparent" }
            contentItem: Label {
                leftPadding: Theme.unit - entry.leftPadding
                verticalAlignment: Text.AlignVCenter
                text: entry.text
                color: entry.text === "删除" ? Theme.danger : Theme.text
            }
        }
        Action { text: "复制"; onTriggered: side.duplicateRequested(menu.targetId) }
        Action { text: "删除"; onTriggered: side.removeRequested(menu.targetId) }
    }
}
