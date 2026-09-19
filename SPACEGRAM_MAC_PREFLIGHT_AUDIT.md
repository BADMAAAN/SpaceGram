# SpaceGram — Windows preflight перед первым Mac/Xcode проходом

Дата: 2026-09-19. Рабочая копия: `C:\Project\Qwengram`.

**Результат: доступный Windows-preflight завершён. iOS build, XCTest и runtime не выполнены.**
Владелец подтвердил, что Mac/SSH сейчас недоступны, и поручил завершить Windows-проверки и подготовить перенос.
Это отчёт о готовности исходников к следующей проверке, а не подтверждение готовности приложения к установке.

## 1. Окружение и границы проверки

| Параметр | Фактически обнаружено | Требование / следующий шаг |
|---|---|---|
| ОС / архитектура | Microsoft Windows 10.0.28000, X64 | macOS; `versions.json`: 26 |
| Python | 3.14.7, установленный Miniconda Python | Проверить Python 3 на Mac; работоспособность wrapper на Mac ещё не проверена |
| Xcode / SDK / Simulator | Недоступны | `xcode` и `deploy_xcode`: 26.2 |
| Active developer directory | `DEVELOPER_DIR` не установлен; `xcode-select` недоступен | Сверить фактический active developer directory |
| Bazel | Не найден в PATH | 8.4.2; checksum закреплён в `versions.json` |
| Swift / xcrun / xcodebuild | Не найдены | Нужны инструменты Xcode и iOS SDK |
| jj | Не найден; `jj st` и `jj log -r @ -n 1 --no-graph` недоступны | Восстановить штатный jj workflow перед изменениями на Mac |
| SSH | Windows OpenSSH установлен | Доступного Mac нет по ответу владельца |
| `build-input` | Пуст в этой Windows-копии | Это не свидетельство отсутствия сертификатов на будущем Mac |
| `local.bazelrc` | Отсутствует | Настроить под выбранную фазу на Mac |
| Keychain / profiles / iPhone | Не проверены | Только после стабильного Simulator build перейти к signing preflight |

`versions.json` не изменён: app 12.9.3, Xcode 26.2, Bazel 8.4.2, macOS 26.
В `docs/build.md` также описан прежний локальный Xcode 26.5. Это историческая настройка другого окружения, а не факт об этом хосте и не основание автоматически обновлять Xcode или отключать проверку версий.

Прочитаны `SPACEGRAM_OVERNIGHT_AUDIT.md`, `SPACEGRAM_INTERNAL_MIGRATION_AUDIT.md`,
`SpaceGram/SPACEGRAM_ARCHITECTURE_AUDIT.md`, `SpaceGram/SPACEGRAM_BRANDING_AUDIT.md`,
`SpaceGram/FOUNDATION_AUDIT.md`, `SpaceGram/MEDIA_ARCHIVE_AUDIT.md`, `AGENTS.md`,
нужные разделы `docs/build.md`, `docs/ui-testing.md`, текущие status/diff и build definitions.

## 2. Выполненные проверки

| Проверка | Результат | Ограничение |
|---|---|---|
| `python tools/check_spacegram_preflight.py` | 0 ошибок | Статический Python-checker, не Bazel analysis |
| Вложенный consistency checker | 773 BUILD, 74 Swift-файла, 5 каталогов локализации; 0 ошибок | 74 включает 69 продуктовых и 5 тестовых файлов |
| Все 31 различных literal local dependency labels из SpaceGram BUILD | Пакеты и цели/файлы найдены | Не проверяет транзитивную совместимость API или внешние Bazel repositories |
| Source inclusion / старые активные пути | Проверенные SpaceGram sources включены; старые imports/labels не найдены | Legacy storage keys, fixtures и внешние identifiers сохранены намеренно |
| Коллизии регистра путей SpaceGram и целевых тестов | Не найдены | Не является аудитом всего upstream дерева |
| Plist inputs | 32, включая 2 XML dictionary fragments; успешно разобраны | Финальный объединённый Info.plist ещё не создан |
| XML templates в Telegram/BUILD | 19 шаблонов успешно разобраны с удалёнными placeholders | 3 динамических шаблона требуют Bazel: TelegramEntitlements, NotificationFilteringInfoPlist, NotificationServiceEntitlements |
| Assets | 193 Contents.json, 293 ссылки на существующие файлы | `actool` не запускался |
| Иконки SpaceGram | 36 PNG: размеры, RGB, CRC chunks, zlib, scanline lengths/filter bytes проверены | Pillow недоступен; это не визуальный и не device runtime тест |
| Локализация | 5 каталогов; проверенные literal SpaceGram keys присутствуют в EN/RU | UI layout и динамически составляемые ключи требуют runtime |
| Workflow YAML | 4 файла разобраны | Семантика CI и выполнение workflow не проверены |
| Зависимости | Все 13 директорий из `.gitmodules` существуют и непусты | Точные revisions, рекурсивная полнота и совместимость API не подтверждены |
| Make.py CLI | `build --help`, `query --help`, `test --help` успешны | Только parser/help; не запуск toolchain |
| Swift grammar | 26 advisory nodes в 8 файлах | Не считать ни compiler errors, ни успешной компиляцией |
| `git diff --check` | Успешно | Не проверяет содержимое untracked файлов |
| Сохранность предыдущей работы | Проверка baseline: отсутствующих исходных файлов нет | Сравнение Windows-копии с предыдущим Windows baseline |

Все шесть extension libraries имеют непустые прямые source globs: Share — 1 файл,
NotificationContent — 1, NotificationService — 1, Intents — 3, Widget — 2,
BroadcastUpload — 1. Это количество прямых файлов, а не размер транзитивных модулей.
Основной app target сохраняет все шесть расширений в обычной ветке `extensions`.

Доказательства: `SpaceGram/audits/mac-preflight-static.json`,
`SpaceGram/audits/overnight-preflight.json`, `SpaceGram/audits/overnight-migration-map.json`.
Дополнительные AST/XML/PNG проверки выполнены Python из stdin, без исполнения BUILD-кода.
Для общего checker повторно использовались существующие зависимости в
`$env:TEMP/qwengram-audit-xn59oy9q/validation-deps`; новые пакеты не устанавливались.

## 3. Изменения и сохранность рабочего дерева

В этом проходе продуктовый код, tests, BUILD, signing identifiers и зависимости не изменялись.
Реальных compiler errors не получено; compiler fixes не заявляются.
Добавлены этот отчёт, статические результаты и ведомость переноса.
Предыдущая большая миграция остаётся незакоммиченной; новый `SpaceGram/` и новые assets/tests
необходимо переносить вместе с изменениями отслеживаемых файлов и удалениями старых путей.
Один `git diff` или checkout базового commit не переносит untracked содержимое.

`qwengram_run7_fix.patch` не изменён. SHA-256:
`1a375a8973c3f8c9cdb6c15ad12b52d0d78681def9978f80c57232a6094af0e0`.
Commit, push, tag, release и destructive reset не выполнялись.

`SpaceGram/audits/mac-handoff-manifest.json` фиксирует SHA-256 существующих изменённых
и untracked файлов из `git status --porcelain=v1 -z --untracked-files=all`, а также удалённые пути.
Сам manifest исключён во избежание самоссылки. Это ведомость текущих изменений,
**не полный снимок неизменённого upstream и содержимого submodules**.
Существование правильной копии на Mac сейчас подтвердить невозможно.

Перед переносом и на Mac сверить manifest этой командой из корня проекта:

```sh
python3 - <<'PY'
from pathlib import Path
import hashlib, json
root = Path.cwd()
m = json.loads((root / 'SpaceGram/audits/mac-handoff-manifest.json').read_text(encoding='utf-8'))
errors = []
for row in m['files']:
    p = root / row['path']
    if not p.is_file():
        errors.append('missing: ' + row['path'])
    elif hashlib.sha256(p.read_bytes()).hexdigest() != row['sha256']:
        errors.append('changed: ' + row['path'])
for name in m['deleted_paths']:
    if (root / name).exists():
        errors.append('retired path remains: ' + name)
for error in errors:
    print(error)
print(f"Checked {len(m['files'])} files and {len(m['deleted_paths'])} deletions; {len(errors)} mismatches")
raise SystemExit(bool(errors))
PY
```

Базовый commit из предыдущей инвентаризации: `8ab2f718f66543e778ee51f635c63d0fbf6bbae2`.
Переносить всю рабочую копию на соответствующую базу с материализованными зависимостями,
не накладывать новые файлы поверх старого `Qwengram/` без учёта удалений.
Подтвердить базу и revisions зависимостей через разрешённый workflow на Mac.
Gitignored signing inputs получать отдельно из согласованного владельцем источника;
не копировать чужой workspace и не публиковать секреты в отчёте.

## 4. XCTest: инвентаризация, а не результат выполнения

| Файл | Методов |
|---|---:|
| SpaceGramConversationStoreTests.swift | 10 |
| SpaceGramHistoryQueryTests.swift | 4 |
| SpaceGramMediaArchiveTests.swift | 14 |
| SpaceGramMigrationTests.swift | 15 |
| SpaceGramPrivacyTests.swift | 4 |
| Итого SpaceGram | 47 |

**Passed: 0; failed: 0; skipped XCTest: 0; impossible to run here: 47.**
Это счётчик объявлений `func test...`, не результат XCTest discovery.
`Tests/AllTests` также включает upstream `TgCallsTests`, поэтому итоговое число в полном прогоне может быть больше 47.
Runner целевого набора закреплён на iPhone 17 / iOS 26.2; availability runtime необходимо проверить на Mac.
Тесты миграции секрета проверяют helper с подставленными closures; они не доказывают работу Security.framework,
access groups, заблокированного Keychain или durable owner marker на iPhone.

## 5. Команды для будущего Mac-прохода — НЕ выполнялись здесь

Выполнять из корня перенесённого проекта; перед изменениями выполнить `jj st` и `jj log -r @ -n 1 --no-graph`.
Если jj недоступен, восстановить его или получить отдельное разрешение на требуемые Git-команды.

### Окружение и graph

```sh
sw_vers
uname -m
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun --find swift
xcrun swift --version
python3 --version
cat versions.json
xcrun simctl list runtimes
xcrun simctl list devices available
python3 tools/check_spacegram_preflight.py
```

Проверить pinned Bazel 8.4.2, который использует Make.py, и checksum из `versions.json`.
Не подменять его произвольным `bazel` из PATH. Подтвердить наличие iOS 26.2 runtime.
Проверить все local_path_override из MODULE.bazel и директории зависимостей.
Не лечить пустые зависимости сменой signing mode.

Для Simulator использовать отдельную локальную конфигурацию: сохранить существующий `local.bazelrc`, если он есть,
и добавить `build --//Telegram:disableProvisioningProfiles`. Оставить расширения включёнными для проверки всех targets;
не включать `disableExtensions` и `nagramNotificationExtensionsOnly` для обхода ошибок.
Документированный упрощённый simulator mode разрешает отключение расширений, но его успешность не подтверждает их сборку.

```sh
python3 build-system/Make/Make.py --cacheDir ~/telegram-bazel-cache \
  query --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --queryArgs='deps(//Telegram:Telegram)'
```

В этой версии Make.py подкоманда `query` вызывает **Bazel aquery**, а не обычный query;
она уже требует рабочего Apple toolchain и generated build configuration.
Проверить resolved graph и generated plist/entitlements; XML placeholders в Windows ещё не подтверждают их значения.

### Полная Simulator build и XCTest

```sh
set -o pipefail
python3 build-system/Make/Make.py --cacheDir ~/telegram-bazel-cache \
  build --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError 2>&1 | tee /tmp/spacegram-simulator-build.log

python3 build-system/Make/Make.py --cacheDir ~/telegram-bazel-cache \
  test --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning 2>&1 | tee /tmp/spacegram-xctest.log
```

Команды предполагают соответствующий pinned Xcode. `--overrideXcodeVersion` добавлять перед subcommand
только после проверки фактической версии и обоснования совместимости, а не автоматически.
Не добавлять warning suppression или обновлять зависимости до анализа конкретной ошибки.
Сохранять exit status и test XML из `bazel-testlogs`; разделять build failure, test failure, skip и unavailable runtime.
Исправлять минимальный root cause, повторять полную сборку и затронутые проверки.

### Simulator smoke и миграции

Использовать отдельный тестовый Simulator, выбранный по `simctl list`, и booted device этого прогона.
После сборки на свежем тестовом Simulator:

```sh
SPACEGRAM_SIM_DIR="$(mktemp -d /tmp/spacegram-sim.XXXXXX)"
unzip -q bazel-bin/Telegram/Telegram.ipa -d "$SPACEGRAM_SIM_DIR"
SPACEGRAM_SIM_APP="$SPACEGRAM_SIM_DIR/Payload/Telegram.app"
SPACEGRAM_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SPACEGRAM_SIM_APP/Info.plist")"
xcrun simctl uninstall booted "$SPACEGRAM_BUNDLE_ID" # только на выделенном тестовом Simulator; отсутствие app допустимо
xcrun simctl install booted "$SPACEGRAM_SIM_APP"
xcrun simctl launch booted "$SPACEGRAM_BUNDLE_ID" --ui-test
```

Не задавать bundle ID из памяти; читать итоговый plist. Uninstall обязателен при обычном обновлении Simulator
из-за возможных старых dylib, но **не применять его к upgrade/migration fixture или данным реального iPhone**.

- Проверить launch/branding, Settings → SpaceGram, General, Ghost, History, Media Archive, Tools & AI, Appearance,
  Qwen без API запроса, theme picker и App Icon UI; записать доступность экранов до/после тестового login.
- Для XCUITest использовать только предусмотренный `--ui-test` и Telegram test servers. Проект нужно предварительно сгенерировать
  штатным workflow; команду `xcodebuild test` из `docs/ui-testing.md` адаптировать к реально установленному simulator runtime.
- `--ui-test` очищает изолированное хранилище на каждом запуске. Проверки upgrade, persistence и relaunch проводить отдельно
  на одноразовой тестовой копии с сохраняемыми fixtures; автоматизированные XCUITests с production data не запускать.
- Снять фактические логи/скриншоты и crashes; изменение иконки на Simulator не заменяет подтверждение на iPhone.

## 6. Миграции: что известно из исходников и что проверить

| Область | Статически установлено | Обязательная проверка на Apple runtime |
|---|---|---|
| UserDefaults | Legacy keys копируются, новое значение (включая false) имеет приоритет; legacy сохраняются | Повторный запуск, частичный перенос, master switch, shared defaults основного app/extension |
| Keychain | New-first, legacy scoped/unscoped fallback; запись и read-back до удаления старого; owner marker | Реальный Keychain, два аккаунта, lock/unlock, ошибки записи/удаления, relaunch; секреты не логировать |
| History | Postbox collection 1009 и packed message identity сохранены | v1/v2 fixtures, edit/delete, filters, media references, account isolation |
| Media | `qwengram-media-v1` → `spacegram-media-v1` через same-parent rename под lock | Manifest/payload/UUID, interrupted files, два аккаунта, повторный запуск, конфликт двух директорий |
| AI history | `qwengram-conversations-v1` → `spacegram-conversations-v1`; migrate перед clear/delete | Отсутствие resurrection, partial response, rename/delete, relaunch и context trimming |

У History **нет отдельной переименовываемой директории**: данные находятся в существующем Postbox.
Не создавать фиктивную directory migration только ради названия пункта checklist.
При одновременном наличии старого и нового archive мигратор сообщает конфликт и сохраняет обе копии.
Старые данные не удалялись и миграторы не запускались над пользовательскими данными в этом проходе.
Crash durability, межпроцессная работа lock и отсутствие repeated migrations требуют runtime подтверждения.

## 7. Signing и device — отложены до стабильного Simulator build

Не выбран ни full signing, ни free Apple ID mode. Windows-копия не содержит local signing inputs.
Нельзя пока назвать конкретное действие в Apple Developer Portal: отсутствуют сведения о выбранном Mac,
сертификате, профилях и устройстве. Identifiers не менять.

На Mac после успешных предыдущих фаз:

1. `xcrun devicectl list devices`: найти подключённый paired iPhone и проверить Developer Mode.
2. `security find-identity -v -p codesigning`: проверить действующий Apple Development identity.
3. Сверить `build-input/local-configuration.json` с сертификатом и всеми 7 development profiles:
   app, Share, NotificationContent, NotificationService, Intents, Widget, BroadcastUpload.
4. Проверить срок, Team ID, application-identifier, device UDID, App Groups, Keychain groups, push/Siri entitlement
   и фактически генерируемые entitlement каждого target. У Intents suffix bundle ID — `.SiriIntents`, имя profile — `Intents`.
5. Для full signing убрать simulator-only `disableProvisioningProfiles`, оставить все расширения включёнными.
   Проверить, что нет `disableExtensions` и режима только notification extensions.
6. При недостающих материалах запросить только конкретные обнаруженные недостающие assets у владельца;
   не переходить автоматически к free signing. Для такого режима требуется явный запрос владельца.

Только при пройденном signing preflight:

```sh
set -o pipefail
python3 build-system/Make/Make.py --cacheDir ~/telegram-bazel-cache \
  build --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 --configuration=debug_arm64 --continueOnError 2>&1 | tee /tmp/spacegram-device-build.log
```

До установки проверить generated IPA: итоговый Info.plist, primary/Alternate icon declarations,
все 6 `.appex`, подпись и соответствие embedded profiles/entitlements. Development/debug, без TestFlight/release.
После выбора фактического UDID:

```sh
SPACEGRAM_DEVICE_UDID='<UDID из devicectl>'
SPACEGRAM_DEVICE_DIR="$(mktemp -d /tmp/spacegram-device.XXXXXX)"
unzip -q bazel-bin/Telegram/Telegram.ipa -d "$SPACEGRAM_DEVICE_DIR"
xcrun devicectl device install app --device "$SPACEGRAM_DEVICE_UDID" "$SPACEGRAM_DEVICE_DIR/Payload/Telegram.app"
xcrun devicectl device info apps --device "$SPACEGRAM_DEVICE_UDID"
```

Проверить установленный bundle ID/version и запуск. Не удалять старое приложение перед проверкой upgrade.
IPA без подтверждённой установки и проверки результата не считать завершённым device-проходом.

## 8. Runtime checklist и оставшиеся ограничения

Все пункты ниже **NOT RUN**:

- Core: launch, тестовый Telegram login, account switching, chats, send/receive.
- SpaceGram: master switch и live updates, RU/EN, Appearance; primary → Alternate → Default и состояние после relaunch.
- Ghost: read receipts, typing/activity, online, Stories, media consumption, mentions/reactions/polls/read metrics.
  Для каждого отметить серверный результат со второго аккаунта/устройства; наличие переключателя не доказывает эффект.
- History: edit/delete, rich text, filters, account isolation, удалённые/недоступные assets.
- Media: photo/video/file, удаление после download, partial/missing resources, cleanup, reference safety и лимиты.
- TTL/view-once: только тестовый контент; проверить штатные timers, архивирование только реально полученного локального asset;
  неполученный ресурс не должен отображаться восстановленным.
- AI: Keychain, реальный Qwen request, streaming/Stop, partial response, history/relaunch, context budget, master switch;
  без API keys, заголовков Authorization и пользовательских сообщений в диагностических логах.
- Performance: main-thread stalls, copy spikes, memory, crashes, repeated migration, cleanup и завершение streaming lifecycle.

Новых подтверждённых History/Media/AI дефектов этим статическим проходом не установлено.
Это не означает их отсутствия. Особенно не подтверждены Keychain migration, server-side Ghost behavior,
rendering/history rich text, lifecycle streaming и App Groups взаимодействие расширений.

## 9. Условия продолжения

Windows-side исходники и материалы проверки подготовлены к переносу.
Следующая обязательная точка — Mac с Xcode/SDK, полная копия рабочего дерева и зависимостей,
сверка manifest, затем реальный aquery → full Simulator compilation → XCTest → runtime.
Для последующих фаз нужны signing assets, paired iPhone и тестовый второй аккаунт/устройство;
для живого AI запроса — настроенный владельцем ключ.
До этих проверок статус проекта: **build/runtime readiness не подтверждена**.
