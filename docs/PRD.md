# PRD: CC Usage Viewer v2.0

## 1. Document Control

- Product: `CC Usage Viewer`
- Type: Product Requirements Document
- Platform: macOS (`MenuBarExtra`, `LSUIElement`, `Window`)
- Version: `v2.0`
- Date: `2026-04-02`
- Owner: `Product + Engineering`
- Previous: v1.0 (PTY-only, 2026-03-29)

---

## 2. Product Summary

`CC Usage Viewer` — нативная macOS утилита в menu bar, которая показывает лимиты подписки Claude (Pro/Max) через два источника данных:

1. **Claude.ai REST API** (primary) — структурированный JSON с разбивкой по моделям
2. **PTY capture** (fallback) — интерактивный `/usage` в Claude Code

### Что нового в v2.0

- Claude.ai API как источник данных (3 эндпоинта: usage, overage, prepaid)
- Per-model разбивка (Sonnet, Opus, Cowork, OAuth Apps)
- Dashboard окно с графиками (Swift Charts) + безлимитная история (SwiftData)
- Нотификации при достижении порогов (UNUserNotificationCenter)
- Live countdown таймеры (посекундное обновление)
- Compact mode в menu bar ("67% · 2h 30m")
- Настраиваемые цветовые пороги (warn/danger)
- WKWebView-авторизация через Google/Email

---

## 3. Problem Statement

Пользователь Claude Code на personal-подписке хочет:

- Быстро видеть остаток лимитов (session + weekly)
- Видеть разбивку по моделям (Sonnet, Opus)
- Отслеживать тренды использования за время (графики)
- Получать уведомления при приближении к лимитам
- Видеть live countdown до сброса

---

## 4. Goals & Non-Goals

### Goals (v2)

1. Подключение к Claude.ai API для получения структурированных данных
2. Per-model usage breakdown
3. Dashboard с графиками истории использования
4. Настраиваемые нотификации при пересечении порогов
5. Live countdown таймеры до сброса лимитов
6. Compact menu bar mode
7. Graceful fallback на PTY при недоступности API

### Non-Goals (v2)

1. iOS/iPadOS клиент
2. Cloud sync между устройствами
3. Cost estimation / billing analytics
4. Multi-account support
5. Anthropic organization admin API

---

## 5. Target Users

1. Solo-разработчики на Claude Pro/Max, использующие Claude Code ежедневно
2. Power users, которым важна быстрая проверка remaining limits
3. Пользователи, которые хотят отслеживать тренды потребления

---

## 6. Data Sources

### Primary: Claude.ai REST API

| Endpoint | Данные |
|----------|--------|
| `GET /api/organizations` | Валидация сессии, получение orgId |
| `GET /api/organizations/{orgId}/usage` | Session (5h), weekly (7d), per-model |
| `GET /api/organizations/{orgId}/overage_spend_limit` | Extra usage / overage |
| `GET /api/organizations/{orgId}/prepaid/credits` | Prepaid balance |

Аутентификация: cookie `sessionKey` на `.claude.ai`

### Fallback: PTY Capture

Интерактивный запуск `claude` → `/usage` → ANSI parsing → semantic extraction.
Используется когда API недоступен или пользователь не авторизован.

---

## 7. Functional Requirements

### FR-1 API Data Source
Система должна получать данные через Claude.ai REST API.
- Аутентификация через sessionKey (хранение в macOS Keychain)
- Параллельный запрос 3 эндпоинтов (usage + overage + prepaid)
- Fallback на PTY при ошибке API

### FR-2 WKWebView Authorization
Система должна поддерживать авторизацию через встроенный браузер.
- Открытие окна 1000x700 с claude.ai/login
- Поддержка Google OAuth (popup handling, Safari UA)
- Автоматический перехват sessionKey cookie
- Валидация через /api/organizations
- Хранение в macOS Keychain

### FR-3 Per-Model Breakdown
Система должна показывать usage по отдельным моделям.
- Sonnet, Opus, Cowork, OAuth Apps
- Expandable section в popover

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

### FR-6 Countdown Timers
Система должна показывать live countdown до сброса лимитов.
- Посекундное обновление
- Круговой прогресс-индикатор
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

### FR-9 PTY Capture Pipeline (preserved from v1)
Все FR из v1 (capture, ANSI parsing, usage parsing, plan detection, error handling) сохранены.

---

## 8. Non-Functional Requirements

### NFR-1 Performance
- API response < 5s
- PTY capture < 15s
- UI non-blocking

### NFR-2 Security
- sessionKey в macOS Keychain (SecItemAdd)
- Нет внешних зависимостей
- Локальное хранение данных

### NFR-3 Privacy
- Все данные локальны
- Нет телеметрии
- Raw capture только для диагностики

### NFR-4 Reliability
- Graceful degradation при смене API формата
- PTY fallback при недоступности API
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

### In Scope (v2.0)
1. Claude.ai API integration (3 endpoints)
2. WKWebView auth (Google + Email)
3. Per-model usage breakdown
4. SwiftData history + Swift Charts dashboard
5. UNUserNotificationCenter alerts
6. Live countdown timers
7. Compact menu bar mode
8. Configurable color thresholds
9. All v1 PTY features preserved

### Out of Scope (v2.0)
1. Multi-account
2. Cloud sync
3. Cost estimation
4. iOS/iPadOS
5. Login window auto-close (known issue)
