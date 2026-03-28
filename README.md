# Claude Usage

Native macOS menu bar app for one very specific question:

**How much Claude subscription usage do I have left right now?**

Claude Usage launches Claude Code in its own PTY session, opens the interactive `/usage` screen, captures the rendered terminal UI, and turns it into a clean menu bar snapshot for **Claude Pro / Max** users.

No browser scraping. No cost API. No organization admin tooling. Just the limits that Claude Code already shows on your Mac.

## Why this exists

Anthropic does not currently expose a clean public API for **remaining personal subscription limits** on Claude Pro / Max.

If you use Claude Code every day, that creates a real gap:

- You want to know whether you're close to the session cap.
- You want to see weekly pressure before you hit it.
- You do not want to guess from token logs or API billing.

Claude Usage fills that gap with a small native utility that lives in your menu bar and reads the same `/usage` view you would check manually.

## What it does

- Shows your current Claude subscription snapshot from interactive `/usage`
- Captures current session usage
- Captures weekly usage when Claude renders it
- Surfaces reset timestamps when available
- Works as a lightweight `LSUIElement` menu bar app
- Falls back gracefully when Claude changes the TUI layout

## What it does not do

- It does not use Anthropic cost analytics
- It does not use organization admin APIs
- It does not parse local `~/.claude/usage-data` as a source of truth
- It does not invent numbers when Claude's UI changes

## How it works

1. The app launches `claude` inside an app-owned PTY session.
2. It uses an empty working directory at `~/Library/Application Support/CCUsageViewer/ClaudeCLI`.
3. It automatically clears the one-time trust prompt for that directory.
4. It sends `/usage`.
5. It captures the rendered terminal screen with a small ANSI/TUI parser.
6. It extracts the sections that matter and shows them in the menu bar UI.

Because the source is the real Claude Code UI, this is the closest thing to a live “remaining limits” viewer without an official personal subscription API.

## Built for

- macOS users on Claude Pro or Max
- People who use Claude Code heavily and want a faster way to check limits
- Developers who care more about remaining capacity than token accounting

## Quick start

### Requirements

- macOS
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Claude Code installed locally as `claude`
- Claude logged into a subscription account on this Mac

### Run locally

```bash
xcodegen generate
open CCUsageViewer.xcodeproj
```

Then run the app from Xcode and click `Refresh` from the menu bar popover.

## Reliability model

Claude Usage is intentionally honest about where its data comes from.

- If `/usage` renders cleanly, you get a live snapshot.
- If Claude changes the terminal layout, the parser falls back to partial data and raw capture text.
- If the capture fails, the app shows the last useful state instead of pretending it knows more than it does.

## Project structure

- `CCUsageViewer/Services/ClaudeUsageCaptureService.swift`: launches Claude and drives `/usage`
- `CCUsageViewer/Services/ANSIStreamParser.swift`: interprets terminal control sequences
- `CCUsageViewer/Services/TerminalScreenBuffer.swift`: stores the virtual screen
- `CCUsageViewer/Services/UsageScreenParser.swift`: converts captured TUI text into limit snapshots
- `CCUsageViewer/ViewModels/LimitViewModel.swift`: refresh, stale state, and diagnostics
- `CCUsageViewer/Views/`: menu bar UI and settings

## Limitations

- macOS only for now
- Depends on the current Claude Code `/usage` layout
- Designed for personal subscription visibility, not API billing or enterprise analytics

## Roadmap

- Better plan/account labeling from the captured UI
- Exportable diagnostics for parser regressions
- Improved partial parsing when Anthropic tweaks the `/usage` screen

## License

MIT
