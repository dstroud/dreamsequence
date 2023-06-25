-- ships with norns
ER = require("er")
musicutil = require("musicutil")
engine.name = "PolyPerc"

local lib = "dreamsequence/lib/"

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