# Nagram removal / migration audit

> Historical first-pass audit. The current SpaceGram cleanup, exact removal
> scope and dependency inventory are in [SPACEGRAM_ARCHITECTURE_AUDIT.md](SPACEGRAM_ARCHITECTURE_AUDIT.md).
> The icon, remotes, submodule initialization and profile-badge statements below
> describe the earlier snapshot, not the current tree. The linked TSV inventories
> have been regenerated for the current tree.

Дата: 19 сентября 2026. Рабочая директория: `C:\Project\Qwengram`.
Основной обзор: [QWENGRAM_PROJECT_AUDIT.md](../QWENGRAM_PROJECT_AUDIT.md).

## Что обнаружено

На входе Nagram состоял из девяти пакетов (43 файла), а его зависимости были
встроены в TelegramCore, TelegramUI, SettingsUI, GalleryUI, TranslateUI и другие
компоненты. Простое удаление каталога сломало бы сборку, перевод, настройки,
жесты, фильтры, профильные утилиты, iCloud и demo startup.

Продуктовые SettingsUI/HistoryUI Qwengram непосредственно использовали
`NagramStrings`, включая новые незакоммиченные английские и русские строки.
Qwen, History и Media Archive имеют собственные реализации; заменять их
унаследованными аналогами оснований нет.

Branding был смешан: имя основного приложения уже Qwengram, но Settings entry,
icon selector, primary/alternate icon resources и IPA post-processor относились
к Nagram. Два корневых Bazel symlink placeholders указывали на чужие macOS execroot.
README и agent instructions описывали трёхслойный продукт Telegram→Nagram→Qwengram.

## Что перенесено и переименовано

| До | После | Контракт |
| --- | --- | --- |
| `Nagram/Settings` | `Qwengram/Enhancements/Settings` | `NagramSettings`, defaults/Keychain/iCloud keys сохранены |
| `Nagram/SettingsSignal` | `Qwengram/Enhancements/SettingsSignal` | Реактивные APIs сохранены |
| `Nagram/SettingsUI` | `Qwengram/Enhancements/SettingsUI` | Все работающие контроллеры сохранены |
| `Nagram/Translate` | `Qwengram/Enhancements/Translate` | Native/LLM translation facade сохранён |
| `Nagram/LinkMetadata` | `Qwengram/Enhancements/LinkMetadata` | Metadata channel/cache/protocol сохранены |
| `Nagram/MediaMetadata` | `Qwengram/Enhancements/MediaMetadata` | Gallery inspection сохранён |
| `Nagram/TelegramSettingsCloudSync` | `Qwengram/Enhancements/TelegramSettingsCloudSync` | Синхронизация сохранена |
| `Nagram/Demo` | `Qwengram/Enhancements/Demo` | Demo/test startup сохранён |
| `Nagram/Strings` | `Qwengram/Strings` | Один общий ресурсный модуль, без дубликата |
| `NagramStrings` | `QwengramStrings` | Все Swift imports и BUILD deps обновлены |
| `NagramLocalization` | `QwengramLocalization` | Загрузчик и его singleton переименованы |
| `NagramLocalizableStrings` | `QwengramLocalizableStrings` | App resource dependency обновлена |
| `NagramLocalizable.strings` | `QwengramLocalizable.strings` | Все пять локалей и lookup имени ресурса обновлены |
| `nagramFallbackLocale` | `qwengramFallbackLocale` | Поведение fallback не менялось |

`ngI18n`, ключи `Nagram.*` и существующие публичные enhancement symbols остались.
Это единая реализация, а не пара независимых слоёв. Перенос переводов включил
пользовательскую `ru.lproj`, которая на входе была untracked.

Английские onboarding, permissions, widget/call и другие брендовые строки основного
каталога Telegram переведены на Qwengram; Arabic/Korean CFBundleDisplayName overrides
также показывают Qwengram. Ключи Telegram strings остаются прежними.

Раздел настроек унаследованных возможностей теперь называется **Qwengram · Telegram**;
отдельный продуктовый раздел Qwengram остаётся. Старые enum/navigation cases и
long press debug action сохраняют доступ к уже работающим настройкам. `Nagram.Title`
показывает Qwengram, iCloud footer описывает Qwengram enhancements. Упоминания
внешнего Nagram metadata provider и community attribution не маскировались
названием Qwengram.

## Что убрано из рабочего дерева

- 114 файлов в 47 корневых элементах icon pipeline (1 843 268 байт), включая
  семейства `Telegram/Telegram-iOS/Nagram*.icon`, `Nagram*.alticon`, `Nagram*.png`,
  включая Build/26 варианты. Удалены их preview/alternate/Composer BUILD declarations.
- `Telegram/Telegram-iOS/NagramFixComposerAlternateIcons.sh`, genrule и sh_binary
  `GenerateNagramFixComposerAlternateIcons` / `NagramFixComposerAlternateIcons`.
- Устаревшие Nagram-only icon-title и special preview branches в SettingsUI.
- Nagram icon list из AppDelegate. Теперь единственный selectable icon — стандартный
  `BlueIcon`; active alternate icon при upgrade сбрасывается в primary через UIKit.
- Ссылка на удалённый PNG в UTTypeIconFiles убрана; theme documents используют
  системное представление вместо dangling file reference.
- `docs/UPSTREAM_NAGRAM_README.md`: дублирующий старый продуктовый README.
  Copyright/brand notices остаются в `BRANDING.md`, исходная копия — в резерве.
- `bazel-fix-message-filter`, `bazel-message-forwarding-q0kp`: два доказанно
  устаревших указателя на Bazel output другого компьютера.

Автоматическая проверка отклонила первоначальную объединённую команду правок и
массового удаления; подробная причина не предоставлена. Она не исполнилась.
Вместо необратимого удаления ресурсы перемещены в резерв через проверенные
абсолютные пути, после проверки `git status` для каждого icon root. Пользовательские
изменённые assets не перемещались. В Git это unstaged удаления исходных путей.

Резерв этой сессии:
`C:\Users\somebody give a fuck\AppData\Local\Temp\qwengram-audit-xn59oy9q`.
Он содержит `originals/`, `baseline.diff`, `initial.json`, `inventory.json`,
`retired-icons/`, старый README и два symlink placeholders. Это временный локальный
резерв, не долговременная система backup; он не добавлен в репозиторий.

## Что осталось и почему

| Остаток | Класс | Причина |
| --- | --- | --- |
| Enhancement module/type/function names `Nagram*` | Временная техническая зависимость C | Живые consumers; полный rename не требуется для смены владения |
| `nagram.*` settings, iCloud/cache/Keychain identifiers | Необходимо | Переименование без data migration сбросило бы доступ к данным |
| `Nagram.*` localization keys | Необходимо | Динамические ключи и сотни callers; один общий ресурсный модуль |
| `nagram_remote_metadata`, deep links / nasettings | Временная внешняя зависимость | Существующий remote protocol и опубликованные ссылки |
| Notification bundle IDs, filtering plist keys, extension-only flag | Необходимо до отдельной проверки signing | Не менять entitlement-sensitive contracts на Windows |
| `NAGRAM_*` Make.py toolchain overrides | Временная техническая зависимость | Совместимость существующих local build configurations |
| `// MARK: NAGRAM`, copyright/header/history | Attribution / необходимо | Происхождение кода и обязательные rebase-маркеры AGENTS |
| BRANDING.md | Attribution | Уведомления правообладателей не заменяются новым именем продукта |
| Profile badge/community explanatory strings | Attribution | Реальные исторические авторы/спонсоры, не собственные разработчики Qwengram |
| Historical plans/build/refactor docs | Необходимо / история | Описывают сохранённые реализации и воспроизводимость |
| origin remote Nagram | Локальная техническая зависимость | `main` всё ещё tracking origin; изменения Git config не выполнялись |

Реестр [remaining-nagram-references.tsv](audits/remaining-nagram-references.tsv)
содержит файл, строку, число совпадений и консервативную классификацию каждой
оставшейся текстовой строки с Nagram вне Git/binary/signing данных. Это реестр
совместимости и происхождения, не доказательство того, что каждый private helper
минимально необходим. Неподтверждённые dead-code кандидаты не удалялись.
Сам TSV исключён из повторного сканирования, чтобы не считать его собственные записи.

## Какие зависимости и BUILD files изменены

Все старые абсолютные Bazel package paths `//Nagram/...` заменены текущими путями.
Переезд Strings дополнительно меняет имя Swift module/resource target. Остальные
module names сохранены, поэтому imports `NagramSettings` и подобных корректны.

Обновлены девять перенесённых BUILD, `Qwengram/{SettingsUI,HistoryUI}/BUILD`,
`Telegram/BUILD` и прямые consumers в `submodules`, в том числе TelegramCore,
TelegramUI, SettingsUI, GalleryUI, TranslateUI, Display, ChatListUI, TextFormat,
TextProcessingScreen и компоненты, использующие enhancement settings/signals.
Точный список текущих consumer→label связей находится в
[enhancement-dependencies.tsv](audits/enhancement-dependencies.tsv).

Source globs перемещены вместе с файлами; HistoryIntegration остаётся filegroup
TelegramCore. Цели тестов, media archive, Qwen request gate и schema v2 не удалены.
Иконки теперь используют `primary_app_icon = "AppIconLLC"` и `:DefaultAppIcon`.
Все файлы, перечисленные в Contents.json этого каталога, существуют.

Точки изменения upstream Swift имеют `// MARK: NAGRAM`; дополнительно сохранены
существующие QWENGRAM markers. Изменения app icon wiring и импортов не являются
заявлением о прохождении линковки или проверки IPA.

## Сохранность текущей разработки

До редактирования сохранены исходный binary diff и содержимое 50 файлов с текущими
пользовательскими изменениями/untracked additions. Все эти файлы существуют после
операции, включая переехавшие English/Russian catalogs. 31 файл побайтно неизменен;
42 исходно изменённых Swift/BUILD-файла дополнительно сравнены целиком с допустимыми
заменами imports/labels/markers — непредусмотренных изменений нет. Остальные получили
только необходимые imports/BUILD/resource references,
документацию или значения отображаемого бренда. Все исходные `Qwengram.*` значения
English/Russian сравнены с резервом и совпадают.

Ghost policy, settings storage, suppression logic, HistoryStorage schema/data,
TTL/view-once hooks, MediaArchive, AI provider/request gate/Keychain и тестовые
исходники не переписывались ради очистки. Временно возникшая проблема encoding
при правке трёх первоначально чистых файлов исправлена повторным применением
правок к проверенному UTF-8 исходнику; пользовательские изменения этим не затронуты.

## Реально выполненные проверки

| Проверка | Результат и границы |
| --- | --- |
| `git status`, log, remotes, worktrees, gitlinks | Выполнены; 13 uninitialized submodules, один repository/worktree |
| Инвентаризация дерева/размеров | Выполнена без раскрытия ссылок за пределы workspace |
| `python tools/check_qwengram_consistency.py` | 768 BUILD, 58 product Swift source paths, 5 catalogs: syntax/labels, module existence, glob inclusion, app resources и icon files проходят |
| Workflow YAML | Три файла разобраны PyYAML; семантика Actions/секреты не проверены |
| English/Russian keys | Все статические product `ngI18n` keys найдены в обеих локалях; старые значения сохранены |
| Старые пути, labels, localization module/resource names | В действующих Swift/BUILD ссылках отсутствуют |
| Deleted icon consumers | Удалённый icon post-processor, target names и preview resource names больше не используются |
| Swift third-party grammar | Строгий дополнительный запуск сообщает шесть ошибок product sources, также существующих до cleanup; это **не успешная Swift syntax validation** |
| Swift baseline comparison | Для обследованных собственных и изменённых upstream Swift файлов новых файлов с parser error не обнаружено; старые upstream errors в AppDelegate/AccountStateManagementUtils/AccountViewTracker сохраняются |
| `git diff --check` | Прошёл; новые untracked файлы дополнительно читаются filesystem checker |
| iOS build / XCTest / installation | Не выполнялись: Windows, нет Xcode; Swift/Bazel также не найдены в PATH |

PyYAML/tree-sitter пакеты установлены только в `validation-deps/` временного резерва.
Для повторной проверки YAML нужен PyYAML в Python environment. Опциональная команда
`python tools/check_qwengram_consistency.py --swift-grammar` требует tree-sitter и
tree-sitter-swift и на данном дереве завершится ошибкой из-за описанных parser findings.
Без опционального флага checker проверяет ссылки/ресурсы, а не грамматику Swift.

## Риски и следующий gate

1. Полная macOS app build обязательна: Windows consistency не проверяет Swift types,
   Bazel analysis, visibility/linking, resource collisions и actool behavior.
2. Проверить запуск/иконку после upgrade с выбранным Nagram alternate icon. Своего
   Qwengram artwork нет; временный Telegram icon — явно незавершённый branding.
3. Проверить settings navigation, все локали, iCloud/Keychain и данные v1/v2 на upgrade.
4. Структура ownership упрощена, но namespace cleanup и выделение минимальных
   patches из исторической базы ещё требуют отдельных миграций и macOS regression tests.
5. Remote metadata provider и deep links всё ещё зависят от исторической инфраструктуры.
   Для независимости поведения потребуется свой контракт/миграция, а не rename URL.
6. GitHub уже `fork: false`; внешних действий для detach не требуется. Локальные
   remotes отдельно привести к роли официального Telegram upstream после согласования.

Не выполнены commit, push, pull/rebase/merge, reset/checkout/clean, tag/release,
изменение GitHub repository или удаление веток. Индекс не менялся.
