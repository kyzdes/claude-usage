# CC Usage Viewer

Native macOS menu bar app that shows your Claude subscription usage at a glance.

**How much Claude usage do I have left right now?**

## Features

- **Claude.ai API integration** — real-time usage data (session, weekly, per-model)
- **Per-model breakdown** — Sonnet, Opus, Cowork, OAuth Apps usage
- **Live countdown timers** — circular progress with per-second updates
- **Usage history & dashboard** — Swift Charts graphs with unlimited SwiftData storage
- **Desktop notifications** — configurable warn/danger thresholds
- **Compact menu bar** — shows "67% · 2h 30m" at a glance
- **PTY fallback** — captures Claude Code `/usage` when API is unavailable
- **Zero dependencies** — pure SwiftUI, no external packages

## Data Sources

| Source | How | When |
|--------|-----|------|
| Claude.ai API | REST endpoints with sessionKey cookie | Primary (when authenticated) |
| PTY capture | Launches `claude` CLI, parses `/usage` screen | Fallback |

## Quick Start

### Requirements

- macOS 15.0+
- Xcode 16+ (Swift 6.0)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Run

```bash
xcodegen generate
open CCUsageViewer.xcodeproj
# Run from Xcode (Cmd+R)
```

### Connect to Claude.ai API

1. Click the menu bar icon → Settings → Data Source → "Login to Claude.ai"
2. Log in with Google or Email in the browser window
3. Window closes automatically → green checkmark appears

### PTY-only mode

Works without API login — just needs `claude` CLI installed and logged in.

## Project Structure

```
CCUsageViewer/
├── App/                    # App entry point, settings model
├── Models/                 # Domain models, API models, SwiftData
├── Services/               # API client, auth, PTY capture, history, notifications
├── ViewModels/             # LimitViewModel, DashboardViewModel
├── Views/                  # Menu bar, settings, dashboard, timers, charts
└── Resources/              # Entitlements
```

## Documentation

- [PRD](docs/PRD.md) — Product requirements
- [Architecture](docs/architecture.md) — System design and file map
- [Context Map](docs/context-map.md) — External systems, API endpoints, settings
- [Authorization Debug](docs/authorization-debug.md) — Auth implementation history and pipeline spec

## How It Works

1. **API path**: sessionKey cookie → 3 parallel API calls → structured JSON → snapshot
2. **PTY path**: forkpty() → ANSI parser → state machine → semantic parser → snapshot
3. **Coordinator** picks API or PTY based on user preference and credential availability
4. **Each refresh**: records history sample (SwiftData) + checks notification thresholds
5. **Timers**: 1-second update cycle, auto-refresh when countdown hits zero

## License

MIT
