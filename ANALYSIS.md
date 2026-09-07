# Sortomat — the working analysis

*What is done, what is left, and enough detail on each open item that it can be
picked up cold. This is the document to read first and to keep current.
It supersedes the still-open half of two review records that stay in the tree
for provenance — `fable-is-awesome.md` (waves 1–3) and `fable.md` (wave 4) —
which say how each finding was arrived at and which of them were refuted.*

*Last updated when wave 5 finished merging. Every `file:line` reference points
at `main` at that point unless a branch is named.*

---

## How to work on this repo

Seven things that cost real time to learn, in the order they will bite.

1. **CI is the only compiler.** There is no macOS toolchain in the review
   environment, so `.github/workflows/ci.yml` (Xcode 16.2 on `macos-14`) is
   where Swift is first parsed. Push early, push small, and read the
   `Testing failed:` block — `xcbeautify` prints the error messages there
   without file or line, and the full text a few lines further down. A round
   trip is about seventy seconds. **Run `Tools/check/run` before every push**:
   seven scripts that answer, without a compiler, the questions a compiler asks
   first — every localized key exists in both languages, every format string
   consumes what its call site passes, every type that claims a protocol
   implements it, every initializer call site still matches its type, and
   every exhaustive switch still covers its enum (trap 3 below), every static
   call site passes its arguments in the order the declaration lists them, and
   every test method sits inside the class whose helpers it calls. Each
   exists because that mistake was made here and cost a cycle. They do not
   typecheck; a clean run means the mechanical mistakes are gone, not that the
   branch builds. `Tools/check/README.md` says what each one cannot see.
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
7. **A run that finishes in ten seconds with no runner is not a build failure.**
   For two days every workflow on this repository — macOS *and* Linux, on
   `main` and on every branch — was created, reported "completed" within thirty
   seconds, ran no steps, and left no log at all (`get_job_logs` answers HTTP
   404). The cause was **repository visibility**: a private repository draws on
   the account's included Actions minutes, and when those are gone *every*
   runner class stops, which is why it looked account-wide rather than like a
   macOS problem. Public repositories get minutes and artifact storage free,
   and making the repository public is what brought CI back. Check visibility
   and the minute allowance first — I spent two days confidently blaming a
   spending limit, which was the same shape of answer and the wrong one.

---

## Scoreboard — what shipped

| Wave | What | Where | State |
| --- | --- | --- | --- |
| 1 | 16 fix PRs (#1–#16) | — | merged |
| 2 | 18 review branches (#17–#34), composed into one train | [#35](https://github.com/L-K-M/Sortomat/pull/35) | merged; the originals are closed as integrated |
| 4 | CI failure artifacts expire, so a red run stops failing twice | [#36](https://github.com/L-K-M/Sortomat/pull/36) | merged |
| 4 | Engine-core hardening: fail-closed hashing, verified cross-volume moves, document packages as candidates, the classification valves | [#37](https://github.com/L-K-M/Sortomat/pull/37) | merged |
| 5 | On-device extraction: office documents, spreadsheets, decks, OpenDocument, HTML text, Vision OCR | [#38](https://github.com/L-K-M/Sortomat/pull/38) | merged, six review rounds answered |
| 5 | The Inbox-first main window | [#39](https://github.com/L-K-M/Sortomat/pull/39) | merged |
| 5 | Undo on the notification itself | [#40](https://github.com/L-K-M/Sortomat/pull/40) | merged |
| 5 | Guardrails: a monthly spend ceiling, power holds, a pause that survives a relaunch | [#41](https://github.com/L-K-M/Sortomat/pull/41) | merged |
| 5 | Pass efficiency: one stability pause per pass, undo that prunes its own folders, byte-aware names | [#42](https://github.com/L-K-M/Sortomat/pull/42) | merged |
| 5 | One CI build per push instead of two, artifact upload kept | [#43](https://github.com/L-K-M/Sortomat/pull/43) | merged |
| 5 | Chrome: the icon on Apple's grid, antialiased at every size, one palette, a lighter menu-bar mark | [#45](https://github.com/L-K-M/Sortomat/pull/45) | merged |
| 5 | The wave-4 review record kept in the tree (`fable.md`) | [#44](https://github.com/L-K-M/Sortomat/pull/44) | merged |
| 5 | Rule engine v2 — typed conditions, real globs, five date attributes, a template language, traces, lossless migration, a step editor with a live match count, a dry run, a rule validator, side effects that run, the model as one word in a destination | [#46](https://github.com/L-K-M/Sortomat/pull/46) | merged, seven review rounds |
| 5 | Undo that says so when there is nothing left to undo, and a batch undo that says why it refused | [#47](https://github.com/L-K-M/Sortomat/pull/47) | merged, four review rounds |

**All of wave 5 is on `main`.** Getting here took a two-day detour worth one
sentence of memory: the last third of the
wave was written with no compiler at all, because CI was down for the reason in
trap 7 above, and each branch got a second reader's pass instead. That pass
found eight real defects in the engine branch (§1) and the compiler then found
one more it could not have — `URLResourceValues.tagNames` is get-only in the
Swift overlay, so tag-writing did not compile. Reading is a good substitute for
a compiler on logic and a poor one on SDKs.

Findings closed by that work and **not** repeated below: the twenty-three
wave-3 engine items (W1–W38); the hand-read items H-A, H-B, H-C, H-D, H-F,
H-G, H-K, H-Q, H-S, H-T, H-W, H-Y; the verified product findings P0-2, P0-7 through
P0-11; and five of the seventeen verified product findings the engine closed —
P0-12 and P0-16 (globs), P0-13 (dates), P0-14 (tokens and captures), P0-15
(kind), P0-17 (Unicode normalization).

---

## 1. The rule engine — landed, phases 1–3 of five

[#46](https://github.com/L-K-M/Sortomat/pull/46) landed phases 1–3 of the
five-phase plan: the data model, the pure evaluator, the fact
source, lossless migration in both directions, the pipeline wiring, a step
editor, a validator, and the side-effect executor. Two thirds of it was written
with no compiler (see the scoreboard) and then read by a second model, which
found and fixed eight things worth knowing the shape of, because each is a
class rather than a typo: the model's `folder` was never derived from its
answer, so `{model.folder}` rendered empty through the pipeline while the unit
test handed the engine a ready-made answer; a memo hit returned the raw routing
and skipped the actions after `askModel`; `decide` deferred on a spent budget
*before* the memo lookup; the resume walk skipped the actions before the
asking one on a builder that is fresh every walk; the step count counted only
steps that *place* a file; three `ForEach`es over `indices` crashed on delete;
a test stub conformed to `FactSource` with one of six requirements; and a
step's own `ModelStepOptions` were decoded, validated and never read. The
pattern in all eight: a feature proven by a test that constructs the input the
real caller never produces. Test through the pipeline, not beside it.

When the compiler came back it found one thing reading had not, and it is the
honest measure of what reading can do: `URLResourceValues.tagNames` is
**get-only** in the Swift overlay, so `ActionExecutor` could not write a Finder
tag at all. It writes through `NSURL.setResourceValue(_:forKey:)` now. One
compile error in 7 286 lines across 40 files — and exactly the kind of question
(what does this SDK actually expose?) that no amount of careful reading
settles.

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
- **`trash`** — accepted, and then planned as a *skip*, because
  `Placement.relativePath` is nil for it and `plan(from:)` requires one: the
  file is left exactly where it is. Safe, and not what the rule says; the
  validator warns, and now says accurately which of the two happens. Journal it
  as a move whose destination is the file's `~/.Trash` URL and `Journal.undo`
  reverses it with no new code; if
  `FileManager.trashItem(at:resultingItemURL:)` proves awkward to bridge, move
  into `<target>/_Trash/` instead. **S**

One design note that survives all of this: tag, comment and label changes need
their own `SideEffectJournal` keyed by the existing `batchID` before undo can
reverse them. They are not file moves and do not belong in `journal.jsonl`,
whose shape is frozen. Today an undone move leaves the tags it added behind —
which matches what Hazel does, and is worth deciding rather than inheriting.

### 1.2 `RuleValidator` — done

`RuleValidator.findings(for:)` is pure: no disk, no cost, safe to
run on every keystroke, and each finding carries the exact step, condition or
action it belongs to. It covers the empty `any` group, the step that claims
every file and strands the ones after it, the step that matches and does
nothing, two placements in one step, unknown attributes, operators, action types
and template tokens, a regex the engine refuses to run, a content condition
under `metadataOnly`, a destination whose last component can render empty, a
capture with nothing capturing, an action naming a destination root that does
not exist, and `askModel` with no instruction anywhere. `RuleIssues` draws them
in the editor under "Before you enable this".

**Where they are drawn is now settled.** Each finding is a caption under the
condition or action it names, with a mark in the step's header as the summary;
`RuleIssues` keeps only what belongs to the rule as a whole and has nowhere
else to go. The hand-rolled privacy hint in the condition row went with it.

Doing that turned up the validator's one wrong finding, worth recording
because the shape recurs: the privacy check read `FileFacts.cost(of:) >=
.content` as "does this open the file". It is a different question.
`duplicateInTarget` is a `probe` — dearer than a content read — that asks an
index and opens nothing, so a working rule got a red error; and `title`,
`authors`, `subjects` and `language` ask Spotlight first, so "can never match"
overstated them (they are a note now). `FileFacts` names both sets beside the
lookups that produce them, and `RuleCatalog`'s `needsContent` is derived from
them rather than stored, because those two lists had already drifted on
exactly that attribute — the editor stayed quiet while the validator called
the rule broken.

The review rounds found a second finding of that shape. The token checker ran
on every action's template, but two action types do not hold a token template:
`sortIntoDatedFolder` reads its as a *date format*, and `runShortcut` reads its
as a Shortcuts *name*. A shortcut called "Convert {heic}" is a perfectly good
shortcut and was being called a broken template — an error, on a rule that
works. Both are exempt now, and `runShortcut` keeps the check that is right for
a name: it must not be empty.

Two rules kept it useful and are worth keeping: an **error** is a rule that
cannot do what it says, a **note** is a rule that works but probably surprises
its author; and no finding may be wrong, because a validator that cries wolf
gets switched off. The migrated legacy rules are the yardstick — they come
through silent.

### 1.3 `dryDecide` and `matchCount` — there, and the step pill is built on them

Both exist (`Pipeline.dryDecide(file:rule:allowModel:)` returning a `DryRun`
with a `matched` flag read off the trace, and `Pipeline.matchCount(rule:limit:)`
returning `(matched, scanned, needsModel)`); the rule editor's "Try it" row
calls them, and every `StepCard` now carries "12 of 200 files match this step",
recounted as the conditions are typed — debounced through `task(id:)`, and
only while every condition is answerable by a `stat`, because a content
condition would mean one extraction per file per keystroke. What is *not* built
on them yet: the menu-bar file drop, the Inbox's Check now, and the live "your
folder right now" pane (§7).

One thing still worth doing: `matchCount` runs *on* the
`Pipeline` actor — up to five hundred `stat`s that block a pass in flight, and
that queue behind one. Nothing in `dryDecide`, `matchCount`, `evaluationContext`
or `candidateFiles` touches actor state, so all four can be `nonisolated` —
**but only together with the caller moving off the main thread**: a
`nonisolated` method runs on whoever calls it, and `AppState.matchCount`
calls from `@MainActor`, so the same change without a `Task.detached` around
the call would move those five hundred `stat`s onto the main thread and turn
"the count waits for the watcher" into "the editor freezes". Both halves, or
neither. **S**

### 1.4 Nested condition groups in the editor

The model supports any depth; `StepCard` edits one level and shows a nested
group as a read-only row. A recursive `ConditionGroupView` with depth rails is
the answer — never a nested `List`, and never `\.self` as an identity:
`ConditionTest` and `ConditionGroup` both carry `id: UUID` for exactly this.

### 1.5 `{ask:…}` — the model as a token

**The behaviour exists; only the sugar is missing.** A step can now ask the
model for one value and place the file itself:

    if   stem matches ^(?<author>[^-]+) - (?<title>.+)$
    then ask the model for the genre
         move to Bücher/{model.folder}/{match.author} — {match.title}.{ext}

That did not work before: when the answer arrived, `bindModel` claimed the
placement immediately, so any later `move` in the step found the builder
terminal and was silently ignored — `{model.folder}` could never appear inside
a template a person wrote. The model's answer now yields when the step places
the file itself, and a *quarantined* answer still wins outright, because a
guess the taxonomy refused must not end up inside a folder name.

The pipeline half had the same shape of bug and is fixed too: the answer the
engine was handed carried only `relativePath`, so `{model.folder}` and
`{model.filename}` rendered empty on every real file. They are now read off
the path that is actually applied — the same one the taxonomy was checked
against, and the only thing a remembered verdict carries — so a model that
answered with one `relative_path`, or a memo hit, still names a folder and a
name. A step's own prompt is applied as well (§1.6), which is what makes "ask
for the genre" a different question from the rule's.

What is left is the spelling. `{ask:genre}` in a destination should imply the
`askModel` action with the prompt "answer with one short value for: genre",
and bind only that token, so the rule reads as one line instead of two actions.
Nothing about the valves, the memo or the budget needs to change: this is a
rewrite of the step at edit time — `StepCard` or a `RuleStep.desugared()` run
on save — not a new path through the engine. **S**

### 1.6 Per-step model options — applied, half-editable

`ModelStepOptions` — a step's own prompt, taxonomy, privacy mode and confidence
threshold — now lays over the rule's from the moment a step asks, so the
question, the valves and the extraction read the same settings. The editor
offers the prompt as the ask-the-model action's one field; taxonomy, privacy
mode and threshold per step are still hand-edited JSON. Worth surfacing as a
disclosure under the action rather than three more fields in the row. **S**

Two smaller things on the same path, both deliberate for now: a *second*
`askModel` further down the same step is not asked (the resume runs with the
model disallowed, and the routing result stands), and the decision memo is
keyed by the rule, so two steps in one rule with different prompts share
remembered answers — the remembered path is re-routed through each step's own
valves on every hit, which keeps the taxonomy honest but not the question.
Neither shape appears in any rule the migration or the templates produce.

### 1.7 Attribute gaps

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

## 2. The interface — what is still to build

#39 delivered the shell: a main window (⌘0) with Inbox, History and rules grouped
by watched folder; one card per file with the decision as a sentence, its origin,
and the confidence as a word; a single **Automatic · Ask first · Off** mode
replacing two booleans; and a first launch that opens something. The rest of the
specification, in build order:

1. **`RuleEditorView` proper [H-I].** #39 wrapped the existing `RuleEditor` in a
   header, so the wall of fields — a bare priority stepper, an unexplained
   "preview only", a free-text extension field, a non-native `TextEditor`
   stroke — is still what a user meets. The designed editor is the step list
   #46 landed plus a Try-it pane, and it needs §1.3. This is the largest
   single gap between what the engine can now do and what a person can reach.
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

Numbering kept from the wave-4 review document (`fable.md`, in the tree) so
nothing needs re-learning.

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

*[H-Z] and [P1-52] closed with [#45](https://github.com/L-K-M/Sortomat/pull/45):
the app icon sits on Apple's 824-of-1024 grid (it was full-bleed, so it
rendered about a quarter larger than every neighbour in the Dock), and every
size is filtered down from one master — the old generator skipped downsampling
for the 1024px icon, which is the one on a release page. The icon itself is now
the artwork in `media-sources/icon.png`: `Tools/generate_icon.py` fits it to
the grid rather than drawing a tile, so replacing the icon is replacing that
one PNG. The menu-bar funnel is inset, and stays a monochrome silhouette — a
photographic icon does not reduce to an 18-point template image.*

- **[H-X] The log is a file, opened in TextEdit.** "Open log" hands
  `activity.log` to whatever owns `.log`; there is no in-app viewer, no
  filtering by rule or outcome, and no way to get from a line to the file it
  describes. The status popover (§2.3) is where a real one belongs.
- **[P1-53] Three `.green` call sites are still hand-picked** rather than
  taken from the palette: `UIModel.swift:63` (the Automatic mode dot),
  `UIModel.swift:105` (certain / exact confidence) and
  `GeneralTab.swift:29` (the connection-test tick). The blocker is gone — the
  two that lived in files #39 deleted are gone with them — so this is now a
  three-line sweep onto `Color.accentColor` or a named palette constant. **S**

---

*Closed since this document was written:* **H-U** — `L10nTests` now compares the
conversion characters each key consumes in both tables, in order unless either
side uses positional markers (#46). A sweep of all 1 818
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
- **Both undo paths read the entire journal.** `undo(batch:)` and
  `undoLastBatch` load every entry with `limit: .max` and filter in memory. The
  `.max` is deliberate and must stay — a pass over a big folder can exceed any
  window, and a limit would reverse *part* of a batch while reporting the whole
  thing undone (#42 fixed exactly that) — but a `Journal.entries(batchID:)` that
  streams the file and keeps only the matching lines would do the same work
  without holding the whole history in memory. Worth doing when a journal is
  big enough to measure, not before. **S**
- **`AppState` cannot be constructed in a test, so none of its behaviour is
  pinned.** Every test reaches it through `nonisolated static` helpers only,
  because `init()` acquires the process lock, reads the Keychain, requests
  notification authorization, builds FSEvents watchers, starts the timer and
  requests a scan — a unit test that built one would watch the developer's own
  folders. That leaves the class holding most of the app's decisions (when to
  scan, when to hold, what to announce) provable only by reading. An `init`
  that takes its collaborators, or a `.forTesting` construction that starts
  nothing, would unlock a whole category of tests; a `Notifier` delivery hook
  (the shape `L10n.forcedLanguage` already uses) would let those tests assert
  what the app *said*. **M**, and the highest-leverage **M** in this list.
- **An apostrophe inside a quoted filter argument breaks the template.**
  `indexOfClose`, `parseBody` and `splitReplacement` each toggle a `quoted`
  flag with no escape, so `{title|default:'L'été'}` toggles three times, the
  closing brace is read as quoted, and the template reports
  `.unterminatedPlaceholder`. French, Italian and English possessives are
  ordinary values. Doubling — `''` for a literal apostrophe — is the usual
  answer and has to go into all three scanners plus the unquoting. **S** each,
  **M** to be sure they agree.
- **`{n|round:…}` promises fractional spans that `mo` and `y` do not keep.**
  `TimeSpan.cutoff` documents that `1.5h` is ninety minutes, and it is — for
  the fixed-second units. `wholeUnits` rounds, so `1.5mo` is two months and
  nothing in the trace says so. Either round-trip the fraction through days or
  say in the operator help that months and years are whole. **S**
- **`RegexCache` re-scans the pattern for named groups on every match.**
  `firstMatch` calls `namedGroups(in:)` per invocation — an O(pattern) scan and
  a fresh array per file — beside a cache that exists precisely to avoid
  per-file work. Cache the names next to the compiled expression. **S**
- **The five date attributes offer `before`/`after` with a duration field.**
  All five declare `shape: .duration` with examples like "30d", and
  `dateOperators` includes `.before` and `.after`, which compare against a
  calendar date. `ValueShape.date` exists and no attribute uses it, which is
  the tell. Split the operator sets, or wire the shape up. **S**
- **A case drift between the watch root and the file's path costs `relPath`,
  `subfolder` and `depth`.** `FileFacts.relativePath` tests
  `full.hasPrefix(base + "/")` exactly. macOS volumes are case-insensitive by
  default, so a persisted watch root and the spelling an enumerator reports can
  disagree; when they do, all three attributes silently fall back to the file
  name, `""` and `0`. An anchored case-insensitive match is the obvious fix and
  is *not* obviously right: on a case-sensitive volume it would compute a
  relative path for a file genuinely not under that root, trading a visible
  degradation for a wrong answer. Worth doing with a case-sensitivity probe of
  the volume, or not at all. **S** to change, **M** to get right.
- **A side effect that failed is indistinguishable from one that had nothing
  to do.** `ActionExecutor.apply` returns the action *types* it carried out, and
  a tag it skipped because the file already had it looks exactly like a tag it
  could not write. `Pipeline` discards the result at both call sites and reports
  `ok: true` regardless — and for a tag-and-leave skip the side effects are the
  whole operation, so the activity line can say "done" when nothing happened.
  The fix is a return shape that separates "nothing to do" from "tried and
  failed", not another call site reading the existing one. **M**
- **`matchesRegex` on a list attribute says `.unknownOperator`.** `stringList`
  has no regex case, so `tags matchesRegex ^client-` falls through to the
  verdict that means "you typed the operator wrong" — when the operator is real
  and simply unsupported for lists. Either implement it per element (captures
  are meaningless there, which is most of why it was skipped) or add a verdict
  that says "not for this kind of value". **S** either way, and the diagnostic
  is the part that matters. **S**
- **`TemplateDates` builds a `DateFormatter` per token.** Every `{date:…}`
  in a destination constructs one, and a rule with three date tokens
  constructs three per file. `DateFormatter` is famously dear to build and
  cheap to reuse, and `RegexCache` is the pattern already in the tree for
  exactly this. Measure first — a pass is dominated by disk, and a cache keyed
  by format string plus locale plus time zone is only worth it if it shows up.
  **S**
- **`AccentColor` is a green the icon no longer contains.** It was set to the
  midpoint of the old generated icon's green gradient, on the argument that the
  tint the app draws with and the tile it ships in should be one colour. The
  icon is now blue, so that argument now points the other way: every capsule,
  filled dot and `.move` badge in the app is a green that appears nowhere in
  the Dock. Sampling the artwork's blue is a one-value change; whether the
  whole UI should follow the icon is the product question underneath it. **S**
  to retint, **M** to decide.
- **Tags an undo leaves behind.** `ActionExecutor` writes Finder tags after the
  move is journaled, and `Journal.undo` puts the file back with the tags still
  on it. This matches what Hazel does; the fix is the `SideEffectJournal` in
  §1.1, and until then it is worth stating in the UI rather than discovering.
  **S** to say, **M** to fix.

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
- **A notification summary for a file at the volume root would say `→ /`** —
  `commonFolder` ends `guard shared.count > 1 else { return nil }`, and
  `/one.pdf` yields the single path component `["/"]`, so it already answers
  nil. `testNoCommonFolderWhenTheAnswerWouldBeTheRoot` pins it.
- **`Notifier.handler` can run before `AppState` exists** — `state` is assigned
  at `AppDelegate.swift:29` and the handler is installed at line 47, so the
  optional can never be nil when a banner is clicked. (The guard was still
  narrowed to the one case that needs it, because a guard that reads as a
  dependency should have one.)

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
  one each on #39–#42, four on #47 and seven on #46. Everything applied,
  declined or refuted is recorded in the commit messages, which is where the
  reasoning lives. The rounds earned their keep three times over: round 5 on #38 caught that round 3 of the same
  PR had silently disabled the fallback it added; the round on #41 caught a Core
  Foundation over-release — `takeRetainedValue` on a Get-rule function — that
  would only ever have crashed in the field; and the round on #40, which
  arrived after #40 had merged and was triaged against `main` rather than
  dropped with the PR, found that the Undo button on a notification could
  complete in total silence (#47). A review that lands late is still a review.
- **Tests:** 106 before wave 4, 161 after the integration train, 307 on `main` before
  the engine and 449 with it, green on the merge commit.

---

*The two design specifications behind §1 and §2 — 2 303 lines for the engine,
2 379 for the interface — were each produced from three independent proposals,
scored and synthesized. They are not in the tree; this document is their
executive form, and every decision that matters is recorded above.*
