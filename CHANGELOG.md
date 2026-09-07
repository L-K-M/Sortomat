# Changelog

All notable changes to Sortomat are documented here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow the git tags.

## [Unreleased]

### Since wave 5

- **A real app icon.** Sortomat ships the artwork committed at
  `media-sources/icon.png` instead of a procedurally drawn funnel tile.
  `Tools/generate_icon.py` fits that artwork to Apple's 824-of-1024 grid and
  filters it down to every size in the ladder, so replacing the icon is
  replacing one PNG and re-running one script.

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

### Waves 4 and 5 — the deterministic engine, and an app you can see

The rule engine, rewritten. A rule is now an ordered list of *if this, then
that* steps rather than one prompt with a few pre-rules in front of it:

- **Conditions** on name, stem, extension, relative path and depth; kind
  (resolved through `UTType`, not an extension table); size; **five dates** —
  added, created, modified, opened, captured; Finder tags, label and comment;
  where a file came from; image dimensions, page count, duration; and the
  file's text. Grouped `all` / `any` / `none`, nestable, and evaluated
  cheapest-first so a name test rejects a file before anything opens it.
- **Real globs** (`{a,b}`, `[0-9]`, `**`, negation) and regular expressions
  whose captures feed the destination; a pattern that could take exponential
  time is refused rather than run.
- **Destinations as templates** — `{name}`, `{added|date:'yyyy-MM'}`,
  `{match.invoice.year}`, `{counter}` — with filters for case, padding,
  truncation and fallbacks.
- **A trace per decision**: every condition, the value actually found, and the
  verdict — six distinct reasons rather than one `false`, because "this photo
  has no capture date" and "this photo was taken in 2019" are different
  answers to *why didn't my rule fire*.
- **Lossless migration in both directions.** Existing rules are upgraded on
  load, and a config edited by this build still opens in the previous one.

Around it:

- **Text out of real documents**: Word, Excel, PowerPoint, OpenDocument, RTF
  and HTML, plus on-device **OCR** for screenshots and scanned PDFs — a PDF
  whose text layer is only a scanner's stamp is recognized instead.
- **An Inbox-first window** (⌘0) replacing the settings dialog: files waiting
  for a yes, history with undo, and rules grouped by the folder they watch.
  Each rule is **Automatic**, **Ask first** or **Off** in place of two
  booleans, and the words changed to ones people use — *preview* became the
  Inbox, *dry run* became Ask first, *quarantine* became "park this".
- **Undo on the notification itself**, so a banner from a pass that happened
  while you were away is actionable rather than only informative.
- **Guardrails**: a monthly spend ceiling on top of the per-check budget,
  holds on battery and in Low Power Mode, and a pause that survives a relaunch.
- **A rule editor that answers questions**: how many files each step claims
  right now, what a rule would do with one file you pick, and what is wrong
  with the rule before you enable it — a condition that can never be true, a
  step that hides the ones after it, a destination that could leave a file
  with no name.
- **A template that needs no API key** — *Tidy up by kind*, four buckets by
  content kind, and the rule seeded on first launch.
- **Finder tags applied**, one stability pause per pass instead of one per
  file, undo that prunes the empty folders it leaves behind, and file names
  that fit the 255-*byte* limit rather than 255 graphemes.
- The app icon sits on Apple's icon grid and is antialiased at every size.

Everything still open is in `ANALYSIS.md`, which supersedes the wave-1–3 half
of `fable-is-awesome.md`.

### Review wave 2 (merged as one integration PR)

- Full findings, the re-verified backlog and the branch plan live in
  `fable-is-awesome.md`; the eighteen branches were composed in the
  conflict-minimizing order that review computed, with the three silent-loss
  composition hazards (W30–W32) resolved explicitly: undo hardening + batch undo, stale-plan
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
