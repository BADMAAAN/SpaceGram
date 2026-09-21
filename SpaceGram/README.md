# SpaceGram product layer

`SpaceGram/` owns the app-specific settings, privacy policies, local history presentation, media archive, optional message actions, localization and settings UI. Telegram behavior remains in upstream modules except for small integration hooks documented in [SPACEGRAM_HOOKS.md](SPACEGRAM_HOOKS.md).

The active product has one settings hub and no SpaceGram AI/Qwen or custom QR tool. Telegram's native QR features remain upstream.

Key contracts:

- Ghost Mode has one global persistent state and suppresses voluntary presence, typing/activity, automatic reads and Story acknowledgements. Group-call speaking is an intentional exception.
- Read on Interact runs only after a successful explicit send or reaction; delayed queueing never reads.
- Delayed Send uses corrected server time, a 12-second minimum and post-upload revalidation.
- Deleted-message preservation is an account-local presentation overlay, never fake Telegram/Postbox history.
- Media Archive accepts only complete locally received cloud resources, validates atomic publication, applies bounded cleanup and excludes secret chats.
- Custom message actions, formatting, automation and archive features are opt-in.
- Outgoing translation is isolated by account/chat and preserves the draft on failure.

Retained code in `Enhancements/` keeps compatibility names and required attribution. Upstream modifications use a nearby `// MARK: NAGRAM` marker.

See [SPACEGRAM_ARCHITECTURE_AUDIT.md](SPACEGRAM_ARCHITECTURE_AUDIT.md) for the current module map, [MEDIA_ARCHIVE_AUDIT.md](MEDIA_ARCHIVE_AUDIT.md) for archive details, and the repository [build guide](../docs/build.md) for macOS/device validation.
