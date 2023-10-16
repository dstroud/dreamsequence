-- ships with norns
er = require("er")

-- musicutil = require("musicutil")
engine.name = "PolyPerc"

-------------------------------------------------------------
local lib = "dreamsequence_dev/lib/"  -- todo prerelease!
------------------------------------------------------------


-- @dewb's updated musicutil with some modified chord names I've added
include(lib .. "musicutil_ds")

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
nb = include("lib/nb/lib/nb")  -- not sure why this doesn't work here?

include("lib/mod") -- ooh baby