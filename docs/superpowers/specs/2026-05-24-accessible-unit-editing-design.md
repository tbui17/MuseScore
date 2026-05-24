# Accessible Unit Selection and Editing Design

Date: 2026-05-24

## Summary

This spec defines the second increment of an accessibility-first score editing experience for MuseScore Studio. It covers keyboard selection, erase, time deletion, copy, cut, and beat/time-slice editing for blind users working from screen-reader feedback.

The design intentionally minimizes deviation from existing MuseScore behavior. Existing engraving commands remain authoritative for low-level edit semantics. The new work adds a thin unit-aware action layer that resolves the unit announced by navigation, materializes it as a normal MuseScore selection or range, delegates to existing edit primitives, and provides operation-specific accessibility feedback.

This spec builds on `2026-05-24-accessible-score-navigation-feedback-design.md`.

## Goals

- Let a blind user edit the same unit that navigation announces: note, chord/rhythmic event, beat/time-slice, measure, or explicit range.
- Preserve MuseScore's existing distinction between erasing content and deleting time.
- Make `Delete` and `Backspace` directional: current unit vs previous unit.
- Make structural deletion predictable: `Ctrl+Delete` deletes current unit time; `Ctrl+Backspace` deletes previous unit time.
- Change cut into a relocation command: copy, then delete time/structure.
- Add current-staff beat/time-slice editing as a new unit.
- Reuse existing selection, clipboard, undo, error, and engraving edit systems.
- Add operation-specific success feedback through the accessibility feedback layer.

## Non-goals

- Do not replace `Score::cmdDeleteSelection()`, `Score::cmdTimeDelete()`, `Score::cmdPaste()`, or existing copy serialization.
- Do not change `Ctrl+V` paste semantics; paste remains existing MuseScore paste behavior.
- Do not implement numeric go-to dialogs or command-palette prompt arguments.
- Do not make non-time-bearing elements first-class units in this spec.
- Do not show routine success popups.

## Existing context

Relevant systems:

- Global edit shortcuts route through `src/appshell/internal/applicationactioncontroller.cpp`.
- Notation actions are registered in `src/notationscene/internal/notationactioncontroller.cpp`.
- UI action metadata and enabled state live in `src/notationscene/internal/notationuiactions.cpp`.
- Selection and edit primitives live in `src/notation/internal/notationinteraction.cpp`.
- Core engraving edit commands live in `src/engraving/editing/edit.cpp` and related engraving files.
- Accessibility selection text is built in `src/notation/internal/notationaccessibility.cpp`.
- Existing shortcut bindings live in `src/app/configs/data/shortcuts.xml`, `shortcuts_azerty.xml`, and `shortcuts_mac.xml`.

Existing behavior already aligned with this design:

- Plain `Delete` / `Backspace` erase content while preserving time for notes, chords, and ranges.
- `Ctrl+Delete` / `Ctrl+Backspace` already map to `time-delete`, which removes time/structure and closes the gap.
- `cmdDeleteSelection()` already selects a nearby rest or top note after many erase operations.
- `copySelection()`, `pasteSelection()`, `deleteSelection()`, and `removeSelectedRange()` already use standard undo/error mechanisms.
- `MScore::setError(...)` plus `checkAndShowError()` already surfaces operation failures.

Pain points addressed by this spec:

- `Delete` and `Backspace` are currently aliases; this spec separates current-unit and previous-unit behavior.
- `Ctrl+Delete` and `Ctrl+Backspace` are currently aliases; this spec separates current-time and previous-time behavior when no explicit selection exists.
- Existing `Ctrl+X` is copy plus erase; this spec changes it to copy plus delete time/structure for relocation.
- Existing time-delete often leaves no useful selection; this spec requires focus repair.
- Existing accessibility describes selection state, not the operation that just occurred; this spec requires operation-specific success feedback.
- Beat/time-slice editing is not a first-class unit today; this spec adds it for the current staff.

## User model

The user works from the unit announced by navigation. There is no separate editing mode.

The target unit is either:

- an explicit range/list selection, if the user has created one; or
- the current navigation-announced unit, such as “Chord…”, “Note…”, “Beat…”, or “Measure…”.

Explicit ranges win over navigation context. Single navigation focus is treated as a cursor-like target.

## Interaction semantics

### Target resolution

- Explicit range or list selection wins. Editing commands act on that selection.
- Without an explicit selection, editing commands act on the current announced unit.
- `Backspace` variants resolve the previous unit at the same granularity.
- Structural delete from a note focus promotes to the enclosing time-bearing chord/event.
- Shift+navigation creates or extends an explicit selection/range at the corresponding unit granularity.

Supported units:

- Note inside a chord.
- Chord/rhythmic event.
- Current-staff beat/time-slice.
- Measure.
- Explicit range/list selection.

### Command meanings

- `Delete`: erase the current announced unit, preserving time. If selection exists, erase the selection.
- `Backspace`: erase the previous announced unit, preserving time. If selection exists, erase the selection.
- `Ctrl+Delete`: delete time/structure for the current announced unit. If selection exists, delete selected time/structure.
- `Ctrl+Backspace`: delete time/structure for the previous announced unit. If selection exists, delete selected time/structure.
- `Ctrl+C`: copy the current announced unit or explicit selection.
- `Ctrl+X`: copy the current announced unit or explicit selection, then delete its time/structure.
- `Ctrl+V`: preserve existing MuseScore paste behavior.

### Erase vs delete time

Erase means remove content while preserving musical time:

- Note focus: remove that pitch only.
- Chord/event focus: replace the event with an equivalent-duration rest.
- Beat/time-slice focus: replace current-staff beat contents with rests.
- Measure focus: replace contents with a full-measure rest.
- Explicit range: replace selected content with rests using existing range-delete behavior.

Delete time/structure means remove the time-bearing container and close the gap:

- Note focus inside a chord promotes to chord/event time deletion.
- Chord/event focus deletes that event duration.
- Beat/time-slice focus deletes that beat/time-slice duration on the current staff where supported.
- Measure focus deletes the measure.
- Explicit range deletes the selected section/time.

## Architecture

### Placement

Add unit-aware wrapper behavior near `NotationActionController`, because global edit shortcuts already converge there after `ApplicationActionController` dispatches notation-specific actions.

The wrapper layer should not duplicate engraving logic. It resolves units and delegates.

### Unit target resolver

Add a small helper used by notation action wrappers. It resolves:

- whether the current selection is an explicit range/list;
- the current announced navigation unit;
- the previous unit at the same granularity;
- the time-bearing container for structural delete;
- how to materialize the target as a MuseScore selection/range.

The current announced unit comes from the navigation feedback model introduced by spec #1. If needed, spec #2 may store a lightweight “last announced unit granularity” state so edit actions can distinguish note, chord/event, beat/time-slice, and measure focus.

### Wrapper actions

Add or update notation-context action handlers for:

- erase current unit;
- erase previous unit;
- delete current unit time;
- delete previous unit time;
- copy current unit or selection;
- cut current unit or selection;
- existing paste.

Wrappers should:

1. Resolve the target unit or explicit selection.
2. Materialize the target as a normal MuseScore selection/range.
3. Delegate to existing primitives:
   - erase: `NotationInteraction::deleteSelection()` / `Score::cmdDeleteSelection()`;
   - time-delete: `NotationInteraction::removeSelectedRange()` / `Score::cmdTimeDelete()`;
   - copy: `NotationInteraction::copySelection()`;
   - cut: copy, then time-delete;
   - paste: existing `NotationActionController::pasteSelection()` behavior.
4. Accept existing post-action selection when useful.
5. Repair focus where existing primitives leave no useful selection, especially time-delete.
6. Trigger operation-specific accessibility feedback.

### Action and shortcut integration

Current `Delete`/`Backspace` and `Ctrl+Delete`/`Ctrl+Backspace` aliasing must be split into separate action codes or otherwise be distinguishable by the action layer.

Recommended action labels for command palette and shortcuts:

- “Erase current unit”
- “Erase previous unit”
- “Delete current unit time”
- “Delete previous unit time”
- “Copy current unit or selection”
- “Cut current unit or selection”

`Ctrl+V` remains existing paste.

Shortcut changes must be applied consistently in default, AZERTY, and macOS shortcut files.

## Data flow and focus behavior

### Erase current or selection

1. Resolve current unit or explicit selection.
2. Materialize target selection/range.
3. Call existing delete-selection behavior.
4. Preserve the resulting selection from `cmdDeleteSelection()` when it selects a replacement rest, surviving note, or nearby chord/rest.
5. Announce operation-specific success and resulting focus.

### Erase previous

1. Resolve previous unit at current granularity.
2. Materialize target selection/range.
3. Call existing delete-selection behavior.
4. Focus the affected result at the previous unit location.
5. Announce operation-specific success and resulting focus.

### Delete time current or selection

1. Resolve current unit or explicit selection.
2. Promote note focus to enclosing chord/event.
3. Materialize target selection/range.
4. Call existing time-delete behavior.
5. Focus the unit now occupying the deleted position after later music shifts earlier.
6. If no later unit exists, fall back to nearest previous valid unit.
7. Announce operation-specific success and resulting focus.

### Delete time previous

1. Resolve previous unit at current granularity.
2. Promote note focus to previous chord/event as needed.
3. Materialize target selection/range.
4. Call existing time-delete behavior.
5. Focus the unit now occupying the deleted previous position.
6. If none exists, fall back to nearest previous valid unit.
7. Announce operation-specific success and resulting focus.

### Copy

1. If explicit selection exists, use it.
2. Otherwise materialize the current announced unit.
3. Call existing copy behavior.
4. Preserve focus.
5. Announce copied unit or range.

### Cut

1. Resolve current unit or explicit selection.
2. Materialize it.
3. Copy with existing copy behavior.
4. Delete time/structure using the same semantics as `Ctrl+Delete`.
5. Focus the unit now occupying the cut position.
6. Announce copied and removed result.

### Paste

Use existing MuseScore paste behavior. This spec does not add “paste after unit” semantics.

## Beat/time-slice editing

Beat/time-slice editing is new in this spec.

Scope:

- Current staff only.
- Uses the beat or time-slice announced by navigation.
- Erase replaces current-staff contents in that beat/time-slice with rests.
- Delete time removes that duration from the current staff where supported.
- Unsupported tuplet, irregular, or boundary cases should fail through the existing error path.

The implementation must define a safe materialization strategy before editing:

- start tick;
- end tick/duration;
- current staff and relevant voice handling;
- behavior when voices contain content that does not align to the beat boundary;
- behavior inside tuplets and measure repeats.

When safe materialization is not possible, the wrapper must not perform a partial or surprising edit.

## Error handling

Use existing MuseScore error mechanisms first.

- Existing engraving errors remain authoritative.
- Existing failures should flow through `MScore::setError(...)` and `NotationInteraction::checkAndShowError()`.
- Existing copy, paste, delete, and time-delete validation should not be duplicated in wrapper code.
- New wrapper-level errors should be added only for target-resolution failures that existing commands cannot express, such as “no previous unit” or “cannot materialize beat here.”
- Routine success must not use `interactive()->info()` or warning dialogs.

Potential new errors:

- No editable unit selected.
- No previous unit.
- Cannot edit this beat.
- Cannot delete time for this beat.

These should follow the existing `MsError` / `MScoreErrorsController` style if added.

## Accessibility feedback

Existing `NotationAccessibility` describes the current selection. This spec requires operation-specific success feedback in addition to the resulting selection description.

The feedback layer from spec #1 should be extended or reused so successful operations can announce:

- operation performed;
- unit affected;
- erase vs delete-time distinction;
- resulting focus.

Examples:

- “Chord erased; quarter rest inserted.”
- “Previous chord erased; focus on quarter rest, measure 5 beat 2.”
- “Current chord time deleted; focus on next chord now at beat 2.”
- “Measure erased; full-measure rest.”
- “Range cut; following music shifted earlier.”
- “Copied beat.”

Failure feedback should use the existing error path and avoid duplicate announcements.

## Testing and verification

Existing engraving tests already cover low-level delete, time-delete, range delete, and copy/paste behavior. New tests should focus on the new wrapper/action semantics and accessibility behavior.

### Reuse existing coverage

Rely on existing tests for:

- `cmdDeleteSelection()` erase/rest replacement:
  - `selectionrange_tests.cpp`
  - `selectionfilter_tests.cpp`
  - `links_tests.cpp`
  - `measure_tests.cpp`
  - `beam_tests.cpp`
  - `partialtie_tests.cpp`
- `cmdTimeDelete()` measure/time deletion:
  - `measure_tests.cpp`
  - `spanners_tests.cpp`
- `cmdPaste()` and copy/paste correctness:
  - `copypaste_tests.cpp`
  - `partialtie_tests.cpp`
  - `copypastesymbollist_tests.cpp`
  - `selectionfilter_tests.cpp`

### Add focused tests

Add notation/action-level tests for:

- `Delete` vs `Backspace` routing:
  - Delete targets current announced unit.
  - Backspace targets previous announced unit.
- `Ctrl+Delete` vs `Ctrl+Backspace` routing:
  - `Ctrl+Delete` deletes current unit time.
  - `Ctrl+Backspace` deletes previous unit time.
  - Explicit range makes both act on selected range.
- Changed `Ctrl+X` behavior:
  - copies target;
  - deletes time/structure instead of erase-to-rest.
- Unit resolution:
  - current screen-reader-announced unit is used as target;
  - structural delete from note focus promotes to enclosing chord/event;
  - range/list selection overrides navigation unit.
- Beat/time-slice editing:
  - current-staff beat materialization;
  - erase beat preserves time;
  - delete beat removes duration where supported;
  - unsupported tuplet/boundary cases use existing error path.
- Time-delete focus repair:
  - focus moves to the unit now occupying the deleted position.
- Measure erase:
  - measure-unit `Delete` invokes full-measure-rest behavior.
- Operation-specific accessibility feedback:
  - announces operation, unit, erase vs delete-time, and resulting focus.

### Paste verification

Since `Ctrl+V` preserves existing paste behavior, only verify that new wrappers do not alter existing paste routing or semantics.

## Open implementation risks

- Distinguishing explicit range/list selection from single navigation focus must be reliable.
- The last announced unit must be available to edit wrappers.
- Beat/time-slice materialization is the highest-risk new editing primitive.
- Time-delete focus repair must account for deleting at the end of a staff, measure, or score.
- Shortcut splitting changes existing aliases and must be handled carefully for user migration.
- Changing `Ctrl+X` from erase semantics to delete-time semantics is intentional but significant.

## Acceptance criteria

- `Delete`, `Backspace`, `Ctrl+Delete`, and `Ctrl+Backspace` perform the unit and direction semantics defined above.
- Explicit ranges override current/previous navigation-unit targeting.
- `Ctrl+X` copies and structurally removes the target.
- `Ctrl+V` remains existing MuseScore paste behavior.
- Beat/time-slice erase and time-delete work on the current staff where safe.
- Time-delete and cut leave focus on the unit now occupying the deleted position.
- Success feedback distinguishes erase from delete-time and names the affected unit.
- Existing engraving delete/copy/paste tests continue to pass.
