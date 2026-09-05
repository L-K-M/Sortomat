# Sortomat — the working analysis

*What is done, what is left, and enough detail on each open item that it can be
picked up cold. This is the document to read first and to keep current.
It supersedes the still-open half of `fable-is-awesome.md` (waves 1–3), which
stays in the tree as the record of how those findings were arrived at, and the
whole of the wave-4 review document, which lives on the review branch
`claude/hazel-alternative-review-ve9w1z`.*

*Last updated after wave 5. Every `file:line` reference points at `main` at that
point unless a branch is named.*

---

## How to work on this repo

Six things that cost real time to learn, in the order they will bite.

1. **CI is the only compiler.** There is no macOS toolchain in the review
   environment, so `.github/workflows/ci.yml` (Xcode 16.2 on `macos-14`) is
   where Swift is first parsed. Push early, push small, and read the
   `Testing failed:` block — `xcbeautify` prints the error messages there
   without file or line, and the full text a few lines further down. A round
   trip is about seventy seconds.
2. **The project uses `PBXFileSystemSynchronizedRootGroup`** (objectVersion
   70). New files *and new folders* under `Sortomat/` and `SortomatTests/` are
   compiled automatically — **no `project.pbxproj` edit is ever needed.**
3. **Blind-Swift traps that actually happened here**, each of which cost a CI
   round: a `public` type whose stored property names an `internal` one; a
   `switch` over an enum you just widened (`PlannedAction.Origin`); `CodingKeys`
   is *not* synthesized once a type hand-writes **both** `init(from:)` and
   `encode(to:)`; `SingleValueDecodingContainer.decodeNil()` does not throw; a
   UTI like `com.amazon.mobi8-ebook` resolves only on a machine with the app
   that declares it, so a bare runner returns nil; and **`@MainActor` on a class
   isolates its `static` members too**, so a pure helper a test wants to call
   needs `nonisolated`.
4. **`L10n.t` asserts in Debug on a missing key**, and `L10nTests` requires the
   English and German tables to hold exactly the same keys. Add both halves in
   the same edit or the whole suite goes red — and if you *remove* a key,
   `grep` the tests too: a live assertion in `L10nTests` for a deleted key kills
   the test host rather than failing one line.
5. **Darwin does not follow symlinks the way you expect.** Neither
   `attributesOfItem` nor `URL.resourceValues` traverses the final link, while
   `FileHandle`, `NSAttributedString(url:)`, `CGImageSourceCreateWithURL` and
   `ZipArchive` all do. Every size cap in this codebase has had this bug at
   least once. Use `stat(2)`, `fstat` on a handle you already opened, or
   `resolvingSymlinksInPath()` before measuring.
6. **The safety core is off limits without a very good reason.** `Sanitizer`,
   `Mover`, `Journal` and `Ledger` are the four files that decide where bytes go
   and how to undo it. Everything else can be rewritten; these four are changed
   deliberately, with tests, and never as a side effect.

---

## Scoreboard — what shipped

| Wave | What | Where | State |
| --- | --- | --- | --- |
| 1 | 16 fix PRs (#1–#16) | — | merged |
| 2 | 18 review branches (#17–#34), composed into one train | [#35](https://github.com/L-K-M/Sortomat/pull/35) | merged; the originals are closed as integrated |
| 4 | CI failure artifacts expire, so a red run stops failing twice | [#36](https://github.com/L-K-M/Sortomat/pull/36) | merged |
| 4 | Engine-core hardening: fail-closed hashing, verified cross-volume moves, document packages as candidates, the classification valves | [#37](https://github.com/L-K-M/Sortomat/pull/37) | merged |
| 5 | On-device extraction: office documents, spreadsheets, decks, OpenDocument, HTML text, Vision OCR | [#38](https://github.com/L-K-M/Sortomat/pull/38) | open, five review rounds answered |
| 5 | The Inbox-first main window | [#39](https://github.com/L-K-M/Sortomat/pull/39) | open |
| 5 | Undo on the notification itself | [#40](https://github.com/L-K-M/Sortomat/pull/40) | open |
| 5 | Guardrails: a monthly spend ceiling, power holds, a pause that survives a relaunch | [#41](https://github.com/L-K-M/Sortomat/pull/41) | open |
| 5 | Pass efficiency: one stability pause per pass, undo that prunes its own folders, byte-aware names | [#42](https://github.com/L-K-M/Sortomat/pull/42) | open |
| 5 | Half the CI bill, and no artifact upload | [#43](https://github.com/L-K-M/Sortomat/pull/43) | open |
| — | Rule engine v2 — typed conditions, real globs, five date attributes, a template language, traces, lossless migration, a step editor, a dry run, a match count, and a rule validator | `claude/rule-engine-v2`, stacked on #38 | branch, no pull request yet |

**Read this before merging anything.** #38–#43 were each green, then took one
or more review rounds whose fixes were pushed **after GitHub Actions stopped
running jobs on this account** — from about 18:47 UTC on 2026-09-05 every run,
macOS and Linux alike, fails in under fifteen seconds with no runner, no steps
and no logs, which is what an Actions spending limit looks like from the inside.
The last commit on each of those branches has therefore never been compiled.
When runners come back: re-run CI on each, fix what it finds, and merge in the
order #38 → #39–#43 (only #38 has a dependent, and `claude/rule-engine-v2`
gets its pull request once #38 is in). #43 exists partly to halve what a
green day costs.

Findings closed by that work and **not** repeated below: the twenty-three
wave-3 engine items (W1–W38); the hand-read items H-A, H-B, H-C, H-D, H-F,
H-G, H-K, H-Q, H-S, H-T, H-W, H-Y; the verified product findings P0-2, P0-7 through
P0-11; and five of the seventeen verified product findings the engine closed —
P0-12 and P0-16 (globs), P0-13 (dates), P0-14 (tokens and captures), P0-15
(kind), P0-17 (Unicode normalization).

---

## 1. The rule engine — the largest open piece

`claude/rule-engine-v2` implements phases 1–3 of the five-phase plan: the data
model, the pure evaluator, the fact source, lossless migration in both
directions, the pipeline wiring, and a step editor. It is green, and stacked on
#38 — open its pull request once that merges, when its diff is only its own.

**What a rule is now.** `Rule` gained `schemaVersion`, `steps`, `fallback` and
`destinationRoots`; `preRules` survives as a downgrade projection written by a
custom `encode(to:)`, so a config edited by this build still opens in the last
one. `LegacyMigration.upgrade` runs in **both** `init(from:)` and the memberwise
initializer — the second one is not optional: every template, every rule pack
and every test builds rules memberwise, and without it they all decode with
empty `steps` and quietly stop matching.

### 1.1 Actions — three of eight are carried out

`ActionExecutor` exists and runs from `Pipeline.apply` **after** `Journal.record`,
so a side effect that fails can never cost the user their undo. It applies
`addTags`, `removeTags` and `notify`; the plan carries the effects now, where
`plan(from:)` used to drop them, so what the Inbox previewed is what runs.
`rename` was already correct (it is planned as a move that never leaves the
file's own folder).

Still not carried out, and now *named in the editor* rather than silently
skipped — `ActionExecutor.supported` is the one list and `RuleValidator` reads
it:

- **`reveal` and `open`** — not for want of an API. An automatic rule over a
  four-hundred-file backlog would open four hundred windows, and "how many is
  too many" is a product decision. A cap, or "only when the main window is
  open", or only for the first file in a batch. **S** once decided.
- **`setComment`, `setLabel`, `runShortcut`** — each needs an API worth writing
  with a compiler at hand: Finder comments have no public setter (`MDItemSetAttribute`
  is not it), `URLResourceValues.labelNumber` is read-only on some SDKs, and
  `runShortcut` means spawning the `shortcuts` binary. **M**
- **`trash`** — accepted, then planned as a move, so the file lands in the
  destination folder instead of the Trash. Safe and undoable, and not what the
  rule says; the validator says so. Journal it as a move whose destination is
  the file's `~/.Trash` URL and `Journal.undo` reverses it with no new code; if
  `FileManager.trashItem(at:resultingItemURL:)` proves awkward to bridge, move
  into `<target>/_Trash/` instead. **S**

One design note that survives all of this: tag, comment and label changes need
their own `SideEffectJournal` keyed by the existing `batchID` before undo can
reverse them. They are not file moves and do not belong in `journal.jsonl`,
whose shape is frozen. Today an undone move leaves the tags it added behind —
which matches what Hazel does, and is worth deciding rather than inheriting.

### 1.2 `RuleValidator` — done, with one piece left

`RuleValidator.findings(for:)` is on the branch: pure, no disk, no cost, safe to
run on every keystroke, and each finding carries the exact step, condition or
action it belongs to. It covers the empty `any` group, the step that claims
every file and strands the ones after it, the step that matches and does
nothing, two placements in one step, unknown attributes, operators, action types
and template tokens, a regex the engine refuses to run, a content condition
under `metadataOnly`, a destination whose last component can render empty, a
capture with nothing capturing, an action naming a destination root that does
not exist, and `askModel` with no instruction anywhere. `RuleIssues` draws them
in the editor under "Before you enable this".

What is left is where they are drawn: a per-step badge on `StepCard` and an
inline marker on the offending condition row, rather than one list. The finding
already carries `stepID` and the condition's `UUID`, so this is view work only.

Two rules kept it useful and are worth keeping: an **error** is a rule that
cannot do what it says, a **note** is a rule that works but probably surprises
its author; and no finding may be wrong, because a validator that cries wolf
gets switched off. The migrated legacy rules are the yardstick — they come
through silent.

### 1.3 `dryDecide` and `matchCount` — already there

Both exist on the branch (`Pipeline.dryDecide(file:rule:allowModel:)` returning
a `DryRun`, and `Pipeline.matchCount(rule:limit:)` returning
`(matched, scanned, needsModel)`), and the rule editor's "Try it" row already
calls them. What is *not* built on top of them yet: the "● 12 match now" pill
beside each step, the menu-bar file drop, the Inbox's Check now, and the live
"your folder right now" pane (§7).

### 1.4 Nested condition groups in the editor

The model supports any depth; `StepCard` edits one level and shows a nested
group as a read-only row. A recursive `ConditionGroupView` with depth rails is
the answer — never a nested `List`, and never `\.self` as an identity:
`ConditionTest` and `ConditionGroup` both carry `id: UUID` for exactly this.

### 1.5 `{ask:…}` — the model as a token

The highest-value idea in the whole set, and the architecture is already there.
`Bücher/{ask:genre}/{author} — {title}.{ext}` is a rule that is deterministic
everywhere except one slot, and the slot is the only thing anyone pays for.
Implementation: a `{ask:…}` token in a destination makes the step imply an
`askModel` action whose prompt is "answer with one word for: genre", and whose
answer binds only that token. Everything else — the valves, the memo, the
budget — already applies.

### 1.6 Attribute gaps

A `modelSays` **condition** is declared and wired to nothing: the fact lookup
answers `needsModel`, only a `pass` passes, so the test is silently never true.
The `askModel` *action* is the supported way to ask. Either wire the condition
through the same resume path the action uses, or delete the attribute — the
validator flags it as an error in the meantime, which is honest but temporary.

`isQuarantined` is declared and always reports "unavailable": reading it needs
`getxattr` for `com.apple.quarantine`, deliberately deferred as the riskiest API
in the blind set. `contentHash` is wired to a bounded digest; decide whether
`in`/`notIn` against a hash list is worth a full-file read. Packages get no
`DecisionMemo` digest (a directory has no `ContentHash`), so an identical bundle
re-arriving pays for a second classification — `Mover.treeDigest` is the fix.

---

## 2. The interface — what #39 left open

#39 delivers the shell: a main window (⌘0) with Inbox, History and rules grouped
by watched folder; one card per file with the decision as a sentence, its origin,
and the confidence as a word; a single **Automatic · Ask first · Off** mode
replacing two booleans; and a first launch that opens something. The rest of the
specification, in build order:

1. **`RuleEditorView` proper [H-I].** #39 wraps the existing `RuleEditor` in a
   header, so the wall of fields — a bare priority stepper, an unexplained
   "preview only", a free-text extension field, a non-native `TextEditor`
   stroke — is still what a user meets. The designed editor is the step list
   from `claude/rule-engine-v2` plus a Try-it pane, and it needs §1.3.
2. **Welcome window**, four steps, ending on a preview of the user's *own* files
   — and a template gallery sheet. `AppDelegate.didShowMainWindowKey` is where
   first-run currently branches.
3. **Status popover and file drop.** Left-click the funnel for status; drop a
   file on it for "what would happen to this?". The popover retires the
   activity submenu, whose items cannot wrap, so a long path makes the menu
   absurdly wide. The drop needs §1.3.
4. **Token chips behind a flag**, drag reorder, `QLThumbnailGenerator` previews.

Three decisions worth keeping:

- **AppKit shell, SwiftUI panes**, and `HSplitView` rather than
  `NavigationSplitView`: on the macOS 13 floor the newer container is the least
  predictable thing inside an `NSHostingController`, and none of this can be
  compiled locally. It compiled first try; keep the bargain.
- **"Why" is a bottom pane plus a popover** — never a third column.
  `.inspector` is macOS 14, and a trailing column cannot be hidden on 13.
- **The words changed, the code did not.** *preview* → Inbox, *dry run* → Ask
  first, *scan* → check, *quarantine* → "park this, I'm not sure". The old words
  survive in code, logs and the CLI.

---

## 3. Verified product findings, still open

Each was raised by a review fleet and then confirmed against the source by a
second agent whose instructions were to refute it. Ordered by what a user would
notice first.

- **[P0-5] The editing lock is keyed on selection, not on editing.** #39 moved
  it — `MainWindowController` sets `editingRuleID` from the sidebar selection —
  but the shape of the bug survived the move: selecting a rule in the sidebar
  and switching apps for the afternoon still parks that rule, skipped by every
  pass, with nothing on screen saying so. *Fix: key the lock on actual edits
  with a short idle timer, and show it in the rule header.* **S**
- **[P0-3] "Skip" means "until relaunch", and nothing says so.** It clears
  `pendingActions`; the pipeline's `previewed` set still holds the key and the
  ledger records nothing, so the file stays gone this session and is
  re-classified — re-paid — after a relaunch. Users expect "ignore this file" or
  "remind me later"; this is neither. *Fix: make it one of those two,
  explicitly, recording a `.skipped` ledger entry for the first.* **M**
- **[P0-4] Two rules matching one file produce two competing Inbox cards.** In
  automatic mode priority resolves contention because the first rule moves the
  file. In ask-first mode — the default for every new rule — each rule plans
  independently, `ingest` de-duplicates only by `(source, ruleID)`, and "File
  all" executes both: the second fails with "source file vanished", visible only
  in the activity log, while the Inbox reports "Filed N items". The Priority
  stepper promises an arbitration the planning never performs. *Fix: claim files
  by priority at plan time, and show the loser as "superseded by «Invoices»".*
  **M**
- **[P0-6] The notification permission prompt is the first thing the app ever
  shows** — now second, after the main window #39 added, but still before any
  explanation. Decline it and the toggle stays on, forever, pointing nowhere.
  *Fix: ask on first *use*, and reflect a denial in the toggle with a link to
  System Settings.* **S**
- **[P0-1] launchd parity is a README promise.** The documented LaunchAgent puts
  the API key in a plist environment variable in plaintext while the GUI keeps
  it in the Keychain; `Notifier` is GUI-only, so a failing headless run is silent
  apart from exit code 1; and `ProcessLock` means the agent and the GUI cannot
  coexist at all. *Fix: make "the GUI is the agent" true — launch at login
  already exists, so what is missing is a scheduled pass that survives no-one
  being at the menu bar, plus a `sortomat://scan` URL the CLI can poke.* **M**

---

## 4. Open items from the hand-read

Numbering kept from the wave-4 review document (`fable.md`, on the review
branch) so nothing needs re-learning.

**Approachability**

- **[H-E] No provider presets, model picker or "test connection".** Model and
  base URL are free text; a wrong model name fails per file, later, in a log
  line. → a Settings *Model* pane, with pricing autofill.
- **[H-O] The status menu has no "open watched folder"** and no key equivalents
  beyond ⌘, ⌘0 and ⌘Q.
- **[H-H] The recent-activity submenu cannot wrap**, so long paths make it
  absurdly wide, and there is no reveal or undo per line. → the status popover
  (§2.3).

**Correctness and cost**

- **[H-M] The decision memo full-hashes every model-bound file** up to 256 MiB
  before *and* after classification. A `size|mtime` pre-key with a content
  digest only on a hit would cut a backlog's I/O by most of it.
- **[H-R] Recursive rules have no exclusion patterns**, so a rule on
  `~/Documents` descends into `node_modules` and build folders. The engine now
  has `relpath` and a real glob compiler, so this is a *default*: seed new
  recursive rules with a `relpath does not match pattern` step.
- **[H-V] Renaming a rule to an existing name is allowed** — uniqueness is only
  enforced on add and duplicate — and the logs then cannot tell them apart.
- **[H-N] `ProcessLock` makes a launchd `scan-once` refuse whenever the GUI
  runs** — correct, but launchd users get a silent no-op job. Needs a documented
  "delegate to the running app" path. See P0-1.
- **[H-J] `folder «» not in taxonomy`** — a root placement under a taxonomy
  produces an unreadable reason.
- **[H-L] The Spotlight text tier is dead code.** `kMDItemTextContent` via
  `MDItemCopyAttribute` is query-only and almost certainly returns nothing;
  extraction runs anyway, so this is harmless but misleading.
- **[H-P] `Rule.extensions` is applied before the steps**, so a rule limited to
  `pdf` can never route a `.zip` even with an explicit step. Deliberate — it
  keeps non-matching files from being stat-ed at all — but the editor must say
  so, above the step list.

**Chrome**

- **[H-X] The log is a file, opened in TextEdit.** "Open log" hands
  `activity.log` to whatever owns `.log`; there is no in-app viewer, no
  filtering by rule or outcome, and no way to get from a line to the file it
  describes. The status popover (§2.3) is where a real one belongs.
- **[H-Z] The menu-bar funnel reads heavier than its neighbours at 18 pt**, and
  there is no 16 pt-tuned variant.
- **[P1-52] The app icon is full-bleed** — no Apple icon-grid margin, so it
  renders about a quarter larger than every neighbour in the Dock.
- **[P1-53] The brand has three unrelated greens** (icon gradient, AccentColor,
  system `.green`) and no codified palette.

---

*Closed since this document was written:* **H-U** — `L10nTests` now compares the
conversion characters each key consumes in both tables, in order unless either
side uses positional markers (`claude/rule-engine-v2`). A sweep of all 1 818
`L10n.t`/`L10n.plural` call sites across every open branch found no live
mismatch, so it is a guard rail for the next string rather than a fix.

## 5. Collected from the review rounds

Real, verified, and deliberately left out of the pull request that surfaced
them — each is a product decision or a change wider than the diff it appeared
in.

- **Per-file OCR timing, and a per-pass recognition budget.** With OCR in the
  pipeline a file can cost seconds; an image-heavy folder makes a pass feel
  stalled. Log the elapsed time per extraction first, then decide between a
  budget and `.fast` recognition. **S** to measure, **M** to act.
- **A per-rule switch for "Downloaded from".** The field is metadata and its
  query string is stripped, so it stays in metadata-only mode — but it is the
  most identifying metadata there is, and two review rounds flagged it. A
  switch is the honest answer; silently dropping it is not. **S**
- **`PowerSource` behind a protocol.** The fail-open policy — a desktop, or an
  unreadable IOKit answer, counting as plugged in — is the safety-critical half
  of the power guard and cannot be asserted through a `Bool`. **S**
- **Legacy `.xls`/`.ppt`.** `.doc` gets AppKit extraction; its two siblings get
  name and metadata only. Check whether Spotlight's `kMDItemTextContent` covers
  them before writing a reader. **S**
- **The monthly ceiling is re-read between rules, not between files**, so one
  rule over a very large folder can overshoot before the next is held.
  `perScanBudget` is the hard cap on a burst; this is the cap on the month.
  Moving the check into the per-file loop is a small change with a real
  contention question attached. **S**
- **`spreadsheetText` opens the same archive up to three times** — shared
  strings, document properties, and the inline-string fallback each construct
  their own `ZipArchive`, re-running `sizeAllows` and re-parsing the central
  directory. The saving is small (the file is already capped at 64 MB) and the
  cost is restructuring the one function in the extraction branch that has
  produced two regressions from being restructured, so it waits for a green
  compiler and a test that pins the current output first. **S**
- **"Downloaded from", host only.** The query string — where the credentials
  live — is already stripped, but a path can carry a user id, and the field is
  sent in metadata-only mode like every other metadata field. `URL(string:)?.host`
  keeps the classification signal ("a bank's domain files differently") and
  drops the rest. Pairs with the per-rule switch above. **S**
- **Vision recognition blocks a cooperative-pool thread.** `handler.perform` is
  seconds of uninterruptible CPU inside `Task.detached`. Harmless while
  extraction is one file at a time — which it is — and a real constraint the day
  extraction runs in parallel. Revisit then, with
  `withCheckedThrowingContinuation` onto a global queue. **M**
- **Undo prunes empty folders it did not create.** Nothing records which
  directories a move made, so the cleanup removes any empty chain under the
  target root — including a taxonomy skeleton the user pre-made. Recording the
  created subpath on the journal entry would make it exact. **S**

---

## 6. The unverified backlog

Sixty-six findings survived deduplication but not verification — the fleet was
cut short. They are *leads*, not claims: check each against the source before
acting. The strongest, grouped:

*Rules and templates* — a blank rule is created **enabled** and an empty prompt
is accepted, so paid instruction-less calls can start as soon as folders are
picked [P1-13]; the seeded e-book rule pairs an English prompt with a
German-only 31-genre taxonomy [P1-14, E1-20]; the invoice and e-book templates
ship *zero* deterministic steps, so a keyless user gets nothing from them
[P1-16] — and with the engine in place that is now easy to fix; one rule = one
watched folder, so covering Downloads *and* Desktop means two diverging copies
of the same prompt [P1-10]; there is no whole-config backup/restore, only
single-rule packs [P1-12].

*Inbox* — "Undo" on a copy row silently deletes a file, with the same label and
no hint the row was a copy [P1-18]; a nearly-right suggestion can only be filed
or skipped, never corrected — and a correction is the single most valuable thing
the memo could learn [P1-23]; the empty state says "Nothing to file" when the
truth is "no rules are enabled" or "you are paused" [P1-19]; no Quick Look, no
Finder tags [P1-24].

*Rule editor* — the extension filter silently rejects `*.pdf` and `pdf;epub`
[P1-37]; `pathWarnings` stats the filesystem on every body evaluation, which is
every keystroke [P1-40].

*Engine* — an undone mis-filing is not forgotten by the memo, so a
byte-identical re-arrival is filed the same wrong way automatically [E1-10];
model answers with a leading `/` or `~` are rejected *after* payment and re-paid
every interval forever [E1-16]; `ZipArchive` reads the whole EPUB into memory
before checking its 200 MB cap [E1-14]; Sortomat's own moves re-trigger a full
pass because FSEvents paths are not filtered [E1-25]; model-supplied `reason`
text reaches the line-based `activity.log` unsanitized [E1-9].

*Chrome* — the update check steals focus with a modal alert [P1-51]; image-only
buttons have no accessibility labels, so VoiceOver reads "plus", "minus",
"trash" [P1-48]; two About surfaces disagree and the standard panel's copyright
is empty [P1-26].

---

## 7. Ideas worth having

Thirty-six proposals came out of three idea panels; these are the ones that
survive a second look, in the order I would build them. Effort in brackets.

**They make the deterministic engine genuinely better**

- **`{ask:genre}` — the model as a token inside a template.** [M] See §1.5. The
  single most Sortomat-shaped idea in the set.
- **Smart attributes and token filters.** [M] `{amount}`, `{iban}`,
  `{invoiceNumber}` extracted by the engine, so nobody writes a regex for the
  five things everyone extracts.
- **Rule examples as regression tests.** [M] Every rule keeps a handful of "this
  file → this destination" examples; `sortomat test` re-runs them and the editor
  shows a green/red strip. Editing a rule stops being scary because the rule can
  prove it still does what it did.
- **Carried captures and `continue`.** [M] A matching step hands its captures to
  the next one — staged pipelines ("strip the vendor prefix, *then* file by
  year") without one giant regex. The `continue` action already exists; the
  capture store just needs to survive the step boundary.
- **Backfill mode.** [L] Point it at a folder with 8 000 files, get a coverage
  report ("4 100 of these match a rule deterministically"), approve by bucket,
  resume where it stopped. The difference between a tool for new files and a
  tool for the mess you already have.

**They make it approachable**

- **Describe it, don't configure it.** [L] Type "put invoices from Amazon in
  Finanzen/2026" and get a *draft rule* — conditions, actions and destination
  filled in, every field editable, nothing saved until the user looks at it. One
  model call at rule-writing time to avoid a thousand at filing time.
- **The fill-in-the-blanks editor.** [L] The summary sentence *is* the control:
  every underlined fragment is a popover. `StepSentence` already renders the
  sentence; this makes it interactive.
- **"Your folder right now."** [M] A live pane beside the editor: the actual
  files in the watched folder, each showing what this rule would do with it as
  you type. Needs `MatchCounter` and `dryDecide` (§1.3).
- **Imagine a file.** [S] Type a filename that does not exist and watch the rule
  evaluate against it. Free — `FileFacts` already accepts a stub source — and
  the fastest way to learn a pattern language.
- **Drop a folder on Sortomat and it profiles it** [M] — 60 % PDFs named
  `Rechnung_*`, 30 % screenshots — and proposes starter rules from what it
  found. The first-run experience writes itself.
- **"Why isn't anything happening?"** [M] A readiness checklist that never nags
  and always answers: no rules enabled, paused, held on battery, monthly limit
  reached, no key, watched folder missing, everything already filed. Half of
  those states now exist and are reported in the menu bar; the Inbox's empty
  state is where they belong.

**They make it a pleasure**

- **The receipt.** [M] A small tear-off ticket after an automatic filing: what
  moved, why, and an Undo that stays valid for a minute. #40 put Undo on the
  notification; the receipt is the in-app version, for people who keep the
  window open.
- **Ghost example.** [M] The destination template rendered against a real file
  from the folder, live, as you type. Removes an entire class of "why did it go
  there?".
- **Rewind.** [L] Drag the History timeline backwards and watch filings undo in
  batches. Undo as a *place*, not a button.
- **Clean streak.** [S] How many days in a row your Downloads folder ended
  empty. Trivial, and the only part of the app that will ever make someone smile
  on purpose.
- **"Where did it go?"** [S] A menu-bar search over everything Sortomat ever
  filed. The journal already holds every answer; nothing reads it back.
- **Finder Quick Action: "File with Sortomat."** [M] Any file, anywhere,
  right-click, filed by whichever rule claims it.

---

## 8. Things that are *not* problems

Recorded so they are not re-raised. Each was claimed by a reviewer and refuted
against the source.

- **A zip bomb can exhaust memory through `DocumentText`** — raised three times.
  `ZipArchive.data(for:)` rejects an entry whose declared uncompressed *or*
  compressed size exceeds 16 MiB **before reading a byte**, and `inflate` hands
  `compression_decode_buffer` exactly that declared size as its destination
  capacity. The cap sits before inflation; the `prefix` in `collect` is a second,
  tighter bound on top of it.
- **The monthly budget has no month** — raised twice. `usage` is loaded through
  `SpendStore.load`, which discards a record from any month but the current one,
  and `accumulate` restarts the counter when the month key rolls over. The
  ceiling lifts by itself on the first.
- **New L10n keys must be added to every `.strings` table** — this project has
  no `.strings` files. The tables are in `L10n.swift` and `L10nTests` enforces
  parity over them.
- **Confidence is on a 0–100 scale** — `normalizeConfidence` divides by 100 for
  any value above 1, and has since the wave-2 train.
- **`%d` is handed a Double** — the call site passes
  `Int((confidence * 100).rounded())`.
- **`.filed` is never inferred** — the one site that actually files a file passes
  `kind: .filed` explicitly; duplicates and skips are correctly `.info`.
- **The stale-plan guard is inert** — `process()` stamps `plan.fingerprint`
  before the plan is queued.
- **`Journal.lastBatch` can select undo tombstones, so a second undo redoes the
  batch** — `recent()` folds away both the tombstones and the entries they
  reverse before `lastBatch` ever sees them, and every caller goes through it.
- **`Ledger.prune`'s `fileExists` follows symlinks** — discovery requires
  `.isRegularFileKey`, which is false for a symlink, so no live ledger entry can
  name one.
- **German "Einsetzen" should be "Einlegen"** — macOS's own German localization
  uses *Einsetzen* for Paste.
- **`Data.write(to:)` is deprecated** — it is not; `write(to:options:)` has a
  defaulted parameter. The deprecated call is `NSData`'s
  `write(toFile:atomically:)`.
- **AppKit has no OpenDocument reader** — it has one,
  `NSAttributedString.DocumentType.openDocument`, for text documents. Which is
  why the fix was to *name* the type rather than skip the reader.
- **The GUI should refuse to run without the process lock** — the GUI is the
  user's primary surface; refusing to launch because a cron job holds the lock
  is worse than the race it avoids. The CLI still refuses and the GUI logs the
  overlap.
- **The rule-signature denylist should be an allowlist** — the denylist fails
  toward spurious re-planning, the allowlist toward stale previews. The safer
  failure is the one we have.

Two claims were **right in a way their authors did not realize**, and both are
worth remembering:

- `URL.resourceValues(forKeys: [.fileSizeKey])` does *not* follow a symlink on
  Darwin. Neither does `attributesOfItem`. Only `stat(2)` — or `fstat` on a
  handle you already opened, or resolving the link first — describes the file
  whose bytes you are about to read. This bug has now appeared in three
  different size caps.
- A stringified boolean action cuts *both* ways. `"false"` already skipped,
  which is safe — but `"true"` also fell out of the `isMove` whitelist, so a
  serializer that stringifies its booleans had its "file this" quietly ignored.

---

## 9. Where the numbers came from

So a future reader can judge how much to trust each item.

- **Wave 4 fleets:** 206 findings after deduplication, of which **123 were
  refuted against the source** by an adversarial verification pass, 17 were
  confirmed (§3), and 66 were never reached (§6). The refutation rate is the
  point: most were plausible from a diff and false in context — a guard three
  lines above the quoted range, a cap enforced by the caller, a "silent failure"
  that logs one function up.
- **Review bot rounds:** four on the integration train, one on #37 (nine
  actionable items, all resolved; the second round never returned), five on #38,
  and one each on #39–#42. Everything applied, declined or refuted is recorded
  in the commit messages, which is where the reasoning lives. The rounds earned
  their keep twice over: round 5 on #38 caught that round 3 of the same PR had
  silently disabled the fallback it added, and the round on #41 caught a Core
  Foundation over-release — `takeRetainedValue` on a Get-rule function — that
  would only ever have crashed in the field.
- **Tests:** 106 before wave 4, 161 after the integration train, and about 320
  with wave 5 — the exact figure is whatever the last green CI run reports.

---

*The two design specifications behind §1 and §2 — 2 303 lines for the engine,
2 379 for the interface — were each produced from three independent proposals,
scored and synthesized. They are not in the tree; this document is their
executive form, and every decision that matters is recorded above.*
