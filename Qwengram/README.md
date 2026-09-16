# Qwengram

`Qwengram/` contains Qwengram-only features. Qwengram is a standalone Telegram
iOS client; the `Nagram/` directory is legacy code currently retained only
where existing Telegram integration still requires it. New Qwengram work must
not depend on that layer.

Keep the architecture layered:

```text
Official Telegram iOS modules
↓
Qwengram custom modules
```

If a future upstream modification is unavoidable, mark it with:

```swift
// MARK: QWENGRAM
```

Implemented modules:

- SettingsSignal
- SettingsUI
- Bots (`QwengramBots`)
- AI (`QwengramAI`) foundation with Qwen provider support

QR Tools is the first functional Bots Hub utility: it generates QR codes locally
on-device. No bot-network execution or integration exists yet.

Qwen credentials are stored in Keychain. Qwen Assistant is the first functional
AI entry and requires a user-supplied Qwen API key. It supports streaming text
responses; its conversation remains in-memory only. Attachments and persistence
are not implemented.

Summarizer is functional and uses the configured Qwen provider. Submitted text
and generated summaries remain in-memory only.

Translator is functional and uses the configured Qwen provider. Source text and
translations remain in-memory only; its initial target-language list is
intentionally small.

Planned modules:
- Privacy
- History
- Media
