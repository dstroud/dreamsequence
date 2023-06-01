-- ships with norns
ER = require("er")
musicutil = require("musicutil")
engine.name = "PolyPerc"

local lib = "dreamsequence/lib/"

-- divisions for clock modulo and durations
include(lib .. "divisions")

-- Lookup table for events
include(lib .. "events")

-- Chord and arp pattern generator + engine params
include(lib .. "generator")