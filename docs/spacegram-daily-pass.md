# SpaceGram: daily-use pass, 2026-09-20

Base: current `main` / `main@origin`, `689b9a6f` (fetched twice before publication).
The cancelled Actions run was not restarted, inspected for progress or modified.
QR implementation and tests are unchanged and deferred. No secondary utility work.

## Changes and evidence

| Priority | Source change / inspected path | Evidence still required |
| --- | --- | --- |
| 1. Branding | Visually inspected `Components/AppBadge.imageset/AppBadge@3x.png`: it is the exact blue N + NAGRAM capsule. `AppDelegate` creates `nativeWindowHostView` → `Window1`; its `badgeView` is attached above controller views. Main already stopped assigning the raster. Visibility updates now unconditionally clear/hide it, removing the delayed-show branch. Added an actual UIKit window-host lifecycle test, not a grep assertion. | Installed source SHA and an iPhone view hierarchy/screenshot. This Windows session did not observe the user's running binary. |
| 2. Ghost | One persisted `ghostModeEnabled` master now enables all four protections despite migrated partial settings. Removed contradictory per-path switches from the Ghost section. Inspected `updateStatus`, cloud/encrypted `setTyping`, story view/read RPCs, read metrics, message views, content/mention/reaction receipts. Added live suspension of pending content/mention/reaction receipts, bounded authorization for queued history reads, and fresh checks around asynchronous topic reads. | Two-account network/visibility checks, including offline queue then Ghost activation and session restore. Already transmitted RPCs cannot be recalled. Calls retain native signaling. |
| 3. Read on Interact | The read happens inside TelegramCore after confirmed immediate cloud send/reply/album delivery or ordinary reaction success. It targets the actual conversation/topic and message index, independently of an open UI controller. Removed the visible-chat read callback. Read permission is account scoped and forgotten on restart. OFF never grants it. Scheduled/upload ACKs never grant it. | Successful, failed and cancelled interactions; two open topics; reconnect. Automatic delayed sends deliberately never initiate a read, even when later delivered. Paid reactions are outside this contract. |
| 4. Delayed Send | Target changed from 30 to 12 seconds; corrected `network.globalTime`, rounded upward. Existing single, album and standalone submission hooks recompute after upload/preparation. Explicit native dates are untouched. Nonfinite/out-of-range composer clock fails with existing scheduling feedback. | Measure text and slow-upload media with a second account; retry/offline, cancel/edit and duplicate prevention. A request that spends over the 2-second margin in transit can fall below Telegram's immediate-send threshold; no exact wall-clock guarantee is claimed. |
| 5. Chat entry | Existing new-controller latest anchor retained. Reused controllers now also scroll to latest on ordinary Ghost entry, after thread selection. Message/search/pinned subjects and active search/report routes take precedence. The automatic read path rechecks Ghost separately. | Long unread chats, restored/reused controllers, forum topics, search/reply/mention/pinned/deep-link/date navigation; verify server unread counts on the second client. |
| 6. Deleted messages | Existing local presentation-only snapshots and compact native timestamp metadata retained. Added original cloud sort index as presentation metadata, preserving same-second ordering without changing actionable local IDs. | Exact position after deletion/restart, timestamp size/tint, copy/reply/reaction behavior. No synthetic server/Postbox message rows were introduced. |
| 7. Deleted media | Full and ranged native fetch completion now pins completed inodes synchronously before downstream completion/queued deletion. Main-queue cache hits no longer silently skip pinning. Copy/hash → temporary file → atomic payload/manifest publication remains on the archive queue. Optional account-local resource IDs support lookup independently of a delete-event link. Late linking matches the existing deleted snapshot, never recreates deleted archive rows. Sticker/GIF pack/recent references are captured before deletion too. Deduplication avoids repeated copies consuming capacity. Resolving verifies SHA-256. Sticker metadata is restored, completed display-size photos are usable, and album members merge with surviving members. | Playback/rendering of photo, video, voice, round video, GIF/animation, document, static/animated/video sticker, and mixed deleted/live albums. Fully received files must remain usable after Telegram cache cleanup and restart within policy limits. |
| 8. Quick Ghost | SpaceGram orbital glyph now includes a visible ON/OFF capsule; layout reserves its full width and at least the native hit target. Settings and button read/write the same master. | Narrow screens, light/dark themes, VoiceOver, settings/button synchronization and persistence after relaunch. |
| 9. Crash pass | Guarded the navigation stack's `count - 2` access when an attachment is its sole restored controller. Clock conversions are bounded. Other daily paths were inspected, not declared device-proven. | Launch/session restore, chats, send/media/voice/round, reply/reactions, profiles, settings and back. Obtain a matching-SHA crash log for any failure. |

The runtime-source investigation also inspected the application window creation,
root-controller badge control, the window overlay ordering/layout, extension plists
and build targets, and `MediaManager` Now Playing metadata. The latter derives
title/artwork from the playing message rather than the badge raster. No ActivityKit
implementation/Live Activity declaration was found in these application sources.
These are source findings, not an observation of all live windows on the iPhone.
If the capsule remains on the new SHA, inspect all `UIWindowScene.windows` in Xcode
View Debugger, including window levels and image views, after foreground/background,
lock/unlock and media playback; record About SHA and the screenshot together.

## Archive boundaries retained

- Opt-in archive switch; account-specific root; no secret-chat archival or new download.
- Existing 128 MiB per-file, 512 MiB total, 1,000-asset and 30-day defaults/policy controls.
- Resource-indexed completed files are valid references before deletion; orphan cleanup
  no longer removes them after five minutes. Retention, capacity and explicit media
  archive clear still apply. Regression tests cover this distinction and expiry.
- Partial/unreceived, expired, evicted, oversized or corrupt resources cannot be shown
  as a full attachment. The existing honest unavailable placeholder is used.
- Historical records without the new optional resource IDs still resolve by asset UUID.
- Secret-chat lifecycle acknowledgements remain native. Cloud media playback receipts
  are suppressed while Ghost is active, including timed media; archival does not
  insert or restore Telegram server records.

## Validation and publication constraints

Executed on Windows: consistency checker; 16 portable feature contracts; 3 build-info
tests; plist/asset/BUILD/YAML preflight; comparative tree-sitter scan of changed Swift
files against the parent. Existing grammar limitations are advisory, not compiler
results. Added XCTest covers the actual window host, persistent Ghost policy,
12-second/fractional server clock, archive unlink/reconstruction for seven media kinds,
resource deduplication and retention before/after deletion. XCTest requires the CI Mac.

No local Xcode/xcrun/Apple Keychain/paired-device inspection is available. Local signing
configuration, development profiles and local.bazelrc are absent; Bazel rule directories
are populated. This does not select free signing. The requested existing workflow is
unchanged: simulator XCTest first, then its fake-profile, resignable `debug_arm64` IPA.
No claim of a signed install or successful device build is made before that evidence.

One manual `SpaceGram iPhone Test Build` is to be dispatched after commit/push. No CI
polling/watch/retry. QR tests remain in the suite: a QR failure can still stop the IPA
step and remains a known deferred issue, not a reason to alter QR in this pass.
The pre-existing `SpaceGram/audits/overnight-preflight.json` change is preserved byte
for byte and excluded from this commit. New preflight output is in the task's temp folder.

## Behavioral references

Inspected pinned source/reference snapshots; no foreign branding/artwork copied:

- [Novagram runtime Ghost gate](https://github.com/Novagramorg/iOS/blob/268aa3be43a4f286d942162765d6e1f5740d3347/submodules/TelegramCore/Sources/Fenixuz/FenixuzGhostMode.swift)
  and [lifecycle/UX hooks](https://github.com/Novagramorg/iOS/blob/268aa3be43a4f286d942162765d6e1f5740d3347/submodules/Fenixuz/HOOKS.md).
- [AyuGram scheduling helpers](https://github.com/AyuGram/AyuGramDesktop/blob/db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a/Telegram/SourceFiles/ayu/utils/telegram_helpers.cpp)
  and sending/worker snapshots: server scheduling and interaction/privacy behavior.
  SpaceGram uses post-upload corrected time instead of a file-size upload estimate.
