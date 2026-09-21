# Device recovery pass — 2026-09-21

Base: `e395b301aab4c8ce1fc3b255c584f19661b5dc76` (`main`; Git checkout detached, jj workspace).
This is a source/configuration recovery pass. iPhone crash freedom, playback and APNs delivery are not verified by Windows checks.

## Reference inspected before changes

Read-only [Novagramorg/iOS](https://github.com/Novagramorg/iOS/tree/268aa3be43a4f286d942162765d6e1f5740d3347), revision `268aa3be43a4f286d942162765d6e1f5740d3347`; selected source downloaded to a separate temporary directory. No history/remote/branding/API credentials imported.

| Actual reference path | Finding and adaptation |
| --- | --- |
| `submodules/Fenixuz/HOOKS.md`, `HOOK_INVENTORY.md` | Located Fenixuz hooks, then checked their source rather than treating the inventory as proof. |
| `TelegramCore/Sources/State/AccountStateManagementUtils.swift` | Global/channel delete hooks retain existing messages with a deleted attribute at the account transaction layer. Edit hooks capture the previous message before replacement, without a visible ChatController. SpaceGram retains its separate archive/overlay instead of changing server history semantics. |
| `TelegramCore/Sources/Message/DeletedMessageAttribute.swift`, `Postbox/Sources/DeletedMessagesView.swift` | Stored deleted identity and local presentation support. SpaceGram keeps original account/peer/message/thread identities in its archive. |
| `TelegramCore/Sources/SyncCore/SyncCore_EditedMessageHistoryAttribute.swift` | Previous text/entities/media and original/prior edit dates. SpaceGram uses genuine edit events to select earlier revisions; capture/cleanup snapshots are excluded. |
| `Fenixuz/EditedHistory/Sources/EditedMessageHistoryController.swift` | Dedicated scrolling history controller. Its cloud media references/refetch are not evidence of durable archived bytes. SpaceGram uses a native ItemList controller with full text, dates, current version and copy actions. |
| `TelegramCore/Sources/Fenixuz/FenixuzGhostMode.swift` | Checked separate presence/read controls; retained SpaceGram policy and scheduling implementation. |

Paths in this table after the first row are relative to Novagram's `submodules/`. No independently validated atomic durable resource archive was found in the examined reference paths; no claim that Novagram solves unavailable/suspended downloads.

## Changes and causes

- **Settings/startup:** synchronous defaults delivery could reenter subscribers while enhancement settings/iCloud migration initialized another singleton. Bootstrap enhancement settings before observing; queue SpaceGram notification emissions, serialize access, suppress callbacks after disposal. Persisted Read on Interact is preserved. This removes a concrete startup hazard; without the observed crash's `.ips`, it is not proven to be its sole cause.
- **Scroll:** removed Ghost's forced `.upperBound` open. Ordinary reopen uses saved Telegram anchor/offset before unread state. Explicit navigation still selects the existing explicit branches. Chat/thread/account persistence remains native.
- **Received/deleted data:** Postbox store/update hooks capture a bounded account-local inbox in collection 1010 (separate from history 1009). Deletes use an existing message or that snapshot; global-ID lookup includes received snapshots. Duplicate delete updates do not append another deleted revision.
- **Completed bytes:** account-lifetime resource-data observers associate received metadata with local completion, including downloads outside a visible chat and restored pending associations on launch. No extra fetch is started. Existing pin/copy/hash/size-validation/atomic-publication machinery owns the bytes; incomplete/zero-size data is not published. Native completion hooks remain as complementary coverage. Archive/peer/message clear removes pending snapshots too.
- **Media rendering:** bind each metadata item to its own resource IDs; preserve single-item legacy assets without resource IDs, photos and thumbnails, voice/round/video/file/GIF/sticker associations. Normalize round-video MIME to `video/mp4`; preserve the video stream and audio track rather than rewriting bytes.
- **Round/voice:** remove recording-to-bubble transitions that waited for ordinary history while enqueue produced scheduled messages. Enqueue acknowledgement closes the originating recording only. Protect repeated sends, late recorder/export/thumbnail callbacks, picker cancellation and replacement drafts. Failed voice sends retain preview bytes; trimmed sends copy their source. Failed round sends restore preview. Group deletion no longer duplicates stale/ungrouped IDs and forwards the caller's group-delete flag.
- **Self presence:** separate account preference accepts server offline timestamps and successful online-RPC request times using corrected network time. It never copies Telegram's synthetic self-online sentinel and never advances on offline heartbeats. Ghost self header shows the native last-seen string; no known timestamp means unknown status. Presence timer ownership, refresh and disposal are explicit. No new presence RPC.
- **Edit history:** `.edit` events select A/B from A→B→C, ordered by revision sequence. Current C is shown separately, timestamps come from original/server edit dates. Normal and archived capture/deletion versions do not masquerade as edits.
- **Push:** DEBUG no longer chooses APNs sandbox. Registration/login read the installed provisioning environment; missing/malformed capability fails with a diagnostic. Device CI no longer disables extensions; simulator flags, bounded download retry and existing post-test SIGTRAP handling remain. CI inspects the built IPA and requires Notification Service Extension.

The 12-second/post-upload scheduling policy, upload manager and timer constants were not changed. Optional icon redesign was deferred while device validation remains open.

## Actual IPA evidence

Read without modifying or re-signing:

- `C:\Users\somebody give a fuck\Desktop\Telegram.ipa`
- `C:\Users\somebody give a fuck\Downloads\SpaceGram-iPhone-test(5).zip` → `Telegram.ipa`

Both IPA payloads have SHA-256 `ff0672b6cd4218bffc3b4d98de6f8f5f435704a6b924b44e74ab1694e1276c98` and embedded source SHA matching the base above. These are the original fake-signed CI artifact, not proof of AltStore's final installed signature.

| Field | Signed Mach-O slot | Embedded profile |
| --- | --- | --- |
| APNs | `production` | `production` |
| Application identifier | `C67CF9S4VU.ph.telegra.Telegraph` | same |
| Team identifier | absent | `C67CF9S4VU` |
| Keychain groups | absent | `C67CF9S4VU.*`, `com.apple.token` |
| App Groups | `group.ph.telegra.Telegraph` | same |
| Main bundle | `ph.telegra.Telegraph`; display name `SpaceGram` | — |
| Extensions | none in IPA | — |

Original artifact therefore had a production/sandbox registration mismatch and no notification extension. All six repository extension profiles exist; source bundle/group derivation and notification-service completion paths were checked. Profile/entitlement contents are inspected, not cryptographically validated.

A final AltStore-resigned IPA/app bundle was not found in the examined download/AltServer/temp locations. Whether AltStore removed push/App Groups or changed bundle identifiers on this iPhone remains unproven. Run `python tools/inspect_spacegram_ipa.py <final-resigned.ipa> --output <report.json>` on an existing final signer output when available; compare all fields and extension bundles. A valid final push capability, supported APNs topic/server credentials and retained extension shared-container access are still required. This pass cannot create those signing capabilities.

## Validation and remaining device work

- Portable feature contracts: 28 passed; build-info tests: 3 passed; IPA inspector tests: 4 passed.
- Consistency/preflight: no errors (773 BUILD files, 79 product Swift files, 33 plists, 198 asset JSON files, 376 assets).
- Swift grammar differential against the base: no new advisory diagnostics. Manual declaration/call-label/optional/enum/dependency audit performed; this is not Swift type checking.
- Added/strengthened Swift tests for persisted Read on Interact, asynchronous reentrancy, APNs environment, received snapshots, edit filtering and per-resource media reconstruction. Existing archive corruption/unlink/restart/retention/account-isolation tests retained. XCTest and full iOS build require the single macOS workflow.
- `git diff --check` reports existing whitespace in the user's saved simulator log. Scoped check for `.github SpaceGram Tests submodules tools` passes. User log and `overnight-preflight.json` remain byte-identical to initial jj revision `4fa17152` and are excluded from this commit.
- User file SHA-256: log `d089cf6ade377c70ba26c195c8dc681364941aa04d95e19e37700318187fa569`; preflight `c80ff379d6a11b8a8da7f11a96592f68f013b15c70fd170343c4c62b1eed55f9`.
- No Xcode/device build or `devicectl` install was possible on this Windows host. Workflow uses `debug_sim_arm64` tests then fake-signed `debug_arm64` with extensions; it is a re-signable artifact, not a verified installation. No UI screenshots or successful APNs delivery are claimed. CI is dispatched once after push, without polling.

Device checks: cold launch with Read on Interact OFF/ON; repeated toggles and account switching; saved middle position plus explicit search/reply/latest/thread navigation; receive/download in another chat and background, delete, reopen and restart; round/voice send, retry, cancel, scheduled-picker cancel and stale delete; self last-seen after Ghost; A→B→C edits; locked/background push and account logout/token refresh. Content never received while iOS suspends the process cannot be reconstructed. Inbox/history/media retention bounds still apply; playback must be checked with real encoded media.

## Export the observed crash

On the affected iPhone, enable Ghost + Read on Interact, leave the chat, close/reopen SpaceGram, then repeat the action that previously crashed. Record the exact time, iOS version and build number. Separately reproduce deletion of a stale round only if it still exists. Do not reinstall to reset settings.

Open **Settings → Privacy & Security → Analytics & Improvements → Analytics Data** (Russian: **Настройки → Конфиденциальность и безопасность → Аналитика и улучшения → Данные аналитики**). Select the `Telegram-…` or `SpaceGram-…` report matching the time, then **Share → Save to Files** and transfer the `.ips`. If no app report exists, include a matching `JetsamEvent-…` report if present. Send the file, not a screenshot of a stack fragment. See [Apple's crash-report guide](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs).
