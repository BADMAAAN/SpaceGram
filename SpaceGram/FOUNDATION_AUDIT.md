# Qwengram foundation audit — 2026-09-18

**Historical Foundation snapshot.** The subsequent Ghost/Media Archive stage is
implemented and documented in [MEDIA_ARCHIVE_AUDIT.md](MEDIA_ARCHIVE_AUDIT.md).
That audit supersedes the v1/no-binary/archive-not-implemented statements below
and records the current validation results and remaining limitations.

This is a source audit and first implementation increment, not certification of
all features in the product roadmap. The supplied request ends at `online/p`.

## Actual source inventory

| Area | Existing implementation and current result |
| --- | --- |
| Settings | `Settings/QwengramSettings.swift`, `SettingsSignal/Sources/QwengramSettingsSignal.swift`; persistent device-wide UserDefaults preferences. Effective feature/ghost policies now include the master switch. No account-specific settings migration. |
| Settings UI | `SettingsUI/QwengramSettingsController.swift`; Telegram ItemList UI, General, Ghost, History, Tools & AI, Media. Uses the existing QwengramStrings loader and separate Qwengram English/Russian keys. No empty security/appearance screens. |
| Tools | `Bots/QwengramBotDescriptor.swift` and existing controllers retained; Tools Hub name replaces the visible Bots title. QR is local; unfinished catalog entries remain disabled. |
| AI | `AI/QwengramQwenProvider.swift`; regular HTTP and SSE, model, Stop, Qwen Assistant, Summarizer, Translator, explicit send from selected message text. Requests are gated/cancelled by the master switch. No conversation persistence or attachments. |
| Secrets | `AI/QwengramAIKeychain.swift`; `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, app-scoped Qwen key. Separate from Nagram's translation provider credentials. |
| HistoryStorage | Account Postbox collection 1009; schema v1, complete packed message identity, text/entities/author/time/metadata, ordered revisions/events. 1,000 records, 20 revisions, 100 events, 256 KiB per record. Older revisions/events now yield to the newest when the byte cap is reached. |
| HistoryIntegration | Source filegroup compiled in TelegramCore; old-content callback and explicit server deletion sources. Timed deletions/expiration and secret chat archives are excluded. Capture uses the effective master/history policy. |
| HistoryUI | Existing archive browser and per-message detail remain accessible while disabled. Fault-isolated reads exist. Search/filter/cleanup/media playback are not yet implemented. |
| Ghost | Opt-in automatic chat-read suppression, chat activity suppression, regular/pinned Story acknowledgements and explicit presence. Native unread state and explicit Mark as Read preserved. No guarantee of server-side invisibility. |
| Media archive | No binary archive exists. Existing media metadata is descriptive only. No recovery of missing resources is implemented or claimed. |

All existing TelegramUI/Core integrations are inventoried in SPACEGRAM_HOOKS.md.
The pre-existing `qwengram_run7_fix.patch` was not modified or applied.

## Reuse and next integration points

- Nagram's `Settings/NagramRegexFilters.swift` already has enable flags, peer
  scopes, regex validation and hide/mask/replace-style actions; inspect its actual
  action enum and SettingsUI before adding Qwengram controls. It uses throwing
  NSRegularExpression construction and skips invalid compiled expressions.
- `Qwengram/Enhancements/Translate` and `NagramTranslationLLMKeychain.swift` are separate translation
  facilities. Do not merge them with Qwen Assistant credentials or conversation state.
- `Qwengram/Enhancements/MediaMetadata` inspects available resource metadata; it is not a durable
  binary archive. A completedResourcePath lookup alone cannot protect against
  eviction between lookup and copying.
- `TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift` removes
  timed messages or replaces media with expiration tombstones inside a transaction.
  A future archive needs resource retention, off-transaction copying, account-local
  paths, bounded cleanup and crash recovery before attaching to this path. Simply
  dispatching a copy after deletion would introduce a resource race.
- Read state transport includes `State/SynchronizePeerReadState.swift`, explicit
  `TelegramEngine/Messages/MarkAllChatsAsRead.swift`, reply-thread read discussion,
  and content-consumption operations. Further receipt coverage must distinguish
  explicit actions, local read state and server synchronization; never falsely
  confirm a skipped synchronization as delivered.
- Telegram has `PasscodeUI`, `SettingsUI/.../PasscodeOptionsController.swift` and
  `LocalAuth`. Reuse the existing app lock before considering another PIN store.
- `submodules/Markdown/Source/Markdown.swift`, rich-text components and browser
  markdown support exist. Inspect rendering capabilities before expanding AI UI.

## Build and validation

`versions.json` pins Xcode 26.2, Bazel 8.4.2 and macOS 26. This host is Windows,
with Python but without Swift, Bazel, Xcode, simulator or an iPhone install path.
Full iOS compilation and runtime/privacy verification remain outstanding.

- `python build-system/Make/Make.py --help`: passed; the supported build/test entry
  point was inspected. No signing flags or credentials were changed.
- Passed static parsing of 12 BUILD files: Qwengram plus touched TelegramCore/TelegramUI and
  QwengramStrings; checked referenced local packages, added target names and source-glob coverage.
  This is static validation, not Bazel analysis or Swift type checking.
- Compared 22 changed/new Swift files with pre-edit tree-sitter baselines: no new
  parser diagnostics. The parser reports
  pre-existing false positives for empty tuple expressions `()`; these must not be
  presented as compiler errors or a successful Swift compile.
- Passed 26-key English/Russian parity, duplicate-key, UTF-8, UI-reference and
  Settings stable-ID checks; checked inclusion
  through Telegram's existing QwengramLocalizableStrings resource dependency.
- `Tests/AllTests/BUILD` includes TgCallsTests, not a dedicated Qwengram suite.
  No new implementation-mirroring Python tests were substituted for runtime tests.
- `qwengram-ios-test.yml` uses a manual macos-26 debug ARM64 workflow with fake
  signing for a resignable artifact; it is not proof of device installation.
  `testflight.yml` publishes signed release builds and must not be dispatched here.
  The older `build.yml` targets macos-13 despite the newer pinned toolchain.
  Workflows were inspected, not triggered or changed.
- `jj st` / `jj log -r '@' -n 1 --no-graph` could not run because jj is absent.
  The explicitly requested `git status --short` was read before editing. No other
  Git command, commit, push or release was performed. Review used saved file baselines.

## Required macOS validation before release

1. Full app simulator build through Make.py following docs/build.md, then existing
   tests. UI tests must use `--ui-test`; device builds require the signing preflight.
2. Toggle Qwengram off with ordinary and streaming Qwen requests in flight. Verify
   one completion per request, no subsequent chunks, preserved text/history/key,
   disabled actions, and a fresh request after reenable. Verify with a local HTTP
   fixture, not a real user's messages or API key.
3. Start with each Ghost option off (native behavior), then independently enable
   them. Verify outbound requests with a test account: chat views do not mark
   messages read; explicit Mark as Read does; typing/recording/upload actions are
   absent; voice calls work; both Story paths suppress acknowledgements; online
   timer stops while updates and push continue. Repeat across account switches.
4. Exercise foreground/background, live incoming messages, forums/reply threads,
   media consumption and settings changes with pending operations. Confirm the
   documented limitations instead of promising universal invisibility.
5. Fill an archive record past the byte limit using large multibyte revisions;
   verify oldest-first eviction, monotonically increasing revision numbers,
   missing-revision UI, and no partial write if a single newest snapshot is too
   large. Verify account isolation, corrupt-entry handling and disabled capture.
6. Inspect English/Russian Settings and Tools UI at large Dynamic Type sizes.

The broader roadmap remains open: binary media archive/TTL retention, richer
History UI, comprehensive receipt policy, scheduled sending, persistent AI chats,
Qwengram filter controls and additional privacy/appearance integration.
