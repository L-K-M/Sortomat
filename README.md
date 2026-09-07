# Sortomat

**Hazel, but the rule is a sentence.**

Sortomat is a macOS app that watches folders and files their new contents away.
A rule is a list of *if this, then that* steps — conditions on the name, kind,
size, dates, tags, origin or contents of a file, and a destination written as a
template:

> *`kind is image` → `Images/{name}`*
> *`name matches ^RE-(\d{4})` → `Invoices/{match.1}/{name}`*

Everything that can be decided that way is decided that way: for free, offline,
instantly, and identically every time. **A rule that needs no model runs
without an API key at all** — the template you meet on first launch is one of
those.

For the judgement a pattern cannot express — *what genre is this book, who sent
this invoice, what project is this screenshot from* — a rule can hand the file
to a language model, with the answer constrained to a folder set you chose and
anything doubtful parked rather than misfiled:

> *"Sort e-books into `{Genre}/{Last, First}/{Title}.epub`."*
> *"File invoices under `{Year}/{Sender}/{Date Subject}.pdf`."*

**Latest release:** v<!-- version -->1.0.0<!-- /version --> ·
[Download](https://github.com/L-K-M/Sortomat/releases/latest)

> [!IMPORTANT]
> Most of this code was written by an LLM from the design in `AGENTS.md` and
> `PLAN.md`. The file-moving core (path safety, dedup, undo) is deliberately
> conservative and covered by tests — but review before trusting it with
> irreplaceable files, and leave new rules on **Ask first**.

## What it does

- **Rules that are steps, not one guess.** Each step is a group of conditions
  (all / any / none, nestable) and the actions that follow. Conditions can ask
  about the name, stem, extension, path and depth; the kind (`image`, `pdf`,
  `archive`, …, resolved through the type system, not a hard-coded extension
  list); size; **five different dates** — added, created, modified, opened,
  captured — because "the date" silently meaning *modified* is the most
  confusing thing about every other tool; Finder tags, label and comment; where
  a file was downloaded from; image dimensions, page count, duration; and the
  file's **text**.
- **Real patterns.** Globs with `{a,b}`, `[0-9]`, `**` and negation, and
  regular expressions whose captures you can use in the destination —
  `Rechnung_(\d{4})` → `{match.1}/`. Patterns that could take exponential time
  are refused rather than run.
- **Destinations as templates.** `{name}`, `{stem}`, `{ext}`, `{parent}`,
  `{added|date:'yyyy-MM'}`, `{match.invoice.year}`, `{counter}` — with filters
  for case, padding, truncation and fallbacks.
- **It tells you what it will do.** Every step shows how many files in the
  folder it claims *right now*; point it at one file and it explains, condition
  by condition, what it found and what it decided. The rule editor lists what
  is wrong with a rule — a condition that can never be true, a step that hides
  the ones after it, a destination that could leave a file with no name —
  before you turn it on.
- **Reads what files contain.** Word, Excel, PowerPoint, OpenDocument, RTF,
  HTML, PDF and EPUB text without leaving the machine, and on-device **OCR**
  for screenshots and scans, so a rule can match on a scanned invoice's number.
- **Safe by default.** New rules start in **ask first** — Sortomat shows every
  planned move and touches nothing until you approve. Path building rejects
  traversal and absolute paths, forces the real file extension, detects true
  duplicates by **content hash** (not just size), and verifies cross-volume
  copies before deleting the original.
- **Reversible.** Every move is journaled; one click in History, one click on
  the notification, or `Sortomat … undo` puts it back.
- **Constrained where the model is involved.** Give a rule an **allowed folder
  set (taxonomy)** and the model can only file into those folders; anything
  else — or anything low-confidence — is parked rather than mis-sorted.
- **Private by choice.** A rule can run **metadata-only** (name + metadata,
  contents never read), and you can point it at a **local model** (Ollama, LM
  Studio) instead of the cloud.
- **Cost-aware.** A per-check budget *and* a monthly ceiling, spend in the
  menu, and holds for battery and Low Power Mode — so an afternoon of downloads
  cannot quietly become a bill.

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

1. Open the window from the menu-bar icon, or ⌘0. It has three things: the
   **Inbox** (files waiting for a yes), **History** (everything filed, with
   undo), and your rules grouped by the folder they watch.
2. Pick a rule template. **Tidy up by kind** needs no API key and nothing else
   configured — choose the folder to watch and the folder to file into, and it
   works. It is the rule seeded on first launch.
3. For a rule that asks a model, paste an API key in **Settings** (it is stored
   in the Keychain). The default provider is Mistral; point the base URL at any
   OpenAI-compatible endpoint, including a local one.
4. Every rule is **Automatic**, **Ask first** or **Off**. New rules start on
   *Ask first*: they do all the work and then wait for you in the Inbox.

## How it works

For each new, *stable* file (not still being written; partial downloads and
hidden files are ignored):

1. **The rule's steps run in order**, and the first one whose conditions match
   claims the file — unless it says *continue*, which hands the file and
   anything it captured to the next step. Conditions inside a step are
   evaluated cheapest-first, so a name test rejects a file before anything
   opens it: a rule that never mentions contents never reads one.
2. **Only what no step claimed** reaches the model, and only if the rule says
   so. Then the file's name, metadata and (unless the rule is metadata-only) a
   text excerpt are sent, and the model returns a destination and a confidence.
3. The answer is **sanitized** and, if the rule has a taxonomy or a confidence
   threshold, checked; out-of-set or low-confidence results are parked.
4. The file is moved/copied with collision suffixing and duplicate detection,
   the move is journaled, and any tags the rule asked for are applied.

Identical bytes under the same rule get the identical decision without asking
twice — the answer is remembered by content, so re-downloading the same file
costs nothing.

Folders are watched via FSEvents — new files are picked up within seconds of
*settling* (a short stability probe guards against half-written downloads) —
plus a periodic safety-net scan. Everything a rule has decided is remembered in
a persistent ledger, so files aren't re-classified — or re-paid for — on every
scan or relaunch.

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
# (requires the shared lkm-build tool: https://github.com/L-K-M/release-tool —
#  the xcodebuild commands above are the dependency-free path)
./scripts/build.sh
```

See [`CICD.md`](CICD.md) for the release process, [`AGENTS.md`](AGENTS.md) for
the architecture, and [`ANALYSIS.md`](ANALYSIS.md) for what is done, what is
open and what to read first — it is the document to start from.
[`fable-is-awesome.md`](fable-is-awesome.md) is the earlier review record.
`sort_epubs.py` is the original dependency-free batch EPUB sorter that seeded
the idea.

## Releasing

```sh
scripts/release.sh 1.2.0 --push   # bump, tag v1.2.0, push → CI builds & publishes
```

## License

[The Unlicense](LICENSE) — public domain.