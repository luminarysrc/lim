.pragma library

// Panel ring logic: turns provider data and settings into rings ready to draw.
// Pure functions only, tested by tests/tst_rings.qml. Colors are "#rrggbb" strings.

var PROVIDER_ORDER = ["claude", "codex", "antigravity"]
// An empty color means "follow the theme's text color".
var DEFAULT_COLORS = {claude: "#d97757", codex: "", antigravity: "#4285f4"}

function sectionKey(providerId, group) {
    return providerId + "/" + group
}

// One entry per quota group, in first-appearance order.
// A group's usage is its highest member's, its reset the earliest.
function sectionsOf(provider) {
    const sections = []
    const byGroup = {}
    for (const limit of provider.limits || []) {
        const group = limit.group ?? limit.label
        let section = byGroup[group]
        if (!section) {
            section = byGroup[group] = {group: group, used: limit.used ?? 0, resetsAt: limit.resets_at ?? null}
            sections.push(section)
            continue
        }
        section.used = Math.max(section.used, limit.used ?? 0)
        if (limit.resets_at != null && (section.resetsAt == null || limit.resets_at < section.resetsAt))
            section.resetsAt = limit.resets_at
    }
    return sections
}

function parseColor(color) {
    let hex = String(color).replace("#", "")
    if (hex.length === 3) hex = hex.split("").map(c => c + c).join("")
    if (hex.length === 8) hex = hex.slice(2) // #aarrggbb: drop alpha
    return [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) || 0)
}

function toHex(rgb) {
    return "#" + rgb.map(v => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("")
}

function luminance(rgb) {
    const [r, g, b] = rgb.map(v => {
        const c = v / 255
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

// Shade `index` of a base color: 0 is the base itself, each next one a step lighter,
// or a step darker when the base is too light to lighten.
function shade(base, index) {
    const rgb = parseColor(base)
    if (index <= 0) return toHex(rgb)
    if (luminance(rgb) > 0.7) {
        const t = Math.min(0.35 * index, 0.8)
        return toHex(rgb.map(v => v * (1 - t)))
    }
    const t = Math.min(0.3 * index, 0.8)
    return toHex(rgb.map(v => v + (255 - v) * t))
}

// Arcs in degrees clockwise from 12 o'clock, `gapDegrees` apart.
function sectionArcs(count, gapDegrees) {
    if (count <= 1) return [{start: 0, end: 360}]
    const size = 360 / count
    const arcs = []
    for (let i = 0; i < count; i++)
        arcs.push({start: i * size + gapDegrees / 2, end: (i + 1) * size - gapDegrees / 2})
    return arcs
}

var SIZE_RANGE = [40, 100]       // ring diameter, % of panel thickness
var LINE_RANGE = [5, 25]         // line width, % of ring diameter
var NESTED_LINE_MAX = 14         // nested rings sit 15% apart; keep a sliver between them

function clamp(value, range) {
    return Math.min(range[1], Math.max(range[0], value))
}

// Ring diameter and line width in pixels for a panel `thickness` px thick.
function ringMetrics(thickness, sizePercent, linePercent, nested) {
    const diameter = thickness * clamp(sizePercent, SIZE_RANGE) / 100
    let line = clamp(linePercent, LINE_RANGE)
    if (nested) line = Math.min(line, NESTED_LINE_MAX)
    return {diameter: diameter, lineWidth: Math.max(1, Math.round(diameter * line) / 100)}
}

// Arcs to stroke with round caps: each end is pulled in by the cap's own angle,
// so the gap between sections stays visible at any line width.
function drawnArcs(count, gapDegrees, lineWidth, radius) {
    const arcs = sectionArcs(count, gapDegrees)
    if (count <= 1 || radius <= 0) return arcs
    const cap = (lineWidth / 2) / radius * 180 / Math.PI
    return arcs.map(arc => {
        const middle = (arc.start + arc.end) / 2
        const start = Math.min(arc.start + cap, middle)
        return {start: start, end: Math.max(arc.end - cap, start)}
    })
}

// settings: {hidden: [key], colors: {providerId: color}, overrides: {key: color}, textColor, scriptFailed}
// No rings when the script failed: old data must not look current.
function ringsFor(providers, settings) {
    if (settings.scriptFailed) return []
    const hidden = settings.hidden || []
    const colors = settings.colors || {}
    const overrides = settings.overrides || {}
    const rings = []
    for (const id of PROVIDER_ORDER) {
        const provider = (providers || []).find(p => p.id === id)
        if (!provider || provider.error) continue
        const base = colors[id] || DEFAULT_COLORS[id] || settings.textColor
        const sections = sectionsOf(provider)
            .map((section, index) => ({section, index, key: sectionKey(id, section.group)}))
            .filter(entry => !hidden.includes(entry.key))
            .map(({section, index, key}) => ({
                key: key,
                label: section.group,
                remaining: Math.min(1, Math.max(0, 1 - section.used / 100)),
                color: overrides[key] || shade(base, index),
            }))
        if (sections.length > 0)
            rings.push({id: id, sections: sections})
    }
    return rings
}

// Section groups per provider for the settings page. Providers that failed this time
// keep what was seen before, so the settings don't lose them while a tool is closed.
function mergeKnownSections(previous, providers) {
    const known = Object.assign({}, previous || {})
    for (const provider of providers || []) {
        if (provider.error) continue
        known[provider.id] = sectionsOf(provider).map(section => section.group)
    }
    return known
}
