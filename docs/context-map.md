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
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     forkpty()        ┌──────────────────────┐
│ Claude CLI  │◄────────────────────│  ClaudeUsageCapture  │
│ (/usage)    │  PTY terminal        │  Service             │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     SecItem*         ┌──────────────────────┐
│ macOS       │◄────────────────────│  SessionKeyStorage   │
│ Keychain    │                      │                      │
└─────────────┘                     └──────────────────────┘
                                           │
┌─────────────┐     UNNotification   ┌──────────────────────┐
│ macOS       │◄────────────────────│  NotificationManager │
│ Notification│  Center              │                      │
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
| `/api/organizations/{orgId}/usage` | GET | sessionKey cookie | `{five_hour, seven_day, seven_day_sonnet, ...}` |
| `/api/organizations/{orgId}/overage_spend_limit` | GET | sessionKey cookie | `{monthly_credit_limit, used_credits, is_enabled, currency}` |
| `/api/organizations/{orgId}/prepaid/credits` | GET | sessionKey cookie | `{amount, currency}` |

## Data Flow Summary

```
Auth: WKWebView → sessionKey cookie → Keychain
                                         │
Data: Keychain → ClaudeAPIService ──────►│
      or PTY → CaptureService ──────────►├─► SubscriptionLimitSnapshot
                                         │         │
                                         │    ┌────┴────┐
                                         │    │         │
                                    HistoryStore   NotificationManager
                                    (SwiftData)    (UNNotification)
                                         │
                                    DashboardView
                                    (Swift Charts)
```

## Settings Map

| Setting | Key | Default | Range |
|---------|-----|---------|-------|
| Auto refresh | `autoRefreshEnabled` | true | bool |
| Refresh interval | `refreshIntervalMinutes` | 5 | 1-60 min |
| Stale threshold | `staleThresholdMinutes` | 15 | 1-180 min |
| Data source | `preferredDataSource` | autoFallback | auto/api/pty |
| Notifications | `notificationsEnabled` | true | bool |
| Warn threshold | `warnThreshold` | 75 | 1-99% |
| Danger threshold | `dangerThreshold` | 90 | 1-99% |
| Compact menu bar | `compactMenuBarMode` | false | bool |
| Dashboard range | `dashboardTimeRange` | sevenDays | 7d/30d/90d/all |
| Show raw capture | `showRawCapture` | false | bool |
| Display mode | `displayMode` | claudeOnly | claude/codex/both |
