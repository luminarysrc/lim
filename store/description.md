AI Limits puts your Claude Code, Codex and Antigravity usage in the system tray as a set of nested rings, so you can see how much quota you have left without opening anything.

**How to read it**

- One ring per tool: Claude Code on the outside, Codex in the middle, Antigravity inside.
- Each ring is split into one section per quota: 5-hour and weekly for Claude Code and Codex, Gemini and third-party models for Antigravity.
- A full section means the quota is untouched. As you use it, the section empties. An empty section means you've hit the limit.
- Click the icon for the details: every limit with its percentage and the time until it resets.

**Settings**

- Pick each tool's color. The sections get shades of it automatically, and you can override any one of them.
- Hide quotas you don't care about. The remaining sections fill the whole ring. Hidden quotas still show in the popup.
- Adjust the ring size and line thickness.
- Choose the refresh interval and which tools to track.

**Private and read-only**

AI Limits uses the logins the tools already keep on your machine. There are no API keys, no extra accounts, and nothing is sent anywhere except the tools' own usage endpoints. It never refreshes or changes your tokens.

**Requirements**

- KDE Plasma 6
- `bash`, `curl`, `jq`
- Signed in to the tools you want to track: `claude`, `codex login` with a ChatGPT account, or Antigravity running

**After installing**

The widget lives in the system tray and appears there by itself. If you don't see it, open *System Tray Settings → Entries* and set **AI Limits** to *Always shown* or *Shown when relevant*.

**Note:** these usage endpoints aren't public APIs. They're what the official tools use internally, so they can change without notice. If something breaks, please open an issue.

Source and issues: https://github.com/luminarysrc/lim
