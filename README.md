# Dreamsequence

Requirements: Monome Norns and Grid
Optional: Crow, Just Friends, MIDI sequencer/controller

Dreamsequence is an intuitive chord sequencer, arpeggiator, harmonizer, and arranger. 


## NORNS INTERFACE
- KEY 1: Grid functions (hold)
- KEY 2: Play/pause
- KEY 3: Reset
- ENC 2: Select
- ENC 3: Edit 


## CROW
- Crow IN 1: CV in
- Crow IN 2: Trigger in
- Crow OUT 1: V/oct out
- Crow OUT 2: Trigger/envelope out
- Crow OUT 3: Clock out
- Crow OUT 4: Events

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


