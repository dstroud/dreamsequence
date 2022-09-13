-- norns-arp
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
UI = require "ui"

-- params:add_option("do_follow", "Follow", {"False","True"},True) -- Whether arranger is enabled
-- params:set_action("do_follow", print(params:string('do_follow')))

params:add{
  type = 'number',
  id = 'do_follow',
  name = 'do_follow',
  min = 0,
  max = 1,
  default = 1,
  formatter = function(param) return t_f_string(param:get()) end,
  action = function() reset_arrangement() end, function() grid_redraw() end
  -- action = function() grid_redraw() end
  }

params:add_option("do_crow_auto_rest", "Crow Auto-rest", {"False","True"}, 1) -- Whether repeat notes are suppressed

params:add_number("transpose","Transpose",-24, 24, 0)
params:add_number('arp_div', 'Arp Division', 1, 32, 4) --most useful {1,2,4,8,16,24,32}
params:add_number('chord_div', 'Chord Division', 4, 128, 32) -- most useful {4,8,12,16,24,32,65,96,128,192,256
params:add_number('crow_div', 'Crow Division', 1, 32, 8) --most useful TBD

params:add_option("chord_dest", "Chord dest.", {"Engine", 'MIDI'},1)
params:add_option("arp_dest", "Arp dest.", {"Engine","Crow", 'MIDI'},1)
params:add_option("crow_dest", "Crow dest.", {"Engine","Crow",'MIDI'},1)
params:add_option("midi_dest", "Midi dest.", {"Engine","Crow", 'MIDI'},1)

-- params:add_number('midi_out_a', 'MIDI Out A', 1, 16, 1)
-- params:add_number('midi_out_b', 'MIDI Out B', 1, 16, 2)
-- params:add_number('midi_out_c', 'MIDI Out C', 1, 16, 3)


mode = math.random(1,9)
scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
-- harmo_filter = 0 -- 1 filters out duplicate notes, 0 allows 
prev_harmonizer_note = -999
chord_seq_retrig = true

in_midi = midi.connect(1)
out_midi = midi.connect(1) -- Should set up params for several USB options or virtual?

function init()
  -- out_midi = midi.connect(1) -- Should set up params for several USB options or virtual?
  -- m = midi.connect() -- if no argument is provided, we default to port 1
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
  submenus = {
              {'Follow'}, -- Arrange
              {'Division', 'Destination'}, -- Chord
              {'Division', 'Destination'}, -- Arp
              {'Division', 'Destination', 'Auto-rest'}, -- Crow
              {'Destination'}, -- MIDI
              {'Tempo','Scale','Transpose'} -- Global
              }
  -- submenu = 1
  submenu_index = 1
  selected_menu = submenus[page_index][submenu_index]
  transport_active = false
  pattern_length = {2,2,2,2} -- loop length for each of the 4 patterns
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
      chord_seq[p][i] = {x = 1} -- raw value
      chord_seq[p][i]["c"] = 1  -- chord wrapped 1-7   
      chord_seq[p][i]["o"] = 0  -- octave
    end
  end
  chord_seq_position = 0
  chord = {} --probably doesn't need to be a table but might change how chords are loaded
  chord = {music.generate_chord_scale_degree(chord_seq[pattern][1].o * 12, mode, chord_seq[pattern][1].c, false)}
  chord_hanging_notes = {}
  arp_seq = {{8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8},
            {8,8,8,8,8,8,8,8}
            } -- sub table in case we want multiple arp patterns
  arp_pattern_length = {8,8,8,8}
  arp_pattern = 1
  arp_seq_position = 0
  arp_seq_note = 8
  engine.release(5)
  reset_clock() -- will turn over to step 0 on first loop
  -- clock.run(grid_redraw_clock) --Not used currently
  grid_redraw()
end

function t_f_string(x)
  return(x == 1 and 'True' or 'False')
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
  stop_chord()
  if params:get('do_follow') == 1 then
    reset_arrangement()
  end
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
          harmonizer(arp_note_num, params:string('arp_dest'))
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
  chord = {music.generate_chord_scale_degree(chord_seq[pattern][chord_seq_position].o * 12, mode, chord_seq[pattern][chord_seq_position].c, false)}
  if destination == 'Engine' then
    for i=1,#chord[1] do -- only one chord is stored but it's in index 1. Kinda weird IDK.
      engine.hz(music.note_num_to_freq(chord[1][i] + params:get('transpose')+ 48 )) -- same as above
    end
  elseif destination == 'MIDI' then
    for i=1,#chord[1] do -- only one chord is stored but it's in index 1. Kinda weird IDK.
      out_midi:note_on((chord[1][i] + params:get('transpose')+ 48 ),127) 
      chord_hanging_notes[i] = chord[1][i] + params:get('transpose')+ 48
    end
  end
end

function stop_chord()
  for i = 1, #chord_hanging_notes do          --Turn off any hanging chord notes
    out_midi:note_off(chord_hanging_notes[i])
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
            print("pattern_seq_length "..pattern_seq_length)
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
  elseif page_name == 'Arrange' then
    if selected_menu == 'Follow' then 
      params:set("do_follow", util.clamp(params:get("do_follow") + d, 0, 1))
    end
  elseif page_name == 'Chord' then
    if selected_menu == 'Division' then
      params:set("chord_div", util.clamp(params:get("chord_div") + d, 4, 128))
      elseif selected_menu == 'Destination' then 
      params:set("chord_dest", util.clamp(params:get("chord_dest") + d, 1, 2)) -- only 2 destinations
    end
  elseif page_name == 'Arp' then
    if selected_menu == 'Division' then
      params:set("arp_div", util.clamp(params:get("arp_div") + d, 1, 32))
    elseif selected_menu == 'Destination' then 
      params:set("arp_dest", util.clamp(params:get("arp_dest") + d, 1, 2))
    end
  elseif page_name == 'Crow' then
    if selected_menu == 'Division' then
      params:set("crow_div", util.clamp(params:get("crow_div") + d, 1, 32))
    elseif selected_menu == 'Destination' then 
      params:set("crow_dest", util.clamp(params:get("crow_dest") + d, 1, 2))
    elseif selected_menu == 'Auto-rest' then
      params:set("do_crow_auto_rest", util.clamp(params:get("do_crow_auto_rest") + d, 1, 2))
    end
  elseif page_name == 'MIDI' then
    if selected_menu == 'Destination' then 
      params:set('midi_dest', util.clamp(params:get('midi_dest') + d, 1, 2))
    end
  elseif page_name == 'Global' then
    if selected_menu == 'Tempo' then
      params:set("clock_tempo", util.clamp(params:get("clock_tempo") + d, 1, 300))
    elseif selected_menu == 'Scale' then
      mode = util.clamp(mode + d, 1, 9)
      scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
    elseif selected_menu == 'Transpose' then
      params:set('transpose', util.clamp(params:get('transpose') + d, -24, 24))
    end
  end
  redraw()
end

function crow_trigger(s) --Trigger in used to sample voltage from Crow IN 1
    state = s
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
    print('crow trigger in')
end

function sample_crow(v)
  volts = v
  crow_note_num =  round(volts * 12,0) + 1
  harmonizer(crow_note_num, params:string('crow_dest')) 
end
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

in_midi.event = function(data)
  local d = midi.to_msg(data)
  if d.type == "note_on" then
    -- engine.amp(d.vel / 127)
    -- engine.hz(music.note_num_to_freq(d.note))
    harmonizer(d.note - 36, params:string('midi_dest'))
    -- print('midi note in: ' ..d.note)
  end
end

function harmonizer(note_num, destination) 
  -- print(note_num .. " " ..destination)
  prev_harmonizer_note = harmonizer_note
  harmonizer_note = chord[1][util.wrap(note_num, 1, #chord[1])]
  harmonizer_octave = math.floor((note_num - 1) / #chord[1],0)
  -- print(arp_note_num.. "  " .. harmonizer_note.."  "..harmonizer_octave)
  -- if chord_seq_retrig == true or harmo_filter == 0 or (harmo_filter == 1 and (prev_harmonizer_note ~= harmonizer_note)) then
  if chord_seq_retrig == true or params:string('do_crow_auto_rest') == 'False' or (params:string('do_crow_auto_rest') == 'True' and (prev_harmonizer_note ~= harmonizer_note)) then
  -- params:add_option("do_crow_auto_rest", "Crow Auto-rest", {"False","True"}, 1) -- Whether repeat notes are suppressed
    if destination == 'Engine' then
      engine.hz(music.note_num_to_freq(harmonizer_note + (harmonizer_octave * 12) + params:get('transpose') + 48))
    elseif destination == 'Crow' then
      crow.output[4].volts = (harmonizer_note + (harmonizer_octave * 12) + params:get('transpose')) / 12
      crow.output[3].slew = 0
      crow.output[3].volts = 8
      crow.output[3].slew = 0.005
      crow.output[3].volts = 0
    end
  end
  chord_seq_retrig = false
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
  screen.move(40,10)
  screen.level(15)
  if page_name == 'Arrange' then
    screen.text('Follow: '..params:string("do_follow"))
    screen.move(40,20)
    screen.text('Length: ' .. arrangement_time())
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
      -- screen.rect(rect_x + i - pattern_seq_position - 1, 60, rect_w, rect_h)
      screen.fill()
      rect_x = rect_x + rect_w
      -- print(rect_x.. ' ' .. rect_h)
    end
  elseif page_name == 'Chord' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Division: '..params:get('chord_div'))
    screen.move(40,20)
    screen.level(submenu_index == 2 and 15 or 3)
    screen.text('Destination: '..params:string('chord_dest'))
  elseif page_name == 'Arp' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Division: '..params:get('arp_div'))
    screen.move(40,20)
    screen.level(submenu_index == 2 and 15 or 3)
    screen.text('Destination: '..params:string('arp_dest'))
  elseif page_name == 'Crow' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Division: '..params:get('crow_div'))
    screen.move(40,20)
    screen.level(submenu_index == 2 and 15 or 3)
    screen.text('Destination: '..params:string('crow_dest'))
    screen.move(40,30)
    screen.level(submenu_index == 3 and 15 or 3)
    screen.text('Auto-rest: '..params:string('do_crow_auto_rest'))
  elseif page_name == 'MIDI' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Destination: '..params:string('midi_dest'))
    -- screen.move(40,20)
    -- screen.level(submenu_index == 2 and 15 or 3)
    -- screen.text('Auto-rest: '..params:string('do_midi_auto_rest'))
  elseif page_name == 'Global' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Tempo: '..params:get("clock_tempo"))
    screen.move(40,20)
    screen.level(submenu_index == 2 and 15 or 3)
    screen.text('Scale: ' .. music.SCALES[mode].name)
    screen.move(40,30)
    screen.level(submenu_index == 3 and 15 or 3)
    screen.text('Transpose: ' .. params:get('transpose'))
  end
  screen.update()
end
