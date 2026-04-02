# Authorization Debug Log & Final Pipeline

## Approaches Tried

### 1. WKWebView как Sheet (первый подход)
**Идея:** Открыть WKWebView как sheet из Settings, пользователь логинится, перехватываем cookie.

**Проблемы:**
- Открывалось как маленький popup-sheet внутри окна Settings — плохой UX
- Google OAuth не работал: ошибка "There was an error logging you in" — WKWebView блокирует popup-окна Google OAuth по умолчанию
- Пользователь попросил "открывать в браузере, а не в поп-ап окне"

**Статус:** Отклонён по UX.

---

### 2. Системный браузер + ручной ввод sessionKey
**Идея:** Открыть Safari через `NSWorkspace.shared.open(url)`, пользователь логинится, копирует sessionKey из DevTools → вставляет в текстовое поле в приложении.

**Реализация:**
- `WebAuthService.openBrowserLogin()` — открывает Safari
- `WebAuthView` — sheet с инструкциями "Step 1: Open browser → Step 2: DevTools → Cookies → paste"
- `validateAndSave(sessionKey:)` — валидация через API

**Проблемы:**
- Требует от пользователя ходить в Developer Tools (F12 → Application → Cookies) — слишком сложно
- Пользователь спросил: "как в опенсорс проекте сделать без DevTools?"

**Статус:** Работало технически, отклонён по UX.

---

### 3. WKWebView как отдельное окно (финальный подход)
**Идея:** Как в Electron-проекте — открыть полноценное окно с WKWebView, пользователь логинится, приложение автоматически ловит sessionKey cookie.

**Эволюция и баги:**

#### 3a. nonPersistent data store + cookie polling через Task
- `WKWebViewConfiguration().websiteDataStore = .nonPersistent()`
- Polling через `Task { while true { sleep; check cookies } }`
- **Баг:** Google OAuth не работал — возвращал ошибку. Причины: 1) `nonPersistent` store ломает OAuth flow, 2) popup-окно Google блокировалось, 3) User-Agent выглядел как embedded browser

#### 3b. default data store + Safari User-Agent + popup handling
- Переключились на `.default()` (persistent cookies)
- Добавили `customUserAgent` = Safari 18.3
- Добавили `WKUIDelegate.createWebViewWith` — перехват popup'ов Google OAuth и загрузка в том же WebView
- **Результат:** Google OAuth заработал! Пользователь смог залогиниться.

#### 3c. Краш при закрытии окна
- **Баг:** `EXC_BAD_ACCESS` в `objc_release` → `_NSWindowTransformAnimation dealloc`
- **Причина:** NSWindow освобождался во время анимации закрытия. `windowWillClose` обнулял `loginWindow = nil`, единственная strong-ссылка пропадала, а анимация ещё работала.
- **Фикс:** `window.isReleasedWhenClosed = false` + отложенное обнуление ссылок через `DispatchQueue.main.async`

#### 3d. Cookie polling не находит sessionKey
- **Баг:** Пользователь залогинен (видит "Afternoon, Slava"), но Settings показывает "Not connected"
- **Попытки:**
  1. `Task`-based polling каждые 1.5с с `cookieStore.allCookies()` — не вызывался (Task терял `self`)
  2. Детекция через `WKNavigationDelegate.didFinish` — не вызывался (claude.ai = SPA, навигация через JS)
  3. URL polling через Task — `self` становился `nil` из-за `[weak self]`
  4. `WKHTTPCookieStoreObserver.cookiesDidChange` — срабатывал, но не логгировал (проблемы с stdout)
- **Попытки дебага:**
  - `print()` — не появляется в stdout при запуске GUI-приложения
  - `NSLog()` — не появляется в `log show` (фильтруется macOS)
  - `os.Logger` — не появляется в `log show` с уровнем `.info`
  - Запись в файл через `FileHandle` — **единственный способ который работал!**

#### 3e. Рабочий дебаг → реальный диагноз
- Лог из `/tmp/ccusage_auth.log` показал: `alreadyCaptured=true` на первом же poll-тике
- Это значит `WKHTTPCookieStoreObserver.cookiesDidChange` **СРАБОТАЛ** и нашёл sessionKey
- Но `handleCapturedSessionKey()` вызвал `apiService.fetchOrganizations()` который упал с ошибкой парсинга

#### 3f. Ошибка парсинга /api/organizations
- **Баг:** "Failed to parse API response: The data couldn't be read because it isn't in the correct format"
- **Причина:** `JSONDecoder().decode([ClaudeAPIOrganization].self, from: data)` — ответ API содержит много дополнительных полей с вложенными объектами, датами и enum'ами, которые ломают strict Codable decoding
- **Фикс:** Заменили `Codable` на `JSONSerialization` для `/api/organizations` — ручной парсинг только нужных полей (`uuid`, `id`, `name`):
```swift
guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { ... }
return array.map { dict in
    ClaudeAPIOrganization(uuid: dict["uuid"] as? String, id: dict["id"] as? String, name: dict["name"] as? String)
}
```

#### 3g. WKHTTPCookieStoreObserver ловит старые cookies
- **Баг:** Observer срабатывал мгновенно при открытии login окна — ещё до того как пользователь начал логиниться
- **Причина:** `.default()` data store содержит cookies от прошлой сессии. При создании WKWebView observer видит existing cookies и захватывает старый sessionKey.
- **Фикс:** Полностью удалили WKHTTPCookieStoreObserver. Перешли на DispatchQueue polling only.

#### 3h. DispatchQueue polling + selective cookie cleanup (финальная версия)
- **Решение:** Перед загрузкой login page удаляется **только sessionKey cookie** (не все claude.ai cookies). Google/auth cookies сохраняются для smooth re-login.
- **Polling:** `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` с рекурсивным `scheduleNextPoll()`. Стартует после `didFinish` загрузки login page.
- **Детекция:** Проверяет URL (не /login) + наличие sessionKey cookie. Нет JS injection (вызывал page flicker).
- **Результат:** Надёжно работает. Пользователь логинится, polling детектирует, окно закрывается автоматически.

#### 3i. Real popup window для Google OAuth
- **Проблема:** Загрузка popup URL в том же WebView ломала `window.opener.postMessage()` — Google не мог вернуть результат OAuth.
- **Решение:** `createWebViewWith` теперь создаёт real NSWindow (500x600) с child WKWebView. Shared `WKWebViewConfiguration` сохраняет `window.opener` reference.
- **Автозакрытие:** `webViewDidClose` delegate закрывает popup когда Google вызывает `window.close()` после завершения OAuth.

**Статус:** РАБОТАЕТ.

---

## Финальный рабочий пайплайн авторизации

### Компоненты

| Файл | Роль |
|------|------|
| `WebAuthService.swift` | Управляет окном логина, DispatchQueue polling cookies, real popup для OAuth, валидация, хранение |
| `SessionKeyStorage.swift` | UserDefaults-хранение sessionKey + orgId |
| `ClaudeAPIService.swift` | HTTP-клиент для API claude.ai |
| `SettingsView.swift` | UI: кнопка Login/Logout, статус подключения |
| `WebAuthView.swift` | Placeholder (не используется — login window managed by WebAuthService) |

### Последовательность

```
Пользователь нажимает "Login to Claude.ai" в Settings
        │
        ▼
WebAuthService.startLogin()
        │
        ├─ Создаёт WKWebView (default data store, Safari UA, popup handling)
        ├─ Создаёт NSWindow 1000x740 (content + hint banner 40px)
        │   └─ Banner: "Log in to your Claude account. The window will close automatically."
        ├─ isReleasedWhenClosed = false
        ├─ Selective cookie cleanup: удаляет ТОЛЬКО sessionKey cookie
        │   (Google/auth cookies сохраняются для smooth re-login)
        └─ Загружает https://claude.ai/login
        │
        ▼
WKNavigationDelegate.didFinish()
        │
        └─ Запускает DispatchQueue polling (3с интервал)
        │
        ▼
Пользователь логинится (Google real popup / Email)
        │
        ├─ Google OAuth: WKUIDelegate.createWebViewWith → real NSWindow 500x600
        │   └─ Child WKWebView (shared config, window.opener works)
        │   └─ webViewDidClose → popup closes automatically
        │
        ▼
DispatchQueue polling → pollForLogin()                   ◄── каждые 3 секунды
        │
        ├─ Проверяет webView.url:
        │   └─ host contains "claude.ai" AND path NOT contains "login"
        │
        ├─ Проверяет cookieStore.allCookies()
        │   └─ Ищет cookie: name="sessionKey", domain contains "claude.ai"
        │
        ├─ [если cookie найден] → handleCapturedSessionKey(value)
        │       │
        │       ├─ URLSession GET https://claude.ai/api/organizations
        │       │   Cookie: sessionKey=<value>
        │       │   User-Agent: Safari 18.3
        │       │
        │       ├─ Парсит ответ через JSONSerialization (не Codable!)
        │       │   orgId = array[0]["uuid"] ?? array[0]["id"]
        │       │
        │       ├─ SessionKeyStorage.setSessionKey(value) → UserDefaults
        │       ├─ SessionKeyStorage.setOrganizationId(orgId) → UserDefaults
        │       │
        │       ├─ isAuthenticated = true → UI обновляется (зелёная галочка)
        │       └─ closeLoginWindow()
        │
        └─ [если cookie НЕ найден] → next poll tick in 3 seconds
```

### Ключевые решения

1. **`.default()` data store** — persistent cookies, OAuth работает через перезапуски
2. **Safari User-Agent** — Google не блокирует как embedded browser
3. **Real popup window for Google OAuth** — NSWindow 500x600 с child WKWebView, `window.opener.postMessage()` работает
4. **`isReleasedWhenClosed = false`** — предотвращает краш при закрытии окна
5. **DispatchQueue polling (not Timer/Task)** — `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` надёжно сохраняет self
6. **Selective cookie cleanup** — только sessionKey cookie удаляется, Google/auth cookies сохраняются
7. **JSONSerialization вместо Codable** — для `/api/organizations` (ответ слишком сложный для strict decoding)
8. **UserDefaults storage** — sessionKey + orgId (без Keychain password prompts)
9. **Hint banner** — информирует пользователя что окно закроется автоматически
10. **No JS injection** — polling проверяет URL + cookie store, без evaluateJavaScript (вызывал page flicker)
11. **Дебаг через FileHandle** — единственный способ логгирования из GUI SwiftUI app (print/NSLog/os.Logger не работают)

### Known Issues

- При `logout()` удаляется только sessionKey cookie — Google/auth cookies остаются для smooth re-login
