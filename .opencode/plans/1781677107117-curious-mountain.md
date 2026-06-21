# Accessibility Tracker Implementation Plan

## Go-To Position Dialog: Value Capture Fix

### Problem

The `GoToPositionDialog` always returns `1` regardless of what the user types. This makes it seem like:
- **Command palette doesn't work** — the action dispatches, the dialog opens, but entering any value navigates to position 1 (often where the cursor already is, so nothing visible happens)
- **Hotkeys open dialog but value is ignored** — same root cause

### Root Cause

In `GoToPositionDialog.qml` (line 98), `currentValue: 1` is hardcoded with no `onValueEdited` handler. The `IncrementalPropertyControl` emits `valueEdited` on every keystroke (via its internal `onTextEdited` handler at `IncrementalPropertyControl.qml:256-268`), but the dialog never captures it. So `currentValue` stays at `1` forever.

The existing `TempoDialog.qml` and `SelectMeasuresCountDialog.qml` both handle this correctly with a separate tracking property + `onValueEdited` handler:

```qml
// TempoDialog pattern (correct):
property int tempoBpm: 120
IncrementalPropertyControl {
    currentValue: root.tempoBpm
    onValueEdited: function(newValue) { root.tempoBpm = newValue }
    onAccepted: { root.ret = { errcode: 0, value: root.tempoBpm }; root.hide() }
}
```

### Fix

**File:** `src/notationscene/qml/MuseScore/NotationScene/GoToPositionDialog.qml`

Follow the `TempoDialog` pattern exactly:

1. **Add tracking property** (after `property string dimension: "beat"`, line 31):
   ```qml
   property int positionValue: 1
   ```

2. **Bind `currentValue` to tracking property** (line 98):
   - Change `currentValue: 1` → `currentValue: root.positionValue`

3. **Add `onValueEdited` handler** (after `maxValue: 999`, line 102):
   ```qml
   onValueEdited: function(newValue) {
       root.positionValue = newValue
   }
   ```
   This fires on every keystroke (via `IncrementalPropertyControl`'s internal `onTextEdited` → `valueEdited` chain) and also on +/- button clicks.

4. **Return tracking property in `onAccepted`** (line 105):
   - Change `root.ret = { errcode: 0, value: currentValue }` → `root.ret = { errcode: 0, value: root.positionValue }`

5. **Return tracking property in OK button** (line 131):
   - Change `root.ret = { errcode: 0, value: inputField.currentValue }` → `root.ret = { errcode: 0, value: root.positionValue }`

### Why This Works

The `IncrementalPropertyControl` has an internal `onTextEdited` handler (line 256-268 of `IncrementalPropertyControl.qml`) that:
1. Fires on every keystroke in the text field
2. Parses the text to a number
3. Emits `valueEdited(newValue)`

When the dialog handles `onValueEdited`, it updates `root.positionValue` on every keystroke. By the time the user presses Enter or clicks OK, `root.positionValue` already holds the typed value.

The binding `currentValue: root.positionValue` ensures the display stays in sync (e.g., if +/- buttons are used, the text field updates).

### Verification

1. `.\dev.ps1 build -j 8` — build succeeds
2. `.\dev.ps1 run` — launch app
3. Open a score with multiple measures
4. Press `Ctrl+Alt+M` — dialog opens
5. Type `5`, press Enter — cursor should jump to measure 5
6. Press `Ctrl+Alt+S` — dialog opens
7. Type `2`, click OK — cursor should jump to staff 2
8. Open command palette (`Ctrl+K`), type "go to beat", select it
9. Type `3`, press Enter — cursor should jump to beat 3
10. Test clamping: type `9999`, press Enter — cursor should jump to last measure

---

## Previous: Accessibility Tracker Implementation Plan

## Goal

Address the remaining GitHub tracker issues on `tbui17/MuseScore` without turning screen-reader output into noisy, constant narration.

Tracker state at planning time:

- `#1` Accessibility: instrument selection feedback - closed, implemented.
- `#2` Accessibility: screen reader too verbose when toggling 6-key braille input mode - open.
- `#3` Accessibility: braille input announces dashes instead of numbers - open.
- `#4` Bug: instrument playback blocked when braille panel is disabled - open.
- `#5` Audit screen reader quality across core workflows - open, audit comment posted.
- `#6` Tempo BPM command-palette access - closed, implemented.
- `#7` Feature: shortcut to play current measure/beat/staff - open.

## Guiding Decisions

- Do not announce command-palette result counts on every typed character. The screen reader already echoes typed text, and per-keystroke result-count announcements would likely be noisy.
- For command palette, prioritize useful state changes: selected result when arrowing and `No matching commands` when the list becomes empty.
- Treat score-navigation verbosity as both staged approaches:
  - First: add shortcut/command-palette-activated on-demand announcements for details.
  - Later: add a user-facing verbosity setting once the useful detail levels are validated.
- Treat `#2` and `#3` as reproduction-gated. If manual testing shows the current behavior is already acceptable, close or rewrite those issues instead of forcing unnecessary patches.
- Prefer command-palette availability first for new accessibility actions. Add default shortcuts only after checking all shortcut maps for conflicts.

## Recommended Execution Order

1. Close out quick, safe `#5` patches that reduce immediate accessibility gaps.
2. Reproduce and either fix or close/refine `#2` and `#3`.
3. Fix likely `#4` root cause in braille state tracking: current braille item state is currently tied to braille panel visibility.
4. Implement `#7` in two steps: first add a playback-controller scoped-range API, then add command-palette actions.
5. Add on-demand detail announcements for `#5` score-navigation verbosity.
6. Add a verbosity setting only after on-demand commands prove the desired content and wording.

## Phase 1: Quick `#5` Accessibility Fixes

### 1.1 Announce Note-Input Sub-Mode Changes

Issue coverage: `#5`

Files:

- `src/notation/internal/notationnoteinput.cpp`
- `src/notation/internal/notationnoteinput.h` if declarations need adjustment
- `src/notationscene/internal/notationactioncontroller.cpp` for action-path verification only

Plan:

- In `NotationNoteInput::setNoteInputMethod()`, announce the new method after the method is applied and `notifyAboutStateChanged()` runs.
- Reuse the existing `nameOfNoteInputMethod(method).translated()` helper already used by `startNoteInput()`.
- Do not announce if the requested method is already active and the method was not changed.
- Code check: `setNoteInputMethod()` already exits early when `is.usingNoteEntryMethod(method)` is true and when the method is unavailable, so the patch can be a single `accessibilityController()->announce(nameOfNoteInputMethod(method).translated())` after line 437's `notifyAboutStateChanged()`.
- No header change appears necessary because `NotationNoteInput` already has accessibility-controller access for `startNoteInput()` and `endNoteInput()` announcements.

Verification:

- Enter note input mode; confirm existing method announcement still occurs.
- While still in note input mode, switch to repitch/rhythm/duration input; confirm the new mode is announced.
- Exit note input mode; confirm `Normal mode` is still announced once.

### 1.2 Improve Command Palette State Feedback Without Per-Keystroke Noise

Issue coverage: `#5`

Files:

- `src/appshell/qml/MuseScore/AppShell/CommandPaletteDialog.qml`
- `src/appshell/qml/MuseScore/AppShell/commandpalettemodel.h`
- `src/appshell/qml/MuseScore/AppShell/commandpalettemodel.cpp`
- `muse/framework/accessibility/iaccessibilitycontroller.h` for API reference only

Plan:

- Do not call `announce()` from `onSearchTextChanged`.
- Improve each result delegate's accessible name in `CommandPaletteDialog.qml` from `model.title` to useful position context, e.g. `Set tempo, 2 of 4`.
- Keep the visible result count label, but do not make it an assertive live region by default.
- Make arrow-key navigation the primary feedback path: when the selected delegate receives focus, the screen reader should hear the selected command title and position.
- If manual validation shows `navigation.requestActive()` still does not cause result names to be spoken, add a model/controller announcement method as a fallback and call it only for Up/Down selection changes.
- Add a no-results announcement only when `resultCount` transitions from nonzero to zero, e.g. `No matching commands`.
- If the count label is revoiced on every model reset during testing, make that label static/non-live and rely on on-demand focus/selection output instead.
- Code check: the model already exposes `resultCount` and delegate `index`, so position text can be done entirely in QML without changing `CommandPaletteModel`.
- Code check: `focusResult()` already calls `item.navigation.requestActive()` after `positionViewAtIndex()`. If that is enough for screen readers, avoid adding `IAccessibilityController` to the model.
- If no-results needs an explicit announcement, add a minimal `CommandPaletteModel::announceEmptyStateIfNeeded()` only after validating that focusing `emptyStateLabel` or its `Accessible.name` is insufficient. Guard it with a previous-result-count state so it fires only on nonzero-to-zero transitions.

Verification:

- Open command palette and type normally; confirm typed characters are not interrupted by count announcements.
- Press Up/Down through results; confirm the selected command title and position are announced.
- Type a query with no matches; confirm `No matching commands` is announced once when entering the empty state.
- Clear or change search back to matching results; confirm the command palette remains usable and not overly chatty.

### 1.3 Add Playback Control Accessible Values

Issue coverage: `#5`

Files:

- `src/playback/qml/MuseScore/Playback/internal/PlaybackSpeedSlider.qml`
- `src/playback/qml/MuseScore/Playback/internal/PlaybackSpeedPopup.qml`
- `src/playback/qml/MuseScore/Playback/internal/PlaybackToolBarActions.qml`
- `src/playback/qml/MuseScore/Playback/PlaybackToolBar.qml`

Plan:

- Add current values to accessible names for playback speed controls, e.g. `Speed 80%`.
- Add a clear accessible label for the play-position slider.
- Add a clear accessible name for the tempo display/button that includes the current tempo when available.
- Keep wording short; these controls are frequently focused.
- Code check: `PlaybackToolBarModel::tempo()` returns `noteSymbol` and integer `value`; QML can use `root.playbackModel.tempo.value` for `Tempo %1 BPM` without C++ changes.
- Code check: `PlaybackSpeedSlider.qml` and `PlaybackSpeedPopup.qml` set only `navigation.accessible.name: "Speed"` on the incremental control, and their sliders have no explicit navigation accessible name. Add value-bearing accessible names to both controls.
- Code check: the floating play-position `StyledSlider` in `PlaybackToolBar.qml` has navigation panel/order but no accessible name. Add a label such as `Playback position` and, if supported by `StyledSlider` accessibility, expose current percentage/time via name or value.
- Code check: the non-floating tempo button in `PlaybackToolBarActions.qml` has `toolTipTitle: "Speed"` but no explicit accessible name. Add `accessible.name: qsTrc("playback", "Speed %1%; tempo %2 BPM")...` or shorter `Speed %1%` depending on manual output. The floating `TempoView` component is visual-only, so wrap/expose an accessible name on the containing item if it can receive navigation focus.

Verification:

- Focus playback speed slider and adjust it with keyboard; confirm value is announced.
- Focus tempo display/button; confirm current tempo is announced clearly.
- Focus play-position slider; confirm it has a label.

### 1.4 Fix Tempo Accessibility Polish

Issue coverage: `#5`, related to closed `#6`

Files:

- `src/engraving/dom/tempotext.cpp`
- `src/notationscene/qml/MuseScore/NotationScene/TempoDialog.qml`

Plan:

- Update `TempoText::accessibleInfo()` or nearby tempo accessibility formatting to include effective BPM from the score tempo map when safe and available.
- Make `TempoDialog.qml` expose an explicit accessible dialog name if `StyledDialogView` does not already map `title` to the accessible name.

Verification:

- Navigate to a tempo marking; confirm BPM is clear and not redundant.
- Open Set Tempo dialog; confirm the screen reader announces `Set tempo` and the BPM field label/value.

## Phase 2: Reproduction-Gated Braille Issues

### 2.1 `#2`: 6-Key Toggle Verbosity

Files:

- `src/braille/internal/notationbraille.cpp`
- `src/braille/qml/MuseScore/Braille/BrailleView.qml`
- `src/braille/qml/MuseScore/Braille/braillemodel.cpp`
- `src/appshell/qml/MuseScore/AppShell/notationpagemodel.cpp`
- `src/notationscene/qml/MuseScore/NotationScene/notationviewinputcontroller.cpp`
- `.personal/braille-panel-ux-notes.md` for expected behavior reference, if present

Plan:

- First reproduce manually with a screen reader or inspect the precise announcement path.
- Capture what is spoken when toggling 6-key input mode on and off.
- Current code has three distinct mode paths that must be reasoned about together:
- `NotationBraille::init()` sets mode from `brailleConfiguration()->sixKeyInputEnabled()`.
- `NotationPageModel` toggles only the configuration value for action `toggle-braille-six-key-input`.
- `NotationViewInputController::ensureBrailleSixKeyNoteInputStarted()` silently calls `notationBraille()->setMode(BrailleMode::BrailleInput)` when score-view six-key input begins.
- `BrailleView.qml` exposes `fakeNavCtrl.navigation.accessible.name` as either `Six-key input mode` or `Navigation mode`.
- `NotationBraille::toggleMode()` announces either `Six-key input mode` or `Navigation mode`, with `; pending braille input discarded` appended when needed.
- Risk: `BrailleModel::load()` currently forces `notationBraille()->setMode(BrailleMode::Navigation)` even if `NotationBraille::init()` restored the persisted six-key setting. Confirm whether this overrides the startup restore when the panel loads; if so, remove that reset or make it honor `sixKeyInputEnabled()`.
- If the current output is already concise, comment on `#2` with findings and close or rewrite the issue around the actual remaining problem.
- If output is verbose, first identify whether duplicate speech comes from explicit `announce()` plus a focus/name change on `fakeNavCtrl`. Prefer one source of truth.
- If explicit mode announcements remain, centralize wording in `NotationBraille` so the default announcement is only `Six-key input mode` or `Navigation mode`.
- Keep the pending-input warning short. The current appended phrase is already concise; do not expand it unless testing proves it is unclear.
- Do not tie six-key mode state to braille panel visibility. Score-view six-key input already works through `NotationViewInputController` without the panel.

Verification:

- Toggle 6-key mode with no pending input; confirm a short mode announcement.
- Toggle with pending input; confirm the discard behavior is clear but not verbose.
- Confirm normal braille input feedback still works.

### 2.2 `#3`: Braille Dashes vs Semantic Input Feedback

Files:

- `src/braille/internal/notationbraille.cpp`
- `src/braille/internal/brailleinput.cpp`
- `src/braille/internal/brailleinput.h`
- `src/braille/internal/braille.cpp` if rendered braille strings are the source of dashes
- `src/braille/qml/MuseScore/Braille/BrailleView.qml`

Plan:

- First reproduce the exact `dashes instead of numbers` output.
- Determine whether the dashes come from:
  - the visual braille panel text being exposed as the accessible name,
  - a fallback dot-pattern announcement,
  - or stale behavior already fixed by current semantic note/rest announcements.
- If obsolete/not reproducible, comment on `#3` and close or rewrite it.
- If reproducible, prefer semantic announcements first: note/rest names, durations, and musical meaning.
- Use concise fallback wording only when semantic parsing is unavailable, e.g. `dots 1 4`, not dash-heavy strings.
- Current code already has semantic announcements for completed notes and rests:
- `NotationBraille::setKeys()` calls `accessibilityController()->announce(noteAnnouncement(...))` after note entry.
- `NotationBraille::setKeys()` calls `accessibilityController()->announce(restAnnouncement(...))` after rest entry.
- Current code already has semantic pending announcements for octave, accidental, and augmentation dot cells via `semanticPendingAnnouncement()`.
- Current fallback `dotsAnnouncement()` formats each cell using `dots.join('-')`, producing text like `Dots 1-4 entered; input pending`; this may be the dash source. If #3 is reproducible on pending/unknown cells, change this formatter to use spaces (`dots.join(' ')`) or a translatable list phrase, not hyphenated strings.
- The visual braille panel exposes `accessible.text: brailleTextArea.text`, so screen readers may also read rendered braille panel strings when focus is inside the panel. If #3 happens only while navigating/focusing the panel, fix the panel accessible text/name strategy rather than the six-key parser.
- `parseBrailleKeyInput()` maps S/D/F/J/K/L to sorted dot numbers; preserve this behavior. The fix should be presentation only unless parsing is demonstrably wrong.

Verification:

- Enter six-key input mode.
- Type note and rest patterns; confirm musical output is announced.
- Type incomplete or invalid cells; confirm fallback output is concise and understandable.

### 2.3 Missing Braille Operation Announcements From `#5`

Files:

- `src/braille/internal/notationbraille.cpp`

Plan:

- Add concise announcements for interval, tie, slur start, and slur completion flows only after verifying the operations themselves are working.
- Avoid repeating information already produced by playback if it would be noisy.
- Code check: interval input currently adds the note and calls `playbackController()->playElements({ currentEngravingItem() })`, but does not announce; add an `intervalAnnouncement()` near `noteAnnouncement()` and announce after the interval is successfully added.
- Code check: tie input currently stores `tieStartNote` and resets without announcing; announce `Tie started` when a start note is captured, and announce `Tie added` or `Could not add tie` after `addTie()` runs on the next note.
- Code check: short slur input currently stores `slurStartNote` and resets without announcing; announce `Slur started` and `Slur added`/failure around `addSlur()`.
- Code check: long slur stop calls `addLongSlur()` and clears state without announcing; announce completion only when `addLongSlur()` returns true.
- Use `currentEngravingItem()->accessibleInfo()` only if it does not make the message too long; otherwise keep operation-state messages short.

Verification:

- In six-key mode, add an interval; confirm a short semantic announcement.
- Start/end tie or slur operations; confirm the state change is spoken.

## Phase 3: `#4` Playback Blocked When Braille Panel Disabled

Issue coverage: `#4`

Files to investigate first:

- `src/braille/internal/notationbraille.cpp`
- `src/braille/internal/*configuration*`
- `src/braille/qml/MuseScore/Braille/BrailleView.qml`
- `src/notationscene/qml/MuseScore/NotationScene/notationviewinputcontroller.cpp`
- `src/notationscene/qml/MuseScore/NotationScene/NotationView.qml`
- `src/appshell/qml/MuseScore/AppShell/NotationPage/NotationPage.qml`

Plan:

- Reproduce with `Preferences > Braille > Show braille panel = off`.
- Current likely root cause from code: `NotationBraille::doBraille()` returns without doing anything when `brailleConfiguration()->braillePanelEnabled()` is false.
- That means `current_engraving_item`, `current_measure`, and `current_bei` are only refreshed while the visual braille panel is enabled.
- Score-view six-key input does not require the visual panel: `NotationViewInputController::isBrailleSixKeyInputContextActive()` checks `sixKeyInputEnabled()`, `notationBraille()`, note-input state, and edit state, but does not check `braillePanelEnabled()`.
- `NotationViewInputController::handleBrailleSixKeyRelease()` eventually calls `notationBraille()->setKeys(sequence)`.
- `NotationBraille::setKeys()` depends on `currentEngravingItem()` for note-entry playback (`playElements({ currentEngravingItem() })`), interval playback, tie/slur state, and `setVoice()`.
- Therefore disabling the panel can leave score-view six-key input with stale or null current item state, causing playback/operation failures even though the input feature remains enabled.
- Fix direction: split `NotationBraille::doBraille()` into two responsibilities:
- Always resolve the current selected element/measure and call `setCurrentEngravingItem(e, false)` when a notation selection exists, regardless of panel visibility.
- Only generate expensive visual braille strings (`convertItem()`, `convertMeasure()`, `setBrailleInfo()`, `setCurrentItemPosition()`) when `braillePanelEnabled()` is true.
- When panel is disabled, still keep `current_measure` and `current_engraving_item` coherent enough for `setKeys()` and playback. Avoid creating/updating `BrailleEngravingItemList` unless needed for the visible panel.
- Also review `BrailleModel::load()` because it resets mode to Navigation; this is a separate startup-mode risk but may be observed during #4 reproduction if the panel is toggled on/off.
- Do not change `PlaybackController::isPlayAllowed()` unless reproduction shows regular playback action state is disabled. Current playback-core allowed state depends on playback init, notation, visible parts, and loaded state, not braille panel settings.

Verification:

- With braille panel enabled, score-view six-key note entry still plays entered notes/rests normally.
- With braille panel disabled but six-key input enabled, score-view six-key note entry still plays entered notes/rests normally.
- With braille panel disabled, interval/tie/slur operations that depend on `currentEngravingItem()` still have current selection context.
- Toggle the braille panel preference without restarting if supported; panel-specific visual braille output appears/disappears, but six-key input state and playback remain functional.
- Confirm ordinary toolbar playback (`play`, `play-from-selection`) remains unchanged; if it was the originally reported failure, revisit playback action state separately.

## Phase 4: `#7` Play Current Measure / Beat / Staff

Issue coverage: `#7`

Files to explore first:

- `src/playback/internal/playbackuiactions.cpp`
- `src/playback/internal/playbackcontroller.cpp`
- `src/playback/internal/playbackcontroller.h`
- `src/playback/iplaybackcontroller.h`
- `muse/framework/audio/main/iplayer.h`
- `src/playback/tests/mocks/playbackcontrollermock.h`
- `src/notation/internal/notationactioncontroller.cpp`
- `src/notationscene/internal/notationactioncontroller.h`
- `src/notation/inotationinteraction.h`
- `src/notation/internal/notationinteraction.cpp`
- `src/notation/inotationplayback.h`
- `src/notation/internal/notationplayback.cpp`
- `src/notation/internal/inotationselectionrange.h`
- `src/notation/internal/notationselectionrange.cpp`
- `src/app/configs/data/shortcuts.xml`
- `src/app/configs/data/shortcuts_mac.xml`
- `src/app/configs/data/shortcuts_azerty.xml`

Plan:

- Current code has seek helpers but no public scoped-range playback API:
- `IPlaybackController` exposes `seekElement()`, `seekBeat()`, `playElements()`, `playNotes()`, but not `playRange(startTick, endTick)`.
- `PlaybackController::playFromSelection()` seeks to a start tick and starts playback, but it does not stop at an end tick unless loop/range state already constrains playback.
- `PlaybackController::toggleLoopPlayback()` and `updateLoop()` can set loop boundaries and player loop from raw ticks, but this mutates persistent score loop state and is the wrong primitive for one-shot commands unless state is saved/restored.
- `PlaybackController::updateSoloMuteStates()` already force-mutes tracks outside a range selection by using `selectionRange()->selectedParts()` and `instrumentTrackIdSetForRangePlayback()`, but that logic depends on real range selection state.
- Recommended implementation: add a small playback-controller API rather than faking selection or persistent loop state.
- Add `IPlaybackController::playRange(Fraction startTick, Fraction endTick, std::optional<InstrumentTrackIdSet> allowedTracks = std::nullopt)` or equivalent using raw tick ints if following existing playback-controller style.
- `IPlayer` supports `setLoop(fromSecs, toSecs)` and `resetLoop()`, but does not expose a dedicated one-shot range or stop-at-time method.
- `PlaybackController::setupPlayer()` currently stops only when position reaches `totalPlayTime()`, so a scoped range method must manage its own temporary end condition instead of relying on existing total-duration stopping.
- Implementation should convert raw ticks using `notationPlayback()->playPositionTickByRawTick()`, convert to seconds with `playedTickToSecs()`, seek start, temporarily call `currentPlayer()->setLoop(fromSecs, toSecs)` or track a one-shot end second from `playbackPositionChanged()`, start playback, then restore previous persistent loop state after the scoped playback stops.
- Safer first design: add `PlaybackController` private state for a one-shot scoped playback end position and stop/reset it in the existing `playbackPositionChanged()` callback when `pos >= scopedEndSecs`, leaving score loop boundaries untouched.
- Only use `IPlayer::setLoop()` for scoped playback if manual testing confirms it can be temporary without toggling the user-visible loop action or persisting score loop boundaries.
- For `play-current-measure`, derive target measure from `currentNotationSelection()` or `currentNotationInteraction()->contextItem()`:
- If range selection exists, use `range->startTick()` and `range->rangeStartSegment()->measure()`.
- Else use `contextItem()->findMeasure()`.
- Start tick is `measure->tick()`, end tick is `measure->endTick()`.
- For `play-current-beat`, reuse `INotationPlayback::beat(tick)` and `beatToRawTick(measureIndex, beatIndex)`: start is current beat raw tick, end is next beat raw tick, clamped to measure/score end. Existing `PlaybackController::seekBeat()` and `beatToSecs()` confirm the measure/beat model is already available.
- For `play-current-staff`, avoid implementing as a first slice unless the new scoped-range API supports temporary allowed-track sets. Derive staff/part from `contextItem()->staffIdx()` or range `startStaffIndex()`, then build an `InstrumentTrackId` for that part at the start tick. Existing range playback track filtering in `instrumentTrackIdSetForRangePlayback()` is a useful reference but is currently private and selection-dependent.
- Add command-palette actions in `NotationUiActions`, not `PlaybackUiActions`, if the implementation depends on notation selection/context and accessibility announcements. Register in `NotationActionController::init()` near `current-tempo`/`set-tempo` or near playback/navigation actions.
- Suggested action names/titles:
- `play-current-measure` / `Play current measure`
- `play-current-beat` / `Play current beat`
- `play-current-staff` / `Play current staff`
- Initially add no default shortcuts. After behavior is proven, check conflicts in all `shortcuts*.xml` maps before assigning anything.
- Announce before or after starting playback via `accessibilityController()->announce()`, e.g. `Playing current measure`, `Playing current beat`, `Playing current staff`.
- Keep existing `play` and `play-from-selection` behavior unchanged.

Verification:

- Put cursor in a measure; run `Play current measure` from command palette; confirm only that measure plays.
- Put cursor on a beat; run `Play current beat`; confirm only that beat plays and stops at the next beat.
- Put cursor on a staff; run `Play current staff`; confirm only that staff/part plays if the temporary track-filter API is implemented.
- Confirm screen reader announces what playback scope started.
- Confirm existing `play` and `play-from-selection` actions are unchanged.
- Confirm existing loop playback boundaries and loop-enabled state are unchanged after scoped playback ends.
- Confirm shortcuts, if added, have no conflicts in standard, macOS, and AZERTY maps.

## Phase 5: `#5` On-Demand Details Then Verbosity Setting

### 5.1 On-Demand Detail Actions

Files:

- `src/notationscene/internal/notationactioncontroller.cpp`
- `src/notationscene/internal/notationactioncontroller.h`
- `src/notationscene/internal/notationuiactions.cpp`
- `src/notation/internal/notationaccessibility.cpp`
- `src/notation/internal/notationaccessibility.h`
- `src/engraving/accessibility/accessibleitem.cpp`
- `src/app/configs/data/shortcuts*.xml` only after conflict checks

Plan:

- Add one command-palette action with no default shortcut first:
  - `announce-selection-details`
- Use existing accessibility-formatting helpers where possible:
  - current item: existing single-element accessibility info
  - position: measure, beat, staff, voice if available
  - range: existing range accessibility info, possibly simplified
- Announce via `accessibilityController()->announce()`.
- After manual validation, decide which actions deserve default shortcuts.
- Code check: `NotationAccessibility::singleElementAccessibilityInfo()` already builds detailed item text from `element->accessibleInfo()`, `formatBarsAndBeats()`, staff index, and staff/part name.
- Code check: `NotationAccessibility::rangeAccessibilityInfo()` already builds start/end measure and beat text for range selections.
- Minimal implementation option: expose explicit formatter methods on `INotationAccessibility`/`NotationAccessibility` or add one controller helper that reuses the same logic from `currentNotation()->accessibility()->accessibilityInfo().val` for the current selection.
- If using `accessibilityInfo().val` directly, `read-current-item` and `read-selection-summary` may collapse to the same output. That is acceptable for a first slice if action naming is simplified to one action such as `announce-selection-details`.
- Recommended first action after code review: `announce-selection-details`, because existing `NotationAccessibility` already maintains exactly that string and the design review recommended this name/scope.
- Add more granular `read-current-position` only if manual testing shows users need position independently from item details.

Verification:

- Navigate to a note and run `Announce selection details`; confirm detailed but useful output.
- Select a range and run `Announce selection details`; confirm range output is understandable.
- Add and test `Read current position` only if users still need position independently from selection details.

### 5.2 Verbosity Setting

Files to design after 5.1 validation:

- likely notation or accessibility configuration interface and implementation
- preferences UI for accessibility-related settings
- `src/engraving/accessibility/accessibleitem.cpp`
- `src/notation/internal/notationaccessibility.cpp`

Plan:

- Add a user preference with at least two levels:
  - Standard: current behavior with small cleanup.
  - Concise: shorter default navigation output; details available through on-demand actions.
- Avoid changing platform-specific behavior blindly because some platforms fold descriptions into names.
- Use on-demand action wording as the validated source for detailed output.

Verification:

- Switch to concise mode and navigate normal notes; confirm core information remains available.
- Use on-demand detail commands; confirm full detail is still available.
- Switch back to standard; confirm existing rich announcements are restored.

## Phase 6: Palette and Preferences Follow-Ups From `#5`

### 6.1 Palette Accessibility Structure

Files:

- `src/palette/widgets/palettewidget.cpp`
- `src/palette/internal/palettecell.cpp`
- `src/palette/internal/palettemodel.cpp`
- `src/palette/qml/MuseScore/Palette/PalettesPanel.qml`

Plan:

- Change palette widget accessible role from static text to an interactive container role only after verifying child/cell roles still behave correctly.
- Implement real rectangles for palette cells if enough widget geometry is available.
- Add live/announced no-results feedback to palette search, but avoid per-keystroke count narration.

Verification:

- Tab into palette panel; confirm screen reader reports an interactive list/container.
- Navigate palette cells; confirm cell names and positions are available.
- Search with no matches; confirm `No results found` is announced.

### 6.2 Preferences and Secondary Dialog Context

Files:

- `src/preferences/qml/MuseScore/Preferences/PreferencesDialog.qml`
- `src/preferences/qml/MuseScore/Preferences/internal/BrailleAdvancedSection.qml`
- `src/instrumentsscene/qml/MuseScore/InstrumentsScene/internal/InstrumentSettingsPopup.qml`
- palette cell properties dialog files if later prioritized

Plan:

- Announce active preferences page when keyboard navigation changes pages.
- Ensure braille advanced combo boxes announce title plus current value, not internal navigation IDs.
- Add clear popup/dialog accessible names where missing.

Verification:

- Open Preferences; move between pages by keyboard; confirm page changes are announced.
- Focus braille advanced controls; confirm labels and current values are spoken.
- Open instrument settings; confirm popup context is spoken.

## Build And Test Strategy

For each implementation slice:

- Run `git diff --check` before committing.
- Build only when ready for user validation: `.\dev.ps1 build` or `.\dev.ps1 build -j 8`.
- Prefer manual screen-reader validation for announcement changes because many behaviors depend on NVDA/JAWS/VoiceOver/Orca behavior outside unit tests.
- For QML-only changes, run the app and validate keyboard focus and screen-reader output.
- For C++ interface changes, update mocks/tests if new pure virtual methods are added.

## Commit Strategy

Use small commits by issue/slice:

- `fix(accessibility): announce note input method changes`
- `fix(commandpalette): announce selected command results`
- `fix(accessibility): expose playback control values`
- `fix(braille): simplify six-key mode announcements` or close `#2` if not reproducible
- `fix(braille): announce semantic six-key fallback input` or close `#3` if not reproducible
- `fix(playback): decouple playback from braille panel visibility`
- `feat(playback): add play current measure action`
- `feat(accessibility): add current item detail announcements`

---

# Plan: Three Bug Fixes (Braille Tables, Cmd Palette Typing, Cmd Palette Scroll)

## Fix 1: Braille Tables CMake Post-Build Copy

**Problem:** `appDataPath()` resolves to `applicationDirPath() + "/../"` = repo root for debug builds (`globalconfiguration.cpp:68-72`). Braille tables (424 files across two source dirs) are only copied via `install()` rules which don't run during Ninja builds. Other resources (styles, templates) work because they're already at the repo root in `share/`.

**File:** `src/braille/CMakeLists.txt` (after line 35, after `target_link_libraries`)

**Change:** Add a `POST_BUILD` custom command on the `braille` target:
```cmake
if (OS_IS_WIN AND NOT CMAKE_GENERATOR MATCHES "Visual Studio")
    set(BRAILLE_TABLES_OUTPUT_DIR "${CMAKE_BINARY_DIR}/../tables")
    add_custom_command(TARGET braille POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/liblouis/tables"
            "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/tables"
            "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMENT "Copying braille tables to ${BRAILLE_TABLES_OUTPUT_DIR}"
    )
endif()
```

- `copy_directory` merges into the target (doesn't replace), so calling it twice for the two source dirs works
- Skips unchanged files on subsequent builds (fast incremental)
- `NOT Visual Studio` guard avoids duplicating the existing VS post-build cmake_install mechanism
- After this works, delete the manual `tables/` workaround at repo root (it's gitignored anyway)

**Verify:** `.\dev.ps1 build` then check `build.debug\..\tables\` has 424+ files. Run MuseScore and open braille panel — no crash.

---

## Fix 2 + 3 (REVISED): Keep Focus on Search Field

**Root cause:** The original pattern transfers focus to delegates via `navigation.requestActive()`. This creates a focus round-trip (search → delegate → search) that breaks typing. The `nav-down`/`nav-up` shortcuts also steal arrow keys from the search field because `valueInput.Keys.onShortcutOverride` (`TextInputField.qml:208`) doesn't accept Up/Down.

**New pattern:** Focus stays on the search field at all times. Arrow keys move the selection highlight (model state, not focus). Typing naturally goes to the search field. No existing component implements this — `StyledMenu` uses the same `requestActive()` pattern.

**File:** `src/appshell/qml/MuseScore/AppShell/CommandPaletteDialog.qml`

### Changes:

1. **Add `Keys.onShortcutOverride` on `searchField`** — accepts Up/Down to prevent `nav-down`/`nav-up` shortcuts from stealing them. This fires AFTER `valueInput`'s handler (which returns without accepting for Up/Down), then propagates to the `searchField` FocusScope:
```qml
Keys.onShortcutOverride: function(event) {
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
        event.accepted = true
    }
}
```

2. **Simplify `searchField.Keys.onPressed`** — just call `moveSelection`, no `focusResult`:
```qml
Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Down) {
        paletteModel.moveSelection(1)
        event.accepted = true
    } else if (event.key === Qt.Key_Up) {
        paletteModel.moveSelection(-1)
        event.accepted = true
    }
}
```

3. **Remove `focusResult` function** entirely (lines 34-48) — no longer needed.

4. **Remove `_focusSearchField` property** — no longer needed.

5. **Remove delegate `Keys.onShortcutOverride` and `Keys.onPressed`** — focus never transfers to delegates, so no key handling needed there.

6. **Keep `currentIndex: paletteModel.selectedIndex`** on `StyledListView` — syncs the list position.

7. **Add `Connections` block** for scrolling (was removed earlier, now needed since delegates aren't activated):
```qml
Connections {
    target: paletteModel
    function onSelectedIndexChanged() {
        if (paletteModel.selectedIndex >= 0) {
            resultsList.positionViewAtIndex(paletteModel.selectedIndex, ListView.Contain)
        }
    }
}
```

8. **Keep `navigation.onActiveChanged`** on delegate — still useful for mouse-click activation.

9. **Keep `navigation.panel`/`navigation.row`** on delegates — still needed for accessibility structure, but delegates won't be activated via keyboard.

### Why this works:
- `valueInput.Keys.onShortcutOverride` returns without accepting Up/Down → event propagates to `searchField.Keys.onShortcutOverride` → accepts → shortcut system doesn't intercept → `searchField.Keys.onPressed` fires → `moveSelection` updates `selectedIndex` → `Connections` scrolls the list → `isSelected` binding updates the visual highlight
- Typing goes directly to `valueInput` (which always has active focus) — no interception needed
- Enter fires `searchField.onAccepted` → `runSelection()` — already works

### Accessibility:
Screen readers won't read the selected delegate on arrow navigation (since it's not activated). Can be addressed later by updating `searchField.accessible.name` to include the selected item info, or via `announce()`.

**Verify:** Open command palette → type "note" → arrow down through results → type another letter → should filter immediately with no focus loss. Scroll should follow selection.

---

## Commit Strategy

- `fix(build): copy braille tables for debug builds` (already committed)
- `fix(commandpalette): keep focus on search field during navigation` (replaces previous typing + scroll commits)
