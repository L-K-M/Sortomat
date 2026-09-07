# AGENTS.md

Guidance for AI coding agents working in the **Sortomat** repository.

## What Sortomat Is

Sortomat is a macOS menu-bar app that watches folders and files their new
contents away automatically, using **user-defined natural-language rules**
interpreted by an LLM — *Hazel, but the rule is a sentence*. Each rule is a
watched folder + a target folder + a plain-language prompt; every new file is
classified and moved (or copied) into the structure the prompt describes. See
`PLAN.md` for the full design and roadmap.

## Tech Stack

- **Language:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`).
- **UI:** SwiftUI for the Settings and Preview content; AppKit for windowing
  (`NSStatusItem`, `NSWindow`, `NSHostingController`).
- **System APIs:** FSEvents (folder watching), PDFKit + `MDItem` Spotlight
  metadata (content extraction), CryptoKit (content-hash dedup), the Compression
  framework (in-process EPUB/zip reading), `SMAppService` (launch at login),
  `UNUserNotificationCenter` (notifications), Keychain (API key).
- **Persistence:** a Codable `Config` as JSON in
  `~/Library/Application Support/Sortomat/config.json`; a move journal
  (`journal.jsonl`), a dedup ledger (`ledger.json`) and an `activity.log`
  alongside it. The API key lives in the Keychain (device-only).
- **Min target:** macOS 13 (Ventura). **Built with Xcode 16+.**
- **App type:** menu-bar agent (`LSUIElement = true`, `.accessory` policy, no
  Dock icon).
- **No third-party dependencies.** The model client speaks the OpenAI-compatible
  `chat/completions` API, so it works with Mistral, OpenAI, or a local server
  (Ollama, LM Studio).

## Build & Run

The Xcode project uses **file-system-synchronized groups**, so new `.swift`
files added under `Sortomat/` or `SortomatTests/` are picked up automatically —
no `project.pbxproj` edits needed.

```bash
# Build
xcodebuild -project Sortomat.xcodeproj -scheme Sortomat -configuration Debug build

# Run tests (pure logic: path safety, dedup, pre-rules, EPUB parsing, ledger…)
xcodebuild -project Sortomat.xcodeproj -scheme Sortomat -destination 'platform=macOS' test
```

Prefer building/running from Xcode during development so the menu-bar item,
permission prompts and notifications appear in a real GUI session.

`scripts/build.sh` builds and reveals `Sortomat.app` in Finder (thin stub over
the shared `lkm-build` engine). The app icon is generated from the master
artwork in `media-sources/icon.png`; edit that, then regenerate the ladder with
`python3 Tools/generate_icon.py` (dependency-free) or, on macOS,
`swift Tools/GenerateAppIcon.swift`.

Headless modes (for tests / launchd / scripts):

```bash
Sortomat.app/Contents/MacOS/Sortomat scan-once   # sort all enabled rules once
Sortomat.app/Contents/MacOS/Sortomat preview      # print what would happen
Sortomat.app/Contents/MacOS/Sortomat undo         # reverse the most recent batch
```

## Module Layout (mirrors `PLAN.md`)

- `Sortomat/App/` — entry point (`SortomatMain`), `AppDelegate`, `AppState`.
- `Sortomat/Model/` — `Rule`/`Config`/`PreRule` models, `ConfigStore`,
  `Classification`, `PlannedAction`, `ActivityEntry`, `Templates`, `L10n`.
- `Sortomat/Engine/` — the testable core: `Sanitizer`, `Mover`, `ContentHash`,
  `ZipArchive`, `EpubReader`, `HTMLText`, `TextDecoding`, `FileContext`,
  `DeterministicEngine`, `LLMClient`, `Journal`, `Ledger`, `Pipeline`,
  `HeadlessRunner`, `Keychain`.
- `Sortomat/Watch/` — `FSEventsWatcher`.
- `Sortomat/MenuBar/` — `StatusItemController`, `BlockMenuItem`.
- `Sortomat/Settings/` — the SwiftUI settings window (`SettingsView` + tabs +
  `RuleEditor`) and its window controller.
- `Sortomat/Preview/` — the dry-run review + undo history window.
- `Sortomat/Updates/` — dependency-free GitHub-Releases update checker.
- `Sortomat/Common/` — `Log`, `ActivationPolicy`, `LaunchAtLogin`, `Notifier`,
  `SemanticVersion`, `AppInfo`.
- `SortomatTests/` — pure-logic XCTest suite.

## Conventions

- Follow the Swift API Design Guidelines. One type per file; the file name
  matches the primary type. Use `// MARK:` to organize sections.
- Avoid force-unwraps outside tests.
- **Keep the Engine testable.** Anything that decides *where a file goes* lives
  under `Engine/` and is exercised by `SortomatTests/`. Don't push that logic
  into SwiftUI views.
- Never log file contents or the API key.

## Critical Constraints (safety is the whole product)

- **Safe by default.** Never destroy data. Path building rejects absolute paths
  and `..` traversal, forces the original extension, and confirms the result
  stays under the target. Duplicate detection is by **content hash**, never by
  byte size alone. The cross-volume fallback verifies the copy before deleting
  the original.
- **Reversible.** Every placement is recorded in the move journal with enough
  detail for one-click undo. Don't add a move path that bypasses the journal.
- **Trust before automation.** New rules default to **preview** (`dryRun`);
  nothing moves until the user approves it. Keep that default.
- **Cost- and privacy-aware.** One cloud call per file is real money and sends
  data off the machine. Respect a rule's `privacyMode` (metadata-only never
  reads contents), the per-scan budget, and the deterministic pre-rules that
  keep the common case off the paid path.
- **Keep `LSUIElement = true`** (no Dock icon); windows flip the app to
  `.regular` while visible and back to `.accessory` on close via
  `ActivationPolicy`.

## Testing Notes

- Unit-test the pure logic: path safety/sanitization, content-hash dedup,
  deterministic pre-rules, EPUB/zip parsing, text decoding, the ledger, the
  journal/undo, config migration, semantic versioning.
- `AppDelegate.applicationDidFinishLaunching` is guarded by `isRunningTests`, so
  the test host doesn't boot the menu bar or start scanning.
- The end-to-end pipeline (which calls the model API and moves real files) is
  verified manually or against a mock OpenAI-compatible server; it isn't unit
  tested in CI.

## Do / Don't

- **Do** update `PLAN.md` when the design changes and keep `README.md` in sync
  (including the `<!-- version -->` marker).
- **Do** assume Developer ID + notarization (not the App Store) for distribution;
  the CI release path signs and notarizes automatically when the org secrets are
  present, and ad-hoc signs otherwise.
- **Don't** add third-party dependencies; prefer system frameworks.
- **Don't** send file contents when a rule is metadata-only, and don't bypass the
  ledger/journal/preview safety layers.
