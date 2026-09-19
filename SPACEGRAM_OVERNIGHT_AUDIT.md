# SpaceGram overnight engineering audit

Date: 2026-09-19. Windows workspace: `C:\Project\Qwengram`.
Branch: `qwengram/main`. HEAD: `8ab2f718f66543e778ee51f635c63d0fbf6bbae2`.

## Executive summary

The product source tree is now **SpaceGram**, with migrated own Swift names,
BUILD labels, resource tables and localization keys. Data migrations cover
preferences, Qwen Keychain entries, media roots and persistent conversation
roots without changing History's account Postbox identity or asset UUIDs.

This pass found that the requested History browser, media management and
persistent AI were already implemented. They were retained and reviewed, then
extended with testable History queries, native formatting for saved text,
configurable API context limits and missing master-switch privacy gates.
Five remaining old-brand iOS permission strings were corrected.

Phase A is implemented, with explicit legacy contracts retained. Phases B/C
retain the existing product feature set with the above improvements; runtime/UI
acceptance remains pending. Privacy work was limited to the master gate. No
new security framework, media player or parallel archive was created.

The 51 entry-dirty tracked paths and untracked branding/artwork were respected.
All saved baseline files still exist at their mapped paths. The user's patch
SHA-256 matches the entry snapshot. A normalized comparison of pre-pass upstream
Swift shows only one new behavior change: master gating for outgoing photo
sanitization. Other new upstream edits rename product references/markers/imports.
Pre-existing upstream branding/badge changes were not reverted.

`jj st` and `jj log -r '@' -n 1 --no-graph` were attempted, but jj is absent.
Only the read-only Git inspection authorized by the request was used. No commit,
staging, push, tag, release, workflow dispatch, remote mutation, dependency
update or provisioning modification occurred. New/renamed files are untracked
until the operator includes them; **a plain `git diff` alone is not a complete
transfer artifact for the Mac**. Transfer the entire changed working tree.

## Current architecture

Telegram-iOS is the base. `SpaceGram/` owns Core, Settings/SettingsSignal,
SettingsUI, Strings, HistoryStorage/HistoryUI, MediaArchive, AI, Privacy,
Appearance and the shared Migration module. `HistoryIntegration` remains a
source filegroup inside TelegramCore; Telegram hooks call this small boundary.
Retained Nagram-derived implementations stay under `SpaceGram/Enhancements`.

The application and six extensions retain their bundle/signing contracts.
The root directory is intentionally still named Qwengram.

## Migration status

79 owned type declarations and 45 Swift/resource filenames were renamed.
The product/test directory moves, source globs, modules, imports, target labels,
visibility edges and current documentation were updated. Own settings helpers
use `spaceGram*`; lookup keys/table use `SpaceGram.*`/`SpaceGramLocalizable`.

See [the migration audit](SPACEGRAM_INTERNAL_MIGRATION_AUDIT.md) for ordering,
failure behavior and retained contracts. Legacy preference copies remain;
Keychain deletion requires successful read-back; directory moves are atomic
under an account-parent lock. Two divergent old/new directories fail closed
and remain available for manual recovery. The app never chooses an archive by
silently discarding the other one.

Old privacy filenames/mirrors, bundle IDs, CI secrets/branch/workflow names,
legacy migration fixtures, root path and historical documentation remain.
There are no old active product source paths, modules, types or localization
lookups. [The reference inventory](SpaceGram/audits/remaining-qwengram-references.tsv)
classifies remaining matches as A compatibility, B history/explanation,
C preserved root path or D external contract; E requires review and must be empty.

## History status

Existing browser: search saved text/filenames/peer/author, Edited/Deleted/Media
and chat filters, chronological sorting, lightweight preview, event/media status
and 200-row display pagination. Scanning/filtering runs in the account Postbox
transaction, not on the main thread. This remains a bounded full collection
scan, not a new indexed search database.

The shared query helper now has focused tests for composed filters, Cyrillic/
case-insensitive search, missing asset evidence and stable binary identity.
Details show revisions, timestamps, event types, previous text and metadata.
Saved bold/italic/code/pre/underline/strikethrough now use Telegram TextFormat
with validated UTF-16 ranges. Other entity metadata remains visible. Rendering
is bounded; very large text falls back to plain presentation.

Existing event/revision/message/chat/all-history deletion remains. A complete
survivor scan protects shared assets; unreadable records block detached cleanup.
The context-menu History/Edited/Deleted indicators and their three switches are
preserved. No invasive bubble renderer changes were made. A message already
deleted from Telegram is inspected through the archive, not an invented chat bubble.

## Media Archive status

Account-local archive now migrates to `spacegram-media-v1`. History UUID links,
manifest/policy versions, SHA-256 verification and backup/file-protection rules
are preserved. Limits remain 512 MiB/account, 128 MiB/file, 1,000 assets and 30
days by default. Storage/retention presets, automatic cleanup, usage/count,
manual expiry cleanup and explicit Clear Archive are retained.

Deletion safety still distinguishes unreferenced cleanup from explicit clear
and age/size/count eviction, which can leave History text with an unavailable
asset. Corrupt/future/missing records keep conservative behavior. A new test
checks UUID preview lookup after an old-root migration.

Only complete local files are captured. Secret chats and partial/unreceived
resources remain excluded. Background capture can fail without preventing native
Telegram deletion. Quick Look uses a verified temporary copy; codec support
remains system-dependent, especially Ogg voice. No remote recovery is claimed.

## Ghost Mode status

Source comparison preserved policy behavior while renaming Settings/Signals and
hooks. Master-off restores native automatic behavior; Ghost remains device-wide
and opt-in. Automatic text/content reads, mentions/reactions/polls, live-location
viewing, view increments, read metrics, typing/activity, Stories and presence
remain covered by the existing boundaries. TTL/view-once acknowledgements,
explicit reads and already-accepted operations keep their documented exceptions.

No iPhone packet capture or server-side verification was performed. This is
not a guarantee of invisibility. Repeat tests across accounts and pending
operations, including another logged-in client. See the historical
[Ghost/media audit](SpaceGram/MEDIA_ARCHIVE_AUDIT.md) for protocol boundaries.

## AI status

The existing account-scoped persistent conversation store and list were kept:
create/open/search/rename/delete, updatedAt order, stable messages, selected
model, created/updated timestamps, optional system prompt/context metadata,
schema v1/v2, atomic JSON writes, corrupt-neighbor isolation and bounded storage.
Migration runs before list/save/remove/clear. Limits: 100 conversations and
1 MiB per file. Summarizer/Translator and message actions remain available.

Context is now configurable in Provider settings: 8,000/16,000/24,000 characters,
with up to 64 recent non-system messages and a system-prompt allowance of 4,096
characters. Whole messages are retained; a leading assistant response is removed
when its question falls outside the suffix. The UI shows selected message/
character count and characters÷4 as an explicitly approximate token count.
This is not a tokenizer, model capacity guarantee or billing estimate, especially
for Cyrillic/CJK/code. Full local history is unchanged by request trimming.

Streaming, Stop, Copy, Share, Retry, Regenerate and Delete are retained. Stop
saves a nonempty partial response. The request gate cancels when master-off;
Settings and saved history remain accessible. The bounded existing Markdown
renderer is retained: Telegram's simple Markdown parser supports fewer styles;
the renderer uses native attributed text/Telegram link attributes instead of
adding a dependency. It supports common emphasis/code/links/lists, not all
CommonMark constructs. There is no media upload/attachment implementation.

Known limits remain: some errors are English-only; picker search covers title
and latest-message preview, not all transcripts; empty unsent drafts are not
saved; a storage limit/write failure is reported rather than evicting old chats.
Real Keychain, streaming cancellation, process termination and disk-full behavior
must be exercised on iOS before claiming production readiness.

## Branding/icons

The prepared primary/alternate artwork and 18 renditions per catalog are retained.
Default maps to nil alternate name; Alternate maps to `Alternate` through native
UIApplication binding. BUILD and iPhone/iPad plist names agree. All declared
files exist; primary/alternate RGB PNG dimensions pass the existing checker.
Five old-brand permission descriptions in the main Info.plist were fixed.
Actual actool compilation and icon switching/relaunch persistence are pending.

## Nagram debt

Eight active enhancement modules remain: Settings, SettingsSignal, SettingsUI,
Translate, LinkMetadata, MediaMetadata, TelegramSettingsCloudSync and Demo.
Their import consumers remain 71/11/2/4/3/2/1/1 respectively. The inventory has
45 enhancement BUILD edges. Active preference/iCloud/translation Keychain keys,
deep links, metadata provider IDs, module names, attribution and required
`// MARK: NAGRAM` rebase markers remain.

No newly proven dead implementation was found that warranted deletion in this
pass. Existing role-badge removal was preserved. Registration-date and remote
metadata services remain external dependencies; renaming their names would not
remove them. See [the classified registry](SpaceGram/audits/remaining-nagram-references.tsv).

## Tests

**23 new XCTest methods; 47 total; zero executed on Windows.**

- 15 migration/master-mirror scenarios: defaults copy/no-overwrite/retry; secret
  new-first/read-back/write/read/delete failures; atomic-root restart, conflicts,
  symlinks, missing account and account isolation; extension master values.
- Four History query/stable-key scenarios.
- Three AI legacy-directory/deletion/context-limit scenarios.
- One migrated media UUID/checksum preview scenario.

Existing tests cover v1/v2 History, media references/corruption/retention/limits,
conversation CRUD/rename/schema/corruption/accounts/size and privacy/sanitizer
behavior. Real Postbox transaction deletion and UI interaction coverage remains
a Mac integration task. Keychain migration failure tests inject closures; they
do not certify the platform Keychain API or its access-group configuration.

## Preflight

Executed on Windows:

| Check | Result |
| --- | --- |
| `python tools/check_spacegram_consistency.py` | PASS: 773 BUILD files, 74 owned/test Swift files, five localization catalogs |
| Source globs/modules/labels, old imports/paths and duplicate source checks | PASS within the static checker scope; no Bazel evaluation claimed |
| EN/RU literal localization coverage, duplicate keys and renamed resource loader | PASS |
| Plists | PASS: 30 full plists and two upstream dictionary fragments imported by AddAlternateIcons.sh |
| Assets | PASS: 193 Contents.json files, 293 declared files; exact primary/alternate dimensions/RGB checked |
| YAML | PASS: three GitHub workflows and .gitlab-ci.yml; syntax only |
| Advisory Swift grammar | 26 existing grammar nodes in eight files; no diagnostics in added sources/tests; details below |
| Baseline mapping and protected patch SHA-256 | PASS; no baseline file missing |
| `git diff --check` | PASS |

`tools/check_spacegram_preflight.py` records details in
[overnight-preflight.json](SpaceGram/audits/overnight-preflight.json).
Existing PyYAML/tree-sitter packages were reused from the previous temporary
audit directory; no dependency was installed. A host without them receives an
explicit skip. No successful full Swift parse or type check is claimed.

### The previous “five warnings”

The previous architecture audit reported five grammar findings within its
changed-file subset, not five Swift compiler warnings. The current whole-tree
scan is larger. Its 26 nodes are:

- Eight missing `!` nodes at valid `()` empty-tuple expressions in ConversationStore
  (3), QwenProvider (2), HistorySettings (1), MediaSettings (1), PrivacySettings (1).
  These existed in the entry source. History browser's two former tuple findings
  disappeared naturally when it began passing context for native rich text.
- One identical tuple grammar gap in retained NagramLLMTranslateProvider.
- Nine parser ERROR nodes for valid `as? Bool ?? true/false` in retained
  NagramBottomBarSettings.
- Eight parser ERROR nodes for valid optional-cast/coalescing expressions in
  retained NagramSettingsSignal (two source expressions reported as several nodes).

These are advisory grammar limitations, not generated-code or proven compiler
errors. The retained implementations were not rewritten to appease the parser.
New code avoids these ambiguous parser shapes. Xcode remains authoritative.

## Known blockers

Windows has no Xcode/iOS SDK, Swift compiler, Bazel iOS toolchain, simulator or
device install path in this session. Full app build, XCTest, asset compilation,
platform storage/Keychain behavior, entitlement correctness, notification app-group
propagation, UI accessibility and real Ghost/TTL traffic remain unverified.

Migration preserves source/data contracts but intentionally changes internal
source API/module names. Downgrading to the old binary does not reverse renamed
directories. Conflicting restored roots require manual backup/reconciliation.
No accounts, archives, credentials or real provisioning inputs were manipulated
during this source pass.

## Recommended first Mac commands

Run from the transferred **complete working tree**. First inspect
`docs/build.md`, especially signing selection, device preflight, workspace inputs
and the chosen signing section. `versions.json` pins Xcode 26.2/Bazel 8.4.2/macOS
26; docs also mention a local 26.5 workaround. Inspect the actual toolchain rather
than silently applying a different machine's overrides.

```sh
jj st
jj log -r @ -n 1 --no-graph
xcodebuild -version
xcrun swift --version
python3 tools/check_spacegram_preflight.py
python3 build-system/Make/Make.py --help
```

Inspect rule/submodule directories for materialized pinned dependencies. Empty
directories are dependency failures. Git recovery commands require their own
explicit authorization under the workspace policy. Restore private build inputs
only from an operator-approved source; do not infer free signing from absence.

First build the **whole app for the simulator**. Preserve any existing
`local.bazelrc`, inspect its local overrides, and use only the simulator flags
shown in `docs/build.md` (`disableProvisioningProfiles` and `disableExtensions`).

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --buildNumber=1 \
  --configuration=debug_sim_arm64 --continueOnError

python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache test \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning
```

The test wrapper targets Tests/AllTests; the product suite specifies an iPhone 17,
iOS 26.2 runner. Install that runtime. UI tests must launch with `--ui-test`.
For simulator installation use the documented uninstall-first flow on an isolated
test simulator; do not uninstall a device whose upgrade data is being tested.

Before a device build, inspect `xcrun devicectl list devices`, Apple Development
identity, main + all six extension profiles, configuration JSON, signing directory,
dependencies and local.bazelrc. Full profiles mean full signing: remove simulator
disable flags and keep all extensions/profiles. Then:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 --configuration=debug_arm64 --continueOnError

xcrun devicectl list devices
unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/spacegram-device
xcrun devicectl device install app --device <UDID> /tmp/spacegram-device/Payload/Telegram.app
xcrun devicectl device info apps --device <UDID>
```

Verify the installed bundle/version in the final listing and launch on the device.
An IPA alone is not a successful device installation. Free Apple ID mode is only
appropriate when complete profiles are genuinely unavailable and that mode is
explicitly requested; it must never disable provisioning profiles.

## Recommended regression checklist

- Upgrade two fixture accounts with different preferences, old scoped/unscoped
  Keychain entries, History v1/v2, shared asset IDs, policy files and AI v1/v2.
  Confirm IDs/content/formatting/timestamps/model/title and account separation.
- Relaunch before/after migration; inject failed writes, locked Keychain, missing
  roots, symlinks, disk-full, corrupt neighbors and conflicting directories.
  Confirm recoverable copies survive and deletes/clear cannot resurrect old data.
- Search/filter/sort History; inspect text/entities, present/missing/corrupt media;
  delete event/revision/message/chat/all; ensure shared assets survive their other
  references and unreadable records conservatively block orphan cleanup.
- Exercise all supported media formats, fully received versus partial/evicted,
  128 MiB and account/count caps, 7/30/90-day cleanup, timed/view-once/server delete,
  pending capture, background/foreground and account removal.
- Stream Qwen against a local fixture provider; Stop/master-off/retry/regenerate;
  verify one completion, persisted partial output, reopen/rename/delete/restart,
  system prompt, context presets, long multilingual input and storage-limit errors.
- Compare Ghost-off native traffic against each enabled policy, explicit reads,
  already-queued operations, TTL exceptions, account switching and second-client
  acknowledgements. Check Stories, typing, presence, mentions, reactions, polls,
  location, counters and metrics separately.
- Disable/re-enable master: stop active capture/AI/tools and metadata sanitizing;
  check notification extension mirror propagation while preserving privacy choices.
  Settings and saved history/data-management must remain accessible.
- Confirm Default/Alternate icons before/after relaunch, EN/RU screens, dark
  appearance, Dynamic Type, VoiceOver, native lock/PIN/biometric fallback and
  notification sender/preview behavior for each account.
