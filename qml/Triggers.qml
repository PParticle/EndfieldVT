pragma Singleton
import QtQuick

// Conditions and triggers of a control.
//
// A condition is one test against the game data, judged by
// BridgeReader.evaluate(): { type, ...fields }.
//
// `triggers` role (JSON): when the control shows, and what it does.
//   { show: "always" | "active", list: [ { conditions: [condition], mode: "all" | "any",
//       effect, startAngle, spread, spreadColor, spreadOpacity,
//       timing, playSeconds, after, reverse } ] }
//   show "always": drawn as styled; triggers only add effects. "active":
//   drawn only while a trigger is active (no triggers: always drawn).
//   A trigger is active when all (or any) of its conditions hold; its
//   progress, value, stacks and text come from the first condition.
//   effect "radial" (中心扩散) has two kinds (`spread`):
//     "overlay": the icon stays; a copy of its shape in spreadColor grows
//                from the center to the icon's size over it.
//     "self":    the icon itself grows from nothing to its size.
//   The first active trigger that has an effect drives an icon. timing
//   "follow": the condition's own progress (buff time left, cooldown,
//   charge); "play": on becoming active, animate 0 -> 1 over playSeconds,
//   then keep the end state or hide (until the trigger starts again).
//   Bars: the first active trigger gives the progress. Texts: triggers
//   only decide when the text shows.
QtObject {
    readonly property var types: [
        { value: "buff", label: "Buff / Debuff", desc: "某个单位身上有（或没有）指定的 Buff" },
        { value: "atb", label: "技力", desc: "技力或技力格数达到条件" },
        { value: "ultimate", label: "终结技充能", desc: "终结技充能达到条件或已充满" },
        { value: "combo", label: "连携技", desc: "释放连携技后的冷却，或冷却完毕" },
        { value: "hp", label: "HP", desc: "单位的 HP 百分比达到条件" },
        { value: "poise", label: "失衡", desc: "单位处于失衡，或失衡值达到条件" },
        { value: "lock", label: "锁定目标", desc: "有（或没有）锁定的目标" },
        { value: "combat", label: "战斗状态", desc: "小队在战斗中（或不在）" },
        { value: "skillCast", label: "技能释放", desc: "释放技能后的一段时间" },
        { value: "always", label: "始终", desc: "不依赖游戏数据，一直满足" },
    ]
    function label(type) {
        for (const t of types) if (t.value === type) return t.label
        return type
    }

    readonly property var effects: [
        { label: "无", value: "none" },
        { label: "顺时针填充", value: "clockwise" },
        { label: "逆时针填充", value: "counterclockwise" },
        { label: "中心扩散", value: "radial" },
    ]
    function effectLabel(value) {
        for (const e of effects) if (e.value === value) return e.label
        return value
    }

    // Which units each type can watch.
    readonly property var squadUnits: [
        { label: "主控干员", value: "main" }, { label: "1 号位", value: "slot1" }, { label: "2 号位", value: "slot2" },
        { label: "3 号位", value: "slot3" }, { label: "4 号位", value: "slot4" }
    ]
    readonly property var buffUnits: squadUnits.concat([
        { label: "任意小队成员", value: "anySquad" }, { label: "锁定目标", value: "target" },
        { label: "任意敌人", value: "anyEnemy" }
    ])
    readonly property var hpUnits: squadUnits.concat([{ label: "锁定目标", value: "target" }])
    readonly property var castUnits: squadUnits.concat([
        { label: "任意小队成员", value: "anySquad" }, { label: "任意敌人", value: "anyEnemy" }
    ])
    readonly property var compareOps: [
        { label: "≥", value: ">=" }, { label: ">", value: ">" }, { label: "≤", value: "<=" },
        { label: "<", value: "<" }, { label: "=", value: "==" }, { label: "≠", value: "!=" }
    ]

    // A new condition of `type` with every field it uses.
    function makeCondition(type) {
        switch (type) {
        case "buff": return { type: type, unit: "main", buffIds: "", source: "any", show: "present" }
        case "atb": return { type: type, measure: "cells", op: ">=", value: 1 }
        case "ultimate": return { type: type, unit: "main", measure: "ready", op: ">=", value: 100 }
        case "combo": return { type: type, unit: "main", show: "cooling" }
        case "hp": return { type: type, unit: "main", op: "<=", value: 30 }
        case "poise": return { type: type, unit: "target", show: "broken", op: "<=", value: 30 }
        case "lock": return { type: type, show: "locked" }
        case "combat": return { type: type, show: "in" }
        case "skillCast": return { type: type, unit: "main", skillType: "any", skillId: "", duration: 3 }
        default: return { type: "always" }
        }
    }
    // A new trigger: one condition, and an effect that suits it.
    function makeTrigger(type) {
        const condition = makeCondition(type)
        // Timers sweep; one-off states (charged, locked) play an animation.
        const timed = ["buff", "combo", "skillCast"].includes(type)
        return {
            conditions: [condition],
            mode: "all",
            effect: timed ? "clockwise" : "radial",
            startAngle: 0,
            spread: timed ? "overlay" : "self",
            spreadColor: "#ffffff",
            spreadOpacity: 70,
            timing: timed ? "follow" : "play",
            playSeconds: 0.4,
            after: "keep",
            // A cooldown reports the time left; the sweep should fill up as it ends.
            reverse: type === "combo"
        }
    }
    // Bars draw their own progress, texts only show or hide: no effect.
    function makeBarTrigger(type) {
        return { conditions: [makeCondition(type)], mode: "all", effect: "none", timing: "follow", reverse: type === "combo" }
    }
    function makeTextTrigger(type) {
        return { conditions: [makeCondition(type)], mode: "all", effect: "none", timing: "follow", reverse: false }
    }

    // ---- reading the role
    function parseTriggers(text) {
        let d = null
        try { d = JSON.parse(text || "") } catch (e) {}
        const list = d && Array.isArray(d.list) ? d.list : []
        // Files are migrated when read (Main.migrate); skip anything else.
        return { show: d && d.show === "active" ? "active" : "always",
                 list: list.filter(t => t && Array.isArray(t.conditions)) }
    }
    // A trigger against the data: the first condition's result (progress,
    // value, stacks, text), active by `mode`; `parts`: every condition's result.
    function evaluateTrigger(reader, t) {
        const parts = t.conditions.map(c => reader.evaluate(c))
        const active = parts.length === 0 ? true
                     : t.mode === "any" ? parts.some(r => r.active) : parts.every(r => r.active)
        const first = parts.length > 0 ? parts[0] : { available: true, progress: 1, value: 0, max: 0, stacks: 0, text: "", note: "" }
        return Object.assign({}, first, { active: active, parts: parts })
    }

    // A bar: the first active trigger gives the progress (`reverse`
    // applies). No triggers: full. None active: empty, or hidden with
    // show "active".
    function runBar(reader, text) {
        const d = parseTriggers(text)
        const results = d.list.map(t => evaluateTrigger(reader, t))
        if (d.list.length === 0) return { progress: 1, text: "", stacks: 0, hidden: false, results: results, driving: -1 }
        for (let i = 0; i < d.list.length; ++i) {
            if (!results[i].active) continue
            const p = Math.max(0, Math.min(1, results[i].progress))
            return { progress: d.list[i].reverse ? 1 - p : p, text: results[i].text || "",
                     stacks: results[i].stacks || 0, hidden: false, results: results, driving: i }
        }
        return { progress: 0, text: "", stacks: 0, hidden: d.show === "active", results: results, driving: -1 }
    }
    // A text: shown unless show "active" and no trigger is active.
    function runText(reader, text) {
        const d = parseTriggers(text)
        const results = d.list.map(t => evaluateTrigger(reader, t))
        let driving = -1
        for (let i = 0; i < results.length && driving < 0; ++i) if (results[i].active) driving = i
        return { hidden: d.show === "active" && d.list.length > 0 && driving < 0, results: results, driving: driving }
    }

    // ---- text
    // `textMode`: "static" (staticText), "dynamic" (a value from the game) or
    // "both" (staticText, then the value). `textSource` role (JSON), the value:
    //   { condition, show: "auto" | "value" | "ratio" | "percent" | "stacks",
    //     decimals, empty, hideEmpty }
    // `condition` picks the data as a trigger condition does; only what it
    // reads matters, not whether its test holds. While there is no value (no
    // data, the buff is gone, no target) `empty` stands in, or with
    // hideEmpty the whole text is hidden.
    // Lock and combat have no value to show.
    readonly property var textTypes: types.filter(t => !["always", "lock", "combat"].includes(t.value))
    readonly property var textShows: [
        { label: "自动（剩余时间、技力等）", value: "auto" }, { label: "数值", value: "value" },
        { label: "数值 / 最大值", value: "ratio" }, { label: "百分比", value: "percent" },
        { label: "层数", value: "stacks" }
    ]
    function makeTextSource(type) {
        return { condition: makeCondition(type), show: "auto", decimals: 0, empty: "", hideEmpty: true }
    }
    function parseTextSource(text) {
        let d = null
        try { d = JSON.parse(text || "") } catch (e) {}
        if (!d || typeof d !== "object" || !d.condition) return makeTextSource("buff")
        return {
            condition: d.condition,
            show: textShows.some(s => s.value === d.show) ? d.show : "auto",
            decimals: Math.max(0, Math.min(3, Math.round(Number(d.decimals) || 0))),
            empty: d.empty !== undefined ? String(d.empty) : "",
            hideEmpty: d.hideEmpty !== false
        }
    }
    // The value part of a text, as shown; "" = no value now.
    function dynamicValue(reader, source) {
        // A buff source reads the buff itself, whatever its 状态 says.
        const condition = source.condition.type === "buff"
                          ? Object.assign({}, source.condition, { show: "present" }) : source.condition
        const r = reader.evaluate(condition)
        if (!r.available) return ""
        // Present-or-not data has nothing to show while absent.
        if ((condition.type === "buff" || condition.type === "skillCast") && !r.active) return ""
        const f = v => Number(v || 0).toFixed(source.decimals)
        switch (source.show) {
        case "value": return f(r.value)
        case "ratio": return f(r.value) + " / " + f(r.max)
        case "percent": return f(r.progress * 100) + "%"
        case "stacks": return String(r.stacks || 0)
        default: return r.text || ""
        }
    }
    // The whole text: { text, hidden }. `arranging`: a value that is missing
    // shows as "--", never hidden, so the text can still be seen and placed.
    function composeText(reader, mode, staticText, sourceText, arranging) {
        if (mode === "static") return { text: staticText, hidden: false }
        const source = parseTextSource(sourceText)
        let value = dynamicValue(reader, source)
        let hidden = false
        if (value === "") {
            if (arranging) value = "--"
            else if (source.hideEmpty) hidden = true
            else value = source.empty
        }
        return { text: (mode === "both" ? staticText : "") + value, hidden: hidden }
    }

    // Steps an icon's triggers. `state` is the icon's own object, kept between
    // calls (when each trigger became active); `nowMs` is Date.now(). Returns
    // what to draw: effect, progress (0-1), startAngle, hidden, playing,
    // stacks, text, and each trigger's result.
    function run(reader, text, state, nowMs) {
        const d = parseTriggers(text)
        const triggers = d.list
        const results = triggers.map(t => evaluateTrigger(reader, t))
        if (!state.since) state.since = []
        let drive = null, anyActive = false
        for (let i = 0; i < triggers.length; ++i) {
            const active = results[i].active
            anyActive = anyActive || active
            if (active && !state.since[i]) state.since[i] = nowMs
            if (!active) state.since[i] = 0
            if (drive === null && active && (triggers[i].effect || "none") !== "none") drive = i
        }
        state.since.length = triggers.length
        const out = { effect: "none", progress: 1, startAngle: 0, spread: "overlay", spreadColor: "#ffffff",
                      spreadOpacity: 70, hidden: d.show === "active" && triggers.length > 0 && !anyActive,
                      playing: false, stacks: 0, text: "", results: results, driving: drive === null ? -1 : drive }
        if (drive === null) return out
        const t = triggers[drive], r = results[drive]
        out.effect = t.effect
        out.spread = t.spread === "self" ? "self" : "overlay"
        out.spreadColor = t.spreadColor || "#ffffff"
        out.spreadOpacity = t.spreadOpacity !== undefined ? Number(t.spreadOpacity) : 70
        out.startAngle = Number(t.startAngle) || 0
        out.stacks = r.stacks || 0
        out.text = r.text || ""
        let p
        if (t.timing === "play") {
            const seconds = Math.max(0.05, Number(t.playSeconds) || 0.4)
            p = (nowMs - state.since[drive]) / (seconds * 1000)
            if (p < 1) {
                out.playing = true
            } else {
                p = 1
                if (t.after === "hide") out.hidden = true
            }
        } else {
            p = r.progress
        }
        p = Math.max(0, Math.min(1, p))
        out.progress = t.reverse ? 1 - p : p
        return out
    }
}
