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

*(Sections 3.4–3.9 — the verified fleet findings for pipeline/state,
performance, security, LLM valves, UX, visual, localization, the deterministic
gap and product gaps — are appended below as the fleets report.)*
