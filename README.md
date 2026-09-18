[English](README.md) | [Русский](README_RU.md)

# Qwengram

**An experimental, open-source, unofficial Telegram client for iOS.**

Qwengram explores a client with more user control, integrated AI, useful built-in tools, and a cleaner experience for people who want more from Telegram. It uses Telegram infrastructure and protocol through Telegram-iOS; it is not a new messaging network.

Qwengram is built as Telegram-iOS plus a Qwengram product layer. Selected inherited implementations remain as compatibility modules owned under `Qwengram/Enhancements`; Nagram is a historical source of code, not the architectural upstream. See [the current project audit](QWENGRAM_PROJECT_AUDIT.md) for source-verified features and limitations.

## Why Qwengram exists

Telegram already provides a powerful messaging platform. Qwengram explores how additional privacy controls, AI-assisted workflows, utilities, message actions, and power-user settings can fit into that experience.

The immediate priority is quality: compile, sign, install, and test the existing MVP on a real iPhone, fix the problems found there, and then expand major features.

## Architecture

```text
Telegram-iOS upstream
    ↓
Qwengram (features, retained enhancements, integration hooks)
```

| Layer | Responsibility |
| --- | --- |
| Telegram-iOS | Original upstream application and platform foundation, including Telegram integration. |
| Retained enhancements | Selected inherited implementations under Qwengram ownership; compatibility names and storage keys are preserved. |
| Qwengram | Independent custom product layer developed in this repository. |

Qwengram-specific code should primarily live under `Qwengram/`. Inherited implementations live in `Qwengram/Enhancements/`; attribution and stable storage keys remain intact.

Unavoidable Telegram/Nagram integration points use `// MARK: QWENGRAM` and are recorded in the [upstream hook notes](Qwengram/QWENGRAM_HOOKS.md). The hooks connect settings navigation and message actions to Qwengram controllers.

## Current feature overview

**Implemented** means present in the inspected source, not certified for production or proven on a physical iPhone. The overall product remains experimental. **Planned** entries have no working implementation yet.

Locations below are relative to `Qwengram/`.

| Feature | Status | Location | What it does |
| --- | --- | --- | --- |
| Qwengram Settings | Implemented | `SettingsUI/QwengramSettingsController.swift` | Separate settings page with toggles and tool navigation. |
| Bots Hub | Implemented | `Bots/`, `SettingsUI/QwengramBotsController.swift` | Categorized launcher for internal tools. |
| QR Tools | Implemented | `SettingsUI/QwengramQRToolsController.swift` | Generates a QR image locally from text. |
| Qwen Assistant | Implemented | `SettingsUI/QwengramQwenAssistantController.swift` | Text conversation with Qwen. |
| Streaming responses | Implemented | `AI/QwengramQwenProvider.swift` | Delivers incremental text to the assistant UI. |
| Stop Generating | Implemented | Assistant controller and Qwen provider | Cancels the assistant stream and retains received text. |
| AI Settings | Implemented | `SettingsUI/QwengramAISettingsController.swift` | Saves provider settings and removes the API key. |
| Secure Qwen API key storage | Implemented | `AI/QwengramAIKeychain.swift` | Stores the user-supplied key in iOS Keychain. |
| Configurable Qwen model | Implemented | `Settings/QwengramSettings.swift` | Stores a model identifier; default: `qwen-plus`. |
| Summarizer | Implemented | `SettingsUI/QwengramSummarizerController.swift` | Summarizes explicitly submitted text. |
| Translator | Implemented | `SettingsUI/QwengramTranslatorController.swift` | Translates text into one of eight target languages. |
| Telegram message → Qwengram AI | Implemented | Documented TelegramUI hook; `SettingsUI/QwengramMessageAIController.swift` | Opens a local review screen with selected text. |
| Ask Qwen | Implemented | Message AI and assistant controllers | Prefills the assistant input; sending remains explicit. |
| Summarize message | Implemented | Message AI and summarizer controllers | Prefills the summarizer without starting a request. |
| Translate message | Implemented | Message AI and translator controllers | Prefills the translator without starting a request. |
| Ghost Mode, Message History, Media Archive | Planned | Disabled settings placeholders | Reserve space for future functionality. |

## Qwengram Settings

A separate Qwengram entry in the app's Settings opens the custom settings page. It currently exposes:

| Setting | Default | Current behavior |
| --- | --- | --- |
| `qwengramEnabled` | `true` | Stores the “Qwengram Enabled” preference. It is not currently a universal gate for every Qwengram entry point. |
| `botsHubEnabled` | `true` | Controls whether “Open Bots Hub” is enabled on this settings page. |
| `qwenModel` | `qwen-plus` | Stores the model identifier edited through AI settings. |

These preferences use local `UserDefaults.standard`. The `SettingsSignal/` layer emits initial toggle values and observes `UserDefaults.didChangeNotification`, filtering repeated values so the settings UI updates without polling.

The AI section opens **Qwen Provider**. **Ghost Mode**, **Message History**, and **Media Archive** are disabled “Coming soon” placeholders. Global gating behavior may evolve as development continues; the toggles should not be treated as a comprehensive privacy switch.

## Bots Hub

Bots Hub is currently Qwengram's internal tool and assistant launcher, not a generic remote bot execution framework.

| Category | Current entries |
| --- | --- |
| AI | Qwen Assistant, Summarizer, Translator — functional. |
| Media | Media Tools — disabled placeholder. |
| Utilities | QR Tools — functional; Reminders — disabled placeholder. |
| Custom | Shown as “My Bots”; Add Bot is a disabled placeholder. |

The catalog holds descriptors such as title, category, and enabled state. Enabled entries route to local Qwengram controllers. Remote bot execution and user-added bots are not implemented.

## QR Tools

Open **Qwengram Settings → Open Bots Hub → QR Tools**, enter text, and tap **Generate QR**. The generated image appears on the same screen. Empty input and generation failures produce an error message.

Generation uses CoreImage's `CIQRCodeGenerator` with UTF-8 text and happens entirely on the device. It requires no network request. The current tool generates and displays QR codes; it does not add a scanner or a dedicated export workflow.

## Qwen AI integration

The AI layer separates message types, errors, provider interfaces, Keychain access, and the Qwen implementation:

- `QwengramAIMessage` represents system, user, and assistant messages.
- `QwengramAIProvider` exposes non-streaming `generateText`.
- `QwengramAIStreamingProvider` exposes `streamText`, with a cancellable `QwengramAIStreamingTask`.
- `QwengramQwenProvider` implements both interfaces using `URLSession`.

The current implementation targets Alibaba Cloud Model Studio / DashScope's OpenAI-compatible chat-completions API. Its source-defined default endpoint is:

```text
https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
```

The default model is **`qwen-plus`**. **Qwengram Settings → AI → Qwen Provider** lets the user enter another model identifier. The endpoint can be supplied when constructing the provider in code; the current settings UI does not expose an endpoint editor or provider picker.

Requests use JSON messages and Bearer authentication. Qwen Assistant uses streaming; Summarizer and Translator use non-streaming requests. The provider interfaces support separation of concerns, but multiple selectable AI providers are not currently implemented.

## API key security

The Qwen API key is supplied by the user and stored through iOS Keychain, not embedded in source or saved in ordinary UserDefaults. The Keychain item uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The inspected Qwengram AI paths do not intentionally log the key.

The settings screen provides a password-style input, **Save**, configuration status, and **Remove API Key**. A blank key field can leave the existing key unchanged when saving a model. “Configured” indicates a stored key; it is not a successful provider connectivity test.

| Credential | Purpose |
| --- | --- |
| Telegram API ID / API hash | Build and Telegram application/authentication configuration. The test workflow reads repository secrets. |
| Qwen API key | Optional AI requests made by Qwengram at runtime. The user supplies it in the app. |

These credentials are separate. Do not put actual credential values in source, public documentation, or issue reports.

## Qwen Assistant

1. Open **Qwen Assistant** from Bots Hub, or **Ask Qwen** from a message's local AI review screen.
2. Write or edit the input and press **Send**.
3. The controller validates non-empty input, the stored key, and the configured model.
4. It sends the current in-memory conversation, including previous user and assistant messages, to Qwen.
5. Incoming text progressively updates the assistant response.
6. **Stop Generating** cancels the active stream. Text already received remains in the conversation; an empty assistant placeholder is removed.

The dismissal handler also stops an active generation. Network, HTTP, decoding, and empty-response failures are surfaced to the user.

This is a temporary text conversation, not permanent chat storage. There are no attachments or persisted conversation history. The controller does not implement automatic conversation truncation, so provider limits can affect longer sessions.

## Summarizer

Open **Summarizer**, paste or type text, review it, and press **Summarize**. Opening it from a message prefills the same input field.

It reuses the configured Qwen model and Keychain key, sending the supplied text with a summarization instruction. It does not scan chats automatically. The result appears after the non-streaming request finishes.

Input and result stay in controller memory. Starting another summary clears the previous result; there is no persisted summary history or Stop Generating control on this screen.

## Translator

Open **Translator**, provide or review the text, select a target language, and press **Translate**. The source-language row is fixed to **Auto Detect**: the model infers the source language from the submitted text, with no separate local detection step.

The current target list is **English, Russian, Chinese, Spanish, German, French, Japanese, and Korean**. English is initially selected.

Translation uses the existing Qwen provider, model, and Keychain key. Input and result remain in memory, and a new request clears the previous result. This screen uses non-streaming generation and has no Stop Generating control.

## Telegram message integration

```text
Long-press an eligible normal text message
    ↓
Qwengram AI
    ↓
Local review/action screen
    ↓
Ask Qwen / Summarize / Translate
    ↓
Review or edit the prefilled tool input
    ↓
Explicitly press Send / Summarize / Translate
```

The hook checks for a single message, non-whitespace text, and no secret media; its surrounding branch excludes expired content. The checked-in hook does not explicitly exclude all secret-chat text, so a blanket “never available in secret chats” guarantee would be inaccurate.

**Opening the Qwengram AI menu sends no message content to the AI provider.** Selecting a tool also only opens a prefilled controller. A request starts only after the user presses the tool's execution button.

This deliberate boundary separates local inspection from external AI processing. The review screen passes text into the tool; it does not automatically upload a whole conversation.

## Streaming and cancellation

The Qwen provider requests Server-Sent Events (SSE). It buffers incoming bytes, assembles `data:` events, decodes incremental `delta.content`, and treats `[DONE]` as successful stream completion. A connection that ends without that marker is reported as an unexpected end.

A serial state queue coordinates parsing, cancellation, and completion. A completion guard prevents terminal callbacks from being delivered more than once. Finishing clears buffers, cancels the task, and invalidates the stream session.

The assistant controller tracks a generation identifier. Stopping advances that identifier, so callbacks from an older generation cannot change the current conversation. UI updates run on the main queue and check controller visibility. These safeguards are implemented in source; real-device validation remains part of the MVP work.

## Privacy model

| Operation or data | Current boundary |
| --- | --- |
| Open message AI menu or choose a tool | Local review/navigation; no AI request. |
| Execute an AI action | Submitted text and relevant assistant conversation context go to Qwen. |
| Qwen API key | Persisted in iOS Keychain and used to authenticate provider requests. |
| AI input, conversations, and results | Kept in memory by the current controllers; no persistent AI history. |
| QR generation | Local CoreImage processing; no network dependency. |
| Upstream integration | Small documented hooks into Qwengram controllers. |

These statements describe the inspected Qwengram features, not a claim that the entire Telegram client is offline or “completely private.” Telegram continues to communicate with its infrastructure, and optional AI functions communicate with Qwen. Local in-memory handling does not establish the external provider's retention policy or guarantee immediate memory erasure.

## Media and ephemeral content

Ordinary media, cache, and archive management are roadmap areas. **Media Tools** and **Media Archive** are currently placeholders, not working archive features.

Planned media work concerns ordinary media handling. Bypassing sender-selected view-once, self-destruct, or ephemeral-media protections is not a Qwengram feature advertised here.

## Current iPhone development workflow

```text
Windows development
    ↓
Git push
    ↓
GitHub repository
    ↓
GitHub Actions macOS runner
    ↓
Xcode + Bazel
    ↓
ARM64 iPhone IPA
    ↓
Download to Windows
    ↓
Personal signing / sideloading
    ↓
Physical iPhone testing
```

Normal local coding can happen on Windows without owning a Mac. The GitHub-hosted macOS runner supplies Apple's iOS/Xcode toolchain for compilation. Signing and installation remain separate steps.

The manually triggered [Qwengram iPhone Test Build workflow](.github/workflows/qwengram-ios-test.yml) checks out `qwengram/main`. On success it publishes **Qwengram-iPhone-test**, containing `Telegram.ipa`. The workflow also defines a build-failure log artifact.

See the [iPhone test build guide](Qwengram/IOS_TEST_BUILD.md) for setup and required repository secret names. An unsigned IPA is not directly installable, and artifact creation alone does not prove successful signing, installation, or runtime behavior.

## Build configuration

| Item | Current test pipeline |
| --- | --- |
| Target | Physical iPhone ARM64, `debug_arm64`; app target `Telegram/Telegram`. |
| Build tooling | Bazel through `build-system/Make/Make.py`. |
| Runner | `macos-26`, with Xcode selected and checked against `versions.json`. |
| Test bundle identifier | `com.badmaaan.qwengram`. |
| Output | Unsigned `Telegram.ipa`. |
| Extensions and provisioning | Both disabled by this existing unsigned CI workflow. |
| Apple signing material | No Apple certificates, profiles, Apple IDs, or passwords imported by the workflow. |

This table describes the existing test pipeline; its unsigned configuration is not a recipe for a fully signed device build. Personal installation needs a suitable signing/provisioning process. The workflow does not establish a minimum supported iOS version, so this page makes no minimum-version claim.

## Current development status

Qwengram is under active development. The order of work is:

1. **First:** get the existing MVP compiled, signed, installed, and tested on a real iPhone.
2. **Then:** fix real-device bugs and stabilize the current tools.
3. **After that:** expand major privacy, history, and media features.

Source implementation and workflow definitions are not evidence of a completed real-device validation cycle.

## Roadmap

These are planned directions, not delivery promises or claims of available functionality.

| Area | Planned work |
| --- | --- |
| Privacy | Ghost Mode; additional privacy and user-control options. |
| Messages | Edited-message history; deleted-message history where technically and legally appropriate; richer context actions. |
| Media | Improved ordinary media, cache, and archive management. |
| Bots | Additional utilities; a richer Bots Hub; custom bot/tool support. |
| AI | Improved Telegram context integration; provider/model improvements; richer assistant workflows. |
| Product | Complete Qwengram branding and an independent icon; Settings/UI polish; improved build, signing, and installation workflow. |

## Repository structure

```text
Qwengram/
├── AI/
├── Bots/
├── Core/
├── Settings/
├── SettingsSignal/
├── SettingsUI/
├── README.md
├── QWENGRAM_HOOKS.md
└── IOS_TEST_BUILD.md
```

| Path | Responsibility |
| --- | --- |
| `Qwengram/AI/` | Provider interfaces, messages, errors, Qwen networking, and Keychain access. |
| `Qwengram/Bots/` | Tool categories, descriptors, and the built-in catalog. |
| `Qwengram/Core/` | Product identity constant, including the Qwengram display name. |
| `Qwengram/Settings/` | UserDefaults-backed toggles and model preference. |
| `Qwengram/SettingsSignal/` | Reactive updates for the two boolean settings. |
| `Qwengram/SettingsUI/` | Settings, launcher, QR, AI, and message-review controllers. |
| `Qwengram/Enhancements/` | Retained inherited functions, with documented compatibility identifiers. |
| `Telegram/`, `submodules/` | App targets and upstream libraries. |
| `build-system/` | Existing build tooling. |

The [module overview](Qwengram/README.md), [hook notes](Qwengram/QWENGRAM_HOOKS.md), and [test build guide](Qwengram/IOS_TEST_BUILD.md) provide focused development references.

## Development philosophy

Keep Qwengram isolated where possible, minimize invasive upstream changes, and document unavoidable hooks. Preserve the ability to update or rebase against upstream without hiding where inherited code came from.

Contributions should be focused, distinguish implemented behavior from placeholders, and audit privacy-sensitive paths such as the transition from local review to network requests. Validate the current MVP before aggressively expanding scope, and keep the English and Russian documentation aligned.

## Upstream projects and credits

- [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) provides the original client foundation.
- **Nagram-iOS**, NextAlone, and its contributors contributed the retained inherited implementations. The related Android project is [Nagram](https://github.com/NextAlone/Nagram).
- **Qwen / Alibaba Cloud Model Studio** provides the external AI service targeted by the current Qwen implementation.
- **Qwengram contributors** develop this repository's custom layer and tools.

Inherited copyright and brand notices are preserved in [BRANDING.md](BRANDING.md). The obsolete product README has been removed; current build instructions remain in `docs/build.md`.

The archive is a historical document. Its relative paths still assume the repository root and are intentionally unchanged; for its local references, use [BRANDING.md](BRANDING.md) and [docs/build.md](docs/build.md) from the root.

## Licensing, trademarks, and independence

Upstream code and third-party components retain their respective licenses and copyrights. This documentation does not introduce a new license or claim ownership of inherited code.

Nagram-iOS-specific source and materials retain attribution to NextAlone and Nagram-iOS contributors. Nagram icon artwork is copyright MaitungTM, all rights reserved. Nagram names and assets, Telegram names and trademarks, and Qwen/Alibaba names remain with their respective owners. See the existing [branding policy](BRANDING.md) for inherited notices.

Qwengram uses its own project identity. The app displays Qwengram and no longer bundles Nagram icons. A distinct Qwengram icon remains roadmap work; the existing Telegram asset catalog is used temporarily. Source licenses do not grant trademark rights, and Qwengram distributions must not imply official Telegram or Nagram affiliation.

**Qwengram is unofficial and independent. It is not affiliated with, endorsed by, or an official product of Telegram, Nagram, Alibaba, or Qwen.**
