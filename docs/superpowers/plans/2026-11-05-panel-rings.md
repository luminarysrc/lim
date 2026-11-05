# Panel Rings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the panel's icon + peak-percentage with one ring per provider, split into one section per quota, each a fuel gauge (full = 0% used, empty = 100%), with layout, color and per-section visibility settings.

**Architecture:** The Bash script tags every limit with a `group`. A pure-JS library (`rings.js`, `.pragma library`) turns the provider JSON plus settings into a flat list of drawable rings. That keeps all decisions unit-testable with `qmltestrunner`. A `Canvas`-based `Ring.qml` only draws. `CompactRepresentation.qml` lays rings out in one of three layouts. A new settings page edits colors, layout and hidden sections, using a section list cached in config by `main.qml`.

**Tech Stack:** KDE Plasma 6 plasmoid (QML, Kirigami, KCMUtils, `org.kde.kquickcontrols` ColorButton), Bash + jq, QtTest via `/usr/bin/qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-11-05-panel-rings-design.md`

## Global Constraints

- KDE Plasma 6 plasmoid, plain QML plus the existing Bash + jq script. No new runtime dependencies.
- `bash tests/test.sh` keeps passing. `shellcheck package/contents/code/ai-limits.sh tests/test.sh` stays clean.
- Full ring = 0% used, empty = 100% used. The colored arc length of a section = `1 - used/100`, clamped to [0, 1].
- Hidden sections and errored providers affect **only** the panel. The popup (`FullRepresentation`, `ProviderSection`, `LimitBar`) is untouched.
- Config keys for sections are `providerId + "/" + group` (e.g. `antigravity/Gemini`, `claude/5h`).
- Default colors: Claude `#d97757`, Antigravity `#4285f4`, Codex = empty string meaning "theme text color" (resolved live, never stored).
- Layouts: `side` (default), `lettered` (C / X / A), `nested` (Claude outer, Codex middle, Antigravity inner).
- Antigravity groups: `Gemini` and `Claude / GPT-OSS` (exact strings).

## Review Focus

1. **Antigravity not running on a settings visit.** The cached section list must keep Antigravity's last-known groups instead of wiping them when the provider errors. Owned by Task 2 (`mergeKnownSections`).
2. **Theme switches between light and dark.** Codex's default color must follow `Kirigami.Theme.textColor` live, and the derived shades must follow too. Owned by Task 2 (`ringsFor` takes the resolved text color as an argument, Task 3 binds it).
3. **Theme colors with alpha (`#aarrggbb`) or uppercase hex** passed into shade math must not produce `NaN` colors. Owned by Task 2 (`shade` test).
4. **Every ring filtered out** (first load, all errors, all hidden, script failure). The panel must still show a clickable icon. Owned by Task 2 (`ringsFor` returns `[]`) and Task 3 (fallback icon).
5. **A group with several models at different usage.** The section uses the max `used` and the earliest `resets_at`, not the first model's. Owned by Task 2 (`sectionsOf` test).

---

### Task 1: `group` field in the data script

**Files:**
- Modify: `package/contents/code/ai-limits.sh` (`JQ_LIB` `limit`, `parse_claude`, `parse_codex`, `parse_antigravity`)
- Test: `tests/test.sh`

**Interfaces:**
- Produces: every limit object is `{label, used, resets_at, group}`. Claude/Codex: `group == label`. Antigravity: `group` is `"Gemini"` when `.modelId` starts with `gemini` (or, when `.modelId` is absent, `.label` starts with `Gemini`), otherwise `"Claude / GPT-OSS"`. Antigravity output is sorted Gemini group first, then by label.

- [ ] **Step 1: Update the existing expectations and add an Antigravity grouping test**

In `tests/test.sh`, add `"group":"5h"` / `"group":"7d"` to every Claude and Codex expected object (field order: `label, used, resets_at, group`). Replace the Antigravity test with:

```bash
expect "antigravity: grouped by model id, Gemini first, missing fraction means exhausted" \
  '[{"label":"Gemini 3 Pro","used":20,"resets_at":1763632800,"group":"Gemini"},{"label":"Gemini Flash","used":0,"resets_at":1763632800,"group":"Gemini"},{"label":"Claude Sonnet","used":100,"resets_at":1763632800,"group":"Claude / GPT-OSS"},{"label":"GPT-OSS 120B (Medium)","used":0,"resets_at":1763632800,"group":"Claude / GPT-OSS"}]' \
  "$(parse_antigravity <<< '{"userStatus": {"cascadeModelConfigData": {"clientModelConfigs": [
    {"label": "Gemini 3 Pro", "modelId": "gemini-3-pro", "quotaInfo": {"remainingFraction": 0.8, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "Claude Sonnet", "modelId": "claude-sonnet-4-6", "quotaInfo": {"resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "GPT-OSS 120B (Medium)", "modelId": "gpt-oss-120b-medium", "quotaInfo": {"remainingFraction": 1, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "Gemini Flash", "quotaInfo": {"remainingFraction": 1, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "No quota model"}]}}}')"
```

("Gemini Flash" has no `modelId`, which covers the label fallback.)

- [ ] **Step 2: Run tests, expect failures**

Run: `bash tests/test.sh`
Expected: the Claude, Codex and Antigravity parser lines print `FAIL` (no `group` yet). The rest print `ok`.

- [ ] **Step 3: Implement**

Change `limit` to `limit($label; $used; $resets_at; $group)`, appending `group: $group`. Claude/Codex pass their label. In `parse_antigravity` compute the group from `.modelId // ""` with `startswith("gemini")`, falling back to `(.label // "") | startswith("Gemini")`. Replace `sort_by(.label)` with `sort_by(.group != "Gemini", .label)`.

- [ ] **Step 4: Run tests and shellcheck**

Run: `bash tests/test.sh && shellcheck package/contents/code/ai-limits.sh tests/test.sh`
Expected: every line `ok`, exit 0, no shellcheck output. Also run `bash package/contents/code/ai-limits.sh antigravity | jq -c '.providers[0].limits[] | [.label, .group]'` and confirm the live data shows Gemini models in `Gemini` and Claude/GPT-OSS models in `Claude / GPT-OSS`.

- [ ] **Step 5: Commit**

```bash
git add package/contents/code/ai-limits.sh tests/test.sh
git commit -m "Tag every limit with its quota group"
```

---

### Task 2: Ring logic library

**Files:**
- Create: `package/contents/ui/rings.js` (`.pragma library`)
- Create: `tests/tst_rings.qml` (QtTest `TestCase`, imports `"../package/contents/ui/rings.js" as Rings`)
- Modify: `tests/test.sh` (at the end, before `exit`, run `qmltestrunner -input "$(dirname "$0")/tst_rings.qml"` and count a non-zero exit as one failure)

**Interfaces:**
- Consumes: provider objects `{id, name, limits: [{label, used, resets_at, group}], error}` from Task 1.
- Produces (all pure, no QML types; colors are `"#rrggbb"` strings):
  - `PROVIDER_ORDER = ["claude", "codex", "antigravity"]`, `LETTERS = {claude: "C", codex: "X", antigravity: "A"}`, `DEFAULT_COLORS = {claude: "#d97757", codex: "", antigravity: "#4285f4"}`
  - `sectionKey(providerId: string, group: string) -> string`: `providerId + "/" + group`
  - `sectionsOf(provider) -> [{group, used, resetsAt}]`: distinct groups in first-appearance order. `used` = max of members, `resetsAt` = min non-null `resets_at` (or `null`).
  - `shade(base: string, index: int) -> string`: index 0 returns `base` normalised to lowercase `#rrggbb`. Accepts `#rgb`, `#rrggbb`, `#aarrggbb` (alpha dropped). For index ≥ 1, if relative luminance of base > 0.7, mix toward black by `min(0.35 * index, 0.8)`, otherwise mix toward white by `min(0.3 * index, 0.8)`.
  - `sectionArcs(count: int, gapDegrees: number) -> [{start, end}]`: degrees clockwise from 12 o'clock. Count 1 → `[{start: 0, end: 360}]` (no gap). Otherwise section i spans `[i*360/count + gap/2, (i+1)*360/count - gap/2]`.
  - `ringsFor(providers, settings) -> [{id, letter, sections: [{key, label, remaining, color}]}]` where `settings = {hidden: [key], colors: {providerId: string}, overrides: {key: string}, textColor: string}`. Rings come in `PROVIDER_ORDER`. Providers with `error` or no visible sections are omitted. The base color is `colors[id]` if non-empty, else `DEFAULT_COLORS[id]` if non-empty, else `textColor`. A section's color is `overrides[key]` if non-empty, else `shade(base, i)`, where `i` is its index among **all** of the provider's sections (hidden ones included). `remaining = clamp(1 - used/100, 0, 1)`.
  - `mergeKnownSections(previous: {providerId: [group]}, providers) -> {providerId: [group]}`: providers without error replace their entry with their current groups. Errored or absent providers keep their previous entry.

- [ ] **Step 1: Write the failing tests in `tests/tst_rings.qml`**

One `TestCase { name: "Rings" }` with these functions (use `compare` / `verify`):

```qml
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
    verify(/^#[0-9a-f]{6}$/.test(Rings.shade("#4285f4", 3)))
}
function test_sectionArcs() {
    compare(Rings.sectionArcs(1, 8), [{start: 0, end: 360}])
    compare(Rings.sectionArcs(2, 8), [{start: 4, end: 176}, {start: 184, end: 356}])
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
}
function test_mergeKnownSections_keeps_errored_provider() {
    const prev = {antigravity: ["Gemini", "Claude / GPT-OSS"], claude: ["5h"]}
    const merged = Rings.mergeKnownSections(prev, [
        {id: "antigravity", limits: [], error: "Antigravity is not running"},
        {id: "claude", limits: [{group: "5h"}, {group: "7d"}], error: null}])
    compare(merged, {antigravity: ["Gemini", "Claude / GPT-OSS"], claude: ["5h", "7d"]})
}
```

- [ ] **Step 2: Run, expect failure**

Run: `qmltestrunner -input tests/tst_rings.qml`
Expected: fails to load (`rings.js` missing).

- [ ] **Step 3: Implement `package/contents/ui/rings.js`** with the signatures above. Add the `qmltestrunner` call to `tests/test.sh`.

- [ ] **Step 4: Run tests**

Run: `bash tests/test.sh && shellcheck tests/test.sh`
Expected: all shell `ok` lines, then `Totals: 9 passed, 0 failed` from qmltestrunner (7 tests + initTestCase/cleanupTestCase), exit 0.

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/rings.js tests/tst_rings.qml tests/test.sh
git commit -m "Add ring layout and color logic"
```

---

### Task 3: Rings in the panel

**Files:**
- Create: `package/contents/ui/Ring.qml`
- Modify: `package/contents/ui/CompactRepresentation.qml` (rewrite)
- Modify: `package/contents/ui/main.qml` (remove `peakUsage` use in compact, pass rings, cache known sections)
- Modify: `package/contents/config/main.xml`

**Interfaces:**
- Consumes: `Rings.ringsFor`, `Rings.sectionArcs`, `Rings.mergeKnownSections`, `Rings.LETTERS` from Task 2.
- Produces (config entries, group `General`, used by Task 4):
  - `ringLayout` String, default `side` (values `side|lettered|nested`)
  - `colorClaude` String default `#d97757`, `colorCodex` String default empty, `colorAntigravity` String default `#4285f4`
  - `sectionColors` String default `{}` (JSON object key → `#rrggbb`)
  - `hiddenSections` StringList default empty
  - `knownSections` String default `{}` (JSON `{providerId: [group]}`, written by `main.qml` only)
- Produces: `Ring.qml` properties `sections: var` (`[{remaining, color}]`), `trackColor: color`, `letter: string` (empty = none), `lineWidth: real`. It draws with `Canvas` and repaints when any of them change. Arcs come from `Rings.sectionArcs(sections.length, 8)`. The track is drawn first across each arc, then the colored part from the arc start clockwise for `remaining` of its length. Round caps.

- [ ] **Step 1: Add the config entries** to `main.xml` exactly as listed.

- [ ] **Step 2: Write `Ring.qml`.** Track color = `Kirigami.Theme.textColor` with alpha 0.15 (set by the caller). Line width defaults to `width * 0.13`. The letter is a centered bold `PlasmaComponents.Label`, `font.pixelSize: height * 0.42`.

- [ ] **Step 3: Wire `main.qml`**

```qml
readonly property var rings: Rings.ringsFor(providers, {
    hidden: Plasmoid.configuration.hiddenSections,
    colors: {claude: Plasmoid.configuration.colorClaude, codex: Plasmoid.configuration.colorCodex,
             antigravity: Plasmoid.configuration.colorAntigravity},
    overrides: JSON.parse(Plasmoid.configuration.sectionColors || "{}"),
    textColor: Kirigami.Theme.textColor.toString()
})
```

In `onNewData` after parsing, compute `Rings.mergeKnownSections(JSON.parse(knownSections || "{}"), result.providers)` and write it back only if the `JSON.stringify` differs. Pass `rings: root.rings` and `layout: Plasmoid.configuration.ringLayout` to `CompactRepresentation`. Keep `peak()` for the tooltip. Keep `peakUsage` only if still used elsewhere, otherwise delete it.

- [ ] **Step 4: Rewrite `CompactRepresentation.qml`**

Properties `rings: var`, `layout: string`. Three states:
- `rings.length === 0`: the old `Kirigami.Icon { source: Plasmoid.icon }` only (Review Focus 4).
- `side` / `lettered`: a `GridLayout` with `flow` set to `TopToBottom` when `vertical`, else `LeftToRight`. One `Ring` per entry, square, sized to panel thickness (`height` when horizontal, `width` when vertical). `letter: layout === "lettered" ? modelData.letter : ""`. Size hints: `Layout.minimumWidth` = row width when horizontal; when vertical, `Layout.minimumHeight` = column height.
- `nested`: a square item of panel thickness with stacked, centered `Ring`s. Ring k (in `rings` order) has diameter `size * (1 - k * 0.3)` and `lineWidth: size * 0.1`. With fewer rings the outer slots are taken first.

The MouseArea `onClicked` behavior and `hoverEnabled` stay as now.

- [ ] **Step 5: Verify**

Run: `qmllint -I /usr/lib/qt6/qml package/contents/ui/*.qml` (no new errors beyond the existing unresolved-Plasma-import warnings), then `bash tests/test.sh`.
Then `kpackagetool6 -t Plasma/Applet -u package && plasmawindowed com.github.ailimits` (use `-i` on first install). Confirm by eye and with a screenshot:
- rings are visible, with Claude orange, Codex in the theme text color and Antigravity blue
- the Claude 7d section is mostly empty (live data was 88% used)
- clicking opens the popup

Temporarily set `ringLayout` through the settings dialog (Task 4) or `kwriteconfig6` to check `lettered` and `nested`.

- [ ] **Step 6: Commit**

```bash
git add package/contents/ui/Ring.qml package/contents/ui/CompactRepresentation.qml package/contents/ui/main.qml package/contents/config/main.xml
git commit -m "Show provider rings in the panel"
```

---

### Task 4: Appearance settings page

**Files:**
- Create: `package/contents/ui/configAppearance.qml`
- Create: `package/contents/ui/ProviderAppearance.qml`
- Modify: `package/contents/config/config.qml` (add `ConfigCategory { name: i18n("Appearance"); icon: "preferences-desktop-color"; source: "configAppearance.qml" }`)

**Interfaces:**
- Consumes: the config entries from Task 3 (as `cfg_ringLayout`, `cfg_colorClaude`, `cfg_colorCodex`, `cfg_colorAntigravity`, `cfg_sectionColors`, `cfg_hiddenSections`, `cfg_knownSections`). Also `Rings.shade`, `Rings.sectionKey`, `Rings.DEFAULT_COLORS`.
- Produces: `ProviderAppearance.qml` with properties `providerId`, `name`, `baseColor: string` (the cfg value, may be empty), `groups: var`, `hidden: var`, `overrides: var`, and signals `baseColorEdited(string)`, `hiddenEdited(var)`, `overridesEdited(var)`.

- [ ] **Step 1: Write `configAppearance.qml`** as a `KCM.SimpleKCM` with a `Kirigami.FormLayout`:
  - A "Layout:" `QQC2.ComboBox` with entries "Side by side" / "Side by side with letters" / "Nested", mapping to `side` / `lettered` / `nested`.
  - One `ProviderAppearance` per provider in `Rings.PROVIDER_ORDER`, with `groups` taken from `JSON.parse(cfg_knownSections)[id] ?? []`.
  - Each signal writes back to the matching `cfg_` property. Arrays and objects are reassigned as new values so KCM notices the change. Overrides are written with `JSON.stringify`.

- [ ] **Step 2: Write `ProviderAppearance.qml`**
  - A header row: the provider name, a `KQuickControls.ColorButton` (`import org.kde.kquickcontrols`) showing the effective base color (`baseColor`, else `DEFAULT_COLORS`, else `Kirigami.Theme.textColor`), and a "Default" button that emits `baseColorEdited("")`. The button is only enabled when `baseColor !== Rings.DEFAULT_COLORS[providerId]`.
  - One row per group: a `QQC2.CheckBox` "Show in panel" labelled with the group (checked = key not in `hidden`), a `ColorButton` showing `overrides[key] ?? shade(effectiveBase, index)`, and a reset button enabled only when an override exists.
  - When `groups` is empty, a dimmed label: "Sections appear here after the first refresh."

- [ ] **Step 3: Verify**

Run: `qmllint -I /usr/lib/qt6/qml package/contents/ui/config*.qml package/contents/ui/ProviderAppearance.qml`, then reinstall (`kpackagetool6 -t Plasma/Applet -u package`) and open the settings with `plasmawindowed com.github.ailimits` → right-click → Configure. Check each of these:
- Hiding `claude/5h` makes the Claude 7d section a full ring.
- Changing the Claude color re-derives the 7d shade.
- Overriding Codex 7d sticks after Apply and survives a restart.
- "Default" restores Codex to the theme color.
- Switching layout redraws immediately.
- The popup still lists Claude 5h while it's hidden.

- [ ] **Step 4: Commit**

```bash
git add package/contents/ui/configAppearance.qml package/contents/ui/ProviderAppearance.qml package/contents/config/config.qml
git commit -m "Add appearance settings for rings"
```

---

### Task 5: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1:** Make these changes:
  - Replace the panel bullet ("The panel shows your highest usage…") with a description of the rings: one per provider, a section per quota, full = unused.
  - Mention the Appearance settings (layout, colors, hidden sections).
  - Add `{"group": …}` to the JSON example.
  - Add a `rings.js` / `Ring.qml` line to the file tree.
  - Note under Development that `tests/test.sh` also runs `qmltestrunner` (from Qt's `qt6-declarative` tools).
  - Fix the stale `cd ai-limits` install line to `cd lim`.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document panel rings"
```
