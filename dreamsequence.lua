-- Dreamsequence
-- v1.3.1 @modularbeat
-- l.llllllll.co/dreamsequence
--
-- Chord-based sequencer, 
-- arpeggiator, and harmonizer 
-- for Monome Norns+Grid
-- 
-- KEY 2: Pause/Stop(2x)
-- KEY 3: Play
--
-- ENC 1: Scroll (16x8 Grid)
-- ENC 2: Select
-- ENC 3: Edit
--
-- Crow IN 1: CV in
-- Crow IN 2: Trigger in
-- Crow OUT 1: CV out
-- Crow OUT 2: Envelope out
-- Crow OUT 3: Events out
-- Crow OUT 4: Clock out

norns.version.required = 240221
g = grid.connect()
include(norns.state.shortname.."/lib/includes")
clock.link.stop() -- transport won't start if external link clock is already running

-- locals
local latest_strum_coroutine = coroutine.running()

function init()
  -----------------------------
  -- todo p0 prerelease ALSO MAKE SURE TO UPDATE ABOVE!
  local version = "v1.3.1.3"
  -----------------------------

  function read_prefs()  
    prefs = {}
    local filepath = norns.state.data
    if util.file_exists(filepath) then
      if util.file_exists(filepath.."prefs.data") then
        prefs = tab.load(filepath.."prefs.data")
        print("table >> read: " .. filepath.."prefs.data")
        else
          print("table >> missing: " .. filepath.."prefs.data")
      end
    end
  end
  read_prefs()

  if prefs ~= nil then
    nb.voice_count = prefs.voice_instances or 1
    print("nb.voice_count set to " .. nb.voice_count)
  end
  nb:init()
  -- suppress some nb_crow and nb_jf mod players-- they come back on next nb init
  nb.players["crow 1/2"] = nil
  nb.players["crow 3/4"] = nil
  nb.players["crow para"] = nil
  nb.players["jf kit"] = nil
  nb.players["jf mpe"] = nil


  ------------------------------------
  -- redefine system functions/actions
  ------------------------------------
  
  -- update MIDI clock ports on add/remove/clock param change. Restored on script init
  for i = 1,16 do
    local old_action = params.params[params.lookup["clock_midi_out_" .. i]].action
    params:set_action("clock_midi_out_"..i,
      function(x)
        old_action(x)
        transport_midi_update()
      end
    )
  end

  function midi.add(dev)      -- Restored on script init
    transport_midi_update()
  end

  function midi.remove(dev)   -- Restored on script init
    transport_midi_update()
  end


  -- thanks @dndrks for this little bit of magic to check ^^crow^^ version!!
  norns.crow.events.version = function(...)
    crow_version = ...
  end
  crow.version() -- Uses redefined crow.version() function to set crow_version global var
  crow_version_clock = clock.run(
    function()
      clock.sleep(.05) -- a small hold for usb round-trip
      local major, minor, patch = string.match(crow_version or "v9.9.9", "(%d+)%.(%d+)%.(%d+)")
      local crow_version_num = major + (minor /10) + (patch / 100)  -- this feels like it's gonna break lol
      if crow_version ~= nil then print("Crow version " .. crow_version) end
      if crow_version_num < 4.01 then
        print("Crow compatibility mode enabled per https://github.com/monome/crow/pull/463")
        crow_trigger_in = function()
          if crow_div == 0 then
            crow.send("input[1].query = function() stream_handler(1, input[1].volts) end")
            crow.input[1].query()
          end
        end
      else
        crow_trigger_in = function()
          -- todo p2 could just overwrite function so nothing happens. Not sure how to do that and maintain crow clock_source though
          if crow_div == 0 then
            crow.input[1].query()
          end
        end
      end
      crow.input[1].stream = sample_crow
      crow.input[1].mode("none")
      -- todo idea: could do a gate with "both" for ADSR envelope so this can do passthrough note duration
      if params:get("clock_source") ~= 4 then
        crow.input[2].mode("change", 2 , 0.1, "rising") -- voltage threshold, hysteresis, "rising", "falling", or “both"
        crow.input[2].change = crow_trigger_in
      end
    end
  )


  crow.ii.jf.event = function(e, value)
    if e.name == "mode" then
      -- print("preinit jf.mode = "..value)
      preinit_jf_mode = value
    elseif e.name == "time" then
      jf_time = value
      -- print("jf_time = " .. value)
    end
  end

  
  ------------------------------------
  -- save and restore pre-init state
  ------------------------------------
  function capture_preinit()
    preinit_jf_mode = clock.run(
      function()
        clock.sleep(0.005) -- a small hold for usb round-trip -- not sure this is needed any more
        crow.ii.jf.get ("mode") -- will trigger the above .event function
        -- Activate JF Synthesis mode here so it happens after the hold
        crow.ii.jf.mode(1)
      end
    )
  end
  capture_preinit()


  -- Reverts changes to crow and jf that might have been made by DS
  function cleanup()
    seq_lattice:destroy()
    clock.link.stop()
    
    if preinit_jf_mode == 0 then
      crow.ii.jf.mode(preinit_jf_mode)
      print("Restoring jf.mode to " .. preinit_jf_mode)
    end

    -- clear our weirdo crow players so they don't persist to other scripts
    for i = 1, 4 do             -- cv
      for j = 0, 4 do           -- env
        if i ~= j then
          nb.players["crow_ds "..i.."/"..j] = nil
        end
      end
    end

  end
  
  
  -------------
  -- Read prefs
  -------------
  read_prefs()
  
  init_generator()
  

  ---------------------
  -- Initialize Events
  ---------------------
  
  local events_lookup_names = {}
  local events_lookup_ids = {}
  local event_categories = {}
  
  function init_events()
    events_lookup_names = {}  -- locals defined outside of function
    events_lookup_ids = {}
    for i = 1, #events_lookup do
      events_lookup_names[i] = events_lookup[i].name
      events_lookup_ids[i] = events_lookup[i].id
    end
    
    -- key = event_id, value = index
    events_lookup_index = tab.invert(events_lookup_ids)
    
    -- Used to derive the min and max indices for the selected event category (Song, Chord, Seq, etc...)
    -- local event_categories = {}
    event_categories = {}
    for i = 1, #events_lookup do
      event_categories[i] = events_lookup[i].category
    end
  
    event_categories_unique = {}
    for i = 1, #event_categories do
      if i == 1 then
        table.insert(event_categories_unique, event_categories[i])
      elseif event_categories[i] ~= event_categories_unique[#event_categories_unique] then
        table.insert(event_categories_unique, event_categories[i])
      end
    end
  
    -- Generate subcategories lookup tables
    gen_event_tables()
    -- Derivatives:
    --  event_subcategories: Unique, ordered event subcategories for each category. For generating subcategories
    --  event_indices: key = conctat category_subcategory with first_index and last_index values
  end
  

  --------------------
  -- PARAMS
  --------------------
  ----------------------------------------
  params:add_separator ("DREAMSEQUENCE")

  ------------------
  -- PREFERENCES PARAMS --
  ------------------
  -- Persistent settings saved to prefs.data and managed outside of .pset files

  params:add_group("preferences", "PREFERENCES", 6 + 16)

  params:add_trigger("save_template", "Save template")
  params:set_save("save_template", false)
  params:set_action("save_template", function() params:write(00,"template") end)

  params:add_option("default_pset", "Load pset", {"Off", "Last", "Template"}, 1)
  params:set_save("default_pset", false)
  params:set("default_pset", param_option_to_index("default_pset", prefs.default_pset) or 1)
  params:set_action("default_pset", function() save_prefs() end)
  
  params:add_option("chord_readout", "Chords as", {"Name", "Degree"}, 1)
  params:set_save("chord_readout", false)
  params:set("chord_readout", param_option_to_index("chord_readout", prefs.chord_readout) or 1)
  params:set_action("chord_readout", function() save_prefs() end)
  
  params:add_option("crow_pullup", "Crow pullup", {"Off", "On"}, 2)
  params:set_save("crow_pullup", false)
  params:set("crow_pullup", param_option_to_index("crow_pullup", prefs.crow_pullup) or 2)
  params:set_action("crow_pullup", function(val) crow_pullup(val); save_prefs() end)
  
  params:add_number("voice_instances", "Voice instances", 1, 4, 4)
  params:set_save("voice_instances", false)
  params:set("voice_instances", (prefs.voice_instances or 1))
  params:set_action("voice_instances", function() save_prefs() end)

  params:add_separator ("MIDI CLOCK OUT") -- todo hide if no MIDI devices
    for i = 1, 16 do 
    local id = "midi_continue_" .. i
      params:add_option(id, id, {"pattern", "song"}, 2)
      params:set_save(id, false)
      params:set(id, param_option_to_index(id, prefs.id) or 2)
      params:set_action(id, function()
        save_prefs()
      end)
    end
    transport_midi_update() -- renames midi_continue_ params

  
  ------------------
  -- ARRANGER PARAMS --
  ------------------
  params:add_group("arranger_group", "ARRANGER", 2)

  params:add_option("arranger", "Arranger", {"Off", "On"}, 1)
  -- params:set_action("arranger", function() update_arranger_active() end) setting post-bang
  
  params:add_option("playback", "Playback", {"1-shot","Loop"}, 2)
  params:set_action("playback", function() arranger_ending() end)
  -- params:add_option("crow_assignment", "Crow 4", {"Reset", "On/high", "V/pattern", "Chord", "Pattern"},1) -- todo
  
    
  ------------------
  -- SONG PARAMS --
  ------------------
  params:add_group("song", "SONG", 13)
  
  params:add_number("mode", "Mode", 1, 9, 1, function(param) return mode_index_to_name(param:get()) end) -- post-bang action

  params:add_number("transpose", "Key", -12, 12, 0, function(param) return transpose_string(param:get()) end)

  params:add_number("ts_numerator", "Beats per bar", 1, 99, 4) -- Beats per bar
  params:add_option("ts_denominator", "Beat length", {1, 2, 4, 8, 16}, 3) -- Beat length

  params:add_option("crow_out_1", "Crow out 1", {"Off", "CV", "Env", "Events"}, 2)
  params:set_action("crow_out_1",function() gen_voice_lookups(); update_voice_params() end)  
  
  params:add_option("crow_out_2", "Crow out 2", {"Off", "CV", "Env", "Events"}, 3)
  params:set_action("crow_out_2",function() gen_voice_lookups(); update_voice_params() end)
  
  params:add_option("crow_out_3", "Crow out 3", {"Off", "CV", "Env", "Events"}, 4)
  params:set_action("crow_out_3",function() gen_voice_lookups(); update_voice_params() end)  

  params:add_option("crow_out_4", "Crow out 4", {"Off", "CV", "Env", "Events", "Clock"}, 5)
  params:set_action("crow_out_4",function() gen_voice_lookups(); update_voice_params() end)  

  -- Crow clock uses hybrid notation/PPQN
  params:add_number("crow_clock_index", "Crow clk", 1, 58, 7,function(param) return crow_clock_string(param:get()) end)
  
  params:add_number("crow_clock_swing", "Crow swing", 50, 99, 50, function(param) return percent(param:get()) end)
  
  params:add_number("dedupe_threshold", "Dedupe <", 0, 10, div_to_index("1/32"), function(param) return divisions_string(param:get()) end)
  params:set_action("dedupe_threshold", function() dedupe_threshold() end)
  
  -- deprecated
  -- params:add_number("chord_preload", "Chord preload", 0, 10, div_to_index("1/64"), function(param) return divisions_string(param:get()) end)
  -- params:set_action("chord_preload", function(x) chord_preload(x) end)     

  -- figured better here since generators can touch things outside of the chord/seq space
  params:add_option("chord_generator", "C-gen", chord_algos["name"], 1)

  params:add_option("seq_generator", "S-gen", seq_algos["name"], 1)

  
  ------------------
  -- CHORD PARAMS --
  ------------------
  params:add_group("chord", "CHORD", 17)

  params:add_number("chord_div_index", "Step length", 6, 57, 15, function(param) return divisions_string(param:get()) end)
  -- action required here for pset loading. Will then be redefined post-bang with action for lattice
  params:set_action("chord_div_index",function(val) chord_div = division_names[val][1] end)

  -- chord_div needs to be set *before* the bang happens
  chord_div = division_names[params:get("chord_div_index")][1]

  nb:add_param("chord_voice_raw", "Voice raw")
  params:hide("chord_voice_raw")

  gen_voice_lookups() -- required to build front-end voice selectors (chord_voice_raw dependency)
  params:add_option("chord_voice", "Voice", voice_param_options, 1)
  params:set_action("chord_voice", function(index) params:set("chord_voice_raw", voice_param_index[index]) end)

  params:add_number("chord_duration_index", "Duration", 0, 57, 0, function(param) return durations_string(param:get()) end)
  params:set_action("chord_duration_index",function(val) chord_duration = val == 0 and chord_div or division_names[val][1] end)
  
  params:add_number("chord_octave","Octave", -4, 4, 0)
  
  params:add_option("chord_type","Chord type", {"Triad", "7th"}, 1)
  
  params:add_number("chord_range", "Range", 3, 64, 4, function(param) return chord_range_string(param:get()) end) -- intervals

  params:add_number("chord_max_notes", "Max notes", 1, 24, 4)

  params:add_number("chord_inversion", "Inversion", 0, 16, 0)
  
  params:add_option("chord_style", "Strum", {"Off", "Low-high", "High-low"}, 1)
  
  params:add_number("chord_strum_length", "Strum length", 1, 15, 15, function(param) return strum_length_string(param:get()) end)
  
  params:add_number("chord_timing_curve", "Strum curve", -100, 100, 0, function(param) return percent(param:get()) end)

  params:add_number("chord_swing", "Swing", 50, 99, 50, function(param) return percent(param:get()) end)

  params:add_number("chord_dynamics", "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)

  params:add_number("chord_dynamics_ramp", "Ramp", -100, 100, 0, function(param) return percent(param:get()) end)

  -- params:add_number("chord_rotate", "Pattern rotate", -14, 14, 0)
  -- params:set_action("chord_rotate",function() pattern_rotate_abs("chord_rotate") end)  
  
  -- params:add_number("chord_shift", "Pattern shift", -14, 14, 0)
  -- params:set_action("chord_shift",function() pattern_shift_abs("chord_shift") end)
  
  -- will act on current pattern unlike numbered seq param
  max_chord_pattern_length = 16
  params:add_number("chord_pattern_length", "Pattern length", 1, max_chord_pattern_length, 4)
  params:set_action("chord_pattern_length", function() pattern_length("chord_pattern_length") end)


  ------------------
  -- SEQ PARAMS --
  ------------------
  params:add_group("seq", "SEQ", 18)

  params:add_option("seq_note_map_1", "Notes", {"Triad", "7th", "Mode+Transp.", "Mode", "Chromatic"}, 1)
  
  -- todo p1 rename these and update documentation: {"Repeat", "Chord step", "Chord", "Cue"}
  params:add_option("seq_start_on_1", "Start on", {"Seq end", "Step", "Chord", "Cue"}, 1)
  -- params:set_save("seq_start_on_1", false)
  -- params:hide(params.lookup["seq_start_on_1"])
    
  params:add_option("seq_reset_on_1", "Reset on", {"Step", "Chord", "Stop"}, 3)
  
  -- Technically acts like a trigger but setting up as add_binary lets it be PMAP-compatible
  params:add_binary("seq_start_1","Start", "trigger")
  params:set_action("seq_start_1",function()  play_seq = true end) -- seq_1_shot_1 = true end)
  
  -- Technically acts like a trigger but setting up as add_binary lets it be PMAP-compatible
  params:add_binary("seq_reset_1","Reset", "trigger")
  params:set_action("seq_reset_1",function() seq_pattern_position = 0 end)
  
  params:add_number("seq_div_index_1", "Step length", 1, 57, 8, function(param) return divisions_string(param:get()) end)

  nb:add_param("seq_voice_raw_1", "Voice raw")
  params:hide("seq_voice_raw_1")

  params:add_option("seq_voice_1", "Voice", voice_param_options, 1)
  params:set_action("seq_voice_1", function(index) params:set("seq_voice_raw_1", voice_param_index[index]) end)
  
  params:add_number("seq_duration_index_1", "Duration", 0, 57, 0, function(param) return durations_string(param:get()) end)
  params:set_action("seq_duration_index_1", function(val) seq_duration = val == 0 and division_names[params:get("seq_div_index_1")][1] or division_names[val][1] end)

  max_seq_pattern_length = 16  
  params:add_number("seq_rotate_1", "Pattern rotate", (max_seq_pattern_length * -1), max_seq_pattern_length, 0)
  params:set_action("seq_rotate_1", function() pattern_rotate_abs("seq_rotate_1") end)
  
  params:add_number("seq_shift_1", "Pattern shift", -14, 14, 0)
  params:set_action("seq_shift_1", function() pattern_shift_abs("seq_shift_1") end)
  
  -- numbered so we can operate on parallel seqs down the road
  params:add_number("seq_pattern_length_1", "Pattern length", 1, max_seq_pattern_length, 8)
  params:set_action("seq_pattern_length_1", function() pattern_length(1) end)
  
  params:add_number("seq_octave_1", "Octave", -4, 4, 0)

  params:add_number("seq_swing_1", "Swing", 50, 99, 50, function(param) return percent(param:get()) end)

  params:add_number("seq_dynamics_1", "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)

  params:add_number("seq_accent_1", "Accent", -100, 100, 0, function(param) return percent(param:get()) end)
  
  params:add_number("seq_probability_1", "Probability", 0, 100, 100, function(param) return percent(param:get()) end)


  ------------------
  -- MIDI HARMONIZER PARAMS --
  ------------------
  params:add_group("midi_harmonizer", "MIDI HARMONIZER", 8)  

  params:add_option("midi_note_map", "Notes", {"Triad", "7th", "Mode+Transp.", "Mode", "Chromatic"}, 1)

  nb:add_param("midi_voice_raw", "Voice raw")
  params:hide("midi_voice_raw")

  params:add_option("midi_voice", "Voice", voice_param_options, 1)
  params:set_action("midi_voice", function(index) params:set("midi_voice_raw", voice_param_index[index]) end)

  params:add_number("midi_harmonizer_in_port", "Port in",1,#midi.vports,1)
    params:set_action("midi_harmonizer_in_port", function(value)
      in_midi.event = nil
      in_midi = midi.connect(params:get("midi_harmonizer_in_port"))
      in_midi.event = midi_event      
    end)
    -- set in_midi port once before params:bang()
    in_midi = midi.connect(params:get("midi_harmonizer_in_port"))
    in_midi.event = midi_event
  
  params:add_number("midi_duration_index", "Duration", 1, 57, 10, function(param) return durations_string(param:get()) end)
  params:set_action("midi_duration_index", function(val) midi_duration = division_names[val][1] end) -- pointless?
    
  params:add_number("midi_octave", "Octave", -4, 4, 0)
  
  params:add_number("midi_dynamics", "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)


  ------------------
  -- CV HARMONIZER PARAMS --
  ------------------
  params:add_group("cv_harmonizer", "CV HARMONIZER", 10)
  
  nb:add_param("crow_voice_raw", "Voice raw")
  params:hide("crow_voice_raw")
  
  params:add_option("crow_voice", "Voice", voice_param_options, 1)
  params:set_action("crow_voice", function(index) params:set("crow_voice_raw", voice_param_index[index]) end)

  params:add_number("crow_div_index", "Trigger", 0, 57, 0, function(param) return crow_trigger_string(param:get()) end)
  params:set_action("crow_div_index", function(val) crow_div = val == 0 and 0 or division_names[val][1] end) -- overwritten

  params:add_option("crow_note_map", "Notes", {"Triad", "7th", "Mode+Transp.", "Mode", "Chromatic"}, 1)

  params:add_option("crow_auto_rest", "Auto-rest", {"Off", "On"}, 1)

  params:add_number("crow_duration_index", "Duration", 0, 57, 10, function(param) return durations_string(param:get()) end)
  params:set_action("crow_duration_index", function(val) 
    if val == 0 then  -- if in "Step" mode
      if crow_div ~= 0 then -- and not triggering via Crow IN 2
        crow_duration = crow_div  -- set duration to div
      end
    else -- not in "Step" mode so just apply the value
      crow_duration = division_names[val][1]
    end  
  end)

  params:add_number("crow_octave", "Octave", -4, 4, 0)
  
  params:add_number("cv_harm_swing", "Swing", 50, 99, 50, function(param) return percent(param:get()) end)
  
  params:add_number("crow_dynamics", "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)


  ------------------
  -- NB PARAMS --
  ------------------  
  params:add_separator("VOICES")
  nb:add_player_params() -- modified to also add nb.indices
  
  -- due to crow_ds adding *all* shared params for Crow outs 1-4 in one player, break them up:
  local function subdivide_indices(string)
    local category
    local indices = nb.indices[string]
    for i = indices.start_index, indices.end_index do
      local param = params.params[i]
      if param.t == 7 then -- group
        category = param.name
        nb.indices[category] = {start_index = i}
      else
        nb.indices[category].end_index = i
      end
    end
    nb.indices[string] = nil
  end
  subdivide_indices("crow_ds 1/0") -- cv params
  subdivide_indices("crow_ds 1/2") -- env params
  
  -- append nb params to events_lookup
  -- todo shared function with gen_voice_lookup() but mind the different trim width
  local function gen_category_name(string)
    local string = string
    
    -- shorten midi names
    if nb.players[string] ~= nil and nb.players[string].conn ~= nil then
  
      local function find_vport(name)
        for k,v in pairs(midi.vports) do
          if v.name == name then
            return k
          end
        end
      end
  
      local vport_name = nb.players[string].conn.name
      -- can't rely on nb.players[string].conn.device.port since nbout doesn't set this :/
      local port = find_vport(vport_name)
      local voice = string.match(string, "(%d+)$")
      local name = first_to_upper(string.lower(vport_name))
      if screen.text_extents(name) > 41 then  -- longest we can go and still append " 16.16" (port.voice)
        name = string.upper(util.acronym(name))
      end
      string = name .. " " .. port .. "." .. voice
    end
    return util.trim_string_to_width(string, 81) -- different length for event vs standard menus
  end

  -- Function to sort table keys alphabetically. Might move to lib/functions
  local function sort_keys(tbl)
    local keys = {}
    for key in pairs(tbl) do
      table.insert(keys, key)
    end
    table.sort(keys)
    return keys
  end
  local sorted = sort_keys(nb.indices)

  for _, k in pairs(sorted) do
    local v = nb.indices[k]
    local separator = "general"
    for i = 1, params:get(v.start_index) do
      local param = params:lookup_param(i + v.start_index) -- skips inital group

    -- tSEPARATOR = 0, tNUMBER = 1, tOPTION = 2, tCONTROL = 3, tFILE = 4, tTAPER = 5, tTRIGGER = 6, tGROUP = 7, tTEXT = 8, tBINARY = 9,
      if param.t == 1 -- number
      or param.t == 2 -- option
      or param.t == 3 -- control
      or param.t == 5 -- taper
      or param.t == 6 -- trigger
      or param.t == 9 then -- binary
        local event = {
          id = param.id,
          category = gen_category_name(k),
          value_type = param.t == 6 and "trigger" or "continuous",
          name = util.trim_string_to_width(param.name, 84),
          subcategory	= separator,
          event_type = "param"
          }
          table.insert(events_lookup, event)
      elseif param.t == 0 then
        separator = util.trim_string_to_width(param.name, 78)
      end
    end
  end


  init_events() -- creates lookup tables for events
   
  ------------------
  -- EVENT PARAMS --
  ------------------

  params:add_option("event_category", "Category", event_categories_unique, 1)
  params:hide("event_category")
  
  -- options will be dynamically swapped out based on the current event_global param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  params:add_option("event_subcategory", "Subcategory", event_subcategories["Song"], 1)
  params:hide("event_subcategory")
 
  params:add_option("event_name", "Event", events_lookup_names, 1) -- Default value overwritten later in Init
  params:hide("event_name")
  
  -- options will be dynamically swapped out based on the current event_name param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  event_operation_options_continuous = {"Set", "Increment", "Wander", "Random"}
  event_operation_options_discreet = {"Set", "Random"}
  event_operation_options_trigger = {"Trigger"} 
  params:add_option("event_operation", "Operation", _G["event_operation_options_" .. events_lookup[1].value_type], 1)
  params:hide("event_operation")

  -- todo p1 needs paramcontrol if this is even still used?
  params:add_number("event_value", "Value", -9999, 9999, get_default_event_value())
  params:hide("event_value")

  params:add_number("event_probability", "Probability", 0, 100, 100, function(param) return percent(param:get()) end)
  params:hide("event_probability")
  
  params:add_option("event_op_limit", "Limit", {"Off", "Clamp", "Wrap"}, 1)
  params:set_action("event_op_limit",function() gen_menu_events() end)
  params:hide("event_op_limit")

  params:add_option("event_op_limit_random", "Limit", {"Off", "On"}, 1)
  params:set_action("event_op_limit_random",function() gen_menu_events() end)
  params:hide("event_op_limit_random")

  params:add_number("event_op_limit_min", "Min", -9999, 9999, 0)
  params:hide("event_op_limit_min")
  
  params:add_number("event_op_limit_max", "Max", -9999, 9999, 0)
  params:hide("event_op_limit_max")
  
  params:add_number("crow_5v_8_steps_1", "5v 8-steps", 1, 8, 1)
  params:set_action("crow_5v_8_steps_1", function(param) crow_5v_8_steps_1(param) end)
  params:hide("crow_5v_8_steps_1")
  
  params:add_number("crow_5v_8_steps_2", "5v 8-steps", 1, 8, 1)
  params:set_action("crow_5v_8_steps_2", function(param) crow_5v_8_steps_2(param) end)
  params:hide("crow_5v_8_steps_2")
  
  params:add_number("crow_5v_8_steps_3", "5v 8-steps", 1, 8, 1)
  params:set_action("crow_5v_8_steps_3", function(param) crow_5v_8_steps_3(param) end)
  params:hide("crow_5v_8_steps_3")
  
  params:add_number("crow_5v_8_steps_4", "5v 8-steps", 1, 8, 1)
  params:set_action("crow_5v_8_steps_4", function(param) crow_5v_8_steps_4(param) end)
  params:hide("crow_5v_8_steps_4")
  
  
  
  -----------------------------
  -- POST-PARAM INIT STUFF
  -----------------------------
  -- globals
  
  function grid_size()
    if g.cols >= 16 then
      rows = g.rows >= 16 and 16 or 8
      print("Configured for 16x" .. rows .. " Grid")
    else
      rows = 8
      print("16x8 or 16x16 Grid required. Add in SYSTEM >> DEVICES >> GRID")
    end
    extra_rows = rows - 8
  end 

  function grid.add(dev)
    grid_size()
  end

  grid_size()

  -- pre_sync_val = nil
  debug_change_count = 0 -- todo remove
  start = false
  send_continue = false
  transport_state = "stopped"
  clock_start_method = "start"
  -- link_start_mode = "reset" -- might just use clock_start_method??
  -- link_stop_source = nil
  global_clock_div = 48 -- todo replace with ppqn and update div lookup to be fractional
  build_scale()
  -- Send out MIDI stop on launch if clock ports are enabled
  transport_multi_stop()  
  arranger_active = false
  chord_pattern_retrig = true
  play_seq = false
  screen_views = {"Session","Events"}
  screen_view_index = 1
  screen_view_name = screen_views[screen_view_index]
  grid_dirty = true
  -- grid "views" are decoupled from screen "pages"  
  grid_views = {"Arranger","Chord","Seq"}
  grid_view_keys = {}
  grid_view_name = grid_views[2]
  math.randomseed(os.time()) -- doesn't seem like this is needed but not sure why
  fast_blinky = 1
  pages = {"SONG►", "CHORD", "SEQ", "MIDI HARMONIZER", "◀CV HARMONIZER"}
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  gen_menu()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  transport_active = false
  chord_pattern_length = {4,4,4,4}
  set_chord_pattern(1)
  pattern_name = {"A","B","C","D"}
  pattern_queue = false
  pattern_copy_performed = false
  arranger_retrig = false
  max_arranger_length = 64
  arranger = {}
  for segment = 1, max_arranger_length do
    arranger[segment] = 0
  end
  arranger[1] = 1 -- setting this so new users aren't confused about the pattern padding
  arranger_padded = {} -- generates chord patterns for held segments
  arranger_position = 0
  arranger_length = 1
  arranger_grid_offset = 0 -- offset allows us to scroll the arranger grid view beyond 16 segments
  gen_arranger_padded()
  d_cuml = 0
  interaction = nil
  events = {}
  for segment = 1, max_arranger_length do
    events[segment] = {}
    for step = 1, max_chord_pattern_length do
      events[segment][step] = {}
    end
  end
  
  -- event menu init
  events_index = 1
  selected_events_menu = "event_category"
  change_category()
  params:set("event_name", event_subcategory_index_min)  -- Overwrites initial param value
  change_subcategory()
  change_event()
  gen_menu_events()
  
  event_edit_segment = 0 --todo p1 rename to event_edit_segment
  event_edit_step = 0
  event_edit_lane = 0
  steps_remaining_in_arrangement = 0
  elapsed = 0
  percent_step_elapsed = 0
  seconds_remaining = 0
  chord_no = 0
  pattern_keys = {}
  arranger_pattern_key_first = nil -- simpler way to identify the first key held down so we can handle this as a "copy" action and know when to act on it or ignore it. don't need a whole table.
  arranger_loop_key_count = 0 -- rename arranger_events_strip_key_count?
  key_counter = 4
  pattern_key_count = 0
  chord_key_count = 0
  view_key_count = 0
  event_key_count = 0
  -- keys = {}
  key_count = 0
  chord_pattern = {{},{},{},{}}
  seq_pattern = {{},{},{},{}}
  for p = 1, 4 do
    for i = 1, max_chord_pattern_length do
      chord_pattern[p][i] = 0
    end
  end
  for p = 1, 4 do
    for i = 1, max_seq_pattern_length do
      seq_pattern[p][i] = 0
    end
  end  
  pattern_grid_offset = 0 -- grid view scroll offset
  current_shift_seq = 0
  current_shift_chord = 0
  current_rotation_seq = 0
  chord_pattern_position = 0
  chord_raw = {}
  current_chord_x = 0
  current_chord_o = 0
  current_chord_c = 1
  next_chord_x = 0
  next_chord_o = 0
  next_chord_c = 1  
  seq_pattern_length = {8,8,8,8}
  active_seq_pattern = 1
  seq_pattern_position = 0
  note_history = {}  -- todo p2 performance of having one vs dynamically created history for each voice
  dedupe_threshold()
  -- reset_clock() -- might need reset_lattice but it hasn't been intialized
  get_next_chord()
  chord_raw = next_chord

  -- table names we want pset callbacks to act on
  pset_lookup = {"arranger", "events", "chord_pattern", "chord_pattern_length", "seq_pattern", "seq_pattern_length", "misc", "voice"}
  
  
  -----------------------------
  -- PSET callback functions --   
  -----------------------------
  function params.action_write(filename,name,number)
    local number = number or "00" -- template
    local filepath = norns.state.data..number.."/"
    os.execute("mkdir -p "..filepath)
    -- Make table with version (for backward compatibility checks) and any useful system params
    misc = {}
    misc.timestamp = os.date()
    misc.version = version
    misc.clock_tempo = params:get("clock_tempo")
    misc.clock_source = params:get("clock_source")
    misc.current_shift_seq = current_shift_seq
    misc.current_shift_chord = current_shift_chord
    misc.current_rotation_seq = current_rotation_seq

    -- need to save and restore nb voices which can change based on what mods are enabled
    voice = {}
    local sources = {"chord", "seq", "crow", "midi"}
    for i = 1, #sources do
      local param_string = sources[i].."_voice"
      local param_string = param_string == "seq_voice" and "seq_voice_1" or param_string
      voice[param_string] = params:string(param_string)
    end

    for i = 1, #pset_lookup do
      local tablename = pset_lookup[i]
      tab.save(_G[tablename],filepath..tablename..".data")
      print("table >> write: " .. filepath..tablename..".data")
    end
  end


  function params.action_read(filename,silent,number)
    local number = number or "00" -- template
    nb:stop_all()
    local filepath = norns.state.data..number.."/"
    if util.file_exists(filepath) then
      -- Close the event editor if it's currently open so pending edits aren't made to the new arranger unintentionally
      screen_view_index = 1
      screen_view_name = "Session"
      misc = {}
      voice = {}
      for i = 1, #pset_lookup do
        local tablename = pset_lookup[i]
          if util.file_exists(filepath..tablename..".data") then
          _G[tablename] = tab.load(filepath..tablename..".data")
          print("table >> read: " .. filepath..tablename..".data")
        else
          print("table >> missing: " .. filepath..tablename..".data")
        end
      end
      -- clock_tempo isn't stored in .pset for some reason so set it from misc.data (todo: look into inserting into .pset)
      params:set("clock_tempo", misc.clock_tempo or params:get("clock_tempo"))
      current_shift_seq = misc.current_shift_seq
      current_shift_chord = misc.current_shift_chord
      current_rotation_seq = misc.current_rotation_seq

      -- restore nb voices based on string
      local sources = {"chord", "seq", "crow", "midi"}
      for i = 1, #sources do
        local param_string = sources[i].."_voice"
        local param_string = param_string == "seq_voice" and "seq_voice_1" or param_string
        local prev_param_name = voice[param_string] --params:string(param_string)
        local iterations = #params:lookup_param(param_string).options + 1
        if prev_param_name ~= nil then -- skip if not found (old pset data)
          for j = 1, iterations do
            if j == iterations then
              params:set(param_string, 1)
              print("Unable to find NB voice " .. prev_param_name .. " for " .. param_string)
            elseif prev_param_name == params:lookup_param(param_string).options[j] then
              params:set(param_string, j)
              break
            end
          end
        end
      end
      
      -- reset event-related params so the event editor opens to the default view rather than the last-loaded event
      params:set("event_category", 1)
      change_category()
      params:set("event_subcategory", 1) -- called by the above
      params:set("event_name", 1)
      change_event()
      params:set("event_operation", 1)
      params:set("event_op_limit", 1)
      params:set("event_op_limit_random", 1)
      params:set("event_probability", 100) -- todo p1 change after float
      params:set("event_value", get_default_event_value())
      events_index = 1
      selected_events_menu = events_menus[events_index]
      gen_menu_events()
      event_edit_active = false
  
      -- todo p2 loading pset while transport is active gets a little weird with Link and MIDI but I got other stuff to deal with
      if params:get("clock_source") == "internal" then 
        reset_lattice() -- reset_clock() -- untested
      else
        gen_arranger_padded()
      end
      arranger_queue = nil
      arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
      pattern_queue = false
      seq_pattern_position = 0
      chord_pattern_position = 0
      arranger_position = 0
      set_chord_pattern(arranger_padded[1])
      if transport_state == "paused" then
        transport_state = "stopped" -- just flips to the stop icon so user knows they don't have to do this manually
      end

      -- don't remember why this was needed?
      -- local seq_reset_on_1 = params:get("seq_reset_on_1")
      -- if seq_reset_on_1 == 3 then -- Stop or Event type.
      --   play_seq = true
      -- else
      --   play_seq = false
      -- end
      play_seq = false
    
      build_scale() -- Have to run manually because mode bang comes after all of this for some reason
      get_next_chord()
      chord_raw = next_chord
      chord_no = 0 -- wipe chord readout
      gen_chord_readout()
      gen_dash("params.action_read")
      read_prefs()
      -- if transport_active, reset and continue playing so user can demo psets from the system menu
      -- todo p2 need to send different sync values depending on clock source.
      -- when link clock is running we can pick up on the wrong beat.
      -- unsure about MIDI
      -- if transport_active == true then
      --   clock.transport.start()
      -- end
      
      -- Overwrite these prefs
      params:set("chord_readout", param_option_to_index("chord_readout", prefs.chord_readout) or 1)
      params:set("default_pset", param_option_to_index("default_pset", prefs.default_pset) or 1)
      params:set("crow_pullup", param_option_to_index("crow_pullup", prefs.crow_pullup) or 2)
      for i = 1,16 do
        local id = "midi_continue_" .. i
        params:set(id, param_option_to_index(id, prefs[id]) or 2)
      end
    end
  
  grid_dirty = true

  local function verify_events()
    local warning = false
    for segment = 1, max_arranger_length do
      for step = 1, max_chord_pattern_length do
        for slot = 1, 16 do
          local event = events[segment][step][slot]
          if event ~= nil then
            if events_lookup_index[event.id] == nil then
              warning = true
              print("WARNING: unable to locate " .. event.event_type .. " " ..  event.id .. " on event ["..segment.."][" .. step .. "][" .. slot .. "]")
              
              events[segment][step][slot] = nil
              events[segment][step].populated = events[segment][step].populated - 1
              -- If the step's new populated count == 0, decrement count of populated event STEPS in the segment
              if (events[segment][step].populated or 0) == 0 then
                events[segment].populated = (events[segment].populated or 0) - 1
              end
            end
          end
        end
      end
    end
    if warning then
      print("Possible options:")
      print("1. Enable appropriate NB voice mods and restart")
      print("2. Remove or modify " .. filename)
      print("3. Continue using this .pset with event(s) removed")
      print("DO NOT SAVE .PSET UNLESS YOU WISH TO LOSE AFFECTED EVENT(S)")
    end
  end
  verify_events()

  end


  function params.action_delete(filename,name,number)
    norns.system_cmd("rm -r "..norns.state.data.."/"..number.."/")
    print("directory >> delete: " .. norns.state.data .. number)
  end
  ---------------------------
  -- end of PSET callbacks --   
  ---------------------------


  -------------
  -- Write prefs
  -------------
  function save_prefs()
    local filepath = norns.state.data
    local prefs = {}
    prefs.timestamp = os.date()
    prefs.last_version = version
    prefs.chord_readout = params:string("chord_readout")
    prefs.default_pset = params:string("default_pset")
    prefs.crow_pullup = params:string("crow_pullup")
    prefs.voice_instances = params:get("voice_instances")
    for i = 1, 16 do
      local id = "midi_continue_" .. i
      prefs[id] = params:string(id)
    end 
    tab.save(prefs, filepath .. "prefs.data")
    if countdown_timer ~= nil then --  trick to keep this from junking up repl on init bang (x2 if pset loads)
      print("table >> write: " .. filepath.."prefs.data")
    end
  end


  -- Optional: load most recent pset on init
  if params:string("default_pset") == "Last" then
    params:default()
  elseif params:string("default_pset") == "Template" then
    params:read(00)
  end
  
  params:bang()
  -- Some actions need to be added post-bang.
  params:set_action("arranger", function() update_arranger_active() end)

  params:set_action("mode", function() build_scale(); update_chord_action() end)

-- Redefine div change actions, this time with lattice stuff

-- WIP: needs some work! currently only allowing time signature div changes at lattice reset which is dumb
params:set_action("ts_numerator",
    function(val) 
      if transport_state == "stopped" then
        sprocket_measure:set_division(val / params:string("ts_denominator"))
      end
    end
  )

  params:set_action("ts_denominator",
  function(val) 
    if transport_state == "stopped" then
      sprocket_measure:set_division(params:get("ts_numerator") / params:string("ts_denominator"))
    end
  end
)

  params:set_action("chord_div_index",
    function(val) 
      chord_div = division_names[val][1]; -- extra thing needed for chord. may get rid of this
      sprocket_chord:set_division(chord_div/global_clock_div/4)
      if params:get("chord_duration_index") == 0 then
        chord_duration = chord_div
      end
    end
  )

  params:set_action("crow_clock_index",
    function(val) 
      sprocket_crow_clock:set_division(crow_clock_lookup[params:get("crow_clock_index")][1]/global_clock_div/4)
    end
  )

  params:set_action("seq_div_index_1",
    function(val) 
      sprocket_seq_1:set_division(division_names[val][1]/global_clock_div/4)
      if params:get("seq_duration_index_1") == 0 then
        seq_duration = division_names[params:get("seq_div_index_1")][1]
      end
    end
  )    

  params:set_action("crow_div_index",
    function(val) 
      crow_div = val == 0 and 0 or division_names[val][1]
      sprocket_cv_harm:set_division(val == 0 and (1/96) or division_names[val][1]/global_clock_div/4) -- 1/96 (64T) when in manual trigger mode
      if params:get("crow_duration_index") == 0 then
        if val ~= 0 then  -- if manually triggering CV harmo, don't change duration when in "Step" mode
          crow_duration = crow_div
        end
      end
    end
  )    
  
  params:set_action("chord_swing", function(val) sprocket_chord:set_swing(val) end)
  params:set_action("crow_clock_swing", function(val) sprocket_crow_clock:set_swing(val) end)
  params:set_action("seq_swing_1", function(val) sprocket_seq_1:set_swing(val) end)
  params:set_action("cv_harm_swing", function(val) sprocket_cv_harm:set_swing(val) end)


  seq_lattice = lattice:new{
    auto = true,
    ppqn = 48 -- global_clock_div -- todo not sure if we'll go with 48 or 96 yet. mostly affects swing
  }
  

  -- returns 7-bit LSB and MSB for a given number
  function get_bytes(number)
  local lsb = number % 128 -- Extract the lower 7 bits
  local msb = math.floor(number / 128) -- Shift right by 7 bits
  
  return lsb, msb
  end

  -- keep track of playing notes and decrement each pulse of lattice (whether enabled or disabled!)
  function process_notes()
    -- todo: spin up tables for active voices so new notes only check against history for the matching voice
    -- Assumes PPQN == global_clock_div. Lookup tables will need adjustments if PPQN ~= 48
    for i = #note_history, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      note_history[i].step = note_history[i].step - 1
      if note_history[i].step == 0 then
        note_history[i].player:note_off(note_history[i].note)
        table.remove(note_history, i)
      end
    end
  end


  function disable_sprockets()
    sprocket_measure.enabled = false -- should we let this sprocket's phase be advanced when pausing?
    sprocket_16th.enabled = false   -- should we let this sprocket's phase be advanced when pausing?
    sprocket_chord.enabled = false
    sprocket_crow_clock.enabled = false
    sprocket_seq_1.enabled = false
    sprocket_cv_harm.enabled = false
  end

  function enable_sprockets()
    sprocket_measure.enabled = true
    sprocket_16th.enabled = true
    sprocket_chord.enabled = true
    sprocket_crow_clock.enabled = true
    sprocket_seq_1.enabled = true
    sprocket_cv_harm.enabled = true
  end


  -- Continually-running high-resolution sprocket to process note duration/note-off
  sprocket_notes = seq_lattice:new_sprocket{
    division = 1 / (seq_lattice.ppqn * 4),
    order = 1,  -- todo ensure 1st within order
    enabled = true,
    action = function(t)
      process_notes()
    end
  }


  sprocket_16th = seq_lattice:new_sprocket{
    division = 1/16, -- SPP quantum, also used for start pre-sync
    order = 1,
    enabled = true,
    action = function(t)

      -- bits for handling transport stop (pausing sprockets and rolling back transport)
      if stop then
        -- print("DEBUG sprocket_16th processing STOP")
        -- Keep this as backup! calculate clock.sync offset arg for resuming in-phase relative to beat clock.
        -- option "b" for clock.transport.start internal clock source
        -- local ppqn = seq_lattice.ppqn
        -- pre_sync_val = (seq_lattice.transport % (ppqn * 4)) / ppqn  -- phase/beats elapsed (4/4 time)
        
        local clock_source = params:string("clock_source")
        if clock_source == "link" then
        
          -- general plan: always pause. 
          -- Start K3 or external clock start will do the "reset" stuff
          -- K1+K3 will be like Ableton's Shift+Space (resume and pickup on quantum)

          -- local link_stop_mode = "reset"
          -- local link_stop_mode = "pause"

          -- -- option A: immediate stop and reset of DS sequences irrespective of link_stop_source
          -- if link_stop_mode == "reset" then
          --   if link_stop_source == "norns" then
          --     clock.link.stop()
          --   end
          --   transport_multi_stop()   
          --   if arranger_active then
          --     print(transport_state)
          --   else
          --     reset_pattern()
          --   end
          --   transport_active = false
          --   reset_arrangement()
          --   transport_state = "stopped"
          --   stop = false
          --   link_stop_source = nil
          --   seq_lattice.transport = -1 -- probably a better place for this

          -- option B: pause
          -- elseif link_stop_mode == "pause" then
            -- if link_stop_source == "norns" then
            --   -- running this here is problematic if we're on 16/16. Ticks over to next measure.
            --   -- moving to instant-stop on K2 so we can stop link early, then DS quantizes.
            --   -- clock.link.stop()
            -- end

            -- hard stop since we can't do continue (https://github.com/monome/norns/issues/1756)
            transport_multi_stop()
            transport_active = false
            transport_state = "stopped"
            print(transport_state)
            -- link_stop_source = nil

            if arranger_active then
              reset_arrangement()
            else
              reset_pattern()
            end

            stop = false
            start = false

          -- end

          -- todo: some variation of the below for other options when stopping, e.g.
          -- option B: pause (so we can resume on Norns using K3 then trigger link start on next quantum)
          -- option C: continue playing and pause on the next division of sync quantum

          -- to pause no matter what
          -- if link_stop_source == "norns" then
            -- clock.link.stop()
            -- transport_multi_stop()
            -- transport_active = false
            -- transport_state = "paused"
            -- print(transport_state)
            -- stop = false
            -- start = false
            -- link_stop_source = nil
          
          -- -- TODO p0 this is going to be an issue re v1.3 lattice changes. Need to move link stopping elsewhere probably.
          -- -- Link clock_source with external stop. No quantization. Just resets pattern/arrangement immediately
          -- -- May also want to do this for MIDI but need to set create a link_stop_source equivalent
          -- -- todo p2 look at options for a start/continue mode for external sources that support this
          -- else -- external Link stop msg
          --   transport_multi_stop()   
          --   if arranger_active then
          --     print(transport_state)
          --   else
          --     reset_pattern()
          --   end
          --   transport_active = false
          --   reset_arrangement()
          --   transport_state = "stopped"
          --   stop = false
          -- end
        
          -- For internal, midi, and crow clock source, stop is quantized to occur at the end of the chord step.
          -- todo p1 currently a stop received from midi will result in quantized stop, unlike link. May just have it do an immediate stop for consistency
          -- todo p1 also use this when running off norns link beat_count
        elseif clock_source == "midi" then
          -- transport_multi_stop() -- won't propagate to downstream devices
          transport_active = false
          transport_state = "stopped"
          print(transport_state)
          clock_start_method = "start"

          if params:get("arranger") == 2 then
            reset_arrangement()
          else
            reset_pattern()
          end

          -- seq_lattice.transport = -1 -- something is overwriting this
          -- print("DEBUG setting transport = -1")
          stop = false
          start = false
        else -- internal and crow
          -- transport_multi_stop() -- 24-02-10 moving to K2 for immediate stop (make this an option?)
          transport_active = false
          if transport_state ~= "stopped" then -- Probably a better way of blocking this
            transport_state = "paused"
            print(transport_state)

          end
          stop = false
          start = false
        end

        -- for all clock sources, stop and pause
        -- todo: why not stop sprockets here as well (external stop?)
        
        -- -- print("a. stopping seq_lattice") -- debug stop
        -- print("transport "..string.format("%05d", (seq_lattice.transport or 0)), 
        -- "phase "..(sprocket_chord.phase or ""),
        -- "beat "..round(clock.get_beats(),2),
        -- "seq_lattice:stop")

        seq_lattice:stop()

        -- paused is handled here whereas "stopped" is handled with K2 transport control and transport start
        -- adding "stopped" condition here prevents the issue with each sprocket playing when K2 is double-tapped. 
        -- But it also looks to double-decrement transport (can be -1) which might be an issue
        -- Issue might be jumping immediately from "pausing" to "stopped"
        if transport_state == "paused" then
          disable_sprockets()

          -- roll back transport position
          -- print("Rolling back transport from " .. seq_lattice.transport .. " to " .. (seq_lattice.transport - 1))
          seq_lattice.transport = seq_lattice.transport - 1

          -------------------------------------------------
          -- Roll back this sprocket's phase which was just incremented (wrap so 0 becomes max phase)
          sprocket_16th.phase = util.wrap(sprocket_16th.phase - 1, 1, sprocket_16th.division * 4 * seq_lattice.ppqn)
          -------------------------------------------------


        elseif transport_state == "stopped" then
          -- disable sprockets, necessary when 2x K2 jumps from "pausing" directly to "stopped" or sprocket actions fire
          disable_sprockets()
          reset_sprockets("transport start")  -- 24.02.10
          -- print("debug 16th setting transport to -1")
          seq_lattice.transport = -1 -- 0 for internal?           --24.02.10
          -- print("DEBUG post-stop transport = " .. seq_lattice.transport)
          -- print("sprocket_seq_1.enabled = " .. tostring(sprocket_seq_1.enabled))

          -- currently settings to 0 in K2 transport controls section because this misses stops that occur after we're paused (only works on pausing>>stop)
          -- Will be incremented back to 0 by lattice
          -- Todo: revisit with other clock sources
          -- seq_lattice.transport = -1
          -- print("Stopped: resetting transport to -1 (will be 0)")



        end

        -- option for starting MIDI clock when in "song" (SPP) mode
      elseif start then
        -- eventually we want this to work with Link clock source, but current state prevents this (negative beat issue)
        if params:string("clock_source") == "internal" then
          if clock_start_method == "continue" then  -- if it's "start", we send a start via transport_multi_start
            if send_continue then
              -- print("DEBUG SEND_CONTINUE TRUE")
              transport_multi_continue("sprocket_measure") -- sends SPP out
              send_continue = false  -- set this so we don't keep sending SPP every 1/16th until next measure
            end
          end
        end
        -- SEND MIDI SPP AND CONTINUE MESSAGES
        --------------------------
        -- DEBUG WITH multi_start first, then continue/spp!
        -- replace with midi_continue_
        -- clock_start_method = "start"  -- "time signature based "pattern" continue on next measure"
        -- clock_start_method = "continue"  -- "time signature based "pattern" continue on next measure"
        ----------------------------

      -- -- if start == true and stop ~= true then
      --   transport_active = true
      -- -- Send out MIDI start/continue messages
      --   if clock_start_method == "start" then
      --     transport_multi_start("sprocket_measure")  
      --   else
      --     transport_multi_continue("sprocket_measure")
      --   end
      --   clock_start_method = "continue"
      --   start = false
      -- end

      end

    end,
  } 
  

  function init_sprocket_measure(div)
    sprocket_measure = seq_lattice:new_sprocket{
      action = function(t)
        -- SEND MIDI CLOCK START MESSAGES at the start of new measure for "pattern" syncing
        if start then
          transport_active = true
          transport_multi_start("sprocket_measure")
          start = false
        end

      end,
      -- div_action = function(t)  -- call action when div change is processed
      -- end,
      division = div, -- params:get("ts_numerator") / params:string("ts_denominator"),
      order = 2,
      enabled = true
    }
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time.
  init_sprocket_measure(params:get("ts_numerator") / params:string("ts_denominator"))


  function init_sprocket_chord(div)
    sprocket_chord = seq_lattice:new_sprocket{
      pre_action = function(t)  -- handle div-quantized pause and div changes
       
        if params:string("arranger") == "On" then
          arranger_ending() -- check if arranger is ending
          if chord_pattern_position >= chord_pattern_length[active_chord_pattern] then -- advance arranger
            if not arranger_one_shot_last_pattern then
              do_events_pre(arranger_padded[arranger_queue] ~= nil and arranger_queue or (arranger_position + 1 > arranger_length) and 1 or arranger_position + 1, 1)
            end
          elseif arranger_position == 0 and chord_pattern_position == 0 then  -- bodge for post-reset state
            do_events_pre(1, 1)
          else
            do_events_pre(arranger_position, chord_pattern_position + 1)
          end
        end
        
      end,
      action = function(t)
          -- get_next_chord()  -- Deprecated
          advance_chord_pattern()
        grid_dirty = true
      end,
      -- div_action = function(t)  -- call action when div change is processed
      -- end,
      division = div,
      swing = params:get("chord_swing"),
      order = 3,
      enabled = true
    }
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time.
  init_sprocket_chord(division_names[params:get("chord_div_index")][1]/global_clock_div/4)

  
  function init_sprocket_crow_clock(div)
    sprocket_crow_clock = seq_lattice:new_sprocket{
      action = function(t) 
  
        if params:get("crow_out_4") == 5 then
          crow_clock_out()
        end

      end,

      division = div,
      swing = params:get("crow_clock_swing"),
      order = 4,
      enabled = true
    } 
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time. 
  init_sprocket_crow_clock(crow_clock_lookup[params:get("crow_clock_index")][1]/global_clock_div/4)
  

  function init_sprocket_seq_1(div)
    sprocket_seq_1 = seq_lattice:new_sprocket{
      action = function(t)
        -- something like this is needed or stop during "pausing" (2x K2) will reset and play sequence again
        -- might be better to include a check in lattice since this probably affects all sprockets (including crow/harm)
        -- if transport_state == "playing" or transport_state == "pausing" then 
          local seq_start_on_1 = params:get("seq_start_on_1")
          if seq_start_on_1 == 1 then -- Seq end
            advance_seq_pattern()
            grid_dirty = true
          elseif play_seq then
            advance_seq_pattern()
            grid_dirty = true      
          end
        -- end
      end,
      -- div_action = function(t)  -- call action when div change is processed
      -- end,
      division = div,
      swing = params:get("seq_swing_1"),
      order = 5, -- WAG
      enabled = true
    } 
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time. 
  init_sprocket_seq_1(division_names[params:get("seq_div_index_1")][1]/global_clock_div/4)


  function init_sprocket_cv_harm(div)
    sprocket_cv_harm = seq_lattice:new_sprocket{
      action = function(t) 
        -- alternate mode for cv_harmonizer to ignore crow in 2 and trigger on schedule
        -- todo feature: add delay here for external sequencer race condition
        
        -- for now, this sprocket always runs but not necessarily the action. 
        -- look into disabling sprocket when not needed (not sure if downbeat and phase can be reset using cv_harm_self_sample)
        if crow_div ~= 0 then
          crow.input[1].query()
          -- cv_harm_self_sample()
        end
      end,

      division = div,
      -- div_action = function(t)  -- call action when div change is processed
      -- end,    
      swing = params:get("cv_harm_swing"),
      order = 5, -- wag
      enabled = true
    } 
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time. 

  if crow_div == 0 then
  -- when in manual trigger mode, run seq at 1/96 (64T) so we can catch div changes
    init_sprocket_cv_harm(1/96)
  else
    init_sprocket_cv_harm(division_names[params:get("crow_div_index")][1]/global_clock_div/4)
  end
  
  
  -- todo: seeing some issues with grid freezing still. I thought this would fix it but maybe lower rate further.
  grid_redraw_metro = metro.init(grid_refresh, 1/30, -1)
  grid_dirty = true
  grid_redraw_metro:start()

  -- screen refresh and blinkies
  countdown_timer = metro.init()
  countdown_timer.event = countdown
  countdown_timer.time = 0.1 -- 1/15
  countdown_timer.count = -1
  countdown_timer:start()

  -- start and reset lattice to get note durations working
  disable_sprockets()
  seq_lattice:start()
  seq_lattice:stop()
  reset_lattice("init")
  reset_arrangement()

end -- end of init


-----------------------------------------------
-- Assorted functions junkdrawer
-----------------------------------------------
  

function clone_param(id)
  if params:lookup_param(id) ~= nil then
    preview = copy(params:lookup_param(id))
    preview.action = function() end -- kill off action
  end
end


-- -- WIP thing to jump immediately to voice's param group when tapping K1. 
-- -- Needs bits to pass group id from new nb tables when page or voice is changed (enc)
-- -- todo handle based on whether group is true or false
-- -- test in alternate menu mode (mapping)
-- function hack()
--         -- if t == params.tGROUP then
--         -- build_sub(i)
--         -- m.group = true
--         -- m.groupid = i
--         -- m.groupname = params:string(i)
--         -- m.oldpos = m.pos
--         -- m.pos = 0
        

--   local group_idx = 228 --388
  
--   _menu.m.PARAMS.groupid = group_idx
--   _menu.m.PARAMS.groupname = "doubledecker"
--   -- _menu.m.PARAMS.oldpos = 14 -- need to set this so backing out of param group works as expected
  
--   -- _menu.rebuild_params(); _menu.m.PARAMS.group = true
  
--   -- recreate top-level PARAMS menu so we can use this to set oldpos for group
--   local params_page = {}
--   -- local function build_page()
--     -- params_page = {}
--     local i = 1
--     repeat
--       if params:visible(i) then 
--         -- print("inserting " .. i)
--         table.insert(params_page, i)
        
--         -- this is the good bit. Don't really need the table except to count
--         if i == group_idx then
--           _menu.m.PARAMS.oldpos = #params_page - 1 -- so backing out of param group works as expected
--           print("setting oldpos to " .. _menu.m.PARAMS.oldpos)
--         end
        
--       end
--       if params:t(i) == params.tGROUP then
--         -- print("one")
--         i = i + params:get(i) + 1
--       else
--         -- print("two")
--         i = i + 1 
--       end
--     until i > params.count
    
--     -- print("done")
--   -- end
  
--   -- build_
--   -- print("wtf")
--   -- print("page index 228 " .. params_page[1])

--   -- local function build_sub(sub)
--     -- local page = {}
--     -- for i = 1,params:get(group_idx) do
--     --   if params:visible(i + group_idx) then
--     --     table.insert(page, i + group_idx)
--     --   end
--     -- end
--   -- end
  
--   _menu.rebuild_params()
--   -- _menu.redraw()
--   -- tab.print(page)
-- end


function gen_menu()
  -- SONG MENU 
  menus[1] = {"mode", "transpose", "clock_tempo", "ts_numerator", "ts_denominator", "clock_source", "crow_out_1", "crow_out_2", "crow_out_3", "crow_out_4", "crow_clock_index", "crow_clock_swing", "dedupe_threshold", "chord_generator", "seq_generator"}
  
  -- CHORD MENU
  menus[2] = {"chord_voice", "chord_type", "chord_octave", "chord_range", "chord_max_notes", "chord_inversion", "chord_style", "chord_strum_length", "chord_timing_curve", "chord_div_index", "chord_duration_index", "chord_swing", "chord_dynamics", "chord_dynamics_ramp"}
 
  -- SEQ MENU
  menus[3] = {"seq_voice_1", "seq_note_map_1", "seq_start_on_1", "seq_reset_on_1", "seq_octave_1", "seq_rotate_1", "seq_shift_1", "seq_div_index_1", "seq_duration_index_1", "seq_swing_1", "seq_accent_1", "seq_dynamics_1", "seq_probability_1"}

  -- MIDI HARMONIZER MENU
  menus[4] = {"midi_voice", "midi_note_map", "midi_harmonizer_in_port", "midi_octave", "midi_duration_index", "midi_dynamics"}

  -- CV HARMONIZER MENU
  menus[5] = {"crow_voice", "crow_div_index", "crow_note_map", "crow_auto_rest", "crow_octave", "crow_duration_index","cv_harm_swing", "crow_dynamics"}
end


-- -- takes offset (milliseconds) input and converts to a beat-based value suitable for clock.sync offset
-- -- called by offset param action and clock.tempo_change_handler() callback
-- function ms_to_beats(ms)
--   return(ms / 1000 * clock.get_tempo() / 60)
-- end


function grid_refresh()
  if grid_dirty then
    grid_redraw()
    grid_dirty = false
  end
end

-- front-end voice selector param that dynamically serves up players to be passed to _voice_raw param:
-- 1. shortens MIDI player names to port # and voice_count (sorry, outta space!)
-- 2. only serves up valid crow cv/env options based on crow_out_ param config
function gen_voice_lookups()
  voice_param_options = {}
  voice_param_index = {}

  local vport_names = {}
  for k,v in pairs(midi.vports) do  
    vport_names[k] = v.name
  end  
  
  local function trim_menu(string)
    return util.trim_string_to_width(string, 63)
  end
  
  for i = 1, params:lookup_param("chord_voice_raw").count do
    local option = params:lookup_param("chord_voice_raw").options[i]

      -- identify connected MIDI players and rename
      if nb.players[option] ~= nil and nb.players[option].conn ~= nil then
        
        local function find_vport(name)
          for k,v in pairs(midi.vports) do
            if v.name == name then
              return k
            end
          end
        end

        local vport_name = nb.players[option].conn.name
        -- can't rely on nb.players[option].conn.device.port since nbout doesn't set this :/
        local port = find_vport(vport_name)
        local voice = string.match(option, "(%d+)$")
        local name = first_to_upper(string.lower(vport_name))
        if screen.text_extents(name) > 41 then  -- longest we can go and still append " 16.16" (port.voice)
          name = string.upper(util.acronym(name))
        end
        
        local option = name .. " " .. port .. "." .. voice
        table.insert(voice_param_options, trim_menu(option))
        table.insert(voice_param_index, i)
        
      -- mask any unwanted crow_ds players  
      elseif string.sub(option, 1, 7) == "crow_ds" then
        local length = string.len(option)
        local cv = tonumber(string.sub(option, length - 2, length - 2))
        local env = tonumber(string.sub(option, length, length))
        
        if env == 0 then
          if params:string("crow_out_"..cv) == "CV" then
            table.insert(voice_param_options, "Crow "..cv)
            table.insert(voice_param_index, i)
          end
        elseif params:string("crow_out_"..cv) == "CV" and params:string("crow_out_"..env) == "Env" then
          table.insert(voice_param_options, "Crow "..cv.."/"..env)
          table.insert(voice_param_index, i)            
        end
        
      -- other players pass through as-is
      else
        table.insert(voice_param_options, trim_menu(first_to_upper(option)))
        table.insert(voice_param_index, i)
      end
      
  end
end


-- updates voice selector options and sets (or resets) new param index after custom crow_out param changes
function update_voice_params()
  local sources = {"chord", "seq", "crow", "midi"}
  for i = 1, #sources do
    local param_string = sources[i].."_voice"
    local param_string = param_string == "seq_voice" and "seq_voice_1" or param_string
    local prev_param_name = params:string(param_string)
    params:lookup_param(param_string).options = voice_param_options
    params:lookup_param(param_string).count = #voice_param_options
    local iterations = #params:lookup_param(param_string).options + 1
    for j = 1, iterations do
      if j == iterations then
        params:set(param_string, 1)
      elseif prev_param_name == params:lookup_param(param_string).options[j] then
        params:set(param_string, j)
        break
      end
    end
  end
end


-- return first number from a string
function find_number(string)
  return tonumber(string.match (string, "%d+"))
end


-- replacement for reset_clock()?
function reset_lattice(from)
  -- print("debug reset_lattice called by " .. (from or "nil"))
  if seq_lattice.enabled then -- not sure this condition ever happens
    -- print("debug reset_lattice setting transport to -1")
    seq_lattice.transport = -1
  else
    -- print("debug reset_lattice setting transport to 0")
    seq_lattice.transport = 0
  end
  reset_sprockets("reset_lattice")
  gen_arranger_padded()
end


function reset_sprockets(from)
  -- print("b. reset_sprockets called by " .. from)
  -- seq_lattice.transport = 0  -- wag moving this elsewhere. depends on the situation
  reset_sprocket_16th("reset_sprockets")  
  reset_sprocket_measure("reset_sprockets")  
  reset_sprocket_chord("reset_sprockets")
  reset_sprocket_crow_clock("reset_sprockets")
  reset_sprocket_seq_1("reset_sprockets")
  reset_sprocket_cv_harm("reset_sprockets")
end


function reset_sprocket_16th(from)
  -- print("reset_sprocket_16th() called by " .. from)
  sprocket_16th.phase = sprocket_16th.division * seq_lattice.ppqn * 4 * (1 - sprocket_16th.delay)
  sprocket_16th.downbeat = false
end


function reset_sprocket_measure(from)
  -- print("reset_sprocket_measure() called by " .. from)
  sprocket_measure.division = params:get("ts_numerator") / params:string("ts_denominator")
  sprocket_measure.phase = sprocket_measure.division * seq_lattice.ppqn * 4 * (1 - sprocket_measure.delay)
  sprocket_measure.downbeat = false
end


function reset_sprocket_chord(from)
  -- print("reset_sprocket_chord() called by " .. from)
  sprocket_chord.division = division_names[params:get("chord_div_index")][1]/global_clock_div/4
  sprocket_chord.phase = sprocket_chord.division * seq_lattice.ppqn * 4 * (1 - sprocket_chord.delay)
  sprocket_chord.downbeat = false
end


function reset_sprocket_crow_clock(from)
  -- print("reset_sprocket_crow_clock() called by " .. from)
  sprocket_crow_clock.division = crow_clock_lookup[params:get("crow_clock_index")][1]/global_clock_div/4
  sprocket_crow_clock.phase = sprocket_crow_clock.division * seq_lattice.ppqn * 4 * (1 - sprocket_crow_clock.delay)
  sprocket_crow_clock.downbeat = false
end


function reset_sprocket_seq_1(from)
  -- print("reset_sprocket_seq_1() called by " .. from)
  sprocket_seq_1.division = division_names[params:get("seq_div_index_1")][1]/global_clock_div/4
  sprocket_seq_1.phase = sprocket_seq_1.division * seq_lattice.ppqn * 4 * (1 - sprocket_seq_1.delay)
  sprocket_seq_1.downbeat = false
end


function reset_sprocket_cv_harm(from)
  -- print("reset_sprocket_cv_harm() called by " .. from)
  sprocket_cv_harm.division = params:get("crow_div_index") == 0 and (1/96) or division_names[params:get("crow_div_index")][1]/global_clock_div/4
  sprocket_cv_harm.phase = sprocket_cv_harm.division * seq_lattice.ppqn * 4 * (1 - sprocket_cv_harm.delay)
  sprocket_cv_harm.downbeat = false
end


-- todo p3 move with other musicutil functions
function build_scale()
  notes_nums = musicutil.generate_scale_of_length(0, params:get("mode"), 7)
end
  
  --todo p3 move and can simplify by arg concats (rename pattern to active_chord_pattern)
function pattern_rotate_abs(source)
  local new_rotation_val = params:get(source)
  if source == "seq_rotate_1" then
    local offset = new_rotation_val - (current_rotation_seq or 0)
    local length = seq_pattern_length[active_seq_pattern]
    local temp_seq_pattern = {}
    for i = 1, length do
      temp_seq_pattern[i] = seq_pattern[active_seq_pattern][i]
    end
    
    for i = 1, length do
      seq_pattern[active_seq_pattern][i] = temp_seq_pattern[util.wrap(i - (offset), 1, length)]
    end
    
    current_rotation_seq = params:get(source)
    
  end
  grid_dirty = true
end


--todo p3 move and can simplify by arg concats (rename pattern to active_chord_pattern)
function pattern_shift_abs(source)
  local new_shift_val = params:get(source)
  -- print("DEBUG SHIFT", (current_shift_seq or 0), new_shift_val)
  if source == "seq_shift_1" then
    local offset = new_shift_val - (current_shift_seq or 0)
    for y = 1, max_seq_pattern_length do
      if seq_pattern[active_seq_pattern][y] ~= 0 then
        seq_pattern[active_seq_pattern][y] = util.wrap(seq_pattern[active_seq_pattern][y] + offset, 1, 14)
      end
    end    
    current_shift_seq = params:get(source)
  elseif source == "chord_shift" then
    local offset = new_shift_val - (current_shift_chord or 0)
    for y = 1, max_chord_pattern_length do
      if chord_pattern[active_chord_pattern][y] ~= 0 then
        chord_pattern[active_chord_pattern][y] = util.wrap(chord_pattern[active_chord_pattern][y] + offset, 1, 14)
      end
    end    
    current_shift_chord = params:get(source)  
  end
  grid_dirty = true
end


-- param action for xxxx_pattern_length params
function pattern_length(source)
  -- print("setting pattern length via param action")
  if source == "chord_pattern_length" then
    chord_pattern_length[active_chord_pattern] = params:get(source)
  else
    seq_pattern_length[source] = params:get("seq_pattern_length_" .. source)
  end
  grid_dirty = true
end


function div_to_index(string)
  for i = 1,#division_names do
    if tab.key(division_names[i],string) == 2 then
      return(i)
    end
  end
end


-- generate lookup table with MIDI ports being sent system clock
-- update midi_continue_n params to show in preferences
function transport_midi_update()
  midi_transport_ports = {}
  local index = 1
  for i = 1,16 do
    if params:get("clock_midi_out_" .. i) == 1 then
      midi_transport_ports[index] = {}
      midi_transport_ports[index].port = i
      midi_transport_ports[index].name = midi.vports[i].name
      index = index + 1
      params.params[params.lookup["midi_continue_" .. i]].name = midi.vports[i].name
      params:show("midi_continue_" .. i)
    else
      params.params[params.lookup["midi_continue_" .. i]].name = "midi_continue_" .. i
      params:hide("midi_continue_" .. i)
    end
  end
end


function transport_multi_start(source)
  -- print("DEBUG transport_multi_start called by " .. source)
  for i = 1, #midi_transport_ports do
    -- if transport_state == "stopped" then  -- state already updated by the time MIDI is sent out
    if clock_start_method == "start" then -- this overrides SPP
      -- print("clock_start_method == start")
      local transport_midi = midi.connect(midi_transport_ports[i].port)
      transport_midi:start()
    else
      -- print("clock_start_method == continue/nil")
      if params:string("midi_continue_" .. midi_transport_ports[i].port) == "pattern" then
        local transport_midi = midi.connect(midi_transport_ports[i].port)
        transport_midi:start()
      end
    end
  end

end


-- check which ports the global midi clock is being sent to and sends a stop message there
function transport_multi_stop()
  for i in pairs(midi_transport_ports) do  
    local transport_midi = midi.connect(midi_transport_ports[i].port)
    transport_midi:stop()
  end  
  -- print(clock.get_beats() .. ", pos " .. (seq_lattice.transport or 0).. ", phase " .. (sprocket_measure.phase or ""), "sprocket_measure action")  
end


-- check which ports the global midi clock is being sent to and sends a spp and continue message there
function transport_multi_continue(source)
  -- print("DEBUG transport_multi_continue called by " .. source)
  for i = 1, #midi_transport_ports do
    -- local port midi_transport_ports[i].port
    if params:string("midi_continue_" .. midi_transport_ports[i].port) == "song" then
      local transport_midi = midi.connect(midi_transport_ports[i].port)
      -- print("-------SENDING SPP bytes-----")
      -- print(get_bytes(seq_lattice.transport / (seq_lattice.ppqn * 4 / 16)))
      -- print("-----------------------------")
      transport_midi:song_position(get_bytes(seq_lattice.transport / (seq_lattice.ppqn * 4 / 16)))
      transport_midi:continue()
    end
  end
end


function crow_pullup(val)
  crow.ii.pullup(val == 2 and true or false)
end


-- Dump param ids to a table for dev work
function param_dump()
  param_reference = {}
  for i = 1, #params.params do 
    param_reference[i] = params.params[i].id
  end
end


function first_to_upper(str)
  return (str:gsub("^%l", string.upper))
end


function crow_clock_string(index) 
  return(crow_clock_lookup[index][2])
end


function divisions_string(index) 
  if index == 0 then return("Off") else return(division_names[index][2]) end
end

function durations_string(index) 
  if index == 0 then return("Step") else return(division_names[index][2]) end
end


function crow_trigger_string(index)
  return(index == 0 and "Crow IN 2" or division_names[index][2])
end


function chord_range_string(arg) 
  if params:get("chord_max_notes") > params:get("chord_range") then
    return(arg .. "*")
  else
    return(arg)
  end
end


function ms_string(arg)
  return(arg .. "ms")
end


function strum_length_string(arg)
    return(strum_lengths[arg][2])
end


function duration_sec(dur_mod)
  return(dur_mod/global_clock_div * clock.get_beat_sec())
end


-- todo p2 why is this firing every time grid view keys are pressed? Menu redraw inefficiency
function param_id_to_name(id)
  -- print("param_id_to_name id = " .. (id or "nil"))
  return(params.params[params.lookup[id]].name)
end


function mode_index_to_name(index)
  return(musicutil.SCALES[index].name)
end
  
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end


function t_f_string(x)
  return(x == 1 and "True" or "False")
end


function transpose_string(x)
  return(
    modes.keys[params:get("mode")][util.wrap(x, 0, 11)].key
    .. (x == 0 and "" or " ") ..  (x >= 1 and "+" or "") .. (x ~= 0 and x or "")
  )
end


function t_f_bool(x)
  return(x == 1 and true or false)
end


function neg_to_off(x)
  return(x < 0 and "Off" or x)  
end


function ten_v(x)
  return((x / 10) .. "v")
end


function mult_100_percent(x)
  return(math.floor(x * 100) .. "%")
end


function percent(x)
  return(math.floor(x) .. "%")
end


-- Establishes the threshold in seconds for considering duplicate notes as well as providing an integer for placeholder duration
function dedupe_threshold()
  local index = params:get("dedupe_threshold")
  dedupe_threshold_int = (index == 0) and 1 or division_names[index][1]
  dedupe_threshold_s = (index == 0) and 1 or duration_sec(dedupe_threshold_int) * .95
end  


-- function chord_preload(index)
--   chord_preload_tics = (index == 0) and 0 or division_names[index][1]
-- end  


function percent_chance (percent)
  return percent >= math.random(1, 100) 
end


function clear_chord_pattern()
  for i = 1, max_chord_pattern_length do
    chord_pattern[active_chord_pattern][i] = 0
  end
end


function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end


-- Callback function when system tempo changes
function clock.tempo_change_handler()  
  dedupe_threshold()  
  -- crow_clock_offset = ms_to_beats(params:get("crow_clock_offset"))
end  


-- Pads out arranger where it has 0 val segments
-- Called when selecting/deselecting Arranger segments, changing Arranger lenth via key or enc (insert/delete), switching patterns manually
function gen_arranger_padded()
  arranger_padded = {}
  
  -- First identify the first and last populated segments
  first_populated_segment = 0
  last_populated_segment = 0
  patt = nil

  -- -- todo: profile this vs the 2x pass and break
  -- for k, v in pairs(arranger) do -- no longer need to do in pairs because there are no nils
  --   if arranger[k] > 0 then
  --     if first_populated_segment == 0 then first_populated_segment = k end
  --     last_populated_segment = math.max(last_populated_segment,k)
  --   end
  -- end

  for i = 1, max_arranger_length do
    if arranger[i] > 0 then
      first_populated_segment = i
      break
    end
  end  

  for i = max_arranger_length, 1, -1 do
    if arranger[i] > 0 then
      last_populated_segment = i
      -- print("last_populated_segment = " .. last_populated_segment)
      break
    end
  end    

  arranger_length = math.max(last_populated_segment,1)
  
  -- Run this as a second loop since the above needs to iterate through all segments to update vars and set arranger_length
  for i = 1, arranger_length do
    -- First, let's handle any zeroed segments at the beginning of the sequence. Since the Arranger can be looped, we use the last populated segment where possible, then fall back on the current Pattern. Otherwise we would have a situation where the initial pattern potentially changes upon looping which is not very intuitive.
    if i < (first_populated_segment) then
      arranger_padded[i] = arranger[last_populated_segment] or active_chord_pattern
    -- From this point on, we log the current segment's pattern so it can be used to propagate the pattern, then set this on the current step.
    elseif (arranger[i] or 0) > 0 then
      patt = arranger[i]
      arranger_padded[i] = patt
    else
      arranger_padded[i] = (patt or active_chord_pattern)
    end
  end
  gen_dash("gen_arranger_padded")
end


function calc_seconds_remaining()
  if arranger_active then
    -- percent_step_elapsed = arranger_position == 0 and 0 or (math.max(clock_step,0) % chord_div / (chord_div-1)) -- todo kill chord_div?
    percent_step_elapsed = (arranger_position == 0 and 0 or sprocket_chord.phase) / (sprocket_chord.division * 4 * seq_lattice.ppqn) -- ppc
    seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - (percent_step_elapsed or 0))
  else
    seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - (steps_remaining_in_active_pattern or 0))
  end
  seconds_remaining = s_to_min_sec(math.ceil(seconds_remaining))
  end


-- 1/10s timer used to calculate arranger countdown timer and do transport/grid blinkies
function countdown()
  calc_seconds_remaining()
  fast_blinky = fast_blinky ~ 1
  grid_dirty = true -- for fast_blinky scrolling pattern indicator.
end


function refresh()
  -- refresh = refresh or -1 + 1
  -- if refresh % 3 == 0 then -- 60fps / 3 == 20 fps refresh
    redraw()  -- fuck it let's sandbag with 60fps!
  -- end 
end


function clock.transport.start(sync_value)
  -- print("clock.transport.start called with sync_value " .. (sync_value or "nil"))
  
  if transport_state == "stopped" then
    -- todo not sure if this is the best place for this (could add transport_state check to lattice.lua)
    -- lattice flips downbeat AFTER transport stop initiates sprocket resets
    -- so we always set to downbeat = false if transport is stopped
    reset_sprockets("transport start")
  end
  
  if params:get("seq_start_on_1") == 1 then -- Seq end
    play_seq = true
  end
  start = true
  stop = false -- 2023-07-19 added so when arranger stops in 1-shot and then external clock stops, it doesn't get stuck
  transport_active = true

  -- pre-sync to make sure lattice is in sync with system clock (not necessarily in phase though)
  clock.run(function()
    transport_state = "starting"
    print(transport_state)

    local clock_source = params:string("clock_source")

    -- INITIAL SYNC DEPENDING ON CLOCK SOURCE
    if clock_source == "internal" then
      -- option a: sync on next 1/16th note for SPP (1/4 of beat = 1/16th note)
      -- this will be out of phase with system beat value, but MIDI clock pulses will be synced
      clock.sync(1/4)
      
      -- keep this in case we need to switch for some reason (e.g. mods that rely on beat count)
      -- -- option b: delay sync so we're on the same phase (4/4 time sig)
      -- -- print("DEBUG PRE-SYNC BEAT " .. round(clock.get_beats(), 3))
      -- -- print("DEBUG PRE_SYNC_VAL " .. (pre_sync_val or ""))
      -- clock.sync(1, pre_sync_val or 0)
      -- -- print("DEBUG POST-SYNC BEAT " .. round(clock.get_beats(), 3))
      -- pre_sync_val = nil        
      -- -- print("post-sync clock beat " .. clock.get_beats())

      -- print("----------------------------------")
      -- print(clock.get_beats() .. ", pos " .. (seq_lattice.transport or 0).. ", phase " .. (sprocket_measure.phase or ""), "post-sync")  
    elseif clock_source == "link" then
      
      -- removing this (at least while Link is start/stop only) and moving to sprocket_16th stop
      -- print("SYNC_VALUE = " .. (sync_value or "nil"))
      -- if link_start_mode == "reset" then  -- external start signal
      --   --------------------------
      --   -- todo: make this a function and figure out how to also call it when called by external link start
      --   transport_multi_stop()
      --   if arranger_active then
      --     print(transport_state)  -- wtf is this for?
      --   else
      --     reset_pattern()
      --   end
      --   transport_active = false
      --   reset_arrangement()
      --   transport_state = "stopped"
      --   stop = false
      --   link_stop_source = nil
      --   seq_lattice.transport = 0 -- probably a better place for this
      --   --------------------------
      -- elseif link_start_mode == "resume" then  -- internal start
      --     link_start_mode = "reset"
      -- end

      print("syncing to link_quantum")
      clock.sync(params:get("link_quantum"))
    elseif clock_source == "midi" then
      clock.sync(1/24)  -- I think this makes sense for MIDI clock?
    -- elseif clock_source == "crow" then
      -- clock.sync(1/24) -- wag lol
    -- elseif sync_val ~= nil then -- indicates MIDI clock but starting from K3
      -- clock.sync(sync_val)  -- uses sync_val arg (chord_div / global_clock_div) to sync on the correct beat of an already running MIDI clock
    end
    -- end)


    -- -- Question: this was previously part of the sequence_clock loop
    -- -- should this be moved to 16th and measure sprockets?
    transport_state = "playing"
    print(transport_state)

    -- -- debug print for clock.transport.start
    -- print("transport "..string.format("%05d", (seq_lattice.transport or 0)), 
    -- "phase "..(sprocket_chord.phase or ""),
    -- "beat "..round(clock.get_beats(),2),
    -- "seq_lattice:start")

    enable_sprockets()
    seq_lattice:start()
    
  end)

end


-- only used for external clock messages. Otherwise we just set stop directly
function clock.transport.stop()
  -- print("DEBUG clock.transport.stop called")
  stop = true
end


function reset_pattern() -- todo: Also have the chord readout updated (move from advance_chord_pattern to a function)
  transport_state = "stopped"
  print(transport_state)
  pattern_queue = false
  seq_pattern_position = 0
  chord_pattern_position = 0
  reset_sprockets("reset_pattern")
  reset_lattice() -- reset_clock()
  get_next_chord()
  chord_raw = next_chord
  gen_dash("reset_pattern")
  grid_dirty = true
end


function reset_arrangement() -- todo: Also have the chord readout updated (move from advance_chord_pattern to a function)
  arranger_queue = nil
  arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
  arranger_position = 0
  if arranger[1] > 0 then set_chord_pattern(arranger[1]) end
  if params:string("arranger") == "On" then arranger_active = true end
  reset_pattern()
end


-- Used when resetting view K3 or when jumping to chord pattern immediately via g.key press
-- Link can't be reset. Sending a stop then start will just result in stopping.
function reset_external_clock()
  -- If we're sending MIDI clock out, send a stop msg
  -- Tell the transport to Start on the next sync of sequence_clock
  if transport_active then
    transport_multi_stop()
  end
  -- Tell sequence_clock to send a MIDI start/continue message after initial clock sync
  clock_start_method = "start"
  start = true
end


function advance_chord_pattern()
  local debug = true

  chord_pattern_retrig = true -- indicates when we're on a new chord seq step for CV harmonizer auto-rest logic
  local seq_start_on_1 = params:get("seq_start_on_1")
  local seq_reset_on_1 = params:get("seq_reset_on_1")
  local arrangement_reset = false

  -- Advance arranger sequence if enabled
  if params:string("arranger") == "On" then

    -- arranger_ending() moved to pre-action so this can be used for events, too
    
    -- If it's post-reset or at the end of chord sequence
    -- TODO: Really need a global var for when in a reset state (arranger_position == 0 and chord_pattern_position == 0)
    if (arranger_position == 0 and chord_pattern_position == 0) or chord_pattern_position >= chord_pattern_length[active_chord_pattern] then
      
      -- This variable is only set when the "arranger" param is "On" and we're moving into a new Arranger segment (or after reset)
      arranger_active = true
      
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        -- print("DEBUG arranger_one_shot_last_pattern")
        
        -- 24-02-13 instant stop after one-shot arranger
        -- link_stop_source = "norns"  -- obsolete?
        clock.link.stop() -- no stop quantization for sending Link stop out

        transport_multi_stop()
        -- clock.link.stop() -- no stop quantization for sending Link stop out
        -- link_stop_source = "norns"
        transport_active = false
        -- transport_state = "stopped"
        -- print(transport_state)
        -- link_stop_source = nil

        transport_active = false
        stop = false
        start = false
        seq_lattice:stop()
        disable_sprockets()
        -- end of new bits

        arrangement_reset = true
        reset_arrangement() -- also reset_pattern() >> reset_lattice
        -- stop = true
        seq_lattice.transport = -1           --24.02.15 roll back since lattice has yet to increment
      else
        -- changed from wrap to a check if incremented arranger_position exceeds seq_pattern_length
        arranger_position = arranger_padded[arranger_queue] ~= nil and arranger_queue or (arranger_position + 1 > arranger_length) and 1 or arranger_position + 1
        set_chord_pattern(arranger_padded[arranger_position])
        arranger_queue = nil
      end
      
      -- Indicates arranger has moved to new pattern.
      arranger_retrig = true
    end
    -- Flag if arranger is on the last pattern of a 1-shot sequence
    -- arranger_ending() -- moved to beginning of fn
  end

  -- If arrangement was not just reset, update chord position. 
  if arrangement_reset == false then
    if chord_pattern_position >= chord_pattern_length[active_chord_pattern] or arranger_retrig then
      if pattern_queue then
        set_chord_pattern(pattern_queue)
        pattern_queue = false
      end
      chord_pattern_position = 1
      arranger_retrig = false
    else  
      chord_pattern_position = util.wrap(chord_pattern_position + 1, 1, chord_pattern_length[active_chord_pattern])
    end

    if arranger_active then
      do_events()
      gen_dash("advance_chord_pattern")
    end
    
    local x = chord_pattern[active_chord_pattern][chord_pattern_position]

    -- Play the chord
    if x > 0 then
      update_chord(x)
      play_chord()
      if seq_reset_on_1 == 2 then -- Chord
        seq_pattern_position = 0
        -- play_seq = true
      end
      if seq_start_on_1 == 3 then -- Chord
        play_seq = true
      end
    end
    
    if seq_reset_on_1 == 1 then -- Step
      seq_pattern_position = 0
    end
    
    if seq_start_on_1 == 2 then -- Step
      play_seq = true 
    end
    
    if chord_key_count == 0 then
      chord_no = current_chord_c + ((params:get("chord_type") + 2) == 4 and 7 or 0)
      gen_chord_readout()
    end

  end
end


function arranger_ending()
  arranger_one_shot_last_pattern = 
    arranger_position >= arranger_length 
    and params:string("playback") == "1-shot"
    and (arranger_queue == nil or arranger_queue > arranger_length)
end


-- Checks each time arrange_enabled param changes to see if we need to also immediately set the corresponding arranger_active var to false. arranger_active will be false until Arranger is re-synched/resumed.
-- Also sets pattern_queue to false to clear anything previously set
function update_arranger_active()
  if params:string("arranger") == "Off" then 
    arranger_active = false
  elseif params:string("arranger") == "On" then
    if chord_pattern_position == 0 then arranger_active = true end
    pattern_queue = false
  end
  gen_dash("update_arranger_active")
end  


-- variant of do_events specifically for handling chord division changes BEFORE chord plays
-- gets passed a false arranger_pos/chord_pos for upcoming chord by sprocket
-- TODO p1 really need to optimize this by having top level "order" tables for events rather than checking each event
-- Can also block these in standard do_events (but probably catching some edge-cases (resets?) by firing chord_div_index twice)
function do_events_pre(arranger_pos,chord_pos)
  local arranger_position = arranger_pos
  local chord_pattern_position = chord_pos
  if events[arranger_position] ~= nil then
    if (events[arranger_position][chord_pattern_position].populated or 0) > 0 then
      for i = 1, 16 do
        local event_path = events[arranger_position][chord_pattern_position][i]
        if event_path ~= nil and event_path.order == 1 then
          if math.random(1, 100) <= event_path.probability then
   
            -- from here on out, same as do_events (todo consolidate or optimize)
            local event_type = event_path.event_type
            local event_name = event_path.id
            local value = event_path.operation == "Wander" and cointoss_inverse(event_path.value) or event_path.value or ""
            local limit = event_path.limit  -- can be "events_op_limit" or, for Random op, "events_op_limit_random"
            local limit_min = event_path.limit_min
            local limit_max = event_path.limit_max
            local operation = event_path.operation
            local action = event_path.action or nil
            local args = event_path.args or nil
            
            if event_type == "param" then
              if operation == "Set" then
                params:set(event_name, value)
              elseif operation == "Increment" or operation == "Wander" then
                
                if limit == "Clamp" then
                  -- issue: ideally should use a variant of clone_param() used to preview delta (make sure to write to a different table than `preview`!), clamp within limits, then set once. This way the action doesn't fire repeatedly.
                  params:delta(event_name, value) 
                  if params:get(event_name) < limit_min then
                    params:set(event_name, limit_min)
                  elseif params:get(event_name) > limit_max then
                    params:set(event_name, limit_max)
                  end
                  
                -- Wrap logic tries to maintain "expected" values for nonlinear controlspec/taper deltas:
                -- 1. If within wrap min/max, delta (but clamp if the delta would exceed limit)
                -- 2. If *at* max when event fires with positive value, wrap to min regardless of value
                -- 3. If *at* min when event fires with negative value, wrap to max regardless of value
                elseif limit == "Wrap" then
                  local reset = false
                  
                  -- positive delta
                  if value > 0 then
                    if params:get(event_name) >= limit_max then
                      reset = true
                    end
                    if reset then
                      params:set(event_name, limit_min)
                      break
                    else
                      for i = 1, value do
                        if params:get(event_name) < limit_max then
                          params:delta(event_name, 1)
                        else
                          break
                        end
                      end
                    end
                  
                  -- negative delta
                  elseif value < 0 then
                    if params:get(event_name) <= limit_min then
                      reset = true
                    end
                    if reset then
                      params:set(event_name, limit_max)
                      break
                    else
                      for i = value, -1 do
                        if params:get(event_name) > limit_min then
                          params:delta(event_name, -1)
                        else
                          break
                        end
                      end
                    end            
                  end
                  
                else
                  params:delta(event_name, value) 
                end
                
              elseif operation == "Random" then
                local param = params:lookup_param(event_name)
  
                if param.t == 1 then -- number
                  if limit == "Off" then
                    limit_min = param.min
                    limit_max = param.max
                  end
   
                  local rand = math.random(limit_min, limit_max)
                  params:set(event_name, rand)  
                  
                elseif param.t == 2 then -- options
                  if limit == "Off" then
                    limit_min = 1
                    limit_max = param.count
                  end
                  
                  local rand = math.random(limit_min, limit_max)
                  params:set(event_name, rand)  
                  
                  -- for controlspec and taper, this attempts to return an expected value, as if user had done a standard delta. Not sure it's worth the trouble but what the heck.
                elseif param.t == 3 then -- controlspec
                  limit_min = param.controlspec:unmap(limit_min or param.controlspec.minval)
                  limit_max = param.controlspec:unmap(limit_max or param.controlspec.maxval)
  
                  params:set(event_name, param.controlspec:map(quantize(random_float(limit_min, limit_max), param.controlspec.quantum)))
  
                elseif param.t == 5 then -- taper
                  limit_min = param:unmap_value(limit_min or param.min)
                  limit_max = param:unmap_value(limit_max or param.max)
  
                  params:set(event_name, param:map_value(quantize(random_float(limit_min, limit_max), param:get_delta())))
                end
              -- print("Event randomization value " .. event_name .. " to " .. params:string(event_name))
  
              -- IMPORTANT: CURRENTLY USING ADD_BINARY IN PLACE OF ADD_TRIGGER FOR PMAP SUPPORT. WILL LIKELY NEED ALTERNATE LOGIC FOR TRUE TRIGGER PARAM.
              elseif operation == "Trigger" then
                params:set(event_name, 1)
                params:set(event_name, 0)
              end
            else -- FUNCTIONS
              -- currently the only function ops are Triggers. Will likely need to expand Operation checks if there are other types.
              -- elseif operation == "Random" then
              --   if limit == "On" then
              --     local value = math.random(limit_min, limit_max)
              --     _G[event_name](value)
                  
              --     -- currently not using actions other than param actions which will fire automatically.
              --     -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
              --     if action ~= nil then
              --       _G[action](args)
              --     end                
              --   else
              --     -- todo: make sure we pick up the latest range in case it has changed since event was saved (pset load)
                  
              --     -- currently not using actions other than param actions which will fire automatically.
              --     -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
              --     if action ~= nil then
              --       _G[action](args)
              --     end                    
              --   end
              -- else
              
              -- Some function events can have faux ids that are just used to store the event
              -- Actual functions will be called as "actions" which can include extra args
              -- e.g. this allows us to use have crow_event_trigger function and the output is determined via args
              -- print("DEBUG FN TYPE" .. type(_G[event_name]))
              if type(_G[event_name]) == "function" then
                _G[event_name](value)
              end
              if action ~= nil then
                _G[action](args)
              end
              
            end
 
          end
        end
      end
    end
  end
end


function do_events()
  if events[arranger_position] ~= nil then
    if events[arranger_position][chord_pattern_position].populated or 0 > 0 then

      -- alt if we need to be strict about not double-firing order 1 events
      -- for i = 1, 16 do
        -- local event_path = events[arranger_position][chord_pattern_position][i]
        -- if event_path ~= nil and event_path.order == 2 then
        --   if math.random(1, 100) <= event_path.probability then

      for i = 1, 16 do
        local event_path = events[arranger_position][chord_pattern_position][i]
        if event_path ~= nil and math.random(1, 100) <= event_path.probability then
          local event_type = event_path.event_type
          local event_name = event_path.id
          local value = event_path.operation == "Wander" and cointoss_inverse(event_path.value) or event_path.value or ""
          local limit = event_path.limit  -- can be "events_op_limit" or, for Random op, "events_op_limit_random"
          local limit_min = event_path.limit_min
          local limit_max = event_path.limit_max
          local operation = event_path.operation
          local action = event_path.action or nil
          local args = event_path.args or nil
          
          if event_type == "param" then
            if operation == "Set" then
              params:set(event_name, value)
            elseif operation == "Increment" or operation == "Wander" then
              
              if limit == "Clamp" then
                -- issue: ideally should use a variant of clone_param() used to preview delta (make sure to write to a different table than `preview`!), clamp within limits, then set once. This way the action doesn't fire repeatedly.
                params:delta(event_name, value) 
                if params:get(event_name) < limit_min then
                  params:set(event_name, limit_min)
                elseif params:get(event_name) > limit_max then
                  params:set(event_name, limit_max)
                end
                
              -- Wrap logic tries to maintain "expected" values for nonlinear controlspec/taper deltas:
              -- 1. If within wrap min/max, delta (but clamp if the delta would exceed limit)
              -- 2. If *at* max when event fires with positive value, wrap to min regardless of value
              -- 3. If *at* min when event fires with negative value, wrap to max regardless of value
              elseif limit == "Wrap" then
                local reset = false
                
                -- positive delta
                if value > 0 then
                  if params:get(event_name) >= limit_max then
                    reset = true
                  end
                  if reset then
                    params:set(event_name, limit_min)
                    break
                  else
                    for i = 1, value do
                      if params:get(event_name) < limit_max then
                        params:delta(event_name, 1)
                      else
                        break
                      end
                    end
                  end
                
                -- negative delta
                elseif value < 0 then
                  if params:get(event_name) <= limit_min then
                    reset = true
                  end
                  if reset then
                    params:set(event_name, limit_max)
                    break
                  else
                    for i = value, -1 do
                      if params:get(event_name) > limit_min then
                        params:delta(event_name, -1)
                      else
                        break
                      end
                    end
                  end            
                end
                
              else
                params:delta(event_name, value) 
              end
              
            elseif operation == "Random" then
              local param = params:lookup_param(event_name)

              if param.t == 1 then -- number
                if limit == "Off" then
                  limit_min = param.min
                  limit_max = param.max
                end
 
                local rand = math.random(limit_min, limit_max)
                params:set(event_name, rand)  
                
              elseif param.t == 2 then -- options
                if limit == "Off" then
                  limit_min = 1
                  limit_max = param.count
                end
                
                local rand = math.random(limit_min, limit_max)
                params:set(event_name, rand)  
                
                -- for controlspec and taper, this attempts to return an expected value, as if user had done a standard delta. Not sure it's worth the trouble but what the heck.
              elseif param.t == 3 then -- controlspec
                limit_min = param.controlspec:unmap(limit_min or param.controlspec.minval)
                limit_max = param.controlspec:unmap(limit_max or param.controlspec.maxval)

                params:set(event_name, param.controlspec:map(quantize(random_float(limit_min, limit_max), param.controlspec.quantum)))

              elseif param.t == 5 then -- taper
                limit_min = param:unmap_value(limit_min or param.min)
                limit_max = param:unmap_value(limit_max or param.max)

                params:set(event_name, param:map_value(quantize(random_float(limit_min, limit_max), param:get_delta())))
              end
            -- print("Event randomization value " .. event_name .. " to " .. params:string(event_name))

            -- IMPORTANT: CURRENTLY USING ADD_BINARY IN PLACE OF ADD_TRIGGER FOR PMAP SUPPORT. WILL LIKELY NEED ALTERNATE LOGIC FOR TRUE TRIGGER PARAM.
            elseif operation == "Trigger" then
              params:set(event_name, 1)
              params:set(event_name, 0)
            end
          else -- FUNCTIONS
            -- currently the only function ops are Triggers. Will likely need to expand Operation checks if there are other types.
            -- elseif operation == "Random" then
            --   if limit == "On" then
            --     local value = math.random(limit_min, limit_max)
            --     _G[event_name](value)
                
            --     -- currently not using actions other than param actions which will fire automatically.
            --     -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
            --     if action ~= nil then
            --       _G[action](args)
            --     end                
            --   else
            --     -- todo: make sure we pick up the latest range in case it has changed since event was saved (pset load)
                
            --     -- currently not using actions other than param actions which will fire automatically.
            --     -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
            --     if action ~= nil then
            --       _G[action](args)
            --     end                    
            --   end
            -- else
            
            -- Some function events can have faux ids that are just used to store the event
            -- Actual functions will be called as "actions" which can include extra args
            -- e.g. this allows us to use have crow_event_trigger function and the output is determined via args
            -- print("DEBUG FN TYPE" .. type(_G[event_name]))
            if type(_G[event_name]) == "function" then
              _G[event_name](value)
            end
            if action ~= nil then
              _G[action](args)
            end
            
          end
        end
      end
    end
  end
end


function gen_chord_readout()
  if chord_no > 0 then
    if params:string("chord_readout") == "Degree" then
      chord_readout = chord_lookup[params:get("mode")]["chords"][chord_no]
    else -- chord name
      chord_readout = modes.keys[params:get("mode")][util.wrap(params:get("transpose"), 0, 11)][chord_no]
    end
  end
end


  -- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord.
  -- Also used for manual g.key presses while transport is stopped/paused
  -- Mode is always updated in case no chord has been set but user has changed Mode param.
function update_chord(x)
    current_chord_x = x
    current_chord_o = (x > 7) and 1 or 0
    current_chord_c = util.wrap(x, 1, 7)
    
    -- optionally: always includes 7th note since this will be used by seq, harmonizers
    chord_raw = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get("mode"), current_chord_c, true)
    
    transform_chord()
  end


-- Expands chord notes (range), inverts, and thins based on max notes
function transform_chord()
  local notes_in_chord = (params:get("chord_type") + 2)
  chord_transformed = {}

  -- This adds intervals to achieve range plus upper inversion notes in a single pass
  for i = 1, params:get("chord_range") + params:get("chord_inversion") do
    local octave = math.ceil(i / notes_in_chord) - 1
    chord_transformed[i] = chord_raw[util.wrap(i, 1, notes_in_chord)] + (i > notes_in_chord and (octave * 12) or 0)
  end
  
  -- remove lower inverted notes
  for i = 1, params:get("chord_inversion") do
    table.remove(chord_transformed, 1)
  end  
  
  -- Thin out notes in chord to not exceed params:get("chord_max_notes")
  local polyphony = params:get("chord_max_notes")
  local notes = #chord_transformed

  -- special handling for poly==1
  if polyphony == 1 then
    for i = notes, 2, -1 do
      table.remove(chord_transformed, i)
    end
  -- regular handling of thinning to match poly. todo- additional thinning algos, e.g. preserve base triad  
  elseif notes > polyphony then
    chord_thinned = er.gen(polyphony - 1, notes - 1, 0)
    for i = notes - 1, 2, -1 do
      if chord_thinned[i] == false then
        table.remove(chord_transformed, i)
      end
    end
  end
  
end


-- This triggers when mode param changes and allows seq and harmonizers to pick up the new mode immediately. Doesn't affect the chords and doesn't need chord transformations since the chord advancement will overwrite
function update_chord_action()
  chord_raw = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get("mode"), current_chord_c, true)
  next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get("mode"), next_chord_c, true)
end


-- variable curve formula from @dewb
-- x == note number * .1
-- to-do: can move upstream * 0.1 here but not sure what the implications are
function curve_get_y(x, curve)
  local curve = curve
  if curve == 0 then
    return x
  else
    return (math.exp(curve * x) - 1) / (math.exp(curve) - 1)
  end
end


-- -- Optional: variable ramp formula for velocity/amp/etc
-- function ramp(note_sequence, note_qty, velocity, ramp, elapsed, minimum, maximum)
--   local elapsed = (note_sequence - 1) / (note_qty - 1)
--   local velocity = velocity + (velocity * ramp * .01 * elapsed)
--   return(util.clamp(round(velocity), minimum, maximum))
-- end


-- todo relocate!
function to_player(player, note, dynamics, duration)
  -- todo check if note_history exists and create if not?
  -- also need to keep a list of players to run countdown functions on
  
  local note_on_time = util.time()
  player_play_note = true
  note_history_insert = true
  
  for i = 1, #note_history do
    -- Check for duplicate notes and process according to dedupe_threshold setting
    if note_history[i].player == player and note_history[i].note == note then
      
      -- Preserve longer note-off duration to avoid which-note-was-first race condition. 
      -- Ex: if a sustained chord and a staccato note play at approximately the same time, the chord's note will sustain without having to worry about order
      note_history[i].step = math.max(duration, note_history[i].step)
      note_history_insert = false -- don't insert a new note-off record since we just updated the duration

      if params:get("dedupe_threshold") > 1 and (note_on_time - note_history[i].note_on_time) < dedupe_threshold_s then
        -- print(("Deduped " .. note_on_time - note_history[i].note_on_time) .. " | " .. dedupe_threshold_s)
        player_play_note = false -- Prevent duplicate note from playing
      end
    
      -- Always update any existing note_on_time, even if a note wasn't played. 
      -- Otherwise the note duration may be extended but the gap between note_on_time and current time grows indefinitely and no dedupe occurs.
      -- Alternative is to not extend the duration when dedupe_threshold > 0 and a duplicate is found
      note_history[i].note_on_time = note_on_time
    end
  end


  -- if we're going to play a note...
  if player_play_note == true then
    
    -- existing (or updated) note duration exists
    -- MIDI/ex requires that we send a note-off for every note-on so immediately fire a note-off 
    if note_history_insert == false then
      player:note_off(note)
      
    -- no other note duration exists so insert a new note record into the history table
    else
      table.insert(note_history, {
        step = duration,
        player = player,
        note = note,
        note_on_time = note_on_time
      })
    end
  
  -- Play note
    player:note_on(note, dynamics)
  end

end


function play_chord()
  local speed = chord_div / global_clock_div * strum_lengths[params:get("chord_strum_length")][1]
  local start, finish, step -- Determine the starting and ending indices based on the direction
  local playback = params:string("chord_style")
  local note_qty = #chord_transformed
  
  if playback == "High-low" then
    start, finish, step = note_qty, 1, -1  -- Bottom to top
  else
    start, finish, step = 1, note_qty, 1   -- Top to bottom for chord or Low-high strum/arp
  end 
  
  local curve = params:get("chord_timing_curve") * .1
  -- local max_pre_scale = curve_get_y(#chord_transformed * .1, curve) -- scales across all notes
  local max_pre_scale = curve_get_y((note_qty - 1) * .1, curve) * (1/((note_qty - 1) / note_qty)) -- scales to penultimate note
  local prev_y_scaled = 0
  local y_scaled = 0
  local y_scaled_delta = 0
  local note_sequence = 0
  local player = params:lookup_param("chord_voice_raw"):get_player()


  strum_clock = clock.run(function()
    latest_strum_coroutine = coroutine.running() -- sets coroutine each time a new strum occurs
    for i = start, finish, step do

      -- Strums will interrupt one another by default. TODO p2 make this a param because overlap is p sweet
      if coroutine.running() == latest_strum_coroutine then
        local note_sequence = playback == "High-low" and (note_qty + 1 - i) or i  -- force counting upwards
        local elapsed = note_qty == 1 and 0 or (note_sequence - 1) / (note_qty - 1)
        local dynamics = params:get("chord_dynamics") * .01
        local dynamics = dynamics + (dynamics * params:get("chord_dynamics_ramp") * .01 * elapsed)
        local dynamics = util.clamp(dynamics, 0, 1) -- per destination
        local note = chord_transformed[i] + params:get("transpose") + (params:get("chord_octave") * 12) + 48
        to_player(player, note, dynamics, chord_duration)
  
        if playback ~= "Off" and note_qty ~= 1 then
          local prev_y_scaled = y_scaled
          y_scaled = curve_get_y(note_sequence * .1, curve) / max_pre_scale
          local y_scaled_delta = y_scaled - prev_y_scaled
          
          -- race-condition exists around time-based sleep method and clock.sync/lattice. Could look at using metro?
          -- Reproduce:
          -- Swing: 60%
          -- Max notes: 5
          -- Strum length 1
          -- Step length 1/2
          
          clock.sleep(clock.get_beat_sec() * speed * y_scaled_delta)
        end
        
      end
      
    end
  end)
  
  
 
end


-- Get upcoming chord. Was used for harmonizers but disabling for now..
-- Pre-load upcoming chord to address race condition around map_note() events occurring before chord change
function get_next_chord()
  local pre_arrangement_reset = false
  local pre_arranger_position = arranger_position
  local pre_arranger_retrig = arranger_retrig
  local pre_chord_pattern_position = chord_pattern_position
  local pre_pattern_queue = pattern_queue
        pre_pattern = active_chord_pattern

  -- Move arranger sequence if On
  if params:get("arranger") == 2 then

    -- If it's post-reset or at the end of chord sequence
    if (pre_arranger_position == 0 and pre_chord_pattern_position == 0) or pre_chord_pattern_position >= chord_pattern_length[pre_pattern] then
      
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        pre_arrangement_reset = true
      else
        pre_arranger_position = arranger_padded[arranger_queue] ~= nil and arranger_queue or util.wrap(pre_arranger_position + 1, 1, arranger_length)
        pre_pattern = arranger_padded[pre_arranger_position]
        
      end
      
      -- Indicates arranger has moved to new pattern.
      pre_arranger_retrig = true
    end
    
  end
  
  -- If arrangement was not just reset, update chord position. 
  if pre_arrangement_reset == false then
    if pre_chord_pattern_position >= chord_pattern_length[pre_pattern] or pre_arranger_retrig then
      if pre_pattern_queue then
        pre_pattern = pre_pattern_queue
        pre_pattern_queue = false
      end
      pre_chord_pattern_position = 1
      pre_arranger_retrig = false
    else  
      pre_chord_pattern_position = util.wrap(pre_chord_pattern_position + 1, 1, chord_pattern_length[pre_pattern])
    end
    
    -- Arranger automation step. todo: examine impact of running some events here rather than in advance_chord_pattern
    -- Could be important for anything that changes patterns but might also be weird for grid redraw

    -- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord. 
    -- Mode is always updated in case no chord has been set but user has changed Mode param.
    -- todo p3 efficiency test vs if/then
      next_chord_x = chord_pattern[pre_pattern][pre_chord_pattern_position] > 0 and chord_pattern[pre_pattern][pre_chord_pattern_position] or next_chord_x
      next_chord_o = chord_pattern[pre_pattern][pre_chord_pattern_position] > 0 and (chord_pattern[pre_pattern][pre_chord_pattern_position] > 7 and 1 or 0) or next_chord_o
      next_chord_c = chord_pattern[pre_pattern][pre_chord_pattern_position] > 0 and util.wrap(chord_pattern[pre_pattern][pre_chord_pattern_position], 1, 7) or next_chord_c
      next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get("mode"), next_chord_c, true)
    
  end
end


function map_note_1(note_num, octave)-- , pre) -- triad chord mapping
  local chord_length = 3
  -- local quantized_note = pre == true and next_chord[util.wrap(note_num, 1, chord_length)] or chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_note = chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("transpose"))
end


function map_note_2(note_num, octave) --, pre) -- 7th chord mapping
  local chord_length = 4
  -- local quantized_note = pre == true and next_chord[util.wrap(note_num, 1, chord_length)] or chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_note = chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("transpose"))
end


function map_note_3(note_num, octave) --, pre)  -- mode mapping + diatonic transposition
  -- local diatonic_transpose = (math.max(pre == true and next_chord_x or current_chord_x, 1)) -1
  local diatonic_transpose = (math.max(current_chord_x, 1)) -1
  local note_num = note_num + diatonic_transpose
  local quantized_note = notes_nums[util.wrap(note_num, 1, 7)] + (math.floor((note_num -1) / 7) * 12)
  return(quantized_note + (octave * 12) + params:get("transpose"))
end


function map_note_4(note_num, octave) -- mode mapping
  local note_num = note_num
  local quantized_note = notes_nums[util.wrap(note_num, 1, 7)] + (math.floor((note_num -1) / 7) * 12)
  return(quantized_note + (octave * 12) + params:get("transpose"))
end

function map_note_5(note_num, octave) -- chromatic mapping
  return(note_num -1 + (octave * 12) + params:get("transpose"))
end


function advance_seq_pattern()
  if seq_pattern_position > seq_pattern_length[active_seq_pattern] or arranger_retrig == true then
    seq_pattern_position = 1
  else
    seq_pattern_position = util.wrap(seq_pattern_position + 1, 1, seq_pattern_length[active_seq_pattern])
  end

  local x = seq_pattern[active_seq_pattern][seq_pattern_position]
  if x > 0 and math.random(1, 100) <= params:get("seq_probability_1") then
    -- shared with g.key except for dynamics accent bit. Could consolidate
    local player = params:lookup_param("seq_voice_raw_1"):get_player()
    local dynamics = (params:get("seq_dynamics_1") * .01)
    local dynamics = dynamics + (dynamics * (sprocket_seq_1.downbeat and (params:get("seq_accent_1") * .01) or 0))
    local note = _G["map_note_" .. params:get("seq_note_map_1")](x, params:get("seq_octave_1")) + 36
    to_player(player, note, dynamics, seq_duration)
  end
  
  if seq_pattern_position >= seq_pattern_length[active_seq_pattern] then
    local seq_start_on_1 = params:get("seq_start_on_1")
    if seq_start_on_1 ~= 1 then -- seq end
      play_seq = false
      -- if seq_start_on_1 == 4 then -- Only reset if we're currently in Event start_on mode. Could go either way here.
      --   seq_1_shot_1 = false
      -- end
    end
  end
end


function crow_clock_out()
  crow.output[4].volts = 10
  clock.run(function()
    local swing_mod = sprocket_crow_clock.downbeat 
      and (2 - (2 * sprocket_crow_clock.swing / 100)) 
      or (2 * sprocket_crow_clock.swing / 100)
    clock.sleep(120/(clock.get_tempo()/(sprocket_crow_clock.division * swing_mod))) -- could also pass division
    crow.output[4].volts = 0
  end)
end


-- cv harmonizer input
function sample_crow(volts)
  -- local note = _G["map_note_" .. params:get("crow_note_map")](round(volts * 12, 0) + 1, params:get("crow_octave"), params:get("chord_preload") ~= 0) + 36
  local note = _G["map_note_" .. params:get("crow_note_map")](round(volts * 12, 0) + 1, params:get("crow_octave")) + 36
  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_pattern_retrig == true
  or params:get("crow_auto_rest") == 1
  or (params:get("crow_auto_rest") == 2 and (prev_note ~= note)) then
    -- Play the note
    
    local player = params:lookup_param("crow_voice_raw"):get_player()
    local dynamics = params:get("crow_dynamics") * .01

    to_player(player, note, dynamics, crow_duration)
    
  end
  
  prev_note = note
  chord_pattern_retrig = false -- Resets at chord advance
end


--midi harmonizer input
midi_event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then

    -- local note = _G["map_note_" .. params:get("midi_note_map")](d.note - 35, params:get("midi_octave"), params:get("chord_preload") ~= 0) + 36 -- todo p1 octave validation for all sources
    local note = _G["map_note_" .. params:get("midi_note_map")](d.note - 35, params:get("midi_octave")) + 36 -- todo p1 octave validation for all sources

    local player = params:lookup_param("midi_voice_raw"):get_player()
    local dynamics = params:get("midi_dynamics") * .01 -- todo p1 velocity passthru (normalize to 0-1)

    to_player(player, note, dynamics, midi_duration)
    
  end
end


--todo p2 check with Trent to see if there is a calc we can use rather than the regression
function est_jf_time()
  crow.ii.jf.get ("time") --populates jf_time global
  
  jf_time_hold = clock.run(
    function()
      clock.sleep(0.005) -- a small hold for usb round-trip
      local jf_time_s = math.exp(-0.694351 * jf_time + 3.0838) -- jf_time_v_to_s.
      print("jf_time_s = " .. jf_time_s)
      -- return(jf_time_s)   
      end
  )
end


function grid_redraw()
  g:all(0)
  
  -- Events supercedes other views
  if screen_view_name == "Events" then

  -- Draw grid with 16 event lanes (columns) for each step in the selected pattern
    local length = chord_pattern_length[arranger_padded[event_edit_segment]] or 0
    for x = 1, 16 do -- event lanes
      for y = 1, rows do -- pattern steps
        local led = events[event_edit_segment][y + pattern_grid_offset][x] ~= nil and 7 or (y + pattern_grid_offset > length and 0 or 2)

        if length > rows - pattern_grid_offset 
        and length - pattern_grid_offset > rows 
        and y == rows then
          g:led(x, y, led + (fast_blinky))
        elseif pattern_grid_offset > 0 and y == 1 then 
          g:led(x, y, led + (fast_blinky))
        elseif y + pattern_grid_offset == event_edit_step and x == event_edit_lane then
          g:led(x, y, 15)
        else
          g:led(x, y, led)
        end
        
      end
    end    
  else
    for i = 6, 8 do
      g:led(16, i + extra_rows, 4)
    end
    
    for i = 1, #grid_view_keys do
      g:led(16, grid_view_keys[i] + extra_rows , 7)
    end  
    
    -- ARRANGER GRID REDRAW
    if grid_view_name == "Arranger" then
      g:led(16, 6 + extra_rows, 15)
      
      
      ----------------------------------------------------------------------------
      -- Arranger shifting rework here
      ----------------------------------------------------------------------------
      if arranger_loop_key_count > 0 then
        x_draw_shift = 0
        local in_bounds = event_edit_segment <= arranger_length -- some weird stuff needs to be handled if user is shifting events past the end of the pattern length
        if d_cuml >= 0 then -- Shifting arranger pattern to the right and opening up this many segments between event_edit_segment and event_edit_segment + d_cuml
   
        ------------------------------------------------
        -- positive d_cuml shifts arranger to the right and opens a gap
        ------------------------------------------------
        -- x_offsets fall into 3 groups:
        --  >= event_edit_segment + d_cuml will shift to the right by d_cuml segments
        --  < event_edit_segment draw as usual
        --  Remaining are in the "gap" and we need to grab the previous pattern and repeat it
          for x = 16, 1, -1 do -- draw from right to left
            local x_offset = x + arranger_grid_offset -- Grid x + the offset for whatever page or E1 shift is happening

            for y = 1,4 do
              g:led(x, y, x_offset == arranger_position and 6                                               -- playhead
                or x_offset == arranger_queue and 4                                                             -- queued
                or x_offset <= (arranger_length + (in_bounds and d_cuml or 0)) and 2                       -- seq length
                or 0)
            end
            
            -- group 1.
            if x_offset >= event_edit_segment + d_cuml then
              local x_offset = x_offset - d_cuml
              for y = 1,4 do -- patterns
                if in_bounds then
                  if y == arranger_padded[x_offset] then g:led(x, y, x_offset == arranger_position and 9 or 7) end -- dim padded segments
                end
                if y == arranger[x_offset] then g:led(x, y, 15) end -- regular segments
              end
              g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_length and 3 or 7) -- events
              
            elseif x_offset < event_edit_segment then
              for y = 1,4 do -- patterns
                if y == arranger_padded[x_offset] then g:led(x, y, x_offset == arranger_position and 9 or 7) end -- dim padded segments
                if y == arranger[x_offset] then g:led(x, y, 15) end -- regular segments
              end
              -- if x == 3 then print("2") end
              g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_length and 3 or 7) -- events
              
            else
              -- no need to do anything with patterns if extending beyond arranger_length
              -- can still move around events beyond
              if in_bounds then
                local pattern_padded = arranger_padded[math.max(event_edit_segment - 1, 1)]
                for y = 1,4 do -- patterns
                  if y == pattern_padded then g:led(x, y, x_offset == arranger_position and 9 or 7) end
                end
                g:led(x, 5, 7)
              else
                g:led(x, 5, 3)
              end
            end
          end  
            
        
        ------------------------------------------------
        -- negative d_cuml shifts arranger to the left
        ------------------------------------------------
        -- x_offsets fall into 2 groups:
        --  >= event_edit_segment + d_cuml will shift to the left by d_cuml segments
        --  < event_edit_segment + d_cuml are drawn as usual
        else
          for x = 1, 16 do
            local x_offset = x + arranger_grid_offset -- Grid x + the offset for whatever page or E1 shift is happening
            
            -- draw playhead, arranger_queue, adjusted sequence length, blanks
            if in_bounds then
              for y = 1,4 do 
                g:led(x, y, x_offset == arranger_position and 6                                             -- playhead
                  or x_offset == arranger_queue and 4                                                           -- queued
                  or x_offset <= (arranger_length + d_cuml) and 2                                           -- seq length
                  or 0)                                    
              end
            else
              for y = 1,4 do
                g:led(x, y, x_offset == arranger_position and 6                                             -- playhead
                  or x_offset == arranger_queue and 4                                                           -- queued
                  or x_offset <= arranger_length and x_offset < (d_cuml + event_edit_segment) and 2         -- seq length
                  or 0)
              end              
            end  

            -- Redefine x_offset only for group #1: patterns that need to be shifted left. Group 2 will be handled as usual
            local x_offset = (x_offset >= event_edit_segment + d_cuml) and (x_offset - d_cuml) or x_offset
            for y = 1,4 do -- patterns
              if y == arranger_padded[x_offset] then g:led(x, y, x_offset == arranger_position and 9 or 7) end -- dim padded segments
              if y == arranger[x_offset] then g:led(x, y, 15) end -- regular segments
            end
            g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_length and 3 or 7) -- events
          end -- of drawing for negative d_cuml shift              
        end
      
      else -- arranger_loop_key_count == 0: no arranger shifting
        for x = 1, 16 do
          local x_offset = x + arranger_grid_offset
          for y = 1,4 do
            g:led(x,y, x_offset == arranger_position and 6 or x_offset == arranger_queue and 4 or x_offset <= arranger_length and 2 or 0)
            if y == arranger_padded[x_offset] then g:led(x, y, x_offset == arranger_position and 9 or 7) end
            if y == arranger[x_offset] then g:led(x, y, 15) end
          end
          -- Events strip
          g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_length and 3 or 7)
        end
      end
  

      g:led(1, 8 + extra_rows, params:get("arranger") == 2 and 15 or 4)
      g:led(2, 8 + extra_rows, params:get("playback") == 2 and 15 or 4)
        
      -- More sophisticated pagination with scroll indicator for arranger grid view
      -- for i = 0,3 do
      --   local target = i * 16
      --   g:led(i + 7, 8 , math.max(10 + util.round((math.min(target, arranger_grid_offset) - math.max(target, arranger_grid_offset))/2), 2) + 2)
      -- end
      for i = 7, 10 do
        g:led(i, 8 + extra_rows, 4)
      end
      
      if arranger_grid_offset == 0 then g:led(7, 8 + extra_rows, 15)
      elseif arranger_grid_offset == 16 then g:led(8, 8 + extra_rows, 15)    
      elseif arranger_grid_offset == 32 then g:led(9, 8 + extra_rows, 15)
      elseif arranger_grid_offset == 48 then g:led(10, 8 + extra_rows, 15)
      end  
      
      
    -- CHORD GRID REDRAW  
    elseif grid_view_name == "Chord" then
      if params:string("arranger") == "On" and arranger_one_shot_last_pattern == false then
        next_pattern_indicator = arranger_padded[util.wrap(arranger_position + 1, 1, arranger_length)]
      else
        next_pattern_indicator = pattern_queue or active_chord_pattern
      end
      
      -- chord pattern selector leds
      for i = 1, 4 do
        g:led(16, i, i == next_pattern_indicator and 7 or pattern_keys[i] and 7 or 3) 
        if i == active_chord_pattern then
          g:led(16, i, 15)
        end
      end
      
      g:led(16, 7 + extra_rows, 15) -- grid view selector
      
      -- chord playhead
      local chord_pattern_position_offset = chord_pattern_position - pattern_grid_offset
      -- fix for Midigrid which was breaking when drawing out-of-bounds. should no longer be strictly necessary AFAIK
      -- if chord_pattern_position_offset > 0 and chord_pattern_position_offset <= rows then
        for i = 1, 14 do                                                               
          g:led(i, chord_pattern_position - pattern_grid_offset, 3)
        end
      -- end
      
      local length = chord_pattern_length[active_chord_pattern]
      for i = 1, rows do
      -- pattern_length LEDs
      -- if length > rows - pattern_grid_offset then
        if length - pattern_grid_offset > rows and i == rows then
          g:led(15, i, (length < (i + pattern_grid_offset) and 4 or 15 - (fast_blinky * 2)))
        elseif pattern_grid_offset > 0 and i == 1 then 
          g:led(15, i, (length < (i + pattern_grid_offset) and (4 + (fast_blinky)) or (15 - (fast_blinky * 2))))
        else  
          g:led(15, i, length < (i + pattern_grid_offset) and 4 or 15)
        end
        
        -- sequence pattern LEDs off/on
        if chord_pattern[active_chord_pattern][i + pattern_grid_offset] > 0 then
          g:led(chord_pattern[active_chord_pattern][i + pattern_grid_offset], i, 15)
        end
      end
      
      
    -- SEQ GRID REDRAW  
    elseif grid_view_name == "Seq" then
      g:led(16, 8 + extra_rows, 15)
      
      -- seq playhead
      local seq_pattern_position_offset = seq_pattern_position - pattern_grid_offset
      -- fix for Midigrid which was breaking when drawing out-of-bounds. todo: check if this is still necessary
      -- if seq_pattern_position_offset > 0 and seq_pattern_position_offset <= rows then
        for i = 1, 14 do                                                               
          g:led(i, seq_pattern_position - pattern_grid_offset, 3)
        end
      -- end
      
      local length = seq_pattern_length[active_seq_pattern]
      for i = 1, rows do
        
        -- pattern_length LEDs
        -- if length > rows - pattern_grid_offset then
          if length - pattern_grid_offset > rows and i == rows then 
            g:led(15, i, (length < (i + pattern_grid_offset) and 4 or 15 - (fast_blinky * 2)))
          elseif pattern_grid_offset > 0 and i == 1 then 
            g:led(15, i, (length < (i + pattern_grid_offset) and (4 + (fast_blinky)) or (15 - (fast_blinky * 2))))
          else  
            g:led(15, i, length < (i + pattern_grid_offset) and 4 or 15)
          end
          
        -- sequence pattern LEDs off/on
        if seq_pattern[active_seq_pattern][i + pattern_grid_offset] > 0 then
          g:led(seq_pattern[active_seq_pattern][i + pattern_grid_offset], i, 15)
        end
      end
    end
  end
  g:refresh()
end


-- GRID KEYS
-- todo p1 put in some top level checks so we can break this up into functions or something navigatable
---@diagnostic disable-next-line: duplicate-set-field
function g.key(x,y,z)
  if z == 1 then

    if screen_view_name == "Events" then
      -- Setting of events past the pattern length is permitted
      event_key_count = event_key_count + 1
      
        -- function g.key events loading
        -- First touched event is the one we edit, effectively resetting on key_count = 0
        if event_key_count == 1 then
          event_edit_step = y + pattern_grid_offset
          event_edit_lane = x
          event_saved = false

          local events_path = events[event_edit_segment][y + pattern_grid_offset][x]
          if events[event_edit_segment][y + pattern_grid_offset][x] == nil then
            event_edit_status = "(New)"
            -- print("setting event_edit_status to " .. event_edit_status)
          else
            event_edit_status = "(Saved)"
            -- print("setting event_edit_status to " .. event_edit_status)
          end

          -- If the event is populated, Load the Event vars back to the displayed param. Otherwise keep the last touched event's settings so we can iterate quickly.
          if events[event_edit_segment][y + pattern_grid_offset][x] ~= nil then
            
            events_index = 1
            selected_events_menu = events_menus[events_index]

            local id = events_path.id
            local index = events_lookup_index[id]
            local value = events_path.value
            local operation = events_path.operation
            local limit = events_path.limit or "Off"

            params:set("event_category", param_option_to_index("event_category", events_lookup[index].category))
            change_category()
            
            params:set("event_subcategory", param_option_to_index("event_subcategory", events_lookup[index].subcategory))
            change_subcategory()
            
            params:set("event_name", index)
            change_event()
            
            params:set("event_operation", param_option_to_index("event_operation", operation))
            change_operation("g.key") -- 2024-03-28 added to update prev_operation in called function
            if operation == "Random" then
              params:set("event_op_limit_random", param_option_to_index("event_op_limit_random", limit))
            else
              params:set("event_op_limit", param_option_to_index("event_op_limit", limit))
            end
            if limit ~= "Off" then
              params:set("event_op_limit_min", events_path.limit_min)
              params:set("event_op_limit_max", events_path.limit_max)
            end
            if value ~= nil then params:set("event_value", value) end -- triggers don't save
            params:set("event_probability", events_path.probability)
          end
          gen_menu_events()
          event_edit_active = true
          
        else -- Subsequent keys down paste event
          local events_path = events[event_edit_segment][y + pattern_grid_offset][x]
          -- But first check if the events we're working with are populated
          local og_event_populated = events[event_edit_segment][y + pattern_grid_offset][x] ~= nil
          local copied_event_populated = events[event_edit_segment][event_edit_step][event_edit_lane] ~= nil

          -- Then copy
          events[event_edit_segment][y + pattern_grid_offset][x] = deepcopy(events[event_edit_segment][event_edit_step][event_edit_lane])
          
          -- Adjust populated events count at the step level. todo: also set at the segment level once implemented
          if og_event_populated and not copied_event_populated then
            events[event_edit_segment][y + pattern_grid_offset].populated = events[event_edit_segment][y + pattern_grid_offset].populated - 1
            
            -- If the step's new populated count == 0, decrement count of populated event STEPS in the segment
            if (events[event_edit_segment][y + pattern_grid_offset].populated or 0) == 0 then 
              events[event_edit_segment].populated = (events[event_edit_segment].populated or 0) - 1
            end
          elseif not og_event_populated and copied_event_populated then
            events[event_edit_segment][y + pattern_grid_offset].populated = (events[event_edit_segment][y + pattern_grid_offset].populated or 0) + 1

            -- If this is the first event to be added to this step, increment count of populated event STEPS in the segment
            if (events[event_edit_segment][y + pattern_grid_offset].populated or 0) == 1 then
              -- print("incrementing segment populated")
              events[event_edit_segment].populated = (events[event_edit_segment].populated or 0) + 1
            end
          end
          
          print("Copy+paste event from segment " .. event_edit_segment .. "." .. event_edit_step .. " lane " .. event_edit_lane  .. " to " .. event_edit_segment .. "." .. (y + pattern_grid_offset) .. " lane " .. x)
        end

    -- view_key buttons  
    elseif x == 16 and y > 5 + extra_rows then
      if interaction == nil then  -- interactions block view switching
        view_key_count = view_key_count + 1
        pattern_grid_offset = 0
        
        -- following lines cancel any pending pattern changes by acting as if a copy was just performed (overrides)
        -- pattern_key_count = 0
        -- pattern_copy_performed = true
        
        table.insert(grid_view_keys, y - extra_rows)
        if view_key_count == 1 then
          grid_view_name = grid_views[y - extra_rows - 5]
        elseif view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
          screen_view_name = "Chord+seq"
        end
      end
      
    --ARRANGER KEY DOWN-------------------------------------------------------
    elseif grid_view_name == "Arranger" then
      local x_offset = x + arranger_grid_offset

      -- enable/disable Arranger
      if x == 1 and y == 8 + extra_rows then
        if params:get("arranger") == 1 then
          params:set("arranger", 2)
        else
          params:set("arranger", 1)
        end

      -- Switch between Arranger playback Loop or 1-shot mode
      elseif x == 2 and y == 8 + extra_rows then
        if params:get("playback") == 2 then
          params:set("playback", 1)
        else
          params:set("playback", 2)
        end
        
      -- Arranger pagination jumps
      elseif y == 8 + extra_rows then
        if x > 6 and x < 11 then
          arranger_grid_offset = (x - 7) * 16
        end
        
      
      -- ARRANGER SEGMENT CHORD PATTERNS
      elseif y < 5 and interaction ~= "arranger_shift" then
        if y == arranger[x_offset] then
          arranger[x_offset] = 0
        else
          arranger[x_offset] = y
        end
        gen_arranger_padded()
        
        -- allow pasting of events while setting patterns (but not the other way around)
        if interaction == "event_copy" then
          events[x_offset] = deepcopy(events[event_edit_segment])
          print("Copy+paste events from segment " .. event_edit_segment .. " to segment " .. x)
          gen_dash("Event copy+paste")
        end
        
      -- ARRANGER EVENTS TIMELINE KEY DOWN
      elseif y == 5 then
        arranger_loop_key_count = arranger_loop_key_count + 1
        if interaction ~= "arranger_shift" then -- nil then
          interaction = "event_copy"  
          -- First touched pattern is the one we edit, effectively resetting on key_count = 0
          if arranger_loop_key_count == 1 then
            event_edit_segment = x_offset
  
          -- Subsequent keys down paste all arranger events in segment, but not the segment pattern
          -- arranger shift interaction will block this
          -- implicit here that more than 1 key is held down so we're pasting
          else
            events[x_offset] = deepcopy(events[event_edit_segment])
            print("Copy+paste events from segment " .. event_edit_segment .. " to segment " .. x)
            gen_dash("Event copy+paste")
          end
        end
      end
      
    --CHORD PATTERN KEYS
    elseif grid_view_name == "Chord" then

      if x < 15 then
        chord_key_count = chord_key_count + 1
        if x == chord_pattern[active_chord_pattern][y + pattern_grid_offset] then
          chord_pattern[active_chord_pattern][y + pattern_grid_offset] = 0
        else
          chord_pattern[active_chord_pattern][y + pattern_grid_offset] = x
          
          -- -- option A:
          -- -- plays Chord when pressing on a blank Grid key
          -- if transport_state == "stopped" or transport_state == "paused" then
          --   update_chord(x)
          --   play_chord()
          -- end

        end

        chord_no = util.wrap(x, 1, 7) + ((params:get("chord_type") + 2) == 4 and 7 or 0) -- or 0
        gen_chord_readout()

        -- -- option B:
        -- plays Chord when pressing on any Grid key (even turning chord off)
        if transport_state == "stopped" or transport_state == "paused" then
          update_chord(x)
          play_chord()
        end

      -- set chord_pattern_length  
      elseif x == 15 then
        params:set("chord_pattern_length", y + pattern_grid_offset)
        gen_dash("g.key chord_pattern_length")
      

      elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher.
        interaction = "chord_pattern_copy"
        pattern_key_count = pattern_key_count + 1
        pattern_keys[y] = 1
        if pattern_key_count == 1 then
          pattern_copy_source = y
        elseif pattern_key_count > 1 then
          print("Copying pattern " .. pattern_copy_source .. " to pattern " .. y)
          pattern_copy_performed = true
          for i = 1, max_chord_pattern_length do
            chord_pattern[y][i] = chord_pattern[pattern_copy_source][i]
          end
          -- If we're pasting to the currently viewed active_chord_pattern, do it via param so we update param + table.
          if y == active_chord_pattern then
            params:set("chord_pattern_length", chord_pattern_length[pattern_copy_source])
          -- Otherwise just update the table.
          else
            chord_pattern_length[y] = chord_pattern_length[pattern_copy_source]
          end
        end
      end
      
      if transport_active == false then -- Pre-load chord for when play starts
        get_next_chord()
        chord_raw = next_chord
      end
      
    -- SEQ PATTERN KEYS
    elseif grid_view_name == "Seq" then
      if x < 15 then
        if x == seq_pattern[active_seq_pattern][y + pattern_grid_offset] then
          seq_pattern[active_seq_pattern][y + pattern_grid_offset] = 0
        else
          seq_pattern[active_seq_pattern][y + pattern_grid_offset] = x

          -- -- option A:
          -- -- plays note when pressing on a blank Grid key
          -- -- mostly shared with advance_seq. could be consolidated into one fn
          -- if transport_state == "stopped" or transport_state == "paused" then
          --   local player = params:lookup_param("seq_voice_raw_1"):get_player()
          --   local dynamics = (params:get("seq_dynamics_1") * .01)
          --   -- local dynamics = dynamics + (dynamics * (sprocket_seq_1.downbeat and (params:get("seq_accent_1") * .01) or 0))
          --   local note = _G["map_note_" .. params:get("seq_note_map_1")](x, params:get("seq_octave_1")) + 36
          --   to_player(player, note, dynamics, seq_duration)
          -- end

        end

        -- -- option B:
        -- plays note when pressing on any Grid key (even turning note off)
        -- mostly shared with advance_seq. could be consolidated into one fn
        if transport_state == "stopped" or transport_state == "paused" then
          local player = params:lookup_param("seq_voice_raw_1"):get_player()
          local dynamics = (params:get("seq_dynamics_1") * .01)
          -- local dynamics = dynamics + (dynamics * (sprocket_seq_1.downbeat and (params:get("seq_accent_1") * .01) or 0))
          local note = _G["map_note_" .. params:get("seq_note_map_1")](x, params:get("seq_octave_1")) + 36
          to_player(player, note, dynamics, seq_duration)
        end

      elseif x == 15 then
        params:set("seq_pattern_length_" .. active_seq_pattern, y + pattern_grid_offset)
      end
    end
    
  --------------
  --G.KEY RELEASED
  --------------
  elseif z == 0 then
    -- Events key up
    if screen_view_name == "Events" then
      event_key_count = math.max(event_key_count - 1,0)
      
      -- Reset event_edit_step/lane when last key is released (if it was skipped when doing a K3 save to allow for copy+paste)
      if event_key_count == 0 and event_saved then
        event_edit_step = 0
        event_edit_lane = 0
      end

    -- view_key buttons
    elseif x == 16 and y > 5 then
      view_key_count = math.max(view_key_count - 1, 0)
      table.remove(grid_view_keys, tab.key(grid_view_keys, y))
      if view_key_count > 0 then
        grid_view_name = grid_views[grid_view_keys[1] - 5]
        
        if view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
          screen_view_name = "Chord+seq"
        else
          screen_view_name = "Session"  
        end
      else
        screen_view_name = "Session"
      end

    -- Chord key up      
    elseif grid_view_name == "Chord" then
      if x == 16 then
        if y <5 then
          pattern_key_count = math.max(pattern_key_count - 1,0)
          pattern_keys[y] = nil
          if pattern_key_count == 0 and pattern_copy_performed == false then
            
            -- Resets current active_chord_pattern immediately if transport is stopped
            if y == active_chord_pattern and transport_active == false then
              print("Manual reset of current pattern; disabling arranger")
              params:set("arranger", 1)
              pattern_queue = false
              -- seq_pattern_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
              chord_pattern_position = 0
              reset_external_clock()
              reset_pattern()
              -- tells dash to show RST rather than 1.0
              if arranger_position == 1 and chord_pattern_position == 0 then
                reset_arrangement()
              end
              
            -- Manual jump to queued pattern  
            elseif y == pattern_queue and transport_active == false then
              print("Manual jump to queued pattern")
              
              pattern_queue = false
              set_chord_pattern(y)
              seq_pattern_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
              chord_pattern_position = 0
              reset_external_clock()
              reset_pattern() -- todo needs to calculate new transport- not just reset pattern!
  
            -- Cue up a new pattern        
            else 
              print("New pattern queued; disabling arranger")
              if pattern_copy_performed == false then
                pattern_queue = y
                params:set("arranger", 1)
              end
            end
          end
        end
        if pattern_key_count == 0 then
          -- print("resetting pattern_copy_performed to false")
          pattern_copy_performed = false
          interaction = nil
        end  
      elseif x < 15 then
        chord_key_count = chord_key_count - 1
        if chord_key_count == 0 then
          -- This reverts the chord readout to the currently loaded chord but it is kinda confusing when paused so now it just wipes and refreshes at the next chord step. Could probably be improved todo p2
          -- chord_no = current_chord_c + ((params:get("chord_type") + 2) == 4 and 7 or 0)          
          -- gen_chord_readout()
          chord_no = 0
        end
      end
    
    
    -- ARRANGER KEY UP
    elseif grid_view_name == "Arranger" then
      local x_offset = x + arranger_grid_offset -- currently only used 
      
      -- ARRANGER EVENTS TIMELINE KEY UP
      if y == 5 then
        arranger_loop_key_count = math.max(arranger_loop_key_count - 1, 0)
        
        -- Insert/remove patterns/events after arranger shift with K3
        if arranger_loop_key_count == 0 then
          if interaction == "arranger_shift" then
            apply_arranger_shift()
          end
          interaction = nil
        end
      end
    end

  end
  -- screen_dirty = true -- redraw()
  grid_dirty = true
end


-- todo p3 relocated
function apply_arranger_shift()
  if d_cuml > 0 then  -- same as interaction == "arranger_shift"? todo p2 clean up anywhere this check is used
    for i = 1, d_cuml do
      table.insert(arranger, event_edit_segment, 0)
      table.remove(arranger, max_arranger_length + 1)
      table.insert(events, event_edit_segment, nil)
      events[event_edit_segment] = {{},{},{},{},{},{},{},{}}
      table.remove(events, max_arranger_length + 1)
    end
    gen_arranger_padded()
    d_cuml = 0

  elseif d_cuml < 0 then
    for i = 1, math.abs(d_cuml) do --math.min(math.abs(d_cuml), 1) do
      table.remove(arranger, math.max(event_edit_segment - i, 1))
      table.insert(arranger, 0)
      table.remove(events, math.max(event_edit_segment - i, 1))
      table.insert(events, {})
      events[max_arranger_length] = {{},{},{},{},{},{},{},{}}
    end
    gen_arranger_padded()
    d_cuml = 0
  end
end


----------------------
-- NORNS KEY FUNCTIONS
----------------------
function key(n,z)
  if z == 1 then
    -- keys[n] = 1
    key_count = key_count + 1
    -- KEY 1 just increments keys and key_count for alt functions
    -- if n == 1 then
    -- KEY 2  
    if n == 2 then
      -- if keys[1] == 1 then
      -- Not used at the moment
        
      -- Arranger Events strip held down
      if arranger_loop_key_count > 0 and interaction ~= "arranger_shift" then -- interaction == nil then
        arranger_queue = event_edit_segment
        -- jumping arranger queue cancels pattern change on key up
        if arranger_queue <= arranger_length then arranger_one_shot_last_pattern = false end -- instantly de-blink glyph
        grid_dirty = true
      
      elseif screen_view_name == "Events" then
       
       
        ------------------------
        -- K2 DELETE EVENT
        ------------------------
        if event_edit_active then

          -- Record the count of events on this step
          local event_count = events[event_edit_segment][event_edit_step].populated or 0
          
          -- Check if event is populated and needs to be deleted
          if events[event_edit_segment][event_edit_step][event_edit_lane] ~= nil then
            
            -- Decrement populated count at the step level
            events[event_edit_segment][event_edit_step].populated = event_count - 1
            
            -- If the step's new populated count == 0, update the segment level populated count
            if events[event_edit_segment][event_edit_step].populated == 0 then 
              events[event_edit_segment].populated = events[event_edit_segment].populated - 1 
            end
            
            -- Delete the event
            events[event_edit_segment][event_edit_step][event_edit_lane] = nil
          end
          
          -- Back to event overview
          event_edit_active = false
          
          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true
          
          -- screen_dirty = true -- redraw()
          
          
        -------------------------------------------
        -- K2 DELETE ALL EVENTS IN SEGMENT
        -------------------------------------------
        else
          event_k2 = true
          clock.run(delete_all_events_segment)
        end
        
        gen_dash("K2 events editor closed") -- update events strip in dash after making changes in events editor
        grid_dirty = true
        
        
      ----------------------------------------
      -- K2 Transport controls K2 - STOP/RESET --
      ----------------------------------------
        
      elseif interaction ~= "arranger_shift" then -- == nil then -- actually seems fine to do transport controls this during arranger shift?

        if params:string("clock_source") == "internal" then
          -- print("internal clock")
          if transport_state == "starting" or transport_state == "playing" then
            -- print("DEBUG K2 TRANSPORT STOPPING")
            transport_multi_stop() -- 24-02-10 moving from sprocket_16th to K2 for immediate stop (make this an option?)

            stop = true
            transport_state = "pausing"
            print(transport_state)        
            clock_start_method = "continue"
            send_continue = true
          else
            reset_external_clock()
            if params:get("arranger") == 2 then
              reset_arrangement()
            else
              reset_pattern()
            end
            -- print("K2 setting transport to 0")
            seq_lattice.transport = 0 -- check if needed
            -- pre_sync_val = nil -- no start sync offset needed when stopping
          end
        
        elseif params:string("clock_source") == "link" then

          if transport_state == "starting" or transport_state == "playing" then

            -- temporarily disable this since Link continue is not possible with negative beats
            -- see https://github.com/monome/norns/issues/1756
            -- clock.link.stop() -- no stop quantization for sending Link stop out
            -- -- print("K2 on transport " .. seq_lattice.transport)
            -- link_stop_source = "norns"
            -- stop = true -- will trigger DS to do 1/16 quantized stop
            -- clock_start_method = "continue"
            -- transport_state = "pausing"
            -- print(transport_state)

            -----------------------------
            -- full stop for the time being
            clock.link.stop() -- no stop quantization for sending Link stop out
            -- link_stop_source = "norns"
            stop = true -- will trigger DS to do 1/16 quantized stop
            clock_start_method = "start"

            transport_state = "pausing" -- will immediately be flipped to Stop in sprocket
            print(transport_state)

            if params:get("arranger") == 2 then
              reset_arrangement()
            else
              reset_pattern()       
            end
            -----------------------------

          -- don't let link reset while transport is active or it gets outta sync
          --  modified so we can always do a stop when not playing (external sync and weird state exceptions) 
          elseif transport_state == "paused" or transport_state == "stopped" then
            if params:get("arranger") == 2 then
              reset_arrangement()
            else
              reset_pattern()       
            end
            
          end
        
        --   elseif params:string("clock_source") == "midi" then
        --   if transport_state == "starting" or transport_state == "playing" then
        --     stop = true
        --     transport_state = "pausing"
        --     print(transport_state)        
        --     clock_start_method = "continue"
        --     -- start = true
        --   else --  remove so we can always do a stop (external sync and weird state exceptions)  if transport_state == "pausing" or transport_state == "paused" then
        --     reset_external_clock()
        --     if params:get("arranger") == 2 then
        --       reset_arrangement()
        --     else
        --       reset_pattern()       
        --     end
        --   end
          
          -- elseif params:string("clock_source") == "crow" then
          -- if transport_state == "starting" or transport_state == "playing" then
          --   stop = true
          --   transport_state = "pausing"
          --   print(transport_state)        
          --   clock_start_method = "continue"
          --   -- start = true
          -- else --  remove so we can always do a stop (external sync and weird state exceptions)  if transport_state == "pausing" or transport_state == "paused" then
          --   reset_external_clock()
          --   if params:get("arranger") == 2 then
          --     reset_arrangement()
          --   else
          --     reset_pattern()       
          --   end
          -- end
        end
        
      end
  
      -----------------------  
      -- KEY 3  
      -----------------------
    elseif n == 3 then
      -- if keys[1] == 1 then
      if init_message ~= nil then
        init_message = nil
      
      elseif view_key_count > 0 then -- Grid view key held down
        if screen_view_name == "Chord+seq" then
        
          -- When Chord+Seq Grid View keys are held down, K3 runs Generator (and resets pattern+seq on internal clock)
          generator()

          -- This reset patterns and resyncs seq, but only for internal clock. todo p1 think on this. Not great and might be weird with new seq reset logic
          if params:string("clock_source") == "internal" then
            local prev_transport_state = transport_state
            reset_external_clock()
            -- don't reset arranger it's confusing if we generate on, say, pattern 3 and then Arranger is reset and we're now on pattern 1.
            reset_pattern()
            if transport_state ~= prev_transport_state then
              transport_state = prev_transport_state
              print(transport_state)
            end
          end
     
        elseif grid_view_name == "Chord" then       
          chord_generator_lite()
          -- gen_dash("chord_generator_lite") -- will run when called from event but not from keys
        elseif grid_view_name == "Seq" then       
          seq_generator("run")
        end
        grid_dirty = true
      
        ---------------------------------------------------------------------------
        -- Event Editor --
        -- K3 with Event Timeline key held down enters Event editor / function key event editor
        ---------------------------------------------------------------------------        
      elseif arranger_loop_key_count > 0 and interaction ~= "arranger_shift" then -- interaction == nil then
        pattern_grid_offset = 0
        arranger_loop_key_count = 0
        event_edit_step = 0
        event_edit_lane = 0
        event_edit_active = false
        screen_view_name = "Events"
        interaction = nil
        grid_dirty = true
  
      -- K3 saves event to events
      elseif screen_view_name == "Events" then

        ---------------------------------------
        -- K3 TO SAVE EVENT
        ---------------------------------------
        if event_edit_active then

          local event_index = params:get("event_name")
          local order = tonumber(events_lookup[event_index].order) or 2 -- (order 1 fires before chord (no swing), order 2 fires after chord (with swing))

          -- function or param
          local event_type = events_lookup[event_index].event_type
          local value = params:get("event_value")
          
          -- trigger, discreet, continuous
          local value_type = events_lookup[event_index].value_type
          
          -- Set, Increment, Wander, Random
          local operation = params:string("event_operation") -- changed to id which will need to be looked up and turned into an id
          local action = events_lookup[event_index].action
          local args = events_lookup[event_index].args
          
          local limit = params:string(operation == "Random" and "event_op_limit_random" or "event_op_limit")
          -- variant for "Random" op -- todo p1 make sure we can store here and get it loaded into the right param correctly
          -- local limit_random = params:string("event_op_limit_random")
          local limit_min = params:get("event_op_limit_min")
          local limit_max = params:get("event_op_limit_max")
          
          local probability = params:get("event_probability") -- todo p1 convert to 0-1 float?
          
          -- Keep track of how many events are populated in this step so we don't have to iterate through them all later
          local step_event_count = events[event_edit_segment][event_edit_step].populated or 0

          -- If we're saving over a previously-nil event, increment the step populated count          
          if events[event_edit_segment][event_edit_step][event_edit_lane] == nil then
            events[event_edit_segment][event_edit_step].populated = step_event_count + 1

            -- Also check to see if we need to increment the count of populated event STEPS in the SEGMENT
            if (events[event_edit_segment][event_edit_step].populated or 0) == 1 then
              events[event_edit_segment].populated = (events[event_edit_segment].populated or 0) + 1
            end
          end

          -- Wipe existing events, write the event vars to events
          if value_type == "trigger" then
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type,
                value_type = value_type,
                operation = operation,  -- sorta redundant but we do use it to simplify reads
                -- value = 
                probability = probability
              }
              
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")
            print(">> id = " .. events_lookup[event_index].id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> probability = " .. probability)
            
          elseif operation == "Set" then
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                value = value, 
                probability = probability
              }
              
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")     
            print(">> id = " .. events_lookup[event_index].id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> value = " .. value)
            print(">> probability = " .. probability)
              
          elseif operation == "Random" then
            if limit == "Off" then -- so clunky yikes
              events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage              
                probability = probability
              }
              else
              events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage
                  limit_min = limit_min,  -- adding
                  limit_max = limit_max,  -- adding
                probability = probability
              }
            end
            
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")       
            print(">> id = " .. events_lookup[event_index].id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> limit = " .. limit)
            if limit ~= "Off" then
              print(">> limit_min = " .. limit_min)
              print(">> limit_max = " .. limit_max)
            end
            print(">> probability = " .. probability)
           
              
          else --operation == "Increment" or "Wander"
           if limit == "Off" then -- so clunky yikes
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit,
                value = value, 
                probability = probability
              }
            else
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                order = order,
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit,
                limit_min = limit_min,  -- adding
                limit_max = limit_max,  -- adding
                value = value, 
                probability = probability
              }
            end  
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")       
            print(">> id = " .. events_lookup[event_index].id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> limit = " .. limit)
            if limit ~= "Off" then
              print(">> limit_min = " .. limit_min)
              print(">> limit_max = " .. limit_max)            
            end
            print(">> value = " .. value)
            print(">> probability = " .. probability)
            
          end
          
          -- Extra fields are added if action is assigned to param/function
          if action ~= nil then
            events[event_edit_segment][event_edit_step][event_edit_lane].action = action
            events[event_edit_segment][event_edit_step][event_edit_lane].args = args
            
            print(">> action = " .. action)
            print(">> args = " .. (args or "nil"))
          end
          
          -- Back to event overview
          event_edit_active = false
          
          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true
          
          grid_dirty = true
        
        else
          screen_view_name = "Session"
          event_key_count = 0
          gen_dash("K3 events saved") -- update events strip in dash after making changes in events editor
          grid_dirty = true
        end

        ----------------------------------
        -- Transport controls K3 - PLAY --
        ----------------------------------
        -- Todo p1 need to have a way of canceling a pending pause once transport controls are reworked
      elseif interaction == nil then
        
        if params:string("clock_source") == "internal" then
          -- todo p0 evaluate this vs transport_state
          if transport_active == false then
            
            -- can use this to skip clock.sync(1)
            -- also calls clock.transport.start()
            -- but throws timing of quantized stop off (play/pause drifts...)
            -- params:set("clock_reset", 1)
            clock.transport.start()
          else -- we can cancel a pending pause by pressing K3 before it fires
            stop = false
            transport_state = "playing"
            print(transport_state)            
          end
        
          -- -- redo to fire params:set("clock_reset") and sync on beat 0 rather than 1
          -- if params:string("clock_source") == "internal" then
          --   -- todo p0 evaluate this vs transport_state
          --   if transport_active == false then
          --     -- clock.transport.start()
          --     params:set("clock_reset") -- resets beat to 0 and starts clock
          --   else -- we can cancel a pending pause by pressing K3 before it fires
          --     stop = false
          --     transport_state = "playing"
          --     print(transport_state)            
          --   end          
            
          --     -- this needs to be rewritten to incorporate sprocket.transport, if we want to MIDI punch-in thing to work
          -- elseif params:string("clock_source") == "midi" then
          --   if transport_active == false then
          --     clock.transport.start(sprocket_measure.division) --chord_div / global_clock_div) -- sync_val  -- WIP here!
          --   else -- we can cancel a pending pause by pressing K3 before it fires
          --     stop = false
          --     transport_state = "playing"
          --     print(transport_state)            
          --   end
            
          -- disabling until issue with internal link start clobbering clocks is addressed
          -- test once https://github.com/monome/norns/pull/1740 is available
        elseif params:string("clock_source") == "link" then
          if transport_active == false then

            -- K3 or external will result in reset before starting
            
            -- --------------------------
            -- -- todo: make this a function and figure out how to also call it when called by external link start
            -- transport_multi_stop()   
            -- if arranger_active then
            --   print(transport_state)
            -- else
            --   reset_pattern()
            -- end
            -- transport_active = false
            -- reset_arrangement()
            -- transport_state = "stopped"
            -- stop = false
            -- link_stop_source = nil
            -- seq_lattice.transport = 0 -- -1 -- probably a better place for this
            -- --------------------------

            -- link_start_mode = "resume"  -- resume/continue only supported with K3 for now
            clock.link.start()


          else -- we can cancel a pending pause by pressing K3 before it fires
            stop = false
            transport_state = "playing"
            print(transport_state)            
          end
          
        -- todo p0 untested in 1.3
        -- elseif params:string("clock_source") == "crow" then
        --   if transport_active == false then
        --     clock.transport.start(1)  -- sync on next beat
        --   else -- we can cancel a pending pause by pressing K3 before it fires
        --     stop = false
        --     transport_state = "playing"
        --     print(transport_state)            
        --   end          
        end
      end
      -----------------------------------
        
    end
  elseif z == 0 then
    -- keys[n] = nil
    key_count = key_count - 1
    if n == 2 then
      -- reset this for event segment delete countdown
      event_k2 = false
    end
  end
  -- screen_dirty = true -- redraw()
end


-----------------------------------
-- ENCODERS
----------------------------------          
function enc(n,d)
  -- todo p1 more refined switching between clamped and raw deltas depending on the use-case
  -- local d = util.clamp(d, -1, 1)
  
  -- Scrolling/extending Arranger, Chord, Seq patterns
  if n == 1 then
    local d = util.clamp(d, -1, 1)
    -- ------- SCROLL ARRANGER GRID VIEW--------
    -- if grid_view_name == "Arranger" then
    --   arranger_grid_offset = util.clamp(arranger_grid_offset + d, 0, max_arranger_length -  16)
    --   grid_redraw()
    -- end
    --------- SCROLL PATTERN VIEWS -----------
    if grid_view_name == "Chord" or screen_view_name == "Events" then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_chord_pattern_length -  rows)
      grid_dirty = true
    elseif grid_view_name == "Seq" then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_seq_pattern_length -  rows)
      grid_dirty = true
    end
  
  -- n == ENC 2 ------------------------------------------------
  elseif n == 2 then
    if view_key_count > 0 then
      local d = util.clamp(d, -1, 1)
      if (grid_view_name == "Chord" or grid_view_name == "Seq") then-- Chord/Seq 
        rotate_pattern(grid_view_name, d)
        grid_dirty = true            
      end
   
    elseif screen_view_name == "Events" and event_saved == false then
      -- Scroll through the Events menus (name, type, val)
      events_index = util.clamp(events_index + d, 1, #events_menus)
      
      selected_events_menu = events_menus[events_index]
      
    else
      menu_index = util.clamp(menu_index + d, 0, #menus[page_index])
      selected_menu = menus[page_index][menu_index]
    end
    
  -- n == ENC 3 -------------------------------------------------------------  
  else
  
    if view_key_count > 0 then
      local d = util.clamp(d, -1, 1)
      if (grid_view_name == "Chord" or grid_view_name == "Seq") then-- Chord/Seq 
        transpose_pattern(grid_view_name, d)
        grid_dirty = true
      end
        
    ----------------------    
    -- Event editor menus
    ----------------------    
    -- Not using param actions on these since some use dynamic .options which don't reliably fire on changes. Also we want to fire edit_status_edited() on encoder changes but not when params are set elsewhere (loading events etc)
    elseif screen_view_name == "Events" and event_saved == false then

      if selected_events_menu == "event_category" then
        if delta_menu(d) then
          change_category()
        end
        
      elseif selected_events_menu == "event_subcategory" then
        if delta_menu(d) then
          change_subcategory()
        end
        
      elseif selected_events_menu == "event_name" then
        if delta_menu(d, event_subcategory_index_min, event_subcategory_index_max) then
          change_event()
        end
        
      elseif selected_events_menu == "event_operation" then
        if delta_menu(d) then
          change_operation()
        end
        
      elseif selected_events_menu == "event_value" then
        if params:string("event_operation") == "Set" then
          -- alternate function to process via preview
          delta_menu_set(d, event_range[1], event_range[2]) -- Dynamic event_range lookup. no functions to call here

        elseif params:string("event_operation") == "Wander" then
          delta_menu(d, 1) -- nil max defaults to 9999
        else
          params:delta(selected_events_menu, d)
          edit_status_edited()
        end
      
      elseif selected_events_menu == "event_op_limit_min" then
        delta_menu_range(d, event_range[1], params:get("event_op_limit_max"))

      elseif selected_events_menu == "event_op_limit_max" then
        delta_menu_range(d, params:get("event_op_limit_min"), event_range[2])
  
      -- this should work for the remaining event menus that don't need to fire functions: probability, limit, limit_random
      else
        delta_menu(d)
        
      end
      
    --------------------
    -- Arranger shift --  
    --------------------
    elseif grid_view_name == "Arranger" and arranger_loop_key_count > 0 then
      local d = util.clamp(d, -1, 1)
      -- Arranger segment detail options are on-screen
      -- block event copy+paste, K2 and K3 (arranger jump and event editor)
      -- new global to identify types of user interactions that should block certain other interactions e.g. copy+paste, arranger jump, and entering event editor
      interaction = "arranger_shift"
      d_cuml = util.clamp(d_cuml + d, -64, 64)
      
      grid_dirty = true
  
    elseif screen_view_name == "Session" then
      if menu_index == 0 then
        menu_index = 0
        page_index = util.clamp(page_index + d, 1, #pages)
        page_name = pages[page_index]
        selected_menu = menus[page_index][menu_index]
      else
        params:delta(selected_menu, d)
      end
    end
  
  end -- n
  -- screen_dirty = true -- redraw()
end


-- utility function for enc deltas
-- Performs a similar operation to params:delta with a couple of differences:
-- 1. Can accept optional arguments for min/max for parameters that don't have this set
-- 2. Calls edit_status_edited() as a psuedo param action (that we only want to run for encoder-initiaded set/deltas)
-- 3. Returns whether or not the value changed so that we can call followup change_xxxxx functions
function delta_menu(d, minimum, maximum)
  local prev_value = params:get(selected_events_menu)
  local minimum = minimum or params:get_range(selected_events_menu)[1]
  local maximum = maximum or params:get_range(selected_events_menu)[2]
  local value = util.clamp(prev_value + d, minimum, maximum)
  if value ~= prev_value then
    params:set(selected_events_menu, value)
    edit_status_edited()
    return(true)
  else
    return(false)
  end
end


-- alt of delta_menu used when selected_events_menu == "event_value" to handle preview
function delta_menu_set(d, minimum, maximum)
  local prev_value = params:get(selected_events_menu)
  local minimum = minimum or params:get_range(selected_events_menu)[1]
  local maximum = maximum or params:get_range(selected_events_menu)[2]
  preview:delta(d)
  local value = util.clamp(preview:get(), minimum, maximum)
  if value ~= prev_value then
    params:set(selected_events_menu, value)
    edit_status_edited()
    return(true)
  else
    return(false)
  end
end


-- alt of delta_menu used when using preview to adjust op range min/max
-- 1. store current preview value (or not... see alt)
-- 2. set current preview value to min/max
-- 3. use delta to adjust and return delta'd preview value as min/max
-- 4. restore preview value from step 1 (or just clone_param())
function delta_menu_range(d, minimum, maximum)  -- TODO fix min/max can't be flipped
  local prev_value = params:get(selected_events_menu) -- e.g. 0 or 1
  preview:set(prev_value) -- pass the min/max value to preview so we can delta it
  preview:delta(d)
  local value = util.clamp(preview:get(), minimum, maximum) -- prevernt min/max overlap
  if value ~= prev_value then
    params:set(selected_events_menu, value)

    edit_status_edited()
    return(true)
  else
    return(false)
  end
end


---------------------------------------
-- CASCADING EVENTS EDITOR FUNCTIONS --
---------------------------------------
local debug_change_functions = false

function change_category()
  local category = params:get("event_category")
  if debug_change_functions then print("1. change_category called") end
  if category ~= prev_category then
    if debug_change_functions then print("  1.1 new category") end
    
    update_event_subcategory_options("change_category")
    params:set("event_subcategory", 1) -- no action- calling manually on next step.
    change_subcategory()
  end
    prev_category = category  -- todo p1 can this be local and persist on next call? I think not.
end


function change_subcategory()
  if debug_change_functions then print("2. change_subcategory called") end
  -- concat this because subcategory string isn't unique and index resets with options swap!
  local subcategory = params:string("event_category") .. params:string("event_subcategory")
  if debug_change_functions then print("  new subcategory = " .. subcategory .. "  prev_subcategory = " .. (prev_subcategory or "nil")) end

  if subcategory ~= prev_subcategory then
    set_event_indices()

    if debug_change_functions then print("  setting event to " .. events_lookup[event_subcategory_index_min].name) end
    
    params:set("event_name", event_subcategory_index_min)
    change_event()
  end  
  prev_subcategory = subcategory
end


function change_event() -- index
  local event = params:get("event_name")
  if debug_change_functions then print("3. change_event called") end
  if debug_change_functions then print("   new event: " .. events_lookup[event].name) end
  if event ~= prev_event then
    update_event_operation_options("change_event")
    
    -- Currently only changing on new event. Changing operation keeps the limit type
    params:set("event_op_limit", 1)
    params:set("event_op_limit_random", 1)

    set_event_range()
    
    -- can also move to set_event_range() but this seems fine
    params:set("event_op_limit_min", event_range[1])
    params:set("event_op_limit_max", event_range[2])
    
    params:set("event_operation", 1) -- no action so call on next line
    change_operation("change_event")  -- pass arg so we can tell change_operation to set values even if op hasn't changed
    params:set("event_probability", 100) -- Only reset probability when event changes
    local event = events_lookup[params:get("event_name")]
    if event.event_type == "param" then
      clone_param(event.id)
    end
  end
  prev_event = event
end


function change_operation(source)
  if debug_change_functions then print("4. change_operation called") end
  local operation = params:string("event_operation")
  if debug_change_functions then print("   operation = " .. operation) end

  -- We also need to set default value if the event changed!
  if source == "change_event" or operation ~= prev_operation then
    
    -- alternative placement if we want to reset change event_op_limit and event_op_limit_random on both event and op change
    
    if debug_change_functions then print("    setting default values") end

    local event_index = params:get("event_name")
    local value_type = events_lookup[event_index].value_type
    local event_type = events_lookup[event_index].event_type

		-- set default_value for this operation
		if debug_change_functions then print("    event_type = " .. event_type) end
    if event_type == "param" then
      if debug_change_functions then print("4.1 param value") end
      if operation == "Set" then
        --todo p2 if adding more Discreet functions, need to expand on this because it's setting param value on function event types
        local default_value = params:get(events_lookup[event_index].id)
        local default_value = util.clamp(default_value, event_range[1], event_range[2])
        if debug_change_functions then print("5. Set: setting default value to " .. default_value) end
        params:set("event_value", default_value)
      elseif operation == "Wander" then
        if debug_change_functions then print("5. Wander: setting default value to " .. 1) end
        params:set("event_value", 1)
      elseif operation == "Increment" then
      if debug_change_functions then print("5. Increment: setting default value to " .. 0) end
      params:set("event_value", 0)
      end
    -- else -- SKIP TRIGGER AND RANDOM!!!
    end
    gen_menu_events()
  end
  prev_operation = operation
  if debug_change_functions then print("     debug setting prev_operation to " .. prev_operation) end
end


-- todo p3 handle with insert/removes or make a lookup table
function gen_menu_events()
  operation = params:string("event_operation")
  if operation == "Trigger" then
    events_menus =  {"event_category", "event_subcategory", "event_name", "event_probability"}
  elseif operation == "Set" then -- no limits
    events_menus =  {"event_category", "event_subcategory", "event_name", "event_operation", "event_value", "event_probability"}    
  elseif operation == "Random" then  -- no value, swap in event_op_limit_random
    if params:string("event_op_limit_random") == "Off" then
      events_menus =  {"event_category", "event_subcategory", "event_name", "event_operation", "event_op_limit_random", "event_probability"}
    else
      events_menus =  {"event_category", "event_subcategory", "event_name", "event_operation", "event_op_limit_random", "event_op_limit_min", "event_op_limit_max", "event_probability"} 
    end
  elseif params:string("event_op_limit") == "Off" then  -- Increment and Wander get it all
    events_menus =  {"event_category", "event_subcategory", "event_name", "event_operation", "event_value", "event_op_limit", "event_probability"}
  else
    events_menus =  {"event_category", "event_subcategory", "event_name", "event_operation", "event_value", "event_op_limit", "event_op_limit_min", "event_op_limit_max", "event_probability"}    
  end
end
  

-- Running this in change_ events so it only fires if the value actually changes (rather than enc delta"d)
function edit_status_edited()
  if event_edit_status == "(Saved)" then
    event_edit_status = "(Edited)"
    -- print("setting event_edit_status to " .. event_edit_status)
  end
end
    
-- Fetches the min and max events_lookup index for the selected subcategory so we know what events are available
function set_event_indices()
  local category = params:string("event_category")
  local subcategory = params:string("event_subcategory")
  event_subcategory_index_min = event_indices[category .. "_" .. subcategory].first_index
  event_subcategory_index_max = event_indices[category .. "_" .. subcategory].last_index
  
  if debug_change_functions then 
    print("  Set event_subcategory_index_min to " .. event_subcategory_index_min) 
    print("  Set event_subcategory_index_max to " .. event_subcategory_index_max) 
  end
end


-- Sets the min and max ranges for the event param or function. No formatting stuff.
function set_event_range()
  local event_index = params:get("event_name")
  -- Determine if event range should be clamped
  if events_lookup[event_index].event_type == "param" then
    if events_lookup[event_index].value_type ~= "trigger" then
      
      -- 2024-03-20 removed this which was causing issues with range when flipping from chord step length to mode
      -- if params:string("event_operation") == "Increment" then
      --   event_range = {-9999,9999}
      -- else -- discreet"
        event_range = params:get_range(params.lookup[events_lookup[event_index].id]) or {-9999, 9999}
      -- end
    end
  else -- function. May have hardcoded ranges in events_lookup at some point
    event_range = {-9999,9999}
  end
  
  if debug_change_functions then 
    print("  Set event_range[1] to " .. event_range[1]) 
    print("  Set event_range[2] to " .. event_range[2]) 
  end  
end  


function get_options(param)
  local options = params.params[params.lookup[param]].options
  return (options)
end


function update_event_subcategory_options(source)
  if debug_change_functions then print("   update_event_subcategory_options called by " .. (source or "nil")) end
  swap_param_options("event_subcategory", event_subcategories[params:string("event_category")])
end

function update_event_operation_options(source)
  if debug_change_functions then print("   updating operations on " .. (params:string("event_name") or "nil")) end
  swap_param_options("event_operation", _G["event_operation_options_" .. events_lookup[params:get("event_name")].value_type])
end


-- used to set default value of event after init and pset load
function get_default_event_value()  
  if events_lookup[params:get("event_name")].event_type == "param" then
    return(params.params[params.lookup[events_lookup[params:get("event_name")].id]].default)
  else
    return(0)
  end
end  
  
  
function chord_steps_to_seconds(steps)
  return(steps * 60 / params:get("clock_tempo") / global_clock_div * chord_div) -- switched to var Fix: timing
end


-- Alternative for more digits up to 9 hours LETSGOOOOOOO
function s_to_min_sec(seconds)
  local seconds = tonumber(seconds)
    -- hours = (string.format("%02.f", math.floor(seconds/3600));
    hours_raw = math.floor(seconds/3600);
    hours = string.format("%1.f", hours_raw);
    mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)));
    secs = string.format("%02.f", math.floor(seconds - hours*3600 - mins *60));
    -- Modify hours if it's 2+ digits
    -- hours = hours < 10 and string.format("%2.f",hours) or ">";
    if hours_raw < 10 then
      return hours..":"..mins..":"..secs
    else
      return hours.." hrs"
    end
end


-- generates truncated flat tables at the chord step level for the arranger mini dashboard
-- runs any time the arranger changes (generator, events, pattern changes, length changes, key pset load, arranger/pattern reset, event edits)
function gen_dash(source)
  -- print("gen_dash called by " .. (source or "?"))
  dash_patterns = {}
  -- dash_levels correspond to 3 arranger states:
  -- 1. Arranger was disabled then re-enabled mid-segment so current segment should be dimmed
  -- 2. Arranger is enabled so upcoming segments should be bright
  -- 3. Arranger is disabled completely and should be dimmed  
  dash_levels = {}
  dash_events = {}
  dash_steps = 0
  steps_remaining_in_active_pattern = 0
  steps_remaining_in_arrangement = 0

  ---------------------------------------------------------------------------------------------------
  -- iterate through all steps in arranger so we can get a total for steps_remaining_in_arrangement
  -- then build the arranger dash charts, limited to area drawn on screen (~30px)
  ---------------------------------------------------------------------------------------------------
  for i = math.max(arranger_position, 1), arranger_length do
    
  -- _sticky vars handle instances when the active arranger segment is interrupted, in which case we want to freeze its vars to stop the segment from updating on the dash (while still allowing upcoming segments to update)
  -- Scenarios to test for:
    -- 1. User changes the current arranger segment pattern while on that segment. In this case we want to keep displaying the currently *playing* chord pattern
    -- 2. User changes the current chord pattern by double tapping it on the Chord grid view. This sets arranger_active to false and should suspend the arranger mini chart until Arranger pickup occurs.
    -- 3. Current arranger segment is turned off, resulting in it picking up a different pattern (either the previous pattern or wrapping around to grab the last pattern. arranger_padded shenanigans)
    -- 4. We DO want this to update if the arranger is reset (arranger_position = 0, however)
    
    -- Note: arranger_position == i idenifies if we're on the active segment. Implicitly false when arranger is reset (arranger_position 0) todo p2 make local
    if arranger_position == i then
      -- todo p2 would be nice to rewrite this so these can be local
      if arranger_active == true then
        active_pattern = active_chord_pattern
        active_chord_pattern_length = chord_pattern_length[active_pattern]
        active_chord_pattern_position = math.max(chord_pattern_position, 1)
        segment_level = 15
      else
        segment_level = 2 -- interrupted segment pattern, redraw will add +1 for better contrast only on events
      end
      pattern_sticky = active_pattern
      chord_pattern_length_sticky = active_chord_pattern_length
      chord_pattern_position_sticky = active_chord_pattern_position

      local steps_incr = math.max(active_chord_pattern_length - math.max((active_chord_pattern_position or 1) - 1, 0), 0)
      steps_remaining_in_pattern = steps_incr
      steps_remaining_in_active_pattern = steps_remaining_in_active_pattern + steps_incr
    -- print("active_pattern = " .. active_pattern) --todo debug to see if this is always set
    else -- upcoming segments always grab their current values from arranger
      pattern_sticky = arranger_padded[i]
      chord_pattern_length_sticky = chord_pattern_length[pattern_sticky]
      chord_pattern_position_sticky = 1
      steps_remaining_in_pattern = chord_pattern_length[pattern_sticky]
      segment_level = params:get("arranger") == 2 and 15 or 2
    end
    
    -- used to total remaining time in arrangement (beyond what is drawn in the dash)  
    steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
    
    -- todo p3 some sort of weird race condition is happening at init that requires nil check on events
    if events ~= nil and dash_steps < 30 then -- capped so we only store what is needed for the dash (including inserted blanks)
      for s = chord_pattern_position_sticky, chord_pattern_length_sticky do -- todo debug this was letting 0 values through at some point. Debug if errors surface.
        -- if s == 0 then print("s == 0 " .. chord_pattern_position_sticky .. "  " .. chord_pattern_length_sticky) end -- p0 debug looking for 0000s
        if dash_steps == 30 then
         break 
        end -- second length check for each step iteration cuts down on what is saved for long segments
        table.insert(dash_patterns, pattern_sticky)
        table.insert(dash_levels, segment_level)
        table.insert(dash_events, ((events[i][s].populated or 0) > 0) and math.min(segment_level + 1, 15) or 1)
        dash_steps = dash_steps + 1
      end
    -- insert blanks between segments
    table.insert(dash_patterns, 0)
    table.insert(dash_events, 0) 
    table.insert(dash_levels, 0)
    dash_steps = dash_steps + 1 -- and 1 to grow on!
    end
  end
  calc_seconds_remaining() -- firing before lattice is running which causes error
end


--------------------------
-- REDRAW
-------------------------
-- todo p1: this can be improved quite a bit by just having these custom screens be generated at the key/g.key level. Should be a fun refactor.
function redraw()
  -- if transport_active then
    -- redraw_count = redraw_count + 1
    -- print("redraw_count = "..redraw_count)
  -- end
  
  screen.clear()
  local dash_x = 94
      
  -- Screens that pop up when g.keys are being held down take priority--------
  -- POP-up g.key tip always takes priority
  if view_key_count > 0 then
    if screen_view_name == "Chord+seq" then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. " GRID FUNCTIONS")
      screen.move(2,28)
      screen.text("ENC 2: rotate ↑↓")
      screen.move(2,38)
      screen.text("ENC 3: transpose ←→")
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right("(K3) GEN. CHORDS+SEQ")      

    elseif grid_view_name == "Arranger" then
      screen.level(15)
      screen.move(2,8)
      -- Placeholder
      -- screen.text(string.upper(grid_view_name) .. " GRID FUNCTIONS")
      screen.text(string.upper(grid_view_name) .. " GRID")
      -- screen.move(2,28)
      -- screen.text("ENC 2: Rotate ↑↓")
      -- screen.move(2,38)
      -- screen.text("ENC 3: Transpose ←→")
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
        
    elseif grid_view_name == "Chord" then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. " GRID FUNCTIONS")
      screen.move(2,28)
      screen.text("ENC 2: rotate ↑↓")
      screen.move(2,38)
      screen.text("ENC 3: transpose ←→")
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right("(K3) GEN. CHORDS")     
        
     elseif grid_view_name == "Seq" then --or grid_view_name == "Seq") then-- Chord/Seq 
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. " GRID FUNCTIONS")
      screen.move(2,28)
      screen.text("ENC 2: rotate ↑↓")
      screen.move(2,38)
      screen.text("ENC 3: transpose ←→")
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right("(K3) GEN. SEQ")  
      end
      
  -- Arranger shift interaction
  elseif interaction == "arranger_shift" then
    screen.level(15)
    screen.move(2,8)
    screen.text("ARRANGER SEGMENT " .. event_edit_segment)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,38)
    screen.text("ENC 3: shift segments ←→")
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()    
  
    
  -- Arranger events timeline held down
  elseif arranger_loop_key_count > 0 then
    screen.level(15)
    screen.move(2,8)
    screen.text("ARRANGER SEGMENT " .. event_edit_segment)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,28)
    screen.text("Hold+tap: paste events")
    screen.move(2,38)
    screen.text("ENC 3: shift segments ←→")
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()
    screen.level(3)
    screen.move(1,62)
    screen.text("(K2) CUE SEG.")    
    screen.move(82,62)
    screen.text("(K3) EVENTS")

  -- Chord patterns held down
  -- --        elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher. Key UP events farther down in function.
  --       pattern_key_count = pattern_key_count + 1
  --       pattern_keys[y] = 1
  --       if pattern_key_count == 1 then
  --         pattern_copy_source = y
  --       elseif pattern_key_count > 1 then
  --         print("Copying pattern " .. pattern_copy_source .. " to pattern " .. y)
  --         pattern_copy_performed = true
          
  -- tooltips for interacting with chord patterns      
  elseif grid_view_name == "Chord" and pattern_key_count > 0 then -- add a new interaction for this
    screen.level(15)
    screen.move(2,8)
    screen.text("CHORD PATTERN " .. pattern_name[pattern_copy_source])
    screen.move(2,28)
    -- screen.text("Tap a pattern to paste")
    screen.text("Hold+tap: paste pattern") --. " .. pattern_name[pattern_copy_source])
    screen.move(2,38)
    screen.text("Release: queue pattern")
    screen.move(2,48)
    -- screen.text("Tap again to force jump")
    screen.text("Tap 2x while stopped: jump")
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()    
  
  -- Standard priority (not momentary) menus---------------------------------  
  else
    ---------------------------
    -- UI elements placed here will persist in all views including Events editor
    ---------------------------

    ----------------
    -- Events screen (function redraw events)
    ----------------    
    if screen_view_name == "Events" then
      screen.level(15)
      screen.move(2,8)
      if event_edit_active == false then
        if key_counter == 4 then
          screen.text("ARRANGER SEGMENT " .. event_edit_segment .. " EVENTS")
          screen.level(15)
          screen.move(2,23)
          screen.text("Grid: select event slot")
          screen.move(2,33)
          screen.text("1↓16: chord pattern step")
          screen.move(2,43)
          screen.text("1→16: event order")
          screen.level(4)
          screen.move(1,54)
          screen.line(128,54)
          screen.stroke()
          screen.level(3)      
          screen.move(1,62)
          screen.text("(K1 HOLD) DEL.")
          screen.move(128,62)
          screen.text_right("(K3) ARRANGER")
        else
          screen.level(15)      
          screen.move(36,33)
          screen.text("DELETING IN " .. key_counter)
        end
      else
   
   
        --------------------------
        -- Scrolling events menu
        --------------------------
        -- todo p2 move some of this to a function that can be called when changing event or entering menu first time (like get_range)
        -- todo p2 this mixes events_index and menu_index. Redundant?
        local lookup = events_lookup[params:get("event_name")]  -- todo global + change_event()
        local menu_offset = scroll_offset_locked(events_index, 10, 2) -- index, height, locked_row
        local line = 1
        for i = 1, #events_menus do
          local debug = false
          
          screen.move(2, line * 10 + 8 - menu_offset)
          screen.level(events_index == i and 15 or 3)

          local menu_id = events_menus[i]
          local menu_index = params:get(menu_id)
          local event_val_string = params:string(menu_id)
          
          -- use event_value to format values
          -- values are already set on var event_val_string so if no conditions are met they pass through raw
          -- >> "Set" operation should do .options lookup where possible
          -- >> functions are raw
          -- >> inc, random, wander are raw but ranges have been formatted above
          if menu_id == "event_value" then
            if debug then print("-------------------") end
            if debug then print("formatting event_value menu") end
            operation = params:string("event_operation")
            
            if operation == "Set" then
              if debug then print("Set operator") end
              if lookup.event_type == "param" then  -- move above operation check?
                
                preview:set(event_val_string)
                event_val_string = preview:string()
                
              -- and params:t(lookup.id) == 2 then -- params:t == 2 means it's an add_options type param
                -- if debug then print("Setting string val from options") end
                -- print("value set options")
                -- Uses event index to look up all the options for that param, then select using index
                -- event_val_string = options[menu_index]
              end
              if debug then print("Nil formatter: skipping") end
            elseif operation == "Wander" then
              event_val_string = "\u{0b1}" .. event_val_string
            end
            if debug then print("Value passed raw") end
          
          -- hack to use preview to get formatting for min/max
          -- elseif string.sub(menu_id, 1, 15) == "event_op_limit_" then
          elseif menu_id == "event_op_limit_min" or menu_id == "event_op_limit_max" then
            -- print("DEBUG menu_id = " .. menu_id) 
            -- print("DEBUG min/max event_val_string " .. (event_val_string or "nil"))
            local actual_val = preview:get()
            preview:set(event_val_string)
            event_val_string = preview:string()
            preview:set(actual_val) -- restore actual value in case we switch back to "Set" op. TEST
          end -- end of event_value stuff
      
          ------------------------------------------------
          -- Draw menu and <> indicators for scroll range
          ------------------------------------------------
          -- Leaving in param formatter and some code for truncating string in case we want to eventually add system param events that require formatting.
          local events_menu_trunc = 22 -- WAG Un-local if limiting using the text_extents approach below
          if events_index == i then
            local range =
              (menu_id == "event_category" or menu_id == "event_subcategory" or menu_id == "event_operation") 
              and params:get_range(menu_id)
              or menu_id == "event_name" and {event_subcategory_index_min, event_subcategory_index_max}
              or event_range -- if all else fails, slap -9999 to 9999 on it from set_event_range lol

            local single = menu_index == range[1] and (range[1] == range[2]) or false
            local menu_value_pre = single and "\u{25ba}" or menu_index == range[2] and "\u{25c0}" or " "
            local menu_value_suf = single and "\u{25c0}" or menu_index == range[1] and "\u{25ba}" or ""
            local events_menu_txt = first_to_upper(param_id_to_name(menu_id)) .. ":" .. menu_value_pre .. first_to_upper(string.sub(event_val_string, 1, events_menu_trunc)) .. menu_value_suf

            if debug and menu_id == "event_value" then print("menu_id = " .. (menu_id or "nil")) end
            if debug and menu_id == "event_value" then print("event_val_string = " .. (event_val_string or "nil")) end

            screen.text(events_menu_txt)
          else
            
            if debug and menu_id == "event_value" then print("menu_id = " .. (menu_id or "nil")) end
            if debug and menu_id == "event_value" then print("event_val_string = " .. (event_val_string or "nil")) end
            
            screen.text(first_to_upper(param_id_to_name(menu_id)) .. ": " .. first_to_upper(string.sub(event_val_string, 1, events_menu_trunc)))
          end

          line = line + 1
        end
        
        -- scrollbar
        screen.level(10)
        local offset = scrollbar(events_index, #events_menus, 4, 2, 40) -- (index, total, in_view, locked_row, screen_height)
        local bar_height = 4 / #events_menus * 40
        screen.rect(127, offset, 1, bar_height)
        screen.fill()
      
     -- Events editor sticky header
        screen.level(4)
        screen.rect(0,0,128,11)
        screen.fill()
        screen.move(2,8)
        screen.level(0)
        screen.text("SEG " .. event_edit_segment .. "." .. event_edit_step .. ", EVENT " .. event_edit_lane .. "/16")
        screen.move(126,8)
        screen.text_right(event_edit_status)           
      
    -- Events editor footer
        -- not needed if we use static events editor rather than scrolling
        screen.level(0)
        screen.rect(0,54,128,11)
        screen.fill()
        
        screen.level(4)
        screen.move(1,54)
        screen.line(128,54)
        screen.stroke()
        screen.level(3)
        screen.move(1,62)
        screen.text("(K2) DELETE")
        screen.move(128,62)
        if event_edit_status == "(Saved)" then
          screen.text_right("(K3) EVENTS")
        else
          screen.text_right("(K3) SAVE")
        end
      end
        
        
    -- SESSION VIEW (NON-EVENTS), not holding down Arranger segments g.keys  
    else
      ---------------------------
      -- UI elements placed here appear in all non-Events views
      ---------------------------
      
      --------------------------------------------
      -- Scrolling menus
      --------------------------------------------
      -- todo p1 move calcs out of redraw
      local menu_offset = scroll_offset_locked(menu_index, 10, 3) -- index, height, locked_row
      line = 1
      for i = 1,#menus[page_index] do
        screen.move(2, line * 10 + 8 - menu_offset)
        screen.level(menu_index == i and 15 or 3)
        
        -- Generate menu and draw <> indicators for scroll range
        if menu_index == i then
          local range = params:get_range(menus[page_index][i])
          local menu_value_suf = params:get(menus[page_index][i]) == range[1] and "\u{25ba}" or ""
          local menu_value_pre = params:get(menus[page_index][i]) == range[2] and "\u{25c0}" or " "
          local session_menu_txt = first_to_upper(param_id_to_name(menus[page_index][i])) .. ":" .. menu_value_pre .. params:string(menus[page_index][i]) .. menu_value_suf
          screen.text(session_menu_txt)
        else  
          screen.text(first_to_upper(param_id_to_name(menus[page_index][i])) .. ": " .. params:string(menus[page_index][i]))
        end
        line = line + 1
      end

      -- -- mask the area to the right of main menu since we can't rely on screen.text_extents
      -- screen.level(0)
      -- screen.rect(91, 0, 37, 64)
      -- screen.fill()
      
      -- scrollbar
      screen.level(10)
      local offset = scrollbar(menu_index, #menus[page_index], 5, 3, 52) -- (index, total, in_view, locked_row, screen_height)
      local bar_height = 5 / #menus[page_index] * 52
      screen.rect(91, offset, 1, bar_height)
      screen.fill()
      
      
      --Sticky header
      screen.level(menu_index == 0 and 15 or 4)
      screen.rect(0,0,92,11)
      screen.fill()
      screen.move(2,8)
      screen.level(0)
      screen.text(page_name)
      screen.fill()




      --------------------------------------------
      -- Transport state, pattern, chord readout
      --------------------------------------------

      screen.level(9)
      screen.rect(dash_x+1,11,33,12)
      screen.stroke()
      
      screen.level(menu_index == 0 and 15 or 13)
      screen.rect(dash_x,0,34,11)
      screen.fill()

      -- Draw transport status glyph
      screen.level(((transport_state == "starting" or transport_state == "pausing") and fast_blinky or 0) * 2)
      local x_offset = dash_x + 27
      local y_offset = 3

      -- simplify intermediate states for the glyph selection
      local transport_state = transport_state == "starting" and "playing" or transport_state == "pausing" and "paused" or transport_state
      for i = 1, #glyphs[transport_state] do
        screen.pixel(glyphs[transport_state][i][1] + x_offset, glyphs[transport_state][i][2] + y_offset)
      end
      screen.fill()
    
      --------------------------------------------    
      -- Pattern position readout
      --------------------------------------------      
      screen.level(0)
      screen.move(dash_x + 2, y_offset + 5)
      if chord_pattern_position == 0 then
        screen.text(pattern_name[active_chord_pattern].. ".RST")
      else
        screen.text(pattern_name[active_chord_pattern] ..".".. chord_pattern_position)
        -- screen.text(pattern_name[active_chord_pattern] ..".".. chord_pattern_position .. "/" .. chord_pattern_length[active_chord_pattern])
      end
      
      --------------------------------------------
      -- Chord readout
      --------------------------------------------
      screen.level(15)
      if chord_no > 0 then
        screen.move(dash_x + 17,y_offset + 16)
        screen.text_center(chord_readout)
      end
      
      
      --------------------------------------------
      -- Arranger dash
      --------------------------------------------
      local arranger_dash_y = 24
      
      -- Axis reference marks
      for i = 1,4 do
        screen.level(1)
        screen.rect(dash_x + 3, arranger_dash_y + 12 + i * 3, 1, 2)
      end
      screen.pixel(dash_x + 3, arranger_dash_y + 27)
      screen.fill()
      
      local arranger_dash_x = dash_x + (arranger_position == 0 and 5 or 3) -- If arranger is reset, add an initial gap to the x position
      
      -- Draw arranger patterns and events timeline straight from x_dash_flat
      for i = 1, dash_steps do -- alternative to #dash_patterns. This is faster at the cost of a global var which I guess is okay?
        screen.level(dash_levels[i] or 1)
        -- arranger segment patterns
        if dash_patterns[i] ~= 0 then
          screen.rect(arranger_dash_x, arranger_dash_y + 12 + (dash_patterns[i] * 3), 1, 2)
          screen.fill()
        end
        -- events pips
        screen.level(dash_events[i] or 0)
        screen.pixel(arranger_dash_x, 51)
        screen.fill()

        arranger_dash_x = arranger_dash_x + 1
      end

      -- Arranger dash rect (rendered after chart to cover chart edge overlap)
      screen.level(params:get("arranger") == 2 and 9 or 2)
      
      screen.rect(dash_x+1, arranger_dash_y+2,33,38)
      screen.stroke()
      
      -- Header
      screen.level(params:get("arranger") == 2 and 10 or 2)
      screen.rect(dash_x, arranger_dash_y+1,34,11)
      screen.fill()

      --------------------------------------------
      -- Arranger countdown timer readout
      --------------------------------------------
    
      -- Arranger time
      screen.level(params:get("arranger") == 2 and 15 or 3)

      -- Bottom left
      screen.move(dash_x +3, arranger_dash_y + 36)
      screen.text(seconds_remaining)
      
      -- Arranger mode glyph
      local x_offset = dash_x + 27
      local y_offset = arranger_dash_y + 4

      if params:string("playback") == "Loop" then
        screen.level(((
          arranger_position == arranger_length 
          and (arranger_queue == nil or arranger_queue > arranger_length)) -- if arranger is jumped on the last seg
        and fast_blinky or 0) * 2)
        for i = 1, #glyphs.loop do
          screen.pixel(glyphs.loop[i][1] + x_offset, glyphs.loop[i][2] + y_offset)
        end
      else 
        screen.level(((arranger_position == arranger_length 
          and arranger_one_shot_last_pattern) -- if arranger is jumped on the last seg
        and fast_blinky or 0) * 2)

        for i = 1, #glyphs.one_shot do
          screen.pixel(glyphs.one_shot[i][1] + x_offset, glyphs.one_shot[i][2] + y_offset)
        end
      end
      screen.fill()
      
      --------------------------------------------
      -- Arranger position readout
      --------------------------------------------      
      screen.level(0)
      screen.move(dash_x + 2,arranger_dash_y + 9)

      if arranger_position == 0 then
        if arranger_queue == nil then
          screen.text("RST")
        elseif arranger_active == false then
          screen.text((arranger_queue or util.wrap(arranger_position + 1, 1, arranger_length)) .. ".".. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
        else
          screen.text(arranger_queue .. ".0")
        end
      elseif arranger_active == false then
        if chord_pattern_position == 0 then -- condition for when pattern is reset to position 0 and is in-between segments
          screen.text(arranger_position .. ".0")
        elseif arranger_position == arranger_length then
          if params:string("playback") == "Loop" then
            screen.text("LP." .. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
          else
            screen.text("EN." .. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
          end
        else
          screen.text((arranger_queue or util.wrap(arranger_position + 1, 1, arranger_length)) .. ".".. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
        end
      else
        screen.text(arranger_position .. "." .. chord_pattern_position)
        
      end      
      screen.fill()
      
      
    end -- of event vs. non-event check
  end
  screen.update()
end