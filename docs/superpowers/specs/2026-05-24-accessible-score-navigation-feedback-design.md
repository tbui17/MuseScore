# Accessible Score Navigation and Feedback Design

Date: 2026-05-24

## Summary

This spec defines the first increment of an accessibility-first score navigation experience for MuseScore Studio. It covers keyboard score navigation feedback only: moving through the score, hearing the selected musical event, and receiving clear screen-reader announcements for the focused musical context.

This spec does not cover selection-unit editing, copy, paste, deletion, or numeric go-to dialogs. Those are follow-up specs.

## Goals

- Preserve existing MuseScore score-navigation semantics where possible.
- Make navigation usable for a blind musician who needs simultaneous musical audio feedback and screen-reader context.
- Keep horizontal navigation aligned with time and vertical navigation aligned with simultaneity, pitch, staff, and voice.
- Add a focused feedback layer instead of creating a separate screen-reader-only navigation mode.
- Define stable context and feedback contracts that later editing and go-to specs can reuse.

## Non-goals

- Do not implement selection-unit copy, paste, deletion, or replacement behavior.
- Do not implement `go to note`, `go to beat`, `go to bar`, or `go to track` dialogs.
- Do not replace the existing action, shortcut, playback, or accessibility systems.
- Do not promise harmonic chord-name analysis unless an existing chord symbol or reliable source provides it.

## Existing context

Relevant existing systems:

- Navigation actions are defined in `src/notationscene/internal/notationuiactions.cpp`.
- Navigation action handling runs through `src/notationscene/internal/notationactioncontroller.cpp`.
- Score movement primitives live in `src/notation/internal/notationinteraction.cpp` and `src/engraving/editing/cmd.cpp`.
- Accessibility selection info is built in `src/notation/internal/notationaccessibility.cpp`.
- Element screen-reader details come from engraving item methods such as `Note::screenReaderInfo()` and `EngravingItem::formatBarsAndBeats()`.
- Preview playback APIs include `playElements()`, `playNotes()`, and `seekElement()` from the playback controller.
- Command palette dispatches registered actions, but command-palette shortcut display and numeric go-to prompts are separate follow-up work.

Existing conventions to preserve:

- `Left` / `Right`: previous or next rhythmic event, currently expressed as note/chord/rest navigation.
- `Alt+Up` / `Alt+Down`: note above or below, including notes inside a chord and nearby vertical material.
- `Ctrl+Left` / `Ctrl+Right`: previous or next measure.
- `next-track` / `prev-track`: existing staff-or-voice track movement.
- `Shift+L`: get current location.

## User experience

The navigation model is:

- Horizontal movement means time.
- Vertical movement means simultaneity, pitch, staff, or voice.
- Every successful score-navigation move provides coordinated feedback:
  - an audio preview of the relevant musical object, when audio preview is enabled;
  - one clear screen-reader announcement of the resulting musical context.

Examples:

- Single note horizontal landing: “C4, quarter; measure 5 beat 1; Piano staff 1.”
- Chord horizontal landing: “Chord, 3 notes: C4 E4 G4, quarter; focused note C4; measure 5 beat 1; Piano staff 1.”
- Rest horizontal landing: “Quarter rest; measure 5 beat 2; Piano staff 1.”
- Vertical chord drill-down: “E4, note 2 of 3 in chord.”
- Track movement: “Piano lower staff, voice 1; measure 5 beat 1.”

## Architecture

Add a small accessibility-navigation feedback layer on top of existing navigation actions.

### Navigation feedback coordinator

The coordinator owns feedback timing for handled navigation actions.

Responsibilities:

- receive notification that a navigation action has completed;
- obtain the current selection or focused engraving item;
- ask the context resolver for musical context;
- ask the audio preview adapter to preview the correct target;
- ask the announcement builder for a canonical spoken payload;
- avoid duplicate, stale, or overly verbose feedback.

The coordinator should not move the score itself. Existing navigation paths remain responsible for movement.

### Musical context resolver

The resolver converts the selected or focused engraving item into a stable `NavigationFeedbackContext`.

The context should include:

- `navigationAction`: horizontal, vertical, measure, track/staff, or location refresh;
- `focusedElement`: selected engraving item;
- `rhythmicEvent`: note, chord, or rest at the current segment and track;
- `focusedNote`: note within a chord, if applicable;
- `chordNotes`: ordered notes in the chord, if applicable;
- `duration`;
- `measureNumber`;
- `displayedMeasureNumber`, when different;
- `beat`;
- `tick` or segment reference;
- `staffIndex`;
- `partOrInstrumentName`;
- `voice`;
- `track`;
- flags for grace notes, ties, cross-staff notation, percussion, tablature, invisible state, and range-selected state.

The resolver should reuse existing data sources wherever possible, including `EngravingItem::formatBarsAndBeats()`, note screen-reader info, staff/part names, current selection state, and current chord/rest fallback behavior.

### Audio preview adapter

The adapter provides safe, short audio feedback for navigation.

Responsibilities:

- use preview APIs only;
- never start full playback transport;
- preview the full chord when horizontal navigation lands on a chord;
- preview the focused note when vertical navigation drills into a chord;
- keep previews short and bounded;
- cancel or coalesce stale previews during rapid key repeat;
- respect existing audio-preview, mixer, mute, solo, and volume behavior as exposed by current preview APIs.

### Announcement builder

The builder produces one canonical announcement string for each navigation action.

Responsibilities:

- summarize the changed musical object first;
- include enough location to orient the user;
- include staff, part, voice, or track when needed for disambiguation;
- avoid promising chord names unless a reliable existing source provides them;
- support a brief default form and a detailed form for location-refresh behavior;
- keep output stable enough to test.

### Action integration

Existing actions remain the entry points:

- `notation-move-left`
- `notation-move-right`
- `notation-move-left-quickly`
- `notation-move-right-quickly`
- `up-chord`
- `down-chord`
- `next-track`
- `prev-track`
- `get-location`

After a handled navigation action succeeds, the action controller or interaction layer should invoke the feedback coordinator with the action category.

## Behavior rules

### Horizontal navigation

- Moves to the previous or next rhythmic event.
- A single note previews that note and announces note plus location.
- A chord previews the full chord and announces chord summary plus focused note plus location.
- A rest produces no pitched preview and announces rest duration plus location.
- A one-note chord should be announced as a note unless the score model requires chord wording for clarity.

### Vertical navigation

- `Alt+Up` and `Alt+Down` navigate notes inside a chord or nearby vertical material using existing MuseScore behavior.
- Preview the focused note, not the whole chord.
- Announce the focused note and vertical position, such as “note 2 of 3 in chord.”
- At chord boundaries, announce boundary transitions clearly, for example “No higher note in chord” or “Moved to Viola staff, voice 1.”

### Measure navigation

- `Ctrl+Left` and `Ctrl+Right` retain existing previous/next measure behavior.
- Preview the focused event at the new location.
- Announce measure context and event summary.

### Track and staff navigation

- Use existing `next-track` and `prev-track` semantics.
- Announce user-facing context, such as instrument, staff, and voice.
- Do not expose only internal track numbers to the user.
- If no default shortcut exists for these actions, document discoverability as an implementation consideration.

### Beat navigation

Beat navigation is a known gap. This spec may define desired feedback behavior for future beat navigation, but implementation should not fake score navigation using playback-only seek state.

If safe score-selection primitives are available, explicit previous-beat and next-beat actions may be added. Otherwise, beat navigation should remain a follow-up spec item.

## Speech policy

- Emit one canonical announcement per handled navigation action.
- Avoid duplicate speech from simultaneous focus-change names and explicit announcements.
- Always announce the musical object that changed.
- Do not repeat unchanged measure, staff, or voice context unless needed for disambiguation.
- Use brief announcements by default.
- Use detailed announcements for location-refresh behavior, such as `get-location`, or for a future explicit “announce detailed context” command.

## Audio policy

- Use preview behavior only; do not start or alter full playback transport.
- Respect user audio-preview settings.
- Follow existing instrument, mixer, mute, solo, and volume behavior as current preview APIs support it.
- Cancel or coalesce previews during rapid key repeat.
- Keep previews short enough that speech remains understandable.
- If audio preview is disabled or unavailable, speech feedback still occurs.
- If screen-reader accessibility is disabled, audio preview still follows normal preview settings.

## Edge cases

- Empty selection: restore current chord/rest or first element, consistent with current get-location fallback behavior.
- Multi-voice music: include voice when ambiguity exists or when moving by track/voice.
- Multi-staff instruments: include staff identity, such as upper or lower staff where possible.
- Cross-staff notation: include cross-staff state using existing note accessibility data.
- Grace notes: include grace-note order in horizontal navigation; use vertical navigation for chord tones inside each grace chord.
- Ties: include tie context when existing note accessibility data provides it.
- Percussion: use existing drum or instrument names rather than pitch names when appropriate.
- Tablature: include string and fret context using existing TAB accessibility data.
- Invisible or generated elements: preserve existing accessible state where it affects the spoken object.

## Testing

### Unit tests

Add focused tests for announcement-building and context resolution where feasible:

- single note;
- chord with multiple notes;
- one-note chord;
- rest;
- percussion note;
- tablature note;
- multi-voice note;
- cross-staff note;
- grace-note chord;
- tied note.

### Interaction tests

Where feasible, test that handled navigation actions request the expected feedback target:

- horizontal chord navigation requests full-chord preview and chord announcement;
- vertical chord drill-down requests focused-note preview and focused-note announcement;
- measure navigation announces the new measure and selected event;
- track navigation announces staff, instrument, and voice context.

### Manual QA

- NVDA on Windows.
- VoiceOver on macOS when available.
- Verify that speech is not duplicated.
- Verify that rapid key repeat does not queue stale previews.
- Verify chord preview on horizontal navigation.
- Verify focused-note preview on vertical drill-down.
- Verify audio-preview-off behavior.

## Future specs

Follow-up specs should cover:

1. Unit-level selection, copy, paste, deletion, and replacement.
2. Numeric go-to actions and dialogs for note, beat, bar, measure, track, and staff.
3. Command palette improvements, including shortcut display and promptable actions.
4. Optional expert preference for horizontal navigation that visits every note inside chords.
