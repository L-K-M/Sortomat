# Sortomat — Plan & Architecture

## Vision

A macOS menubar app that watches folders and files their new contents away
automatically, using **user-defined natural-language rules** interpreted by an
LLM. Instead of hand-coding sorting logic, the user writes a prompt per folder
("sort e-books into `{Genre}/{Nachname, Vorname}/{Titel}.epub`", "file invoices
under `{Jahr}/{Absender}`", "move screenshots into the matching project folder")
and the app applies it to every new file that lands.

Think **Hazel, but the rule is a sentence** — with the LLM handling the fuzzy
judgment (genre, author, topic, "what is this document about") that deterministic
rules can't express.

---

## Goals & non-goals

**Goals**
- Continuous, unattended folder monitoring on macOS.
- Per-folder rules expressed in plain language, not code.
- Safe, reversible file operations the user can trust.
- Works across arbitrary file types (e-books, PDFs, text, images, …).
- Local-first option (swap the cloud LLM for a local model).

**Non-goals (for now)**
- Deep content transformation (renaming/OCR/rewriting file *contents*).
- Cross-machine sync of rules or state.
- A general workflow engine (we sort/route files; we don't run arbitrary actions).

---

## Design principles (derived from the audit)

1. **Safe by default.** Never destroy data. Prefer copy → verify → delete over
   blind move; never overwrite; wait until files are fully written.
2. **Reversible.** Every action is recorded with enough detail to undo it.
3. **Predictable-first.** Deterministic rules should handle the common case; the
   LLM is the fallback for genuinely fuzzy decisions, constrained to a
   user-defined taxonomy rather than free-form invented paths.
4. **Transparent.** The user can preview what *would* happen (dry-run) and see
   what *did* happen (audit log, notifications).
5. **Cost-aware.** One cloud LLM call per file is real money; dedupe, cache, and
   surface usage.
6. **Private by choice.** File contents leave the machine only when the user
   opts in per rule; a metadata-only mode and local-model mode exist.

---

## What already exists

The repository currently contains two independent implementations of the same
core idea, at different maturity levels.

### 1. `sort_epubs.py` — the original batch script (working)

A dependency-free Python 3 script that sorts a directory tree of EPUBs into
`{Genre}/{Nachname, Vorname}/{Titel}.epub` using the Mistral API.

- Recursively finds EPUBs (case-insensitive), excludes the target subtree.
- Extracts OPF metadata + a ~4'000-char text sample from the first real content
  chapters (skips cover/TOC pages).
- Classifies against a **fixed list of 31 normalized German genres** (rejects any
  genre outside the list, falls back to `Unbekannt`).
- Robust EPUB parsing hardened against real-world breakage: HTML entities in
  XML, mis-declared encodings (treats `ISO-8859-1` as `cp1252` like browsers do),
  stray control characters, missing/mis-cased `container.xml` (falls back to
  scanning for any `.opf`), and case-mismatched spine hrefs.
- Filesystem-safe path sanitization, duplicate detection (same name + size),
  collision suffixes `(2)`, `(3)`, …
- Retries on HTTP 429/5xx with exponential backoff; `--dry-run`, `--copy`,
  `--limit`, `--delay` flags; unreadable files are skipped and reported.

**Role going forward:** reference implementation / one-shot batch tool. The
EPUB-specific parsing and genre list are the seed for Sortomat's example rule.

### 2. `Sortomat/` — the macOS menubar app (prototype)

A native SwiftUI `MenuBarExtra` app (Swift 5.9, macOS 13+, no external
dependencies). Generalizes the script: each **rule** = watched folder + target
folder + natural-language prompt + optional extension filter + move/copy toggle.

**Source layout** (`Sortomat/Sources/Sortomat/`):

| File | Responsibility |
|---|---|
| `Config.swift` | `Rule`, `Config` models; `ConfigStore` (JSON load/save in Application Support, activity log). Seeds a disabled EPUB example rule on first launch. |
| `Keychain.swift` | Mistral API key in the macOS Keychain; `MISTRAL_API_KEY` env override for headless use. |
| `Mistral.swift` | `MistralClient` — chat/completions call, JSON-object response, retry/backoff; `Classification` (`action`, `relative_path`, `reason`). |
| `FileContext.swift` | `describe(url:)` — name, dates, Spotlight metadata, and a content excerpt (plain text, PDF via PDFKit, EPUB via `/usr/bin/unzip` + `XMLDocument`). |
| `Mover.swift` | Path sanitization, LLM-path → safe destination (rejects `..`/absolute, forces real extension), move/copy with collision + duplicate handling. |
| `Pipeline.swift` | `actor Pipeline` — candidate discovery, file-stability check, per-file classify + move; in-memory skip/fail caches. `HeadlessRunner` for `scan-once`. |
| `FolderWatcher.swift` | Per-folder dispatch-source watcher (write/extend/rename events). |
| `AppState.swift` | `@MainActor` observable app state; owns watchers, the periodic timer, and scan coalescing/debounce. |
| `App.swift` | `MenuBarExtra` UI, `AppDelegate` (accessory / no-Dock), menu content (pause, scan now, recent activity, open settings). |
| `SettingsView.swift` | Rules tab (list + editor: paths, extensions, prompt, copy toggle) and General tab (API key, model, base URL, scan interval). |
| `main.swift` | Entry point: `scan-once` headless mode vs. GUI. |
| `build.sh` | Builds `Sortomat.app`, writes `Info.plist` (`LSUIElement`), ad-hoc signs. |

**What works today**
- Menubar app launches, runs as an accessory (no Dock icon), stays resident.
- Rules are configured in a Settings window and persisted to JSON; API key in Keychain.
- Folders are watched via dispatch sources (instant reaction) plus a periodic
  safety-net scan (default 60 s).
- Files are only acted on once **stable** (not modified in the last few seconds,
  size constant across a re-check); partial downloads and hidden files are ignored.
- Per file: builds context → asks Mistral for a target-relative path or `skip` →
  sanitizes → moves/copies with duplicate + collision handling.
- Skipped/failed files are remembered for the process lifetime (avoids re-asking).
- Activity shows in the menu and appends to `activity.log`.
- `scan-once` headless mode for tests/scripts/launchd.

**Verified end-to-end** against a mock Mistral server (files classified, moved
into model-decided hierarchies, collisions suffixed, non-matches skipped, `.app`
launches stably). Only the happy path is covered; there is no automated test target.

---

## Assessment summary (from adversarial audit)

A six-dimension code audit produced 40 findings; **34 survived adversarial
verification** (13 high, 13 medium, 8 low); 6 were refuted as false positives.

**Genuinely solid** — the highest-risk area (irreversible file moves) is the
best-built part: traversal/absolute-path rejection, per-component sanitization,
forced real extension, collision suffixing, stability + partial-download
checks, Keychain for secrets. Verifiers tried to break the path-safety logic and
could not.

**The core tension:** the LLM-per-file design is simultaneously the
differentiator (fuzzy judgment Hazel can't do) and the liability
(non-deterministic, costs money per file, sends contents to the cloud, can
silently misfile). Everything in the roadmap below is about keeping the upside
while containing that liability.

### Must-fix correctness bugs
- **Cross-rule cache poisoning** (`Pipeline.swift`): skip/fail caches are keyed
  by file only and shared across rules, so one rule's "skip" permanently blocks
  another rule from ever sorting the same file.
- **Size-only duplicate detection** (`Mover.swift`): two different files of equal
  byte size → the second is treated as a duplicate and stranded.
- **Double-move across processes**: `scan-once` running alongside the GUI (two
  `Pipeline` instances) can both classify and move the same file; the second
  operates on a vanished source.
- **Watcher never recovers** after the folder is unmounted/renamed
  (`FolderWatcher.swift`) — detection silently falls back to the timer only.
- **`unzip` read loop can deadlock the pipeline** (`FileContext.swift`) on a
  malformed EPUB or stalling network share, stopping all sorting.
- **Cross-volume fallback** (`Mover.swift`) catches *every* move error and does
  copy-then-delete, so a degraded copy (dropped xattrs/resource forks) still
  triggers deletion of the original.

### Trust gaps (block productization)
- **No dry-run/preview** — enabling a rule moves real files immediately.
- **No undo, source path not recorded** — moves are effectively irreversible.
- **Skip state is in-memory only** — every relaunch re-classifies and re-pays for
  every previously-skipped file.

### Security & privacy
- API key + file contents POSTed to a **user-editable base URL** (SSRF / key-exfil surface).
- **No App Sandbox**, ad-hoc signing → TCC permission drops on every rebuild.
- **Prompt injection** from file contents can steer the destination path.
- No per-rule opt-out for sending contents; Keychain item lacks a
  `ThisDeviceOnly` accessibility class.

### Robustness & scale
- Non-recursive watching/scanning (subfolders ignored).
- No batching/throttle/budget — one serial LLM call per file (a 3'000-file folder
  = 3'000 sequential calls, likely tripping rate limits).
- UTF-8-only text decode corrupts non-UTF-8 files (cp1252/UTF-16).
- No rule ordering/priority when multiple rules match; no notifications on failure;
  no cost/token visibility.

### Refuted (already handled — no action needed)
Path-traversal guard ordering, `O_EVTONLY` descriptor "leak", XML entity-expansion
(billion laughs), and two claimed scan-races were checked and found not to hold.

---

## Roadmap

Phases are ordered by trust impact. Each is independently shippable.

### Phase 0 — Current state ✅
Working prototype (see "What already exists"). Usable as a personal tool in
**copy mode** on a non-critical folder.

### Phase 1 — Correctness & safety fixes
Close the confirmed data-loss and reliability bugs.
- Key skip/fail caches by `rule.id` + file fingerprint.
- Content-hash (not size-only) duplicate detection.
- Per-file in-flight reservation inside the actor; guard `Mover.place` against a
  vanished source; make check-and-move atomic.
- Restrict the cross-volume copy-then-delete fallback to genuine
  cross-volume errors and verify the copy before deleting.
- Make `runUnzip` non-blocking with a hard timeout; replace with an in-process
  zip reader (also a prerequisite for sandboxing).
- Rebuild the watcher when the underlying folder disappears/reappears.

### Phase 2 — The trust trio
Turn it from "runs" into "trustworthy".
- **Dry-run / preview**: compute and display planned moves without executing;
  approve to apply. Reuse the same source→dest plan structure as undo.
- **Move journal + undo**: record every `source → destination` (+ timestamp,
  rule, reason) in a machine-readable log; one-click revert.
- **Persistent skip/dedup ledger**: survive restarts; stop re-classifying and
  re-paying for known files.

### Phase 3 — Robustness & scale
- Recursive watching via **FSEvents** (with the periodic full scan as source of truth).
- Concurrency cap + throttle + per-scan budget; batch where possible.
- Encoding detection for text extraction (reuse the script's cp1252/UTF-16 logic).
- Rule ordering/priority; system notifications on success/failure; a "stuck file"
  view with dismiss.

### Phase 4 — Productization
- **Developer ID signing + notarization + signed DMG + auto-update** (currently
  ad-hoc signed; won't launch cleanly on other Macs).
- TCC / security-scoped-bookmark flow for Downloads/Desktop/Documents; decide
  sandbox vs. full-disk-access distribution.
- Onboarding for non-programmers (rule templates, guided first rule).
- Cost controls + spend/usage display.
- English localization (UI, prompts, logs are German-only today).
- Automated test target (Mover sanitization, collision/dedup, path safety, the
  EPUB-parsing edge cases already handled in the Python script).

### Phase 5 — Differentiation & intelligence
- **Deterministic pre-rules** (glob/regex/date/kind) with the LLM as fallback —
  predictability of Hazel + fuzziness of an LLM.
- **User-defined taxonomies**: constrain the LLM to an enumerated folder set per
  rule instead of free-form invented paths (kills a whole class of mis-sorts).
- **Local-model mode**: point `apiBase` at Ollama / LM Studio / a local
  OpenAI-compatible server (near-free since the client is already standard).
- **Metadata-only privacy mode**: classify on filename/metadata without sending
  contents.
- Confidence threshold → low-confidence files go to a quarantine folder instead
  of being moved.

---

## Key decisions still open
- **Sandbox vs. full disk access** — drives distribution (Mac App Store vs.
  Developer-ID DMG) and forces the in-process zip reader. Decide before Phase 4.
- **Free-form paths vs. enumerated taxonomy** — the single biggest lever on
  mis-sort risk (Phase 5, but affects prompt design now).
- **Cloud vs. local default** — privacy/cost posture and onboarding story.
- **How opinionated to be about deterministic-first** — do we ship pure-LLM and
  add rules later, or lead with the hybrid?

---

## Repository layout

```
sort-epubs/
├── PLAN.md                 ← this file
├── sort_epubs.py           ← original batch EPUB sorter (Python, working)
├── README.md               ← script usage
└── Sortomat/               ← macOS menubar app (Swift prototype)
    ├── Package.swift
    ├── build.sh            ← build + ad-hoc sign Sortomat.app
    ├── README.md
    └── Sources/Sortomat/   ← app sources (see table above)
```
