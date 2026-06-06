# Braille Six-Key Score Input Design

Date: 2026-06-06

## Goal

Allow users to enter braille music chords directly from the score view without opening or focusing the braille input panel. A new checkable View menu action enables six-key input on bare `S`, `D`, `F`, `J`, `K`, and `L` keys, matching the chord behavior used by the existing braille input mode while preserving ordinary modified shortcuts and navigation.

## Current Context

The existing six-key path is implemented in `src/braille/qml/MuseScore/Braille/BrailleView.qml`. That view captures mapped braille dot keys, buffers simultaneous key presses, converts the pressed keys into a chord string, and forwards it to `NotationBraille::setKeys()` in `src/braille/internal/notationbraille.cpp`.

This behavior currently depends on the braille panel having focus. When the score view has focus, bare dot keys already have ordinary shortcut meanings such as note entry, slur entry, enharmonic actions, or tablature fret shortcuts. The new feature intentionally overrides those bare dot-key shortcuts only while the six-key toggle is enabled.

## User-Approved Approach

Use score-canvas interception and reuse `NotationBraille::setKeys()` as the source of truth.

This is the smallest design because it keeps braille parsing, duration handling, note insertion, playback, and announcements inside the existing braille implementation. The score view becomes responsible only for deciding when to capture bare dot keys and for forwarding completed chord strings.

Rejected alternatives:

- Move six-key capture into a shared helper used by both score view and braille panel. This is cleaner long-term but requires more refactoring and increases risk to existing braille panel behavior.
- Create shortcut actions for each braille chord. Normal shortcut dispatch is a poor fit for simultaneous key chords and would be more fragile.

## Architecture

The toggle is a checkable View menu action, independent of whether the braille panel is visible. When enabled, the score view intercepts only bare `S`, `D`, `F`, `J`, `K`, and `L` key events. Modifier shortcuts such as `Ctrl+C`, `Ctrl+V`, `Ctrl+K`, `Shift+S`, and arrow navigation continue through the existing shortcut system.

The score-view key handling buffers simultaneous dot-key presses. When the chord is complete, it emits the same string format that the braille panel already sends to `NotationBraille::setKeys()`.

## Components

### Braille Configuration

Add a persisted boolean named `sixKeyInputEnabled` to `IBrailleConfiguration` and `BrailleConfiguration`, with a change notification. The setting stores whether the score view captures bare six-key braille chords.

### App Action And Menu

Add a checkable View menu action named `toggle-braille-six-key-input`. Its checked state reflects the persisted braille configuration value, and invoking it updates that value.

### Score View Input Controller

Extend `NotationViewInputController` so that, when the setting is enabled and the score canvas has focus, it intercepts only bare `S`, `D`, `F`, `J`, `K`, and `L` in the key event path.

`shortcutOverrideEvent()` should accept matching bare dot-key events before normal shortcut dispatch. `keyPressEvent()` and `keyReleaseEvent()` should maintain the active chord buffer, ignore repeat events for keys already held, and dispatch the chord when the last held dot key is released.

### Braille Note Entry

Reuse `INotationBraille::setKeys()` and `NotationBraille::setKeys()` for the actual braille action. The score view should not duplicate braille parsing or note-creation logic.

## Data Flow

1. The user enables the checkable View action.
2. The user focuses the score view and presses a braille chord using bare `S`, `D`, `F`, `J`, `K`, and `L` keys.
3. The score view accepts those bare dot-key events before normal shortcut dispatch.
4. The score view buffers the keys until the chord is complete.
5. The completed chord string is sent to `NotationBraille::setKeys()`.
6. Existing braille logic inserts the note, rest, interval, or pending braille cell.

## Interaction Rules

- With the toggle disabled, all existing score-view shortcuts keep their current behavior.
- With the toggle enabled, bare `S`, `D`, `F`, `J`, `K`, and `L` are reserved for six-key braille chord input while the score canvas has focus.
- If note input is already active, the chord immediately feeds existing braille note-entry logic.
- If note input is not active, the first valid bare dot-key chord starts note input and then processes the chord.
- Modifier combinations are not intercepted. `Ctrl+D`, `Ctrl+K`, `Shift+S`, `Alt+J`, and similar shortcuts keep their existing behavior.
- Arrow navigation, copy, paste, undo, redo, delete, backspace, and non-dot-key shortcuts keep their existing behavior.
- Text editing and element-editing contexts bypass six-key capture so lyrics, text frames, and other text-entry fields are not broken.

## Error Handling And Edge Cases

- If the toggle is enabled but no notation is active, dot keys fall through normally.
- If note input cannot start, the controller clears the buffered chord and avoids consuming future unrelated shortcut behavior.
- If `NotationBraille::setKeys()` cannot resolve a chord, error handling remains inside the existing braille logic.
- Auto-repeat key presses are ignored while the key is already held, preventing repeated characters from corrupting a chord.
- Focus loss, notation changes, or mode changes clear any partially buffered chord.
- Existing braille pending-input behavior remains inside `NotationBraille`; the score view only captures and forwards chord strings.

## Testing

Targeted verification should cover these cases:

- Toggle off: bare `S`, `D`, `F`, `J`, `K`, and `L` preserve existing score-view shortcut behavior.
- Toggle on: bare dot keys are captured as braille chords from score focus.
- Toggle on: `Ctrl+C`, `Ctrl+V`, `Ctrl+K`, arrows, delete, backspace, undo, redo, and other modified or non-dot-key shortcuts still work.
- Toggle on: text-editing contexts do not capture dot keys.
- Toggle on: a braille chord can insert score content without opening or focusing the braille panel.
- Existing braille panel input still works through its current focused-panel path.

The implementation should use the narrowest practical build target for verification. If only app-shell QML and input-controller code is touched, use the relevant targeted build. If broader dependencies are touched, build the full app target.

## Scope Boundaries

This design does not introduce a new braille parser, a new shortcut model, or a replacement for the existing braille panel. It only adds a score-view six-key capture toggle and routes completed chords into the existing braille note-entry path.
