# Retained enhancements

These implementations are now owned within the SpaceGram product layer. They
were inherited from Nagram-iOS (Copyright NextAlone and Nagram-iOS contributors).
This move does not change their license or erase their provenance; see
[BRANDING.md](../../BRANDING.md).

The official base-client upstream is Telegram-iOS. This directory is not a
second upstream or a separately updated fork. Keep new product functionality
in the appropriate SpaceGram module rather than expanding this compatibility layer.

| Package | Why it remains |
| --- | --- |
| Settings | Active preferences, filters, gestures, menu configuration, profile utilities, LLM credentials and iCloud state |
| SettingsSignal | Reactive settings used across Telegram UI components |
| SettingsUI | Existing controls for those features, including translation and layout editors |
| Translate | External and LLM providers used by native translation and translate-before-send |
| LinkMetadata | Link preview and inline bot rules, including the existing external metadata service |
| MediaMetadata | Gallery image/video metadata inspection |
| TelegramSettingsCloudSync | Opt-in synchronization of selected native Telegram preferences |
| Demo | Isolated demo/test startup and account preparation |

`Nagram*` Swift module/type names, `nagram.*` persistent keys, notification names,
Keychain services, deep links and external metadata identifiers are retained
compatibility contracts. Do not globally replace them: storage and URL migrations
need separate tests. The shared string loader was moved to `SpaceGram/Strings`
and renamed to `SpaceGramStrings`; existing `ngI18n` calls and localization keys
remain supported by that single implementation.

The enhancement settings entry is displayed as **SpaceGram · Telegram** alongside
the product's SpaceGram settings. It retains the original navigation cases and
debug long-press action. Removing the entry would make live settings inaccessible.

See [the removal audit](../NAGRAM_REMOVAL_AUDIT.md) for dependencies and limitations.
