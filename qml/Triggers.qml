pragma Singleton
import QtQuick

// Conditions and triggers of a control.
//
// A condition is one test against the game data, judged by
// BridgeReader.evaluate(): { type, ...fields }.
//
// `triggers` role (JSON): when the control shows, and what it does.
//   { show: "always" | "active" | "never", list: [ { conditions: [condition], mode: "all" | "any",
//       effect, startAngle, spread, spreadColor, spreadOpacity,
//       timing, playSeconds, after, reverse } ] }
//   show "always": drawn as styled; triggers only add effects. "active":
//   drawn only while a trigger is active (no triggers: always drawn).
//   "never": not drawn at all (in game and in the preview's live view), its
//   settings kept: a control switched off without deleting it.
//   `motion`: how it comes and goes when its triggers show / hide it:
//     { appear, disappear: "none" | "fade" | "slide" | "pop", ms, from }
//     (`from`, for slide: "down" | "up" | "left" | "right", where it comes
//     from and goes back to). A member with neither uses its group's.
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
//   Bars: the first active trigger that gives progress (`drives`, default
//   on) gives it. Texts and buff lists: triggers only decide when they show.
//   Style, any kind, while a trigger is active (all optional; later active
//   triggers win field by field, a member's own over its group's):
//     tint + tintColor   recolor: icon border and fill, a bar's progress,
//                        a text, buff cells
//     alpha              opacity 0-100 (100 = unchanged)
//     glow: "none" | "soft" | "flow" | "pixel", glowColor, glowSize
//     loop: "none" | "pulse" | "breathe" | "blink" | "shake" | "spin", loopSeconds
QtObject {
    readonly property var types: [
        { value: "buff", label: "Buff / Debuff", desc: "某个单位身上有（或没有）指定的 Buff" },
        { value: "atb", label: "技力", desc: "技力值或满格数" },
        { value: "ultimate", label: "终结技充能", desc: "终结技充能达到条件或已充满" },
        { value: "combo", label: "连携技", desc: "释放连携技后的冷却，或冷却完毕" },
        { value: "hp", label: "HP", desc: "单位的 HP（数值；比较时按百分比）" },
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

    readonly property var glows: [
        { label: "无", value: "none" }, { label: "外发光", value: "soft" },
        { label: "流光（沿边框转圈）", value: "flow" }, { label: "像素边框", value: "pixel" }
    ]
    readonly property var loops: [
        { label: "无", value: "none" }, { label: "脉冲（放大缩小）", value: "pulse" },
        { label: "呼吸（渐隐渐显）", value: "breathe" }, { label: "闪烁", value: "blink" },
        { label: "抖动", value: "shake" }, { label: "旋转", value: "spin" }
    ]
    // What the active triggers' styles add up to: { tint, alpha, glow,
    // glowColor, glowSize, loop, loopSeconds }, only the fields some active
    // trigger sets.
    function styleOf(list, results) {
        const s = {}
        for (let i = 0; i < list.length; ++i) {
            if (!results[i] || !results[i].active) continue
            const t = list[i]
            if (t.tint) s.tint = t.tintColor || "#e5484d"
            if (t.alpha !== undefined && Number(t.alpha) < 100) s.alpha = Math.max(0, Number(t.alpha))
            if (t.glow && t.glow !== "none") {
                s.glow = t.glow
                s.glowColor = t.glowColor || "#ffd166"
                s.glowSize = t.glowSize !== undefined ? Math.max(1, Number(t.glowSize)) : 8
            }
            if (t.loop && t.loop !== "none") {
                s.loop = t.loop
                s.loopSeconds = Math.max(0.1, Number(t.loopSeconds) || 1)
            }
        }
        return s
    }
    // A member's style: its group's, with its own fields on top.
    function mergeStyle(group, own) { return Object.assign({}, group || {}, own || {}) }
    function hasStyle(t) {
        return !!t.tint || (t.alpha !== undefined && Number(t.alpha) < 100)
            || (t.glow && t.glow !== "none") || (t.loop && t.loop !== "none")
    }

    readonly property var motions: [
        { label: "无", value: "none" }, { label: "淡入淡出", value: "fade" },
        { label: "滑动", value: "slide" }, { label: "弹出 / 缩回", value: "pop" }
    ]
    readonly property var slideFroms: [
        { label: "从下方", value: "down" }, { label: "从上方", value: "up" },
        { label: "从左边", value: "left" }, { label: "从右边", value: "right" }
    ]
    function parseMotion(m) {
        const ok = v => ["fade", "slide", "pop"].includes(v) ? v : "none"
        m = m && typeof m === "object" ? m : {}
        return { appear: ok(m.appear), disappear: ok(m.disappear),
                 ms: m.ms !== undefined ? Math.max(0, Math.min(5000, Number(m.ms) || 0)) : 200,
                 from: ["down", "up", "left", "right"].includes(m.from) ? m.from : "down" }
    }
    function hasMotion(m) { return m.appear !== "none" || m.disappear !== "none" }

    // Which units each type can watch.
    readonly property var squadUnits: [
        { label: "主控干员", value: "main" }, { label: "1 号位", value: "slot1" }, { label: "2 号位", value: "slot2" },
        { label: "3 号位", value: "slot3" }, { label: "4 号位", value: "slot4" },
        { label: "每个小队成员 ×4", value: "each" }
    ]
    // ---- per-unit expansion
    // A control any of whose conditions (or a buff list's unit) is "each"
    // is drawn four times, one per squad slot, laid out by expandDir /
    // expandGap: the control itself is slot 1, Main's copies are 2-4. Each
    // reads its own slot through slotReader(n), which only rewrites "each".
    function usesEach(c) {
        return c.kind !== "group" && (c.buffUnit === "each"
            || /"unit":"each"/.test(c.triggers || "") || (c.kind === "text" && /"unit":"each"/.test(c.textSource || "")))
    }
    function slotReader(n) {
        const slot = "slot" + n
        const fix = spec => spec && spec.unit === "each" ? Object.assign({}, spec, { unit: slot }) : spec
        return {
            slot: n,
            evaluate: spec => BridgeReader.evaluate(fix(spec)),
            buffList: spec => BridgeReader.buffList(fix(spec))
        }
    }
    // Copy n's offset from the control, design px.
    function expandOffset(c, n) {
        const d = c.expandDir, gap = Number(c.expandGap) || 0
        const along = (d === "left" || d === "right" ? c.boxWidth : c.boxHeight) + gap
        const k = (n - 1) * along
        return { x: d === "right" ? k : d === "left" ? -k : 0, y: d === "down" ? k : d === "up" ? -k : 0 }
    }
    readonly property var buffUnits: squadUnits.concat([
        { label: "任意小队成员", value: "anySquad" }, { label: "锁定目标", value: "target" },
        { label: "任意敌人", value: "anyEnemy" }
    ])
    readonly property var hpUnits: squadUnits.concat([{ label: "锁定目标", value: "target" }])
    readonly property var castUnits: squadUnits.concat([
        { label: "任意小队成员", value: "anySquad" }, { label: "任意敌人", value: "anyEnemy" }
    ])
    readonly property var compareOps: [
        { label: "不比较", value: "any" }, { label: "≥", value: ">=" }, { label: ">", value: ">" }, { label: "≤", value: "<=" },
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
    // Bars draw their own progress, texts only show or hide: no effect. A
    // bar's number conditions start as "不比较": the bar only needs the value.
    function makeBarTrigger(type) {
        const c = makeCondition(type)
        if (c.op !== undefined) c.op = "any"
        if (type === "atb") c.measure = "sp"
        if (type === "ultimate") c.measure = "value"
        return { conditions: [c], mode: "all", effect: "none", timing: "follow", reverse: type === "combo",
                 range: "full", rangeFrom: 0, rangeTo: 100 }
    }
    // A bar's progress from a trigger's result: the whole 0..max, or a part
    // of it (rangeFrom..rangeTo, in the value's own units), so several bars
    // can each show one part (SP cell 1 = 0..100, cell 2 = 100..200...).
    function barProgress(t, r) {
        if (t.range === "part") {
            const span = Number(t.rangeTo) - Number(t.rangeFrom)
            return span > 0 ? (Number(r.value) - Number(t.rangeFrom)) / span : 0
        }
        return r.progress
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
        return { show: d && (d.show === "active" || d.show === "never") ? d.show : "always",
                 list: list.filter(t => t && Array.isArray(t.conditions)),
                 motion: parseMotion(d ? d.motion : null) }
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
    // show "active". Show "never": hidden.
    function runBar(reader, text) {
        const d = parseTriggers(text)
        const results = d.list.map(t => evaluateTrigger(reader, t))
        const never = d.show === "never"
        const style = styleOf(d.list, results)
        if (d.list.length === 0) return { progress: 1, text: "", stacks: 0, hidden: never, results: results, driving: -1, style: style }
        const anyActive = results.some(r => r.active)
        for (let i = 0; i < d.list.length; ++i) {
            if (!results[i].active || d.list[i].drives === false) continue
            const p = Math.max(0, Math.min(1, barProgress(d.list[i], results[i])))
            return { progress: d.list[i].reverse ? 1 - p : p, text: results[i].text || "",
                     stacks: results[i].stacks || 0, hidden: never, results: results, driving: i, style: style }
        }
        return { progress: 0, text: "", stacks: 0, hidden: never || (d.show === "active" && !anyActive),
                 results: results, driving: -1, style: style }
    }
    // A text: shown unless show "never", or "active" and no trigger is active.
    function runText(reader, text) {
        const d = parseTriggers(text)
        const results = d.list.map(t => evaluateTrigger(reader, t))
        let driving = -1
        for (let i = 0; i < results.length && driving < 0; ++i) if (results[i].active) driving = i
        return { hidden: d.show === "never" || (d.show === "active" && d.list.length > 0 && driving < 0),
                 results: results, driving: driving, style: styleOf(d.list, results) }
    }

    // ---- text
    // `textMode`: "static" (staticText), "dynamic" (a value from the game),
    // "both" (staticText, then the value) or "template" (staticText with
    // placeholders, see fillTemplate). `textSource` role (JSON), the value:
    //   { condition, show: "auto" | "value" | "ratio" | "percent" | "stacks",
    //     decimals, empty, hideEmpty, more: [condition] }
    // `more`: a template's sources 2, 3...; `condition` is source 1.
    // `condition` picks the data as a trigger condition does; only what it
    // reads matters, not whether its test holds. While there is no value (no
    // data, the buff is gone, no target) `empty` stands in, or with
    // hideEmpty the whole text is hidden.
    // Lock and combat have no value to show.
    readonly property var textTypes: types.filter(t => !["always", "lock", "combat"].includes(t.value))
    readonly property var textShows: [
        { label: "自动（剩余时间、技力等）", value: "auto" }, { label: "数值", value: "value" },
        { label: "数值 / 上限", value: "ratio" }, { label: "百分比", value: "percent" },
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
            hideEmpty: d.hideEmpty !== false,
            more: Array.isArray(d.more) ? d.more.filter(c => c && typeof c === "object" && c.type) : []
        }
    }
    // What a source reads now; null = no value (no data, the buff is gone).
    function readSource(reader, condition) {
        // A buff source reads the buff itself, whatever its 状态 and extra tests say.
        const c = condition.type === "buff"
                  ? Object.assign({}, condition, { show: "present", stacksOp: "any", leftOp: "any" }) : condition
        const r = reader.evaluate(c)
        if (!r.available) return null
        // Present-or-not data has nothing to show while absent.
        if ((c.type === "buff" || c.type === "skillCast") && !r.active) return null
        return r
    }
    // The value part of a text, as shown; "" = no value now.
    function dynamicValue(reader, source) {
        const r = readSource(reader, source.condition)
        if (!r) return ""
        const f = v => Number(v || 0).toFixed(source.decimals)
        switch (source.show) {
        case "value": return f(r.value)
        case "ratio": return f(r.value) + " / " + f(r.max)
        case "percent": return f(r.progress * 100) + "%"
        case "stacks": return String(r.stacks || 0)
        default: return r.text || ""
        }
    }
    // Template placeholders: {名称}, {名称N} for source N (1 when left out),
    // {名称:格式}. Anything else in braces stays as it is.
    //   名称   数值 (also 技力 / HP / 终结技 / 失衡 / 值)  上限  百分比  层数
    //          剩余 (seconds left; 冷却 too)  自动 (as 「自动」 shows it)
    //   {N}    source N, 自动
    //   格式   mm:ss, m:ss, ss (whole seconds), 0 / 0.0 / 0.00 (decimals)
    readonly property var placeholderNames: ({
        "数值": "value", "值": "value", "技力": "value", "HP": "value", "hp": "value", "终结技": "value", "失衡": "value",
        "上限": "max", "百分比": "percent", "层数": "stacks", "剩余": "left", "冷却": "left", "自动": "auto"
    })
    function formatNumber(v, format, fallbackDecimals) {
        v = Number(v || 0)
        if (format === "mm:ss" || format === "m:ss") {
            const t = Math.max(0, Math.ceil(v))
            const m = Math.floor(t / 60), sec = t % 60
            return (format === "mm:ss" && m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
        }
        if (format === "ss") return String(Math.max(0, Math.ceil(v)))
        if (/^0(\.0{1,3})?$/.test(format)) return v.toFixed(format.length > 1 ? format.length - 2 : 0)
        return v.toFixed(fallbackDecimals)
    }
    // Fills a template; { text, missing }: missing = a placeholder had no value.
    function fillTemplate(reader, template, source, arranging) {
        const conditions = [source.condition].concat(source.more)
        const reads = []
        let missing = false
        const text = String(template).replace(/\{([^{}:]+?)(\d*)(?::([^{}]+))?\}/g, (whole, name, digits, format) => {
            // "{2}": the name is all digits.
            let key, n
            if (/^\d+$/.test(name + digits)) { key = "auto"; n = Number(name + digits) }
            else { key = placeholderNames[name.trim()]; n = digits !== "" ? Number(digits) : 1 }
            if (!key || n < 1 || n > conditions.length) return whole
            if (reads[n] === undefined) reads[n] = readSource(reader, conditions[n - 1])
            const r = reads[n]
            if (!r) {
                missing = true
                return arranging ? "--" : source.empty
            }
            const f = format || ""
            switch (key) {
            case "value": return formatNumber(r.value, f, source.decimals)
            case "max": return formatNumber(r.max, f, source.decimals)
            case "percent": return formatNumber(r.progress * 100, f, source.decimals) + (f === "" || f.startsWith("0") ? "%" : "")
            case "stacks": return String(r.stacks || 0)
            case "left": return r.timeLeft >= 0 ? formatNumber(r.timeLeft, f, 1) : arranging ? "--" : source.empty
            default: return f !== "" && r.text !== "" ? formatNumber(r.value, f, source.decimals) : r.text || ""
            }
        })
        return { text: text, missing: missing }
    }
    // The whole text: { text, hidden }. `arranging`: a value that is missing
    // shows as "--", never hidden, so the text can still be seen and placed.
    function composeText(reader, mode, staticText, sourceText, arranging) {
        if (mode === "static") return { text: staticText, hidden: false }
        const source = parseTextSource(sourceText)
        if (mode === "template") {
            const t = fillTemplate(reader, staticText, source, arranging)
            return { text: t.text, hidden: t.missing && !arranging && source.hideEmpty }
        }
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
                      spreadOpacity: 70,
                      hidden: d.show === "never" || (d.show === "active" && triggers.length > 0 && !anyActive),
                      playing: false, stacks: 0, text: "", results: results, driving: drive === null ? -1 : drive,
                      style: styleOf(triggers, results) }
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
