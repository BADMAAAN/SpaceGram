# SpaceGram presence semantics audit

Audited 2026-09-22. This document separates source-confirmed behavior from the
two-account device behavior that still has to be measured.

## Reference findings

### AyuGram Desktop

Source revision: `AyuGram/AyuGramDesktop` `dev`
`db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a`.

- `api/api_updates.cpp` suppresses the normal `account.updateStatus(offline:
  false)` path when `sendOnlinePackets` is disabled.
- Sending a message is nevertheless documented as a server-side online reveal.
  The successful send path in `data/data_histories.cpp` calls
  `AyuWorker::markAsOnline`.
- `ayu/ayu_worker.cpp` checks that mark every three seconds and sends
  `account.updateStatus(offline: true)`. It does not wait for natural expiry.
- `ayu/utils/telegram_helpers.cpp::applyGhostScheduling` assigns a real
  `scheduled` date to the Telegram send options. It is not a local sleep followed
  by a normal send.
- No reference code stores an old `userStatusOffline.was_online` and no API call
  sends a chosen replacement timestamp.

Relevant source:

- https://github.com/AyuGram/AyuGramDesktop/blob/db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a/Telegram/SourceFiles/api/api_updates.cpp
- https://github.com/AyuGram/AyuGramDesktop/blob/db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a/Telegram/SourceFiles/data/data_histories.cpp
- https://github.com/AyuGram/AyuGramDesktop/blob/db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a/Telegram/SourceFiles/ayu/ayu_worker.cpp
- https://github.com/AyuGram/AyuGramDesktop/blob/db3b9891cb0b04ebb7d8c0e71ada3bcc669b910a/Telegram/SourceFiles/ayu/utils/telegram_helpers.cpp
- https://docs.ayugram.one/shared/ghost/

### Novagram / Fenixuz iOS

Source revision: `Novagramorg/iOS` `main`
`268aa3be43a4f286d942162765d6e1f5740d3347`.

- `ManagedAccountPresence.swift` suppresses `offline: false`, but selects
  `account.updateStatus(offline: true)` whenever Ghost is active.
- It has no send-scoped transient-online controller, natural-expiry mechanism,
  or preservation of an old server `was_online` value.
- `FenixuzGhostReadOnSend.swift` concerns read receipts only. It must not be
  treated as presence evidence.

Relevant source:

- https://github.com/Novagramorg/iOS/blob/268aa3be43a4f286d942162765d6e1f5740d3347/submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift
- https://github.com/Novagramorg/iOS/blob/268aa3be43a4f286d942162765d6e1f5740d3347/submodules/TelegramCore/Sources/Fenixuz/FenixuzGhostReadOnSend.swift

### Protocol boundary

`account.updateStatus` accepts only `offline: Bool`. `userStatusOnline` contains
an expiry, while `userStatusOffline` contains `was_online`. Public MTProto does
not expose a method for restoring an arbitrary prior timestamp.

- https://core.telegram.org/method/account.updateStatus
- https://core.telegram.org/constructor/userStatusOnline
- https://core.telegram.org/constructor/userStatusOffline

The reference source disproves the hypothesis that AyuGram itself deliberately
waits for natural expiry. It does not prove what timestamp Telegram's server will
publish after the explicit offline request; that requires wire observation from
a second account.

## SpaceGram flow

### Before this change

`SharedWakeupManager` foreground state
→ `Account.shouldKeepOnlinePresence`
→ `ManagedAccountPresence`
→ Ghost resolves desired online to false
→ `account.updateStatus(offline: true)`
→ optional 25-second offline heartbeat.

An immediate message follows the normal enqueue and pending-message RPC path.
Telegram may expose a transient online status as a server-side consequence. The
offline heartbeat could then overwrite the server's offline state again.

### After this change

With Ghost active:

`SharedWakeupManager` foreground state
→ `ManagedAccountPresence`
→ cancel the client's online refresh and any pending presence request
→ send neither `offline: false` nor `offline: true`.

Immediate send:

tap Send
→ TelegramUI enqueue
→ `PendingMessageManager`
→ ordinary `messages.sendMessage` / media RPC without `schedule_date`
→ server result
→ content-free `immediate send completed` diagnostic.

There is no client-created online RPC and no post-send explicit offline RPC.
Any server-created online status is allowed to expire. Whether the server then
re-exposes the exact earlier `was_online` is intentionally not claimed here.
If an authoritative `userStatusOffline` update does contain an older timestamp,
the self-profile cache now accepts that rollback instead of preferring a newer
local observation.

Delayed send:

tap Send
→ attach `OutgoingScheduleInfoMessageAttribute`
→ upload media if required
→ recompute `schedule_date` from `Network.globalTime`
→ `messages.sendMessage` / `sendMedia` / `sendMultiMedia` with a real
`schedule_date`
→ Telegram server queue and acknowledgement.

No local timer performs a later ordinary send. Ghost presence suppression stays
active during tap, upload, enqueue, acknowledgement, and later server delivery.

## Verification boundary

Source and contract tests prove:

- Ghost no longer emits explicit online or offline presence RPCs.
- automatic delayed sends still require a non-nil corrected schedule date;
- immediate and scheduled network completions emit content-free diagnostics;
- the self-profile accepts the latest server `was_online`, including rollback;
- read-on-interact code was not changed.

A physical-device, two-account test must still record:

- status before the send;
- transient-online duration;
- status and exact `was_online` after expiry;
- absence of online, typing, reads, and last-seen movement for scheduled send;
- round-video upload followed by scheduled enqueue and server delivery.

Do not claim preservation of the old server-visible last-seen timestamp until
that test passes.
