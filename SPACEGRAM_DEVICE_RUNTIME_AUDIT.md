# SpaceGram Device Runtime Audit

Updated: 2026-09-20. This replaces the earlier source-complete claims with
separate implementation, compilation, automated-test and device evidence.

## Baseline and publication

- At the initial checkpoint, local `main`, saved `main@origin`, and the GitHub API agreed on
  `cde2035fa095c46356334265c7ba9dfbdadd6055`.
- Baseline iPhone workflow #14 succeeded:
  https://github.com/BADMAAAN/SpaceGram/actions/runs/35485267376
- Installed iPhone source SHA: **UNKNOWN**. No crash log or connected Apple
  device is available in this Windows session. The old report does not prove
  which binary the user tested, or that a QR runtime crash was fixed.
- `jj` 0.45.1 is installed through WinGet; its absolute executable path works.
  Existing working changes were snapshotted as `6024bf2b`; a baseline diff and
  operation ID are in the local temporary `spacegram-stabilization-20260920`
  checkpoint directory. The 159 pre-existing whitespace changes are excluded
  from this task's commits and remain in the working copy.
- `qwengram_run7_fix.patch` stays untracked through the local exclude file.
  SHA-256 before edits: `1A375A8973C3F8C9CDB6C15AD12B52D0D78681DEF9978F80C57232A6094AF0E0`.
- GitHub CLI login is confirmed as BADMAAAN with repo/workflow access. No Git
  CLI command, force push, release or PR is used.
- Intermediate source `05dd7e094d28874ac96606d8bddbdff53bb77dc0` is published
  through `jj git push`; workflow #15 is running:
  https://github.com/BADMAAAN/SpaceGram/actions/runs/35509471423
  It passed preflight and reached the full ARM64 app build. Queued/running is
  not BUILD-PASSED.
- Second-pass source `189be17b7e27e0e62fe8e750921dcb667a76ce0d` is published
  through jj and confirmed by the GitHub commits API. It contains status-bar,
  scheduling rejection, media retry and P1 safety/UX changes. Its build is pending
  the intermediate run result.

## P0: findings and implementation

| Area | Evidence and change | Acceptance status |
| --- | --- | --- |
| QR input/preview | `SpaceGramQRImageItemNode.init` ran in the ItemList worker, then accessed a view-backed `ASImageNode.layer`. AsyncDisplayKit enforces main-thread loading. Layer configuration now runs in `didLoad`; input title is empty with a separate accessibility label. Controller capture is weak. The QR payload retains the original whitespace/newlines (trimming is only used to reject blank input). Generator bounds UTF-8 to 2,000 bytes, integer scale 1...16, and adds an opaque four-module quiet zone. | IMPLEMENTED; actual user's crash cause remains a hypothesis pending a matching crash stack. DEVICE-VERIFICATION-REQUIRED. |
| NAGRAM status-bar capsule | User confirmed a permanent live overlay between time and system indicators. Inspected `Components/AppBadge.imageset/AppBadge@3x.png`: the raster contains the blue N + NAGRAM capsule. `Display/Source/WindowContent.swift` loads it, adds it to the window and centers it at `deviceMetrics.appBadgeOffset`; `TelegramRootController` controls visibility. Removed the decorative image assignment and keep the empty badge hidden. | SOURCE-IDENTIFIED / IMPLEMENTED; absence across screens still requires the updated IPA on iPhone. |
| Ghost presence | Existing aggregate master/settings and typing/group-call behavior retained. `updatePresence` now checks current policy immediately before forming the RPC, including timer/queued callback paths. | IMPLEMENTED; second-account online/typing/read observation required. No universal invisibility claim. |
| Read on Interact | Removed reads at send/reaction enqueue. Regular cloud delivery events in the open chat trigger the guarded read; scheduled ACKs do not. Non-thread reactions read only after successful server response. Policy is rechecked after asynchronous UI delivery. Forum/thread reaction acknowledgment remains unimplemented; paid reactions are unchanged. | IMPLEMENTED for stated paths; DEVICE-VERIFICATION-REQUIRED. |
| Auto delay | Existing persisted provenance marker, corrected network time and post-upload submit hooks retained. Margin is 30 seconds (10-second server threshold plus 20-second transit/rounding budget). Removed size-based additional delays. Explicit schedules retain their date. Auto delay no longer opens the scheduled-message screen. | IMPLEMENTED; network delay can exceed the margin. Unsupported cases now fail closed with localized feedback at both enqueue boundaries. Composer validation precedes draft cleanup; explicit schedules stay native. Attachment picker/recording draft retention still needs device verification. Exactly-once/offline/edit/cancel require server/device tests. |
| Ordinary Ghost navigation | Initial construction uses the same upper-bound/top anchor as native scroll-to-end, after checking explicit message/pinned targets. Existing controller scroll is untouched; no read-state mutation. | IMPLEMENTED; DEVICE-VERIFICATION-REQUIRED for holes, restored chats and archive-only pages. |
| Deleted text | Removed the appended emoji/italic deletion text. The common native timestamp formatter renders a small localized Deleted label from the local presentation attribute. Original caption/entities remain separate. | IMPLEMENTED; themes/Dynamic Type need device verification. |
| Deleted media | Confirmed baseline defect: overlay always emitted `media: []` even with saved assets. It now resolves actual archive files, leases them through sandbox hard links, reconstructs native photo/video/voice/round/file media and opens them standalone instead of querying nonexistent Postbox IDs. Missing full files use a document placeholder without changing caption text. Spoilers, edited timestamp and album grouping are retained in optional v2 fields. | IMPLEMENTED; native renderer/playback is not yet device-proven. Unsupported/contact/complex media and old incomplete metadata are not fully reconstructed. |
| Media lifetime | Account-scoped native full-fetch completion now requests an archive capture, including while another chat is open. Existing bounded file-descriptor pin, serial copy/hash and atomic publication are reused. Pending jobs attach only to their existing capture UUID. Deletion can reuse an earlier capture of the same media identity. | IMPLEMENTED; partial/ranged streaming, outgoing local-to-cloud reconciliation, delete-during-upload and force-quit matrices remain unverified. No background keepalive or extra download is added. |
| Launch/auth/icons/send | No identity, signing credential, icon artwork or auth-store migration. | DEVICE-VERIFICATION-REQUIRED; seven-icon nil/default mapping unchanged. |

### Known archive boundaries

Collection 1009, schema-v1/v2 reading, account Postbox separation, asset UUIDs,
512 MiB/128 MiB/1,000-asset/30-day defaults and the existing secret-chat
exclusion remain. New metadata fields are optional; runtime lease paths are not
serialized. Only complete locally received files are captured. The existing
archive switch explicitly discloses timed-media retention. Transport/TTL
acknowledgments are unchanged.

The existing archive list is bounded to 1,000 records, but still scans that
collection; this pass does not claim indexed pagination. Stale lease links from a terminated process are cleaned on the next archive use. Thread/reply reconstruction, detailed
missing/evicted/corrupt status presentation, ranged-download capture and a full
outgoing-resource reconciliation matrix remain open work. Current native
missing-media placeholders do not distinguish every failure reason.

## Build provenance and validation

- Make.py stamps full source SHA, UTC build time and local dirty state into
  `Telegram/SpaceGramBuildInfo.plist` before Bazel. About shows the short SHA.
- CI verifies checkout SHA against GITHUB_SHA and checks embedded IPA metadata;
  `build-info.json` is published beside the IPA. API credentials and device/account
  identifiers are not included in this diagnostic artifact.
- Existing manual `SpaceGram iPhone Test Build` signing/bundle settings are
  unchanged (fake-profile, resignable debug_arm64 intermediate artifact).
  This is not a verified full-profile device installation. Windows has no
  xcrun/Keychain or paired-device inspection; build-input is empty here.
  Bazel-rule directories are populated. No concurrency cancellation is configured.
- dSYM generation and symbol artifact upload are enabled. The workflow also
  runs SpaceGram simulator XCTest after the IPA is built, through Make.py.
- AUTOMATED-TEST-PASSED (Windows): `python tools/check_spacegram_consistency.py`,
  `python tools/check_spacegram_preflight.py`, and
  `python tools/test_spacegram_feature_contracts.py` (16 tests), plus `python tools/test_spacegram_build_info.py` (3 identity-verification tests). Pillow pixel
  checks, five catalogs, 775 BUILD files, 33 plists and 198 asset JSONs pass.
  These are portable/static contracts, not Swift compilation or functional iOS tests.
- Added XCTest: QR decode for text/URL/Cyrillic/emoji/multiline/limit, rejected
  byte/scale boundaries, the actual preview node constructed off-main then loaded
  on main repeatedly, updated scheduling margins, exact copied text, unavailable
  media placeholder, and a live media lease surviving archive clear.
  XCTest status remains NOT RUN until CI results are available.

## P1/P2

Existing independent opt-in actions, Message Shot renderer, Accounts anchor and
app icon choices were preserved. They are not newly declared runtime-verified.
Forward-as-new remains unimplemented; forward-without-name retains Telegram semantics.

- Ghost toolbar uses a product-owned vector orbital template: outline OFF,
  filled planet/satellite ON, native tint and 44-point hit target.
- Existing opt-in profile ID becomes a separate accent row next to native user
  data, with tap-to-copy and native feedback. It uses the model's unwrapped
  numeric user ID, not packed PeerId or access_hash. DC/date settings remain.
- Outgoing translation remains global/opt-in. Requests belong to the controller,
  support cancellation and a 45-second timeout, and validate peer/thread,
  visibility and the exact attributed draft before replacing it. Secret chats,
  detected links and entities other than basic emphasis are excluded. The result
  remains an editable draft; nothing auto-sends on failure. Account-switch and
  in-flight cancellation require runtime verification.
- Automatic inline rules require a second, per-bot recipient choice (empty by
  default). Only one HTTP(S) URL is submitted; ordinary draft text and secret
  chats are excluded. Native explicit @bot requests are unchanged. Metadata
  updates cannot add consent; resetting SpaceGram settings clears it. Remote payload/rule/input/match counts are bounded;
  ICU progress callbacks reject matching after a shared 20 ms budget. Compilation
  is bounded by a 512-character pattern limit, not a preemptive compiler timeout.
  RU/EN footers now describe the actual recipient and behavior.
- Failed/partial media archive captures no longer permanently block a later
  native download-completion retry.

These additions are source-implemented and await the next exact-SHA CI/device pass.
SpaceGram Cosmic and an approved wallpaper registry are not implemented. P2 is
held behind the unresolved P0/device checks; no unapproved artwork is added.

## Reference mapping (inspection only, no foreign module copied)

| Requirement | Inspected source revision/symbol | SpaceGram hook/change |
| --- | --- | --- |
| Runtime Ghost gate | Novagramorg/iOS main `268aa3be43a4f286d942162765d6e1f5740d3347`, `isFenixuzGhostModeActive` | Existing `SpaceGramGhostPolicy`; fresh presence-RPC gate |
| Ghost button/settings | Same Novagram SHA, `HOOKS.md` Ghost section, `FenixSettingsController.updateShowGhostMode`, `ChatListController.updateGhostModeButton`, `NavigationButtonComponent` icon branch | Existing separate visibility/master state preserved; own 24-point orbital template and native 44-point hit target. Foreign branding/artwork and runtime keys are not copied. |
| Read on send distinction | Same SHA, `fenixuzForceReadHistory` | Unconditional direct readHistory bypass deliberately not copied; success-only opt-in paths |
| Presence worker | AyuGram/AyuGramDesktop dev `db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a`, `GhostModeAccountSettings`, `AyuWorker::runOnce` | Existing account presence manager; no three-second cross-client online/offline race |
| Scheduling | Same Ayu SHA, `api_sending.cpp`/`applyGhostScheduling` and `ayu/utils/telegram_helpers.cpp` | Existing provenance attribute and post-upload server-clock adjustment; bounded 30-second margin |
| Deleted storage | Same Ayu SHA, `AyuMessages::map`, `addDeletedMessage`, `getDeletedMessages` | Existing Postbox archive retained; local media bridge added. This Ayu mapper sets mediaPath to a placeholder and skips empty-text records; it is not evidence of a complete media-retention implementation. |
| Message Shot | Same Ayu SHA, `AyuFeatures::MessageShot::Make` in `features/message_shot/message_shot.cpp` | Existing SpaceGram bounded renderer preserved; no screenshot/watermark transplant |

Also consulted the supplied Ghost/features docs, Telegram scheduled-messages
and inline-bot API documentation, and Apple's background notification page.
Public-source behavior is not proof of an installed reference binary.

## Device acceptance for the new SHA

1. Upgrade with the same signing identity/bundle ID without deleting app data;
   record About version/build/SHA/time. Verify login and icon selection remain.
2. QR: ASCII, URL, Cyrillic, emoji, multiline, empty/limit/oversize, repeated
   generation, Back, share and Photos permissions; decode the saved image.
3. With a separate observer and other sessions quiet, record offline baseline;
   test Ghost OFF/full ON, Read on Interact OFF/ON, relaunch and account switch.
4. Send text/photo/large video/voice/round through slow upload and reconnect;
   inspect queue date, edit/cancel, delivery with app closed and exactly one copy.
5. Open a chat with old unread messages: newest first without read; then explicit
   search/reply/pin/deep link, manual scrolling and return from gallery.
6. Receive/edit/delete photo/video/voice/round/file/album; test ready vs thumbnail,
   offline reopen, two accounts, archive cleanup and deletion during copying.
7. Check compact Deleted/edited metadata in both themes and large text, launch,
   normal sends/edits/replies/forwards/calls and all seven icon choices.
8. If QR crashes, export the matching SpaceGram .ips from iPhone Settings >
   Privacy & Security > Analytics & Improvements > Analytics Data, with build
   number, timestamp and reproduction steps. Match binary UUID to the dSYM;
   do not commit raw crash logs or personal screenshots.
