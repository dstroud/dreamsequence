-- Dreamsequence
--
-- KEY 1: Fn (hold)
-- KEY 2: Play/pause
-- KEY 3: Reset/Generate
--
-- ENC 1: Pages
-- ENC 2: Scroll
-- ENC 3: Edit value 
--
-- Crow IN 1: CV in
-- Crow IN 2: Trigger in
-- Crow OUT 1: V/oct out
-- Crow OUT 2: Trigger/envelope out
-- Crow OUT 3: Clock out
-- Crow OUT 4: Assignable


g = grid.connect()
include("dreamsequence/lib/includes")


-- To-do, add options for selecting MIDI in/out ports
in_midi = midi.connect(1)
out_midi = midi.connect(1) -- To-do: multiple MIDI in/out
transport_midi = midi.connect(math.max(params:get('clock_midi_out') - 1, 1))

function init()
  crow.ii.jf.mode(1)
  params:set('clock_crow_out', 1) -- Turn off built-in Crow clock so it doesn't conflict with Bento's clock


  --Global params
  params:add_separator ('Global')
  params:add_number("transpose","Key",-12, 12, 0, function(param) return transpose_string(param:get()) end)
  params:add{
    type = 'number',
    id = 'mode',
    name = 'Mode',
    min = 1,
    max = 9,
    default = 1,
    formatter = function(param) return mode_index_to_name(param:get()) end,}
    params:add_option('repeat_notes', 'Rpt. notes', {'Retrigger','Dedupe'},1)
      params:set_action('repeat_notes',function() menu_update() end)
  params:add_number('dedupe_threshold', 'Threshold', 1, 10, division_to_index('1/32'), function(param) return divisions_string(param:get()) end)
    params:set_action('dedupe_threshold', function() dedupe_threshold() end)
  params:add_number('chord_preload', 'Chord preload', 1, 10, division_to_index('1/64'), function(param) return divisions_string(param:get()) end)
    params:set_action('chord_preload', function(x) chord_preload(x) end)      
      
  --Arrange params
  params:add_separator ('Arranger')
  params:add{
    type = 'number',
    id = 'arranger_enabled',
    name = 'Enabled',
    min = 0,
    max = 1,
    default = 0,
    formatter = function(param) return t_f_string(param:get()) end,
    action = function() grid_redraw() end}
  params:add{
  type = 'number',
  id = 'playback',
  name = 'Playback',
  min = 0,
  max = 1,
  default = 1,
  formatter = function(param) return playback_string(param:get()) end}
  params:add_option('crow_assignment', 'Crow 4', {'Reset', 'On/high', 'V/pattern', 'Chord', 'Pattern'},1) -- To-do
  
  
  --Chord params
  params:add_separator ('Chord')
  params:add_number('chord_div_index', 'Step length', 1, 57, 15, function(param) return divisions_string(param:get()) end)
    params:set_action('chord_div_index',function() set_div('chord') end)

  params:add_option('chord_dest', 'Destination', {'None', 'Engine', 'MIDI', 'ii-JF'},3)
    params:set_action("chord_dest",function() menu_update() end)
  params:add{
    type = 'number',
    id = 'chord_pp_amp',
    name = 'Amp',
    min = 0,
    max = 100,
    default = 80,
    formatter = function(param) return percent(param:get()) end}
  params:add_control("chord_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,800,'hz'))
    pp_gain = controlspec.def{
    min=0,
    max=400,
    warp='lin',
    step=5,
    default=100,
    quantum=.01,
    wrap=false,
    -- units='khz'
  }
  params:add_control("chord_pp_gain","Gain", pp_gain)
  params:add_number("chord_pp_pw","Pulse width",1, 99, 50)
  params:add_number('chord_midi_velocity','Velocity',0, 127, 100)
  params:add_number('chord_midi_ch','Channel',1, 16, 1)
  params:add_number('chord_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  params:add_number('crow_pullup','Crow Pullup',0, 1, 0,function(param) return t_f_string(param:get()) end) --JF = chord only
    params:set_action("crow_pullup",function() crow_pullup() end)
    
  params:add_number('chord_duration_index', 'Duration', 1, 57, 15, function(param) return divisions_string(param:get()) end)
    params:set_action('chord_duration_index',function() set_duration('chord') end)
  
  params:add_number('chord_octave','Octave',-2, 4, 0)
  params:add_number('chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)


  --Arp params
  params:add_separator ('Arp')
  
  params:add_number('arp_div_index', 'Step length', 1, 57, 8, function(param) return divisions_string(param:get()) end)
    params:set_action('arp_div_index',function() set_div('arp') end)
  params:add_option("arp_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF'},2)
    params:set_action("arp_dest",function() menu_update() end)
  params:add{
    type = 'number',
    id = 'arp_pp_amp',
    name = 'Amp',
    min = 0,
    max = 100,
    default = 80,
    formatter = function(param) return percent(param:get()) end}
  params:add_control("arp_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,800,'hz'))
  params:add_control("arp_pp_gain","Gain", pp_gain)
  params:add_number("arp_pp_pw","Pulse width",1, 99, 50)
  params:add_number('arp_midi_ch','Channel',1, 16, 1)
  params:add_number('arp_midi_velocity','Velocity',0, 127, 100)
  params:add_number('arp_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  params:add_option("arp_tr_env", "Output", {'Trigger','AR env.'},1)
  params:set_action("arp_tr_env",function() menu_update() end)
  params:add_number('arp_ar_skew','AR env. skew',0, 100, 0)
  params:add_number('arp_duration_index', 'Duration', 1, 57, 8, function(param) return divisions_string(param:get()) end)
    params:set_action('arp_duration_index',function() set_duration('arp') end)
    
  params:add_number('arp_octave','Octave',-2, 4, 0)
  params:add_number('arp_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)
  params:add_option("arp_mode", "Mode", {'Loop','One-shot'},2)
  
  
  --MIDI params
  params:add_separator ('MIDI')
  params:add_option("midi_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF'},3)
    params:set_action("midi_dest",function() menu_update() end)
  params:add{
    type = 'number',
    id = 'midi_pp_amp',
    name = 'Amp',
    min = 0,
    max = 100,
    default = 80,
    formatter = function(param) return percent(param:get()) end}
  params:add_control("midi_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,800,'hz'))
  params:add_control("midi_pp_gain","Gain", pp_gain)
  params:add_number("midi_pp_pw","Pulse width",1, 99, 50)
  params:add_number('midi_midi_ch','Channel',1, 16, 1)
  params:add_number('midi_midi_velocity','Velocity',0, 127, 100)
  params:add_number('midi_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  params:add{
    type = 'number',
    id = 'do_midi_velocity_passthru',
    name = 'Pass velocity',
    min = 0,
    max = 1,
    default = 0,
    formatter = function(param) return t_f_string(param:get()) end,
    action = function() menu_update() end}
  params:add_option("midi_tr_env", "Output", {'Trigger','AR env.'},1)
    params:set_action("midi_tr_env",function() menu_update() end)
  params:add_number('midi_ar_skew','AR env. skew',0, 100, 0)
  params:add_number('midi_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
    params:set_action('midi_duration_index',function() set_duration('midi') end)
    
  params:add_number('midi_octave','Octave',-2, 4, 0)
  params:add_number('midi_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)

  
  --Crow params
  params:add_separator ('Crow')
  params:add_number('crow_div', 'Crow clk. div', 1, 32, 8) --most useful TBD. Should change to PPQN
  params:add_option("crow_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow', 'ii-JF'},1)
    params:set_action("crow_dest",function() menu_update() end)
  params:add{
    type = 'number',
    id = 'crow_pp_amp',
    name = 'Amp',
    min = 0,
    max = 100,
    default = 80,
    formatter = function(param) return percent(param:get()) end}
  params:add{
    type = 'number',
    id = 'do_crow_auto_rest',
    name = 'Auto-rest',
    min = 0,
    max = 1,
    default = 0,
    formatter = function(param) return t_f_string(param:get()) end}
  params:add_control("crow_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,800,'hz'))
  params:add_control("crow_pp_gain","Gain", pp_gain)
  params:add_number("crow_pp_pw","Pulse width",1, 99, 50)
  params:add_number('crow_midi_ch','Channel',1, 16, 1)
  params:add_number('crow_midi_velocity','Velocity',0, 127, 100)
  params:add_number('crow_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  params:add_option("crow_tr_env", "Output", {'Trigger','AR env.'},1)
    params:set_action("crow_tr_env",function() menu_update() end)
  params:add_number('crow_ar_skew','AR env. skew',0, 100, 0)
  params:add_number('crow_duration_index', 'Duration', 1, 57, 10, function(param) return divisions_string(param:get()) end)
    params:set_action('crow_duration_index',function() set_duration('crow') end)
    
  params:add_number('crow_octave','Octave',-2, 4, 0)
  params:add_number('crow_chord_type','Chord type',3, 4, 3,function(param) return chord_type(param:get()) end)


  glyphs = {
    {{1,0},{2,0},{3,0},{0,1},{0,2},{4,2},{4,3},{1,4},{2,4},{3,4}}, --repeat glyph     
    {{2,0},{3,1},{0,2},{1,2},{4,2},{3,3},{2,4}},} --one-shot glyph
  
  
  clock_start_method = 'start'
  
  -- Send out MIDI stop on launch
  transport_midi_update() 
  if params:get('clock_midi_out') ~= 1 then
    transport_midi:stop()
  end
        
  chord_seq_retrig = true
  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  crow.input[2].mode("change",2,0.1,"rising") --might want to use as a gate with "both"
  crow.input[2].change = crow_trigger
  crow.output[2].action = "pulse(.001,5,1)" -- Need to test this more vs. roll-your-own pulse
  crow.output[3].action = "pulse(.001,5,1)" 
  screen_views = {'Generator','Session','Arranger'}
  screen_view_index = 2
  screen_view_name = screen_views[screen_view_index]
  grid_dirty = true
  grid_views = {'Arranger','Chord','Arp'} -- grid "views" are decoupled from screen "pages"
  grid_view_index = 2
  grid_view_name = grid_views[grid_view_index]
  -- flicker = 3
  pages = {'GLOBAL', 'CHORD', 'ARP', 'MIDI IN', 'CV IN'}
  page_index = 1
  page_name = pages[page_index]
  menus = {}
  menu_update()
  menu_index = 0
  selected_menu = menus[page_index][menu_index]
  arranger_menus = {}
  arranger_menu_index = 1 -- No top level option (yet)
  selected_arranger_menu = arranger_menus[arranger_menu_index]
    print(selected_arranger_menu)
  transport_active = false
  automator_events = {}
  pattern_length = {4,4,4,4} -- loop length for each of the 4 patterns. rename to chord_seq_length prob
  pattern = 1
  steps_remaining_in_pattern = pattern_length[pattern]
  pattern_queue = false
  pattern_copy_performed = false
  pattern_seq_retrig = false
  pattern_seq = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  pattern_seq_position = 0
  pattern_seq_length = 1
  steps_remaining_in_arrangement = 0
  elapsed = 0
  pattern_pos = 1 -- Check
  percent_step_elapsed = 0
  seconds_remaining_in_arrangement = 0
  chord_no = 0
  pattern_keys = {}
  pattern_key_count = 0
  chord_key_count = 0
  view_key_count = 0
  keys = {}
  key_count = 0
  global_clock_div = 48
  chord_seq = {{},{},{},{}} 
  for p = 1,4 do
    for i = 1,8 do
      chord_seq[p][i] = {x = 0} -- raw value
      chord_seq[p][i]["c"] = 0  -- chord wrapped 1-7   
      chord_seq[p][i]["o"] = 0  -- octave
    end
  end
  chord_seq_position = 0
  chord = {} --probably doesn't need to be a table but might change how chords are loaded
  chord = musicutil.generate_chord_scale_degree(chord_seq[pattern][1].o * 12, params:get('mode'), chord_seq[pattern][1].c, true)
  arp_seq = {{0,0,0,0,0,0,0,0},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8}
            } -- sub table for multiple arp patterns
  arp_pattern_length = {8,8,8,8}
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
  midi_note_history = {}
  engine_note_history = {}
  crow_note_history = {}
  jf_note_history = {}
  dedupe_threshold()
  reset_clock() -- will turn over to step 0 on first loop
  get_next_chord() -- Placeholder for when table loading from file is implemented
  -- grid_dirty = true
  params:bang()
  grid_redraw()
  redraw()
end


function menu_update()
  
  -- Arranger menu. TBD if this should be here or in a separate function
  arranger_menus = {'arranger_enabled', 'playback', 'crow_assignment'}
  
  
  --Global menu
  if params:string('repeat_notes') == 'Retrigger' then
    menus[1] = {'mode', 'transpose', 'clock_tempo', 'clock_source', 'clock_midi_out', 'crow_div', 'repeat_notes', 'chord_preload', 'crow_pullup'}
  else
    menus[1] = {'mode', 'transpose', 'clock_tempo', 'clock_source', 'clock_midi_out', 'crow_div', 'repeat_notes', 'dedupe_threshold', 'chord_preload', 'crow_pullup'}
  end
  
  --chord menus   
  if params:string('chord_dest') == 'None' then
    menus[2] = {'chord_dest', 'chord_div_index', 'chord_type', 'chord_octave'}
  elseif params:string('chord_dest') == 'Engine' then
    menus[2] = {'chord_dest', 'chord_div_index', 'chord_duration_index', 'chord_type', 'chord_octave', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_gain', 'chord_pp_pw'}
  elseif params:string('chord_dest') == 'MIDI' then
    menus[2] = {'chord_dest', 'chord_midi_ch', 'chord_div_index', 'chord_duration_index', 'chord_type', 'chord_octave', 'chord_midi_velocity'}
  elseif params:string('chord_dest') == 'ii-JF' then
    menus[2] = {'chord_dest', 'chord_div_index', 'chord_type', 'chord_octave', 'chord_jf_amp'}
  end
  
  --arp menus
  if params:string('arp_dest') == 'None' then
    menus[3] = {'arp_dest', 'arp_mode', 'arp_div_index', 'arp_chord_type', 'arp_octave'}
  elseif params:string('arp_dest') == 'Engine' then
    menus[3] = {'arp_dest', 'arp_mode', 'arp_div_index', 'arp_duration_index', 'arp_chord_type', 'arp_octave', 'arp_pp_amp', 'arp_pp_cutoff', 'arp_pp_gain', 'arp_pp_pw'}
  elseif params:string('arp_dest') == 'MIDI' then
    menus[3] = {'arp_dest', 'arp_mode', 'arp_midi_ch', 'arp_div_index', 'arp_duration_index', 'arp_chord_type', 'arp_octave', 'arp_midi_velocity'}
  elseif params:string('arp_dest') == 'Crow' then
    if params:string('arp_tr_env') == 'Trigger' then
      menus[3] = {'arp_dest', 'arp_mode', 'arp_tr_env', 'arp_chord_type', 'arp_octave', 'do_crow_auto_rest'}
    else
      menus[3] = {'arp_dest', 'arp_mode', 'arp_tr_env', 'arp_duration_index', 'arp_ar_skew', 'arp_chord_type', 'arp_octave', 'do_crow_auto_rest'}
    end
  elseif params:string('arp_dest') == 'ii-JF' then
    menus[3] = {'arp_dest', 'arp_mode', 'arp_div_index', 'arp_chord_type', 'arp_octave', 'arp_jf_amp'}
  end
  
    --MIDI menus
  if params:string('midi_dest') == 'None' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave'}
  elseif params:string('midi_dest') == 'Engine' then
    menus[4] = {'midi_dest', 'midi_duration_index', 'midi_chord_type', 'midi_octave', 'midi_pp_amp', 'midi_pp_cutoff', 'midi_pp_gain', 'midi_pp_pw'}
  elseif params:string('midi_dest') == 'MIDI' then
    if params:get('do_midi_velocity_passthru') == 1 then
      menus[4] = {'midi_dest', 'midi_midi_ch', 'midi_duration_index', 'midi_chord_type', 'midi_octave', 'do_midi_velocity_passthru'}
    else
      menus[4] = {'midi_dest', 'midi_midi_ch', 'midi_duration_index', 'midi_chord_type', 'midi_octave', 'do_midi_velocity_passthru', 'midi_midi_velocity'}
    end
  elseif params:string('midi_dest') == 'Crow' then
    if params:string('midi_tr_env') == 'Trigger' then
      menus[4] = {'midi_dest', 'midi_tr_env', 'midi_chord_type', 'midi_octave', 'do_crow_auto_rest'}
    else
      menus[4] = {'midi_dest', 'midi_tr_env', 'midi_duration_index', 'midi_ar_skew', 'midi_chord_type', 'midi_octave', 'do_crow_auto_rest'}
    end
  elseif params:string('midi_dest') == 'ii-JF' then
    menus[4] = {'midi_dest', 'midi_chord_type', 'midi_octave', 'midi_jf_amp'}
  end
  
    --Crow menus
  if params:string('crow_dest') == 'None' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest'}
  elseif params:string('crow_dest') == 'Engine' then
    menus[5] = {'crow_dest', 'crow_duration_index', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest', 'crow_pp_amp', 'crow_pp_cutoff', 'crow_pp_gain', 'crow_pp_pw'}
  elseif params:string('crow_dest') == 'MIDI' then
    menus[5] = {'crow_dest', 'crow_midi_ch', 'crow_duration_index', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest', 'crow_midi_velocity'}
  elseif params:string('crow_dest') == 'Crow' then
    if params:string('crow_tr_env') == 'Trigger' then
      menus[5] = {'crow_dest', 'crow_tr_env', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest'}
    else
      menus[5] = {'crow_dest', 'crow_tr_env', 'crow_duration_index', 'crow_ar_skew', 'crow_chord_type', 'crow_octave', 'do_crow_auto_rest'}
    end
  elseif params:string('crow_dest') == 'ii-JF' then
    menus[5] = {'crow_dest', 'crow_chord_type', 'crow_octave', 'crow_jf_amp'}
  end  
end



function division_to_index(string)
  for i = 1,#division_names do
    if tab.key(division_names[i],string) == 2 then
      return(i)
    end
  end
end


-- Sends midi transport messages on the same 'midi out' port used for system clock
-- If Off in system clock params, it will default to port 1
function transport_midi_update()
  transport_midi = midi.connect(math.max(params:get('clock_midi_out') - 1, 1))
end


function crow_pullup()
  crow.ii.pullup(t_f_bool(params:get('crow_pullup')))
  print('crow pullup: ' .. t_f_string(params:get('crow_pullup')))
end

function first_to_upper(str)
    return (str:gsub("^%l", string.upper))
end

function divisions_string(index)
    return(division_names[index][2])
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

function param_id_to_name(id)
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
  return(keys[x + 13] .. ' ' .. (x >= 1 and '+' or '') .. (x ~= 0 and x or '') )
end

function t_f_bool(x)
  return(x == 1 and true or false)
end

function playback_string(x)
  return(x == 1 and 'Loop' or 'One-shot')
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
  dedupe_threshold_int = division_names[params:get('dedupe_threshold')][1]
  dedupe_threshold_s = duration_sec(dedupe_threshold_int) * .95
end  


function chord_preload(index)
  chord_preload_tics = division_names[index][1]
end  


-- Callback function when system tempo changes
function clock.tempo_change_handler()  
  dedupe_threshold()
end  

-- Hacking up MusicUtil.generate_chord_roman to get modified chord_type for chords.
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
 -- To-do: evaluate efficiency of having separate clocks, one for tuplets and one for standard meter
function sequence_clock()
  while transport_active do
    -- To-do: add option for initial delay when syncing to external MIDI/Link
    
    
    clock.sync(1/global_clock_div)    -- To-do: Add offset param usable for Link delay compensation


    -- START
    if start == true and stop ~= true then
      -- Send out MIDI start/continue messages
      transport_midi_update()
      if params:get('clock_midi_out') ~= 1 then 
        if clock_start_method == 'start' then
          transport_midi:start()
        else
          transport_midi:continue()
        end
      end
      clock_start_method = 'continue'
      print("Clock "..sequence_clock_id.. " started")
      start = false
    end
    
    
    -- ADVANCE CLOCK_STEP
    -- Wrap not strictly needed and could actually be used to count arranger position? 
    -- 192 tics per measure * 8 (max a step can be, 0-indexed. 
    clock_step = util.wrap(clock_step + 1,0, 1535)
    
    
    
    -- STOP beat-quantized
    if stop == true then
      
      -- Stop is quantized to occur at the end of the beat ( trying out x4 to stop at end of measure) To-do: add param for this?
      if (clock_step) % (global_clock_div * 4) == 0 then  --stops at the end of the beat.
        
        -- Reset the clock_step so sequence_clock resumes at the same position as MIDI beat clock
        clock_step = util.wrap(clock_step - 1, 0, 1535)  
          
        transport_midi_update() 
        if params:get('clock_midi_out') ~= 1 then
          transport_midi:stop()
        end
        
        print('Transport stopping at clock_step ' .. clock_step .. ', clock_start_method: '.. clock_start_method)
        print('Canceling clock_id ' .. (sequence_clock_id or 0))
        
        clock.cancel(sequence_clock_id)-- or 0)
      
        -- If syncing to an external clock source
        if params:get('clock_source') ~= 1 then -- External clock
          if params:get('arranger_enabled') == 1 then 
            reset_arrangement()
          else
            reset_pattern()
          end
        end
        transport_active = false
        stop = false
          -- transport_active = false
      end
    end
  
  
    -- Checking transport state again in case transport was just set to 'false' by Stop
    if transport_active then
      -- pre-loads next chord to allow early notes to be quantized according to the upcoming chord
      if util.wrap(clock_step + chord_preload_tics, 0, 1535) % chord_div == 0 then
        get_next_chord()
      end
      
      if clock_step % chord_div == 0 then
        advance_chord_seq()
        grid_dirty = true
        redraw() -- Update chord readout
      end
  
      if clock_step % arp_div == 0 then
        if params:string('arp_mode') == 'Loop' or play_arp then
          advance_arp_seq()
          grid_dirty = true      
        end
      end
      
      if clock_step % params:get('crow_div') == 0 then
        crow.output[3]() --pulse defined in init
      end
    end
    
    if grid_dirty == true then
      grid_redraw()
      grid_dirty = false
    end

  end
end


--Clock used to redraw screen every second for arranger countdown timer
function seconds_clock()
  while true do
    redraw()
    clock.sleep(1)
  end
end
    
    
-- This clock is used to keep track of which notes are playing so we know when to turn them off and for optional deduping logic
function timing_clock()
  while true do
    clock.sync(1/global_clock_div)

    for i = #midi_note_history, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      midi_note_history[i][1] = midi_note_history[i][1] - 1
      if midi_note_history[i][1] == 0 then
        -- print('note_off')
        out_midi:note_off(midi_note_history[i][2], 0, midi_note_history[i][3]) -- note, vel, ch.
        table.remove(midi_note_history, i)
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
    
    

function clock.transport.start()
  if params:string('clock_source') == 'link' then link_start = true end

  transport_active = true
  
    
  -- Clock for note duration, note-off events
  clock.cancel(timing_clock_id or 0) -- Cancel previous timing clock (if any) and...
  timing_clock_id = clock.run(timing_clock) --Start a new timing clock. Not sure about efficiency here.
  
  -- Clock for chord/arp/arranger sequences
  sequence_clock_id = clock.run(sequence_clock)
  
  
  --Clock used to refresh screen once a second for the arranger countdown timer
  clock.cancel(seconds_clock_id or 0) 
  seconds_clock_id = clock.run(seconds_clock)
  
  -- Tells sequence_clock to send a MIDI start/continue message after initial clock sync
  start = true
end


function clock.transport.stop()
  stop = true
  -- transport_active = false  -- Move inside sequence_clock
  
  -- transport_midi_update()   -- Move inside sequence_clock
  -- if params:get('clock_midi_out') ~= 1 then
  --   transport_midi:stop()
  -- end
  
  -- print('Transport stopping. clock_start_method: '.. clock_start_method)
  -- print('Canceling clock_id ' .. (sequence_clock_id or 0))
  
  -- clock.cancel(sequence_clock_id)-- or 0) -- Move inside sequence_clock

  -- -- If syncing to an external clock source
  -- if params:get('clock_source') ~= 1 then -- External clock
  --   if params:get('arranger_enabled') == 1 then 
  --     reset_arrangement()
  --   else
  --     reset_pattern()
  --   end
  -- end
end


-- function clock.transport.stop()
--   transport_active = false
--   transport_midi_update()
--   if params:get('clock_midi_out') ~= 1 then
--     transport_midi:stop()
--   end
--   print('Transport stopping. clock_start_method: '.. clock_start_method)
--   print('Canceling clock_id ' .. (sequence_clock_id or 0))
--   clock.cancel(sequence_clock_id)-- or 0)

--   -- If syncing to an external clock source
--   if params:get('clock_source') ~= 1 then -- External clock
--     if params:get('arranger_enabled') == 1 then 
--       reset_arrangement()
--     else
--       reset_pattern()
--     end
--   end
-- end



-- Does not set start = true since this can be called by clock.transport.stop() when pausing
function reset_pattern() -- To-do: Also have the chord readout updated (move from advance_chord_seq to a function)
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  reset_clock()
  get_next_chord()
  grid_redraw()
  redraw()
end

-- Does not set start = true since this can be called by clock.transport.stop() when pausing
function reset_arrangement() -- To-do: Also have the chord readout updated (move from advance_chord_seq to a function)
  arranger_one_shot_last_pattern = false -- Added to prevent 1-pattern arrangements from auto stopping.
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  pattern_seq_position = 0
  pattern = pattern_seq[1]
  reset_clock()
  get_next_chord()
  grid_redraw()
  redraw()
end


function reset_clock()
  clock_step = -1 -- clock_step rewrite
  -- clock_start_method = 'start'    -- This could be causing a start when we want continue
end


function advance_chord_seq()
  chord_seq_retrig = true -- indicates when we're on a new chord seq step for crow auto-rest logic.
  play_arp = true
  local arrangement_reset = false

  -- Move arranger sequence if enabled
  if params:get('arranger_enabled') == 1 then

    -- If it's post-reset or at the end of chord sequence
    if (pattern_seq_position == 0 and chord_seq_position == 0) or chord_seq_position >= pattern_length[pattern] then
      
      -- Check if it's the last pattern in the arrangement.
      -- This also needs to be run after firing chord so we can catch last-minute changes to arranger_one_shot_last_pattern
      if arranger_one_shot_last_pattern then -- Reset arrangement and block chord seq advance/play
        arrangement_reset = true
        reset_arrangement()
        clock.transport.stop()
      else  -- If not the last pattern in the arrangement, update the arranger sequence position
        pattern_seq_position = util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)
        pattern = pattern_seq[pattern_seq_position]
      end
      
      -- According to my notes, pattern_seq_retrig "Prevents arp from extending beyond chord pattern length"
      -- This isn't happenening even when disabled, so probably not needed
      -- Might be interesting to have several arp modes
          -- Loop (current Loop)
          -- Let arp play through to completion (even if multiple chords play), then pause until the next chord retriggers (current one-shot)
          -- Force arp reset each time a new chord is played
      -- pattern_seq_retrig = true -- Disabling to see what breaks
    end
    
    -- Flag if arranger is on the last pattern of a 1-shot sequence
    arranger_one_shot_last_pattern = pattern_seq_position >= pattern_seq_length and params:string('playback') == 'One-shot'
  end
  
  -- If arrangement was not just reset, update chord position. 
  if arrangement_reset == false then
    if chord_seq_position >= pattern_length[pattern] or pattern_seq_retrig then
      if pattern_queue then
        pattern = pattern_queue
        pattern_queue = false
      end
      chord_seq_position = 1
      pattern_seq_retrig = false
    else  
      chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
    end
    
    -- Arranger automation step
    -- if params:get('arranger_enabled') == 1 then
    --   automator()
    -- end
    
    -- Play the chord
    if chord_seq[pattern][chord_seq_position].c > 0 then
  -- if chord_seq_position > 0 then --Turning this off to see if it breaks something. Not sure why it's needed.
      play_chord(params:string('chord_dest'), params:get('chord_midi_ch'))
      if chord_key_count == 0 then
        chord_no = chord_seq[pattern][chord_seq_position].c + (params:get('chord_type') == 4 and 7 or 0) --or 0
        generate_chord_names()
      end
  -- end
    end
  end
end


function automator()
  --pattern_seq_position, chord_seq_position, event_no
  
  -- need to hardcode max # of vars here once known, or generate somehow. Also needs to set # of top level indices based on arranger length 
  automator_events = {
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    {{},{},{},{},{},{},{},{},},
                    }
  -- Arranger pattern_seq_position, chord_seq_position, automation event index
  automator_events[1][2][1] = {'rotate_pattern', 'Arp', 1} --event name, var 1, var 2
  automator_events[1][1][1] = {'transpose', 0} --event name, var 1, var 2
  automator_events[1][5][1] = {'transpose', 2} --event name, var 1, var 2
  -- automator_events[1][2][2] = {'shuffle_arp'}

  if pattern_seq_position ~= 0 and chord_seq_position ~= 0 then
    -- if automator_events[pattern_seq_position][chord_seq_position] ~= nil then
    if automator_events[pattern_seq_position][chord_seq_position][1] then -- only checks for first event. insert and remove to preserve something in index 1
      -- print(pattern_seq_position .. ' ' .. chord_seq_position .. ' ' ..automator_events[pattern_seq_position][chord_seq_position][1][1])
      
      for i = 1, #automator_events[pattern_seq_position][chord_seq_position] do
        local do_event = automator_events[pattern_seq_position][chord_seq_position][i][1]
        -- Sub for do loop for dynamic # of vars being stored
        local var_1 = automator_events[pattern_seq_position][chord_seq_position][i][2]
        local var_2 = automator_events[pattern_seq_position][chord_seq_position][i][3]
        -- local var_3 = automator_events[pattern_seq_position][chord_seq_position][i][1]
        
        print(pattern_seq_position .. ' ' .. chord_seq_position .. ' ' .. do_event)
        if do_event == 'rotate_pattern' then
          rotate_pattern(var_1, var_2)
        elseif do_event == 'transpose' then
          params:set('transpose',var_1)
        elseif do_event == 'shuffle_arp' then
          local shuffled_arp_seq = shuffle(arp_seq[arp_pattern])
          arp_seq[arp_pattern] = shuffled_arp_seq
        end
      end
    end
  end
end
  
function generate_chord_names()
  if chord_no > 0 then
    chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_no]
    --To-do: more thoughful selection of sharps or flats depending on the key.
    chord_name = musicutil.NOTE_NAMES[util.wrap((musicutil.SCALES[params:get('mode')]['intervals'][util.wrap(chord_no, 1, 7)] + 1) + params:get('transpose'), 1, 12)]
    chord_name_modifier = get_chord_name(1 + 1, params:get('mode'), chord_degree) -- transpose root?
  end
end  


function play_chord(destination, channel)
  chord = musicutil.generate_chord_scale_degree(chord_seq[pattern][chord_seq_position].o * 12, params:get('mode'), chord_seq[pattern][chord_seq_position].c, true)
  local destination = params:string('chord_dest')
  if destination == 'Engine' then
    for i = 1, params:get('chord_type') do
      local note = chord[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_engine('chord', note)
    end
  elseif destination == 'MIDI' then
    for i = 1, params:get('chord_type') do
      local note = chord[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_midi(note, params:get('chord_midi_velocity'), params:get('chord_midi_ch'), chord_duration)
    end
  elseif destination == 'Crow' then
    for i = 1, params:get('chord_type') do
      local note = chord[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_crow('chord',note)
    end
  elseif destination =='ii-JF' then
    for i = 1, params:get('chord_type') do
      local note = chord[i] + params:get('transpose') + 12 + (params:get('chord_octave') * 12)
      to_jf('chord',note, params:get('chord_jf_amp')/10)
    end
  end
end


-- Pre-load upcoming chord to address race condition around quantize_note() events occurring before chord change
function get_next_chord()
  local temp_pattern = pattern
  local temp_chord_seq_position = chord_seq_position
  local temp_pattern_seq_retrig = false

  -- Rewriting this to see if it works without temp_pattern_seq_retrig
  -- -- If arranger is enabled and it's the last step in the chord sequence, advance the arranger first and set temp_pattern_seq_retrig
  -- if params:get('arranger_enabled') == 1 and temp_chord_seq_position >= pattern_length[temp_pattern] then 
  --   temp_pattern = pattern_seq[util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)]
  --   temp_pattern_seq_retrig = true
  -- end
  -- -- Irrespective of arranger state, if it's the last step in the chord sequence OR temp_pattern_seq_retrig (redundant?), advance the chord sequence pattern and reset temp_pattern_seq_retrig
  -- if temp_chord_seq_position >= pattern_length[temp_pattern] or temp_pattern_seq_retrig then
  --   if pattern_queue then
  --     temp_pattern = pattern_queue
  --   end
  --   temp_chord_seq_position = 1
  --   temp_pattern_seq_retrig = false
  -- else  
  --   temp_chord_seq_position = util.wrap(temp_chord_seq_position + 1, 1, pattern_length[temp_pattern])
  -- end

  --Refactor
  if temp_chord_seq_position >= pattern_length[temp_pattern] then
    if params:get('arranger_enabled') == 1 then
      temp_pattern = pattern_seq[util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)]
    end
    if pattern_queue then
      temp_pattern = pattern_queue
    end
    temp_chord_seq_position = 1
  else  
    temp_chord_seq_position = util.wrap(temp_chord_seq_position + 1, 1, pattern_length[temp_pattern])
  end
  
  
  if chord_seq[temp_pattern][temp_chord_seq_position].c > 0 then
    chord = musicutil.generate_chord_scale_degree(chord_seq[temp_pattern][temp_chord_seq_position].o * 12, params:get('mode'), chord_seq[temp_pattern][temp_chord_seq_position].c, true)
  end
end


function quantize_note(note_num, source)
  local chord_length = params:get(source..'_chord_type') -- Move upstream?
  local source_octave = params:get(source..'_octave') -- Move upstream?
  local quantized_note = chord[util.wrap(note_num, 1, chord_length)]
  local quantized_octave = math.floor((note_num - 1) / chord_length)
  return(quantized_note + ((source_octave + quantized_octave) * 12) + params:get('transpose'))
end


function advance_arp_seq()
  if arp_seq_position > arp_pattern_length[arp_pattern] or pattern_seq_retrig == true then -- Validate pattern_seq_retrig addition
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
      to_midi(note, params:get('arp_midi_velocity'), params:get('arp_midi_ch'), arp_duration)
    elseif destination == 'Crow' then
      to_crow('arp',note)
    elseif destination =='ii-JF' then
      to_jf('arp',note, params:get('arp_jf_amp')/10)
    end
  end
  
  if params:string('arp_mode') == 'One-shot' and arp_seq_position >= arp_pattern_length[arp_pattern] then
     play_arp = false
  else
  end   
end

function crow_trigger(s) --Trigger in used to sample voltage from Crow IN 1
    state = s
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
end


function sample_crow(volts)
  local note = quantize_note(round(volts * 12, 0) + 1, 'crow')
  
  -- Blocks duplicate notes within a chord step so rests can be added to simple CV sources
  if chord_seq_retrig == true
  or params:get('do_crow_auto_rest') == 0 
  or (params:get('do_crow_auto_rest') == 1 and (prev_note ~= note)) then
    
    -- Play the note
    local destination = params:string('crow_dest')
    if destination == 'Engine' then
      to_engine('crow', note)
    elseif destination == 'MIDI' then
      to_midi(note, params:get('crow_midi_velocity'), params:get('crow_midi_ch'), crow_duration)
    elseif destination == 'Crow' then
      to_crow('crow', note)
    elseif destination =='ii-JF' then
      to_jf('crow',note, params:get('crow_jf_amp')/10)
    end
  end
  
  prev_note = note
  chord_seq_retrig = false -- Resets at chord advance
end


in_midi.event = function(data)
  local d = midi.to_msg(data)
  -- if params:get('clock_source') == 2 and d.type == 'stop' then -- placeholder for determining source of transport.stop
  if d.type == "note_on" then
    local note = quantize_note(d.note - 35, 'midi')
    local destination = params:string('midi_dest')
    if destination == 'Engine' then
      to_engine('midi', note)
    elseif destination == 'MIDI' then
      to_midi(note, params:get('do_midi_velocity_passthru') == 1 and d.vel or params:get('midi_midi_velocity'), params:get('midi_midi_ch'), midi_duration)
    elseif destination == 'Crow' then
      to_crow('midi', note)
    elseif destination =='ii-JF' then
      to_jf('midi', note, params:get('midi_jf_amp')/10)
    end
  end
end


function to_engine(source, note)
  local note_on_time = util.time()
  engine_play_note = true
  engine_note_history_insert = true  
  
  -- Check for duplicate notes and process according to repeat_notes setting
  for i = 1, #engine_note_history do
    if engine_note_history[i][2] == note then
      engine_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:string('repeat_notes') == 'Dedupe' and (note_on_time - engine_note_history[i][3]) < dedupe_threshold_s then
        engine_play_note = false
      end
    end
  end
  
  if engine_play_note == true then
    engine.amp(params:get(source..'_pp_amp') / 100)
    engine.cutoff(params:get(source..'_pp_cutoff'))
    -- engine.release(duration_sec(source.._duration))
    engine.release(duration_sec(_G[source .. '_duration']))

    engine.gain(params:get(source..'_pp_gain') / 100)
    engine.pw(params:get(source..'_pp_pw') / 100)
    engine.hz(musicutil.note_num_to_freq(note + 36))
  end
  
  if engine_note_history_insert == true then
    -- Subbing dedupe_threshold_int for duration for engine out. Only used to make sure record is kept long enough to do a dedupe check.
    table.insert(engine_note_history, {dedupe_threshold_int, note, note_on_time})    
  end
end


function to_midi(note, velocity, channel, duration)
  local midi_note = note + 36
  local note_on_time = util.time()
  midi_play_note = true
  midi_note_history_insert = true
  
  -- Check for duplicate notes and process according to repeat_notes setting
  for i = 1, #midi_note_history do
    if midi_note_history[i][2] == midi_note and midi_note_history[i][3] == channel then

      -- Preserves longer note-off duration to avoid weirdness around a which-note-was first race condition. Ex: if a sustained chord and a staccato note play at approximately the same time, the chord's note will sustain without having to worry about which came first. This does require some special handling below which is not present in other destinations.
      
      midi_note_history[i][1] = math.max(duration, midi_note_history[i][1])
      midi_note_history_insert = false -- Don't insert a new note-off record since we just updated the duration

      if params:string('repeat_notes') == 'Dedupe' and (note_on_time - midi_note_history[i][4]) < dedupe_threshold_s then
        -- print(('Deduped ' .. note_on_time - midi_note_history[i][4]) .. ' | ' .. dedupe_threshold_s)
        midi_play_note = false -- Prevent duplicate note from playing
      end
    
      -- Always update any existing note_on_time, even if a note wasn't played. 
      -- Otherwise the note duration may be extended but the gap between note_on_time and current time grows indefinitely and no dedupe occurs.
      -- Alternative is to not extend the duration when 'repeat_notes' == 'Dedupe' and a duplicate is found
      midi_note_history[i][4] = note_on_time
    end
  end
  
  -- Play note and insert new note-on record if appropriate
  if midi_play_note == true then
    out_midi:note_on((midi_note), velocity, channel)
  end
  if midi_note_history_insert == true then
    table.insert(midi_note_history, {duration, midi_note, channel, note_on_time})
  end
end


function to_crow(source, note)
  local note_on_time = util.time()
  crow_play_note = true
  crow_note_history_insert = true

  -- Check for duplicate notes and process according to repeat_notes setting
  for i = 1, #crow_note_history do
    if crow_note_history[i][2] == note then
      crow_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:string('repeat_notes') == 'Dedupe' and (note_on_time - crow_note_history[i][3]) < dedupe_threshold_s then
        crow_play_note = false
      end
    end
  end

  --Play the note
  if crow_play_note == true then
    crow.output[1].volts = (note) / 12
    crow.output[2].volts = 0  -- Needed or skew 100 AR gets weird
    if params:get(source..'_tr_env') == 1 then  -- Trigger
      crow.output[2].action = 'pulse(.001,10,1)' -- (time,level,polarity)
    else -- envelope
      local crow_attack = duration_sec(_G[source .. '_duration']) * params:get(source..'_ar_skew') / 100
      local crow_release = duration_sec(_G[source .. '_duration']) * (100 - params:get(source..'_ar_skew')) / 100
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


--WIP for estimating JF's envelope time using regression. Doesn't update on call though because of an issue with crow.ii.jf.event?
-- crow.ii.jf.event = function( e, value )
--   if e.name == 'time' then
--     jf_time_v = value
--     jf_time_v_to_s = math.exp(-0.694351 * value + 3.0838)
--   end
-- end

-- function jf_time()
--   crow.ii.jf.get( 'time' )
--   return(jf_time_v_to_s)
-- end


function to_jf(source, note, amp)
  local note_on_time = util.time()
  jf_play_note = true
  jf_note_history_insert = true 

  -- Check for duplicate notes and process according to repeat_notes setting
  for i = 1, #jf_note_history do
    if jf_note_history[i][2] == note then
      jf_note_history_insert = false -- Don't insert or update note record since one is already there
      if params:string('repeat_notes') == 'Dedupe' and (note_on_time - jf_note_history[i][3]) < dedupe_threshold_s then
        jf_play_note = false
      end
    end
  end
  
  if jf_play_note == true then
    crow.ii.jf.play_note((note - 24)/12, amp)
  end
  
  if jf_note_history_insert == true then
    -- Subbing dedupe_threshold_int for duration for engine out. Only used to make sure record is kept long enough to do a dedupe check.
  table.insert(jf_note_history, {dedupe_threshold_int, note, note_on_time})    
  end
end


function grid_redraw()
  g:all(0)
  for i = 6,8 do
    g:led(16,i,4)
  end
  if grid_view_name == 'Arranger' then
    g:led(16,6,15)
    for x = 1,16 do
      for y = 1,4 do
        g:led(x,y, x == pattern_seq_position and 7 or 3)
        if y == pattern_seq[x] then
          g:led(x, y, 15)
        end
      end
    end
  elseif grid_view_name == 'Chord' then
    if params:get('arranger_enabled') == 1 and arranger_one_shot_last_pattern == false then
      next_pattern_indicator = pattern_seq[util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)]
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
      g:led(15, i, pattern_length[pattern] < i and 4 or 15)           --set pattern_length LEDs
      if chord_seq[pattern][i].x > 0 then                             -- muted steps
        g:led(chord_seq[pattern][i].x, i, 15)                         -- set LEDs for chord sequence
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
  g:refresh()
end

function g.key(x,y,z)
  if z == 1 then
    if x == 16 and y > 5 then --view switcher buttons
      view_key_count = view_key_count + 1
      grid_view_index = y - 5
      grid_view_name = grid_views[grid_view_index]
      
    --ARRANGER KEYS
    elseif grid_view_name == 'Arranger' then
      if y < 5 then
        if y == pattern_seq[x] and x > 1 then 
          pattern_seq[x] = 0
        else pattern_seq[x] = y  
        end
        for i = 1,17 do
          if pattern_seq[i] == 0  or i == 17 then
            pattern_seq_length = i - 1
            break
          end
        end 
        -- Jump to first pattern in arranger if it's changed while arranger is reset (not paused). Might be confusing?
        if params:get('arranger_enabled') == 1 and pattern_seq_position == 0 and chord_seq_position == 0 then  
          pattern = pattern_seq[1]
        end
      end
      if transport_active == false then -- Update chord for when play starts
        get_next_chord()
      end
    --CHORD KEYS
    elseif grid_view_name == 'Chord' then
      if x < 15 then
        chord_key_count = chord_key_count + 1
        if x == chord_seq[pattern][y].x then
          chord_seq[pattern][y].x = 0
          chord_seq[pattern][y].c = 0
          chord_seq[pattern][y].o = 0
        else
          chord_seq[pattern][y].x = x --raw key x coordinate
          chord_seq[pattern][y].c = util.wrap(x, 1, 7) --chord 1-7 (no octave). Should move this to a function since it's called a few places.
          chord_seq[pattern][y].o = math.floor(x / 8) --octave
        end
        chord_no = x + (params:get('chord_type') == 4 and 7 or 0) -- or 0
        generate_chord_names()
      elseif x == 15 then
        pattern_length[pattern] = y
      elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher. Key UP events farther down in function.
        pattern_key_count = pattern_key_count + 1 -- Fix: issue with this not firing resulting in negative key count?
        pattern_keys[y] = 1
        if pattern_key_count == 1 then
          pattern_copy_source = y
        elseif pattern_key_count > 1 then
          print('Copying pattern ' .. pattern_copy_source .. ' to pattern ' .. y)
          pattern_copy_performed = true
          for i = 1,8 do
            chord_seq[y][i].x = chord_seq[pattern_copy_source][i].x
            chord_seq[y][i].c = chord_seq[pattern_copy_source][i].c
            chord_seq[y][i].o = chord_seq[pattern_copy_source][i].o
          end
          pattern_length[y] = pattern_length[pattern_copy_source]
        end
      end
      if transport_active == false then -- Pre-load chord for when play starts
        get_next_chord()
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
  
  --KEY RELEASED
  elseif z == 0 then
    if grid_view_name == 'Chord' then
      if x == 16 and y <5 then
        pattern_key_count = pattern_key_count - 1 --        pattern_key_count = math.max( 0, pattern_key_count - 1)
        pattern_keys[y] = nil
        if pattern_key_count == 0 and pattern_copy_performed == false then
          if y == pattern then
            print('a - manual reset of current pattern')
            params:set('arranger_enabled', 0)
            pattern_queue = false
            arp_seq_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_clock()             -- Fix: Should be a reset flag that is executed on the next beat
          elseif y == pattern_queue then -- Manual jump to queued pattern
            print('b - manual jump to queued pattern')
            pattern_queue = false
            pattern = y
            arp_seq_position = 0       -- For manual reset of current pattern as well as resetting on manual pattern change
            chord_seq_position = 0
            reset_clock()             -- Fix: Should be a reset flag that is executed on the next beat
          else                        -- Queue up a new pattern
            print('c - new pattern queued')
            if pattern_copy_performed == false then
              pattern_queue = y
              params:set('arranger_enabled', 0)
            end
          end
        end
      elseif x < 15 then
        chord_key_count = chord_key_count - 1
        if chord_key_count == 0 and chord_seq_position ~= 0 then
          chord_no = chord_seq[pattern][chord_seq_position].c + (params:get('chord_type') == 4 and 7 or 0)
          generate_chord_names()
        else chord_no = 0
        end
      end
    end
    
  -- GRID VIEW SWITCHER KEYS  
  if x == 16 and y > 5 then
    view_key_count = view_key_count - 1
  end
  if pattern_key_count == 0 then
    pattern_copy_performed = false
  end
end
redraw()
grid_redraw()
end


function key(n,z)
  if z == 1 then
  keys[n] = 1
  key_count = key_count + 1
    if n == 1 then
      -- Fn menu is displayed since keys[1] == 1
    elseif n == 2 then
      if keys[1] == 1 then
        randomize()
      elseif params:string('clock_source') == 'internal' then
        if transport_active then
          clock.transport.stop()
          clock_start_method = 'continue'
          start = true  -- Test!
        else
          clock.transport.start()
        end
      end
    elseif n == 3 then
      -- K3 in Generator immediately randomizes and resets, other views just reset
      if screen_view_name == 'Generator' then
        randomize()
      end
      
      
      -- If we're sending MIDI clock out, send a stop msg
      -- Tell the transport to Start on the next sync of sequence_clock
      if params:get('clock_midi_out') ~= 1 then
        if transport_active then
          transport_midi:stop()
        end
        -- Tells sequence_clock to send a MIDI start/continue message after initial clock sync
        clock_start_method = 'start'
        start = true
      end    

  
      if params:get('arranger_enabled') == 1 then
        reset_arrangement()
      else
        reset_pattern()       
      end
      

      
      -- -- KEEP THIS AROUND: Logic for resetting arranger
      -- if params:get('arranger_enabled') == 1 then
      --   reset_arrangement()
      -- else
      --   reset_pattern()

      -- Enable/disable Arranger. Switching out with Reset key.
      -- if params:get('arranger_enabled') == 1 then  -- If follow is on, turn off
      --   params:set('arranger_enabled', 0)
      -- elseif transport_active == true then  -- If follow is off but we're playing, pick up arrangement
      --   print('Resuming arrangement on next pattern advance')
      --   params:set('arranger_enabled', 1)
      -- else 
      --   print('Transport stopped; resetting arrangement')
      --   params:set('arranger_enabled', 1)  -- If follow is off and transport is stopped, reset arrangement
      --   reset_arrangement()
      -- end
      
    end
  elseif z == 0 then
    keys[n] = nil
    key_count = key_count - 1
  end
  redraw()
end


-- Rotate looping portion of pattern
function rotate_pattern(view, direction)
  if view == 'Chord' then
    local length = pattern_length[pattern]
    local temp_chord_seq = {}
    for i = 1, length do
      temp_chord_seq[i] = {x = chord_seq[pattern][i].x} -- I still don't get why this has to be formatted differently
      temp_chord_seq[i]['c'] = chord_seq[pattern][i].c 
      temp_chord_seq[i]['o'] = chord_seq[pattern][i].o
    end
    for i = 1, length do
      chord_seq[pattern][i]['x'] = temp_chord_seq[util.wrap(i - direction,1,length)].x
      chord_seq[pattern][i]['c'] = temp_chord_seq[util.wrap(i - direction,1,length)].c
      chord_seq[pattern][i]['o'] = temp_chord_seq[util.wrap(i - direction,1,length)].o
    end
  elseif view == 'Arp' then
    local length = arp_pattern_length[arp_pattern]
    local temp_arp_seq = {}
    for i = 1, length do
      temp_arp_seq[i] = arp_seq[arp_pattern][i]
    end
    for i = 1, length do
      arp_seq[arp_pattern][i] = temp_arp_seq[util.wrap(i - direction,1,length)]
    end
  end
end


-- "Transposes" pattern if you can call it that
function transpose_pattern(direction)
  if grid_view_name == 'Chord' then
    for y = 1,8 do
      if chord_seq[pattern][y]['x'] ~= 0 then
        chord_seq[pattern][y]['x'] = util.wrap(chord_seq[pattern][y]['x'] + direction, 1, 14)
        chord_seq[pattern][y].c = util.wrap(chord_seq[pattern][y]['x'], 1, 7) --chord 1-7 (no octave)
        chord_seq[pattern][y].o = math.floor(chord_seq[pattern][y]['x'] / 8) --octave
      end
    end
  elseif grid_view_name == 'Arp' then
    for y = 1,8 do
      if arp_seq[arp_pattern][y] ~= 0 then
        arp_seq[arp_pattern][y] = util.wrap(arp_seq[arp_pattern][y] + direction, 1, 14)
      end
    end
  end  
end   

  
function enc(n,d)
  if keys[1] == 1 then -- function key (KEY1) held down mode
    if n == 2 then
      rotate_pattern(grid_view_name, d)
    elseif n == 3 then
      transpose_pattern(d)
    end
    grid_redraw()
  else
      if n == 1 then
      -- menu_index = 0
      -- page_index = util.clamp(page_index + d, 1, #pages)
      -- page_name = pages[page_index]
      -- selected_menu = menus[page_index][menu_index]
      
      screen_view_index = util.clamp(screen_view_index + d, 1, 3)
      screen_view_name = screen_views[screen_view_index]
      elseif n == 2 then
        if screen_view_name == 'Arranger' then
          arranger_menu_index = util.clamp(arranger_menu_index + d, 1, #arranger_menus)
          print(arranger_menu_index)
          selected_arranger_menu = arranger_menus[arranger_menu_index]
          -- print(selected_arranger_menu)
        else
          menu_index = util.clamp(menu_index + d, 0, #menus[page_index])
          selected_menu = menus[page_index][menu_index]
        end
    else -- n== 3
      if screen_view_name == 'Arranger' then      
        selected_arranger_menu = arranger_menus[arranger_menu_index]
        params:delta(selected_arranger_menu, d)
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
  end
  redraw()
end


function chord_steps_to_seconds(steps)
  return(steps * 60 / params:get('clock_tempo') / global_clock_div * chord_div) -- switched to var Fix: timing
end

-- Truncates hours. Requires integer.
function s_to_min_sec(s)
  local m = math.floor(s/60)
  -- local h = math.floor(m/60)
  m = m%60
  s = s%60
  return string.format("%02d",m) ..":".. string.format("%02d",s)
end

function param_formatter(param)
  if param == 'source' then
    return('Clock: ')
  elseif param == 'midi out' then
    return('Out: ')
  else 
    return(param .. ': ')
  end
end


--This needs some work and will get off if the menu is too long
function scroll_offset(index, total, in_view, height) --index of list, count of items in list, #viewable, line height
  if total > in_view and menu_index > 1 then
    --math.ceil might make jumps larger than necessary, but ensures nothing is cut off at the bottom of the menu
    return(math.ceil(((index - 1) * (total - in_view) * height / total)))
  else return(0)
  end
end


function redraw()
  screen.clear()
  screen.aa(0)
  
  --Arranger time rect
  screen.level(7)
  screen.rect(94,0,34,11)
  screen.fill()
  screen.level(0)
  screen.rect(95,1,32,9)
  screen.fill()

  -- Chord readout rect
  screen.level(4)
  screen.rect(94,13,34,20)
  screen.fill()
  screen.level(0)
  screen.rect(95,14,32,18)
  screen.fill()

  -- Chord degree and name
  if chord_no > 0 then
    screen.move(111,21)
    screen.level(15)
    screen.text_center(chord_degree or '') -- Chord degree
    screen.move(111,29)
    screen.text_center((chord_name or '')..(chord_name_modifier or '')) -- Chord name
  end
  
   --Calculate what we need to display arrangement time remaining and draw the arranger mini-chart
  local rect_x = pattern_seq_position == 0 and 1 or 0 -- If arranger is reset, add an initial gap to the x position
  pattern_pos = pattern_seq_position == 0 and 1 or pattern_seq_position --same as max 1
  steps_remaining_in_arrangement = 0  -- Reset this before getting a running sum from the DO below

  for i = pattern_pos, pattern_seq_length do
    steps_elapsed = (i == pattern_pos and math.max(chord_seq_position,1) or 0) or 0 -- steps elapsed in current pattern  -- MAKE LOCAL
    percent_step_elapsed = (math.max(clock_step,0) % chord_div / (chord_div-1)) -- % of current chord step elapsed
    
    -- % of current chord step remaining
    -- percent_step_remaining = 1-(math.max(clock_step,0) % params:get('chord_div_index') / (params:get('chord_div_index')-1))
    
    steps_remaining_in_pattern = pattern_length[pattern_seq[i]] - steps_elapsed  --rect_w
    steps_remaining_in_arrangement = steps_remaining_in_arrangement + steps_remaining_in_pattern
    seconds_remaining_in_arrangement = chord_steps_to_seconds(steps_remaining_in_arrangement + 1-percent_step_elapsed )
    
    -- Draw timeline. Needs to be run in this loop rather than in Arranger view section
    if screen_view_name == 'Arranger' then
      rect_h = 2
      rect_y = 50 + (pattern_seq[i]* 2) + pattern_seq[i]
      rect_gap_adj = pattern_pos - 1
      screen.level(params:get('arranger_enabled') == 1 and 15 or 3)
      screen.rect(rect_x + i - rect_gap_adj, rect_y, steps_remaining_in_pattern, rect_h)
      screen.fill()
      rect_x = rect_x + steps_remaining_in_pattern
    end
  end
    
  -- For all screen views, draw arranger time and glyphs
  screen.move(97,8)
  screen.level(params:get('arranger_enabled') == 1 and 15 or 4)
  screen.text(s_to_min_sec(math.ceil(seconds_remaining_in_arrangement)))
  if params:get('arranger_enabled') == 1 then
    local x_offset = 120
    local y_offset = 3
      if params:get('playback') == 1 then
      for i = 1, #glyphs[1] do
        screen.pixel(glyphs[1][i][1] + x_offset, glyphs[1][i][2] + y_offset)
      end
    else 
      for i = 1, #glyphs[2] do
        screen.pixel(glyphs[2][i][1] + x_offset, glyphs[2][i][2] + y_offset)
      end
    end
  end
  
  -- Draw the arranger Y axis reference marks
  if screen_view_name == 'Arranger' then

    -- Axis reference marks so it's easier to distinguish the pattern position
    for i = 1,4 do
      screen.level(i == pattern_seq[pattern_seq_position] and 15 or 2)
      screen.rect(0,50 + i * 3, 1, 2)
      screen.fill()
    end  
    
  -- Arranger menu
    local menu_offset = scroll_offset(arranger_menu_index,#arranger_menus, 5, 10)  -- To-do: edit values to reflect Arranger screen space
    line = 1
    for i = 1,#arranger_menus do
      screen.move(2, line * 10 + 8 - menu_offset)    --exp
      screen.level(arranger_menu_index == i and 15 or 3)
      screen.text(first_to_upper(param_formatter(param_id_to_name(arranger_menus[i]))) .. string.sub(params:string(arranger_menus[i]), 1, 16))
      line = line + 1
    end
 
    -- Arranger sticky header
    screen.level(arranger_menu_index == 0 and 15 or 4)
    screen.rect(0,0,92,11)
    screen.fill()
    screen.move(2,8)
    screen.level(0)
    screen.text('ARRANGER')
      
  elseif screen_view_name == 'Generator' then
    -- Arranger sticky header
    screen.level(4)
    screen.rect(0,0,92,11)
    screen.fill()
    screen.move(2,8)
    screen.level(0)
    screen.text('GENERATOR')
    
  else -- SESSION
    -- print('Session')
    if view_key_count > 0 then
      screen.level(7)
      screen.move(64,32)
      screen.font_size(16)
      screen.text_center(grid_view_name)
      screen.font_size(8)
    elseif keys[1] == 1 then
      screen.level(15)
      screen.move(2,8)
      screen.text('FN KEY +')
      screen.move(2,28)
      screen.text('KEY 2: Randomize')
      screen.move(2,48)
      screen.text('ENC 2: Rotate seq ↑↓')
      screen.move(2,58)
      screen.text('ENC 3: Transpose seq ←→')
    else
      
      -- Scrolling menus
      local menu_offset = scroll_offset(menu_index,#menus[page_index], 5, 10)
      line = 1
      for i = 1,#menus[page_index] do
        screen.move(2, line * 10 + 8 - menu_offset)    --exp
        screen.level(menu_index == i and 15 or 3)
        screen.text(first_to_upper(param_formatter(param_id_to_name(menus[page_index][i]))) .. string.sub(params:string(menus[page_index][i]), 1, 16))
        line = line + 1
      end
   
      --Sticky header
      screen.level(menu_index == 0 and 15 or 4)
      screen.rect(0,0,92,11)
      screen.fill()
      screen.move(2,8)
      screen.level(0)
      screen.text('SESSION-'.. page_name)
      
    screen.fill()
    end
  end
  screen.update()
end

function percent_chance (percent)
  return percent >= math.random(1, 100) 
end

function clear_chord_pattern()
  for i = 1, 8 do
    chord_seq[pattern][i].x = 0
    chord_seq[pattern][i].c = 0
    chord_seq[pattern][i].o = 0
  end
end


function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

    
function randomize()
  
  params:set('chord_octave', math.random(0,1)) -- Linked to cutoff
  params:set('arp_octave', math.random(-1,1)) -- Linked to cutoff
    
    
  -- These can be overwritten by individual algorithms
  -- local random_divisions = {16,32,12,20,24,28,32}
  -- params:set('chord_div_index', random_divisions[math.random(1,2) + (percent_chance(10) and math.random(1,5) or 0)]) -- Mostly standard

  -- local random_divisions = {4,2,1,8,6,3,16,12,32,24,28,20} -- Front loaded with ones I like more
  -- params:set('arp_div_index', random_divisions[math.random(1,6 + (percent_chance(20) and math.random(1,6) or 0))])
  arp_pattern_length[1] = math.random(3,4) * (percent_chance(70) and 2 or 1)
  tuplet_shift = (arp_pattern_length[1] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
  params:set('arp_div_index', (math.random(2,6) * 2) - tuplet_shift)
  params:set('arp_duration_index',params:get('arp_div_index'))  -- Testing out setting these to the same val

  
  --SEQUENCE RANDOMIZATION
  
  params:set('transpose', math.random(-12,12))
  params:set('chord_type', percent_chance(20) and 4 or 3)
  params:set('arp_chord_type', percent_chance(40) and 4 or 3)
  
  if params:get('clock_source') == 1 then 
    params:set('clock_tempo', math.random(70,130))
  end
  params:set('mode', math.random(1,9))

  
  --ENGINE BASED RANDOMIZATIONS
  -- May be overwritten depending on algo type
  params:set('chord_pp_amp', 50)
  params:set('chord_pp_gain', math.random(0,350))
  params:set('chord_pp_pw', math.random(10,90))
  params:set('chord_div_index', 15)
  params:set('chord_duration_index', params:get('chord_div_index'))
  
  params:set('arp_pp_amp', 70)
  params:set('arp_pp_gain', math.random(0,350))
  params:set('arp_pp_pw', math.random(10,90))
  params:set('arp_mode', 1) -- Disabling unless enabled by specific algos, math.random(1,2))
  
  
  --CHORD PROGRESSION ALGOS
  chord_algo = math.random(1,4)
  
  if chord_algo == 1 then
    -- I-V-vi-IV based progression ****
    -- To-do: logic for 7th
    print('Chord algo: I-V-vi-IV-based progression')
    local modes = {1,2,3,8}
    params:set('mode', modes[math.random(1,4)])
    local progression = {1,5,6,4}
    pattern_length[pattern] = 4
    clear_chord_pattern()
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    rotate_pattern('Chord', math.random(0, 3))
    transpose_pattern(math.random() >= .5 and 7 or 0)
    
    
  elseif chord_algo == 2 then
    -- I-vi based major progression ***
    print('Chord algo: I-vi based major progression')
    -- local modes = {1,5,6,7,9} --Preferred but kinda optional. Check this again.
    params:set('mode', 1) -- modes[math.random(1,4)])
    local progression = {1,2,3,4,5,6}
    local progression = shuffle(progression)
    pattern_length[pattern] = 4
    clear_chord_pattern()
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    rotate_pattern('Chord', math.random(0, 3))
    transpose_pattern(math.random() >= .5 and 7 or 0)    
  
 
  elseif chord_algo == 3 then
    -- Some weird mostly random stuff
    print('Chord algo: Weird random chords')
    random_pattern_lengths = {3,4,6,8}
    random_pattern_length = random_pattern_lengths[2 + (percent_chance(20) and math.random(-1,2) or 0)] -- Mostly 4-chord patt, chance of others
    pattern_length[pattern] = random_pattern_length
    random_chord_offset = math.random (0,7)
    for i = 1, 8 do
      chord_seq[pattern][i].x = 0
      chord_seq[pattern][i].c = 0
      chord_seq[pattern][i].o = 0
    end
    for i = 1, pattern_length[pattern] do
      local random_1_14 = math.random(1,7) + random_chord_offset
      chord_seq[pattern][i].x = random_1_14 --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(random_1_14, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(random_1_14 / 8) --octave
    end
    
    if random_pattern_length > 4 and percent_chance(90) then  --Repeat the first half of 6/8-chord patterns
      local half_random_pattern_length = random_pattern_length / 2
      for i = 1, random_pattern_length / 2 do
        chord_seq[pattern][i + half_random_pattern_length].x = chord_seq[pattern][i].x
        chord_seq[pattern][i + half_random_pattern_length].c = chord_seq[pattern][i].c
        chord_seq[pattern][i + half_random_pattern_length].o = chord_seq[pattern][i].o
      end
      -- Modify the last chord of the pattern. Kinda cheesy.
      local random_1_14 = math.random(0,7) + random_chord_offset
      chord_seq[pattern][random_pattern_length].x = random_1_14 --raw key x coordinate
      chord_seq[pattern][random_pattern_length].c = util.wrap(random_1_14, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][random_pattern_length].o = math.floor(random_1_14 / 8) --octave
    end
  
  elseif chord_algo == 4 then
    -- I-vi based 2-chord progression ****
    print('Chord algo: I-vi based 2-chord progression')
    local modes = {1}
    params:set('mode', modes[math.random(1,#modes)])
    local progression = {1,2,3,4,5,6}
    local progression = shuffle(progression)
    if progression[1] - progression[2] > 3 then
      progression[2] = progression[2] + 7
    elseif progression[2] - progression[1] > 3 then
      progression[1] = progression[1] + 7
    end
    pattern_length[pattern] = 2
    clear_chord_pattern()
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end
    
    
    
elseif chord_algo == 5 then
    -- vi-ii-V-I based circle progression ***
    -- keeps ii–V–I turnaround at the end with random pattern length
    print('Chord algo: vi-ii-V-I based circle progression')
    local progression = {1,5,6,4}
    local progression = {8,4,7,3,6,2,5,1}
    local swappable_index_iii = {1,2,6,7,8} --Spots we might swap in a iii (avoiding repeat iii chords)
    local swappable_index_v = {1,2,3,4,5}   --Spots we might swap in a V (avoiding repeat V chords)
    -- Chance of adding a iii and V
    local chord_index = swappable_index_iii[math.random(1,4)]
    progression[chord_index] = percent_chance(50) and 3 or progression[chord_index]
    local chord_index = swappable_index_v[math.random(1,4)]
    progression[chord_index] = percent_chance(50) and 5 or progression[chord_index]
    pattern_length[pattern] = math.random(2,4) * 2
    clear_chord_pattern()
    for i = 1, pattern_length[pattern] do
      local x = progression[i + (8 - pattern_length[pattern])]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    -- 50% chance of rotating to end on I−vi−ii−V turnaround
    if percent_chance(50) then
      rotate_pattern('Chord', math.random() >= .5 and 1 or 0)
      -- optional octave shift of first chord. Doesn't really sound better IMO.
      -- if chord_seq[pattern][1].x == 1 then
      --   chord_seq[pattern][1].x = 8 --raw key x coordinate
      --   chord_seq[pattern][1].c = 1 --chord 1-7 (no octave)
      --   chord_seq[pattern][1].o = 1 --octave 
      -- end
    end
  end

    
    
  -- elseif chord_algo == 3 then
  --   -- ii-iii-IV-V based progression ***
  --   print('Chord algo: ii-iii-IV-V based progression')
  --   local modes = {1,5,8,9} --Preferred but kinda optional
  --   params:set('mode', modes[math.random(1,4)])
  --   local progression = {2,3,4,5}
  --   local progression = shuffle(progression)
  --   pattern_length[pattern] = 4
  --   clear_chord_pattern()
  --   for i = 1, pattern_length[pattern] do
  --     local x = progression[i]
  --     chord_seq[pattern][i].x = x --raw key x coordinate
  --     chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][i].o = math.floor(x / 8) --octave
  --   end  
  --   rotate_pattern('Chord', math.random(0, 3))
  --   transpose_pattern(math.random() >= .5 and 7 or 0)

  
  
    -- elseif chord_algo == 4 then
    -- -- I-ii-iii-IV-V based progression ***
    -- print('Chord algo: I-ii-iii-IV-V based progression')
    -- local modes = {1,5,6,7,9} --Preferred but kinda optional. Check this again.
    -- params:set('mode', modes[math.random(1,4)])
    -- local progression = {1,2,3,4,5}
    -- local progression = shuffle(progression)
    -- pattern_length[pattern] = 4
    -- clear_chord_pattern()
    -- for i = 1, pattern_length[pattern] do
    --   local x = progression[i]
    --   chord_seq[pattern][i].x = x --raw key x coordinate
    --   chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
    --   chord_seq[pattern][i].o = math.floor(x / 8) --octave
    -- end  
    -- rotate_pattern('Chord', math.random(0, 3))
    -- transpose_pattern(math.random() >= .5 and 7 or 0)
    
    
      -- elseif chord_algo == 4 then
  --   -- I-ii-iii-IV based progression ***
  --   print('Chord algo: I-ii-iii-IV based progression')
  --   local modes = {1,5,6,7,9} --Preferred but kinda optional
  --   params:set('mode', modes[math.random(1,4)])
  --   local progression = {1,2,3,4}
  --   local progression = shuffle(progression)
  --   pattern_length[pattern] = 4
  --   clear_chord_pattern()
  --   for i = 1, pattern_length[pattern] do
  --     local x = progression[i]
  --     chord_seq[pattern][i].x = x --raw key x coordinate
  --     chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][i].o = math.floor(x / 8) --octave
  --   end  
  --   rotate_pattern('Chord', math.random(0, 3))
  --   transpose_pattern(math.random() >= .5 and 7 or 0)
  
  --   elseif chord_algo == 5 then  
  --   -- Andalusian cadence *
  --   local mode = percent_chance(50) and 6 or 2 --Phyrigian or natural minor
  --   params:set('mode', mode)
  --   print('Chord algo: Andalusian cadence, ' .. params:string('mode'))
  --   local progression = {4,3,2,1}
  --   pattern_length[pattern] = 4
  --   clear_chord_pattern()
  --   for i = 1, pattern_length[pattern] do
  --     local x = progression[i] + (params:string('mode') == 'Natural Minor' and 4 or 0)
  --     chord_seq[pattern][i].x = x --raw key x coordinate
  --     chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][i].o = math.floor(x / 8) --octave
  --   end  
    
    
                  
  
  --ARP
  
  local arp_min = math.random(1,7)
  local arp_max = math.random(8,14)
  local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  local random_1_7 = math.random(1,7)
  local random_4_11 = math.random(4,11)   --arp note distribution center
  local random_1_14 = math.random(1,14)  
  
  -- arp_pattern_length[1] = (math.random(1,4) * 2) + (percent_chance(20) and math.random(-1,1) or 0) -- Mostly even lengths
  random_note_offset = math.random (0,7)
  for i = 1,8 do --Wipe
    arp_seq[1][i] = 0
  end
  
  er_table = {{},{}}
  er_table[1] = ER.gen(math.random(1, math.max(1,arp_pattern_length[1] - 1)), arp_pattern_length[1], 0) --pulses, steps, shift  -- max pulses?
  er_table[2] = ER.gen(math.random(1, math.max(1,arp_pattern_length[1] - 1)), arp_pattern_length[1], 0) --pulses, steps, shift  -- max pulses?
  
  er_note_on_count = 0
  for i = 1, #er_table[1] do
    er_note_on_count = er_note_on_count + (er_table[1][i] and 1 or 0)
  end
  
  arp_root = math.random(arp_min, arp_max)
  repeat
    arp_offset = math.random(arp_min, arp_max)
  until (arp_root ~= arp_offset)


  random_arp_algo = math.random(1,10)

  -- ER 1-note + rests ****
  if random_arp_algo == 1 then
    print('Arp algo: ER 1-note + rests ****')
    for i = 1, #er_table[1] do
      arp_seq[1][i] = er_table[1][i] and arp_root or 0
    end
    rotate_pattern('Arp', math.random(0,percent_chance(50) and 7 or 0)) 
    
    
  -- ER sequential + rests ****
  elseif random_arp_algo == 2 then    -- To-do: simplify once there is a universal check for out-of-range values
    print('Arp algo: ER sequential + rests ****')
    local note_shift = 0
    if arp_root - er_note_on_count < 1 then
      for i = 1, #er_table[1] do
        arp_seq[1][i] = er_table[1][i] and (arp_root + note_shift) or 0
        note_shift = note_shift + (er_table[1][i] and 1 or 0)
      end
    elseif arp_root + er_note_on_count > 14 then
      for i = 1, #er_table[1] do
        arp_seq[1][i] = er_table[1][i] and (arp_root + note_shift) or 0
        note_shift = note_shift - (er_table[1][i] and 1 or 0)
      end
    else
      local direction = (arp_root + math.random() > .5 and 1 or -1)
      for i = 1, #er_table[1] do    -- I don't think this is firing?
        arp_seq[1][i] = er_table[1][i] and (arp_root + note_shift) or 0
        note_shift = note_shift + (er_table[1][i] and direction or 0)
      end
    end


  -- ER drunk + rests ***  -- no check for out of bounds x
  elseif random_arp_algo == 3 then
    print('Arp algo: ER drunk + rests ***')
    local note_shift = 0
    for i = 1, #er_table[1] do
      arp_seq[1][i] = er_table[1][i] and (arp_root + note_shift) or 0
      direction = math.random() > .5 and 1 or -1
      note_shift = note_shift + (er_table[1][i] and direction or 0)
    end
  
  
  elseif random_arp_algo == 4 then   
    -- Sequential up
    print('Arp algo: Sequential up')
    for i = 1, arp_pattern_length[1] do
      arp_seq[1][i] = arp_min - 1 + i
    end


  elseif random_arp_algo == 5 then       
    -- Sequential down
    print('Arp algo: Sequential down')
    for i = 1, arp_pattern_length[1] do
      arp_seq[1][i] = arp_max + 1 - i
    end
  
  
  elseif random_arp_algo == 6 then       
    -- Random with chance of ER mask
    print('Arp algo: Random with ER mask')
    for i = 1, arp_pattern_length[1] do
      arp_seq[1][i] = math.random(1,7) + random_note_offset
    end
    if percent_chance(60) then --add some rests to the arp
      for i = 1, arp_pattern_length[1] do
        arp_seq[1][i] = er_table[1][i] and arp_seq[1][i] or 0
      end
    end
  
  elseif random_arp_algo == 7 then 
    -- Strum up
    print('Arp algo: Strum up')
    
    -- Pretty fast arps here so no shifting octave down
    -- params:set('arp_octave', math.max(params:get('arp_octave'), 0))
    
    params:set('arp_mode', 2)
    params:set('arp_pp_amp',70) --Turn down amp since a lot of notes can clip
    params:set('arp_duration_index',15)
    arp_pattern_length[1] = math.random(3,4) * 2

    -- Strum speed from 1/64T to 1/32T
    params:set('arp_div_index', math.random(1,5))
    
    for i = 1, arp_pattern_length[1] do
      arp_seq[1][i] = arp_min - 1 + i
    end 


  elseif random_arp_algo == 8 then
    -- Strum down
    print('Arp algo: Strum down')
    
    -- Pretty fast arps here so no shifting octave down
    -- params:set('arp_octave', math.max(params:get('arp_octave'), 0))
    
    params:set('arp_mode', 2)
    params:set('arp_pp_amp',70) --Turn down amp since a lot of notes can clip
    params:set('arp_duration_index',15)
    arp_pattern_length[1] = math.random(3,4) * 2

    -- Strum speed from 1/64T to 1/32T
    params:set('arp_div_index', math.random(1,5))
    
    for i = 1, arp_pattern_length[1] do
      arp_seq[1][i] = arp_max - 1 - i
    end
    
    
  -- Sequential up-down  
  elseif random_arp_algo == 9 then 
    print('Arp algo: Sequential up-down')
      
    -- Pretty fast arps here so no shifting octave down
    params:set('arp_octave', math.max(params:get('arp_octave'), 0))

    -- Prefer longer and faster sequence    
    arp_pattern_length[1] = math.random(3,4) * 2 -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[1] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    print(params:get('clock_tempo') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    local peak = math.random(2, arp_pattern_length[1] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_min - 1 + i
    end
    for i = 1, arp_pattern_length[1] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] - i
    end  
 

  -- Sequential down-up  
  elseif random_arp_algo == 10 then 
    print('Arp algo: Sequential down-up')
      
    -- Pretty fast arps here so no shifting octave down
    params:set('arp_octave', math.max(params:get('arp_octave'), 0))

    -- Prefer longer and faster sequence    
    arp_pattern_length[1] = math.random(3,4) * 2 -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[1] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    -- print(params:get('clock_tempo') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    local peak = math.random(2, arp_pattern_length[1] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_max - 1 - i
    end
    for i = 1, arp_pattern_length[1] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] + i
    end  
    
    
  end -- end of arp selection
  




  -- This is all about setting the engine cutoff values to something reasonable for the pitch of the chord and arp  
  local chord_octave_shift = (params:get('chord_octave') * 7 ) -- octave param effectively shifts chord x by this many colums 
  local arp_octave_shift = (params:get('arp_octave') * params:get('arp_chord_type') ) -- octave param effectively shifts arp x by this many colums  

  max_chord_x = 0
  for i = 1,8 do
    max_chord_x = chord_seq[pattern][i].x > max_chord_x and chord_seq[pattern][i].x or max_chord_x
  end
  max_chord_x = max_chord_x + chord_octave_shift + params:get('transpose')
  
  local max_arp_x = math.max(table.unpack(arp_seq[1])) + arp_octave_shift + (params:get('transpose') / params:get('arp_chord_type'))-- Max x + effective offset for arp octave
  local arp_min_cutoff = util.round(math.exp(.09 * max_arp_x + 6.1)) -- Makes sure the cutoff is appropriate for the arp range
  local arp_max_cutoff = util.round(52.8017 * max_arp_x  + 3294.61) -- Setting an upper limit on the cutoff so there is some adjustability after
  local chord_min_cutoff = util.round(math.exp(0.03 * max_arp_x + 6.2)) -- Makes sure the cutoff is appropriate for the chord range
  
  -- To-do: update cutoff logic to consider pitch change from 4-note (7th chords as well as key/transposition)
  params:set('arp_pp_cutoff', math.random(arp_min_cutoff, arp_min_cutoff + 1000)) -- testing with min first math.random(arp_min_cutoff, arp_max_cutoff))
  params:set('chord_pp_cutoff', math.random(chord_min_cutoff, chord_min_cutoff + 1000)) -- testing with min first

  grid_redraw()
  redraw()
end