# Sortomat

**Hazel, but the rule is a sentence.**

Sortomat is a macOS menu-bar app that watches folders and files their new
contents away automatically — using **plain-language rules** you write, applied
by an LLM. Instead of hand-coding sorting logic, you describe what you want:

> *"Sort e-books into `{Genre}/{Last, First}/{Title}.epub`."*
> *"File invoices under `{Year}/{Sender}/{Date Subject}.pdf`."*
> *"Route screenshots into the matching project folder."*

…and Sortomat applies it to every new file that lands, letting the model handle
the fuzzy judgment (genre, author, topic, "what is this document about") that
deterministic rules can't express.

**Latest release:** v<!-- version -->1.0.0<!-- /version --> ·
[Download](https://github.com/L-K-M/Sortomat/releases/latest)

> [!IMPORTANT]
> Most of this code was written by an LLM from the design in `AGENTS.md` and
> `PLAN.md`. The file-moving core (path safety, dedup, undo) is deliberately
> conservative and covered by tests — but review before trusting it with
> irreplaceable files, and start in **preview** mode.

## What it does

- **Natural-language rules.** Each rule is a watched folder + a target folder +
  a prompt. New files are classified and moved (or copied) into the structure
  the prompt describes.
- **Safe by default.** New rules start in **preview** — Sortomat shows you every
  planned move and touches nothing until you approve it. Path building rejects
  traversal and absolute paths, forces the real file extension, detects true
  duplicates by **content hash** (not just size), and verifies cross-volume
  copies before deleting the original.
- **Reversible.** Every move is journaled; one click in the History tab (or
  `Sortomat … undo`) puts it back.
- **Predictable where it can be.** Deterministic **pre-rules** (glob / regex /
  kind / age) handle the obvious cases for free, and only what falls through
  goes to the model.
- **Constrained where it matters.** Give a rule an **allowed folder set
  (taxonomy)** and the model can only file into those folders; anything else —
  or anything low-confidence — goes to a quarantine folder instead of being
  mis-sorted.
- **Private by choice.** A rule can run **metadata-only** (name + metadata,
  contents never leave the machine), and you can point it at a **local model**
  (Ollama, LM Studio) instead of the cloud.
- **Cost-aware.** Set a per-check budget and see estimated spend in the menu.

## Install

Download the latest `.dmg` from the
[Releases](https://github.com/L-K-M/Sortomat/releases/latest) page and drag
`Sortomat.app` to `/Applications`.

Releases are unsigned unless built with signing secrets, so on first launch
macOS Gatekeeper may warn. Either **right-click → Open → Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Sortomat.app
```

Launch at login is a toggle inside the app. Requires macOS 13+.

## Setup

1. Menu-bar icon → **Rules & Settings…**
2. **Settings** tab: paste your model API key (stored in the Keychain). The
   default provider is Mistral; point the base URL at any OpenAI-compatible
   endpoint, including a local one.
3. **Rules** tab: add a rule (start from a template), choose the watched and
   target folders, write the prompt, and leave **Preview only** on until you've
   seen it do the right thing.

A disabled e-book example rule (German genre taxonomy) is seeded on first launch.

## How it works

For each new, *stable* file (not still being written; partial downloads and
hidden files are ignored):

1. **Deterministic pre-rules** run first — a match can route, skip, or defer to
   the model.
2. If deferred, the file's name, metadata and (unless the rule is metadata-only)
   a text excerpt — plain text, PDF via PDFKit, EPUB via an in-process reader —
   are sent to the model, which returns a destination folder + filename and a
   confidence.
3. The answer is **sanitized** and, if the rule has a taxonomy or a confidence
   threshold, checked; out-of-set or low-confidence results are quarantined.
4. The file is moved/copied with collision suffixing and duplicate detection,
   and the move is journaled.

Folders are watched via FSEvents (instant reaction) plus a periodic safety-net
scan. Everything a rule has decided is remembered in a persistent ledger, so
files aren't re-classified — or re-paid for — on every scan or relaunch.

## Headless mode

```sh
SORTOMAT_API_KEY=… /Applications/Sortomat.app/Contents/MacOS/Sortomat scan-once
/Applications/Sortomat.app/Contents/MacOS/Sortomat preview   # print, don't move
/Applications/Sortomat.app/Contents/MacOS/Sortomat undo      # reverse last batch
```

`scan-once` processes all enabled rules and exits (exit code 1 on error) —
useful for launchd jobs. `SORTOMAT_CONFIG_DIR` overrides the config directory.

## Privacy

A file's name, metadata and (unless a rule is metadata-only) a text excerpt (up
to ~4,000 characters) are sent to the model to classify it. For sensitive
folders, use a metadata-only rule, a tight extension filter, or a local model.
The API key is stored device-only in the Keychain and never leaves the machine.

## Build & Run

Requires Xcode 16+.

```sh
# Build
xcodebuild -project Sortomat.xcodeproj -scheme Sortomat -configuration Debug build

# Test
xcodebuild -project Sortomat.xcodeproj -scheme Sortomat -destination 'platform=macOS' test

# Build Sortomat.app and reveal it in Finder
./scripts/build.sh
```

See [`CICD.md`](CICD.md) for the release process and [`AGENTS.md`](AGENTS.md)
for the architecture. `sort_epubs.py` is the original dependency-free batch
EPUB sorter that seeded the idea.

## Releasing

```sh
scripts/release.sh 1.2.0 --push   # bump, tag v1.2.0, push → CI builds & publishes
```

## License

[The Unlicense](LICENSE) — public domain.