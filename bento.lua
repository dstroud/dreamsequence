-- Bento
--
-- KEY 1: n/a
-- KEY 2: start/stop
-- KEY 3: arrange on/off
--
-- ENC 1: select page
-- ENC 2: select menu
-- ENC 3: edit value 
--
-- Crow IN 1: cv in
-- Crow IN 2: trigger in
-- Crow OUT 1: v/oct out
-- Crow OUT 2: trigger out
-- Crow OUT 3: clock out
-- Crow OUT 4: assignable


g = grid.connect()
engine.name = "PolyPerc"
music = require 'musicutil'

in_midi = midi.connect(1)
out_midi = midi.connect(1) -- To-do: multiple MIDI in/out


function init()
  crow.ii.jf.mode(1)
  params:set('clock_crow_out', 1) -- Turn off built-in Crow clock so it doesn't conflict with Bento's clock

  -- Duration name, clock tics, beat multiplier. Triplet vals? To-do: assign calculation of seconds to clock_tempo action.
  durations = {
    {'1/32', 8, .125},
    {'1/16',16, .25},
    {'1/8', 32, .5},
    {'1/4', 64, 1}, --clock.get_beat_sec()
    {'1/2', 128, 2},
    {'Whole', 256, 4}}

  --Global params
  params:add_separator ('Global')
  params:add_number("transpose","Transpose",-24, 24, 0)
  params:add{
    type = 'number',
    id = 'mode',
    name = 'Mode',
    min = 1,
    max = 9,
    default = 1,
    formatter = function(param) return mode_index_to_name(param:get()) end,}
  params:add{
  type = 'number',
  id = 'block_repeats',
  name = 'Block Repeats',
  min = 0,
  max = 1,
  default = 0,
  formatter = function(param) return t_f_string(param:get()) end}

  --Arrange params
  params:add_separator ('Arrange')
  params:add{
    type = 'number',
    id = 'do_follow',
    name = 'Follow',
    min = 0,
    max = 1,
    default = 1,
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
  
  --Chord params
  params:add_separator ('Chord')
  params:add_number('chord_div', 'Division', 4, 128, 32) -- most useful {4,8,12,16,24,32,65,96,128,192,256
  params:add_option("chord_dest", "Destination", {'None',"Engine", 'MIDI', 'ii-JF'},3)
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
  params:add_number("chord_pp_gain","Gain",0, 400, 200)
  params:add_number("chord_pp_pw","Pulse width",1, 99, 50)
  params:add_number('chord_midi_velocity','Velocity',0, 127, 100)
  params:add_number('chord_midi_ch','Channel',1, 16, 1)
  params:add_number('chord_jf_amp','Amp',0, 50, 10,function(param) return div_10(param:get()) end)
  params:add_number('crow_pullup','Crow Pullup',0, 1, 0,function(param) return t_f_string(param:get()) end) --JF = chord only
    params:set_action("crow_pullup",function() crow_pullup() end)
  params:add_number('chord_duration', 'Duration', 1, 6, 6, function(param) return duration_string(param:get()) end)
  params:add_number('chord_octave','Octave',-2, 2, 0)

  --Arp params
  params:add_separator ('Arp')
  params:add_number('arp_div', 'Division', 1, 32, 4) --most useful {1,2,4,8,16,24,32}
  params:add_option("arp_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow'},3)
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
  params:add_number("arp_pp_gain","Gain",0, 400, 200)
  params:add_number("arp_pp_pw","Pulse width",1, 99, 50)
  params:add_number('arp_midi_velocity','Velocity',0, 127, 127)
  params:add_number('arp_midi_ch','Channel',1, 16, 1)
  params:add_number('arp_duration', 'Duration', 1, 6, 3, function(param) return duration_string(param:get()) end)
  params:add_number('arp_octave','Octave',-2, 2, 0)
  
  --MIDI params
  params:add_separator ('MIDI')
  params:add_option("midi_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow'},3)
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
  params:add_number("midi_pp_gain","Gain",0, 400, 200)
  params:add_number("midi_pp_pw","Pulse width",1, 99, 50)
  params:add_number('midi_midi_ch','Channel',1, 16, 1)
  params:add_number('midi_midi_velocity','Velocity',0, 127, 110)
  params:add{
    type = 'number',
    id = 'do_midi_velocity_passthru',
    name = 'Pass velocity',
    min = 0,
    max = 1,
    default = 0,
    formatter = function(param) return t_f_string(param:get()) end,
    action = function() menu_update() end}
  params:add_number('midi_duration', 'Duration', 1, 6, 3, function(param) return duration_string(param:get()) end)
  params:add_number('midi_octave','Octave',-2, 2, 0)
  
  --Crow params
  params:add_separator ('Crow')
  params:add_number('crow_div', 'Clock out div', 1, 32, 8) --most useful TBD
  params:add_option("crow_dest", "Destination", {'None', 'Engine', 'MIDI', 'Crow'},3) --Fix: change back from MIDI
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
  params:add_number("crow_pp_gain","Gain",0, 400, 200)
  params:add_number("crow_pp_pw","Pulse width",1, 99, 50)
  -- params:add_number("crow_pp_release","Release",1, 10, 5)
  params:add_number('crow_midi_ch','Channel',1, 16, 1)
  params:add_number('crow_midi_velocity','Velocity',0, 127, 127)
  params:add_number('crow_duration', 'Duration', 1, 6, 3, function(param) return duration_string(param:get()) end)
  params:add_number('crow_octave','Octave',-2, 2, 0)
  
  glyphs = {
    {{1,0},{2,0},{3,0},{0,1},{0,2},{4,2},{4,3},{1,4},{2,4},{3,4}}, --repeat glyph     
    {{2,0},{3,1},{0,2},{1,2},{4,2},{3,3},{2,4}}, --one-shot glyph
          }
  prev_harmonizer_note = -999
  chord_seq_retrig = true
  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  crow.input[2].mode("change",2,0.1,"rising") --might want to use as a gate with "both"
  crow.input[2].change = crow_trigger
  crow.output[3].action = "pulse(.001,5,1)" -- Need to test this more vs. roll-your-own pulse
  grid_dirty = true
  views = {'Arrange','Chord','Arp'} -- grid "views" are decoupled from screen "pages"
  view_index = 2
  view_name = views[view_index]
  pages = {'Arrange','Chord','Arp','MIDI','Crow','Global'}
  page_index = 6
  page_name = pages[page_index]
  menus = {}
  menu_update()
  menu_index = 1
  selected_menu = menus[page_index][menu_index]
  transport_active = false
  pattern_length = {4,4,4,4} -- loop length for each of the 4 patterns. rename to chord_seq_length prob
  pattern = 1
  -- pattern_queue = pattern
  pattern_queue = false
  pattern_copy_performed = false
  pattern_seq_retrig = false
  pattern_seq = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  pattern_seq_position = 1
  pattern_seq_length = 1 
  pattern_key_count = 0
  global_clock_div = 8
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
  chord = music.generate_chord_scale_degree(chord_seq[pattern][1].o * 12, params:get('mode'), chord_seq[pattern][1].c, false)
  arp_seq = {{0,0,0,0,0,0,0,0},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8}
            } -- sub table for multiple arp patterns
  arp_pattern_length = {8,8,8,8}
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
  note_off_buffer = {}
  reset_clock() -- will turn over to step 0 on first loop
  -- clock.run(grid_redraw_clock) --Not used currently
  reset_clock()
  get_next_chord() -- Placeholder for when table loading from file is implemented
  grid_dirty = true
  grid_redraw()
end

function menu_update()
  -- Arrange menu
  menus[1] = {'do_follow','playback'}
  
  --chord menus   
  if params:string('chord_dest') == 'None' then
    menus[2] = {'chord_dest', 'chord_div', 'chord_octave'}
  elseif params:string('chord_dest') == 'Engine' then
    menus[2] = {'chord_dest', 'chord_div', 'chord_duration', 'chord_octave', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_gain', 'chord_pp_pw'}
  elseif params:string('chord_dest') == 'MIDI' then
    menus[2] = {'chord_dest', 'chord_midi_ch', 'chord_div', 'chord_duration', 'chord_octave', 'chord_midi_velocity'}
  elseif params:string('chord_dest') == 'ii-JF' then
    menus[2] = {'chord_dest', 'chord_div', 'chord_octave', 'chord_jf_amp', 'crow_pullup'}
  end
  
  --arp menus
  if params:string('arp_dest') == 'None' then
    menus[3] = {'arp_dest', 'arp_div', 'arp_octave'}
  elseif params:string('arp_dest') == 'Engine' then
    menus[3] = {'arp_dest', 'arp_div', 'arp_duration', 'arp_octave', 'arp_pp_amp', 'arp_pp_cutoff', 'arp_pp_gain', 'arp_pp_pw'}
  elseif params:string('arp_dest') == 'MIDI' then
    menus[3] = {'arp_dest', 'arp_midi_ch', 'arp_div', 'arp_duration', 'arp_octave', 'arp_midi_velocity'}
  elseif params:string('arp_dest') == 'Crow' then
    menus[3] = {'arp_dest', 'arp_div', 'arp_octave'}
  end
  
    --MIDI menus
  if params:string('midi_dest') == 'None' then
    menus[4] = {'midi_dest', 'midi_octave'}
  elseif params:string('midi_dest') == 'Engine' then
    menus[4] = {'midi_dest', 'midi_duration', 'midi_octave', 'midi_pp_amp', 'midi_pp_cutoff', 'midi_pp_gain', 'midi_pp_pw'}
  elseif params:string('midi_dest') == 'MIDI' then
    if params:get('do_midi_velocity_passthru') == 1 then
      menus[4] = {'midi_dest', 'midi_midi_ch', 'midi_duration', 'midi_octave', 'do_midi_velocity_passthru'}
    else
      menus[4] = {'midi_dest', 'midi_midi_ch', 'midi_duration', 'midi_octave', 'do_midi_velocity_passthru', 'midi_midi_velocity'}
    end
  elseif params:string('midi_dest') == 'Crow' then
    menus[4] = {'midi_dest', 'midi_octave'}
  end
  
    --Crow menus
  if params:string('crow_dest') == 'None' then
    menus[5] = {'crow_dest', 'crow_div', 'crow_octave', 'do_crow_auto_rest'}
  elseif params:string('crow_dest') == 'Engine' then
    menus[5] = {'crow_dest', 'crow_div', 'crow_duration', 'crow_octave', 'do_crow_auto_rest', 'crow_pp_amp', 'crow_pp_cutoff', 'crow_pp_gain', 'crow_pp_pw'}
  elseif params:string('crow_dest') == 'MIDI' then
    menus[5] = {'crow_dest', 'crow_div', 'crow_duration', 'crow_octave', 'do_crow_auto_rest', 'crow_midi_ch', 'crow_midi_velocity'}
  elseif params:string('crow_dest') == 'Crow' then
    menus[5] = {'crow_dest', 'crow_div', 'crow_octave', 'do_crow_auto_rest'}
  end  
  
  --Global menu
  menus[6] = {'clock_source', 'clock_tempo', 'mode', 'transpose', 'clock_midi_out', 'block_repeats'}
end


function crow_pullup()
    crow.ii.pullup(t_f_bool(params:get('crow_pullup')))
    print('crow pullup: ' .. t_f_string(params:get('crow_pullup')))
end

function first_to_upper(str)
    return (str:gsub("^%l", string.upper))
end

function duration_string(index)
  return(durations[index][1])  
end

function duration_int(index)
  return(durations[index][2])  
end

function duration_sec(index)
  return(durations[index][3] * clock.get_beat_sec())  
end

function param_id_to_name(id)
  return(params.params[params.lookup[id]].name)
end

function mode_index_to_name(index)
  return(music.SCALES[index].name)
end
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

function t_f_string(x)
  return(x == 1 and 'True' or 'False')
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

function print_this(x)
  print(x)
end

function timing_clock()
  while true do
    clock.sync(1/64)
    for i = #note_off_buffer, 1, -1 do -- Steps backwards to account for table.remove messing with [i]
      note_off_buffer[i][1] = note_off_buffer[i][1] - 1
      if note_off_buffer[i][1] == 0 then
        out_midi:note_off(note_off_buffer[i][2], 0, note_off_buffer[i][3]) -- note, vel, ch.
        table.remove(note_off_buffer, i)
      end
    end
  end
end
    
function clock.transport.start()
  transport_active = true
  clock.cancel(timing_clock_id or 0) -- Cancel previous timing clock (if any) and...
  timing_clock_id = clock.run(timing_clock) --Start a new timing clock. Not sure about efficiency here.
  sequence_clock_id = clock.run(sequence_clock, global_clock_div) --8 == global clock at 32nd notes
  if params:get('clock_midi_out') ~= 1 then 
    if clock_start_method == 'start' then
      out_midi:start()
    else
      out_midi:continue()
    end
  end
  clock_start_method = 'continue'
  print("Clock "..sequence_clock_id.. " started")
end

function clock.transport.stop()
  print('Transport stopping')
  transport_active = false
  if params:get('clock_midi_out') ~= 1 then 
    out_midi:stop() --Stop vs continue?
  end
  if params:get('clock_source') ~= 1 then -- External clock
    if params:get('do_follow') == 1 then -- When following an external clock, reset arranegement.
      reset_arrangement()
    else
      reset_pattern()
    end
  end
  get_next_chord()
  print('Canceling clock id ' .. sequence_clock_id or 0)
  clock.cancel(sequence_clock_id or 0)
end
   
 function reset_pattern()
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  reset_clock()
  grid_redraw()
  redraw()
end

function reset_arrangement() -- check: how to send a reset out to Crow for external clocking
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  pattern_seq_position = 1
  pattern = pattern_seq[1]
  reset_clock()
  get_next_chord() -- New. Seems OK?
  grid_redraw()
  redraw()
end

function reset_clock()
  clock_step = params:get('chord_div') - 1
  clock_start_method = 'start'
end

 --Clock to control sequence events including chord pre-load, chord/arp sequence, and crow clock out
function sequence_clock(rate)
  while transport_active do
    clock.sync(1/rate)
    clock_step = util.wrap(clock_step + 1, 0, params:get('chord_div') - 1)
    if util.wrap(clock_step + 1, 0, params:get('chord_div') - 1) % params:get('chord_div') == 0 then
      get_next_chord()
    end
    if clock_step % params:get('chord_div') == 0 then
      advance_chord_seq()
      grid_dirty = true
    end
    if clock_step % params:get('arp_div') == 0 then
      advance_arp_seq()
      grid_dirty = true
    end
    if clock_step % params:get('crow_div') == 0 then
      crow.output[3]() --pulse defined in init
    end
    if grid_dirty == true then
      grid_redraw()
      grid_dirty = false
    end
  end
end


function advance_chord_seq()
  chord_seq_retrig = true -- indicates when we're on a new chord seq step for auto-rest logic
  
  -- If Arranger is enabled and we're on/after the last step in the pattern
  if params:get("do_follow") == 1 and chord_seq_position >= pattern_length[pattern] then
    
    --Check if it's the last pattern in the arrangement. Doesn't trigger if last pattern is turned off midway through. Maybe fix this.
    if pattern_seq_position == pattern_seq_length and params:string('playback') == 'One-shot' then
      arrangement_reset = true
    end
    
    -- Update the arranger sequence position
    pattern_seq_position = util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)
    pattern = pattern_seq[pattern_seq_position]
    
    -- Prevents arp from extending beyond chord pattern length. Fix: add check to Arp loop (set chord div to 16)
    pattern_seq_retrig = true 
  end
  
  if arrangement_reset == true and params:string('playback') == 'One-shot' then
    print('arrangement ended')
    clock.transport.stop()
    arrangement_reset = false
    -- break --  To-do: Need to check if this was preventing the following from running...
  end

  if chord_seq_position >= pattern_length[pattern] or pattern_seq_retrig then
    if pattern_queue then
    -- if pattern_queue ~= pattern then
      pattern = pattern_queue
      pattern_queue = false
      -- pattern_queue = pattern
    end
    chord_seq_position = 1
    pattern_seq_retrig = false
  else  
    chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
  end
  if chord_seq[pattern][chord_seq_position].c > 0 then
    play_chord(params:string('chord_dest'), params:get('chord_midi_ch'))
  end
  redraw() -- To update Arrange mini chart
end


-- Pre-load upcoming chord to address race condition.
function get_next_chord()
  local temp_pattern = pattern
  local temp_chord_seq_position = chord_seq_position
  local temp_pattern_seq_retrig = false
  if params:get("do_follow") == 1 and temp_chord_seq_position >= pattern_length[temp_pattern] then 
    temp_pattern = pattern_seq[util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)]
    temp_pattern_seq_retrig = true
  end
  if temp_chord_seq_position >= pattern_length[temp_pattern] or temp_pattern_seq_retrig then
    if pattern_queue then
    -- if pattern_queue ~= pattern then
      temp_pattern = pattern_queue
    end
    temp_chord_seq_position = 1
    temp_pattern_seq_retrig = false
  else  
    temp_chord_seq_position = util.wrap(temp_chord_seq_position + 1, 1, pattern_length[temp_pattern])
  end
  if chord_seq[temp_pattern][temp_chord_seq_position].c > 0 then
    chord = music.generate_chord_scale_degree(chord_seq[temp_pattern][temp_chord_seq_position].o * 12, params:get('mode'), chord_seq[temp_pattern][temp_chord_seq_position].c, false)
  end
end


function advance_arp_seq()
  if arp_seq_position > arp_pattern_length[arp_pattern] or pattern_seq_retrig == true then -- Validate pattern_seq_retrig addition
    arp_seq_position = 1
  else  
    arp_seq_position = util.wrap(arp_seq_position + 1, 1, arp_pattern_length[arp_pattern])
  end
  if arp_seq[arp_pattern][arp_seq_position] > 0 then
    arp_note_num =  arp_seq[arp_pattern][arp_seq_position]
    harmonizer(
      'arp',
      params:string('arp_dest'), 
      arp_note_num,
      params:get('arp_octave'),
      params:get('arp_midi_ch'), 
      params:get('arp_midi_velocity'), 
      params:get('arp_pp_amp'), 
      params:get('arp_pp_cutoff'), 
      params:get('arp_pp_gain'), 
      params:get('arp_pp_pw'), 
      duration_sec(params:get('arp_duration')), --release
      duration_int(params:get('arp_duration')))
  end
end


function play_chord(destination, channel)
  chord = music.generate_chord_scale_degree(chord_seq[pattern][chord_seq_position].o * 12, params:get('mode'), chord_seq[pattern][chord_seq_position].c, false)
  chord_duration_int = duration_int(params:get('chord_duration'))
  if destination == 'Engine' then
    for i=1,#chord do
      engine.amp(params:get('chord_pp_amp') / 100)
      engine.cutoff(params:get('chord_pp_cutoff'))
      engine.release(duration_sec(params:get('chord_duration')))
      engine.gain(params:get('chord_pp_gain') / 100)
      engine.pw(params:get('chord_pp_pw') / 100)
      engine.hz(music.note_num_to_freq(chord[i] + params:get('transpose') + 48 + (params:get('chord_octave') * 12)))
    end
  elseif destination == 'MIDI' then
    chord_note_off_insert = true
    for i=1,#chord do
      chord_note = chord[i] + params:get('transpose') + 48 + (params:get('chord_octave') * 12)
      out_midi:note_on(chord_note, params:get('chord_midi_velocity'), channel) 
      for i = 1, #note_off_buffer do
        if note_off_buffer[i][2] == chord_note and note_off_buffer[i][3] == channel then
          note_off_buffer[i][1] =  chord_duration_int
          chord_note_off_insert = false
        end
      end
      if chord_note_off_insert == true then
        table.insert(note_off_buffer, {chord_duration_int, chord_note, channel})
      end
    end
  elseif destination == 'ii-JF' then
    for i=1,#chord do
      crow.ii.jf.play_note((chord[i] + params:get('transpose') + (params:get('chord_octave') * 12))/12, params:get('chord_jf_amp')/10)
    end
  end
end

--Update with if params:get('block_repeats') == 1 then
function harmonizer(source, destination, note_num, octave, channel, velocity, amp, cutoff, gain, pw, release,duration)
  quantized_note = chord[util.wrap(note_num, 1, #chord)]
  harmonizer_octave = math.floor((note_num - 1) / #chord)
  harmonizer_note = quantized_note + ((harmonizer_octave + octave) * 12) + params:get('transpose')   
  -- print(source .. ' ' .. note_num.. "  " .. quantized_note.."  "..harmonizer_octave)
  if 
  source ~= 'crow'   -- Logic for auto-rest
  or chord_seq_retrig == true 
  or params:get('do_crow_auto_rest') == 0 
  or (params:get('do_crow_auto_rest') == 1 and (prev_harmonizer_note ~= harmonizer_note)) then
      if destination == 'Engine' then
        engine.amp(amp / 100)
        engine.cutoff(cutoff)
        engine.release(release)
        engine.gain(gain / 100)
        engine.pw(pw / 100)
        engine.hz(music.note_num_to_freq(harmonizer_note + 48))
      elseif destination == 'Crow' then
        crow.output[1].volts = (harmonizer_note) / 12
        crow.output[2].slew = 0
        crow.output[2].volts = 8
        crow.output[2].slew = 0.005
        crow.output[2].volts = 0
      elseif destination == 'MIDI' then
        harmonizer_note_off_insert = true
        out_midi:note_on((harmonizer_note + 48), velocity, channel)
        for i = 1, #note_off_buffer do
          if note_off_buffer[i][2] == harmonizer_note + 48 and note_off_buffer[i][3] == channel then
            note_off_buffer[i][1] = duration
            harmonizer_note_off_insert = false
          end
        end
        if harmonizer_note_off_insert == true then
          table.insert(note_off_buffer, {duration, harmonizer_note + 48, channel})
        end
      end
    end
  if source == 'crow' then
    if chord_seq_trig == true then -- Check if this is used for anything other than auto-rest
      chord_seq_retrig = false
    end
    prev_harmonizer_note = harmonizer_note
  end
end

function grid_redraw()
  g:all(0)
  for i = 6,8 do
    g:led(16,i,4)
  end
  if view_name == 'Arrange' then
    g:led(16,6,15)
    for x = 1,16 do
      for y = 1,4 do
        g:led(x,y, x == pattern_seq_position and 7 or 3)
        if y == pattern_seq[x] then
          g:led(x, y, 15)
        end
      end
    end
  elseif view_name == 'Chord' then
    if params:get('do_follow') == 1 then
      next_pattern_indicator = pattern_seq[util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)]
    else
      next_pattern_indicator = pattern_queue or pattern
    end
  for i = 1,4 do
      g:led(16, i, i == next_pattern_indicator and 7 or 3)
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
  elseif view_name == 'Arp' then
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
      view_index = y - 5
      view_name = views[view_index]
    --ARRANGER KEYS
    elseif view_name == 'Arrange' then
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
      end
      if transport_active == false then -- Update chord for when play starts
        get_next_chord()
      end
    --CHORD KEYS
    elseif view_name == 'Chord' then
      if x < 15 then
        if x == chord_seq[pattern][y].x then
          chord_seq[pattern][y].x = 0
          chord_seq[pattern][y].c = 0
          chord_seq[pattern][y].o = 0
        else
          chord_seq[pattern][y].x = x --raw key x coordinate
          chord_seq[pattern][y].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
          chord_seq[pattern][y].o = math.floor(x / 8) --octave
          grid_dirty = true
        end
      elseif x == 15 then
        pattern_length[pattern] = y
      elseif x == 16 and y <5 then  --Key DOWN events for pattern switcher. Key UP events farther down in function.
        pattern_key_count = pattern_key_count + 1
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
    elseif view_name == 'Arp' then
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
  redraw()
  grid_redraw()
  elseif view_name == 'Chord' and x == 16 and y <5 then --z == 0, pattern key UP
    pattern_key_count = pattern_key_count - 1
    if pattern_key_count == 0 and pattern_copy_performed == false then
      if y == pattern then
        print('a - manual reset of current pattern')
        params:set("do_follow", 0)
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
          params:set("do_follow", 0)
        end
      end
    end
    redraw()
    grid_redraw()
  end
  if pattern_key_count == 0 then
    pattern_copy_performed = false
  end
end

function key(n,z)
  if z == 1 then
    if n == 2 then
      if params:get('clock_source') == 1 then --Internal clock only
        if transport_active then
          clock.transport.stop()
        else
          clock.transport.start()
        end
      end
    elseif n == 3 then
      if params:get('do_follow') == 1 then  -- If follow is on, turn off
        params:set('do_follow', 0)
      elseif transport_active == true then  -- If follow is off but we're playing, pick up arrangement
        print('Resuming arrangement on next pattern advance')
        params:set('do_follow', 1)
      else 
        print('Transport stopped; resetting arrangement')
        params:set('do_follow', 1)  -- If follow is off and transport is stopped, reset arrangement
        reset_arrangement()
        -- pattern_queue = pattern 
      end
      redraw()
    end
  end
end

function enc(n,d)
  if n == 1 then
    menu_index = 1
    page_index = util.clamp(page_index + d, 1, #pages)
    page_name = pages[page_index]
    selected_menu = menus[page_index][menu_index]
  elseif n == 2 then
    menu_index = util.clamp(menu_index + d, 1, #menus[page_index])
    selected_menu = menus[page_index][menu_index]
  else
    params:delta(selected_menu, d)
  end
  redraw()
end

function crow_trigger(s) --Trigger in used to sample voltage from Crow IN 1
    state = s
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
end

function sample_crow(v)
  volts = v
  crow_note_num =  round(volts * 12,0) + 1
  harmonizer(
    'crow',
    params:string('crow_dest'), 
    crow_note_num, 
    params:get('crow_octave'),
    params:get('crow_midi_ch'), 
    params:get('crow_midi_velocity'), 
    params:get('crow_pp_amp'), 
    params:get('crow_pp_cutoff'), 
    params:get('crow_pp_gain'), 
    params:get('crow_pp_pw'), 
    duration_sec(params:get('crow_duration')), --release
    duration_int(params:get('crow_duration')))
  chord_seq_retrig = false -- Check this to make sure it's working correct
end

in_midi.event = function(data)
  local d = midi.to_msg(data)
  -- if params:get('clock_source') == 2 and d.type == 'stop' then -- placeholder for determining source of transport.stop
  if d.type == "note_on" then
    if params:get('do_midi_velocity_passthru') == 1 then  --Clunky
      harmonizer(
        'midi',
        params:string('midi_dest'), 
        d.note - 35,  
        params:get('midi_octave'),
        params:get('midi_midi_ch'), 
        d.vel,
        params:get('midi_pp_amp'), 
        params:get('midi_pp_cutoff'), 
        params:get('midi_pp_gain'), 
        params:get('midi_pp_pw'), 
        duration_sec(params:get('midi_duration')), --release
        duration_int(params:get('midi_duration')))
    else
      harmonizer(
        'midi',
        params:string('midi_dest'), 
        d.note - 35, 
        params:get('midi_octave'),
        params:get('midi_midi_ch'), 
        params:get('midi_midi_velocity'),   
        params:get('midi_pp_amp'), 
        params:get('midi_pp_cutoff'), 
        params:get('midi_pp_gain'), 
        params:get('midi_pp_pw'), 
        duration_sec(params:get('midi_duration')), --release
        duration_int(params:get('midi_duration')))
      end
  end
end
  
function arrangement_time()
  arrangement_steps = 0
  for i = 1, pattern_seq_length do
    arrangement_steps = arrangement_steps + pattern_length[pattern_seq[i]]
  end
  arrangement_time_s = arrangement_steps * 60 / params:get('clock_tempo') / global_clock_div * params:get('chord_div')
  hours = string.format("%02.f", math.floor(arrangement_time_s/3600));
  mins = string.format("%02.f", math.floor(arrangement_time_s/60 - (hours*60)));
  secs = string.format("%02.f", math.floor(arrangement_time_s - hours*3600 - mins *60));
  arrangement_time_clock = hours..":"..mins..":"..secs
  return(arrangement_time_clock)
end  

-- WIP to turn arrangement timer into a countdown clock USE util.s_to_hms (s)
-- function arrangement_time()
--   steps_remaining_in_pattern = math.min(pattern_length[pattern_seq_position], pattern_length[pattern_seq_position] - chord_seq_position + 1)
--   -- print(steps_remaining_in_pattern)
--   arrangement_steps = 0
--   if pattern_seq_length - pattern_seq_position > 0 then
--     for i = math.min(pattern_seq_position + 1, pattern_seq_length), pattern_seq_length do  --steps after the current pattern
--       arrangement_steps = arrangement_steps + pattern_length[pattern_seq[i]]
--     end
--   end
--   arrangement_steps = arrangement_steps + steps_remaining_in_pattern
--   -- print(arrangement_steps)
--   -- print('chord_seq_length[pattern_seq_position]')
--   arrangement_time_s = arrangement_steps * 60 / params:get('clock_tempo') / global_clock_div * params:get('chord_div')
--   hours = string.format("%02.f", math.floor(arrangement_time_s/3600));
--   mins = string.format("%02.f", math.floor(arrangement_time_s/60 - (hours*60)));
--   secs = string.format("%02.f", math.floor(arrangement_time_s - hours*3600 - mins *60));
--   arrangement_time_clock = hours..":"..mins..":"..secs
--   return(arrangement_time_clock)
-- end  

--This needs some work and will get off if the menu is too long
function scroll_offset(index, total, in_view ,height) --index of list, count of items in list, #viewable, line height
  if total > in_view then
    return(math.ceil(((index - 1) * (total - in_view) * height / total))) --math.ceil might be necessary if some options are cut off
  else return(0)
  end
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.level(7)
  screen.move(36,0)
  screen.line_rel(0,64)
  screen.stroke()
  for i = 1,#pages do
    screen.move(0,i*10 - 1)
    screen.level(page_name == pages[i] and 15 or 3)
    screen.text(pages[i])
  end
  
  --menu and scroll stuff
  local menu_offset = scroll_offset(menu_index,#menus[page_index], 6, 10)
  line = 1
  for i = 1,#menus[page_index] do
    screen.move(40, line*10 - 1 - menu_offset)
    screen.level(menu_index == i and 15 or 3)
    screen.text(first_to_upper(param_id_to_name(menus[page_index][i])) .. ': ' .. params:string(menus[page_index][i]))
    line = line + 1
  end

  -- Draw the sequence and add timer for Arrange
  if page_name == 'Arrange' then
    screen.move(40,50)
    screen.level(3)
    screen.text('Time: ' .. arrangement_time())
    -- All the following needs to be revisited after getting pattern switching figured out. Also use s_to_hms (s)
    local rect_x = 39
    -- local rect_gap_adj = 0
    for i = params:get('do_follow') == 1 and pattern_seq_position or 1, pattern_seq_length do
      screen.level(15)
      elapsed = params:get('do_follow') == 1 and (i == pattern_seq_position and chord_seq_position or 0) or 0 --recheck if this is needed when not following.
      rect_w = pattern_length[pattern_seq[i]] - elapsed
      rect_h = pattern_seq[i]
      rect_gap_adj = params:get('do_follow') == 1 and (pattern_seq_position - 1) or 0 --recheck if this is needed when not following
      screen.rect(rect_x + i - rect_gap_adj, 60, rect_w, rect_h)
      screen.fill()
      rect_x = rect_x + rect_w
    end
  end
  --Draw glyphs
  if params:get('do_follow') == 1 then
  local x_offset = 123
  local y_offset = 0
  screen.level(15)
    if params:get('playback') == 1 then
    for i = 1, #glyphs[1] do
      screen.pixel(glyphs[1][i][1] + x_offset, glyphs[1][i][2] + y_offset)
    end
  else 
    for i = 1, #glyphs[2] do
      screen.pixel(glyphs[2][i][1] + x_offset, glyphs[2][i][2] + y_offset)
    end
  end
  screen.fill(15)
  end
  screen.update()
end
