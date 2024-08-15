local lib = norns.state.shortname.."/lib/"


-- ships with norns
er = require("er")

-- modular dashboard functions
include(lib .. "dashboards")

-- modified version of lattice lib
lattice = include(lib .. "lattice")

-- lookup tables for chord names/qualities in mode, default custom scales, etc...
include(lib .. "theory")

-- divisions for clock modulo and durations
include(lib .. "divisions")

-- Lookup table for events
include(lib .. "events")

-- Chunky bois
include(lib .. "functions")

-- Chord and arp pattern generator + engine params
include(lib .. "generator")

-- cute little pics
include(lib .. "glyphs")

-- nota bene
nb = include("lib/nb/lib/nb")

-- bundled nb voices
include("lib/crow")

include("lib/midi")