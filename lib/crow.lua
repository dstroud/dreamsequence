-- nb voice for Crow that provides every configuration of cv+env output pair
-- called by Dreamsequence; does not get registered with mod hook and is removed on script cleanup
-- params are shared across voices
-- derivative of https://github.com/sixolet/nb_crow

local mod = require "core/mods"
local music = require "lib/musicutil"
local voice = require "lib/voice"

local ASL_SHAPES = {'linear','sine','logarithmic','exponential','now'}

-- since multiple players can share ports, keep usage count of each port so we know when to show/hide their param groups
if crow_ports == nil then
    crow_ports = {
                  cv_1 = 0, cv_2 = 0, cv_3 = 0, cv_4 = 0,
                  env_0 = 0, env_1 = 0, env_2 = 0, env_3 = 0, env_4 = 0
    }
end
        
if note_players == nil then
    note_players = {}
end

local function freq_to_note_num_float(freq)
    local reference = music.note_num_to_freq(60)
    local ratio = freq/reference
    return 60 + 12*math.log(ratio)/math.log(2)
end

local function add_player(cv, env)
    local player = {
        -- ext = "_"..cv.."_"..env,
        count = 0,
        tuning = false,
    }
      
    function player:add_params()
        for i = 1, 4 do
            if params.lookup["nb_crow_cv_"..i] == nil then
                params:add_group("nb_crow_cv_"..i, "crow "..i.." (cv)", 3)
                params:add_control("nb_crow_portamento_"..i, "portamento", controlspec.new(0.0, 1, 'lin', 0, 0.0, "s"))
                params:add_control("nb_crow_freq_"..i, "tuned to", controlspec.new(20, 4000, 'exp', 0, 440, 'Hz', 0.0003))
                params:add_binary("nb_crow_tune_"..i, "tune", "trigger")
                params:set_action("nb_crow_tune_"..i, function()
                    self:tune(i)
                end)
                params:hide("nb_crow_cv_"..i)
            end
            
            if env > 0 then
                if params.lookup["nb_crow_env_"..i] == nil and env > 0 then
                    params:add_group("nb_crow_env_"..i, "crow "..i.." (env)", 8)
                    params:add_control("nb_crow_attack_time_"..i, "attack", controlspec.new(0.0001, 3, 'exp', 0, 0.1, "s"))
                    params:add_option("nb_crow_attack_shape_"..i, "attack shape", ASL_SHAPES, 3)
                    params:add_control("nb_crow_decay_time_"..i, "decay", controlspec.new(0.0001, 10, 'exp', 0, 1.0, "s"))
                    params:add_option("nb_crow_decay_shape_"..i, "decay shape", ASL_SHAPES, 3)
                    params:add_control("nb_crow_sustain_"..i, "sustain", controlspec.new(0.0, 1.0, 'lin', 0, 0.75, ""))
                    params:add_control("nb_crow_release_time_"..i, "release", controlspec.new(0.0001, 10, 'exp', 0, 0.5, "s"))
                    params:add_option("nb_crow_release_shape_"..i, "release shape", ASL_SHAPES, 3)
                    params:add_binary("nb_crow_legato_"..i, "legato", "toggle", 0)
                    params:hide("nb_crow_env_"..i)
                end
            end
        end
    end
    

    function player:note_on(note, vel)
        if self.tuning then return end
        -- I have zero idea why I have to add 50 cents to the tuning for it to sound right.
        -- But I do. WTF.
        local halfsteps = note - freq_to_note_num_float(params:get("nb_crow_freq_"..cv))
        local v8 = halfsteps/12
        local v_vel = vel * 10
        local portamento = params:get("nb_crow_portamento_"..cv)
        
        if self.count > 0 then
            crow.output[cv].action = string.format("{ to(%f,%f,sine) }", v8, portamento)
            crow.output[cv]()
        else
            crow.output[cv].volts = v8
        end
        
        if env > 0 then
            local attack = params:get("nb_crow_attack_time_"..env)
            local attack_shape = ASL_SHAPES[params:get("nb_crow_attack_shape_"..env)]
            local decay = params:get("nb_crow_decay_time_"..env)
            local decay_shape = ASL_SHAPES[params:get("nb_crow_decay_shape_"..env)]
            local sustain = params:get("nb_crow_sustain_"..env)
            local legato = params:get("nb_crow_legato_"..env)
            local action

            if self.count > 0 and legato > 0 then
                action = string.format("{ to(%f,%f,'%s') }", v_vel*sustain, decay, decay_shape)
            else
                action = string.format("{ to(%f,%f,'%s'), to(%f,%f,'%s') }", v_vel, attack, attack_shape, v_vel*sustain, decay, decay_shape)
            end
            
            crow.output[env].action = action
            crow.output[env]()
        end
        self.count = self.count + 1
    end
    
    function player:note_off(note)
        if self.tuning then return end
        self.count = self.count - 1
        if self.count <= 0 then
            self.count = 0
            if env > 0 then
                local release = params:get("nb_crow_release_time_"..env)
                local release_shape = ASL_SHAPES[params:get("nb_crow_release_shape_"..env)]
                crow.output[env].action = string.format("{ to(%f,%f,'%s') }", 0, release, release_shape)
                crow.output[env]()
            end
        end
    end

    function player:set_slew(s)
        params:set("nb_crow_portamento_"..cv, s)
    end

    function player:describe(note)
        return {
            name = "crow_ds "..cv.."/"..env,
            supports_bend = false,
            supports_slew = true,
            modulate_description = "unsupported",
        }
    end

    function player:active()
        crow_ports["cv_"..cv] = crow_ports["cv_"..cv] + 1
        params:show("nb_crow_cv_"..cv)
        if env > 0 then
            crow_ports["env_"..env] = crow_ports["env_"..env] + 1
            params:show("nb_crow_env_"..env)  -- what about nils
        end
        _menu.rebuild_params()
    end

    function player:inactive()
        crow_ports["cv_"..cv] = crow_ports["cv_"..cv] - 1
        if crow_ports["cv_"..cv] == 0 then
            params:hide("nb_crow_cv_"..cv)
        end
        
        if env > 0 then
            crow_ports["env_"..env] = crow_ports["env_"..env] - 1
            if crow_ports["env_"..env] == 0 then
                params:hide("nb_crow_env_"..env)
            end
            _menu.rebuild_params()
        end
    end

    -- modified from usual nb_crow since env source is variable
    function player:tune(cv)
        print("OMG TUNING: Turn down Norns monitor level, patch oscillator to Norns left input bypassing VCA...")
        self.tuning = true
        crow.output[cv].volts = 0
        local p = poll.set("pitch_in_l")
        p.callback = function(f) 
            print("in > "..string.format("%.2f",f))
            params:set("nb_crow_freq_"..cv, f)
        end
        p.time = 0.25
        p:start()
        clock.run(function()
             clock.sleep(10)
             p:stop()
             clock.sleep(0.2)
             self.tuning = false
             print("Tuning done!")
        end)
    end
    note_players["crow_ds "..cv.."/"..env] = player
end

for i = 1, 4 do               -- cv
    for j = 0, 4 do           -- env
        if i ~= j then
            add_player(i, j)
        end
    end
end