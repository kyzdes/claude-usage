# PRD: CC Usage Viewer v2.1

## 1. Document Control

- Product: `CC Usage Viewer`
- Type: Product Requirements Document
- Platform: macOS (`MenuBarExtra`, `LSUIElement`, `Window`)
- Version: `v2.1`
- Date: `2026-04-02`
- Owner: `Product + Engineering`
- Previous: v2.0 (Claude + Codex dual-provider, 2026-04-02), v1.0 (PTY-only, 2026-03-29)

---

## 2. Product Summary

`CC Usage Viewer` — нативная macOS утилита в menu bar, которая показывает лимиты подписки Claude (Pro/Max) через два источника данных:

1. **Claude.ai REST API** (primary, recommended) — структурированный JSON с разбивкой по моделям
2. **PTY capture** (optional, not recommended) — интерактивный `/usage` в Claude Code

### Что нового в v2.1

- Приложение полностью Claude-only (Codex код удалён)
- API only = default data source (Recommended); PTY опции показывают risk warning alert
- Per-model разбивка включает Haiku (seven_day_haiku) наряду с Sonnet, Opus, Cowork, OAuth Apps
- Per-model + Extra Usage объединены в один expandable "Models & Extra Usage" DisclosureGroup
- LimitSectionCard упрощён: title + progress bar + % + countdown timer (без дублирования)
- Countdown timer увеличен: 48x48, шрифт 11pt
- Mini chart: gap detection с dashed lines для интерполированных данных (>10 мин), gradient fill, expandable с заголовком
- Notifications: UNUserNotificationCenterDelegate показывает баннеры в foreground, test notification с проверкой permissions, кнопка "Open System Settings" при блокировке
- Login window: real popup для Google OAuth, selective cookie cleanup (только sessionKey), DispatchQueue polling, hint banner
- Empty state: иконка + сообщение + кнопка "Open Settings"
- SessionKeyStorage: UserDefaults вместо Keychain (без password prompts)
- Settings: TextField вместо Stepper для числовых значений, NSEvent monitor для dismiss focus, убран Diagnostics section
- Settings window: всегда на переднем плане, default size 520x620

---

## 3. Problem Statement

Пользователь Claude Code на personal-подписке хочет:

- Быстро видеть остаток лимитов (session + weekly)
- Видеть разбивку по моделям (Sonnet, Opus, Haiku)
- Отслеживать тренды использования за время (графики)
- Получать уведомления при приближении к лимитам
- Видеть live countdown до сброса

---

## 4. Goals & Non-Goals

### Goals (v2.1)

1. Claude-only приложение — единый provider без переключения
2. Claude.ai API как primary и recommended data source
3. Per-model usage breakdown (Sonnet, Opus, Haiku, Cowork, OAuth Apps)
4. Dashboard с графиками истории использования
5. Настраиваемые нотификации при пересечении порогов (с foreground support)
6. Live countdown таймеры до сброса лимитов
7. Compact menu bar mode
8. PTY capture как optional fallback с risk warning

### Non-Goals (v2.1)

1. iOS/iPadOS клиент
2. Cloud sync между устройствами
3. Cost estimation / billing analytics
4. Multi-account support
5. Anthropic organization admin API
6. Codex / OpenAI integration (removed)

---

## 5. Target Users

1. Solo-разработчики на Claude Pro/Max, использующие Claude Code ежедневно
2. Power users, которым важна быстрая проверка remaining limits
3. Пользователи, которые хотят отслеживать тренды потребления

---

## 6. Data Sources

### Primary: Claude.ai REST API (Recommended)

| Endpoint | Данные |
|----------|--------|
| `GET /api/organizations` | Валидация сессии, получение orgId |
| `GET /api/organizations/{orgId}/usage` | Session (5h), weekly (7d), per-model (Sonnet, Opus, Haiku, Cowork, OAuth Apps) |
| `GET /api/organizations/{orgId}/overage_spend_limit` | Extra usage / overage |
| `GET /api/organizations/{orgId}/prepaid/credits` | Prepaid balance |

Аутентификация: cookie `sessionKey` на `.claude.ai`

### Optional: PTY Capture (Not Recommended)

Интерактивный запуск `claude` → `/usage` → ANSI parsing → semantic extraction.
Выбирается вручную в Settings с предупреждением о рисках. При выборе PTY опций показывается alert с объяснением рисков; принятие логируется с timestamp.

---

## 7. Functional Requirements

### FR-1 API Data Source
Система должна получать данные через Claude.ai REST API.
- Аутентификация через sessionKey (хранение в UserDefaults)
- Параллельный запрос 3 эндпоинтов (usage + overage + prepaid)
- API only = default (Recommended)

### FR-2 WKWebView Authorization
Система должна поддерживать авторизацию через встроенный браузер.
- Открытие окна 1000x740 с claude.ai/login и hint banner
- Поддержка Google OAuth (real popup window 500x600, не загрузка в том же WebView)
- Selective cookie cleanup — удаляется только sessionKey cookie, Google/auth cookies сохраняются для smooth re-login
- DispatchQueue polling (3с интервал) вместо Timer/Task
- Автоматический перехват sessionKey cookie
- Валидация через /api/organizations
- Хранение в UserDefaults

### FR-3 Per-Model Breakdown
Система должна показывать usage по отдельным моделям.
- Sonnet, Opus, Haiku, Cowork, OAuth Apps
- Per-model + Extra Usage объединены в expandable "Models & Extra Usage" DisclosureGroup

### FR-4 Usage History & Dashboard
Система должна хранить историю и показывать графики.
- Безлимитное хранение через SwiftData
- Dashboard окно с Swift Charts
- Time ranges: 7d, 30d, 90d, All
- Ручная очистка истории

### FR-5 Notifications
Система должна уведомлять при пересечении порогов.
- Два порога: warn (default 75%) и danger (default 90%)
- Per-metric dedup (не спамить)
- Seeding при старте (не стрелять если уже выше порога)
- UNUserNotificationCenterDelegate для показа баннеров в foreground
- "Send test notification" кнопка в Settings с проверкой permissions
- "Open System Settings" кнопка при блокировке нотификаций

### FR-6 Countdown Timers
Система должна показывать live countdown до сброса лимитов.
- Посекундное обновление
- Круговой прогресс-индикатор (48x48, 11pt font)
- Цветовые пороги
- Авто-refresh при достижении 0

### FR-7 Compact Menu Bar Mode
Система должна поддерживать compact display в menu bar.
- Формат: "67% · 2h 30m"
- Toggle в настройках

### FR-8 Color Thresholds
Прогресс-бары и таймеры должны менять цвет по порогам.
- Зелёный → Жёлтый (warn%) → Красный (danger%)
- Настраиваемые значения (1-99%)

### FR-9 PTY Capture Pipeline (optional, preserved from v1)
Все FR из v1 (capture, ANSI parsing, usage parsing, plan detection, error handling) сохранены как optional fallback.
Выбор PTY опций требует подтверждения risk warning alert.

### FR-10 Settings Window
- Default size 520x620, always comes to foreground
- TextField controls для числовых значений (вместо Stepper)
- NSEvent monitor: клик вне text field снимает focus
- Data source picker: API only = default (Recommended), PTY опции с risk warning
- No Diagnostics section (raw capture, working dir, run capture removed)

### FR-11 Empty State
При отсутствии данных показывается:
- Иконка (gauge)
- Информационное сообщение
- Кнопка "Open Settings"

### FR-12 Mini Chart
Sparkline в footer попover:
- Gap detection: промежутки >10 минут отображаются dashed lines
- Gradient fill для реальных данных
- Expandable DisclosureGroup с заголовком "Usage trend (24h)"

---

## 8. Non-Functional Requirements

### NFR-1 Performance
- API response < 5s
- PTY capture < 15s
- UI non-blocking

### NFR-2 Security
- sessionKey в UserDefaults (приемлемо для локальной dev-утилиты)
- Нет внешних зависимостей
- Локальное хранение данных

### NFR-3 Privacy
- Все данные локальны
- Нет телеметрии

### NFR-4 Reliability
- Graceful degradation при смене API формата
- PTY fallback при выборе пользователем
- Last-good-snapshot при любых ошибках

---

## 9. Success Metrics

| Metric | Target |
|--------|--------|
| API auth success rate | >= 95% |
| Data refresh success (API or PTY) | >= 95% |
| Time to first data | < 5s (API), < 15s (PTY) |
| Crash-free sessions | >= 99.5% |
| Notification accuracy | 100% (no false positives) |

---

## 10. Release Scope

### In Scope (v2.1)
1. Claude-only (Codex removed)
2. Claude.ai API integration (3 endpoints, recommended default)
3. WKWebView auth (Google real popup + Email)
4. Per-model usage breakdown (Sonnet, Opus, Haiku, Cowork, OAuth Apps)
5. SwiftData history + Swift Charts dashboard
6. UNUserNotificationCenter alerts (foreground banners, test notification)
7. Live countdown timers (48x48)
8. Compact menu bar mode
9. Configurable color thresholds
10. PTY fallback preserved (optional, risk warning)
11. Combined "Models & Extra Usage" DisclosureGroup
12. Mini chart with gap detection and gradient fill
13. Empty state with "Open Settings" button
14. Settings: TextField inputs, NSEvent focus dismiss

### Out of Scope (v2.1)
1. Multi-account
2. Cloud sync
3. Cost estimation
4. iOS/iPadOS
5. Codex / OpenAI integration
