[English](README.md) | [Русский](README_RU.md)

# SpaceGram

SpaceGram is an experimental, open-source and unofficial Telegram client for iOS. It uses Telegram-iOS as its platform foundation and keeps product-owned code under `SpaceGram/` with small, marked integration hooks in upstream modules.

## Current product surface

- One **SpaceGram** row in Telegram Settings opens a grouped settings hub.
- **Ghost Mode** uses one persistent global switch for presence, typing/activity, automatic reads and Story acknowledgements. Group-call speaking remains native so calls continue to work.
- **Read on Interact** can acknowledge history only after a successful explicit cloud send or reaction. Opening, viewing, scrolling, typing and queueing a delayed message do not mark the chat read.
- **Delayed Send** schedules supported ordinary sends at least 12 seconds from corrected Telegram server time and revalidates the timestamp after uploads.
- Ordinary Ghost chat opens start at the latest messages without changing server unread state; explicit message, search, reply, mention, pinned, date and deep-link targets take precedence.
- Deleted cloud messages are presented through an account-local overlay. Original text remains unchanged and deletion is shown as compact timestamp metadata.
- **Media Archive** preserves complete resources already received by the current account. Missing bytes stay unavailable; secret chats are excluded.
- Optional message actions include Message Shot, Save Protected Media, Forward as New and Forward without Name. They are independent and default off; unavailable actions are shown as unavailable rather than faked.
- Profile ID, outgoing translation, inline-bot rules, appearance, privacy and retained enhancement settings are available through the hub.

The retired SpaceGram AI/Qwen and custom SpaceGram QR tools are not part of the product. Telegram's upstream QR flows remain intact.

## Architecture

```text
Telegram-iOS upstream
    ↓ marked integration hooks
SpaceGram settings, policies, local storage and UI
```

| Path | Responsibility |
| --- | --- |
| `SpaceGram/Settings`, `SettingsSignal` | Product settings and reactive policy state. |
| `SpaceGram/SettingsUI` | The SpaceGram hub and product settings screens. |
| `SpaceGram/HistoryStorage`, `HistoryOverlay`, `HistoryIntegration` | Account-local edit/delete capture and presentation-only overlays. |
| `SpaceGram/MediaArchive` | Validated, bounded storage for complete locally received media. |
| `SpaceGram/Privacy` | Ghost and privacy policy helpers. |
| `SpaceGram/Enhancements` | Retained implementations with compatibility identifiers and attribution preserved. |
| `SpaceGram/Strings` | SpaceGram-owned localization resources. |

Upstream edits use nearby `// MARK: NAGRAM` markers as required by the repository guide. See [the architecture map](SpaceGram/SPACEGRAM_ARCHITECTURE_AUDIT.md) and [integration hook notes](SpaceGram/SPACEGRAM_HOOKS.md).

## Defaults and boundaries

Ghost Mode, delayed send, Read on Interact, the formatting button, Media Archive, automated inline-bot rules and custom message actions are opt-in. The SpaceGram master switch does not fabricate Telegram server history or bypass membership, paywalls, authentication or resource authorization.

Media Archive stores only complete resources already available to the account. It uses account-derived roots, resource identity deduplication, validated temporary writes and bounded cleanup. It does not recover resources that were never downloaded.

Outgoing translation is per account and chat, defaults off, and preserves the draft on errors or empty results. Standard Telegram `@bot query` behavior remains native.

## Build and validation

The supported build entry point is `build-system/Make/Make.py`; detailed signing modes and device preflight are in [docs/build.md](docs/build.md). A full iOS build requires macOS, the pinned Xcode version and the appropriate signing configuration.

The manually triggered [SpaceGram iPhone Test Build workflow](.github/workflows/spacegram-ios-test.yml) runs portable checks and the SpaceGram XCTest target on `macos-15` with the repository-pinned Xcode. A teardown-only XCTest SIGTRAP is retried at most once, and only when the first attempt proves zero XCTest failures plus signal 5 and a non-zero wrapper exit. Real test failures are never ignored.

Windows can run the portable validation scripts, but it cannot certify iOS compilation, signing, installation or device behavior.

## Credits and independence

[Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) provides the upstream client foundation. Retained Nagram-iOS-derived code keeps its copyright, attribution and compatibility names; see [BRANDING.md](BRANDING.md).

SpaceGram is unofficial and independent. It is not affiliated with, endorsed by, or an official product of Telegram or Nagram.
