# SpaceGram internal migration audit

Date: 2026-09-19. Workspace root remains `C:\Project\Qwengram`.
Baseline HEAD: `8ab2f718f66543e778ee51f635c63d0fbf6bbae2`, branch `qwengram/main`.
All changes are uncommitted. The pre-existing branding/appearance changes and
the user's `qwengram_run7_fix.patch` were preserved. No runtime user data was
opened. Migration code below still requires execution on macOS/iOS fixtures.

## Rename map

| Previous | Current |
| --- | --- |
| `Qwengram/` product source tree | `SpaceGram/` |
| `Qwengram*` owned Swift types/modules | `SpaceGram*` |
| `qwengram*` owned camel-case helpers/properties | `spaceGram*` |
| Settings section enum case `qwengram` | `spaceGram` (same position/item IDs) |
| `//Qwengram/<package>:Qwengram<target>` | `//SpaceGram/<package>:SpaceGram<target>` |
| `Tests/QwengramMediaArchiveTests` | `Tests/SpaceGramMediaArchiveTests` |
| `QwengramLocalizable.strings` and resource/table/module | `SpaceGramLocalizable.strings` and matching loader/targets |
| Owned localization keys `Qwengram.*` | `SpaceGram.*` |
| `QWENGRAM_HOOKS.md` | `SpaceGram/SPACEGRAM_HOOKS.md` |
| `tools/check_qwengram_consistency.py` | `tools/check_spacegram_consistency.py` |
| CI temporary cache/artifact/config paths | `spacegram-*` |

The inventory identifies **79 renamed type declarations** and 45 renamed Swift/
localization files, including existing test files. The directory moves also carry
the retained enhancement implementations and historical audits. There is one
product source tree, not two implementations. `SpaceGramAppearance` already had
its final name and was retained.

Detailed maps: [migration map](SpaceGram/audits/overnight-migration-map.json),
[current targets](SpaceGram/audits/spacegram-targets.tsv).
Examples include Settings, GhostPolicy, Product, HistoryStore, HistoryRecord,
HistoryMessageKey, MediaArchive, ConversationStore, AIKeychain, QwenProvider,
PrivacyPolicy and every owned controller. Telegram, Qwen, Apple APIs and active
Nagram module identities were not renamed.

## UserDefaults

`SpaceGramMigrationCoordinator` in the new Foundation/Darwin-only Migration
module runs before the shared settings object exposes migrated preferences.

- Actual existing keys use lower-case `qwengram.settings.*`; their destination is
  `spacegram.settings.*`. The coordinator also supports capitalized `Qwengram.*`
  to `SpaceGram.*` compatibility entries.
- A destination object, including `false`, always wins. Only absent destinations
  are copied. Values are read back before recording migration version 1.
- Legacy preferences are **retained**, because UserDefaults offers no durable
  write acknowledgement. The version marker is diagnostic, never a skip guard;
  a partial migration is retried safely on the next settings initialization.
- Native/Nagram preferences and iCloud keys are untouched. Defaults and Ghost
  settings remain device-wide, as before; they were not silently made per-account.
- The main app mirrors the effective master switch into its existing app group.
  Extension feature gates and Notification Service read this mirror; they cannot overwrite it from their own
  standard defaults domain. Existing privacy policy choices remain saved.

## Keychain

New service: `com.spacegram.ai`; legacy service: `com.qwengram.ai`.
The scoped account string remains `qwen.api-key.<Telegram account Int64>`.

Load order is new scoped entry, old scoped entry, then the historical unscoped
entry. Migration writes the new scoped entry, reads it back and compares it,
and only then attempts old-entry deletion. Lookup/write/verification failures
do not delete the legacy secret. A successfully written new entry wins on retry,
even if old deletion previously failed. Operations are serialized in process.

The old unscoped key retains its documented first-account ownership semantics.
An add-only Keychain owner marker prevents another account claiming that key
after an interrupted migration or failed deletion. A failed first claimant can
retry; another account must configure its own key. Explicit deletion clears
legacy scoped entries before the new entry, preventing resurrection. The owner
marker contains an account identifier, never the secret.

Accessibility remains `WhenUnlockedThisDeviceOnly`. No API keys, Authorization
headers or credential material are logged or serialized into conversation JSON.
Retained enhancement translation credentials are a separate unchanged contract.
Closure-injected migration tests exercise failures; real Security.framework
queries, entitlements and concurrent extension behavior still need iOS tests.

## History and media storage

**History itself does not require a file migration.** It remains in collection
**1009** of each account's Postbox, with the same 16-byte big-endian message key,
schema v1/v2, Codable field names, revision/event limits and asset UUIDs. Swift
type names are not embedded in these JSON payloads. No collection was replaced
and no second database was introduced.

Media root moves from `qwengram-media-v1` to `spacegram-media-v1`, beside that
account's MediaBox. Conversation root similarly moves from
`qwengram-conversations-v1` to `spacegram-conversations-v1`.

Before first storage access, the coordinator locks `.spacegram-migration.lock`
in the existing account parent and performs a same-parent POSIX rename. It never
copies individual manifests away from their payloads. Restart sees either the
old directory or the renamed directory. The lock serializes migrations by new
processes. Missing account parents are not recreated; symlink roots are rejected.
These operations run on the existing media/conversation utility workers.

If both roots already exist, neither is merged, overwritten or deleted.
Storage reports a conflict and requires backup/reconciliation before retrying.
This state is not produced by the atomic rename, but can occur after manual
restores or running an old binary after upgrade. **Downgrade and simultaneous
old/new binaries are not supported migrations.** Back up fixture data before
upgrade/downgrade testing. No reverse migration is provided.

Media manifests/policy remain version 1; binary UUIDs, checksums, file protection,
relative names, retention and reference ownership stay intact. History references
therefore continue to address the same asset after moving the directory.
Default limits remain 512 MiB/account, 128 MiB/file, 1,000 assets and 30 days.
Existing `.partial` files move with the directory and existing maintenance deals
with them. Missing/corrupt/future data keeps the previous refusal/isolation rules.
Preview names now use `spacegram-preview-`; cleanup still recognizes old previews.

Conversation remove/clear also migrate **before** deletion, so clearing before
the first list operation cannot resurrect old conversations. Schema v1/v2,
100-conversation and 1 MiB/file limits remain. API context trimming does not
remove saved messages.

## Deliberately retained compatibility

| Contract | Reason |
| --- | --- |
| `qwengram-privacy-v1.json`, `qwengram.privacy.notification.v1.<account>` | Existing per-account policy and extension mirror; no benefit from another synchronous file migration in this pass |
| CI `com.badmaaan.qwengram`, `QWENGRAM_TELEGRAM_API_*`, branch/workflow identity | Signing, deployed CI secrets and branch contracts; not product UI |
| Checkout root, existing user patch, historical audit names/text | Explicitly retained user filesystem/artifacts and provenance |
| Legacy settings/service/directory strings and test fixtures | Upgrade compatibility |
| Nagram enhancement symbols, settings, deep links, provider identifiers | Active consumers, attribution and compatibility |

Per-line classifications A–E are in
[remaining-qwengram-references.tsv](SpaceGram/audits/remaining-qwengram-references.tsv).
Current Swift identifiers, imports, product BUILD labels and localization lookup
keys no longer use Qwengram. Permission prompt leftovers were also fixed.

## BUILD, localization and signing

All existing owned BUILD packages and their consumers use the new labels.
HistoryIntegration remains a filegroup compiled inside TelegramCore, preserving
the dependency direction. Migration is shared by Settings, AI and MediaArchive;
Privacy depends on Settings for the effective master gate. HistoryUI now reuses
Telegram TextFormat. Tests remain included by `Tests/AllTests`.

Five localization catalogs and the loader/resource bundle were renamed together.
EN/RU static key coverage and duplicate-key checks pass; the new context controls
and media migration-conflict message have EN/RU translations. Existing English-only
error/details wording remains UI localization debt. Active Nagram keys and
attribution remain. Current READMEs, agent guides and hook notes use new paths.
Older audits are explicitly historical and point to these current reports.

Bundle identifiers, URL schemes, entitlements, real profiles, app groups, signing
inputs and extension names were not renamed. This migration needs the same app
identity to access existing defaults, Keychain and account directories. Neither
icon artwork nor its Default/Alternate identifiers changed.

## Validation and limitations

Added **23 XCTest methods** (47 total): migration failure/retry and account cases,
history query behavior/stable identity, migrated media preview, migrated AI
deletion/clear, context bounds and the extension master gate. None were run on
Windows. Existing tests still cover history schemas, reference preservation,
media corruption/limits/cleanup and conversation CRUD/schema/account separation.

Portable checks passed: 773 BUILD files, 74 product/test Swift sources, five
catalogs; 32 plist inputs (30 complete files plus two valid upstream XML fragments),
193 asset JSONs, 293 file references, four YAML definitions, source inclusion,
old-reference checks and `git diff --check`. Advisory grammar findings are
classified in the [overnight audit](SPACEGRAM_OVERNIGHT_AUDIT.md).

No full Bazel graph analysis, Swift compilation, XCTest, actool, simulator,
Keychain runtime, signing, device install or network-level Ghost/TTL validation
was possible on this Windows host. These are explicit next gates, not implied
successes of static validation.
