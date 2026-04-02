# CC Usage Viewer: Context Map

## External Systems

```
┌─────────────┐     HTTPS/JSON      ┌──────────────────────┐
│ Claude.ai   │◄────────────────────│  ClaudeAPIService    │
│ REST API    │  Cookie: sessionKey  │  (URLSession)        │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     WKWebView       ┌──────────────────────┐
│ Claude.ai   │◄────────────────────│  WebAuthService      │
│ Login Page  │  Cookie capture      │  (WKWebView window)  │
│             │  Real popup (OAuth)  │  (DispatchQueue poll)│
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     forkpty()        ┌──────────────────────┐
│ Claude CLI  │◄────────────────────│  ClaudeUsageCapture  │
│ (/usage)    │  PTY terminal        │  Service             │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     UserDefaults     ┌──────────────────────┐
│ macOS       │◄────────────────────│  SessionKeyStorage   │
│ UserDefaults│  sessionKey + orgId  │                      │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     UNNotification   ┌──────────────────────┐
│ macOS       │◄────────────────────│  NotificationManager │
│ Notification│  Center + Delegate   │  (foreground banners)│
│ Center      │                      │                      │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     ModelContainer   ┌──────────────────────┐
│ SQLite      │◄────────────────────│  UsageHistoryStore   │
│ (SwiftData) │                      │                      │
└─────────────┘                     └──────────────────────┘
```

## API Endpoints

| Endpoint | Method | Auth | Response |
|----------|--------|------|----------|
| `/api/organizations` | GET | sessionKey cookie | `[{uuid, id, name, ...}]` |
| `/api/organizations/{orgId}/usage` | GET | sessionKey cookie | `{five_hour, seven_day, seven_day_sonnet, seven_day_opus, seven_day_haiku, seven_day_cowork, seven_day_oauth_apps}` |
| `/api/organizations/{orgId}/overage_spend_limit` | GET | sessionKey cookie | `{monthly_credit_limit, used_credits, is_enabled, currency}` |
| `/api/organizations/{orgId}/prepaid/credits` | GET | sessionKey cookie | `{amount, currency}` |

## Data Flow Summary

```
Auth: WKWebView → sessionKey cookie → UserDefaults
                                         │
Data: UserDefaults → ClaudeAPIService ──►│
      or PTY → CaptureService ──────────►├─► SubscriptionLimitSnapshot
                                         │         │
                                         │    ┌────┴────┐
                                         │    │         │
                                    HistoryStore   NotificationManager
                                    (SwiftData)    (UNNotification +
                                         │         foreground delegate)
                                    DashboardView
                                    (Swift Charts)
```

## Settings Map

| Setting | Key | Default | Range |
|---------|-----|---------|-------|
| Auto refresh | `autoRefreshEnabled` | true | bool |
| Refresh interval | `refreshIntervalMinutes` | 5 | 1-60 min |
| Stale threshold | `staleThresholdMinutes` | 15 | 1-180 min |
| Data source | `preferredDataSource` | api | api/autoFallback/ptyCapture |
| Notifications | `notificationsEnabled` | true | bool |
| Warn threshold | `warnThreshold` | 75 | 1-99% |
| Danger threshold | `dangerThreshold` | 90 | 1-99% |
| Compact menu bar | `compactMenuBarMode` | false | bool |
| Dashboard range | `dashboardTimeRange` | sevenDays | 7d/30d/90d/all |
| Show raw capture | `showRawCapture` | false | bool |
| PTY risk accepted | `ptyRiskAcceptedAt` | nil | timestamp (Double) |

### Removed Settings (v2.1)
| Setting | Reason |
|---------|--------|
| `displayMode` (UsageDisplayMode) | Codex removed, app is Claude-only |

## Per-Model Breakdown Fields

| API Field | Display Name | ID |
|-----------|-------------|-----|
| `seven_day_sonnet` | Sonnet (7d) | `seven_day_sonnet` |
| `seven_day_opus` | Opus (7d) | `seven_day_opus` |
| `seven_day_haiku` | Haiku (7d) | `seven_day_haiku` |
| `seven_day_cowork` | Cowork (7d) | `seven_day_cowork` |
| `seven_day_oauth_apps` | OAuth Apps (7d) | `seven_day_oauth_apps` |
