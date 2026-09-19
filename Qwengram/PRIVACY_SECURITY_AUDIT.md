# Qwengram Privacy & Security audit

Date: 2026-09-19. Base checkpoint:
`d4aeb7d3cd0399819e7dab729da9a9dd6fe1e2ec` on `qwengram/main`.
The work described here is local and uncommitted.

## App Lock and biometrics

Qwengram reuses Telegram-iOS's existing App Lock instead of presenting a second
lock overlay or keeping a second PIN. The Qwengram Privacy & Security screen opens
the native passcode controller for enable/disable, PIN creation and change,
Face ID or Touch ID, PIN fallback and timeout selection. It also exposes Lock Now.
The native UI only presents the biometric method reported by `LocalAuth`; devices
without available or enrolled biometrics do not get a Face ID/Touch ID toggle.
Authentication errors, lockout, changed enrollment/domain state and fallback are
handled by the existing `LocalAuth` and `PasscodeUI` flow.

The timeout list gains Immediately. Its persisted value is `-1`; positive values
keep Telegram's existing timeout behavior and `nil` remains Disabled. AppLock
interprets `-1` as lock on background and on the first lifecycle evaluation after
relaunch. Changing to Immediately while the app is already foreground does not
unexpectedly cover the settings screen. Biometrics, when enabled in the native
screen, are requested by the existing lock overlay after relaunch, immediate lock
or an elapsed timeout, with the PIN still available as fallback.

No cryptographic algorithm or passcode verifier was added. Telegram's current
`PostboxAccessChallengeData` remains the source of truth for its native App Lock.
Migrating that upstream representation to a new Keychain verifier would change
the authentication contract across AppLock, PasscodeUI and extensions and is not
safe as an isolated Qwengram layer. Qwengram never logs or separately persists a
PIN. The pre-existing Qwen provider secret remains in Keychain and is now scoped
by Telegram account ID with a one-time migration from the old app-global entry.

## Notification privacy

The selected account stores a small versioned policy next to its MediaBox and
mirrors only that policy into the existing application-group defaults so the
Notification Service extension can read it. The extension waits until the
notification encryption key resolves an `AccountRecordId`; policies cannot be
applied across accounts. Invalid, missing, oversized or future-version data falls
back to the native presentation.

The policy can hide the sender identity, combined notification title, message
preview and preview attachments, or replace visible content with generic text.
Telegram notification settings remain available through a native shortcut. The
extension preserves delivery, decryption, sound, badge, category, thread ID and
`userInfo`. Hiding identity also suppresses the Siri/Intents sender donation, and
hiding preview suppresses rich emoji rendering and visible attachments.

iOS does not expose a reliable general device-lock state to this Notification
Service architecture. The conditional setting is therefore explicitly tied to
Telegram/Qwengram App Lock state, which is shared with the extension. It does not
claim to detect the lock-screen state. Telegram's title data does not consistently
separate sender and chat in every payload, so either identity switch hides the
combined title rather than risking a partial identity leak.

## Local account data controls

The new screen can clear the selected account's Message History, Media Archive,
Qwen conversations, Qwen API key and account privacy policy. Clear All performs
those operations together after two explicit confirmations. It never removes an
account, authorization/session state, chats, cloud data or another account's
files. Conversation removal validates the account-local directory before deleting
it. Media and history continue to use their existing account roots and Postbox.

Older Qwengram feature toggles are stored in shared `UserDefaults` and are not
safe to reset for one account. “Clear Local Privacy Settings” therefore resets
only the new account-scoped notification and metadata policy. Clear All likewise
leaves shared feature toggles unchanged; the confirmation text states its exact
scope. This preserves the account-aware requirement instead of silently changing
other logged-in accounts.

## Emergency groundwork

`QwengramEmergencyAction` currently permits only a future local
`lockApplication` policy. There is no panic PIN, destructive wipe, remote account
deletion, hidden destructive path or automatic data removal. The Settings screen
documents the boundary and exposes no experimental destructive control.

## Metadata sanitization

The opt-in metadata policy applies to ordinary still photos selected through
Telegram's `PhotoLibraryMediaResource` path. That native path already obtains
decoded image pixels and re-encodes the outgoing photo; Qwengram additionally
forces the non-EXIF path and performs a final single-frame ImageIO re-encode that
retains orientation while omitting EXIF, GPS and other source dictionaries.
Processing remains on the existing photo resource worker/signal path, not the
main thread.

Original files/documents, animated images and videos are unchanged. Rewriting
those formats could alter user-selected bytes, signatures, animation or codec
metadata and is not enabled without a format-specific safe design. A failed final
sanitizer falls back only to Telegram's already re-encoded photo result, never to
the original photo asset bytes.

## Validation and remaining runtime work

The iOS test target includes policy defaults and locked-only behavior, account
isolation and clearing, EXIF/GPS removal, and conversation clearing without
cross-account deletion. On this Windows host, the repository consistency checker
passed across 771 BUILD files, 65 product Swift files and five localization
catalogs. Advisory tree-sitter parsing of 16 changed Swift files reported zero
`ERROR` nodes; its four missing-token diagnostics are the grammar's known false
positive for empty tuple expressions `()`. BUILD/source inclusion, English/Russian
localization references and `git diff --check` also passed.

The Swift compiler, Bazel iOS toolchain, Xcode, simulator and device runtime are
not available here. A macOS validation pass must compile the app and Notification
Service, run the iOS tests, exercise PIN/biometric fallback and every timeout,
test notification presentation for two accounts, and inspect sanitized outgoing
photos while confirming original-file and video sends remain byte-preserving.
