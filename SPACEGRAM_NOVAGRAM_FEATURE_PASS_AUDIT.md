# SpaceGram: Novagram-inspired feature pass

Date: 2026-09-20. Baseline: `e461a059e7`. Repository: `BADMAAAN/SpaceGram`.

## Delivery status

This is a **partial implementation of the complete requested roadmap**, following its priority order. Source checks passed; new iOS code is **not yet compiler- or device-verified**. Do not interpret source checks as a successful app build or installation.

| Phase | Implemented in this pass | Remaining / verification gate |
| --- | --- | --- |
| 1 — Settings | One root entry, S asset, native grouped scrolling hub, stable ordered entries, About, accounts callback, RU/EN hub, flattened legacy advanced screen, current Telegram theme | Device crash reproduction/regression and screenshots; exhaustive translation of deep legacy/tool screens |
| 2 — History | Deleted/edited entry filters, chat-specific deleted viewer, edit-history context label, localized events, deletion marker, pure revision/event presentation model | Device/server deletion and media matrix; live-chat overlay intentionally deferred |
| 3 — Ghost | Aggregate over existing four preferences, full toggle, opt-in quick button, initial offline presence update, native delayed text/media enqueue | Runtime network/device tests; read-on-interact, periodic offline enforcement, pre-story alert are not implemented |
| 4 — Messaging | Existing forward-without-author control exposed, formatter default OFF without preference overwrite, translation controls reused, optional first-message navigation | Round video from gallery, camera long-press selection, new text styles/postfix remain unimplemented |
| 5 — Utilities | Automatic media download/predownload policy switch; existing privacy, proxy, archive and AI screens linked; icon picker previews/layout repaired | Per-chat lock, new transcription controls/fallback, stranger/foreign-number blocking, send confirmations, hidden folder strip, mutual badge and extra local pins remain unimplemented |

Unsupported features have no new no-op buttons. The existing whole-app lock is not presented as a per-chat lock. Native Telegram transcription entitlement checks remain unchanged.

## Audit and references

Reviewed the architecture, internal migration, overnight and device-feedback audits before editing. Reused SpaceGram History schema v2, collection 1009, Media Archive, privacy policy, AI/provider controllers and retained Nagram enhancement preferences. No second history store, account manager, camera stack or scheduling timer was introduced.

Behavioral references consulted:

- [Novagram Android](https://github.com/Novagramorg/android), including `GhostMenu.kt`: grouped settings and composite Ghost controls.
- [AyuGram4A](https://github.com/AyuGram/AyuGram4A), including `AyuGhostUtils.java`: aggregate Ghost state.
- [AyuGramDesktop](https://github.com/AyuGram/AyuGramDesktop), including `ayu_settings.cpp`: privacy preference separation.
- [AyuGram Ghost documentation](https://docs.ayugram.one/shared/ghost/): scheduling policy and limitations.

No Android/C++ implementation was copied. Existing Nagram attribution is preserved; the policy comment links its behavioral reference. Existing artwork was resized for settings and previews; no new future-icon artwork was generated.

## Settings crash: source-level root cause

The old standalone controller constructed entries out of order: stable IDs 22 before 10, and 23 before 20. `ItemListControllerNode.swift` asserts strict `isLessThan` ordering for every transition. This is a concrete crash path, not a reason to merely hide the old entry.

The replacement uses fixed section/row identities and `entries.sorted()`; optional rows do not renumber the others. Contract tests enforce uniqueness and sorting. Existing settings migration/observer bootstrap ordering remains intact. No new force unwrap/cast was added to the hub. A real device regression test remains necessary: this finding does not prove there cannot be another device-specific crash.

## Root structure and language

Telegram Settings now has one `SpaceGram` row with a rounded S tile. It opens native `ItemListUI` blocks with colored icons, switches, disclosure rows and explanatory footers:

Information → Accounts → Chat → Ghost → Protection → Interface → Messages → History and Media → AI & Tools → Appearance → Advanced.

Accounts reuses Telegram's existing account switcher with an optional gesture, not a synthetic gesture. Theme and icon links reuse Telegram settings. Advanced preserves all retained legacy groups in a scrolling screen rather than the General/Messages/Other tab header; old deep links remain compatible.

New hub keys and main advanced-screen labels have RU/EN coverage. Locale normalization accepts `ru-RU`/`en-US` and uses Telegram presentation language, never keyboard language. Provider settings and archive/history alerts were also localized. **Full deep-subscreen localization is not complete**: inherited nested enhancement/tool screens still need a separate exhaustive audit, as do raw history metadata labels. Primary hub text is covered by automated key checks.

## Deleted messages and edit history

- Existing opt-in storage settings and captured records are preserved; no migration forces history ON.
- Deleted/edited hub entries open the existing query/filter controller with the appropriate initial kind. A chat context action opens deleted records for that peer.
- Existing capture hooks and schema v2 archived asset references are unchanged. Nothing is reinserted into Postbox as a fabricated server message.
- Deleted events have a trash marker. Revision lookup follows the event's revision number; an expired/missing revision cannot display unrelated newer text.
- Timeline model retains orphan revisions, orders observations deterministically, and preserves entities and media references. Existing detail UI renders text/entities and exposes formatting/media metadata.
- Context menu uses “История правок” when saved edits exist. Native Telegram's edited indicator is retained.
- Existing Media Archive viewer handles complete local assets and missing-file placeholders. Files never received by the device cannot be recovered. Secret/ephemeral media restrictions remain unchanged.
- Live-chat supplemental deleted bubbles are deferred to avoid modifying server history/synchronization.

## Ghost and scheduling behavior

`SpaceGramGhostMode` is a read-only aggregate over the master and four existing preferences: reads, stories, presence and activity. `setGhostMode` changes those four only upon explicit user action. Initialization does not rewrite partial existing preferences. Full Ghost requires all four plus SpaceGram enabled.

The quick chat-list button is opt-in, reflects the same aggregate and has localized accessibility text. It is hidden while editing/non-root chat lists or when SpaceGram is disabled. Partial configurations are not shown as full Ghost.

Existing automatic read/content acknowledgement, story-view, activity and read-metric hooks remain the enforcement layer. Group-call speaking events stay exempt. Timer/view-once lifecycle acknowledgements are intentionally preserved. Ordinary reads retain the existing local unread behavior; this pass does not invent separate local/server read state.

Presence now has an initially unknown previous state, allowing an initial offline update when Ghost is already active. MTProto and push connections are not disconnected. Replies/reactions/server actions, other logged-in clients and explicit sends can reveal activity; invisibility is not guaranteed. Periodic offline enforcement and dedicated read-on-interact/story warning controls are not included.

Delayed sending is OFF by default and requires full Ghost. `SpaceGramDelayedSendPolicy` calculates 12 seconds for text and `max(6, ceil(MiB * 4.5))` for media, capped at one day against malformed sizes. Unknown media uses a 3 MiB estimate (14 seconds); an album shares the largest member's delay and one timestamp, not a sum-of-upload-times estimate.

Both the composer text callback and common media enqueue boundary use the same policy and native `OutgoingScheduleInfoMessageAttribute`. Explicit schedules and sends from the scheduled-messages screen are preserved. There is no independent timer or second enqueue operation. The native scheduled queue is opened, providing Telegram's edit/cancel/persistence/retry behavior.

Automatic scheduling deliberately excludes secret chats, bots, forwards, story replies, paid messages, suggested posts, autoremove attributes and unsupported media types. Text with web previews and supported file/image sends can be scheduled; unsupported sends retain native behavior. Slow uploads, offline reconnection or server scheduling semantics may cause a date to expire before transmission; this is disclosed in the settings footer. Runtime duplicate/cancel/offline safety is a release gate, not a locally verified claim.

## Other implemented controls

- “К первому сообщению” adds an optional context action using native timestamp navigation, not a scan of full history.
- “Переслать без имени” exposes the existing Nagram forward-without-quote implementation and its existing preference.
- Formatter uses the same stored key with fallback changed to OFF; saved true/false choices are retained.
- Disable auto-download guards automatic download and predownload policy only; manual download code is untouched. Already-running transfers are not canceled and already-rendered items may require reopening the chat.
- Stories panel, compact chat list, seconds and translate-before-send reuse existing preferences/backends.
- Icon picker uses real Default/Alternate PNG previews, responsive columns and a data-driven existing icon list. A future preview is a list entry/resource, but an actual switchable iOS icon also requires asset catalog/Info.plist registration. No Mars/Earth/Sun placeholder artwork was added.

## Validation

Executed on Windows:

- `python tools/test_spacegram_feature_contracts.py`: **7 passed** (root entry, identities/RU-EN keys, resources, initialization order, formatter default/key, advanced RU labels, both delayed enqueue integration paths and group-call exception).
- `python tools/check_spacegram_consistency.py`: **passed**, 773 BUILD files, 80 product/test Swift files, 5 localization catalogs, 0 errors.
- `python tools/check_spacegram_preflight.py --report SpaceGram/audits/novagram-feature-preflight.json`: **passed**, 32 plists, 193 asset JSONs, 291 referenced asset files, 4 YAML files, 0 errors.
- `git diff --check`: **passed**.

Preflight's Swift grammar scan has 26 advisory nodes in 8 files, including known parser limitations on existing valid Swift constructs. It is not a Swift compiler or Bazel dependency analysis. Report: `SpaceGram/audits/novagram-feature-preflight.json`.

Added 10 XCTest methods, included by the existing test target's glob:

- `SpaceGramHistoryPresentationTests`: 4 cases for deletion, missing revision, edit/formatting mapping, orphan revisions/filter behavior.
- `SpaceGramGhostModeTests`: 4 cases for aggregate state, text opt-in, media rounding, overflow/malformed input.
- `SpaceGramFeatureDefaultsTests`: 2 cases for formatter preference preservation and partial-Ghost/history migration preservation.

**XCTest, Swift type checking, simulator and device tests were not run locally: this host has no Xcode.** The workflow builds an intermediate fake-signed debug ARM64 IPA for subsequent re-signing; it does not prove installation or run these XCTest cases. No signing configuration or Node 20 action versions were changed.

Baseline CI [run 35466865141](https://github.com/BADMAAAN/SpaceGram/actions/runs/35466865141) was observed successful; it is **not validation of this feature pass**. After the final push, a new `SpaceGram iPhone Test Build` is dispatched for `main`; the new run URL/status is reported in the task handoff.

## Logical commits

- `72d1e05bd5` — unified hub and ordering crash fix.
- `2af1c01299` — deleted/edit presentation integration.
- `03483c9c30` — Ghost aggregate, quick control, native scheduling.
- `050ceed74f` — composer text scheduling path.
- `346d033ac8` — localized enhancements, chat controls, defaults tests.
- Audit/report commit follows these changes; final hash is in the handoff.

All upstream integration changes are marked `MARK: NAGRAM` (BUILD comments use `#`). The pre-existing untracked `qwengram_run7_fix.patch` is not included or modified.

## Manual iPhone checklist

Use an isolated Telegram test account; record iOS/build/language/theme. Re-sign and install the produced IPA with the approved provisioning workflow before marking any item passed.

- [ ] Cold launch existing migrated profile and clean profile; no recursive preference initialization crash.
- [ ] Settings contains exactly one SpaceGram row; S tile is sharp and appropriately sized.
- [ ] Open, leave and reopen hub; toggle conditional rows repeatedly; no ItemList assertion.
- [ ] RU and EN app languages, light/dark, large text: labels, footers, icons and navigation remain usable. Changing keyboard alone does not change UI language.
- [ ] Deleted text: receive while capture enabled, delete from second client, open global and per-chat deleted viewers; verify text, author, deletion mark and ordering.
- [ ] Multiple edits: inspect previous text, timestamps, entities and media metadata; retained/expired revisions never mismatch events.
- [ ] Deleted downloaded photo/video/voice/round-video/file/GIF: open archived asset. Never-downloaded/evicted asset: placeholder, no crash. No fake live-chat server messages.
- [ ] Partial and full Ghost states survive restart/migration. Quick button reflects state; disabled master hides/disables effective Ghost behavior.
- [ ] Second client checks automatic text/media/voice/video reads, mentions/reactions, metrics and local unread behavior. Explicit server actions/timer media limitations match footer.
- [ ] Second client checks typing, recording, upload, sticker activity and story views; group-call speaking still works.
- [ ] Ghost active at launch sends initial offline state; background/foreground and push delivery work. Other sessions/server actions are not promised invisible.
- [ ] Delayed text: one pending message, ~12-second requested schedule, composer clears once; cancel/edit/send-now without duplicates.
- [ ] Delayed photo/file/video/voice/GIF/album: check formula/shared date, pending UI, slow upload, app termination, offline/reconnect and retry. Confirm no loss/duplicate sends.
- [ ] Ghost partial/OFF or delay OFF: ordinary send. Explicit schedule, secret/bot/forward/paid/story/ephemeral sends keep native semantics.
- [ ] Round video from gallery and long-press camera selection: **not implemented**, do not mark passed; existing recording must still work.
- [ ] Forward without name: content copied with no author attribution; restricted/protected content rules remain native.
- [ ] Formatter OFF for clean preferences; previous ON choice preserved; ON opens existing formatting UI.
- [ ] Jump-to-first handles large histories/topics without loading everything; deleted earliest messages do not crash navigation.
- [ ] Auto-download switch blocks new automatic/predownload requests while explicit manual download still works; previous native network preferences return when disabled.
- [ ] Default/Alternate icon previews render, switch actual home-screen icons, and survive restart; test narrow and wide layouts.
- [ ] Telegram theme follows light/dark; account row switches through native account manager.
- [ ] History retention/cleanup, proxy, AI tools/provider settings and translation keep existing behavior.
- [ ] Per-chat lock, voice-language/translation controls, local pins, hidden folders, mutual badge and send-confirmation matrix: **not implemented**, separate follow-up gates.
