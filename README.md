# Dreamsequence

Chord-based sequencer, arpeggiator, and harmonizer for Monome Norns+Grid.

Required: Monome Norns (**v2.7.6 or later**) and Grid.

Optional:
- Crow can be used to process incoming CV+triggers as well as to send sequences to CV gear or certain i2c gear (currently Just Friends and Disting EX).
- MIDI can be used to process incoming notes (from a sequencer or MIDI controller) as well as to send MIDI sequences to synths, samplers, DAWs, etc..


# Overview

As a self-taught musical tinkerer, I've often struggled with getting an idea out of my head and into a sequencer/DAW/instrument. My limited knowledge of theory and my amateur keyboard chops make for a rather laborious songwriting process. By the time I have composed something okay-sounding, I've iterated on and listened to it so much that it has long since worn its welcome.

Wouldn't it be nice if there was a tool that offloaded some of the music-theory burden so we can focus on enjoying the process of composing? Dreamsequence aims to be just such a tool; it's a musical sketchpad that allows for rapid prototyping, improvisation, experimentation, and performance- without the risk of going too far off the rails.

The core concept is one that I began exploring with my Teletype scripts [Minim](https://github.com/dstroud/minim) and [Subsequence](https://github.com/dstroud/subsequence). Similar to those tools, *Dreamsequence works by first limiting the available chords to a given mode and key, then limiting the arpeggiator and harmonizer outputs to only notes in the active chord. In other words, you are free to poke wildly at Grid and there is a pretty good chance that the result will be musically coherent.*

Let's take a look at the core components of Dreamsequence:

### Grid-based chord sequencer
- Create up to 4 chord patterns (A, B, C, D) by entering a pattern on Grid (or by using the procedural chord progression Generator).

- Chord patterns are referenced by chord degrees (I-VII) across two octaves. You can quickly and non-destructively change the mood of a composition by simply switching to a different mode or key which will adjust the chord output accordingly.

- Chords can be sent to one of several destinations: 
  - Norns sound engine
  - MIDI
  - Just Friends or Disting EX via Crow's i2c bus

- The active chord is always sent to the arpeggiator and harmonizers where it will be used to restrict their output to match the chord, even if direct chord playback is disabled.

### Grid-based arpeggiator (Arp)
- Arpeggiate or strum the active chord by entering a pattern on Grid (or by using the procedural arp Generator). The "Chord Type" menu option allows selecting Triad or 7th chords. Example assuming the chord sequencer is playing Cmaj/7:
  
  | Column    | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 |
  |:---------:|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
  | Triad Out | C1 | E1 | G1 | C2 | E2 | G2 | C3 | E3 | G3 | C4 | E4 | G4 | C5 | E5 |
  | 7th Out   | C1 | E1 | G1 | B1 | C2 | E2 | G2 | B2 | C3 | E3 | G3 | B3 | C4 | E4 |

- Arp can be sent to one of several destinations: 
  - Norns sound engine
  - MIDI
  - CV via Crow outputs 1 (CV) and 2 (trigger or envelope)
  - Just Friends or Disting EX via Crow's i2c bus

### MIDI harmonizer
- Transform an incoming MIDI sequence to play notes from the active chord across a wide range of octaves.

- +/- 1 change in incoming semitone relative to C1 results in a +/- 1 change in note selection from the active chord (across range of octaves). The "Chord Type" menu option allows selecting Triad or 7th chords. Example assuming the chord sequencer is playing Cmaj/7:

  | Note In | Triad Out| 7th Out  |
  |---------|----------|----------|
  | C1      | C1       | C1       |
  | C#/D♭1  | E1       | E1       |
  | D1      | G1       | G1       |
  | D#/E♭1  | C2       | B1       |
  | E1      | E2       | C2       |
  | F1      | G2       | E2       |
  
  | Note In   | C1 | C# | D1 | D# | E1 | F1 | F# | G1 | G# | A1 | A# | B1 |
  |:---------:|----|----|----|----|----|----|----|----|----|----|----|----|
  | Triad Out | C1 | E1 | G1 | C2 | E2 | G2 | C3 | E3 | G3 | C4 | E4 | G4 |
  | 7th Out   | C1 | E1 | G1 | B1 | C2 | E2 | G2 | B2 | C3 | E3 | G3 | B3 |
  
- Typical use-cases might include:
  - Turning a synced step sequencer into a secondary arpeggio, melody, bassline, etc...
  - Improvising with a MIDI keyboard in a live performance (no dud notes!).
  - Using a looping MIDI clip from a synced DAW to generate more complex chord voicings and timings (e.g., swing).

- MIDI Harmonizer can be sent to one of several destinations: 
  - Norns sound engine
  - MIDI
  - CV via Crow outputs 1 (CV) and 2 (trigger or envelope)
  - Just Friends or Disting EX via Crow's i2c bus

### CV harmonizer (requires Crow)
- Transform incoming control voltage (CV) to play notes from the active chord across a wide range of octaves.

- +/- 1/12v (1 semitone @ 1v/oct) change in incoming voltage results in a +/- 1 change in note selection from the active chord (across range of octaves). Example assuming the chord sequencer is playing Cmaj/7:

  | Volts In| Triad Out| 7th Out  |
  |---------|----------|----------|
  | 0v      | C1       | C1       |
  | 1/12v   | E1       | E1       |
  | 2/12v   | G1       | G1       |
  | 3/12v   | C2       | B1       |
  | 4/12v   | E2       | C2       |
  | 5/12v   | G2       | E2       |

  | Volts In  | 1/12v | 2/12v | 3/12v | 4/12v | 5/12v | 6/12v | 7/12v | 8/12v | 9/12v | 10/12v | 11/12v | 1v     |
  |:---------:|-------|-------|-------|-------|-------|-------|-------|-------|-------|--------|--------|--------|
  | Triad Out | C1    | E1    | G1    | C2    | E2    | G2    | C3    | E3    | G3    | C4     | E4     | G4     |
  | 7th Out   | C1    | E1    | G1    | B1    | C2    | E2    | G2    | B2    | C3    | E3     | G3     | B3     |
  
- Typical use-cases might include:
  - Using a synced Eurorack sequencer with modulations to create an evolving sequence.
  - Turning LFOs, function generators, S&H modules, etc... into chord-quantized sequencers.
  - Using trigger/clock/voltage sources to create complex (or totally desynced) sequence timing.

- CV Harmonizer can be sent to one of several destinations: 
  - Norns sound engine
  - MIDI
  - CV via Crow outputs 1 (CV) and 2 (trigger or envelope)
  - Just Friends or Disting EX via Crow's i2c bus

### Arranger
- Sequence playback of chord patterns (A, B, C, D) and schedule "Events" along the Arranger timeline.

- Events set or increment parameter values as well as call functions. For example, you might create a dynamic crescendos/accelerandos, schedule a mode/key change, redirect sequences to various destinations, send triggers out from Crow to CV gear, and even generate or transform chord and arp patterns.

### Generator
- Algorithmically generate chord progressions and arpeggios, along with some randomization of things like tempo, mode, and key.

- Generator algorithms can be selected at random or set using the "C-gen" and "A-gen" Global menu options.


# Grid interface

### Chord view
![ds_chord_grid](https://user-images.githubusercontent.com/435570/205140357-8cf54869-e00c-4991-aefd-77bc8f69672e.svg)
The Chord view is used to sequence chord patterns A-D. Since the arp and harmonizers operate on the active chord, this is typically where you'll begin composing.

- Sequence plays from top to bottom and sequence length is set using column 15.

- Chords are selected using columns 1-14 which represent chord degrees I-VII across two octaves. Pressing and holding a key will display the corresponding chord on the Norns screen Pattern Dashboard.

- Rows 1-4 of the rightmost column represent 4 chord patterns: A, B, C, D.
  - Tapping a pattern will disable the Arranger and cue the pattern to play once the current pattern is completed.
  - Tapping a pattern twice (or the currently playing pattern once) will immediately jump to the pattern.
  - Holding one pattern and tapping on another will copy and paste chords from the held pattern.

- The last three keys on the bottom of the rightmost column switch between Arranger, Chord, and Arp views.
  - Holding the Chord view key enables alternate functions:
    - E2 rotates the looped portion of the chord sequence.
    - E3 shifts the chord pattern left or right, decrementing or incrementing chord degrees.
    - K3 generates a new chord sequence and also randomizes some related parameters like mode, key, and tempo.
    - Holding the Chord+Arp view keys together enables K3 to generate both a new chord sequence and a new arp.

----------------------------------------------------------------------------------------------------------------------
### Arp view
![ds_arp_grid](https://user-images.githubusercontent.com/435570/205157464-555400fc-a94d-43d7-86d6-1d877d23561d.svg)
The Arp view is used to create an arpeggio or one-shot (strummed) pattern based on the currently-playing chord.

- Notes from the active chord are sequenced using columns 1-14. Ex: if playing a Cmaj chord, columns 1-3 would result in the notes C, E, G. Columns 4-6 would result in the same notes one octave higher. Chord Type in the Arp menu can result in 4 notes/columns per octave.

- Arp plays from top to bottom and sequence length is set using column 15. Playback will either loop or wait until the next chord step depending on the Mode setting in the Arp menu.

- The last three keys on the bottom of the rightmost column switch between Arranger, Chord, and Arp views.
  - Holding the Arp view key enables alternate functions:
    - E2 rotates the looped portion of the arp pattern.
    - E3 shifts the arp pattern left or right.
    - K3 generates a new arp pattern.
    - Holding the Arp+Chord view keys together enables K3 to generate both a new chord sequence and a new arp.

----------------------------------------------------------------------------------------------------------------------
### Arranger view
![ds_arranger_grid](https://user-images.githubusercontent.com/435570/205140359-95a72fb4-a905-4a6c-a025-3b6bdc7d85aa.svg)
The Arranger view is used to sequence chord patterns and enter the Events editor.

- Rows 1-4 correspond to chord patterns A-D and columns 1-16 represent "segments" of the Arranger sequence. The Arranger length automatically resizes to the rightmost set pattern and any gaps in the sequence are filled in lighter colors to indicate that the previous chord pattern will be sustained.

- Row 5 is the Events Timeline, which illuminates a key if a segment contains one or more events. Holding down a key on the Events Timeline will enable alternate functions:
  - E3 shifts the selected segment and subsequent segments to the right or left depending on the direction of rotation.
  - K2 will jump the playhead to the selected segment after the current segment is finished.
  - K3 enters the Events view (see below).
  - Holding one segment and tapping on another will copy and paste events from the held segment.

- Grid key 1 (bottom left) will enable or disable the Arranger.

- Grid key 2 (bottom, second from left) switches between Loop (bright) and One-shot (dim) Arranger modes.

- The last three keys on the bottom of the rightmost column switch between Arranger, Chord, and Arp views. 

----------------------------------------------------------------------------------------------------------------------
### Events view
![ds_events_grid](https://user-images.githubusercontent.com/435570/205140348-9ca26128-de84-44ca-bf74-afa3ca21bec6.svg)
The Events view is used to manage the scheduling of parameter changes and functions at certain points in the Arrangement.

- Events view is entered by holding down an Arranger segment on row 5 of the Arranger view, then pressing K3.

- Each key represents an event, which fire from left to right then top to bottom.
  - Columns 1-16 are 'event lanes', although you can mix event types if you wish.
  - Rows 1-8 represent each step in the segment's chord pattern. Keys will be dimly-illuminated to indicate the length of the assigned pattern. Note that you can create events beyond the range of the chord pattern's length- they just won't fire.

- If an event is present (brightly illuminated), tapping the key will show the event settings. If an event is empty, tapping it will default to the last-selected event type as a convenience.

- Events are set using E2 and E3, and are saved using K3.

- K2 deletes the selected event or all events if none is selected.

- Holding one event and tapping on another will copy and paste events from the held position.

- K3 is used to return to the Arranger view once finished.


# Norns interface

## Norns keys and encoders

- K1: Not currently used

- K2: Play/pause
  - Play occurs immediately while pause is quantized to always occur at the end of the active beat (assumes 4/4 time signature).
  - In certain states, alternate functions are enabled: 
    - While holding down an arranger Event Timeline key: jump the arranger playhead to the selected segment.
    - While in the Events editor screen: delete selected or all events.

- K3: Reset
  - Arranger disabled: reset arp and chord playhead positions.
  - Arranger enabled: reset arranger, arp, and chord playhead positions.
  - In certain states, alternate functions are enabled: 
    - While holding down an arranger Event Timeline key: enter Event Editor.
    - While in the Events editor screen: save Events and return back to Arranger.
    - While holding Chord, Arp, or Chord+Arp Grid view keys (last two keys on the rightmost column): Generate a new chord pattern, arp pattern, or both chord and arp patterns. Algorithms used can be set in Global: C-gen/A-gen (chord and arp, respectively).

- E1: Not currently used

- E2: Select menu
  - Scroll up/down to select a menu.
  - In certain states, alternate functions are enabled: 
    - While holding Chord or Arp Grid view keys (last two keys on the rightmost column): rotate the looped portion of the active pattern up or down.


- E3: Edit
  - Changes the value of the selected menu item, including changing the 'page' on top level menus.
  - In certain states, alternate functions are enabled: 
    - While holding Chord or Arp Grid view keys (last two keys on the rightmost column): shift the selected pattern left or right.
    - While holding down a key on the Events Timeline (row 5): shift the selected segment and subsequent segments to the right or left depending on the direction of rotation.

## Norns screen

Dreamsequence boots to the Global menu page. The following documentation explains each section of the screen.

![ds_global_corrected](https://user-images.githubusercontent.com/435570/205408391-6636eec4-8fce-4683-9575-4e72978d946d.png)
----------------------------------------------------------------------------------------------------------------------
 
### Pattern Dashboard

![ds_pattern_mask](https://user-images.githubusercontent.com/435570/205408704-f8704d71-08dd-456e-835a-e4a4ec2d2c62.png)

- "A1" in the example above means we are on step 1 of pattern A.
- To the right of this, a symbol will indicate the current playback state: Playing, Paused, or Stopped.
- Below, the currently-playing chord will be displayed. Holding down a chord key on the Chord Grid view will temporarily overwrite this to indicate the chord that corresponds to the held key.
----------------------------------------------------------------------------------------------------------------------

### Arranger Dashboard

![ds_arranger_mask](https://user-images.githubusercontent.com/435570/205408738-b5681489-2fad-4b31-9003-b8cbf2e360ec.png)

- Dashboard will be brightly illuminated when Arranger is enabled, and dimmed when disabled.
- The numbers in the top left indicate the current Arranger segment and step. If the Arranger is interrupted by being disabled and re-enabled, this readout will change to something like "T-4" where the number is a countdown, in steps, until the current pattern is completed and the Arranger resumes on the next segment.
- To the right, a symbol will indicate if the Arranger is in Loop mode (as in the example above) or One-shot mode (arrow symbol).
- In the middle of the dashboard, a mini chart shows the current and upcoming Arranger segments. In the example above, pattern A will be played twice, then pattern B twice, then pattern C twice. Note that, unlike the Arranger Grid view, this chart shows the individual steps within each segment, at a scale of one pixel per step.
- At the bottom of the chart is an indication of which steps have events. In the example above, events are highlighted on the first step of segments one, three, and five.
- At the very bottom of the dash is a readout of the remaining time on the Arranger. Note that this countdown will be adjusted if the Arranger is interrupted by being disabled and re-enabled.
----------------------------------------------------------------------------------------------------------------------

### Menus
![ds_menu_mask](https://user-images.githubusercontent.com/435570/205408637-b9f59a51-072f-4f1d-8ce9-bdb155f5e52f.png)

The left portion of the Norns screen displays one of the following "pages" and associated menu items:
  - GLOBAL <> CHORD <> ARP <> MIDI HARMONIZER <> CV HARMONIZER
 
To navigate between pages, use E2 to scroll to the top of the list of menu items until the page name is highlighted, then use E3 to change the page. To change a menu item, simply scroll down the list using E2 and change its value using E3. < and > symbols will appear when you are at the end of the range of possible values. Descriptions of each page and menu options follow.

#### Global menu

- Mode: 9 modes: Major, Natural Minor, Harmonic Minor, Melodic Minor, Dorian, Phrygian, Lydian, Mixolydian, Locrian.

- Key: Global transposition of +/- 12 semitones.

- Tempo: sets Norns system clock tempo in BPM.

- Clock: System clock setting. Internal is recommended, but MIDI will work assuming you are syncing to a delay/latency-compensated clock source. Link is not recommended since there is no latency compensation in Norns’ system clock AFAIK. Crow clock source is not supported at this time. _Note that MIDI clock out ports must be set in the system parameters:clock settings._

- Crow clock: Frequency of the clock pulse from Crow out port 3. Defaults to note-style divisions but Pulses Per Quarter Note (PPQN) are also available by scrolling left. Note that higher PPQN settings are likely to result in instability. _At launch, Dreamsequence sets the Norns system clock "crow out" parameter to "off" since Dreamsequence generates its own clock pulses for Crow that only runs when the script's transport is playing._

- Dedupe <: This enables and sets the threshold for detecting and de-duplicating repeat notes at each destination. This can be particularly helpful when merging sequences from different sources (say arp and harmonizer). Rather than trying to send the same note twice (potentially resulting in truncated notes or phase cancellation issues), this will let the initial note pass and filter out the second note if it arrives within the specified period of time.

- Chord preload: This setting enables the sequencer to fetch upcoming chord changes slightly early for processing the harmonizer inputs. This compensates for situations where the incoming note may arrive slightly before the chord change it's intended to harmonize with, such as when playing on a keyboard and hitting a note just before the chord change. This does not change the timing of the Chord and Arp sequences.

- Crow pullup: enable or disable Crow's i2c pullup resistors.

- C-gen: Which algorithm is used for generating _chord_ patterns. The default value picks an algorithm randomly.

- A-gen: Which algorithm is used for generating _arp_ patterns. The default value picks an algorithm randomly.

#### Chord menu
- Destination: Where the output of the chord sequence is sent for playback. Some menu items are destination-specific.
  - None: Still sends chords to the arp and harmonizers, they just won't play directly. 
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - ii-JF: Just Friends Eurorack module requires Crow connected via i2c.
  - Disting: Disting EX Eurorack module requires Crow connected via i2c.

- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently so it's possible for the Chord to output triads while the other sources output 7ths (and vice versa).

- Octave: Shifts output from -2 to +4 octaves.

- Spread: Raises the highest note in the chord by this many octaves while keeping the lowest note at the original octave and redistributing the remaining note(s) between. Ex: Octave 1 and Spread 3 will result in a Cmaj voiced as C1, E2, G3.

- Inversion: Incrementally shifts the lowest note up an octave so that 1 = first inversion, 2 = second inversion, etc... Multiples of 3 (for triads) or 4 (for 7ths) will effectively transpose the sequence up an octave which might be desired when incrementing this parameter with an Event automation.

- Step length: The length of each step/row in the chord pattern, relative to 1 measure. Values ending in T are tuplets.

- Duration (_Engine, MIDI Disting_): Chord note duration relative to 1 measure.

- Amp: (_Engine, Just Friends_): Either Norns sound engine amplitude in percent or Just Friends amplitude in volts (0-5v).

- Cutoff (_Engine_): Norns sound engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns sound engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): Norns sound engine gain setting.

- Pulse width (_Engine_): Norns sound engine square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI, Disting_: Note velocity.

#### Arp menu
- Destination: Where the output of the arpeggio is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the arp.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected via i2c.
  - Disting: Disting EX Eurorack module requires Crow connected via i2c.
  
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: Shifts output from -2 to +4 octaves.

- Mode: Loop will repeat the arp pattern indefinitely. One-shot will fire the arp pattern once per chord step (strum).

- Step length: The length of each step/row in the arp pattern, relative to 1 measure. Values ending in T are tuplets.

- Duration (_Engine, Crow, MIDI, Disting_): Arp note duration relative to 1 measure. 

- Amp: (_Engine, Just Friends_): Either Norns sound engine amplitude in percent or Just Friends amplitude in volts (0-5v).

- Cutoff (_Engine_): Norns sound engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns sound engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): Norns sound engine gain setting.

- Pulse width (_Engine_): Norns sound engine square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI, Disting_): Note velocity.

- Output (_Crow_): Select between trigger or Attack Decay (AD) envelope to be sent from Crow out 2.

- AD env. skew: Amount the AD envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.

#### MIDI Harmonizer menu
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected via i2c.
  - Disting: Disting EX Eurorack module requires Crow connected via i2c.
  
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: Shifts output from -2 to +4 octaves.

- Duration (_Engine, Crow, MIDI_): Note duration relative to 1 measure. _Currently, Dreamsequence always uses this value regardless of how long the source note is sustained._

- Amp: (_Engine, Just Friends_): Either Norns sound engine amplitude in percent or Just Friends amplitude in volts (0-5v).

- Cutoff (_Engine_): Norns sound engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns sound engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): Norns sound engine gain setting.

- Pulse width (_Engine_): Norns sound engine square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Pass velocity (_MIDI_): Option to use the incoming MIDI velocity for the outgoing note.

- Velocity (_MIDI, Disting_: Note velocity (only available for MIDI destination when pass velocity = false).

- Output (_Crow_): Select between trigger or Attack Decay (AD) envelope to be sent from Crow out 2.

- AD env. skew: Amount the AD envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.

#### CV Harmonizer menu
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected via i2c.
  - Disting: Disting EX Eurorack module requires Crow connected via i2c.
  
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: shifts output from -2 to +4 octaves.

- Duration (_Engine, Crow, MIDI_): Note duration relative to 1 measure.

- Auto-rest: When true, this option will suppress the same note when it is repeated consecutively within one chord step, resulting in a rest.

- Amp: (_Engine, Just Friends_): Either Norns sound engine amplitude in percent or Just Friends amplitude in volts (0-5v).

- Cutoff (_Engine_): Norns sound engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns sound engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): Norns sound engine gain setting.

- Pulse width (_Engine_): Norns sound engine square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI, Disting_: Note velocity.

- Output (_Crow_): Select between trigger or Attack Decay (AD) envelope to be sent from Crow out 2.

- AD env. skew: Amount the AD envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.


# Crow Patching

Dreamsequence supports using Crow to receive incoming CV for the CV Harmonizer as well as to send out a CV sequence with trigger/envelope, clock, and optional Event triggers.

- Crow IN 1: CV in, feeding the CV harmonizer
- Crow IN 2: Trigger (rising past 2 volts) in will sample the CV on Crow IN 1
- Crow OUT 1: V/oct out
- Crow OUT 2: Trigger or 10v Attack Decay envelope out
- Crow OUT 3: Clock out (beat-division or PPQN set in "Global:Crow clock" menu item.
- Crow OUT 4: A trigger can be sent from this output by scheduling an [Arranger Event](https://github.com/dstroud/dreamsequence/edit/main/README.md#events-view).
