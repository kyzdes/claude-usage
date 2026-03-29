# PRD: Claude Usage

## 1. Document Control

- Product: `Claude Usage`
- Type: Product Requirements Document
- Platform: macOS (`MenuBarExtra`, `LSUIElement`)
- Version: `v1.0`
- Date: `2026-03-29`
- Owner: `Product + Engineering`

---

## 2. Product Summary

`Claude Usage` — это нативная menu bar утилита для macOS, которая показывает остатки лимитов подписки Claude (`Pro/Max`) через интерактивный `/usage` в Claude Code.

Ключевой принцип продукта: **не придумывать цифры и не симулировать API, которого нет**.  
Если данные нельзя корректно прочитать, продукт показывает частичные данные/ошибку, а не “красивую неправду”.

---

## 3. Problem Statement

Пользователь Claude Code на personal-подписке хочет быстро понимать:

- сколько лимита осталось в текущей сессии;
- сколько осталось по неделе;
- когда сбросятся лимиты.

Сейчас это неудобно:

- нет простого публичного API для персональных remaining limits;
- приходится вручную открывать `claude` и запускать `/usage`;
- повторяющаяся ручная проверка замедляет рабочий поток.

---

## 4. Goals & Non-Goals

## Goals (v1)

1. Показать в menu bar актуальные лимиты из `/usage` за один клик.
2. Обновлять данные вручную и по авто-таймеру.
3. Обеспечить честную деградацию при изменениях TUI/layout.
4. Показать тип плана (`Pro/Max`), когда его удается определить.

## Non-Goals (v1)

1. Подсчет cost/API billing.
2. Интеграция с Anthropic organization/admin analytics.
3. Парсинг `~/.claude/usage-data` как источника remaining limits.
4. iOS/iPadOS клиент.
5. Полноценная аналитика исторических токенов.

---

## 5. Target Users

1. Solo-разработчики на Claude Pro/Max, которые используют Claude Code ежедневно.
2. Power users, которым важна быстрая проверка remaining limits без отвлечения.
3. Пользователи, которым нужен “живой индикатор доступной емкости”, а не cost-отчеты.

---

## 6. Jobs To Be Done

1. Когда я работаю в коде, я хочу за 2-3 секунды увидеть остатки лимитов, чтобы понимать, могу ли продолжать длинную сессию.
2. Когда лимиты близки к исчерпанию, я хочу заранее увидеть это и перепланировать работу.
3. Когда данные нельзя прочитать, я хочу прозрачную причину и диагностику, чтобы быстро восстановить работу.

---

## 7. User Experience Requirements

## Primary UX

1. Пользователь кликает по иконке в menu bar.
2. Видит:
- план (`Claude Pro/Max`, если доступно);
- статус источника (`Live/Partial/Stale/Unavailable/...`);
- блок `Current session`;
- блок `Current week`.
3. Нажимает `Refresh` для ручного обновления.
4. Может открыть `Settings`, закрыть popover (`Close`) или завершить приложение (`Quit`).

## Settings UX

Пользователь может:

- включить/выключить `Auto refresh`;
- настроить интервал обновления;
- настроить порог stale;
- включить raw-capture diagnostics;
- запустить `Run capture now`.

---

## 8. Functional Requirements

## FR-1 Capture Pipeline

Система должна запускать `claude` в PTY и выполнять `/usage` интерактивно.

Acceptance criteria:

1. Приложение использует app-owned working dir:
`~/Library/Application Support/CCUsageViewer/ClaudeCLI`.
2. Trust prompt обрабатывается автоматически (`Enter`).
3. `/usage` отправляется в сессию после готовности.

## FR-2 ANSI/TUI Rendering

Система должна собирать экран из ANSI-последовательностей до стабильного текстового состояния.

Acceptance criteria:

1. Поддерживаются базовые cursor/erase операции, нужные для Claude TUI.
2. Из PTY формируется `renderedText`, пригодный для semantic parse.

## FR-3 Usage Parsing

Система должна извлекать из `/usage`:

- Current session;
- Current week (предпочтительно `(all models)`);
- reset text;
- progress percent/used/remaining (если присутствуют).

Acceptance criteria:

1. При отсутствии usage markers parser возвращает controlled error.
2. При частичном контенте snapshot помечается как `partial`.

## FR-4 Plan Detection

Система должна определять план `Pro/Max`:

1. сначала из финального usage-screen;
2. если не найдено — из промежуточного welcome screen (`plan hint`).

Acceptance criteria:

1. Если план не найден, UI показывает generic label (`Claude subscription`).
2. Никакой “угадайки” вне подтвержденных текстовых маркеров.

## FR-5 Error Handling & Fallback

Система должна корректно деградировать.

Acceptance criteria:

1. Ошибки capture/parser отображаются в UI.
2. Если есть `lastGoodSnapshot`, UI показывает его, помечая `stale/partial`.
3. При отсутствии успешных snapshot показывается понятный empty/error state.

## FR-6 Refresh Behavior

Система должна поддерживать manual и auto refresh.

Acceptance criteria:

1. Кнопка `Refresh` инициирует немедленный захват.
2. Auto refresh работает по интервалу в минутах.
3. При изменении настроек цикл refresh пересоздается без перезапуска app.

## FR-7 Menu Controls

Popover должен содержать:

1. `Refresh`
2. `Close` (закрыть popover)
3. `Settings...`
4. `Quit` (закрыть приложение)

---

## 9. Non-Functional Requirements

## NFR-1 Performance

1. Первый успешный capture в нормальных условиях: целевой SLA до `8-12s`.
2. Manual refresh должен быть неблокирующим для UI.

## NFR-2 Reliability

1. App не падает при изменениях Claude TUI.
2. Все сбои возвращаются как controlled errors.

## NFR-3 Security & Privacy

1. Локальный запуск, без отправки capture-данных на внешний backend.
2. Raw text показывается только локально пользователю.
3. Минимально необходимые доступы в рамках обычного desktop app run.

## NFR-4 Maintainability

1. Capture/state-machine/parser покрыты unit tests.
2. Архитектура разделена на четкие слои.

---

## 10. Success Metrics (v1)

## Product KPIs

1. `Capture Success Rate` (live or partial) >= `90%` в стабильном окружении.
2. `Time To First Useful Snapshot` <= `15s` для нового запуска.
3. `Manual Refresh Completion` <= `10s` p50.

## Quality KPIs

1. `Crash-free sessions` >= `99.5%`.
2. `Parser false-positive rate` ~ `0` (лучше ошибка, чем неверные числа).

---

## 11. Release Scope

## In Scope (v1.0)

1. macOS menu bar app.
2. PTY-based capture `/usage`.
3. Session/week/reset parsing.
4. Plan fallback detection (`Pro/Max hint`).
5. Settings + diagnostics.
6. Базовые тесты pipeline/parser/state machine.

## Out of Scope (v1.0)

1. Multi-platform клиенты.
2. Cloud sync.
3. Исторические дашборды usage.
4. Cost estimation.

---

## 12. Risks & Mitigations

## Risk 1: Anthropic изменит `/usage` layout

Mitigation:

1. tolerant parser;
2. partial fallback + raw diagnostics;
3. тестовые фикстуры на разные варианты layout.

## Risk 2: `claude` недоступен в app environment

Mitigation:

1. расширенный поиск бинаря (`PATH`, common paths, shell resolve);
2. понятное сообщение об ошибке.

## Risk 3: trust flow нестабилен

Mitigation:

1. state machine с ретраем trust confirm;
2. фазовые timeout’ы и controlled failure.

---

## 13. Milestones

1. `M1`: Core capture pipeline + parser + menu bar UI.
2. `M2`: Error handling, stale fallback, settings, diagnostics.
3. `M3`: Plan hint fallback + UX polish (Close/Quit, cleaner header).
4. `M4`: Open-source packaging (`README`, `architecture.md`, tests).

---

## 14. Open Questions

1. Нужно ли выводить отдельный блок `Current week (Sonnet only)` как третий card?
2. Нужен ли явный “last successful at” timestamp в settings (а не в основном поповере)?
3. Нужно ли добавлять telemetry (локальный opt-in лог) для диагностики parser regressions?

---

## 15. Appendix: Current Technical Baseline

Текущая реализация уже содержит:

1. PTY capture (`forkpty`) + ANSI screen parsing.
2. Capture flow state machine для trust + `/usage`.
3. Semantic parser с weekly-priority для `(all models)`.
4. Plan hint fallback (`Pro/Max`) из промежуточных экранов.
5. Unit tests для parser/state machine/ANSI parser.
