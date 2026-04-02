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
**Идея:** Как в Electron-проекте — открыть полноценное окно 1000x700 с WKWebView, пользователь логинится, приложение автоматически ловит sessionKey cookie.

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
- **Фикс:** `window.isReleasedWhenClosed = false` + отложенное обнуление ссылок через `Task.sleep(500ms)`

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

**Статус:** РАБОТАЕТ.

---

## Финальный рабочий пайплайн авторизации

### Компоненты

| Файл | Роль |
|------|------|
| `WebAuthService.swift` | Управляет окном логина, polling cookies, валидация, хранение |
| `SessionKeyStorage.swift` | Keychain-хранение sessionKey + UserDefaults для orgId |
| `ClaudeAPIService.swift` | HTTP-клиент для API claude.ai |
| `SettingsView.swift` | UI: кнопка Login/Logout, статус подключения |

### Последовательность

```
Пользователь нажимает "Login to Claude.ai" в Settings
        │
        ▼
WebAuthService.startLogin()
        │
        ├─ Создаёт WKWebView (default data store, Safari UA, popup handling)
        ├─ Создаёт NSWindow 1000x700, isReleasedWhenClosed = false
        ├─ Загружает https://claude.ai/login
        ├─ Регистрирует WKHTTPCookieStoreObserver
        └─ Запускает Timer (2с интервал) для fallback polling
        │
        ▼
Пользователь логинится (Google / Email)
        │
        ▼
WKHTTPCookieStoreObserver.cookiesDidChange()    ◄── PRIMARY: мгновенная реакция
   или Timer → pollForLogin()                    ◄── FALLBACK: проверка каждые 2с
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
        │       ├─ SessionKeyStorage.setSessionKey(value) → macOS Keychain
        │       ├─ SessionKeyStorage.setOrganizationId(orgId) → UserDefaults
        │       │
        │       ├─ isAuthenticated = true → UI обновляется (зелёная галочка)
        │       └─ closeLoginWindow()
        │
        └─ [если cookie НЕ найден] → JS fallback
                │
                ├─ evaluateJavaScript: fetch('/api/organizations', {credentials: 'include'})
                ├─ Парсит JSON ответ → извлекает orgId
                └─ handleAuthenticatedSession(orgId)
                        │
                        ├─ Пытается получить sessionKey из cookie store
                        ├─ Пытается получить из document.cookie (JS)
                        └─ Last resort: сохраняет placeholder "wkwebview-session-active"
```

### Ключевые решения

1. **`.default()` data store** — persistent cookies, OAuth работает через перезапуски
2. **Safari User-Agent** — Google не блокирует как embedded browser
3. **WKUIDelegate popup handling** — Google OAuth popup загружается в том же WebView
4. **`isReleasedWhenClosed = false`** — предотвращает краш при закрытии окна
5. **Отложенное обнуление ссылок** — `Task.sleep(500ms)` после `windowWillClose` чтобы анимация завершилась
6. **JSONSerialization вместо Codable** — для `/api/organizations` (ответ слишком сложный для strict decoding)
7. **Дебаг через FileHandle** — единственный способ логгирования из GUI SwiftUI app (print/NSLog/os.Logger не работают)

### Known Issues

- Окно логина не закрывается автоматически после успешной авторизации (пользователь закрывает вручную) — требуется доработка `closeLoginWindow()` timing
- При `logout()` нужно чистить cookies в default data store чтобы следующий логин начинался с чистого состояния
