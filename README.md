# Dreamsequence

Intuitive chord sequencer, arpeggiator, harmonizer, and arranger. 

Requirements: Monome Norns and Grid

Optional: Crow, Just Friends, MIDI sequencer/controller



# Overview

Dreamsequence takes a walled-garden approach to composition by first limiting the available chords to a given mode and key, then limiting the output of the arpeggiator and harmonizers to only notes in the currently-playing chord. It will make you sound like a musical genius (or at least vaguely competent).

To understand Dreamsequence, let's take a look at its five linked components:

### Grid-based chord sequencer
- Available chords are based on the global mode and key setting and are referenced by chord degrees 1-7.
- Create up to 4 chord patterns (A, B, C, D) by entering a pattern on Grid.
- Chords can be directly output to one of several destinations: Norns engine, MIDI, or Just-Friends (Norns USB>>Crow>>i2c>>JF)
- Currently-playing chord is sent to the linked arpeggiator and harmonizers where it will define behavior.

### Grid-based arpeggiator
- Arpeggiate or strum notes from the current chord by entering a pattern on Grid.
- Outgoing sequence can be sent to one of several destinations: Norns engine, CV (Norns USB>>Crow), MIDI, or Just-Friends (Norns USB>>Crow>>i2c>>JF)

### MIDI harmonizer
- Harmonizer transforms an incoming MIDI sequence to play notes from the current chord across a wide range of octaves.
- +/- 1 change in incoming semitone relative to C1 results in a +/- 1 change in note selection from the current chord (across range of octaves).
- Ex when the chord sequencer is currently playing a Cmaj chord (_note in_>>_note out_): _C1_>>_C1_, _C#1_>>_E1_, _D1_>>_G1_, _D#1_>>_C2_
- Outgoing sequence can be sent to one of several destinations: Norns engine, CV (Norns USB>>Crow), MIDI, or Just-Friends (Norns USB>>Crow>>i2c>>JF)

### CV harmonizer (requires Crow)
- Harmonizer transforms an incoming control voltage (CV) sequence to play notes from the current chord across a wide range of octaves.
- + 1/12v (1 semitone @ 1v/oct) change in incoming voltage results in a + 1 change in note selection from the current chord (across range of octaves).
- Ex when the chord sequencer is currently playing a Cmaj chord (_volts in_>>_note out_): _0v_>>_C1_, _1/12v_>>_E1_, _2/12v_>>_G1_, _3/12v_>>_C2_
- Outgoing sequence can be sent to one of several destinations: Norns engine, CV (Norns USB>>Crow), MIDI, or Just-Friends (Norns USB>>Crow>>i2c>>JF)

### Arranger
- Harmonizer sequences the chord patterns (A, B, C, D) and handles the scheduling of automation events.
- Automation events can introduce parameter changes, transform or generate chord/arp patterns, send CV triggers from Crow, etc...

# Grid interface


# Norns interface

## Norns keys and encoders

- KEY 1: Grid functions (hold)
  - Holding down key 1 enables alternative functions depending on which view is currently selected on Grid

- KEY 2: Play/pause
- Play occurs immediately while pause is quantized to always occur at the end of the active beat (assumes 4/4 time signature).
- In certain states, the K2 will be reassigned for other uses. Currently this includes the following:
  - While holding down an arranger Event Timeline key: jump the arranger playhead to the selected segment.
  - While in the Events editor screen: delete selected or all events


- KEY 3: Reset
- Arranger disabled: reset arp and chord playhead positions
- Arranger enabled: reset arranger, arp, and chord playhead positions
- While holding KEY 1: Generate a new chord and/or arp pattern. Algorithms used can be set in Global: C-gen/A-gen (chord and arp, respectively).
  - While holding down an arranger Event Timeline key: enter Event Editor
  - While in the Events editor screen: save Events

- ENC 2: Select menu
- Scrolls up/down to select menu
- While holding KEY 1 in Chord and Arp Grid views: rotate the looped portion of the active pattern up or down


- ENC 3: Edit
- Changes the value of the selected menu item, including changing the 'page' on top level menus
- While holding KEY 1 in Chord and Arp Grid views: shift the selected pattern left or right

## Norns screen

## Menus
### Global menu: General settings that affect the entire script
- Mode: 9 primary modes
- Key: Global transposition of +/- 12 semitones
- Tempo: sets Norns system clock tempo in BPM
- Arranger: loop the Arranger continuously or run one time before stopping (One-shot)
- Clock: System clock setting. Internal is recommended, but MIDI will work assuming you are syncing to a delay/latency-compensated clock source. Link is not recommended (can introduce latency which can not be compensated for with the current Norns clock). Crow clock source is not supported at this time.
- Out: System MIDI out parameter
- Crow clock: This parameter controls the frequency of the clock pulse from Crow out port 3. Options include note-style divisions or Pulses Per Quarter Note (PPQN). Note that higher PPQN settings are likely to result in instability. _At launch, Dreamsequence sets the Norns system clock "crow out" parameter to 'off'. Instead, of using the system clock, Dreamsequence has its own clock that only runs when the script's transport is playing. _
- Dedupe <: This enables and sets the threshold for detecting and de-duplicating repeat notes at each destination. This can be particularly helpful when merging sequences from different sources (say arp and harmonizer). Rather than trying to send the same note twice (resulting in truncated notes or phasing issues), this will let the initial note pass and filter out the second note if it arrives within the defined period of time.
- Chord preload: This setting enables the sequencer to fetch upcoming chord changes slightly early for processing the harmonizer inputs. This compensates for situations where the incoming note may arrive slightly before the chord change it's intended to harmonize with. This does not change when the Chord and Arp sequences fire, it's only for background processing.
- Crow pullup: enable or disable Crow's i2c pullup resistors.
- C-gen: Which algorithm is used for generating _chord_ patterns (K1+K3 or events). The default value of Random picks an algorighm randomly each time.
- A-gen: Which algorithm is used for generating _arp_ patterns (K1+K3 or events). The default value of Random picks an algorighm randomly each time.

### Chord menu: Settings for the chord sequencer
- Destination: Where the output of the chord sequence is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will still send chords to the arp and harmonizers, they just won't play directly. 
  - Engine: Norns' PolyPerc engine
  - MIDI: Output on MIDI port 1
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently
- Octave: Octave -2 to +4 octaves
- Step length: the length of each step/row in the chord pattern, relative to 1 measure. Values ending in T are tuplets
- Duration (_Engine, MIDI_): chord note duration relative to 1 measure 
- Amp: (_Engine_): Norns engine amplitude
- Cutoff (_Engine_): Norns engine filter frequency offset
- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept)
- Gain (_Engine_): I don't actually know what this is. Filter Q?
- Pulse width (_Engine_): PolyPerc's square-wave based pulse width
- Channel (_MIDI_): MIDI channel
- Velocity (_MIDI_: MIDI note velocity
- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping

### Arp menu: Setting for the built-in arpeggiator
- Destination: Where the output of the arpeggio is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the arp
  - Engine: Norns' PolyPerc engine
  - MIDI: Output on MIDI port 1
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear
    - Crow out 1: 1v/oct pitch CV 
    - Crow out 2: Trigger or 10v Attack Release (AR) envelope
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently
- Octave: Octave -2 to +4 octaves
- Mode: Loop will repeat the arp pattern indefinitely. One-shot will fire the arp pattern once per chord step
- Step length: the length of each step/row in the arp pattern, relative to 1 measure. Values ending in T are tuplets
- Duration (_Engine, Crow, MIDI_): arp note duration relative to 1 measure 
- Amp: (_Engine_): Norns engine amplitude
- Cutoff (_Engine_): Norns engine filter frequency offset
- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept)
- Gain (_Engine_): I don't actually know what this is. Filter Q?
- Pulse width (_Engine_): PolyPerc's square-wave based pulse width
- Channel (_MIDI_): MIDI channel
- Velocity (_MIDI_: MIDI note velocity
- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3
- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only 
- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping

### MIDI in menu: Setting for the MIDI harmonizer
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer
  - Engine: Norns' PolyPerc engine
  - MIDI: Output on MIDI port 1
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear
    - Crow out 1: 1v/oct pitch CV 
    - Crow out 2: Trigger or 10v Attack Release (AR) envelope
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently
- Octave: Octave -2 to +4 octaves
- Duration (_Engine, Crow, MIDI_): note duration relative to 1 measure 
- Amp: (_Engine_): Norns engine amplitude
- Cutoff (_Engine_): Norns engine filter frequency offset
- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept)
- Gain (_Engine_): I don't actually know what this is. Filter Q?
- Pulse width (_Engine_): PolyPerc's square-wave based pulse width
- Channel (_MIDI_): MIDI channel
- Pass velocity: Option to use the incoming MIDI velocity on the outgoing note
- Velocity (_MIDI_: If pass velocity is false, use this MIDI note velocity
- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3
- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only 
- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping


### CV in menu: Setting for the CV harmonizer
- Destination: Where the output of the harmonizer is sent for playback. Some menu items are destination-specific.
  - None: Selecting 'none' will mute the harmonizer
  - Engine: Norns' PolyPerc engine
  - MIDI: Output on MIDI port 1
  - Crow: Outputs a monophonic sequence via Crow for Eurorack and other CV-capable gear
    - Crow out 1: 1v/oct pitch CV 
    - Crow out 2: Trigger or 10v Attack Release (AR) envelope
  - ii-JF: Just Friends Eurorack module requires Crow connected to Just Friends via i2c
- Chord type: Selects between triads and 7th chords. Note that each sequence source can set this independently
- Octave: Octave -2 to +4 octaves
- Duration (_Engine, Crow, MIDI_): note duration relative to 1 measure
- Auto-rest: When true, this function will suppress the same note when it is repeated within one chord step, resulting in a rest.
- Amp: (_Engine_): Norns engine amplitude
- Cutoff (_Engine_): Norns engine filter frequency offset
- Fltr tracking (_Engine_): Amount of "Keyboard tracking" applied to the Norns engine filter. Higher values will result in a higher filter cutoff for higher pitched notes. Final filter frequency = note frequency * filter tracking + cutoff. (y = mx + b slope-intercept)
- Gain (_Engine_): I don't actually know what this is. Filter Q?
- Pulse width (_Engine_): PolyPerc's square-wave based pulse width
- Channel (_MIDI_): MIDI channel
- Velocity (_MIDI_: MIDI note velocity
- Output (_Crow_): Select between trigger or Attack Release (AR) envelope to be sent from Crow out 3
- AR env. skew: Amount the AR envelope will be skewed, where 0 = Decay only, 50 = triangle, and 100 = Attack only 
- Amp (_Just Friends_): amplitude of Just Friends' voice. Note that the amp range is very wide an can result in distortion or clipping


## CROW patching
- Crow IN 1: CV in
- Crow IN 2: Trigger in
- Crow OUT 1: V/oct out
- Crow OUT 2: Trigger/envelope out
- Crow OUT 3: Clock out
- Crow OUT 4: A trigger can be sent from this output by scheduling an Event in the Arranger
