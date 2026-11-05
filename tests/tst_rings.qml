import QtQuick
import QtTest
import "../package/contents/ui/rings.js" as Rings

// Unit tests for the panel ring logic. Run: qmltestrunner -input tests/tst_rings.qml
TestCase {
    name: "Rings"

    function test_sectionsOf_groups_by_max_used_and_earliest_reset() {
        const s = Rings.sectionsOf({limits: [
            {label: "Gemini Pro", used: 20, resets_at: 200, group: "Gemini"},
            {label: "Claude", used: 50, resets_at: 300, group: "Claude / GPT-OSS"},
            {label: "Gemini Flash", used: 60, resets_at: 100, group: "Gemini"}]})
        compare(s, [{group: "Gemini", used: 60, resetsAt: 100}, {group: "Claude / GPT-OSS", used: 50, resetsAt: 300}])
    }

    function test_shade() {
        compare(Rings.shade("#D97757", 0), "#d97757")
        compare(Rings.shade("#ffffff", 1), "#a6a6a6")      // light base darkens: 255*(1-0.35)
        compare(Rings.shade("#000000", 1), "#4d4d4d")      // dark base lightens: 255*0.3
        compare(Rings.shade("#ff000000", 1), "#4d4d4d")    // alpha dropped
        compare(Rings.shade("#fff", 0), "#ffffff")
        verify(/^#[0-9a-f]{6}$/.test(Rings.shade("#4285f4", 3)))
    }

    function test_sectionArcs() {
        compare(Rings.sectionArcs(1, 8), [{start: 0, end: 360}])
        compare(Rings.sectionArcs(2, 8), [{start: 4, end: 176}, {start: 184, end: 356}])
    }

    function test_drawnArcs_leave_a_visible_gap_with_round_caps() {
        // radius 10, line 4: each cap reaches 2px past its angle = 2/10 rad ≈ 11.46°
        const arcs = Rings.drawnArcs(2, 8, 4, 10)
        const cap = 2 / 10 * 180 / Math.PI
        fuzzyCompare(arcs[0].start, 4 + cap, 1e-6)
        fuzzyCompare(arcs[0].end, 176 - cap, 1e-6)
        verify(arcs[1].start - cap - (arcs[0].end + cap) >= 8 - 1e-6)
        compare(Rings.drawnArcs(1, 8, 4, 10), [{start: 0, end: 360}])   // single ring: no caps to trim
        compare(Rings.drawnArcs(2, 8, 40, 10)[0].end, Rings.drawnArcs(2, 8, 40, 10)[0].start) // never negative
    }

    function test_ringMetrics_scales_size_and_line() {
        compare(Rings.ringMetrics(30, 100, 13, false), {diameter: 30, lineWidth: 3.9})
        compare(Rings.ringMetrics(30, 50, 20, false), {diameter: 15, lineWidth: 3})
        compare(Rings.ringMetrics(30, 10, 13, false).diameter, 12)           // size floored at 40%
        compare(Rings.ringMetrics(30, 100, 99, false).lineWidth, 7.5)        // line capped at 25%
        compare(Rings.ringMetrics(10, 100, 5, false).lineWidth, 1)           // never thinner than 1px
        // nested: rings are 15% of the outer size apart, so the line can't exceed 14%
        compare(Rings.ringMetrics(100, 100, 25, true), {diameter: 100, lineWidth: 14})
        compare(Rings.ringMetrics(100, 100, 10, true), {diameter: 100, lineWidth: 10})
    }

    function test_ringsFor_hides_errors_and_hidden_sections_keeps_shade_index() {
        const providers = [
            {id: "antigravity", limits: [{label: "g", used: 0, resets_at: 1, group: "Gemini"}], error: null},
            {id: "codex", limits: [], error: "Not signed in"},
            {id: "claude", limits: [{label: "5h", used: 25, resets_at: 1, group: "5h"},
                                    {label: "7d", used: 120, resets_at: 2, group: "7d"}], error: null}]
        const rings = Rings.ringsFor(providers, {hidden: ["claude/5h"], colors: {}, overrides: {}, textColor: "#eeeeee"})
        compare(rings.map(r => r.id), ["claude", "antigravity"])
        compare(rings[0].sections.length, 1)
        compare(rings[0].sections[0].key, "claude/7d")
        compare(rings[0].sections[0].remaining, 0)
        compare(rings[0].sections[0].color, Rings.shade("#d97757", 1))
        compare(rings[1].sections[0].remaining, 1)
    }

    function test_ringsFor_colors() {
        const providers = [{id: "codex", limits: [{label: "5h", used: 0, group: "5h"}, {label: "7d", used: 0, group: "7d"}], error: null}]
        let r = Rings.ringsFor(providers, {hidden: [], colors: {}, overrides: {}, textColor: "#232629"})
        compare(r[0].sections[0].color, "#232629")                         // codex default follows theme
        r = Rings.ringsFor(providers, {hidden: [], colors: {codex: "#00ff00"}, overrides: {"codex/7d": "#123456"}, textColor: "#232629"})
        compare(r[0].sections[0].color, "#00ff00")
        compare(r[0].sections[1].color, "#123456")
    }

    function test_ringsFor_empty_when_nothing_visible() {
        compare(Rings.ringsFor([], {hidden: [], colors: {}, overrides: {}, textColor: "#fff"}), [])
        const allHidden = [{id: "codex", limits: [{label: "5h", used: 0, group: "5h"}], error: null}]
        compare(Rings.ringsFor(allHidden, {hidden: ["codex/5h"], colors: {}, overrides: {}, textColor: "#fff"}), [])
    }

    function test_ringsFor_empty_when_script_failed() {
        const providers = [{id: "codex", limits: [{label: "5h", used: 0, group: "5h"}], error: null}]
        compare(Rings.ringsFor(providers, {hidden: [], colors: {}, overrides: {}, textColor: "#fff", scriptFailed: true}), [])
    }

    function test_mergeKnownSections_keeps_errored_provider() {
        const prev = {antigravity: ["Gemini", "Claude / GPT-OSS"], claude: ["5h"]}
        const merged = Rings.mergeKnownSections(prev, [
            {id: "antigravity", limits: [], error: "Antigravity is not running"},
            {id: "claude", limits: [{group: "5h"}, {group: "7d"}], error: null}])
        compare(merged, {antigravity: ["Gemini", "Claude / GPT-OSS"], claude: ["5h", "7d"]})
    }
}
