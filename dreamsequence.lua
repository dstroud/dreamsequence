-- Dreamsequence
-- 1.4 240818 Dan Stroud
-- llllllll.co/t/dreamsequence
--
-- Chord-based sequencer, 
-- arpeggiator, and harmonizer 
-- for Monome Norns+Grid
-- 
-- K1: Alt (hold)
-- K2: Pause/Stop(2x)
-- K3: Play
--
-- E1: Scroll Grid
-- E2: Select
-- E3: Edit (+K1 to defer)
--
-- Crow IN 1: CV in
-- Crow IN 2: Trigger in
-- Crow OUT 1: CV out
-- Crow OUT 2: Envelope out
-- Crow OUT 3: Events out
-- Crow OUT 4: Clock out


-- stuff needed by includes
dreamsequence = {}

-- layout and palette
xy = {
  dash_x = 93,
  header_x = 0,
  header_y = 8,
  menu_y = 8,
  scrollbar_y = 12
}

local lvl_normal = {
  menu_selected = 15,
  menu_deselected = 4,
  pane = 15,
  pane_selected = 0,  -- also chart black
  pane_deselected = 3,
  pane_dark = 7,
  chart_deselected = 3,
}

local lvl_dimmed = {
  menu_selected = 7,
  menu_deselected = 2,
  pane = 7,
  pane_selected = 1,
  pane_deselected = 3, -- not dimmed
  pane_dark = 3,
  chart_deselected = 2,
}

lvl = lvl_normal -- required for includes:dashboards.lua

blinky = 0 -- must be global for dashboards.lua todo look into this
local led_high = 15
local led_med = 7
local led_low = 3
local led_high_blink = 15 - blinky * 4
local led_med_blink = 7 - blinky * 2
local led_low_blink = 3 - blinky
led_pulse = 0  -- must be global for dashboards.lua todo look into this

max_seqs = 3
max_seq_cols = 15 - max_seqs
max_seq_patterns = 4
max_seq_pattern_length = 16


-- base scales used to define triads
dreamsequence.scales = {

-- canonical scales
"Major", -- "Ionian", 
"Natural Minor", -- "Aeolian", 
"Harmonic Minor",
"Melodic Minor",
"Dorian",
"Phrygian",
"Lydian",
"Mixolydian",
"Locrian",

-- -- some nice additions that work, too, but needs to think about handling degree readout
-- "Altered Scale",  -- double flats in F, might wait for norns.ttf
-- "Harmonic Major", -- double flats in Db, might wait for norns.ttf
-- "Overtone",
}

-- pre-init bits n bobs
norns.version.required = 231114 -- rolling back for Fates but 240221 is required for link support
g = grid.connect()
include(norns.state.shortname.."/lib/includes")

-- load global scale mask file if present
local filepath = norns.state.data
masks = {} -- has to be global because of pset write function. todo p2 fix

if util.file_exists(filepath) then
  if util.file_exists(filepath.."masks.data") then
    masks = tab.load(filepath.."masks.data")
    print("table >> read: " .. filepath.."masks.data")
  else
    masks = gen_default_masks()
  end
end

theory.masks = masks


clock.link.stop() -- transport won't start if external link clock is already running

-- pre-init locals
local latest_strum_coroutine = coroutine.running()

--#region init
function init()
  -----------------------------
  -- todo p0 prerelease ALSO MAKE SURE TO UPDATE ABOVE!
  local version = 010400 --1.4.0
  -----------------------------

  function read_prefs()  
    prefs = {}
    local filepath = norns.state.data
    if util.file_exists(filepath) then
      if util.file_exists(filepath.."prefs.data") then
        local p = tab.load(filepath.."prefs.data")
        if (tonumber(p.last_version) or 0) >= 010400 then -- todo p0 prerelease UPDATE if prefs have changed
          print("table >> read: " .. filepath.."prefs.data")
          prefs = p
        else
          print("Ignoring obsolete prefs.data")
        end
      else
        print("table >> missing: " .. filepath.."prefs.data")
      end
    else
      print("table >> missing: " .. filepath.."prefs.data")
    end
  end
  read_prefs()

  if prefs ~= nil then
    nb.voice_count = prefs.voice_instances or 1
    print("nb.voice_count set to " .. nb.voice_count)
  end

  nb:init()


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
    nb:stop_all()
    note_players = nil -- clears bundled crow/midi players for next script
    clock.link.stop()
    
    if preinit_jf_mode == 0 then
      crow.ii.jf.mode(preinit_jf_mode)
      print("Restoring jf.mode to " .. preinit_jf_mode)
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

  -- functions and globals used by params
  pattern_name = {"A","B","C","D"}

  -- show or hide midi channel param/menu
  local function set_channel_vis(id, channel_param)
    local old_visible = params:visible(channel_param)
    local player = nb.players[id]
    local new_visible = player and player.channel
    if old_visible ~= new_visible then
      if new_visible then
        params:show(channel_param)
      else
        params:hide(channel_param)
      end
      _menu.rebuild_params()
      gen_menu()
    end
  end

  ----------------------------------------
  params:add_separator ("DREAMSEQUENCE")

  ------------------
  -- PREFERENCES PARAMS --
  ------------------
  -- Persistent settings saved to prefs.data and managed outside of .pset files

  params:add_group("preferences", "PREFERENCES", 16 + 16) -- 16 midi ports

  -- params:add_separator("pset","pset")

  params:add_option("default_pset", "Default song", {"New", "Last PSET", "Template"}, 1)
  params:set_save("default_pset", false)
  -- param_option_to_index is used rather than set_param_string to handle any invalid/changed saved values
  params:set("default_pset", param_option_to_index("default_pset", prefs.default_pset) or 1)
  params:set_action("default_pset", function() save_prefs() end)

  params:add_trigger("save_template", "Save template")
  params:set_save("save_template", false)
  params:set_action("save_template", function() params:write(00,"template") end)

  params:add_trigger("save_masks", "Save masks")
  params:set_save("save_masks", false)
  params:set_action("save_masks", function() write_global_scales() end)
  
  -- params:add_separator("interaction","interaction")

  params:add_option("sync_views", "Sync views", {"Off", "On"}, 2)
  params:set_save("sync_views", false)
  params:set("sync_views", param_option_to_index("sync_views", prefs.sync_views) or 2)
  params:set_action("sync_views", function() save_prefs() end)

  params:add_option("notifications", "Notifications", {"Off", "Momentary", "Brief", "Extended"}, 3)
  params:set_save("notifications", false)
  params:set("notifications", param_option_to_index("notifications", prefs.notifications) or 3)
  params:set_action("notifications", function() save_prefs() end)

  params:add_option("preview_notes", "Preview notes", {"Off", "On"}, 2)
  params:set_save("preview_notes", false)
  params:set("preview_notes", param_option_to_index("preview_notes", prefs.preview_notes) or 2)
  params:set_action("preview_notes", function() save_prefs() end)

  -- params:add_separator("dashboard","dashboard")

  local defaults = {"Metro T+", "Arranger chart", "Chord progress", "Chord name"}
  -- todo probably a better way to do this rather than having these dummy funcs being called
  local function init_dummy_funcs()
    function calc_seconds_remaining() end
    function calc_seconds_elapsed() end
    function gen_dash_chord_viz() end
  end
  init_dummy_funcs()
  xy.dash_x = 129 -- kinda silly but in case user has no dashboards, shift over the scrollbar

  max_dashboards = 4
  for dash_no = 1, max_dashboards do -- limiting to 4 dashboards for now
    params:add_option("dash_" .. dash_no, "Dash " .. dash_no, dash_name, 1)
    params:set_save("dash_" .. dash_no, false)
    params:set("dash_" .. dash_no, param_option_to_index("dash_" .. dash_no, prefs["dash_" .. dash_no] or defaults[dash_no]) or 1 )
    params:set_action("dash_" .. dash_no, 
      function(val)
        save_prefs()
        dash_list[dash_no] = dash_functions[dash_ids[val]]

        -- redefine dash functions depending on selection

        -- init functions in inactive states
        init_dummy_funcs()
        seconds_remaining = "00:00"
        seconds_elapsed_raw = 0

        for dash_no = 1, max_dashboards do -- check every param each time one is changed
          local dash = params:string("dash_" .. dash_no)
          if dash == "Metro T-" then

            function calc_seconds_remaining()
              if arranger_state == "on" then
                percent_step_elapsed = (arranger_position == 0 and 0 or sprocket_chord.phase) / (sprocket_chord.division * 4 * seq_lattice.ppqn) -- ppc
                seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - (percent_step_elapsed or 0))
              else
                seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - (steps_remaining_in_active_pattern or 0))
              end
              seconds_remaining = s_to_min_sec(math.ceil(seconds_remaining))
            end

            xy.dash_x = 93

          elseif dash == "Metro T+" then --redefine function if needed
            function calc_seconds_elapsed()
              seconds_elapsed_raw = seconds_elapsed_raw + .1
              seconds_elapsed = s_to_min_sec(seconds_elapsed_raw)
            end

            xy.dash_x = 93

          elseif dash == "Chord kbd" then -- generate chord keyboard diagram for dash

            function gen_dash_chord_viz()
              local txp = params:get("tonic")
              local w = {0, 2, 4, 5, 7, 9, 11} -- white keys
              local b = {1, 3, 6, 8, 10} -- black keys
              local keystate = {}
              dash_keys_white = {}
              dash_keys_black = {}

              for i = 1, #chord_raw do
                keystate[util.wrap(chord_raw[i] + txp, 0, 11)] = true
              end

              for i = 1, 7 do
                dash_keys_white[i] = keystate[w[i]]
              end

              for i = 1, 5 do
                dash_keys_black[i] = keystate[b[i]]
              end
            end

          elseif dash ~= "Off" then
            xy.dash_x = 93
          end
        end

      end)
  end
  
  params:add_option("crow_pullup", "Crow pullup", {"Off", "On"}, 2)
  params:set_save("crow_pullup", false)
  params:set("crow_pullup", param_option_to_index("crow_pullup", prefs.crow_pullup) or 2)
  params:set_action("crow_pullup", function(val) crow_pullup(val); save_prefs() end)
  
  params:add_number("voice_instances", "Voice instances", 1, 4, 1)
  params:set_save("voice_instances", false)
  params:set("voice_instances", (prefs.voice_instances or 1))
  params:set_action("voice_instances", function() save_prefs() end)

  local function config_enc(enc, val)
    local accel = 1 - (val % 2)
    local val = (9 - val + accel) / 2
    -- print("enc " .. enc .. ": sens " .. util.round(val) .. ", accel " .. (accel == 1 and "on" or "off"))
    norns.enc.sens(enc, val)
    norns.enc.accel(enc, accel == 1)
  end

  for i = 1, 3 do
    params:add_option("config_enc_" .. i, "Enc " .. i, {"Slower -accel", "Slower +accel", "Slow, -accel", "Slow +accel", "Normal -accel", "Normal +accel", "Fast -accel", "Fast +accel"}, 6)
    params:set_save("config_enc_" .. i, false)
    params:set("config_enc_" .. i, ((prefs["config_enc_" .. i]) or 6))
    params:set_action("config_enc_" .. i, function(val) save_prefs(); config_enc(i, val) end)
  end
  
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

  params:add_option("arranger", "Arranger", {"Off", "On"}, 1) -- action set post-bang
  
  params:add_option("playback", "Playback", {"1-shot", "Loop"}, 2)
  params:set_action("playback", function() update_arranger_next() end)
    
    
  ------------------
  -- SONG PARAMS --
  ------------------
  params:add_group("song", "SONG", 13)
 
  params:add_number("tonic", "Tonic", -12, 12, 0, function(param) return transpose_string(param:get()) end)
  params:set_action("tonic", function() gen_chord_readout() end)

  local scales = {}
  for i = 1, #dreamsequence.scales do
    scales[i] = dreamsequence.scales[i]:gsub("%f[%a]Minor%f[%A]", "Min")
  end
  params:add_option("scale", "Scale", scales, 1) -- post-bang action

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
  params:add_group("chord", "CHORD", 18)

  nb:add_param("chord_voice_raw", "Voice raw")
  params:hide("chord_voice_raw")

  gen_voice_lookups() -- required to build front-end voice selectors (chord_voice_raw dependency)
  params:add_option("chord_voice", "Voice", voice_param_options, 1)
  params:set_action("chord_voice",
    function(index)
      params:set("chord_voice_raw", voice_param_index[index])
      set_channel_vis(params:string("chord_voice_raw"), "chord_channel")
    end
  )

  params:add_number("chord_channel", "Channel", 1, 16, 1)
  params:hide("chord_channel")

  params:add_option("chord_mute", "Play/mute", {"Play", "Mute"}, 1)
  
  params:add_number("chord_octave","Octave", -4, 4, 0)

  params:add_number("chord_range", "Range", 0, 64, 0, 
    function(param)
      local val = param:get()

      if val == 0 then
        return("Chord")
      -- elseif params:get("chord_notes") > params:get("chord_range") then -- circle back on this. might keep
        -- return(val .. "*")
      else
        return(val)
      end
    end
  )

  params:add_number("chord_notes", "Max notes", 1, 25, 25,
  function(param)
    local val = param:get()

    if val == 25 then
      return("Range")
    else
      return(val)
    end
  end
  )
  
  params:add_number("chord_inversion", "Inversion", 0, 16, 0) -- todo negative inversion

  params:add_option("chord_style", "Strum", {"Off", "Low-high", "High-low"}, 1)
  
  params:add_number("chord_strum_length", "Strum length", 1, 15, 15, function(param) return strum_length_string(param:get()) end)
  
  params:add_number("chord_timing_curve", "Strum curve", -100, 100, 0, function(param) return percent(param:get()) end)

  params:add_number("chord_div_index", "Step length", 5, 57, 15, function(param) return divisions_string(param:get()) end)
  -- action required here for pset loading. Will then be redefined post-bang with action for lattice
  params:set_action("chord_div_index",function(val) chord_div = division_names[val][1] end)

  -- chord_div needs to be set *before* the bang happens
  chord_div = division_names[params:get("chord_div_index")][1]
  
  params:add_number("chord_duration_index", "Duration", 0, 57, 0, function(param) return durations_string(param:get()) end)
  params:set_action("chord_duration_index",function(val) chord_duration = val == 0 and chord_div or division_names[val][1] end)

  params:add_number("chord_swing", "Swing", 50, 99, 50, function(param) return percent(param:get()) end)

  params:add_number("chord_dynamics", "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)

  params:add_number("chord_dynamics_ramp", "Ramp", -100, 100, 0, function(param) return percent(param:get()) end) --todo p1 update param and docs to "Tracking"

  -- will act on current pattern unlike numbered seq param
  max_chord_pattern_length = 16
  params:add_number("chord_pattern_length", "Pattern length", 1, max_chord_pattern_length, 4)
  params:set_action("chord_pattern_length", function(val) chord_pattern_length[active_chord_pattern] = val  end)


  ------------------
  -- SEQ PARAMS --
  ------------------

  local note_map = {"Triad", "Chord raw", "Chord extd.", "Chord dense", "Scale", "Scale+tr.", "Chromatic", "Chromatic+tr.", "Kit"} -- used by all but chord
  for i = 1, 8 do
    table.insert(note_map, "Mask " .. i)
    table.insert(note_map, "Mask " .. i .. "+tr.")
  end

  for seq_no = 1, max_seqs do

    params:add_group("seq"..seq_no, "SEQ "..seq_no, 37)

    params:add_option("seq_note_map_"..seq_no, "Notes", note_map, 1)
    
    params:add_option("seq_grid_"..seq_no, "Grid", {"Mono", "Pool L→", "Pool ←R", "Pool Random"}, 1)

    params:add_number("seq_polyphony_"..seq_no, "Polyphony", 1, max_seq_cols, 1)

    params:add_option("seq_start_on_"..seq_no, "Start", {"Loop", "Every step", "Chord steps", "Empty steps", "Measure", "Off/trigger"}, 1)

    params:add_option("seq_reset_on_"..seq_no, "Reset",         {"Every step", "Chord steps", "Empty steps", "Measure", "Off/trigger"}, 4)

    params:add_binary("seq_start_"..seq_no, "Trigger start", "trigger")
    params:set_action("seq_start_"..seq_no, function()  play_seq[seq_no] = true end)
    
    params:add_binary("seq_reset_"..seq_no, "Trigger reset", "trigger")
    params:set_action("seq_reset_"..seq_no, function() reset_seq_pattern(seq_no) end)

    params:add_option("seq_pattern_change_"..seq_no, "Change", {"Instantly", "On loop", "On reset"}, 1)
    params:set_action("seq_pattern_change_"..seq_no, 
      function(val) -- immediately switch to any pending pattern q
        if val == 1 and seq_pattern_q[seq_no] then
          params:set("seq_pattern_" .. seq_no, seq_pattern_q[seq_no])
          seq_pattern_q[seq_no] = false
        end
      end
    )

    params:add_number("seq_div_index_"..seq_no, "Step length", 1, 57, 8, function(param) return divisions_string(param:get()) end)

    nb:add_param("seq_voice_raw_"..seq_no, "Voice raw")
    params:hide("seq_voice_raw_"..seq_no)

    params:add_option("seq_voice_"..seq_no, "Voice", voice_param_options, 1)
    params:set_action("seq_voice_"..seq_no,
      function(index)
        params:set("seq_voice_raw_"..seq_no, voice_param_index[index])
        set_channel_vis(params:string("seq_voice_raw_"..seq_no), "seq_channel_"..seq_no)
      end
    )

    params:add_number("seq_channel_"..seq_no, "Channel", 1, 16, 1)
    params:hide("seq_channel_"..seq_no)

    params:add_option("seq_mute_"..seq_no, "Play/mute", {"Play", "Mute"}, 1)

    params:add_number("seq_duration_index_"..seq_no, "Duration", 0, 57, 0, function(param) return durations_string(param:get()) end)
    params:set_action("seq_duration_index_"..seq_no, function(val) seq_duration[seq_no] = val == 0 and division_names[params:get("seq_div_index_"..seq_no)][1] or division_names[val][1] end)

    
    params:add_number("seq_pattern_rotate_"..seq_no, "Pattern ↑↓", 0, max_seq_pattern_length - 1, 0, nil, true) -- endless but confusing
    params:set_action("seq_pattern_rotate_"..seq_no, function(val) seq_pattern_rotate_abs(seq_no, val) end)

    for pattern = 1, max_seq_patterns do
      params:add_number("prev_seq_pattern_rotate_"..seq_no .. "_" .. pattern, "prev_seq_pattern_rotate_"..seq_no .. "_" .. pattern, (max_seq_pattern_length * -1), max_seq_pattern_length, 0)
      params:hide("prev_seq_pattern_rotate_"..seq_no .. "_" .. pattern)
    end


    params:add_number("seq_loop_rotate_"..seq_no, "Loop ↑↓", -9999, 9999, 0) -- can't use math.huge or is breaks random event values
    params:set_action("seq_loop_rotate_"..seq_no, function(val) seq_loop_rotate_abs(seq_no, val) end)

    for pattern = 1, max_seq_patterns do
      params:add_number("prev_seq_loop_rotate_"..seq_no .. "_" .. pattern, "prev_seq_loop_rotate_"..seq_no .. "_" .. pattern, -math.huge, math.huge, 0)
      params:hide("prev_seq_loop_rotate_"..seq_no .. "_" .. pattern)
    end


    params:add_number("seq_shift_"..seq_no, "Pattern ←→", 0, max_seq_cols - 1, 0, nil, true)
    params:set_action("seq_shift_"..seq_no, function(val) seq_shift_abs(seq_no, val) end)

    for pattern = 1, max_seq_patterns do
      params:add_number("prev_seq_shift_"..seq_no .. "_" .. pattern, "prev_seq_shift_"..seq_no .. "_" .. pattern, -max_seq_cols, max_seq_cols, 0)
      params:hide("prev_seq_shift_"..seq_no .. "_" .. pattern)
    end


    params:add_option("seq_pattern_"..seq_no, "Pattern", pattern_name, 1)
    params:set_action("seq_pattern_"..seq_no,
    function(val)
      active_seq_pattern[seq_no] = val -- store in table so we don't need x4 params
      params:set("seq_pattern_length_"..seq_no, seq_pattern_length[seq_no][val])
      
      local current_pattern_rotation = params:get("seq_pattern_rotate_" .. seq_no)
      if current_pattern_rotation ~= params:get("prev_seq_pattern_rotate_" .. seq_no .. "_" .. val) then
        seq_pattern_rotate_abs(seq_no, current_pattern_rotation)
      end

      local current_loop_rotation = params:get("seq_loop_rotate_" .. seq_no)
      if current_loop_rotation ~= params:get("prev_seq_loop_rotate_" .. seq_no .. "_" .. val) then
        seq_loop_rotate_abs(seq_no, current_loop_rotation)
      end

      local current_shift = params:get("seq_shift_" .. seq_no)
      if current_shift ~= params:get("prev_seq_shift_" .. seq_no .. "_" .. val) then
        seq_shift_abs(seq_no, current_shift)
      end

      grid_dirty = true
    end
    )
    -- issue: if an event runs this before changing pattern, it won't operate on the new pattern. might be confusing
    params:add_number("seq_pattern_length_"..seq_no, "Pattern length", 1, max_seq_pattern_length, 8)
    params:set_action("seq_pattern_length_"..seq_no,
      function(val)
        seq_pattern_length[seq_no][active_seq_pattern[seq_no]] = val -- store in table so we don't need x4 params
        grid_dirty = true
      end
    )

    params:add_number("seq_octave_"..seq_no, "Octave", -4, 4, 0)
  
    params:add_number("seq_swing_"..seq_no, "Swing", 50, 99, 50, function(param) return percent(param:get()) end)
  
    params:add_number("seq_dynamics_"..seq_no, "Dynamics", 0, 100, 70, function(param) return percent(param:get()) end)
  
    params:add_number("seq_accent_"..seq_no, "Accent", -100, 100, 0, function(param) return percent(param:get()) end)
    
    params:add_number("seq_probability_"..seq_no, "Probability", 0, 100, 100, function(param) return percent(param:get()) end)
    
  end


  ------------------
  -- MIDI HARMONIZER PARAMS --
  ------------------
  params:add_group("midi_harmonizer", "MIDI HARMONIZER", 9)

  params:add_option("midi_note_map", "Notes", note_map, 1)

  nb:add_param("midi_voice_raw", "Voice raw")
  params:hide("midi_voice_raw")

  params:add_option("midi_voice", "Voice", voice_param_options, 1)
  params:set_action("midi_voice", 
    function(index)
      params:set("midi_voice_raw", voice_param_index[index])
      set_channel_vis(params:string("midi_voice_raw"), "midi_channel")
    end
  )

  params:add_number("midi_channel", "Channel", 1, 16, 1)
  params:hide("midi_channel")

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
  params:add_group("cv_harmonizer", "CV HARMONIZER", 11)
  
  nb:add_param("crow_voice_raw", "Voice raw")
  params:hide("crow_voice_raw")
  
  params:add_option("crow_voice", "Voice", voice_param_options, 1)
  params:set_action("crow_voice",
    function(index)
      params:set("crow_voice_raw", voice_param_index[index])
      set_channel_vis(params:string("crow_voice_raw"), "crow_channel")
    end
  )

  params:add_number("crow_channel", "Channel", 1, 16, 1)
  params:hide("crow_channel")

  params:add_number("crow_div_index", "Trigger", 0, 57, 0, function(param) return crow_trigger_string(param:get()) end)
  params:set_action("crow_div_index", function(val) crow_div = val == 0 and 0 or division_names[val][1] end) -- overwritten

  params:add_option("crow_note_map", "Notes", note_map, 1)

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
  -- EVENT-SPECIFIC PARAMS --
  ------------------  
  params:add_number("next_arranger_pos", "Next Arranger Position", 1, 64, 1) -- event action as we need to bang even if index hasn't changed and don't want to bang on init/pset load
  params:hide("next_arranger_pos")

  ------------------
  -- NB PARAMS --
  ------------------  
  params:add_separator("VOICES")
  nb:add_player_params() -- modified to also add nb.indices
  

  -- insert MIDI events for active MIDI ports

  -- program change
  for port = 1, 16 do
    if midi.vports[port].connected then
      for ch = 1, 16 do

        -- generate param for each port/channel
        local name = "midi_bank_msb_" .. port .. "_" .. ch
        params:add_number(name, name, 1, 128, 1)
        params:set_save(name, false)
        params:hide(name)

        -- using event action rather than param action since:
        -- 1. we don't want this being sent at param bang and 
        -- 2. we do want it to bang every time event fires, even if param index hasn't changed
        table.insert(events_lookup, {
          category = "MIDI port " .. port,
          subcategory = "Channel " .. ch,
          event_type = "param",
          id = name,
          name = "Bank select",
          action = 'midi.vports[' .. port .. ']:cc(0, params:get("' .. name .. '"), ' .. ch .. ')'
        })


        -- generate param for each port/channel
        local name = "midi_bank_lsb_" .. port .. "_" .. ch
        params:add_number(name, name, 1, 128, 1)
        params:set_save(name, false)
        params:hide(name)

        -- using event action rather than param action since:
        -- 1. we don't want this being sent at param bang and 
        -- 2. we do want it to bang every time event fires, even if param index hasn't changed
        table.insert(events_lookup, {
          category = "MIDI port " .. port,
          subcategory = "Channel " .. ch,
          event_type = "param",
          id = name,
          name = "Bank select (fine)",
          action = 'midi.vports[' .. port .. ']:cc(32, params:get("' .. name .. '"), ' .. ch .. ')'
        })


        -- generate param for each port/channel
        local name = "midi_program_change_" .. port .. "_" .. ch
        params:add_number(name, name, 1, 128, 1)
        params:set_save(name, false)
        params:hide(name)

        -- using event action rather than param action since:
        -- 1. we don't want this being sent at param bang and 
        -- 2. we do want it to bang every time event fires, even if param index hasn't changed
        table.insert(events_lookup, {
          category = "MIDI port " .. port,
          subcategory = "Channel " .. ch,
          event_type = "param",
          id = name,
          name = "Program change",
          action = 'midi.vports[' .. port .. ']:program_change(params:get("' .. name .. '") - 1, ' .. ch .. ')'
        })

      end
    end
  end

  -- -- bank select MSB
  -- for port = 1, 16 do
  --   if midi.vports[port].connected then
  --     for ch = 1, 16 do
  --       -- generate param for each port/channel
  --       local name = "midi_bank_msb_" .. port .. "_" .. ch
  --       params:add_number(name, name, 1, 128, 0)
  --       params:set_save(name, false)
  --       params:hide(name)

  --       -- using event action rather than param action since:
  --       -- 1. we don't want this being sent at param bang and 
  --       -- 2. we do want it to bang every time event fires, even if param index hasn't changed
  --       table.insert(events_lookup, {
  --         category = "MIDI port " .. port,
  --         subcategory = "Channel " .. ch,
  --         event_type = "param",
  --         id = name,
  --         name = "Bank select",
  --         action = 'midi.vports[' .. port .. ']:cc(0, params:get("' .. name .. '"), ' .. ch .. ')'
  --       })
  --     end
  --   end
  -- end

  --   -- bank select LSB
  --   for port = 1, 16 do
  --     if midi.vports[port].connected then
  --       for ch = 1, 16 do
  --         -- generate param for each port/channel
  --         local name = "midi_bank_lsb_" .. port .. "_" .. ch
  --         params:add_number(name, name, 1, 128, 0)
  --         params:set_save(name, false)
  --         params:hide(name)
  
  --         -- using event action rather than param action since:
  --         -- 1. we don't want this being sent at param bang and 
  --         -- 2. we do want it to bang every time event fires, even if param index hasn't changed
  --         table.insert(events_lookup, {
  --           category = "MIDI port " .. port,
  --           subcategory = "Channel " .. ch,
  --           event_type = "param",
  --           id = name,
  --           name = "Bank select (fine)",
  --           action = 'midi.vports[' .. port .. ']:cc(32, params:get("' .. name .. '"), ' .. ch .. ')'
  --         })
  --       end
  --     end
  --   end

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
  -- todo derivative of gen_voice_lookup() but mind the different trim width
  local function gen_category_name(string)
    local string = string
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

  for n, k in pairs(sorted) do
    local name = sorted[n]
    -- block voices we have replacements for
    if string.sub(name, 1, 5) ~= "midi:"
    and name ~= "crow 1/2"
    and name ~= "crow 3/4"
    and name ~= "crow para" -- todo test
    -- and name ~= "jf kit" -- todo test
    and name ~= "jf mpe" then

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
            name = util.trim_string_to_width(param.name, 84),
            subcategory	= separator,
            event_type = "param",
          }
          table.insert(events_lookup, event)
        elseif param.t == 0 then
          separator = util.trim_string_to_width(param.name, 78)
        end
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
  
  params:add_number("event_lane", "Lane", 1, 15, 1) -- Selected event lane in event editor. 16 == all
  params:hide("event_lane")

  -- event quick action ideas:
  -- copy pattern forward/back
  -- apply to pattern A/B/C/D
  -- pattern defaults
  -- apply single pattern default
  -- apply all pattern defaults
  -- Reset lane (all segments)
  -- copy/paste lane (need to think about steps tho)
  -- etc...
  event_quick_actions = {"Quick actions:", "Clear segment events"}
  params:add_option("event_quick_actions", "Event actions", event_quick_actions, 1)
  params:hide("event_quick_actions")

  -- options will be dynamically swapped out based on the current event_name param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  event_operation_options_continuous = {"Set", "Increment", "Wander", "Random"}
  event_operation_options_discreet = {"Set", "Random"}
  event_operation_options_trigger = {"Trigger"} 
  derive_value_type(1) -- populate value_type for this entry
  params:add_option("event_operation", "Operation", _G["event_operation_options_" .. events_lookup[1].value_type], 1)
  params:hide("event_operation")

  -- todo p1 needs paramcontrol if this is even still used?
  params:add_number("event_value", "Value", -math.huge, math.huge, get_default_event_value())
  params:hide("event_value")

  params:add_number("event_probability", "Probability", 0, 100, 100, function(param) return percent(param:get()) end)
  params:hide("event_probability")
  
  params:add_option("event_op_limit", "Limit", {"Off", "Clamp", "Wrap"}, 1)
  params:set_action("event_op_limit",function() gen_menu_events() end)
  params:hide("event_op_limit")

  params:add_option("event_op_limit_random", "Limit", {"Off", "On"}, 1)
  params:set_action("event_op_limit_random", function() gen_menu_events() end)
  params:hide("event_op_limit_random")

  params:add_number("event_op_limit_min", "Min", -math.huge, math.huge, 0)
  params:hide("event_op_limit_min")
  
  params:add_number("event_op_limit_max", "Max", -math.huge, math.huge, 0)
  params:hide("event_op_limit_max")



  -- crow events load their actions from the event table to avoid being set on load via bang (last to fire wins!)
  for out = 1, 4 do
    -- params:add_option("crow_gate_" .. out, "Gate", {0, 10}, 1, function(param) return param:get() .. "v" end)
    params:add_number("crow_gate_" .. out, "Gate", 0, 1, 0, function(param) return param:get() * 10 .. "v" end)
    params:hide("crow_gate_" .. out)
    params:set_save("crow_gate_" ..out, false)
    
    params:add_number("crow_v_12_" .. out, "1/12v increments", -60, 120, 0, function(param) return volts_string_note(12, param:get()) end)
    params:hide("crow_v_12_" .. out)
    params:set_save("crow_v_12_" ..out, false)
    
    params:add_number("crow_v_10_" .. out, "1/10v increments", -50, 100, 0, function(param) return volts_string(10, param:get()) end)
    params:hide("crow_v_10_" .. out)
    params:set_save("crow_v_10_" .. out, false)
    
    params:add_number("crow_v_100_" .. out, "1/100v increments", -500, 1000, 0, function(param) return volts_string(100, param:get()) end)
    params:hide("crow_v_100_" .. out)
    params:set_save("crow_v_100_" .. out, false)

    params:add_number("crow_v_1000_" .. out, "1/1000v increments", -5000, 10000, 0, function(param) return volts_string(1000, param:get()) end)
    params:hide("crow_v_1000_" .. out)
    params:set_save("crow_v_1000_" .. out, false)
    
    params:add_number("crow_5v_8_steps_" .. out, "5v 8-steps", 1, 8, 1)
    params:hide("crow_5v_8_steps_" .. out)
    params:set_save("crow_5v_8_steps_" .. out, false)
  end
  
  
  -----------------------------
  -- POST-PARAM INIT STUFF
  -----------------------------

  --#region grid globals
  function grid_size()
    if g.cols >= 16 then
      rows = g.rows >= 16 and 16 or 8
      print("Configured for 16x" .. rows .. " Grid")
    else
      rows = 8
      print("16x8 or 16x16 Grid required. Add in SYSTEM >> DEVICES >> GRID")
    end
    extra_rows = 0 -- rows - 8 -- todo prefs for various layouts
  end 

  function grid.add(dev)
    grid_size()
  end
  grid_size()
  --#endregion grid globals


  start = false
  metro_measure = false
  send_continue = false
  transport_state = "stopped"
  clock_start_method = "start"
  global_clock_div = 48 -- todo replace with ppqn and update div lookup to be fractional
  build_scale()
  transport_multi_stop() --   -- Send out MIDI stop on launch if clock ports are enabled
  arranger_state = "off"
  chord_pattern_retrig = true
  play_seq = {false, false}
  grid_dirty = true
  grid_views = {"Arranger","Chord","Seq"}
  grid_view_keys = {}
  grid_view_name = grid_views[1]


  -- ui
  cycle_1_16 = 1
  -- led_pulse = 0
  screen_view_name = "Session"
  dash_y = 0

  --#region scale globals
  editing_scale = 1
  scale_index = 0
  --#endregion


  --#region chord globals
  chord_menu_index = 1
  editing_chord_root = 0
  chord_pattern_length = {4,4,4,4}
  set_chord_pattern(1)
  chord_pattern_q = false
  chord_no = 0
  chord_key_count = 0
  pending_chord_disable = {} -- [x][y][chord_pattern] chord pattern to disable on key up
  chord_pattern_position = 0
  chord_raw = {}
  current_chord_x = 1 -- WAG here now that we're using this rather than _c for readout. Might break something.
  current_chord_o = 0
  current_chord_d = 1 -- to default readout/note transformations
  -- next_chord_x = 0
  -- next_chord_o = 0
  -- next_chord_d = 1
  chord_pattern = {{},{},{},{}}
  for p = 1, 4 do
    for i = 1, max_chord_pattern_length do
      chord_pattern[p][i] = 0
    end
  end
  --#endregion chord globals


  --#region page and menu globals
  pages = {"SONG", "CHORD"}
  for i = 1, max_seqs do
    table.insert(pages, "SEQ " .. i)
  end
  table.insert(pages, "MIDI")
  table.insert(pages, "CV")
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  gen_menu()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  preview_param_q_get = {}
  preview_param_q_string = {}
  transport_active = false
  --#endregion page and menu globals


  --#region arranger globals
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
  --#endregion arranger globals

  d_cuml = 0
  grid_interaction = nil
  norns_interaction = nil
  event_lanes = {}
  for i = 1, 15 do
    event_lanes[i] = {} --{type = "single", id = nil}
  end
  events = {}
  events_length = {}
  
  -- init events table and events_length table
  for segment = 1, max_arranger_length do
    events[segment] = {}
    for step = 1, max_chord_pattern_length do
      events[segment][step] = {}
    end
    events_length[segment] = max_chord_pattern_length
  end
  
  -- event menu init
  events_index = 1
  selected_events_menu = "event_category"
  change_category()
  params:set("event_name", event_subcategory_index_min)  -- Overwrites initial param value
  change_subcategory()
  change_event()
  gen_menu_events()
  events_menus =  {"event_category", "event_subcategory", "event_name", "event_probability"}
  event_edit_segment = 0 --todo p1 rename to event_edit_segment
  event_edit_step = 0
  event_edit_lane = 0

  steps_remaining_in_arrangement = 0
  elapsed = 0
  percent_step_elapsed = 0
  seconds_remaining = 0
  arranger_pattern_key_first = nil -- simpler way to identify the first key held down so we can handle this as a "copy" action and know when to act on it or ignore it. don't need a whole table.
  arranger_loop_key_count = 0 -- rename arranger_events_strip_key_count?
  view_key_count = 0
  event_key_count = 0
  key_count = 0

  --#region seq globals
  -- todo: rethink this structure. Might make more sense to consolidate into one table per seq_no
  seq_pattern = {}
  seq_pattern_length = {}
  seq_pattern_position = {}
  seq_duration = {}
  active_seq_pattern = {}
  seq_pattern_q = {}
  selected_seq_no = 1 -- unlike chord, selected is not always the same as *active*
  pattern_copy_performed = {} -- also used for chord which always uses index 1
  pattern_key_count = 0 -- also used for chord
  update_seq_pattern = {} -- flag and store patterns which seqs need to be set to on pattern key release
  pattern_keys = {} -- also used for chord which always uses index 1. used to highlight all held pattern keys
  copied_seq_no = nil
  copied_pattern = nil

  for seq_no = 1, max_seqs do
    -- initialize seq pattern tables
    seq_pattern[seq_no] = {}
    seq_pattern_length[seq_no] = {}
    seq_pattern_position[seq_no] = {}
    pattern_copy_performed[seq_no] = false
    pattern_keys[seq_no] = {}
    seq_pattern_q[seq_no] = false


    for pattern = 1, max_seq_patterns do
      seq_pattern[seq_no][pattern] = {}
      seq_pattern_length[seq_no][pattern] = 8
      pattern_keys[seq_no][pattern] = false

      for step = 1, max_seq_pattern_length do
        seq_pattern[seq_no][pattern][step] = {}
        for col = 1, max_seq_cols do
          seq_pattern[seq_no][pattern][step][col] = 0
        end
      end

      -- set seq pattern length
      seq_pattern_position[seq_no][pattern] = 0

      -- set starting pattern
      active_seq_pattern[seq_no] = 1
    end

  end
  --#endregion seq globals


  pattern_grid_offset = 0 -- grid view scroll offset
  note_history = {}  -- todo p2 performance of having one vs dynamically created history for each voice
  dedupe_threshold()
  -- reset_clock() -- might need reset_lattice but it hasn't been intialized
  
  -- replacing
  -- get_next_chord()
  -- chord_raw = next_chord
  preload_chord()

  --#region PSET callback functions
  -- prefs .data table names we want pset callbacks to act on
  pset_lookup = {"arranger", "events", "event_lanes", "chord_pattern", "chord_pattern_length", "seq_pattern", "seq_pattern_length", "misc", "voice", "masks", "chord"}

  function params.action_write(filename, name, number)
    local number = number or "00" -- template
    local filepath = norns.state.data .. number .. "/"
    os.execute("mkdir -p " .. filepath)
    
    -- Make table with version (for backward compatibility checks) and any useful system params
    misc = {}
    misc.timestamp = os.date()
    misc.version = version
    misc.clock_tempo = params:get("clock_tempo")
    -- misc.clock_source = params:get("clock_source") -- defer to system
    
    -- these have to be global which is dumb
    masks = deepcopy(theory.masks)
    chord = deepcopy(theory.custom_chords)

    -- need to save and restore nb voices which can change based on what mods are enabled
    -- reworked for seq2 but haven't tested
    voice = {}

    local sources = {}
    table.insert(sources, "chord_voice")
    for seq_no = 1, max_seqs do
      table.insert(sources, "seq_voice_" .. seq_no)
    end
    table.insert(sources, "crow_voice")
    table.insert(sources, "midi_voice")

    for i = 1, #sources do
      -- local param_string = sources[i].."_voice"
      -- local param_string = param_string == "seq_voice" and "seq_voice_1" or param_string
      -- voice[param_string] = params:string(param_string)
      
      -- print("debug sources[i] " .. params:string(sources[i]))
      voice[sources[i]] = params:string(sources[i])
    end


    for i = 1, #pset_lookup do
      local tablename = pset_lookup[i]
      tab.save(_G[tablename], filepath .. tablename .. ".data")
      print("table >> write: " .. filepath..tablename .. ".data")
    end
  end


  function params.action_read(filename, silent, number)
    local number = number or "00" -- template
    nb:stop_all()
    local filepath = norns.state.data..number.."/"
    if util.file_exists(filepath) then
      -- Close the event editor if it's currently open so pending edits aren't made to the new arranger unintentionally
      screen_view_name = "Session"
      misc = {}
      voice = {}
      masks = {}
      for i = 1, #pset_lookup do
        local tablename = pset_lookup[i]
          if util.file_exists(filepath..tablename..".data") then
          _G[tablename] = tab.load(filepath..tablename..".data")
          print("table >> read: " .. filepath..tablename..".data")
        else
          print("table >> missing: " .. filepath..tablename..".data")
        end
      end

      if masks and #masks > 0 then
        theory.masks = deepcopy(masks)
      end

      if chord and #chord > 0 then
        theory.custom_chords = deepcopy(chord)
      end

      -- clock_tempo isn't stored in .pset for some reason so set it from misc.data (todo: look into inserting into .pset)
      params:set("clock_tempo", misc.clock_tempo or params:get("clock_tempo"))

      -- restore nb voices based on string
      local sources = {}
      table.insert(sources, "chord_voice")
      for seq_no = 1, max_seqs do
        table.insert(sources, "seq_voice_"..seq_no)
      end
      table.insert(sources, "crow_voice")
      table.insert(sources, "midi_voice")

      for i = 1, #sources do
        -- local param_string = sources[i].."_voice"
        -- local param_string = param_string == "seq_voice" and "seq_voice_1" or param_string
        local param_string = sources[i]
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
      -- todo p2 loading pset while transport is active gets a little weird with Link and MIDI but I got other stuff to deal with
      if params:get("clock_source") == "internal" then 
        reset_lattice() -- reset_clock() -- untested
      else
        gen_arranger_padded()
      end
      arranger_q = nil
      set_chord_pattern_q(false)
      for seq_no = 1, max_seqs do
        reset_seq_pattern(seq_no)
        play_seq[seq_no] = false
      end
      chord_pattern_position = 0
      arranger_position = 0
      set_chord_pattern(arranger_padded[1])
      if transport_state == "paused" then
        transport_state = "stopped" -- just flips to the stop icon so user knows they don't have to do this manually
      end
      build_scale() -- Have to run manually because mode bang comes after all of this for some reason
      preload_chord()

      chord_no = 0 -- wipe chord readout
      gen_chord_readout()
      gen_arranger_dash_data("params.action_read")
      read_prefs()
      -- if transport_active, reset and continue playing so user can demo psets from the system menu
      -- todo p2 need to send different sync values depending on clock source.
      -- when link clock is running we can pick up on the wrong beat.
      -- unsure about MIDI
      -- if transport_active == true then
      --   clock.transport.start()
      -- end

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
          if events[segment][step] ~= nil then
            for lane = 1, 15 do
              local event = events[segment][step][lane]
              if event ~= nil then
                if events_lookup_index[event.id] == nil then
                  warning = true
                  print("WARNING: unable to locate " .. event.event_type .. " " ..  event.id .. " on event ["..segment.."][" .. step .. "][" .. lane .. "]")
                  
                  events[segment][step][lane] = nil
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
  --#endregion PSET callback functions



  -------------
  -- Write prefs
  -------------
  function save_prefs()
    local filepath = norns.state.data
    local prefs = {}
    prefs.timestamp = os.date()
    prefs.last_version = version
    prefs.default_pset = params:string("default_pset")
    prefs.sync_views = params:string("sync_views")
    prefs.notifications = params:string("notifications")
    prefs.preview_notes = params:string("preview_notes")
    for dash_no = 1, max_dashboards do
      local id = "dash_" .. dash_no
      prefs[id] = params:string(id)
    end
    prefs.crow_pullup = params:string("crow_pullup")
    prefs.voice_instances = params:get("voice_instances")
    prefs.config_enc_1 = params:get("config_enc_1")
    prefs.config_enc_2 = params:get("config_enc_2")
    prefs.config_enc_3 = params:get("config_enc_3")
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
  if params:string("default_pset") == "Last PSET" then
    params:default()
  elseif params:string("default_pset") == "Template" then
    params:read(00)
  end
  
  params:bang()
  -- Some actions need to be added post-bang.
  params:set_action("arranger", function(val) update_arranger_state(val) end)

  params:set_action("scale", 
    function()
      build_scale()
      if transport_state == "stopped" then
        preload_chord()
      else -- immediately update the active chord with whatever custom or triad is on this step (for downstream note sources)
        update_chord(current_chord_x)
        gen_chord_readout()
      end
    end
  )

  -- Redefine div change actions, this time with lattice stuff
  -- WIP: needs some work! Currently blocks any changes unless stopped LOL
  params:set_action("ts_numerator",
    function(val) 
      if transport_state == "stopped" then
        ts_numerator = val
        sprocket_measure:set_division(val / params:string("ts_denominator"))
      else
        params:set("ts_numerator", ts_numerator or 4)
        notification("STOP TRANSPORT FIRST")
      end
    end
  )

  params:set_action("ts_denominator",
    function(val) 
      if transport_state == "stopped" then
        ts_denominator = val
        sprocket_measure:set_division(params:get("ts_numerator") / params:string("ts_denominator"))
        sprocket_metro:set_division(1 / params:string("ts_denominator") / 2)
      else
        params:set("ts_denominator", ts_denominator or 3)
        notification("STOP TRANSPORT FIRST")
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

  for seq_no = 1, max_seqs do
    params:set_action("seq_div_index_"..seq_no,
      function(val) 
        _G["sprocket_seq_"..seq_no]:set_division(division_names[val][1]/global_clock_div/4)
        if params:get("seq_duration_index_"..seq_no) == 0 then
          seq_duration[seq_no] = division_names[params:get("seq_div_index_"..seq_no)][1]
        end
      end
    )

    params:set_action("seq_swing_"..seq_no, function(val) _G["sprocket_seq_"..seq_no]:set_swing(val) end)
  end

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
  -- params:set_action("seq_swing_1", function(val) sprocket_seq_1:set_swing(val) end)
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
  -- also called by modded lattice.lua
  function process_notes()
    -- todo: spin up tables for active voices so new notes only check against history for the matching voice
    -- Assumes PPQN == global_clock_div. Lookup tables will need adjustments if PPQN ~= 48
    for i = #note_history, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      local hist = note_history[i]
      hist.step = hist.step - 1

      if hist.step == 0 then
        if hist.channel then -- todo unsure if this check is optimal vs just sending properties
          hist.player:note_off(hist.note, 0, {ch = hist.channel})
        else
          hist.player:note_off(hist.note)
        end
        table.remove(note_history, i)
      end

    end
  end


  function disable_sprockets()
    sprocket_measure.enabled = false -- should we let this sprocket's phase be advanced when pausing?
    sprocket_metro.enabled = false
    sprocket_16th.enabled = false   -- should we let this sprocket's phase be advanced when pausing?
    sprocket_chord.enabled = false
    sprocket_crow_clock.enabled = false
    for seq_no = 1, max_seqs do
      _G["sprocket_seq_"..seq_no].enabled = false
    end
    sprocket_cv_harm.enabled = false
  end

  function enable_sprockets()
    sprocket_measure.enabled = true
    sprocket_metro.enabled = true
    sprocket_16th.enabled = true
    sprocket_chord.enabled = true
    sprocket_crow_clock.enabled = true
    for seq_no = 1, max_seqs do
      _G["sprocket_seq_"..seq_no].enabled = true
    end
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


  -- sprocket used for quantizing transport stops to 1/16 div which is what MIDI SPP uses-- also used to send continue/SPP on resume
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
          --   if arranger_state == "on" then
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

            -- link_stop_source = nil

            -- if arranger_state == "on" then --or transport_state == "stopped" then
            --   reset_arrangement()
            -- else
            --   reset_pattern()
            -- end
  
            reset_arrangement() -- always reset arrangement since link negative beat clock is broken

            transport_state = "stopped"
            print(transport_state)

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
          --   if arranger_state == "on" then
          --     print(transport_state)
          --   else
          --     reset_pattern()
          --   end
          --   transport_active = false
          --   reset_arrangement()
          --   transport_state = "stopped"
          --   stop = false
          -- end
        
        -- since we don't support incoming SPP, treat as reset
        elseif clock_source == "midi" then
          -- transport_multi_stop() -- won't propagate to downstream devices
          transport_active = false
          transport_state = "stopped"
          print(transport_state)
          clock_start_method = "start"

          -- always reset pattern AND arranger
          reset_arrangement()

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

        for seq_no = 1, max_seqs do
          if params:string("seq_reset_on_" .. seq_no) == "Measure" then
            reset_seq_pattern(seq_no)
          end

          if params:string("seq_start_on_" .. seq_no) == "Measure" then
            play_seq[seq_no] = true
          end

        end

      end,
      -- div_action = function(t)  -- call action when div change is processed -- todo along with measure
      division = div, -- params:get("ts_numerator") / params:string("ts_denominator"),
      order = 2,
      enabled = true
    }
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time.
  init_sprocket_measure(params:get("ts_numerator") / params:string("ts_denominator"))


  -- runs at 2x time signature to turn metronome on/off
  -- can also be used to calculate beats if needed
  function init_sprocket_metro(div)
    sprocket_metro = seq_lattice:new_sprocket{
      action = function(t)
        -- metro_measure = util.wrap(metro_measure + 1, 1, params:get("ts_numerator") * 2) -- alternative for actual 1/2 beats
        metro_measure = sprocket_measure.phase == 1
      end,
      -- div_action = function(t)  -- call action when div change is processed
      -- end,
      division = div,
      order = 2, -- todo see where this needs to come relative to sprocket_measure for metronome
      enabled = true
    }
  end
  -- some weirdness around order in which param actions fire. So we do via a function the first time.
  init_sprocket_metro(1 / params:string("ts_denominator") / 2)
  
  
  function init_sprocket_chord(div)
    sprocket_chord = seq_lattice:new_sprocket{

      -- fires order 1 events for upcoming segment (such as chord div change) that need to occur before action
      pre_action = function(t)  
        if params:string("arranger") == "On" then -- don't use arranger_state since we'll be have synced on advance_chord_pattern
          if (arranger_position == 0 and chord_pattern_position == 0) or (chord_pattern_position >= chord_pattern_length[active_chord_pattern]) then -- if advancing arranger
            update_arranger_next()
            local q = arranger_q
            local next = q ~= nil and q <= arranger_length and q or arranger_next
            do_events(next, 1)
          end
        end
      end,

      action = function(t)
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
  
  for seq_no = 1, max_seqs do
    _G["init_sprocket_seq_"..seq_no] = function(div)
      _G["sprocket_seq_"..seq_no] = seq_lattice:new_sprocket{
          action = function(t)
          -- something like this is needed or stop during "pausing" (2x K2) will reset and play sequence again
          -- might be better to include a check in lattice since this probably affects all sprockets (including crow/harm)
          -- if transport_state == "playing" or transport_state == "pausing" then 
          if params:string("seq_start_on_"..seq_no) == "Loop" then
            advance_seq_pattern(seq_no)
            grid_dirty = true   -- todo should check active grid view?
          elseif play_seq[seq_no] then  -- todo seq2?
            advance_seq_pattern(seq_no)
            grid_dirty = true
          end
        end,
        -- div_action = function(t)  -- call action when div change is processed
        -- end,
        division = div,
        swing = params:get("seq_swing_"..seq_no),
        order = 5,
        enabled = true
      } 
    end
    -- some weirdness around order in which param actions fire. So we do via a function the first time. 
    _G["init_sprocket_seq_"..seq_no](division_names[params:get("seq_div_index_"..seq_no)][1]/global_clock_div/4)
  end

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
  
  
  -- todo: seeing some intermittent issues with grid freezing still. I thought this would fix it but maybe lower rate further.
  -- libmonome: error in write: Input/output error
  grid_redraw_metro = metro.init(grid_refresh, 1/30, -1)
  grid_dirty = true
  grid_redraw_metro:start()

  -- screen refresh and blinkies
  countdown_timer = metro.init()
  countdown_timer.event = countdown
  countdown_timer.time = 0.1 -- 1/15
  countdown_timer.count = -1
  countdown_timer:start()

  -- gen_triad_lookups() -- not sure if needed any more

  -- start and reset lattice to get note durations working
  disable_sprockets()
  seq_lattice:start()
  seq_lattice:stop()
  reset_lattice("init")
  reset_arrangement()

end -- end of init
--#endregion init

-----------------------------------------------
-- Assorted functions junkdrawer
-----------------------------------------------
 
-- shows a brief pop-up message
-- end_tab is table indicating which grid or norns key release will end the message
-- e.g. {g, x, y} or {k, 3}
-- nil end_tab will result in long notification (enc)
function notification(message, end_tab)
  local d = params:get("notifications")
  if d > 1 then -- index 1 == off
    if end_tab then
      if message_clock then
        clock.cancel(message_clock)
        popup_countdown = nil
      end
      lvl = lvl_dimmed
      update_dash_lvls()
      screen_message = message
      end_screen_message = end_tab
    else
      lvl = lvl_dimmed
      update_dash_lvls()
      screen_message = message
      do_notification_timer_1(math.max(d, 3)) --  since no end_tab was supplied, do timer of some sort (unless notifs are off)
    end
  end
end


-- param action function that saves current scales to global folder location
function write_global_scales()
  local filepath = norns.state.data  
  local masks = deepcopy(theory.masks)

  tab.save(masks, filepath .. "masks.data")
  print("table >> write: " .. filepath .. "masks.data")
end


function screenshot(name)
  local filepath = norns.state.data .. (name or "screenshot") .. ".png"
  _norns.screen_export_png(filepath)
  print("screenshot saved to " .. filepath)
end


-- Function to remove duplicates
local function remove_duplicates(t)
  local seen = {}
  local result = {}
  for _, value in ipairs(t) do
      if not seen[value] then
          seen[value] = true
          table.insert(result, value)
      end
  end
  return result
end

-- Function to sort a table numerically
local function sort_and_remove_duplicates(t)
  table.sort(t) -- Sort the table numerically
  return remove_duplicates(t) -- Remove duplicates
end


-- Used while transport is stopped to preview the first chord when we're on step 0
function preload_chord()
  if transport_state == "stopped" then
    local x = chord_pattern[active_chord_pattern][1]
    x = x == 0 and current_chord_x or x
    local y = 1 -- should always be step 1 if we're stopped, pretty sure
    update_chord(x, y)
    gen_chord_readout() -- bit of a WAG but seems ok
  end
end


-- checks that arranger_q is valid, resets grid led phase, and sets derivative chord_pattern_q
-- todo p2: not sure where to put this as a local so that event action can access it
function set_arranger_q(seg) -- might have to make global or relocate for events
  if seg <= arranger_length then
    local current_arranger_q = arranger_q
    arranger_q = seg
    if current_arranger_q ~= arranger_q then
      reset_grid_led_phase()
    end
    update_chord_pattern_q()

  -- above will keep existing arranger_q, but we could optionally nil it...
  -- could be useful to clear an existing q jump by jumping out-of-bounds, so to speak
  -- else
  --   arranger_q = nil
  --   update_chord_pattern_q()
  end
end


-- function dump_params()
--   local filepath = norns.state.data
--
--   paramdump = {}
--   for i = 1, #params.params do
--     table.insert(paramdump, params.params[i].name)
--   end

--   tab.save(paramdump, filepath .. "paramdump.data")
--   print("table >> write: " .. filepath.."paramdump.data")
-- end


-- function dump_events()
--   local filepath = norns.state.data

--   eventdump = {}
--   for i = 1, #events_lookup do
--     table.insert(eventdump, events_lookup[i].category .. "/" .. events_lookup[i].subcategory)
--   end

--   tab.save(eventdump, filepath .. "eventdump.data")
--   print("table >> write: " .. filepath.."eventdump.data")
-- end


-- generic timer that runs function after counter reaches 0
-- eg: clock.run(do_timer, 10, function() print("copying") end)
function do_timer(countdown, func)
  while true do
    countdown = countdown - 1
    if countdown == 0 then
        func()
      break
    end
    clock.sleep(.1)
  end
end


-- optional arg to override popup duration pref(e.g. always show extended pop-up when initiated by enc, which has no end state)
function do_notification_timer_1(pref)
  local pref = pref or params:get("notifications")

  if pref < 3 then -- index 1 == off, 2 == momentary
    screen_message = nil
    lvl = lvl_normal
    update_dash_lvls()
  elseif pref > 2 then -- index 3 == brief, 4 == extended
    local time = (pref - 2) * 8
    if (popup_countdown or 0) == 0 then -- start timer
      message_clock = clock.run(
        function()
          popup_countdown = time
          while true do
            popup_countdown = popup_countdown - 1
            if popup_countdown == 0 then
              screen_message = nil
              lvl = lvl_normal
              update_dash_lvls()
              break
            end
            clock.sleep(.1)
          end
        end
      )
    else  -- timer is already running so just restart the countdown
      popup_countdown = time
    end
  end
end   

          
          function pattern_key_timer()
  keydown_timer = 0
  while grid_interaction == "pattern_switcher" do
    keydown_timer = keydown_timer + 1
    clock.sleep(.1)
  end
end


function reset_norns_interaction(interaction)
  local countdown = 3
  while true do
    countdown = countdown - 1
    if countdown == 0 then
      norns_interaction = interaction or nil
      lvl = lvl_normal
      break
    end
    clock.sleep(.1)
  end
end


function delete_events_in_segment(new_action)
  print("Deleting all events in segment " .. event_edit_segment)
  for step = 1, max_chord_pattern_length do
    events[event_edit_segment][step] = {}
  end
  events[event_edit_segment].populated = 0
  update_lanes()
  event_edit_step = 0
  event_edit_active = false
  reset_grid_led_phase()
  grid_dirty = true
  norns_interaction = "event_actions_done"
  clock.run(reset_norns_interaction, new_action)
end

function count_keys(tbl)
  local count = 0
  for _ in pairs(tbl) do
      count = count + 1
  end
  return count
end


-- generates list of distinct events for event lanes, updates lane type/id
-- operates on single lane arg if present. otherwise, all lanes
function update_lanes(lane)
  for lane = lane or 1, lane or 15 do
    local lane_path = event_lanes[lane]
    local id = nil
    -- local event_count = 0

    lane_path.events = {}
    for segment = 1, max_arranger_length do
      for step = 1, max_chord_pattern_length do
        if events[segment][step][lane] ~= nil then
          id = events[segment][step][lane].id
          lane_path["events"][id] = (lane_path["events"][id] or 0) + 1 -- store event count for update_lane_glyph()
        end
      end
    end

    local event_countd = count_keys(lane_path.events) -- distinct

    if event_countd == 0 then -- initialize lane
      event_lanes[lane] = {}
    elseif event_countd == 1 then -- set to Single lane with single event ID
      lane_path.type = "Single"
      lane_path.id = id
    else -- set type to Multi if it was changed via, e.g. addition or copy+paste
      lane_path.type = "Multi"
    end

    lane_path.countd = event_countd -- store distinct event count for update_lane_glyph()

  end
end


-- sets lane glyph preview if the impending event change is going to change lane type
function update_lane_glyph()
  local lane_path = event_lanes[event_edit_lane]
  local saved_event = events[event_edit_segment][event_edit_step][event_edit_lane]

  if lane_path.type == "Single" then
    if preview_event.id ~= lane_path.id then            -- if the new event is different than the lane id
      if saved_event == nil then                        -- and it's a new event slot
        lane_glyph_preview = "Multi"
      elseif lane_path["events"][lane_path.id] > 1 then -- if editing a saved event but it's not the last of its type in the lane
        lane_glyph_preview = "Multi"
      else
        lane_glyph_preview = nil
      end
    else
      lane_glyph_preview = nil
    end

  elseif lane_path.countd == 2                      -- if there's a possibility of going from 2 to 1 event
  and saved_event                                   -- and it's an existing saved event, not a new one
  and (preview_event.id ~= saved_event.id)          -- and the event is changing
  and lane_path["events"][preview_event.id] ~= nil  -- and the event type we're changing to is in use
  and lane_path["events"][saved_event.id] == 1 then -- and we're releasing the last of this event type in the slot
    lane_glyph_preview = "Single"                   -- update the lane preview glyph to Single
  else
    lane_glyph_preview = nil
  end

end


-- returns a dummy version of param with action stripped out 
-- used to delta events, get min/max, and cue param changes with K1 held down
function clone_param(id)
  local preview = shallowcopy(params:lookup_param(id)) -- not sure this is copying all controlspec bits !
  preview.action = function() end -- kill off action
  return(preview)
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


-- todo consider breaking this up into sub-tables/functions as we're generating all of them each time a voice is changed
-- benefit in having them all stored, just not generated
function gen_menu()
  menus = {}

  -- SONG MENU
  table.insert(menus, {"tonic", "scale", "clock_tempo", "ts_numerator", "ts_denominator", "crow_out_1", "crow_out_2", "crow_out_3", "crow_out_4", "crow_clock_index", "crow_clock_swing", "dedupe_threshold", "chord_generator", "seq_generator"})

  -- CHORD MENU
  table.insert(menus, {"chord_voice", "chord_octave", "chord_range", "chord_notes", "chord_inversion", "chord_style", "chord_strum_length", "chord_timing_curve", "chord_div_index", "chord_duration_index", "chord_swing", "chord_dynamics", "chord_dynamics_ramp"})  
  if params:visible("chord_channel") or norns_interaction == "k1" then
    table.insert(menus[#menus], 2, "chord_channel")
  end

  -- SEQ MENUS
  for seq_no = 1, max_seqs do
    table.insert(menus, {
      "seq_voice_"..seq_no,
      "seq_note_map_"..seq_no,
      "seq_grid_"..seq_no,
      "seq_polyphony_"..seq_no,
      "seq_octave_"..seq_no,
      "seq_pattern_rotate_"..seq_no,
      "seq_loop_rotate_"..seq_no,
      "seq_shift_"..seq_no,
      "seq_div_index_"..seq_no,
      "seq_duration_index_"..seq_no,
      "seq_swing_"..seq_no,
      "seq_accent_"..seq_no,
      "seq_dynamics_"..seq_no,
      "seq_probability_"..seq_no,
      "seq_start_on_"..seq_no,
      "seq_reset_on_"..seq_no,
      "seq_pattern_change_"..seq_no
    })
    if params:visible("seq_channel_"..seq_no) or norns_interaction == "k1" then
      table.insert(menus[#menus], 2, "seq_channel_"..seq_no)
    end
  end
  
  -- MIDI HARMONIZER MENU
  table.insert(menus, {"midi_voice", "midi_note_map", "midi_harmonizer_in_port", "midi_octave", "midi_duration_index", "midi_dynamics"})
  if params:visible("midi_channel") or norns_interaction == "k1" then
    table.insert(menus[#menus], 2, "midi_channel")
  end

  -- CV HARMONIZER MENU
  table.insert(menus, {"crow_voice", "crow_div_index", "crow_note_map", "crow_auto_rest", "crow_octave", "crow_duration_index","cv_harm_swing", "crow_dynamics"})
  if params:visible("crow_channel") or norns_interaction == "k1" then
    table.insert(menus[#menus], 2, "crow_channel")
  end

  -- keep us on the same menu or, if menu is gone, previous/above menu
  if (menu_index or 0) ~= 0 then
    menu_index = tab.key(menus[page_index], selected_menu) or page_index - 1
    selected_menu = menus[page_index][menu_index]
  end

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
-- 1. suppresses default midi and nb_crow voices
-- 2. renames midi_ds players
-- 3. only serves up valid crow cv/env options based on crow_out_ param config
function gen_voice_lookups()
  voice_param_options = {}
  voice_param_index = {}

  local vport_names = {}
  for k,v in pairs(midi.vports) do  
    vport_names[k] = v.name
  end  
  
  local function trim_menu(string)
    return util.trim_string_to_width(string, 55)--63)
  end
  
  for i = 1, params:lookup_param("chord_voice_raw").count do
    local option = params:lookup_param("chord_voice_raw").options[i]
    local sub7 = string.sub(option, 1, 7)
      if sub7 == "crow_ds" then

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
        
      -- might be better to handle this by checking if player.channel is true  
      elseif sub7 == "midi_ds" then -- reformat bundled ds midi player names
        -- strip leading 0 that was used by nb to sort 1-2 trailing digits in string
        table.insert(voice_param_options, "MIDI port " .. tonumber(string.sub(option, 9, 10)))
        table.insert(voice_param_index, i)

      -- block some players that are not relevant or have built-in alternatives
      -- if updating, also remember to block during event ingesting
      elseif string.sub(option, 1, 5) ~= "midi:"
      and option ~= "crow 1/2"
      and option ~= "crow 3/4"
      and option ~= "crow para" -- todo test
      -- and option ~= "jf kit" -- todo test
      and option ~= "jf mpe" then
        table.insert(voice_param_options, trim_menu(first_to_upper(option))) -- todo extend this or just mask!
        table.insert(voice_param_index, i)
      end
      
  end
end


-- updates voice selector options and sets (or resets) new param index after custom crow_out param changes
function update_voice_params()
  
  local sources = {}
  table.insert(sources, "chord_voice")
  for seq_no = 1, max_seqs do
    table.insert(sources, "seq_voice_"..seq_no)
  end
  table.insert(sources, "crow_voice")
  table.insert(sources, "midi_voice")

  for i = 1, #sources do
    local param_string = sources[i]
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
  reset_sprocket_metro("reset_sprockets")
  reset_sprocket_chord("reset_sprockets")
  reset_sprocket_crow_clock("reset_sprockets")
  for seq_no = 1, max_seqs do
    _G["reset_sprocket_seq_"..seq_no]("reset_sprockets")
  end
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



function reset_sprocket_metro(from)
  -- print("reset_sprocket_metro() called by " .. from)
  sprocket_metro.division = 1 / params:string("ts_denominator") / 2
  sprocket_metro.phase = sprocket_metro.division * seq_lattice.ppqn * 4 * (1 - sprocket_metro.delay)
  sprocket_metro.downbeat = false
  metro_measure = false
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


for seq_no = 1, max_seqs do
  _G["reset_sprocket_seq_"..seq_no] = function(from)
    -- print("reset_sprocket_seq_"..seq_no.."() called by " .. from)
    _G["sprocket_seq_"..seq_no].division = division_names[params:get("seq_div_index_"..seq_no)][1]/global_clock_div/4
    _G["sprocket_seq_"..seq_no].phase = _G["sprocket_seq_"..seq_no].division * seq_lattice.ppqn * 4 * (1 - _G["sprocket_seq_"..seq_no].delay)
    _G["sprocket_seq_"..seq_no].downbeat = false
  end
end


function reset_sprocket_cv_harm(from)
  -- print("reset_sprocket_cv_harm() called by " .. from)
  sprocket_cv_harm.division = params:get("crow_div_index") == 0 and (1/96) or division_names[params:get("crow_div_index")][1]/global_clock_div/4
  sprocket_cv_harm.phase = sprocket_cv_harm.division * seq_lattice.ppqn * 4 * (1 - sprocket_cv_harm.delay)
  sprocket_cv_harm.downbeat = false
end


function build_scale()
  local mode = params:get("scale")

  scale_heptatonic = theory.lookup_scales[theory.base_scales[params:get("scale")]].intervals
  gen_custom_mask() -- generates bool table with notes for each of the 8 custom masks

  -- todo p1 optimize
  -- could also do this for each source so no lookup is necessary each time a note plays
  scale_custom = {}
  for i = 1, 8 do
    if theory.masks[mode][i] and theory.masks[mode][i][1] then
      scale_custom[i] = theory.masks[mode][i]
    else
      scale_custom[i] = scale_heptatonic -- fall back on standard scale if custom one doesn't exist
    end
  end

end


function rotate_tab_values(tbl, positions)
  local length = #tbl
  local rotated = {}
  for i = 1, length do
      local new_pos = ((i - 1 + positions) % length) + 1
      rotated[new_pos] = tbl[i]
  end
  return rotated
end


function seq_pattern_rotate_abs(seq_no, new_rotation_val)
  local pattern = seq_pattern[seq_no]
  local pattern_no = active_seq_pattern[seq_no]
  local offset = new_rotation_val - params:get("prev_seq_pattern_rotate_" .. seq_no .. "_" .. pattern_no)

  pattern[pattern_no] = rotate_tab_values(pattern[pattern_no], offset)
  params:set("prev_seq_pattern_rotate_" .. seq_no .. "_" .. pattern_no, new_rotation_val)
  grid_dirty = true
end


function seq_loop_rotate_abs(seq_no, new_rotation_val)
  local pattern = seq_pattern[seq_no]
  local pattern_no = active_seq_pattern[seq_no]
  local length = seq_pattern_length[seq_no][pattern_no]
  local temp_seq_pattern = {}
  local offset = new_rotation_val - params:get("prev_seq_loop_rotate_" .. seq_no .. "_" .. pattern_no)

  for i = 1, length do
    temp_seq_pattern[i] = pattern[pattern_no][i]
  end

  -- new method with no wrap
  temp_seq_pattern = rotate_tab_values(temp_seq_pattern, offset)
  for i = 1, length do
    pattern[pattern_no][i] = temp_seq_pattern[i]
  end

  -- look into: maybe can store length-wrapped value for each pattern if we want to not do the wide range thing.
  -- but I don't really thing wrapping the param works when we have various pattern lengths
  params:set("prev_seq_loop_rotate_" .. seq_no .. "_" .. pattern_no, new_rotation_val)
  grid_dirty = true
  
  -- print("DEBUG prev, new, offset, storing", params:get("prev_seq_loop_rotate_" .. seq_no .. "_" .. pattern_no), new_rotation_val, offset, new_rotation_val)

end


function seq_shift_abs(seq_no, new_shift_val)
  local pattern_no = active_seq_pattern[seq_no]
  local offset = new_shift_val - (params:get("prev_seq_shift_" .. seq_no .. "_" .. pattern_no))
  local pattern = seq_pattern[seq_no][pattern_no]

  for y = 1, max_seq_pattern_length do
    pattern[y] = rotate_tab_values(pattern[y], offset)
  end

  params:set("prev_seq_shift_" .. seq_no .. "_" .. pattern_no, new_shift_val)

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
end


-- check which ports the global midi clock is being sent to and sends a spp and continue message there
function transport_multi_continue(source)
  for i = 1, #midi_transport_ports do
    if params:string("midi_continue_" .. midi_transport_ports[i].port) == "song" then
      local transport_midi = midi.connect(midi_transport_ports[i].port)
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


-- for crow bipolar fractional voltage
function volts_string(quantum, index)
  -- return(round(index/quantum, 2) .. "v")
  local pre = index < 0 and "-" or ""
  local index = math.abs(index)
  local v = math.floor(index / quantum) + (index < 0 and 1 or 0)
  local m = index % quantum
 
  if v == 0 then
    return(pre .. m .. "/" .. quantum .."v")
  elseif m == 0 then
    return(pre .. v .. "v")
  else
    return(pre .. v .. " " .. m .. "/" .. quantum .."v")
  end
end


-- supplement to volts_string if we want to show a note alongside 1/12v output.
-- assumes A440 tuning on oscillator
function volts_string_note(quantum, index)
  local notes = {"A#","B", "C", "C#","D","D#","E","F","F#","G","G#","A"}
  return(volts_string(quantum, index) .. ", " .. notes[util.wrap(index, 1, 12)] .. " @A440" )
end


function crow_trigger_string(index)
  return(index == 0 and "Crow IN 2" or division_names[index][2])
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
  
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end


function t_f_string(x)
  return(x == 1 and "True" or "False")
end


function transpose_string(x)
  return(
    theory.scale_chord_letters[params:get("scale")][util.wrap(x, 0, 11)][1]
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


function shuffle(tbl) -- doesn't deepcopy
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
  gen_arranger_dash_data("gen_arranger_padded")
end


-- 1/10s timer used to calculate arranger countdown timer and do transport/grid blinkies
function countdown()

  -- todo p1 these are kinda expensive and run way too frequently. Can switch to once a second maybe but not sure about resuming.
  if transport_state == "playing" then
    calc_seconds_remaining()
    calc_seconds_elapsed()
  end

  cycle_1_16 = util.wrap(cycle_1_16 + 1, 1, 16)
  local led_pulse_tab = {0,0,0,1,2,3,2,1} -- 3x pause at top
  led_pulse = led_pulse_tab[util.wrap(cycle_1_16, 1, 8)]
  blinky = blinky ~ 1
  led_high_blink = 15 - blinky * 4
  led_med_blink = 7 - blinky * 2
  led_low_blink = 3 - blinky
  grid_dirty = true -- for blinky scrolling pattern indicator.
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
  
  for seq_no = 1, max_seqs do
    if params:string("seq_start_on_"..seq_no) == "Loop" then
      play_seq[seq_no] = true
    end
  end

  start = true
  stop = false -- 2023-07-19 added so when arranger stops in 1-shot and then external clock stops, it doesn't get stuck
  transport_active = true

  -- pre-sync to make sure lattice is in sync with system clock (not necessarily in phase though)
  clock.run(function()
    local reset_elapsed = transport_state ~= "paused"
    
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
      --   if arranger_state == "on" then
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

    if reset_elapsed then -- elapsed time dash has to go here after sync
      seconds_elapsed_raw = 0
    end

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
  set_chord_pattern_q(false)
  for seq_no = 1, max_seqs do
    reset_seq_pattern(seq_no)
  end
  chord_pattern_position = 0
  reset_sprockets("reset_pattern")
  reset_lattice() -- reset_clock()
  preload_chord()
  gen_arranger_dash_data("reset_pattern")
  grid_dirty = true
end


function reset_arrangement()
  arranger_next = nil
  arranger_q = nil
  chord_pattern_q = nil
  arranger_position = 0
  if arranger[1] > 0 then set_chord_pattern(arranger[1]) end
  if params:string("arranger") == "On" then arranger_state = "on" end
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
  -- local debug = false
  chord_pattern_retrig = true -- indicates when we're on a new chord seq step for CV harmonizer auto-rest logic
  local arrangement_reset = false
  local arranger_param = params:get("arranger")

  -- Advance arranger sequence if enabled
  if arranger_param == 2 then -- "on"

    -- If arranger is reset or at the end of chord sequence
    if (arranger_position == 0 and chord_pattern_position == 0) or chord_pattern_position >= chord_pattern_length[active_chord_pattern] then
      arranger_state = "on" -- Only set when the "arranger" param is "On" and we're moving into a new Arranger segment (or after reset)
      local q = arranger_q

      -- Check if it's the last pattern in the arrangement.
      if arranger_next == 0 and not q then -- arranger is ending
        clock.link.stop()            -- no stop quantization for sending Link stop out
        transport_multi_stop()
        transport_active = false
        stop = false
        start = false
        seq_lattice:stop()
        disable_sprockets()
        arrangement_reset = true
        reset_arrangement()          -- also reset_pattern() >> reset_lattice
        seq_lattice.transport = -1   -- roll back since lattice has yet to increment
      else
        arranger_position = (q ~= nil and q <= arranger_length and q) or arranger_next
        set_chord_pattern(arranger_padded[arranger_position])
        update_chord_pattern_q()
        arranger_q = nil             -- clear arranger_q after being processed
        update_arranger_next()       -- for pulsing led indicating loop, etc...
      end
      arranger_retrig = true         -- indicates arranger has moved to new pattern
    end
  end

  -- If arrangement was not just reset, update chord position. 
  if arrangement_reset == false then
    if chord_pattern_position >= chord_pattern_length[active_chord_pattern] or arranger_retrig then
      if arranger_param == 1 and chord_pattern_q then -- arranger "off"
        set_chord_pattern(chord_pattern_q)
        set_chord_pattern_q(false)
      end
      chord_pattern_position = 1
      arranger_retrig = false
    else
      local next = chord_pattern_position + 1
      chord_pattern_position = next > chord_pattern_length[active_chord_pattern] and 1 or next
    end

    if arranger_state == "on" then
      do_events()
      gen_arranger_dash_data("advance_chord_pattern")
    end

    -- Play the chord
    local x = chord_pattern[active_chord_pattern][chord_pattern_position]
    if x > 0 then
      update_chord(x)
      if params:get("chord_mute") == 1 then
        play_chord()
      end

      for seq_no = 1, max_seqs do
        local start_on = params:string("seq_start_on_"..seq_no)
        local reset_on = params:string("seq_reset_on_"..seq_no)

        if reset_on == "Every step" or reset_on == "Chord steps" then
          reset_seq_pattern(seq_no)
        end

        if start_on == "Every step" or start_on == "Chord steps" then
          play_seq[seq_no] = true
        end
      end

      gen_chord_readout()  -- update chord names in dash any time a chord is enabled on this step

    else -- no chord but we might need to start/reset seq

      for seq_no = 1, max_seqs do
        local start_on = params:string("seq_start_on_"..seq_no)
        local reset_on = params:string("seq_reset_on_"..seq_no)

        if reset_on == "Every step" or reset_on == "Empty steps" then
          reset_seq_pattern(seq_no)
        end

        if start_on == "Every step" or start_on == "Empty steps" then
          play_seq[seq_no] = true
        end
      end

    end

  end
end


-- returns next segment (including loop/end(0))
function get_next_seg()
  local nx = arranger_position + 1
  local seg
  if nx > arranger_length then
    if params:get("playback") == 1 then -- 1-shot
      seg = 0
    else
      seg = 1
    end
  else
    seg = nx
  end
  return(seg)
end


-- Update and set arranger_next, which can be one of 3 things:
-- 1. sequential arranger segment
-- 2. if looping, segment 1
-- 3. if ending, segment 0
-- notably, this is separate from arranger_q which takes priority
function update_arranger_next()
  arranger_next = get_next_seg()
  update_chord_pattern_q()
end


-- Checks each time arrange_enabled param changes to see if we need to also immediately set the corresponding arranger_state var to "off"
-- Does not flip to true until Arranger is re-synced upon advance_chord_pattern (or transport reset)
-- Also updates chord_pattern_q
function update_arranger_state(val)
  if val == 1 then -- turning off
    update_arranger_next()
    arranger_state = "off"
    set_chord_pattern_q(false)
  else -- turning on OR syncing
    if chord_pattern_position == 0 then
      arranger_state = "on"
    else
      arranger_state = "syncing"
    end
    update_chord_pattern_q()
  end
  gen_arranger_dash_data("update_arranger_state")
end


-- if optional args are passed, they indicate that `order 1` events need to be fired before chord advancement
-- todo p0: optimize his by storing separate tables based on `order`
function do_events(arranger_pos, chord_pos)
  local do_order = arranger_pos and 1 or 2
  local arranger_position = arranger_pos or arranger_position
  local chord_pattern_position = chord_pos or chord_pattern_position

  if events[arranger_position] ~= nil then
    if events[arranger_position][chord_pattern_position].populated or 0 > 0 then

      for i = 1, 15 do
        local event_path = events[arranger_position][chord_pattern_position][i]

        if event_path ~= nil then
          if event_path.order == do_order then

            if event_path.probability == 100 or math.random(1, 100) <= event_path.probability then
              -- local event_type = event_path.event_type -- << todo p2 technically this doesn't need to get stored in event any more (t can replace here)
              local t = event_path.t
              local action = event_path.action or nil

              if t then -- indicates param, as opposed to function
                local event_name = event_path.id
                local value = event_path.operation == "Wander" and cointoss_inverse(event_path.value) or event_path.value or ""
                local limit = event_path.limit  -- can be "events_op_limit" or, for Random op, "events_op_limit_random"
                local limit_min = event_path.limit_min
                local limit_max = event_path.limit_max
                local operation = event_path.operation

                if operation == "Set" then
                  if t == 3 then -- controlspec needs to be set using raw value
                    params:set_raw(event_name, value)
                  else
                    params:set(event_name, value)
                  end

                -- idea: ideally could use a variant of clone_param() used to preview delta (make sure to write to a different table than `preview`!), clamp within limits, then set once. This way the action doesn't fire repeatedly.
                -- for wrap, could do this first and only fall back on iterate if it exceeds limit_max
                elseif operation == "Increment" or operation == "Wander" then

                  local get -- replacement get/set functions depending on whether we're setting raw (controlspec) or standard values
                  local set

                  if t == 3 then -- controlspec will use raw value
                    get = function() return params:get_raw(event_name) end
                    set = function(val) return params:set_raw(event_name, val) end
                  else           -- all other params use standard value
                    get = function() return params:get(event_name) end
                    set = function(val) return params:set(event_name, val) end
                  end

                  if limit == "Clamp" then
                    if value > 0 then -- positive delta
                      if get() < limit_min then
                        set(limit_min)
                      else
                        for _ = 1, value do
                          if get() >= limit_max then
                            set(limit_max)
                            break
                          else
                            params:delta(event_name, 1)
                          end
                        end
                      end

                    elseif value < 0 then -- negative delta
                      if get() > limit_max then
                        set(limit_max)
                      else
                        for _ = value, -1 do
                          if get() <= limit_min then
                            set(limit_min)
                            break
                          else
                            params:delta(event_name, -1)
                          end
                        end
                      end
                    end

                  elseif limit == "Wrap" then
                    local reset = false
                  
                    if value > 0 then -- positive delta
                      if get() < limit_min then
                        set(limit_min)
                      else
                        for _ = 1, value do

                          -- Wrap logic tries to maintain "expected" values for nonlinear controlspec/taper deltas:
                          -- 1. If within wrap min/max, delta (but clamp if the delta would exceed limit)
                          -- 2. If *at* max when event fires with positive value, wrap to min regardless of value
                          -- 3. If *at* min when event fires with negative value, wrap to max regardless of value
                    
                          -- This comparison can fail because of floating point precision, but is probably not worth addressing with the following workaround because of the nature of controlspec, to begin with. Even carefully-crafted and output-quantized controlspec params seem to output different values depending on whether your point of origin is the param default, incrementing from param min, or decrementing from param max.
                          -- if params:get(event_name) - limit_max >= -0.00000001 then
                          if get() >= limit_max then
                            reset = true
                          end
                          if reset then -- at the limit_max *before* applying delta
                            set(limit_min)
                            reset = false
                          else
                            params:delta(event_name, 1)
                          end
                        end
                      end
                    
                    elseif value < 0 then -- negative delta
                      if get() > limit_max then
                        set(limit_max)
                      else
                        for _ = value, -1 do
                          if get() <= limit_min then
                            reset = true
                          end
                          if reset then -- at the limit_min *before* applying delta
                            set(limit_max)
                            reset = false
                          else
                            params:delta(event_name, -1)
                          end
                        end
                      end
                    end
                  
                  else -- limit == "Off"
                    params:delta(event_name, value) 
                  end
                  
                elseif operation == "Random" then
                  local param = params:lookup_param(event_name)

                  if t == 1 then -- number
                    if limit == "Off" then
                      limit_min = param.min
                      limit_max = param.max
                    end
    
                    local rand = math.random(limit_min, limit_max)
                    params:set(event_name, rand)  
                    
                  elseif t == 2 then -- options
                    if limit == "Off" then
                      limit_min = 1
                      limit_max = param.count
                    end
                    
                    local rand = math.random(limit_min, limit_max)
                    params:set(event_name, rand)
                    
                    -- for controlspec and taper, this attempts to return an expected value, as if user had done a standard delta. 
                  elseif t == 3 then -- controlspec
                    limit_min = (limit_min * 100) or 0
                    limit_max = (limit_max * 100) or 100
                    params:set_raw(event_name, util.round((math.random(limit_min, limit_max) / 100), param.controlspec.quantum))

                  elseif t == 5 then -- taper
                    limit_min = param:unmap_value(limit_min or param.min)
                    limit_max = param:unmap_value(limit_max or param.max)

                    params:set(event_name, param:map_value(quantize(random_float(limit_min, limit_max), param:get_delta())))
                  
                  elseif t == 9 then -- and param.behavior == "toggle" then -- binary (toggle behavior is implied as others are value_type `trigger`)
                    params:set(event_name, math.random() > .5 and 1 or 0)
                  end

                elseif operation == "Trigger" then
                  if t == 6 then -- true `trigger` param
                    params:set(event_name, 1)
                  elseif t == 9 then -- binary
                    local type = params:lookup_param(event_name).behavior
                    if type == "momentary" then -- todo variable timer but for now, brief hold
                      params:set(event_name, 1)
                      do_timer(2, function() params:set(event_name, 0) end) -- 0.2s momentary hold as a sort of approximation of manual keypress
                    -- elseif type == "toggle" then -- handled as a `continuous` event
                    else -- "trigger"
                      params:set(event_name, 10)
                    end
                  end

                end
              end

              if action ~= nil then
                load(action)()
              end
              
            end
          end
        end
      end
    end
  end
end

-- generates short chord name/degree for chord readout dashboards
function gen_chord_readout()
  local x = current_chord_x
  local x_wrapped = util.wrap(x, 1, 7)
  local scale = params:get("scale")
  local custom = theory.custom_chords[scale][active_chord_pattern][x]
  local y = chord_pattern_position == 0 and 1 or chord_pattern_position -- 0 to 1 so this can be used while transport is stopped to preview upcoming

  if custom[y] then -- is a custom chord
    if custom[y].name == "Custom" then -- unnamed custom chord
      -- active_chord_name_1 = theory.scale_chord_names[scale][util.wrap(params:get("tonic"), 0, 11)][x_wrapped] .. "*" --
      active_chord_name_1 = theory.scale_chord_letters[scale][util.wrap(params:get("tonic"), 0, 11)][x_wrapped] .. "*"  -- letter*
      active_chord_name_2 = nil

    else
      active_chord_name_1 = theory.scale_chord_letters[scale][util.wrap(params:get("tonic"), 0, 11)][x_wrapped] .. (custom[y].dash_name_1 or "")
      active_chord_name_2 = custom[y].dash_name_2 or nil
    end

    -- todo:
    -- active_chord_degree = theory.chord_degree[scale]["chords"][x_wrapped] .. "*"
  else -- standard triad
    active_chord_name_1 = theory.scale_chord_names[scale][util.wrap(params:get("tonic"), 0, 11)][x_wrapped]
    active_chord_name_2 = nil

    -- todo:
    -- active_chord_degree = theory.chord_degree[scale]["chords"][x_wrapped]
  end

  gen_dash_chord_viz() -- for keyboard diagram
end


-- similar to gen_chord_readout, but this generates long chord name for held chord quick-editor and detailed chord editor menu
function gen_chord_name()
  local p = editing_chord_pattern
  local x = editing_chord_x
  local y = editing_chord_y
  local x_wrapped = util.wrap(x, 1, 7)
  local scale = editing_chord_scale
  local custom = theory.custom_chords[scale][p][x]

  if custom[y] then -- is a custom chord
    if custom[y].name == "Custom" then -- unnamed custom chord
      editing_chord_name = editing_chord_letter .. "*"
    else
      editing_chord_name = editing_chord_letter .. custom[y].name
    end
  else -- standard triad
    editing_chord_name = theory.scale_chord_names[scale][util.wrap(params:get("tonic"), 0, 11)][x_wrapped]
  end
end




-- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord.
-- Todo optimization: cached table of intervals at the scale>>pattern>>y level
-- Also used for previewing chords with g.key while transport is stopped/paused
function update_chord(x, y) -- y is optional when playing chord using g.key
  current_chord_x = x
  current_chord_o = (x > 7) and 1 or 0
  current_chord_d = util.wrap(x, 1, 7)

  -- todo p1 optimize- might build chord_raw, chord_densified, and chord_extended whenever chord is edited or mode changes
  local y = y or chord_pattern_position
  local raw = {}
  local scale = params:get("scale")
  local custom = theory.custom_chords[scale][active_chord_pattern][x]

  -- determines if we're using a custom chord or standard
  if custom[y] then
    raw = custom[y].intervals
  else
    raw = theory.chord_triad_intervals[scale][x]
  end
  chord_raw = raw
  chord_triad = theory.chord_triad_intervals[scale][x] -- trialing keeping the triad even if the chord is customized. needs to be updated elsewhere I suppose.

  local rawcount = #raw
  local max_interval = raw[rawcount] or 0
  local min_interval = raw[1] or 0

  if max_interval - min_interval > 11 then -- Chords with intervals spanning more than an octave need special tables for transform_note fns
    -- generate densified table of chord intervals in 1 octave, reordering notes as necessary
    local densified = {}

    for i = 1, rawcount do
      interval = raw[i]
      densified[i] = (interval - min_interval) > 11 and interval - 12 or interval
    end

    chord_densified = sort_and_remove_duplicates(densified)

    -- generate extended table of chord intervals in 2 octaves by inserting higher-octave tones after highest note in _raw table
    densified = simplecopy(raw)
    min_interval = min_interval + 12 -- redefined to delineate one octave up from min

    for i = 1, rawcount - 1 do
      local n = raw[i]
      
      -- find notes that:
      -- 1. are in the first octave
      -- 2. when raised an octave, are higher pitched than the highest/last tone in chord_raw
      if (n < min_interval) and n + 12 > max_interval then
        table.insert(densified, raw[i] + 12)
      end
    end

    chord_extended = simplecopy(densified)

  else
    chord_densified = raw
    chord_extended = raw
  end

  transform_chord()
end




-- Expands chord notes (range), inverts, and thins based on max notes
function transform_chord()
  local chord_raw = chord_raw
  local chord_extended = chord_extended
  local notes_in_raw = #chord_raw
  local notes_in_extended = #chord_extended
  local extended_oct = notes_in_raw == notes_in_extended and 12 or 24 -- offset to apply when extending
  local range = params:get("chord_range")
  if range == 0 then range = notes_in_raw end
  local max_notes = params:get("chord_notes")
  local inversion = params:get("chord_inversion")

  chord_transformed = {}

  -- Add intervals to achieve range plus apply inversion shift (upper and lower)
  for i = 1, range do
    local inv = i + inversion
    local octave = math.ceil(inv / notes_in_extended) - 1
    chord_transformed[i] = chord_extended[util.wrap(inv, 1, notes_in_extended)] + (inv > notes_in_extended and (octave * extended_oct) or 0)
  end


 -- todo p2 gotta be some way of doing this with note densification for better efficiency
 -- Thin out notes in chord to not exceed params:get("chord_notes")
  if max_notes ~= 25 then
    if max_notes == 1 then
      chord_transformed = {chord_transformed[1]}
    elseif range > max_notes then -- todo- additional thinning algos, e.g. preserve base triad
      chord_thinned = er.gen(max_notes - 1, range - 1, 0)
      for i = range - 1, 2, -1 do
        if chord_thinned[i] == false then
          table.remove(chord_transformed, i)
        end
      end
    end
  end

end


-- variable curve formula from @dewb
-- x == note number * .1
-- to-do: can move upstream * 0.1 here but not sure what the implications are
function curve_get_y(x, curve)
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
function to_player(player, note, dynamics, duration, channel)
  -- todo break up note_history by player so we don't have to check every note against non-matching players

  local note_on_time = util.time()
  local player_play_note = true
  local note_history_insert = true
  
  for i = 1, #note_history do
    local hist = note_history[i]
    -- Check for duplicate notes and process according to dedupe_threshold setting
    if hist.player == player and hist.channel == channel and hist.note == note then
      
      -- Preserve longer note-off duration to avoid which-note-was-first race condition. 
      -- Ex: if a sustained chord and a staccato note play at approximately the same time, the chord's note will sustain without having to worry about order
      hist.step = math.max(duration, hist.step)
      note_history_insert = false -- don't insert a new note-off record since we just updated the duration

      if params:get("dedupe_threshold") > 1 and (note_on_time - hist.note_on_time) < dedupe_threshold_s then
        -- print(("Deduped " .. note_on_time - hist.note_on_time) .. " | " .. dedupe_threshold_s)
        player_play_note = false -- Prevent duplicate note from playing
      end
    
      -- Always update any existing note_on_time, even if a note wasn't played. 
      -- Otherwise the note duration may be extended but the gap between note_on_time and current time grows indefinitely and no dedupe occurs.
      -- Alternative is to not extend the duration when dedupe_threshold > 0 and a duplicate is found
      hist.note_on_time = note_on_time
    end
  end

  -- if we're going to play a note...
  if player_play_note == true then
    
    -- existing (or updated) note duration exists
    -- MIDI/ex requires that we send a note-off for every note-on so immediately fire a note-off 
    if note_history_insert == false then
      if channel then
        player:note_off(note, 0, {ch = channel})
      else
        player:note_off(note)
      end

    -- no other note duration exists so insert a new note record into the history table
    else
      table.insert(note_history, {
        step = duration,
        player = player,
        channel = channel,
        note = note,
        note_on_time = note_on_time
      })
    end
  
    -- Play note
    if channel then -- todo unsure about the efficiency of this check vs. just sending nil properties table
      player:note_on(note, dynamics, {ch = channel})
    else
      player:note_on(note, dynamics)
    end

  end

end


function play_chord()
  -- optional logic if we want to prevent notes being sent when voice == None.
  -- leaving as-is for now since the plan is to break up note_history by player and can be blocked there probably
  -- local param = params:lookup_param("chord_voice_raw")
  -- if param.selected > 1 then -- don't do anything note if voice is None
  -- local player = param:get_player()

  local player = params:lookup_param("chord_voice_raw"):get_player()
  local channel = player.channel and params:get("chord_channel") or nil
  local speed = chord_div / global_clock_div * strum_lengths[params:get("chord_strum_length")][1]
  local start, finish, step -- Determine the starting and ending indices based on the direction
  local playback = params:string("chord_style")
  local chord_transformed = chord_transformed
  local note_qty = #chord_transformed
  local transpose = params:get("tonic") + (params:get("chord_octave") * 12) + 48
  local dynamics = params:get("chord_dynamics") * .01
  local ramp = params:get("chord_dynamics_ramp")
  
  if playback == "High-low" then
    start, finish, step = note_qty, 1, -1  -- Bottom to top
  else
    start, finish, step = 1, note_qty, 1   -- Top to bottom for chord or Low-high strum/arp
  end
  
  local curve = params:get("chord_timing_curve") * .1
  -- local max_pre_scale = curve_get_y(#chord_transformed * .1, curve) -- scales across all notes
  local max_pre_scale = curve_get_y((note_qty - 1) * .1, curve) * (1/((note_qty - 1) / note_qty)) -- scales to penultimate note
  local y_scaled = 0

  strum_clock = clock.run(function()
    latest_strum_coroutine = coroutine.running() -- sets coroutine each time a new strum occurs
    for i = start, finish, step do
      
      -- Strums will interrupt one another by default. TODO p2 make this a param because overlap is p sweet
      if coroutine.running() == latest_strum_coroutine then
        local note_sequence = playback == "High-low" and (note_qty + 1 - i) or i  -- force counting upwards
        local elapsed = note_qty == 1 and 0 or (note_sequence - 1) / (note_qty - 1)
        local dynamics = util.clamp(dynamics + (dynamics * ramp * .01 * elapsed), 0, 1)
        local note = chord_transformed[i] + transpose

        to_player(player, note, dynamics, chord_duration, channel)
  
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


-- note transformation function for seqs, harmonizers, are stored in a table indexed to matched `notes` params
local transform_note = {} -- table containing note transformation functions

transform_note[1] = function(note_num, octave) -- triad chord mapping
  local chord_length = 3
  local quantized_note = chord_triad[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("tonic"))
end


transform_note[2] = function(note_num, octave) -- Chord raw: custom chords played exactly as-is
  local chord_length = #chord_raw or 0
  local additional_octave = math.floor(((chord_raw[chord_length] or 0) - (chord_raw[1] or 0)) / 12) or 0 -- in anticipation of variable max_seqs
  local quantized_note = chord_raw[util.wrap(note_num, 1, chord_length)] or 0
  local quantized_octave = (math.floor((note_num - 1) / chord_length) * (additional_octave + 1)) or 0 -- no work on 24

  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("tonic"))
end


transform_note[3] = function(note_num, octave) -- Chord extd., insert notes from 1st octave into 2nd octave
  local chord_length = #chord_extended or 0

  -- jump to next octave if difference from chord min/max intervals is >1 octave.
  -- local additional_octave = (chord_raw[chord_length] - chord_raw[1]) >= 12 and 1 or 0 -- fine if we have just 12 seq rows
  local additional_octave = math.floor(((chord_extended[chord_length] or 0) - (chord_extended[1] or 0)) / 12) -- in anticipation of variable max_seqs
  local quantized_note = chord_extended[util.wrap(note_num, 1, chord_length)] or 0
  local quantized_octave = math.floor((note_num - 1) / chord_length) * (additional_octave + 1) -- no work on 24

  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("tonic"))
end


transform_note[4] = function(note_num, octave) -- Chord dense: custom chords with notes in 2nd octave played in 1st octave (removes duplicates in pitch class)
  local chord_length = #chord_densified or 0
  local quantized_note = chord_densified[util.wrap(note_num, 1, chord_length)] or 0
  local quantized_octave = math.floor((note_num - 1) / chord_length)

  return(quantized_note + ((octave + quantized_octave) * 12) + params:get("tonic"))
end


transform_note[5] = function(note_num, octave) -- song scale mapping
  local note_num = note_num
  local quantized_note = scale_heptatonic[util.wrap(note_num, 1, 7)] + (math.floor((note_num -1) / 7) * 12)

  return(quantized_note + (octave * 12) + params:get("tonic"))
end


transform_note[6] = function(note_num, octave) -- song scale mapping + diatonic transposition
  -- local diatonic_transpose = (math.max(pre == true and next_chord_x or current_chord_x, 1)) -1
  -- local diatonic_transpose = (math.max(current_chord_x, 1)) -1
  local note_num = note_num + (math.max(current_chord_x, 1)) -1 --(diatonic_transpose)
  local quantized_note = scale_heptatonic[util.wrap(note_num, 1, 7)] + (math.floor((note_num -1) / 7) * 12)

  return(quantized_note + (octave * 12) + params:get("tonic"))
end


transform_note[7] = function(note_num, octave) -- chromatic mapping
  return(note_num -1 + (octave * 12) + params:get("tonic"))
end


transform_note[8] = function(note_num, octave) -- chromatic intervals + base triad root
  local root = theory.chord_triad_intervals[params:get("scale")][current_chord_x][1]

  return(note_num  -1 + root + (octave * 12) + params:get("tonic"))
end


transform_note[9] = function(note_num, octave) -- drum kit/pass-thru mapping (no key transposition)
  return(note_num -1 + (octave * 12)) -- todo param to shift?
end


for i = 1, 8 do
  table.insert(transform_note,
    function(note_num, octave) -- custom mask
      local note_num = note_num
      local scale_custom = scale_custom[i]
      local length = #scale_custom
      local quantized_note = scale_custom[util.wrap(note_num, 1, length)] + (math.floor((note_num -1) / length) * 12)
      return(quantized_note + (octave * 12) + params:get("tonic"))
    end
  )

  table.insert(transform_note,
    function(note_num, octave) -- custom mask + degree transposition
      local note_num = note_num + (math.max(current_chord_x, 1)) -1 -- + transpose by chord degree
      -- local note_num = note_num + (theory.chord_triad_intervals[params:get("scale")][current_chord_x][1])  -- alternative transposing by base triad root (like chromatic+tr)
      local scale_custom = scale_custom[i]
      local length = #scale_custom
      local quantized_note = scale_custom[util.wrap(note_num, 1, length)] + (math.floor((note_num -1) / length) * 12)
      return(quantized_note + (octave * 12) + params:get("tonic"))
    end
  )
end


function reset_seq_pattern(seq_no)
  if seq_pattern_q[seq_no] then
    params:set("seq_pattern_" .. seq_no, seq_pattern_q[seq_no]) -- sets underlying table and length, too
    seq_pattern_q[seq_no] = false
  end

  seq_pattern_position[seq_no] = 0
end


function advance_seq_pattern(seq_no)
  local length = seq_pattern_length[seq_no][active_seq_pattern[seq_no]]

  if seq_pattern_position[seq_no] >= length or arranger_retrig == true then
    if params:string("seq_pattern_change_"..seq_no) == "On loop" then
      reset_seq_pattern(seq_no) -- do move to seq_pattern_q if populated
    else
      seq_pattern_position[seq_no] = 0 -- don't move to seq_pattern_q
    end
  end

  seq_pattern_position[seq_no] = util.wrap(seq_pattern_position[seq_no] + 1, 1, length)

  -- todo dynamic function set by seq_probability action? seems expensive
  -- todo would be awesome to have not just step probability but note probability!
  if params:get("seq_mute_"..seq_no) == 1 and math.random(1, 100) <= params:get("seq_probability_"..seq_no) then
    local player = params:lookup_param("seq_voice_raw_"..seq_no):get_player()
    local channel = player.channel and params:get("seq_channel_"..seq_no) or nil
    local dynamics = (params:get("seq_dynamics_"..seq_no) * .01)
    local dynamics = dynamics + (dynamics * (_G["sprocket_seq_"..seq_no].downbeat and (params:get("seq_accent_"..seq_no) * .01) or 0))
    local priority = params:get("seq_grid_"..seq_no)
    local polyphony = params:get("seq_polyphony_"..seq_no)
    local octave = params:get("seq_octave_"..seq_no)
    local row = seq_pattern[seq_no][active_seq_pattern[seq_no]][seq_pattern_position[seq_no]]
    local transform = transform_note[params:get("seq_note_map_"..seq_no)]

    
    -- todo dynamic function set by seq_priority action
    if priority == 1 then -- mono
      for x = 1, max_seq_cols do
        if row[x] == 1 then 
          local note = transform(x, octave) + 36
          to_player(player, note, dynamics, seq_duration[seq_no], channel)
          break
        end
      end
    
      
    elseif priority == 2 then -- poly L-R
      local count = 0
      for x = 1, max_seq_cols do
        if row[x] == 1 then
          local note = transform(x, octave) + 36
          to_player(player, note, dynamics, seq_duration[seq_no], channel)
          count = count + 1
          if count == polyphony then 
            break
          end
        end
      end
        
    elseif priority == 3 then -- poly R-L
      local count = 0
      for x = max_seq_cols, 1, -1 do
        if row[x] == 1 then 
          local note = transform(x, octave) + 36
          to_player(player, note, dynamics, seq_duration[seq_no], channel)
          count = count + 1
          if count == polyphony then 
            break
          end
        end
      end
      
    else-- if priority == 4 then -- pool

      local pool = {}
      for x = 1, max_seq_cols do
        if row[x] == 1 then
          table.insert(pool, x)
        end

      end
      shuffle(pool)

      for i = 1, math.min(#pool, polyphony) do
        local note = transform(pool[i], octave) + 36  -- make these local!
        to_player(player, note, dynamics, seq_duration[seq_no], channel)
      end
      
    end
  end
  
  
  if seq_pattern_position[seq_no] >= length then
    if params:string("seq_start_on_"..seq_no) ~= "Loop" then
      play_seq[seq_no] = false
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
  local note = transform_note[params:get("crow_note_map")](round(volts * 12, 0) + 1, params:get("crow_octave")) + 36

  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_pattern_retrig == true
  or params:get("crow_auto_rest") == 1
  or (params:get("crow_auto_rest") == 2 and (prev_note ~= note)) then
    -- Play the note
    
    local player = params:lookup_param("crow_voice_raw"):get_player()
    local channel = player.channel and params:get("crow_channel") or nil
    local dynamics = params:get("crow_dynamics") * .01

    to_player(player, note, dynamics, crow_duration, channel)
    
  end
  
  prev_note = note
  chord_pattern_retrig = false -- Resets at chord advance
end


--midi harmonizer input
midi_event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    local player = params:lookup_param("midi_voice_raw"):get_player()
    local channel = player.channel and params:get("midi_channel") or nil
    local transform = transform_note[params:get("midi_note_map")]
    local note = transform(d.note - 35, params:get("midi_octave")) + 36 -- todo p1 octave validation for all sources
    local dynamics = params:get("midi_dynamics") * .01 -- todo p1 velocity passthru (normalize to 0-1)

    to_player(player, note, dynamics, midi_duration, channel)
    
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

--#region local functions for grid_redraw

-- function for drawing arranger patterns + playhead
-- used by regular or shifted arranger (latter will pass modified x_offset depending on section)
-- Q: It's not clear when a jump is occuring if said jump is off-screen. How to address this?
local function draw_patterns_playheads(x, y, x_offset, arranger_led)
  local q = arranger_q
  if arranger_padded[q] then -- if arranger_q is valid, this takes priority for position pulsing

    if x_offset == arranger_q then
      arranger_led = (arranger_led or 0) + (arranger_led == 15 and 0 or 3) - led_pulse
    elseif x_offset == arranger_position and arranger_led ~= 15 then -- regular segments
      arranger_led = (arranger_led or 0) + 3
    end


  elseif arranger_next == 0 then                                      -- arranger ending
    if x_offset == arranger_position and arranger_led ~= 15 then
      arranger_led = led_low_blink
    elseif x_offset == arranger_position and arranger_led ~= 15 then  -- regular segments  
      arranger_led = (arranger_led or 0) + 3
    end

    -- pulse @ arranger_next when:
      -- End of arrangement and looping to 1
      -- arranger is either syncing or will need to sync when arranger is enabled (based on chord_pattern_position)
    -- DON'T pulse when:
      -- Arranger is reset (arranger/chord_position == 0)
      -- Arranger is advancing as usual. pulse indicates non-sequential changes.
  else
    local next = arranger_next
    if arranger_position ~= 0 and (next == 1 or (arranger_state ~= "on" and chord_pattern_position > 0)) then -- == "syncing" then
      if x_offset == next then
        arranger_led = (arranger_led or 0) + (arranger_led == 15 and 0 or 3) - led_pulse
      elseif x_offset == arranger_position and arranger_led ~= 15 then     -- regular segments  
        arranger_led = (arranger_led or 0) + 3
      end

    else
      if x_offset == arranger_position and arranger_led ~= 15 then     -- regular segments  
        arranger_led = (arranger_led or 0) + 3
      end
    end

  end

  if arranger_led then
    g:led(x, y, arranger_led)
  end

end


-- function for drawing event strip
-- used by regular or shifted arranger (latter will pass modified x_offset depending on section)
local function draw_events(x, x_offset)
  -- 4 possible states:
  -- out of bounds and no events    led_low
  -- out of bounds and event        led_med* some ambiguity here
  -- in bounds and no events        led_med* some ambiguity here
  -- in bounds and events           led_high
  --
  -- additionally, blink first and last col if arranger extends off-screen

  local in_bounds = x_offset <= arranger_length
  local populated = (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0
  local do_blink = (x == 1 and arranger_grid_offset > 0) or ((x == 16) and (arranger_length - arranger_grid_offset + d_cuml) > 16)

  if in_bounds then
    if populated then
      g:led(x, 5, do_blink and led_high_blink or led_high)
    else
      g:led(x, 5, do_blink and led_med_blink or led_med)
    end
  else -- OOB
    if populated then
      g:led(x, 5, do_blink and led_med_blink or led_med)
    else
      g:led(x, 5, do_blink and led_low_blink or led_low)
    end
  end

end


local function get_patterns(x_offset, y)
  local arranger_led = nil

  if y == arranger[x_offset] then
    arranger_led = led_high    -- regular segments
  elseif (x_offset <= arranger_length) and y == arranger_padded[x_offset] then
    arranger_led = led_low   -- dim padded segments
  end
  return(arranger_led)
end

--#endregion local functions for grid_redraw


function grid_redraw()
  local blinky = blinky
  local led_high = led_high
  local led_med = led_med
  local led_low = led_low
  local led_high_blink = led_high_blink
  local led_med_blink = led_med_blink
  local led_low_blink = led_low_blink
  local led_pulse = led_pulse
  
  g:all(0) -- todo look into efficiency of this
  
  if screen_view_name == "mask_editor" then
    local editing_scale = editing_scale
    local enabled_level = 8         -- can layer in_mode tones(3) + editing_lane_level(4 - 3 = 1) + pulse(3) = 7 max
    local in_mode = {}  -- table containing 12 notes and t/f if they are in the current mode
    local pattern_led = 0

    for x = 1, 12 do
      in_mode[x] = false
    end
    
    for i = 1, 7 do
      in_mode[scale_heptatonic[i] + 1] = true
    end

    local in_scale = theory.masks_bool

    for y = 1, 8 do
      local in_scale = in_scale[y]

      for x = 1, 12 do
        pattern_led = in_mode[x] and led_low or 0 -- low level highlight tones in mode
        pattern_led = pattern_led + (in_scale and in_scale[x] and enabled_level or 0) -- draw enabled tones for each row/scale
        if y == editing_scale and in_scale[x] and not in_mode[x] then -- pulse out-of-mode selections in editing scale/row
          pattern_led = pattern_led - led_pulse
        end
        g:led(x, y, pattern_led)
      end

      g:led(16, y, y == editing_scale and led_high - led_pulse or led_low) --draw selected scale keys on right side
    end


  elseif screen_view_name == "chord_editor" then
    local editing_chord_bools = editing_chord_bools
    local mode_bool = editing_chord_mode_intervals
    local enabled_level = 8
    local pattern_led = 0

    for i = 1, 24 do -- 2 octaves split across 2 rows
      local in_mode = mode_bool[util.wrap(i, 1, 12)]
      pattern_led = in_mode and led_low or 0 -- highlight tones in mode, starting with root note
      if editing_chord_bools[i] then
        pattern_led = pattern_led + enabled_level
      end
      if pattern_led > 0 and not in_mode then
        pattern_led = pattern_led - led_pulse
      end
      g:led(util.wrap(i, 1, 12), ((i <= 12) and 8 or 7), pattern_led)
    end

  elseif screen_view_name == "Events" then -- EVENT EDITOR
    local length = chord_pattern_length[arranger_padded[event_edit_segment]] or 0
    local lanes = 15
    local saved_level = 8         -- can layer playhead(3) + editing_lane_level(4 - 3 = 1) + pulse(3) = 7 max
    local lane_configured_led = 2 -- not layered and of secondary importance as screen is primary
    local editing_lane_level = 4  -- min of 1 (4 - max led_pulse) so we don't completely lose the led when on unconfigured lanes.

    -- For now, just fixing the loop length to underlying pattern (g.key disabled, too)
    -- events_length[event_edit_segment] = length

    -- Draw grid with [lanes] (columns) for each step in the selected pattern    
    for x = 1, lanes do  -- event lanes
      for y = 1, rows do -- pattern steps
        local y_offset = y + pattern_grid_offset

        -- saved events are medium brightness, configured lanes are low, otherwise 0
        if events[event_edit_segment][y_offset][x] ~= nil then
          pattern_led = saved_level
        elseif event_lanes[x].id ~= nil then
          pattern_led = lane_configured_led
        else
          pattern_led = 0
        end

        -- playhead can work two ways. todo global pref?
        --
        -- OPTION A: show only when this exact arranger segment is being played
        if arranger_position == event_edit_segment and y_offset == chord_pattern_position then
          pattern_led = pattern_led + led_low
        end
        -- OPTION B: show any time the edited arranger segment matches the chord pattern (A-D)
        -- if arranger_padded[event_edit_segment] == active_chord_pattern and y_offset == chord_pattern_position then
        --   pattern_led = pattern_led + playhead_level
        -- end

        -- pulse selected event_lane when not editing event slot
        if not event_edit_active and x == params:get("event_lane") then
          pattern_led = pattern_led + editing_lane_level - led_pulse
        end

        -- selected event supercedes all layers
        -- saved pulses, unsaved/new flickers
        if y_offset == event_edit_step and x == event_edit_lane then
          pattern_led = (event_edit_status ~= "(Saved)" and (led_high_blink) or (led_high - led_pulse))
        end

        g:led(x, y, pattern_led)

      end

    end

    -- pattern length indicator
    -- loop_length is for sub-loop within even
    -- local loop_length = events_length[event_edit_segment]
    -- todo update to use lvl_ vars
    for y = 1, rows do
      local y_offset = y + pattern_grid_offset
      local loop_led = (y_offset <= (length or 0) and 15 or 3)
      
      -- blink the first row if we've scrolled down  
      if y == 1 and pattern_grid_offset > 0 then
        loop_led = loop_led - (blinky * (loop_led == 15 and 4 or 1))
      -- blink the last row if min of underlying pattern or event loop length extends below grid view
      elseif y == rows and (length - pattern_grid_offset) > rows then
        loop_led = loop_led - (blinky * (loop_led == 15 and 4 or 1))
      end

      g:led(16, y, loop_led)
    end
    

  else -- ARRANGER, GRID, SEQ views
    for i = 6, 8 do -- dim view_switcher keys at bottom right
      g:led(16, i + extra_rows, led_low)
    end
    
    for i = 1, #grid_view_keys do -- held view_switcher keys (selected/active is added later)
      g:led(16, grid_view_keys[i] + extra_rows , led_med)
    end
    

    if grid_view_name == "Arranger" then -- ARRANGER GRID REDRAW
      g:led(16, 6 + extra_rows, led_high) -- set view_switcher led

      ----------------------
      -- Arranger shifting 
      ------------------------
      if arranger_loop_key_count > 0 then
        local in_bounds = event_edit_segment <= arranger_length -- some weird stuff needs to be handled if user is shifting events past the end of the pattern length

        if d_cuml >= 0 then -- Shifting arranger pattern to the right and opening up this many segments between event_edit_segment and event_edit_segment + d_cuml

          ------------------------------------------------
          -- positive d_cuml shifts arranger to the right and opens a gap
          ------------------------------------------------
          -- x_offsets fall into 3 groups:
          --  1. >= event_edit_segment + d_cuml will shift to the right by d_cuml segments
          --  2. < event_edit_segment draw as usual
          --  3. Remaining are in the "gap" and we need to grab the previous pattern and repeat it
          for x = 16, 1, -1 do -- draw from right to left
            local x_offset = x + arranger_grid_offset -- Grid x + the offset for whatever page or E1 shift is happening
            
            if x_offset >= event_edit_segment + d_cuml then -- group 1
              local x_offset = x_offset - d_cuml
              
              for y = 1, 4 do -- patterns
                arranger_led = get_patterns(x_offset, y)
                local x_offset = x + arranger_grid_offset -- revert x_offset
                draw_patterns_playheads(x, y, x_offset, arranger_led)
              end

              draw_events(x, x_offset)
              
            elseif x_offset < event_edit_segment then -- group 2
              
              for y = 1, 4 do -- patterns
                arranger_led = get_patterns(x_offset, y)
                draw_patterns_playheads(x, y, x_offset, arranger_led)
              end
              
              draw_events(x, x_offset)

            else -- group 3 (gap)
              -- no need to do anything with patterns if extending beyond arranger_length
              -- can still move around events beyond extent of arranger, though
              if in_bounds then
                local pattern_padded = arranger_padded[math.max(event_edit_segment - 1, 1)]

                for y = 1, 4 do -- patterns
                  arranger_led = y == pattern_padded and 3 or nil
                  draw_patterns_playheads(x, y, x_offset, arranger_led)
                end

                -- can't use draw_events here because we DO want to extend in_bounds area but DON'T want to offset populated segments
                  g:led(x, 5, x == 16 and ((arranger_length - arranger_grid_offset + d_cuml) > 16) and led_med_blink or led_med)

              else -- extending blanks to the right which doesn't require draw_events()
                g:led(x, 5, led_low)  -- just draw the event strip
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
            -- Redefine x_offset only for group #1: patterns that need to be shifted left. Group 2 will be handled as usual
            local x_offset = (x_offset >= event_edit_segment + d_cuml) and (x_offset - d_cuml) or x_offset

            for y = 1, 4 do
              arranger_led = get_patterns(x_offset, y)
              local x_offset = x + arranger_grid_offset -- revert x_offset
              draw_patterns_playheads(x, y, x_offset, arranger_led)
            end

            draw_events(x, x_offset)

          end -- of drawing for negative d_cuml shift              
        end
      
      else -- arranger_loop_key_count == 0: no arranger shifting
        for x = 1, 16 do

          local x_offset = x + arranger_grid_offset

          for y = 1,4 do
            local arranger_led = nil

            arranger_led = y == arranger[x_offset] and 15 or (y == arranger_padded[x_offset] and 3) -- actual/padded segments
            draw_patterns_playheads(x, y, x_offset, arranger_led)
          end

          draw_events(x, x_offset)

        end
      end

      -- enable Arranger, change playback mode
      if arranger_state == "on" then
        g:led(1, 8 + extra_rows, 15)
      elseif arranger_state == "off" then
        g:led(1, 8 + extra_rows, 4)
      else -- syncing
        g:led(1, 8 + extra_rows, 15 - led_pulse)
      end

      g:led(2, 8 + extra_rows, params:get("playback") == 2 and 15 or 4)
        
      -- pagination with scroll indicator for arranger grid view
      -- to flash page of if arranger position is off-grid
      local view_min = arranger_grid_offset + 1
      local view_max = arranger_grid_offset + 16
      local position_page

      if arranger_position < view_min or arranger_position > view_max then
        position_page = math.floor((arranger_position - 1)/16)
      else
        position_page = -1
      end

      for i = 0, 3 do
        local target = i * 16
        local led = math.max(10 + util.round((math.min(target, arranger_grid_offset) - math.max(target, arranger_grid_offset))/2), 1) + 2
 
          if position_page == i then
            led = led - (math.ceil(led / 6) * blinky) -- scale blink intensity to led
          end

        g:led(i + 7, 8 + extra_rows , led)
      end

      -- visual detent on divisions matching pagination jumps
      if arranger_grid_offset % 16 == 0 then
        g:led(7 + (arranger_grid_offset / 16), 8 + extra_rows, 15)
      end
      

    elseif grid_view_name == "Chord" then   -- CHORD GRID REDRAW
      local mute = params:get("chord_mute") == 2
      local level_next = led_med - led_pulse
      local length = chord_pattern_length[active_chord_pattern]

      for i = 1, 4 do
        if i == active_chord_pattern then
          g:led(16, i, mute and led_high_blink or led_high)
        elseif i == chord_pattern_q then
          g:led(16, i, level_next)
        else
          g:led(16, i, pattern_keys[1][i] and led_med or led_low)
        end
      end

      g:led(16, 7 + extra_rows, 15) -- grid view selector
            
      for y = 1, rows do
        local y_offset = y + pattern_grid_offset
        local playhead_row = y_offset == chord_pattern_position
        local on_col = chord_pattern[active_chord_pattern][y_offset]

        if length - pattern_grid_offset > rows and y == rows then -- chord pattern_length LEDs
          g:led(15, y, led_high_blink)
        elseif pattern_grid_offset > 0 and y == 1 then 
          g:led(15, y, (length < (y_offset) and led_low_blink or led_high_blink))
        else  
          g:led(15, y, length < (y_offset) and 3 or 15)
        end
        
        for x = 1, 14 do -- sequence pattern LEDs off/on
          g:led(x, y, (x == on_col and led_med or 0) + (playhead_row and led_low or 0))
        end

      end
      
      
    elseif grid_view_name == "Seq" then  -- SEQ GRID REDRAW
      local selected_seq_no = selected_seq_no
      local level_next = led_med - led_pulse
      local length = seq_pattern_length[selected_seq_no][active_seq_pattern[selected_seq_no]]

      g:led(16, 8 + extra_rows, 15) -- set view_selector indicator to seq position
      
      for y = 1, rows do
        local y_offset = y + pattern_grid_offset
        local playhead_row = y_offset == seq_pattern_position[selected_seq_no]

        if length - pattern_grid_offset > rows and y == rows then -- seq pattern length/loop
          g:led(max_seq_cols + 1, y, led_high_blink)
        elseif pattern_grid_offset > 0 and y == 1 then 
          g:led(max_seq_cols + 1, y, (length < (y_offset) and led_low_blink or led_high_blink))
        else
          g:led(max_seq_cols + 1, y, length < (y_offset) and led_low or led_high)
        end

        for x = 1, max_seq_cols do -- patterns + playhead
          pattern_led = (seq_pattern[selected_seq_no][active_seq_pattern[selected_seq_no]][y_offset][x] == 1) and led_med or 0
          g:led(x, y, pattern_led + (playhead_row and led_low or 0))
        end
        
      end

      -- active seq pattern selector
      for seq_no = 1, max_seqs do
        local x = seq_no + max_seq_cols + 1
        local selected = seq_no == selected_seq_no
        local mute = params:get("seq_mute_"..seq_no) == 2
        -- local q = params:string("seq_pattern_change_"..seq_no) ~= "Instantly"
        local lvl_selected = mute and led_high_blink or led_high
        local lvl_unselected = mute and led_med_blink or led_med

        for pattern = 1, max_seq_patterns do -- y
          if pattern == seq_pattern_q[seq_no] then -- cued pattern
            g:led(x, pattern, level_next)
          elseif pattern == active_seq_pattern[seq_no] then
            g:led(x, pattern, selected and lvl_selected or lvl_unselected)
          else
            g:led(x, pattern, pattern_keys[seq_no][pattern] and led_med or led_low)
          end
        end

      end

    end
  end
  g:refresh()
end


function reset_grid_led_phase()
  cycle_1_16 = 1 -- restart pulse cycle so upcoming pattern is immediately visible
  led_pulse = 0
  grid_dirty = true
end


function set_page()
  page_name = pages[page_index]
  local new_view = nil  
  local new_pattern = selected_seq_no

  if params:string("sync_views") == "On" then 
    if page_name == "SONG" then
      new_view = "Arranger"
    elseif page_name == "CHORD" then
      new_view = "Chord"
    elseif string.sub(page_name, 1, 3) == "SEQ" then
      new_view = "Seq"
      new_pattern = tonumber(string.sub(page_name, 4)) or new_pattern
    end

    if (grid_view_name ~= new_view) or (selected_seq_no ~= new_pattern) then
      pattern_grid_offset = 0
      reset_grid_led_phase() -- reset led pulse phase so it's most visible
      grid_view_name = new_view
      selected_seq_no = new_pattern
      grid_dirty = true
    end

  end

end


function set_grid_view(new_view, new_seq_no) -- optional 2nd arg for seq no
  local new_seq_no = new_seq_no or selected_seq_no

  if (grid_view_name ~= new_view) or (selected_seq_no ~= new_seq_no) then
    pattern_grid_offset = 0
    reset_grid_led_phase() -- reset led pulse phase so it's most visible
    grid_view_name = new_view
    selected_seq_no = new_seq_no
    grid_dirty = true

    if params:string("sync_views") == "On" then -- sync norns screen view with grid view
      local new_page = nil

      if new_view == "Arranger" then
        new_page = "SONG"
      elseif new_view == "Chord" then
        new_page = "CHORD"
      elseif new_view == "Seq" then
        new_page = "SEQ " .. new_seq_no
      end

      page_index = tab.key(pages, new_page)
      page_name = new_page

      menu_index = 0
      selected_menu = menus[page_index][menu_index]
    end

  end
end


-- sets chord_pattern_q var and resets grid_led_phase when appropriate
-- 0 or nil arg will cancel q
function set_chord_pattern_q(new_pattern)
  if new_pattern == 0 then
    chord_pattern_q = nil
  else
    local current_pattern = chord_pattern_q
    chord_pattern_q = new_pattern
    if current_pattern ~= new_pattern then -- actions to take if pattern q changed
      reset_grid_led_phase()
    end
  end
end

-- update chord_pattern_q with what's next up in arranger
function update_chord_pattern_q() -- run after changes are made to arranger or arranger pos (arranger_shift, keys, etc...)
  set_chord_pattern_q(arranger_padded[arranger_q] or arranger_padded[arranger_next])
end

-- inits table of standard chord options for editing mode/degree
-- todo p0 needs to be called on mode param change, too (events)
-- or we need to lock in scales upon entering menu (prob better)
function gen_chord_menus()
  chord_menu_names = theory.lookup_scales[theory.base_scales[params:get("scale")]].chord_names[util.wrap(editing_chord_x, 1, 7)]
end


-- set initial states for bool table so grid_redraw doesn't have to do this every loop.
-- intervals relative to degree I, in octave
-- called by init_chord_editor, g.key, enc
function gen_chord_bools(intervals)
  local root = editing_chord_root

  editing_chord_bools = {}

  for i = 1, 24 do
    editing_chord_bools[i] = false
  end

  for i = 1, #intervals do  -- set earlier to either standard or custom
    editing_chord_bools[intervals[i] + 1 - root] = true
  end
end


-- generates bool table for selected intervals in chord
-- generates chord menus
function init_chord_editor()
  local pattern = editing_chord_pattern
  local x = editing_chord_x
  local y = editing_chord_y
  local root = editing_chord_root
  local name = "Custom"
  local intervals = {}

  gen_chord_menus() -- generates chord_menu_names table

  -- set editing_chord_intervals table which gets the custom interval if available or the standard degree intervals
  local custom = theory.custom_chords[params:get("scale")][pattern][x]

  if custom[y] then
    intervals = custom[y].intervals

    if name == "Custom" then
      editing_chord_type = "custom"
    else
      editing_chord_type = "named" -- default if the subsequent check is negative
      -- check if the recognized chord is "in-mode"
      for i = 1, #chord_menu_names do
        if chord_menu_names[i] == name then
          editing_chord_type = "in-mode"
          break
        end
      end
    end
  else
    intervals = theory.chord_triad_intervals[editing_chord_scale][x]
    editing_chord_type = "standard"
  end

  c = find_chord(intervals, root) -- pass root so intervals can be converted from absolute to relative to root
  gen_chord_bools(intervals)
  chord_menu_index = c and tab.key(chord_menu_names, c.short_name) or 0
end



-- check if this is a named scale and set Scale menu appropriately
function set_scale_menu()
  local lookup = theory.lookup_scales
  local name = find_scale_name(theory.masks[params:get("scale")][editing_scale]) or "Custom"
  if name ~= "Custom" then -- set Scale menu if there's a match
    for i = 1, #lookup do
      if name == lookup[i].name then
        scale_index = i
        break
      end
    end
  else
    scale_index = 0 -- "Custom"
  end
end
        
        
-- GRID KEYS
---@diagnostic disable-next-line: duplicate-set-field
function g.key(x, y, z)
  if z == 1 then
    if screen_view_name == "chord_editor" then
      if x <= 12 and y >= 7 then
        local interval = util.wrap(x, 1, 12) + (y == 7 and 12 or 0)
        local pattern = editing_chord_pattern
        local editing_chord_x = editing_chord_x -- distinct from x/y coords!
        local editing_chord_y = editing_chord_y -- distinct from x/y coords!
        local root = editing_chord_root
        local editing_chord_bools = editing_chord_bools
        local custom = theory.custom_chords[editing_chord_scale][pattern][editing_chord_x]

        if not custom[editing_chord_y] then
          custom[editing_chord_y] = {intervals = {}}
        end
        
        editing_chord_bools[interval] = not editing_chord_bools[interval]

        custom[editing_chord_y]["intervals"] = {} -- write back to custom_chords

        for i = 1, #editing_chord_bools do
          if editing_chord_bools[i] then
            local i = i - 1
            table.insert(custom[editing_chord_y]["intervals"], i + root)
          end
        end

        local c = find_chord(custom[editing_chord_y].intervals, root) -- pass root so intervals can be converted from absolute to relative to root
        chord_menu_index = c and tab.key(chord_menu_names, c.short_name) or 0
        custom[editing_chord_y].name = c and c.short_name or "Custom"
        custom[editing_chord_y].dash_name_1 = c and c.dash_name_1 --or (c.short_name .. "*") -- sub short_name if it's an unnamed chord
        custom[editing_chord_y].dash_name_2 = c and c.dash_name_2 or nil

        gen_chord_name()
      end

    elseif screen_view_name == "mask_editor" then
      if x <= 12 then
        local mode = params:get("scale")
        local scale = theory.masks_bool[y]

        editing_scale = y
        scale[x] = not scale[x] -- set value in flat table

        -- write the changed pattern back to theory.masks which is the save format
        theory.masks[mode][y] = {}
        for i = 1, 12 do
          if theory.masks_bool[y][i] then
            table.insert(theory.masks[mode][y], i - 1)
          end
        end

        build_scale()
        set_scale_menu()

        grid_dirty = true
      elseif x == 16 then
        editing_scale = y
        grid_dirty = true
        set_scale_menu()
      end
    
    elseif screen_view_name == "Events" then
      if x == 16 then -- loop length
        -- temporarily disabled as event loop length needs implementation
        -- events_length[event_edit_segment] = y + pattern_grid_offset
      else
        lane_glyph_preview = nil
        local events_path = events[event_edit_segment][y + pattern_grid_offset][x]

        -- Setting of events beyond the pattern length is permitted
        event_key_count = event_key_count + 1
      
        -- load events
        -- First touched event is the one we edit, effectively resetting on key_count = 0
        if event_key_count == 1 then
          event_edit_step = y + pattern_grid_offset
          params:set("event_lane", x) -- todo can this replace event_lane??
          event_edit_lane = x
          event_saved = false

          local event_edit_lane_id = event_lanes[x].id -- used to determine if lane is configured or not

          -- If the event is populated, Load the Event vars back to the displayed param.
          if events_path ~= nil then
            events_index = 1
            selected_events_menu = events_menus[events_index]

            local id = events_path.id
            local index = events_lookup_index[id]
            local value = events_path.value
            local operation = events_path.operation
            local limit = events_path.limit or "Off"

            event_edit_status = "(Saved)"

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


          elseif event_edit_lane_id ~= nil then -- load default event for configured lane

            events_index = 1
            selected_events_menu = events_menus[1]

            local index = events_lookup_index[event_edit_lane_id]
            local event = events_lookup[index] -- with unconfigured lanes, use event instead of event_path

            event_edit_status = "(New)"

            params:set("event_category", param_option_to_index("event_category", event.category)) -- see if this change can be applied above, too
            change_category()
            
            params:set("event_subcategory", param_option_to_index("event_subcategory", event.subcategory))
            change_subcategory()
            
            params:set("event_name", index)
            change_event()

            -- todo wishlist:     
            -- when working in a single lane, the last-set value persists across slots
            -- but changing to a new lane then returning will reset to the current param value
            -- would be nice to have a memory of the last-set value in lane, but this requires that it be explicitly saved somewhere

          else -- unconfigured lanes
            event_edit_status = "(New)"
            change_operation("change_event") -- sets starting value to param's current value rather than default value
          end
          gen_menu_events()

          event_edit_active = true
          
        else -- Subsequent keys down paste event
          -- But first check if the events we're working with are populated
          local og_event_populated = events_path ~= nil
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

          notification("COPIED " .. event_edit_step .. "." .. event_edit_lane  .. " TO " .. (y + pattern_grid_offset) .. "." .. x , {"g", x, y})
          update_lanes(x) -- update the lanes we've pasted into
        end
      end

    elseif x == 16 and y > 5 + extra_rows then -- view switcher (across all views except Events)
      if (grid_interaction or "view_switcher") == "view_switcher" then  -- other interactions block view switching
        grid_interaction = "view_switcher"
        view_key_count = view_key_count + 1
        
        -- following lines cancel any pending pattern changes by acting as if a copy was just performed (overrides)
        -- pattern_key_count = 0
        -- pattern_copy_performed = true
        
        table.insert(grid_view_keys, y - extra_rows)
        if view_key_count == 1 then
          set_grid_view(grid_views[y - extra_rows - 5])

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
          notification("ARRANGER ON", {"g", x, y})
        else
          params:set("arranger", 1)
          notification("ARRANGER OFF", {"g", x, y})
        end

      -- Switch between Arranger playback Loop or 1-shot mode
      elseif x == 2 and y == 8 + extra_rows then
        if params:get("playback") == 2 then
          params:set("playback", 1)
          notification("LOOPING OFF", {"g", x, y})
        else
          params:set("playback", 2)
          notification("LOOPING ON", {"g", x, y})
        end
        
      -- Arranger pagination jumps
      elseif y == 8 + extra_rows then
        if x > 6 and x < 11 then
          arranger_grid_offset = (x - 7) * 16
        end
        
      
      -- ARRANGER SEGMENT CHORD PATTERNS
      elseif y < 5 and grid_interaction ~= "arranger_shift" then
        arranger[x_offset] = y == arranger[x_offset] and 0 or y  -- change arranger segment
        gen_arranger_padded()
        update_chord_pattern_q()
        
        -- allow pasting of events while setting patterns (but not the other way around)
        if grid_interaction == "event_copy" then
          events[x_offset] = deepcopy(events[event_edit_segment])
          notification("COPIED " .. event_edit_segment .. " TO " .. x_offset, {"g", x, y})
          gen_arranger_dash_data("Event copy+paste")
        end
        
        update_arranger_next() -- updates/sets arranger_next if needed

      -- ARRANGER EVENTS TIMELINE KEY DOWN
      elseif y == 5 then
        arranger_loop_key_count = arranger_loop_key_count + 1
        if (grid_interaction or "event_copy") == "event_copy" then -- if no interaction or already in event_copy
          grid_interaction = "event_copy"
          -- First touched pattern is the one we edit, effectively resetting on key_count = 0
          if arranger_loop_key_count == 1 then
            event_edit_segment = x_offset
  
          -- Subsequent keys down paste all arranger events in segment, but not the segment pattern
          -- arranger shift interaction will block this
          -- implicit here that more than 1 key is held down so we're pasting
          else
            events[x_offset] = deepcopy(events[event_edit_segment])
            notification("COPIED " .. event_edit_segment .. " TO " .. x_offset, {"g", x, y})
            gen_arranger_dash_data("Event copy+paste")
          end
        end
      
      end
      
    elseif grid_view_name == "Chord" then
      if x < 15 then -- chord degrees
        local x_wrapped = util.wrap(x, 1, 7)
        local y_offset = y + pattern_grid_offset
        chord_key_count = chord_key_count + 1 -- used to determine "chord_key_held" grid_interaction

        -- flag this pattern/chord as needing to be disabled on key-up, if not interrupted by some other action
        if x == chord_pattern[active_chord_pattern][y_offset] then
          if not pending_chord_disable[x] then
            pending_chord_disable[x] = {}
          end
          pending_chord_disable[x][y_offset] = active_chord_pattern

        else
          chord_pattern[active_chord_pattern][y_offset] = x
          -- pending_chord_disable = nil -- will be for copy+paste
        end

        -- plays Chord when pressing on any Grid key (even turning chord off)
        if params:get("preview_notes") == 2 and (transport_state == "stopped" or transport_state == "paused") then
          update_chord(x, y)
          play_chord()
        end

        -- todo p0 need to do copy+paste and figure out complications there with simultaneous keypresses
        if not grid_interaction then -- first keypress which defines editing_chord
          grid_interaction = "chord_key_held"
          lvl = lvl_dimmed
          update_dash_lvls()
          editing_chord_scale = params:get("scale")
          editing_chord_pattern = active_chord_pattern
          editing_chord_x = x -- used for chord editor
          editing_chord_y = y -- used for chord editor
          editing_chord_root = theory.chord_triad_intervals[editing_chord_scale][x][1]

          local mode = params:get("scale")
          local key = util.wrap(params:get("tonic"), 0, 11)
          editing_chord_letter = theory.scale_chord_letters[mode][key][x_wrapped]       -- letter
          editing_chord_triad_name = theory.scale_chord_names[mode][key][x_wrapped]        -- base triad name+quality

          -- todo p0!
          editing_chord_degree = theory.chord_degree[mode]["numeral"][x_wrapped]        -- degree roman numeral only
          
          gen_chord_name()
          init_chord_editor() -- moved here from K3 so this can be used for quick chord selection
        end

        preload_chord()

      elseif x == 15 then -- set chord_pattern_length
        params:set("chord_pattern_length", y + pattern_grid_offset)
        gen_arranger_dash_data("g.key chord_pattern_length")
      

      elseif x == 16 and y <5 then  --Key DOWN events for chord pattern switcher
      
        if grid_interaction == "view_switcher" then -- mute/unmute
          params:set("chord_mute", 3 - params:get("chord_mute")) -- toggle mute state
        else

          grid_interaction = "pattern_switcher"
          pattern_key_count = pattern_key_count + 1
          pattern_keys[1][y] = true -- pattern_keys is used by seqs as well so when in chord mode, always use table 1
          if pattern_key_count == 1 then
            copied_pattern = y
          else -- if pattern_key_count > 1 then
            notification("COPIED " ..  pattern_name[copied_pattern] .. " TO " .. pattern_name[y], {"g", x, y})
            pattern_copy_performed[1] = true
            chord_pattern[y] = simplecopy(chord_pattern[copied_pattern])

            for scale = 1, #dreamsequence.scales do             -- copy custom chords (for all scales)
              theory.custom_chords[scale][y] = deepcopy(theory.custom_chords[scale][copied_pattern])
            end

            -- If we're pasting to the currently viewed active_chord_pattern, do it via param so we update param/grid table.
            if y == active_chord_pattern then
              params:set("chord_pattern_length", chord_pattern_length[copied_pattern])
            -- Otherwise just update the table
            else
              chord_pattern_length[y] = chord_pattern_length[copied_pattern]
            end

          end
        end
      end
      
    -- SEQ PATTERN KEYS
    elseif grid_view_name == "Seq" then
      if x <= max_seq_cols then -- seq pattern keys
        local y_offset = y + pattern_grid_offset
        local selected = seq_pattern[selected_seq_no][active_seq_pattern[selected_seq_no]][y_offset]

        if params:string("seq_grid_"..selected_seq_no) == "Mono" then
          local note = selected[x]
          for col = 1, max_seq_cols do
            selected[col] = 0
          end
          selected[x] = 1 - note
        else
          selected[x] = 1 - selected[x]
        end

        -- Play note if stopped/paused. Todo: may want to have this be a pref for stopped/paused, stopped, off
        -- plays note when pressing on any Grid key (even turning note off)
        -- mostly shared with advance_seq. could be consolidated into one fn
        if params:get("preview_notes") == 2 and (transport_state == "stopped" or transport_state == "paused") then
          local player = params:lookup_param("seq_voice_raw_"..selected_seq_no):get_player()
          local channel = player.channel and params:get("seq_channel_"..selected_seq_no) or nil
          local dynamics = (params:get("seq_dynamics_"..selected_seq_no) * .01)
          -- local dynamics = dynamics + (dynamics * (sprocket_seq_1.downbeat and (params:get("seq_accent_1") * .01) or 0))
          local transform = transform_note[params:get("seq_note_map_"..selected_seq_no)]
          local note = transform(x, params:get("seq_octave_"..selected_seq_no)) + 36

          to_player(player, note, dynamics, seq_duration[selected_seq_no], channel)
        end
      elseif x == max_seq_cols + 1 then -- seq loop length
        params:set("seq_pattern_length_" .. selected_seq_no, y + pattern_grid_offset)
      elseif y <= max_seq_patterns then -- seq pattern selector
        local seq_no = x - (16 - max_seqs)

        if grid_interaction == "view_switcher" then -- mute/unmute
          params:set("seq_mute_"..seq_no, 3 - params:get("seq_mute_"..seq_no))

        else
          grid_interaction = "pattern_switcher"
          pattern_key_count = pattern_key_count + 1 --used to identify when the first key is pressed and last key is released. Could also use pattern_keys...
          pattern_keys[seq_no][y] = true -- log keydown

          if pattern_key_count == 1 then -- initial keydown sets pattern to copy and starts timer for simultaneous keydown detection
            simultaneous = false
            copied_seq_no = seq_no
            copied_pattern = y
            clock.run(pattern_key_timer)
            update_seq_pattern = {}
            update_seq_pattern[seq_no] = y -- sets pattern we need to update seq_no/index to on key-up

          else
            if (seq_no ~= copied_seq_no) and (keydown_timer < 2) then -- if ANY other seq is touched <2ms after initial keydown, this is now a simultaneous interaction
              simultaneous = true
            end

            if not simultaneous then -- copy pattern
                update_seq_pattern[copied_seq_no] = nil -- remove entry since we don't want to change to the pattern we're copying from

                -- possibly misleading as this copies the pattern in current state rather than when keydown was performed
                -- todo consider copying the table contents at keydown which is probably what users expect (but more expensive)
                for step = 1, max_seq_pattern_length do
                  for note = 1, max_seq_cols do
                    seq_pattern[seq_no][y][step][note] = seq_pattern[copied_seq_no][copied_pattern][step][note]
                  end
                end

                -- Pattern length. If we're pasting to a current active_seq_pattern, also update param
                if y == active_seq_pattern[seq_no] then
                  params:set("seq_pattern_length_" .. seq_no, seq_pattern_length[copied_seq_no][copied_pattern])
                else
                  seq_pattern_length[seq_no][y] = seq_pattern_length[copied_seq_no][copied_pattern]
                end
                notification("COPIED " ..  copied_seq_no .. "." .. pattern_name[copied_pattern] .. " TO " .. seq_no .. "." .. pattern_name[y], {"g", x, y})

            else -- simultaneous keypresses in other seq columns are interpreted as intent to switch patterns
              update_seq_pattern[seq_no] = y -- sets pattern we need to update seq_no/index to on key-up
            end
          end

        end
      end
    end
    
  --------------
  --G.KEY RELEASED
  --------------
  elseif z == 0 then

    -- Events key up
    if screen_view_name == "mask_editor" then
      -- reserved
    
    elseif screen_view_name == "Events" then

      event_key_count = math.max(event_key_count - 1,0)
      
      -- Reset event_edit_step/lane when last key is released (if it was skipped when doing a K3 save to allow for copy+paste)
      if event_key_count == 0 and event_saved then
        event_edit_step = 0
        event_edit_lane = 0
      end

    elseif x == 16 and y > 5 then -- view_key buttons

      -- tracking of view_switcher keys is never blocked by interactions
      view_key_count = math.max(view_key_count - 1, 0)
      table.remove(grid_view_keys, tab.key(grid_view_keys, y))

      if grid_interaction == "view_switcher" then -- other interactions block processing
        if view_key_count > 0 then
          set_grid_view(grid_views[grid_view_keys[1] - 5]) -- in case multiple are held and one is released
          
          if view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
            screen_view_name = "Chord+seq" -- used for tooltip when holding multiple keys. Kinda hacky.
          else
            screen_view_name = "Session"   -- used for tooltip
          end
        else
          screen_view_name = "Session"     -- used for tooltip
          grid_interaction = nil -- how to handle other interaction keys that are being held and were blocked?
        end
      end
   
    elseif grid_view_name == "Chord" then -- Chord key up
      if x == 16 then
        if y <5 then

          -- always keep track of these even if in a blocking interaction
          pattern_key_count = math.max(pattern_key_count - 1,0)
          pattern_keys[1][y] = nil

          if grid_interaction == "pattern_switcher" then
            if pattern_key_count == 0 and pattern_copy_performed[1] == false then
              
              -- Resets current active_chord_pattern immediately if transport is stopped
              if y == active_chord_pattern and transport_active == false then
                -- print("Manual reset of current pattern; disabling arranger")
                if params:get("arranger") == 2 then
                  params:set("arranger", 1)
                  notification("ARRANGER OFF", {"g", x, y})
                end
                chord_pattern_position = 0
                reset_external_clock()
                reset_pattern()
                if arranger_position == 1 and chord_pattern_position == 0 then
                  reset_arrangement()
                end
                
              elseif y == chord_pattern_q and transport_active == false then -- Manual jump to queued pattern
                print("Manual jump to queued pattern")
                
                set_chord_pattern(y)
                for seq_no = 1, max_seqs do
                  reset_seq_pattern(seq_no)
                end
                chord_pattern_position = 0
                reset_external_clock()
                reset_pattern() -- todo needs to calculate new transport- not just reset pattern!
    
              -- Cue up a new pattern        
              else
                -- print("New pattern queued; disabling arranger")
                if pattern_copy_performed[1] == false then
                  if params:get("arranger") == 2 then
                    params:set("arranger", 1)
                    notification("ARRANGER OFF", {"g", x, y})
                  end
                  set_chord_pattern_q(y)
                end
              end
            end

            if pattern_key_count == 0 then
              -- print("resetting pattern_copy_performed to false")
              pattern_copy_performed[1] = false
              grid_interaction = nil
              pattern_keys[1] = {}
            end

          end
        end


      elseif x < 15 then -- chord degrees
        local y_offset = y + pattern_grid_offset

        chord_key_count = math.max(chord_key_count - 1, 0)

        local p = pending_chord_disable
        if p[x] and p[x][y_offset] then
          local pattern = p[x][y_offset]
          chord_pattern[pattern][y_offset] = 0
          p[x][y_offset] = nil
          if count_table_entries(p[x]) == 0 then
            p[x] = nil
          end
        end
      
        if chord_key_count == 0 then
          if grid_interaction == "chord_key_held" then
            grid_interaction = nil
            lvl = lvl_normal
            update_dash_lvls()
          end
        end

      end

    elseif grid_view_name == "Seq" then -- Seq key up
      if x > max_seq_cols + 1 and y <= max_seq_patterns then
        local seq_no = x - (16 - max_seqs)

        -- always keep track of these even if in a blocking interaction
        pattern_key_count = math.max(pattern_key_count - 1, 0)
        pattern_keys[seq_no][y] = nil

        if grid_interaction == "pattern_switcher" then
          local new_pattern = update_seq_pattern[seq_no]
          local q = seq_pattern_q

          if new_pattern then
            if params:string("seq_pattern_change_"..seq_no) == "Instantly" then -- swap pattern immediately vs cue next pattern
              params:set("seq_pattern_" .. seq_no, new_pattern)
            elseif q[seq_no] and new_pattern == q[seq_no] then -- double tap jumps immediately, like chord
                params:set("seq_pattern_" .. seq_no, new_pattern)
                q[seq_no] = false
            elseif q[seq_no] and new_pattern == active_seq_pattern[seq_no] then -- selecting current active pattern will cancel q
              q[seq_no] = false
            elseif new_pattern ~= active_seq_pattern[seq_no] then -- set new q
              q[seq_no] = new_pattern
            end
          end
  
          if pattern_key_count == 0 then -- reset interaction and change grid view if appropriate
            grid_interaction = nil
            if (not simultaneous) and new_pattern then
              set_grid_view("Seq", seq_no)
            end
          end

        end

      end

    elseif grid_view_name == "Arranger" then -- ARRANGER KEY UP
      
      -- ARRANGER EVENTS TIMELINE KEY UP
      if y == 5 then
        arranger_loop_key_count = math.max(arranger_loop_key_count - 1, 0)


        if arranger_loop_key_count == 0 then
          if grid_interaction == "arranger_shift" then -- Insert/remove patterns/events after arranger shift with E3
            apply_arranger_shift()
            update_chord_pattern_q()
            grid_interaction = nil
          elseif grid_interaction == "event_copy" then
            grid_interaction = nil
          end
        end


      end
    end

    local e = end_screen_message
    if e and e[1] == "g" then
      if x == e[2] and y == e[3] then
        do_notification_timer_1()
      end
    end

  end
  grid_dirty = true
end


function apply_arranger_shift()
  if d_cuml > 0 then
    for i = 1, d_cuml do
      table.insert(arranger, event_edit_segment, 0)
      table.remove(arranger, max_arranger_length + 1)
      table.insert(events, event_edit_segment, nil)
      events[event_edit_segment] = {}
      for p = 1, max_chord_pattern_length do
        table.insert(events[event_edit_segment], {})
      end
      table.remove(events, max_arranger_length + 1)
    end
    gen_arranger_padded()
    d_cuml = 0

  elseif d_cuml < 0 then
    for i = 1, math.abs(d_cuml) do
      table.remove(arranger, math.max(event_edit_segment - i, 1))
      table.insert(arranger, 0)
      table.remove(events, math.max(event_edit_segment - i, 1))
      table.insert(events, {})
      events[max_arranger_length] = {}
      for p = 1, max_chord_pattern_length do
        table.insert(events[max_arranger_length], {})
      end
    end
    gen_arranger_padded()
    d_cuml = 0
  end
end


-- function called when K1 is released or K3 is used to enter scale editor
function bang_params()
  for k, v in pairs(preview_param_q_get) do
    params:set(k, v)
  end
  preview_param = nil
  preview_param_q_get = {}
  preview_param_q_string = {}
  norns_interaction = nil
  gen_menu() -- re-hide any menus we don't need
end


----------------------
-- NORNS KEY FUNCTIONS
----------------------
--#region key local sub functions
-- check if the currently-selected chord is the default triad for editing scale/degree
-- if so, wipe the custom chord entry so we know it's default
local function default_chord_check()
  if chord_menu_names[chord_menu_index] == theory.chord_triad_names[editing_chord_scale][editing_chord_x] then -- if standard chord, delete chord_custom entry
    theory.custom_chords[editing_chord_scale][editing_chord_pattern][editing_chord_x][editing_chord_y] = nil
  end
end

 --#endregion key local sub functions

function key(n, z)
  if z == 1 then
    -- keys[n] = 1

    key_count = (key_count or 0) + 1

    if n == 1 then -- Key 1 is used to preview param changes before applying them on release
      if screen_view_name == "Events" then
        -- if event_edit_active == false then -- maybe
        params:set("event_quick_actions", 1)
        norns_interaction = "event_actions"
        lvl = lvl_dimmed
        -- end
      elseif not grid_interaction and not norns_interaction then
        -- notification("HOLD TO DEFER EDITS")--, {"k", 1}) --always show with timer rather than with a hold for this one 
        norns_interaction = "k1"
        gen_menu() -- show hidden menus so they aren't affected by events and user can switch to specific MIDI channel
        if menu_index ~= 0 then
          preview_param = clone_param(menus[page_index][menu_index])
        end
        -- redraw() -- only place other than refresh because I hate the K1 delay and if this makes it even <1/60fps faster it's worth it
      end

    elseif n == 2 then -- KEY 2
      if screen_view_name == "mask_editor" then -- close and return to session
        screen_view_name = "Session"

      elseif screen_view_name == "chord_editor" then -- close and return to session
        update_chord(editing_chord_x, editing_chord_y)
        play_chord()

      elseif grid_interaction == "chord_key_held" then -- propagate chord
        local scale = params:get("scale")

        notification("CHORD PROPAGATED", {"k", 2}) -- todo maybe replace with momentary rather than timed pop-up
        pending_chord_disable = {} -- cancel any help chord disables to be safe


        local custom = theory.custom_chords[scale][editing_chord_pattern][editing_chord_x]

        if custom[editing_chord_y] then -- custom chord exists
          for pattern = 1, 4 do
            for y = 1, 16 do
              theory.custom_chords[scale][pattern][editing_chord_x][y] = deepcopy(custom[editing_chord_y])
            end
          end
        else
          for pattern = 1, 4 do
            for y = 1, 16 do
              theory.custom_chords[scale][pattern][editing_chord_x][y] = nil
            end
          end
        end

      elseif norns_interaction == "k1" then
        -- placeholder but prob don't want to stop in case they meant to press K3
      elseif view_key_count > 0 then -- Grid view key(s) held down
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
          -- gen_arranger_dash_data("chord_generator_lite") -- will run when called from event but not from keys
        elseif grid_view_name == "Seq" then       
          seq_generator("run")
        end
        grid_dirty = true
      
  
      elseif arranger_loop_key_count > 0 and grid_interaction ~= "arranger_shift" then -- jump arranger playhead
        set_arranger_q(event_edit_segment)
        grid_dirty = true
      
      elseif screen_view_name == "Events" then -- events
       
        if norns_interaction ~= "event_actions" then
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

            update_lanes(event_edit_lane)

            -- Back to event overview
            event_edit_active = false
            reset_grid_led_phase()
            -- fix_ghosting_events()
            
            -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
            if event_key_count == 0 then
              event_edit_step = 0
              event_edit_lane = 0
            end
            event_saved = true
                        
            
            -------------------------------------------
            -- K2 BACK TO ARRANGER VIEW
            -------------------------------------------
          else -- exit back to Arranger
            screen_view_name = "Session"
            event_key_count = 0
            gen_arranger_dash_data("K3 events saved") -- update events strip in dash after making changes in events editor        
            grid_dirty = true
          end
        end
        
        gen_arranger_dash_data("K2 events editor closed") -- update events strip in dash after making changes in events editor
        grid_dirty = true
    
        
      ----------------------------------------
      -- K2 Transport controls K2 - STOP/RESET --
      ----------------------------------------
        
      elseif grid_interaction ~= "arranger_shift" then -- actually seems fine to do transport controls this during arranger shift?

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
          elseif transport_state == "stopped" then -- second press of K2 while stopped
            -- don't want a full reset_arrangement as this changes the current chord pattern for arranger seg 1
            -- instead, manually reset arranger
            arranger_position = 0
            arranger_next = nil
            arranger_q = nil -- no need to set_arranger_q() here
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

    elseif n == 3 then -- KEY 3

      if screen_view_name == "mask_editor" then -- close and return to session
        screen_view_name = "Session"
      elseif screen_view_name == "chord_editor" then -- close and return to session
        default_chord_check()
        grid_interaction = nil
        screen_view_name = "Session"
        gen_chord_readout() -- in case we're editing 1st step while stopped
      elseif norns_interaction == "k1" then

        if params:get("sync_views") == 1 then
          params:set("sync_views", 2) -- on
          set_page() -- set Grid view to current page
        else
          params:set("sync_views", 1)
        end

        notification(params:get("sync_views") == 1 and "SYNC VIEWS OFF" or "SYNC VIEWS ON", {"k", 3})

      elseif grid_interaction == "chord_key_held" then
        local root = editing_chord_root

        -- todo generate when mode is selected so this can be used for dash
        -- generate table of in-mode intervals for grid_redraw
        editing_chord_mode_intervals = {}
        for i = 1, 7 do
          editing_chord_mode_intervals[util.wrap(scale_heptatonic[i] + 1 - root, 1, 12)] = true
        end

        screen_view_name = "chord_editor"
        pending_chord_disable = {} -- cancel any help chord disables to be safe

        lvl = lvl_normal
        update_dash_lvls()

    
      elseif view_key_count > 0 and grid_view_name == "Seq" then -- Grid view key held down

        -- open mask editor
        view_key_count = 0
        grid_view_keys = {}
        scale_menu_index = 0
        screen_view_name = "mask_editor"
        norns_interaction = nil
        grid_interaction = nil
        bang_params() -- apply any defered param edits. could also ignore but this feels okay
        set_scale_menu()

      elseif arranger_loop_key_count > 0 and grid_interaction ~= "arranger_shift" then -- Event Editor --
        pattern_grid_offset = 0
        arranger_loop_key_count = 0
        event_edit_step = 0
        event_edit_lane = 0
        event_edit_active = false
        reset_grid_led_phase()
        screen_view_name = "Events"
        grid_interaction = nil
        grid_dirty = true

        update_lanes() -- in case arranger shift has changed lane config
        -- fix_ghosting_events()


      elseif screen_view_name == "Events" then
        if norns_interaction == "event_actions" then -- previously K3 could be used to fire quick action while keeping window open. Now, nothing.
        --   local action = params:string("event_quick_actions")

        --   if action == "Clear segment events" then
        --     delete_events_in_segment("event_actions") -- pass arg to keep window open
        --   end

          ---------------------------------------
          -- K3 TO SAVE EVENT
          ---------------------------------------
        elseif event_edit_active then
          local event_index = params:get("event_name")
          local lookup = events_lookup[event_index] -- not saved
          local id = lookup.id
          local order = tonumber(lookup.order) or 2 -- (order 1 fires before chord (no swing), order 2 fires after chord (with swing))
          local event_type = lookup.event_type -- function or param
          local t = event_type == "param" and params:t(id) or nil -- param "t" value, e.g. 3 == controlspec
          local value = params:get("event_value")
          local value_type = lookup.value_type -- continuous, trigger
          local operation = params:string("event_operation") -- Set, Increment, Wander, Random, Trigger
          local action = lookup.action
          local limit = params:string(operation == "Random" and "event_op_limit_random" or "event_op_limit")
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
                id = id,
                order = order,
                event_type = event_type,
                t = t,
                value_type = value_type,
                operation = operation,  -- sorta redundant but we do use it to simplify reads
                probability = probability
              }
              
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")
            print(">> id = " .. id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> t = " .. (t or ""))
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> probability = " .. probability)
            
          elseif operation == "Set" then
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = id, 
                order = order,
                event_type = event_type,
                t = t,
                value_type = value_type,
                operation = operation,
                value = value, 
                probability = probability
              }
              
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")     
            print(">> id = " .. id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> t = " .. (t or ""))
            print(">> value_type = " .. value_type)
            print(">> operation = " .. operation)
            print(">> value = " .. value)
            print(">> probability = " .. probability)
              
          elseif operation == "Random" then
            if limit == "Off" then -- so clunky yikes
              events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = id, 
                order = order,
                event_type = event_type,
                t = t,
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage              
                probability = probability
              }
              else
              events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = id, 
                order = order,
                event_type = event_type,
                t = t,
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage
                  limit_min = limit_min,  -- adding
                  limit_max = limit_max,  -- adding
                probability = probability
              }
            end
            
            print("Saving to events[" .. event_edit_segment .."][" .. event_edit_step .."][" .. event_edit_lane .. "]")       
            print(">> id = " .. id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> t = " .. (t or ""))
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
                id = id, 
                order = order,
                event_type = event_type,
                t = t,
                value_type = value_type,
                operation = operation,
                limit = limit,
                value = value, 
                probability = probability
              }
            else
            events[event_edit_segment][event_edit_step][event_edit_lane] =
              {
                id = id, 
                order = order,
                event_type = event_type,
                t = t,
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
            print(">> id = " .. id)
            print(">> order = " .. order)
            print(">> event_type = " .. event_type)
            print(">> t = " .. (t or ""))
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
            print(">> action = " .. action)
          end

          event_lanes[event_edit_lane].id = id -- always set last-saved event id as lane type
          update_lanes(event_edit_lane) -- todo save last values for all ops and min/max!

          -- Back to event overview
          event_edit_active = false
          reset_grid_led_phase()
          -- fix_ghosting_events()
          
          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true
          
          grid_dirty = true
        
        else -- exit back to Arranger
          screen_view_name = "Session"
          event_key_count = 0
          gen_arranger_dash_data("K3 events saved") -- update events strip in dash after making changes in events editor        
          grid_dirty = true  
        end
        
        ----------------------------------
        -- Transport controls K3 - PLAY --
        ----------------------------------
        -- Todo p1 need to have a way of canceling a pending pause once transport controls are reworked
      elseif grid_interaction == nil then
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
            -- if arranger_state == "on" then
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
          
        else -- crow/midi clock source
          -- todo look at crow although I think you're better off just using Internal
          notification("N/A (" .. string.upper(params:string("clock_source")) .. " CLOCK)", {"k", 3})

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
    if n == 1 then
      if norns_interaction == "k1" then
        bang_params() -- defered param changes
      elseif norns_interaction == "event_actions" then

        -- make function if this ends up being used by K1 release as well as K3 down
        local action = params:string("event_quick_actions")
        if action == "Clear segment events" then
          delete_events_in_segment() -- no arg so window will close after
        else -- if "Quick actions:" faux title, close window
          norns_interaction = nil
          lvl = lvl_normal
        end

      end

    -- elseif n == 3 then

    end

    local e = end_screen_message
    if e and e[1] == "k" then
      if n == e[2] then
        do_notification_timer_1()
      end_screen_message = {}
      end
    end

  end
end


-----------------------------------
-- ENCODERS
-----------------------------------

--#region local enc subfunctions

-- select custom chord from menu, set value
local function delta_chord(d)
  local x = editing_chord_x
  local y = editing_chord_y
  local root = editing_chord_root
  local custom = theory.custom_chords[editing_chord_scale][editing_chord_pattern][x]

  chord_menu_index = util.clamp((chord_menu_index or 0) + d, 1, #chord_menu_names)
  local name = chord_menu_names[chord_menu_index]
  local dash_name_1 = nil
  local dash_name_2 = nil

  -- generate intervals for the selected menu and populate dash_name_ fields:
  -- todo probably make this a theory function (replacement for generate_chord)
  local intervals = {}
  local chords = theory.chords

  -- find selected chord in theory.chords
  for c = 1, #chords do
    if name == chords[c].short_name then
      dash_name_1 = (chords[c].dash_name_1 or nil) -- don't include editing_chord_letter as key change may occur
      dash_name_2 = chords[c].dash_name_2 or nil
      
      local c_int = chords[c].intervals
      for i = 1, #c_int do
        intervals[i] = c_int[i] + root
      end
      break
    end
  end

  -- write intervals to chords_custom so they are available to sequencer
  custom[y] = {intervals = {}}
  for i = 1, #intervals do
    custom[y]["intervals"][i] = intervals[i]
  end

  gen_chord_bools(intervals) -- update for grid leds
  custom[y].name = name -- todo this should be more like "chord_type" as it's just used to match against menu selection
  custom[y].dash_name_1 = dash_name_1
  custom[y].dash_name_2 = dash_name_2

  preload_chord()
end
--#endregion local enc subfunctions


function enc(n,d)
  -- Scrolling/extending Arranger, Chord, Seq patterns
  if n == 1 then
    if grid_interaction == "view_switcher" then -- whole pattern rotate
      if (grid_view_name == "Chord" or grid_view_name == "Seq") then-- Chord/Seq 
        local d = util.clamp(d, -1, 1) -- no acceleration
        rotate_pattern(grid_view_name, d)
        grid_dirty = true
      end
    
      ------- SCROLL ARRANGER/PATTERN GRID VIEWS--------
    elseif grid_view_name == "Chord" then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_chord_pattern_length -  rows)
      pending_chord_disable = {} -- forget about any pending chord disables (lotta options here but this is simple and works)
    elseif screen_view_name == "Events" then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_chord_pattern_length -  rows)
    elseif grid_view_name == "Seq" then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_seq_pattern_length -  rows)
    elseif grid_view_name == "Arranger" then
      arranger_grid_offset = util.clamp(arranger_grid_offset + d, 0, max_arranger_length -  16)
    end
    grid_dirty = true

  elseif n == 2 then -- ENC 2
    if grid_interaction == "view_switcher" then
      if (grid_view_name == "Chord" or grid_view_name == "Seq") then-- Chord/Seq 
        local d = util.clamp(d, -1, 1) -- no acceleration
        rotate_pattern(grid_view_name, d, true)
        grid_dirty = true
      end
   
    elseif screen_view_name == "mask_editor" then
      scale_menu_index = util.clamp(scale_menu_index + d, 0, 1)

    elseif screen_view_name == "Events" then
      if norns_interaction == "event_actions" then
        params:delta("event_quick_actions", d) -- change focus on event_quick_actions
      elseif event_edit_active == false then -- lane view
        params:delta("event_lane", d) -- for now, change lane. Redundant with E3
        grid_dirty = true
      elseif event_saved == false then -- Scroll through the Events menus
        events_index = util.clamp(events_index + d, 1, #events_menus)      
        selected_events_menu = events_menus[events_index]
      end

    elseif not grid_interaction then -- standard menus
      menu_index = util.clamp(menu_index + d, 0, #menus[page_index])
      selected_menu = menus[page_index][menu_index]
      if norns_interaction == "k1" and menu_index ~= 0 then
        preview_param = clone_param(menus[page_index][menu_index])
      end
    end
    
  else -- n == ENC 3
    -- Grid-view custom encoder actions
    if grid_interaction == "view_switcher" then
      if (grid_view_name == "Chord" or grid_view_name == "Seq") then-- Chord/Seq
        local d = util.clamp(d, -1, 1)
        transpose_pattern(grid_view_name, d)
        grid_dirty = true
      end
      
    elseif screen_view_name == "chord_editor" then -- full chord editor screen
      delta_chord(d)
      gen_chord_name()
    elseif grid_interaction == "chord_key_held" then -- quick chord editor
      delta_chord(d)
      default_chord_check()
      pending_chord_disable = {} -- cancel any held chord disables to be safe
      gen_chord_name()
    elseif screen_view_name == "mask_editor" then  -- scale editor
      local mode = params:get("scale")

      if scale_menu_index == 0 then
        editing_scale = util.clamp((editing_scale or 1) + d, 1, 8)
        set_scale_menu()
      else
        local lookup = theory.lookup_scales

        -- either show loaded/matching scale or "Custom" if altered
        scale_index = util.clamp((scale_index or 0) + d, 1, #lookup)
        
        -- set theory.masks to selected menu
        theory.masks[mode][editing_scale] = {}

        for i = 1, #lookup[scale_index].intervals do
          theory.masks[mode][editing_scale][i] = lookup[scale_index]["intervals"][i]
        end

        -- set bool table
        theory.masks_bool[editing_scale] = {}
        for x = 1, 12 do
          theory.masks_bool[editing_scale][x] = false
        end
  
        for i = 1, #lookup[scale_index].intervals do
          theory.masks_bool[editing_scale][lookup[scale_index]["intervals"][i] + 1] = true
        end

        build_scale()

        grid_dirty = true
      end


    ----------------------    
    -- Event editor menus
    ----------------------    
    -- Not using param actions on these since some use dynamic .options which don't reliably fire on changes. Also we want to fire edit_status_edited() on encoder changes but not when params are set elsewhere (loading events etc)
    elseif screen_view_name == "Events" then
      if norns_interaction == "event_actions" then
        params:delta("event_quick_actions", d) -- change focus on event_quick_actions
            
      elseif event_edit_active == false then -- event lane view
        params:delta("event_lane", d)
        grid_dirty = true

      elseif event_saved == false then -- event edit menus
        if selected_events_menu == "event_category" then
          if delta_menu(d) then
            change_category()
            update_lane_glyph()
          end

        elseif selected_events_menu == "event_subcategory" then
          if delta_menu(d) then
            change_subcategory()
            update_lane_glyph()
          end
          
        elseif selected_events_menu == "event_name" then
          if delta_menu(d, event_subcategory_index_min, event_subcategory_index_max) then
            change_event()
            update_lane_glyph()
          end

        elseif selected_events_menu == "event_operation" then
          if delta_menu(d) then
            change_operation()
          end
          
        elseif selected_events_menu == "event_value" then
          if params:string("event_operation") == "Set" then
            delta_menu_set(d) -- Dynamic event_range lookup. no manual action to call
          elseif params:string("event_operation") == "Wander" then
            delta_menu(d, 1)
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

      end
      
    elseif grid_interaction == "event_copy" or grid_interaction == "arranger_shift" then -- arranger shift
      local d = util.clamp(d, -1, 1)
      grid_interaction = "arranger_shift"
      d_cuml = util.clamp(d_cuml + d, -64, 64)
      
      grid_dirty = true
  
    elseif (not grid_interaction) and screen_view_name == "Session" then -- 
      if menu_index == 0 then
        menu_index = 0
        page_index = util.clamp(page_index + d, 1, #pages)
        set_page()

      elseif norns_interaction == "k1" then
        preview_param:delta(d)
        preview_param_q_get[preview_param.id] = preview_param:get()
        preview_param_q_string[preview_param.id] = preview_param:string()
      else
        params:delta(selected_menu, d)
      end
    end
  
  end -- n
end


-- utility functions for enc deltas:

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


-- alt of delta_menu used when previewing selected_events_menu == "event_value" and we're using "set" op
function delta_menu_set(d)--, minimum, maximum) -- don't think we need min/max any more, actually
  local event = preview_event
  local prev_value = params:get(selected_events_menu)
  local t = event.t

  if t == 9 and event.behavior == "toggle" then -- toggle will effectively wrap so we have to delta manually
    event.value = util.clamp(event.value + d, 0, 1)
  else
    event:delta(d)
  end

  local new_value = event.t == 3 and event.raw or event:get() -- controlspec or standard param

  if new_value ~= prev_value then
    params:set(selected_events_menu, new_value)
    edit_status_edited()
  end

end


-- variant of delta_menu used to delta event_op_limit_min/max event params
function delta_menu_range(d, minimum, maximum)
  local event = preview_event
  local t = event.t
  local wrap = event.wrap
  local prev_value = params:get(selected_events_menu)
  local new_value

  if wrap then event.wrap = false end -- temporarily disable parameter wrapping which messes with min/max logic

  -- for controlspec, we must delta raw rather than mapped values (precision issue that causes trouble)
  if t == 3 then -- controlspec type param
    if selected_events_menu == "event_op_limit_min" then -- either min or max
      minimum = 0 -- max will be based on the raw value from event_op_limit_max
    else
      maximum = 1 -- min will be based on the raw value from event_op_limit_min
    end

    event:set_raw(prev_value) -- for controlspec we use `set_raw`
    event:delta(d)
    new_value = util.clamp(event.raw, minimum, maximum) -- get delta'd raw and prevent min/max range overlap

  elseif t == 9 and event.behavior == "toggle" then -- toggle will effectively wrap so we have to delta manually
    new_value = util.clamp(event.value + d, 0, 1)
  else
    event:set(prev_value) -- for other params, use `set`
    event:delta(d)
    new_value = util.clamp(event:get(), minimum, maximum) -- get value and prevent min/max range overlap
  end

  if new_value ~= prev_value then
    params:set(selected_events_menu, new_value)
    edit_status_edited() -- flag that event has been edited for UI (clamped edits won't trigger this)
  end

  if wrap then event.wrap = true end -- re-enable wrap
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
  local lookup = events_lookup[event]

  if debug_change_functions then print("3. change_event called") end
  if debug_change_functions then print("   new event: " .. events_lookup[event].name) end
  if event ~= prev_event then
    derive_value_type() -- todo this is being called on-the-fly but we can also just iterate through everything in events_lookup
    update_event_operation_options("change_event")
    
    -- Currently only changing on new event. Changing operation keeps the limit type
    params:set("event_op_limit", 1)
    params:set("event_op_limit_random", 1)

    set_event_range()

    -- set default min/max param ranges (todo look at maybe moving inside set_event_range())
    if lookup.event_type == "param" then
      local p = params:lookup_param(lookup.id)

      if p.t == 3 then -- is controlspec
        -- switch to using `value` to store `raw` so we need to convert the default value
        local spec = p.controlspec
        params:set("event_op_limit_min", spec.warp.unmap(spec, event_range[1]))
        params:set("event_op_limit_max", spec.warp.unmap(spec, event_range[2]))
      else
        params:set("event_op_limit_min", event_range[1])
        params:set("event_op_limit_max", event_range[2])
      end
    -- todo housekeeping
    -- else -- pretty sure sure we don't even need to update ranges for non-param events
    --   params:set("event_op_limit_min", event_range[1])
    --   params:set("event_op_limit_max", event_range[2])
    end

    params:set("event_operation", 1) -- no action so call on next line
    change_operation("change_event")  -- pass arg so we can tell change_operation to set values even if op hasn't changed
    params:set("event_probability", 100) -- Only reset probability when event changes
    if lookup.event_type == "param" then
      preview_event = clone_param(lookup.id)
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
    local lookup = events_lookup[params:get("event_name")]

    -- alternative placement if we want to reset change event_op_limit and event_op_limit_random on both event and op change

    if debug_change_functions then print("    setting default values") end

    local event_type = lookup.event_type

		-- set default_value for this operation
		if debug_change_functions then print("    event_type = " .. event_type) end
    if event_type == "param" then
      if debug_change_functions then print("4.1 param value") end
      if operation == "Set" then
        local p = params:lookup_param(lookup.id)
        local value = p.t == 3 and p.raw or p:get() -- controlspec (raw) or standard value
        
        if debug_change_functions then print("5. Set: setting default value to " .. value) end
        params:set("event_value", value)

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
  local lookup = events_lookup[event_index]
  -- Determine if event range should be clamped
  if lookup.event_type == "param" then
    if lookup.value_type ~= "trigger" then
      event_range = params:get_range(lookup.id) or {-math.huge, math.huge}
    end
  else -- function. May have hardcoded ranges in events_lookup at some point
    event_range = {-math.huge, math.huge} -- is it even necessary to set ranges for these?
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


-- derives event_type for event (either `trigger` or `continuous`) and sets in events_lookup
-- with no arg, operates on selected event
-- pass events_lookup index to operate on a specific event
function derive_value_type(index)
  local lookup_idx = index or params:get("event_name")
  local lookup = events_lookup[lookup_idx]
  local event_type = lookup.event_type -- param or function
  local value_type -- derived this time

  -- todo p2 might want to set up momentary where the value determines how long between on and off (too quick for some stuff)
  if event_type == "param" then
    local t = params:t(lookup.id)

    if t == 6 or (t == 9 and params:lookup_param(lookup.id).behavior ~= "toggle") then -- trigger and momentary or trigger styles of binary
      value_type = "trigger"
    else
      value_type = "continuous" -- toggle binaries are reclassified so their state can be set directly
    end

  else -- function
    value_type = "trigger" -- all functions are triggers for now
  end

  lookup.value_type = value_type -- bit of a WAG but try setting this as it's used a few places
end

-- configures available event ops for the selected event 
function update_event_operation_options(source)
  if debug_change_functions then print("   updating operations on " .. (params:string("event_name") or "nil")) end
  swap_param_options("event_operation", _G["event_operation_options_" .. events_lookup[params:get("event_name")].value_type])
end

-- used to set default value of event after init and pset load
-- for controlspec, will unmap and provide "default raw" value which can be used for preview_event
function get_default_event_value()
  local lookup = events_lookup[params:get("event_name")]

  if lookup.event_type == "param" then
    local p = params:lookup_param(lookup.id)
    if p.t == 3 then -- controlspec
      spec = p.controlspec
      local raw_default = spec.warp.unmap(spec, spec.default)
      return(raw_default)
    else
      return(p.default)
    end
  else
    return(0)
  end

end
  
  
function chord_steps_to_seconds(steps)
  return(steps * 60 / params:get("clock_tempo") / global_clock_div * chord_div) -- switched to var Fix: timing
end


-- Alternative for more digits up to 9 hours LETSGOOOOOOO
function s_to_min_sec(seconds)

  -- hours = (string.format("%02.f", math.floor(seconds/3600));
  hours_raw = math.floor(seconds/3600);
  hours = string.format("%1.f", hours_raw);
  mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)));
  secs = string.format("%02.f", math.floor(seconds - hours*3600 - mins *60));
  -- Modify hours if it's 2+ digits
  -- hours = hours < 10 and string.format("%2.f",hours) or ">";
  if hours_raw < 1 then
    return mins .. ":" .. secs
  elseif hours_raw < 10 then
    return hours .. "h:" .. mins -- .. "m" -- truncated a bit to fit dash
  else
    return hours .. "h+"
  end

end


-- generates truncated flat tables at the chord step level for the arranger mini dashboard
-- runs any time the arranger changes (generator, events, pattern changes, length changes, key pset load, arranger/pattern reset, event edits)
-- holy shit this needs a refactor. really awful
function gen_arranger_dash_data(source)
  local on = params:string("arranger") == "On"
  local dash_steps = 0
  local stop = 29 -- width of chart
  local steps_remaining_in_pattern = nil

  -- print("gen_arranger_dash_data called by " .. (source or "?"))
  dash_patterns = {}
  -- dash_levels correspond to 3 arranger states:
  -- 1. Arranger was disabled then re-enabled mid-segment so current segment should be dimmed
  -- 2. Arranger is enabled so upcoming segments should be bright
  -- 3. Arranger is disabled completely and should be dimmed  
  dash_levels = {}
  dash_events = {}
  steps_remaining_in_active_pattern = 0 -- used to calculate timer as well. todo look at updating in advance_chord_pattern
  steps_remaining_in_arrangement = 0 -- same

  ---------------------------------------------------------------------------------------------------
  -- iterate through all steps in arranger so we can get a total for steps_remaining_in_arrangement
  -- then build the arranger dash charts, limited to area drawn on screen (~30px)
  ---------------------------------------------------------------------------------------------------
  for i = math.max(arranger_position, 1), arranger_length do    
  -- _sticky vars handle instances when the active arranger segment is interrupted, in which case we want to freeze its vars to stop the segment from updating on the dash (while still allowing upcoming segments to update)
  -- Scenarios to test for:
    -- 1. User changes the current arranger segment pattern while on that segment. In this case we want to keep displaying the currently *playing* chord pattern
    -- 2. User changes the current chord patarranger_positiontern by double tapping it on the Chord grid view. This sets arranger_state to false and should suspend the arranger mini chart until Arranger pickup occurs.
    -- 3. Current arranger segment is turned off, resulting in it picking up a different pattern (either the previous pattern or wrapping around to grab the last pattern. arranger_padded shenanigans)
    -- 4. We DO want this to update if the arranger is reset (arranger_position = 0, however)
    
    local segment_level = on and "menu_selected" or "chart_deselected" --and 15 or 2 WAG moving this up here

    -- Note: arranger_position == i idenifies if we're on the active segment. Implicitly false when arranger is reset (arranger_position 0) todo p2 make local
    if arranger_position == i then
      -- todo p2 would be nice to rewrite this so these can be local
      if arranger_state == "on" then
        active_pattern = active_chord_pattern
        active_chord_pattern_length = chord_pattern_length[active_pattern]
        active_chord_pattern_position = math.max(chord_pattern_position, 1)
        segment_level = "menu_selected" -- 15
      else
        segment_level = "chart_deselected" -- interrupted segment
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
      -- segment_level = params:string("arranger") == "On" and 0 or 3 --and 15 or 2
    end
    
    -- used to total remaining time in arrangement (beyond what is drawn in the dash)  
    steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
    
    -- todo p3 some sort of weird race condition is happening at init that requires nil check on events
    if events ~= nil and dash_steps < stop then -- capped so we only store what is needed for the dash (including inserted blanks)
      
      for s = chord_pattern_position_sticky, chord_pattern_length_sticky do -- todo debug this was letting 0 values through at some point. Debug if errors surface.  
        if dash_steps == stop then
          break 
        end -- second length check for each step iteration cuts down on what is saved for long segments

        table.insert(dash_patterns, pattern_sticky)
        table.insert(dash_levels, segment_level)
        table.insert(dash_events, ((events[i][s].populated or 0) > 0) and segment_level or "chart_deselected")
        dash_steps = dash_steps + 1
      end

      -- insert blanks between segments
      if dash_steps < stop then
        table.insert(dash_patterns, 0)
        table.insert(dash_events, "pane_selected")
        table.insert(dash_levels, "pane_selected")
        dash_steps = dash_steps + 1 -- and 1 to grow on!
      end

    end
  end
  calc_seconds_remaining() -- firing before lattice is running which causes error
end



-- pop-up tooltips when certain grid keys are held down
local function tooltips(header, strings)
  local strings = strings or ""
  screen.level(lvl.menu_selected)
  screen.move(xy.header_x, xy.header_y)
  screen.text(header)
  screen.level(lvl.menu_deselected)
  for i = 1, #strings do
    screen.move(0, xy.menu_y + (i * 10))
    screen.text(strings[i] or "")
  end
end


-- rectangles and K2/K3 text
-- optional bool to override dynamic dimming
local function footer(k2, k3, no_dim) -- todo move out of redraw loop and pass lvl_pane_dark
  local lvl_pane = no_dim and lvl_normal.pane_dark or lvl.pane_dark
  local lvl_txt = no_dim and 0 or lvl.pane_selected
  if k2 then
    screen.level(lvl_pane)
    -- screen.rect(0, 55, 63, 9) -- 2px border
    screen.rect(0, 53, 63, 11) -- 3px border
    screen.fill()
    screen.level(lvl_txt)
    screen.move(31, 61) -- 3px border
    screen.text_center("K2 ".. k2)
  end
  if k3 then
    screen.level(lvl_pane)
    screen.rect(65, 53, 63, 11) -- 3px border
    screen.fill()
    screen.level(lvl_txt)
    screen.move(96, 61) -- 3px border
    screen.text_center("K3 " .. k3)
  end
end


--------------------------
-- REDRAW
-------------------------
-- todo p1: this can be improved quite a bit by just having these custom screens be generated at the key/g.key level. Should be a fun refactor.
function redraw()
  -- screen.font_face(tab.key(screen.font_face_names, "norns"))

  local dash_x = xy.dash_x   -- x origin of chord and arranger dashes
  local header_x = xy.header_x
  local header_y = xy.header_y
  local menu_y = xy.menu_y
  local scrollbar_y = xy.scrollbar_y
  local lvl_menu_selected = lvl.menu_selected
  local lvl_menu_deselected = lvl.menu_deselected

  local grid_interaction = grid_interaction
  local screen_view_name = screen_view_name

  screen.clear()

  -- POP-up g.key tooltips always takes priority
  if grid_interaction == "view_switcher" then
    -- technically screen_view_name can be used to show generator operates on chord+seq, but footer redesign is too small
    -- if screen_view_name == "Chord+seq" then -- technically this can be used to show generator operates on chord+seq
    --   local line3 = grid_view_name == "Chord" and "Tap pattern A-D: mute" or "Tap SEQ 1-" .. max_seqs .. ": mute"
    --   tooltips(string.upper(grid_view_name) .. " GRID FUNCTIONS", {"E2: rotate ↑↓", "E3: transpose ←→", line3})
    --   footer("GENERATE") -- technically this should indicate generating patterns for chord+seq
    if grid_view_name == "Arranger" then
      tooltips("SONG ARRANGER GRID")
    elseif grid_view_name == "Chord" then
      tooltips("CHORD GRID", {"E1: pattern ↑↓ ", "E2: loop ↑↓", "E3: transpose ←→", "Tap pattern A-D: mute"})
      footer("GENERATE")
    elseif grid_view_name == "Seq" then
      tooltips("SEQ " .. selected_seq_no .. " GRID", {"E1: pattern ↑↓ ", "E2: loop ↑↓", "E3: transpose ←→", "Tap SEQ 1-" .. max_seqs .. ": mute"})
      footer("GENERATE", "EDIT MASK")
    end

  elseif grid_interaction == "arranger_shift" then
    tooltips("ARRANGER SEGMENT " .. event_edit_segment, {"E3: shift segments ←→"})

  elseif grid_interaction == "event_copy" then
    tooltips("ARRANGER SEGMENT " .. event_edit_segment, {"E3: shift segments ←→", "Hold+tap: paste events"})
    footer("JUMP", "EVENTS")
  
  elseif grid_interaction == "pattern_switcher" then
    if grid_view_name == "Chord" then -- if page_name == "CHORD" then
      tooltips("CHORD PATTERN " .. pattern_name[copied_pattern], {"Hold+tap: paste pattern", "Release: cue pattern", "Tap 2x while stopped: jump"})
    else
      if simultaneous then
        tooltips("MULTIPLE SEQS", {"Release: choose patterns"})
      else
        tooltips("SEQ " .. copied_seq_no .. ", PATTERN " .. pattern_name[copied_pattern], {"Hold+tap: paste pattern", "Release: choose pattern"})
      end
    end


  else -- Standard priority (not momentary) menus
    -- NOTE: UI elements placed here appear in all views


    if screen_view_name == "Events" then -- EVENTS SCREENS
      local lane = params:get("event_lane")
      local lane_id = event_lanes[lane].id
      local lane_type = event_lanes[lane].type -- or "Empty"
      local lane_glyph = lane_type == "Single" and "☑" or lane_type == "Multi" and "☰" or "☐" -- ☑  -- todo norns.ttf

      if event_edit_active == false then -- lane-level preview
        --------------------------
        -- Event lanes preview
        --------------------------
        local event_def = events_lookup[events_lookup_index[lane_id]]

        -- LANE EDITOR HEADER/GLYPHS
        screen.level(lvl_menu_selected)
        screen.move(header_x, header_y)
        screen.text("LANE " .. lane)

        for i = 1, 15 do
          local type = event_lanes[i].type
          local glyph = type == "Single" and "☑" or type == "Multi" and "☰" or "☐" --☑ -- todo norns.ttf

          screen.level(lane == i and lvl_menu_selected or lvl_menu_deselected)
          screen.move((header_x + 35 + (i - 1) * 6), header_y)
          screen.text(glyph)
        end

        -- simplified description of lane. multi-event lanes show last-saved event
        if event_def then
          screen.move(0, menu_y + 10)
          screen.text("Category: " .. first_to_upper(event_def["category"]))
          screen.move(0, menu_y + 20)
          screen.text("Subcategory: " .. first_to_upper(event_def["subcategory"]))
          screen.move(0, menu_y + 30)
          screen.text("Event: " .. first_to_upper(event_def["name"]))
        else
          screen.move(0, menu_y + 10)
          screen.level(lvl_menu_deselected)
          screen.text("No events in lane")
        end

        footer(nil, "EXIT") -- K2 also goes back to arranger 🤫

      else -- EVENT EDITOR MENUS
        -- todo p2 move some of this to a function that can be called when changing event or entering menu first time (like get_range)
        -- todo p2 this mixes events_index and menu_index. Redundant?

        -- local event_def = events_lookup[params:get("event_name")]  -- todo global + change_event()
        local event_type = events_lookup[params:get("event_name")].event_type
        local is_controlspec = (preview_event.t == 3) -- todo make sure this isn't trouble for functions!
        local menu_offset = scroll_offset_locked(events_index, 10, 2) -- index, height, locked_row
        local line = 1

        -- EVENT EDITOR HEADER
        -- lane_glyph (with dynamic preview)
        if lane_glyph_preview == "Single" then
          screen.level(lvl_menu_deselected)
          lane_glyph = "⏹"--"☑" -- probably no need to blink if we're going down to Single event lane
        elseif lane_glyph_preview == "Multi" then
          screen.level(blinky == 0 and lvl_menu_deselected or lvl_menu_selected)
          lane_glyph = "☰"
        else
          screen.level(lvl_menu_deselected)
        end

        screen.move(header_x, header_y)
        screen.text(lane_glyph)
        screen.move(header_x + 6, header_y)
        screen.level(lvl_menu_deselected)
        screen.text(" LANE " .. event_edit_lane .. ", STEP " .. event_edit_step) -- add event_edit_segment?

        -- event save status
        screen.move(128 - 4, header_y)
        screen.text_right(event_edit_status)
        footer("DELETE", event_edit_status == "(Saved)" and "DONE" or "SAVE") -- todo revisit delete/cancel logic

        for i = 1, #events_menus do -- event hierarchy, op, probability, etc...
          -- local debug = false
          local menu_id = events_menus[i]
          local menu_index = params:get(menu_id)
          local event_val_string = params:string(menu_id)
          local y = line * 10 + menu_y - menu_offset

          if y > 11 and y < 52 then
          screen.move(0, y) --line * 10 + 9 - menu_offset)
          screen.level(events_index == i and lvl_menu_selected or lvl_menu_deselected)

          -- use event_value to format values
          -- values are already set on var event_val_string so if no conditions are met they pass through raw
          -- >> "Set" operation should do .options lookup where possible
          -- >> functions are raw
          -- >> inc, random, wander are raw but ranges have been formatted above
          if menu_id == "event_value" then
            -- if debug then print("-------------------") end
            -- if debug then print("formatting event_value menu") end
            local operation = params:string("event_operation")
            
            if operation == "Set" then
              -- if debug then print("Set operator") end
              -- if event_def.event_type == "param" then  -- move above operation check?
              if event_type == "param" then  -- move above operation check?
                -- same chunk of code shared by event_op_limit_min/max, below
                if is_controlspec then
                  preview_event:set_raw(event_val_string) -- SET using raw value which has greater precision than set/value
                else
                  preview_event:set(event_val_string) -- event_val_string is actually param index at this point
                end
                event_val_string = preview_event:string() -- convert from index to actual string

              end
              -- if debug then print("Nil formatter: skipping") end
            elseif operation == "Wander" then
              event_val_string = "\u{0b1}" .. event_val_string
            end
            -- if debug then print("Value passed raw") end
      
          elseif menu_id == "event_op_limit_min" or menu_id == "event_op_limit_max" then
            if is_controlspec then
              preview_event:set_raw(event_val_string) -- SET using raw value which has greater precision than set/value
            else
              preview_event:set(event_val_string) -- event_val_string is actually param index at this point
            end
            event_val_string = preview_event:string() -- convert from index to actual string

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
                or event_range
                
              local single = menu_index == range[1] and (range[1] == range[2]) or false
              local menu_value_pre = single and "\u{25ba}" or menu_index == range[2] and "\u{25c0}" or " "
              local menu_value_suf = single and "\u{25c0}" or menu_index == range[1] and "\u{25ba}" or ""
              
              -- local events_menu_txt = first_to_upper(param_id_to_name(menu_id)) .. ":" .. menu_value_pre .. first_to_upper(string.sub(event_val_string, 1, events_menu_trunc)) .. menu_value_suf

              -- if debug and menu_id == "event_value" then print("menu_id = " .. (menu_id or "nil")) end
              -- if debug and menu_id == "event_value" then print("event_val_string = " .. (event_val_string or "nil")) end

              -- screen.text(events_menu_txt)

              screen.text(first_to_upper(param_id_to_name(menu_id)) .. ":" .. menu_value_pre .. first_to_upper(string.sub(event_val_string, 1, events_menu_trunc)) .. menu_value_suf)

            else            
              -- if debug and menu_id == "event_value" then print("menu_id = " .. (menu_id or "nil")) end
              -- if debug and menu_id == "event_value" then print("event_val_string = " .. (event_val_string or "nil")) end
              
              screen.text(first_to_upper(param_id_to_name(menu_id)) .. ": " .. first_to_upper(string.sub(event_val_string, 1, events_menu_trunc)))
            end

            -- simplified option (perhaps alternate view via prefs?)
            -- screen.text(string.lower(param_id_to_name(menu_id)))
            -- screen.move(124, y)
            -- screen.text_right((string.lower(string.sub(event_val_string, 1, events_menu_trunc))))

          end
          line = line + 1
        end
        
        -- events editor scrollbar
        screen.level(lvl_menu_selected)
        local offset = scrollbar_y + scrollbar(events_index, #events_menus, 4, 2, 38) -- (index, total, in_view, locked_row, screen_height)
        local bar_height = 4 / #events_menus * 41
        screen.rect(127, offset, 1, bar_height)
        screen.fill()

        -- footer
        footer("DELETE", event_edit_status == "(Saved)" and "DONE" or "SAVE") -- todo revisit delete/cancel logic
      end


      -- K1 event actions pop-up quick-menu
      if norns_interaction == "event_actions_done" then -- flash "DONE!" message
        local border = 12 -- portion of lower layer still shown
        local rect = {1 + border, border, 127 - (border * 2), 63 - (border * 2)}

        screen.level(0)
        screen.rect(table.unpack(rect))
        screen.fill()
        screen.level(15)
        screen.rect(table.unpack(rect))
        screen.stroke()

        screen.level(15)
        screen.move(64, 34)
        screen.text_center("DONE!")

      elseif norns_interaction == "event_actions" then
        local border = 12 -- portion of lower layer still shown
        local rect = {1 + border, border, 127 - (border * 2), 63 - (border * 2)}
        
        screen.level(0)
        screen.rect(table.unpack(rect))
        screen.fill()
        screen.level(15)
        screen.rect(table.unpack(rect))
        screen.stroke()

        for row = 1, #event_quick_actions do
          screen.level(params:get("event_quick_actions") == row and 15 or 3)
          screen.move(border + 6, row * 10 + 14)  -- exaggerate border a bit
          screen.text(event_quick_actions[row])
        end
      end

    elseif screen_view_name == "mask_editor" then
      local editing_scale = editing_scale
      local paging = scale_menu_index == 0
      local scale_index = scale_index
      local scale_name = scale_index == 0 and "Custom" or theory.lookup_scales[scale_index].name
      local editing_scale_modified = false -- flag to set if scale was manually modified

      screen.move(header_x, header_y)
      screen.level(paging and lvl_menu_selected or lvl_menu_deselected)
      screen.text("CUSTOM SCALE MASK " .. editing_scale)

      screen.move(header_x, menu_y + 10)
      screen.level(paging and lvl_menu_deselected or lvl_menu_selected)
      screen.text("Scale: " .. (editing_scale_modified and "custom" or scale_name))

      footer(nil, "EXIT")

    elseif screen_view_name == "chord_editor" then    
      screen.move(header_x, header_y)
      screen.level(lvl_menu_deselected)
      screen.text("CHORD DEGREE " .. editing_chord_degree .. ", BASE: " .. editing_chord_triad_name)

      screen.move(header_x, menu_y + 10)
      screen.level(lvl_menu_selected)
      screen.text("Chord: " .. editing_chord_name)

      footer("PREVIEW", "EXIT")

    else -- SESSION VIEW (NON-EVENTS), not holding down Arranger segments g.keys  
      -- NOTE: UI elements placed here appear in all non-Events views


      --------------------
      -- MAIN MENUS, PAGES
      --------------------
      -- todo p1 move calcs out of redraw
      -- todo don't draw offscreen
      local paging = menu_index == 0
      local menu_offset = scroll_offset_locked(menu_index, 10, 2) -- index, height, locked_row
      local line = 1

      for i = 1, #menus[page_index] do
        local param_id = menus[page_index][i]
        local q = preview_param_q_get[param_id] and "-" or "" -- indicates if delta is waiting on param_q
        local param_get = preview_param_q_get[param_id] or params:get(param_id)
        local param_string = preview_param_q_string[param_id] or params:string(param_id)
        local y = line * 10 + menu_y - menu_offset
        
        if y > 12 and y < 64 then
          screen.move(0, y)
       
          if menu_index == i then  -- Generate menu and draw ▶◀ indicators for scroll range
            screen.level(lvl_menu_selected)
            if norns_interaction then q = "-" end
            local range = params:get_range(param_id)
            local menu_value_pre = param_get == range[2] and "\u{25c0}" or " "
            local menu_value_suf = param_get == range[1] and "\u{25ba}" or ""
            screen.text(q .. first_to_upper(param_id_to_name(param_id)) .. ":" .. menu_value_pre .. param_string .. menu_value_suf)
          else  
            screen.level(lvl_menu_deselected)
            screen.text(q .. first_to_upper(param_id_to_name(param_id)) .. ": " .. param_string)
          end

        end

        line = line + 1
      end


      -- main menu scrollbar
      if not paging then
        screen.level(lvl_menu_selected)
        local offset = scrollbar_y + scrollbar(menu_index, #menus[page_index], 5, 2, 52) -- (index, total, in_view, locked_row, screen_height)
        local bar_height = 5 / #menus[page_index] * 52
        screen.rect(dash_x - 2, offset, 1, bar_height)
        screen.fill()
      end
      

      -- A: center pagination and small menu

      -- MAIN MENU PAGINATION
      if paging then  -- if we want it to only appear when changing pages
        local width = (4 * #pages) - 1
        local x = math.ceil((dash_x - width) / 2) -- 35 calculated
        for i = 1, #pages do
          screen.level(i == page_index and lvl_menu_selected or lvl_menu_deselected)
          screen.rect(x + ((i - 1) * 4), 0, 3, 1) -- small top-centered pagination
          -- screen.rect(((i - 1) * 4), 0, 3, 1) -- small left-aligned pagination
          screen.fill()
        end
      end

      -- screen.move(header_x, header_y)
      -- screen.level(paging and lvl_menu_selected or lvl_menu_deselected)
      -- screen.text(page_name)
      

      -- B: small menu only, shifted up
      screen.move(header_x, header_y)
      screen.level(paging and lvl_menu_selected or lvl_menu_deselected)
      screen.text(page_name)

      -- -- C: Jumbotron
      -- screen.level(paging and lvl_menu_selected or lvl_menu_deselected)
      -- screen.move(0, 10)
      -- screen.font_size(16)
      -- screen.text(page_name)
      -- screen.font_size(8)

      -- screen.level(lvl_menu_deselected)
      -- screen.rect(0, 9, screen.text_extents(page_name), 1)
      -- screen.fill()

      -- -- WIP, optional glyph (todo norns.ttf required) to indicate when grid-norns syncing is enabled
      -- if params:string("sync_views") == "On" then
      --   screen.level(lvl_menu_deselected)

      --   -- screen.move(dash_x - 10, 7)
      --   -- screen.text("▦")

      --   local x = dash_x - 10
      --   screen.pixel(x, 2)
      --   screen.pixel(x, 4)
      --   screen.pixel(x, 6)
      --   local x = dash_x - 8
      --   screen.pixel(x, 2)
      --   screen.pixel(x, 4)
      --   screen.pixel(x, 6)
      --   local x = dash_x - 6
      --   screen.pixel(x, 2)
      --   screen.pixel(x, 4)
      --   screen.pixel(x, 6) 
      --   screen.fill()
      -- end

      -- iterate through list of modular dashboard functions
      dash_y = 0
      for _, func in pairs(dash_list) do
        func()
      end

      if grid_interaction == "chord_key_held" then       
        screen.level(0)
        screen.rect(0, 0, dash_x - 2, 52)
        screen.rect(0, 52, 128, 12) -- 1-px footer mask (3-border footer)
        screen.fill()

        screen.level(15)
        screen.rect(1, 1, dash_x - 2, 51)
        screen.stroke()

        screen.move(44, 28)
        screen.text_center(editing_chord_name)

        screen.level(lvl_menu_deselected)
        screen.move(dash_x - 4, 8)
        screen.text_right("E3")
        -- glyph, replace with norns.ttf
        -- for i = 1, #glyphs.loop do
        --   screen.pixel(dash_x - 9 + glyphs.loop[i][1], glyphs.loop[i][2] + 3)
        -- end
        screen.fill()

        footer("PROPAGATE", "EDIT CHORD", true) -- true overrides dimming to emphasize momentary keys
      end

    end -- of event vs. non-event check
  end


  if screen_message then
    -- footer-area notification display
    -- 1px border
    screen.level(0)
    screen.rect(0, 52, 128, 1)
    screen.fill()

    screen.level(15)
    screen.rect(0, 53, 128, 12)
    screen.fill()

    screen.level(0)
    screen.move(64, 61)
    screen.text_center(screen_message)
  end

  screen.update()
end