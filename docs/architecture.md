# CC Usage Viewer: Architecture v2.1

## 1. System Overview

`CC Usage Viewer` — `LSUIElement` macOS menu bar приложение (Claude-only) с двумя источниками данных:

1. **Claude.ai REST API** — структурированный JSON (primary, recommended)
2. **PTY capture** — интерактивный терминал Claude Code (optional fallback, not recommended)

Zero external dependencies. SwiftUI + SwiftData + Swift Charts + WebKit + UserNotifications.

---

## 2. Layer Diagram

```
┌─────────────────────────────────────────────────┐
│  UI Layer (SwiftUI)                             │
│  CCUsageViewerApp · MenuBarContentView          │
│  SettingsView · DashboardView                   │
│  CountdownTimerView · PerModelBreakdownView     │
│  MiniChartView · LimitSectionCard (inline)      │
├─────────────────────────────────────────────────┤
│  State / Orchestration                          │
│  AppModel (UserDefaults)                        │
│  LimitViewModel (refresh, timers, notifications)│
│  DashboardViewModel (history queries)           │
├─────────────────────────────────────────────────┤
│  Auth Layer                                     │
│  WebAuthService (WKWebView login window)        │
│  SessionKeyStorage (UserDefaults)               │
├─────────────────────────────────────────────────┤
│  Data Source Layer                              │
│  UsageDataSourceCoordinator (API→PTY fallback)  │
│  ├─ ClaudeAPIService (URLSession)               │
│  ├─ ClaudeAPIResponseMapper (JSON→Snapshot)     │
│  └─ ClaudeUsageCaptureService (PTY capture)     │
│     ├─ CaptureFlowStateMachine                  │
│     ├─ ANSIStreamParser + TerminalScreenBuffer  │
│     └─ UsageScreenParser                        │
├─────────────────────────────────────────────────┤
│  Persistence Layer                              │
│  UsageHistoryStore (SwiftData)                  │
│  NotificationManager (UNUserNotificationCenter) │
├─────────────────────────────────────────────────┤
│  Domain Models                                  │
│  SubscriptionLimitSnapshot · LimitSection       │
│  ModelLimitSection · ExtraUsageInfo             │
│  ClaudeAPIModels · UsageHistorySample           │
└─────────────────────────────────────────────────┘
```

---

## 3. File Map

### App/
| File | Role |
|------|------|
| `CCUsageViewerApp.swift` | @main, MenuBarExtra + Dashboard Window + Settings (520x620, always foreground) |
| `AppModel.swift` | UserDefaults settings (refresh, thresholds, data source, ptyRiskAcceptedAt) |

### Models/
| File | Role |
|------|------|
| `SubscriptionLimitModels.swift` | Core domain types: Snapshot, LimitSection, ModelLimitSection, ExtraUsageInfo, DataSourceKind |
| `ClaudeAPIModels.swift` | Codable structs for API responses (usage incl. seven_day_haiku, organizations, overage, prepaid) |
| `UsageHistorySample.swift` | SwiftData @Model for usage history persistence |

### Services/
| File | Role |
|------|------|
| `ClaudeAPIService.swift` | URLSession HTTP client for claude.ai API (4 endpoints) |
| `ClaudeAPIResponseMapper.swift` | Maps API JSON → SubscriptionLimitSnapshot (incl. Haiku model) |
| `SessionKeyStorage.swift` | UserDefaults CRUD for sessionKey + orgId |
| `WebAuthService.swift` | WKWebView login window, real popup for Google OAuth, DispatchQueue polling, selective cookie cleanup, hint banner |
| `UsageDataSourceCoordinator.swift` | Orchestrates API→PTY fallback based on user preference |
| `UsageHistoryStore.swift` | SwiftData container for usage history samples |
| `NotificationManager.swift` | UNUserNotificationCenterDelegate with foreground banners, threshold dedup, seeding, test notification, "Open System Settings" |
| `ClaudeUsageCaptureService.swift` | PTY-based Claude CLI capture (v1, preserved) |
| `CaptureFlowStateMachine.swift` | Trust→Usage state machine (v1, preserved) |
| `ANSIStreamParser.swift` | ANSI escape sequence parser (v1, preserved) |
| `TerminalScreenBuffer.swift` | Virtual terminal screen (v1, preserved) |
| `UsageScreenParser.swift` | Semantic extraction from terminal text (v1, preserved) |

### ViewModels/
| File | Role |
|------|------|
| `LimitViewModel.swift` | Central orchestrator: refresh, coordinator, history, notifications, timers |
| `DashboardViewModel.swift` | Queries UsageHistoryStore for chart data |

### Views/
| File | Role |
|------|------|
| `MenuBarContentView.swift` | Menu bar popover: LimitSectionCards (title + bar + % + timer), combined "Models & Extra Usage" DisclosureGroup, mini chart, empty state with "Open Settings" |
| `SettingsView.swift` | Settings: data source (API default + PTY risk alert), TextField numeric inputs, NSEvent click-to-dismiss focus, test notification button, no Diagnostics section |
| `DashboardView.swift` | Dashboard window: Swift Charts, time range picker |
| `CountdownTimerView.swift` | Circular countdown timer (48x48, 11pt monospaced font) |
| `PerModelBreakdownView.swift` | Per-model usage bars (Sonnet, Opus, Haiku, Cowork, OAuth Apps) |
| `MiniChartView.swift` | Sparkline chart: gap detection (>10min = dashed lines), gradient fill, expandable DisclosureGroup |
| `WebAuthView.swift` | Placeholder (unused — login window managed by WebAuthService) |

### Removed Files (v2.1)
| File | Reason |
|------|--------|
| `CodexExecutableResolver.swift` | Codex support removed |
| Codex-related test files | Codex support removed |

---

## 4. Data Flow

### API Path (primary, recommended)
```
User → Refresh
  → LimitViewModel.refresh()
  → UsageDataSourceCoordinator.fetchSnapshot()
  → ClaudeAPIService.fetchUsage/Overage/Prepaid (parallel async let)
  → ClaudeAPIResponseMapper.map() → SubscriptionLimitSnapshot
    (includes Sonnet, Opus, Haiku, Cowork, OAuth Apps)
  → LimitViewModel stores snapshot
  → UsageHistoryStore.recordSample()
  → NotificationManager.checkAndFireAlerts()
  → UI updates (MenuBarContentView, timers, menu bar title)
```

### PTY Path (optional fallback)
```
Coordinator API fails (or user chose PTY) → fallback
  → ClaudeUsageCaptureService.captureUsage()
  → forkpty() → ANSIStreamParser → CaptureFlowStateMachine
  → UsageScreenParser.parse() → SubscriptionLimitSnapshot
  → Same downstream (history, notifications, UI)
```

### Auth Flow
```
User clicks "Login to Claude.ai"
  → WebAuthService.startLogin()
  → Selective cookie cleanup (only sessionKey, keep Google/auth cookies)
  → NSWindow 1000x740 + hint banner + WKWebView → claude.ai/login
  → User logs in (Google real popup / Email)
  → DispatchQueue polling (3s) detects sessionKey cookie
  → ClaudeAPIService.fetchOrganizations(sessionKey) → orgId
  → SessionKeyStorage: UserDefaults (sessionKey + orgId)
  → isAuthenticated = true → window closes automatically
```

---

## 5. Auth Architecture

See [authorization-debug.md](authorization-debug.md) for the full debug history.

Key decisions:
- **WKWebView** (not system browser) — can capture cookies
- **`.default()` data store** — persistent cookies, OAuth works
- **Safari User-Agent** — Google doesn't block
- **Real popup window for Google OAuth** — NSWindow 500x600 with child WKWebView, `window.opener.postMessage()` works
- **DispatchQueue polling** — `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` instead of Timer/Task (reliable `self` retention)
- **Selective cookie cleanup** — only `sessionKey` cookie deleted on login/logout, Google/auth cookies preserved
- **JSONSerialization** for /api/organizations (not Codable — response too complex)
- **UserDefaults storage** — sessionKey + orgId (no Keychain password prompts in debug builds)
- **Hint banner** — "Log in to your Claude account. The window will close automatically."

---

## 6. Persistence

| What | Where | Retention |
|------|-------|-----------|
| Settings | UserDefaults | Permanent |
| sessionKey | UserDefaults | Until logout |
| organizationId | UserDefaults | Until logout |
| ptyRiskAcceptedAt | UserDefaults | Permanent |
| Usage history | SwiftData (SQLite) | Unlimited, manual cleanup |
| WKWebView cookies | WKWebsiteDataStore.default() | Managed by WebKit |

---

## 7. Notification System

- `UNUserNotificationCenter` (native macOS)
- `UNUserNotificationCenterDelegate` — shows banners even when app is in foreground (`willPresent` → `.banner, .sound`)
- Two thresholds per metric: warn (default 75%), danger (default 90%)
- Alert dedup: `alertFired` dictionary, reset when usage drops below warn
- Seeding on first load: if already above threshold, don't fire
- Fires for both session and weekly metrics
- "Send test notification" button:
  - Checks permission status
  - If not determined → requests permission
  - If denied → shows NSAlert with "Open System Settings" button
  - If authorized → sends test notification with 1s delay trigger

---

## 8. Timer System

- `Timer.publish(every: 1)` for countdown display
- Circular progress ring (48x48, 11pt monospaced font)
- Auto-refresh when timer hits 0 (3s delay for server sync)
- Circular progress ring shows elapsed % of window (5h or 7d)
- Colors follow warn/danger thresholds

---

## 9. Error Handling

| Scenario | Behavior |
|----------|----------|
| API auth expired | Show error, keep last-good-snapshot |
| API Cloudflare blocked | Fallback to PTY (if user enabled) |
| PTY claude not found | Show unavailable + diagnostic paths |
| Both sources fail | Combined error message |
| JSON decode error | Log + fallback gracefully |
| History store init fail | App works without history |
| No data + no error | Empty state: icon + message + "Open Settings" button |

---

## 10. Build & Configuration

- **XcodeGen**: `project.yml` generates `.xcodeproj`
- **Entitlements**: `com.apple.security.network.client` (API access)
- **Target**: macOS 15.0+, Swift 6.0
- **LSUIElement**: YES (menu bar only, no Dock icon)
- **Dashboard**: Shows in Dock when open (`NSApp.setActivationPolicy(.regular)`)
- **Settings window**: 520x620, always brought to foreground on open
