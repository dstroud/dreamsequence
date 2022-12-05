# Dreamsequence

Intuitive chord sequencer, arpeggiator, harmonizer, and arranger. 

Requirements: Monome Norns and Grid.

Optional: Crow, Just Friends, CV and/or MIDI sequencers/controllers.



# Overview

Dreamsequence is a walled-garden sequencer built for speed, improvisation, and experimentation. Rather than aim for an open-ended approach in which any possible chord or note can be sequenced, it operates by first limiting the available chords to a given mode and key, then limiting the output of the arpeggiator and harmonizers to only notes in the currently-playing chord. The upshot to such a constrained approach to composition is that we're able to get weird with features like live pattern manipulation and harmonizers that ingest CV/MIDI sequences and adapt them to fit your song's structure.

Let's take a look at the core components of Dreamsequence:

### Grid-based chord sequencer
- Create up to 4 chord patterns (A, B, C, D) by entering a pattern on Grid (or by using the Generator).

- Sequencer pattern operates using chord degrees (I-VII) across two octaves. You can quickly and non-destructively change the mood of a composition by simply switching to a different Mode which will adjust the chord output accordingly.

- Chords can be output to one of several destinations: 
  - Norns engine
  - MIDI
  - Just-Friends (Norns USB>>Crow>>i2c>>JF)

- The currently playing chord is sent to the linked arpeggiator and harmonizers where it will define their behavior.

### Grid-based arpeggiator (Arp)
- Arpeggiate or strum the current chord by entering a pattern on Grid (or by using the Generator). The "Chord Type" menu option allows selecting Triad or 7th chords. Example assuming the chord sequencer is playing Cmaj:

  | Column  | Triad Out| 7th Out  |
  |---------|----------|----------|
  | 1       | C1       | C1       |
  | 2       | E1       | E1       |
  | 3       | G1       | G1       |
  | 4       | C2       | B1       |
  | 5       | E2       | C2       |
  | 6       | G2       | E2       |

- Arp can be output to one of several destinations: 
  - Norns engine
  - CV (Norns USB>>Crow)
  - MIDI
  - Just-Friends (Norns USB>>Crow>>i2c>>JF)

### MIDI harmonizer
- Transform an incoming MIDI sequence to play notes from the current chord across a wide range of octaves.

- +/- 1 change in incoming semitone relative to C1 results in a +/- 1 change in note selection from the current chord (across range of octaves). The "Chord Type" menu option allows selecting Triad or 7th chords. Example assuming the chord sequencer is playing Cmaj:

  | Note In | Triad Out| 7th Out  |
  |---------|----------|----------|
  | C1      | C1       | C1       |
  | C#1     | E1       | E1       |
  | D1      | G1       | G1       |
  | D#1     | C2       | B1       |
  | E1      | E2       | C2       |
  | F1      | G2       | E2       |

- Harmonizer can be output to one of several destinations: 
  - Norns engine
  - CV (Norns USB>>Crow)
  - MIDI
  - Just-Friends (Norns USB>>Crow>>i2c>>JF)

### CV harmonizer (requires Crow)
- Transform an incoming control voltage (CV) sequence to play notes from the current chord across a wide range of octaves.

- +/- 1/12v (1 semitone @ 1v/oct) change in incoming voltage results in a +/- 1 change in note selection from the current chord (across range of octaves). Example assuming the chord sequencer is playing Cmaj:

  | Volts In| Triad Out| 7th Out  |
  |---------|----------|----------|
  | 0v      | C1       | C1       |
  | 1/12v   | E1       | E1       |
  | 2/12v   | G1       | G1       |
  | 3/12v   | C2       | B1       |
  | 4/12v   | E2       | C2       |
  | 5/12v   | G2       | E2       |

- Harmonizer can be output to one of several destinations: 
  - Norns engine
  - CV (Norns USB>>Crow)
  - MIDI
  - Just-Friends (Norns USB>>Crow>>i2c>>JF)

### Arranger
- Sequence the chord patterns (A, B, C, D) and schedule "Events" along the Arranger timeline.

- Events set or increment parameter values as well as call functions. For example, you might create a dynamic crescendos/accelerandos, schedule a Barry-Manilow key change or two, redirect sequences to various destinations, send triggers out from Crow to CV gear, and even generate and transform chord and arp patterns.

### Generator
- Algorithmically generate chord progressions and arpeggios, along with some randomization of things like tempo, mode, and key.

- Generator algorithms can be selected at random or set using the "C-gen" and "A-gen" Global menu options.


# Grid interface

### Chord view
![ds_chord_grid](https://user-images.githubusercontent.com/435570/205140357-8cf54869-e00c-4991-aefd-77bc8f69672e.svg)
The Chord view is used to sequence chord patterns A-D. Since the following views are all affected by what chord is playing, this is typically where you'll begin composing.

- Sequence plays from top to bottom and sequence length is set using column 15.

- Chords are selected using columns 1-14 which represent chord degrees I-VII across two octaves. Pressing and holding a key will display the corresponding chord on the Norns screen Pattern Dashboard.

- Rows 1-4 of rightmost column represent 4 chord patterns: A, B, C, D.
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

- Notes from the current chord are sequenced using columns 1-14. Ex: if playing a Cmaj chord, columns 1-3 would result in the notes C, E, G. Columns 4-6 would result in the same notes one octave higher. Chord Type in the Arp menu can result in 4 notes/columns per octave.

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
The Arranger view is used to sequence chord patterns and enter the Events editor. This is typically the last step of the composition process.

- Rows 1-4 correspond to chord patterns A-D and columns 1-16 represent "segments" of the Arranger sequence. The Arranger length automatically resizes to the rightmost set pattern and any gaps in the sequence are filled in lighter colors to indicate that the previous chord pattern will be held.

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

- Each key represents on event, which fire from left to right then top to bottom.
  - Columns 1-16 are 'event lanes', although you can mix event types if you embrace chaos in your life (highly recommended).
  - Rows 1-8 represent each step in the segment's chord pattern. Keys will be dimly-illuminated to indicate the length of the pattern. Note that you can create events beyond the range of the chord pattern's length- they just won't fire.

- If an event is present (brightly illuminated), tapping the key will show the event settings. If an event is empty, tapping it will show the last-selected event type as a convenience.

- Events are set using E2 and E3, and are saved using K3.

- K2 deletes the selected event or all events if none is selected.

- Holding one event and tapping on another will copy and paste events from the held position.

- K3 is used to return to the Arranger view once finished.


# Norns interface

## Norns keys and encoders

- K1: Not currently used

- K2: Play/pause
  - Play occurs immediately while pause is quantized to always occur at the end of the active beat (assumes 4/4 time signature).
  - In certain states, the K2 will be reassigned for other uses. Currently this includes the following:
    - While holding down an arranger Event Timeline key: jump the arranger playhead to the selected segment.
    - While in the Events editor screen: delete selected or all events.

- K3: Reset
  - Arranger disabled: reset arp and chord playhead positions.
  - Arranger enabled: reset arranger, arp, and chord playhead positions.
  - While holding down an arranger Event Timeline key: enter Event Editor.
  - While in the Events editor screen: save Events and return back to Arranger.
  - While holding Chord, Arp, or Chord+Arp Grid view keys (last two keys on the rightmost column): Generate a new chord pattern, arp pattern, or both chord and arp patterns. Algorithms used can be set in Global: C-gen/A-gen (chord and arp, respectively).

- E1: Not currently used

- E2: Select menu
  - Scrolls up/down to select menu.
  - While holding Chord or Arp Grid view keys (last two keys on the rightmost column): rotate the looped portion of the active pattern up or down.


- E3: Edit
  - Changes the value of the selected menu item, including changing the 'page' on top level menus.
  - While holding Chord or Arp Grid view keys (last two keys on the rightmost column): shift the selected pattern left or right.

## Norns screen

Dreamsequence starts up on the Global menu page. The following documentation explains each section of the screen.

![ds_global_corrected](https://user-images.githubusercontent.com/435570/205408391-6636eec4-8fce-4683-9575-4e72978d946d.png)
----------------------------------------------------------------------------------------------------------------------
 
### Pattern Dashboard

![ds_pattern_mask](https://user-images.githubusercontent.com/435570/205408704-f8704d71-08dd-456e-835a-e4a4ec2d2c62.png)

- "A1" in the example above means we are on step 1 of pattern A.
- To the right of this, a symbol will show the current playback state: Playing, Paused, or Stopped.
- Below, the currently-playing chord will be displayed. Holding down a chord key on the Chord Grid view will temporarily overwrite this to indicate the chord that corresponds to the held key.
----------------------------------------------------------------------------------------------------------------------

### Arranger Dashboard

![ds_arranger_mask](https://user-images.githubusercontent.com/435570/205408738-b5681489-2fad-4b31-9003-b8cbf2e360ec.png)

- Dashboard will be brightly illuminated when Arranger is enabled, and dimmed when disabled.
- The numbers in the top left indicate the current Arranger segment and step. "1.1" in the example above indicates the first step of segment 1. If the Arranger is interrupted by being disabled and re-enabled, this readout will change to something like "T-4" where the number is a countdown, in steps, until the current pattern is completed and the Arranger resumes on the next segment.
- To the right, a symbol will indicate if the Arranger is in Loop mode (as in the example above) or One-shot mode (arrow symbol).
- In the middle of the dashboard, a mini chart shows the current and upcoming Arranger segments. In the example above, pattern A will be played twice, then pattern B twice, and pattern C twice. Note that, unlike the Arranger Grid view, this chart shows the individual steps within each segment, at a scale of one pixel per step.
- At the bottom of the chart is an indication of which steps have events. In the example above, events are highlighted on the first step of segments one, three, and five.
- At the very bottom of the dash is a readout of the remaining time on the Arranger. Note that this countdown may be adjusted if the Arranger is interrupted by being disabled and re-enabled.
----------------------------------------------------------------------------------------------------------------------

### Menus
![ds_menu_mask](https://user-images.githubusercontent.com/435570/205408637-b9f59a51-072f-4f1d-8ce9-bdb155f5e52f.png)

The left portion of the Norns screen displays one of the following "pages" and associated menu items:
  - GLOBAL <> CHORD <> ARP <> MIDI HARMONIZER <> CV HARMONIZER
 
To navigate between pages, use E2 to scroll to the top of the list of menu items until the page name is highlighted, then use E3 to change the page. To change a menu item, simply scroll down the list using E2 and change its value using E3. < and > symbols will appear when you are at the end of the range of possible values. Descriptions of each page and menu options follow.

#### Global menu: General settings that affect the entire script.
- Mode: 9 primary modes.

- Key: Global transposition of +/- 12 semitones.

- Tempo: sets Norns system clock tempo in BPM.

- Clock: System clock setting. Internal is recommended, but MIDI will work assuming you are syncing to a delay/latency-compensated clock source. Link is not recommended since there is no latency compensation in Norn's system clock. Crow clock source is not supported at this time.

- Out: System MIDI clock destination parameter.

- Crow clock: Frequency of the clock pulse from Crow out port 3. Options include note-style divisions or Pulses Per Quarter Note (PPQN). Note that higher PPQN settings are likely to result in instability. _At launch, Dreamsequence sets the Norns system clock "crow out" parameter to "off" since Dreamsequence generates its own clock pulses for Crow that only runs when the script's transport is playing._

- Dedupe <: This enables and sets the threshold for detecting and de-duplicating repeat notes at each destination. This can be particularly helpful when merging sequences from different sources (say arp and harmonizer). Rather than trying to send the same note twice (potentially resulting in truncated notes or phase cancellation issues), this will let the initial note pass and filter out the second note if it arrives within the specified period of time.

- Chord preload: This setting enables the sequencer to fetch upcoming chord changes slightly early for processing the harmonizer inputs. This compensates for situations where the incoming note may arrive slightly before the chord change it's intended to harmonize with. This does not change when the Chord and Arp sequences fire, it's only for background processing.

- Crow pullup: enable or disable Crow's i2c pullup resistors.

- C-gen: Which algorithm is used for generating _chord_ patterns. The default value of Random picks an algorighm randomly each time.

- A-gen: Which algorithm is used for generating _arp_ patterns. The default value of Random picks an algorighm randomly each time.

#### Chord menu: Settings for the chord sequencer.
- Destination: Where the output of the chord sequence is sent for playback. Some menu items are destination-specific.
  - None: Still sends chords to the arp and harmonizers, they just won't play directly. 
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c

- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: shifts output from -2 to +4 octaves.

- Step length: the length of each step/row in the chord pattern, relative to 1 measure. Values ending in T are tuplets.

- Duration (_Engine, MIDI_): chord note duration relative to 1 measure.

- Amp: (_Engine_): Norns engine amplitude.

- Cutoff (_Engine_): Norns engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): I don't actually know what this is. Filter Q?

- Pulse width (_Engine_): PolyPerc's square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI_: MIDI note velocity.

- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping.

#### Arp menu: Setting for the built-in arpeggiator
- Destination: Where the output of the arpeggio is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the arp.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c.

- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: shifts output from -2 to +4 octaves.

- Mode: Loop will repeat the arp pattern indefinitely. One-shot will fire the arp pattern once per chord step (strum).

- Step length: the length of each step/row in the arp pattern, relative to 1 measure. Values ending in T are tuplets.

- Duration (_Engine, Crow, MIDI_): arp note duration relative to 1 measure. 

- Amp: (_Engine_): Norns engine amplitude.

- Cutoff (_Engine_): Norns engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): I don't actually know what this is. Filter Q?

- Pulse width (_Engine_): PolyPerc's square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI_: MIDI note velocity.

- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3.

- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.

- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping.

#### MIDI in menu: Setting for the MIDI harmonizer
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c.

- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: shifts output from -2 to +4 octaves.

- Duration (_Engine, Crow, MIDI_): note duration relative to 1 measure.

- Amp: (_Engine_): Norns engine amplitude.

- Cutoff (_Engine_): Norns engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): I don't actually know what this is. Filter Q?

- Pulse width (_Engine_): PolyPerc's square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Pass velocity: Option to use the incoming MIDI velocity on the outgoing note.

- Velocity (_MIDI_: If pass velocity is false, use this MIDI note velocity.

- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3.

- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.

- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping.


#### CV in menu: Setting for the CV harmonizer
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer.
  - Engine: Norns' PolyPerc engine.
  - MIDI: Output on MIDI port 1.
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear. See [Crow Patching](https://github.com/dstroud/dreamsequence/blob/main/README.md#crow-patching).
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c.

- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently.

- Octave: shifts output from -2 to +4 octaves.

- Duration (_Engine, Crow, MIDI_): note duration relative to 1 measure.

- Auto-rest: When true, this option will suppress the same note when it is repeated consecutively within one chord step, resulting in a rest.

- Amp: (_Engine_): Norns engine amplitude.

- Cutoff (_Engine_): Norns engine filter frequency offset.

- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept).

- Gain (_Engine_): I don't actually know what this is. Filter Q?

- Pulse width (_Engine_): PolyPerc's square-wave based pulse width.

- Channel (_MIDI_): MIDI channel.

- Velocity (_MIDI_: MIDI note velocity.

- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3.

- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only.

- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping.


## Crow Patching

Dreamsequence supports using Crow to receive an incoming CV sequence+trigger to feed the CV Harmonizer as well as to send out a CV sequence+trigger, clock, and optional Event triggers.

- Crow IN 1: CV in, feeding the CV harmonizer
- Crow IN 2: Trigger in will sample the CV on Crow IN 1
- Crow OUT 1: V/oct out
- Crow OUT 2: Trigger or 10v AR envelope out
- Crow OUT 3: Clock out (beat-division or PPQN set in "Global:Crow clock" menu item.
- Crow OUT 4: A trigger can be sent from this output by scheduling an Event.
