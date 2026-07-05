# Sortomat — Full Review

*A living review of Sortomat by Claude (Fable), now spanning two waves.*

*Wave 1 reviewed the app as of `3623512`: a complete hand-read of every Swift
file plus a fan-out of specialized review agents, adversarially verified. Its
16 fix-PRs (#1–#16) are all merged.*

*Wave 2 (this update) reviews the app as of `85065c6` — i.e. **including** the
wave-1 fixes. Method: a second complete hand-read of every Swift file, the full
wave-1 diff re-reviewed for regressions, every previously-documented-but-unfixed
item re-verified against current code, plus idea panels. (A 15-agent
adversarial verification fleet was launched for this wave but mostly cut short
by an API session limit; one specialist panel survived. Every finding below is
therefore anchored to code read directly — file and line references point at
the evidence at `85065c6`.)*

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

*— Fable*
