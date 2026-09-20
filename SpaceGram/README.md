# SpaceGram

The product and its own source tree are named SpaceGram.
`SpaceGram/` owns the client-specific settings, tools, AI and message archive.
Telegram integration stays in small hooks documented in [SPACEGRAM_HOOKS.md](SPACEGRAM_HOOKS.md).
Upstream Swift edits use `// MARK: NAGRAM` as required by the repository guide.
The common localization loader and resources live in `SpaceGram/Strings`.
Retained implementations are owned in `SpaceGram/Enhancements`; compatibility
symbols and storage keys preserve existing users’ preferences.

## Implemented

- Settings and reactive settings signals; a master switch gates new history
  capture, Qwen requests and Tools actions. Turning it off cancels active Qwen
  requests and disables Ghost policies. Existing history, settings and Keychain
  management remain accessible; stored preferences/data are not erased.
- Tools Hub (existing `Bots` module and IDs retained), with Qwen Assistant,
  Summarizer and Translator. Unimplemented tools are disabled.
- Qwen streaming and Stop; model selection and a device-only, when-unlocked
  Keychain API key. Assistant conversations persist per account; summaries and
  translations remain in controller memory.
- Message History: previous versions and selected explicit server deletion events,
  an account-isolated Postbox store, global browser and per-message details.
  Storage is bounded; large histories evict older snapshots before rejecting an
  oversized newest snapshot. Capture never prevents Telegram's ordinary writes.
- Independent opt-in Ghost controls for automatic chat reading, outgoing chat
  activity, Story view acknowledgements (including pinned Stories), and explicit online presence.
  Presence changes leave the Telegram connection and push configuration intact.

- Opt-in Media Archive: complete received cloud-message resources captured at
  server deletion, timed consumption and local/remote expiration. Independent
  account storage, bounded retention, SHA-256 verification and local Quick Look
  from History. History v1 remains readable; writes use v2 media references.

## Current limits

Ghost Mode is partial: automatic reads from the chat history view are suppressed
without changing unread state. Native explicit mark-as-read actions remain
available. Untimed media-consumption receipts, automatic mention/reaction/poll reads, live
location receipts, channel view increments and read metrics are also suppressed.
Timed/view-once lifecycle acknowledgements and previously queued read operations
remain native; this is not a universal protocol-level read receipt firewall. Requests
already transmitted cannot be withdrawn. Sending/reactions may expose activity.
Viewing a later Story with suppression off can acknowledge earlier IDs as well.
Group-call speaking events are preserved so calls continue functioning.

Media Archive defaults off and requires SpaceGram and Message History enabled.
Limits are 512 MiB / 1,000 assets per account, 128 MiB per asset, 30-day lazy
retention. Only complete local files are captured: no network recovery, partial
streams, secret-chat binaries or Story archive. Unsupported codecs may not play
in Quick Look. Capture is best effort, not a guarantee against all deletions or
cache eviction. Search, filters, pagination, manual cleanup, persistent AI,
Privacy & Security and product-screen dark appearance are implemented in source.
See [SPACEGRAM_ARCHITECTURE_AUDIT.md](SPACEGRAM_ARCHITECTURE_AUDIT.md) for the
current map, retained dependencies, validation boundaries and technical debt.

See [MEDIA_ARCHIVE_AUDIT.md](MEDIA_ARCHIVE_AUDIT.md) for current integration,
protocol exceptions, retention semantics and the required macOS tests.

See [FOUNDATION_AUDIT.md](FOUNDATION_AUDIT.md) for the source inventory, next
integration points and the remaining validation work. No iOS build or device
verification has been performed for this change on the Windows host.
