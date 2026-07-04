# CI/CD (detailed)

Two GitHub Actions workflows, both on `macos-14` with Xcode pinned to **16.2**.
Sortomat has **no third-party dependencies**, so nothing is resolved or vendored
on the runner.

See the top-level [`CICD.md`](../CICD.md) for the quick reference; this document
covers the details and how Sortomat keeps in step with its sibling apps.

## The family

Sortomat is one of a family of menu-bar apps by the same author (Zap, MacDring,
Gans) that share this CI/build tooling. The `ci.yml` and `release.yml` files are
**identical except for the `env:` block** (`PROJECT`, `SCHEME`, `APP_NAME`) and
Sortomat's optional signing path. Keeping them in lockstep means a fix to one
can be copied to the others. A future refactor could extract a `workflow_call`
reusable workflow into a shared `L-K-M/.github` repo.

## CI details

- CI needs a **shared scheme** (`Sortomat.xcscheme` under
  `xcshareddata/xcschemes/`) whose Test action covers the `SortomatTests`
  target. It's committed.
- The Xcode project uses **file-system-synchronized groups**, so adding a Swift
  file under `Sortomat/` or `SortomatTests/` requires no `project.pbxproj`
  edit — CI picks it up automatically.
- CI builds with `CODE_SIGNING_ALLOWED=NO`, so it also works on forked-PR
  branches with no secrets.

## Cutting a release

```
git tag v1.2.0 && git push origin v1.2.0
# or: scripts/release.sh 1.2.0 --push
```

The workflow: **test** → build Release (unsigned, version from tag) → **sign**
(Developer ID + `notarytool --wait` + `stapler` when secrets exist, else ad-hoc)
→ package `.zip` (`ditto`) + `.dmg` (`create-dmg`) → publish via
`softprops/action-gh-release`.

## Signing: on vs. off

The `release` job sets `HAS_SIGNING` from the presence of both
`DEVELOPER_ID_P12_BASE64` and `AC_API_KEY_BASE64`. Each signing step is gated on
`if: env.HAS_SIGNING == 'true'`; the ad-hoc step and unsigned release notes are
gated on the negation. So the same workflow produces a notarized build for the
maintainer and an ad-hoc build for a fork or a secret-less checkout, with no
edits.

The hardened runtime is already enabled in the project. Sortomat uses **no
entitlements file** and is **not sandboxed** — it needs to read and move files
across the user's chosen folders, so it's distributed as a Developer-ID app, not
via the Mac App Store. If sandboxing is ever pursued, the in-process EPUB reader
(no `unzip` subprocess) is already a prerequisite that's been met.

## Troubleshooting

- **`built Sortomat.app not found`** — the Release build failed earlier; read
  the build log above the error.
- **`create-dmg` exited non-zero but the DMG exists** — a known headless-runner
  quirk; the workflow tolerates it (`|| true`) and then verifies the file.
- **App won't launch on Apple Silicon** — it must be at least ad-hoc signed;
  the workflow always signs.
- **Bumping Xcode** — change `xcode-version` in *both* workflows together.
