# SpaceGram Device Runtime Audit

Updated: 2026-09-20

This document distinguishes source-complete work from behavior that still needs
an iPhone build. It must not be read as a device-test result.

## Completed in this pass

### Product identity

- The main app and all six extension plist fragments now expose `SpaceGram` as
  `CFBundleDisplayName` / `CFBundleName`. The operating-system capsule obtains
  its label from the active app or extension bundle metadata; no capsule-color
  workaround is used.
- The product keeps the prepared `SpaceGramAppIcon` default catalog and the
  Moon, Earth, Mars, Sun, Saturn and Neptune alternate identifiers. The removed
  `SpaceGram-Primary` catalog was not restored.
- User-facing Qwen settings, assistant, summarizer and message actions were
  removed. Their old storage keys remain dormant to avoid a destructive
  migration.
- Visible localization values are checked for Nagram, NGram, AyuGram, AuraGram,
  Qwengram and Qwen. Internal compatibility identifiers, attribution and
  migration keys are intentionally retained.
- The hard-coded Chinese gallery action was replaced by Telegram's localized
  `Conversation.ContextMenuStickerPackInfo` string (`Info` / `Информация`).
- The separate edit/deleted-history viewer module and its entry points were
  removed. History storage schemas remain compatible and are not wiped.

### Settings and tools

- Telegram Settings has one SpaceGram product entry with the SpaceGram S art.
- The account switcher is still Telegram's native switcher. Its source anchor
  is now the navigation bar instead of the full settings controller view, which
  previously placed the bottom-anchored card near the lower safe area.
- QR generation moved to a bounded `SpaceGramQRGenerator`: non-empty UTF-8 is
  required, invalid extents/scales fail without trapping, rendering uses a
  reusable `CIContext`, and the result can be shared/saved through the system
  activity sheet. Empty, UTF-8 and long-ish input have service tests.
- Translator no longer depends on Qwen. It uses the retained translation
  service, localized RU/EN labels, vertical source/target lists and a checkmark
  selection model. Failures never replace the input with empty text.
- App-icon UI selection changes only after a successful
  `setAlternateIconName` callback. Default maps to `nil`; error leaves the old
  selection in place and displays a localized alert. Debug builds log requested,
  previous and resulting identifiers and the callback error.
- About SpaceGram now covers Ghost Mode, Read on Interact, Delayed Send,
  deleted/history retention, Media Archive, translator/QR tools, Message Shot,
  protected saves, opt-in message actions, icons and iOS background limits. It
  includes the app version/build and contains no Qwen/product-tier branding.

The original QR exception cannot be reproduced on this Windows host. The
confirmed unsafe path was the controller-local Core Image/render-update path,
which had no validated boundary and mixed generation with list updates. It has
been replaced rather than patched around. The exact iOS exception type still
must be confirmed from the next device crash log if any crash remains.

### Ghost Mode

- `spacegram.settings.ghostModeEnabled` is the persisted master state. Settings
  and the chat-list quick button read and mutate this same value.
- Migration version 2 enables the new master only when an existing suppression
  preference was already enabled. First-time master opt-in enables the complete
  preset; later master toggles preserve customized subsettings.
- Read, story, presence and activity policies require both the master and their
  own subsetting. Group-call speaking remains exempt from activity suppression.
- `Read on Interact` does not run on chat open/view/typing. It applies the latest
  visible incoming read index only at an actual send enqueue or after all
  reaction guards pass.
- Presence suppression keeps MTProto connected, sends an explicit offline
  status on transition, cancels the online refresh timer and optionally repeats
  offline publication every 25 seconds.
- A targeted send-pipeline audit found no second `account.updateStatus` caller:
  foreground presence flows through `ManagedAccountPresence`, while typing,
  recording and upload activity flows through `ManagedLocalInputActivities`.
  With the Ghost presence/activity subsettings enabled, the former cannot
  publish online and the latter drops ordinary chat activity at both the live
  signal and RPC boundaries. Group-call speaking remains intentionally exempt.

### Delayed Send

- Delayed Send is active when the Ghost master and Delayed Send are on; it no
  longer requires every Ghost subsetting to be enabled.
- Messages use Telegram's native scheduled-message attribute, preserving the
  native pending/edit/cancel/reconnect UI instead of an in-memory timer.
- Device wall time was replaced by Telegram's corrected network time.
- Text and every media estimate have a minimum schedule offset of 12 seconds.
  Media uses a conservative size estimate and a bounded 4.5 seconds/MiB offset.
- Explicit user schedules, secret chats, bots, paid messages, suggested posts,
  story replies and autoremove messages are not rewritten.
- SpaceGram-created schedule attributes now carry a persisted minimum-delay
  marker. Immediately after upload and before every pending/standalone send RPC,
  the planned date is compared with fresh Telegram server time and moved to at
  least 12 seconds ahead if it became too close or passed.
- Ordinary Telegram scheduled messages have no marker and remain unchanged.
  Native random ids, pending-message state and retry paths are preserved, so
  the recalculation does not create a second outgoing message.

Post-upload timing and absence of online exposure are source-complete but still
require the slow-upload and second-account iPhone matrix before runtime
acceptance.

### Protected media and outgoing translation

- **SOURCE COMPLETE / DEVICE VERIFICATION REQUIRED:** the opt-in protected-media
  action now covers already-local photos and ordinary videos through Telegram's
  camera-roll pipeline, and documents, animations, voice messages and round
  videos through the lifetime-managed Files exporter. It appears only for a
  protected, non-secret message whose primary resource status is local. Paid or
  otherwise unavailable resources are not fetched around Telegram access
  control; membership, access hashes and paywalls are not bypassed.
- Forward without name remains a Telegram forward-options flow, is now a
  separate SpaceGram action defaulting off, and does not claim to recreate the
  media as a new upload.
- Translate-before-send remains opt-in and uses the existing non-Qwen
  translation service. The translated draft is shown before the user sends it;
  empty/failing translations leave the draft intact. The current preference is
  global rather than per-chat, so per-chat policy remains future work.

### Message Shot and custom message menu

- **SOURCE COMPLETE / DEVICE VERIFICATION REQUIRED:** `SpaceGramMessageShot`
  is a dedicated `UIGraphicsImageRenderer` module; it never snapshots the chat
  view hierarchy. It renders sender/initials, timestamp, formatted text, reply
  preview, photos/video/sticker cached thumbnails, and bounded placeholders for
  files, voice, round video and unsupported media against the current theme and
  locally available wallpaper image/color.
- Rendering is capped at 50 messages, 1440 points wide, 8192 points high and a
  20-megapixel bitmap budget. Larger selections are truncated with an omitted
  count instead of allocating an unbounded image.
- `SpaceGramMessageAction` is the data-driven action registry. Every custom
  action has a stable id, localization key, symbol, persisted preference,
  implementation state and applicability predicate. All custom actions default
  off. Message Shot, Save Protected Media and Forward without Name are wired;
  Forward as New is visibly marked not implemented in Settings and never
  appears in the message menu.
- Settings exposes `SpaceGram → Advanced → Message Menu`. Native Telegram
  actions remain in the pre-existing managed list and are not gated by the new
  SpaceGram preferences.

## Not completed

- **PARTIAL — Deleted live-chat overlay:** persisted server-delete snapshots are
  now observed per account and merged into the normal chat presentation in
  original timestamp order. The overlay deduplicates live server ids, is
  thread/page bounded, survives relaunch through the existing Postbox archive,
  uses local-namespace presentation messages marked `Deleted` / `Удалено`, and
  is always passed to the UI as read. It never inserts a fake server message or
  modifies Postbox unread state. Text, supported formatting and sender peers
  are restored when available. Deleted media currently shows a graceful local
  archive/unavailable label; rendering the retained photo/file bytes directly
  in the bubble is **NOT IMPLEMENTED** and still requires a lifetime-safe media
  resource bridge.
- **NOT IMPLEMENTED — SpaceGram Cosmic:** no theme or approved wallpaper preset
  exists.
- **NOT IMPLEMENTED — Forward as New:** the retained repeat/forward paths still
  use Telegram forwarding semantics. No local-content re-upload path is
  advertised as a new message.
- **PARTIAL — outgoing translator:** the safe opt-in draft translation exists,
  but the preference is not per-chat.
- **DEVICE VERIFICATION REQUIRED:** no physical-device build, install,
  second-account presence matrix, or deleted-overlay runtime pass was run.

These items must remain described as unavailable, not partially advertised in
the UI.

## Validation performed

- `python tools/check_spacegram_consistency.py`
- `python tools/check_spacegram_preflight.py`
- `python tools/test_spacegram_feature_contracts.py`

At the time of this audit these checks pass. They cover BUILD ownership,
localization keys/branding, plist parsing, asset declarations, icon contracts,
Ghost source-of-truth/presence boundaries, delayed-send post-upload RPC wiring
deleted-overlay ownership/merge boundaries, Message Shot bounds, custom-action
default/applicability rules, protected exporter routing, outgoing-translation
failure behavior and portable service contracts.
Swift compilation and iOS runtime behavior are not covered on this host. Swift
unit coverage additionally includes slow upload, too-close/past dates,
reconnect recalculation, deterministic retry behavior, overlay page boundaries,
local identity and missing-media fallback; it requires the macOS/iOS test
runner. Message Shot unit coverage includes one/many text messages, photo,
unsupported-media fallback, empty input and bitmap bounds.

## Required next iPhone pass

1. Confirm the system capsule says SpaceGram and uses the S artwork.
2. Generate/share QR for ASCII, Cyrillic, emoji and long text.
3. Switch through every alternate icon and return to Default.
4. Compare Ghost off, Ghost on/delay off and Ghost on/delay on from a second
   account for online, typing, reads and delivery timing.
5. Exercise text and slow media delayed sends, including edit, cancel and
   reconnect; verify the final scheduled time remains at least 12 seconds after
   upload completion.
6. Confirm protected-photo/video save only for content the account can already
   view.
7. Delete text/formatted/media messages from a second account; confirm the text
   overlay remains in chronology after pagination and relaunch, has no unread
   effect, and missing media uses the fallback without crashing.
8. Enable Message Shot, create one- and multi-message images, verify current
   colors/wallpaper and share-sheet presentation, then test the 50-message cap.
9. Confirm all SpaceGram message actions are absent by default, each toggle is
   independent, and protected document/animation/voice/round-video export uses
   only already-local resources.
