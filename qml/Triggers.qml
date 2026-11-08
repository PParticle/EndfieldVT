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
//     once: "none" | "flash" | "bounce" | "sweep" | "ring", onceColor, onceSeconds:
//                        plays once as the trigger starts to hold (ControlView)
//   Bars also have the condition 进度条已满 ({ type: "barFull", hold }): met
//   for `hold` seconds from when the bar fills (runBar).
QtObject {
    readonly property var types: [
        { value: "buff", label: "Buff/Debuff", desc: "目标身上存在（或不存在）指定 Buff/Debuff" },
        { value: "atb", label: "技力", desc: "技力值或可用格数" },
        { value: "ultimate", label: "终结技", desc: "终结技充能状态或已就绪" },
        { value: "combo", label: "连携技", desc: "连携技冷却状态或已就绪" },
        { value: "hp", label: "生命值(HP)", desc: "目标的生命值（百分比判定）" },
        { value: "poise", label: "失衡", desc: "目标失衡状态或失衡值" },
        { value: "lock", label: "锁定目标", desc: "是否存在已锁定的目标" },
        { value: "combat", label: "战斗状态", desc: "小队处于战斗状态中" },
        { value: "skillCast", label: "技能释放", desc: "释放指定技能后的一段时间内" },
        { value: "always", label: "始终满足", desc: "忽略游戏数据，始终判定为满足" },
    ]
    // Bars: also 进度条已满, judged on the bar itself (runBar), not the game data.
    readonly property var barTypes: types.slice(0, -1).concat([
        { value: "barFull", label: "进度条已满", desc: "进度条刚填满时满足，持续设定的时长" }
    ], types.slice(-1))
    function label(type) {
        for (const t of barTypes) if (t.value === type) return t.label
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
        { label: "沿边框流光", value: "flow" }, { label: "像素边框", value: "pixel" }
    ]
    readonly property var onces: [
        { label: "无", value: "none" }, { label: "闪光", value: "flash" },
        { label: "弹跳", value: "bounce" }, { label: "扫光", value: "sweep" },
        { label: "光圈扩散", value: "ring" }
    ]
    readonly property var loops: [
        { label: "无", value: "none" }, { label: "脉冲 (缩放)", value: "pulse" },
        { label: "呼吸 (透明度)", value: "breathe" }, { label: "闪烁", value: "blink" },
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
            // One-shot animations, by trigger: ControlView plays each as it
            // turns up here (the trigger has just started to hold).
            if (t.once && t.once !== "none") {
                if (!s.onces) s.onces = []
                s.onces.push({ key: i, type: t.once, color: t.onceColor || "#ffffff",
                               seconds: Math.max(0.05, Number(t.onceSeconds) || 0.4) })
            }
        }
        return s
    }
    // A member's style: its group's, with its own fields on top.
    function mergeStyle(group, own) { return Object.assign({}, group || {}, own || {}) }
    function hasStyle(t) {
        return !!t.tint || (t.alpha !== undefined && Number(t.alpha) < 100)
            || (t.glow && t.glow !== "none") || (t.loop && t.loop !== "none") || (t.once && t.once !== "none")
    }

    readonly property var motions: [
        { label: "无", value: "none" }, { label: "淡入淡出", value: "fade" },
        { label: "滑动", value: "slide" }, { label: "弹出缩回", value: "pop" }
    ]
    readonly property var slideFroms: [
        { label: "自下方", value: "down" }, { label: "自上方", value: "up" },
        { label: "自左侧", value: "left" }, { label: "自右侧", value: "right" }
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
        { label: "主控干员", value: "main" }, { label: "1号位", value: "slot1" }, { label: "2号位", value: "slot2" },
        { label: "3号位", value: "slot3" }, { label: "4号位", value: "slot4" },
        { label: "队伍成员 ×4", value: "each" }
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
        { label: "任意队伍成员", value: "anySquad" }, { label: "锁定目标", value: "target" },
        { label: "任意敌方", value: "anyEnemy" }
    ])
    readonly property var hpUnits: squadUnits.concat([{ label: "锁定目标", value: "target" }])
    readonly property var castUnits: squadUnits.concat([
        { label: "任意队伍成员", value: "anySquad" }, { label: "任意敌方", value: "anyEnemy" }
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
        case "barFull": return { type: type, hold: 0.5 }
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
    // 进度条已满: holds the bar full and flashes it once.
    function makeBarTrigger(type) {
        const c = makeCondition(type)
        if (type === "barFull")
            return { conditions: [c], mode: "all", effect: "none", timing: "follow", reverse: false,
                     range: "full", rangeFrom: 0, rangeTo: 100, once: "flash", onceColor: "#ffffff", onceSeconds: 0.4 }
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
    // show "active". Show "never": hidden. `state`: the bar's own object,
    // kept between calls, for 进度条已满 (barFullState).
    function runBar(reader, text, state, nowMs) {
        const d = parseTriggers(text)
        const never = d.show === "never"
        if (d.list.length === 0) return { progress: 1, text: "", stacks: 0, hidden: never, results: [], driving: -1, style: {}, playing: false }
        state = state || {}
        const now = nowMs || Date.now()
        // Each condition read once, though the triggers are gone through twice.
        const cache = new Map()
        const plain = { evaluate: c => { if (!cache.has(c)) cache.set(c, reader.evaluate(c)); return cache.get(c) } }
        const hasFull = t => t.conditions.some(c => c && c.type === "barFull")
        // The progress without the 进度条已满 triggers is what fills; then those.
        const plainResults = d.list.map(t => hasFull(t) ? null : evaluateTrigger(plain, t))
        const full = barFullState(barDrive(d.list, plainResults), state, now)
        const withFull = { evaluate: c => c && c.type === "barFull" ? full(c) : plain.evaluate(c) }
        const results = d.list.map((t, i) => plainResults[i] || evaluateTrigger(withFull, t))
        const drive = barDrive(d.list, results)
        const r = drive.index >= 0 ? results[drive.index] : null
        return { progress: drive.progress, text: r ? r.text || "" : "", stacks: r ? r.stacks || 0 : 0,
                 hidden: never || (d.show === "active" && !results.some(x => x.active)),
                 results: results, driving: drive.index, style: styleOf(d.list, results),
                 // Frames until a 进度条已满 ends on time.
                 playing: full.holding }
    }
    // The first active trigger that gives progress: { index, progress, timeLeft, timed }.
    // A 进度条已满 trigger gives a full bar.
    function barDrive(list, results) {
        for (let i = 0; i < list.length; ++i) {
            const t = list[i], r = results[i]
            if (!r || !r.active || t.drives === false) continue
            if (t.conditions.length > 0 && t.conditions[0].type === "barFull") return { index: i, progress: 1, timeLeft: -1, timed: false }
            const p = Math.max(0, Math.min(1, barProgress(t, r)))
            return { index: i, progress: t.reverse ? 1 - p : p, timeLeft: r.timeLeft,
                     timed: t.conditions.length > 0 && ["combo", "buff", "skillCast"].includes(t.conditions[0].type) }
        }
        return { index: -1, progress: 0, timeLeft: -1, timed: false }
    }
    // When the bar fills: its progress reaches 99.5%, or a timer filling it
    // (a cooldown, reversed buff time) runs out. Reads come every 100 ms, so
    // the last one before a cooldown ends can be short of full; the timer
    // ending counts too. Fires once, then again only after the bar has
    // dropped below 97%. Returns a reader for 进度条已满 conditions (met for
    // their `hold` seconds after firing) with `holding` set.
    function barFullState(base, state, now) {
        const filled = base.progress >= 0.995
        const prev = state.barPrev
        const ended = !!prev && prev.nearEnd && (base.index !== prev.index || base.progress < prev.progress - 0.2)
        if (state.barArmed === undefined) {
            state.barArmed = !filled          // already full when first seen: no flash
        } else if (state.barArmed && (filled || ended)) {
            state.barFiredAt = now
            state.barArmed = false
        } else if (!state.barArmed && base.progress < 0.97 && !ended) {
            state.barArmed = true
        }
        state.barPrev = { index: base.index, progress: base.progress,
                          nearEnd: base.timed && base.timeLeft >= 0 && base.timeLeft <= 0.35 && base.progress >= 0.5 }
        const since = state.barFiredAt !== undefined ? (now - state.barFiredAt) / 1000 : Infinity
        let holding = false
        const read = c => {
            const hold = Math.max(0.05, Number(c.hold) || 0.5)
            const on = since < hold
            holding = holding || on
            return { available: true, active: on, progress: on ? 1 : 0, value: on ? 1 : 0, max: 1, stacks: 0,
                     timeLeft: on ? hold - since : -1, infinite: false, text: "",
                     note: on ? "刚填满（还剩 " + (hold - since).toFixed(1) + " 秒）" : filled ? "已满（等待下次填满）" : "未填满" }
        }
        return Object.defineProperty(read, "holding", { get: () => holding })
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
        { label: "自动", value: "auto" }, { label: "数值", value: "value" },
        { label: "数值与上限", value: "ratio" }, { label: "百分比", value: "percent" },
        { label: "层数", value: "stacks" }
    ]
    function makeTextSource(type) {
        return { condition: makeCondition(type), show: "auto", decimals: 0, empty: "", hideEmpty: true }
    }
    function parseTextSource(text) {
        let d = null
        try { d = JSON.parse(text || "") } catch (e) {}
        if (!d || typeof d !== "object" || !d.condition) return Object.assign(makeTextSource("buff"), { more: [] })
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
