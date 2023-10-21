-- nb crow envelope voice pseudo-mod
-- piggybacks off the nb player but does not register mod hook
-- only called by Dreamsequence and players are removed on script cleanup
-- performs only the env output portion of nb_crow mod
-- pretty much wholesale ripped off from https://github.com/sixolet/nb_crow

local mod = require 'core/mods'  -- disabling since we are not registering
local music = require 'lib/musicutil'
local voice = require 'lib/voice'

local ASL_SHAPES = {'linear','sine','logarithmic','exponential','now'}


if note_players == nil then
    note_players = {}
end


local function add_player(env)
    local player = {
        ext = "_"..env,
        count = 0,
        tuning = false,
    }
    
    function player:add_params()
        -- if params.lookup["nb_ds_crow_env"..self.ext] == nil then 
          params:add_group("nb_ds_crow_env"..self.ext, "crow "..env.." (env)", 8)
        -- end
        params:add_control("nb_ds_crow_attack_time"..self.ext, "attack", controlspec.new(0.0001, 3, 'exp', 0, 0.1, "s"))
        params:add_option("nb_ds_crow_attack_shape"..self.ext, "attack shape", ASL_SHAPES, 3)
        params:add_control("nb_ds_crow_decay_time"..self.ext, "decay", controlspec.new(0.0001, 10, 'exp', 0, 1.0, "s"))
        params:add_option("nb_ds_crow_decay_shape"..self.ext, "decay shape", ASL_SHAPES, 3)
        params:add_control("nb_ds_crow_sustain"..self.ext, "sustain", controlspec.new(0.0, 1.0, 'lin', 0, 0.75, ""))
        params:add_control("nb_ds_crow_release_time"..self.ext, "release", controlspec.new(0.0001, 10, 'exp', 0, 0.5, "s"))
        params:add_option("nb_ds_crow_release_shape"..self.ext, "release shape", ASL_SHAPES, 3)
        params:add_binary("nb_ds_crow_legato"..self.ext, "legato", "toggle", 1)
        params:hide("nb_ds_crow_env"..self.ext)
    end

    function player:note_on(note, vel)
        local v_vel = vel * 10
        local attack = params:get("nb_ds_crow_attack_time"..self.ext)
        local attack_shape = ASL_SHAPES[params:get("nb_ds_crow_attack_shape"..self.ext)]
        local decay = params:get("nb_ds_crow_decay_time"..self.ext)
        local decay_shape = ASL_SHAPES[params:get("nb_ds_crow_decay_shape"..self.ext)]
        local sustain = params:get("nb_ds_crow_sustain"..self.ext)
        local legato = params:get("nb_ds_crow_legato"..self.ext)
        local action
        if self.count > 0 and legato > 0 then
            action = string.format("{ to(%f,%f,'%s') }", v_vel*sustain, decay, decay_shape)
        else
            action = string.format("{ to(%f,%f,'%s'), to(%f,%f,'%s') }", v_vel, attack, attack_shape, v_vel*sustain, decay, decay_shape)
        end
        -- print(action)
        if env > 0 then -- if env out is not "off"
          crow.output[env].action = action
          crow.output[env]()
        end
        self.count = self.count + 1
    end

    function player:note_off(note)
        -- if self.tuning then return end
        self.count = self.count - 1
        if self.count <= 0 then
            self.count = 0
            -- local env = params:get("nb_ds_crow_env_out"..self.ext) - 1
            if env > 0 then -- if env out is not "off"
              local release = params:get("nb_ds_crow_release_time"..self.ext)
              local release_shape = ASL_SHAPES[params:get("nb_ds_crow_release_shape"..self.ext)]
              crow.output[env].action = string.format("{ to(%f,%f,'%s') }", 0, release, release_shape)
              crow.output[env]()
            end
        end
    end

    -- function player:set_slew(s)
    --     params:set("nb_ds_crow_portomento"..self.ext, s)
    -- end

    function player:describe(note)
        return {
            name = "crow "..env.." env",
            supports_bend = false,
            supports_slew = false,
            modulate_description = "unsupported",
        }
    end

    function player:active()
        params:show("nb_ds_crow_env"..self.ext)
        _menu.rebuild_params()
    end

    function player:inactive()
        params:hide("nb_ds_crow_env"..self.ext)
        _menu.rebuild_params()
    end

    -- note_players["crow_ds "..env] = player
    note_players["crow env "..env] = player

end

add_player(1)
add_player(2)
add_player(3)
add_player(4)