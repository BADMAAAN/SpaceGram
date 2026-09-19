# SpaceGram Branding Audit

## Current cosmic app-icon collection — 2026-09-20

This section supersedes the historical two-icon notes below.

- Default source: `Branding/SpaceGram/IconSources/SpaceGram-Alternate.png`.
- Alternate sources found and connected: `Moon.png`, `Earth.png`, `Mars.png`,
  `Sun.png`, `Saturn.png`, and `Neptune.png`.
- `SpaceGram-Primary.png` was intentionally removed by the product owner and
  was not restored or recovered from history.
- Source files were not edited. Prepared 1024 × 1024 masters are under
  `Branding/SpaceGram/PreparedIcons/`; only crop, proportional Lanczos resize,
  RGB/sRGB normalization, and metadata cleanup were applied.
- Crop bounds in the original 1254 × 1254 pixel coordinates (`left, top,
  right, bottom`) are: Default full canvas `(0, 0, 1254, 1254)`; Moon
  `(130, 117, 1122, 1109)`; Earth `(127, 111, 1122, 1106)`; Mars
  `(130, 118, 1122, 1110)`; Sun `(130, 117, 1121, 1108)`; Saturn
  `(129, 117, 1121, 1109)`; Neptune `(130, 118, 1122, 1110)`.
- Large external black margins were found in all six planet sources and
  removed. The Default source was already full-bleed. The source tile's thin
  edge highlight was retained as artwork; no new mask, rounded rectangle,
  frame, border, inpainting, or generative edit was introduced.
- The generated contact sheet is
  `Branding/SpaceGram/PreparedIcons/SpaceGram-Icon-Contact-Sheet.png`. It is an
  audit-only file and is not packaged by `Telegram/BUILD`.
- Seven catalogs contain 17 current slots each, for 119 app-icon renditions.
  The obsolete iPad `76x76@1x` slot is absent. All generated app-icon PNGs are
  opaque 8-bit RGB with embedded sRGB profiles, exact manifest dimensions, no
  EXIF, and no transparent outer fringe.
- `SpaceGramAppIcon` is the primary catalog and is rendered from
  `SpaceGram-Alternate`. Moon, Earth, Mars, Sun, Saturn, and Neptune remain
  native iOS alternate icons selected through `UIApplication.setAlternateIconName`.
  Returning to Default passes `nil`, so `UIApplication.alternateIconName`
  correctly reflects the selection.
- The existing Appearance picker is data-driven, shows real preview resources,
  has no premium locks, and uses explicit English/Russian product names.
- The consistency checker validates source inventory, prepared master size,
  color mode/profile/metadata, suspiciously uniform outer edge fields,
  catalog manifests, 119 rendition files, plist keys, BUILD wiring, picker
  entries, dangling legacy catalog references, and the removed-primary guard.
- Feature commit: `PENDING`.
- GitHub Actions `SpaceGram iPhone Test Build`: `PENDING`.

> Historical pre-migration snapshot. The source namespace has since moved to
> `SpaceGram/`; see [the overnight audit](../SPACEGRAM_OVERNIGHT_AUDIT.md) and
> [migration contracts](../SPACEGRAM_INTERNAL_MIGRATION_AUDIT.md).

Date: 2026-09-19
Baseline: `8ab2f718f66543e778ee51f635c63d0fbf6bbae2` on `qwengram/main`

## Scope

This stage changes the visible product brand from **Qwengram** to
**SpaceGram**. It does not migrate persisted data, identifiers, signing, or Git
topology.

## Visible product changes

- The main application display name and bundle name are `SpaceGram`.
- Settings entry points, the app-lock and notification copy, onboarding,
  widgets, Siri error copy, demo content, and AI actions use the SpaceGram
  name.
- Values in the product localization catalogs use SpaceGram while the existing
  `Qwengram.*` localization keys and `QwengramLocalizable` table remain stable.
- English and Russian product strings were updated. Existing Japanese,
  Simplified Chinese, Traditional Chinese, and affected Telegram resource
  values were also updated so users do not see a mixed brand.
- GitHub Actions keeps compatibility-sensitive paths, branch names, bundle ID,
  and secret names, while workflow and uploaded artifact display names use
  SpaceGram.
- README and branding surfaces present SpaceGram and explain why internal
  Qwengram names remain.

## Internal identifiers intentionally preserved

The following remain unchanged because they are source or compatibility
contracts:

- `Qwengram/` source paths, Swift module/type names, Bazel target labels, and
  `// MARK: QWENGRAM` integration markers;
- `qwengram.*` preferences, storage roots, schemas, migration identifiers,
  queue/log labels, and account-scoped data layout;
- the `QwengramLocalizable` table and its `Qwengram.*` keys;
- Keychain services/accounts and the existing account-aware migration;
- bundle identifiers, URL/deep-link contracts, entitlements, signing inputs,
  CI secret names, branch names, remotes, and submodule revisions.

No storage migration is required for this branding stage.

## Application icon

The official master assets are retained unchanged under
`Branding/SpaceGram/IconSources`:

- `SpaceGram-Primary.png` is the current unframed primary icon source;
- `SpaceGram-Alternate.png` is the current unframed alternate icon source.

The initial framed JPEG masters were moved to `Branding/SpaceGram/LegacySources/`
after device feedback. Current validation and the static welcome-screen change
are documented in [the device feedback audit](../SPACEGRAM_DEVICE_FEEDBACK_AUDIT.md).
Earlier rendition counts and validation below describe the original branding pass.

Both sources are 1254 × 1254 JPEG images in RGB mode, with no alpha channel and
no embedded ICC profile. Their EXIF data only describes orientation 1 and 72 dpi.
They provide enough source resolution for the 1024 × 1024 App Store rendition.

The primary icon is compiled from
`Telegram/Telegram-iOS/SpaceGramAppIcon.xcassets/SpaceGramAppIcon.appiconset`.
The alternate icon is compiled from
`Telegram/Telegram-iOS/SpaceGramAlternateAppIcon.xcassets/Alternate.appiconset`.
Each catalog contains the complete 18-file iPhone, iPad, and App Store rendition
set. Generated files are 8-bit RGB PNGs with an embedded sRGB profile, exact
declared pixel dimensions, and no copied EXIF or Photoshop metadata. Resizing
uses a high-quality Lanczos filter and does not alter the artwork.

The previous graphite icon is retained at
`Branding/SpaceGram/LegacySources/SpaceGram-Graphite-Legacy.png`. It is not wired
into the application target.

## Appearance and theme hooks

`Qwengram/Appearance` provides one small presentation adapter for SpaceGram
owned list screens. It constructs Telegram's built-in `.night` presentation
theme and retains the active strings, Dynamic Type list size, name order, and
date format. Settings, Tools & AI, History, Media Archive, and Privacy &
Security screens use this adapter, giving them a consistent black/graphite
surface without modifying Telegram's global theme engine.

The SpaceGram Settings Appearance row continues to open Telegram's existing
theme settings controller. Its native **App Icon** section now receives two
non-premium product choices: `Default` and `Alternate`. Selecting `Default`
requests a nil alternate icon name; selecting `Alternate` requests the
`Alternate` asset identifier. Telegram's existing application binding calls
`UIApplication.setAlternateIconName`, reads `UIApplication.alternateIconName`
when the screen opens, and therefore delegates persistence to iOS. No
SpringBoard workaround or parallel preference is used.

The existing Telegram theme picker remains otherwise unchanged. General
Telegram screens continue to follow the user's selected theme.

## Build and plist wiring

`Telegram/BUILD` passes both catalogs through the rules_apple `app_icons`
attribute and identifies `SpaceGramAppIcon` as `primary_app_icon`. The primary
catalog name and alternate `Alternate` identifier match the application icon
provider and both the iPhone and iPad `CFBundleIcons` dictionaries. Stale
Black/Blue/Classic/Filled alternate-icon declarations were removed from the
active Info.plist because those inherited catalogs are no longer packaged as
application icons.

## Limits

- This is a focused product-screen style. It does not force a global dark theme
  across chats or other upstream Telegram screens.
- The icon is wired and structurally validated on Windows, but asset-catalog
  compilation and runtime switching require Xcode and an iOS device or
  simulator.
- Historical audits keep the Qwengram name where it identifies the baseline,
  source layout, or compatibility contract.

## Required macOS and device checks

1. Build `debug_sim_arm64` with the repository's pinned Xcode and confirm the
   asset catalog compiles with `SpaceGramAppIcon` as the primary icon.
2. Inspect both icons on the Home Screen, Spotlight, Settings, notifications,
   and App Store surfaces, including iPad sizes.
3. Open SpaceGram Settings and each product screen in English and Russian;
   verify navigation bars, search fields, disabled states, destructive actions,
   separators, Dynamic Type, and contrast.
4. Confirm Appearance opens the native Telegram theme picker, switch between
   Default and Alternate, relaunch the app, and verify that iOS preserves the
   selected icon without affecting theme selection.
5. Exercise account switching, App Lock, History/Media cleanup, notification
   privacy, and persistent Qwen conversations to confirm branding did not
   change account isolation or stored data.

## Validation performed on Windows

The final validation commands and outcomes were:

- `python tools/check_qwengram_consistency.py` — passed: 772 BUILD files, 66
  product Swift files, five localization catalogs, both SpaceGram icon
  catalogs, BUILD wiring, and Info.plist wiring were checked with zero errors.
  Workflow YAML parsing was skipped because PyYAML is not installed.
- App-icon catalog validation — passed for all 36 renditions: every declared
  PNG exists, is 8-bit RGB with an embedded sRGB profile, has the exact declared
  pixel dimensions, and contains no EXIF metadata.
- Both `Contents.json` files and `Info.plist` parsed successfully.
- Advisory tree-sitter parsing of the changed `AppDelegate.swift` produced the
  same single pre-existing missing-node finding as `HEAD`; this change added no
  parser finding. This is not Swift type checking.
- Active icon wiring contains no inherited Black/Blue/Classic/Filled alternate
  icon references. The legacy graphite source is not referenced by BUILD,
  plist, or Swift code.
- Localization checks — passed for duplicate keys, required English/Russian
  keys, and absence of the old visible product name in localized values.
- `git diff --check` — passed.

No Xcode asset compilation, iOS build, simulator run, runtime icon switch,
codesigning, or device installation was performed on this Windows host.
