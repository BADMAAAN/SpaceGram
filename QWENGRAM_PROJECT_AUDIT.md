# Qwengram — аудит рабочей директории

> Исторический аудит первого этапа. Текущая архитектура **Telegram-iOS + SpaceGram**,
> зависимости, очистка после ребрендинга и проверки описаны в
> [SPACEGRAM_ARCHITECTURE_AUDIT.md](Qwengram/SPACEGRAM_ARCHITECTURE_AUDIT.md).
> Прежние сведения об иконке, remotes и submodules ниже сохранены как история.

Дата: 19 сентября 2026. Источник истины: `C:\Project\Qwengram`.
Проверены фактическое дерево, Git-метаданные, BUILD-файлы, ссылки в исходниках,
ресурсы и реализации ключевых функций. Это статический аудит на Windows,
не подтверждение компиляции, запуска или корректности всех протокольных сценариев.

## 1. Executive summary

Qwengram — самостоятельный продуктовый слой над исторически модифицированной
базой Telegram-iOS. История действительно проходит через Nagram, но отдельный
верхнеуровневый слой `Nagram/` больше не нужен: используемые реализации перенесены
в `Qwengram/Enhancements`, общая локализация — в `Qwengram/Strings`.

Целевая и текущая организация владения кодом: **Telegram-iOS + Qwengram + точки
интеграции**. Перенос не превращает модифицированную базу в чистый upstream:
многочисленные исторические патчи TelegramCore/UI остаются действующими.
Удалять их только по префиксу было бы потерей функций.

Удалены из рабочего дерева Nagram-иконки, их Composer-обработчик и специальные
BUILD-цели, устаревший продуктовый README и два указателя на чужой Bazel execroot.
Авторство и политика бренда сохранены в `BRANDING.md`. Имя приложения уже было
Qwengram; унаследованный вход настроек переименован в `Qwengram · Telegram`.
Временная иконка — существующая штатная Telegram, отдельного дизайна Qwengram нет.
Обновлены также английские onboarding/permission/widget/call строки и два
локализованных override имени приложения (Arabic/Korean).

50 исходно изменённых/неотслеживаемых файлов сохранены с учётом переноса переводов.
Бизнес-логика Ghost, History v2, Media Archive, Qwen и тесты не удалялись.
Ни commit, ни изменение индекса, ни push, ни release не выполнялись.

## 2. Directory map

Классы: A — база Telegram/зависимости; B — собственный Qwengram; C — используемый
унаследованный код; D — ненужное наследие; E — восстанавливаемые артефакты;
F — назначение/происхождение недостаточно установлено, сохранять.

| Директория / файл | Назначение и классификация |
| --- | --- |
| `.git/` | Единственный найденный Git repository; история и локальная конфигурация, сохранять |
| `.github/` | Три workflow, CONTRIBUTING и шаблон issue; A/B, не отдельный Nagram release pipeline |
| `.vscode/`, `.xcodebuildmcp/` | Настройки инструментов; F в части персональных предпочтений, сохранены |
| `build-input/` | Пустой локальный каталог; signing/config inputs отсутствуют, не признак free signing |
| `build-system/` | Make.py, Bazel helpers, генераторы, конфигурации и fake signing; A/C |
| `buildbox/` | Исходники инфраструктуры сборки; A, это не каталог build output |
| `docs/` | Сборка, UI tests, rich-text, demo и журналы миграций; A/C, действующие инструкции сохранены |
| `Qwengram/` | B: Core, Settings, SettingsSignal, SettingsUI, Bots, AI, HistoryStorage, HistoryIntegration, HistoryUI, MediaArchive |
| `Qwengram/Strings/` | B/C: единый общий загрузчик переводов, пять локалей, Qwengram и унаследованные ключи |
| `Qwengram/Enhancements/` | C: восемь используемых пакетов, подробнее ниже |
| `Nagram/` | Бывшие 43 файла перенесены, старый каталог отсутствует |
| `Telegram/` | A/B/C: основное приложение, шесть расширений, Watch, plist, assets и app BUILD |
| `submodules/` | A/C/B: 18 541 файл на входе; большинство — обычные отслеживаемые исходники, не Git-submodules |
| `third-party/` | A: 8 513 vendored файлов на входе; лицензии и бинарные зависимости сохранены |
| `Tests/` | A/B: тесты, демо-приложения, fixtures, QwengramMediaArchiveTests |
| `scripts/` | A/C: сборка/LLDB/simulator helpers; семь файлов на входе, не исполнялись |
| `tools/` | A/B: `main.cpp`, `ipadiff.py`, новая проверка consistency |
| `WORKSPACE` | Пустой маркер workspace, не мусор |
| `MODULE.bazel`, `MODULE.bazel.lock`, `BUILD.bazel`, `.bazelrc` | A/C: Bzlmod, pinning и корневые цели; `local.bazelrc` отсутствует |
| `.gitmodules`, `.gitattributes`, `.gitignore`, `.gitlab-ci.yml` | A/C: зависимости, правила файлов и унаследованная CI-конфигурация |
| `.cursorignore`, `AGENTS.md`, `CLAUDE.md` | Инструкции инструментов; архитектурные описания актуализированы, signing-ограничения сохранены |
| `README.md`, `README_RU.md`, `BRANDING.md` | Описание продукта и сохранённые уведомления об авторстве |
| `versions.json`, `build_number_offset` | Входные параметры сборки, сохранять |
| `qwengram_run7_fix.patch` | F/B: исходно неотслеживаемый пользовательский patch, сохранён побайтно |
| `Random.txt` | F: 18 байт, назначение не установлено; сохранён |
| `bazel-fix-message-filter`, `bazel-message-forwarding-q0kp` | E: отслеживаемые ссылки mode 120000 на недоступные `/private/var/tmp/_bazel_nextalone/...`; убраны в резерв |

Полная исходная файловая инвентаризация, размеры, исходный diff и копии изменённых
файлов сохранены в локальном резерве, указанном в отчёте об очистке. Каталог `.git`
не интерпретировался как исходный код и не очищался. Символические ссылки при
обходе не раскрывались за пределы проекта; другая рабочая директория не читалась.

## 3. Git topology

| Параметр | Фактическое состояние на начало аудита |
| --- | --- |
| Корень | `C:/Project/Qwengram` |
| Branch | `qwengram/main` |
| HEAD | `e7f325c713aa60c997f36edaff68c50eb4c67630` |
| Последний commit | `chore: normalize workflow file`, 16 сентября 2026 |
| Tracking | `qwengram/qwengram/main`, локально ahead 4 относительно сохранённого remote ref; fetch не делался |
| Вторая локальная ветка | `main`, `63c5cb34612b79c73e34132be9058c4688deb9d9` |
| Общий предок HEAD и локального origin/main | `63c5cb34612b79c73e34132be9058c4688deb9d9` |
| origin | `https://github.com/NextAlone/Nagram-iOS.git`, fetch только main |
| qwengram | `https://github.com/BADMAAAN/Qwengram.git` |
| upstream / официальный Telegram remote | Отсутствует |
| Worktrees | Единственный зарегистрированный — текущий |
| Nested repositories | Дополнительных `.git` файлов/директорий не найдено |
| jj | Не установлен; Git разрешён владельцем для этой задачи |

13 gitlinks зарегистрированы в `.gitmodules`; **все не инициализированы**
(`git submodule status` показывает `-`):

- `build-system/bazel-rules/{apple_support,rules_apple,rules_swift,rules_xcodeproj,sourcekit-bazel-bsp}`;
- `submodules/LottieCpp/lottiecpp`, `submodules/TgVoipWebrtc/tgcalls`, `submodules/rlottie/rlottie`;
- `third-party/XcodeGen`, `third-party/dav1d/dav1d`, `third-party/libvpx/libvpx`,
  `third-party/td/td`, `third-party/webrtc/webrtc`.

Их URL относятся к TelegramMessenger, ali-fareed, bazelbuild, MobileNativeFoundation,
spotify, webmproject, tdlib и yonaskolb. Это реальные зависимости, не Nagram-мусор.
Инициализация не запускалась: разрешённый Git в этой задаче — read-only.

Read-only GitHub API `https://api.github.com/repos/BADMAAAN/Qwengram` вернул
`fork: false`, `default_branch: qwengram/main`, без parent/source. Следовательно,
GitHub уже считает этот repository независимым; detach/recreation не требуется.
Локальные remotes не менялись: `origin` ещё обслуживает tracking ветки `main`.
Для последующей работы следует отдельно согласовать добавление официального
Telegram upstream и переименование remotes. Изменение remote URL само по себе
не изменяет ancestry Git или fork network GitHub. Переход в fork network Telegram
потребует отдельного действия владельца на GitHub; здесь оно не выполнялось.

## 4. Telegram-iOS base

`versions.json`: app **12.9.3**, Xcode/deploy Xcode **26.2**, macOS **26**, Bazel
**8.4.2** с SHA-256. Это версия текущего дерева, а не доказанный официальный
Telegram commit. Точный upstream SHA не установлен: официального remote/ref нет,
историческая основа `main` содержит merge demo/release исправлений Nagram.

TelegramCore обеспечивает аккаунты, network/state, TelegramEngine и media lifecycle;
Postbox — локальные транзакции и таблицы; TelegramUI и многочисленные компонентные
пакеты — UI. `// MARK: NAGRAM` обозначает наследованные и обязательные по AGENTS
точки вмешательства; наличие маркера не означает неиспользуемый код.
Postbox→TelegramEngine migration и rich-text composer уже затрагивают базу.
Их журналы в `docs/` сохранены, обратная миграция не выполнялась.

## 5. Qwengram architecture

| Модуль | Реализация и границы |
| --- | --- |
| Core | `QwengramProduct.displayName` |
| Settings | UserDefaults wrappers, master enable и настройки функций; `QwengramGhostPolicy` |
| SettingsSignal | Реактивное наблюдение без polling |
| SettingsUI | Основной контроллер, History settings, Qwen, AI credentials, Tools, Summarizer, Translator, QR |
| Bots | Каталог инструментов; историческое имя модуля/IDs сохранено, это Tools Hub |
| AI | Provider interfaces, Qwen streaming/non-streaming, request gate, cancellation, errors, Keychain |
| HistoryStorage | Postbox ordered collection, schema v1/v2, ограниченные revisions/events |
| HistoryIntegration | **filegroup**, включается в TelegramCore; отдельного Swift-модуля с циклической зависимостью нет |
| HistoryUI | Общий браузер, сведения о сообщении, Quick Look локального media |
| MediaArchive | Отдельное файловое хранение и manifest, capture, retention, hashes, preview |
| Strings | Общий `QwengramStrings`, `QwengramLocalization`, пять локалей; старый `ngI18n` сохранён |
| Enhancements | Совместимые реализации функций, таблица зависимостей в разделе 7 |

Ключевые hooks: `PeerInfoSettingsItems.swift` и settings navigation; `ChatHistoryListNode.swift`
для автоматических read paths; `ChatInterfaceStateContextMenus.swift` для History/AI;
`AccountStateManagementUtils.swift` для старых снимков при server edits/deletes;
`ManagedAutoremoveMessageOperations.swift` для expiration; `AccountViewTracker.swift`,
`ManagedAccountPresence.swift`, `ManagedLocalInputActivities.swift` и
`ManagedSynchronizeViewStoriesOperations.swift` для privacy policies.
TelegramEngine hooks находятся в `Messages/{InstallInteractiveReadMessagesAction,
MarkMessageContentAsConsumedInteractively,Stories,TelegramEngineMessages}.swift`.
Подробности сохранены в `SpaceGram/SPACEGRAM_HOOKS.md`.

## 6. Implemented features

Ниже «реализовано» означает наличие исходников и вызовов, а не успешный device test.

- Foundation/master switch: отключает новые захваты, AI/Tools и Ghost policies,
  не стирает сохранённые данные и ключи. AIRequestGate отслеживает отмену запросов.
- Ghost: opt-in suppression автоматического чтения, активности чата, story views,
  online presence. Прямые mark-as-read и timed/view-once lifecycle сохраняют
  оговорённые исключения; уже отправленные/поставленные операции не отзываются.
- History: старые редакции сообщений, выбранные server deletion events, браузер
  и просмотр записи, schema v2 с чтением v1. Не гарантирует перехват всех удалений.
- Media Archive: opt-in capture полных локальных cloud-media в точках deletion,
  consumption и expiration, account isolation, SHA-256, retention, Quick Look.
  Это независимый архив, не новый сетевой загрузчик исчезнувших файлов.
- Qwen Assistant: запросы пользователя, stream/Stop, выбор модели; Summarizer и
  Translator используют AI layer. API key хранится в Keychain.
- Tools Hub: локальная генерация QR и перечисленные AI-инструменты; неготовые
  пункты остаются отключёнными. QR scanning/persistent AI history не подтверждены.
- Локализация Qwengram English/Russian; унаследованные локали также сохранены.
- Сохранённые функции: native translation providers, LLM translator, regex filters,
  gestures/double tap, context menu, profile utilities, appearance/Liquid Glass,
  media metadata и opt-in iCloud settings.

## 7. Nagram dependency report

| Функция Qwengram | Сохранённая зависимость | Telegram dependency / consumer |
| --- | --- | --- |
| Все продуктовые экраны | Общая локализация теперь `QwengramStrings` | AppBundle, Telegram app string resources |
| Native translation / translate-before-send | Enhancements/Translate + Settings + LLM Keychain | TranslateUI, TextProcessingScreen, ChatMessageDisplaySendMessageOptions, TelegramCore |
| Filters | Enhancements/Settings/NagramRegexFilters | TelegramCore/state и message presentation hooks |
| Gestures, double tap, menus/copy | Settings, MessageDoubleTapAction, MessageMenuSettings | ChatController, ChatInterfaceStateContextMenus, TextFormat, chat bubbles |
| Profile utilities | Settings + RegistrationDate + SettingsUI | PeerInfoScreen и TelegramEngine |
| Layout / Liquid Glass | Settings + SettingsSignal + BottomBarSettings/UI | Display, navigation/tab bars, component UI |
| Media metadata | Enhancements/MediaMetadata | GalleryUI image/video items, TelegramCore resources |
| Link previews / inline bots | Enhancements/LinkMetadata | ChatInterfaceStateContextQueries/InputContexts, TelegramEngine |
| iCloud settings | SettingsCloudSync + TelegramSettingsCloudSync | UserDefaults/KVS, SharedAccountContext, AccountManager |
| Demo/developer utilities | Enhancements/Demo + Settings/NagramDemoMode | AppDelegate, TelegramCore Account/Network, isolated startup |
| Qwen / History / Media Archive | Собственная логика Qwengram; общая локализация только в UI | Postbox, TelegramCore, TelegramUI |

Все восемь enhancement packages имеют живых потребителей. Их удаление либо
удаление UI настроек сделало бы функции недоступными. Переименованы пути владения,
а не все типы/ключи: это уменьшает риск миграции. Удаление Nagram assets выполнено
после отключения всех их потребителей. Подробный список — в
`Qwengram/NAGRAM_REMOVAL_AUDIT.md`.

Оставшиеся упоминания классифицированы в
`Qwengram/audits/remaining-nagram-references.tsv`: attribution/история, необходимые
идентификаторы/ключи и временные технические зависимости. Особенно существенны
`nagram_remote_metadata`, старые deep-link schemes, Keychain/iCloud keys,
`NAGRAM_*` toolchain overrides и signing/notification identifiers. Подмена названия
в этих строках могла бы изменить протокол, удалить доступ к данным или entitlement.

## 8. Build architecture

Bazel/Bzlmod: `MODULE.bazel` + lock; пустой WORKSPACE остаётся маркером. App target
`//Telegram:Telegram`, основной wrapper `build-system/Make/Make.py`. Swift libraries
используют явные deps и glob sources; HistoryIntegration подключён через filegroup.
Изменение путей отражено в прямых потребителях BUILD, локализация включена app target.
Icons теперь компилируются через существующий `DefaultAppIcon`/`AppIconLLC`,
без Nagram IPA post-processor. Это требует проверки actool/IPA на macOS.

CI: `qwengram-ios-test.yml` — ручная unsigned/resignable debug ARM64 сборка;
`testflight.yml` — signed release ARM64, загрузка в App Store Connect, ветка release
или ручной запуск; `build.yml` — старый generic Telegram pipeline на master с release
steps. `.gitlab-ci.yml` — унаследованная build infrastructure. Workflow не запускались.
Старый generic workflow не признан Nagram-only и не удалён; его поддерживаемость
и секреты отдельно не проверены. Product artifact names Qwengram уже используются.

`Tests/AllTests` включает TgCallsTests и QwengramMediaArchiveTests. Последние имеют
runner iPhone 17 / iOS 26.2. Также существуют TextFormat tests, UI tests под
Telegram/Tests и RichTextEditor package tests. XCUITest обязан использовать `--ui-test`.
Ни один iOS test на Windows не запускался. Swift, Bazel и Xcode в PATH не найдены.

Signing-sensitive bundle IDs, team IDs, extension profiles, notification entitlement
allowlists и native scheme не менялись. В BUILD остаётся Nagram notification-only
flag и идентификаторы filtering: это совместимость конфигурации, не branding.
Пустой `build-input` и отсутствующие gitlinks блокируют полноценную локальную сборку
ещё до вопросов подписи. Полная app build — следующий обязательный gate на macOS.

## 9. Storage architecture

| Данные | Реализация / сохранённый контракт |
| --- | --- |
| Qwengram settings | `UserDefaults.standard`, существующие `qwengram.*` ключи |
| Inherited settings | Старые `nagram.*`, wrappers и opt-in KVS; без массовой смены ключей |
| History | Postbox collection **1009**, отдельно на аккаунт; 16-byte message key; JSON v1/v2 |
| History limits | 1 000 сообщений, 20 revisions, 100 events, 256 KiB record; logical maximum около 250 MiB без DB overhead |
| Media Archive | Каталог аккаунта рядом с MediaBox, отдельные файлы/manifest; ссылки на assets из History v2 |
| Media limits | 512 MiB / 1 000 assets; 128 MiB на asset; 30 дней lazy retention; проверка SHA-256 |
| Qwen API key | Keychain service `com.qwengram.ai`, account `qwen.api-key`, WhenUnlockedThisDeviceOnly |
| LLM translation key | Отдельный унаследованный Keychain contract, не объединён с Qwen |
| AI conversation/results | Память процесса/контроллера; постоянная история не реализована |
| Metadata rules | Существующий UserDefaults cache и внешний Telegram metadata channel; TTL 15 минут |

History v1 читается без немедленной перезаписи; следующая запись использует v2.
Будущие неизвестные версии отклоняются. Media eviction может оставить текстовую
историю без бинарного asset; это предусмотренная раздельная retention semantics.
Миграции каталогов приложения/данных эта очистка не выполняет.

## 10. Current limitations

- Архитектурное владение отделено, но исторические изменения базы не извлечены в
  воспроизводимую patch series к конкретному официальному Telegram commit.
- `Nagram*` публичные символы, настройки и внешние metadata/deep-link contracts
  остаются техническим долгом. Их нельзя считать удалёнными только после переноса папок.
- Своя иконка Qwengram отсутствует. Проверка обновления установленного приложения
  с ранее выбранной Nagram alternate icon обязательна; добавлен reset на primary icon.
- Полная компиляция, линковка, actool, entitlements, runtime navigation, iCloud sync,
  сохранение данных на upgrade и device installation здесь не проверены.
- Ghost не является абсолютным сетевым firewall; отдельные native lifecycle events
  остаются разрешёнными. Media capture зависит от наличия полного локального файла;
  secret-chat media, Stories и восстановление из сети не поддержаны.
- Archive search/filter/manual cleanup UI, durable AI conversations и дальнейшие
  security/appearance controls остаются roadmap, не готовыми возможностями.
- Сторонний Swift grammar parser сообщает ошибки на шести product sources и трёх
  затронутых upstream sources **также до изменений**. Новых файлов с parser error
  не появилось; это не заменяет диагностику Swift compiler.

## 11. Repository hygiene

На входе обход содержал 30 269 файлов вне `.git`, 393.26 MiB.
Большие файлы имеют объяснимое назначение: CallUITest video fixture ~10 MiB,
RecaptchaEnterprise simulator framework ~9 MiB, OpenSSL source archive ~8.4 MiB,
sqlite3.c ~8.2 MiB, Opus source archive ~7.5 MiB, Skia test frameworks ~2.8 MiB.
Vendored LCMS PDF/ZIP и generated Telegram API headers — часть зависимостей,
а не автоматически удаляемый cache. Все сохранены.

Собранных IPA, активного bazel-out, Xcode DerivedData или отдельной старой копии
проекта в обследованном дереве не выявлено. Generated headers/API исходники,
lockfiles и vendored archives не удалялись. Пользовательский patch и Random.txt
сохранены. Переименованные файлы остаются unstaged/untracked до решения владельца;
обычный `git diff` не включает содержимое новых untracked путей, поэтому проверка
consistency обходит файловую систему напрямую.

`tools/check_qwengram_consistency.py` проверяет BUILD syntax/labels, наличие
модулей, source glob inclusion, English/Russian product keys, ресурсы и icons;
с PyYAML — синтаксис трёх workflow. Это не Bazel analysis и не Swift type checking.
`git diff --check` прошёл. Детальные результаты и сохранность исходных правок —
в отчёте очистки.

## 12. Recommended next steps

1. На macOS восстановить утверждённые signing inputs и инициализировать pinned
   submodules с отдельным разрешением на Git mutations. Не выбирать free signing
   из-за отсутствия локальных файлов. Проверить Xcode 26.2/Bazel 8.4.2.
2. Выполнить полную simulator build и тесты; проверить bundle strings, icon catalog,
   локализацию пяти локалей и переходы обоих settings screens. Затем full-profile
   device build/install по `docs/build.md`, если запрошена установка.
3. Проверить upgrade с существующими UserDefaults, iCloud, Keychain, History v1/v2,
   media manifest и ранее установленной alternate icon. Не менять ключи без миграции.
4. Создать самостоятельную иконку Qwengram и заменить временный Telegram asset catalog.
5. Согласовать remote topology с официальным Telegram upstream, определить точный
   base commit и каталогизировать исторические patches. Не делать rebase поверх
   незакоммиченной работы.
6. Отдельными изменениями уменьшать совместимые `Nagram*` API и внешние зависимости;
   сначала storage/deep-link tests, затем новые имена. Сохранить attribution.
7. После build gate продолжить roadmap: archive UX/cleanup, AI persistent history,
   regression coverage privacy/TTL paths; не выдавать экспериментальные hooks за
   подтверждённую протокольную защиту.
# Product naming note

Qwengram is now branded as **SpaceGram**. This audit keeps historical source,
module, and compatibility names intact; see
[`Qwengram/SPACEGRAM_BRANDING_AUDIT.md`](Qwengram/SPACEGRAM_BRANDING_AUDIT.md)
for the visible-brand migration.
