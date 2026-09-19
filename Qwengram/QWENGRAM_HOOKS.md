# Qwengram upstream hooks

- **File:** `submodules/Postbox/Sources/SeedConfiguration.swift`
  **Section:** `MessageUpdateSource`, `SeedConfiguration.beforeMessageUpdate`
  **Reason:** Optional synchronous, non-throwing pre-write callback with the current
  transaction, rendered OLD, proposed NEW and source (`addMessages` / `updateMessage`).
  **Module:** Postbox API; no Qwengram storage dependency.
  **Rebase note:** Keep the default `nil`. Callers must not retain the transaction
  or re-enter message/history writes from this callback.

- **File:** `submodules/Postbox/Sources/MessageHistoryTable.swift`
  **Section:** `addMessages`, `processIndexOperations`
  **Reason:** Read OLD by its physical history index before `justUpdate` for
  `InsertExistingMessage`. For timestamp replacement, recognize only adjacent
  `Remove(oldIndex)` + `InsertMessage(new)` with identical MessageId and different
  timestamps; call before OLD is physically removed.
  **Module:** Postbox internal callback (`IntermediateMessage`, `InternalStoreMessage`).
  **Rebase note:** Keep index generation, operation order, removal accumulation,
  read-state commits and deferred media updates unchanged. Do not pre-snapshot the
  input array, look OLD up by the final MessageId index, deduplicate or split batches.
  Plain inserts without OLD do not invoke the callback. Other operation callers
  retain the default `nil` callback.

- **File:** `submodules/Postbox/Sources/Postbox.swift`
  **Section:** `PostboxImpl.addMessages`, `PostboxImpl.updateMessage`
  **Reason:** Capture the live Transaction, render IntermediateMessage as Message,
  convert InternalStoreMessage to StoreMessage, then invoke SeedConfiguration.
  Explicit update calls the hook only after `.update(updatedMessage)` is returned
  and before `messageHistoryTable.updateMessage`; `.skip` has no hook.
  **Module:** Postbox.
  **Rebase note:** Preserve all StoreMessage fields during conversion and keep the
  callback synchronous. Do not install an additional table callback for explicit
  updateMessage, which would double-count that path.

- **File:** `submodules/TelegramCore/Sources/SyncCore/SyncCore_StandaloneAccountTransaction.swift`
  **Section:** `telegramPostboxSeedConfiguration`
  **Reason:** Installs `qwengramBeforeMessageUpdate` for account Postbox writes.
  **Module:** TelegramCore / `Qwengram/HistoryIntegration`.
  **Rebase note:** Integration archives existing cloud messages with unchanged
  identity; secret chats and local-to-cloud reconciliation are excluded.

- **File:** `submodules/TelegramCore/BUILD`
  **Section:** TelegramCore sources and dependencies
  **Reason:** Compiles `//Qwengram/HistoryIntegration:Sources` inside TelegramCore
  and links `//Qwengram/HistoryStorage:QwengramHistoryStorage`.
  Also links `//Qwengram/Settings:QwengramSettings` for capture gating.
  **Module:** TelegramCore.
  **Rebase note:** Integration is a source filegroup, not a Swift module importing
  TelegramCore. The dependency direction is TelegramCore -> HistoryStorage ->
  Postbox. Never add a Postbox -> HistoryStorage or HistoryStorage -> TelegramCore
  dependency. Upstream hooks use `// MARK: NAGRAM` as required by AGENTS.md;
  BUILD comments use `# // MARK: NAGRAM` for valid Starlark syntax.

## History edit content and failure contract

The content allowlist compares text, UTF-16 text entities (including URL, language,
mention, custom emoji ID and formatted-date parameters), image/file identity and
contact content. Entities are canonicalized by range, type and sorted parameter
key/value pairs before comparison, preserving duplicate entities. Supported media
are compared as a multiset: embedded/reference rendering order is ignored, but
each occurrence must match once. Custom emoji sticker-pack references are deliberately excluded.
Reactions, views, tags, flags, local state, timestamps/edit timestamps, author,
forward/reply/thread metadata, resources, file references, thumbnails, file
size/duration and download metadata do not trigger revisions. Expired-content
tombstones suppress the entire hook, including any simultaneous TTL text cleanup.
V1 conservatively ignores web previews, polls/results, locations and other media
types; edits confined to those unsupported media types are not archived.

OLD snapshots retain text/entities, original and server-edit timestamps, author,
forward/reply/thread metadata and supported descriptive media metadata. No media
bytes, access hashes, file references, local paths or resources are stored.
After a meaningful change, one load and one upsert append a numbered OLD revision
and its edit event with the same observation time. Source is explicit; addMessages
uses `syncDetectedEdit`, updateMessage uses `edit`. No cross-call deduplication:
reverting content and later editing it again must preserve both transitions.
Read/decode/validation/encoding/size failures are caught inside integration; a
content-free diagnostic is logged and the Telegram write continues. Upsert validates
and encodes before mutating the ordered list, so a failed archive write does not
leave an orphan event. Low-level process/database failures are not recoverable
Swift storage errors and are outside this contract.

## History edit validation cases

Here A/B/C are distinct supported content values of the same cloud MessageId.
Each saved OLD has one matching event. Batch operations remain sequential.

| Input | OLD revisions | Telegram final content |
| --- | --- | --- |
| A -> B | A | B |
| A -> [B, C] | A, B | C |
| A -> [B, B] | A | B |
| Entity permutation only (including duplicate entities) | none | reordered entities |
| Media permutation only (including embedded/reference order) | none | reordered media |
| Text, entity range/type/parameter or supported media content change | A | B |
| Entity or supported media multiplicity change | A | B |
| A(t1) -> [B(t2), C(t3)] | A(t1), B(t2) | C(t3) |
| New message without OLD | none | new message |
| Technical-only update | none | updated technical state |
| Storage failure | no partial revision/event write | NEW still written |

These cases are checked by source review and an operation-order model on Windows;
they are not a live Postbox/Swift runtime test. Full app build and runtime validation
still require macOS/Xcode. No Actions are used.

## Server delete capture

- **File:** `submodules/TelegramCore/Sources/Account/AccountIntermediateState.swift`
  **Section:** `DeleteMessages`, `deleteMessages`
  **Reason:** Carries an optional typed server source with the existing ordered
  deletion operation. The default is `nil`, including scheduled/ephemeral/quick-reply
  callers. Global-ID deletion operations originate only in `updateDeleteMessages`.
  **Rebase note:** Preserve the source through operation replay/optimization.
  Swift modification sites use `// MARK: NAGRAM`.

- **File:** `submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift`
  **Section:** accepted `updateDeleteChannelMessages`, channel difference
  `otherUpdates`, and deletion operation replay
  **Reason:** Marks only explicit server delete updates. During replay, calls
  `qwengramBeforeServerDelete` before the existing physical deletion. Global IDs
  are resolved by `Transaction.messageIdsForGlobalIds`, the same lookup used by
  Telegram's delete path (cloud users and basic groups); channel/supergroup IDs
  retain their peer ID and cloud namespace.
  **Rebase note:** Keep pts acceptance, operation order, resource cleanup, thread
  statistics and deleted-message notifications unchanged. Do not mark generic
  deletes or infer deletes from missing messages in channel differences.

Integration requires a live OLD cloud message in a private chat, basic group,
channel or supergroup. Each ID is captured once per call. It appends one OLD
revision and one `.delete` event with reason `serverDelete` and source
`updateDeleteMessages`, `updateDeleteChannelMessages` or `channelDifference`, then
performs one validated upsert. The event confirms server-reported deletion; the
initiator is unknown. It must never be displayed as "deleted by the interlocutor".
The existing snapshot fields and TelegramCore -> HistoryStorage -> Postbox
dependency direction are reused; no Postbox API or BUILD change is needed.

Local delete-for-me/delete-for-everyone, clear history, validation cleanup,
min-available history, and local expiration do not call this hook. Scheduled,
ephemeral, quick-reply and secret-chat namespaces are excluded. Delete updates
carry no cause, so all messages with autoremove/autoclear attributes (including
unstarted timers and view-once) are conservatively skipped, even for a manual
server deletion. Expired-media tombstones and history-cleared placeholders are
also skipped. A local interactive delete physically removes OLD in its transaction;
a subsequent server echo or repeated update has no live OLD and does not archive
an earlier HistoryStorage revision as a new delete snapshot.

Read/decode/validation/encoding/size errors are caught per ID, with a content-free
diagnostic. Other IDs and Telegram's normal delete continue; snapshot/event are
never written separately. Process/database failures remain outside Swift error
recovery, as with edit capture.

Delete validation uses source review and a transaction-order model on Windows:
private/basic-group global-ID resolution, channel/supergroup peer identity,
duplicate IDs/echoes, local deletion followed by echo, all excluded namespaces,
TTL/autoclear/expired/clear placeholders, non-server cleanup paths and injected
storage failures. This is not a Swift/Postbox runtime test; macOS/Xcode build and
runtime validation remain unavailable here. No Actions are used.

## History settings

The existing Qwengram Settings Message History entry opens History Settings.
All three switches use `QwengramSettings` / `@QwengramDefault` with persistent
`UserDefaults.standard` keys (all default to `true`):

- `qwengram.settings.messageHistoryEnabled`
- `qwengram.settings.saveEditedMessages`
- `qwengram.settings.saveServerDeletedMessages`

The screen observes the existing UserDefaults notification mechanism through
`QwengramSettingsSignal`. Each capture callback reads current settings before
snapshotting or accessing HistoryStorage: edit requires Qwengram Enabled AND
Message History AND save-edited; server delete requires Qwengram Enabled AND
Message History AND save-server-deleted. Turning master off leaves
the individual preferences intact. Settings changes never remove stored history.
The general Qwengram Enabled preference also gates capture, without hiding
previously stored records.
No new upstream callbacks or message history list UI are introduced.

Validation on Windows: source review and all eight boolean gating combinations.
Persistence follows the existing UserDefaults wrapper; an actual app restart,
UI interaction and full iOS build still require macOS/Xcode. No Actions are used.

## History browser integration

- `Qwengram/SettingsUI` links `Qwengram/HistoryUI` and opens its History browser
  from **History Settings > View History**, including while capture is disabled.
- `Qwengram/HistoryUI` reads only `context.account.postbox` in a transaction on
  opening each screen. Reopen the browser to refresh its snapshot; tapping a row
  loads the current record by its full archive key. No network requests are made.
- `QwengramHistoryStore.listRecords` is a read-only, per-entry fault-isolating
  alternative to strict `readArchive`: it returns valid records in stored order
  plus an unreadable count. It uses the existing version/size/key/revision
  validation. Detail reuses throwing `load`; neither API repairs or deletes data.
- The browser sorts by latest observation descending, retaining storage order
  for ties. Rows show locally cached peer titles, a bounded text preview, event
  type and local date/time. Missing peers use **Unknown or deleted peer**; deleted
  users use Telegram's existing title helper. Invalid packed peer IDs are never
  passed to Postbox's asserting initializer.
- Detail shows full saved text and events oldest first. Events whose revisions
  were evicted show an unavailable-text message; unpaired revisions remain
  visible as **Saved revision**. Server deletion is always **Deleted on server**,
  without attributing an initiator. Empty, loading, missing and unreadable states
  are explicit; one corrupt row does not prevent displaying other rows.

Dependency direction: SettingsUI -> HistoryUI -> HistoryStorage -> Postbox.
HistoryUI also uses existing AccountContext, TelegramCore and list UI modules;
HistoryStorage has no UI or TelegramCore dependency. No upstream file, capture
hook, stored JSON format, ordinary chat bubble or archive write API is changed.

Validation here uses source review and fixture models for edit-only, delete-only,
multiple revisions, newest-first/tie ordering, missing peers, empty archives and
isolated corrupt entries. Full Swift/iOS build and visual runtime verification
require macOS/Xcode and are unavailable on Windows. No Actions are used.

## Per-message history action

- **File:** `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`
  **Section:** `contextMenuForChatPresentationInterfaceState` data loading and actions
  **Reason:** Joins the existing menu data signal with
  `qwengramMessageHistoryAvailable`. Only a single non-service, non-scheduled
  message is eligible. HistoryUI additionally requires the cloud message namespace
  and a cloud user/group/channel peer, excluding secret, scheduled, quick-reply,
  local, ephemeral and unsupported namespaces before any archive read.
  A full validated `load` in the current account's transaction must return a record;
  missing or corrupt records return `false`, so no action is inserted. Capture
  preferences do not hide existing history. Both edit and server-delete records
  qualify if the ordinary message remains accessible in the menu's UI context.
  **Navigation:** **Message History** dismisses the menu and pushes the public
  `qwengramHistoryDetailController(context:messageId:)` entry point. It converts
  the complete message ID to the existing archive key and delegates to the same
  detail screen used by the browser. Detail reloads the record and handles a
  missing/unreadable record if it changed after the visibility check.
  **Rebase note:** Preserve the asynchronous join before `deliverOnMainQueue`,
  the conditional action, and nearby `// MARK: NAGRAM` markers.

- **File:** `submodules/TelegramUI/BUILD`
  **Section:** TelegramUI dependencies
  **Reason:** Adds a direct dependency on `QwengramHistoryUI`. Its visibility now
  permits SettingsUI and TelegramUI only. No TelegramUI -> HistoryStorage edge
  is needed; Postbox reads and archive key construction remain inside HistoryUI.

No capture logic, archive format or second detail UI is introduced. Validation
uses source review, eligibility/error fixture models and target-level dependency
inspection on Windows; a full iOS build and interactive navigation verification
remain unavailable without macOS/Xcode. No Actions are used.

## Other upstream hooks

- **File:** `submodules/AppLock/Sources/AppLock.swift`
  **Section:** lock-state evaluation
  **Reason:** Extends Telegram's existing App Lock timeout with the `-1` persisted
  value for immediate locking after background and after a process relaunch. This
  keeps the native PIN/biometric overlay, fallback and lifecycle handling.
  **Rebase note:** Preserve `isInitialEvaluation` and `immediateLockPending`; a
  live settings change must not lock the foreground app, while a background or
  first evaluation after launch must stay locked until successful unlock.

- **File:** `submodules/SettingsUI/Sources/Privacy and Security/PasscodeOptionsController.swift`
  **Section:** public controller entry point and autolock values
  **Reason:** Lets Qwengram Privacy & Security open Telegram's single passcode
  settings screen and adds the immediate timeout choice. No second passcode store
  or overlay is introduced.
  **Rebase note:** Keep `nil` as Disabled and `-1` as Immediately. Positive values
  retain Telegram's native timeout semantics.

- **File:** `submodules/TelegramUI/Components/TelegramAccountAuxiliaryMethods/Sources/TelegramAccountAuxiliaryMethods.swift`
  **Section:** `PhotoLibraryMediaResource` fetch
  **Reason:** Reads the selected account's Qwengram metadata policy off the main
  thread. When enabled, the normal photo-library result is re-encoded without
  EXIF/GPS before upload.
  **Rebase note:** Apply only to complete, ordinary still-image results. Original
  files/documents, animated images and videos must keep their bytes.

- **File:** `Telegram/NotificationService/Sources/NotificationService.swift`
  **Section:** account discovery and `NotificationContent.generate`
  **Reason:** Loads the account-scoped redaction policy only after the encrypted
  notification key resolves its account, then hides configured identity, preview,
  rich-body and attachment presentation without changing delivery metadata.
  **Rebase note:** Preserve sound, badge, category, thread and `userInfo`. Error and
  control notifications before account resolution retain native content.

- **File:** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift`
  **Section:** `SettingsSection` and `settingsItems`
  **Reason:** Adds the Qwengram settings entry.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the separate section and disclosure action.

- **File:** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`
  **Section:** `PeerInfoSettingsSection`
  **Reason:** Adds the Qwengram settings destination.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the destination case.

- **File:** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift`
  **Section:** `openSettings(section:)`
  **Reason:** Routes the destination to `qwengramSettingsController(context:)`.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the import and switch case.

- **File:** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/BUILD`
  **Section:** `PeerInfoScreen` dependencies
  **Reason:** Links the Qwengram settings UI module.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the direct Bazel dependency.

- **File:** `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`
  **Section:** `contextMenuForChatPresentationInterfaceState(...)`
  **Reason:** Adds the Qwengram AI message context-menu entry for a single, non-empty, non-secret text message.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the local-only handoff to `qwengramMessageAIController(context:text:)`; do not invoke an AI provider from the menu action.

- **File:** `submodules/TelegramUI/BUILD`
  **Section:** `TelegramUI` dependencies
  **Reason:** Makes `QwengramSettingsUI` available to the TelegramUI context-menu hook.
  **Module:** `QwengramSettingsUI`
  **Rebase note:** Preserve the direct Bazel dependency next to the other fork UI dependencies.

- **File:** `Qwengram/Enhancements/Demo/Sources/NagramDemo.swift`
  **Section:** Demo message seeding
  **Reason:** Splits a large `StoreMessage` map expression into smaller typed expressions so Xcode 26.2 can type-check it during the ARM64 build.
  **Module:** `NagramDemo`
  **Rebase note:** Compatibility-only refactor; preserve behavior and re-test whether the workaround is still required after upstream changes.


## Ghost policies and master switch (2026-09-18)

The effective policy lives in `Qwengram/Settings/QwengramGhostPolicy.swift`.
All four Ghost preferences default to false and require Qwengram Enabled.
Settings are device-wide like the existing Qwengram preferences; each account's
history remains in its own Postbox. Signals register the notification observer
before reading the initial value and serialize notification emissions.

- `TelegramCore/Sources/State/ManagedLocalInputActivities.swift`: combines activity
  updates with the effective policy, disposes pending suppressed activities, and
  checks again inside the transaction before cloud/encrypted typing requests.
  Group-call speaking events are exempt because they maintain live call state.
- `TelegramCore/Sources/State/ManagedAccountPresence.swift`: combines Telegram's
  desired online state with the policy on the manager queue. Switching suppression
  on transitions an already-online manager to offline and stops its timer;
  switching it off resumes Telegram's current desired state. Connection management
  and push registration are untouched. This is not server-side invisibility.
- `TelegramCore/Sources/TelegramEngine/Messages/Stories.swift`: suppresses pinned
  `incrementStoryViews` requests and avoids enqueuing normal view synchronization,
  while retaining Telegram's existing local story progress.
- `TelegramCore/Sources/State/ManagedSynchronizeViewStoriesOperations.swift`:
  pending operations reached while suppressed complete without a request and are
  removed by the existing operation runner. They are not retried on disable.
  A later normal `readStories(maxId:)` can still cover earlier story IDs.
- `TelegramCore/BUILD`: direct dependency on QwengramSettingsSignal (Foundation,
  QwengramSettings, SwiftSignalKit only; no UI/Core cycle).
- `TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`: gates Qwengram AI
  availability and rechecks at tap time. Its BUILD links QwengramSettings.
  Saved Message History actions deliberately remain available.

All modified upstream sites have nearby `// MARK: NAGRAM` markers. Rebase by
preserving these boundaries, not by moving product logic into Telegram code.

QwenProvider independently rejects new requests while disabled and owns a
settings observer for each active request. Both streaming and non-streaming tasks
are cancelled on disable; a disabled-request outcome is sticky even if the user
reenables Qwengram before the cancellation callback. Already delivered data cannot
be recalled. No request body, API key or error containing content is logged.


### Automatic chat reading

`TelegramUI/Sources/ChatHistoryListNode.swift` combines its existing can-read signal
with the Qwengram policy for both visible-index handling and the live read-action
subscription. It rechecks current settings before applying a visible read index.
This also pauses its automatic mention/reaction handling and read metrics. The
TelegramCore store-message action in `InstallInteractiveReadMessagesAction.swift`
checks the same policy inside the transaction, so newly arriving messages are
not read by an action awaiting UI disposal. TelegramUI links SettingsSignal directly.

Local unread state is deliberately retained; the hook does not lie to Postbox's
synchronization queue about having sent a receipt. Native explicit mark-as-read
(including Mark All) remains an intentional way to acknowledge messages. Turning
suppression off, or disabling Qwengram, restores normal reading of visible messages.

This covers chat-history viewing, not every possible Telegram receipt. Media
consumption/TTL, explicit user actions and already queued/transmitted operations
remain outside this hook. Test peer chats, reply threads, forums, secret chats,
background/foreground transitions and multiple accounts before release.


## Media Archive and extended receipt policy (2026-09-18)

See [MEDIA_ARCHIVE_AUDIT.md](MEDIA_ARCHIVE_AUDIT.md) for the current behavior,
exceptions and validation. This extends the earlier automatic-read section.

- `TelegramCore/Sources/State/AccountStateManagementUtils.swift`: passes Postbox
  into both explicit server-delete hooks and cloud remote content-consumption
  updates; allows pinning complete resources before deletion/tombstoning.
- `TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift`: captures
  before automatic removal or replacement with expired media.
- `TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift`:
  captures timed media before initial consumption and remote expiration;
  suppresses untimed automatic consumption and reaction/poll seen-state mutation.
  Timed acknowledgement/timer behavior is preserved. Secret-chat remote callers
  retain the default nil Postbox argument and are not archived.
- `TelegramCore/Sources/TelegramEngine/Messages/InstallInteractiveReadMessagesAction.swift`:
  stops automatic reaction/poll pending actions before local mutation.
- `TelegramCore/Sources/State/AccountViewTracker.swift`: suppresses automatic
  mention/reaction/poll/live-location reads before queuing, rechecks live-location
  requests, and fetches channel counters with increment=false under Ghost.
- `TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift`:
  suppresses peer-read metrics at request creation.
- `TelegramCore/BUILD`: adds QwengramMediaArchive. HistoryIntegration's existing
  Swift filegroup includes QwengramMediaIntegration.swift; do not turn it into a
  separate module importing TelegramCore (that would create a dependency cycle).
- `Qwengram/HistoryUI/BUILD`: adds MediaArchive and QwengramStrings. The existing
  Swift glob includes the Quick Look preview controller. Live Postbox observation
  refreshes successfully linked assets; copies and verification run off UI.
- `Tests/AllTests/BUILD`: includes QwengramMediaArchiveTests alongside TgCallsTests.

Upstream modification sites are marked `// MARK: NAGRAM`. Preserve capture order
before deletion; moving only the path lookup into an asynchronous callback loses
the original file. Never bypass MediaBox deletion or fake acknowledgement success.

## History browser and Qwen conversations (2026-09-19)

The History browser remains in `Qwengram/HistoryUI`; it uses the existing
Postbox collection and does not add upstream hooks. Search, event/peer filters,
time ordering and a 200-row display window are computed from the selected
account's records off the main thread. Media availability is checked from
manifests for the visible rows; binary hashing is confined to the selected
message detail on the Media Archive utility queue. Quick Look still opens a
verified temporary copy.

Deletion of an event, revision, message, chat or full history runs in the same
account Postbox. Assets without a surviving readable history reference are
removed after the transaction;
clearing Media Archive is a separate confirmed action. History text remains
readable if Media Archive is cleared. No Telegram message tables are modified.

`Qwengram/AI/QwengramConversationStore.swift` saves each Qwen conversation in
the selected account directory with iOS file protection and backup exclusion.
It stores messages and model names, never API keys. The assistant sends a
bounded suffix of complete messages as context and shows older UI messages on
demand. The native message context menu displays optional History, Edited and
Deleted markers in one existing `// MARK: NAGRAM`-scoped TelegramUI hook.
See [HISTORY_AI_AUDIT.md](HISTORY_AI_AUDIT.md) for policy, migration and tests.
