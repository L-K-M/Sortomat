# Changelog

All notable changes to Sortomat are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow the git tags.

## [Unreleased]

### Review wave 1 (merged as #1–#16; findings in `fable-is-awesome.md`)

Data safety & correctness:
- Cross-volume moves verify the **entire content** of the copy and fail
  closed when either side can't be hashed (previously a 4 MiB prefix, and
  two failed reads counted as a successful verification).
- Undo got honest: diverged copies are refused instead of deleted, undone
  entries no longer resurrect in the History tab (journal tombstones), and
  undo pins the restored file in the ledger so the next scan doesn't just
  move it back.
- A corrupt `config.json` is preserved as a timestamped backup instead of
  being silently replaced by an empty config on the next save.
- Percent-style numeric confidences are normalized (the quarantine
  threshold was silently defeated), unknown model actions skip instead of
  moving, non-retryable HTTP errors surface immediately instead of being
  retried four times, and base URLs ending in `/v1` work (the Ollama /
  LM Studio convention).
- `Rule.priority` is actually honored (it was a documented no-op); the
  per-scan LLM budget actually holds; `<style>`/`<script>` bodies and
  split multi-byte UTF-8 characters no longer pollute the excerpts sent to
  the model; Keychain saves update in place with checked statuses.

UI & localization:
- Review tab: a Dismiss button, an honest empty state when no API key is
  set, refresh/apply feedback, and rule + decision-origin badges on rows;
  both windows remember their frames.
- Menu bar: a pending-review count badge, real disabled states, ⌘W, and
  notifications that appear while the app is frontmost; the update checker
  no longer strands a Dock icon, stamps its check time only on success,
  and re-checks periodically instead of only at launch.
- Rule deletion asks for confirmation; the launch-at-login toggle the
  README promised exists; default names, the quarantine folder and the
  template prompts follow the UI language (EN/DE).
- Pre-release tags publish as GitHub pre-releases instead of becoming
  "latest".

### Review wave 2 (in progress)

- Full findings, the re-verified backlog and the branch plan live in
  `fable-is-awesome.md`: undo hardening + batch undo, stale-plan
  revalidation on apply, keyless deterministic sorting, engine edge cases
  (future mtimes, dangling symlinks, fake zip EOCDs), FSEvents lifetime,
  preview hygiene, honest notifications, monthly spend persistence, ledger
  pruning + log rotation, rule export/import, a content-addressed decision
  memo, and a cross-process config lock.

### Earlier

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
