# Ghost Mode / Media Archive / TTL audit — 2026-09-18

This is the implemented second increment after FOUNDATION_AUDIT.md. It is a
source audit with static validation on Windows, not a verified iOS build or a
claim of universal Telegram invisibility. No commit, push, release, workflow,
signing change or device installation was performed.

## Effective settings and protocol behavior

Ghost preferences remain opt-in and require the Qwengram master switch. They
change mutation/enqueue/request behavior, not just UI. Switching them off restores
native behavior. No read synchronization is falsely confirmed as delivered.

| Path inspected | Current policy and boundary |
| --- | --- |
| Automatic text/history reads | Existing ChatHistoryListNode can-read/visible-index guards and InstallInteractiveReadMessagesAction transaction guard retain local unread state and prevent automatic read operations. |
| Incoming automatic reaction/poll reads | Added guard to StoreOrUpdateMessageActionImpl before pending actions. |
| Untimed voice, round video and other content consumption | MarkMessageContentAsConsumedInteractively now exits before consumed flags, secret service operations or consume-operation enqueue. Playback callers use this engine entry point. |
| Timed/view-once consumption | Deliberately retains native acknowledgement and timer mutation. Suppressing only transport would desynchronize consumption/expiration with the server and other clients. Opening these media can be visible to the sender. |
| Mentions, reactions, poll results | AccountViewTracker guards before dedup/queuing; engine reaction/poll seen entry point guards before local mutation. |
| Live-location viewing | Tracker guards enqueue and rechecks inside the transaction before messages/channels.readMessageContents. |
| Channel message view counters | getMessagesViews still fetches counters but uses increment=false under automatic-read suppression. |
| Read metrics | TelegramEngineMessages.reportPeerReadMetrics checks policy immediately before messages.reportReadMetrics. |
| Normal Stories | Existing Stories enqueue guard and ManagedSynchronizeViewStoriesOperations transport guard suppress readStories. The Story queue removes suppressed operations; later native maxId reads can acknowledge earlier IDs. |
| Pinned Stories | Existing incrementStoryViews guard remains active. Local Story progress is retained. |
| Typing/recording/upload/other chat input activity | ManagedLocalInputActivities combines the effective policy, cancels suppressed activities and guards cloud setTyping / encrypted setEncryptedTyping before requests. Group-call speaking is deliberately exempt. |
| Explicit online presence | ManagedAccountPresence transitions offline and stops online refresh while suppression is enabled; transport/push stay native. Sending/reactions can still reveal activity. |
| Reply threads/forums/saved threads | ReplyThreadHistory and ApplyMaxReadIndexInteractively contain readDiscussion/readSavedHistory. Automatic viewing is gated at the existing read producer, not by lying about transport success. Explicit index/read actions remain native. |
| Already accepted read operations | SynchronizePeerReadState, ManagedSynchronizeConsumeMessageContentsOperations and ManagedConsumePersonalMessagesActions still deliver queued ordinary/timed operations. Enabling Ghost is not retroactive. Dropping them after local consumption/read mutation would leave state inconsistent. |
| Explicit Mark as Read / Mark All | MarkAllChatsAsRead and ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations remain native, including readReactions/readPollVotes. These are intentional acknowledgements. |
| Other interactions | Sponsored-message impressions (AdMessages.viewSponsoredMessage), featured-sticker catalogue reads, sending, reactions, Story reactions, explicit live-location sharing, games/bot actions and call signaling remain native. No general activity firewall is claimed. |

Read-only getters (read participants, outbox read dates, replies, unread
mentions/reactions, peer Story state) are not acknowledgements. Network traffic
for fetching content remains possible. Another logged-in client can acknowledge
messages independently. New upstream callers must be checked when rebasing.

## Archive implementation and supported payloads

`Qwengram/MediaArchive` is an independent Foundation/CryptoKit/Darwin module.
`HistoryIntegration/QwengramMediaIntegration.swift` is included in TelegramCore
through the existing filegroup; no dependency back from MediaArchive to Core.

The new Media Archive toggle defaults off. Effective capture requires Qwengram,
Message History and Media Archive enabled. Explicit server-deletion capture also
requires the existing Save Server Deleted Messages setting. Turning capture off
does not erase saved data or block existing History access.

- Complete cloud-message photo representations, video, voice, round video,
  document/file, GIF/animation and file thumbnail resources are supported.
  Largest photo representations are considered first. File names are display
  metadata; physical paths use generated UUIDs and sanitized extensions.
- Only MediaBox.resourcePath (the complete-file path) is opened. No partial-file
  fallback, remote fetch, reconstruction or fictitious asset is created. Empty,
  missing, symlink and over-limit resources are skipped.
- Pinning opens a read-only file descriptor with O_NOFOLLOW and checks regular
  file type/size on the Postbox queue. It performs no payload read there and
  refuses UI-thread calls. At most 32 resources are pinned per message, and
  64 descriptors / 512 MiB pending per process across accounts.
- MediaBox's current removal paths unlink complete files. An open descriptor
  pins that inode across unlink. The archive then reads it on one utility queue
  in 1 MiB chunks into an independent file; it does not keep a cache hard link,
  change cache ownership, block cache deletion or modify MediaBox/Postbox internals.
- Copy requires exact byte count, EOF and unchanged source size/mtime. SHA-256
  is stored and checked again before opening. This detects archive corruption;
  it is not Telegram server-checksum validation or a codec validator. A corrupt
  source already accepted as complete can still be copied as received.
- Payload is fsynced and renamed before atomic metadata publication. Metadata
  is `UUID.json`, binary is `UUID.data.<extension>`; JSON documents cannot be
  confused with manifests. History asset IDs are attached only after success.
- Files use completeUntilFirstUserAuthentication protection; archive root is
  excluded from backup. This is native file protection, not a new encryption
  vault, Keychain key or separate app lock. No payload/path/filename is logged
  on failures.

## Storage and cleanup policy

Root is `qwengram-media-v1`, a sibling of the selected account Postbox MediaBox
folder, outside ordinary Telegram cache cleanup. The account's own MediaBox path
is used, never the shared account-manager cache. Root creation requires its parent
already exist so a queued capture cannot recreate a removed account directory.
The containing account directory owns the archive lifecycle.

Limits per account: **512 MiB binary payload, 1,000 assets, 128 MiB per asset,
30 days**. Metadata is separately bounded/read at at most 8 KiB per asset.
Oldest-first eviction runs before storing; expiry, missing/invalid manifests,
orphan payloads and interrupted `.partial` files are reclaimed on store/list/open.
Cross-process flock serializes maintenance and publication for each account.
There is no background deletion timer: age cleanup occurs on archive access,
so unused archives can remain on disk beyond day 30 until next access.

SHA mismatches refuse preview. Invalid/missing files show unavailable; no fallback
to a Telegram URL silently downloads replacement content. Future manifest
versions fail closed without deleting their files. Storage-full/copy/permission
failures leave Telegram deletion and synchronization running normally.

Quick Look receives another verified private temporary copy held by a preview
lease, so archive eviction cannot remove an open preview. Four active previews
and 512 MiB temporary payload are allowed per process; crash leftovers older
than 24 hours are cleaned on the next preview request. The aggregate preview cap
across different processes/accounts is best effort (archive caps are locked per
account). Native Quick Look determines codec support; voice Ogg and arbitrary
files may show generic file presentation rather than playable media.

History-record eviction/clear does not immediately collect its already-linked
assets; these still obey the same bounded archive retention/space limits.
Failed or stale async links explicitly remove newly copied assets. Crash between
metadata publication and History linking can leave an unreferenced asset until
retention/space eviction. There is no archive management/clear UI in this stage.

## TTL / view-once lifecycle and integration order

The checked version represents timing through AutoremoveTimeoutMessageAttribute
and AutoclearTimeoutMessageAttribute. viewOnceTimeout is 0x7fffffff; autoclear
schedules its sentinel at countdown begin rather than adding that sentinel to
the timestamp. Media playback reaches markMessageContentAsConsumedInteractively;
Telegram's normal consumed flags, service operations and timer updates stay intact.

| Integration point | Capture ordering |
| --- | --- |
| AccountStateManagementUtils explicit deletion updates / channel difference | qwengramBeforeServerDelete pins live message resources and records the existing server-delete event before ordinary deletion. It accepts timed messages too, but does not infer who deleted them or why. |
| MarkMessageContentAsConsumedInteractively | Incoming timed media is pinned before consumption starts its lifecycle. This early point helps with immediate view-once tombstoning when a complete file already exists. |
| ManagedAutoremoveMessageOperations | Pins before _internal_deleteMessages or replacement with TelegramMediaExpiredContent. Original removal/clear branches continue unchanged. |
| markMessageContentAsConsumedRemotely | Both cloud update call sites pass Postbox; resources are pinned before remote expiration replaces the media. Secret-chat callers retain nil and do not archive. |

Captures at timed consumption and subsequent expiration can duplicate data;
there is no content deduplication. Limits bound this duplication. This is a
best-effort lifecycle archive, not continuous mirroring of every downloaded file.
If the cache was already evicted, the client only streamed a partial file, the
process terminates before copying, storage is unavailable or limits are reached,
there may be no archive copy. An open descriptor survives unlink, not arbitrary
in-place mutation or process death.

Not covered: encrypted secret-chat payloads, inline stripped thumbnails,
transient decoded frames/audio buffers, partial streaming ranges, embedded
webpage/game/paid-media wrapper resources, Story binaries, media replaced by an
edit before these hooks, bulk history-clear/local-delete/validation-cleanup paths,
or files destroyed before the client receives a usable resource. No recovery is
claimed for content this device never received. Additional lifecycle paths must
be integrated individually; a blanket low-level MediaBox deletion hook would
lose message identity and risk caching resources outside the intended scope.

## History schema and UI

History schema **v2** adds optional event `mediaCaptureId` / `mediaAssetIds` and a
`mediaArchive` reason. V1 reads remain unchanged; absent fields decode nil. A
successful upsert lazily writes v2. Future versions remain rejected. Text,
revision numbering, message keys and existing logical record limits are preserved.
Downgrade to an old v1-only binary will not read newly written v2 records.

Each capture has a UUID token. The async copy callback reloads the same account
record and matches that exact event token before linking real successful asset
IDs. It cannot resurrect a removed record or attach to a recreated message's
history. Failed capture can leave a real text/event snapshot without assets;
there is never a placeholder binary asset pretending unavailable media was saved.

The browser marks records with linked media. Detail lists currently present assets,
opens them locally via Quick Look, and shows a localized unavailable state for
missing/evicted/failed captures. History now observes its Postbox ordered collection
so asynchronous links refresh without polling. A browser badge can outlive payload
eviction; detail/open checks availability. UI previews have no network fallback.

## Validation performed here

- Read Foundation audit, existing settings/implementation and the requested Git
  diff before changes. jj remains unavailable. Only authorized `git diff` variants
  were used this stage; no commit/push/release.
- Compared **18 changed/new Swift files** against the saved start-of-stage baseline
  with tree-sitter-swift 0.7.3 / tree-sitter 0.25.2: **no new parser diagnostics**,
  process exit 0. Existing empty-tuple grammar false positives were compared with
  baseline. Tree-sitter 0.26 initially crashed on teardown for two large upstream
  files, also on their untouched baselines; rerun with 0.25.2 completed cleanly.
  This is syntax screening, not Swift type checking.
- Parsed **15 BUILD files**; checked referenced local packages, Qwengram target
  names, and source-glob inclusion for the new archive, integration, preview and
  test files. TelegramCore and HistoryUI have direct MediaArchive dependencies;
  Tests/AllTests includes the new unit suite. No Bazel analysis was available.
- Checked **30 EN/RU Qwengram keys**, UTF-8, duplicate keys, parity and literal
  localization references. Resources use the existing QwengramStrings loader.
- `git diff --check`: passed. Removed CRLF/mixed-ending diff noise only from
  already-modified files; no broad reformat of upstream code.
- `python build-system/Make/Make.py --help`: passed. Xcode/Swift/Bazel are absent;
  no iOS build, simulator/device execution or packet-capture test was performed.
- Added **six XCTest scenarios**, wired into Tests/AllTests: pinned inode surviving
  unlink with a JSON payload; same-size corruption rejection; missing/partial/
  symlink/oversized resource refusal; retention removes metadata and payload;
  account isolation and future manifest preservation; v1 text-history decoding.
  They have not been executed on this Windows host.

## Required macOS follow-up

1. Full simulator app build and Tests/AllTests through Make.py with the documented
   simulator signing mode; no per-module build substituted for the full app.
2. Test all priority media formats on Telegram test accounts, complete versus
   streaming resources, view-once at initial playback/dismissal, server deletion,
   local TTL, remote consumption, account switch/removal, disk full and restart
   during copy. Verify archived copies remain readable after cache removal.
3. Exercise 128 MiB/per-account/count limits, concurrent processes, expiration,
   pending descriptor backpressure, corrupt metadata/payload and stale event tokens.
4. Observe outbound protocol calls for text/reply threads/forums, ordinary media,
   mentions/reactions/polls, location, Stories and timed exceptions. Repeat with
   toggles changing while operations are queued and a second client logged in.
5. Inspect EN/RU UI, large text, missing files, repeated preview/dismissal and codec
   limitations. UI tests must use --ui-test and isolated data.
