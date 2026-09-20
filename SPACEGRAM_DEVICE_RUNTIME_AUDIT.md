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
- About SpaceGram describes device-local retention limits and includes the app
  version/build.

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

Known limitation: the schedule date is computed at enqueue. The current patch
does not yet tag SpaceGram schedules and re-normalize them immediately before a
post-upload RPC. A very slow upload can therefore consume the remaining offset.
Online invisibility and final media timing require the second-account iPhone
matrix before acceptance.

### Protected media and outgoing translation

- Existing retained hooks allow saving already-accessible protected photos and
  videos when local force-copy is enabled, but continue to reject paid content.
  They use Telegram's received media/resource pipeline and do not bypass server
  membership, access hashes or paywalls.
- The existing forward-without-quote path remains available as a new outgoing
  message path. It is not presented as an authentic server forward.
- Translate-before-send remains opt-in and uses the existing non-Qwen
  translation service. The translated draft is shown before the user sends it;
  failure leaves the draft intact.

## Not completed

- Deleted-message snapshots are captured before server deletion and downloaded
  media can be retained, but they are not yet merged back into normal chat
  chronology as a supplemental overlay. No fake server message is inserted.
- Message Shot and its dedicated bounded renderer are not implemented.
- `SpaceGram Cosmic` and approved cosmic wallpaper presets are not implemented.
- The protected-media hooks above have not been extended to every file/voice/
  round-video context-menu surface in this pass.
- No physical-device build, install or second-account behavior matrix was run.

These items must remain described as unavailable, not partially advertised in
the UI.

## Validation performed

- `python tools/check_spacegram_consistency.py`
- `python tools/check_spacegram_preflight.py`
- `python tools/test_spacegram_feature_contracts.py`

At the time of this audit these checks pass. They cover BUILD ownership,
localization keys/branding, plist parsing, asset declarations, icon contracts,
Ghost source-of-truth wiring, delayed-send structure and portable service
contracts. Swift compilation and iOS runtime behavior are not covered on this
host.

## Required next iPhone pass

1. Confirm the system capsule says SpaceGram and uses the S artwork.
2. Generate/share QR for ASCII, Cyrillic, emoji and long text.
3. Switch through every alternate icon and return to Default.
4. Compare Ghost off, Ghost on/delay off and Ghost on/delay on from a second
   account for online, typing, reads and delivery timing.
5. Exercise text and slow media delayed sends, including edit, cancel and
   reconnect.
6. Confirm protected-photo/video save only for content the account can already
   view.
