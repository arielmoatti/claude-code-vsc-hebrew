# Claude Code Hebrew Fix (RTL) v4

Fix Hebrew (and Arabic) display in the Claude Code VSCode extension.

Without this fix, Hebrew text appears reversed — `םולש` instead of `שלום`.

## The Problem

Claude Code's webview CSS includes a `unicode-bidi: bidi-override` rule that forces left-to-right character ordering on **all** text, breaking every RTL language.

## What This Fix Does

A Bash script that runs automatically at every Claude Code session start (via [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)) and does three things:

1. **Neutralizes the bug** — replaces `bidi-override` with `normal`
2. **Injects CSS** — per-paragraph direction isolation, code blocks always LTR, proper list bullet positioning
3. **Injects smart JS** — real-time language detection per paragraph using MutationObserver

### Smart Language Detection (v4)

Each paragraph is analyzed independently:

| First strong letter | Hebrew ratio | Result |
|---|---|---|
| Hebrew | any | **RTL** |
| Latin | ≥ 30% Hebrew | **RTL** |
| Latin | < 30% Hebrew | **LTR** |
| none (only numbers/emoji) | — | unchanged |

Additionally, an **RLM anchor** (U+200F) is injected at the start of RTL paragraphs to fix BiDi issues when the first inline child contains LTR text (e.g. `<code>` inside a Hebrew sentence).

### Examples

```
"שלום עולם"                        → RTL (first strong = Hebrew)
"Hello world"                      → LTR (first strong = Latin, 0% Hebrew)
"Hello שלום"                       → RTL (first strong = Latin, but 36% ≥ 30%)
"1.1 Migration: הוספת שדות"         → RTL (first strong = Latin, but ~50% ≥ 30%)
"🎉 שלום"                          → RTL (emoji skipped, first strong = Hebrew)
```

## Installation

### Quick Install (paste into Claude Code)

Copy this entire block and paste it into Claude Code — it will set everything up:

```
Install the Hebrew RTL fix for Claude Code VSCode extension.
Do all these steps:

Step 1 — Create a scripts directory in the current working directory (if it doesn't exist).

Step 2 — Download fix-claude-rtl.sh from
https://raw.githubusercontent.com/arielmoatti/claude-code-vsc-hebrew/main/fix-claude-rtl.sh
and save it to scripts/fix-claude-rtl.sh

Step 3 — Create scripts/rtl-mode.conf with the content: full

Step 4 — Add a SessionStart hook to ~/.claude/settings.json:
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash FULL_PATH/scripts/fix-claude-rtl.sh"
      }
    ]
  }
}
Replace FULL_PATH with the absolute path to your project's scripts directory.

Step 5 — Run the script once to apply the fix.

Step 6 — Ask me to do Reload Window (Ctrl+Shift+P → Developer: Reload Window).
```

### Manual Install

1. Download `fix-claude-rtl.sh` to a `scripts/` folder in your project
2. Create `scripts/rtl-mode.conf` containing `full`
3. Add the SessionStart hook to `~/.claude/settings.json` (see above)
4. Run `bash scripts/fix-claude-rtl.sh`
5. Reload VSCode window

## Two Modes

| Mode | Description |
|---|---|
| **full** (default) | Full RTL with language detection — Hebrew right-aligned, English left-aligned |
| **word** | Character fix only — Hebrew words readable, no paragraph direction change |

Switch by telling Claude: *"Switch RTL to word"* or *"Switch RTL to full"*

## How It Works

The script patches the Claude Code extension's webview files (`index.css` and `index.js`) located in `~/.vscode/extensions/anthropic.claude-code-*/webview/`.

**CSS patch:**
- `unicode-bidi: isolate` on all text elements (paragraphs, headings, list items, etc.)
- `unicode-bidi: embed` + `direction: ltr` on code blocks
- `list-style-position: inside` for RTL list items
- `direction: inherit` on children of user message bubbles (to counter the global `* { direction: ltr }` rule)

**JS patch:**
- Two MutationObservers — one for Claude's responses, one for sent user messages
- Per-paragraph direction detection using the first-strong + 30% threshold algorithm
- Watchdog on user messages that re-applies direction if VSCode resets it

The script is **idempotent** — it removes any previous patch before applying, so it's safe to run multiple times. It handles all installed extension versions simultaneously.

## Known Limitations

- A user message that starts with English and has < 30% Hebrew will be fully LTR (each message bubble is a single element)
- Conflicts with other RTL extensions (e.g. `YechielBy/claude-code-rtl-extension` or `GuyRonnen/rtl-for-vs-code-agents`) — use only one

## Credits

v4 detection algorithm inspired by [GuyRonnen/rtl-for-vs-code-agents](https://github.com/GuyRonnen/rtl-for-vs-code-agents) (30% threshold, RLM anchors, `unicode-bidi: isolate`).

## License

MIT
