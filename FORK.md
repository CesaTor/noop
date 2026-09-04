# This fork: MG on Mac + Android, nothing else

This fork (`CesaTor/noop`) exists for one purpose: **WHOOP MG support, developed and
field-tested on macOS and Android**. It is not a general-purpose mirror of upstream.

## Scope

- **In:** anything touching the WHOOP MG strap on the **macOS app** (`Strand` scheme,
  `NOOP Staging` identity) and the **Android app** (`Full`/`Demo` flavors), plus the shared
  layers underneath them (`Packages/*`, protocol twins, analytics twins, migrations).
- **Out:** iOS/watch-specific work, Oura/experimental-brand work, and anything that cannot be
  exercised on the owner's hardware. Shared-source changes still compile toward iOS via the
  macOS build, but the iOS leg is **never claimed as verified** here (no SDK, no device) —
  upstream PRs say so explicitly, and the iOS artifact in fork builds ships as CI-built only.

## Merge rule

Nothing reaches `master` unless it **works on Mac AND Android**, proven on hardware the owner
holds: the MG strap, a macOS staging build, and an Android debug APK. One platform is a study;
two platforms is a merge.

## Branches

- `main` — tracks `upstream/main`. Never developed on directly.
- `pr/*` — one concern per branch, each destined for one upstream PR.
- `master` — the release line: only merged `pr/*` branches that passed the merge rule.
  Dispatching a build always happens from here, so it is always releasable.

## Syncing with upstream

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main   # main follows upstream
git checkout master && git merge main                     # release line absorbs upstream
```

Conflicts resolve in favor of keeping `master` green on both test devices; rebase the open
`pr/*` branches onto the new `master` afterwards.

## Builds and releases (all on-demand, from `master`)

- **Testing:** Actions → `Testing build (fork)` → Run from `master`. Publishes the rolling
  `testing-latest` prerelease: Android release + debug APKs, macOS zip, unsigned iOS IPA.
- **Release:** Actions → `Release build (fork)` → Run from `master` with the bump. Commits the
  version bump (both `MARKETING_VERSION` and `versionName`), cuts a fixed `v<VERSION>` release,
  which is what the in-app "Check for updates" reads.

## Upstreaming

Upstream PRs come from `pr/*` branches. Each carries the dual-device verification (what strap,
what builds, what was exercised) and names what was NOT verified (iOS leg). The 9 Android unit
failures that reproduce on pristine upstream `main` (`AiCoachContextTest`, `RecoveryDriversTest`,
`StandardHrSensorFormatTest`, `TodayExplainabilityTest`) are disclosed, not fixed inside a
feature PR.
