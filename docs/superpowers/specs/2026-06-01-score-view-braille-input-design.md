# Score View Six-Key Braille Input Design

## Purpose

Users should be able to enter Braille music notation from the score view without focusing the Braille panel. A toggleable six-key Braille input mode will reserve `S D F J K L` for Braille chording while keeping arrow-key navigation and non-conflicting shortcuts available.

This mode is independent from the Braille panel visibility. The panel remains useful as visual and accessibility feedback, but it is not required for input.

## Recommendation

Use the score view as the input capture point and keep the existing Braille parser and score mutation logic in `NotationBraille`.

This is the best fit because the current problem is where keyboard events are captured, not how Braille music input is interpreted. `NotationBraille` already owns `BrailleInputState`, pending prefixes, note/rest/interval recognition, score edits, playback feedback, and accessibility announcements. Moving that logic would increase risk and duplicate domain behavior. `NotationViewInputController` already owns score-view keyboard routing, so adding a narrow six-key collector there keeps responsibilities clear:

- `NotationViewInputController`: physical key capture and shortcut precedence in the score view.
- `NotationBraille`: Braille sequence interpretation, pending state, notation edits, and announcements.

## User-Facing Behavior

Add a toggle action, likely `toggle-braille-input`, separate from `toggle-braille-panel`.

- `toggle-braille-panel` controls whether the Braille display panel is visible.
- `toggle-braille-input` controls whether the score view interprets `S D F J K L` as six-key Braille chord keys.

When six-key Braille input is enabled:

- The score view remains the active editing surface.
- Plain `S D F J K L` are reserved for Braille chord entry.
- Multi-key chords using those six keys are reserved for Braille chord entry.
- Standard pitch-letter note entry through those keys is disabled.
- Arrow keys continue to navigate normally.
- Non-conflicting shortcuts continue normally.
- Modified shortcuts such as `Ctrl+S` should continue normally.
- The implementation may internally enter MuseScore note input mode if needed to insert notes, but users should not need to toggle standard note input separately.
- Accessibility announces that six-key Braille input is on.

When six-key Braille input is disabled:

- Pending uncommitted Braille input is cleared.
- Accessibility announces that six-key Braille input is off.
- If pending input was discarded, the announcement mentions that.
- Standard note-input state is restored according to the prior state:
  - If standard note input was off before enabling Braille input, turn it off when disabling Braille input.
  - If standard note input was already on before enabling Braille input, leave it on when disabling Braille input.

This restoration rule prevents the Braille toggle from permanently changing the user's editing mode.

## Components

### Toggle Action

Register a checkable action such as `toggle-braille-input` through the normal MuseScore action system so it can appear in menus, command palette search, and shortcut preferences.

The action should toggle a Braille input state, not the Braille panel. Its checked state should reflect whether score-view six-key Braille input is active.

### Braille Input Interface

Extend `INotationBraille` with explicit score-view input methods if the existing mode API is too panel-oriented. Suggested names:

```cpp
bool brailleInputEnabled() const;
void setBrailleInputEnabled(bool enabled);
void handleBrailleKeySequence(const QString& sequence);
```

Clear names are preferred because `BrailleMode::Navigation` and `BrailleMode::BrailleInput` historically describe the Braille panel behavior. The new behavior is a score-view entry mode. The implementation may still map this state onto the existing `BrailleMode` internally if that keeps the change small.

### Score-View Key Collector

Add a small six-key chord collector to `NotationViewInputController`.

On `ShortcutOverride`:

- If Braille input is disabled, do nothing.
- If the event is a plain unmodified `S D F J K L` key, accept it.
- If the event is an arrow key, function key, `Esc`, or modified shortcut, leave it in the existing routing path.

On `KeyPress`:

- If Braille input is disabled, do nothing.
- If the key is a plain unmodified `S D F J K L`, add it to the pressed-key set and accept the event.
- Ignore auto-repeat for captured keys.

On `KeyRelease`:

- If Braille input is disabled, do nothing.
- If the key is one of the captured six keys, remove it from the pressed-key set.
- When the pressed-key set becomes empty, convert the collected chord to the existing sequence format, for example `F+J+L`, and send it to `NotationBraille`.
- Clear the collector after emission.

The collector must not interpret musical meaning. It only translates physical key combinations into the string sequence already understood by the Braille input backend.

### Braille Parser And Score Mutation

Keep Braille music interpretation in `NotationBraille`.

Existing behavior should remain centralized there:

- pending accidentals, octave marks, dots, tuplets, ties, and slurs
- note, rest, and interval recognition
- note/rest insertion through notation APIs
- pending-input cleanup
- accessibility announcements
- playback feedback

If needed, rename or wrap `setKeys(const QString&)` with a clearer method such as `handleBrailleKeySequence(const QString&)`, but do not duplicate parser logic in the score-view controller.

## Shortcut Precedence

While six-key Braille input is active:

- Plain `S D F J K L` belong to Braille input.
- Direct chords made from `S D F J K L` belong to Braille input.
- Modified shortcuts such as `Ctrl+S`, `Alt+F`, and app-level command shortcuts should continue through the existing shortcut path.
- Arrow keys continue through the existing score-navigation path.
- `Esc` continues through the existing cancel/exit path unless implementation discovery shows pending Braille input needs a first-chance clear action.
- `Backspace` and `Delete` should retain the existing Braille semantics when routed to `NotationBraille`:
  - `Backspace` removes the last pending Braille cell when pending input exists.
  - `Delete` clears pending Braille input when it exists, otherwise deletes the selected notation.

The design reserves the smallest possible key surface: unmodified six-key Braille chords. This preserves user trust in global shortcuts while still disabling standard note entry through the keys that Braille chording needs.

## Error Handling And Edge Cases

- If there is no current notation, the toggle should be disabled or should no-op with no crash.
- If Braille input is enabled and the score cannot accept a parsed note, the existing `NotationBraille` failure behavior should apply.
- If the user switches scores, pending captured physical keys should be cleared.
- If the user disables Braille input while keys are physically held, the collector should clear without emitting a chord.
- If the user leaves standard note input mode through another command while Braille input remains enabled, Braille input remains enabled. The next Braille sequence that commits notation re-enters the required internal note-input state before inserting the note or rest.
- If the Braille panel is hidden, all input and announcements should still work.

## Testing

Use deterministic tests for deterministic behavior.

### Chord Collector Unit Tests

Add focused tests for the score-view chord collector helper:

- Press `F`, press `J`, press `L`, release all: emits `F+J+L`.
- Press and release single `S`: emits `S`.
- Auto-repeat does not duplicate keys.
- Arrow keys are not captured.
- `Ctrl+S` is not captured.
- Collector resets after emission.
- Collector clears without emission when disabled.

### Controller Tests

Extend `NotationViewInputController` tests where feasible:

- `ShortcutOverride` accepts plain Braille keys only when Braille input is enabled.
- Plain Braille keys are not forwarded to standard note entry while Braille input is enabled.
- Arrow keys remain in the existing navigation path.
- Modified shortcuts remain in the existing shortcut path.
- Disabling the mode clears captured physical-key state.

### Braille Behavior Regression Tests

Reuse or extend existing Braille tests:

- Pending prefix input survives until a completing chord.
- Backspace removes pending Braille cells.
- Disabling Braille input clears pending input.
- Note/rest insertion continues to use the existing parser behavior.

### Manual Verification

Manually verify:

1. Select a note or rest.
2. Toggle six-key Braille input on.
3. Enter a simple Braille note chord.
4. Navigate with arrow keys.
5. Use `Ctrl+S`.
6. Hide the Braille panel and confirm input still works.
7. Toggle six-key Braille input off.
8. Confirm standard note-entry behavior returns to the prior state.

## Out Of Scope

- Rewriting the Braille parser.
- Redesigning the Braille panel UI.
- Changing the Braille panel's current display semantics.
- Adding a new full Braille input service unless implementation discovery shows the score-view controller would otherwise need to duplicate parser behavior.
- Changing unrelated shortcuts.
