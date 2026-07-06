# Sortomat — Full Review

*A living review of Sortomat by Claude (Fable), now spanning three waves.*

*Wave 1 reviewed the app as of `3623512`: a complete hand-read of every Swift
file plus a fan-out of specialized review agents, adversarially verified. Its
16 fix-PRs (#1–#16) are all merged.*

*Wave 2 reviewed the app as of `85065c6` — i.e. **including** the wave-1 fixes.
Method: a second complete hand-read of every Swift file, the full wave-1 diff
re-reviewed for regressions, every previously-documented-but-unfixed item
re-verified against current code, plus idea panels. It opened **eighteen**
implementation branches (PRs #17–#34), all still open as of this wave.*

*Wave 3 (this update) reviews the app as of `3af2b3b` — the current `main`,
which carries the wave-1 fixes and the wave-2 review but **not** the 18 open
PRs. It does two things wave 2 could not: **(1)** a fresh fan-out of 15
dimension finders, 6 PR-diff auditors, a merge-composition analyst and idea
panels — and **(2)** the first real audit of the 18 open branches *as a set*,
including a sim-verified merge order and three "silent-loss" composition bugs
that only appear when two branches merge. Honesty note: the fleet was cut short
by a monthly spend limit after 9 of ~68 agents completed (the six heaviest
finders and the merge analyst landed; the l10n/security/CI/features finders and
the adversarial-verify pass did not). Every wave-3 finding below is therefore
anchored to code I re-read directly — file and line references point at the
evidence at `3af2b3b` — rather than to an unrun verifier. See
[Wave 3](#wave-3--the-post-fix-review) below.*

The short version, updated: the foundation is genuinely good and wave 1
removed the worst data-safety holes. What's left splits into four piles:
**(a)** a handful of places where a wave-1 fix is *incomplete* — right idea,
one call-site short; **(b)** engine edge cases and responsiveness gaps that
were documented but deliberately deferred; **(c)** the trust/product features
(persistent previews, quarantine UI, batch undo, portability) that separate
"works" from "product"; **(d)** polish. Wave 2 ships branches for a large cut
of (a), (b) and (c) — see the [implementation plan](#wave-2-implementation-plan).

Legend: **[B#]/[P#]/[U#]/[F#]/[C#]/[L#]/[I#]** — wave-1 numbering (bug /
performance / UX / feature / CI / localization / idea), kept stable so nothing
needs re-learning. **[R#]** — wave-2 regression or incomplete fix.
**[N#]** — wave-2 new finding. Items marked **→ branch** are implemented in a
dedicated wave-2 branch. Items marked **✅ #n** shipped in that wave-1 PR.

---

## 0. Wave-1 scoreboard

All sixteen wave-1 PRs merged cleanly. For the record:

| Shipped | Items | PR |
| --- | --- | --- |
| Cross-volume verify fails closed, hashes full content | B1, B2 | #1 |
| Non-retryable LLM errors surface immediately; `/v1` base URLs | B10 | #2 |
| Numeric percent confidences normalized; unknown actions skip | B11, B12 | #3 |
| Corrupt config backed up instead of wiped | B3 | #4 |
| `Rule.priority` actually honored; interval clamp | B13, B23a | #5 |
| LLM budget cap holds; target subtree skipped | B14, P7d | #6 |
| UTF-8 tail trim, `<style>/<script>` dotall, zip stored-entry cap | B15, B16, B17 | #7 |
| Keychain update-in-place with checked statuses | B8 | #8 |
| Update checker: Dock icon, honest alerts, post-success stamp, 6 h cadence | B20, B21 | #9 |
| Preview window: dismiss, honest empty state, feedback, richer rows, frames | U1–U4, U10, B19 | #10 |
| Menu-bar badge, real disabled states, ⌘W, foreground notifications | U5, U7, U9, B18 | #11 |
| Rule deletion confirmation + toolbar tooltips | U6 | #12 |
| Launch-at-login toggle | F1 | #13 |
| Pre-release tags publish as GitHub pre-releases; DMG-staple docs | C1, C2 | #14 |
| Undo: ledger pinning, diverged-copy refusal, tombstones | B4, B5, B6 | #15 |
| Localized defaults and template prompts | L1 | #16 |

---

## 1. Wave 2 — regressions & incomplete fixes in the merged work

The most valuable review a second wave can do is audit the first. These are
places where a wave-1 fix is right in spirit but incomplete or has a new cost.

**[R1] The copy-undo "don't destroy edits" guard only looks at the first 4 MiB.**
PR #15 taught `Journal.undo` to refuse deleting a copy that diverged from the
surviving original — but the comparison uses `ContentHash.digest(of:)` with its
*default 4 MiB prefix* limit (`Sortomat/Engine/Journal.swift:84-85`), the exact
bounded-digest trap B2 fixed in `Mover` with `limit: .max`. Edit a >4 MiB copy
anywhere past the prefix, press Undo, and the guard passes — the edited copy is
deleted. **→ branch `claude/undo-hardening`**

**[R2] CLI undo still ping-pongs.** The B4 fix routes *GUI* undo through
`AppState.undo`, which pins the restored file as `skipped` in the ledger
(`AppState.swift:256-261`). `HeadlessRunner.undoLast` still calls
`Journal.undo(entry)` directly (`Sortomat/Engine/HeadlessRunner.swift:57`) —
no ledger pin, so the next `scan-once` re-classifies (re-pays) and re-moves
every file the CLI just restored. The bug class B4 closed is alive on the
second of its two paths. **→ branch `claude/undo-hardening`**

**[R3] "Saved to the Keychain." can still be a lie.** PR #8 made
`Keychain.set` return whether the write succeeded — and no caller reads it.
`AppState.saveAPIKey` ignores the result (`AppState.swift:72-76`) and
`GeneralTab` unconditionally shows the success caption (`GeneralTab.swift:19-28`).
The storage bug is fixed; the UI honesty half of B8 never landed. Also still
here: the caption never clears while typing a new key (U12a).
**→ branch `claude/keychain-feedback`**

**[R4] The budget cap serializes everything once the budget runs low.**
PR #6's `batchCap = max(1, min(cap, budgetRemaining))`
(`Sortomat/Engine/Pipeline.swift:74`) correctly stops overshoot — by shrinking
*the whole batch*, including files that pre-rules would handle for free. With
`perScanBudget: 1` (the cautious configuration) every file in a backlog is
processed in a batch of one, each paying the ~700 ms stability probe serially:
a 1 000-file folder spends ~12 minutes mostly sleeping where wave-0 code ran
8-wide. The cap should bound *LLM-eligible* slots per batch, not batch width.
**→ branch `claude/budget-and-keyless`**

**[R5] `inExecutionOrder()` promises a stability Swift doesn't.** The doc
comment says "stable for equal priorities" (`Sortomat/Model/Models.swift:169-175`),
but `sorted(by:)`'s stability is an implementation detail Swift explicitly does
not guarantee. Equal-priority rules could reorder between runs on a toolchain
change. One-line fix: sort `enumerated()` pairs with an index tiebreak.
**→ branch `claude/budget-and-keyless`**

**[R6] `UpdateChecker.lastResult` is hardcoded English — and dead.** Two
user-facing-looking strings ("Update available: …", "You're up to date (…)",
`Sortomat/Updates/UpdateChecker.swift:83,86`) bypass L10n; meanwhile nothing in
the app ever displays `lastResult`. Localize or delete.
**→ branch `claude/l10n-stragglers`** (localized; kept published for a future About display)

**[R7] History undo has no re-entrancy guard and now hashes on the main actor.**
`HistoryTab.undo` fires an unguarded Task per click (`PreviewView.swift:229-240`);
a double-click double-undoes (the second attempt can only fail, surfacing a
scary error) — and `AppState.undo` runs `Journal.undo`'s content hashing *on
the main actor*, which after R1's full-content fix would mean hashing a
multi-GB copy on the UI thread. Undo gets a busy state and hops off-main.
**→ branch `claude/undo-hardening`**

---

## 2. Wave 2 — new findings

**[N1] Approving a preview executes against whatever is at the path *now*.**
(Promoted from wave-1 footnote B23h — it deserves better than a footnote.)
`PlannedAction` carries no fingerprint of the file it was computed for;
`applyApproved` recomputes `Ledger.fingerprint(plan.source)` at apply time and
executes regardless (`Sortomat/Engine/Pipeline.swift:315-322`). A file can be
fully replaced between "Sortomat suggests X" and the user clicking Apply — the
replacement is then filed under the stale suggestion. Plans now capture the
fingerprint at decide time and apply refuses (with a clear activity entry) when
the file changed. **→ branch `claude/apply-revalidation`**

**[N2] Pending previews go stale and never die.** `ingest` de-duplicates
pending plans by (source, ruleID) (`AppState.swift:198`), but nothing ever
*removes* a plan whose file has since vanished (applying it just errors), and
editing a rule invalidates neither its queued plans nor the pipeline's
`previewed` cache (`Pipeline.swift:15-18`) — so after rewriting a prompt, the
Review tab keeps showing (and the badge keeps counting) suggestions from the
old prompt until relaunch. **→ branch `claude/preview-hygiene`**

**[N3] Quit loses in-memory ledger records.** There is no
`applicationWillTerminate` (`Sortomat/App/AppDelegate.swift`); the ledger is
persisted only at the end of a scan pass (`AppState.swift:191`). Quit mid-pass
and every `skipped` verdict the model was just paid for is forgotten — and
re-paid next launch. **→ branch `claude/spend-persistence`** (terminate flush)

**[N4] Files dated in the future are never processed.** (B23b, re-verified.)
`isStable` requires `Date().timeIntervalSince(modified) > 5`
(`Pipeline.swift:396`) — a camera with a wrong clock or a badly-stamped
download yields a negative interval forever. Fix: compare `abs(…)`, still
requiring the size-stability probe. **→ branch `claude/engine-edge-cases`**

**[N5] A dangling symlink at the destination defeats placement forever.**
(B23e, re-verified.) `resolvePlacement` probes with `fm.fileExists(atPath:)`
(`Sortomat/Engine/Mover.swift:90,104`), which *follows* symlinks — a dangling
link reports "free", `moveItem` then throws, and the file retries into the same
wall every 30 minutes. Probe with `attributesOfItem` (lstat semantics) instead.
**→ branch `claude/engine-edge-cases`**

**[N6] A fake EOCD signature in a zip comment rejects a valid EPUB.** (B23d,
re-verified.) `findEOCD` takes the *last* signature-looking bytes it meets
scanning backwards (`Sortomat/Engine/ZipArchive.swift:121-130`) — bytes
`PK\x05\x06` inside the archive comment win over the real record. Validate the
candidate (comment length must reach exactly EOF) and keep scanning otherwise.
**→ branch `claude/engine-edge-cases`**

**[N7] `Sanitizer` speaks German in every locale.** The fallback for a
component that sanitizes to nothing is a hardcoded `"Unbekannt"`
(`Sortomat/Engine/Sanitizer.swift:34`) — an English user whose model returns a
weird folder name gets a German folder. **→ branch `claude/engine-edge-cases`**

**[N8] No cap on model output.** The request payload sets `temperature` and
`response_format` but no `max_tokens` (`Sortomat/Engine/LLMClient.swift:79-87`);
a rambling model bills unbounded completion tokens for what should be a
five-line JSON answer. **→ branch `claude/llm-hardening`**

**[N9] Dead L10n keys.** Defined and never referenced:
`rules.addFromTemplate`, `about.privacy`, `activity.preRuleRoute`,
`journal.undone`, `journal.undoAll`, `preview.column.file/.action/.destination`,
`preview.cancel` (`Sortomat/Model/L10n.swift`). Two get *used* by wave-2
branches (`journal.undoAll` → batch undo; `journal.undone` → its status line);
the rest are pruned. **→ branches `claude/undo-hardening`, `claude/l10n-stragglers`**

**[N10] `menuNeedsUpdate`'s "Preview changes…" always fires a refresh** — even
while paused or keyless (harmless thanks to the guards, but it looks like a
button that does nothing; documented, not fixed).

---

## 3. Standing backlog, re-verified at `85065c6`

Every wave-1 "documented, not fixed" item was re-checked against current code.
Status and what wave 2 does about it:

| Item | Status | Wave-2 action |
| --- | --- | --- |
| B7 dedup 4 MiB-prefix collisions can strand a distinct file | still present (`Mover.swift:94,107`) | documented trade-off; unchanged |
| B9 GUI ↔ `scan-once` clobber ledger/journal cross-process | still present | **→ branch `claude/process-lock`** (flock on the config dir; headless refuses politely) |
| B22 FSEvents callback can use-after-free on watcher rebuild | still present (`FSEventsWatcher.swift:21,59`) | **→ branch `claude/watching-robustness`** (retained context box + explicit stop) |
| B23b future-mtime files never stabilize | still present | **→ `claude/engine-edge-cases`** (N4) |
| B23c `TextDecoding.decode(_:declared:)` declared-tier dead code | still present (`TextDecoding.swift:13`, no caller passes it) | documented; wiring XML/HTML charset detection is follow-up |
| B23d EOCD fake-signature lockup | still present | **→ `claude/engine-edge-cases`** (N6) |
| B23e dangling-symlink collision blindness | still present | **→ `claude/engine-edge-cases`** (N5) |
| B23f `JournalTests` setenv vs cached environment | **refuted** on re-read: `ConfigStore.directory` reads the env var per access (`ConfigStore.swift:8`), so the `setUp` override is honored | — |
| B23g `sort_epubs.py` size-only dedup | still present (`sort_epubs.py`) | legacy script; README already frames it as historical |
| B23h preview-approve TOCTOU | still present | **promoted to N1 → branch `claude/apply-revalidation`** |
| P1 preview classifications re-paid every relaunch | still present (`Pipeline.swift:15-18`) | needs persistent pending store (F2); designed, not blind-built |
| P2 batch barrier lets one stuck file stall its batch | still present (`Pipeline.swift:78-89`) | documented; sliding-window rewrite deserves a Mac |
| P3 700 ms stability sleep | still present, **but wave-1 overstated it**: the sleeps overlap within a batch, so the cost is ~700 ms per *batch* — except where R4 collapses batches to width 1, which is the actual fix that matters | **→ `claude/budget-and-keyless`** (R4) |
| P4 new files wait for the next timer tick | still present (`Pipeline.swift:396` + no follow-up scheduling) | **→ branch `claude/watching-robustness`** (scan reports deferred-unstable files; AppState schedules one follow-up pass) |
| P5 unbounded ledger / journal / activity.log; main-thread journal reads; ledger rewritten when clean | still present (`Ledger.swift:75-82`, `ConfigStore.swift:70-81`, `Journal.swift:43-52`) | **→ branch `claude/maintenance-rotation`** (log rotation, ledger pruning of vanished paths, dirty-flag saves); journal rotation deliberately *not* done (it's the undo history) |
| P6 watcher teardown/rebuild on every debounced save | still present (`AppState.swift:61-70,110-118`) | **→ `claude/watching-robustness`** (diff the (path, enabled) set) |
| P7a EPUB double memory copy | still present (`ZipArchive.swift:25-28`) | micro; documented |
| P7b Spotlight text normalized before truncation | still present (`FileContext.swift:73-75`) | micro; documented |
| P7c collision loop re-hashes neighbors per placement | still present (`Mover.swift:99-110`) | documented |
| P7e fat `AppState` invalidates every view per keystroke | still present | needs UI profiling on a Mac; documented |
| P7f fresh `ISO8601DateFormatter` per log line | still present (`ConfigStore.swift:72`) | **→ `claude/spend-persistence`** (cached formatter) |
| U8 notification toggle overpromises; missing-folder spam | still present (`AppState.swift:209-215`; `activity.missingWatch` re-fires every pass) | **→ branch `claude/notifications-honesty`** (success summaries, failure summaries, once-per-outage folder alerts) |
| U11 editing lock is invisible | still present (`AppState.swift:24`, no UI reads `editingRuleID`) | **→ branch `claude/rule-editor-guardrails`** (inline "paused while editing" note) |
| U12a stale "Saved" caption | still present | **→ `claude/keychain-feedback`** (R3) |
| U12b window title ≠ menu wording | still present (`L10n.swift:52` vs `:44`) | **→ `claude/l10n-stragglers`** |
| U12c `%d change(s)` plural hacks | still present (`L10n.swift:47,160,161,33`) | **→ `claude/l10n-stragglers`** (tiny one/other plural helper) |
| U12d taxonomy hint never shown | still present (`L10n.swift:87` unused; `RuleEditor.swift:56`) | **→ `claude/rule-editor-guardrails`** (empty-editor overlay placeholder) |
| U12e zero validation in the rule editor | still present | **→ `claude/rule-editor-guardrails`** (missing/equal/nested path warnings, invalid-regex flag on pre-rule cards) |
| U13 first-run is a shrug | still present | see ideas I1/I3; onboarding tour needs a Mac to do honestly |
| L2 hardcoded-English stragglers | partially fixed (#9/#11/#15 localized updates, Close, undo errors); **still English**: `PathField` ("Choose…", "/path/to/folder", `PathField.swift:12-14`), `MainMenu` App/Edit items (`MainMenu.swift:17-31,47-55`), `HeadlessRunner` output (`HeadlessRunner.swift:16,49,59,61`), `GitHubReleaseClient` errors (`GitHubReleaseClient.swift:15-20`), `Sanitizer` fallback (N7), `UpdateChecker.lastResult` (R6) | **→ `claude/l10n-stragglers`** + `claude/engine-edge-cases` (N7) |
| L3 Screenshots template double no-op | still present (`Templates.swift:50-57`: glob→`useLLM` *is* the fall-through; prompt still cites "visible text and the image description" the app never sends) | **→ branch `claude/screenshots-template`** (catch-all skip pre-rule so only screenshot-named files hit the model, `Bildschirmfoto` glob, honest prompt) |
| F2 pending previews don't survive relaunch | still present (`AppState.swift:16`) | designed (pending.json invalidated by rule-edit + fingerprint), deliberately not blind-built; N2 fixes the in-session half |
| F3 quarantine is a roach motel | still present (no UI reads quarantine folders) | needs real UI; see I6, I31 |
| F4 no batch undo; CLI's 5-second "batch" | still present (`HeadlessRunner.swift:52-54`; `JournalEntry` has no batch id) | **→ `claude/undo-hardening`** (per-pass `batchID`, GUI "Undo last check", CLI uses the id) |
| F5 one global model for all rules | still present (`Models.swift:180-233`) | per-rule override designed; not blind-built (UI surface) — see I21 |
| F6 deterministic-only rules held hostage by the key field | still present (`AppState.swift:181,222`, `HeadlessRunner.swift:25-28`) | **→ `claude/budget-and-keyless`** (keyless runs execute pre-rules; LLM-needing files defer like budget-exhausted ones) |
| F7 no image/OCR path | still present | Vision OCR is the right shape; needs a Mac to validate |
| F8 spend resets every launch | still present (`AppState.swift:19`) | **→ branch `claude/spend-persistence`** (monthly persisted usage) |
| F9 rules aren't portable | still present | **→ branch `claude/rule-packs`** (export/import, paths stripped, imports arrive disabled+preview) |
| F10a-d exclusions / collision policy / rename-in-place / retry backoff | still present (`DeterministicEngine.swift:44`, `Mover.swift:99`, `Pipeline.swift:361`, `Ledger.swift:25`) | documented; F10a has a design in I20 |
| C3a `APPLE_TEAM_ID` docs drift | still present (`.github/CICD.md`) | **→ branch `claude/changelog-docs`** |
| C3b `lkm-build` hard dependency in scripts | still present (`scripts/build.sh`) | **→ `claude/changelog-docs`** (documented as optional path) |
| C3c README "instant reaction" oversell | improves with P4's follow-up pass | **→ `claude/changelog-docs`** (wording) |
| C3d AGENTS.md update-cadence claim | fixed by #9's 6 h re-check (claim now roughly true) | — |
| **New:** CHANGELOG says nothing about the 16 merged fixes | (`CHANGELOG.md` Unreleased still lists only pre-wave-1 items) | **→ `claude/changelog-docs`** |

---

## 4. Security & privacy notes (unchanged posture, one addition)

Wave-1's assessment stands: prompt injection is contained to *misfiling inside
the target* by the layered `Sanitizer` (pre-check → sanitize → standardized
prefix re-check), taxonomy and quarantine narrow it further, the update flow is
HTTPS-to-github.com with default certificate validation, and `ZipArchive`
declines what it can't parse safely. Wave-2 hand-checks of the offset
arithmetic (`Int` from `UInt32` on a 64-bit platform, bounds-checked reads),
the EPUB path resolver (still can't escape the archive namespace), and log
hygiene (no Authorization header or key material reaches `activity.log`) found
no new holes. Additions:

- **`max_tokens` absent** is also a cost concern: a file that steers the model
  into rambling multiplies output-token spend per file. Fixed by N8.
- The deeper adversarial sweep planned for this wave (Unicode-normalization
  corners in `sanitizeComponent`, symlinked-intermediate-directory races
  between `createDirectory` and `moveItem`) was cut short by the session
  limit; those two corners remain **unaudited**, flagged here for wave 3.

---

## 5. Ideas — wave 2 additions

I1–I17 from wave 1 remain the trust/power/delight backlog (none shipped yet —
they need a running Mac for honest polish). Wave 2 adds, from the surviving
power/wildcard panel plus the editor's own list. Ones marked **→ built** ship
in this wave.

**Power**
- **[I18] Plan/apply as data**: `plan --json` emits every `PlannedAction`;
  `apply --plan file.json` executes a hand-edited subset; `classify <file>`
  one-shots a single decision. Turns Sortomat into a composable Unix citizen —
  and the decide/apply split already *is* this, minus argument parsing.
- **[I19] launchd recipe installer**: `sortomat install-agent --interval 15m`
  writes and bootstraps the LaunchAgent plist the README currently asks users
  to hand-roll. Pairs with the process lock (**→ built**, `claude/process-lock`)
  that makes GUI + launchd coexistence safe in the first place.
- **[I20] Hazel-parity pre-rule pack**: `sizeOver/UnderMB`, `pathGlob` (real
  exclusion patterns for recursive rules — closes F10a), `finderTag`,
  `addedSince` (kMDItemDateAdded ≠ mtime for downloads). Every new
  deterministic match is a file that never costs an LLM call.
- **[I21] Confidence cascade**: classify with the cheap/local model first;
  below-threshold answers escalate to a designated stronger model *instead of*
  quarantining. Cuts cost the way email-triage cascades do, and shrinks the
  quarantine pile (F3's roach motel gets fewer roaches).
- **[I22] Model downgrade advisor**: replay a rule's journaled decisions
  through a candidate (local) model and print an agreement score — "23/25
  identical, est. $0 vs $0.31/mo". Answers "can I move this rule to Ollama?"
  with evidence.

**Wildcard**
- **[I23] Content-hash decision memo** (**→ built**, `claude/decision-memo`):
  the ledger keys on path|size|mtime, so the same bytes under a new name are
  re-classified and re-paid. A small per-rule digest → decision memo consulted
  before any LLM call makes identical bytes get identical decisions — free,
  instant, deterministic. Memoization à la ccache, for filing.
- **[I24] Pre-rule miner**: mine the journal for LLM decisions that were
  deterministic in hindsight ("every `Rechnung*.pdf` went to
  `Finanzen/{year}`") and offer one-click promotion to a free glob pre-rule.
  The app literally compiles its own LLM into rules as it runs.
- **[I25] Breadcrumb mode**: after a move, leave a Finder alias at the origin
  that a sweeper dissolves after N days — muscle memory keeps working during
  the transition, then the clutter self-cleans. No competitor does this.
- **[I26] Provenance stamps + `whence`**: stamp every filed file with an xattr
  accession record (original path, date, rule, reason, confidence);
  `sortomat whence <file>` — and a History row action — answers "how did this
  get here and why", even after the journal is long gone.
- **[I27] Snooze**: "ask me again in a week" on a Review row — the ledger's
  `retryAfter` machinery already *is* this, one status case away. Fills the gap
  between Apply and Dismiss for "still working on this" files.
- **[I28] Label-don't-move**: a third rule mode that writes the taxonomy
  verdict as Finder tags and leaves the file in place — Gmail labels for the
  filesystem, undo-safe by construction, composes with smart folders.

**Trust & delight (editor's additions, replacing the panel the rate limiter ate)**
- **[I29] Drag-onto-the-funnel "what would happen?"**: drop a file on the
  menu-bar icon → a popover shows which rule would claim it, the destination,
  and why — a zero-risk single-file preview. (NSStatusItem buttons accept
  drags; the decide path is already pure.)
- **[I30] Tidy tally**: lifetime stats in About, computed from the journal —
  "4 812 files filed · 92 GB organized · 14 undos". Cheap, honest bragging.
- **[I31] Quarantine digest**: one weekly notification — "5 files waiting in
  quarantine, oldest 12 days" — so F3's folder stops being invisible even
  before it gets real UI.

---

## 6. Refuted / verified-fine (cumulative)

Wave 1's list stands (env-var key override works; Sanitizer's traversal
defense layered and correct; EpubReader can't escape the archive; both CICD
files intentional; locked-keychain headless exit is clean; CI pipeline solid).
Wave 2 adds:

- **UpdateChecker alerts off the main thread** — raised during diff review,
  refuted: the class is `@MainActor` (`UpdateChecker.swift:7`), so the 6 h
  background task's alerts hop to main correctly.
- **`GeneralTab` launch-at-login `onChange` feedback loop** — refuted: the
  re-read assignment converges (writes only differ when registration was
  refused, and then stabilize).
- **B23f test-env pollution** — refuted on re-read: `ConfigStore.directory`
  computes from `ProcessInfo` per access, so `setenv` in `setUp` *is* honored.
- **EN/DE format-string arity** — audited key-by-key across both tables; no
  mismatches (the crash class a `%@`-count divergence would cause is absent).
- **StatusItem pending badge not updating** — refuted: `$pendingActions` sink
  drives `updateIcon()` (`StatusItemController.swift:40`).

---

## Wave-2 implementation plan

Eighteen branches, each self-contained, ordered so file overlap is minimal
(where two branches touch the same file they touch disjoint regions; L10n
additions land in each branch's own table section):

| Branch | Items | Files touched |
| --- | --- | --- |
| `claude/undo-hardening` | R1, R2, R7, F4 (batchID + Undo-last-check), N9-partial | Journal, HeadlessRunner, Pipeline (stamp), AppState (undo), PreviewView (History), L10n (journal), JournalTests |
| `claude/apply-revalidation` | N1 (B23h) | PlannedAction, Pipeline (capture+verify), tests |
| `claude/budget-and-keyless` | R4, R5, F6 | Pipeline (scan loop), Models, AppState, HeadlessRunner, RuleOrderTests, new tests |
| `claude/engine-edge-cases` | N4 (B23b), N5 (B23e), N6 (B23d), N7 | Pipeline (isStable), Mover, ZipArchive, Sanitizer, L10n (errors), tests |
| `claude/watching-robustness` | B22, P6, P4 | FSEventsWatcher, AppState (watchers/requestScan), Pipeline (ScanResult), tests |
| `claude/preview-hygiene` | N2 | AppState (ingest/refresh/remove), Pipeline (forgetPreviews), tests |
| `claude/notifications-honesty` | U8 | AppState (notify), L10n (notifications) |
| `claude/keychain-feedback` | R3, U12a | AppState (saveAPIKey), GeneralTab, L10n (general) |
| `claude/rule-editor-guardrails` | U11, U12d, U12e | RuleEditor, DeterministicEngine (validity helper), L10n (rule), tests |
| `claude/l10n-stragglers` | L2-remainder, R6, U12b, U12c, N9-partial | L10n (+plural helper), PathField, MainMenu, UpdateChecker, GitHubReleaseClient, StatusItemController, PreviewView, SettingsWindowController |
| `claude/spend-persistence` | F8, N3, P7f | ConfigStore, AppState, AppDelegate, L10n (menu), tests |
| `claude/maintenance-rotation` | P5-partial | ConfigStore (log rotation), Ledger (prune + dirty flag), Pipeline (persist), LedgerTests |
| `claude/screenshots-template` | L3 | Templates, L10n (templates), TemplatesTests |
| `claude/rule-packs` | F9 | new RulePack, RulesTab, L10n (rules), new tests |
| `claude/llm-hardening` | N8 | LLMClient, LLMClientTests |
| `claude/process-lock` | B9 | new ProcessLock, HeadlessRunner, AppState, new tests |
| `claude/decision-memo` | I23 | new DecisionMemo, Pipeline (decide/apply hooks), ConfigStore (path), new tests |
| `claude/changelog-docs` | CHANGELOG, C3a-c | CHANGELOG.md, README.md, .github/CICD.md, scripts comments |

Deliberately **not** implemented without a Mac to verify on: P1/F2
(pending-plan persistence — interacts with everything above; next wave, on a
Mac), P2 (sliding-window scheduler), F3 (quarantine UI), F5/I21 (per-rule
models — a real settings-UI design task), F7 (Vision OCR), U13/I1 (first-run
tour), and the §5 ideas not marked built.

---

# Wave 3 — the post-fix review

Legend continues from above. Wave-3 findings are tagged **[W#]**. Each is
anchored to code I re-read at `3af2b3b`; confidence is my own (the adversarial
verifier didn't run). Items I ship this wave are marked **→ branch**. Nothing
here duplicates a wave-1/2 finding unless the framing was materially wrong, in
which case it says so.

The one-paragraph version: the safety *core* is strong, but it leans on two
guarantees that turn out to be softer than advertised — the content hash "fails
closed" only on *open* errors, not mid-read I/O errors ([W1]); and the
"verify-before-delete" cross-volume path is mostly dead code because Foundation
already does an *un*verified copy-delete for you ([W2]). Around that core, a
consistent theme: **the paid, non-deterministic path has too few safety valves**
— a `nil` confidence sails past the quarantine threshold ([W12]), a
contradictory model answer defeats taxonomy ([W11]), an ampersand-heavy EPUB can
hang the whole scan ([W6]), and several deterministic dead-ends (empty route
template, dotted filenames, `.`-segments) re-pay the model on every 30-minute
retry ([W8]–[W10]). The Settings panel — the surface you flagged — is *correct*
but reads non-native and has three controls that fight the user ([W20]–[W23]).
And the 18 open PRs, merged naively, would silently drop three of their own
fixes ([W30]–[W32]).

## W1. Data-safety core — the guarantees that are softer than they look

**[W1] `ContentHash.digest` treats a mid-read I/O error as EOF and returns a
valid-looking digest of a truncated prefix.** The contract (and the comment) is
"nil if the file can't be read", and three fail-closed guards rest on it:
`copyVerifyDelete` (`Mover.swift:71-77`), dedup, and the copy-undo divergence
check (`Journal.swift:84-86`). But only *open* failure yields nil —
`(try? handle.read(...)) ?? Data()` (`ContentHash.swift:19`) coerces an I/O
error mid-read into an empty chunk, ends the loop, and returns a normal hex hash
of whatever prefix was read (possibly zero bytes) plus the stat size. If a NAS
drops mid-verify and *both* sides' first reads fail, both digest an empty prefix,
the digests match, and the original is deleted. One-line fix: `try` (not `try?`)
inside the loop, return nil on any read error. **→ branch `claude/hash-integrity`**

**[W2] The wave-1 "verify the cross-volume copy before deleting" fix (B1/PR #1)
is largely dead code.** `FileManager.moveItem(at:to:)` *itself* copies-then-
deletes across volumes and normally **succeeds** rather than throwing
(`Mover.swift:49`). So `copyVerifyDelete` — the hash-verified fallback — only
runs when Foundation's own move *throws* (occupied target, permissions); the
ordinary cross-volume move deletes the original after an *un*verified Foundation
copy. That's the exact posture B1 claimed to close, and the scoreboard line
"cross-volume verify fails closed, hashes full content" is materially
optimistic. Fix: detect cross-volume up front (`isCrossVolume` *before*
`moveItem`) and route those placements directly through `copyVerifyDelete`.
*(Documented; the fix needs a real two-volume Mac to validate, so not
blind-shipped this wave.)*

**[W3] The cross-volume fallback cleanup deletes whatever occupies the
destination — including a file Sortomat never created.** `copyItem` throws
`NSFileWriteFileExistsError` *without copying anything* when the target is
occupied, yet the `catch` unconditionally `removeItem(at: target)`
(`Mover.swift:66-70`). An occupant that appeared after `resolvePlacement`'s
probe — or the dangling-symlink case N5 sets up (`fileExists` says free,
`moveItem`/`copyItem` both fail `EEXIST`) — is silently destroyed, the error
logs as transient, and the 30-min retry then fills the freed slot. Data loss
*outside* Sortomat's ownership. Fix: only remove `target` if it did not exist
immediately before `copyItem`, or skip cleanup on `EEXIST`. *(High severity, but
it lives inside `Mover.place`, which `claude/engine-edge-cases` (N5) also edits;
documented so the two are resolved together rather than racing.)*

**[W4] The plain copy path has no partial-file cleanup.** Unlike
`copyVerifyDelete`, the copy-rule branch (`Mover.swift:43-46`) never removes a
half-written target on failure. A `copyItem` interrupted mid-copy (disk full,
NAS drop) leaves a truncated file at the canonical name; the ledger marks
`.failed`, and the 30-min retry files the *intact* copy as `name (2).ext` beside
it — the corrupt partial keeps the real name forever. Source is safe (copy
mode), so this is corruption-shaped clutter, not loss. Same one-branch overlap
as W3.

**[W5] Move-undo relocates whatever currently sits at `destinationPath` — no
fingerprint was captured at placement.** `JournalEntry` stores only paths; the
copy path got a divergence guard (B5/R1) but the *move* path has none
(`Journal.swift:94-101`): it checks that *something* exists at the destination
and moves it back. If the destination was replaced (sync, another tool, a manual
save of the same name), undo yanks the impostor to the old source path — it
vanishes from the destination and the "restored" file is not the one that moved.
GUI History offers undo on 200 entries, so a stale entry is one click away.
`claude/undo-hardening` already plans to stamp fingerprints in `JournalEntry`;
this is the argument for making the *move* side use it too. *(Folded into the
undo-hardening design note, not a separate branch.)*

## W2. Engine & parsing — the paid path's sharp edges

**[W6] An ampersand-heavy EPUB chapter hangs the entire scan (quadratic entity
decode).** For every `&` with no later `;`, `decodeEntities` calls
`input[index...].firstIndex(of: ";")` — scanning the whole remainder — then
`distance(...)` re-walks it, all before the `<= 12` guard rejects
(`HTMLText.swift:41-42`). `strip()` runs on the *full* decompressed chapter (up
to 16 MiB) *before* the 4 000-char truncation, so a chapter that's megabytes of
`&` with no semicolons (compresses to KB) is O(n²) — ~10¹⁴ comparisons at 16
MiB; `decide()` never returns, and with the batch barrier (P2) the whole pass
stalls, re-stalling every scan and across relaunches. Fix: bound the semicolon
search to a 12-char window with `index(_:offsetBy:limitedBy:)`, and cap the
markup fed to `strip()` (only 4 000 chars are kept anyway). **→ branch
`claude/html-extraction`**

**[W7] `.html`/`.htm`/`.rtf` files feed raw markup — not visible text — to the
classifier.** `readPlainText` returns the first 64 KiB of *raw* bytes
unstripped (`FileContext.swift:10-13, 88-97`). A saved web page's 4 000-char
excerpt is `<head>`/CSS/JS boilerplate; an `.rtf` excerpt is
`{\rtf1\ansi…}` control words — the model classifies on noise. `HTMLText.strip`
exists for exactly this and is used only for EPUB chapters. Fix: route
`html`/`htm` through `strip` (after fixing W6, which the same markup would
otherwise trigger), and parse `rtf` via
`NSAttributedString(rtf:documentAttributes:).string`. **→ branch
`claude/html-extraction`**

**[W8] An empty route template expands to an absolute `/{name}` and fails every
matching file forever — and `PreRule()`'s default state *is* this.**
`expandRoute("")` yields `"/{name}"` (`DeterministicEngine.swift:68-72`), which
`Sanitizer.destination` rejects as absolute; the file records `.failed` and
retries every 30 min. `PreRule()` defaults to `action: .route, routePath: ""`
(`Models.swift:56-57`), so the rule-editor's **"Add pre-rule"** button creates
exactly this broken pre-rule. The same shape hits `Pipeline.swift:258`: an
emptied `quarantineSubfolder` yields `/name`, so every quarantine decision fails
*after the LLM was paid*. Fix: treat an empty route template as `"{name}"`;
build the quarantine path only when the subfolder is non-empty. **→ branch
`claude/sanitizer-correctness`** (route side) / documented (quarantine side, in
hot `Pipeline`).

**[W9] Extension forcing strips the last dot-segment of dotted stems, silently
renaming files.** When the planned filename doesn't already end in the original
extension, `destination()` runs `deletingPathExtension` before appending it
(`Sanitizer.swift:59-64`), deleting real name content. A 24-h-locale screenshot
`Screenshot 2024-06-01 at 10.15.32.png` routed by a pre-rule becomes
`…at 10.15.png` (same-minute shots then collide into ` (2)` suffixes);
`backup.2024.01.tar` becomes `backup.2024.tar`. Fires on the deterministic route
path with the file's *own* name. Fix: strip only if the current `pathExtension`
case-insensitively equals `originalExtension`. **→ branch
`claude/sanitizer-correctness`**

**[W10] `.` path components become `Unbekannt` folders, and `./`-prefixed model
answers defeat taxonomy.** `destination()` rejects `..` but lets `.` through to
`sanitizeComponent`, which maps it to `Unbekannt` (`Sanitizer.swift:33`,
`:49-55`). A model answering `./Docs/report.pdf` (a common LLM path style) files
to `target/Unbekannt/Docs/report.pdf`; worse, `Classification.topFolder()` on
`./Fantasy/x.epub` returns `.`, so a correct in-taxonomy answer is quarantined
as "folder «.» not in taxonomy" *after* the model was paid. Fix: drop `.`
segments when splitting in `destination()`, and skip a leading `.` in
`topFolder()`. **→ branches `claude/sanitizer-correctness`** (path) /
**`claude/classification-hardening`** (taxonomy).

## W3. Safety valves on the model's answer

**[W11] Taxonomy is enforced against `folder` but placement uses
`relative_path` — a contradictory answer bypasses quarantine.**
`Pipeline.decide` checks taxonomy via `c.topFolder()` (`Pipeline.swift:238`),
which prefers the `folder` field; the destination is built from
`c.resolvedRelativePath()` (`:229`), which prefers `relative_path`. A response
carrying both with *different* values —
`{"folder":"Rechnungen","relative_path":"Sonstiges/x.pdf"}` — passes taxonomy on
"Rechnungen" but files under "Sonstiges/". Prompt-injected file content can
steer the model to emit exactly this, defeating the taxonomy+quarantine
containment layer (the `Sanitizer` still confines to the target, so this is
mis-filing, not escape). Fix: derive the taxonomy check from the *same* path
that will be applied — the first directory segment of `resolvedRelativePath()`.
**→ branch `claude/classification-hardening`**

**[W12] A missing or unparseable confidence sails past the quarantine threshold
(fail-open).** `decodeConfidence` returns nil for anything that isn't a `Double`
or a `%`-stripped numeric string — `"high"`, `"0,85"` (German decimal comma),
`"85 %"` (the trailing space defeats `Double`), a boolean, or an omitted field
(`Classification.swift:77-86`). With nil, the `let confidence = c.confidence`
binding in the threshold check fails and the whole check is skipped
(`Pipeline.swift:248-249`) — so the file is filed as *fully trusted*. Exactly
the off-schema responses that deserve the most suspicion skip the safety valve.
Same bug *class* as the fixed B11 (numeric percent), but the nil path was left
open. Fix: when `confidenceThreshold > 0`, treat nil as below threshold
(quarantine), and trim/accept comma decimals in `decodeConfidence` before giving
up. *(The quarantine decision is in hot `Pipeline`; the parsing half is in
untouched `Classification` and ships in `claude/classification-hardening`, which
makes nil an explicit low value so the existing check quarantines it.)*

**[W13] A boolean `"action": false` (or `null`/`0`) decodes as `"move"`.** Any
non-string action fails the `String` decode and falls back to `"move"`
(`Classification.swift:26`). The comment justifies this for `true`/absent, but
the same fallback *inverts* an explicit `false`: if the model also populated
`folder`/`filename` (models often fill every schema field even when declining),
the file is moved despite a clear refusal. B12 made unknown action *strings*
safe-skip; the non-string path still defaults to the unsafe direction for a tool
that moves user files. Fix: decode `false`/`0`/`null` → `"skip"`; keep the
`"move"` default only for a genuinely absent key. **→ branch
`claude/classification-hardening`**

**[W14] Failed LLM calls are invisible to both the budget and the spend meter.**
`decision.usage`/`usedLLM` are only read when `decide()` *returns*
(`Pipeline.swift:145-149`); when `classify` throws, the `catch` records `.failed`
but `usedLLM` stays false and `usage` zero. So (a) `budgetRemaining` never
decrements for failed calls — `perScanBudget` caps only *successes*, and a
backlog against a rate-limited or JSON-mangling endpoint fires one paid request
per file (×4 attempts on 429/5xx) with no cap; (b) tokens billed on
200-but-unparseable responses never reach `AppState.usage`, so the cost estimate
under-counts exactly when the model misbehaves. *(Fix touches hot `Pipeline`
decide/scan accounting; documented, best done alongside `budget-and-keyless`.)*

**[W15] A non-JSON 200 body is retried four times despite "parse failures are
terminal".** If a 200 response isn't JSON at all (captive portal, proxy HTML
error page, wrong base URL answering 200 with a webpage),
`JSONSerialization.jsonObject` throws a plain Cocoa `NSError`, not an `LLMError`
(`LLMClient.swift:141`). `classify`'s `catch let error as LLMError` (`:112`)
misses it, so the generic catch marks it retryable: 4 identical attempts plus
~12 s of sleeps per file, contradicting the line-105 comment, and the surfaced
error is the raw "data couldn't be read" instead of `badResponse`'s body
excerpt. Fix: wrap the `JSONSerialization` call in `parse()` and rethrow as
`LLMError.badResponse` with a body-prefix. *(Small, but `LLMClient` is edited by
`claude/llm-hardening`; documented so they land together.)*

## W4. App behavior — pause, preview, quit, CLI

**[W16] Pause does not stop an in-flight scan pass.** `runScans` checks `paused`
once per pass, before the rule loop (`AppState.swift:179`); neither the loop nor
`Pipeline.scan` re-checks it, and nothing cancels the `Task`. Choosing **Pause**
dims the icon instantly (`appearsDisabled`) but a pass already underway runs to
completion — every remaining rule and file, including LLM spend and moves. With
a big backlog and low budget (R4's serialized batches, ~12 min/1 000 files) the
emergency brake — pulled exactly when the user sees a rule mis-filing — does
nothing for minutes while wrong moves keep landing. `editingRuleID` is already
re-read per rule, so a per-rule `paused` re-check fits the existing shape; a
cancellation probe into `Pipeline.scan`'s batch loop would make it halt within
one batch. *(Fix is in hot `AppState`/`Pipeline`; documented — it wants the same
scan-loop surgery `budget-and-keyless`/`watching-robustness` are already doing.)*

**[W17] "Preview changes…" on a *live* rule double-pays the model and the file
moves out from behind the review window.** The `previewed` de-dup is consulted
only when previewing, and preview never records to the ledger
(`Pipeline.swift:131`). So after the menu's **Preview changes…** force-previews a
non-`dryRun` rule and queues it in Review with Apply/Dismiss, the next ordinary
scan (timer, 60 s default, or FSEvents) re-runs `decide()` for the same file
(second paid call, same session) and moves it *without approval*; the pending
row then points at a vanished source and Apply later errors "source vanished".
This is the mechanism behind the Review UI implying a control the auto path
overrides. Adjacent to N1/N2 but the same-session double-pay is undocumented.
Fix: on ordinary scans, defer files that already have a queued pending plan (or
reuse the paid decision). *(Interacts with F2/P1 pending-plan persistence;
designed, deliberately not blind-built — matches wave-2's deferral.)*

**[W18] `refreshPreview` ignores both the editing lock and Pause — so N10's
"harmless" is wrong.** `runScans` skips `editingRuleID` and returns early when
paused; `refreshPreview` does neither (`AppState.swift:220-231`), guarding only
on the missing key. So (a) with a rule mid-edit, the status-menu **Preview
changes…** or Review's **Refresh** sends the *half-typed* prompt to the model
(paid) and queues plans that **Apply All** — the default-action button — will
execute; and (b) clicking **Preview changes…** while **Paused** runs a full paid
sweep over every enabled rule. Wave-2 N10 called this "harmless thanks to the
guards" — there is no such guard. Fix: mirror `runScans` (skip `editingRuleID`,
`guard !paused`). **→ branch `claude/preview-respects-state`** *(small, one hot
file; see plan)*.

**[W19] Quit within the 800 ms persist debounce silently discards the last
edits.** The debounced `persistTask` is the *only* path that writes config to
disk (`AppState.swift:61-70`; every edit routes through `persistAndApply`), and
`AppDelegate` has no `applicationWillTerminate`. ⌘Q or the status-menu **Quit**
within 800 ms of the last edit exits before the save runs: toggle a misbehaving
rule off, quit immediately, and next launch it's still enabled and resuming
moves. Sibling of N3 (ledger loss on quit) but distinct data — the hand-tuned
prompts the delete dialog calls "irreplaceable". `claude/spend-persistence`
already adds a terminate flush for the ledger; the config `persistTask` must be
flushed in the same handler. *(Folded into the spend-persistence terminate-flush
design; noted so it isn't missed.)*

**[W-CLI] A typo'd CLI command silently boots the GUI; `HeadlessRunner`'s
`exit(64)` is unreachable.** `SortomatMain` routes only the three exact strings
`scan-once`/`preview`/`undo` to `HeadlessRunner`; anything else
(`scanonce`, `--help`, `undo-last`) falls through and launches the menu-bar GUI,
which never exits (`SortomatMain.swift:12`). In a launchd/cron job a typo'd
`ProgramArguments` yields a background GUI that hangs the job forever and fights
the real GUI over the ledger/journal (aggravating B9). `HeadlessRunner`'s
`default: exit(64)` (`HeadlessRunner.swift:15-17`) can therefore never run. Fix:
forward any `argv[1]` to `HeadlessRunner` (unknown → usage + exit 64); launch the
GUI only with no user arguments. **→ branch `claude/cli-dispatch`**

## W5. The Settings panel (you asked specifically)

The panel is *functionally* correct and its wave-1/2 polish (real disabled
states, editing lock, confirmations) holds up. What's left is native-feel and
three controls that actively mislead.

**[W20] The budget stepper can't express small budgets, and decrementing bottoms
out at "unlimited".** Per-scan budget is a bare `Stepper(… in: 0...1000, step:
10)` (`GeneralTab.swift:58`). Values 1–9 — the most cautious configs, the exact
`perScanBudget: 1` case R4 discusses — are unreachable; the minimum non-zero
budget is 10. Worse, the semantics invert at the bottom: clicking **–** to
*reduce* spend goes 30→20→10→**0**, and `0` means **unlimited** — the
cheapest-looking click yields the most expensive setting. Reaching 1 000 takes
100 clicks. (Same stepper-without-field pattern on Priority 0…100,
`RuleEditor.swift:18`.) Fix: pair the Stepper with a `TextField`, `step: 1`, and
replace the 0-sentinel with an explicit **Unlimited** toggle. **→ branch
`claude/general-tab-controls`**

**[W21] The scan-interval slider reports raw seconds with no min/max labels, and
its range disagrees with the engine clamp.** The readout is always `%d s`
(`GeneralTab.swift:51`), so the top half reads "420 s"/"600 s" instead of
"7 min"/"10 min"; the slider has no `minimumValueLabel`/`maximumValueLabel`, so
the 15 s–10 min range is undiscoverable. The engine clamps to 10–86 400 s
(`AppState.swift:156`) while the slider covers 15–600, so a hand-edited
`3600` shows "3600 s" pinned at max and any touch silently rewrites it to ≤600.
Fix: format with natural units, add end labels. **→ branch
`claude/general-tab-controls`**

**[W22] Pricing fields accept negatives, go stale on model change, and bad input
*hides* the spend readout.** Both price fields are unbounded full-width numeric
`TextField`s with no validation (`GeneralTab.swift:38-41`): a negative price
makes `estimatedSpend` negative, and the `> 0` guard (`:42`) then *hides* the
spend caption — the feature vanishes instead of flagging the input. The defaults
(0.2/0.6) are Mistral-small prices; editing **Model** leaves pricing silently
wrong. Fix: clamp ≥ 0, fixed ~100 pt width, show the spend line whenever
`usage > 0`. **→ branch `claude/general-tab-controls`**

**[W23] Naming maze + the no-key first-run is two hops from the key field.**
Three names for one surface: menu **"Rules & Settings…"**, window title
**"Sortomat — Rules"** (`L10n.swift:52`), a tab labeled **"Settings"** — yielding
the in-app instruction "add one under Rules & Settings → Settings"
(`L10n.swift:163`). The keyless first-run is worst-served: the menu-bar "No API
key set" item is a *disabled* `NSMenuItem` (`StatusItemController.swift:134,
161-165`) and Settings opens on **Rules**, two hops from the key field. Fix:
rename the General tab (or the window), and make the no-key status item
*clickable* to open Settings pre-selected on General. *(Touches the L10n swamp +
window-title wording `l10n-stragglers` already edits; documented to avoid
piling onto that conflict cluster.)*

**[W24] The window looks non-native, and `⌘,` is dead while a window is
frontmost.** The default `TabView` renders the legacy centered tab-box; the outer
`.padding(8)` (`SettingsView.swift:21`) plus each Form's own `.padding()`
(`GeneralTab.swift:79`, `RuleEditor.swift:103`) triple-inset the content. HIG
settings windows use toolbar-style tabs. Labels also carry trailing colons
("Name:", "Model:"), the old columns convention. Separately, the installed main
menu (`MainMenu.swift`) has no **Settings…** item, so the standard `⌘,` does
nothing whenever the Preview/Settings window is focused — the only binding lives
in the status menu, which fires key equivalents only while open. Fix: toolbar-
style tabs; add **Settings… (⌘,)** to the app menu. *(Cosmetic tab styling wants
a Mac; the `⌘,` menu item is a clean add but touches `MainMenu`, which
`l10n-stragglers` localizes — documented.)*

**[W25] The About tab is a splash screen, not a tab.** It's icon + tagline +
version + two buttons, with `Spacer()` leaving the bottom ~60 % of a 460 pt
window empty (`AboutTab.swift`). It lacks what would earn the slot: a
**Check for Updates…** button (otherwise only in the menu bar; `lastResult` —
R6 — was "kept for a future About display"), a copyright/license line, and it
oddly promotes the debug "Open log" affordance. Fix: add a lifetime "tidy tally"
from the journal (I30), a copyright/Unlicense line. **→ branch
`claude/about-tidy-tally`** (tally + license line; the update-check button needs
an `UpdateChecker` hook wired through the view and is deferred).

## W6. Review / History window

**[W26] "Applied N change(s)" counts *requested* plans, not successes — failed
applies vanish silently.** `apply()` reports `plans.count` regardless of outcome
(`PreviewView.swift:94`), and `AppState.apply` removes every applied id from
`pendingActions` even when `Mover` threw (`AppState.swift:238`), never calling
`notify()`. Approve 10, 3 fail (collision cap, vanished source, verify failure):
rows disappear, the caption says "Applied 10", and the only trace is a line in
the menu-bar activity submenu — the Review tab has no error surface at all
(History has a red line; Review has none). Fix: count ok/failed from the
returned entries, show "Applied X, failed Y" plus a red detail, keep failed rows
visible. *(Touches `AppState.apply` + `PreviewView`, both edited by
`undo-hardening`/`l10n-stragglers`; documented to resolve together.)*

**[W27] The pending badge counts non-actionable "would skip" rows, so it stays
inflated after Apply All.** `process` queues *every* previewed plan as pending,
including `kind == .skip`, and the badge counts `pendingActions.count` wholesale
(`StatusItemController.swift:52`). A dry-run rule over a busy Downloads folder
shows "40" where 35 are skips; **Apply all** filters to `isActionable`
(`PreviewView.swift:80`), so the 35 survive and the badge never returns to zero
without manual dismissal — training users to ignore it. Fix: count
`pendingActions.filter(\.isActionable)` for the badge and `menu.pendingReview`
(or don't queue skip-kind plans). **→ branch `claude/actionable-badge`**

**[W28] Review rows truncate the destination to one un-tooltipped line — you
approve a move you can't fully read.** Rule/action/destination share one
`lineLimit(1)` caption with no `.help()`, no reveal-in-Finder, no Quick Look, no
sort/filter (`PreviewView.swift:106-138`). For an *approval* UI that's a trust
gap: `Belletristik/Le Guin, Ursula K./The Dispossessed.epub` plus a long model
reason get ellipsized. Fix: `.help()` with full source, destination and reason —
a zero-risk realization of I2 ("why this destination"). **→ branch
`claude/review-row-detail`**

**[W29] Review's empty state lies while a menu-triggered scan is still running,
and History goes stale.** `busy` is view-local, set only by the tab's own
Refresh (`PreviewView.swift:20, 58`); the menu's **Preview changes…** fires
`refreshPreview()` in a detached Task, during which the window shows the
all-is-well "Nothing to file right now" checkmark with no spinner, then rows pop
in. History likewise reloads only on appear/manual refresh and never clears a
stale red undo-error line (`:221, 237`). Fix: publish an `isScanning` flag from
`AppState` and drive the empty state + toolbar spinner from it; reload History
after apply/undo and clear `error` at the start of each undo. *(Touches hot
`AppState`; documented.)*

## W7. Merge composition of the 18 open PRs

This is the review only wave 3 can do: the 18 branches *as a set*. Simulated
pairwise (`git merge-tree` over all 153 pairs) plus sequential merges in a
clone.

**Recommended merge order (12 clean, then 6 conflicted — the minimum):**
`changelog-docs → llm-hardening → screenshots-template → rule-editor-guardrails
→ rule-packs → undo-hardening → keychain-feedback → engine-edge-cases →
apply-revalidation → maintenance-rotation → watching-robustness →
l10n-stragglers → budget-and-keyless → decision-memo → process-lock →
notifications-honesty → preview-hygiene → spend-persistence`. Steps 1–12 merge
clean; expect conflicts only at 13–18 (the hot files). Notably `undo-hardening`
merges clean against all 17 others despite touching six hot files. **This
corrects the wave-2 plan's claim that "where two branches touch the same file
they touch disjoint regions" — it's false for 18 of the 153 pairs**, clustered
in `AppState` (the property block after line 34: WR/PH/NH/SP/PL all insert
there), `Pipeline`, `ConfigStore`, `ActivityEntry`, and adjacent `L10n` inserts.

Three of those are **silent-loss composition bugs** — either one-sided
resolution compiles, so CI stays green while a fix quietly disappears:

**[W30] `budget-and-keyless` × `watching-robustness` (Pipeline scan loop).**
budget-and-keyless rewrites the outcome-accounting line that watching-robustness
makes the *only* consumer of `FileOutcome.unstable`. Taking budget-and-keyless's
side still compiles (`unstable` stays declared, never incremented), so
`ScanResult.unstableCount` is always 0, `scheduleFollowUpScan` never fires, and
the **P4 follow-up-scan fix silently regresses** to waiting for the timer. This
is the one conflict in the train that needs real interleaving. Guard: a test
asserting `unstableCount > 0` for a too-young file.

**[W31] `maintenance-rotation` × `decision-memo` (`Pipeline.persist`).** MR makes
`persist()` = `{ ledger.prune(); ledger.save() }`; DM makes it
`{ ledger.save(); memo.save() }`. Both one-sided resolutions compile: MR's side
means the **DecisionMemo is never persisted** (every relaunch re-pays the model
for identical bytes — the exact spend DM exists to kill — while
`DecisionMemoTests` stay green because they call `memo.save()` directly); DM's
side **silently drops ledger pruning** (a P5 regression). Correct resolution:
`{ ledger.prune(); ledger.save(); memo.save() }` + a Pipeline-level test that
`persist()` writes *both* files.

**[W32] `spend-persistence` × `maintenance-rotation` (`ConfigStore.appendLog`).**
SP replaces the per-line `ISO8601DateFormatter` with a shared `timestamp()`
helper (P7f); MR inserts `rotateLogIfNeeded()` one line above. Either one-sided
resolution compiles: SP's side **loses log rotation** (undoes P5); MR's side
**loses the cached formatter** and leaves SP's helper only half-wired. Correct
resolution: `rotateLogIfNeeded()` then `timestamp()`, then grep for any
surviving `ISO8601DateFormatter()`.

**[W33] Two branches reintroduce the `%d …(s)` plural hack that `l10n-stragglers`
removes.** `l10n-stragglers` adds `L10n.plural` and converts every `(s)` hack to
`.one`/`.other` pairs (U12c); meanwhile `undo-hardening` adds
`"Undid %d move(s)."` and `notifications-honesty` adds `"Filed %d file(s)."` —
brand-new instances of the pattern being removed. After all 18 merge, properly
pluralized menu strings sit beside "Filed 1 file(s)". Post-merge sweep: convert
the new count-bearing keys via `L10n.plural`.

## W8. Localization, security & tests (partial — finders cut by the spend limit)

**[W34] Review rows and quarantine log lines mix hardcoded English into a German
UI.** The reason strings surfaced verbatim in `PlanRow` and
`activity.quarantined` are English: `pre-rule «…»` (`Pipeline.swift:201`),
`folder «…» not in taxonomy` (`:243`), `confidence NN% below threshold` (`:252`),
`rule does not apply` (`:225`). None are in the known L2 straggler list. A German
user sees "…· Verschieben →" beside "folder «Sonstiges» not in taxonomy". Fix:
route the four through `L10n`. *(Touches hot `Pipeline` + the `L10n` swamp;
documented — a clean sweep once the merge train settles.)*

**[W35] EPUB XML is parsed without `.nodeLoadExternalEntitiesNever` (XXE
exposure).** `container.xml` and the OPF are attacker-controlled (any downloaded
EPUB) and parsed with `[.nodePreserveWhitespace]` / `[.documentTidyXML]`
(`EpubReader.swift:132-139`). `NSXMLDocument`'s default external-entity behavior
is version-dependent and under-documented; if Foundation resolves a
`<!ENTITY x SYSTEM "file:///…">` for a data-based parse, local file contents
land in the metadata title/description — which `FileContext` sends verbatim to
the configured endpoint and which can leak into folder names. The one-line
hardening is warranted regardless. **→ branch `claude/epub-xxe`**

**[W36] Invisible and bidi-control characters survive `sanitizeComponent` (the
"unaudited corner" wave 2 left for wave 3 — confirmed).** The forbidden class
stops at `\x1f` (`Sanitizer.swift:23-24`): DEL (`\x7f`), zero-width chars
(U+200B/U+FEFF — category Cf, so `\s+` doesn't collapse them either) and bidi
overrides (U+202E) pass into names. A prompt-injected document can steer the
model into "Fantasy​" (with a zero-width space) — a folder visually identical to
"Fantasy" — splitting files across indistinguishable directories, or an RLO name
that displays reversed in Finder. Contained inside the target, but real. Fix:
extend the strip class with `\x7f` and `\p{Cf}`. **→ branch
`claude/sanitizer-correctness`**

**[W37] Glob-derived `.*` chains and raw regex pre-rules run with no ICU time
limit.** `globToRegex` turns each `*` into unbounded `.*`
(`DeterministicEngine.swift:93-107`); a user glob with a dozen stars, or a raw
`.regex` like `(a+)+$`, matched against an adversarial ~200-char filename in a
watched Downloads folder, backtracks combinatorially and stalls the Pipeline
actor with no error. Fix: match globs segment-wise (fnmatch-style) or run with a
deadline. *(The rule-editor already gains regex *validity* flags in
`rule-editor-guardrails`; the ReDoS/time-limit angle is documented for a
follow-up that can profile on a Mac.)*

**[W38] The most-exercised zip path and the `classify` retry taxonomy have zero
test coverage.** `ZipWriter` emits only stored (method-0) entries, so
`ZipArchive.inflate` — the deflate path every real EPUB uses — is untested; a
regression there passes CI and silently blanks every EPUB's text. `LLMClientTests`
never stub `URLSession`, so the retryable-status set, 400/401 immediate-surface,
and the W15 non-JSON-200 escape are unverified. `MoverTests` never exercise the
fail-closed branches (verify-failure, occupied-target cleanup) — a regression
test would have caught W3. *(New test files risk colliding with
`engine-edge-cases`' own `ZipArchiveTests`; the safe additions land inside the
feature branches above — `html-extraction`, `epub-xxe`, `classification-
hardening`, `sanitizer-correctness` each ship their own tests.)*

**Minor, documented (not shipped):** kind-map gaps — `document` lacks `odp`,
`image` lacks `svg`/`avif`/raw formats (`DeterministicEngine.swift:14-23`);
`FileContext` dates use the user's calendar so a Buddhist/Japanese system feeds
the model era years (`FileContext.swift:18`) while `DeterministicEngine` pins
Gregorian — the same file's pre-rule and LLM routes can disagree on the year;
`expandRoute` substitutes tokens in Dictionary (hash-seeded) order, so a file
literally named `receipt {year}.pdf` routes differently across launches
(`DeterministicEngine.swift:86`); `sanitizeComponent` truncates by grapheme
count (150) but APFS caps at 255 *bytes*, so a long CJK title fails
`ENAMETOOLONG` in a paid retry loop; glob/regex matching is
normalization-sensitive so an NFD filename never matches an NFC-typed pattern;
`kMDItemTextContent` is documented query-only, so the Spotlight full-text tier
likely yields nothing on a Mac (verify); `temperature: 0` is hardcoded, which
OpenAI reasoning models reject with a 400 that can't be fixed from settings;
`kSecAttrAccessible…ThisDeviceOnly` without `kSecUseDataProtectionKeychain` may
be a no-op on the macOS file keychain. Each is real but small; parked for a
wave that can compile on a Mac.

## W9. Ideas — restored backlog + wave-3 additions

The wave-2 rewrite referenced "I1–I17 from wave 1" without restating them; for a
living doc that's a broken link. Restored, compact:

- **[I1]** Sandboxed first-run tour (`~/Sortomat Demo/` + 3 sample files).
- **[I2]** "Why this destination?" popover — *shipping the tooltip half this
  wave as [W28]*.
- **[I3]** Per-rule trust score → suggest turning preview off after N clean
  approvals.
- **[I4]** Before/after folder-tree diff in Review.
- **[I5]** Undo action button *on the failure notification* (pairs with W-notify
  click handler).
- **[I6]** Quarantine inbox with one-click "re-classify with hint" (F3).
- **[I7]** Backlog wizard: "1 843 files, est. \$0.74 — proceed?".
- **[I8]** Persistent monthly cost meter with per-rule attribution (F8 →
  `spend-persistence`).
- **[I9]** Batch classification: N files per LLM call.
- **[I10]** Per-rule model override (F5).
- **[I11]** Rule simulation: "test on 5 random matching files".
- **[I12]** `sortomat://` URL scheme + Shortcuts action.
- **[I13]** Funnel-gulp menu-bar animation on a filing.
- **[I14]** Weekly Tidy Report notification.
- **[I15]** "Chaos meter" gauge for the watch folder.
- **[I16]** Milestone toasts (1 000th file filed).
- **[I17]** Spend in espresso units ("≈ half a latte this month").

I18–I31 from wave 2 stand. Wave-3 adds:

- **[I32] Lifetime "tidy tally" in About** — files filed · GB organized · undos,
  computed from the journal. Cheap, honest bragging; **→ built this wave**
  (`claude/about-tidy-tally`), the concrete half of I30.
- **[I33] "Explain this move" in the History context menu** — surface the stored
  `reason` + rule + confidence for a filed file, so "why is this here?" has an
  answer even weeks later (the poor cousin of the I26 provenance stamp, free
  because the journal already stores it).
- **[I34] Dry-run heat preview** — before enabling a live rule, colour each
  pending row by confidence (green/amber) so the eye lands on the rows worth
  scrutinizing; turns the flat Review list into a triage surface.

## Wave-3 implementation plan

Ten small, self-contained branches, chosen to (a) fix the highest-confidence
new findings and (b) touch files the 18 open PRs *don't* — six of the ten edit
files no open PR touches at all, so they merge orthogonally to the whole train.
No new branch touches `L10n.swift` except `about-tidy-tally` (the L10n hot spot
is deliberately avoided). All base on `main` (`3af2b3b`).

| Branch | Items | Primary files (open-PR overlap) |
| --- | --- | --- |
| `claude/hash-integrity` | W1 | `ContentHash.swift`, test — *no overlap* |
| `claude/html-extraction` | W6, W7 | `HTMLText.swift`, `FileContext.swift`, `HTMLTextTests` — *no overlap* |
| `claude/epub-xxe` | W35 | `EpubReader.swift`, `EpubReaderTests` — *no overlap* |
| `claude/classification-hardening` | W11, W12(parse), W13, W10(taxonomy) | `Classification.swift`, `ClassificationTests` — *no overlap* |
| `claude/sanitizer-correctness` | W8(route), W9, W10(path), W36 | `Sanitizer.swift`, `DeterministicEngine.expandRoute`, tests — disjoint region vs `engine-edge-cases`' N7 line |
| `claude/general-tab-controls` | W20, W21, W22 | `GeneralTab.swift` — L10n-free; disjoint section vs `keychain-feedback` |
| `claude/actionable-badge` | W27 | `StatusItemController.swift` — disjoint vs `l10n-stragglers` |
| `claude/review-row-detail` | W28 (I2 tooltip) | `PreviewView.swift` PlanRow — disjoint vs `undo-hardening`/`l10n-stragglers` |
| `claude/preview-respects-state` | W18 | `AppState.refreshPreview` — small guard in a hot file |
| `claude/cli-dispatch` | W-CLI | `SortomatMain.swift`, `HeadlessRunner` — disjoint |
| `claude/about-tidy-tally` | W25(part), I32 | `AboutTab.swift` (no overlap) + minimal `L10n.swift` keys |

Deliberately **not** shipped (documented above): W2/W3/W16/W17/W19/W26/W29/W34
and W14/W15/W37 — each lives in a hot file (`Mover`, `Pipeline`, `AppState`,
`LLMClient`, `L10n`) already being rewritten by an open PR, or needs a real Mac
to verify (cross-volume moves, keychain accessibility, ICU/Spotlight behavior).
Folding those in *after* the wave-2 train merges — on a machine that can
compile — is wave 4.

*— Fable (wave 3; the fleet was rate-limited mid-flight, so this wave trusts its
own eyes over an unrun verifier — every line above points at the code)*
