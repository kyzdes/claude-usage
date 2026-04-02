# Decisions Log

Хронологический лог архитектурных и продуктовых решений.

---

## D-001: Форк вместо модификации оригинала
**Дата:** 2026-04-02
**Контекст:** Нужно добавить 7 фич из open-source Electron-виджета в наш нативный проект.
**Решение:** Форкнуть `cc-usage-plugin` → `cc-usage-improved`, оригинал не трогать.
**Причина:** Безопасный откат, параллельная разработка, оригинал остаётся рабочим.

---

## D-002: Claude.ai REST API как primary data source
**Дата:** 2026-04-02
**Контекст:** PTY capture даёт только текстовый вывод `/usage` без разбивки по моделям.
**Решение:** Добавить 3 эндпоинта claude.ai API (usage, overage, prepaid). PTY остаётся как fallback.
**Причина:** API даёт структурированный JSON с per-model данными, overage, prepaid — то, что PTY не показывает.
**Trade-off:** Требует авторизации (sessionKey), зависит от стабильности неофициального API.

---

## D-003: WKWebView для авторизации (не системный браузер)
**Дата:** 2026-04-02
**Контекст:** Нужен способ получить sessionKey cookie от claude.ai.
**Альтернативы:**
- Системный браузер + ручной копипаст sessionKey из DevTools → отклонено, плохой UX
- ASWebAuthenticationSession → отклонено, claude.ai не поддерживает callback URL scheme
- Чтение cookie из Safari/Chrome на диске → отклонено, хрупко + требует Full Disk Access
**Решение:** WKWebView в отдельном окне 1000x740. Перехват cookie через DispatchQueue polling.
**Причина:** Единственный способ автоматически получить cookie без DevTools.

---

## D-004: Default WKWebsiteDataStore (не nonPersistent)
**Дата:** 2026-04-02
**Контекст:** `nonPersistent()` ломал Google OAuth flow.
**Решение:** `.default()` — persistent cookies между сессиями.
**Причина:** Google OAuth требует сохранения промежуточных cookies. Persistent store также позволяет не логиниться повторно при перезапуске окна.
**Trade-off:** При logout нужно явно чистить cookies.

---

## D-005: Safari User-Agent для WKWebView
**Дата:** 2026-04-02
**Контекст:** Google блокирует OAuth в embedded browsers.
**Решение:** `customUserAgent = "Mozilla/5.0 ... Safari/605.1.15"` — маскировка под Safari.
**Причина:** Google проверяет User-Agent и блокирует WKWebView. Safari UA проходит проверку.

---

## D-006: WKUIDelegate для Google OAuth popup
**Дата:** 2026-04-02
**Контекст:** Google OAuth открывает popup-окно (accounts.google.com), WKWebView блокирует его по умолчанию.
**Решение:** `createWebViewWith` delegate — загрузка popup URL в том же WebView.
**Причина:** Без этого кнопка "Continue with Google" выдавала ошибку.
**Обновлено (v2.1):** Теперь создаётся real popup window (NSWindow 500x600 с child WKWebView) вместо загрузки URL в том же WebView — это позволяет `window.opener.postMessage()` работать корректно для завершения OAuth flow.

---

## D-007: JSONSerialization вместо Codable для /api/organizations
**Дата:** 2026-04-02
**Контекст:** `JSONDecoder().decode([ClaudeAPIOrganization].self)` падал с "data couldn't be read".
**Решение:** Ручной парсинг через `JSONSerialization`, извлекаем только `uuid`, `id`, `name`.
**Причина:** Ответ API содержит десятки полей с вложенными объектами, датами и enum'ами. Strict Codable ломается на неизвестных типах. JSONSerialization игнорирует лишнее.

---

## D-008: isReleasedWhenClosed = false для login окна
**Дата:** 2026-04-02
**Контекст:** Краш `EXC_BAD_ACCESS` при закрытии окна авторизации.
**Решение:** `window.isReleasedWhenClosed = false` + отложенное обнуление ссылок (500ms).
**Причина:** NSWindow деаллоцировался во время анимации закрытия. Без `isReleasedWhenClosed = false` система авто-релизит окно, но анимация ещё держит ссылки.

---

## D-009: UserDefaults для хранения sessionKey (ранее Keychain)
**Дата:** 2026-04-02
**Контекст:** macOS Keychain показывал password prompt при каждом запуске debug-билда (code signature меняется).
**Решение:** Хранить sessionKey + orgId в UserDefaults вместо Keychain.
**Причина:** Keychain привязывает доступ к code signature. Debug-билды получают новую подпись при каждой компиляции, что вызывает повторный password prompt. UserDefaults не имеет этой проблемы.
**Trade-off:** Менее безопасно (plaintext plist), но приемлемо для локальной dev-утилиты. Для production-релиза можно вернуть Keychain с подписанным билдом.

---

## D-010: SwiftData для истории (не UserDefaults/JSON)
**Дата:** 2026-04-02
**Контекст:** Нужно хранить неограниченную историю usage samples.
**Решение:** SwiftData с `@Model UsageHistorySample`. Безлимитное хранение, ручная очистка.
**Альтернативы:** UserDefaults (лимит ~1MB), JSON файл (нет индексов), Core Data (тяжелее).
**Причина:** SwiftData встроен в macOS 14+, лёгкий API, поддерживает predicate-запросы для time ranges.

---

## D-011: Timer.scheduledTimer вместо Task для polling
**Дата:** 2026-04-02
**Контекст:** `Task { while true { sleep; check } }` с `[weak self]` терял ссылку на self.
**Решение:** `Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true)` на main run loop.
**Причина:** Timer гарантированно вызывается на main run loop. Task с weak self мог потерять объект при пересоздании SwiftUI views.
**Обновлено (v2.1):** Cookie polling в WebAuthService теперь использует DispatchQueue.main.asyncAfter вместо Timer (см. D-020).

---

## D-012: Тройная стратегия детекции cookie
**Дата:** 2026-04-02
**Контекст:** Одного метода перехвата sessionKey недостаточно.
**Решение:** Три параллельных механизма:
1. `WKHTTPCookieStoreObserver` — instant detection при изменении cookies
2. `Timer` polling (2s) — проверка URL + cookies + JS fallback
3. JS `fetch('/api/organizations')` из контекста страницы — когда cookie store не отдаёт httpOnly cookies
**Причина:** SPA-навигация не триггерит `didFinish`, cookie store может не отдать httpOnly cookies, Task-based polling теряет self.
**Обновлено (v2.1):** Упрощено до DispatchQueue polling only. Observer удалён (срабатывал на старых cookies). JS injection удалён (вызывал page flicker). См. D-014 и D-020.

---

## D-013: Дебаг через FileHandle (не print/NSLog/os.Logger)
**Дата:** 2026-04-02
**Контекст:** Нужно было понять почему cookie polling не работает. Никакой стандартный метод логгирования не давал вывод.
**Решение:** `FileHandle(forWritingAtPath: "/tmp/ccusage_auth.log")`.
**Выяснено:**
- `print()` — буферизуется, не появляется в stdout GUI-приложения
- `NSLog()` — не появляется в `log show` для данного процесса
- `os.Logger(.info)` — фильтруется macOS по умолчанию
- `FileHandle` → файл на диске — единственный надёжный способ
**Статус:** Debug-only, убрать перед релизом.

---

## D-014: Remove WKHTTPCookieStoreObserver, use DispatchQueue polling only
**Дата:** 2026-04-02
**Контекст:** Cookie observer срабатывал мгновенно при добавлении (cookies от прошлой сессии в `.default()` store), закрывая окно до того как пользователь мог залогиниться.
**Решение:** Убрать observer полностью. Использовать только `DispatchQueue.main.asyncAfter` polling каждые 3с. Перед загрузкой login page — очищать только sessionKey cookie (не все claude.ai cookies).
**Причина:** Observer не различает "старые cookies от прошлого логина" и "новые cookies от текущего логина". Polling проверяет URL (не /login) + cookies — это надёжно определяет свежий логин.

---

## D-015: SessionKeyStorage — UserDefaults вместо Keychain
**Дата:** 2026-04-02
**Контекст:** macOS Keychain показывал password prompt при каждом запуске debug-билда (code signature меняется).
**Решение:** Хранить sessionKey в UserDefaults вместо Keychain.
**Trade-off:** Менее безопасно (plaintext plist), но приемлемо для локальной dev-утилиты. Для production-релиза можно вернуть Keychain с подписанным билдом.

---

## D-016: Zero external dependencies
**Дата:** 2026-04-02
**Контекст:** Open-source проект использует Electron + Chart.js + electron-store (~150MB).
**Решение:** Всё на встроенных фреймворках: SwiftUI, Swift Charts, SwiftData, WebKit, UserNotifications.
**Причина:** Нативное приложение должно быть лёгким. Все нужные API есть в macOS SDK.

---

## D-017: Remove Codex entirely — Claude-only app
**Дата:** 2026-04-02
**Контекст:** Приложение поддерживало два провайдера (Claude + Codex) через UsageDisplayMode и UsageProvider enums. Codex требовал отдельные services, models, views и tests.
**Решение:** Удалить весь Codex код: services, models, views, tests, enums (UsageDisplayMode, UsageProvider). Приложение стало Claude-only.
**Удалённые файлы:** CodexExecutableResolver.swift, Codex test files, все Codex-related enum cases.
**Причина:** Приложение ориентировано на Claude Code пользователей. Codex добавлял сложность без ценности для целевой аудитории. Упрощение кодовой базы улучшает maintainability.

---

## D-018: API as default data source with PTY risk warning
**Дата:** 2026-04-02
**Контекст:** Data source picker предлагал три опции (auto/api/pty) с `autoFallback` как default.
**Решение:** Default = `api` ("API only (Recommended)"). PTY опции (`autoFallback`, `ptyCapture`) показывают NSAlert с предупреждением о рисках. Принятие логируется с timestamp через `ptyRiskAcceptedAt`.
**Причина:** PTY mode запускает CLI в terminal session — это нестабильно, потребляет ресурсы, может сломаться при обновлении CLI. API mode — надёжный и рекомендуемый способ.

---

## D-019: Real popup window for Google OAuth
**Дата:** 2026-04-02
**Контекст:** Google OAuth открывает popup (accounts.google.com). Ранее URL загружался в том же WebView через `createWebViewWith`. Это ломало `window.opener.postMessage()` — Google не мог вернуть результат OAuth в исходное окно.
**Решение:** Создавать real NSWindow (500x600) с child WKWebView, передавая ту же `WKWebViewConfiguration`. Popup закрывается автоматически через `webViewDidClose` когда Google вызывает `window.close()`.
**Причина:** Child WebView с shared configuration сохраняет `window.opener` reference, позволяя `postMessage()` работать. Это стандартный паттерн для OAuth popup в WKWebView.

---

## D-020: DispatchQueue polling instead of Timer/Task for cookie detection
**Дата:** 2026-04-02
**Контекст:** Cookie polling в WebAuthService использовал Timer.scheduledTimer (D-011). Timer с `[weak self]` capture иногда терял ссылку. Task-based polling (async/await) тоже терял self при пересоздании SwiftUI views.
**Решение:** `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` с рекурсивным вызовом `scheduleNextPoll()`. Проверяет `[weak self]` + `isPolling` + `!alreadyCaptured` на каждом тике.
**Причина:** DispatchQueue dispatch надёжно вызывается на main thread, не зависит от RunLoop mode, self-retention через closure предсказуем. Polling стартует только после `didFinish` загрузки login page.

---

## D-021: NSEvent monitor for click-to-dismiss focus in Settings
**Дата:** 2026-04-02
**Контекст:** TextField для числовых значений в Settings оставались в focus (с курсором) после ввода. Пользователю приходилось нажимать Tab или Enter для подтверждения.
**Решение:** `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` — при клике вне NSTextField вызывает `window.makeFirstResponder(nil)`.
**Причина:** SwiftUI не предоставляет нативного способа dismiss focus при клике outside. NSEvent monitor — стандартный AppKit паттерн для этого.

---

## D-022: UNUserNotificationCenterDelegate for foreground notifications
**Дата:** 2026-04-02
**Контекст:** macOS по умолчанию не показывает notification banners когда приложение в foreground.
**Решение:** NotificationManager наследует `UNUserNotificationCenterDelegate`, устанавливает себя как delegate в `init()`. Метод `willPresent` возвращает `[.banner, .sound]`.
**Причина:** Menu bar приложение практически всегда "active" (popover open = foreground). Без delegate пользователь никогда не увидит threshold alerts.
**Дополнительно:** "Send test notification" кнопка проверяет permission status. При `.denied` показывает NSAlert с кнопкой "Open System Settings" для включения нотификаций.

---

## D-023: Haiku model support added
**Дата:** 2026-04-02
**Контекст:** Claude.ai API начал возвращать `seven_day_haiku` поле в usage response.
**Решение:** Добавлен `sevenDayHaiku` в `ClaudeAPIUsageResponse`. `ClaudeAPIResponseMapper.buildPerModelLimits()` создаёт `ModelLimitSection(id: "seven_day_haiku", modelName: "Haiku (7d)")`.
**Причина:** Haiku — одна из моделей Claude, доступная пользователям. Per-model breakdown должен отражать все модели.

---

## D-024: Combined "Models & Extra Usage" expandable section
**Дата:** 2026-04-02
**Контекст:** Per-model breakdown и Extra Usage были отдельными секциями в popover, занимая много места.
**Решение:** Объединены в один `DisclosureGroup("Models & Extra Usage")`. Per-model bars и extra usage card внутри одной expandable секции.
**Причина:** Экономия вертикального пространства в popover. Per-model и extra usage — связанная информация (детализация usage). Collapsed по умолчанию — основные метрики (session + weekly) всегда видны.

---

## D-025: Chart gap detection with dashed interpolation lines
**Дата:** 2026-04-02
**Контекст:** MiniChartView рисовал сплошную линию между всеми точками, даже если между ними был перерыв в данных (приложение было закрыто, компьютер в sleep).
**Решение:** Gap detection с порогом 10 минут. Данные разбиваются на сегменты. Реальные данные — solid line + gradient AreaMark. Интерполированные промежутки — dashed line (dash: [4, 4]) с пониженной opacity.
**Причина:** Визуально отличает реальные данные от интерполированных. Пользователь сразу видит где были перерывы в мониторинге.
