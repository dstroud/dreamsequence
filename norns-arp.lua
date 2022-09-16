-- Bento
--
-- KEY 1: start/stop
-- ENC 1: main menu
--
-- ENC 2: sub menu
-- ENC 3: edit value 
--
-- Crow IN 1: voltage to sample
-- Crow IN 2: trigger
-- Crow OUT 1: clock
-- Crow OUT 2: assignable
-- Crow OUT 3: trigger out
-- Crow OUT 4: v/oct out


g = grid.connect()
engine.name = "PolyPerc"
music = require 'musicutil'
-- UI = require "ui"

in_midi = midi.connect(1)
chord_out_midi = midi.connect(1)
harmonizer_out_midi = midi.connect(1)

function init()
  
--Global params
params:add_separator ('Global')
params:add_number("transpose","Transpose",-24, 24, 0)
-- params:add_number("mode","Mode",1 , 9, 1)
params:add{
  type = 'number',
  id = 'mode',
  name = 'Mode',
  min = 1,
  max = 9,
  default = 1,
  formatter = function(param) return mode_index_to_name(param:get()) end,
  }


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
  action = function() reset_arrangement() end, function() grid_redraw() end
  }

--Chord params
params:add_separator ('Chord')
params:add_number('chord_div', 'Division', 4, 128, 32) -- most useful {4,8,12,16,24,32,65,96,128,192,256
params:add_option("chord_dest", "Destination", {'None',"Engine", 'MIDI'},2)
  params:set_action("chord_dest",function() submenu_update() end)
params:add{
  type = 'number',
  id = 'chord_pp_amp',
  name = 'Amp.',
  min = 0,
  max = 100,
  default = 80,
  formatter = function(param) return percent(param:get()) end,
  }
params:add_control("chord_pp_cutoff","Cutoff",controlspec.new(50,5000,'exp',0,800,'hz'))
params:add_number("chord_pp_gain","Gain",0, 400, 200)
params:add_number("chord_pp_pw","Pulse width",1, 99, 50)
params:add_number("chord_pp_release","Release",1, 10, 5)
params:add_number('chord_midi_velocity','Velocity',0, 127, 127)
params:add_number('chord_midi_ch','Channel',1, 16, 1)
-- params:add_number("chord_midi_cc1","MIDI Mod",0, 127, 0)

--Arp params
params:add_separator ('Arp')
params:add_number('arp_div', 'Division', 1, 32, 4) --most useful {1,2,4,8,16,24,32}
params:add_option("arp_dest", "Destination", {'None',"Engine","Crow", 'MIDI'},2)
params:add_number("arp_pp_release","Release",1, 10, 5)
params:add_number('arp_midi_ch','Channel',1, 16, 2)
params:add_number('arp_midi_vel','Velocity',0, 127, 127)

--Crow params
params:add_separator ('Crow')
params:add_number('crow_div', 'Clock out div.', 1, 32, 8) --most useful TBD
params:add_option("crow_dest", "Destination", {'None',"Engine","Crow",'MIDI'},2)
params:add{
  type = 'number',
  id = 'do_crow_auto_rest',
  name = 'Auto-rest',
  min = 0,
  max = 1,
  default = 0,
  formatter = function(param) return t_f_string(param:get()) end,
  }
params:add_number('crow_midi_ch','Channel',1, 16, 2)
params:add_number('crow_midi_vel','Velocity',0, 127, 127)

--MIDI params
params:add_separator ('MIDI')
params:add_option("midi_dest", "Destination", {'None',"Engine","Crow", 'MIDI'},2)
params:add_number('midi_midi_ch','Channel',1, 16, 2)
params:add_number('midi_midi_vel','Velocity',0, 127, 127)
params:add{
  type = 'number',
  id = 'do_midi_vel_passthru',
  name = 'Velocity Passthru',
  min = 0,
  max = 1,
  default = 0,
  formatter = function(param) return t_f_string(param:get()) end,
  }

-- params:bang()
  
  -- mode = math.random(1,9)
-- scale = music.generate_scale_of_length(60,music.SCALES[params:get('mode')].name,8)
prev_harmonizer_note = -999
chord_seq_retrig = true

  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  crow.input[2].mode("change",2,0.1,"rising") --might want to use as a gate with "both"
  crow.input[2].change = crow_trigger
  grid_dirty = true
  views = {'Arrange','Chord','Arp'} -- grid "views" are decoupled from screen "pages"
  view_index = 2
  view_name = views[view_index]
  pages = {'Arrange','Chord','Arp','Crow','MIDI','Global'}
  page_index = 6
  page_name = pages[page_index]
  -- submenus = {
  --             {'Follow'}, -- Arrange
  --             {'Division', 'Destination', 'Amp', 'Cutoff', 'Pulse width', 'Release'}, -- Chord
  --             {'Division', 'Destination'}, -- Arp
  --             {'Division', 'Destination', 'Auto-rest'}, -- Crow
  --             {'Destination'}, -- MIDI
  --             {'Tempo','Scale','Transpose'} -- Global
  --             }
  
    submenus = {
              {'do_follow'}, -- Arrange
              {'chord_div', 'chord_dest', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_gain', 'chord_pp_pw', 'chord_pp_release'}, -- Chord
              {'arp_div', 'arp_dest'}, -- Arp
              {'crow_div', 'crow_dest', 'do_crow_auto_rest'}, -- Crow
              {'midi_dest'}, -- MIDI
              {'clock_tempo','mode','transpose'} -- Global
              }
              
  submenu_index = 1
  selected_menu = submenus[page_index][submenu_index]
  transport_active = false
  pattern_length = {4,4,4,4} -- loop length for each of the 4 patterns. rename to chord_seq_length prob
  pattern = 1
  pattern_queue = false
  -- pattern_preview = false
  pattern_seq = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  pattern_seq_position = 1
  pattern_seq_length = 1 
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
  chord = {music.generate_chord_scale_degree(chord_seq[pattern][1].o * 12, params:get('mode'), chord_seq[pattern][1].c, false)}
  chord_hanging_notes = {}  
  harmonizer_hanging_notes = {{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}}
  arp_seq = {{0,0,0,0,0,0,0,0},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8}
            } -- sub table in case we want multiple arp patterns
  arp_pattern_length = {8,8,8,8}
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
  -- engine.release(5)
  reset_clock() -- will turn over to step 0 on first loop
  -- clock.run(grid_redraw_clock) --Not used currently
  grid_redraw()

end

-- Dynamic chord submenus
function submenu_update()
  if params:string('chord_dest') == 'None' then
    submenus[2] = {'chord_div', 'chord_dest'}
  elseif params:string('chord_dest') == 'Engine' then
    submenus[2] = {'chord_div', 'chord_dest', 'chord_pp_amp', 'chord_pp_cutoff', 'chord_pp_gain', 'chord_pp_pw', 'chord_pp_release'}
  elseif params:string('chord_dest') == 'MIDI' then
    submenus[2] = {'chord_div', 'chord_dest', 'chord_midi_velocity'}
  end
end

function first_to_upper(str)
    return (str:gsub("^%l", string.upper))
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

function clock.transport.start()
  --TBD if we want to reset to beginning of sequence/arps with reset_clock()
  transport_active = true
  clock_loop_id = clock.run(loop, global_clock_div) --8 == global clock at 32nd notes
  print("Clock "..clock_loop_id.. " called")
end

function clock.transport.stop()
  transport_active = false
  clock.cancel(clock_loop_id)
  if params:get('do_follow') == 1 then
    reset_arrangement()
  end
  for i = 1,16 do
    stop_harmonizer(i)
  end
  stop_chord()
end
   
function reset_arrangement() -- check: how to send a reset out to Crow for external clocking
  print('resetting arrangement')
  pattern_queue = false
  arp_seq_position = 0
  chord_seq_position = 0
  pattern_seq_position = 1
  pattern = pattern_seq[1]
  reset_clock()
  grid_redraw()
  redraw()
end

function reset_clock()
  clock_step = params:get('chord_div') - 1    
end

function loop(rate) --using one clock to control all sequence events
  while transport_active do
    clock.sync(1/rate)
    clock_step = util.wrap(clock_step + 1, 0, params:get('chord_div') - 1) -- 0-indexed counter for checking when to fire events
    
    --chord clock
    if clock_step % params:get('chord_div') == 0 then
      chord_seq_retrig = true -- indicates when we're on a new chord seq step for arp filtering
      if params:get("do_follow") == 1 and chord_seq_position >= pattern_length[pattern] then    
        pattern_seq_position = util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)
        pattern = pattern_seq[pattern_seq_position]
        pattern_seq_retrig = true -- prevents arp from extending beyond chord pattern length
      end
      if chord_seq_position >= pattern_length[pattern] or pattern_seq_retrig then
        -- print('pattern retrig')
        if pattern_queue then
          pattern = pattern_queue
          pattern_queue = false
        end
        chord_seq_position = 1
        pattern_seq_retrig = false
      else  
        chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
      end
      if chord_seq[pattern][chord_seq_position].c > 0 then
        play_chord(params:string('chord_dest'))
      end
      grid_redraw() -- move
      redraw() -- to update Arrange mini chart. Worth it?
    end
    
    -- arp clock
      if clock_step % params:get('arp_div') == 0 then
        if arp_seq_position > arp_pattern_length[arp_pattern] then 
          arp_seq_position = 1
        else  
          arp_seq_position = util.wrap(arp_seq_position + 1, 1, arp_pattern_length[arp_pattern])
        end
        if arp_seq[arp_pattern][arp_seq_position] > 0 then
          arp_note_num =  arp_seq[arp_pattern][arp_seq_position]
          harmonizer(params:string('arp_dest'), arp_note_num, params:get('arp_midi_ch'), params:get('arp_midi_vel'))
        end
        grid_redraw() --move
      end

    --crow clock out
    if clock_step % params:get('crow_div') == 0 then
      crow.output[1].slew = 0
      crow.output[1].volts = 8
      crow.output[1].slew = 0.005 --WAG here
      crow.output[1].volts = 0  
    end
    -- end
  end
end

function play_chord(destination)
  stop_chord()
  chord = {music.generate_chord_scale_degree(chord_seq[pattern][chord_seq_position].o * 12, params:get('mode'), chord_seq[pattern][chord_seq_position].c, false)}
  if destination == 'Engine' then
    for i=1,#chord[1] do -- only one chord is stored but it's in index 1. Kinda weird IDK.
      engine.amp(params:get('chord_pp_amp') / 100)
      engine.cutoff(params:get('chord_pp_cutoff'))
      engine.release(params:get('chord_pp_release'))
      -- engine.gain(params:get('chord_pp_gain') / 100)
      engine.pw(params:get('chord_pp_pw') / 100)
      engine.hz(music.note_num_to_freq(chord[1][i] + params:get('transpose')+ 48 )) -- same as above
    end
  elseif destination == 'MIDI' then
    for i=1,#chord[1] do -- only one chord is stored but it's in index 1. Kinda weird IDK.
      chord_out_midi:note_on((chord[1][i] + params:get('transpose')+ 48 ),params:get('chord_midi_velocity')) 
      chord_hanging_notes[i] = {chord[1][i] + params:get('transpose')+ 48, params:get('chord_midi_ch')} --note index, note, channel (simplified)
    end
  end
end

function stop_chord()
  for i = 1, #chord_hanging_notes do          --Turn off any hanging chord notes
    chord_out_midi:note_off(chord_hanging_notes[i][1], 0, chord_hanging_notes[i][2])
  end
end

function harmonizer(destination, note_num, channel, velocity)
  -- print('Harmonizer: ' ..destination .. ' '.. note_num .. ' ' .. channel .. ' ' .. velocity)
  prev_harmonizer_note = harmonizer_note
  harmonizer_note = chord[1][util.wrap(note_num, 1, #chord[1])]
  harmonizer_octave = math.floor((note_num - 1) / #chord[1],0)
  -- print(arp_note_num.. "  " .. harmonizer_note.."  "..harmonizer_octave)
  if chord_seq_retrig == true or params:get('do_crow_auto_rest') == 0 or (params:get('do_crow_auto_rest') == 1 and (prev_harmonizer_note ~= harmonizer_note)) then
    if destination == 'Engine' then
      engine.release(params:get('arp_pp_release')) -- Fix: test only. Needs to be passed from calling function
      engine.hz(music.note_num_to_freq(harmonizer_note + (harmonizer_octave * 12) + params:get('transpose') + 48))
    elseif destination == 'Crow' then
      crow.output[4].volts = (harmonizer_note + (harmonizer_octave * 12) + params:get('transpose')) / 12
      crow.output[3].slew = 0
      crow.output[3].volts = 8
      crow.output[3].slew = 0.005
      crow.output[3].volts = 0
    elseif destination == 'MIDI' then
      stop_harmonizer(channel)
      harmonizer_out_midi:note_on((harmonizer_note + (harmonizer_octave * 12) + params:get('transpose') + 48), velocity, channel)
      harmonizer_hanging_notes[channel] = {(harmonizer_note + (harmonizer_octave * 12) + params:get('transpose') + 48)}
    end
  end
  chord_seq_retrig = false -- Fix: Needs to be fired by calling function depending on where enabled
end

function stop_harmonizer(channel) --midi
  -- for i = #harmonizer_hanging_notes[channel], #harmonizer_hanging_notes[channel] do 
  if #harmonizer_hanging_notes[channel] then
    harmonizer_out_midi:note_off(harmonizer_hanging_notes[channel][1], 0, channel) -- note, vel, ch. Not sure if there is a reason we need [i] index
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
      g:led(16, i, i == next_pattern_indicator and 7 or 3) --Should add something to highlight when pattern_preview is ~= nil
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
      
    --arrange keys
    elseif view_name == 'Arrange' then
      if y < 5 then
        if y == pattern_seq[x] and x > 1 then 
          pattern_seq[x] = 0
        else pattern_seq[x] = y  
        end
        for i = 1,17 do
          if pattern_seq[i] == 0  or i == 17 then
            pattern_seq_length = i - 1
            -- print("pattern_seq_length "..pattern_seq_length)
            break
          end
        end 
      end
    
    --chord keys
    -- print('checking for Chord keys')
    elseif view_name == 'Chord' then
      if x < 15 then
        if x == chord_seq[pattern][y].x then
          chord_seq[pattern][y].x = 0 -- Only need to set one of these TBH
          chord_seq[pattern][y].c = 0 -- Only need to set one of these TBH
          chord_seq[pattern][y].o = 0 -- Only need to set one of these TBH
        else
          chord_seq[pattern][y].x = x --raw
          chord_seq[pattern][y].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
          chord_seq[pattern][y].o = math.floor(x / 8) --octave
          grid_dirty = true
        end
      elseif x == 15 then
        pattern_length[pattern] = y
      elseif x == 16 and y <5 then  --Pattern switcher
        -- pattern_preview = y --not implemented yet
        -- print('previewing pattern '.. pattern_preview)
      end

    -- arp keys
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
  elseif view_name == 'Chord' and x == 16 and y <5 then --z == 0, pattern key released
    -- pattern_preview = false
    params:set("do_follow", 0) -- Check: Maybe allow follow to stay on if y == pattern or if transport is stopped?
    if y == pattern_queue then
      pattern = y
      arp_seq_position = 0
      chord_seq_position = 0
      reset_clock()
    else
      pattern_queue = y
    end
    redraw()
    grid_redraw()
  end
end

function key(n,z)
  if n == 1 and z == 0 then -- Transport control operates on key up because of the K1 delay
    if transport_active then
      print("stop key")
      clock.transport.stop()
    else
      print("start key")
      clock.transport.start()
    end
  end
end

function enc(n,d)
  if n == 1 then
    submenu_index = 1
    page_index = util.clamp(page_index + d, 1, #pages)
    page_name = pages[page_index]
    selected_menu = submenus[page_index][submenu_index]
  elseif n == 2 then
    submenu_index = util.clamp(submenu_index + d, 1, #submenus[page_index])
    selected_menu = submenus[page_index][submenu_index]
  else
    params:delta(selected_menu, d)
  end
  redraw()
end

function crow_trigger(s) --Trigger in used to sample voltage from Crow IN 1
    state = s
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
    -- print('crow trigger in')
end

function sample_crow(v)
  volts = v
  crow_note_num =  round(volts * 12,0) + 1
  harmonizer(params:string('crow_dest'), crow_note_num, params:get('crow_midi_ch'), params:get('crow_midi_vel'))
  chord_seq_retrig = false -- Check this to make sure it's working correct
end

in_midi.event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    if params:get('do_midi_vel_passthru') == 1 then                                               -- Fix: velocity to engine.amp
      harmonizer(params:string('midi_dest'), d.note - 36, params:get('midi_midi_ch'), d.vel)
      -- print(d.vel)
    else
      harmonizer(params:string('midi_dest'), d.note - 36, params:get('midi_midi_ch'), params:get('midi_midi_vel'))
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

-- WIP to turn arrangement timer into a countdown clock
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

function scroll_offset(index, total, in_view ,height) --index of list, count of items in list, #viewable, line height
  if total > in_view then
    return((index - 1) * (total - in_view) * height / total) --math.ceil might be necessary if some options are cut off
  else return(0)
  end
end

function redraw()
  screen.clear()
  screen.level(7)
  screen.move(36,0)
  screen.line_rel(0,64)
  screen.stroke()
  for i = 1,#pages do
    screen.move(0,i*10)
    screen.level(page_name == pages[i] and 15 or 3)
    screen.text(pages[i])
  end
  --menu and scroll stuff
  
  local menu_offset = scroll_offset(submenu_index,#submenus[page_index], 6, 10)
  
  line = 1
  for i = 1,#submenus[page_index] do
    screen.move(40, line*10 - menu_offset)
    screen.level(submenu_index == i and 15 or 3)
    screen.text(first_to_upper(param_id_to_name(submenus[page_index][i])) .. ': ' .. params:string(submenus[page_index][i]))
    line = line + 1
  end

  -- Draw the sequence and add timer for Arrange
  if page_name == 'Arrange' then
    screen.move(40,50)
    screen.level(3)
    screen.text('Time: ' .. arrangement_time())
    -- All the following needs to be revisited after getting pattern switching figured out
    local rect_x = 39
    -- local rect_gap_adj = 0
    for i = params:get('do_follow') == 1 and pattern_seq_position or 1, pattern_seq_length do
      screen.level(15)
      elapsed = params:get('do_follow') == 1 and (i == pattern_seq_position and chord_seq_position or 0) or 0 --recheck if this is needed when not following
      rect_w = pattern_length[pattern_seq[i]] - elapsed
      rect_h = pattern_seq[i]
      rect_gap_adj = params:get('do_follow') == 1 and (pattern_seq_position - 1) or 0 --recheck if this is needed when not following
      screen.rect(rect_x + i - rect_gap_adj, 60, rect_w, rect_h)
      screen.fill()
      rect_x = rect_x + rect_w
    end
  end
  screen.update()
end






