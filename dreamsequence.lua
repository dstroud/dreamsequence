-- Dreamsequence
-- v1.1.3b @modularbeat
-- llllllll.co/t/dreamsequence
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
-- Crow OUT 1: V/oct out
-- Crow OUT 2: Trigger/envelope out
-- Crow OUT 3: Clock out
-- Crow OUT 4: Events out


g = grid.connect()
rows = g.device.rows or 8
extra_rows = rows - 8
include("dreamsequence/lib/includes")

norns.version.required = 230526 -- update when new musicutil lib drops

function init()
  -----------------------------
  -- todo p0 prerelease ALSO MAKE SURE TO UPDATE ABOVE!
  version = 'v1.1.3'
  -----------------------------

  -- thanks @dndrks for this little bit of magic to check ^^crow^^ version!!
  norns.crow.events.version = function(...)
    crow_version = ...
  end
  crow.version() -- Uses redefined crow.version() function to set crow_version global var
  crow_version_clock = clock.run(
    function()
      clock.sleep(.05) -- a small hold for usb round-trip
      local major, minor, patch = string.match(crow_version or 'v9.9.9', "(%d+)%.(%d+)%.(%d+)")
      local crow_version_num = major + (minor /10) + (patch / 100)  -- this feels like it's gonna break lol
      if crow_version ~= nil then print('Crow version ' .. crow_version) end
      if crow_version_num < 4.01 then
        print('Crow compatibility mode enabled per https://github.com/monome/crow/pull/463')
        crow_trigger = function()
          crow.send("input[1].query = function() stream_handler(1, input[1].volts) end")
          crow.input[1].query()
        end
      else
        crow_trigger = function()
          crow.input[1].query()
        end
      end
      crow.input[1].stream = sample_crow
      crow.input[1].mode("none")
      -- voltage threshold, hysteresis, "rising", "falling", or “both"
      -- TODO: might want to use as a gate with "both"
      crow.input[2].mode("change",2,0.1,"rising")
      crow.input[2].change = crow_trigger
      -- time,level,polarity
      crow.output[2].action = "pulse(.001,5,1)"
      crow.output[3].slew = 0
    end
  )


  crow.ii.jf.event = function(e, value)
    if e.name == 'mode' then
      -- print('preinit jf.mode = '..value)
      preinit_jf_mode = value
    elseif e.name == 'time' then
      jf_time = value
      -- print('jf_time = ' .. value)
    end
  end
  
  
  function capture_preinit()
    preinit_clock_source = params:get('clock_source')
    -- print('preinit_clock_source = ' .. preinit_clock_source)
    preinit_clock_crow_out = params:get('clock_crow_out')
    -- print('preinit_clock_crow_out = ' .. preinit_clock_crow_out)
    preinit_jf_mode = clock.run(
      function()
        clock.sleep(0.005) -- a small hold for usb round-trip
        crow.ii.jf.get ('mode') -- will trigger the above .event function
        -- Activate JF Synthesis mode here so it happens after the hold
        crow.ii.jf.mode(1)
      end
    )
  
    -- If syncing to Crow clock, turn this off since we need to use Crow inputs for harmonizer. Revert in cleanup()
    if preinit_clock_source == 4 then params:set('clock_source',1) end
    
    -- Turn off system Crow clock out so it doesn't conflict with DS' custom one. Revert in cleanup()
    -- Todo p2 look at dynamically turning this on/off rather than use the DS custom clock. Or allow choice.
    params:set('clock_crow_out', 1)
  end
  capture_preinit()


  -- Reverts changes to crow and jf that might have been made by DS
  function cleanup()
    clock.link.stop()
    if preinit_clock_source == 4 then 
      params:set('clock_source', preinit_clock_source)
      print('Restoring clock_source to ' .. preinit_clock_source)
    end
    if preinit_clock_crow_out ~= 1 then 
      params:set('clock_crow_out', preinit_clock_crow_out)
      print('Restoring clock_crow_out to ' .. preinit_clock_crow_out)
    end
    if preinit_jf_mode == 0 then
      crow.ii.jf.mode(preinit_jf_mode)
      print('Restoring jf.mode to ' .. preinit_jf_mode)
    end
  end
  
    
  -------------
  -- Read prefs
  -------------
  function read_prefs()  
    prefs = {}
    local filepath = norns.state.data
    if util.file_exists(filepath) then
      if util.file_exists(filepath.."prefs.data") then
        prefs = tab.load(filepath.."prefs.data")
        print('table >> read: ' .. filepath.."prefs.data")
        else
          print('table >> missing: ' .. filepath.."prefs.data")
      end
    end
  end
  
  read_prefs()
  
  clock.link.stop() -- or else transport won't start if external link clock is already running

  init_generator()
  
  -- midi stuff
  midi_device = {} -- container for connected MIDI devices
  midi_device_names = {} -- container for their names
  refresh_midi_devices()
  
  -- events init
  local events_lookup_names = {}
  local events_lookup_ids = {}
  for i = 1, #events_lookup do
    events_lookup_names[i] = events_lookup[i].name
    events_lookup_ids[i] = events_lookup[i].id
  end
  
  -- key = event_id, value = index
  events_lookup_index = tab.invert(events_lookup_ids)
  
  -- Used to derive the min and max indices for the selected event category (Global, Chord, Seq, etc...)
  local event_categories = {}
  for i = 1, #events_lookup do
    event_categories[i] = events_lookup[i].category
  end
  
  -- Generate subcategories lookup tables
  gen_event_tables()
  -- Derivatives:
  --  event_subcategories: Unique, ordered event subcategories for each category. For generating subcategories
  --  event_indices: key = conctat category_subcategory with first_index and last_index values


  --------------------
  -- PARAMS
  --------------------
  
  ----------------------------------------
  params:add_separator ('DREAMSEQUENCE')

  ------------------
  -- PREFERENCES PARAMS --
  ------------------
  -- Persistent settings saved to prefs.data and managed outside of .pset files

  params:add_group('preferences', 'PREFERENCES', 3)

  params:add_option('default_pset', 'Load pset', {'Off', 'Last'}, 1)
  params:set_save('default_pset', false)
  params:set('default_pset', param_option_to_index('default_pset', prefs.default_pset) or 1)
  params:set_action('default_pset', function() save_prefs() end)
  
  params:add_option('chord_readout', 'Chords as', {'Name', 'Degree'}, 1)
  params:set_save('chord_readout', false)
  params:set('chord_readout', param_option_to_index('chord_readout', prefs.chord_readout) or 1)
  params:set_action('chord_readout', function() save_prefs() end)
  
  params:add_option('crow_pullup', 'Crow pullup', {'Off', 'On'}, 2)
  params:set_save('crow_pullup', false)
  params:set('crow_pullup', param_option_to_index('crow_pullup', prefs.crow_pullup) or 2)
  params:set_action("crow_pullup", function(val) crow_pullup(val); save_prefs() end)
  
  
  ------------------
  -- ARRANGER PARAMS --
  ------------------
  params:add_group('arranger_group', 'ARRANGER', 2)

  params:add_option('arranger', 'Arranger', {'Off', 'On'}, 1)
  params:set_action('arranger', function() grid_redraw(); update_arranger_active() end)
  
  params:add_option('playback', 'Playback', {'1-shot','Loop'}, 2)
  params:set_action('playback', function() grid_redraw(); arranger_ending() end)
  -- params:add_option('crow_assignment', 'Crow 4', {'Reset', 'On/high', 'V/pattern', 'Chord', 'Pattern'},1) -- todo
  
    
  ------------------
  -- GLOBAL PARAMS --
  ------------------
  params:add_group('global', 'GLOBAL', 7)
  
  params:add_number('mode', 'Mode', 1, 9, 1, function(param) return mode_index_to_name(param:get()) end) -- post-bang action
  
  params:add_number("transpose", "Key", -12, 12, 0, function(param) return transpose_string(param:get()) end)
  
  -- Tempo and clock source appear in Global menu but are actually system parameters so aren't here
  -- todo p2 would be nice to replicate these and have a version of clock_source that handles the crow clock situation...
  
  -- Crow clock uses hybrid notation/PPQN
  params:add_number('crow_clock_index', 'Crow clock', 1, 65, 18,function(param) return crow_clock_string(param:get()) end)
  params:set_action('crow_clock_index',function() set_crow_clock() end)  

  params:add_number('dedupe_threshold', 'Dedupe <', 0, 10, div_to_index('1/32'), function(param) return divisions_string(param:get()) end)
  params:set_action('dedupe_threshold', function() dedupe_threshold() end)
  
  params:add_number('chord_preload', 'Chord preload', 0, 10, div_to_index('1/64'), function(param) return divisions_string(param:get()) end)
  params:set_action('chord_preload', function(x) chord_preload(x) end)     

  -- figured better here since generators can touch things outside of the chord/seq space
  params:add_option('chord_generator', 'C-gen', chord_algos['name'], 1)

  params:add_option('seq_generator', 'S-gen', seq_algos['name'], 1)


  ------------------
  -- EVENT PARAMS --
  ------------------
  --todo p3 generate from events_lookup or derivative
  params:add_option('event_category', 'Category', {'Global', 'Chord', 'Seq', 'MIDI harmonizer', 'CV harmonizer'}, 1)
  params:hide(params.lookup['event_category'])
  
  -- options will be dynamically swapped out based on the current event_global param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  params:add_option('event_subcategory', 'Subcategory', event_subcategories['Global'], 1)
  params:hide(params.lookup['event_subcategory'])
 
  params:add_option('event_name', 'Event', events_lookup_names, 1) -- Default value overwritten later in Init
  params:hide(params.lookup['event_name'])
  
  -- options will be dynamically swapped out based on the current event_name param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  event_operation_options_continuous = {'Set', 'Increment', 'Wander', 'Random'}
  event_operation_options_discreet = {'Set', 'Random'}
  event_operation_options_trigger = {'Trigger'} 
  params:add_option('event_operation', 'Operation', _G['event_operation_options_' .. events_lookup[1].value_type], 1)
  params:hide(params.lookup['event_operation'])

  -- todo p1 needs paramcontrol if this is even still used?
  params:add_number('event_value', 'Value', -9999, 9999, get_default_event_value())
  params:hide(params.lookup['event_value'])

  params:add_number('event_probability', 'Probability', 0, 100, 100, function(param) return percent(param:get()) end)
  params:hide(params.lookup['event_probability'])
  
  params:add_option('event_op_limit', 'Limit', {'Off', 'Clamp', 'Wrap'}, 1)
  params:set_action('event_op_limit',function() gen_menu_events() end)
  params:hide(params.lookup['event_op_limit'])

  params:add_option('event_op_limit_random', 'Limit', {'Off', 'On'}, 1)
  params:set_action('event_op_limit_random',function() gen_menu_events() end)
  params:hide(params.lookup['event_op_limit_random'])

  params:add_number('event_op_limit_min', 'Min', -9999, 9999, 0)
  params:hide(params.lookup['event_op_limit_min'])
  
  params:add_number('event_op_limit_max', 'Max', -9999, 9999, 0)
  params:hide(params.lookup['event_op_limit_max'])
  

  ------------------
  -- CHORD PARAMS --
  ------------------
  params:add_group('chord', 'CHORD', 23)  
  
  chord_div = 192 -- seems to be some race-condition when loading pset, index value 15, and setting this via param action so here we go
  params:add_number('chord_div_index', 'Step length', 1, 57, 15, function(param) return divisions_string(param:get()) end)
  params:set_action('chord_div_index',function(val) chord_div = division_names[val][1] end)

  params:add_option('chord_output', 'Output', {'Mute', 'Engine', 'MIDI', 'ii-JF', 'Disting'},2)
  params:set_action("chord_output",function() update_menus() end)
  
  params:add_number('chord_duration_index', 'Duration', 1, 57, 15, function(param) return divisions_string(param:get()) end)
  params:set_action('chord_duration_index',function(val) chord_duration = division_names[val][1] end) -- pointless?
  
  params:add_number('chord_octave','Octave', -2, 4, 0)
  
  params:add_option('chord_type','Chord type', {'Triad', '7th'}, 1)
  
  params:add_number('chord_density', 'Density', 0, 8, 3)
  
  params:add_number('chord_inversion', 'Inversion', 0, 16, 0)
  
  params:add_number('chord_spread', 'Spread', 0, 6, 0)

  -- params:add_number('chord_rotate', 'Pattern rotate', -14, 14, 0)
  -- params:set_action('chord_rotate',function() pattern_rotate_abs('chord_rotate') end)  
  
  -- params:add_number('chord_shift', 'Pattern shift', -14, 14, 0)
  -- params:set_action('chord_shift',function() pattern_shift_abs('chord_shift') end)
  
  -- will act on current pattern unlike numbered seq param
  max_chord_pattern_length = 16
  params:add_number('chord_pattern_length', 'Pattern length', 1, max_chord_pattern_length, 4) -- max length to be based on 
  params:set_action('chord_pattern_length', function() pattern_length('chord_pattern_length') end)

  ----------------------------------------
  params:add_separator ('chord_engine', 'Engine')
  
  params:add_number('chord_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  
  params:add_control("chord_pp_cutoff","Cutoff",controlspec.new(50, 5000, 'exp', 0, 700, 'hz'))
  params:add_number('chord_pp_tracking', 'Fltr tracking', 0, 100, 50, function(param) return percent(param:get()) end)
  pp_gain = controlspec.def{
    min=0,
    max=400,
    warp='lin',
    step=10,
    default=100,
    wrap=false,
    }
  params:add_control("chord_pp_gain", "Gain", pp_gain, function(param) return util.round(param:get()) end)
  
  params:add_number("chord_pp_pw", "Pulse width", 1, 99, 50, function(param) return percent(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('chord_midi', 'MIDI')
  
  params:add_number('chord_midi_velocity', 'Velocity', 0, 127, 100)
  
  params:add_number('chord_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("chord_midi_cc_1_val",function(val) send_cc('chord', 1, val) end)
  
  params:add_number('chord_midi_out_port', 'Port', 1, #midi.vports, 1)
    -- params:set_action('chord_midi_out_port', function(value) chord_midi_out = midi_device[value] end)    
  params:add_number('chord_midi_ch', 'Channel', 1, 16, 1)
  
  ----------------------------------------
  params:add_separator ('chord_jf', 'Just Friends')
  params:add_number('chord_jf_amp', 'Amp', 0, 50, 10, function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('chord_disting', 'Disting')
  params:add_number('chord_disting_velocity', 'Velocity', 0, 100, 50, function(param) return ten_v(param:get()) end)


  ------------------
  -- SEQ PARAMS --
  ------------------
  params:add_group('seq', 'SEQ', 30)

  params:add_option("seq_note_map_1", "Notes", {'Triad', '7th', 'Mode+Transp.', 'Mode'}, 1)
  
  params:add_option("seq_start_on_1", "Start on", {'Seq end', 'Step', 'Chord', 'Cue'}, 1)
  -- params:set_save('seq_start_on_1', false)
  -- params:hide(params.lookup['seq_start_on_1'])
    
  params:add_option('seq_reset_on_1', 'Reset on', {'Step', 'Chord', 'Stop'}, 3)
  -- params:set_save('seq_reset_on_1', false)
  -- params:hide(params.lookup['seq_reset_on_1'])

  -- option combo style way of setting the above  
  -- local seq_modes = 
  --   {
  --   'Loop/step',
  --   'Loop/chord',
  --   'Loop/stop',
  --   'Step/step',
  --   'Step/chord',
  --   'Step/stop',
  --   'Chord/step',
  --   'Chord/chord',
  --   'Chord/stop',
  --   '1-shot/step',
  --   '1-shot/chord',
  --   '1-shot/stop',
  --   }
    
  -- params:add_option("seq_mode_combo_1", "Mode", seq_modes, 1)
  -- params:set_action("seq_mode_combo_1",function(val) set_seq_mode_1(val) end)
  -- function set_seq_mode_1(val)
  --   params:set('seq_start_on_1', math.ceil(val/3))
  --   params:set('seq_reset_on_1', (val - 1) % 3 + 1)
  -- end
  
  -- Technically acts like a trigger but setting up as add_binary lets it be PMAP-compatible
  params:add_binary('seq_start_1','Start', 'trigger')
  params:set_action('seq_start_1',function()  play_seq = true end) -- seq_1_shot_1 = true end)
  
  -- Technically acts like a trigger but setting up as add_binary lets it be PMAP-compatible
  params:add_binary('seq_reset_1','Reset', 'trigger')
  params:set_action('seq_reset_1',function() seq_pattern_position = 0 end)
  
  params:add_number('seq_div_index_1', 'Step length', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('seq_div_index_1', function(val) seq_div = division_names[val][1] end)

  params:add_option("seq_output_1", "Output", {'Mute', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'},2)
  params:set_action("seq_output_1",function() update_menus() end)
  
  params:add_number('seq_duration_index_1', 'Duration', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('seq_duration_index_1', function(val) seq_duration = division_names[val][1] end)

  max_seq_pattern_length = 16  
  params:add_number('seq_rotate_1', 'Pattern rotate', (max_seq_pattern_length * -1), max_seq_pattern_length, 0)
  params:set_action('seq_rotate_1', function() pattern_rotate_abs('seq_rotate_1') end)
  
  params:add_number('seq_shift_1', 'Pattern shift', -14, 14, 0)
  params:set_action('seq_shift_1', function() pattern_shift_abs('seq_shift_1') end)
  
  -- numbered so we can operate on parallel seqs down the road
  params:add_number('seq_pattern_length_1', 'Pattern length', 1, max_seq_pattern_length, 8)
  params:set_action('seq_pattern_length_1', function() pattern_length(1) end)
  
  params:add_number('seq_octave_1', 'Octave', -2, 4, 0)

  ----------------------------------------
  params:add_separator ('seq_engine', 'Engine')
  
  params:add_number('seq_pp_amp_1', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  
  params:add_control("seq_pp_cutoff_1", "Cutoff", controlspec.new(50, 5000, 'exp', 0, 700, 'hz'))
  
  params:add_number('seq_pp_tracking_1', 'Fltr tracking', 0, 100, 50,function(param) return percent(param:get()) end)
  params:add_control("seq_pp_gain_1","Gain", pp_gain, function(param) return util.round(param:get()) end)
  params:add_number("seq_pp_pw_1","Pulse width",1, 99, 50,function(param) return percent(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('seq_midi', 'MIDI')
  params:add_number('seq_midi_out_port_1', 'Port', 1, #midi.vports, 1)
  params:add_number('seq_midi_ch_1','Channel',1, 16, 1)
  params:add_number('seq_midi_velocity_1','Velocity',0, 127, 100)
  
  params:add_number('seq_midi_cc_1_val_1', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("seq_midi_cc_1_val_1",function(val) send_cc('seq', 1, val) end)

  ----------------------------------------
  params:add_separator ('seq_jf_1', 'Just Friends')
  params:add_number('seq_jf_amp_1','Amp',0, 50, 10,function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('seq_disting_1', 'Disting')
  params:add_number('seq_disting_velocity_1', 'Velocity', 0, 100, 50, function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('seq_crow', 'Crow')
  
  params:add_option("seq_tr_env_1", "Output", {'AD env.', 'Trigger'}, 1)
  params:set_action("seq_tr_env_1",function() update_menus() end)
  
  params:add_number('seq_ad_skew_1','AD env. skew', 0 , 100, 0, function(param) return percent(param:get()) end)
  
  
  ------------------
  -- MIDI HARMONIZER PARAMS --
  ------------------
  params:add_group('midi_harmonizer', 'MIDI HARMONIZER', 24)  

  params:add_option("midi_note_map", "Notes", {'Triad', '7th', 'Mode+Transp.', 'Mode'}, 1)

  params:add_option("midi_output", "Output", {'Mute', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'}, 2)
  params:set_action("midi_output",function() update_menus() end)
    
  params:add_number('midi_harmonizer_in_port', 'Port in',1,#midi.vports,1)
    params:set_action('midi_harmonizer_in_port', function(value)
      in_midi.event = nil
      in_midi = midi.connect(params:get('midi_harmonizer_in_port'))
      in_midi.event = midi_event      
    end)
    -- set in_midi port once before params:bang()
    in_midi = midi.connect(params:get('midi_harmonizer_in_port'))
    in_midi.event = midi_event
  
  params:add_number('midi_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
  params:set_action('midi_duration_index', function(val) midi_duration = division_names[val][1] end) -- pointless?
    
  params:add_number('midi_octave', 'Octave', -2, 4, 0)

  ----------------------------------------
  params:add_separator ('midi_harmonizer_engine', 'Engine')
  
  params:add_number('midi_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_control("midi_pp_cutoff", "Cutoff", controlspec.new(50, 5000, 'exp', 0, 700, 'hz'))
  params:add_number('midi_pp_tracking', 'Fltr tracking', 0, 100, 50,function(param) return percent(param:get()) end)
  params:add_control("midi_pp_gain", "Gain", pp_gain, function(param) return util.round(param:get()) end)
  params:add_number("midi_pp_pw","Pulse width", 1, 99, 50, function(param) return percent(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('midi_harmonizer_midi', 'MIDI')
  
  params:add_number('midi_midi_out_port', 'Port out',1,#midi.vports,1)   -- (clock out ports configured in global midi parameters) 
  params:add_number('midi_midi_ch','Channel', 1, 16, 1)
  params:add_option('midi_velocity_passthru', 'Pass velocity', {'Off', 'On'}, 1)
  params:set_action("midi_velocity_passthru", function() update_menus() end)  
  params:add_number('midi_midi_velocity', 'Velocity', 0, 127, 100)
  
  params:add_number('midi_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("midi_midi_cc_1_val", function(val) send_cc('midi', 1, val) end)
  
  ----------------------------------------
  params:add_separator ('Just Friends')
  
  params:add_number('midi_jf_amp', 'Amp', 0, 50, 10, function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('Disting')
  
  params:add_number('midi_disting_velocity', 'Velocity', 0, 100, 50, function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('midi_harmonizer_crow', 'Crow')
  
  params:add_option("midi_tr_env", "Output", {'AD env.','Trigger'},1)
  params:set_action("midi_tr_env",function() update_menus() end)
  
  params:add_number('midi_ad_skew', 'AD env. skew', 0, 100, 0, function(param) return percent(param:get()) end)

  
  ------------------
  -- CV HARMONIZER PARAMS --
  ------------------
  params:add_group('cv_harmonizer', 'CV HARMONIZER', 23)
  
  params:add_option("crow_note_map", "Notes", {'Triad', '7th', 'Mode+Transp.', 'Mode'}, 1)

  params:add_option("crow_output", "Output", {'Mute', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'},2)
  params:set_action("crow_output", function() update_menus() end)
  
  params:add_number('crow_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
  params:set_action('crow_duration_index', function(val) crow_duration = division_names[val][1] end) -- pointless?
  
  
  params:add_number('crow_octave', 'Octave', -2, 4, 0)

  ----------------------------------------
  params:add_separator ('cv_harmonizer_engine', 'Engine')
  
  params:add_number('crow_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_option('crow_auto_rest', 'Auto-rest', {'Off', 'On'}, 1)

  params:add_control("crow_pp_cutoff","Cutoff",controlspec.new(50, 5000, 'exp', 0, 700, 'hz'))
  params:add_number('crow_pp_tracking', 'Fltr tracking', 0, 100, 50, function(param) return percent(param:get()) end)
  
  params:add_control("crow_pp_gain","Gain", pp_gain,function(param) return util.round(param:get()) end)
  
  params:add_number("crow_pp_pw","Pulse width", 1, 99, 50, function(param) return percent(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('cv_harmonizer_midi', 'MIDI')
  
  params:add_number('crow_midi_out_port', 'Port', 1, #midi.vports, 1)
  
  params:add_number('crow_midi_ch','Channel', 1, 16, 1)
  
  params:add_number('crow_midi_velocity', 'Velocity', 0, 127, 100)

  params:add_number('crow_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("crow_midi_cc_1_val", function(val) send_cc('crow', 1, val) end)

  ----------------------------------------
  params:add_separator ('cv_harmonizer_jf', 'Just Friends')
  params:add_number('crow_jf_amp', 'Amp', 0, 50, 10, function(param) return ten_v(param:get()) end)
 
  ----------------------------------------
  params:add_separator ('cv_harmonizer_disting', 'Disting')
  params:add_number('crow_disting_velocity', 'Velocity', 0, 100, 50, function(param) return ten_v(param:get()) end)
  
  ----------------------------------------
  params:add_separator ('cv_harmonizer_crow', 'Crow')
  params:add_option("crow_tr_env", "Output", {'AD env.','Trigger'},1)
  params:set_action("crow_tr_env",function() update_menus() end)
  
  params:add_number('crow_ad_skew','AD env. skew',0, 100, 0, function(param) return percent(param:get()) end)
  
  
  -----------------------------
  -- INIT STUFF
  -----------------------------
  start = false
  transport_state = 'stopped'
  clock_start_method = 'start'
  link_stop_source = nil
  global_clock_div = 48
  timing_clock_id = clock.run(timing_clock) --Start a new timing clock to handle note-off

  build_scale()

  -- Send out MIDI stop on launch if clock ports are enabled
  transport_multi_stop()  
  arranger_active = false
  chord_pattern_retrig = true
  play_seq = false
  screen_views = {'Session','Events'}
  screen_view_index = 1
  screen_view_name = screen_views[screen_view_index]
  grid_dirty = true
  -- grid "views" are decoupled from screen "pages"  
  grid_views = {'Arranger','Chord','Seq'}
  grid_view_keys = {}
  grid_view_name = grid_views[2]
  math.randomseed(os.time()) -- doesn't seem like this is needed but not sure why
  fast_blinky = 1
  pages = {'GLOBAL>', 'CHORD', 'SEQ', 'MIDI HARMONIZER', '<CV HARMONIZER'}
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  update_menus()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  transport_active = false
  chord_pattern_length = {4,4,4,4}
  set_chord_pattern(1)
  pattern_name = {'A','B','C','D'}
  pattern_queue = false
  pattern_copy_performed = false
  arranger_retrig = false
  max_arranger_length = 64
  arranger = {}
  for segment = 1, max_arranger_length do
    arranger[segment] = 0
  end
  arranger[1] = 1 -- setting this so new users aren't confused about the pattern padding
  -- Version of arranger which generates chord patterns for held segments
  arranger_padded = {}
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
  selected_events_menu = 'event_category'
  change_category()
  params:set('event_name', event_subcategory_index_min)  -- Overwrites initial param value
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
  -- arranger_pattern_keys = {}
  arranger_pattern_key_first = nil -- simpler way to identify the first key held down so we can handle this as a "copy" action and know when to act on it or ignore it. Don't need a whole table.
  arranger_loop_key_count = 0 -- rename arranger_events_strip_key_count?
  -- arranger_pattern_key_interrupt = false -- todo p1 probably not needed
  key_counter = 4
  pattern_key_count = 0
  chord_key_count = 0
  view_key_count = 0
  event_key_count = 0
  keys = {}
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
  midi_note_history = {}
  engine_note_history = {}
  crow_note_history = {}
  jf_note_history = {}
  disting_note_history = {}
  dedupe_threshold()
  reset_clock() -- will turn over to step 0 on first loop
  get_next_chord()
  chord_raw = next_chord
  -- pset_queue = nil
  -- pset_data_cache = {}
  -- pset_load_source = 'load_system'
  -- -- hidden param for selecting pset events
  -- params:add_number('load_pset', 'Load pset', 1,99, 1)
  -- params:hide(params.lookup['load_pset'])
  -- params:add_number('splice_pset', 'Splice pset', 1,99, 1)
  -- params:hide(params.lookup['splice_pset'])
  -- params:add_number('save_pset', 'Save pset', 1,99, 1)
  -- params:hide(params.lookup['save_pset'])  
    
  -- table names we want pset  callbacks to act on
  pset_lookup = {'arranger', 'events', 'chord_pattern', 'chord_pattern_length', 'seq_pattern', 'seq_pattern_length', 'misc'}
  
  
  -----------------------------
  -- PSET callback functions --   
  -----------------------------
  function params.action_write(filename,name,number)
    local filepath = norns.state.data..number.."/"
    os.execute("mkdir -p "..filepath)
    -- Make table with version (for backward compatibility checks) and any useful system params
    misc = {}
    misc.timestamp = os.date()
    misc.version = version
    misc.clock_tempo = params:get('clock_tempo')
    misc.clock_source = params:get('clock_source')
    misc.current_shift_seq = current_shift_seq
    misc.current_shift_chord = current_shift_chord
    misc.current_rotation_seq = current_rotation_seq
    
    for i = 1, #pset_lookup do
      local tablename = pset_lookup[i]
      tab.save(_G[tablename],filepath..tablename..".data")
      print('table >> write: ' .. filepath..tablename..".data")
    end
    -- cache(number) -- read from filesystem and store in pset_cache
  end


  function params.action_read(filename,silent,number)
    local filepath = norns.state.data..number.."/"
    if util.file_exists(filepath) then
      -- Close the event editor if it's currently open so pending edits aren't made to the new arranger unintentionally
      screen_view_index = 1
      screen_view_name = 'Session'
      misc = {}
      for i = 1, #pset_lookup do
        local tablename = pset_lookup[i]
          if util.file_exists(filepath..tablename..".data") then
          _G[tablename] = tab.load(filepath..tablename..".data")
          print('table >> read: ' .. filepath..tablename..".data")
        else
          print('table >> missing: ' .. filepath..tablename..".data")
        end
      end
      -- clock_tempo isn't stored in .pset for some reason so set it from misc.data (todo: look into inserting into .pset)
      params:set('clock_tempo', misc.clock_tempo or params:get('clock_tempo'))
      current_shift_seq = misc.current_shift_seq
      current_shift_chord = misc.current_shift_chord
      current_rotation_seq = misc.current_rotation_seq
      
      -- reset event-related params so the event editor opens to the default view rather than the last-loaded event
      params:set('event_category', 1)
      change_category()
      params:set('event_subcategory', 1) -- called by the above
      params:set('event_name', 1)
      change_event()
      params:set('event_operation', 1)
      params:set('event_op_limit', 1)
      params:set('event_op_limit_random', 1)
      params:set('event_probability', 100) -- todo p1 change after float
      params:set('event_value', get_default_event_value())
      events_index = 1
      selected_events_menu = events_menus[events_index]
      gen_menu_events()
      event_edit_active = false
  
      -- todo p2 loading pset while transport is active gets a little weird with Link and MIDI but I got other stuff to deal with
      if params:get('clock_source') == 'internal' then 
        reset_clock()
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
      if transport_state == 'paused' then
        transport_state = 'stopped' -- just flips to the stop icon so user knows they don't have to do this manually
      end

      -- don't remember why this was needed?
      -- local seq_reset_on_1 = params:get('seq_reset_on_1')
      -- if seq_reset_on_1 == 3 then -- Stop or Event type.
      --   play_seq = true
      -- else
      --   play_seq = false
      -- end
      play_seq = false
    
      build_scale() -- Have to run manually because mode bang comes after all of this for some reason. todo p2 look into this for the billionth time. There is some reason for it.
      get_next_chord()
      chord_raw = next_chord
      chord_no = 0 -- wipe chord readout
      gen_chord_readout()
      gen_dash('params.action_read')
      read_prefs()
      -- if transport_active, reset and continue playing so user can demo psets from the system menu
      -- todo p2 need to send different sync values depending on clock source.
      -- when link clock is running we can pick up on the wrong beat.
      -- unsure about MIDI
      -- if transport_active == true then
      --   clock.transport.start()
      -- end
      
      -- Overwrite these prefs
      params:set('chord_readout', param_option_to_index('chord_readout', prefs.chord_readout) or 1)
      params:set('default_pset', param_option_to_index('default_pset', prefs.default_pset) or 1)
      params:set('crow_pullup', param_option_to_index('crow_pullup', prefs.crow_pullup) or 2)
    end
  
  grid_redraw()
  redraw()
  end


  function params.action_delete(filename,name,number)
    norns.system_cmd("rm -r "..norns.state.data.."/"..number.."/")
    print('directory >> delete: ' .. norns.state.data .. number)
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
    prefs.chord_readout = params:string('chord_readout')
    prefs.default_pset = params:string('default_pset')
    prefs.crow_pullup = params:string('crow_pullup')
    tab.save(prefs, filepath .. "prefs.data")
    if countdown_timer ~= nil then --  trick to keep this from junking up repl on init bang (x2 if pset loads)
      print('table >> write: ' .. filepath.."prefs.data")
    end
  end


  -- Optional: load most recent pset on init
  if params:string('default_pset') == 'Last' then
    params:default()
  end

  params:bang()
  
  -- Some actions need to be added post-bang. I forget why but something to do with setting the chord readout?
  params:set_action('mode', function() build_scale(); update_chord_action() end)
  
  countdown_timer = metro.init()
  countdown_timer.event = countdown -- call the 'countdown' function below,
  countdown_timer.time = .1 -- 1/10s
  countdown_timer.count = -1 -- for.evarrr
  countdown_timer:start()
  
  grid_redraw()
  redraw()
end



  -- UPDATE_MENUS. todo p2: can be optimized by only calculating the current view+page or when certain actions occur
function update_menus()

  -- GLOBAL MENU 
    menus[1] = {'mode', 'transpose', 'clock_tempo', 'clock_source',
      'crow_clock_index', 'dedupe_threshold', 'chord_preload', 'chord_generator', 'seq_generator'}
  
  -- CHORD MENU
  if params:string('chord_output') == 'Mute' then
    menus[2] = {'chord_output', 'chord_div_index'} -- maybe add chord_type back depending on readout
  elseif params:string('chord_output') == 'Engine' then
    menus[2] = {'chord_output', 'chord_type', 'chord_octave', 'chord_density', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_tracking', 'chord_pp_gain', 'chord_pp_pw'}
  elseif params:string('chord_output') == 'MIDI' then
    menus[2] = {'chord_output', 'chord_type', 'chord_octave', 'chord_density', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_midi_out_port', 'chord_midi_ch', 'chord_midi_velocity', 'chord_midi_cc_1_val'}
  elseif params:string('chord_output') == 'ii-JF' then
    menus[2] = {'chord_output', 'chord_type', 'chord_octave', 'chord_density', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_jf_amp'}
  elseif params:string('chord_output') == 'Disting' then
    menus[2] = {'chord_output', 'chord_type', 'chord_octave', 'chord_density', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_disting_velocity'}  
  end
  
  -- SEQ MENU
  if params:string('seq_output_1') == 'Mute' then
    menus[3] = {'seq_output_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_rotate_1',  'seq_shift_1', 'seq_div_index_1'}
  elseif params:string('seq_output_1') == 'Engine' then
    menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_duration_index_1', 'seq_pp_amp_1', 'seq_pp_cutoff_1', 'seq_pp_tracking_1','seq_pp_gain_1', 'seq_pp_pw_1'}
  elseif params:string('seq_output_1') == 'MIDI' then
    menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_duration_index_1', 'seq_midi_out_port_1', 'seq_midi_ch_1', 'seq_midi_velocity_1', 'seq_midi_cc_1_val_1'}
  elseif params:string('seq_output_1') == 'Crow' then
    if params:string('seq_tr_env_1') == 'Trigger' then
      menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_tr_env_1'}
    else -- AD envelope
      menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_tr_env_1', 'seq_duration_index_1', 'seq_ad_skew_1',}
    end
  elseif params:string('seq_output_1') == 'ii-JF' then
    menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_jf_amp_1'}
  elseif params:string('seq_output_1') == 'Disting' then
    menus[3] = {'seq_output_1', 'seq_note_map_1', 'seq_start_on_1', 'seq_reset_on_1', 'seq_octave_1', 'seq_rotate_1','seq_shift_1', 'seq_div_index_1', 'seq_duration_index_1', 'seq_disting_velocity_1'}    
  end
  
  -- MIDI HARMONIZER MENU
  if params:string('midi_output') == 'Mute' then
    menus[4] = {'midi_output'}
  elseif params:string('midi_output') == 'Engine' then
    menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_duration_index', 'midi_pp_amp', 'midi_pp_cutoff', 'midi_pp_tracking', 'midi_pp_gain', 'midi_pp_pw'}
  elseif params:string('midi_output') == 'MIDI' then
    if params:get('midi_velocity_passthru') == 2 then
      menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_duration_index','midi_harmonizer_in_port', 'midi_midi_out_port', 'midi_midi_ch', 'midi_velocity_passthru', 'midi_midi_cc_1_val'}
    else
      menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_duration_index', 'midi_harmonizer_in_port', 'midi_midi_out_port', 'midi_midi_ch', 'midi_velocity_passthru', 'midi_midi_velocity', 'midi_midi_cc_1_val'}
    end
  elseif params:string('midi_output') == 'Crow' then
    if params:string('midi_tr_env') == 'Trigger' then
      menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_tr_env'}
    else -- AD envelope
      menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_tr_env', 'midi_duration_index', 'midi_ad_skew'}
    end
  elseif params:string('midi_output') == 'ii-JF' then
    menus[4] = {'midi_output', 'midi_note_map', 'midi_octave',  'midi_jf_amp'}
 elseif params:string('midi_output') == 'Disting' then
    menus[4] = {'midi_output', 'midi_note_map', 'midi_octave', 'midi_duration_index', 'midi_disting_velocity'}
  end
  
  -- CV HARMONIZER MENU
  if params:string('crow_output') == 'Mute' then
    menus[5] = {'crow_output'}
  elseif params:string('crow_output') == 'Engine' then
    menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_duration_index', 'crow_pp_amp', 'crow_pp_cutoff', 'crow_pp_tracking', 'crow_pp_gain', 'crow_pp_pw'}
  elseif params:string('crow_output') == 'MIDI' then
    menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_duration_index', 'crow_midi_out_port', 'crow_midi_ch', 'crow_midi_velocity', 'crow_midi_cc_1_val'}
  elseif params:string('crow_output') == 'Crow' then
    if params:string('crow_tr_env') == 'Trigger' then
      menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_tr_env', }
    else -- AD envelope
      menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_tr_env', 'crow_duration_index', 'crow_ad_skew', }
    end
  elseif params:string('crow_output') == 'ii-JF' then
    menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_jf_amp'}
  elseif params:string('crow_output') == 'Disting' then
    menus[5] = {'crow_output', 'crow_note_map', 'crow_auto_rest', 'crow_octave', 'crow_duration_index', 'crow_disting_velocity'}    
  end  
end


-- -- check if string ends with, uh, ends_with
-- function ends_with(string, ends_with)
--   return string:sub(-#ends_with) == ends_with
-- end
  
  
-- return first number from a string
function find_number(string)
  return tonumber(string.match (string, "%d+"))
end
  
  
-- -- return .pset number as string assuming format is 'dreamsequence-xxxx.pset'
-- function pset_number(string)
--   return string.sub(string, 15, string.len(string) - 5)
-- end


-- function init_cache()  
--   -- check /home/we/dust/data/dreamsequence/ for any .psets and store their "numbers" as strings in valid_psets
--   -- this table is used to search for matching table .data files that need to be loaded into the cache
--   script_data = util.scandir(norns.state.data)
--   valid_psets = {}
--   for i = 1, #script_data do
--     if ends_with(script_data[i], '.pset') then
--       table.insert(valid_psets, pset_number(script_data[i]))
--     end
--   end
--   -- cache all .psets and .data tables for numbered directories having a valid .pset
--   pset_data_cache = {}
--   for i = 1, #valid_psets do
--     cache(valid_psets[i])
--   end
-- end


-- function cache(number)  
--   local data_fp = norns.state.data..number.."/"
--   pset_data_cache[number] = {} -- init table using the preset number AS A STRING
--   manual_pset_cache(number)
  
--   if util.file_exists(data_fp) then -- this can also fire upstream so might want to optimize
--     -- pset_data_cache[number] = {} -- init table using the preset number AS A STRING
--     misc = {}
--     for tables = 1,7 do
--       local tablename = pset_lookup[tables]
--       if util.file_exists(data_fp..tablename..".data") then
--         -- pset_data_cache[number] = {} -- init a table using the preset number AS A STRING
--         pset_data_cache[number][tablename] = tab.load(data_fp..tablename..".data")
--       print('table >> cache: ' .. data_fp..tablename..".data")
--       end
--     end
--   end
-- end



--   -- hacked bit from paramset.lua
--   --- read from disk.
--   -- @tparam string filename either an absolute path, number (to read [scriptname]-[number].pset from local data folder) or nil (to read pset number specified by pset-last.txt in the data folder)
--   -- @tparam boolean silent if true, do not trigger parameter actions
--   -- TODO: does this also need to set norns.state.pset_last?
-- function manual_pset_cache(number, silent)
--     -- filename = filename
--   -- filename = filename or norns.state.pset_last
  
--   local function unquote(s)
--     return s:gsub('^"', ''):gsub('"$', ''):gsub('\\"', '"')
--   end

--   -- local pset_number;
--   -- if type(filename) == "number" then
--     -- local n = filename
--     -- filename = norns.state.data .. norns.state.shortname
--     -- pset_number = string.format("%02d",n)
--     -- local pset_number = filename
--     filename = norns.state.data .. norns.state.shortname .. "-" .. number .. ".pset"
--   -- end
--   -- print(filename)
--   print("pset >> read: " .. filename)
--   local fd = io.open(filename, "r")
--   if fd then
--     io.close(fd)
--     local param_already_set = {}
--     pset_data_cache[number]["pset"] = {}
--     local line_count = 0 
--     for line in io.lines(filename) do
--       if util.string_starts(line, "--") then
--         params.name = string.sub(line, 4, -1)
--       else
--         local id, value = string.match(line, "(\".-\")%s*:%s*(.*)")
--         if id and value then
--           line_count = line_count + 1
--           pset_data_cache[number]["pset"][line_count] = {}
--           id = unquote(id)
--           local index = params.lookup[id]
--           if index and params.params[index] and not param_already_set[index] then
--             if tonumber(value) ~= nil then
--               pset_data_cache[number]["pset"][line_count].id = index
--               pset_data_cache[number]["pset"][line_count].value = tonumber(value)
--             elseif value == "-inf" then
--               pset_data_cache[number]["pset"][line_count].id = index
--               pset_data_cache[number]["pset"][line_count].value = -math.huge              
--             elseif value == "inf" then
--               pset_data_cache[number]["pset"][line_count].id = index
--               pset_data_cache[number]["pset"][line_count].value = math.huge      
--             elseif value then
--               pset_data_cache[number]["pset"][line_count].id = index
--               pset_data_cache[number]["pset"][line_count].value = value
--             end
--             param_already_set[index] = true
--           end
--         end
--       end
--     end
--     -- if self.action_read ~= nil then 
--     --   self.action_read(filename,silent,pset_number)
--     -- end
--   else
--     -- print("pset :: "..filename.." not read.")
--   end
-- end


-- todo p3 move with other MusicUtil functions
function build_scale()
  -- print('build_scale ' .. params:string('mode'))
  -- builds scale for quantization. 14 steps + diatonic transposition offset
  notes_nums = MusicUtil.generate_scale_of_length(0, params:get('mode'), 28)
  -- todo p2 might generate freqs for engine and use for chords too?
  -- notes_freq = MusicUtil.note_nums_to_freqs(notes_nums) -- converts note numbers to an array of frequencies
end
  
  --todo p3 move and can simplify by arg concats (rename pattern to active_chord_pattern)
function pattern_rotate_abs(source)
  local new_rotation_val = params:get(source)
  if source == 'seq_rotate_1' then
    local offset = new_rotation_val or 0 - current_rotation_seq or 0 -- I actually have no idea why this requires the or 0 WTF??
    local length = seq_pattern_length[active_seq_pattern]
    local temp_seq_pattern = {}
    for i = 1, length do
      temp_seq_pattern[i] = seq_pattern[active_seq_pattern][i]
    end
    
    for i = 1, length do
      seq_pattern[active_seq_pattern][i] = temp_seq_pattern[util.wrap(i - (offset - current_rotation_seq), 1, length)]
    end
    
    current_rotation_seq = offset
    
  end
  grid_redraw()
end


--todo p3 move and can simplify by arg concats (rename pattern to active_chord_pattern)
function pattern_shift_abs(source)
  local new_shift_val = params:get(source)
  if source == 'seq_shift_1' then
    local offset = new_shift_val or 0 - current_shift_seq or 0 -- I actually have no idea why this requires the or 0 WTF??
    for y = 1, max_seq_pattern_length do
      if seq_pattern[active_seq_pattern][y] ~= 0 then
        seq_pattern[active_seq_pattern][y] = util.wrap(seq_pattern[active_seq_pattern][y] + offset - current_shift_seq, 1, 14)
      end
    end    
    current_shift_seq = offset
  elseif source == 'chord_shift' then
    local offset = new_shift_val or 0 - current_shift_chord or 0 -- I actually have no idea why this requires the or 0 WTF??
    for y = 1, max_chord_pattern_length do
      if chord_pattern[active_chord_pattern][y] ~= 0 then
        chord_pattern[active_chord_pattern][y] = util.wrap(chord_pattern[active_chord_pattern][y] + offset - current_shift_chord, 1, 14)
      end
    end    
    current_shift_chord = offset  
  end
  grid_redraw()
end


-- param action for xxxx_pattern_length params
function pattern_length(source)
  -- print('setting pattern length via param action')
  if source == 'chord_pattern_length' then
    chord_pattern_length[active_chord_pattern] = params:get(source)
  else
    seq_pattern_length[source] = params:get('seq_pattern_length_' .. source)
  end
  grid_redraw()
end


function refresh_midi_devices()
  for i = 1, #midi.vports do -- query all ports
    midi_device[i] = midi.connect(i) -- connect each device
    table.insert( -- register its name:
      midi_device_names, -- table to insert to
      "port "..i..": "..util.trim_string_to_width(midi_device[i].name, 80) -- value to insert
    )
  end
end


function div_to_index(string)
  for i = 1,#division_names do
    if tab.key(division_names[i],string) == 2 then
      return(i)
    end
  end
end


-- This previously was used to define a single destination for sending out MIDI clock (and transport). Now we're using this to look up the system clock destinations and logging those so we send transport messages to all destinations. Fix: this gets called a lot just to be safe, but is probably only needed when the clock params are touched (callback?) or when starting transport.
function transport_midi_update()
  -- Find out which ports Norns is sending MIDI clock on so we know where to send transport messages
  midi_transport_ports = {}
  midi_transport_ports_index = 1
  for i = 1,16 do
    if params:get('clock_midi_out_' .. i) == 1 then
      -- print('clock to port ' .. i)
      midi_transport_ports[midi_transport_ports_index] = i
      midi_transport_ports_index = midi_transport_ports_index + 1
    end
  end
end


-- check which ports the global midi clock is being sent to and sends a start message there
function transport_multi_start()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  -- for i in pairs(midi_transport_ports) do  
  for i = 1,#midi_transport_ports do
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:start()
  end  
end


-- check which ports the global midi clock is being sent to and sends a stop message there
function transport_multi_stop()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  for i in pairs(midi_transport_ports) do  
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:stop()
  end  
end


-- check which ports the global midi clock is being sent to and sends a continue message there
function transport_multi_continue()
  transport_midi_update() -- update valid transport ports. Is there a callback when these params are touched?
  for i in pairs(midi_transport_ports) do  
    transport_midi = midi.connect(midi_transport_ports[i])
    transport_midi:continue()
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
  return(clock_names[index][2])
end


function set_crow_clock(source)
  crow_div = clock_names[params:get('crow_clock_index')][1]
  -- crow_slew = clock.get_beat_sec() / global_clock_div --- divisior should be PPQN
end


function divisions_string(index) 
  if index == 0 then return('Off') else return(division_names[index][2]) end
end


function duration_sec(dur_mod)
  return(dur_mod/global_clock_div * clock.get_beat_sec())
end


-- todo p2 why is this firing every time grid view keys are pressed? Menu redraw inefficiency
function param_id_to_name(id)
  -- print('param_id_to_name id = ' .. (id or 'nil'))
  return(params.params[params.lookup[id]].name)
end


function mode_index_to_name(index)
  return(MusicUtil.SCALES[index].name)
end
  
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end


function t_f_string(x)
  return(x == 1 and 'True' or 'False')
end


function transpose_string(x)
  local keys = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B','C','C#','D','D#','E','F','F#','G','G#','A','A#','B','C'}
  return(keys[x + 13] .. (x == 0 and '' or ' ') ..  (x >= 1 and '+' or '') .. (x ~= 0 and x or '') )
end


function t_f_bool(x)
  return(x == 1 and true or false)
end


function neg_to_off(x)
  return(x < 0 and 'Off' or x)  
end


function ten_v(x)
  return((x / 10) .. 'v')
end


function mult_100_percent(x)
  return(math.floor(x * 100) .. '%')
end


function percent(x)
  return(math.floor(x) .. '%')
end


-- Establishes the threshold in seconds for considering duplicate notes as well as providing an integer for placeholder duration
function dedupe_threshold()
  local index = params:get('dedupe_threshold')
  dedupe_threshold_int = (index == 0) and 1 or division_names[index][1]
  dedupe_threshold_s = (index == 0) and 1 or duration_sec(dedupe_threshold_int) * .95
end  


function chord_preload(index)
  chord_preload_tics = (index == 0) and 0 or division_names[index][1]
end  


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
  -- todo: think about other tempo-based things that are not generated dynamically
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
      -- print('last_populated_segment = ' .. last_populated_segment)
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
  gen_dash('gen_arranger_padded')
end


-- Hacking up MusicUtil.generate_chord_roman to get modified chord_type for chords.
-- todo p0 fix aug7 logic pending @dewb's PR
function get_chord_name(root_num, scale_type, roman_chord_type)
 
  local rct = roman_chord_type or "I"

  local scale_data = lookup_data(MusicUtil.SCALES, scale_type)
  if not scale_data then return nil end

  -- normalize special chars to plain ASCII using MuseScore-compatible characters
  -- lua does not correctly process utf8 in set character classes, so substitute these
  -- prior to the string.match
  -- treat degree symbols or asterisks as 'o'
  rct = string.gsub(rct, "\u{B0}", "o")
  rct = string.gsub(rct, "\u{BA}", "o")
  rct = string.gsub(rct, "*", "o")
  -- treat upper and lowercase o-stroke as 0
  rct = string.gsub(rct, "\u{D8}", "0")
  rct = string.gsub(rct, "\u{F8}", "0")
  -- treat natural sign as h
  rct = string.gsub(rct, "\u{266E}", "h")

  local degree_string, augdim_string, added_string, bass_string, inv_string =
    string.match(rct, "([ivxIVX]+)([+o0hM]*)([1-9]*)-?([1-9]?)([bcdefg]?)")

  local d = string.lower(degree_string)
  local is_capitalized = degree_string ~= d
  local is_augmented = augdim_string == "+"
  local is_diminished = augdim_string == "o"
  local is_seventh = added_string == "7"

  local is_half_diminished = augdim_string == "0" and is_seventh
  local is_major_seventh = augdim_string == "M" and is_seventh
  local is_augmented_major_seventh = augdim_string == "+M" and is_seventh
  local is_minormajor_seventh = augdim_string == "h" and is_seventh

  local chord_type = nil
  if is_capitalized then -- uppercase, assume major in most circumstances
    if is_augmented then
      if is_seventh then
        chord_type = '+7' -- "Augmented 7"
      else
        chord_type = '+' -- "Augmented"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = '\u{B0}7'  --  "Diminished 7"
      else
        chord_type = '\u{B0}' -- "Diminished"
      end
    elseif is_half_diminished then
      chord_type = '\u{F8}7' -- "Half Diminished 7"
    elseif is_minormajor_seventh then
      chord_type = 'm\u{266e}7' --  "Minor Major 7"
    elseif is_augmented_major_seventh then
      chord_type = '+M7' -- "Augmented Major 7"
    elseif is_major_seventh then
      chord_type = 'M7' --  "Major 7"
    elseif is_seventh then
      chord_type = '7'  --  "Dominant 7"
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "Major 69"
      else
        chord_type = "Major 6"
      end
    elseif added_string == "9" then
      chord_type = "Major 9"
    elseif added_string == "11" then
      chord_type = "Major 11"
    elseif added_string == "13" then
      chord_type = "Major 13"
    else
      chord_type = '' -- "Major" -- nil because we're no longer spelling out maj/min
    end
  else -- lowercase degree, assume minor in most circumstances
    if is_augmented then
      if is_seventh then
        chord_type = '+7' -- "Augmented 7"
      else
        chord_type = '+' -- "Augmented"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = '\u{B0}7'  --  "Diminished 7"
      else
        chord_type = '\u{B0}' -- "Diminished"
      end
    elseif is_half_diminished then
      chord_type = '\u{F8}7' -- "Half Diminished 7"
    elseif is_minormajor_seventh then
      chord_type = 'm\u{266e}7' --  "Minor Major 7"
    elseif is_augmented_major_seventh then
      chord_type = '+M7' -- "Augmented Major 7"
    elseif is_major_seventh then
      chord_type = 'M7' --  "Major 7"
    elseif is_seventh then
      chord_type = 'm7' -- "Minor 7"
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "Minor 69"
      else
        chord_type = "Minor 6"
      end
    elseif added_string == "9" then
      chord_type = "Minor 9"
    elseif added_string == "11" then
      chord_type = "Minor 11"
    elseif added_string == "13" then
      chord_type = "Minor 13"
    else
      chord_type = 'm' -- "Minor"
    end
  end

  local degree = nil
  local roman_numerals = { "i", "ii", "iii", "iv", "v", "vi", "vii" }
  for i,v in pairs(roman_numerals) do
    if(v == d) then
      degree = i
      break
    end
  end
  if degree == nil then return nil end

  local inv = string.lower(inv_string)
  local inversion = 0
  local inversioncodes = { "b", "c", "d", "e", "f", "g" }
  for i,v in pairs(inversioncodes) do
    if(v == inv) then
      inversion = i
      break
    end
  end  
  return(chord_type)
end
  
  
 -- Clock to control sequence events including chord pre-load, chord/seq sequence, and crow clock out
function sequence_clock(sync_val)
  transport_state = 'starting'
  print(transport_state)

  -- INITIAL SYNC DEPENDING ON CLOCK SOURCE
  if params:string('clock_source') == 'internal' then
    clock.sync(1)
  elseif params:string('clock_source') == 'link' then
    clock.sync(params:get('link_quantum'))
  elseif sync_val ~= nil then -- indicates MIDI clock but starting from K3
    clock.sync(sync_val)  -- uses sync 1 to come in on the beat of an already running MIDI clock
  end
  
  transport_state = 'playing'
  print(transport_state)
    
  -- Clock used to refresh arranger countdown timer 10x a second
  -- resetting does not seem to be necessary but I figure it can result in marginally better countdown timing?
  -- metro.free(countdown_timer.id)
  countdown_timer:start()
  
  while transport_active do


  -- SEND MIDI CLOCK START/CONTINUE MESSAGES
    if start == true and stop ~= true then
      transport_active = true
    -- Send out MIDI start/continue messages
      if clock_start_method == 'start' then
        transport_multi_start()  
      else
        transport_multi_continue()
      end
      clock_start_method = 'continue'
      start = false
    end
    
    
    -- ADVANCE CLOCK_STEP
    clock_step = clock_step + 1

    
    -- STOP LOGIC DEPENDING ON CLOCK SOURCE
    -- Immediate or instant stop
    if stop == true then
        
      -- When internally clocked, stop is quantized to occur at the end of the chord step. todo p1 also use this when running off norns link beat_count
      if params:string('clock_source') == 'internal' or params:string('clock_source') == 'midi' then
        if (clock_step) % (chord_div) == 0 then  --stops at the end of the chord step
          -- print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: '.. clock_start_method)
          clock_step = clock_step - 1, 0
          transport_multi_stop()
          transport_active = false
          if transport_state ~= 'stopped' then -- Probably a better way of blocking this
            transport_state = 'paused'
            print(transport_state)
          end
          stop = false
          start = false
        end
      elseif link_stop_source == 'norns' then
        if (clock_step) % (chord_div) == 0 then  --stops at the end of the chord step
          -- print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: '.. clock_start_method)
          clock.link.stop()
          clock_step = clock_step - 1, 0
          transport_multi_stop()
          transport_active = false
          transport_state = 'paused'
          print(transport_state)
          stop = false
          start = false
          link_stop_source = nil
        end      
      
      -- External clock_source. No quantization. Just resets pattern/arrangement immediately
      -- todo p2 look at options for a start/continue mode for external sources that support this
      else
        transport_multi_stop()
        -- print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: '.. clock_start_method)
        
        if arranger_active then
          print(transport_state)
        else
          reset_pattern()
        end
        transport_active = false
        reset_arrangement()
        transport_state = 'stopped'
        stop = false
      end
    end -- of stop handling
    
    
    -- ADVANCE SUB CLOCKS: advance_chord_pattern(), advance_seq_pattern(), Crow pulses
    if transport_active then -- check again
      if (clock_step + chord_preload_tics) % chord_div == 0 then
        get_next_chord()
      end
    
      if clock_step % chord_div == 0 then
        advance_chord_pattern()
        grid_dirty = true
        redraw() -- To update chord readout
      end
  
      if clock_step % seq_div == 0 then
        local seq_start_on_1 = params:get('seq_start_on_1')
        if seq_start_on_1 == 1 then -- Seq end
          advance_seq_pattern()
          grid_dirty = true
        -- elseif seq_start_on_1 == 4 then  -- Cue
        --   if seq_1_shot_1 == true then  -- seq_1_shot_1 is sort of an override for play_seq that takes priority when in seq_start_on_1 'cue' mode
        --     advance_seq_pattern()
        --     grid_dirty = true
        --   end
        elseif play_seq then
          advance_seq_pattern()
          grid_dirty = true      
        end
      end
      
      if clock_step % crow_div == 0 then
      -- crow.output[3]() --pulse defined in init
      crow.output[3].volts = 5
      crow.output[3].slew = 0.001 --Should be just less than 192 PPQN @ 300 BPM
      crow.output[3].volts = 0    
      crow.output[3].slew = 0
      end
    end
    
    
    -- UPDATE GRID
    if grid_dirty == true then
      grid_redraw()
      grid_dirty = false
    end
  
  
    -- SET SYNC WITHIN LOOP
    clock.sync(1/global_clock_div)

  end
end


function calc_seconds_remaining()
  if arranger_active then
    percent_step_elapsed = arranger_position == 0 and 0 or (math.max(clock_step,0) % chord_div / (chord_div-1))
    seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - (percent_step_elapsed or 0))
  else
    seconds_remaining = chord_steps_to_seconds(steps_remaining_in_arrangement - steps_remaining_in_active_pattern or 0)
  end
  seconds_remaining = s_to_min_sec(math.ceil(seconds_remaining))
  end


-- Clock used to redraw screen 10x a second for arranger countdown timer
-- Also used to set blinkies
function countdown()
  calc_seconds_remaining()
  fast_blinky = fast_blinky ~ 1
  grid_redraw() -- todo p0 only keep if we are adding grid flashing
  redraw()  
end  
    
-- This clock is used to keep track of which notes are playing so we know when to turn them off and for optional deduping logic.
-- Unlike the sequence_clock, this continues to run after transport stops in order to turn off playing notes
function timing_clock()
  while true do
    clock.sync(1/global_clock_div)

    for i = #midi_note_history, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      midi_note_history[i][1] = midi_note_history[i][1] - 1
      if midi_note_history[i][1] == 0 then
        -- print('note_off')
        midi_device[midi_note_history[i][5]]:note_off(midi_note_history[i][2], 0, midi_note_history[i][3]) -- port, note, vel, ch.
        table.remove(midi_note_history, i)
      end
    end
    
    for i = #disting_note_history, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      disting_note_history[i][1] = disting_note_history[i][1] - 1
      if disting_note_history[i][1] == 0 then
        -- print('note_off')
        crow.ii.disting.note_off(disting_note_history[i][2])
        table.remove(disting_note_history, i)
      end
    end
    
    for i = #engine_note_history, 1, -1 do
      engine_note_history[i][1] = engine_note_history[i][1] - 1
      if engine_note_history[i][1] == 0 then
        table.remove(engine_note_history, i)
      end
    end
    
    for i = #crow_note_history, 1, -1 do
      crow_note_history[i][1] = crow_note_history[i][1] - 1
      if crow_note_history[i][1] == 0 then
        table.remove(crow_note_history, i)
      end
    end
    
    for i = #jf_note_history, 1, -1 do
      jf_note_history[i][1] = jf_note_history[i][1] - 1
      if jf_note_history[i][1] == 0 then
        table.remove(jf_note_history, i)
      end
      
    end
  end
end
    
    
function clock.transport.start(sync_value)
  -- little check for MIDI because user can technically start and stop as per usual and we don't want to restart coroutine
  if not (params:string('clock_source') == 'midi' and transport_active) then
    if params:get('seq_start_on_1') == 1 then -- Seq end
      play_seq = true
    end
    start = true
    stop = false -- 2023-07-19 added so when arranger stops in 1-shot and then external clock stops, it doesn't get stuck
    transport_active = true

    -- Clock for chord/seq/arranger sequences
    sequence_clock_id = clock.run(sequence_clock, sync_value)
  
    -- -- Clock used to refresh arranger countdown timer 10x a second
    -- -- resetting does not seem to be necessary but I figure it will result in better countdown timing?
    -- metro.free(countdown_timer.id)
    -- countdown_timer:start()
  end
end


-- only used for external clock messages. Otherwise we just set stop directly
function clock.transport.stop()
  stop = true
end


function reset_pattern() -- todo: Also have the chord readout updated (move from advance_chord_pattern to a function)
  transport_state = 'stopped'
  print(transport_state)
  pattern_queue = false
  seq_pattern_position = 0
  chord_pattern_position = 0
  reset_clock()
  get_next_chord()
  chord_raw = next_chord
  gen_dash('reset_pattern')
  grid_redraw()
  redraw()
end


function reset_arrangement() -- todo: Also have the chord readout updated (move from advance_chord_pattern to a function)
  arranger_queue = nil
  arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
  arranger_position = 0
  if arranger[1] > 0 then set_chord_pattern(arranger[1]) end
  if params:string('arranger') == 'On' then arranger_active = true end
  reset_pattern()
end


function reset_clock()
  clock_step = -1
  -- Immediately update this so if Arranger is zeroed we can use the current-set pattern (even if paused)
  gen_arranger_padded()
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
  clock_start_method = 'start'
  start = true
end


function advance_chord_pattern()
  chord_pattern_retrig = true -- indicates when we're on a new chord seq step for CV harmonizer auto-rest logic
  local seq_start_on_1 = params:get('seq_start_on_1')
  local seq_reset_on_1 = params:get('seq_reset_on_1')
  local arrangement_reset = false

  -- Advance arranger sequence if enabled
  if params:string('arranger') == 'On' then

    -- If it's post-reset or at the end of chord sequence
    -- TODO: Really need a global var for when in a reset state (arranger_position == 0 and chord_pattern_position == 0)
    if (arranger_position == 0 and chord_pattern_position == 0) or chord_pattern_position >= chord_pattern_length[active_chord_pattern] then
      
      -- This variable is only set when the 'arranger' param is 'On' and we're moving into a new Arranger segment (or after reset)
      arranger_active = true
      
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        arrangement_reset = true
        reset_arrangement()
        stop = true
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
    arranger_ending()
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
      gen_dash('advance_chord_pattern')
    end
    
    update_chord()

    -- Play the chord
    if chord_pattern[active_chord_pattern][chord_pattern_position] > 0 then
      play_chord(params:string('chord_output'), params:get('chord_midi_ch'))
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
    
    if seq_start_on_1 == 2 then play_seq = true end -- Step
    
    if chord_key_count == 0 then

      -- todo p0 temporarily setting chord readout to only show triad until new glyphs are added and we have time to review. Technically this is fine since triad or 7th is defined per voice.
      chord_no = current_chord_c + ((params:get('chord_type') + 2) == 4 and 7 or 0) -- used for chord readout, distinguishing between triad and 7ths
      -- chord_no = current_chord_c -- used for chord readout, distinguishing between triad and 7ths. todo p1 simplify if sticking with triad readout

      gen_chord_readout()
    end

  end
end


function arranger_ending()
  arranger_one_shot_last_pattern = 
  arranger_position >= arranger_length 
  and params:string('playback') == '1-shot'
  and (arranger_queue == nil or arranger_queue > arranger_length)
end


-- Checks each time arrange_enabled param changes to see if we need to also immediately set the corresponding arranger_active var to false. arranger_active will be false until Arranger is re-synched/resumed.
-- Also sets pattern_queue to false to clear anything previously set
function update_arranger_active()
  if params:string('arranger') == 'Off' then 
    arranger_active = false
  elseif params:string('arranger') == 'On' then
    if chord_pattern_position == 0 then arranger_active = true end
    pattern_queue = false
  end
  gen_dash('update_arranger_active')
end  


function do_events()
  if arranger_position == 0 then
    print('arranger_position = 0')
  end
  
  if chord_pattern_position == 0 then
    print('chord_pattern_position = 0')
  end  
  
  if events[arranger_position] ~= nil then
    if events[arranger_position][chord_pattern_position].populated or 0 > 0 then
      for i = 1, 16 do
        local event_path = events[arranger_position][chord_pattern_position][i]
        if event_path ~= nil and math.random(1, 100) <= event_path.probability then
          local event_type = event_path.event_type
          local event_name = event_path.id
          local value = event_path.value or ''
          local limit = event_path.limit  -- can be 'events_op_limit' or, for Random op, 'events_op_limit_random'
          local limit_min = event_path.limit_min
          local limit_max = event_path.limit_max
          local operation = event_path.operation
          local action = event_path.action or nil
          local action_var = event_path.action_var or nil
          
          if event_type == 'param' then
            if operation == 'Set' then
              params:set(event_name, value)
            elseif operation == 'Increment' then
              if limit == 'Clamp' then
                params:set(event_name, util.clamp(params:get(event_name) + value, limit_min, limit_max))
              elseif limit == 'Wrap' then
                params:set(event_name, util.wrap(params:get(event_name) + value, limit_min, limit_max))
              else
                params:set(event_name, params:get(event_name) + value)
              end  
            elseif operation == 'Wander' then
              if limit == 'Clamp' then
                params:set(event_name, util.clamp(params:get(event_name) + cointoss_inverse(value), limit_min, limit_max))
              elseif limit == 'Wrap' then
                params:set(event_name, util.wrap(params:get(event_name) + cointoss_inverse(value), limit_min, limit_max))
              else
                params:set(event_name, params:get(event_name) + cointoss_inverse(value))
              end  
            elseif operation == 'Random' then
              if limit == 'On' then
                local rand = math.random(limit_min, limit_max)
                -- print('Event randomization (limited) value ' .. event_name .. ' to ' .. rand)
                params:set(event_name, rand)
              else
                -- This makes sure we pick up the latest range in case it has changed since event was saved (pset load)
                local rand = math.random(event_range[1], event_range[2])
                -- print('Event randomization value ' .. event_name .. ' to ' .. rand)                
                params:set(event_name, rand)
              end
            -- IMPORTANT: CURRENTLY USING ADD_BINARY IN PLACE OF ADD_TRIGGER FOR PMAP SUPPORT. WILL LIKELY NEED ALTERNATE LOGIC FOR TRUE TRIGGER PARAM.
            elseif operation == 'Trigger' then
              params:set(event_name, 1)
              params:set(event_name, 0)
            end
          else -- functions
            -- currently the only function ops are Trigger and Discreet. So we just need to have a check for Random. Will likely need to expand this later.
            if operation == 'Random' then
              if limit == 'On' then
                local value = math.random(limit_min, limit_max)
                _G[event_name](value)
                
                -- currently not using actions other than param actions which will fire automatically.
                -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
                if action ~= nil then
                  _G[action](action_var)
                end                
              else
                -- This makes sure we pick up the latest range in case it has changed since event was saved (pset load)
                local value = math.random(event_range[1], event_range[2])
                _G[event_name](value)
                
                -- currently not using actions other than param actions which will fire automatically.
                -- todo: if/when param actions are set up this needs to be replicated (or a global var used) to pick up random/wander values
                if action ~= nil then
                  _G[action](action_var)
                end                    
              end
            else
              _G[event_name](value)
            end
          end
        end
      end
    end
  end
end


-- todo p2: More thoughtful display of either sharps or flats depending on mode and key
function gen_chord_readout()
  if chord_no > 0 then
    local chord_degree = MusicUtil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_no]  -- Adding 7 to index returns 7th variants
    if params:string('chord_readout') == 'Degree' then
      chord_readout = chord_degree
    else -- chord name
      local chord_name = MusicUtil.NOTE_NAMES[util.wrap((MusicUtil.SCALES[params:get('mode')]['intervals'][util.wrap(chord_no, 1, 7)] + 1) + params:get('transpose'), 1, 12)]
      local modifier = get_chord_name(1 + 1, params:get('mode'), chord_degree)
      chord_readout = (chord_name .. modifier)
      -- print('chord_name ' .. chord_name .. modifier .. '  ' .. chord_degree)
    end
  end
end  


function update_chord()
-- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord. 
-- Mode is always updated in case no chord has been set but user has changed Mode param.
  current_chord_x = chord_pattern[active_chord_pattern][chord_pattern_position] > 0 and chord_pattern[active_chord_pattern][chord_pattern_position] or current_chord_x
  current_chord_o = chord_pattern[active_chord_pattern][chord_pattern_position] > 0 and (chord_pattern[active_chord_pattern][chord_pattern_position] > 7 and 1 or 0) or current_chord_o
  current_chord_c = chord_pattern[active_chord_pattern][chord_pattern_position] > 0 and util.wrap(chord_pattern[active_chord_pattern][chord_pattern_position], 1, 7) or current_chord_c
  
  -- always includes 7th note since this will be used by seq, harmonizers
  chord_raw = MusicUtil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  
  -- chord transformations
  -- densify_chord()
  invert_chord()
  spread_chord()  
end

-- First step in creating chord_transformed is to add notes until we've reached chord_density param
-- todo call from invert_chord so we can add densification param + inversion for whatever notes are needed
function densify_chord(density) --todo arg
  local notes_in_chord = (params:get('chord_type') + 2)
  -- local density = params:get('chord_density')
  chord_transformed = {}
  for i = 1, notes_in_chord + density do
    local octave = math.ceil(i / notes_in_chord) - 1
    chord_transformed[i] = chord_raw[util.wrap(i, 1, notes_in_chord)] + (i > notes_in_chord and (octave * 12) or 0)
  end
end

-- Applies a sort of inversion by rotating lowest note up to highest octave
function invert_chord()
  -- chord_transformed = {}
  -- for i = 1, (params:get('chord_type') + 2) do
  --   chord_transformed[i] = chord_raw[i]
  -- end
  
  -- todo: can't just add an octave because that spot may already be filled by density
  -- maybe just re-run densify and pass an arg to add x notes, then remove x notes from table beginning from start
  -- local offset = math.ceil(chord_transformed[#chord_transformed] / 12) * 12

  -- if params:get('chord_inversion') ~= 0 then
  --   for i = 1, params:get('chord_inversion') do
  --     local index = util.wrap(i, 1, #chord_transformed)
  --     chord_transformed[index] = chord_transformed[index] + offset
  --   end
  --   -- Re-sort them for next step (spread)
  --   table.sort(chord_transformed)
  -- end
  densify_chord(params:get('chord_density') + params:get('chord_inversion'))
  for i = 1, params:get('chord_inversion') do
    table.remove(chord_transformed, 1)
  end  
end  


-- Applies note spread to chord (in octaves)
-- todo might be better to change so 'Spread' increases density by default then you can pare down with a max 'Density' (rather than spreading in octaves)
function spread_chord()
  if params:get('chord_spread') ~= 0 then
    for i = 1, #chord_transformed do
      -- chord_transformed[i] = chord_transformed[i] + round((params:get('chord_spread') / (params:get('chord_type') + 1) * (i - 1))) * 12
      -- + round((spread / notes-1 * (i - 1))) * 12
      chord_transformed[i] = chord_transformed[i] + math.floor(((params:get('chord_spread') + 1) / #chord_transformed * (i - 1))) * 12
    end
  end
end


-- This triggers when mode param changes and allows seq and harmonizers to pick up the new mode immediately. Doesn't affect the chords and doesn't need chord transformations since the chord advancement will overwrite
function update_chord_action()
  chord_raw = MusicUtil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  next_chord = MusicUtil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
end


function play_chord(destination, channel)
  local destination = params:string('chord_output')
  if destination == 'Engine' then
    
    local amp = params:get('chord_pp_amp') / 100
    local cutoff = params:get('chord_pp_tracking') *.01
    local tracking = params:get('chord_pp_cutoff')
    local release = duration_sec(chord_duration)
    local gain = params:get('chord_pp_gain') / 100
    local pw = params:get('chord_pp_pw') / 100

    for i = 1, #chord_transformed do --(params:get('chord_type') + 2) do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_engine(note, amp, cutoff, tracking, release, gain, pw)
    end
    
  elseif destination == 'MIDI' then
    local channel = params:get('chord_midi_ch')
    local port = params:get('chord_midi_out_port')
    for i = 1, #chord_transformed do --(params:get('chord_type') + 2) do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_midi(note, params:get('chord_midi_velocity'), channel, chord_duration, port)
    end
  -- elseif destination == 'Crow' then -- todo p3 not yet a valid option
  
  elseif destination =='ii-JF' then
    for i = 1, #chord_transformed do --(params:get('chord_type') + 2) do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_jf(note, params:get('chord_jf_amp')/10)
    end
    
  elseif destination == 'Disting' then
    for i = 1, #chord_transformed do --(params:get('chord_type') + 2) do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_disting(note, params:get('chord_disting_velocity'), chord_duration)
    end    
  end
end


-- Pre-load upcoming chord to address race condition around map_note() events occurring before chord change
function get_next_chord()
  local pre_arrangement_reset = false
  local pre_arranger_position = arranger_position
  local pre_arranger_retrig = arranger_retrig
  local pre_chord_pattern_position = chord_pattern_position
  local pre_pattern_queue = pattern_queue
        pre_pattern = active_chord_pattern

  -- Move arranger sequence if On
  if params:get('arranger') == 2 then

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
      next_chord = MusicUtil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
    
  end
end


function map_note_1(note_num, octave, pre) -- triad chord mapping
  local chord_length = 3
  local quantized_note = pre == true and next_chord[util.wrap(note_num, 1, chord_length)] or chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((octave + quantized_octave) * 12) + params:get('transpose'))
end


function map_note_2(note_num, octave, pre) -- 7th chord mapping
  local chord_length = 4
  local quantized_note = pre == true and next_chord[util.wrap(note_num, 1, chord_length)] or chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((octave + quantized_octave) * 12) + params:get('transpose'))
end


function map_note_3(note_num, octave, pre)  -- mode mapping + diatonic transposition
  local diatonic_transpose = (pre == true and next_chord_x or current_chord_x) -1
  local quantized_note = notes_nums[note_num + diatonic_transpose]
  return(quantized_note + (octave * 12) + params:get('transpose'))
end


function map_note_4(note_num, octave) -- mode mapping
  local quantized_note = notes_nums[note_num]
  return(quantized_note + (octave * 12) + params:get('transpose'))
end


function advance_seq_pattern()
  if seq_pattern_position > seq_pattern_length[active_seq_pattern] or arranger_retrig == true then
    seq_pattern_position = 1
  else  
    seq_pattern_position = util.wrap(seq_pattern_position + 1, 1, seq_pattern_length[active_seq_pattern])
  end

  if seq_pattern[active_seq_pattern][seq_pattern_position] > 0 then
    
    local destination = params:string('seq_output_1')
    
    local note = _G['map_note_' .. params:get('seq_note_map_1')](seq_pattern[active_seq_pattern][seq_pattern_position], params:get('seq_octave_1'))
    
    if destination == 'Engine' then
      local amp = params:get('seq_pp_amp_1') / 100
      local cutoff = params:get('seq_pp_tracking_1') *.01
      local tracking = params:get('seq_pp_cutoff_1')
      local release = duration_sec(seq_duration)
      local gain = params:get('seq_pp_gain_1') / 100
      local pw = params:get('seq_pp_pw_1') / 100
      to_engine(note, amp, cutoff, tracking, release, gain, pw)

    elseif destination == 'MIDI' then
      local channel = params:get('seq_midi_ch_1')
      local port = params:get('seq_midi_out_port_1')
      to_midi(note, params:get('seq_midi_velocity_1'), channel, seq_duration, port)
    elseif destination == 'Crow' then
      if params:get('seq_tr_env_1') == 2 then  -- Trigger
        to_crow(note,'pulse(.001,10,1)') -- (time,level,polarity)
      else -- envelope
        local crow_attack = duration_sec(seq_duration) * params:get('seq_ad_skew_1') / 100
        local crow_release = duration_sec(seq_duration) * (100 - params:get('seq_ad_skew_1')) / 100
        to_crow(note, 'ar(' .. crow_attack .. ',' .. crow_release .. ',10)')  -- (attack,release,shape) SHAPE is bugged?
      end
    elseif destination == 'ii-JF' then
      to_jf(note, params:get('seq_jf_amp_1')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('seq_disting_velocity_1'), seq_duration)
    end
  end
  
  if seq_pattern_position >= seq_pattern_length[active_seq_pattern] then
    local seq_start_on_1 = params:get('seq_start_on_1')
    if seq_start_on_1 ~= 1 then -- seq end
      play_seq = false
      -- if seq_start_on_1 == 4 then -- Only reset if we're currently in Event start_on mode. Could go either way here.
      --   seq_1_shot_1 = false
      -- end
     end
  end   
end


-- cv harmonizer input
function sample_crow(volts)
  local note = _G['map_note_' .. params:get('crow_note_map')](round(volts * 12, 0) + 1, params:get('crow_octave'), params:get('chord_preload') ~= 0) 
  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_pattern_retrig == true
  or params:get('crow_auto_rest') == 1
  or (params:get('crow_auto_rest') == 2 and (prev_note ~= note)) then
    -- Play the note
    local destination = params:string('crow_output')
    if destination == 'Engine' then
      local amp = params:get('crow_pp_amp') / 100
      local cutoff = params:get('crow_pp_tracking') *.01
      local tracking = params:get('crow_pp_cutoff')
      local release = duration_sec(crow_duration)
      local gain = params:get('crow_pp_gain') / 100
      local pw = params:get('crow_pp_pw') / 100
      to_engine(note, amp, cutoff, tracking, release, gain, pw)
      
    elseif destination == 'MIDI' then
      local channel = params:get('crow_midi_ch')
      local port = params:get('crow_midi_out_port')
      to_midi(note, params:get('crow_midi_velocity'), channel, crow_duration, port)
    elseif destination == 'Crow' then
      if params:get('crow_tr_env') == 2 then  -- Trigger
        to_crow(note,'pulse(.001,10,1)') -- (time,level,polarity)
      else -- envelope
        local crow_attack = duration_sec(crow_duration) * params:get('crow_ad_skew') / 100
        local crow_release = duration_sec(crow_duration) * (100 - params:get('crow_ad_skew')) / 100
        to_crow(note, 'ar(' .. crow_attack .. ',' .. crow_release .. ',10)')  -- (attack,release,shape) SHAPE is bugged?
      end
    elseif destination =='ii-JF' then
      to_jf(note, params:get('crow_jf_amp')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('crow_disting_velocity'), crow_duration)      
    end
  end
  
  prev_note = note
  chord_pattern_retrig = false -- Resets at chord advance
end


--midi harmonizer input
midi_event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then

    local note = _G['map_note_' .. params:get('midi_note_map')](d.note - 35, params:get('midi_octave'), params:get('chord_preload') ~= 0) 
    local destination = params:string('midi_output')
    if destination == 'Engine' then
      local amp = params:get('midi_pp_amp') / 100
      local cutoff = params:get('midi_pp_tracking') *.01
      local tracking = params:get('midi_pp_cutoff')
      local release = duration_sec(midi_duration)
      local gain = params:get('midi_pp_gain') / 100
      local pw = params:get('midi_pp_pw') / 100
      to_engine(note, amp, cutoff, tracking, release, gain, pw)
    elseif destination == 'MIDI' then
      local channel = params:get('midi_midi_ch')
      local port = params:get('midi_midi_out_port')
      to_midi(note, params:get('midi_velocity_passthru') == 2 and d.vel or params:get('midi_midi_velocity'), channel, midi_duration, port)
    elseif destination == 'Crow' then
      if params:get('crow_tr_env') == 2 then  -- Trigger
        to_crow(note,'pulse(.001,10,1)') -- (time,level,polarity)
      else -- envelope
        local crow_attack = duration_sec(midi_duration) * params:get('midi_ad_skew') / 100
        local crow_release = duration_sec(midi_duration) * (100 - params:get('midi_ad_skew')) / 100
        to_crow(note, 'ar(' .. crow_attack .. ',' .. crow_release .. ',10)')  -- (attack,release,shape) SHAPE is bugged?
      end
    elseif destination =='ii-JF' then
      to_jf(note, params:get('midi_jf_amp')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('midi_disting_velocity'), midi_duration)      
    end
  end
end
  

function to_engine(note, amp, cutoff, tracking, release, gain, pw)
  local note_on_time = util.time()
  engine_play_note = true
  engine_note_history_insert = true  

  -- Check for duplicate notes and process according to dedupe_threshold setting
  for i = 1, #engine_note_history do
    if engine_note_history[i][2] == note then
      engine_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:get('dedupe_threshold') > 1 and (note_on_time - engine_note_history[i][3]) < dedupe_threshold_s then
        engine_play_note = false
      end
    end
  end
  
  if engine_play_note == true then
    -- PolyPerc crashes if sent >24000 hz!!!
    note_hz = math.min(MusicUtil.note_num_to_freq(note + 36), 24000)
    engine.amp(amp)
    engine.cutoff(note_hz * cutoff + tracking)
    engine.release(release)
    engine.gain(gain)
    engine.pw(pw)
    engine.hz(note_hz)
  end
  
  if engine_note_history_insert == true then
    -- Subbing dedupe_threshold_int for duration for engine out. Only used to make sure record is kept long enough to do a dedupe check
    table.insert(engine_note_history, {dedupe_threshold_int, note, note_on_time})    
  end
end
  
  
function to_midi(note, velocity, channel, duration, port)

  local midi_note = note + 36
  local note_on_time = util.time()
  midi_play_note = true
  midi_note_history_insert = true
  
  -- Check for duplicate notes and process according to dedupe_threshold setting
  for i = 1, #midi_note_history do
    if midi_note_history[i][2] == midi_note and midi_note_history[i][5] == port and midi_note_history[i][3] == channel then
      -- Preserves longer note-off duration to avoid weirdness around a which-note-was first race condition. Ex: if a sustained chord and a staccato note play at approximately the same time, the chord's note will sustain without having to worry about which came first. This does require some special handling below which is not present in other destinations.
      
      midi_note_history[i][1] = math.max(duration, midi_note_history[i][1])
      midi_note_history_insert = false -- Don't insert a new note-off record since we just updated the duration

      if params:get('dedupe_threshold') > 1 and (note_on_time - midi_note_history[i][4]) < dedupe_threshold_s then
        -- print(('Deduped ' .. note_on_time - midi_note_history[i][4]) .. ' | ' .. dedupe_threshold_s)
        midi_play_note = false -- Prevent duplicate note from playing
      end
    
      -- Always update any existing note_on_time, even if a note wasn't played. 
      -- Otherwise the note duration may be extended but the gap between note_on_time and current time grows indefinitely and no dedupe occurs.
      -- Alternative is to not extend the duration when dedupe_threshold > 0 and a duplicate is found
      midi_note_history[i][4] = note_on_time
    end
  end

  -- if note is already playing, send a note-off before note_on is sent again
  -- else add note into midi_note_history_insert to be turned off later
  if midi_note_history_insert == false then
    midi_device[port]:note_off((midi_note), 0, channel)
  else
    table.insert(midi_note_history, {duration, midi_note, channel, note_on_time, port})
  end
  -- Play note
  if midi_play_note == true then
    midi_device[port]:note_on((midi_note), velocity, channel)
  end
end


function to_crow(note, action)
  local note_on_time = util.time()
  crow_play_note = true
  crow_note_history_insert = true

  -- Check for duplicate notes and process according to dedupe_threshold setting
  for i = 1, #crow_note_history do
    if crow_note_history[i][2] == note then
      crow_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:get('dedupe_threshold') > 1 and (note_on_time - crow_note_history[i][3]) < dedupe_threshold_s then
        crow_play_note = false
      end
    end
  end

  --Play the note
  -- todo: revisit after Crow 4.x bugs are worked out
  if crow_play_note == true then
    crow.output[1].volts = (note) / 12
    crow.output[2].volts = 0  -- Needed or skew 100 AD gets weird
    crow.output[2].action = action
    crow.output[2]()
  end
  
  -- Insert note-off into the queue
  if crow_note_history_insert == true then
    -- Subbing dedupe_threshold_int for duration for crow out. Only used to make sure record is kept long enough to do a dedupe check.
    table.insert(crow_note_history, {dedupe_threshold_int, note, note_on_time})
  end
end


--todo p2 check JF code and/or with Trent to see if there is a calc we can use rather than the regression
function est_jf_time()
  crow.ii.jf.get ('time') --populates jf_time global
  
  jf_time_hold = clock.run(
    function()
      clock.sleep(0.005) -- a small hold for usb round-trip
      local jf_time_s = math.exp(-0.694351 * jf_time + 3.0838) -- jf_time_v_to_s.
      print('jf_time_s = ' .. jf_time_s)
      -- return(jf_time_s)   
      end
  )
  
end


function to_jf(note, amp)
  local note_on_time = util.time()
  jf_play_note = true
  jf_note_history_insert = true 

  -- Check for duplicate notes and process according to dedupe_threshold setting
  for i = 1, #jf_note_history do
    if jf_note_history[i][2] == note then
      jf_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:get('dedupe_threshold') > 1 and (note_on_time - jf_note_history[i][3]) < dedupe_threshold_s then
        jf_play_note = false
      end
    end
  end
  
  if jf_play_note == true then
    crow.ii.jf.play_note((note - 24)/12, amp)
  end
  
  if jf_note_history_insert == true then
    -- Subbing dedupe_threshold_int for duration for engine out. Only used to make sure record is kept long enough to do a dedupe check
  table.insert(jf_note_history, {dedupe_threshold_int, note, note_on_time})    
  end
end


function to_disting(note, velocity, duration)
  local disting_note = note + 24
  local note_on_time = util.time()
  disting_play_note = true
  disting_note_history_insert = true
  
  -- Check for duplicate notes and process according to dedupe_threshold setting
  for i = 1, #disting_note_history do
    if disting_note_history[i][2] == disting_note then

      -- Preserves longer note-off duration to avoid weirdness around a which-note-was first race condition. Ex: if a sustained chord and a staccato note play at approximately the same time, the chord's note will sustain without having to worry about which came first. This does require some special handling below.
      disting_note_history[i][1] = math.max(duration, disting_note_history[i][1])
      disting_note_history_insert = false -- Don't insert a new note-off record since we just updated the duration

      if params:get('dedupe_threshold') > 1 and (note_on_time - disting_note_history[i][3]) < dedupe_threshold_s then
        -- print(('Deduped ' .. note_on_time - midi_note_history[i][4]) .. ' | ' .. dedupe_threshold_s)
        disting_play_note = false -- Prevent duplicate note from playing
      end
    
      -- Always update any existing note_on_time, even if a note wasn't played. 
      -- Otherwise the note duration may be extended but the gap between note_on_time and current time grows indefinitely and no dedupe occurs.
      -- Alternative is to not extend the duration when dedupe_threshold > 0 and a duplicate is found
      disting_note_history[i][3] = note_on_time
    end
  end


 -- if note is already playing, send a note-off before note_on is sent again
  -- else add note into midi_note_history_insert to be turned off later
  if disting_note_history_insert == false then
    table.insert(disting_note_history, {duration, disting_note,  note_on_time})
  else
    crow.ii.disting.note_off(disting_note)    
  end

  -- Play note
  if disting_play_note == true then
    -- print('disting_note ' .. disting_note .. '  |  velocity ' .. velocity)
    crow.ii.disting.note_pitch(disting_note, (disting_note-48)/12)
    crow.ii.disting.note_velocity(disting_note, velocity/10)
  end

end


function grid_redraw()
  g:all(0)
  
  -- Events supercedes other views
  if screen_view_name == 'Events' then

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
    if grid_view_name == 'Arranger' then
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
              -- if x == 3 then print('2') end
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
  

      g:led(1, 8 + extra_rows, params:get('arranger') == 2 and 15 or 4)
      g:led(2, 8 + extra_rows, params:get('playback') == 2 and 15 or 4)
        
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
    elseif grid_view_name == 'Chord' then
      if params:string('arranger') == 'On' and arranger_one_shot_last_pattern == false then
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
      
      g:led(16, 7 + extra_rows, 15)                                                  -- grid view selector
      
      -- chord playhead
      local chord_pattern_position_offset = chord_pattern_position - pattern_grid_offset
      -- fix for Midigrid which was breaking when drawing out-of-bounds. todo: check if this is still necessary
      if chord_pattern_position_offset > 0 and chord_pattern_position_offset <= rows then
        for i = 1, 14 do                                                               
          g:led(i, chord_pattern_position - pattern_grid_offset, 3)
        end
      end
      
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
    elseif grid_view_name == 'Seq' then
      g:led(16, 8 + extra_rows, 15)
      
      -- seq playhead
      local seq_pattern_position_offset = seq_pattern_position - pattern_grid_offset
      -- fix for Midigrid which was breaking when drawing out-of-bounds. todo: check if this is still necessary
      -- if seq_pattern_position_offset >= math.max(1, pattern_grid_offset) and seq_pattern_position_offset <= rows then
      if seq_pattern_position_offset > 0 and seq_pattern_position_offset <= rows then
        for i = 1, 14 do                                                               
          g:led(i, seq_pattern_position - pattern_grid_offset, 3)
        end
      end
      
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
function g.key(x,y,z)
  if z == 1 then

    if screen_view_name == 'Events' then
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
            event_edit_status = '(New)'
            -- print('setting event_edit_status to ' .. event_edit_status)
          else
            event_edit_status = '(Saved)'
            -- print('setting event_edit_status to ' .. event_edit_status)
          end

          -- If the event is populated, Load the Event vars back to the displayed param. Otherwise keep the last touched event's settings so we can iterate quickly.
          if events[event_edit_segment][y + pattern_grid_offset][x] ~= nil then

            events_index = 1
            selected_events_menu = events_menus[events_index]

            local id = events_path.id
            local index = events_lookup_index[id]
            local value = events_path.value
            local operation = events_path.operation
            local limit = events_path.limit or 'Off'

            params:set('event_category', param_option_to_index('event_category', events_lookup[index].category))
            change_category()
            params:set('event_subcategory', param_option_to_index('event_subcategory', events_lookup[index].subcategory))
            params:set('event_name', index)
            change_event()
            params:set('event_operation', param_option_to_index('event_operation', operation))
            if operation == 'Random' then
              params:set('event_op_limit_random', param_option_to_index('event_op_limit_random', limit))
            else
              params:set('event_op_limit', param_option_to_index('event_op_limit', limit))
            end
            if limit ~= 'Off' then
              params:set('event_op_limit_min', events_path.limit_min)
              params:set('event_op_limit_max', events_path.limit_max)
            end
            if value ~= nil then params:set('event_value', value) end -- triggers don't save
            params:set('event_probability', events_path.probability)
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
              -- print('incrementing segment populated')
              events[event_edit_segment].populated = (events[event_edit_segment].populated or 0) + 1
            end
          end
          
          print('Copy+paste event from segment ' .. event_edit_segment .. '.' .. event_edit_step .. ' lane ' .. event_edit_lane  .. ' to ' .. event_edit_segment .. '.' .. (y + pattern_grid_offset) .. ' lane ' .. x)
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
        --todo p0 check if grid_view_keys are being set correctly for all sizes
        elseif view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
          screen_view_name = 'Chord+seq'
        end
      end
      
    --ARRANGER KEY DOWN-------------------------------------------------------
    elseif grid_view_name == 'Arranger' then
      local x_offset = x + arranger_grid_offset

      -- enable/disable Arranger
      if x == 1 and y == 8 + extra_rows then
        if params:get('arranger') == 1 then
          params:set('arranger', 2)
        else
          params:set('arranger', 1)
        end

      -- Switch between Arranger playback Loop or 1-shot mode
      elseif x == 2 and y == 8 + extra_rows then
        if params:get('playback') == 2 then
          params:set('playback', 1)
        else
          params:set('playback', 2)
        end
        
      -- Arranger pagination jumps
      elseif y == 8 + extra_rows then
        if x > 6 and x < 11 then
          arranger_grid_offset = (x - 7) * 16
        end
        
      
      -- ARRANGER SEGMENT CHORD PATTERNS
      elseif y < 5 and interaction ~= 'arranger_shift' then
        if y == arranger[x_offset] then
          arranger[x_offset] = 0
        else
          arranger[x_offset] = y
        end
        gen_arranger_padded()
        
        -- allow pasting of events while setting patterns (but not the other way around)
        if interaction == 'event_copy' then
          events[x_offset] = deepcopy(events[event_edit_segment])
          print('Copy+paste events from segment ' .. event_edit_segment .. ' to segment ' .. x)
          gen_dash('Event copy+paste')
        end
        
      -- ARRANGER EVENTS TIMELINE KEY DOWN
      elseif y == 5 then
        arranger_loop_key_count = arranger_loop_key_count + 1
        if interaction ~= 'arranger_shift' then -- nil then
          interaction = 'event_copy'  
          -- First touched pattern is the one we edit, effectively resetting on key_count = 0
          if arranger_loop_key_count == 1 then
            event_edit_segment = x_offset
  
          -- Subsequent keys down paste all arranger events in segment, but not the segment pattern
          -- arranger shift interaction will block this
          -- implicit here that more than 1 key is held down so we're pasting
          else
            events[x_offset] = deepcopy(events[event_edit_segment])
            print('Copy+paste events from segment ' .. event_edit_segment .. ' to segment ' .. x)
            gen_dash('Event copy+paste')
          end
        end
      end
      
    --CHORD PATTERN KEYS
    elseif grid_view_name == 'Chord' then

      if x < 15 then
        chord_key_count = chord_key_count + 1
        if x == chord_pattern[active_chord_pattern][y + pattern_grid_offset] then
          chord_pattern[active_chord_pattern][y + pattern_grid_offset] = 0
        else
          chord_pattern[active_chord_pattern][y + pattern_grid_offset] = x
        end
        chord_no = util.wrap(x, 1, 7) + ((params:get('chord_type') + 2) == 4 and 7 or 0) -- or 0
        gen_chord_readout()
        
      -- set chord_pattern_length  
      elseif x == 15 then
        params:set('chord_pattern_length', y + pattern_grid_offset)
        gen_dash('g.key chord_pattern_length')
      

      elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher.
        interaction = 'chord_pattern_copy'
        pattern_key_count = pattern_key_count + 1
        pattern_keys[y] = 1
        if pattern_key_count == 1 then
          pattern_copy_source = y
        elseif pattern_key_count > 1 then
          print('Copying pattern ' .. pattern_copy_source .. ' to pattern ' .. y)
          pattern_copy_performed = true
          for i = 1, max_chord_pattern_length do
            chord_pattern[y][i] = chord_pattern[pattern_copy_source][i]
          end
          -- If we're pasting to the currently viewed active_chord_pattern, do it via param so we update param + table.
          if y == active_chord_pattern then
            params:set('chord_pattern_length', chord_pattern_length[pattern_copy_source])
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
    elseif grid_view_name == 'Seq' then
      if x < 15 then
        if x == seq_pattern[active_seq_pattern][y + pattern_grid_offset] then
          seq_pattern[active_seq_pattern][y + pattern_grid_offset] = 0
        else
          seq_pattern[active_seq_pattern][y + pattern_grid_offset] = x
          grid_dirty = true
        end
      elseif x == 15 then
        params:set('seq_pattern_length_' .. active_seq_pattern, y + pattern_grid_offset)
      end
    end
    
  --------------
  --G.KEY RELEASED
  --------------
  elseif z == 0 then
    -- Events key up
    if screen_view_name == 'Events' then
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
          screen_view_name = 'Chord+seq'
        else
          screen_view_name = 'Session'  
        end
      else
        screen_view_name = 'Session'
      end

    -- Chord key up      
    elseif grid_view_name == 'Chord' then
      if x == 16 then
        if y <5 then
          pattern_key_count = math.max(pattern_key_count - 1,0)
          pattern_keys[y] = nil
          if pattern_key_count == 0 and pattern_copy_performed == false then
            
            -- Resets current active_chord_pattern immediately if transport is stopped
            if y == active_chord_pattern and transport_active == false then
              print('Manual reset of current pattern; disabling arranger')
              params:set('arranger', 1)
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
              print('Manual jump to queued pattern')
              
              pattern_queue = false
              set_chord_pattern(y)
              seq_pattern_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
              chord_pattern_position = 0
              reset_external_clock()
              reset_pattern()
  
            -- Cue up a new pattern        
            else 
              print('New pattern queued; disabling arranger')
              if pattern_copy_performed == false then
                pattern_queue = y
                params:set('arranger', 1)
              end
            end
          end
        end
        if pattern_key_count == 0 then
          -- print('resetting pattern_copy_performed to false')
          pattern_copy_performed = false
          interaction = nil
        end  
      elseif x < 15 then
        chord_key_count = chord_key_count - 1
        if chord_key_count == 0 then
          -- This reverts the chord readout to the currently loaded chord but it is kinda confusing when paused so now it just wipes and refreshes at the next chord step. Could probably be improved todo p2
          -- chord_no = current_chord_c + ((params:get('chord_type') + 2) == 4 and 7 or 0)          
          -- gen_chord_readout()
          chord_no = 0
        end
      end
    
    
    -- ARRANGER KEY UP
    elseif grid_view_name == 'Arranger' then
      local x_offset = x + arranger_grid_offset -- currently only used 
      
      -- ARRANGER EVENTS TIMELINE KEY UP
      if y == 5 then
        arranger_loop_key_count = math.max(arranger_loop_key_count - 1, 0)
        
        -- Insert/remove patterns/events after arranger shift with K3
        if arranger_loop_key_count == 0 then
          if interaction == 'arranger_shift' then
            apply_arranger_shift()
          end
          interaction = nil
        end
      end
    end

  end
  redraw()
  grid_redraw()
end


-- todo p3 relocated
function apply_arranger_shift()
  if d_cuml > 0 then  -- same as interaction == 'arranger_shift'? todo p2 clean up anywhere this check is used
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
  -- KEY 1 just increments keys and key_count to bring up alt menu (disabled currently but whatever) 
    keys[n] = 1
    key_count = key_count + 1
    if n == 1 then
      -- Fn menu is displayed since keys[1] == 1
      
    -- KEY 2  
    elseif n == 2 then
      -- if keys[1] == 1 then
      -- Not used at the moment
        
      -- Arranger Events strip held down
      if arranger_loop_key_count > 0 and interaction ~= 'arranger_shift' then -- interaction == nil then
        arranger_queue = event_edit_segment
        -- jumping arranger queue cancels pattern change on key up
        -- print('setting arranger_pattern_key_interrupt to TRUE')
        -- arranger_pattern_key_interrupt = true -- don't change pattern on g.key up
        if arranger_queue <= arranger_length then arranger_one_shot_last_pattern = false end -- instantly de-blink glyph
        grid_redraw()
      
      elseif screen_view_name == 'Events' then
       
       
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
          
          redraw()
          
          
        -------------------------------------------
        -- K2 DELETE ALL EVENTS IN SEGMENT
        -------------------------------------------
        else
          event_k2 = true
          clock.run(delete_all_events_segment)
        end
        
        gen_dash('K2 events editor closed') -- update events strip in dash after making changes in events editor
        grid_redraw()
        
        
      ----------------------------------------
      -- Transport controls K2 - STOP/RESET --
      ----------------------------------------
        
      elseif interaction ~= 'arranger_shift' then -- == nil then -- actually seems fine to do transport controls this during arranger shift?

        if params:string('clock_source') == 'internal' then
          -- print('internal clock')
          if transport_state == 'starting' or transport_state == 'playing' then
            stop = true
            transport_state = 'pausing'
            print(transport_state)        
            clock_start_method = 'continue'
          else  --  remove so we can always do a stop (external sync and weird state exceptions) if transport_state == 'pausing' or transport_state == 'paused' then
            reset_external_clock()
            if params:get('arranger') == 2 then
              reset_arrangement()
            else
              reset_pattern()       
            end 
          end
        elseif params:string('clock_source') == 'link' then
          -- print('link clock')
          if transport_state == 'starting' or transport_state == 'playing' then
            link_stop_source = 'norns'
            stop = true
            clock_start_method = 'continue'
            transport_state = 'pausing'
            print(transport_state)
          -- don't let link reset while transport is active or it gets outta sync
          elseif transport_state == 'paused' or transport_state == 'stopped' then --  modified so we can always do a stop when not playing (external sync and weird state exceptions) 
            if params:get('arranger') == 2 then
              reset_arrangement()
            else
              reset_pattern()       
            end
          end
        
          elseif params:string('clock_source') == 'midi' then
          if transport_state == 'starting' or transport_state == 'playing' then
            stop = true
            transport_state = 'pausing'
            print(transport_state)        
            clock_start_method = 'continue'
            -- start = true
          else --  remove so we can always do a stop (external sync and weird state exceptions)  if transport_state == 'pausing' or transport_state == 'paused' then
            reset_external_clock()
            if params:get('arranger') == 2 then
              reset_arrangement()
            else
              reset_pattern()       
            end 
          end
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
        if screen_view_name == 'Chord+seq' then
        
          -- When Chord+Seq Grid View keys are held down, K3 runs Generator (and resets pattern+seq on internal clock)
          generator()

          -- This reset patterns and resynces seq, but only for internal clock. todo p1 think on this. Not great and might be weird with new seq reset logic
          if params:string('clock_source') == 'internal' then
            local prev_transport_state = transport_state
            reset_external_clock()
            -- Don't reset arranger it's confusing if we generate on, say, pattern 3 and then Arranger is reset and we're now on pattern 1.
            reset_pattern()
            if transport_state ~= prev_transport_state then
              transport_state = prev_transport_state
              print(transport_state)
            end
          end
     
        elseif grid_view_name == 'Chord' then       
          chord_generator_lite()
          -- gen_dash('chord_generator_lite') -- will run when called from event but not from keys
        elseif grid_view_name == 'Seq' then       
          seq_generator('run')
        end
      grid_redraw()
      
      ---------------------------------------------------------------------------
      -- Event Editor --
      -- K3 with Event Timeline key held down enters Event editor / function key event editor
      ---------------------------------------------------------------------------        
      elseif arranger_loop_key_count > 0 and interaction ~= 'arranger_shift' then -- interaction == nil then
        pattern_grid_offset = 0
        arranger_loop_key_count = 0
        event_edit_step = 0
        event_edit_lane = 0
        event_edit_active = false
        screen_view_name = 'Events'
        interaction = nil
        grid_redraw()
  
      -- K3 saves event to events
      elseif screen_view_name == 'Events' then

        ---------------------------------------
        -- K3 TO SAVE EVENT
        ---------------------------------------
        if event_edit_active then

          local event_index = params:get('event_name')
          
          -- function or param
          local event_type = events_lookup[event_index].event_type
          local value = params:get('event_value')
          
          -- trigger, discreet, continuous
          local value_type = events_lookup[event_index].value_type
          
          -- Set, Increment, Wander, Random
          local operation = params:string('event_operation') -- changed to id which will need to be looked up and turned into an id
          local action = events_lookup[event_index].action
          local action_var_1 = events_lookup[event_index].action_var
          
          local limit = params:string(operation == 'Random' and 'event_op_limit_random' or 'event_op_limit')
          -- variant for 'Random' op -- todo p1 make sure we can store here and get it loaded into the right param correctly
          -- local limit_random = params:string('event_op_limit_random')
          local limit_min = params:get('event_op_limit_min')
          local limit_max = params:get('event_op_limit_max')
          
          local probability = params:get('event_probability') -- todo p1 convert to 0-1 float?
          
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
          if value_type == 'trigger' then
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                event_type = event_type,
                value_type = value_type,
                operation = operation,  -- sorta redundant but we do use it to simplify reads
                probability = probability
              }
              
            print('Saving to events[' .. event_edit_segment ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> probability = ' .. probability)
            
          elseif operation == 'Set' then
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                value = value, 
                probability = probability
              }
              
            print('Saving to events[' .. event_edit_segment ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')     
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> value = ' .. value)
            print('>> probability = ' .. probability)
              
          elseif operation == 'Random' then
            if limit == 'Off' then -- so clunky yikes
              events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
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
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage
                  limit_min = limit_min,  -- adding
                  limit_max = limit_max,  -- adding
                probability = probability
              }
            end
            
            print('Saving to events[' .. event_edit_segment ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')       
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> limit = ' .. limit)
            if limit ~= 'Off' then
              print('>> limit_min = ' .. limit_min)
              print('>> limit_max = ' .. limit_max)
            end
            print('>> probability = ' .. probability)
           
              
          else --operation == 'Increment' or 'Wander'
           if limit == 'Off' then -- so clunky yikes
            events[event_edit_segment][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
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
            print('Saving to events[' .. event_edit_segment ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')       
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> limit = ' .. limit)
            if limit ~= 'Off' then
              print('>> limit_min = ' .. limit_min)
              print('>> limit_max = ' .. limit_max)            
            end
            print('>> value = ' .. value)
            print('>> probability = ' .. probability)
            
          end
          
          -- Extra fields are added if action is assigned to param/function
          if action ~= nil then
            events[event_edit_segment][event_edit_step][event_edit_lane].action = action
            events[event_edit_segment][event_edit_step][event_edit_lane].action_var_1 = action_var_1
            
            print('>> action = ' .. action)
            print('>> action_var_1 = ' .. (action_var_1 or 'nil'))
          end
          
          -- Back to event overview
          event_edit_active = false
          
          -- If the event key is still being held (so user can copy and paste immediatly after saving it), preserve these vars, otherwise zero
          if event_key_count == 0 then
            event_edit_step = 0
            event_edit_lane = 0
          end
          event_saved = true
          
          grid_redraw()
        
        else
          screen_view_name = 'Session'
          event_key_count = 0
          gen_dash('K3 events saved') -- update events strip in dash after making changes in events editor
          grid_redraw()
        end

      ----------------------------------
      -- Transport controls K3 - PLAY --
      ----------------------------------
      -- Todo p1 need to have a way of canceling a pending pause once transport controls are reworked
      elseif interaction == nil then
        if params:string('clock_source') == 'internal' then
          -- todo p0 evaluate this vs transport_state
          if transport_active == false then
            clock.transport.start()
          else -- we can cancel a pending pause by pressing K3 before it fires
            stop = false
            transport_state = 'playing'
            print(transport_state)            
          end
        elseif params:string('clock_source') == 'midi' then
          if transport_active == false then
            clock.transport.start(1)  -- pass along sync value so we know to sync on the next beat rather than immediately
          else -- we can cancel a pending pause by pressing K3 before it fires
            stop = false
            transport_state = 'playing'
            print(transport_state)            
          end
        elseif params:string('clock_source') == 'link' then
          if transport_active == false then
            -- disabling until issue with internal link start clobbering clocks is addressed
            -- clock.link.start()        
          else -- we can cancel a pending pause by pressing K3 before it fires
            stop = false
            transport_state = 'playing'
            print(transport_state)            
          end
        end
      end
      -----------------------------------
        
    end
  elseif z == 0 then
    keys[n] = nil
    key_count = key_count - 1
    if n == 2 then
      -- reset this for event segment delete countdown
      event_k2 = false
    end
  end
  redraw()
end


-----------------------------------
-- ENCODERS
----------------------------------          
function enc(n,d)
  -- todo p1 more refined switching between clamped and raw deltas depending on the use-case
  -- local d = util.clamp(d, -1, 1)
  
  -- Reserved for scrolling/extending Arranger, Chord, Seq sequences
  if n == 1 then
    local d = util.clamp(d, -1, 1)
    -- ------- SCROLL ARRANGER GRID VIEW--------
    -- if grid_view_name == 'Arranger' then
    --   arranger_grid_offset = util.clamp(arranger_grid_offset + d, 0, max_arranger_length -  16)
    --   grid_redraw()
    -- end
    --------- SCROLL PATTERN VIEWS -----------
      if grid_view_name == 'Chord' or screen_view_name == 'Events' then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_chord_pattern_length -  rows)
      grid_redraw() -- redundant?
  elseif grid_view_name == 'Seq' then
      pattern_grid_offset = util.clamp(pattern_grid_offset + d, 0, max_seq_pattern_length -  rows)
      grid_redraw() -- redundant?
  end
  
  -- n == ENC 2 ------------------------------------------------
  elseif n == 2 then
    if view_key_count > 0 then
      local d = util.clamp(d, -1, 1)
      if (grid_view_name == 'Chord' or grid_view_name == 'Seq') then-- Chord/Seq 
        rotate_pattern(grid_view_name, d)
        grid_redraw()            
      end
   
    elseif screen_view_name == 'Events' and event_saved == false then
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
      if (grid_view_name == 'Chord' or grid_view_name == 'Seq') then-- Chord/Seq 
        transpose_pattern(grid_view_name, d)
        grid_redraw()
      end
        
    ----------------------    
    -- Event editor menus
    ----------------------    
    -- Not using param actions on these since some use dynamic .options which don't reliably fire on changes. Also we want to fire edit_status_edited() on encoder changes but not when params are set elsewhere (loading events etc)
    elseif screen_view_name == 'Events' and event_saved == false then

      if selected_events_menu == 'event_category' then
        if delta_menu(d) then
          change_category()
        end
        
      elseif selected_events_menu == 'event_subcategory' then
        if delta_menu(d) then
          change_subcategory()
        end
        
      elseif selected_events_menu == 'event_name' then
        if delta_menu(d, event_subcategory_index_min, event_subcategory_index_max) then
          change_event()
        end
        
      elseif selected_events_menu == 'event_operation' then
        if delta_menu(d) then
          change_operation()
        end
        
      elseif selected_events_menu == 'event_value' then
        if params:string('event_operation') == 'Set' then
          delta_menu(d, event_range[1], event_range[2]) -- Dynamic event_range lookup. no functions to call here
        elseif params:string('event_operation') == 'Wander' then
          delta_menu(d, 1) -- nil max defaults to 9999
        else
          params:delta(selected_events_menu, d)
          edit_status_edited()
        end
      
      elseif selected_events_menu == 'event_op_limit_min' then
        delta_menu(d, event_range[1], params:get('event_op_limit_max'))

      elseif selected_events_menu == 'event_op_limit_max' then
        delta_menu(d, params:get('event_op_limit_min'), event_range[2])
  
      -- this should work for the remaining event menus that don't need to fire functions: probability, limit, limit_random
      else
        delta_menu(d)
        
      end
      
    --------------------
    -- Arranger shift --  
    --------------------
    elseif grid_view_name == 'Arranger' and arranger_loop_key_count > 0 then
      local d = util.clamp(d, -1, 1)
      -- Arranger segment detail options are on-screen
      -- block event copy+paste, K2 and K3 (arranger jump and event editor)
      -- new global to identify types of user interactions that should block certain other interactions e.g. copy+paste, arranger jump, and entering event editor
      interaction = 'arranger_shift'
      d_cuml = util.clamp(d_cuml + d, -64, 64)
      
      -- an event paste was just performed so block any change on the final key release
      -- todo p2 thought: can probably set a special interaction that works in place of arranger_pattern_key_interrupt
      -- arranger_pattern_key_interrupt = true
      grid_redraw()
  
    elseif screen_view_name == 'Session' then
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
  redraw()
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


---------------------------------------
-- CASCADING EVENTS EDITOR FUNCTIONS --
---------------------------------------
debug_change_functions = false

function change_category()
  local category = params:get('event_category')
  if debug_change_functions then print('1. change_category called') end
  if category ~= prev_category then
  if debug_change_functions then print('  1.1 new category') end
    update_event_subcategory_options('change_category')
    params:set('event_subcategory', 1) -- no action- calling manually on next step
    change_subcategory()
  end
  prev_category = category  -- todo p1 can this be local and persist on next call? I think not.
end


function change_subcategory()
  if debug_change_functions then print('2. change_subcategory called') end
  -- concat this because subcategory string isn't unique and index resets with options swap!
  local subcategory = params:string('event_category') .. params:string('event_subcategory')
  if debug_change_functions then print('  new subcategory = ' .. subcategory .. '  prev_subcategory = ' .. (prev_subcategory or 'nil')) end

  if subcategory ~= prev_subcategory then
    set_event_indices()

    if debug_change_functions then print('  setting event to ' .. events_lookup[event_subcategory_index_min].name) end
    params:set('event_name', event_subcategory_index_min)
    change_event()
  end  
  prev_subcategory = subcategory
end


function change_event() -- index
  local event = params:get('event_name')
  if debug_change_functions then print('3. change_event called') end
  if debug_change_functions then print('   new event: ' .. events_lookup[event].name) end
  if event ~= prev_event then
    update_event_operation_options('change_event')
    
    -- Currently only changing on new event. Changing operation keeps the limit type
    params:set('event_op_limit', 1)
    params:set('event_op_limit_random', 1)

    set_event_range()
    
    -- can also move to set_event_range() but this seems fine
    params:set('event_op_limit_min', event_range[1])
    params:set('event_op_limit_max', event_range[2])
    
    params:set('event_operation', 1) -- no action so call on next line
    change_operation('change_event')  -- pass arg so we can tell change_operation to set values even if op hasn't changed
    params:set('event_probability', 100) -- Only reset probability when event changes
    end
  prev_event = event
end


function change_operation(source)
  if debug_change_functions then print('4. change_operation called') end
  local operation = params:string('event_operation')
  
  -- We also need to set default value if the event changed!
  if source == 'change_event' or operation ~= prev_operation then
    
    -- alternative placement if we want to reset change event_op_limit and event_op_limit_random on both event and op change
    
    if debug_change_functions then print('    setting default values') end

    local event_index = params:get('event_name')
    local value_type = events_lookup[event_index].value_type
    local event_type = events_lookup[event_index].event_type

		-- set default_value for this operation
		if debug_change_functions then print('    event_type = ' .. event_type) end
    if event_type == 'param' then
      if debug_change_functions then print('4.1 param value') end
      if operation == 'Set' then
        --todo p2 if adding more Discreet functions, need to expand on this because it's setting param value on function event types
        local default_value = params:get(events_lookup[event_index].id)
        local default_value = util.clamp(default_value, event_range[1], event_range[2])
        if debug_change_functions then print('5. Set: setting default value to ' .. default_value) end
        params:set('event_value', default_value)
      elseif operation == 'Wander' then
        if debug_change_functions then print('5. Wander: setting default value to ' .. 1) end
        params:set('event_value', 1)
      elseif operation == 'Increment' then
      if debug_change_functions then print('5. Increment: setting default value to ' .. 0) end
      params:set('event_value', 0)
      end
    -- else -- SKIP TRIGGER AND RANDOM!!!
    end
    gen_menu_events()
  end  
  prev_operation = operation
end


-- todo p3 handle with insert/removes or make a lookup table
function gen_menu_events()
  operation = params:string('event_operation')
  if operation == 'Trigger' then
    events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_probability'}
  elseif operation == 'Set' then -- no limits
    events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_operation', 'event_value', 'event_probability'}    
  elseif operation == 'Random' then  -- no value, swap in event_op_limit_random
    if params:string('event_op_limit_random') == 'Off' then
      events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_operation', 'event_op_limit_random', 'event_probability'}
    else
      events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_operation', 'event_op_limit_random', 'event_op_limit_min', 'event_op_limit_max', 'event_probability'} 
    end
  elseif params:string('event_op_limit') == 'Off' then  -- Increment and Wander get it all
    events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_operation', 'event_value', 'event_op_limit', 'event_probability'}
  else
    events_menus =  {'event_category', 'event_subcategory', 'event_name', 'event_operation', 'event_value', 'event_op_limit', 'event_op_limit_min', 'event_op_limit_max', 'event_probability'}    
  end
end
  

-- Running this in change_ events so it only fires if the value actually changes (rather than enc delta'd)
function edit_status_edited()
  if event_edit_status == '(Saved)' then
    event_edit_status = '(Edited)'
    print('setting event_edit_status to ' .. event_edit_status)
  end
end
    
-- Fetches the min and max events_lookup index for the selected subcategory so we know what events are available
function set_event_indices()
  local category = params:string('event_category')
  local subcategory = params:string('event_subcategory')
  event_subcategory_index_min = event_indices[category .. '_' .. subcategory].first_index
  event_subcategory_index_max = event_indices[category .. '_' .. subcategory].last_index
  
  if debug_change_functions then 
    print('  Set event_subcategory_index_min to ' .. event_subcategory_index_min) 
    print('  Set event_subcategory_index_max to ' .. event_subcategory_index_max) 
  end
  
end


-- Sets the min and max ranges for the event param or function. No formatting stuff.
function set_event_range()
  local event_index = params:get('event_name')
  -- Determine if event range should be clamped
  if events_lookup[event_index].event_type == 'param' then
        if events_lookup[event_index].value_type ~= 'trigger' then
          if params:string('event_operation') == 'Increment' then
            event_range = {-9999,9999}
          else -- discreet'
            event_range = params:get_range(params.lookup[events_lookup[event_index].id]) or {-9999, 9999}
          end
        end
  else -- function. May have hardcoded ranges in events_lookup at some point
    event_range = {-9999,9999}
  end
  
  if debug_change_functions then 
    print('  Set event_range[1] to ' .. event_range[1]) 
    print('  Set event_range[2] to ' .. event_range[2]) 
  end  
end  


function get_options(param)
  local options = params.params[params.lookup[param]].options
  return (options)
end


function update_event_subcategory_options(source)
  if debug_change_functions then print('   update_event_subcategory_options called by ' .. (source or 'nil')) end
  swap_param_options('event_subcategory', event_subcategories[params:string('event_category')])
end

function update_event_operation_options(source)
  if debug_change_functions then print('   updating operations on ' .. (params:string('event_name') or 'nil')) end
  swap_param_options('event_operation', _G['event_operation_options_' .. events_lookup[params:get('event_name')].value_type])
end


-- used to set default value of event after init and pset load
function get_default_event_value()  
  if events_lookup[params:get('event_name')].event_type == 'param' then
    return(params.params[params.lookup[events_lookup[params:get('event_name')].id]].default)
  else
    return(0)
  end
end  
  
  
function chord_steps_to_seconds(steps)
  return(steps * 60 / params:get('clock_tempo') / global_clock_div * chord_div) -- switched to var Fix: timing
end


-- -- Truncates hours. Requires integer.
-- function s_to_min_sec(s)
--   local m = math.floor(s/60)
--   -- local h = math.floor(m/60)
--   m = m%60
--   s = s%60
--   return string.format("%02d",m) ..":".. string.format("%02d",s)
-- end


-- Alternative for more digits up to 9 hours LETSGOOOOOOO
function s_to_min_sec(seconds)
  local seconds = tonumber(seconds)
    -- hours = (string.format("%02.f", math.floor(seconds/3600));
    hours_raw = math.floor(seconds/3600);
    hours = string.format("%1.f", hours_raw);
    mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)));
    secs = string.format("%02.f", math.floor(seconds - hours*3600 - mins *60));
    -- Modify hours if it's 2+ digits
    -- hours = hours < 10 and string.format("%2.f",hours) or '>';
    if hours_raw < 10 then
      return hours..":"..mins..":"..secs
    else
      return hours.." hrs"
    end
end


function param_formatter(param)
  if param == 'source' then
    return('Clock:')
  -- elseif param == 'midi out' then
  --   return('Out:')
  else 
    return(param .. ':')
  end
end


-- generates truncated flat tables at the chord step level for the arranger mini dashboard
-- runs any time the arranger changes (generator, events, pattern changes, length changes, key pset load, arranger/pattern reset, event edits)
function gen_dash(source)
  -- print('gen_dash called by ' .. (source or '?'))
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
    -- print('active_pattern = ' .. active_pattern) --todo debug to see if this is always set
    else -- upcoming segments always grab their current values from arranger
      pattern_sticky = arranger_padded[i]
      chord_pattern_length_sticky = chord_pattern_length[pattern_sticky]
      chord_pattern_position_sticky = 1
      steps_remaining_in_pattern = chord_pattern_length[pattern_sticky]
      segment_level = params:get('arranger') == 2 and 15 or 2
    end
    
    -- used to total remaining time in arrangement (beyond what is drawn in the dash)  
    steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
    
    -- todo p3 some sort of weird race condition is happening at init that requires nil check on events
    if events ~= nil and dash_steps < 30 then -- capped so we only store what is needed for the dash (including inserted blanks)
      for s = chord_pattern_position_sticky, chord_pattern_length_sticky do -- todo debug this was letting 0 values through at some point. Debug if errors surface.
        -- if s == 0 then print('s == 0 ' .. chord_pattern_position_sticky .. '  ' .. chord_pattern_length_sticky) end -- p0 debug looking for 0000s
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
  calc_seconds_remaining()
end


--------------------------
-- REDRAW
-------------------------
-- todo p1: this can be improved quite a bit by just having these custom screens be generated at the key/g.key level. Should be a fun refactor.
function redraw()
  screen.clear()
  local dash_x = 94
      
  -- Screens that pop up when g.keys are being held down take priority--------
  -- POP-up g.key tip always takes priority
  if view_key_count > 0 then
    if screen_view_name == 'Chord+seq' then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: rotate ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: transpose ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. CHORDS+SEQ')      

    elseif grid_view_name == 'Arranger' then
      screen.level(15)
      screen.move(2,8)
      -- Placeholder
      -- screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.text(string.upper(grid_view_name) .. ' GRID')
      -- screen.move(2,28)
      -- screen.text('ENC 2: Rotate ↑↓')
      -- screen.move(2,38)
      -- screen.text('ENC 3: Transpose ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
        
    elseif grid_view_name == 'Chord' then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: rotate ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: transpose ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. CHORDS')     
        
     elseif grid_view_name == 'Seq' then --or grid_view_name == 'Seq') then-- Chord/Seq 
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: rotate ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: transpose ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. SEQ')  
      end
      
  -- Arranger shift interaction
  elseif interaction == 'arranger_shift' then
    screen.level(15)
    screen.move(2,8)
    screen.text('ARRANGER SEGMENT ' .. event_edit_segment)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,38)
    screen.text('ENC 3: shift segments ←→')
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()    
  
    
  -- Arranger events timeline held down
  elseif arranger_loop_key_count > 0 then
    screen.level(15)
    screen.move(2,8)
    screen.text('ARRANGER SEGMENT ' .. event_edit_segment)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,28)
    screen.text('Hold+tap: paste events')
    screen.move(2,38)
    screen.text('ENC 3: shift segments ←→')
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()
    screen.level(3)
    screen.move(1,62)
    screen.text('(K2) CUE SEG.')    
    screen.move(82,62)
    screen.text('(K3) EVENTS')

  -- Chord patterns held down
  -- --        elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher. Key UP events farther down in function.
  --       pattern_key_count = pattern_key_count + 1
  --       pattern_keys[y] = 1
  --       if pattern_key_count == 1 then
  --         pattern_copy_source = y
  --       elseif pattern_key_count > 1 then
  --         print('Copying pattern ' .. pattern_copy_source .. ' to pattern ' .. y)
  --         pattern_copy_performed = true
          
  -- tooltips for interacting with chord patterns      
  elseif grid_view_name == 'Chord' and pattern_key_count > 0 then -- add a new interaction for this
    screen.level(15)
    screen.move(2,8)
    screen.text("CHORD PATTERN '" .. pattern_name[pattern_copy_source] .. "'")
    screen.move(2,28)
    -- screen.text('Tap a pattern to paste')
    screen.text('Hold+tap: paste pattern') --. ' .. pattern_name[pattern_copy_source])
    screen.move(2,38)
    screen.text('Release: queue pattern')
    screen.move(2,48)
    -- screen.text('Tap again to force jump')
    screen.text('Tap 2x while stopped: jump')
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
    if screen_view_name == 'Events' then
      screen.level(15)
      screen.move(2,8)
      if event_edit_active == false then
        if key_counter == 4 then
          screen.text('ARRANGER SEGMENT ' .. event_edit_segment .. ' EVENTS')
          screen.level(15)
          screen.move(2,23)
          screen.text('Grid: select event slot')
          screen.move(2,33)
          screen.text('1↓16: chord pattern step')
          screen.move(2,43)
          screen.text('1→16: event order')
          screen.level(4)
          screen.move(1,54)
          screen.line(128,54)
          screen.stroke()
          screen.level(3)      
          screen.move(1,62)
          screen.text('(K1 HOLD) DEL.')
          screen.move(128,62)
          screen.text_right('(K3) ARRANGER')
        else
          screen.level(15)      
          screen.move(36,33)
          screen.text('DELETING IN ' .. key_counter)
        end
      else
   
   
        --------------------------
        -- Scrolling events menu
        --------------------------
        -- todo p2 this mixes events_index and menu_index. Redundant?
        local menu_offset = scroll_offset_locked(events_index, 10, 2) -- index, height, locked_row
        line = 1
        for i = 1,#events_menus do
          local debug = false
          
          screen.move(2, line * 10 + 8 - menu_offset)
          screen.level(events_index == i and 15 or 3)

          local menu_id = events_menus[i]
          local menu_index = params:get(menu_id)
          event_val_string = params:string(menu_id)


         -- use event_value to format values
         -- values are already set on var event_val_string so if no conditions are met they pass through raw
         -- >> 'Set' operation should do .options lookup where possible
         -- >> functions are raw
         -- >> inc, random, wander are raw
         -- >> todo p1: think about using formatter on increment and wander. Like how do we handle percentages and large frequencies?
         -- might need an events_lookup[params:get('event_name')].event_type == param check
          if menu_id == 'event_value' then
            if debug then print('-------------------') end
            if debug then print('formatting event_value menu') end
            operation = params:string('event_operation')
            
            if operation == 'Set' then
              if debug then print("'Set' operator") end
              -- params with a formatter
              if events_lookup[params:get('event_name')].formatter ~= nil then -- this operates on functions too :(
                if debug then print('Formatting') end
                event_val_string = _G[events_lookup[params:get('event_name')].formatter](params:string('event_value'))
                
                
                elseif events_lookup[params:get('event_name')].event_type == 'param' 
                
                -- params:t == 2 means it's an add_options type param                
                and params:t(events_lookup[params:get('event_name')].id) == 2 then
                  if debug then print('Setting string val from options') end
                  -- print('value set options')
                  -- Uses event index to look up all the options for that param, then select using index
                  local options = get_options(events_lookup[params:get('event_name')].id)
                  event_val_string = options[menu_index]

              end
              if debug then print('Nil formatter: skipping') end
            elseif operation == 'Wander' then
              event_val_string = '\u{0b1}' .. event_val_string
            end
          if debug then print('Value passed raw') end
          end -- end of event_value stuff
      
          ------------------------------------------------
          -- Draw menu and <> indicators for scroll range
          ------------------------------------------------
          -- Leaving in param formatter and some code for truncating string in case we want to eventually add system param events that require formatting.
          local events_menu_trunc = 22 -- WAG Un-local if limiting using the text_extents approach below
          if events_index == i then
            local range =
              (menu_id == 'event_category' or menu_id == 'event_subcategory' or menu_id == 'event_operation') 
              and params:get_range(menu_id)
              or menu_id == 'event_name' and {event_subcategory_index_min, event_subcategory_index_max}
              or event_range -- if all else fails, slap -9999 to 9999 on it from set_event_range lol

            local single = menu_index == range[1] and (range[1] == range[2]) or false
            local menu_value_pre = single and '>' or menu_index == range[2] and '<' or ' '
            local menu_value_suf = single and '<' or menu_index == range[1] and '>' or ''
            local events_menu_txt = first_to_upper(param_formatter(param_id_to_name(menu_id))) .. menu_value_pre .. string.sub(event_val_string, 1, events_menu_trunc) .. menu_value_suf

            if debug and menu_id == 'event_value' then print('menu_id = ' .. (menu_id or 'nil')) end
            if debug and menu_id == 'event_value' then print('event_val_string = ' .. (event_val_string or 'nil')) end

            screen.text(events_menu_txt)
          else
            
            if debug and menu_id == 'event_value' then print('menu_id = ' .. (menu_id or 'nil')) end
            if debug and menu_id == 'event_value' then print('event_val_string = ' .. (event_val_string or 'nil')) end
            
            screen.text(first_to_upper(param_formatter(param_id_to_name(menu_id))) .. ' ' .. string.sub(event_val_string, 1, events_menu_trunc))
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
        screen.text('SEG ' .. event_edit_segment .. '.' .. event_edit_step .. ', EVENT ' .. event_edit_lane .. '/16')
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
        screen.text('(K2) DELETE')
        screen.move(128,62)
        if event_edit_status == '(Saved)' then
          screen.text_right('(K3) EVENTS')
        else
          screen.text_right('(K3) SAVE')
        end
      end
        
        
    -- SESSION VIEW (NON-EVENTS), not holding down Arranger segments g.keys  
    else
      ---------------------------
      -- UI elements placed here appear in all non-Events views
      ---------------------------

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
      screen.level(((transport_state == 'starting' or transport_state == 'pausing') and fast_blinky or 0) * 2)
      local x_offset = dash_x + 27
      local y_offset = 3

      -- simplify intermediate states for the glyph selection
      local transport_state = transport_state == 'starting' and 'playing' or transport_state == 'pausing' and 'paused' or transport_state
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
        screen.text(pattern_name[active_chord_pattern].. '.RST')
      else
        screen.text(pattern_name[active_chord_pattern] ..'.'.. chord_pattern_position)
        -- screen.text(pattern_name[active_chord_pattern] ..'.'.. chord_pattern_position .. '/' .. chord_pattern_length[active_chord_pattern])
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
      screen.level(params:get('arranger') == 2 and 9 or 2)
      
      screen.rect(dash_x+1, arranger_dash_y+2,33,38)
      screen.stroke()
      
      -- Header
      screen.level(params:get('arranger') == 2 and 10 or 2)
      screen.rect(dash_x, arranger_dash_y+1,34,11)
      screen.fill()

      --------------------------------------------
      -- Arranger countdown timer readout
      --------------------------------------------
    
      -- Arranger time
      screen.level(params:get('arranger') == 2 and 15 or 3)

      -- Bottom left
      screen.move(dash_x +3, arranger_dash_y + 36)
      screen.text(seconds_remaining)
      
      -- Arranger mode glyph
      local x_offset = dash_x + 27
      local y_offset = arranger_dash_y + 4

      if params:string('playback') == 'Loop' then
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
          screen.text('RST')
        elseif arranger_active == false then
          screen.text((arranger_queue or util.wrap(arranger_position + 1, 1, arranger_length)) .. '.'.. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
        else
          screen.text(arranger_queue .. '.0')
        end
      elseif arranger_active == false then
        if chord_pattern_position == 0 then -- condition for when pattern is reset to position 0 and is in-between segments
          screen.text(arranger_position .. '.0')
        elseif arranger_position == arranger_length then
          if params:string('playback') == "Loop" then
            screen.text('LP.' .. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
          else
            screen.text('EN.' .. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
          end
        else
          screen.text((arranger_queue or util.wrap(arranger_position + 1, 1, arranger_length)) .. '.'.. math.min(chord_pattern_position - chord_pattern_length[active_chord_pattern], 0))
        end
      else
        screen.text(arranger_position .. '.' .. chord_pattern_position)
        
      end      
      screen.fill()
      
      
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
        session_menu_trunc = 16
        if menu_index == i then
          local range = params:get_range(menus[page_index][i])
          local menu_value_suf = params:get(menus[page_index][i]) == range[1] and '>' or ''
          local menu_value_pre = params:get(menus[page_index][i]) == range[2] and '<' or ' '
          local session_menu_txt = first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) .. menu_value_pre .. string.sub(params:string(menus[page_index][i]), 1, session_menu_trunc) .. menu_value_suf

          while screen.text_extents(session_menu_txt) > 90 do
            session_menu_trunc = session_menu_trunc - 1
            session_menu_txt = first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) .. menu_value_pre .. string.sub(params:string(menus[page_index][i]), 1, session_menu_trunc) .. menu_value_suf
          end
          
          screen.text(session_menu_txt)
        else  
          screen.text(first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) .. ' ' .. string.sub(params:string(menus[page_index][i]), 1, 16))
        end
        line = line + 1
      end


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

    end -- of event vs. non-event check
  end
  screen.update()
end