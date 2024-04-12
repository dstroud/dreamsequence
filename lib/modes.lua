modes = {}

-- lookup for chord degrees and qualities, mirroring MusicUtil.SCALE_CHORD_DEGREES with added chord "quality"
chord_lookup = {
  {
    name = "Major",
    chords = {
      "I",  "ii",  "iii",  "IV",  "V",  "vi",  "vii°",
      "IM7", "ii7", "iii7", "IVM7", "V7", "vi7", "viiø7"
    },
    quality = {
      "",  "m",  "m",  "",  "",  "m",  "°",
      "M7", "m7", "m7", "M7", "7", "m7", "ø7"
    }
  },
  {
    name = "Natural Minor",
    chords = {
      "i",  "ii°",  "III",  "iv",  "v",  "VI",  "VII",
      "i7", "iiø7", "IIIM7", "iv7", "v7", "VIM7", "VII7"
    },
    quality = {
      "m",  "°",  "",  "m",  "m",  "",  "",
      "m7", "ø7", "M7", "m7", "m7", "M7", "7"
    }
  },
  {
    name = "Harmonic Minor",
    chords = {
      "i",  "ii°",  "III+",  "iv",  "V",  "VI",  "vii°",
      "i♮7", "iiø7", "III+M7", "iv7", "V7", "VIM7", "vii°7"
    },
    quality = {
      "m",  "°",  "+",  "m",  "",  "",  "°",
      "m♮7", "ø7", "+M7", "m7", "7", "M7", "°7"
    }
  },
  {
    name = "Melodic Minor",
    chords = {
      "i",  "ii",  "III+",  "IV",  "V",  "vi°",  "vii°",
      "i♮7", "ii7", "III+M7", "IV7", "V7", "viø7", "viiø7"
    },
    quality = {
      "m",  "m",  "+",  "",  "",  "°",  "°",
      "m♮7", "m7", "+M7", "7", "7", "ø7", "ø7"
    }
  },
  {
    name = "Dorian",
    chords = {
      "i",  "ii",  "III",  "IV",  "v",  "vi°",  "VII",
      "i7", "ii7", "IIIM7", "IV7", "v7", "viø7", "VIIM7"
    },
    quality = {
      "m",  "m",  "",  "",  "m",  "°",  "",
      "m7", "m7", "M7", "7", "m7", "ø7", "M7"
    }
  },
  {
    name = "Phrygian",
    chords = {
      "i",  "II",  "III",  "iv",  "v°",  "VI",  "vii",
      "i7", "IIM7", "III7", "iv7", "vø7", "VIM7", "vii7"
    },
    quality = {
      "m",  "",  "",  "m",  "°",  "",  "m",
      "m7", "M7", "7", "m7", "ø7", "M7", "m7"
    }
  },
  {
    name = "Lydian",
    chords = {
      "I",  "II",  "iii",  "iv°",  "V",  "vi",  "vii",
      "IM7", "II7", "iii7", "ivø7", "VM7", "vi7", "vii7"
    },
    quality = {
      "",  "",  "m",  "°",  "",  "m",  "m",
      "M7", "7", "m7", "ø7", "M7", "m7", "m7"
    }
  },
  {
    name = "Mixolydian",
    chords = {
      "I",  "ii",  "iii°",  "IV",  "v",  "vi",  "VII",
      "I7", "ii7", "iiiø7", "IVM7", "v7", "vi7", "VIIM7"
    },
    quality = {
      "",  "m",  "°",  "",  "m",  "m",  "",
      "7", "m7", "ø7", "M7", "m7", "m7", "M7"
    }
  },
  {
    name = "Locrian",
    chords = {
      "i°",  "II",  "iii",  "iv",  "V",  "VI",  "vii",
      "iø7", "IIM7", "iii7", "iv7", "VM7", "VI7", "vii7"
    },
    quality = {
      "°",  "",  "m",  "m",  "",  "",  "m",
      "ø7", "M7", "m7", "m7", "M7", "7", "m7"
    }
  },
}


-- for converting between enharmonically equivalent chord names
local chord_equivalent = {
  ["A♭"] = {sharp = "G#",    flat = "B♭♭♭", rank_sharp = 0, rank_flat = 1},
  ["A"] =  {sharp = "G##",   flat = "B♭♭",  rank_sharp = 1, rank_flat = 1},
  ["A#"] = {sharp = "G###",  flat = "B♭",   rank_sharp = 1, rank_flat = 0},

  ["B♭"] = {sharp = "A#",    flat = "C♭♭",  rank_sharp = 0, rank_flat = 1},
  ["B"] =  {sharp = "A##",   flat = "C♭",   rank_sharp = 1, rank_flat = 1},
  ["B#"] = {sharp = "A###",  flat = "C",    rank_sharp = 1, rank_flat = 0},

  ["C♭"] = {sharp = "B",     flat = "D♭♭♭", rank_sharp = 0, rank_flat = 1},
  ["C"] =  {sharp = "B#",    flat = "D♭♭",  rank_sharp = 1, rank_flat = 1},
  ["C#"] = {sharp = "B##",   flat = "D♭",   rank_sharp = 1, rank_flat = 0},

  ["D♭"] = {sharp = "C#",    flat = "E♭♭♭", rank_sharp = 0, rank_flat = 1},
  ["D"] =  {sharp = "C##",   flat = "E♭♭",  rank_sharp = 1, rank_flat = 1},
  ["D#"] = {sharp = "C###",  flat = "E♭",   rank_sharp = 1, rank_flat = 0},

  ["E♭"] = {sharp = "D#",    flat = "F♭♭",  rank_sharp = 0, rank_flat = 1},
  ["E"] =  {sharp = "D##",   flat = "F♭",   rank_sharp = 1, rank_flat = 1},
  ["E#"] = {sharp = "D###",  flat = "F",    rank_sharp = 1, rank_flat = 0},

  ["F♭"] = {sharp = "E",     flat = "G♭♭♭", rank_sharp = 0, rank_flat = 1},
  ["F"] =  {sharp = "E#",    flat = "G♭♭",  rank_sharp = 1, rank_flat = 1},
  ["F#"] = {sharp = "E##",   flat = "G♭",   rank_sharp = 1, rank_flat = 0},

  ["G♭"] = {sharp = "F#",    flat = "A♭♭♭", rank_sharp = 0, rank_flat = 1},
  ["G"] =  {sharp = "F##",   flat = "A♭♭",  rank_sharp = 1, rank_flat = 1},
  ["G#"] = {sharp = "F###",  flat = "A♭",   rank_sharp = 1, rank_flat = 0},
}


local function chord_offset(chord, offset)
  local chord_to_index = {A = 1, B = 2, C = 3, D = 4, E = 5, F = 6, G = 7}
  local index_to_chord = {"A","B","C","D","E","F","G"}
  return(index_to_chord[util.wrap(chord_to_index[chord] + offset, 1, 7)])
end


-- enforces the "alphabet rule" for chords and picks whichever key has fewer nonstandard chords (##, bb, B#, Cb, E#, Fb)
-- todo: might also do a secondary ranking on number of accidentals for a tie-breaker
local function gen_keys()
  modes.keys = {}
  local chords_renamed = {}

  for mode = 1, 9 do
    modes.keys[mode] = {}

    for transpose = 0, 11 do
      modes.keys[mode][transpose] = {}
      chords_renamed = {["flat"] = {}, ["sharp"] = {}, ["flat_rank"] = 0, ["sharp_rank"] = 0}

      for _ , option in pairs({"flat", "sharp"}) do
        local prev_chord_name = nil
        local prev_letter = nil
        local key = musicutil.NOTE_NAMES[util.wrap((musicutil.SCALES[mode]["intervals"][1] + 1) + transpose, 1, 12)] -- for debug
        
        for chord_no = 1, 7 do
          local chord_name = musicutil.NOTE_NAMES[util.wrap((musicutil.SCALES[mode]["intervals"][chord_no] + 1) + transpose, 1, 12)]
        
          if chord_no == 1 and option == "flat" and string.sub(chord_name, 2, 2) == "#" then
            chords_renamed[option .. "_rank"] = (chords_renamed[option .. "_rank"] or 0) + chord_equivalent[chord_name].rank_flat
            chord_name = chord_equivalent[chord_name].flat
          end

          local chord_letter = string.sub(chord_name, 1, 1)
          local equivalent = chord_equivalent[chord_name]
          local new_chord_name = chord_name
          local quality = chord_lookup[mode]["quality"][chord_no]

          if prev_chord_name then
            if prev_letter == chord_letter then
              new_chord_name = equivalent.flat
              chords_renamed[option .. "_rank"] = (chords_renamed[option .. "_rank"] or 0) + equivalent.rank_flat
            elseif prev_letter == chord_offset(chord_letter, -2) then
              new_chord_name = equivalent.sharp
              chords_renamed[option .. "_rank"] = (chords_renamed[option .. "_rank"] or 0) + equivalent.rank_sharp
            end
          end

          prev_chord_name = new_chord_name
          prev_letter = string.sub(new_chord_name, 1, 1)
          chords_renamed[option][chord_no] =  new_chord_name .. quality

          if chord_no == 1 then
            chords_renamed[option].key = new_chord_name
          end
        end
      end

      -- keep the key that has a lower rank (fewer undesirable chord names)
      if (chords_renamed.flat_rank or 0) < (chords_renamed.sharp_rank or 0) then
        modes.keys[mode][transpose] = chords_renamed.flat
      else
        modes.keys[mode][transpose] = chords_renamed.sharp
      end
    end
  end
end
gen_keys()