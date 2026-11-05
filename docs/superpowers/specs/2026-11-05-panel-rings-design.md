# Panel rings: design

## Intent

Today the panel shows one icon and the single highest usage percentage. That number says "something is
close to a limit" but not *which* provider or *which* window. The new panel view replaces it with one
ring per provider (Claude Code, Codex, Antigravity), so a glance answers "how much do I have left, and
where" for every quota at once.

A ring is a fuel gauge: **full = nothing used (0%), empty = limit reached (100%)**.

## What gets built

### Rings and sections

- One ring per enabled provider. The existing `showClaude` / `showCodex` / `showAntigravity`
  checkboxes still decide which providers exist at all.
- Each ring is divided into equal **sections**, one per quota of that provider. Each section is its
  own small gauge: its colored arc shrinks from full to empty as that quota's usage goes from 0% to
  100%. The unused part of the section stays visible as a faint track.
  - Claude Code: one section per limit the API returns: `5h`, `7d`, and when present `7d · Opus`
    and `7d · Sonnet`. Usually two, at most four.
  - Codex: `5h` and `7d` (primary and secondary window).
  - Antigravity: one section per **shared quota**, not per model. Gemini models share one quota.
    Third-party models (Claude, GPT-OSS) share another. So that's normally two sections: "Gemini" and
    "Claude / GPT-OSS".
- With two sections the ring is two halves. With N sections it's N equal arcs. With one section
  it's a full ring.
- Sections start at 12 o'clock and run clockwise, separated by a small gap. Order: shortest window
  first (5h before 7d, then the 7d model-specific ones). For Antigravity: Gemini first, then
  third-party. *(my call)*
- If a provider returns an error (not signed in, Antigravity not running, etc.) **its ring is not
  shown**. The popup still shows the error as it does today.
- If a provider has no sections left (all hidden, or no limits returned) its ring is not shown.
- **When no ring is shown at all** (before the first fetch, every provider errored, every section
  hidden, or the script itself failed), the panel falls back to the plain widget icon so there's
  always something to click to open the popup and read the error. *(my call)*

### Hiding sections

- Each section can be hidden from the ring. The remaining sections divide the whole ring between
  them, so hiding one of two sections makes the other a **full** ring, not a half.
- Hiding affects **only the panel ring**. The popup keeps showing every limit.

### Layout (user setting)

Three layouts, chosen in settings (mockups were reviewed and the user wants all three as options):

| Value      | Look                                                                      |
|------------|---------------------------------------------------------------------------|
| `side`     | **Default.** Rings side by side.                                         |
| `lettered` | Rings side by side, each with a letter in the center: C (Claude), X (Codex), A (Antigravity). *(letters are my call)* |
| `nested`   | One icon-sized stack of concentric rings: Claude outer, Codex middle, Antigravity inner. |

- On a vertical panel, `side` and `lettered` stack top to bottom.
- Ring size follows the panel thickness, like any panel icon.
- Clicking still toggles the existing popup. The hover tooltip stays as it is.
- The old peak-percentage label is removed from the panel. The tooltip still lists per-provider usage.

### Colors

- Default provider colors: **Antigravity blue, Claude orange, Codex white.** *(exact values are
  the builder's call; suggested `#4285f4`, `#d97757`)*. Codex's default is "white" on dark
  panels. To keep it visible on light panels, the *default* follows the theme's text color (white
  on dark themes, near-black on light ones). Once the user picks a color, that color is used as is.
  *(my call)*
- The user can change each provider's color in settings.
- Sections of a ring use **shades of the provider color**, derived automatically: section 1 is the
  base color and each next section is a step lighter. When the base is too light to lighten (white,
  pale colors) the steps go darker instead. So white Codex gets white 5h and grey 7d.
- Shades are assigned over **all known sections** of the provider, hidden or not, so a quota keeps
  the same shade whatever else is hidden (e.g. Claude 7d stays the lighter shade even when 5h is
  hidden). *(my call)*
- Each section's shade **can also be overridden** by the user. An override wins over the derived
  shade. Clearing the override goes back to the derived one.
- The empty track is a faint version of the theme's text color, so it works on light and dark panels.
  *(my call)*

### Settings page

Added to the existing General page (or a second "Appearance" page, the builder's call):

- Layout: a choice of the three layouts.
- Per provider: a color picker for the base color. Under it, one row per known section with a
  "show in panel" checkbox and an optional color override (shows the derived shade until overridden).
- The section list comes from the **last data the widget fetched**. Antigravity's groups only exist
  once it has answered, so a provider that has never responded shows no section rows. The widget
  stores the last-seen section list in its config so the settings page can read it. *(my call)*

## Data changes (`ai-limits.sh`)

- Every limit gains a `group` field. The ring has one section per distinct `group`, and the popup keeps
  using one row per limit as now.
  - Claude and Codex: `group` = the limit's label (`5h`, `7d`, …).
  - Antigravity: `group` is decided by **model name**. An entry whose `.modelId` starts with
    `gemini` (falling back to a `.label` starting with "Gemini") goes in the `Gemini` group, and
    everything else goes in the third-party group (shown as "Claude / GPT-OSS"). `.modelId` is a
    top-level field of each `clientModelConfigs[]` entry. Trimmed live samples:
    ```json
    {"label":"Gemini 3.8 Flash (High)","modelOrAlias":{"model":"MODEL_PLACEHOLDER_M318"},"quotaInfo":{"remainingFraction":1,"resetTime":"2026-11-12T15:20:47Z"},"modelId":"gemini-3.8-flash-high"}
    {"label":"Claude Opus 4.6 (Thinking)","modelOrAlias":{"model":"MODEL_PLACEHOLDER_M26"},"quotaInfo":{"remainingFraction":1,"resetTime":"2026-11-12T15:20:47Z"},"modelId":"claude-opus-4-6-thinking"}
    {"label":"GPT-OSS 120B (Medium)","modelOrAlias":{"model":"MODEL_OPENAI_GPT_OSS_120B_MEDIUM"},"quotaInfo":{"remainingFraction":1,"resetTime":"2026-11-12T15:20:47Z"},"modelId":"gpt-oss-120b-medium"}
    ```
    (`modelOrAlias.model` is an opaque enum, so don't use it for grouping.)
- Why name-based: checked against a live response on 2026-11-05. The API has **no quota-group
  field** (`clientModelSorts` is display order only, with all models in one group), and every model
  reported the same `remainingFraction` and `resetTime`. So grouping by equal values would merge
  everything into one section.
- A section's usage is the **highest** `used` among its models, and its reset is the earliest
  `resets_at`. Members of a shared quota should agree anyway. Taking the max errs toward "less left".
- Antigravity has announced that third-party models are going away. When they disappear, the
  third-party group simply stops appearing and Gemini becomes a full ring. Nothing special is
  needed.
- Hidden-section and color-override settings are keyed by `providerId/group` (e.g.
  `antigravity/Gemini`, `claude/5h`).

## Goals

- Read every quota's remaining amount from the panel without opening the popup.
- Sensible defaults out of the box: three colored rings, nothing to configure.
- Full control for those who want it: layout, colors, per-section shades, hidden sections.

## Non-goals

- No changes to the popup's content or layout beyond what's needed to keep it working.
- No new providers, no notifications, no history.
- No numeric percentages inside the rings.

## Anti-goals

- A ring that can't be told apart from "used up" when the real problem is an error. That's why
  errored providers are hidden, not drawn empty.
- Hiding a section and getting a half ring with a hole. Hidden means gone, and the rest fill the ring.
- Hiding a section and losing it from the popup.

## Constraints

- KDE Plasma 6 plasmoid, plain QML plus the existing Bash + jq script. No new runtime dependencies.
- Existing tests (`tests/test.sh`) must keep passing. Add parser tests for the `group` field,
  including the Antigravity name-based grouping.
- `shellcheck` stays clean (CI runs it).

## Left to the builder

- Drawing technique (QML `Shape`/`PathArc`, `Canvas`, …), ring thickness, gap size, exact shade
  step.
- Exact color values for the defaults.
- How config is stored (kcfg entry types for the color map, hidden list, cached section list).
- Whether settings live on one page or two.
- README update describing the new panel view and settings.
