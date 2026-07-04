# Changelog

All notable changes to Sortomat are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow the git tags.

## [Unreleased]

UX fixes from first hands-on use:
- Installed a real **Edit menu** so ⌘X/⌘C/⌘V/⌘A/⌘Z work in text fields (a
  menu-bar agent has no menu bar of its own by default).
- The **menu-bar icon is now the funnel** from the app icon (a template image
  that tints for light/dark menu bars).
- The **taxonomy field accepts Return** for new lines (it no longer re-parses and
  strips the in-progress newline on every keystroke). Same fix stabilizes the
  extensions field when switching between rules.
- **A rule no longer executes while it's open in the editor** — it resumes when
  you switch away or close Settings.
- **Redesigned the deterministic pre-rules UI**: roomy numbered cards with
  reorder (first match wins), aligned Match/Pattern/Action rows, inline help, and
  a plain-language summary of what each pre-rule does.

## [1.0.0] — first full release

Rebuilds the menu-bar prototype into a complete, safe-by-default app.

### Safety & correctness (Phase 1)
- Per-rule ledger keys — one rule's "skip" no longer blocks another rule.
- Duplicate detection by **content hash**, not byte size, so two different files
  of equal size are never conflated.
- In-flight reservation, a guard against a vanished source, and a cross-volume
  fallback that **verifies the copy before deleting** the original.
- In-process EPUB/zip reader (Compression framework) replaces the `unzip`
  subprocess — removes a deadlock risk and is a step toward sandboxing.
- FSEvents folder watching that survives the watched folder being unmounted or
  renamed.

### Trust (Phase 2)
- **Dry-run preview** window: see every planned move and apply on approval. New
  rules preview by default.
- **Move journal + one-click undo** (and a `undo` CLI subcommand).
- **Persistent ledger** so files aren't re-classified or re-paid for across
  scans and relaunches.

### Robustness & scale (Phase 3)
- Recursive watching option; concurrency cap and per-scan model-call budget.
- Encoding detection (UTF-8 / Windows-1252 / UTF-16) for text extraction.
- Rule priority and failure notifications.

### Differentiation (Phase 5)
- **Deterministic pre-rules** (glob / regex / kind / age) with LLM fallback.
- Enumerated **taxonomies** per rule — the model may only file into the allowed
  top-level folders; out-of-set answers are quarantined.
- OpenAI-compatible client → point it at a **local model** (Ollama, LM Studio).
- **Metadata-only** privacy mode — contents never leave the machine.
- **Confidence threshold** → low-confidence results go to a quarantine folder.

### Productization (Phase 4)
- Converted to an Xcode project with file-system-synchronized groups.
- CI (build + test) and a tag-driven release that signs + notarizes when secrets
  are present, ad-hoc signs otherwise, and publishes a `.zip` + `.dmg`.
- Comprehensive XCTest suite (path safety, dedup, pre-rules, EPUB parsing,
  ledger, journal/undo, config migration, semantic versioning).
- English + German localization; onboarding rule templates; cost/usage display;
  a generated app icon.
