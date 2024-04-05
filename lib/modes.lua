-- lookup for chord degrees and qualities, mirroring MusicUtil.SCALE_CHORD_DEGREES with added chord "quality"

chord_lookup = {
  {
    name = "Major",
    chords = {
      "I",  "ii",  "iii",  "IV",  "V",  "vi",  "vii\u{B0}",
      "IM7", "ii7", "iii7", "IVM7", "V7", "vi7", "vii\u{F8}7"
    },
    quality = {
      "",  "m",  "m",  "",  "",  "m",  "\u{B0}",
      "M7", "m7", "m7", "M7", "7", "m7", "\u{F8}7"
    }
  },
  {
    name = "Natural Minor",
    chords = {
      "i",  "ii\u{B0}",  "III",  "iv",  "v",  "VI",  "VII",
      "i7", "ii\u{F8}7", "IIIM7", "iv7", "v7", "VIM7", "VII7"
    },
    quality = {
      "m",  "\u{B0}",  "",  "m",  "m",  "",  "",
      "m7", "\u{F8}7", "M7", "m7", "m7", "M7", "7"
    }
  },
  {
    name = "Harmonic Minor",
    chords = {
      "i",  "ii\u{B0}",  "III+",  "iv",  "V",  "VI",  "vii\u{B0}",
      "i\u{266e}7", "ii\u{F8}7", "III+M7", "iv7", "V7", "VIM7", "vii\u{B0}7"
    },
    quality = {
      "m",  "\u{B0}",  "+",  "m",  "",  "",  "\u{B0}",
      "m\u{266e}7", "\u{F8}7", "+M7", "m7", "7", "M7", "\u{B0}7"
    }
  },
  {
    name = "Melodic Minor",
    chords = {
      "i",  "ii",  "III+",  "IV",  "V",  "vi\u{B0}",  "vii\u{B0}",
      "i\u{266e}7", "ii7", "III+M7", "IV7", "V7", "vi\u{F8}7", "vii\u{F8}7"
    },
    quality = {
      "m",  "m",  "+",  "",  "",  "\u{B0}",  "\u{B0}",
      "m\u{266e}7", "m7", "+M7", "7", "7", "\u{F8}7", "\u{F8}7"
    }
  },
  {
    name = "Dorian",
    chords = {
      "i",  "ii",  "III",  "IV",  "v",  "vi\u{B0}",  "VII",
      "i7", "ii7", "IIIM7", "IV7", "v7", "vi\u{F8}7", "VIIM7"
    },
    quality = {
      "m",  "m",  "",  "",  "m",  "\u{B0}",  "",
      "m7", "m7", "M7", "7", "m7", "\u{F8}7", "M7"
    }
  },
  {
    name = "Phrygian",
    chords = {
      "i",  "II",  "III",  "iv",  "v\u{B0}",  "VI",  "vii",
      "i7", "IIM7", "III7", "iv7", "v\u{F8}7", "VIM7", "vii7"
    },
    quality = {
      "m",  "",  "",  "m",  "\u{B0}",  "",  "m",
      "m7", "M7", "7", "m7", "\u{F8}7", "M7", "m7"
    }
  },
  {
    name = "Lydian",
    chords = {
      "I",  "II",  "iii",  "iv\u{B0}",  "V",  "vi",  "vii",
      "IM7", "II7", "iii7", "iv\u{F8}7", "VM7", "vi7", "vii7"
    },
    quality = {
      "",  "",  "m",  "\u{B0}",  "",  "m",  "m",
      "M7", "7", "m7", "\u{F8}7", "M7", "m7", "m7"
    }
  },
  {
    name = "Mixolydian",
    chords = {
      "I",  "ii",  "iii\u{B0}",  "IV",  "v",  "vi",  "VII",
      "I7", "ii7", "iii\u{F8}7", "IVM7", "v7", "vi7", "VIIM7"
    },
    quality = {
      "",  "m",  "\u{B0}",  "",  "m",  "m",  "",
      "7", "m7", "\u{F8}7", "M7", "m7", "m7", "M7"
    }
  },
  {
    name = "Locrian",
    chords = {
      "i\u{B0}",  "II",  "iii",  "iv",  "V",  "VI",  "vii",
      "i\u{F8}7", "IIM7", "iii7", "iv7", "VM7", "VI7", "vii7"
    },
    quality = {
      "\u{B0}",  "",  "m",  "m",  "",  "",  "m",
      "\u{F8}7", "M7", "m7", "m7", "M7", "7", "m7"
    }
  },
}