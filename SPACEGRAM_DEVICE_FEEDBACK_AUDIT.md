# SpaceGram device feedback audit

Date: 2026-09-19. Workspace: `C:\Project\Qwengram`.
Baseline: `d338cd5cd57c84007cb2b796bbb50e395ef3dbc4`.
Official remote: `https://github.com/BADMAAAN/SpaceGram`.

## Observed issues and confidence

The reported iPhone install opens onboarding, then exits after the login code;
later launches can fail too. The welcome animation still looks like Telegram,
and both app icons have an unwanted black rounded frame.

No device crash report, watchdog report, installed-IPA hash or iPhone runtime
session was available. **The crash cause is a source-level hypothesis, not a
confirmed device diagnosis.** Windows cannot establish that the crash is fixed.

## Post-login findings, ranked

1. **Settings singleton re-entry (strongest SpaceGram-specific candidate).**
   `ManagedAccountPresence` subscribes to `spaceGramSuppressOnlinePresenceSignal`
   when an authorized account starts. Managed typing also subscribes to the
   SpaceGram policy signal. Previously `settingsSignal` registered a synchronous
   UserDefaults observer *before* first reading `SpaceGramSettings.shared`.
   The singleton's initializer migrates defaults and writes a version marker,
   even on a fresh account with no legacy values. A synchronous notification
   during those writes can read the same still-initializing Swift singleton,
   causing recursive once initialization (deadlock/trap; a hang may eventually
   be killed by the watchdog). The recursive signal lock cannot make Swift's
   static initialization reentrant. This also fits repeated failures on launch.
   Notification timing on the affected iOS version remains unverified.
2. **Persisted enhancement integer overflow (conditional).** `NagramDefault`
   converted arbitrary UserDefaults integers to Int32 with a trapping conversion.
   A corrupt/imported value used while building the root UI could crash every
   launch. Now an exact conversion falls back to the declared default. No corrupt
   preference was observed on the actual phone; this is additional hardening.
3. **Restored tab index out of bounds (conditional).** Authorized UI readiness
   indexed the selected tab after checking only the lower bound. Custom tab
   layouts/account switches can change available controllers. Both the startup
   access and keyboard shortcut access now check `indices.contains`.
4. **Other runtime/signing/upstream failures remain unknown.** The installed
   artifact may differ from this source baseline. If the problem persists, use
   a symbolicated `.ips` with the matching dSYM, device/iOS version and build
   identifier. Distinguish an exception from watchdog termination or jetsam.
   Re-signing entitlements/App Groups and protected-data availability must be
   checked on the installed package; no signing policy was changed here.

## Stabilization changes

- Finish `SpaceGramSettings.shared` initialization before any SpaceGram settings
  observer is registered. Register the observer before reading the initial
  snapshot afterward, preserving live changes and multi-subscriber behavior.
- Do not rewrite an already-current migration version marker. The marker still
  does not skip migrations: missing new keys can resume, and legacy values remain.
- Use a nontrapping Int32 conversion with the existing per-setting default.
- Guard selected-tab upper and lower bounds in `ApplicationContext.swift`.
- Add DEBUG-only, fixed-text `SpaceGramStartup` breadcrumbs: settings bootstrap
  begin/complete, authorized UI begin, root controllers created, authorized UI
  ready, invalid integer fallback and missing welcome resource. These contain no
  account identifiers, paths, credentials, keys or private content. No fatal
  startup assertion was added. The ready breadcrumb is emitted on the normal
  selected-controller readiness path, not the pre-existing empty-tab fallback.

## Account subsystem audit

| Area | Finding / handling |
| --- | --- |
| Settings, UserDefaults migration | Bootstrap observer ordering fixed; legacy keys retained; native opt-in Ghost defaults preserved |
| Ghost presence/typing/read policies | Account-start subscriptions reach the fixed shared signal helper; no new polling or account assumptions |
| History | Uses the supplied account transaction and collection 1009; absent records are optional; capture errors are caught and Telegram writes/deletes continue; revision overflow already guarded |
| Media Archive | Disabled by default; starts on capture/user action, not unconditional account construction; worker catches failures; creates archive root before access; invalid policy/conflicting migration fails that operation and preserves data |
| AI/Keychain | Provider and conversation store are created by feature controllers on demand; missing key returns nil and errors are handled; account-scoped secrets and legacy owner claim preserved; no login-time network call added |
| Conversation storage | Root URL alone is constructed initially; worker migrates/creates directory before use; corrupt records skipped, operation failure delivered to caller |
| Privacy | Missing/corrupt policy returns the existing default; account-file and notification-mirror compatibility identifiers intentionally retained |
| Tools/actions | Static catalog; no startup plugin registration, key loading or directory migration |
| Appearance | Pure presentation helper on product screens; no account service initialization |
| Auth completion | Existing completion/navigation/localization callbacks retained; no custom product completion service found |
| Multi-account/storage | Account roots and IDs supplied by existing contexts; no forced account-record unwrap introduced; missing/deleted account directories are not recreated by optional archives |
| Retained iCloud settings | Existing opt-in bridge remains; no demonstrated post-login failure found; signed-device entitlement behavior still needs validation |

Missing optional files already fail gracefully. No broad catch can recover a
Swift trap or Objective-C exception, so the concrete trapping/reentrant paths
were addressed directly. No archive was erased, merged or silently replaced;
there is no blanket feature disable and no new feature.

## Welcome branding

The device path used the inherited OpenGL tour animation. The static path was
limited to ARM64 simulators and attempted to load already-removed `Nagram@*`
artwork. `RMIntroViewController.m` now uses static branding on all devices,
loads `SpaceGramWelcome.png` from the existing `AppResources` glob, and falls
back to a readable S if packaging is incomplete. The static path never starts
the 60 Hz GL timer; cleanup stops a timer even without a GL context. The old
shine overlay was removed. UIKit supplies the welcome image's display corners;
they are not baked into the app-icon pixels.

The 13 bundled English `Tour.*` values, six feature cards and Swift start button
already say SpaceGram; the active RMIntro tour reads that bundled English table.
No unnecessary string replacements were made. The language suggestion and
download/apply flow are unchanged. The checker now guards the device/static
path, resource reference and SpaceGram tour copy. Full localized tour copy beyond
the existing English tour is not introduced by this stabilization pass.

## Icon correction

Both original JPEG masters contained a complete rounded tile within an outer
black square. That frame was reproduced in the renditions before iOS masking.

- Edited both masters with the built-in imagegen tool, preserving the silver S,
  planet and respective dim/bright orbit styles while extending space to every
  square edge. Visual inspection confirmed the inner container is absent.
- Current masters: `Branding/SpaceGram/IconSources/SpaceGram-Primary.png` and
  `SpaceGram-Alternate.png` (1254 square, RGB). Exported alternate alpha onto
  black for opaque iOS artwork. Prompts and regeneration instructions are in
  that directory's README.
- Original JPEGs were moved byte-for-byte to `Branding/SpaceGram/LegacySources/`
  as `SpaceGram-Primary-Framed.jpeg` and `SpaceGram-Alternate-Framed.jpeg`.
- Regenerated all **34** declared app-icon PNGs (17 per catalog), plus the
  444-square welcome resource, with `tools/generate_spacegram_icons.py`.
  Exported renditions are RGB, sRGB, exact manifest dimensions, without alpha.
- Catalog contents were replaced; `Contents.json`, icon identifiers,
  `CFBundleAlternateIcons`, primary target wiring and native switching API are
  unchanged. Earlier audit counts of 36 are historical; current manifests have 34.

## Validation and build readiness

- `python tools/check_spacegram_consistency.py`: PASS, 773 BUILD files,
  75 product/test Swift files, five localization catalogs; zero errors.
- `python tools/check_spacegram_preflight.py`: PASS, 32 plists (including two
  supported fragments), 193 asset JSONs, 291 asset-file references, four YAML
  files. Report saved separately to `SpaceGram/audits/device-feedback-preflight.json`;
  historical overnight report preserved.
- Swift tree-sitter: seven touched/new Swift files have zero diagnostic nodes,
  with no change from baseline. Full-tree advisory parsing reports 26 nodes in
  eight other files; these are not reported as compiler errors or ignored to
  claim a successful Swift build. Comparison is recorded in
  `SpaceGram/audits/device-feedback-swift.json`.
- Both masters and all generated PNG renditions decoded and checked for size,
  opacity and asset references; both large/small icons visually inspected.
- `git diff --check`: PASS. The pre-existing untracked user patch is excluded.
- Added XCTest cases for cold presence subscription, nested subscription /
  notification / disposal, out-of-range enhancement integers, a fresh account
  without archives, and a file where a legacy directory should be. **Not run on
  Windows**. Run the cold test alone in a fresh test process, then the full suite.
- Full app build, Swift type checking, XCTest, asset compilation and device
  install/runtime verification: **not available here** (Windows, no Xcode/iOS SDK).
  No successful build/install or selected signing mode is claimed.
- Existing manual `spacegram-ios-test.yml` now checks source/assets before
  spending time on the build. Credentials, signing flags, triggers and artifact
  handling are unchanged. No workflow, TestFlight upload or release was launched.
  Use the documented signing preflight before the next device build/install.

## Required iPhone retest

1. Build the current source with pinned Xcode and the approved signing mode;
   retain dSYM and identify the installed build. Run the full test suite on macOS.
2. Use a test account for clean authorization: welcome -> phone -> code -> chat
   list. Background/foreground, force-quit/relaunch repeatedly, then restart the
   phone, unlock and launch again. Inspect the fixed-text startup milestones.
3. Upgrade an existing installation without removing its data. Verify preserved
   Ghost settings, History, Media Archive and AI credentials/conversations.
4. Add/switch/remove a second test account. Check custom tab layouts, privacy,
   read/typing/presence toggles, and missing/corrupt optional-store fixtures in an
   isolated test build. Confirm native messaging remains usable on store failure.
5. Check every welcome page, scrolling, start button and suggested-language
   action in light/dark appearance. Verify no Telegram plane/animation is shown.
6. Inspect Default/Alternate on Home Screen, Spotlight and Settings. Switch both
   ways, relaunch and confirm selection persists. Check iPad rendition sizes too.
7. If termination persists, collect the matching symbolicated crash/watchdog
   report and startup stage logs; do not infer the cause from the login timing alone.

## Upstream touch notes

Only two upstream implementation files changed, with nearby `// MARK: NAGRAM`:
`submodules/TelegramUI/Sources/ApplicationContext.swift` (tab guards and stage logs)
and `submodules/RMIntro/Sources/platform/ios/RMIntroViewController.m` (static welcome
resource and timer handling). No Postbox API migration, upstream dependency
update, signing configuration change or broad formatting cleanup was made.
