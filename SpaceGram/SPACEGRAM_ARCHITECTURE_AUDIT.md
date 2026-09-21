# SpaceGram architecture map

Updated from the product source on 2026-09-21. This document maps the current SpaceGram-owned layer; historical audit files describe earlier checkpoints and are not product contracts.

## Ownership and integration

SpaceGram is Telegram-iOS plus product-owned modules under `SpaceGram/` and minimal integration hooks in `Telegram/` and `submodules/`. Upstream edit sites use nearby `// MARK: NAGRAM` markers. Retained Nagram-derived implementations live under `SpaceGram/Enhancements/` with attribution and compatibility identifiers preserved.

The active product has no SpaceGram AI/Qwen module and no custom SpaceGram QR feature. Native Telegram QR flows remain upstream.

| Module | Responsibility |
| --- | --- |
| `Core` | Product identity. |
| `Settings` | Product defaults, the single global Ghost state and feature gates. |
| `SettingsSignal` | Serialized reactive policy updates used at UI and RPC boundaries. |
| `SettingsUI` | One grouped SpaceGram hub plus privacy, archive, translator and message-menu screens. |
| `HistoryStorage` | Account-specific saved revisions and delete events. |
| `HistoryIntegration` | Capture hooks compiled into TelegramCore where a separate module would create a dependency cycle. |
| `HistoryOverlay` | Presentation-only reconstruction of deleted messages using local message namespaces. |
| `HistoryUI` | Local history inspection and cleanup. |
| `MediaArchive` | Account-derived storage, validated atomic publication, resource deduplication, leases and bounded cleanup. |
| `MessageShot` | Bounded rendering of selected messages. |
| `Privacy` | Account privacy policy and local sanitization helpers. |
| `Appearance` | SpaceGram presentation adapters and icon selection integration. |
| `Bots` | Local tool descriptors; ordinary Telegram inline-bot behavior stays upstream. |
| `Strings` | Shared product and retained-enhancement localization catalogs. |
| `Migration` | Idempotent migration of compatible legacy defaults and storage paths. |
| `Enhancements` | Retained settings, translation, inline-rule and UI implementations. |

## Runtime contracts

### Ghost Mode

`SpaceGramSettings.ghostModeEnabled` is the only persistent master state used by the settings screen and quick button. The effective policy is disabled when the SpaceGram master switch is off.

Presence and chat activity are filtered in `ManagedAccountPresence.swift` and `ManagedLocalInputActivities.swift`, with a second check at the request boundary. Group-call speaking is intentionally exempt. Story enqueue and synchronization paths suppress view acknowledgements. Automatic visible-history reads and related automatic actions are stopped without rewriting local unread state.

### Read on Interact and delayed send

Read on Interact is granted only after a successful ordinary cloud send or successful reaction. Scheduled/pending messages do not grant it. Forum and saved-history paths use their matching read request.

Delayed Send preserves explicit native schedules, uses corrected `network.globalTime`, applies a 12-second minimum, and carries that minimum through the outgoing schedule attribute. Pending and standalone send paths recompute the request schedule after upload against fresh server time.

### Navigation and local history

An ordinary chat reopen restores Telegram's saved message anchor and relative offset before considering server unread state, including in Ghost. Explicit navigation subjects retain priority, and new messages do not force-scroll an active chat.

Deleted-message preservation is an account-local presentation overlay. It never inserts or updates Telegram server history. Original text is retained; compact localized deletion metadata is added near the timestamp. Missing resources use a typed unavailable representation.

### Media lifecycle

Complete cloud resources are pinned while still available and published through validated temporary files and atomic metadata. Storage is derived from the account MediaBox location, deduplicated by resource identity, bounded by retention/capacity policy and cleaned on restart. A presentation lease keeps reconstructed bubble media alive. Secret chats remain excluded, and missing bytes are never fabricated or fetched around authorization.

### Settings and optional features

The Telegram Settings screen has exactly one SpaceGram entry. Formatting, message actions, automated inline-bot rules, Media Archive, Ghost, Read on Interact and Delayed Send are opt-in. Profile ID uses the real peer ID. Outgoing translation is isolated by account/chat, defaults off and updates the draft only after a non-empty successful result.

Save Protected Media is offered only for a locally available resource already authorized for the current account and does not bypass membership, paid access, `access_hash` or authentication. Message Shot is capped by message count, height and pixel count.

## Validation boundary

Portable consistency, preflight, feature-contract and build-info tests run on Windows and in CI. Swift/XCTest compilation, simulator teardown behavior, signing, installation and live network/UI behavior require macOS or a physical iPhone. The CI workflow keeps attempt-specific logs and crash reports and permits only one evidence-gated retry for the known post-success simulator SIGTRAP.
