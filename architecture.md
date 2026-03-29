# Claude Usage: Architecture

## 1. Цель системы

`Claude Usage` — это `LSUIElement` macOS menu bar приложение, которое показывает остатки лимитов подписки Claude через интерактивную команду `/usage` в Claude Code.

Источник данных только один: живой TUI-экран Claude Code, запущенный в PTY.

---

## 2. Архитектурная схема

Слои:

1. **UI слой (SwiftUI)**
- `CCUsageViewerApp`
- `MenuBarContentView`
- `SettingsView`

2. **State / Orchestration**
- `AppModel` (настройки и persistence)
- `LimitViewModel` (refresh loop, ошибки, fallback, агрегированное состояние UI)

3. **Capture pipeline**
- `ClaudeUsageCaptureService` (запуск `claude` через `forkpty`, lifecycle процесса, timeouts)
- `CaptureFlowStateMachine` (драйвинг trust prompt -> `/usage` -> capture completed)
- `ANSIStreamParser` + `TerminalScreenBuffer` (восстановление текстового экрана из ANSI-потока)

4. **Semantic parsing**
- `UsageScreenParser` (преобразование сырого экрана в доменную модель лимитов)

5. **Domain models**
- `SubscriptionLimitSnapshot`, `LimitSection`, `UsageCaptureResult`, `CaptureSourceState`

---

## 3. End-to-end data flow

1. Приложение стартует в `CCUsageViewerApp`.
2. Создаются `AppModel` и `LimitViewModel`; `startIfNeeded()` сразу включает авто-refresh.
3. `LimitViewModel.refresh()` вызывает `ClaudeUsageCaptureService.captureUsage()`.
4. Capture service:
- находит исполняемый `claude`
- создает app-owned папку `~/Library/Application Support/CCUsageViewer/ClaudeCLI`
- запускает `claude` через `forkpty`
- читает PTY-байты, прогоняет через ANSI parser
- state machine отправляет `Enter` для trust prompt и `/usage`
- ожидает стабилизации usage-экрана
5. `UsageScreenParser` извлекает session/week/reset/plan.
6. `LimitViewModel`:
- сохраняет snapshot как актуальный
- при ошибках использует `lastGoodSnapshot` и помечает `stale`/`partial`
7. `MenuBarContentView` рендерит карточки лимитов и статус (`Live/Partial/Stale/...`).

---

## 4. Компоненты и методы

## 4.1 App entrypoint

Файл: `CCUsageViewer/App/CCUsageViewerApp.swift`

**Типы и методы:**

- `struct CCUsageViewerApp: App`
- `init()`
  - инициализирует `AppModel`
  - инициализирует `LimitViewModel`
  - запускает авто-refresh через `startIfNeeded()`
- `var body: some Scene`
  - `MenuBarExtra` с `MenuBarContentView`
  - `Settings` окно с `SettingsView`

---

## 4.2 Настройки приложения

Файл: `CCUsageViewer/App/AppModel.swift`

**Ответственность:** хранение пользовательских настроек в `UserDefaults`.

**Ключевые поля:**

- `autoRefreshEnabled`
- `refreshIntervalMinutes`
- `staleThresholdMinutes`
- `showRawCapture`

**Методы/свойства:**

- `init(defaults:)` — загрузка defaults или значений по умолчанию
- `refreshSettingsKey` — составной ключ для реакции UI на изменение настроек
- `workingDirectoryDescription` — путь рабочей директории capture pipeline

---

## 4.3 ViewModel orchestration

Файл: `CCUsageViewer/ViewModels/LimitViewModel.swift`

**Ответственность:** orchestration между capture/parser и UI.

**Ключевые методы:**

- `startIfNeeded()`
  - одноразово включает refresh lifecycle

- `reconfigureAutoRefresh()`
  - отменяет старую `Task`
  - запускает новую циклическую задачу:
    - immediate refresh
    - sleep по `refreshIntervalMinutes`
    - refresh при `autoRefreshEnabled == true`

- `refresh(forceVisibleLoading:)`
  - вызывает `captureService.captureUsage()`
  - запускает `parser.parse(...)`
  - применяет `plan hint` через `applyingPlanHint(...)`
  - обновляет `snapshot`, `lastGoodSnapshot`, `sourceState`
  - при ошибке:
    - пишет `lastErrorMessage`
    - использует fallback на `lastGoodSnapshot` если есть
    - маппит ошибки в `CaptureSourceState`

**Derived state:**

- `isRefreshing`
- `isSnapshotStale`
- `menuBarTitle`
- `menuBarSymbol`

---

## 4.4 Capture service (PTY + process lifecycle)

Файл: `CCUsageViewer/Services/ClaudeUsageCaptureService.swift`

**Публичный контракт:**

- `protocol ClaudeUsageCaptureServiceProtocol`
  - `captureUsage() async throws -> UsageCaptureResult`

**Ключевые методы:**

- `captureUsage()`
  - выполняет sync-capture внутри `Task.detached(priority: .userInitiated)`

- `captureUsageSync()`
  - основной loop захвата:
    - `findClaudeExecutable()`
    - `makeWorkingDirectory()`
    - `startClaudeSession(...)`
    - non-blocking read из PTY
    - `ANSIStreamParser.consume(...)`
    - `CaptureFlowStateMachine.evaluate(...)`
    - `send("\r")` для trust
    - `send("/usage\r")` для открытия usage
    - success при `captureCompleted`
  - собирает `observedPlanName` из промежуточных экранов (`extractPlanHint`)
  - применяет фазовые timeout-ограничения (`shouldTimeout`)
  - корректно завершает дочерний процесс (`terminate` + `waitpid`)

- `findClaudeExecutable()`
  - ищет `claude`:
    - из `PATH`
    - в пользовательских стандартных путях (`~/.local/bin`, `~/bin`, `~/.npm-global/bin`)
    - в системных (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`)
    - fallback: `zsh -lc "command -v claude"`

- `extractPlanHint(from:)`
  - regex-поиск `Claude Max/Pro` или `Max/Pro plan`
  - нужен как fallback, если финальный `/usage` экран не содержит plan label

**Ошибка домена:**

- `ClaudeUsageCaptureError`
  - `claudeNotInstalled`
  - `spawnFailed`
  - `timeout`
  - `screenNotRecognized`
  - `emptyCapture`

---

## 4.5 State machine

Файл: `CCUsageViewer/Services/CaptureFlowStateMachine.swift`

**Фазы:**

- `launching`
- `awaitingTrustPrompt`
- `awaitingReadyPrompt`
- `requestingUsage`
- `awaitingUsageScreen`
- `captured`
- `failed`

**Actions:**

- `.sendTrust`
- `.sendUsage`
- `.captureCompleted`

**Ключевой метод:**

- `evaluate(screenText:now:) -> [CaptureFlowAction]`
  - нормализует экран
  - отслеживает момент последнего изменения экрана
  - решает, когда отправить trust/usage
  - подтверждает успешный capture только после стабильности экрана (`>= 1s` без изменений + usage markers)

Примечание: `looksReadyForCommand` сейчас не участвует в принятии решений (зарезервировано под возможное расширение логики).

---

## 4.6 ANSI -> virtual screen

Файлы:

- `CCUsageViewer/Services/ANSIStreamParser.swift`
- `CCUsageViewer/Services/TerminalScreenBuffer.swift`

### ANSIStreamParser

**Роль:** конвертировать поток байтов PTY в операции над экраном.

**Поддержка:**

- текстовые символы
- `CR`, `LF`, `backspace`, `tab`
- базовые CSI-команды курсора и очистки:
  - `A/B/C/D/E/F/G/H/f/d`
  - `J`, `K`
- OSC-блоки игнорируются безопасно

### TerminalScreenBuffer

**Роль:** хранить и изменять 2D-сетку экрана.

**Ключевые методы:**

- `put`, `carriageReturn`, `lineFeed`, `backspace`
- `moveCursor*`, `moveCursorTo`, `cursorHorizontalAbsolute`, `cursorVerticalAbsolute`
- `eraseLine`, `eraseDisplay`
- `renderedLines()`, `renderedText()`

---

## 4.7 Semantic parser `/usage`

Файл: `CCUsageViewer/Services/UsageScreenParser.swift`

**Контракт:**

- `protocol UsageScreenParserProtocol`
  - `parse(screenText:capturedAt:) throws -> SubscriptionLimitSnapshot`

**Логика parse:**

1. Нормализация текста.
2. Валидация, что это похоже на usage-экран (keyword markers).
3. Извлечение:
- `planName` (если присутствует)
- `currentSession` (`used`, `remaining`, `%`, `reset`)
- `weeklyLimit` (приоритет `Current week (all models)`)
4. Формирование `SubscriptionLimitSnapshot`.

**Ошибка:**

- `UsageScreenParserError.missingUsageMarkers`

---

## 4.8 UI компоненты

### MenuBarContentView
Файл: `CCUsageViewer/Views/MenuBarContentView.swift`

**Что показывает:**

- Заголовок с plan name (`Claude subscription` fallback)
- Badge состояния (`Live`, `Partial`, `Stale`, ...)
- Карточки:
  - `Current session`
  - `Current week`
- Raw capture (`DisclosureGroup`) при включенном diagnostics
- Footer:
  - `Refresh`
  - `Close` (закрыть popover)
  - `Quit` (закрыть приложение)
  - `Settings...`

### SettingsView
Файл: `CCUsageViewer/Views/SettingsView.swift`

**Настройки:**

- auto-refresh
- interval
- stale threshold
- toggle raw capture
- ручной `Run capture now`
- отображение рабочего каталога и диагностик

---

## 4.9 Domain models

Файл: `CCUsageViewer/Models/SubscriptionLimitModels.swift`

**Типы:**

- `CaptureSourceState` — статус качества данных
- `LimitSection` — данные одного блока лимитов
- `SubscriptionLimitSnapshot` — итог parse-снимка
- `UsageCaptureResult` — результат PTY-capture до semantic-parse

**Важный метод:**

- `SubscriptionLimitSnapshot.applyingPlanHint(_:)`
  - подменяет `Unknown Plan` на plan hint из capture-сессии

---

## 5. Error handling и деградация

1. Capture fail до первого успеха:
- UI показывает `Unavailable/Auth/Partial` + текст ошибки.

2. Capture fail после успешного snapshot:
- UI сохраняет предыдущие данные (`lastGoodSnapshot`)
- статус становится `stale` или `partial`.

3. Parser не распознал `/usage`:
- ошибка `missingUsageMarkers`
- при наличии last good snapshot UI остается функциональным.

---

## 6. Тестовая стратегия

Покрытие в `CCUsageViewerTests`:

- `ANSIStreamParserTests`
  - trust prompt после cursor-control
  - erase/reposition сценарии

- `CaptureFlowStateMachineTests`
  - trust -> usage -> capture путь
  - сценарий без trust prompt
  - извлечение plan hint

- `CaptureFlowStateMachineTrustPersistenceTests`
  - повторная trust-confirmation при зависании trust-экрана

- `UsageScreenParserTests`
  - full parse (plan + session + weekly)
  - partial weekly scenarios
  - приоритет `Current week (all models)`
  - reject нерелевантных экранов

---

## 7. Ключевые ограничения

- Только macOS.
- Зависимость от текущего layout `/usage` в Claude TUI.
- Нет официального API Anthropic для personal remaining limits, поэтому архитектура намеренно построена вокруг интерактивного capture.

---

## 8. Точки расширения

1. Улучшить детекцию plan/account type (включая будущие планы).
2. Расширить parser на дополнительные разделы `/usage`, если Anthropic их добавит.
3. Добавить structured diagnostics export для regression-debug parser/capture.
