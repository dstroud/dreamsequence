-- ships with norns
er = require("er")

musicutil = require("musicutil") -- subbed

local lib = norns.state.shortname.."/lib/"

-- modified version of lattice lib
lattice = include(lib .. "lattice")

-- lookup table for chord names/qualities in mode
include(lib .. "modes")

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

-- bundled crow nb voice
include("lib/crow")