# CI/CD

Sortomat is a Swift/Xcode macOS app. CI builds and tests the app on every
change, and the release workflow builds a `.app`, packages it as a `.zip` and
`.dmg`, and publishes a GitHub Release. Releases are **notarized automatically
when the signing secrets are present**, and ad-hoc signed (unsigned) otherwise.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pull requests and pushes to `main` / `claude/**` | Build and test with a pinned Xcode toolchain. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`) | Test, build, (optionally sign + notarize), package `.zip` + `.dmg`, publish a GitHub Release. |

## Continuous integration (`ci.yml`)

Runs a single **Build & Test** job on `macos-14`. In-progress runs for the same
ref are cancelled when a new commit is pushed.

- Selects **Xcode 16.2** via `maxim-lobanov/setup-xcode` — pinned so a
  runner-image bump can't silently change the toolchain.
- Installs `xcbeautify` for readable logs.
- Runs `xcodebuild clean test` against the `Sortomat` scheme with
  `CODE_SIGNING_ALLOWED=NO`, writing `TestResults.xcresult`.
- On failure, uploads `TestResults.xcresult` as an artifact.

### Running CI checks locally

```sh
set -o pipefail
xcodebuild \
  -project Sortomat.xcodeproj \
  -scheme Sortomat \
  -destination 'platform=macOS' \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  clean test | xcbeautify
```

## Releases (`release.yml`)

To cut a release:

```
git tag v1.2.3 && git push origin v1.2.3
```

Or use the helper, which also bumps the committed `MARKETING_VERSION` (and the
README `<!-- version -->` marker) so local/dev builds and the in-app update
checker report the same number, then creates and pushes the tag:

```
scripts/release.sh 1.2.3 --push
```

The version is derived from the tag with the leading `v` stripped; the build
number is the workflow run number. The job first re-runs the tests (a `v*` tag
can land on a commit CI never saw, and the in-app updater offers every published
release to every user), then builds Release.

**Signing is automatic and conditional:**

- **Signed + notarized** — when the Developer ID and App Store Connect secrets
  below exist, the app is codesigned with a Developer ID (`--options runtime`,
  hardened runtime is already on), submitted to `notarytool --wait`, and
  stapled. (Only the app is notarized — the DMG wrapper itself is not, so its
  staple step is best-effort; the stapled app inside opens with **no**
  Gatekeeper warning either way.)
- **Unsigned (default)** — with no secrets, the app is **ad-hoc** signed
  (`codesign --sign -`), which is only enough to launch on Apple Silicon.
  Gatekeeper warns; the release notes tell users to right-click → Open or run
  `xattr -dr com.apple.quarantine`.

Both paths produce a `Sortomat-<version>.zip` (via `ditto`) and a
`Sortomat-<version>.dmg` (via `create-dmg`), attached to a GitHub Release named
`Sortomat <version>` with auto-generated notes. A tag containing a `-`
(e.g. `v1.2.0-beta.1`) is published as a **pre-release**, so it never becomes
the repo's "latest" release and the in-app updater (stable-only) won't offer
it to users.

## Secrets

None are required for a working (unsigned) release. To enable Developer ID
signing + notarization, add these org/repo secrets — the release job turns the
signed path on automatically once they exist:

| Secret | Meaning |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | base64 of the Developer ID Application `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | password for that `.p12` |
| `KEYCHAIN_PASSWORD` | throwaway password for the CI keychain |
| `APPLE_TEAM_ID` | your Apple Developer team id |
| `AC_API_KEY_BASE64` | base64 of the App Store Connect API key (`.p8`) |
| `AC_API_KEY_ID` | the API key id |
| `AC_API_ISSUER_ID` | the API key issuer id |

Beyond those, the workflows use only the automatically provided `GITHUB_TOKEN`
(for creating the release).

## Auto-update

There is no Sparkle dependency. The in-app `UpdateChecker` polls the repo's
GitHub Releases (unauthenticated, once a day) and offers to open the download —
the "feed" is simply this repo's Releases.
