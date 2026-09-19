# SpaceGram architecture and legacy cleanup audit

> Historical pre-migration snapshot. The source namespace has since moved to
> `SpaceGram/`; see [the overnight audit](../SPACEGRAM_OVERNIGHT_AUDIT.md) and
> [migration contracts](../SPACEGRAM_INTERNAL_MIGRATION_AUDIT.md).

Date: 2026-09-19. Workspace: `C:\Project\Qwengram`.
Base HEAD: `8ab2f718f66543e778ee51f635c63d0fbf6bbae2`, branch `qwengram/main`.
This pass began with the complete uncommitted SpaceGram branding diff, the new
Appearance module, icon catalog and branding audit. Those changes were preserved.
No commit, staging, push, remote modification or dependency update was performed.

## Result and architectural boundary

The ownership architecture is **Telegram-iOS + SpaceGram**. `Qwengram/` is the
compatibility source namespace for SpaceGram. The earlier cleanup already moved
the useful inherited implementations into this namespace and removed the old
top-level product tree and artwork pipeline. This pass removes the remaining
project-role branding UI and refreshes the previously stale inventories.

This is not a pristine Telegram checkout: the inherited integration patches
remain in TelegramCore/UI and related libraries. Complete independence from
historical external metadata infrastructure has NOT been achieved. Renaming or
deleting every textual reference would break live features and storage contracts.
The remaining references are classified, not claimed to be dead code.

## Changes made in this pass

- Deleted `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/NagramProfileBadge.swift`
  (80 lines): hardcoded external-project developer/sponsor IDs, role mapping and
  a duplicate localization loader used only by those badges.
- Removed the badge control, properties, setup, selectors, layout, hit testing
  and tooltip closure: 115 lines from PeerInfoHeaderNode and 35 lines from
  PeerInfoScreen before the one-line provenance marker. Native Telegram status
  indicators remain unchanged. Global symbol searches found no other consumers.
- Deleted ten dead keys in each of EN/JA/zh-hans/zh-hant (40 entries):
  `Nagram.Title`, `Nagram.ProfileId`, `Nagram.DataCenter`, `Nagram.RegDate`,
  `Nagram.HideTabBarChats`, `Nagram.WideTabBar`, and four `Nagram.ProfileBadge.*`
  keys. The six older labels had no source lookup; dynamic choice prefixes and
  deep-link alias generation were inspected. Active `RegDate.*` messages and
  the `WideTabBar` deep-link alias are preserved. RU had none of the retired keys.
- Preserved historical contributor/sponsor credit in BRANDING.md. Removing role
  advertising from profiles is not removal of source license/attribution.
- Corrected the remaining TestFlight workflow display name to SpaceGram;
  signing configuration, secrets, triggers and upload behavior are untouched.
- Updated current README feature/storage/icon claims, marked older audits as
  historical, and added reproducible dependency/reference/target inventories.
- Strengthened the portable checker for dangling badge symbols, deleted keys,
  actual Info.plist parsing and exact primary-icon PNG sizes/format.

No useful module needed another physical move: all eight already reside in
`Qwengram/Enhancements`. No module was renamed just to reduce the reference count.
No storage format, Keychain contract or behavioral policy was migrated here.

## Current project map

| Area | Ownership and role |
| --- | --- |
| `Telegram/` | Main app, six extensions, Watch support, plist/resource packaging; app target `//Telegram:Telegram` |
| `submodules/` | Telegram foundation (Postbox, Core, UI, signals, rendering, etc.) plus inherited integration hooks; most directories are ordinary tracked sources, not Git submodules |
| `third-party/` | Vendored codecs/native libraries and their notices; source/build inputs, not disposable caches |
| `Qwengram/Core` | SpaceGram product name; internal namespace retained |
| `Qwengram/Settings`, `SettingsSignal` | Device-wide preferences, effective Ghost/feature gates and reactive updates |
| `Qwengram/SettingsUI`, `Bots` | Settings sections, Tools catalog and AI controls; unfinished tools stay disabled |
| `Qwengram/HistoryStorage` | Account-specific Postbox collection 1009, schema v1/v2 decoding, revisions/events |
| `Qwengram/HistoryIntegration` | Source filegroup compiled inside TelegramCore to avoid a Core dependency cycle; edit/delete/TTL capture hooks |
| `Qwengram/HistoryUI` | Search/filter/sort/display pagination, detail, confirmed deletion and Quick Look access |
| `Qwengram/MediaArchive` | Account-local binary storage, manifests, SHA-256 verification, retention, size/count limits and reference ownership |
| `Qwengram/AI` | Qwen HTTP/SSE provider, protected conversation persistence, bounded context, account-scoped API key |
| `Qwengram/Privacy` | Account privacy policies, notification redaction, native App Lock integration and photo EXIF/GPS sanitization |
| `Qwengram/Appearance` | Product list presentation adapter using Telegram night theme; no independent theme engine |
| `Qwengram/Strings` | Single resource loader, five catalogs, shared stable product/enhancement keys |
| `Qwengram/Enhancements` | Eight retained implementation packages listed below; no separate Nagram product root |
| `build-system/`, `buildbox/` | Make.py, toolchain helpers, Bazel rules, generators, build infrastructure and signing templates; not build outputs |
| `MODULE.bazel`, lockfile, `WORKSPACE`, root BUILD, `.bazelrc` | Dependency pinning and Bazel configuration; preserved |
| `Tests/`, `Telegram/Tests/Sources` | Native test/demo targets and isolated UI tests; AllTests includes TgCallsTests and QwengramMediaArchiveTests |
| `.github/workflows` | Manual SpaceGram device build; inherited master CI; signed release/TestFlight workflow. No workflow was run |
| `.gitlab-ci.yml` | Inherited CI definition retained, not assumed unused simply because GitHub is current |
| `scripts/`, `tools/` | LLDB/simulator/build helpers, IPA tools and portable audit/check scripts |
| `docs/` | Build/UI testing instructions, migration log and historical plans; historical provenance retained |
| `.vscode/`, `.xcodebuildmcp/`, `.cursorignore`, `CLAUDE.md`, `AGENTS.md` | Tool configuration/instructions; no user-specific configuration deleted |
| `build-input/` | Empty on this pass; absence does not imply a signing mode |
| `Random.txt` | Unknown tracked user file; retained |

## Retained implementation dependencies

The complete current consumer paths are in `audits/enhancement-imports.tsv` and
`audits/enhancement-dependencies.tsv`; these record imports and Bazel edges,
not speculative reachability claims.

| Module (all under `Qwengram/Enhancements`) | Swift import sites | Why retained |
| --- | ---: | --- |
| NagramSettings | 71 | Persistent enhancement settings, filters, gestures, registration-date helpers, menus, separate translation credentials and cloud preferences |
| NagramSettingsSignal | 11 | Reactive consumers in chat/contact/profile/root UI |
| NagramSettingsUI | 2 | Existing enhancement settings navigation, including old deep links |
| NagramTranslate | 4 | Native/LLM/external translation used by TranslateUI, text processing and send options; not a second Qwen conversation store |
| NagramLinkMetadata | 3 | Link preview rewriting and inline-bot rules; caller settings/UI remain active |
| NagramMediaMetadata | 2 | Existing image/video gallery metadata inspection; not duplicate Media Archive storage |
| NagramTelegramSettingsCloudSync | 1 | SharedAccountContext starts existing Telegram preference/iCloud synchronization |
| NagramDemo | 1 | AppDelegate demo/test startup; seeding is intentionally retained |

Compatibility retained: `nagram.*` defaults/iCloud/cache/translation Keychain,
`Nagram.*` live localization keys, nasettings/deep-link aliases,
`NAGRAM_*` build overrides, extension/signing-sensitive identifiers and rebase
markers. Public types/imports are still named after their historical source.

External dependencies retained explicitly: `@nagram_remote_metadata` supplies
validated cached link/inline-bot rules; registration dates use the existing
`restore-access.indream.app` endpoint. Provider disclosure strings are not
SpaceGram product branding and are not relabelled to hide third-party provenance.
Replacing these services requires a separately reviewed protocol/data migration.

## Storage and feature boundaries

- Ghost settings remain device-wide and opt-in; native timer acknowledgements,
  explicit reads, queued operations and call signaling retain their documented
  semantics. No universal invisibility claim.
- Message History uses collection 1009 in the selected account's Postbox. Search
  scans are off-main; display pagination does not mean indexed storage queries.
- Media is stored beside the account MediaBox in `qwengram-media-v1`; policy and
  manifests remain v1, separate from Telegram cache. Only complete local assets
  are captured. Shared references and unreadable records conservatively affect
  cleanup; Clear Archive is a separate explicit destructive action.
- Qwen conversations use `qwengram-conversations-v1`; service `com.qwengram.ai`
  and account-scoped Keychain suffixes are preserved, including the prior migration.
- Privacy uses `qwengram-privacy-v1.json` and account-scoped app-group policy
  mirrors. App Lock stays Telegram's one native system, with immediate timeout.
- Product dark styling leaves global Telegram theme selection intact. Its
  contrast/navigation/accessibility behavior still needs on-device validation.
- No runtime user data was opened or erased during this source audit.

## Assets, Git and local artifacts

Primary icon is the new SpaceGram catalog with 18 declared renditions, and both
iPhone/iPad Info.plist references point to it. Old Telegram icon catalogs are
retained upstream resources, not assumed disposable. No top-level Nagram
artwork or its deleted Composer script/target has returned.

HEAD and branch remain unchanged. `origin` is BADMAAAN/Qwengram, `upstream` is
TelegramMessenger/Telegram-iOS, `nagram-legacy` is NextAlone/Nagram-iOS. The 13
registered submodules are initialized at their pinned SHAs (no `-`, `+` or `U`
status prefixes). No fetch was required.

At entry the untracked files were Appearance, SpaceGram icon catalog, branding
audit and `qwengram_run7_fix.patch`. This pass additionally creates this audit,
the inventory generator and additional inventory TSV/JSON outputs. The exact
untracked path list is in `audits/spacegram-inventory.json`.
The only ignored artifact reported by Git is `build-system/Make/__pycache__/`;
it was left alone. No repository backup/debug dumps were added. A recovery diff
and hashes are outside the repository in the session's temporary audit directory.
Unknown files and the user's patch were preserved.

## Reference counting and reproducibility

Run `python tools/audit_spacegram_architecture.py` to regenerate inventories.
`audits/spacegram-inventory.json` contains exact totals by category, matching
line count and file count; `remaining-nagram-references.tsv` lists file, line,
occurrence count and classification. Counts include case-insensitive literal
substrings in comments, source identifiers, keys and historical documentation.
They are not a count of independent features or dependencies.

Scope: existing parent-repository tracked and nonignored untracked UTF-8 text.
Generated inventories exclude themselves. Git internals, the user patch,
signing/private inputs, binaries, non-UTF8, symlinks and nested submodule contents
are excluded. Nested dependency repositories are pinned third-party sources, not
SpaceGram cleanup targets. The whole workspace was inventoried by Git and its
top-level directories, with ignored artifacts inspected by names only.

## Validation and remaining debt

- Portable consistency passed: 772 BUILD files, 66 product Swift files, five
  localization catalogs, zero errors. Covers BUILD syntax/known product labels,
  modules/source globs, EN/RU key coverage, resources and exact icon dimensions.
  All three workflow YAML files also parsed using the external validation tools.
- All seven Telegram Info.plist files parsed successfully; all 106 declared
  file references across main-app asset catalogs resolve, with none missing.
- Advisory Swift tree-sitter comparison against HEAD: 22 existing changed/new
  files, zero new findings; five existing grammar findings across four product
  files remain. This is not Swift type checking or a successful full parse.
  Parser/YAML packages were reused from the previous external temporary
  validation directory, not installed into the repository.
- Deleted badge symbols/key consumers: no remaining source callers; the source
  glob naturally excludes the removed file. No separate target was deleted.
- `git diff --check` passed. The protected patch SHA-256 matches the entry
  manifest. Additional changes to entry-dirty files are limited to documentation,
  four localization catalogs and the checker; all pre-existing product Swift,
  Appearance and icon changes are byte-identical to the start of this pass.
- Xcode, Bazel analysis, iOS compilation, XCTest, installation and runtime
  regression checks are not available/performed on Windows.

Next gate: pinned-Xcode full simulator build followed by device validation of
profile header layout (regular/expanded/editing/premium/verified), SpaceGram
icon/appearance, native App Lock, notifications, multi-account archive cleanup,
Qwen persistence and inherited translation/iCloud settings. Only after that,
reduce inherited upstream patches in small functional groups or migrate external
metadata services. Zero textual Nagram references is not a safe acceptance goal.
