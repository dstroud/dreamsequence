-- nb voice for MIDI that passes channel arg to player as using mod_target `ch`
-- requires modified version of nb to pass `ch` to note_off
-- called by Dreamsequence; does not get registered with mod hook and is removed on script cleanup

local mod = require "core/mods"

if note_players == nil then
    note_players = {}
end

local function add_midi_ds_players()
    for i, v in ipairs(midi.vports) do
        (function(i)
            if v.connected then
                local conn = midi.connect(i)
                local player = {
                    conn = conn
                }

                player.channel = true -- tells Dreamsequence to enable channels for this player

                function player:add_params()
                end

                function player:note_on(note, vel, properties)
                    if properties == nil then
                        properties = {}
                    end
                    local ch = properties.ch or 1 -- self:ch()
                    self.conn:note_on(note, util.clamp(math.floor(127 * vel), 0, 127), ch)
                end

                function player:note_off(note, vel, properties)
                    if properties == nil then
                        properties = {}
                    end
                    local ch = properties.ch or 1 -- self:ch()
                    self.conn:note_off(note, util.clamp(math.floor(127 * (vel or 0)), 0, 127), ch)
                end

                function player:active()
                end

                function player:inactive()
                end

                function player:modulate(val)
                end

                function player:modulate_note(note, key, value)
                    if key == "pressure" then
                        self.conn:key_pressure(note, util.round(value * 127), 1)
                    end
                end

                function player:pitch_bend(note, amount)
                end

                function player:describe()
                    return {
                        name = v.name,
                        supports_bend = false,
                        supports_slew = false,
                        note_mod_targets = { "ch", "pressure" },
                    }
                end

                function player:stop_all(val)
                    for ch = 1, 16 do -- all channels since init() calls before add_params()
                        self.conn:cc(120, 1, ch)
                    end
                end

                -- format using port # since space is very tight. Use 2-digits so nb will sort properly
                note_players["midi_ds " .. string.format("%02d", i)] = player

            end
        end)(i)
    end
end

add_midi_ds_players()