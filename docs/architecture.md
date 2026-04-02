# CC Usage Viewer: Architecture v2.0

## 1. System Overview

`CC Usage Viewer` — `LSUIElement` macOS menu bar приложение с двумя источниками данных:

1. **Claude.ai REST API** — структурированный JSON (primary)
2. **PTY capture** — интерактивный терминал Claude Code (fallback)

Zero external dependencies. SwiftUI + SwiftData + Swift Charts + WebKit + Security framework.

---

## 2. Layer Diagram

```
┌─────────────────────────────────────────────────┐
│  UI Layer (SwiftUI)                             │
│  CCUsageViewerApp · MenuBarContentView          │
│  SettingsView · DashboardView                   │
│  CountdownTimerView · PerModelBreakdownView     │
│  MiniChartView                                  │
├─────────────────────────────────────────────────┤
│  State / Orchestration                          │
│  AppModel (UserDefaults)                        │
│  LimitViewModel (refresh, timers, notifications)│
│  DashboardViewModel (history queries)           │
├─────────────────────────────────────────────────┤
│  Auth Layer                                     │
│  WebAuthService (WKWebView login window)        │
│  SessionKeyStorage (macOS Keychain)             │
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
| `CCUsageViewerApp.swift` | @main, MenuBarExtra + Dashboard Window + Settings |
| `AppModel.swift` | UserDefaults settings (refresh, thresholds, display, data source) |

### Models/
| File | Role |
|------|------|
| `SubscriptionLimitModels.swift` | Core domain types: Snapshot, LimitSection, ModelLimitSection, ExtraUsageInfo, DataSourceKind |
| `ClaudeAPIModels.swift` | Codable structs for API responses (usage, organizations, overage, prepaid) |
| `UsageHistorySample.swift` | SwiftData @Model for usage history persistence |

### Services/
| File | Role |
|------|------|
| `ClaudeAPIService.swift` | URLSession HTTP client for claude.ai API (4 endpoints) |
| `ClaudeAPIResponseMapper.swift` | Maps API JSON → SubscriptionLimitSnapshot |
| `SessionKeyStorage.swift` | macOS Keychain CRUD for sessionKey + UserDefaults for orgId |
| `WebAuthService.swift` | WKWebView login window, cookie capture, Google OAuth popup handling |
| `UsageDataSourceCoordinator.swift` | Orchestrates API→PTY fallback based on user preference |
| `UsageHistoryStore.swift` | SwiftData container for usage history samples |
| `NotificationManager.swift` | UNUserNotificationCenter with threshold dedup and seeding |
| `ClaudeUsageCaptureService.swift` | PTY-based Claude CLI capture (v1, preserved) |
| `CaptureFlowStateMachine.swift` | Trust→Usage state machine (v1, preserved) |
| `ANSIStreamParser.swift` | ANSI escape sequence parser (v1, preserved) |
| `TerminalScreenBuffer.swift` | Virtual terminal screen (v1, preserved) |
| `UsageScreenParser.swift` | Semantic extraction from terminal text (v1, preserved) |
| `CodexExecutableResolver.swift` | Binary path resolution for Codex (v1, preserved) |

### ViewModels/
| File | Role |
|------|------|
| `LimitViewModel.swift` | Central orchestrator: refresh, coordinator, history, notifications, timers |
| `DashboardViewModel.swift` | Queries UsageHistoryStore for chart data |

### Views/
| File | Role |
|------|------|
| `MenuBarContentView.swift` | Menu bar popover: cards, timers, per-model, mini chart, extra usage |
| `SettingsView.swift` | Settings: data source, display, notifications, history, diagnostics |
| `DashboardView.swift` | Dashboard window: Swift Charts, time range picker |
| `CountdownTimerView.swift` | Reusable circular countdown timer |
| `PerModelBreakdownView.swift` | Expandable per-model usage bars |
| `MiniChartView.swift` | Sparkline chart for popover |

---

## 4. Data Flow

### API Path (primary)
```
User → Refresh
  → LimitViewModel.refresh()
  → UsageDataSourceCoordinator.fetchSnapshot()
  → ClaudeAPIService.fetchUsage/Overage/Prepaid (parallel async let)
  → ClaudeAPIResponseMapper.map() → SubscriptionLimitSnapshot
  → LimitViewModel stores snapshot
  → UsageHistoryStore.recordSample()
  → NotificationManager.checkAndFireAlerts()
  → UI updates (MenuBarContentView, timers, menu bar title)
```

### PTY Path (fallback)
```
Coordinator API fails → fallback
  → ClaudeUsageCaptureService.captureUsage()
  → forkpty() → ANSIStreamParser → CaptureFlowStateMachine
  → UsageScreenParser.parse() → SubscriptionLimitSnapshot
  → Same downstream (history, notifications, UI)
```

### Auth Flow
```
User clicks "Login to Claude.ai"
  → WebAuthService.startLogin()
  → NSWindow + WKWebView → claude.ai/login
  → User logs in (Google/Email)
  → WKHTTPCookieStoreObserver detects sessionKey cookie
  → ClaudeAPIService.fetchOrganizations(sessionKey) → orgId
  → SessionKeyStorage: Keychain (sessionKey) + UserDefaults (orgId)
  → isAuthenticated = true → window closes
```

---

## 5. Auth Architecture

See [authorization-debug.md](authorization-debug.md) for the full debug history.

Key decisions:
- **WKWebView** (not system browser) — can capture cookies
- **`.default()` data store** — persistent cookies, OAuth works
- **Safari User-Agent** — Google doesn't block
- **WKUIDelegate popup handling** — Google OAuth popup in same WebView
- **WKHTTPCookieStoreObserver** — instant cookie detection
- **JSONSerialization** for /api/organizations (not Codable — response too complex)
- **Keychain storage** — sessionKey via SecItemAdd/SecItemCopyMatching

---

## 6. Persistence

| What | Where | Retention |
|------|-------|-----------|
| Settings | UserDefaults | Permanent |
| sessionKey | macOS Keychain | Until logout |
| organizationId | UserDefaults | Until logout |
| Usage history | SwiftData (SQLite) | Unlimited, manual cleanup |
| WKWebView cookies | WKWebsiteDataStore.default() | Managed by WebKit |

---

## 7. Notification System

- `UNUserNotificationCenter` (native macOS)
- Two thresholds per metric: warn (default 75%), danger (default 90%)
- Alert dedup: `alertFired` dictionary, reset when usage drops below warn
- Seeding on first load: if already above threshold, don't fire
- Fires for both session and weekly metrics

---

## 8. Timer System

- `Timer.publish(every: 1)` for countdown display
- `countdownTick: Date` observable triggers SwiftUI updates
- Auto-refresh when timer hits 0 (3s delay for server sync)
- Circular progress ring shows elapsed % of window (5h or 7d)
- Colors follow warn/danger thresholds

---

## 9. Error Handling

| Scenario | Behavior |
|----------|----------|
| API auth expired | Show error, keep last-good-snapshot |
| API Cloudflare blocked | Fallback to PTY |
| PTY claude not found | Show unavailable + diagnostic paths |
| Both sources fail | Combined error message |
| JSON decode error | Log + fallback gracefully |
| History store init fail | App works without history |

---

## 10. Build & Configuration

- **XcodeGen**: `project.yml` generates `.xcodeproj`
- **Entitlements**: `com.apple.security.network.client` (API access)
- **Target**: macOS 15.0+, Swift 6.0
- **LSUIElement**: YES (menu bar only, no Dock icon)
- **Dashboard**: Shows in Dock when open (`NSApp.setActivationPolicy(.regular)`)
