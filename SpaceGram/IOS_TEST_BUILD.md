# SpaceGram iPhone test build

Run **SpaceGram iPhone Test Build** manually from the GitHub Actions page. It
checks out the branch selected for the workflow run, builds the physical-device
`debug_arm64` target, and publishes the `SpaceGram-iPhone-test` artifact when
successful.

Configure these repository secrets before running it:

- `SPACEGRAM_TELEGRAM_API_ID`
- `SPACEGRAM_TELEGRAM_API_HASH`

Download `SpaceGram-iPhone-test` from the completed workflow run. It contains
the generated `Telegram.ipa` for development testing.

Only simulator regression tests disable extensions. The device workflow embeds
all extensions, imports the repository's fake signing certificates and uses its
fake provisioning inputs. The resulting IPA is an
intermediate artifact for re-signing, not a verified installable device build.
It cannot validate APNs delivery: a final device build must be signed with a
profile that carries the push entitlement and must embed the notification
service/content extensions. AltStore-style re-signing only supports push when
the final signing profile and installed extension set preserve those capabilities.
It does not disable provisioning profiles. Personal signing and installation
require the separate device preflight documented in `docs/build.md`.

`push-signing-report.json` inspects actual signed entitlement slots and embedded
profiles of the resulting IPA. It does not verify the signature or APNs delivery.
Run `python tools/inspect_spacegram_ipa.py <resigned.ipa>` again on the final
signer's output; original artifact entitlements cannot prove installed entitlements.
