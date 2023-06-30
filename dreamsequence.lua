-- Dreamsequence
-- v1.1 @modularbeat
-- llllllll.co/t/dreamsequence
--
-- Chord-based sequencer, 
-- arpeggiator, and harmonizer 
-- for Monome Norns+Grid
-- 
-- KEY 2: Pause/Stop(2x)
-- KEY 3: Play
--
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
include("dreamsequence/lib/includes")

norns.version.required = 230526

function init()
  -----------------------------
  -- todo prerelease ALSO MAKE SURE TO UPDATE ABOVE!
  -- saved with pset files to suss out issues in the future
  version = 'v1.1'
  -----------------------------

  -- thanks @dndrks for this little bit of magic to check ^^crow^^ version!!
  -- todo prerelease
  norns.crow.events.version = function(...)
    crow_version = ...
  end
  crow.version() -- now redefined to perform the above!
  crow_version_clock = clock.run(
    function()
      clock.sleep(0.1) -- a small hold for usb round-trip
      if crow_version ~= nil then
        local crow_major_version = find_number(crow_version)
        if crow_version ~= 'v3.0.1' then
          init_message = 'Crow version warning'
          redraw()
        end
        print('Crow version ' .. crow_version)
      end
    end
  )

  crow.ii.jf.event = function(e, value)
    if e.name == 'mode' then
      print('preinit jf.mode = '..value)
      preinit_jf_mode = value
    elseif e.name == 'time' then
      jf_time = value
      print('jf_time = ' .. value)
    end
  end
  
  function capture_preinit()
    preinit_clock_source = params:get('clock_source')
    print('preinit_clock_source = ' .. preinit_clock_source)
    preinit_clock_crow_out = params:get('clock_crow_out')
    print('preinit_clock_crow_out = ' .. preinit_clock_crow_out)
    
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
  
  clock.link.stop() -- or else transport won't start if external link clock is already running

  init_generator()
  
  -- midi stuff
  midi_device = {} -- container for connected midi devices
  midi_device_names = {} -- container for their names
  refresh_midi_devices()

  
  local events_lookup_names = {}
  local events_lookup_ids = {}
  for i = 1, #events_lookup do
    events_lookup_names[i] = events_lookup[i].name
    events_lookup_ids[i] = events_lookup[i].id
  end
  
  -- big list of event_id, index
  events_lookup_index = tab.invert(events_lookup_ids)
  
  -- Used to derive the min and max indices for the selected event category (Global, Chord, Arp, etc...)
  event_categories = {} -- todo: make local after debug
  for i = 1, #events_lookup do
    event_categories[i] = events_lookup[i].category
  end
  
  -- Generate subcategories lookup tables
  gen_event_tables()
  
  -- Unique, ordered event subcategories for each category
  -- Used to generate a parameter for each event category containing the subcategories
  -- event_subcategories
  
  -- key = conctat category_subcategory with first_index and last_index values
  -- event_indices
  

  --------------------
  --PARAMS
  --------------------
  params:add_separator ('DREAMSEQUENCE')

  --GLOBAL PARAMS
  params:add_group('global', 'GLOBAL', 6)
  params:add_number('mode', 'Mode', 1, 9, 1, function(param) return mode_index_to_name(param:get()) end) -- post-bang action
  params:add_number("transpose","Key",-12, 12, 0, function(param) return transpose_string(param:get()) end)

  params:add_number('dedupe_threshold', 'Dedupe <', 0, 10, div_to_index('1/32'), function(param) return divisions_string(param:get()) end)
  params:set_action('dedupe_threshold', function() dedupe_threshold() end)
  
  params:add_number('chord_preload', 'Chord preload', 0, 10, div_to_index('1/64'), function(param) return divisions_string(param:get()) end)
  params:set_action('chord_preload', function(x) chord_preload(x) end)     
  
  params:add_number('crow_pullup','Crow Pullup',0, 1, 1,function(param) return t_f_string(param:get()) end)
  params:set_action("crow_pullup",function() crow_pullup() end)
  
  params:add_option('chord_readout', 'Chords as', {'Name', 'Degree'}, 1)


  --ARRANGER PARAMS
  params:add_group('arranger', 'ARRANGER', 2)
  params:add_number('arranger_enabled', 'Enabled', 0, 1, 0, function(param) return t_f_string(param:get()) end)
  params:set_action('arranger_enabled', function() grid_redraw(); update_arranger_active() end)
  
  params:add_option('playback', 'Playback', {'Loop','One-shot'}, 1)
  params:set_action('playback', function() grid_redraw(); arranger_ending() end)
  -- params:add_option('crow_assignment', 'Crow 4', {'Reset', 'On/high', 'V/pattern', 'Chord', 'Pattern'},1) -- todo


  ------------------
  -- EVENT PARAMS --
  ------------------
  params:add_option('event_category', 'Category', {'Global', 'Chord', 'Arp', 'MIDI harmonizer', 'CV harmonizer'}, 1)
  params:set_action('event_category', function(param) change_category(param) end)
  params:hide(params.lookup['event_category'])
  
  -- options will be dynamically swapped out based on the current event_global param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  params:add_option('event_subcategory', 'Subcategory', event_subcategories['Global'], 1)
  params:hide(params.lookup['event_subcategory'])
 
  params:add_option('event_name', 'Event', events_lookup_names, 1) -- Default value overwritten later in Init
  params:set_action('event_name',function(param) change_event(param) end)
  params:hide(params.lookup['event_name'])
  
  -- options will be dynamically swapped out based on the current event_name param
  -- one side-effect of this approach is that param actions won't fire unless the index changes (not string).
  event_operation_options_continuous = {'Set', 'Increment', 'Wander', 'Random'}
  event_operation_options_discreet = {'Set', 'Random'}
  event_operation_options_trigger = {'Trigger'} 
  params:add_option('event_operation', 'Operation', _G['event_operation_options_' .. events_lookup[1].value_type], 1)
  params:hide(params.lookup['event_operation'])

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
  
  
  -- init values based on default event param
  gen_menu_events()
  set_event_indices()


  --CHORD PARAMS
  params:add_group('chord', 'CHORD', 23)  
  params:add_option('chord_generator', 'C-gen', chord_algos['name'], 1)
  chord_div = 192 -- seems to be some race-condition when loading pset, index value 15, and setting this via param action so here we go
  params:add_number('chord_div_index', 'Step length', 1, 57, 15, function(param) return divisions_string(param:get()) end)
    params:set_action('chord_div_index',function() set_div('chord') end)
  params:add_option('chord_dest', 'Destination', {'None', 'Engine', 'MIDI', 'ii-JF', 'Disting'},2)
    params:set_action("chord_dest",function() update_menus() end)
  params:add_number('chord_duration_index', 'Duration', 1, 57, 15, function(param) return divisions_string(param:get()) end)
    params:set_action('chord_duration_index',function() set_duration('chord') end)
  params:add_number('chord_octave','Octave',-2, 4, 0)
  params:add_number('chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)
  params:add_number('chord_inversion', 'Inversion', 0, 16, 0)
  params:add_number('chord_spread', 'Spread', 0, 6, 0)    
    
  params:add_separator ('chord_engine', 'Engine')
  params:add_number('chord_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_control("chord_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,700,'hz'))
  params:add_number('chord_pp_tracking', 'Fltr tracking',0,100,50, function(param) return percent(param:get()) end)
  pp_gain = controlspec.def{
    min=0,
    max=400,
    warp='lin',
    step=10,
    default=100,
    wrap=false,
    }
  params:add_control("chord_pp_gain","Gain",pp_gain,function(param) return util.round(param:get()) end)
  params:add_number("chord_pp_pw","Pulse width",1, 99, 50, function(param) return percent(param:get()) end)
  
  params:add_separator ('chord_midi', 'MIDI')
  params:add_number('chord_midi_velocity','Velocity',0, 127, 100)
  
  params:add_number('chord_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("chord_midi_cc_1_val",function(val) send_cc('chord', 1, val) end)
  
  params:add_number('chord_midi_out_port', 'Port',1,#midi.vports,1)
    -- params:set_action('chord_midi_out_port', function(value) chord_midi_out = midi_device[value] end)    
  params:add_number('chord_midi_ch','Channel',1, 16, 1)
  
  params:add_separator ('chord_jf', 'Just Friends')
  params:add_number('chord_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  
  params:add_separator ('chord_disting', 'Disting')
  params:add_number('chord_disting_velocity','Velocity',0, 100, 50)


  --ARP PARAMS
  params:add_group('arp', 'ARP', 25)  
  params:add_option('arp_generator', 'A-gen', arp_algos['name'], 1)
  params:add_number('arp_div_index', 'Step length', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('arp_div_index',function() set_div('arp') end)
  
  params:add_option("arp_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'},2)
  params:set_action("arp_dest",function() update_menus() end)
  
  params:add_number('arp_duration_index', 'Duration', 1, 57, 8, function(param) return divisions_string(param:get()) end)
  params:set_action('arp_duration_index',function() set_duration('arp') end)
  
  params:add_number('arp_octave','Octave',-2, 4, 0)
  params:add_number('arp_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)
  params:add_option("arp_mode", "Mode", {'Loop','One-shot'},1)    
    
  params:add_separator ('arp_engine', 'Engine')
  params:add_number('arp_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_control("arp_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,700,'hz'))
  params:add_number('arp_pp_tracking', 'Fltr tracking',0,100,50,function(param) return percent(param:get()) end)
  params:add_control("arp_pp_gain","Gain", pp_gain,function(param) return util.round(param:get()) end)
  params:add_number("arp_pp_pw","Pulse width",1, 99, 50,function(param) return percent(param:get()) end)
  
  params:add_separator ('arp_midi', 'MIDI')
  params:add_number('arp_midi_out_port', 'Port',1,#midi.vports,1)
  params:add_number('arp_midi_ch','Channel',1, 16, 1)
  params:add_number('arp_midi_velocity','Velocity',0, 127, 100)
  
  params:add_number('arp_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("arp_midi_cc_1_val",function(val) send_cc('arp', 1, val) end)


  params:add_separator ('arp_jf', 'Just Friends')
  params:add_number('arp_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  
  params:add_separator ('arp_disting', 'Disting')
  params:add_number('arp_disting_velocity','Velocity',0, 100, 50)
  
  params:add_separator ('arp_crow', 'Crow')
  params:add_option("arp_tr_env", "Output", {'Trigger','AD env.'},1)
    params:set_action("arp_tr_env",function() update_menus() end)
  params:add_number('arp_ad_skew','AD env. skew',0, 100, 0)
  
  
  --MIDI PARAMS
  params:add_group('midi_harmonizer', 'MIDI HARMONIZER', 24)  
  params:add_option("midi_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'},2)
    params:set_action("midi_dest",function() update_menus() end)
    
  params:add_number('midi_in_port', 'Port in',1,#midi.vports,1)
    params:set_action('midi_in_port', function(value)
      in_midi.event = nil
      in_midi = midi.connect(params:get('midi_in_port'))
      in_midi.event = midi_event      
    end)
    -- set in_midi port once before params:bang()
    in_midi = midi.connect(params:get('midi_in_port'))
    in_midi.event = midi_event
  
  params:add_number('midi_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
    params:set_action('midi_duration_index',function() set_duration('midi') end)
  params:add_number('midi_octave','Octave',-2, 4, 0)
  params:add_number('midi_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)  
  
  params:add_separator ('midi_harmonizer_engine', 'Engine')
  params:add_number('midi_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_control("midi_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,700,'hz'))
  params:add_number('midi_pp_tracking', 'Fltr tracking',0,100,50,function(param) return percent(param:get()) end)
  params:add_control("midi_pp_gain","Gain", pp_gain,function(param) return util.round(param:get()) end)
  params:add_number("midi_pp_pw","Pulse width",1, 99, 50,function(param) return percent(param:get()) end)
  
  params:add_separator ('midi_harmonizer_midi', 'MIDI')
  params:add_number('midi_midi_out_port', 'Port out',1,#midi.vports,1)   -- (clock out ports configured in global midi parameters) 
  params:add_number('midi_midi_ch','Channel',1, 16, 1)
  params:add_number('do_midi_velocity_passthru', 'Pass velocity', 0, 1, 0, function(param) return t_f_string(param:get()) end)
    params:set_action("do_midi_velocity_passthru",function() update_menus() end)  
  params:add_number('midi_midi_velocity','Velocity',0, 127, 100)
  
  params:add_number('midi_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("midi_midi_cc_1_val",function(val) send_cc('midi', 1, val) end)
  
  params:add_separator ('Just Friends')
  params:add_number('midi_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  
  params:add_separator ('Disting')
  params:add_number('midi_disting_velocity','Velocity',0, 100, 50)
  
  params:add_separator ('midi_harmonizer_crow','Crow')
  params:add_option("midi_tr_env", "Output", {'Trigger','AD env.'},1)
    params:set_action("midi_tr_env",function() update_menus() end)
  params:add_number('midi_ad_skew','AD env. skew',0, 100, 0)

  
  --CV/CROW PARAMS
  params:add_group('cv_harmonizer', 'CV HARMONIZER', 24)  
  -- Crow clock uses hybrid notation/PPQN
  params:add_number('crow_clock_index', 'Crow clock', 1, 65, 18,function(param) return crow_clock_string(param:get()) end)
    params:set_action('crow_clock_index',function() set_crow_clock() end)
  params:add_option("crow_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF', 'Disting'},2)
    params:set_action("crow_dest",function() update_menus() end)
  params:add_number('crow_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
    params:set_action('crow_duration_index',function() set_duration('crow') end)
  params:add_number('crow_octave','Octave',-2, 4, 0)
  params:add_number('crow_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)    

  params:add_separator ('cv_harmonizer_engine', 'Engine')
  params:add_number('crow_pp_amp', 'Amp', 0, 100, 80, function(param) return percent(param:get()) end)
  params:add_number('do_crow_auto_rest', 'Auto-rest', 0, 1, 0, function(param) return t_f_string(param:get()) end)
  params:add_control("crow_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,700,'hz'))
  params:add_number('crow_pp_tracking', 'Fltr tracking',0,100,50,function(param) return percent(param:get()) end)
  params:add_control("crow_pp_gain","Gain", pp_gain,function(param) return util.round(param:get()) end)
  params:add_number("crow_pp_pw","Pulse width",1, 99, 50,function(param) return percent(param:get()) end)
  
  params:add_separator ('cv_harmonizer_midi', 'MIDI')
  params:add_number('crow_midi_out_port', 'Port',1,#midi.vports,1)
  params:add_number('crow_midi_ch','Channel',1, 16, 1)
  params:add_number('crow_midi_velocity','Velocity',0, 127, 100)

  params:add_number('crow_midi_cc_1_val', 'Mod wheel', -1, 127, -1, function(param) return neg_to_off(param:get()) end)
  params:set_action("crow_midi_cc_1_val",function(val) send_cc('crow', 1, val) end)

  
  params:add_separator ('cv_harmonizer_jf', 'Just Friends')
  params:add_number('crow_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  
  params:add_separator ('cv_harmonizer_disting', 'Disting')
  params:add_number('crow_disting_velocity','Velocity',0, 100, 50)
  
  params:add_separator ('cv_harmonizer_crow', 'Crow')
  params:add_option("crow_tr_env", "Output", {'Trigger','AD env.'},1)
    params:set_action("crow_tr_env",function() update_menus() end)
  params:add_number('crow_ad_skew','AD env. skew',0, 100, 0)
  
  -----------------------------
  -- Init stuff
  -----------------------------
  
  start = false
  transport_state = 'stopped'
  clock_start_method = 'start'
  link_stop_source = nil
  global_clock_div = 48
  -- print('START canceling timing_clock_id ' .. (sequence_clock_id or 0))
  -- clock.cancel(timing_clock_id or 0) -- Cancel previous timing clock (if any) and...
  timing_clock_id = clock.run(timing_clock) --Start a new timing clock to handle note-off

  -- Send out MIDI stop on launch if clock ports are enabled
  transport_multi_stop()  
  arranger_active = false
  chord_seq_retrig = true
  
  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  -- voltage threshold, hysteresis, "rising", "falling", or “both"
  -- TODO: might want to use as a gate with "both"
  crow.input[2].mode("change",2,0.1,"rising")
  crow.input[2].change = crow_trigger
  -- time,level,polarity
  crow.output[2].action = "pulse(.001,5,1)"
  crow.output[3].slew = 0
  
  screen_views = {'Session','Events'}
  screen_view_index = 1
  screen_view_name = screen_views[screen_view_index]
  grid_dirty = true
  -- grid "views" are decoupled from screen "pages"  
  grid_views = {'Arranger','Chord','Arp'}
  grid_view_keys = {}
  grid_view_name = grid_views[2]
  math.randomseed(os.time()) -- doesn't seem like this is needed but not sure why
  fast_blinky = 1
  pages = {'GLOBAL>', 'CHORD', 'ARP', 'MIDI HARMONIZER', '<CV HARMONIZER'}
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  update_menus()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  transport_active = false
  chord_pattern_length = {4,4,4,4}
  pattern = 1
  pattern_name = {'A','B','C','D'}
  -- steps_remaining_in_pattern = chord_pattern_length[pattern]
  pattern_queue = false
  pattern_copy_performed = false
  arranger_seq_retrig = false
  max_arranger_seq_length = 64 --(64 arranger segments * 8 chord step * 16 event slots = 8192 events... yikes)
  -- Raw arranger_seq which can contain nils although we're moving away from this I think
  arranger_seq = {}
  for segment = 1, max_arranger_seq_length do
    arranger_seq[segment] = 0
  end
  arranger_seq[1] = 1 -- setting this so new users aren't confused about the pattern padding
  -- Version of arranger_seq which generates chord patterns for held segments
  arranger_seq_padded = {}
  arranger_seq_position = 0
  arranger_seq_length = 1
  arranger_grid_offset = 0 -- offset allows us to scroll the arranger grid view beyond 16 segments
  gen_arranger_seq_padded()
  d_cuml = 0
  interaction = nil
  events = {}
  for segment = 1, max_arranger_seq_length do
    events[segment] = {}
    for step = 1,8 do
      events[segment][step] = {}
    end
  end
  events_index = 1
  selected_events_menu = 'event_category'
  set_event_indices()
  params:set('event_name', event_subcategory_index_min)  -- Overwrites initial value
  
  event_edit_pattern = 0
  event_edit_step = 0
  event_edit_lane = 0
  steps_remaining_in_arrangement = 0
  elapsed = 0
  percent_step_elapsed = 0
  seconds_remaining = 0
  chord_no = 0
  arranger_loop_key_count = 0    
  pattern_keys = {}
  pattern_key_count = 0
  chord_key_count = 0
  view_key_count = 0
  event_key_count = 0
  keys = {}
  key_count = 0
  -- global_clock_div = 48
  chord_seq = {{},{},{},{}}
  arp_seq = {{},{},{},{}}
  for p = 1,4 do
    for i = 1,8 do
      chord_seq[p][i] = 0
      arp_seq[p][i] = 0
    end
  end
  chord_seq_position = 0
  chord_raw = {}
  current_chord_o = 0
  current_chord_c = 1
  next_chord_o = 0
  next_chord_c = 1  
  arp_pattern_length = {8,8,8,8}
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
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
  pset_lookup = {'arranger_seq', 'events', 'chord_seq', 'chord_pattern_length', 'arp_seq', 'arp_pattern_length', 'misc'}
  
  
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
    for i = 1,7 do
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
    for i = 1,7 do
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
    
    -- reset event-related params so the event editor opens to the default view rather than the last-loaded event
    params:set('event_category', 1)  
    params:set('event_subcategory', 1)
    params:set('event_name', 1)
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
      gen_arranger_seq_padded()
    end
    arranger_queue = nil
    arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
    pattern_queue = false
    arp_seq_position = 0
    chord_seq_position = 0
    arranger_seq_position = 0
    pattern = arranger_seq_padded[1]
    if transport_state == 'paused' then
      transport_state = 'stopped' -- just flips to the stop icon so user knows they don't have to do this manually
    end  
    get_next_chord()
    chord_raw = next_chord
    chord_no = 0 -- wipe chord readout
    gen_chord_readout()
    gen_dash('params.action_read')
    
    -- if transport_active, reset and continue playing so user can demo psets from the system menu
    -- todo p2 need to send different sync values depending on clock source.
    -- when link clock is running we can pick up on the wrong beat.
    -- unsure about MIDI
    -- if transport_active == true then
    --   clock.transport.start()
    -- end
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

-- Optional: load most recent pset on init
params:default() -- todo prerelease disable. Set preference for autoloading!
params:bang()

-- Some actions need to be added post-bang
params:set_action('mode', function() update_chord_action() end)

countdown_timer = metro.init()
countdown_timer.event = countdown -- call the 'countdown' function below,
countdown_timer.time = .1 -- 1/10s
countdown_timer.count = -1 -- for.evarrr

grid_redraw()
redraw()
end


-- UPDATE_MENUS. todo p2: can be optimized by only calculating the current view+page or when certain actions occur
function update_menus()

  -- GLOBAL MENU 
    menus[1] = {'mode', 'transpose', 'clock_tempo', 'clock_source',
      'crow_clock_index', 'dedupe_threshold', 'chord_preload', 'crow_pullup', 'chord_generator', 'arp_generator', 'chord_readout'}
  
  -- CHORD MENU
  if params:string('chord_dest') == 'None' then
    menus[2] = {'chord_dest', 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index'}
  elseif params:string('chord_dest') == 'Engine' then
    menus[2] = {'chord_dest', 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_tracking', 'chord_pp_gain', 'chord_pp_pw'}
  elseif params:string('chord_dest') == 'MIDI' then
    menus[2] = {'chord_dest', 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_midi_out_port', 'chord_midi_ch', 'chord_midi_velocity', 'chord_midi_cc_1_val'}
  elseif params:string('chord_dest') == 'ii-JF' then
    menus[2] = {'chord_dest', 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_jf_amp'}
  elseif params:string('chord_dest') == 'Disting' then
    menus[2] = {'chord_dest', 'chord_type', 'chord_octave', 'chord_spread', 'chord_inversion', 'chord_div_index', 'chord_duration_index', 'chord_disting_velocity'}  
  end
  
  -- ARP MENU
  if params:string('arp_dest') == 'None' then
    menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_mode', }
  elseif params:string('arp_dest') == 'Engine' then
    menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_duration_index', 'arp_mode',  'arp_pp_amp', 'arp_pp_cutoff', 'arp_pp_tracking','arp_pp_gain', 'arp_pp_pw'}
  elseif params:string('arp_dest') == 'MIDI' then
    menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_duration_index', 'arp_mode', 'arp_midi_out_port', 'arp_midi_ch', 'arp_midi_velocity', 'arp_midi_cc_1_val'}
  elseif params:string('arp_dest') == 'Crow' then
    if params:string('arp_tr_env') == 'Trigger' then
      menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_mode', 'arp_tr_env' }
    else -- AD envelope
      menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_mode', 'arp_tr_env', 'arp_duration_index', 'arp_ad_skew',}
    end
  elseif params:string('arp_dest') == 'ii-JF' then
    menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_mode', 'arp_jf_amp'}
  elseif params:string('arp_dest') == 'Disting' then
    menus[3] = {'arp_dest', 'arp_chord_type', 'arp_octave', 'arp_div_index', 'arp_duration_index', 'arp_mode', 'arp_disting_velocity'}    
  end
  
  -- MIDI HARMONIZER MENU
  if params:string('midi_dest') == 'None' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave'}
  elseif params:string('midi_dest') == 'Engine' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_duration_index', 'midi_pp_amp', 'midi_pp_cutoff', 'midi_pp_tracking', 'midi_pp_gain', 'midi_pp_pw'}
  elseif params:string('midi_dest') == 'MIDI' then
    if params:get('do_midi_velocity_passthru') == 1 then
      menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_duration_index','midi_in_port', 'midi_midi_out_port', 'midi_midi_ch', 'do_midi_velocity_passthru', 'midi_midi_cc_1_val'}
    else
      menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_duration_index', 'midi_in_port', 'midi_midi_out_port', 'midi_midi_ch', 'do_midi_velocity_passthru', 'midi_midi_velocity', 'midi_midi_cc_1_val'}
    end
  elseif params:string('midi_dest') == 'Crow' then
    if params:string('midi_tr_env') == 'Trigger' then
      menus[4] = {'midi_dest','midi_chord_type', 'midi_octave', 'midi_tr_env'}
    else -- AD envelope
      menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_tr_env', 'midi_duration_index', 'midi_ad_skew'}
    end
  elseif params:string('midi_dest') == 'ii-JF' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_jf_amp'}
 elseif params:string('midi_dest') == 'Disting' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_duration_index', 'midi_disting_velocity'}
  end
  
  -- CV HARMONIZER MENU
  if params:string('crow_dest') == 'None' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest'}
  elseif params:string('crow_dest') == 'Engine' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'crow_duration_index', 'do_crow_auto_rest', 'crow_pp_amp', 'crow_pp_cutoff', 'crow_pp_tracking', 'crow_pp_gain', 'crow_pp_pw'}
  elseif params:string('crow_dest') == 'MIDI' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'crow_duration_index', 'do_crow_auto_rest', 'crow_midi_out_port', 'crow_midi_ch', 'crow_midi_velocity', 'crow_midi_cc_1_val'}
  elseif params:string('crow_dest') == 'Crow' then
    if params:string('crow_tr_env') == 'Trigger' then
      menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest', 'crow_tr_env', }
    else -- AD envelope
      menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest','crow_tr_env', 'crow_duration_index', 'crow_ad_skew', }
    end
  elseif params:string('crow_dest') == 'ii-JF' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest', 'crow_jf_amp'}
  elseif params:string('crow_dest') == 'Disting' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'crow_duration_index', 'do_crow_auto_rest', 'crow_disting_velocity'}    
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


function refresh_midi_devices()
  for i = 1,#midi.vports do -- query all ports
    midi_device[i] = midi.connect(i) -- connect each device
    table.insert( -- register its name:
      midi_device_names, -- table to insert to
      "port "..i..": "..util.trim_string_to_width(midi_device[i].name,80) -- value to insert
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


function crow_pullup()
  crow.ii.pullup(t_f_bool(params:get('crow_pullup')))
  -- print('crow pullup: ' .. t_f_string(params:get('crow_pullup')))
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


--Creates a variable for each source's div.
function set_div(source)
  _G[source .. '_div'] = division_names[params:get(source .. '_div_index')][1]
end


--Creates a variable for each source's duration
function set_duration(source)
  _G[source .. '_duration'] = division_names[params:get(source .. '_duration_index')][1]
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
  return(musicutil.SCALES[index].name)
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


function div_10(x)
  return(x / 10)
end


function mult_100_percent(x)
  return(math.floor(x * 100) .. '%')
end


function percent(x)
  return(math.floor(x) .. '%')
end


function chord_type(x)
  return(x == 3 and 'Triad' or '7th')
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
  for i = 1, 8 do
    chord_seq[pattern][i] = 0
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
function gen_arranger_seq_padded()
  arranger_seq_padded = {}
  
  -- First identify the first and last populated segments
  first_populated_segment = 0
  last_populated_segment = 0
  patt = nil

  -- -- todo: profile this vs the 2x pass and break
  -- for k, v in pairs(arranger_seq) do -- no longer need to do in pairs because there are no nils
  --   if arranger_seq[k] > 0 then
  --     if first_populated_segment == 0 then first_populated_segment = k end
  --     last_populated_segment = math.max(last_populated_segment,k)
  --   end
  -- end

  for i = 1, max_arranger_seq_length do
    if arranger_seq[i] > 0 then
      first_populated_segment = i
      break
    end
  end  

  for i = max_arranger_seq_length, 1, -1 do
    if arranger_seq[i] > 0 then
      last_populated_segment = i
      -- print('last_populated_segment = ' .. last_populated_segment)
      break
    end
  end    

  arranger_seq_length = math.max(last_populated_segment,1)
  
  -- Run this as a second loop since the above needs to iterate through all segments to update vars and set arranger_seq_length
  for i = 1, arranger_seq_length do
    -- First, let's handle any zeroed segments at the beginning of the sequence. Since the Arranger can be looped, we use the last populated segment where possible, then fall back on the current Pattern. Otherwise we would have a situation where the initial pattern potentially changes upon looping which is not very intuitive.
    if i < (first_populated_segment) then
      arranger_seq_padded[i] = arranger_seq[last_populated_segment] or pattern
    -- From this point on, we log the current segment's pattern so it can be used to propagate the pattern, then set this on the current step.
    elseif (arranger_seq[i] or 0) > 0 then
      patt = arranger_seq[i]
      arranger_seq_padded[i] = patt
    else
      arranger_seq_padded[i] = (patt or pattern)
    end
  end
  gen_dash('gen_arranger_seq_padded')
end


-- Hacking up MusicUtil.generate_chord_roman to get modified chord_type for chords.
-- Could probably gain some efficiency by just writing all this to a table
-- @treturn chord_type
function get_chord_name(root_num, scale_type, roman_chord_type)

  local rct = roman_chord_type or "I"

  -- treat extended ascii degree symbols as asterisks
  rct = string.gsub(rct, "\u{B0}", "*")
  rct = string.gsub(rct, "\u{BA}", "*")

  local degree_string, augdim_string, added_string, bass_string, inv_string =
    string.match(rct, "([ivxIVX]+)([+*]?)([0-9]*)-?([0-9]?)([bcdefg]?)")

  local d = string.lower(degree_string)
  local is_major = degree_string ~= d
  local is_augmented = augdim_string == "+"
  local is_diminished = augdim_string == "*"
  local is_seventh = added_string == "7"

  local chord_type = nil
  if is_major then
    if is_augmented then
      if is_seventh then
        chord_type = "aug7"
      else
        chord_type = "aug"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = "dim7"
      else
        chord_type = "dim"
      end
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "maj69"
      else
        chord_type = "maj6"
      end
    elseif is_seventh then
      chord_type = "maj7"
    elseif added_string == "9" then
      chord_type = "maj9"
    elseif added_string == "11" then
      chord_type = "maj11"
    elseif added_string == "13" then
      chord_type = "maj13"
    else
      chord_type = "maj"
    end
  else -- minor
    if is_augmented then
      if is_seventh then
        chord_type = "aug7"
      else
        chord_type = "aug"
      end
    elseif is_diminished then
      if is_seventh then
        chord_type = "dim7"
      else
        chord_type = "dim"
      end
    elseif added_string == "6" then
      if bass_string == "9" then
        chord_type = "min69"
      else
        chord_type = "min6"
      end
    elseif is_seventh then
      chord_type = "min7"
    elseif added_string == "9" then
      chord_type = "min9"
    elseif added_string == "11" then
      chord_type = "min11"
    elseif added_string == "13" then
      chord_type = "min13"
    else
      chord_type = "min"
    end
  end
  return(chord_type)
end


 -- Clock to control sequence events including chord pre-load, chord/arp sequence, and crow clock out
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
    
    
    -- ADVANCE SUB CLOCKS: advance_chord_seq(), advance_arp_seq(), Crow pulses
    if transport_active then -- check again
      if (clock_step + chord_preload_tics) % chord_div == 0 then
        get_next_chord()
      end
    
      if clock_step % chord_div == 0 then
        advance_chord_seq()
        grid_dirty = true
        redraw() -- To update chord readout
      end
  
      if clock_step % arp_div == 0 then
        if params:string('arp_mode') == 'Loop' or play_arp then
          advance_arp_seq()
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
    percent_step_elapsed = arranger_seq_position == 0 and 0 or (math.max(clock_step,0) % chord_div / (chord_div-1))
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
  -- grid_redraw()
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
    print('Transport starting')
    start = true
    stop = false -- 2023-07-19 added so when arranger stops in 1-shot and then external clock stops, it doesn't get stuck
    transport_active = true
    print ('transport set to active via transport.start')
  
    -- Clock for chord/arp/arranger sequences
    sequence_clock_id = clock.run(sequence_clock, sync_value)
  
    --Clock used to refresh arranger countdown timer 10x a second
    countdown_timer:start()
  end
end


-- only used for external clock messages. Otherwise we just set stop directly
function clock.transport.stop()
  stop = true
end


function reset_pattern() -- todo: Also have the chord readout updated (move from advance_chord_seq to a function)
  transport_state = 'stopped'
  print(transport_state)
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  reset_clock()
  get_next_chord()
  chord_raw = next_chord
  gen_dash('reset_pattern')
  grid_redraw()
  redraw()
end


function reset_arrangement() -- todo: Also have the chord readout updated (move from advance_chord_seq to a function)
  arranger_queue = nil
  arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
  arranger_seq_position = 0
  if arranger_seq[1] > 0 then pattern = arranger_seq[1] end
  if params:string('arranger_enabled') == 'True' then arranger_active = true end
  reset_pattern()
end


function reset_clock()
  clock_step = -1
  -- Immediately update this so if Arranger is zeroed we can use the current-set pattern (even if paused)
  gen_arranger_seq_padded()
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


function advance_chord_seq()
  chord_seq_retrig = true -- indicates when we're on a new chord seq step for CV harmonizer auto-rest logic
  play_arp = true
  local arrangement_reset = false

  -- Advance arranger sequence if enabled
  if params:string('arranger_enabled') == 'True' then

    -- If it's post-reset or at the end of chord sequence
    -- TODO: Really need a global var for when in a reset state (arranger_seq_position == 0 and chord_seq_position == 0)
    if (arranger_seq_position == 0 and chord_seq_position == 0) or chord_seq_position >= chord_pattern_length[pattern] then
      
      -- This variable is only set when the 'arranger_enabled' param is 'True' and we're moving into a new Arranger segment (or after reset)
      arranger_active = true
      
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        arrangement_reset = true
        reset_arrangement()
        stop = true
      else
        -- changed from wrap to a check if incremented arranger_seq_position exceeds seq_length
        arranger_seq_position = arranger_seq_padded[arranger_queue] ~= nil and arranger_queue or (arranger_seq_position + 1 > arranger_seq_length) and 1 or arranger_seq_position + 1
        pattern = arranger_seq_padded[arranger_seq_position]
        arranger_queue = nil
      end
      
      -- Indicates arranger has moved to new pattern.
      arranger_seq_retrig = true
    end
    -- Flag if arranger is on the last pattern of a 1-shot sequence
    arranger_ending()
  end
  
  -- If arrangement was not just reset, update chord position. 
  if arrangement_reset == false then
    if chord_seq_position >= chord_pattern_length[pattern] or arranger_seq_retrig then
      if pattern_queue then
        pattern = pattern_queue
        pattern_queue = false
      end
      chord_seq_position = 1
      arranger_seq_retrig = false
    else  
      chord_seq_position = util.wrap(chord_seq_position + 1, 1, chord_pattern_length[pattern])
    end

    if arranger_active then
      do_events()
      gen_dash('advance_chord_seq')
    end
    
    update_chord()

    -- Play the chord
    if chord_seq[pattern][chord_seq_position] > 0 then play_chord(params:string('chord_dest'), params:get('chord_midi_ch')) end
    
    if chord_key_count == 0 then
      chord_no = current_chord_c + (params:get('chord_type') == 4 and 7 or 0)
      gen_chord_readout()
    end

  end
end


function arranger_ending()
  arranger_one_shot_last_pattern = arranger_seq_position >= arranger_seq_length and params:string('playback') == 'One-shot'
end


-- Checks each time arrange_enabled param changes to see if we need to also immediately set the corresponding arranger_active var to false. arranger_active will be false until Arranger is re-synched/resumed.
-- Also sets pattern_queue to false to clear anything previously set
function update_arranger_active()
  if params:string('arranger_enabled') == 'False' then 
    arranger_active = false
  elseif params:string('arranger_enabled') == 'True' then
    if chord_seq_position == 0 then arranger_active = true end
    pattern_queue = false
  end
  gen_dash('update_arranger_active')
end  


function do_events()
  if arranger_seq_position == 0 then
    print('arranger_seq_position = 0')
  end
  
  if chord_seq_position == 0 then
    print('chord_seq_position = 0')
  end  
  
  if events[arranger_seq_position] ~= nil then
    if events[arranger_seq_position][chord_seq_position].populated or 0 > 0 then
      for i = 1, 16 do
        local event_path = events[arranger_seq_position][chord_seq_position][i]
        if event_path ~= nil and math.random() <= event_path.probability / 100 then
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
                params:set(event_name, math.random(limit_min, limit_max))
              else
                -- This makes sure we pick up the latest range in case it has changed since event was saved (pset load)
                params:set(event_name, math.random(event_range[1], event_range[2]))
              end  
            end
          else -- functions
            _G[event_name](value)
          end
          
          if action ~= nil then
            _G[action](action_var)
          end
          
        end
        
      end
    end
  end
end


-- todo: More thoughtful display of either sharps or flats depending on mode and key
function gen_chord_readout()
  if chord_no > 0 then
    local chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_no]
    local chord_name = musicutil.NOTE_NAMES[util.wrap((musicutil.SCALES[params:get('mode')]['intervals'][util.wrap(chord_no, 1, 7)] + 1) + params:get('transpose'), 1, 12)]
    local modifier = get_chord_name(1 + 1, params:get('mode'), chord_degree) -- transpose root?
    chord_readout = params:string('chord_readout') == 'Degree' and chord_degree or chord_name .. modifier
  end
end  


function update_chord()
-- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord. 
-- Mode is always updated in case no chord has been set but user has changed Mode param.
-- todo p3 efficiency test on this vs if/then
  current_chord_o = chord_seq[pattern][chord_seq_position] > 0 and (chord_seq[pattern][chord_seq_position] > 7 and 1 or 0) or current_chord_o
  current_chord_c = chord_seq[pattern][chord_seq_position] > 0 and util.wrap(chord_seq[pattern][chord_seq_position], 1, 7) or current_chord_c
  chord_raw = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  -- chord transformations
  invert_chord()
  spread_chord()  
end

-- Makes a copy of the base chord table with inversion applied
function invert_chord()
  chord_transformed = {}
  for i = 1,params:get('chord_type') do
    chord_transformed[i] = chord_raw[i]
  end  

  if params:get('chord_inversion') ~= 0 then
    for i = 1,params:get('chord_inversion') do
      local index = util.wrap(i, 1, #chord_transformed) --params:get('chord_type'))
      chord_transformed[index] = chord_transformed[index] + 12
    end
    -- Re-sort them so we can apply additional transformations later
    table.sort(chord_transformed)
  end
end  


-- Applies note spread to chord (in octaves)
function spread_chord()
  if params:get('chord_spread') ~= 0 then
    for i = 1,#chord_transformed do
      chord_transformed[i] = chord_transformed[i] + round((params:get('chord_spread') / (params:get('chord_type') - 1) * (i - 1))) * 12
    end
  end
end


-- This triggers when mode param changes and allows arp and harmonizers to pick up the new mode immediately. Doesn't affect the chords and doesn't need chord transformations since the chord advancement will overwrite
function update_chord_action()
  chord_raw = musicutil.generate_chord_scale_degree(current_chord_o * 12, params:get('mode'), current_chord_c, true)
  next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
end


function play_chord(destination, channel)
  local destination = params:string('chord_dest')
  if destination == 'Engine' then
    for i = 1, params:get('chord_type') do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_engine('chord', note)
    end
  elseif destination == 'MIDI' then
    local channel = params:get('chord_midi_ch')
    local port = params:get('chord_midi_out_port')
    for i = 1, params:get('chord_type') do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_midi(note, params:get('chord_midi_velocity'), channel, chord_duration, port)
    end
  elseif destination == 'Crow' then
    for i = 1, params:get('chord_type') do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_crow('chord',note)
    end
  elseif destination =='ii-JF' then
    for i = 1, params:get('chord_type') do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_jf('chord',note, params:get('chord_jf_amp')/10)
    end
  elseif destination == 'Disting' then
    for i = 1, params:get('chord_type') do
      local note = chord_transformed[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_disting(note, params:get('chord_disting_velocity'), chord_duration)
    end    
  end
end


-- Pre-load upcoming chord to address race condition around quantize_note() events occurring before chord change
function get_next_chord()
  local pre_arrangement_reset = false
  local pre_arranger_seq_position = arranger_seq_position
  local pre_arranger_seq_retrig = arranger_seq_retrig
  local pre_chord_seq_position = chord_seq_position
  local pre_pattern_queue = pattern_queue
        pre_pattern = pattern

  -- Move arranger sequence if enabled
  if params:get('arranger_enabled') == 1 then

    -- If it's post-reset or at the end of chord sequence
    if (pre_arranger_seq_position == 0 and pre_chord_seq_position == 0) or pre_chord_seq_position >= chord_pattern_length[pre_pattern] then
      
      -- Check if it's the last pattern in the arrangement.
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        pre_arrangement_reset = true
      else
        pre_arranger_seq_position = arranger_seq_padded[arranger_queue] ~= nil and arranger_queue or util.wrap(pre_arranger_seq_position + 1, 1, arranger_seq_length)
        pre_pattern = arranger_seq_padded[pre_arranger_seq_position]
        
      end
      
      -- Indicates arranger has moved to new pattern.
      pre_arranger_seq_retrig = true
    end
    
  end
  
  -- If arrangement was not just reset, update chord position. 
  if pre_arrangement_reset == false then
    if pre_chord_seq_position >= chord_pattern_length[pre_pattern] or pre_arranger_seq_retrig then
      if pre_pattern_queue then
        pre_pattern = pre_pattern_queue
        pre_pattern_queue = false
      end
      pre_chord_seq_position = 1
      pre_arranger_seq_retrig = false
    else  
      pre_chord_seq_position = util.wrap(pre_chord_seq_position + 1, 1, chord_pattern_length[pre_pattern])
    end
    
    -- Arranger automation step. todo: examine impact of running some events here rather than in advance_chord_seq
    -- Could be important for anything that changes patterns but might also be weird for grid redraw

    -- Update the chord. Only updates the octave and chord # if the Grid pattern has something, otherwise it keeps playing the existing chord. 
    -- Mode is always updated in case no chord has been set but user has changed Mode param.
    -- todo p3 efficiency test vs if/then
      next_chord_o = chord_seq[pre_pattern][pre_chord_seq_position] > 0 and (chord_seq[pre_pattern][pre_chord_seq_position] > 7 and 1 or 0) or next_chord_o
      next_chord_c = chord_seq[pre_pattern][pre_chord_seq_position] > 0 and util.wrap(chord_seq[pre_pattern][pre_chord_seq_position], 1, 7) or next_chord_c
      next_chord = musicutil.generate_chord_scale_degree(next_chord_o * 12, params:get('mode'), next_chord_c, true)
    
  end
end

    
-- Used for CV/MIDI harmonizers to quantize per upcoming chord.
function pre_quantize_note(note_num, source)
  local chord_length = params:get(source..'_chord_type') -- Move upstream?
  local source_octave = params:get(source..'_octave') -- Move upstream?
  local quantized_note = next_chord[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((source_octave + quantized_octave) * 12) + params:get('transpose'))
end


function quantize_note(note_num, source)
  local chord_length = params:get(source..'_chord_type') -- Move upstream?
  local source_octave = params:get(source..'_octave') -- Move upstream?
  local quantized_note = chord_raw[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((source_octave + quantized_octave) * 12) + params:get('transpose'))
end


function advance_arp_seq()
  if arp_seq_position > arp_pattern_length[arp_pattern] or arranger_seq_retrig == true then
    arp_seq_position = 1
  else  
    arp_seq_position = util.wrap(arp_seq_position + 1, 1, arp_pattern_length[arp_pattern])
  end

  if arp_seq[arp_pattern][arp_seq_position] > 0 then
    local destination = params:string('arp_dest')
    local note = quantize_note(arp_seq[arp_pattern][arp_seq_position], 'arp')
    if destination == 'Engine' then
      to_engine('arp', note)
    elseif destination == 'MIDI' then
      local channel = params:get('arp_midi_ch')
      local port = params:get('arp_midi_out_port')
      to_midi(note, params:get('arp_midi_velocity'), channel, arp_duration, port)
    elseif destination == 'Crow' then
      to_crow('arp',note)
    elseif destination == 'ii-JF' then
      to_jf('arp',note, params:get('arp_jf_amp')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('arp_disting_velocity'), arp_duration)
    end
  end
  
  if params:string('arp_mode') == 'One-shot' and arp_seq_position >= arp_pattern_length[arp_pattern] then
     play_arp = false
  else
  end   
end


function crow_trigger() --Trigger in used to sample voltage from Crow IN 1
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
end


function sample_crow(volts)
  local note = params:get('chord_preload') == 0 and quantize_note(round(volts * 12, 0) + 1, 'crow') or pre_quantize_note(round(volts * 12, 0) + 1, 'crow')
  
  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_seq_retrig == true
  or params:get('do_crow_auto_rest') == 0 
  or (params:get('do_crow_auto_rest') == 1 and (prev_note ~= note)) then
    -- Play the note
    local destination = params:string('crow_dest')
    if destination == 'Engine' then
      to_engine('crow', note)
    elseif destination == 'MIDI' then
      local channel = params:get('crow_midi_ch')
      local port = params:get('crow_midi_out_port')
      to_midi(note, params:get('crow_midi_velocity'), channel, crow_duration, port)
    elseif destination == 'Crow' then
      to_crow('crow', note)
    elseif destination =='ii-JF' then
      to_jf('crow',note, params:get('crow_jf_amp')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('crow_disting_velocity'), crow_duration)      
    end
  end
  
  prev_note = note
  chord_seq_retrig = false -- Resets at chord advance
end


--midi harmonizer input
midi_event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    local note = params:get('chord_preload') == 0 and quantize_note(d.note - 35, 'midi') or pre_quantize_note(d.note - 35, 'midi')
    local destination = params:string('midi_dest')
    if destination == 'Engine' then
      to_engine('midi', note)
    elseif destination == 'MIDI' then
      local channel = params:get('midi_midi_ch')
      local port = params:get('midi_midi_out_port')
      to_midi(note, params:get('do_midi_velocity_passthru') == 1 and d.vel or params:get('midi_midi_velocity'), channel, midi_duration, port)
    elseif destination == 'Crow' then
      to_crow('midi', note)
    elseif destination =='ii-JF' then
      to_jf('midi', note, params:get('midi_jf_amp')/10)
    elseif destination == 'Disting' then
      to_disting(note, params:get('midi_disting_velocity'), midi_duration)      
    end
  end
end
  
  
function to_engine(source, note)
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
    note_hz = math.min(musicutil.note_num_to_freq(note + 36), 24000)
    engine.amp(params:get(source..'_pp_amp') / 100)
    engine.cutoff(note_hz * params:get(source..'_pp_tracking') *.01 + params:get(source..'_pp_cutoff'))
    engine.release(duration_sec(_G[source .. '_duration']))

    engine.gain(params:get(source..'_pp_gain') / 100)
    engine.pw(params:get(source..'_pp_pw') / 100)
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
  
  -- Play note and insert new note-on record if appropriate
  if midi_play_note == true then
    midi_device[port]:note_on((midi_note), velocity, channel)
  end
  if midi_note_history_insert == true then
    table.insert(midi_note_history, {duration, midi_note, channel, note_on_time, port})
  end
end


function to_crow(source, note)
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
    if params:get(source..'_tr_env') == 1 then  -- Trigger
      crow.output[2].action = 'pulse(.001,10,1)' -- (time,level,polarity)
    else -- envelope
      local crow_attack = duration_sec(_G[source .. '_duration']) * params:get(source..'_ad_skew') / 100
      local crow_release = duration_sec(_G[source .. '_duration']) * (100 - params:get(source..'_ad_skew')) / 100
      crow.output[2].action = 'ar(' .. crow_attack .. ',' .. crow_release .. ',10)'  -- (attack,release,shape) SHAPE is bugged?
    end
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
      local jf_time_s = math.exp(-0.694351 * jf_time + 3.0838) -- jf_time_v_to_s. Should check code to see actuals
      print('jf_time_s = ' .. jf_time_s)
      -- return(jf_time_s)   
      end
  )
  
end


function to_jf(source, note, amp)
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
  
  -- Play note and insert new note-on record if appropriate
  if disting_play_note == true then
    -- print('disting_note ' .. disting_note .. '  |  velocity ' .. velocity)
      crow.ii.disting.note_pitch( disting_note, (disting_note-48)/12)
      crow.ii.disting.note_velocity( disting_note, velocity/10)    
  end
  if disting_note_history_insert == true then
    table.insert(disting_note_history, {duration, disting_note,  note_on_time})
  end
end


function grid_redraw()
  g:all(0)
  
  -- Events supercedes other views
  if screen_view_name == 'Events' then
    
  -- Draw grid with 16 event lanes (columns) for each step in the selected pattern 
    for x = 1, 16 do -- event lanes
      for y = 1,8 do -- pattern steps
        g:led(x, y, (events[event_edit_pattern][y][x] ~= nil and 7 or (y > (chord_pattern_length[arranger_seq_padded[event_edit_pattern]] or 0) and 0 or 2)))
        if y == event_edit_step and x == event_edit_lane then
          g:led(x, y, 15)
        end  
      end
  end

  else
    for i = 6,8 do
      g:led(16,i,4)
    end
    
    for i = 1, #grid_view_keys do
      g:led(16,grid_view_keys[i], 7)
    end  
    
    if grid_view_name == 'Arranger' then
      g:led(16,6,15)
      
      
      ----------------------------------------------------------------------------
      -- Arranger shifting rework here
      ----------------------------------------------------------------------------
      -- todo p3 limit how far off the screen we can shift for when encoders flip out
      if arranger_loop_key_count > 0 then
        x_draw_shift = 0
        local within_seq = event_edit_pattern <= arranger_seq_length -- some weird stuff needs to be handled if user is shifting events past the end of the pattern length
        if d_cuml >= 0 then -- Shifting arranger pattern to the right and opening up this many segments between event_edit_pattern and event_edit_pattern + d_cuml
   
        ------------------------------------------------
        -- positive d_cuml shifts arranger to the right and opens a gap
        ------------------------------------------------
        -- x_offsets fall into 3 groups:
        --  >= event_edit_pattern + d_cuml will shift to the right by d_cuml segments
        --  < event_edit_pattern draw as usual
        --  Remaining are in the "gap" and we need to grab the previous pattern and repeat it
          for x = 16, 1, -1 do -- draw from right to left
            local x_offset = x + arranger_grid_offset -- Grid x + the offset for whatever page or E1 shift is happening

            for y = 1,4 do
              g:led(x, y, x_offset == arranger_seq_position and 6                                               -- playhead
                or x_offset == arranger_queue and 4                                                             -- queued
                or x_offset <= (arranger_seq_length + (within_seq and d_cuml or 0)) and 2                       -- seq length
                or 0)
            end
            
            -- group 1.
            if x_offset >= event_edit_pattern + d_cuml then
              local x_offset = x_offset - d_cuml
              for y = 1,4 do -- patterns
                if within_seq then
                  if y == arranger_seq_padded[x_offset] then g:led(x, y, x_offset == arranger_seq_position and 9 or 7) end -- dim padded segments
                end
                if y == arranger_seq[x_offset] then g:led(x, y, 15) end -- regular segments
              end
              -- if x == 3 then print('1') end
              g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_seq_length and 3 or 7) -- events
              
            elseif x_offset < event_edit_pattern then
              for y = 1,4 do -- patterns
                if y == arranger_seq_padded[x_offset] then g:led(x, y, x_offset == arranger_seq_position and 9 or 7) end -- dim padded segments
                if y == arranger_seq[x_offset] then g:led(x, y, 15) end -- regular segments
              end
              -- if x == 3 then print('2') end
              g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_seq_length and 3 or 7) -- events
              
            else
              -- no need to do anything with patterns if extending beyond arranger_seq_length
              -- can still move around events beyond
              if within_seq then
                local pattern_padded = arranger_seq_padded[math.max(event_edit_pattern - 1, 1)]
                for y = 1,4 do -- patterns
                  if y == pattern_padded then g:led(x, y, x_offset == arranger_seq_position and 9 or 7) end
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
        --  >= event_edit_pattern + d_cuml will shift to the left by d_cuml segments
        --  < event_edit_pattern + d_cuml are drawn as usual
        else
          for x = 1, 16 do
            local x_offset = x + arranger_grid_offset -- Grid x + the offset for whatever page or E1 shift is happening
            
            -- draw playhead, arranger_queue, adjusted sequence length, blanks
            if within_seq then
              for y = 1,4 do 
                g:led(x, y, x_offset == arranger_seq_position and 6                                             -- playhead
                  or x_offset == arranger_queue and 4                                                           -- queued
                  or x_offset <= (arranger_seq_length + d_cuml) and 2                                           -- seq length
                  or 0)                                    
              end
            else
              for y = 1,4 do
                g:led(x, y, x_offset == arranger_seq_position and 6                                             -- playhead
                  or x_offset == arranger_queue and 4                                                           -- queued
                  or x_offset <= arranger_seq_length and x_offset < (d_cuml + event_edit_pattern) and 2         -- seq length
                  or 0)
              end              
            end  

            -- Redefine x_offset only for group #1: patterns that need to be shifted left. Group 2 will be handled as usual
            local x_offset = (x_offset >= event_edit_pattern + d_cuml) and (x_offset - d_cuml) or x_offset
            for y = 1,4 do -- patterns
              if y == arranger_seq_padded[x_offset] then g:led(x, y, x_offset == arranger_seq_position and 9 or 7) end -- dim padded segments
              if y == arranger_seq[x_offset] then g:led(x, y, 15) end -- regular segments
            end
            g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_seq_length and 3 or 7) -- events
          end -- of drawing for negative d_cuml shift              
        end
      
      else -- arranger_loop_key_count == 0: no arranger shifting
        for x = 1, 16 do
          local x_offset = x + arranger_grid_offset
          for y = 1,4 do
            g:led(x,y, x_offset == arranger_seq_position and 6 or x_offset == arranger_queue and 4 or x_offset <= arranger_seq_length and 2 or 0)
            if y == arranger_seq_padded[x_offset] then g:led(x, y, x_offset == arranger_seq_position and 9 or 7) end
            if y == arranger_seq[x_offset] then g:led(x, y, 15) end
          end
          -- Events strip
          g:led(x, 5, (events[x_offset] ~= nil and events[x_offset].populated or 0) > 0 and 15 or x_offset > arranger_seq_length and 3 or 7)
        end
      end
  

      g:led(1,8, params:get('arranger_enabled') == 1 and 15 or 4)
      -- -- Optionally: Arranger enable/disable key has 3 states. on/re-sync/off
      -- if params:get('arranger_enabled') == 1 then
      --   if arranger_active == false then
      --     g:led(1,8, (fast_blinky * 5) + 10)
      --   else
      --     g:led(1,8, 15)
      --   end
      -- else
      --   g:led(1,8, 4)
      -- end

        g:led(2,8, params:get('playback') == 1 and 15 or 4)
        
      -- More sophisticated pagination with scroll indicator for arranger grid view
      -- for i = 0,3 do
      --   local target = i * 16
      --   g:led(i + 7, 8 , math.max(10 + util.round((math.min(target, arranger_grid_offset) - math.max(target, arranger_grid_offset))/2), 2) + 2)
      -- end
      for i = 7, 10 do
        g:led(i, 8, 4)
      end
      
      if arranger_grid_offset == 0 then g:led(7, 8, 15)
      elseif arranger_grid_offset == 16 then g:led(8, 8, 15)    
      elseif arranger_grid_offset == 32 then g:led(9, 8, 15)
      elseif arranger_grid_offset == 48 then g:led(10, 8, 15)
      end  
      
    elseif grid_view_name == 'Chord' then
      if params:string('arranger_enabled') == 'True' and arranger_one_shot_last_pattern == false then
        next_pattern_indicator = arranger_seq_padded[util.wrap(arranger_seq_position + 1, 1, arranger_seq_length)]
      else
        next_pattern_indicator = pattern_queue or pattern
      end
    for i = 1,4 do
      g:led(16, i, i == next_pattern_indicator and 7 or pattern_keys[i] and 7 or 3) 
      if i == pattern then
        g:led(16, i, 15)
      end
    end
      g:led(16,7,15)
      for i = 1,14 do                                                   -- chord seq playhead
        g:led(i, chord_seq_position, 3)
      end
      for i = 1,8 do
        g:led(15, i, chord_pattern_length[pattern] < i and 4 or 15)     --set pattern_length LEDs
        if chord_seq[pattern][i] > 0 then                               -- muted steps
          g:led(chord_seq[pattern][i], i, 15)                         -- set LEDs for chord sequence
        end
      end
      
    elseif grid_view_name == 'Arp' then
      g:led(16,8,15)
      for i = 1,14 do                                                   -- chord seq playhead
        g:led(i, arp_seq_position, 3)
      end
      for i = 1,8 do
        g:led(15, i, arp_pattern_length[arp_pattern] < i and 4 or 15)   --set pattern_length LEDs
        if arp_seq[arp_pattern][i] > 0 then                             -- muted steps
          g:led(arp_seq[arp_pattern][i], i, 15)                         --set LEDs for arp sequence
        end
      end
    end
  end
  g:refresh()
end


-- GRID KEYS
function g.key(x,y,z)
  if z == 1 then

    if screen_view_name == 'Events' then
      -- Setting of events past the pattern length is permitted
      event_key_count = event_key_count + 1
      
        -- function g.key events loading
        -- First touched event is the one we edit, effectively resetting on key_count = 0
        if event_key_count == 1 then
          event_edit_step = y
          event_edit_lane = x
          event_saved = false

          local events_path = events[event_edit_pattern][y][x]
          if events_path == nil then
            event_edit_status = '(New)'
          else
            event_edit_status = '(Saved)'
          end

          -- If the event is populated, Load the Event vars back to the displayed param. Otherwise keep the last touched event's settings so we can iterate quickly.
          if events_path ~= nil then
            
            events_index = 1
            selected_events_menu = events_menus[events_index]

            local id = events_path.id
            local index = events_lookup_index[id]
            local value = events_path.value
            local operation = events_path.operation
            local limit = events_path.limit or 'Off'

            params:set('event_category', param_option_to_index('event_category', events_lookup[index].category))
            params:set('event_subcategory', param_option_to_index('event_subcategory', events_lookup[index].subcategory))
            params:set('event_name', index)
            params:set('event_operation', param_option_to_index('event_operation', operation))
            if operation == 'Random' then
              print('Random operation, setting limit ' .. limit)
              params:set('event_op_limit_random', param_option_to_index('event_op_limit_random', limit))
            else
              print('Not random operation, setting limit ' .. limit)
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
          
          -- But first check if the events we're working with are populated
          local og_event_populated = events_path ~= nil
          local copied_event_populated = events[event_edit_pattern][event_edit_step][event_edit_lane] ~= nil

          -- Then copy
          events[event_edit_pattern][y][x] = deepcopy(events[event_edit_pattern][event_edit_step][event_edit_lane])
          
          -- Adjust populated events count at the step level. todo: also set at the segment level once implemented
          if og_event_populated and not copied_event_populated then
            events[event_edit_pattern][y].populated = events[event_edit_pattern][y].populated - 1
            
            -- If the step's new populated count == 0, decrement count of populated event STEPS in the segment
            if (events[event_edit_pattern][y].populated or 0) == 0 then 
              events[event_edit_pattern].populated = (events[event_edit_pattern].populated or 0) - 1
            end
          elseif not og_event_populated and copied_event_populated then
            events[event_edit_pattern][y].populated = (events[event_edit_pattern][y].populated or 0) + 1

            -- If this is the first event to be added to this step, increment count of populated event STEPS in the segment
            if (events[event_edit_pattern][y].populated or 0) == 1 then
              print('incrementing segment populated')
              events[event_edit_pattern].populated = (events[event_edit_pattern].populated or 0) + 1
            end
          end
          
          print('Copy+paste event from segment ' .. event_edit_pattern .. '.' .. event_edit_step .. ' lane ' .. event_edit_lane  .. ' to ' .. event_edit_pattern .. '.' .. y .. ' lane ' .. x)
        end

    -- view_key buttons  
    elseif x == 16 and y > 5 then
      view_key_count = view_key_count + 1
      table.insert(grid_view_keys, y)
      if view_key_count == 1 then 
        grid_view_name = grid_views[y - 5] 
      elseif view_key_count > 1 and (grid_view_keys[1] == 7 and grid_view_keys[2] == 8) or (grid_view_keys[1] == 8 and grid_view_keys[2] == 7) then
          screen_view_name = 'Chord+arp'
      end
      
    --ARRANGER KEY DOWN-------------------------------------------------------
    elseif grid_view_name == 'Arranger' then
      local x_offset = x + arranger_grid_offset

      -- enable/disable Arranger
      if x == 1 and y == 8 then
        if params:get('arranger_enabled') == 0 then
          params:set('arranger_enabled',1)
        else
          params:set('arranger_enabled',0)
        end

      -- Switch between Arranger playback Loop or One-shot mode
      elseif x == 2 and y == 8 then
        if params:get('playback') == 1 then
          params:set('playback',2)
        else
          params:set('playback',1)
        end
        
      -- Arranger pagination jumps
      elseif y == 8 then
        if x > 6 and x < 11 then
          arranger_grid_offset = (x -7) * 16
        end
        
      -- Arranger events strip key down
      elseif y == 5 then
        arranger_loop_key_count = arranger_loop_key_count + 1

        -- First touched pattern is the one we edit, effectively resetting on key_count = 0
        if arranger_loop_key_count == 1 then
          event_edit_pattern = x_offset

        -- Subsequent keys down paste all arranger events in segment, but not the segment pattern
        -- arranger shift interaction will block this
        elseif interaction == nil then
          events[x_offset] = deepcopy(events[event_edit_pattern])
          print('Copy+paste events from segment ' .. event_edit_pattern .. ' to segment ' .. x)
          gen_dash('Event copy+paste')
        end
        
      -- ARRANGER SEGMENT PATTERNS
      elseif y < 5 then
        if y == arranger_seq[x_offset]then
          arranger_seq[x_offset] = 0
        else
          arranger_seq[x_offset] = y
        end  
        gen_arranger_seq_padded()
        
      end
      if transport_active == false then -- Update chord for when play starts
        get_next_chord()
        chord_raw = next_chord
      end
      
    --CHORD KEYS
    elseif grid_view_name == 'Chord' then
      if x < 15 then
        chord_key_count = chord_key_count + 1
        if x == chord_seq[pattern][y] then
          chord_seq[pattern][y] = 0
        else
          chord_seq[pattern][y] = x
        end
        chord_no = util.wrap(x,1,7) + (params:get('chord_type') == 4 and 7 or 0) -- or 0
        gen_chord_readout()
        
      -- set chord_pattern_length  
      elseif x == 15 then
        chord_pattern_length[pattern] = y
        gen_dash('g.key chord_pattern_length')

      elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher. Key UP events farther down in function.
        pattern_key_count = pattern_key_count + 1
        pattern_keys[y] = 1
        if pattern_key_count == 1 then
          pattern_copy_source = y
        elseif pattern_key_count > 1 then
          print('Copying pattern ' .. pattern_copy_source .. ' to pattern ' .. y)
          pattern_copy_performed = true
          -- todo: deepcopy
          for i = 1,8 do
            chord_seq[y][i] = chord_seq[pattern_copy_source][i]
          end
          chord_pattern_length[y] = chord_pattern_length[pattern_copy_source]
        end
      end
      if transport_active == false then -- Pre-load chord for when play starts
        get_next_chord()
        chord_raw = next_chord
      end
      
    -- ARP KEYS
    elseif grid_view_name == 'Arp' then
      if x < 15 then
        if x == arp_seq[arp_pattern][y] then
          arp_seq[arp_pattern][y] = 0
        else
          arp_seq[arp_pattern][y] = x
          grid_dirty = true
        end
      elseif x == 15 then
        arp_pattern_length[arp_pattern] = y
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
          screen_view_name = 'Chord+arp'
        else
          screen_view_name = 'Session'  
        end
      else
        screen_view_name = 'Session'
      end

    -- Chord key up      
    elseif grid_view_name == 'Chord' then
      if x == 16 and y <5 then
        pattern_key_count = math.max(pattern_key_count - 1,0)
        pattern_keys[y] = nil
        if pattern_key_count == 0 and pattern_copy_performed == false then
          
          -- Resets current pattern immediately
          if y == pattern then
            print('Manual reset of current pattern; disabling arranger')
            params:set('arranger_enabled', 0)
            pattern_queue = false
            arp_seq_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_external_clock()
            reset_pattern()
            
          -- Manual jump to queued pattern  
          elseif y == pattern_queue then
            print('Manual jump to queued pattern')
            
            pattern_queue = false
            pattern = y
            arp_seq_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_external_clock()
            reset_pattern()

          -- Cue up a new pattern        
          else                       
            print('New pattern queued; disabling arranger')
            if pattern_copy_performed == false then
              pattern_queue = y
              params:set('arranger_enabled', 0)
            end
          end
        end
      elseif x < 15 then
        chord_key_count = chord_key_count - 1
        if chord_key_count == 0 then
          -- This reverts the chord readout to the currently loaded chord but it is kinda confusing when paused so now it just wipes and refreshes at the next chord step.
          -- chord_no = current_chord_c + (params:get('chord_type') == 4 and 7 or 0)          
          -- gen_chord_readout()
          chord_no = 0
        end
      end
    
    -- Arranger key up  
    elseif grid_view_name == 'Arranger' then
      -- Arranger loop strip
      if y == 5 then
        arranger_loop_key_count = math.max(arranger_loop_key_count - 1, 0)
        
        
        -- Insert/remove patterns/events after arranger shift with K3
        if arranger_loop_key_count == 0 then --only do the copy after the last key is released so we don't keep resetting d_cuml if multiple events are held for some reason
          if d_cuml > 0 then
            for i = 1, d_cuml do
              table.insert(arranger_seq, event_edit_pattern, 0)
              table.remove(arranger_seq, max_arranger_seq_length + 1)
              table.insert(events, event_edit_pattern, nil)
              events[event_edit_pattern] = {{},{},{},{},{},{},{},{}}
              table.remove(events, max_arranger_seq_length + 1)
            end
            gen_arranger_seq_padded()
            d_cuml = 0
  
          elseif d_cuml < 0 then
            for i = 1, math.abs(d_cuml) do --math.min(math.abs(d_cuml), 1) do
              table.remove(arranger_seq, math.max(event_edit_pattern - i, 1))
              table.insert(arranger_seq, 0)
              table.remove(events, math.max(event_edit_pattern - i, 1))
              table.insert(events, {})
              events[max_arranger_seq_length] = {{},{},{},{},{},{},{},{}}
            end
            gen_arranger_seq_padded()
            d_cuml = 0
          end
        interaction = nil
        end
        
      end
    end
  
    if pattern_key_count == 0 then
      pattern_copy_performed = false
    end
  end
  redraw()
  grid_redraw()
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
      if arranger_loop_key_count > 0 and interaction == nil then
        arranger_queue = event_edit_pattern
        grid_redraw()
      
      elseif screen_view_name == 'Events' then
        ------------------------
        -- K2 DELETE EVENT
        ------------------------
        if event_edit_active then

          -- Record the count of events on this step
          local event_count = events[event_edit_pattern][event_edit_step].populated or 0
          
          -- Check if event is populated and needs to be deleted
          if events[event_edit_pattern][event_edit_step][event_edit_lane] ~= nil then
            
            -- Decrement populated count at the step level
            events[event_edit_pattern][event_edit_step].populated = event_count - 1
            
            -- If the step's new populated count == 0, update the segment level populated count
            if events[event_edit_pattern][event_edit_step].populated == 0 then 
              events[event_edit_pattern].populated = events[event_edit_pattern].populated - 1 
            end
            
            -- Delete the event
            events[event_edit_pattern][event_edit_step][event_edit_lane] = nil
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
          
        -- K2 here deletes ALL events in arranger SEGMENT
        else
          for step = 1,8 do
            events[event_edit_pattern][step] = {}
          end
            events[event_edit_pattern].populated = 0
          
          screen_view_name = 'Session'
        end
        gen_dash('K2 events editor closed') -- update events strip in dash after making changes in events editor
        grid_redraw()
        
        
      ----------------------------------------
      -- Transport controls K2 - STOP/RESET --
      ----------------------------------------
        
      elseif interaction == nil then

        if params:string('clock_source') == 'internal' then
          -- print('internal clock')
          if transport_state == 'starting' or transport_state == 'playing' then
            stop = true
            transport_state = 'pausing'
            print(transport_state)        
            clock_start_method = 'continue'
            -- 2023-06-30 removing start = true. Not sure why I was doing this 
            -- start = true
          elseif transport_state == 'pausing' or transport_state == 'paused' then
            reset_external_clock()
            if params:get('arranger_enabled') == 1 then
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
          elseif transport_state == 'paused' then
            if params:get('arranger_enabled') == 1 then
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
          elseif transport_state == 'pausing' or transport_state == 'paused' then
            reset_external_clock()
            if params:get('arranger_enabled') == 1 then
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
        if screen_view_name == 'Chord+arp' then
        
          -- When Chord+Arp Grid View keys are held down, K3 runs Generator and resets pattern+arp
          generator()
          
          -- If we're sending MIDI clock out, send a stop msg. This has changed with the multi clock Norns update. Needs testing.
          -- Tell the transport to Start on the next sync of sequence_clock
          if #midi_transport_ports >0 then
            
            if transport_active then
              transport_multi_stop()
            end
            
          -- Tells sequence_clock to send a MIDI start/continue message after initial clock sync
          clock_start_method = 'start'
          start = true
          end    
    
          -- For now, doing a pattern reset but not an arranger reset since it's confusing if we generate on, say, pattern 3 and then Arranger is reset and we're now on pattern 1.
          -- if params:get('arranger_enabled') == 1 then reset_arrangement() else reset_pattern() end
          reset_pattern()
          
        elseif grid_view_name == 'Chord' then       
          chord_generator_lite()
          -- gen_dash('chord_generator_lite') -- will run when called from event but not from keys
        elseif grid_view_name == 'Arp' then       
          arp_generator('run')
        end
      grid_redraw()
      
      ---------------------------------------------------------------------------
      -- Event Editor --
      -- K3 with Event Timeline key held down enters Event editor / function key event editor
      ---------------------------------------------------------------------------        
      elseif arranger_loop_key_count > 0 and interaction == nil then -- blocked by d_cuml if shifting arranger
        arranger_loop_key_count = 0        
        event_edit_step = 0
        event_edit_lane = 0
        event_edit_active = false
        screen_view_name = 'Events'
        grid_redraw()
  
      -- K3 saves event to events
      elseif screen_view_name == 'Events' then
        
        ---------------------------------------
        -- K3 TO SAVE EVENT
        ---------------------------------------
        -- print('event_edit_active ' .. (event_edit_active and 'true' or 'false'))
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
          local step_event_count = events[event_edit_pattern][event_edit_step].populated or 0

          -- If we're saving over a previously-nil event, increment the step populated count          
          if events[event_edit_pattern][event_edit_step][event_edit_lane] == nil then
            events[event_edit_pattern][event_edit_step].populated = step_event_count + 1

            -- Also check to see if we need to increment the count of populated event STEPS in the SEGMENT
            if (events[event_edit_pattern][event_edit_step].populated or 0) == 1 then
              events[event_edit_pattern].populated = (events[event_edit_pattern].populated or 0) + 1
            end
          end

          -- Wipe existing events, write the event vars to events
          if value_type == 'trigger' then
            events[event_edit_pattern][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                event_type = event_type,
                value_type = value_type,
                operation = operation,  -- sorta redundant but we do use it to simplify reads
                probability = probability
              }
              
            print('Saving to events[' .. event_edit_pattern ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> probability = ' .. probability)
            
          elseif operation == 'Set' then
            events[event_edit_pattern][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                value = value, 
                probability = probability
              }
              
            print('Saving to events[' .. event_edit_pattern ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')     
            print('>> id = ' .. events_lookup[event_index].id)
            print('>> event_type = ' .. event_type)
            print('>> value_type = ' .. value_type)
            print('>> operation = ' .. operation)
            print('>> value = ' .. value)
            print('>> probability = ' .. probability)
              
          elseif operation == 'Random' then
            if limit == 'Off' then -- so clunky yikes
              events[event_edit_pattern][event_edit_step][event_edit_lane] = 
              {
                id = events_lookup[event_index].id, 
                event_type = event_type, 
                value_type = value_type,
                operation = operation,
                limit = limit, -- note different source here but using the same field for storage              
                probability = probability
              }
              else
              events[event_edit_pattern][event_edit_step][event_edit_lane] = 
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
            
            print('Saving to events[' .. event_edit_pattern ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')       
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
            events[event_edit_pattern][event_edit_step][event_edit_lane] = 
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
            events[event_edit_pattern][event_edit_step][event_edit_lane] = 
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
            print('Saving to events[' .. event_edit_pattern ..'][' .. event_edit_step ..'][' .. event_edit_lane .. ']')       
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
            events[event_edit_pattern][event_edit_step][event_edit_lane].action = action
            events[event_edit_pattern][event_edit_step][event_edit_lane].action_var_1 = action_var_1
            
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
  end
  redraw()
end


-----------------------------------
-- ENCODERS
----------------------------------          
function enc(n,d)
  --todo p1 more refined switching between clamped and raw deltas
  -- local d = util.clamp(d, -1, 1)
  
  -- Reserved for scrolling/extending Arranger, Chord, Arp sequences
  if n == 1 then
    -- ------- SCROLL ARRANGER GRID VIEW--------
    -- if grid_view_name == 'Arranger' then
    --   arranger_grid_offset = util.clamp(arranger_grid_offset + d, 0, max_arranger_seq_length -  16)
    --   grid_redraw()
    -- end
            
  -- n == ENC 2 ------------------------------------------------
  elseif n == 2 then
    if view_key_count > 0 then
      if (grid_view_name == 'Chord' or grid_view_name == 'Arp') then-- Chord/Arp 
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
    if (grid_view_name == 'Chord' or grid_view_name == 'Arp') then-- Chord/Arp 
      transpose_pattern(grid_view_name, d)
      grid_redraw()
    end
      
  ----------------------    
  -- Event editor menus
  ----------------------    
  elseif screen_view_name == 'Events' and event_saved == false then
    
    -- todo p0 can actually do this in the change_ functions so it only fires when there is a new value!
    -- if event_edit_status == '(Saved)' then
    --   event_edit_status = '(Edited)'
    -- end
      
    -- have to manually call these two functions because param actions won't work on them (string changes but not index)
    -- might just drop param actions for all of the event params because the inconsistency is confusing
    if selected_events_menu == 'event_subcategory' then
      params:delta(selected_events_menu, d)
      change_subcategory()  -- no param action (options swap issue) so call directly
    elseif selected_events_menu == 'event_operation' then
      params:delta(selected_events_menu, d)
      change_operation()  -- no param action (options swap issue) so call directly
    elseif selected_events_menu == 'event_name' then
      local value = params:get(selected_events_menu) + d
        if value >= event_subcategory_index_min and value <= event_subcategory_index_max then
          params:set(selected_events_menu, value)
        end
    elseif selected_events_menu == 'event_value' then
      local value = params:get(selected_events_menu) + d
      if params:string('event_operation') == 'Set' then
        if value >= event_range[1] and value <= event_range[2] then
          params:set(selected_events_menu, value)
          edit_status_edited()
        end
      else
        params:set(selected_events_menu, value)
        edit_status_edited()
      end
    elseif selected_events_menu == 'event_op_limit_min' then
      local value = params:get(selected_events_menu) + d
        if value >= event_range[1] and value <= params:get('event_op_limit_max') then
          params:set(selected_events_menu, value)
          edit_status_edited()
        end
    elseif selected_events_menu == 'event_op_limit_max' then
      local value = params:get(selected_events_menu) + d
        if value >= params:get('event_op_limit_min') and value <= event_range[2] then
          params:set(selected_events_menu, value)
          edit_status_edited()
        end        

    -- event_op_limit, event_op_limit_random, event_probability have no function but we do a little extra work to not trigger edit_status_edited() if delta is outside of range. todo p3 can probably do the smae with other stuff using 'event_range['
    else
      local prev_value = params:get(selected_events_menu)
      local value = prev_value + d
      local value_min = params:get_range(selected_events_menu)[1]
      local value_max = params:get_range(selected_events_menu)[2]
      if value >= value_min and value <= value_max then
        params:set(selected_events_menu, value)
        edit_status_edited()
      end
    end
    
  --------------------
  -- Arranger shift --  
  --------------------
  -- moving from arranger keys 1-4 to the arranger loop strip on row 5. This still trips me up but avoids weirdness around handling dual-use keypress (enable/disable vs. entering event editor). Todo p1: have this work for both? I feel like we can use the new interaction global to make sure it doesn't get weird. Will have to set on/off on key up but that is probably fine here.
  
  elseif grid_view_name == 'Arranger' and arranger_loop_key_count > 0 then
    -- Arranger segment detail options are on-screen
    -- block event copy+paste, K2 and K3 (arranger jump and event editor)
    -- new global to identify types of user interactions that should block certain other interactions e.g. copy+paste, arranger jump, and entering event editor
    interaction = 'arranger_shift'
    d_cuml = util.clamp(d_cuml + d, -64, 64)
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
  
  end
  redraw()
end


---------------------------------------
-- CASCADING EVENTS EDITOR FUNCTIONS --
---------------------------------------
debug_change_functions = false

function change_category(category)
  if debug_change_functions then print('1. change_category called') end
  if category ~= prev_category then   -- todo p0 probably need to init prev_category and category vars for all of these
    print('  1.1 new category')
    update_event_subcategory_options('change_category')
    params:set('event_subcategory', 1) -- no action- calling manually on next step
    change_subcategory()
  end
  prev_category = category  -- todo p1 can this be local and persist on next call? I think not.
end


function change_subcategory()  -- don't need args passed because it's an index that has to be contextualized by looking up options. Using string instead. Oof, so param action doesn't fire if the index isn't changed. This will affect operation as well.
  if debug_change_functions then print('2. change_subcategory called') end
  -- concat this because subcategory string isn't unique and index resets with options swap!
  local subcategory = params:string('event_category') .. params:string('event_subcategory')
  if debug_change_functions then print('  new subcategory = ' .. subcategory .. '  prev_subcategory = ' .. (prev_subcategory or 'nil')) end

  if subcategory ~= prev_subcategory then
    -- print('new subcategory')
    set_event_indices()
    
    params:set('event_name', event_subcategory_index_min)  -- calls change_event
    if debug_change_functions then print('    setting event to ' .. events_lookup[event_subcategory_index_min].name) end
  end  
  prev_subcategory = subcategory
end


function change_event(event) -- index
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
    change_operation('change_event')
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
  edit_status_edited() -- captures change in category, subcategory, and event as well
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
  

-- Flip event edit status. IDK if it makes sense to do a function for this but it saves some rows ¯\_(ツ)_/¯
-- Running this in change_ events so it only fires if the value actually changes (rather than enc delta'd)
function edit_status_edited()
  if event_edit_status == '(Saved)' then
    event_edit_status = '(Edited)'
  end
end
    
-- Fetches the min and max events_lookup index for the selected subcategory so we know what events are available
function set_event_indices()
  local category = params:string('event_category')
  local subcategory = params:string('event_subcategory')
  event_subcategory_index_min = event_indices[category .. '_' .. subcategory].first_index
  event_subcategory_index_max = event_indices[category .. '_' .. subcategory].last_index
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


--index of list, count of items in list, #viewable, line height
function scroll_offset(index, total, in_view, height)
  if total > in_view and index > 1 then
    --math.ceil might make jumps larger than necessary, but ensures nothing is cut off at the bottom of the menu
    return(math.ceil(((index - 1) * (total - in_view) * height / total)))
  else
    return(0)
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
  for i = math.max(arranger_seq_position, 1), arranger_seq_length do
    
  -- _sticky vars handle instances when the active arranger segment is interrupted, in which case we want to freeze its vars to stop the segment from updating on the dash (while still allowing upcoming segments to update)
  -- Scenarios to test for:
    -- 1. User changes the current arranger segment pattern while on that segment. In this case we want to keep displaying the currently *playing* chord pattern
    -- 2. User changes the current chord pattern by double tapping it on the Chord grid view. This sets arranger_active to false and should suspend the arranger mini chart until Arranger pickup occurs.
    -- 3. Current arranger segment is turned off, resulting in it picking up a different pattern (either the previous pattern or wrapping around to grab the last pattern. arranger_seq_padded shenanigans)
    -- 4. We DO want this to update if the arranger is reset (arranger_seq_position = 0, however)
    
    -- Note: arranger_seq_position == i idenifies if we're on the active segment. Implicitly false when arranger is reset (arranger_seq_position 0) todo p2 make local
    if arranger_seq_position == i then
      -- todo p2 would be nice to rewrite this so these can be local
      if arranger_active == true then
        active_pattern = pattern
        active_chord_pattern_length = chord_pattern_length[active_pattern]
        active_chord_seq_position = math.max(chord_seq_position, 1)
        segment_level = 15
      else
        segment_level = 2 -- interrupted segment pattern, redraw will add +1 for better contrast only on events
      end
      pattern_sticky = active_pattern
      chord_pattern_length_sticky = active_chord_pattern_length
      chord_seq_position_sticky = active_chord_seq_position

      local steps_incr = math.max(active_chord_pattern_length - math.max((active_chord_seq_position or 1) - 1, 0), 0)
      steps_remaining_in_pattern = steps_incr
      steps_remaining_in_active_pattern = steps_remaining_in_active_pattern + steps_incr
    -- print('active_pattern = ' .. active_pattern) --todo debug to see if this is always set
    else -- upcoming segments always grab their current values from arranger
      pattern_sticky = arranger_seq_padded[i]
      chord_pattern_length_sticky = chord_pattern_length[pattern_sticky]
      chord_seq_position_sticky = 1
      steps_remaining_in_pattern = chord_pattern_length[pattern_sticky]
      segment_level = params:get('arranger_enabled') == 1 and 15 or 2
    end
    
    -- used to total remaining time in arrangement (beyond what is drawn in the dash)  
    steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
    
    -- todo p3 some sort of weird race condition is happening at init that requires nil check on events
    if events ~= nil and dash_steps < 30 then -- capped so we only store what is needed for the dash (including inserted blanks)
      for s = chord_seq_position_sticky, chord_pattern_length_sticky do -- todo debug this was letting 0 values through at some point. Debug if errors surface.
        -- if s == 0 then print('s == 0 ' .. chord_seq_position_sticky .. '  ' .. chord_pattern_length_sticky) end -- p0 debug looking for 0000s
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


  -- todo p2: this can be improved quite a bit by just having these custom screens be generated at the key/g.key level. Should be a fun refactor.
function redraw()
  screen.clear()
  local dash_x = 94

  if init_message ~= nil then
    screen.level(15)
    -- screen.move(2,8)
    -- screen.text('FYI!')    
    screen.move(2,18)
    screen.text('Crow v.3.0.1 is recommended.')
    screen.move(2,28)
    screen.text('Your version is ' .. crow_version .. '.')
    screen.move(2,38)
    screen.text('If Norns locks up, try')
    screen.move(2,48) 
    screen.text('unplugging Crow inputs 1-2.')
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()
    screen.level(3)      
    screen.move(128,62)
    screen.text_right('(K3) OK')          
    
  -- Screens that pop up when g.keys are being held down take priority--------
  -- POP-up g.key tip always takes priority
  elseif view_key_count > 0 then
    -- screen.level(7)
    -- screen.move(64,32)
    -- screen.font_size(16)
    -- screen.text_center(grid_view_name)
    -- screen.font_size(8)
    
    if screen_view_name == 'Chord+arp' then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. CHORDS+ARP')      

    elseif grid_view_name == 'Arranger' then
      screen.level(15)
      screen.move(2,8)
      -- Placeholder
      -- screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.text(string.upper(grid_view_name) .. ' GRID')
      -- screen.move(2,28)
      -- screen.text('ENC 2: Rotate seq ↑↓')
      -- screen.move(2,38)
      -- screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      
      -- The following key options were moved to arranger grid buttons
      -- screen.move(1,62)
      -- if params:get('arranger_enabled') == 0 then
      --   screen.text('(K2) ENABLE')
      -- else
      --   screen.text('(K2) DISABLE')
      -- end
      -- screen.move(128,62)
      -- if params:get('playback') == 1 then
      --   screen.text_right('(K3) ONE-SHOT')
      -- else
      --   screen.text_right('(K3) LOOP')
      -- end
        
    elseif grid_view_name == 'Chord' then
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. CHORDS')     
        
     elseif grid_view_name == 'Arp' then --or grid_view_name == 'Arp') then-- Chord/Arp 
      screen.level(15)
      screen.move(2,8)
      screen.text(string.upper(grid_view_name) .. ' GRID FUNCTIONS')
      screen.move(2,28)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2,38)
      screen.text('ENC 3: Transpose seq ←→')
      screen.level(4)
      screen.move(1,54)
      screen.line(128,54)
      screen.stroke()
      screen.level(3)      
      screen.move(128,62)
      screen.text_right('(K3) GEN. ARP')  
      end
      
  -- Arranger shift interaction
  elseif interaction == 'arranger_shift' then
    screen.level(15)
    screen.move(2,8)
    screen.text('ARRANGER SEGMENT ' .. event_edit_pattern)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,38)
    screen.text('ENC 3: Shift segments ←→')
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()    
  
    
    -- Arranger events strip held down
  elseif arranger_loop_key_count > 0 then
    screen.level(15)
    screen.move(2,8)
    screen.text('ARRANGER SEGMENT ' .. event_edit_pattern)
    -- todo: might be cool to add a scrollable (K2) list of events in this segment here
    screen.move(2,28)
    screen.text('Tap to paste events')
    screen.move(2,38)
    screen.text('ENC 3: Shift segments ←→')
    screen.level(4)
    screen.move(1,54)
    screen.line(128,54)
    screen.stroke()
    screen.level(3)
    screen.move(1,62)
    screen.text('(K2) JUMP TO')    
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
    screen.text("CHORD PATTERN '" .. pattern_name[pattern_copy_source] .. "'' COPIED")
    screen.move(2,28)
    screen.text('1. Tap a pattern to paste')
    screen.move(2,38)
    screen.text('2. Release to queue pattern')
    screen.move(2,48)
    screen.text('3. Tap again to force jump')
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
      screen.level(4)
      screen.move(2,8)
      if event_edit_active == false then
        screen.text('EDITING SEGMENT ' .. event_edit_pattern)
        screen.move(2,28)
        screen.level(15)
        screen.text('Use Grid to select step (↑↓)')
        screen.move(2,38)
        screen.text('and event number (←→)')
        screen.level(4)
        screen.move(1,54)
        screen.line(128,54)
        screen.stroke()
        screen.level(3)      
        screen.move(1,62)
        screen.text('(K2) DELETE ALL')
        screen.move(128,62)
        screen.text_right('(K3) DONE')
      else
   
   
        --------------------------
        -- Scrolling events menu
        --------------------------
        local menu_offset = scroll_offset(events_index, #events_menus, 4, 10)
        line = 1
        for i = 1,#events_menus do
          local debug = false
          
          screen.move(2, line * 10 + 8 - menu_offset)
          screen.level(events_index == i and 15 or 3)

          local menu_id = events_menus[i]
          local menu_index = params:get(menu_id)
          event_val_string = params:string(menu_id) -- todo p1 local


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
              if debug then print("'Set' operator")end
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
              
            -- flag if it's the only item in a subcategory. todo p0 needs some sort of indicator or it feels frozen!
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
        
        
     -- Events editor sticky header
        screen.level(4)
        screen.rect(0,0,128,11)
        screen.fill()
        screen.move(2,8)
        screen.level(0)
        screen.text('SEG ' .. event_edit_pattern .. '.' .. event_edit_step .. ', EVENT ' .. event_edit_lane .. '/16')
        screen.move(126,8)
        -- screen.level(event_edit_status == '(Edited)' and 11 or 0)
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
        screen.text_right('(K3) SAVE')
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
      if chord_seq_position == 0 then
        screen.text(pattern_name[pattern].. '.RST')
      else
        screen.text(pattern_name[pattern] ..'.'.. chord_seq_position .. '/' .. chord_pattern_length[pattern])
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
      
      local arranger_dash_x = dash_x + (arranger_seq_position == 0 and 5 or 3) -- If arranger is reset, add an initial gap to the x position
      
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
      screen.level(params:get('arranger_enabled') == 1 and 9 or 2)
      
      screen.rect(dash_x+1, arranger_dash_y+2,33,38)
      screen.stroke()
      
      -- Header
      screen.level(params:get('arranger_enabled') == 1 and 10 or 2)
      screen.rect(dash_x, arranger_dash_y+1,34,11)
      screen.fill()

      --------------------------------------------
      -- Arranger countdown timer readout
      --------------------------------------------
    
      -- Arranger time
      screen.level(params:get('arranger_enabled') == 1 and 15 or 3)

      -- Bottom left
      screen.move(dash_x +3, arranger_dash_y + 36)
      screen.text(seconds_remaining)
      
      -- Arranger mode glyph
      screen.level(0)
      local x_offset = dash_x + 27
      local y_offset = arranger_dash_y + 4
      if params:string('playback') == 'Loop' then
        for i = 1, #glyphs.loop do
          screen.pixel(glyphs.loop[i][1] + x_offset, glyphs.loop[i][2] + y_offset)
        end
      else 
        for i = 1, #glyphs.one_shot do
          screen.pixel(glyphs.one_shot[i][1] + x_offset, glyphs.one_shot[i][2] + y_offset)
        end
      end

      --------------------------------------------
      -- Arranger position readout
      --------------------------------------------      
      screen.move(dash_x + 2,arranger_dash_y + 9)

      if arranger_seq_position == 0 then
        if arranger_queue == nil then
          screen.text('RST')
        elseif arranger_active == false then
          screen.text((arranger_queue or util.wrap(arranger_seq_position + 1, 1, arranger_seq_length)) .. '.'.. math.min(chord_seq_position - chord_pattern_length[pattern], 0))
        else
          screen.text(arranger_queue .. '.0')
        end
      elseif arranger_active == false then
        if arranger_seq_position == arranger_seq_length then
          if params:string('playback') == "Loop"  then
            screen.text('LP.' .. math.min(chord_seq_position - chord_pattern_length[pattern], 0))
          else
            screen.text('EN.' .. math.min(chord_seq_position - chord_pattern_length[pattern], 0))
          end
        else
          screen.text((arranger_queue or util.wrap(arranger_seq_position + 1, 1, arranger_seq_length)) .. '.'.. math.min(chord_seq_position - chord_pattern_length[pattern], 0))
        end
      else
        screen.text(arranger_seq_position .. '.' .. chord_seq_position)
        
      end      
      screen.fill()
      
      
      --------------------------------------------
      -- Scrolling menus
      --------------------------------------------
      local menu_offset = scroll_offset(menu_index,#menus[page_index], 5, 10)
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