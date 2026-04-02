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
**Решение:** WKWebView в отдельном окне 1000x700. Перехват cookie через `WKHTTPCookieStoreObserver`.
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

## D-009: macOS Keychain для хранения sessionKey
**Дата:** 2026-04-02
**Контекст:** sessionKey — чувствительные данные, нельзя хранить в UserDefaults.
**Решение:** `SecItemAdd` / `SecItemCopyMatching` с `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
**Причина:** Keychain шифрует данные на уровне ОС. UserDefaults — plaintext plist.

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

---

## D-012: Тройная стратегия детекции cookie
**Дата:** 2026-04-02
**Контекст:** Одного метода перехвата sessionKey недостаточно.
**Решение:** Три параллельных механизма:
1. `WKHTTPCookieStoreObserver` — instant detection при изменении cookies
2. `Timer` polling (2s) — проверка URL + cookies + JS fallback
3. JS `fetch('/api/organizations')` из контекста страницы — когда cookie store не отдаёт httpOnly cookies
**Причина:** SPA-навигация не триггерит `didFinish`, cookie store может не отдать httpOnly cookies, Task-based polling теряет self.

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
**Решение:** Убрать observer полностью. Использовать только `DispatchQueue.main.asyncAfter` polling каждые 2с. Перед загрузкой login page — очищать все claude.ai cookies.
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
**Решение:** Всё на встроенных фреймворках: SwiftUI, Swift Charts, SwiftData, WebKit, Security, UserNotifications.
**Причина:** Нативное приложение должно быть лёгким. Все нужные API есть в macOS SDK.
