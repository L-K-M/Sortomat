# Sortomat — Fable review, wave 4

*A full review of Sortomat as of `23061b8` (main, 2026-09-05), plus the work
that came out of it. Written by Claude (Fable). Earlier waves live in
`fable-is-awesome.md`; this document does not restate them, it builds on them,
and the still-open items from them are consolidated into `ANALYSIS.md` at the
end of this session.*

## 0. The short version

Sortomat's safety core is genuinely good and got better in the eighteen review
branches that sat unmerged for two months. What holds the app back is not
correctness any more; it is **power** and **approachability**:

- The deterministic layer is a toy next to Hazel: five match kinds on the file
  name and age, three actions, no grouping, no content, no dates-added, no
  tags, no rename, no tokens beyond `{name}{ext}{year}{month}{day}`. Everything
  interesting is pushed to a paid, non-deterministic model call.
- The interface is a settings dialog, not a product: a legacy tab box, a wall of
  fields with jargon labels (taxonomy, dry run, quarantine, pre-rule, glob), a
  menu-bar menu of disabled lines, a review list you can't read, and a first
  launch that shows nothing at all.
- Half of what a real file *is* never reaches the classifier: Word, RTF,
  OpenDocument, spreadsheets, presentations, images and scanned PDFs arrive as
  a name and a byte count. Pages/Numbers/Keynote documents are invisible
  altogether because they are folders on disk.

This wave does four things:

1. **Lands the open review train.** The eighteen wave-2 PRs (#17–#34) are
   composed into one integration PR with the three silent-loss composition
   hazards resolved explicitly ([PR #35](https://github.com/L-K-M/Sortomat/pull/35)).
2. **Closes the wave-3 findings that were designed but never shipped** (the
   branches in that review's plan never reached GitHub), plus new engine
   findings from this wave, as `claude/data-safety-hardening`.
3. **Reads what files actually contain** on-device — office documents,
   spreadsheets, presentations, HTML, images (OCR), scanned PDFs (OCR),
   document packages — as `claude/extraction-power`.
4. **Designs and builds the two drastic changes the owner asked for**: a
   Hazel-class deterministic rule engine (conditions, groups, typed
   attributes, actions, a token language, decision traces, lossless
   migration) and a new, approachable interface around it.

Everything below is anchored to code; file:line references point at `23061b8`
unless a branch is named.

## 1. Method

- A complete hand-read of every Swift file (5.9k lines), every test, both
  workflows, the project file, and all eighteen open PR diffs (3.9k lines).
- Four background review fleets: six engine-side finders (data safety,
  pipeline/concurrency, extraction/security, LLM valves, performance,
  tests/CI/docs) and five product-side finders (UX, visual/layout,
  localization/copy, deterministic-power gap, missing features), each finding
  deduplicated and then adversarially verified by an independent agent told
  to refute it and to check whether the integration branch already fixes it;
  three independent rule-engine designs and three independent UI designs,
  each panel scored and synthesized by a judge; three idea panels (delight,
  power, approachability); and one audit of the composed integration branch.
- CI (Xcode 16.2 on macos-14) is the only compiler available to this session;
  every branch here was pushed and compiled there before being counted as done.

## 2. What was done with the eighteen open PRs

All eighteen were CI-green individually, small, and fixing something real, so
none was dropped. They were merged locally in the conflict-minimizing order the
wave-3 review computed; the first twelve merged clean and the last six
conflicted exactly where predicted. Resolutions worth recording:

| Hazard | Resolution on `claude/wave2-integration` |
| --- | --- |
| W30 `budget-and-keyless` × `watching-robustness` | scan-loop accounting keeps both the `unstable` counter (drives the follow-up pass) and the key-deferred/budget-hit split |
| W31 `maintenance-rotation` × `decision-memo` | `Pipeline.persist()` = prune, save ledger, save memo |
| W32 `spend-persistence` × `maintenance-rotation` | `appendLog` rotates first, then stamps with the shared formatter |
| W33 plural hacks | the three reintroduced `%d thing(s)` strings use `L10n.plural`, which now takes extra positional arguments |
| W19 config lost on quit | `flushOnTerminate` writes a pending debounced config save synchronously |
| decision-memo cost | files above 256 MiB are never full-hashed for the memo |

Result: [PR #35](https://github.com/L-K-M/Sortomat/pull/35), 52 files, 147 tests
green (up from 106). #17–#34 are closed as superseded once it merges.

## 3. Findings

Severity is by user impact. **[H#]** items come from this wave's hand-read,
**[F#]** from the verified finder fleets (section 3.x), and prior IDs are cited
where a wave-3 item was still open and is now fixed.

### 3.1 Data safety and the engine core — fixed on `claude/data-safety-hardening`

| ID | Finding | Fix |
| --- | --- | --- |
| W1 | `ContentHash.digest` turned a mid-read I/O error into a valid-looking digest of the prefix; three fail-closed guards rested on it | read errors yield nil |
| W2 | `FileManager.moveItem` copies-then-deletes across volumes *without* verification, so the verified fallback was mostly dead code | cross-volume detected up front → verified path always |
| W3 | failure cleanup in `copyVerifyDelete` deleted whatever occupied the target, even a file Sortomat never created | only a target this call created is removed |
| W4 | the plain copy path left a truncated file under the canonical name after a failed copy | same cleanup for copies |
| W5 | move-undo relocated whatever currently sat at the destination | journal entries stamp `size|mtime`; undo refuses a replaced file |
| H-F | `Journal.record` swallowed write errors: a move without an undo record, silently | logged loudly |
| W6 | `HTMLText.decodeEntities` was quadratic on bare ampersands; `strip` ran on unbounded markup | bounded semicolon search, input cap |
| W35 | EPUB XML parsed with external entities enabled (XXE into folder names and the model prompt) | `.nodeLoadExternalEntitiesNever` |
| W36 | zero-width, bidi-override and DEL characters survived sanitization | stripped |
| W8 | an empty route template (the default of a freshly added pre-rule) expanded to the absolute `/{name}` and failed forever; an emptied quarantine folder did the same after the model was paid | empty means "the target itself" |
| W9 | extension forcing deleted the last dotted segment of stems like `… at 10.15.32` | only a *recognized* wrong extension is replaced |
| W10 | `.` segments became "Unknown" folders and defeated taxonomy | dropped |
| W11 | taxonomy checked `folder` while placement used `relative_path` | enforced on the applied path |
| W12 | a missing or unparseable confidence bypassed the threshold (fail-open) | nil counts as low when a threshold is set; commas, spaces, words parse |
| W13 | `"action": false` decoded as a move | booleans/null/numbers read for their sign; unintelligible → skip |
| W14 | failed model calls were invisible to the per-check budget | they count |
| W15 | a non-JSON 200 body (captive portal, proxy page) was retried four times | terminal |
| W37 | globs became `.*.*.*` regex chains; user regexes had no ReDoS guard | O(n·m) glob matcher; nested-quantifier regexes rejected |
| W34 | four reason strings were hard-coded English inside a German UI | localized |
| W-CLI | a typo'd CLI command booted a second, never-exiting GUI | any bare argument is a CLI call; `help`/`version` added |
| W38 | no tests for deflate entries, the retry taxonomy, fail-closed Mover branches | added (scripted-HTTP stub, deflate fixtures) |
| H-A | **Document packages were never candidates.** `candidateFiles` required `isRegularFile`; `.pages`, `.numbers`, `.key`, `.rtfd`, `.textbundle` are folders, so the "document" kind's own extension list could never match and a Pages file dropped into a watched folder was ignored forever | packages are single candidates, never descended into; stability probes count items and bytes; cross-volume moves verify every file inside |

### 3.2 Extraction — fixed on `claude/extraction-power`

| ID | Finding | Fix |
| --- | --- | --- |
| W7 | `.html`/`.htm` fed raw markup (head, CSS, JS) to the classifier | visible text |
| H-B | no text at all from `.doc/.docx/.rtf/.rtfd/.odt/.xlsx/.pptx` | AppKit's document reader (one call, no dependencies); zip-of-XML for spreadsheets, slides and a fallback for bare docx |
| H-C | no OCR: screenshots, photographed receipts and scanned PDFs were a file name | Vision on-device text recognition, downsampled and size-capped; the description tells the model it is reading OCR output; metadata-only rules never OCR |
| H-K | `FileContext` dates used the user's calendar (era years on Buddhist/Japanese systems) while the engine pins Gregorian | Gregorian |
| — | Spotlight "where from" (download source) never described | described |
| — | image facts (pixel size, capture date, camera) never described; location is deliberately never read | described, also for metadata-only rules |

### 3.3 Open findings from the hand-read (documented for the redesign or ANALYSIS.md)

- **[H-D] First launch is invisible.** A menu-bar-only app that opens nothing,
  posts nothing, and seeds one disabled rule with empty folders. A new user
  does not know it launched. → first-run window (UI redesign).
- **[H-E] No provider presets, model picker or "test connection".** Model and
  base URL are free text; a wrong model name fails per file, later, in a log
  line. → provider presets with pricing autofill and a one-click connection
  test (UI redesign).
- **[H-G] History decodes the whole journal on the main thread** on every
  appearance (`HistoryTab.reload` → `Journal.recent`). Fine at 200 entries,
  a stutter at 20 000.
- **[H-H] The recent-activity submenu cannot wrap;** long paths make the menu
  absurdly wide, and there is no reveal/undo per line. → popover (UI redesign).
- **[H-I] The rule editor is a wall of fields**: a bare priority stepper,
  "Preview only" without explanation, a TextEditor with a hand-drawn border,
  free-text extensions. → sentence-shaped editor (UI redesign).
- **[H-J]** `folder «» not in taxonomy` — a root placement under a taxonomy
  produces an unreadable reason. → reason wording in the engine v2 trace.
- **[H-L]** `kMDItemTextContent` via `MDItemCopyAttribute` is query-only and
  almost certainly returns nothing; the "Spotlight text tier" is dead code that
  misleads readers. Harmless (extraction runs anyway); remove in engine v2.
- **[H-M]** The decision memo full-hashes every model-bound file up to
  256 MiB before *and* after classification; a large backlog reads a lot of
  bytes once. Consider a `size|mtime` pre-key with a content digest only on
  a hit.
- **[H-N]** `ProcessLock` makes a launchd `scan-once` refuse (exit 3) whenever
  the GUI runs — correct, but launchd users get a silent no-op job. Needs a
  documented "delegate to the running app" path (URL scheme or XPC).
- **[H-O]** The status menu has no "open watched/target folder", no shortcut to
  Review, and no keyboard equivalents beyond ⌘, and ⌘Q.
- **[H-P]** `Rule.extensions` is applied *before* pre-rules, so a rule limited
  to `pdf` can never route a `.zip` even with an explicit pre-rule; surprising
  precedence that engine v2 makes explicit (extensions become a condition).
- **[H-Q]** The stability probe sleeps 700 ms *per file* inside each batch;
  with the default concurrency of 2, a 1 000-file backlog spends ~6 minutes
  asleep. One probe per pass (stat all, sleep once, re-stat) costs 0.7 s.
- **[H-R]** Recursive rules have no exclusion patterns; a rule on `~/Documents`
  descends into `node_modules`, build folders and app caches.
- **[H-S]** Undo leaves behind the empty folders a move created
  (`Genre/Author/`), so undone experiments litter the target.
- **[H-T]** `sanitizeComponent` truncates at 150 graphemes; APFS caps names at
  255 *bytes*, so a long CJK title fails with `ENAMETOOLONG` in a retry loop.
- **[H-U]** EN/DE tables are checked for key parity but not for format-specifier
  arity; a `%@` vs `%d` divergence crashes at runtime. → arity test.
- **[H-V]** Renaming a rule to an existing name is allowed; logs then can't
  tell them apart.
- **[H-W]** Notifications: one title, no actions (undo/reveal), no thread
  grouping.
- **[H-Y]** The scan timer re-reads its interval only after the current sleep
  ends: dropping 600 s to 15 s takes up to ten minutes to apply.
- **[H-Z]** The menu-bar funnel reads heavier than its neighbours at 18 pt; no
  16 pt-tuned variant.
- **[H-CI]** The CI artifact upload fails with "artifact storage quota has
  been hit" on every red run (the failure artifact is the *only* artifact and
  has no retention limit). Set `retention-days: 3`. Also: the two most recent
  `main` CI runs (August) are red with expired logs; the composed branch is
  green, so this is not a code failure — re-check after the next merge.

### 3.4 Product findings the fleets raised **and** an adversarial verifier confirmed

Seventeen survived. Each was checked against the source by a second agent whose
instructions were to refute it; the file:line references are that agent's, not
the finder's.

**The engine's deterministic half is wrong as often as it is weak**

- **[P0-13] Age and `{year}/{month}/{day}` silently mean *modification* time.**
  `DeterministicEngine` reads `contentModificationDate` for both. Browsers,
  mail clients, AirDrop, `unzip` and `curl` all preserve the origin's
  `Last-Modified`, so a 2019 invoice downloaded this morning is "older than 30
  days" on the first pass and files into `2019/`. Nothing in the UI says which
  date is used, so the user cannot even predict it. Hazel exposes Date Added,
  Created, Modified and Last Opened separately — engine v2 must too, and
  should default to *date added* for age.
- **[P0-14] Route templates throw away everything interesting.** `matches()`
  returns `Bool` and discards the `NSTextCheckingResult`, so
  `^Rechnung[-_ ](\d{4})-(\d{2})` cannot route to `Finanzen/{1}/{2}` — the
  canonical Hazel rename is impossible. `expandRoute` knows five tokens: no
  date *formats* (`{date:yyyy-MM}`), no date *sources*, no `{parent}` or
  `{relpath}` (a file found at `watch/2020/Trip/IMG.jpg` loses that context on
  a recursive rule), no `{counter}`, `{kind}`, `{size}`.
- **[P0-12] Globs are anchored, the help implies they are not.** `globToRegex`
  wraps the pattern in `^…$`, so `Screenshot`, `IMG_` and `.pdf` — exactly what
  someone types coming from Finder or Hazel's "name contains" — match nothing.
  The seeded template works around it with `*creenshot*`, which is proof the
  authors know. Nothing tells the user the pattern matches zero files.
- **[P0-16] Globs reject brace sets and character classes.** `*.{jpg,png}` and
  `IMG_[0-9]*.jpg` are escaped into literals; a glob containing `/` can never
  match, because matching runs on `lastPathComponent`. Silent no-ops, all of
  them.
- **[P0-17] Matching is Unicode-normalization-sensitive.** Filenames from HFS+
  volumes and many apps are NFD (`Ärzte` = `A` + `U+0308` + `rzte`); a pattern
  typed into a SwiftUI field is NFC, and ICU's regex engine does not implement
  canonical equivalence. So `*Ärzte*` misses the file. `Sanitizer`
  NFC-normalizes *output* already; the matcher never normalizes *input*. For a
  German-first audience this is routine, not exotic.
- **[P0-15] "Kind" is free text against a hand-maintained table.** The
  placeholder advertises `image, pdf, ebook…` while the engine does a
  dictionary lookup on the whole untrimmed lowercased string, so `image, pdf`
  and `image ` match nothing forever. The table has no svg/avif/heic-raw,
  no dmg/iso/pkg, no code or font kinds, and an extensionless file can never
  have a kind. `UTType` already knows all of this, including declared types
  from installed apps.

**State that does not survive a relaunch, or a window being left open**

- **[P0-2] Pause is not persisted.** It is a plain `@Published var` with no
  `Config` field. The emergency brake pulled at 23:00 because a rule is
  misfiling is released by the next launch — including the relaunch the update
  checker itself offers.
- **[P0-5] The editing lock is keyed on selection, not on editing.**
  `editingRuleID` is non-nil whenever Settings is open with a rule selected —
  the resting state of that window, since a rule is auto-selected on appear.
  Leave Settings open and switch to another app for the afternoon and that rule
  is skipped by every pass, with no way to say "I'm done, run it now".
- **[P0-3] "Dismiss" means "until relaunch", and nothing says so.** It clears
  `pendingActions`; the pipeline's `previewed` set still holds the key, and the
  ledger records nothing. So the file stays gone this session and is
  re-classified — re-paid — after a relaunch. Users expect "ignore this file"
  or "remind me later"; this is neither.
- **[P0-4] Two rules matching one file produce two competing Review rows.** In
  live mode priority resolves contention because the first rule moves the file.
  In preview mode — the default for every new rule — each rule plans
  independently, `ingest` de-duplicates only by `(source, ruleID)`, and
  "Apply all" executes both: the second fails with "source file vanished",
  visible only in the activity submenu, while Review reports "Applied N
  changes". The Priority stepper promises an arbitration the preview never
  performs.

**Cost and power awareness**

- **[P0-8] There is no money cap.** The only budget is calls *per pass*; at the
  default 60 s interval, a folder that keeps producing unclassifiable files
  bills up to 14 400 calls a day. The spend meter is display-only — nothing
  reads it to stop scanning. The integration branch's keyless-deferral path
  (pre-rules still run, model-bound files defer with an activity line) is
  exactly the mechanism a monthly cap needs; only the comparison is missing.
- **[P0-9] Scans ignore power and time of day.** The timer loops
  unconditionally and FSEvents fires immediately; nothing consults
  `isLowPowerModeEnabled`, thermal state or AC status. A laptop on battery with
  a backlog hashes, OCRs and calls out at the worst possible moment, and a
  NAS-backed watch folder is woken every minute all night.
- **[P0-1] launchd parity is a README promise, not a feature.** The documented
  LaunchAgent puts the API key in a plist environment variable in plaintext
  while the GUI keeps it in the Keychain, `Notifier` is GUI-only so a failing
  headless run is silent apart from exit code 1, and the new `ProcessLock`
  means the agent and the GUI cannot coexist at all. The honest target is "the
  GUI *is* the agent".

**Interface and platform manners**

- **[P0-11] Notifications carry no actions, no payload, no click handler.** No
  `categoryIdentifier`, no `userInfo`, and the delegate implements only
  `willPresent` — clicking a banner does not even open the window. The
  integration branch's per-pass summaries and journal batch ids are precisely
  the payload an "Undo" button needs.
- **[P0-6] The notification permission prompt is the first thing the app ever
  shows** — before any window or explanation. Decline it and the "Notify about
  filed files and failures" toggle stays on, forever, pointing nowhere.
- **[P0-10] The app leaves a dead menu bar behind.** `revertToAccessoryIfNoOrdinaryWindows`
  flips the activation policy back to `.accessory` without handing focus on;
  AppKit leaves the Sortomat menu in the bar with no key window until the user
  clicks another app.
- **[P0-7] Spend is formatted as `String(format: "$%.4f")`.** In the German UI
  that is a dollar sign, in front, with a decimal point — for a user who may be
  paying in EUR or running a free local model.

### 3.5 The unverified backlog

Sixty-six findings survived deduplication but not verification (the
verification fleet was cut short mid-flight). They are not asserted here; they
are the queue `ANALYSIS.md` inherits, and the strongest of them are:

*Rules and templates* — a blank rule is created **enabled**, and an empty
prompt is accepted, so paid instruction-less calls can start as soon as folders
are picked [P1-13]; the seeded e-book rule pairs an English prompt with a
German-only 31-genre taxonomy [P1-14, E1-20]; the invoice and e-book templates
ship *zero* pre-rules, so a keyless user gets nothing from them [P1-16]; one
rule = one watched folder, so covering Downloads *and* Desktop means two
diverging copies of the same prompt [P1-10]; there is no whole-config
backup/restore, only single-rule packs [P1-12].

*Review* — Return anywhere in the window fires "Apply all", the riskiest
action, as the default button with no confirmation [P1-17]; "Undo" on a copy
row silently deletes a file, with the same label and no hint the row was a copy
[P1-18]; a nearly-right suggestion can only be applied or dismissed, never
corrected — and a correction would be the single most valuable thing the memo
could learn [P1-23]; the empty state says "Nothing to file right now" when the
truth is "no rules are enabled" or "you are paused" [P1-19]; no Reveal, no
Quick Look, no Finder tags [P1-24].

*Rule editor* — the prompt is the hero and the deterministic pre-rules are
buried ~700 pt below it, which is the pipeline upside down [P1-35]; kind and
age take free text behind a placeholder that promises a list, so "images" or
"30 days" fails silently [P1-34]; there is no way to test a rule against
existing files without enabling it or paying [P1-45]; rule state is two
independent toggles plus an unexplained coloured dot [P1-36]; pre-rule cards
are card-in-card, invisible in light mode and sunken in dark [P1-38].

*Engine* — an undone mis-filing is not forgotten by the memo, so a
byte-identical re-arrival is filed the same wrong way automatically [E1-10];
model answers with a leading `/` or `~` are rejected *after* payment and
re-paid every interval forever [E1-16]; `ZipArchive` reads the whole EPUB into
memory before checking its 200 MB cap and then copies it again [E1-14];
Sortomat's own moves re-trigger a full pass because FSEvents paths are not
filtered [E1-25]; model-supplied `reason` text reaches the line-based
`activity.log` unsanitized [E1-9].

*Chrome* — the app icon is full-bleed with no Apple icon-grid margin, so it
renders about a quarter larger than every neighbour in the Dock [P1-52]; the
brand has three unrelated greens and no codified palette [P1-53]; the update
check steals focus with a modal alert [P1-51]; image-only buttons have no
accessibility labels, so VoiceOver reads "plus", "minus", "trash" [P1-48].

### 3.6 What the fleets got wrong

Two hundred and six findings survived deduplication; **123 were refuted against
the source** by the verification pass and never reached this document. The
pattern is worth recording, because it is the failure mode of review fleets in
general: most refuted items were *plausible from a diff and false in context* —
a guard that exists three lines above the quoted range, a cap enforced by the
caller, a "silent failure" that logs one function up. The engine fleet in
particular produced 91 deduplicated findings and had 70 of them refuted, which
says less about the finders than about how much of this codebase's safety
reasoning is written where a reader skimming a hunk will not see it.

Two of the review bot's rounds on the integration PR were refuted the same way
and are recorded in the commit messages rather than here: `.filed` "is never
inferred" (the one site that actually files a file passes it explicitly), and
the removed/renamed L10n keys "leave orphan call sites" (every literal key in
the module resolves). One claim was *right in a way the reviewer did not
realize*: `URL.resourceValues(forKeys: [.fileSizeKey])` does not follow a
symlink on Darwin, which CI proved by failing a test that asserted it does.


## 4. The deterministic engine

Three independent engine designs were produced against the same brief, then
synthesized into one implementation-ready specification
(`designs/engine-SYNTHESIS.md`, ~2 300 lines). The shape:

**A rule stays a rule.** `Rule` remains "one watched folder + one target folder
+ defaults" and keeps its `id` — the key the ledger, the decision memo, the
journal, preview memory, rule packs and `AppState.signature(of:)` all depend
on. Hazel-style rules live *inside* it as `steps: [RuleStep]`, each with a
`when` (a nestable `all`/`any`/`none` group over ~35 typed attributes) and a
`then` (an ordered action list). Steps are first-match-wins unless an action
says `continue`; `rule.fallback` decides what happens to a file no step
claimed. Nothing splits, nothing is renumbered, and no history is orphaned.

**The model becomes one action among many.** `askModel` fills `{model.folder}`,
`{model.title}`, `{model.confidence}` and friends, and the *following* actions
decide what to do with them. So a rule can be fully deterministic, fully
model-driven, or — the interesting case — hybrid:
`Bücher/{model.genre}/{author} — {title}.{ext}` is a rule that pays for exactly
one word. `Pipeline.routing` (taxonomy, confidence threshold, quarantine) still
runs unchanged before the engine resumes, and a quarantine short-circuits the
rest of the step so no template can route around a safety valve.

**Each confirmed defect gets a named fix:**

| Wrong today | Engine v2 |
| --- | --- |
| age and dates silently mean *mtime* [P0-13] | five distinct date attributes; `dateAdded` (`addedToDirectoryDateKey`) is the default basis for new rules, and migrated rules get `dateModified` pinned **explicitly and visibly**, so nobody's behaviour changes behind their back |
| five fixed tokens, captures discarded [P0-14] | one template language: `date:` formats, named and indexed captures scoped by `captureAs`, `{parent}`, `{relpath}`, `{counter}`, `{size}`, `{kind}`, `or:`/`default:` fallback chains, `{{`/`}}` escapes |
| "kind" is free text over a hand-kept table [P0-15] | a closed token set resolved through `UTType` conformance, with a 16-byte sniffer for extensionless files and the legacy table pinned as a compatibility mode |
| globs anchored while the help implies otherwise; `{a,b}` and `[0-9]` escaped to literals [P0-12, P0-16] | a real glob compiler (`*`, `**`, `?`, `[...]`, `{a,b}`) built as an NFA — no regex translation, so no ReDoS — with anchoring kept *and documented*, plus `contains`/`beginsWith`/`endsWith` operators for what people actually meant |
| NFC pattern never matches an NFD filename [P0-17] | every comparison folds both sides through NFC + locale-independent case folding |
| three actions, one per pre-rule | move, copy, rename, sortIntoDatedFolder, addTags, removeTags, setComment, setLabel, trash, reveal, open, notify, runShortcut, askModel, quarantine, skip, stop, continue |
| no way to test a rule without paying or enabling it [P1-45] | evaluation is a *pure synchronous function* of `(Rule, FileFacts, Date)`, so "test against this file" costs nothing and needs no filesystem |

**Three properties make it safe to ship blind.**

1. *Nothing in the config tree can throw on decode.* Every open vocabulary
   (`Attribute`, `Operator`, `Kind`, `ActionType`) is a `RawRepresentable`
   **struct** with hand-written single-value `Codable`, not a `String` enum —
   because `Decodable` synthesis for a `String` enum throws on an unknown raw
   value, and one attribute from a newer build would otherwise make the whole
   `Config` undecodable and throw the user's rules into a `.corrupt-<stamp>`
   file. An unknown attribute evaluates to false, says so in the trace, and
   round-trips untouched on re-save.
2. *Interpolated values can never create folders.* The input design claimed a
   `/` inside a token value is neutralized by `Sanitizer.sanitizeComponent`. It
   is not: `Sanitizer.destination` splits the relative path on `/` **before**
   sanitizing each component, so a title like "AC/DC" would silently create a
   directory. The renderer escapes separators inside every interpolated value.
3. *The safety core is not touched.* `Sanitizer`, `Mover`, `Journal` and
   `Ledger` are unmodified; the engine only ever *reads* attributes. `trash` is
   journaled as a move whose destination is the file's `~/.Trash` URL, so the
   existing undo reverses it unchanged.

**Every decision carries a trace.** Per condition: the attribute, the actual
value found, the operator, and one of eleven verdicts — including which member
of a `none` group was the culprit and where a short-circuit stopped the walk.
The one-line summary goes to the activity log and the journal's `reason`; the
full trace sits behind a disclosure in the preview. "Why did it go there?"
stops being a question.

**Migration is lossless in both directions.** Pre-rules become steps field by
field, `step.id == preRule.id`, characters that the new glob and template
languages gave meaning to are escaped, and `preRules` is *never cleared* in
memory: it is re-derived on encode as a downgrade projection, so an older build
opening a newer config does *nothing* rather than something wrong.

It ships in five phases, and the first three are testable end to end through
`config.json` and rule packs before a single line of the new editor exists —
which is what keeps the largest SwiftUI change in the app off the critical
path.

## 5. The interface

Three independent designs were produced against the same brief and the same
constraints (macOS 13 SDK floor, SwiftUI inside AppKit windows, no
dependencies, CI as the only compiler), then synthesized. The synthesis is
`designs/ui-SYNTHESIS.md`; what follows is the decision record.

**The product is the list of things it wants to do, not a settings form.**
Today the app's only real window is a `TabView` of settings, and the thing a
user actually needs — "here is what I would do with your files, is that right?"
— lives in a second window called *Preview changes* that nothing points at.
That inverts. The new main window (`⌘0`, `NSWindowController` +
`NSToolbar` + `NSSplitViewController`) opens on an **Inbox**, and the rule
editor is the second thing.

The eleven decisions that settle the rest:

1. **The engine contract is engine v2's**: a rule stays "one watched folder →
   one target folder" and gains `steps: [RuleStep]`. No `WatchedFolder` type,
   no splitting one rule into several. `rule.id` is the key for the ledger, the
   decision memo, the journal, preview memory and rule packs; keeping it intact
   is what makes the migration lossless and keeps "your 2 rules became 5" from
   ever happening.
2. **AppKit shell, SwiftUI panes.** No `NavigationSplitView`, no SwiftUI
   `.toolbar`, no `.searchable` — those three are the least predictable surface
   inside an `NSHostingController` on the 13.0 floor, and this session cannot
   run a compiler.
3. **The Inbox is the home screen** and the default sidebar selection.
4. **"Why" is a bottom pane** (`VSplitView`) inside the Inbox, plus a popover
   everywhere else — never a third column (`.inspector` is macOS 14).
5. **Destination and rename fields are a monospaced `TextField` + a token menu
   + a live "e.g." line.** `NSTokenField` chips are a later, flag-gated
   upgrade: the example line carries most of the value at a fraction of the
   risk.
6. **Rows reorder by `⌘⌥↑/↓` and context menu;** drag is polish added last,
   and it is the accessible path anyway.
7. **Nested condition groups are a recursive `VStack` with depth rails** —
   never a nested `List`.
8. **"Always do this" inserts a deterministic step into the same rule.** The
   file stops costing a model call, the rule's history stays attached, and the
   sidebar does not grow.
9. **Snooze reuses `Ledger.Status.failed(retryAfter:)`** plus a small
   `snoozed.json`; no new ledger status is required.
10. **No "Parked"/"Unsure" sidebar section.** Quarantine plans are Inbox rows
    marked *Unsure* whose destination is the unsure folder — a destination is
    not a place in the app.
11. **Settings is a separate `⌘,` window** (`NSTabViewController(tabStyle:
    .toolbar)`); the main window never shows an API-key field.

**The words change too**, everywhere the user can read them (the old ones
survive in code, logs and the CLI): *Preview changes* → **Inbox**; `dryRun` →
the rule mode **Ask first**; `enabled && !dryRun` → **Automatic**; pre-rule →
**step**; `prompt` → **Instruction**; `taxonomy` → **Allowed folders**;
quarantine → **Unsure folder**; `confidenceThreshold` → **How sure it must
be**; confidence → a four-step heat scale (**Certain · Sure · Probably ·
Unsure**). *Dry run*, *taxonomy*, *quarantine*, *pre-rule* and *LLM* are never
shown again.

Also landing with it: a first-run **Welcome** window (four steps) so the app
stops being invisible on launch [H-D]; a **template gallery** sheet; provider
presets with a **Test connection** button [H-E, P1-28]; a menu-bar **status
popover** that replaces the un-wrappable activity submenu [H-H] and accepts
**dropped files** in a "what would happen?" mode; **actionable notifications**
with Undo [P0-11]; and a per-rule **Try it** pane that answers "does this match
anything?" without enabling the rule or paying for a call [P1-45].


## 6. Ideas worth having

Three idea panels ran against the same brief — *delight*, *deterministic
power*, *approachability* — and produced thirty-six proposals with effort and
"wow" estimates. The ones that survive a second look, in the order I would
build them.

**They make the deterministic engine genuinely better**

- **`{ask:genre}` — the model as a token inside a deterministic template.**
  `Bücher/{ask:genre}/{author}.{ext}` is a rule that is deterministic
  everywhere except one slot, and the slot is the only thing anyone pays for.
  It collapses the current "either a pre-rule or the model" fork into a
  gradient, and it is the single most Sortomat-shaped idea in the set. (M)
- **Smart attributes and token filters.** `{date:added|yyyy-MM}`,
  `{amount}`, `{iban}`, `{invoiceNumber}` — extracted by the engine so users
  never write a regex for the five things everyone extracts. (M)
- **Rule examples as regression tests.** Every rule keeps a handful of "this
  file → this destination" examples; `sortomat test` (and a green/red strip in
  the editor) re-runs them. Editing a rule stops being scary because the rule
  can prove it still does what it did. (M)
- **Carried captures and `continue`.** A step that matches can hand its
  captures to the next step instead of ending the pass — staged pipelines
  ("strip the vendor prefix, *then* file by year") without one giant regex. (M)
- **Backfill mode.** Point it at a folder with 8 000 files, get a coverage
  report ("4 100 of these match a rule deterministically"), approve by bucket,
  resume where it stopped. This is the difference between a tool for new files
  and a tool for the mess you already have. (L)

**They make it approachable**

- **Describe it, don't configure it.** Type "put invoices from Amazon in
  Finanzen/2026" and get a *draft rule* — conditions, actions and destination
  filled in, every field editable, nothing saved until the user looks at it.
  One model call, at rule-writing time, to avoid a thousand at filing time. (L)
- **The fill-in-the-blanks editor.** The summary sentence *is* the control:
  every underlined fragment is a popover. This is the honest version of "the
  rule is a sentence" — the app's own tagline, currently contradicted by the
  editor. (L)
- **"Your folder right now."** A live pane beside the editor: the actual files
  in the watched folder, each showing what this rule would do with it as you
  type. It answers the question every rule editor in the world dodges — *does
  this match anything?* (M)
- **Imagine a file.** Type a filename that does not exist and watch the rule
  evaluate against it. Free, instant, and the fastest way to learn a pattern
  language. (S)
- **Drop a folder on Sortomat and it profiles it** — 60 % PDFs named
  `Rechnung_*`, 30 % screenshots — and proposes starter rules from what it
  found. The first-run experience writes itself. (M)
- **The trust dial:** *Ask me first · Do it and tell me · Do it quietly.* Three
  words replace two booleans and one coloured dot. (S)
- **"Why isn't anything happening?"** A readiness checklist that never nags and
  always answers: no rules enabled, paused, no key, watched folder missing,
  everything already filed. Today the answer is silence. (M)

**They make it a pleasure**

- **The receipt.** A small tear-off ticket after an automatic filing: what
  moved, why, and an Undo that stays valid for a minute. It turns the app's
  most anxious moment — "it did something while I wasn't looking" — into its
  most reassuring one. (M)
- **Ghost example.** The destination template renders against a real file from
  the folder, live, as you type. Cheap, and it removes an entire class of
  "why did it go there?". (M)
- **Rewind.** Drag the History timeline backwards and watch filings undo in
  batches. Undo as a *place*, not a button. (L)
- **Clean streak.** How many days in a row your Downloads folder ended empty.
  Trivial, and it is the only part of the app that will ever make someone
  smile on purpose. (S)
- **"Where did it go?"** A menu-bar search over everything Sortomat ever filed
  — the journal already holds every answer; nothing reads it back. (S)
- **Finder Quick Action: "File with Sortomat."** Any file, anywhere,
  right-click, filed by whichever rule claims it. (M)
