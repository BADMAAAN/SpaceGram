# SpaceGram GitHub Migration Audit

Date: 2026-09-19

## Result

The current SpaceGram working state was checkpointed and pushed to the official
public repository without force-pushing:

- repository: `https://github.com/BADMAAAN/SpaceGram`
- remote: `origin = https://github.com/BADMAAAN/SpaceGram.git`
- local branch: `qwengram/main`
- pushed branch: `main`
- checkpoint commit: `1826e6ebe0e909fd1b4cee4239a44011764a2a3f`
- repository-history merge commit: `9e6b421680a98ed153c972414ab265648fd53327`
- push: successful fast-forward from the repository's initial commit to
  `9e6b421680a98ed153c972414ab265648fd53327`

The new repository already had an unrelated one-line initial commit on `main`.
It was retained as a merge parent, and the resulting tree stayed identical to
the reviewed SpaceGram checkpoint. The push used `HEAD:main` and no `--force`.
The pre-existing local branch named `main`, which belongs to another retained
remote history, was not overwritten or deleted.

The old Qwengram repository was not contacted for writes, deleted, or modified.
Its URL is no longer assigned to `origin`.

## CI secret migration

The active workflows now use only these Telegram credential secret names:

- `SPACEGRAM_TELEGRAM_API_ID`
- `SPACEGRAM_TELEGRAM_API_HASH`

Both `.github/workflows/spacegram-ios-test.yml` and
`.github/workflows/testflight.yml` reference the new repository secrets. Their
temporary environment variable names use the same SpaceGram prefix. The two
retired Qwengram-prefixed names and the generic Telegram secret names were
removed from the current tree. `SpaceGram/IOS_TEST_BUILD.md` documents the final
names.

The workflow file was renamed from `qwengram-ios-test.yml` to
`spacegram-ios-test.yml`. Visible workflow and artifact names use SpaceGram.
The workflow checks out the branch selected by GitHub Actions instead of a
hard-coded legacy branch.

## Secret review

Before the checkpoint commit:

- 213 staged text files were scanned;
- no retired Telegram secret name, private-key header, GitHub token pattern, AWS
  access-key pattern, concrete non-placeholder Telegram API ID, or concrete
  Telegram API hash assignment was found in the staged content;
- no `.p12`, `.p8`, `.pem`, `.key`, `.mobileprovision`, `.env`, signing input,
  credential directory, or local build configuration was staged;
- `qwengram_run7_fix.patch` was not staged or committed;
- `git diff --cached --check` passed after line-ending normalization;
- the staged workflow diff was reviewed directly.

The repository contains a long-standing upstream test/example credential
placeholder in four tracked build-system files. It is paired with the upstream
placeholder API ID, is identical across those fixtures, predates this migration,
and is not either SpaceGram repository secret. Its value is intentionally not
reproduced here. Nested third-party submodule examples are not tracked as blobs
by this parent repository.

No actual SpaceGram Telegram API ID or API hash value was read, printed, placed
in a log, staged, or committed. The workflows write credentials only into
gitignored ephemeral `build-input` files on the GitHub runner.

## Validation

The portable preflight passed after the CI edits:

- 773 BUILD files checked;
- 74 SpaceGram/test Swift source files checked for source ownership and labels;
- 32 plist inputs parsed;
- 193 asset-catalog JSON files and 293 referenced asset files checked;
- four workflow YAML files parsed;
- zero portable preflight errors;
- `git diff --check` passed.

These checks do not replace Swift compilation or a macOS/Xcode build.

## GitHub Actions status

After the push, the public GitHub Actions page registered all three workflows:

- `CI`
- `SpaceGram iPhone Test Build`
- `TestFlight (SpaceGram)`

The `SpaceGram iPhone Test Build` workflow page resolves under
`.github/workflows/spacegram-ios-test.yml`. At verification time GitHub reported
zero workflow runs. The workflow is intentionally `workflow_dispatch` only, so
the source push did not trigger it. The local GitHub CLI has no authenticated
session, and the unauthenticated REST quota was exhausted; no manual build was
dispatched and no build conclusion is claimed.

Workflow registration result: **passed**. Workflow execution result:
**not run (manual dispatch required)**.
