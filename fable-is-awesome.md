# Sortomat — Full Review

*A thorough review of Sortomat as of `3623512`, produced by Claude (Fable). Method:
a complete hand-read of every Swift file plus a fan-out of specialized review
agents (engine correctness, I/O & parsing, concurrency, UX/visuals, performance,
security/privacy, build/CI/docs, feature gaps) and three idea panels. Every
finding below was verified against the actual code — file and line references
point at the evidence. A few claims the process raised and then refuted are
listed at the end for transparency.*

The short version: the foundation is genuinely good. The safety architecture
(sanitize → plan → preview → journal → undo, content-hash dedup, taxonomy +
quarantine) is the right shape, the engine is testable and mostly tested, and
the code reads cleanly. But there are several real data-safety holes in exactly
the code the README calls "deliberately conservative", a handful of
promised-but-unwired features, and a long tail of UX and robustness gaps that
stand between "works for the author" and "trustworthy product".

Legend: **[B#]** bug · **[P#]** performance · **[U#]** UX/visual · **[F#]**
feature gap · **[C#]** CI/build/docs · **[I#]** idea.
Items marked **→ branch** are implemented in a dedicated branch (see
[Implementation plan](#implementation-plan)).

---

## 1. Data-safety bugs (the ones that matter most)

**[B1] Cross-volume move verification passes when both hashes are `nil`.**
`Mover.place` falls back to copy-then-delete for cross-volume moves and guards
deletion with `ContentHash.digest(of: source) == ContentHash.digest(of: target)`
(`Sortomat/Engine/Mover.swift:55`). `digest(of:)` returns `nil` when the file
can't be opened. `nil == nil` is `true`, so if *both* reads fail (permissions,
volume hiccup, file busy) the "verification" passes and the original is
**deleted after an unverified copy**. Exactly the failure the guard exists to
prevent. Fix: fail closed — only delete when both digests are non-nil and equal.
**→ branch `claude/fix-cross-volume-verify`**

**[B2] Cross-volume verification only hashes the first 4 MiB.**
`ContentHash.digest` hashes a 4 MiB prefix plus the byte count by default
(`Sortomat/Engine/ContentHash.swift:12`). That's a sensible *dedup* heuristic,
but `Mover` uses the same bounded digest to decide whether a cross-volume copy
is intact before deleting the original (`Mover.swift:55`). A copy of a 2 GB
video truncated-then-padded or corrupted anywhere past 4 MiB passes
verification and the original is deleted. Verification must hash the full
content (dedup can keep the fast prefix). **→ branch `claude/fix-cross-volume-verify`**

**[B3] Corrupt `config.json` silently wipes every rule.**
`ConfigStore.load()` ends with `(try? decode) ?? Config()`
(`Sortomat/Model/ConfigStore.swift:32`). A truncated or malformed config file
(crash mid-write, disk-full, hand-edit) yields a *default* config; the next
debounced save then overwrites the file — the user's rules, prompts and
taxonomies are gone. The doc comment above it claims decoding "never silently
wipes a user's rules", but that only holds for missing fields, not undecodable
files. Fix: keep the broken file as `config.json.corrupt-<timestamp>` and
surface the failure. **→ branch `claude/fix-config-corruption`**

**[B4] Undo ping-pong: an undone move is re-classified and re-moved on the next scan.**
`Journal.undo` moves the file back (`Sortomat/Engine/Journal.swift:59`) but
records nothing in the ledger (`Pipeline.apply` intentionally writes no ledger
entry for moves, since the file left the watch folder — `Pipeline.swift:277-287`).
The restored file therefore looks brand-new to the very rule that moved it, and
the next scan pass re-classifies it (paying again) and moves it right back.
Undo is structurally defeated for enabled non-preview rules. Fix: on undo,
record a `skipped` ledger entry for the restored file so the rule leaves it
alone until it changes. **→ branch `claude/fix-journal-undo`**

**[B5] Undo can delete a file it didn't create.**
For a copy, `Journal.undo` does `removeItem(at: entry.destination)`
(`Journal.swift:64-66`) without checking that what's there *now* is still the
journaled copy. If the user has since edited that copy — or something else now
occupies the path — undo destroys it. Fix: for copies, compare content hashes
with the surviving source and refuse (with a clear error) when they differ.
**→ branch `claude/fix-journal-undo`**

**[B6] Undone entries resurrect in the History tab.**
`HistoryTab.undo` removes the entry only from its local `@State` array
(`Sortomat/Preview/PreviewView.swift:183-189`); nothing marks the journal entry
as undone. Reopen the window (or press Refresh) and the undone move is listed
again, Undo button and all — clicking it now yields "The moved file is no
longer at: …". The journal needs reversal records (tombstones) that
`Journal.recent` folds away. **→ branch `claude/fix-journal-undo`**

**[B7] Duplicate detection can strand distinct files.**
Because dedup uses the same 4 MiB-prefix hash ([B2]), two *different* large
files with equal size and identical first 4 MiB (VM images, disk dumps, large
DBs with header-only diffs) are declared duplicates in
`Mover.resolvePlacement` (`Mover.swift:90`) — the second file is never filed
and sits in the watch folder forever (its ledger entry says `done`). Low
probability, but worth knowing about; the full-hash verify from [B1]/[B2]
leaves dedup's fast path unchanged, so this stays a documented trade-off.

**[B8] Keychain save can silently destroy the stored key.**
`Keychain.set` is delete-then-add and ignores both OSStatus results
(`Sortomat/Engine/Keychain.swift:32-38`). If `SecItemAdd` fails after
`SecItemDelete` succeeded, the old key is gone, the new one was never stored —
and the UI already printed "Saved to the Keychain." Fix: update-in-place via
`SecItemUpdate`, add only when missing, and check the status.
**→ branch `claude/fix-keychain-set`**

**[B9] Journal/ledger are last-writer-wins across processes.** The GUI and a
`scan-once` launchd job share `ledger.json` (whole-file atomic overwrite,
`Ledger.save`) and append to `journal.jsonl` without `O_APPEND` semantics
guarantees across processes (`Journal.record`). Concurrent runs can clobber
each other's ledger records (→ double classification, double moves) and
interleave journal writes. PLAN Phase 1 claims the double-move class is fixed,
but the in-flight reservation is process-local. Needs a config-dir lock file
or single-instance enforcement. *(Documented; not fixed in this pass — needs
design.)*

---

## 2. Correctness bugs

**[B10] `LLMClient` retries non-retryable HTTP errors.**
The retry loop's `guard [429,500,502,503,504].contains(status) else { throw lastError }`
throws from *inside* the `do` block, where `catch let error as LLMError`
catches it and only rethrows **non**-HTTP LLM errors
(`Sortomat/Engine/LLMClient.swift:99-118`). Net effect: 400/401/403 (bad key,
bad model name, malformed request) are retried four times with backoff —
~12 wasted seconds per file, multiplied by every file in the scan.
**→ branch `claude/fix-llm-client`**

**[B11] Percent-style confidences defeat the quarantine threshold.**
`Classification.decodeConfidence` normalizes `"85"` (string) to `0.85`, but a
*numeric* `85` is returned as-is (`Sortomat/Model/Classification.swift:70-77`).
`Pipeline.decide` then checks `confidence < rule.confidenceThreshold` → `85 <
0.7` is false, so a model reporting percentages sails past the low-confidence
quarantine, and the preview shows "8500%". Fix: apply the same `>1 → /100`
normalization to the numeric path. **→ branch `claude/fix-classification-parsing`**

**[B12] Unknown model actions are treated as "move".**
`var isMove: Bool { action != "skip" }` (`Classification.swift:44`). A model
answering `"action": "ignore"`, `"none"`, or `"delete"` with a path present
gets its file **moved**. The safe default for an unrecognized action in a
file-moving product is *skip*, not *move*.
**→ branch `claude/fix-classification-parsing`**

**[B13] Rule priority is a complete no-op.**
`Rule.priority` is documented ("Higher priority rules claim a file first",
`Models.swift:85`), editable (stepper in `RuleEditor.swift:18`), claimed
shipped (CHANGELOG "Rule priority", PLAN Phase 3 ✅) — and never read.
`AppState.runScans` (`AppState.swift:181`) and `HeadlessRunner.scanOnce`
iterate rules in array order. With overlapping watch folders, whichever rule
was created first wins, whatever the steppers say.
**→ branch `claude/fix-rule-priority`**

**[B14] The per-scan LLM budget can overshoot by up to 7 calls.**
`Pipeline.scan` computes `allowLLM = budgetRemaining > 0` once per batch of up
to 8 files and decrements only after the batch completes
(`Pipeline.swift:63-86`). With budget 1 and concurrency 8, up to 8 calls fire.
Also, the budget is enforced *per rule per pass*, not per pass as the settings
copy implies — five enabled rules each get the full budget.
**→ branch `claude/fix-budget-overshoot`** (batch-size cap; per-pass semantics documented)

**[B15] A 64 KiB read boundary turns UTF-8 excerpts into mojibake.**
`FileContext.readPlainText` reads exactly 64 KiB (`FileContext.swift:88-94`);
if that boundary splits a multi-byte UTF-8 character, `String(data:, .utf8)`
fails for the *whole* buffer and `TextDecoding.decode` falls through to
CP1252 — the entire excerpt sent to the model becomes garbage for any non-ASCII
text file over 64 KiB. Fix: trim the trailing partial UTF-8 sequence before
decoding. **→ branch `claude/fix-text-extraction`**

**[B16] `<style>`/`<script>` bodies leak into classification samples.**
`HTMLText.strip`'s regex `<(script|style)[^>]*>.*?</\1>` has no `dotMatchesLineSeparators`
(`HTMLText.swift:16-19`), so any multi-line style/script block — i.e. nearly
all of them — survives tag-stripping as literal CSS/JS "text" in the excerpt
the model sees. Fix: add dotall. **→ branch `claude/fix-text-extraction`**

**[B17] `ZipArchive`'s per-entry memory cap doesn't cover stored entries.**
`data(for:)` checks `uncompressedSize <= maxEntryBytes` but for method 0
returns `compressedSize` bytes (`ZipArchive.swift:57-66`). A hostile central
directory can declare a tiny `uncompressedSize` with a huge `compressedSize`
and bypass the 16 MiB cap (bounded only by the 200 MB archive cap). Fix: cap
both. **→ branch `claude/fix-text-extraction`**

**[B18] "Check now" stays clickable while paused — and silently does nothing.**
`BlockMenuItem(title:…, enabled: !state.paused)` sets `isEnabled`, but the
containing `NSMenu` has `autoenablesItems = true` (default), which re-enables
any item whose target responds to its action
(`MenuBar/BlockMenuItem.swift:12`, `StatusItemController.swift:95`). The
disabled state is cosmetic-only intent that never renders; clicking fires
`requestScan()`, which returns immediately because `paused` guards it.
**→ branch `claude/menu-polish`**

**[B19] Duplicate rows in the Review tab render a raw format string.**
`PlanRow.actionLabel` uses `L10n.t("activity.duplicate")` — a three-argument
format string — with no arguments (`PreviewView.swift:110`), so the row shows
`[%@] Duplicate: %@ already exists as %@`. **→ branch `claude/preview-polish`**

**[B20] Update-check alerts strand a Dock icon.**
All three UpdateChecker alerts call `ActivationPolicy.showRegular()` before
`runModal()` (`UpdateChecker.swift:79,95,104`) and nothing ever reverts to
`.accessory` (reversion only lives in the window controllers'
`windowWillClose`). "Check for Updates…" with no window open leaves a
permanent Dock icon on a menu-bar-only app. **→ branch `claude/fix-update-checker`**

**[B21] UpdateChecker misleads on failure and under-checks by design.**
Three related issues (`UpdateChecker.swift:34-67`): (a) when version parsing
fails it shows the "You're up to date" alert; (b) `lastCheck` is stamped
*before* the network call, so a failed launch-time check (offline Mac waking
up) suppresses retries for 24 h; (c) the "once a day" check only actually runs
at *launch* — a menu-bar agent that stays up for weeks never re-checks,
contradicting CICD.md's "polls once a day".
**→ branch `claude/fix-update-checker`**

**[B22] `FSEventsWatcher` callback can use-after-free.**
The FSEvents callback context uses `Unmanaged.passUnretained(self)`
(`Watch/FSEventsWatcher.swift:22-29`) and teardown happens in `deinit` —
triggered whenever `rebuildWatchers()` drops the old array
(`AppState.swift:110-118`), which happens on every debounced config save. If
an event callback is in flight on the utility queue at that moment, it calls
into a deallocating object. Low probability per save, nonzero over months of
uptime. *(Documented; the fix — retained context + stop-before-release — is
concurrency-sensitive and left for a Mac-verified pass.)*

**[B23] Miscellaneous small ones (documented, not fixed):**
- `startTimer` does `UInt64(interval * 1_000_000_000)` — a hand-edited absurd
  `scanIntervalSeconds` traps at launch (`AppState.swift:154`). (Clamped in
  **→ branch `claude/fix-rule-priority`** while touching the file.)
- Files with a *future* modification date never pass `isStable`
  (`Pipeline.swift:375`) and are silently never processed.
- `TextDecoding.decode(_:declared:)`'s `declared` tier is dead code — no caller
  passes it, so XML/HTML charset declarations are ignored (`TextDecoding.swift:24`).
- `findEOCD` scans backwards and will lock onto a fake EOCD signature embedded
  in an archive comment, rejecting a valid EPUB (`ZipArchive.swift:117-126`).
- A dangling symlink at a destination defeats collision handling:
  `fileExists` says free, `moveItem` then throws, forever (`Mover.swift:73`).
- `JournalTests` calls `setenv("SORTOMAT_CONFIG_DIR", …)` in `setUp`
  (`SortomatTests/JournalTests.swift:11`), but `ProcessInfo.environment` is
  cached the moment `AppDelegate.isRunningTests` reads it at host launch — the
  override is very likely invisible and the tests touch the developer's real
  `~/Library/Application Support/Sortomat`.
- `sort_epubs.py` (the legacy script the README still links) declares two
  books duplicates on byte-size alone (`sort_epubs.py:449`) — the exact bug
  the Swift app fixed.
- Preview-then-approve executes a plan against whatever now sits at the source
  path; `PlannedAction` carries no content fingerprint to re-validate.

---

## 3. Performance & responsiveness

**[P1] Dry-run classifications are never persisted — relaunch re-pays for everything.**
The `previewed` set is in-memory (`Pipeline.swift:15-18`) and preview decisions
are deliberately not written to the ledger. Every app relaunch (and every
headless run) re-classifies — and re-pays for — every pending dry-run file.
For the recommended way to use the app (start everything in preview!), this is
the single biggest cost bug. *(Needs a persisted pending-plans store; design
sketched under [F2].)*

**[P2] One stuck file stalls the whole rule.** `Pipeline.scan` processes files
in strict batches with a barrier (`Pipeline.swift:59-86`): the next batch
starts only when the slowest member of the current one finishes. One file
hitting the 90 s timeout × 4 retries (see [B10]) holds up to 7 neighbors
hostage for ~6 minutes. A sliding-window (task-group with replenishment) fixes
this cheaply.

**[P3] `isStable` sleeps 700 ms per file *inside* the batch slot**
(`Pipeline.swift:369-379`). 10 000 backlog files ≈ 58 minutes of pure sleeping
even with zero LLM calls. The stability probe should run concurrently for the
whole candidate set (or compare against the previous scan's snapshot) rather
than napping per-file.

**[P4] New files wait for the *next* timer tick.** FSEvents fires ~1 s after a
download lands, the debounced scan runs 2 s later — and `isStable` rejects the
file because it's younger than 5 s (`Pipeline.swift:375`). Nothing re-queues a
follow-up, so the file waits for the periodic scan (up to 60 s+). The README's
"instant reaction" is really "next tick". Fix: when a scan skips unstable
candidates, schedule one follow-up pass ~6 s out.

**[P5] Unbounded growth everywhere.** `ledger.json` is never pruned (stale
`path|size|mtime` keys accumulate forever — and a renamed file re-pays
classification since the key is path-based), `journal.jsonl` and `activity.log`
are append-only with no rotation, and `Journal.recent` reads + decodes the
whole journal on the main thread every time the History tab appears
(`Journal.swift:37`, `Ledger`, `ConfigStore.appendLog`). The ledger is also
re-encoded and rewritten after every scan pass even when nothing changed
(`Ledger.save`, called from `AppState.runScans`).

**[P6] Watcher churn on every keystroke-ish.** `persistAndApply()` (debounced
800 ms) unconditionally tears down and recreates *every* FSEvents stream
(`AppState.swift:61-70,110-118`) even for config edits unrelated to watching.
Should diff the (enabled, path) set and rebuild only on change. Also
interacts badly with [B22].

**[P7] Assorted:** whole EPUB loaded into memory twice per classification
(`Data` + `[UInt8]` copy, `ZipArchive.swift:24-31`); Spotlight
`kMDItemTextContent` regex-normalized in full before truncation to 4 000 chars
(`FileContext.swift:73-75`); collision resolution re-hashes up to 4 MiB of
every same-named neighbor on each placement (`Mover.swift:82-93`); recursive
scans enumerate the entire target subtree just to reject every file
(`Pipeline.swift:346-358`); one fat `AppState` `ObservableObject` means every
keystroke in the rule editor invalidates every visible view; a fresh
`ISO8601DateFormatter` per log line on the main actor (`ConfigStore.swift:50`).

---

## 4. UX, visual & layout issues

**[U1] There is no way to say "no" to a suggestion.** The Review tab offers
Apply / Apply All / Refresh — `AppState.dismiss(_:)` exists
(`AppState.swift:243`) but no UI calls it. Declining one wrong move means
either applying it anyway or leaving it to haunt the list.
**→ branch `claude/preview-polish`**

**[U2] No feedback during Refresh / after Apply.** `busy` only disables
buttons (`PreviewView.swift:47-67`); a refresh that's mid-LLM-call looks
identical to "nothing happening", and applying gives no confirmation. Add a
`ProgressView` and a result line. **→ branch `claude/preview-polish`**

**[U3] The empty state lies when no API key is set.** With a missing key,
`refreshPreview` returns before doing anything (`AppState.swift:218-219`) and
the window shows "Nothing to file right now." — the user thinks all is well.
Show the real blocker. **→ branch `claude/preview-polish`**

**[U4] Review rows hide *which rule* and *why*.** `PlanRow` shows file,
destination, reason and confidence, but not the rule name or the decision
origin (pre-rule vs model vs taxonomy-redirect) — with several rules active
you can't tell who claimed what (`PreviewView.swift:77-131`).
**→ branch `claude/preview-polish`**

**[U5] Menu-bar icon never reflects state.** `StatusItemController` subscribes
to `$pendingActions` precisely to update the icon (`StatusItemController.swift:36`)
— but `updateIcon()` only sets the funnel and `appearsDisabled`. Pending
reviews are invisible until you open the menu. A count badge next to the
funnel is the obvious affordance. **→ branch `claude/menu-polish`**

**[U6] Deleting a rule is instant and unrecoverable.** The "−" button
immediately removes the rule and forgets its ledger
(`RulesTab.swift:53-56`, `AppState.remove`). One mis-click destroys a
carefully-tuned prompt and taxonomy. Needs a confirmation dialog.
**→ branch `claude/confirm-rule-deletion`**

**[U7] Notifications never appear while the app is frontmost.** No
`UNUserNotificationCenterDelegate` is installed anywhere, so macOS suppresses
banners while Sortomat is active (`Common/Notifier.swift`) — i.e. exactly when
the user has the Preview/Settings window open and would want to see "3 files
filed". **→ branch `claude/menu-polish`**

**[U8] The notifications toggle overpromises.** Its label says "Show a
notification for each filed / failed file" (`L10n.swift:139`), but the code
posts only the *first failure* per scan result and nothing on success
(`AppState.notify`, `AppState.swift:206-212`). Align copy or behavior — and
note a missing watch folder currently re-notifies on *every* pass with no
cooldown.

**[U9] No ⌘W / Escape to close windows.** `MainMenu` builds only App + Edit
menus (`MenuBar/MainMenu.swift`), so the standard Close shortcut doesn't exist;
windows are mouse-close only. **→ branch `claude/menu-polish`**

**[U10] Windows forget their frame.** Neither window controller sets a frame
autosave name (`SettingsWindowController.swift:25-28`,
`PreviewWindowController.swift:24-27`); size/position reset every launch.
**→ branch `claude/preview-polish`**

**[U11] Editing a rule silently stops it.** The editing lock (a good idea!)
means the *selected* rule doesn't run while the Rules tab is open
(`AppState.swift:184`) — with zero UI indication. Leave Settings open over
lunch and you'll wonder why nothing sorted. A small "paused while editing"
badge on the rule row would do.

**[U12] Assorted polish:** "Saved to the Keychain." confirmation never clears
while typing a new key (`GeneralTab.swift:25`); rules-list toolbar buttons are
icon-only with no tooltips except Duplicate (`RulesTab.swift:39-65`); the
settings window is titled "Sortomat — Rules" while the menu item says
"Rules & Settings…" (`L10n.swift:50`); `1 change(s) awaiting review…` plural
hack (`L10n.swift:33,47`); the taxonomy hint string
(`rule.taxonomy.prompt`) exists but is never displayed since `TextEditor` has
no placeholder support; no validation feedback anywhere in the rule editor
(nonexistent paths, watch == target, invalid regex pre-rules all fail
silently — watch-inside-target silently yields zero candidates forever,
`Pipeline.swift:346`).

**[U13] First-run is a shrug.** The app launches into… nothing visible (menu
bar only), with a disabled German example rule and no pointer to the icon, no
"add your key → pick a folder → watch a preview" path. See [I1]/[I3].

---

## 5. Localization

**[L1] English UI, German soul.** New rules are named "Neue Regel"
(`Models.swift:113,150`), the quarantine folder defaults to `_Quarantäne`
(`Models.swift:125`), and all three template prompts — including the seeded
first-run rule — are German-only (`Templates.swift:86-106`) regardless of UI
language. An English-speaking user gets German folder names and a German
prompt steering their model. **→ branch `claude/localize-defaults`**

**[L2] Hardcoded-English stragglers in a bilingual app:** "Check for
Updates…" (`StatusItemController.swift:112`), every UpdateChecker alert,
`PathField`'s "Choose…" + `/path/to/folder`, the entire `MainMenu`,
`Journal.UndoError` messages, `HeadlessRunner`'s "Nothing to undo.". The
CHANGELOG's "English + German localization" is ~90 % true.
*(Menu + updates strings fixed in `claude/menu-polish` / `claude/fix-update-checker`;
the rest documented.)*

**[L3] The Screenshots template is a double no-op.** Its only pre-rule is glob
`*creenshot*` → action `useLLM` (`Templates.swift:50-57`) — but `useLLM` is
already the fall-through, so the pre-rule changes nothing; and the glob
wouldn't match German "Bildschirmfoto" anyway. Meanwhile the prompt tells the
model to use "visible text and the image description" — content the app never
sends (no OCR/vision path; see [F7]).

---

## 6. Missing features & broken promises

**[F1] Launch at login: promised, implemented, unwired.** README line 63:
"Launch at login is a toggle inside the app." `Common/LaunchAtLogin.swift`
wraps `SMAppService` completely — and is referenced by zero views. There is no
toggle. **→ branch `claude/add-launch-at-login`**

**[F2] Pending previews don't survive a relaunch.** `pendingActions` lives
only in `AppState`; quit and every queued review is gone (and re-paid, [P1]).
For a "preview-first" product the pending queue should persist (a
`pending.json` beside the journal, invalidated by rule edits).

**[F3] Quarantine is a roach motel.** Files go *into*
`target/_Quarantäne` (`Pipeline.swift:243`), and no UI ever shows, re-files,
or even counts them. The README sells taxonomy+quarantine as a headline
safety feature; the product needs a Quarantine tab — list, reason shown,
"re-classify with hint" and "move where I say" actions. (See [I6].)

**[F4] No batch undo in the GUI, and the CLI's "batch" is 5 seconds.**
`HeadlessRunner.undoLast` takes entries within 5 s of the newest
(`HeadlessRunner.swift:53`) — a scan whose LLM calls stretch over minutes gets
partially undone. `JournalEntry` needs a `batchID` (one per scan pass);
History gets "Undo last batch". *(Tombstones + safe copy-undo land in
`claude/fix-journal-undo`; batch IDs documented for a follow-up.)*

**[F5] One global model/provider for all rules.** `Config` has a single
`model`/`apiBase`/`providerRequiresKey` (`Models.swift:172-175`), so the
privacy story "point sensitive rules at a local model" can't coexist with
cloud rules. Per-rule override (defaulting to global) is the natural shape.

**[F6] Deterministic-only rules still demand an API key.** `runScans` bails
app-wide when the provider needs a key and none is set
(`AppState.swift:177-178`), even if every enabled rule would be fully served
by pre-rules. Free, deterministic sorting shouldn't be hostage to a key field.

**[F7] No image/OCR support.** `FileContext.extractSample` handles text, PDF,
EPUB — for images it sends metadata only (plus whatever Spotlight OCR happened
to index), while the bundled Screenshots template *asks* the model about
visible text ([L3]). Vision framework OCR (`VNRecognizeTextRequest`) is a
system-framework-only fit for this codebase, and vision-capable models are one
`image_url` content-part away.

**[F8] No spend persistence.** `usage` (and therefore "Estimated spend")
resets to zero every launch (`AppState.swift:19`); there's no monthly ledger,
no per-rule attribution, no budget alarm. Cost-awareness is a README bullet —
make it real ([I8]).

**[F9] Rules are not portable.** No export/import (Hazel has `.hazelrules`;
organize-tool has shareable YAML). A rule — prompt + taxonomy + pre-rules — is
exactly the kind of artifact people want to share.

**[F10] No exclusion patterns for recursive rules** (pre-rules match filename
only, `DeterministicEngine.swift:44`); no per-rule conflict policy (rename vs
skip vs replace — hardcoded to suffixing); no rename-in-place action (target ==
watch yields zero candidates, `Pipeline.swift:346`); failed files retry every
30 minutes forever with no backoff or "stuck files" surface
(`Ledger.swift:62`, PLAN's promised stuck-file view was never built).

---

## 7. CI / build / release / docs

**[C1] Prerelease tags publish as full releases.** `release.yml` triggers on
`v*` — including `v1.2.0-beta.1` — and neither publish step passes
`prerelease:` to `softprops/action-gh-release`
(`.github/workflows/release.yml:5,146-176`). A beta tag therefore becomes the
repo's *latest* release and the in-app UpdateChecker (stable-only by default,
`allowPrereleases: false`) happily offers it to every user.
**→ branch `claude/fix-release-prerelease`**

**[C2] "Staple the DMG" can never succeed.** Only the *zip of the .app* is
notarized (`release.yml:109-115`); the DMG is created afterwards from the app
and `stapler staple "$DMG"` fails — silently, thanks to `|| true`
(`release.yml:142-144`). Harmless in practice (the app inside is stapled) but
CICD.md's "The DMG is stapled too" is false. **→ branch `claude/fix-release-prerelease`**

**[C3] Docs drift, small but telling:** CICD.md documents `APPLE_TEAM_ID` as a
signing gate but the workflow gates only on the P12 + AC key; `scripts/build.sh`
and `release.sh` hard-depend on an external `lkm-build` tool the README
presents as a working path; README's "watches folders… instant reaction"
oversells given [P4]; AGENTS.md tells agents the update cadence is daily
([B21] says otherwise).

---

## 8. Security & privacy notes

- **Prompt injection is real but well-contained.** File contents go into the
  user prompt, so a hostile document can steer *folder/filename* choice — but
  `Sanitizer.destination` (traversal rejection before sanitizing + post-hoc
  prefix check, `Sanitizer.swift:44-79`) confines the blast radius to
  *misfiling inside the target*, and taxonomy + quarantine narrow it further.
  This is the right architecture; keep it. Consider stripping/flagging
  suspicious "ignore your instructions" excerpts before sending.
- **The API key follows the base URL.** `apiBase` is user-editable and the
  Bearer key is sent wherever it points (`LLMClient.swift:89-94`) — a
  config-file edit (or a hijacked config) exfiltrates the key. At minimum,
  warn loudly in the UI when the base URL changes away from a known provider.
- **No sandbox** (deliberate, Developer-ID distribution) and no entitlements —
  documented accurately in `.github/CICD.md`. Fine for now.
- `ZipArchive` declines zip64 rather than misparsing, bounds the EOCD scan,
  and caps decompression ([B17] aside) — good hostile-input posture.

---

## 9. Ideas — novel, cool, delightful, quirky

Curated from three brainstorm panels (delight / power-user / trust), keeping
only what fits this codebase and its safety-first ethos.

**Trust & onboarding**
- **[I1] Sandboxed first-run tour**: create `~/Sortomat Demo/`, drop 3 sample
  files, run a real preview → approve → undo cycle on them. Teaches the whole
  trust loop in 60 seconds with zero risk to real files.
- **[I2] "Why this destination?" popover**: PlannedAction already carries
  `origin`, `reason`, `confidence` — show exactly what the model saw (the
  FileContext description) and what it answered, per row. Trust through
  transparency, nearly free to build.
- **[I3] Trust score per rule**: after N consecutive approved previews with
  zero corrections, offer "this rule has earned auto-mode" (and the reverse:
  auto-demote to preview after an undo streak). Graduation, not a cliff.
- **[I4] Before/after folder diff** in the Review tab: a two-column tree of
  the target, current vs post-apply, additions highlighted.
- **[I5] Undo where the action happened**: a notification "Undo" action button
  and a menu-bar "Undo last batch…" item — undo shouldn't require opening a
  window and finding a row.

**Power**
- **[I6] Quarantine inbox** ([F3]) with one-click "re-classify with hint" —
  the hint gets appended to the rule prompt for that file only; corrections
  optionally accumulate as few-shot examples the rule learns from.
- **[I7] Backlog wizard**: "This folder has 1 843 files. Estimated cost:
  $0.87. Sort in chunks of 100, preview each chunk?" — turns the scariest
  moment (pointing Sortomat at years of Downloads) into a guided, budgeted run.
- **[I8] Persistent cost meter**: per-month spend + per-rule attribution +
  "each preview row shows its price tag" ($0.0004 — surprisingly calming).
- **[I9] Batch classification**: N files per LLM call (the response is a JSON
  array) — a 5-10× token cost cut for backlogs, at slightly lower per-file
  accuracy; perfect for the wizard in [I7].
- **[I10] Per-rule model override** ([F5]) — local model for the tax-documents
  rule, frontier model for the messy-screenshots rule.
- **[I11] Rule simulation in the editor**: "Test on 5 random matching files"
  → dry classifications shown inline, nothing moved, before the rule is ever
  enabled. (Pipeline's decide/apply split makes this nearly free.)
- **[I12] Automation surface**: `sortomat://scan?rule=…` URL scheme, Shortcuts
  actions (App Intents), and a Finder "Sort with Sortomat" service. The
  headless runner already proves the core is callable.

**Delight**
- **[I13] The funnel gulps**: 300 ms dot-falls-through-funnel animation on the
  menu-bar icon when a file is filed (`NSImageView` frame swap, no heavier
  machinery). Paired with an optional single soft "thunk" per *batch* —
  never per file.
- **[I14] Weekly Tidy Report**: one notification, Monday 9:00 — "42 filed,
  2 quarantined, 0 undone · your Downloads folder lost 3.2 GB · $0.11". Dry
  wit encouraged ("Your desktop can see the sun again").
- **[I15] Chaos meter**: a tiny gauge in the menu header rating the watch
  folders' entropy ("Zen garden" → "Tornado warning") — computed from file
  count / age spread, no LLM needed. Quirky, informative, shareable.
- **[I16] Milestone toasts**: 1 000th file filed gets a one-liner. Rotating
  deadpan empty states in the Review tab ("Inbox zero. Well, folder zero.").
- **[I17] Spend-o-meter in espresso units**: "$0.42 this month — about half an
  espresso." Cost anxiety is the #1 adoption blocker for LLM tools; humor
  disarms it.

---

## 10. Refuted / verified-fine (for transparency)

Claims raised during review that inspection killed — recorded so nobody
re-litigates them:

- `SORTOMAT_API_KEY` env override *is* implemented (`Keychain.swift:41-47`) —
  README's headless example is correct.
- `Sanitizer` traversal defense is genuinely layered and correct for its
  threat model (pre-check before sanitizing + standardized-prefix post-check).
- `EpubReader.resolvePath` can't escape the archive namespace; XML parsing
  doesn't load external entities.
- The two `CICD.md` files are intentional (quick-ref vs. detailed) and
  cross-linked, not an accident.
- `Keychain.get` on a locked keychain returns nil → headless run exits 2 with
  a clear message (not silent 401s as one reviewer claimed).
- CI itself is solid: pinned Xcode, `pipefail`, result-bundle artifact on
  failure, release re-runs tests before publishing.

---

## Implementation plan

Branches implemented in this pass (each self-contained, ordered so file
overlap between them is minimal; L10n additions land in distinct dictionary
sections):

| Branch | Items | Files touched |
| --- | --- | --- |
| `claude/fix-cross-volume-verify` | B1, B2 (+B7 documented) | Mover, ContentHash, MoverTests |
| `claude/fix-llm-client` | B10 + `/v1` base-URL normalization (U-adjacent [F-gap]) | LLMClient, new LLMClientTests |
| `claude/fix-classification-parsing` | B11, B12 | Classification, ClassificationTests |
| `claude/fix-config-corruption` | B3 | ConfigStore, ConfigMigrationTests |
| `claude/fix-journal-undo` | B4, B5, B6 | Journal, AppState, PreviewView (History), JournalTests |
| `claude/fix-rule-priority` | B13 + interval clamp (B23a) | AppState, HeadlessRunner |
| `claude/fix-budget-overshoot` | B14 + target-subtree skip (P7d) | Pipeline |
| `claude/fix-text-extraction` | B15, B16, B17 | FileContext, HTMLText, ZipArchive, tests |
| `claude/fix-keychain-set` | B8 | Keychain |
| `claude/fix-update-checker` | B20, B21 (+ localized alerts, L2-partial) | UpdateChecker, L10n |
| `claude/preview-polish` | U1, U2, U3, U4, U10, B19 | PreviewView, window controllers, L10n |
| `claude/menu-polish` | U5, U7, U9, B18, L2-partial | StatusItemController, BlockMenuItem, MainMenu, Notifier, L10n |
| `claude/confirm-rule-deletion` | U6 | RulesTab, L10n |
| `claude/add-launch-at-login` | F1 | GeneralTab, L10n |
| `claude/localize-defaults` | L1 | Models, Templates, L10n |
| `claude/fix-release-prerelease` | C1, C2 | release.yml, CICD.md |

Deliberately **not** implemented without a Mac to verify on: B9 (cross-process
locking), B22 (FSEvents lifecycle), P1-P4 (pipeline scheduling redesign), F2
(pending-plan persistence), and everything in §9 — those deserve design
attention and a running app, not blind patches.

*— Fable*
