# Message History, Media Archive and Qwen continuation audit

Date: 2026-09-19. Base checkpoint: `b7d52c2231` on `qwengram/main`.
All changes described here remain local and uncommitted.

## Starting point and completed work

The checkpoint already contained the Qwengram foundation, Ghost Mode, the
Postbox-backed Message History collection, media capture hooks, and a bounded
Media Archive. This continuation kept those data paths and the Telegram-iOS
integration hooks. It did not create a second history database or change
Telegram's message deletion, timer, or receipt semantics.

The History browser now searches saved text, filters All/Edited/Deleted/Media
and chat, orders by observation time, and pages visible results. Work on the
Postbox and media utility queues keeps record scanning and binary verification
off the main thread. Rows show event type, date, available author data, and a
lightweight saved-media indicator. Message detail shows saved revisions,
timestamps, source/reason, old text, entities, linked assets, and precise
available/expired/missing/corrupt/never-captured states. Available files open
through Quick Look using a verified temporary copy. Lists never load binary
media just to render a row.

Confirmed deletion actions cover one event or revision, one message, one chat,
all Message History, and all Media Archive. The UI confirms destructive bulk
actions. History removal uses the selected account's Postbox. Archive removal
uses the selected account's media directory. Clearing saved media leaves saved
text readable, with asset state shown as unavailable.

## Media policy and ownership

The Media Archive settings page offers Enabled, storage presets of 256 MiB,
512 MiB, 1 GiB and 2 GiB, retention presets of 7/30/90 days, automatic age
cleanup, current bytes and asset count, Clean Expired, and Clear Archive.
Policy is stored in a protected `policy.json` in the account's archive root.
The default remains 512 MiB, 30 days and automatic cleanup. Disabling automatic
cleanup suspends age eviction and orphan reconciliation; size and count limits
still apply. Clean Expired applies the selected age limit immediately.

History event links are the ownership source. Event/message/chat deletion
checks all surviving readable records before deleting a candidate asset.
Shared assets survive until the last reference is removed. If any record is
unreadable, automatic detached-asset deletion is withheld. After a successful
capture link, orphan reconciliation checks all account references and removes
unreferenced assets older than five minutes; incomplete reference scans do not
authorize this cleanup. The grace period protects in-flight capture/link work.
Explicit Clear Archive intentionally removes binary data even when referenced;
History records remain and show missing or expired asset states. Retention,
storage and asset-count eviction may likewise remove referenced binary media;
the history metadata remains as evidence. A file that was never captured is
distinguished from an expired, missing or corrupt linked file.

Archive manifests remain version 1. Policy is version 1 and rejects invalid
presets. History v1 records still decode; v2 adds optional capture/asset IDs.
Future archive manifest versions are preserved rather than rewritten by older
code. Invalid or missing payloads are reported in detail instead of falling
back to Telegram's cache.

## Telegram UI indicator

The existing message context menu now queries one cloud message's History
record on Postbox and exposes a History action. Its title can include Edited
and Deleted markers. History, Edited and Deleted marker switches are in
Message History settings. This uses the existing menu/status pattern and one
small upstream modification in `ChatInterfaceStateContextMenus.swift` beside
the existing `// MARK: NAGRAM` marker. There is no always-visible bubble badge:
that would require a wider invasive patch across Telegram's message renderers.
The History menu action remains available when markers are disabled.

## Qwen conversation architecture and UX

`QwengramConversationStore` saves one JSON file per conversation under the
selected account's Postbox sibling directory. Files have iOS protection and
the directory is excluded from backup. API credentials stay in Keychain and
are not serialized. The directory has no cross-account shared index. The
version 2 conversation model stores ID, title and custom-title flag, creation
and update dates, selected model, optional system prompt/metadata, and local
messages. Messages have stable IDs and optional attachment descriptors for
future images, documents, Telegram messages, archived media and selected text.
These descriptors are local groundwork: there is no nonfunctional Attach
button and no binary upload path. The provider serializes only role/content.

Version 1 conversations load with creation time derived from their previous
update time and default empty optional fields. They are written as version 2
on the next save. Unreadable conversation files are skipped individually so a
neighboring valid dialog still loads. The store caps each JSON file at 1 MiB
and the directory at 100 conversations.

The assistant UI can list, search, open, create, rename and delete dialogs.
Titles derive from the first user message until explicitly renamed. It keeps
the complete local transcript, while requests use a bounded suffix of complete
messages plus the system prompt. The 24,000-character request budget never
truncates message text and reserves up to 4,096 characters for system messages.
Older local messages remain available through Show Earlier. The selected model
is updated when a request starts. Copy, Share, Retry, Regenerate, Delete message
and Stop generating are available; a sending guard rejects duplicate requests.
Regeneration preserves earlier saved responses. Stop persists a nonempty
partial response; empty placeholders are removed. Streaming text is plain;
completed responses use a small bounded renderer for paragraphs, bold,
italic, inline code, fenced code, HTTP(S) links and unordered lists. The UI
does not parse incomplete Markdown on every token.

## Settings, tests and validation

The Settings entry is grouped into General, Ghost Mode, Privacy & Security,
Message History, Media Archive, Tools & AI, Appearance and Advanced. The last
two link users conceptually to native Telegram settings rather than adding
duplicate appearance controls. New user-facing controls have English and
Russian strings. Existing Qwen error text retains some English-only wording.

XCTest sources cover archive capture and integrity, missing/corrupt states,
retention and manual cleanup, orphan cleanup, size/count selection, shared
asset references, v1 History decoding, AI persistence/deletion/rename, partial
responses, account isolation, v1 migration, corrupt-file isolation, context
trimming/system prompt retention, and the 1 MiB storage limit. The checks run
through the existing Bazel test target on macOS.

On this Windows host, `python tools/check_qwengram_consistency.py`, tree-sitter
Swift syntax parsing of changed files, BUILD/source inclusion checks,
localization consistency and `git diff --check` were run. A Swift compiler,
Bazel iOS toolchain, Xcode, simulator and iPhone are unavailable here. No iOS
build, XCTest, simulator run, signing or device install is claimed. Those need
a macOS/Xcode environment; on-device work additionally needs the signing and
profile preflight in `docs/build.md`.

Known limits: there is no bubble-level marker; the context menu is the native
entry point. Quick Look is used for local files rather than a custom viewer.
The renderer supports the listed common Markdown constructs, not full CommonMark
tables, nested lists or embedded media. Search in the conversation picker
matches titles and latest message previews, not every archived transcript
message. Archive data is local to the device and excluded from backup.
