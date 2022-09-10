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

params:add_option("do_follow", "Follow", {"False","True"},True) -- Whether arranger is enabled

transpose = 48
mode = math.random(1,9)
scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
harmo_filter = 0 -- 1 filters out duplicate notes, 0 allows 
prev_harmonizer_note = -999
chord_seq_retrig = true

function init()
  crow.input[1].stream = sample_crow
  crow.input[1].mode("none")
  crow.input[2].mode("change",2,0.1,"rising") --might want to use as a gate with "both"
  crow.input[2].change = crow_trigger
  grid_dirty = true
  views = {'Arrange','Chord','Arp'} -- grid "views" are decoupled from screen "pages"
  view_index = 2
  view_name = views[view_index]
  pages = {'Arrange','Chord','Arp','Crow','MIDI','Global'}
  page_index = 2
  page_name = pages[page_index]
  submenus = {
              {"Follow"}, -- Arrange
              {}, -- Chord
              {}, -- Arp
              {}, -- Crow
              {}, -- MIDI
              {"Tempo","Scale"} -- Global
              }
  -- submenu = 1
  submenu_index = 1
  transport_active = false
  -- do_follow = true -- whether pattern follows pattern seq
  arp_clock_div = 8 --8th notes, etc
  arp_source_list = {'Internal', 'Crow', 'MIDI'}
  arp_source_index = 1
  arp_source = 'Internal'
  pattern_length = {4,8,8,8} -- loop length for each of the 4 patterns
  pattern = 1
  pattern_seq = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  pattern_seq_position = 1
  pattern_seq_length = 1
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
  clock_step = 31 -- will turn over to step 0 on first loop
  clock.run(grid_redraw_clock)
  -- seq_div[2] = clock.run(loop, 8) --fixed global clock at 32nd notes
  -- clock.transport.start()
end

function clock.transport.start()
  --TBD if we want to reset to beginning of sequence/arps
  transport_active = true
  clock_loop_id = clock.run(loop, 8) --fixed global clock at 32nd notes
  print("Clock "..clock_loop_id.. " called")
end

function clock.transport.stop()
  transport_active = false
  clock.cancel(clock_loop_id)
end
  
function loop(rate) --using one clock to control all sequence events
  while transport_active do
    clock.sync(1/8)
    clock_step = util.wrap(clock_step + 1, 0, 31) -- 0-indexed counter for checking when to fire events
    
    --chord clock
    if clock_step % 32 == 0 then
      chord_seq_retrig = true -- indicates when we're on a new chord seq step for arp filtering
      if params:get("do_follow") == 2 and chord_seq_position >= pattern_length[pattern] then
        pattern_seq_position = util.wrap(pattern_seq_position + 1, 1, pattern_seq_length)
        pattern = pattern_seq[pattern_seq_position]
      end
      if chord_seq_position > pattern_length[pattern] then 
        chord_seq_position = 1
      else  
        chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
      end
      if chord_seq[pattern][chord_seq_position].c > 0 then
        play_chord()
      end
      grid_redraw() -- move
    end
    
    -- arp clock
      if clock_step % 4 == 0 then
        if arp_seq_position > arp_pattern_length[arp_pattern] then 
          arp_seq_position = 1
        else  
          arp_seq_position = util.wrap(arp_seq_position + 1, 1, arp_pattern_length[arp_pattern])
        end
        if arp_seq[arp_pattern][arp_seq_position] > 0 and arp_source == 'Internal' then
          arp_note_num =  arp_seq[arp_pattern][arp_seq_position] 
          harmonizer()
        end
        grid_redraw() --move
      end

    --crow clock out
    if clock_step % 8 == 0 then
      crow.output[1].slew = 0
      crow.output[1].volts = 8
      crow.output[1].slew = 0.005 --WAG here
      crow.output[1].volts = 0  
    end
    -- end
  end
end

function grid_redraw_clock() --Not necessary now. Maybe for pulsing LEDs etc...
  while true do
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
    clock.sleep(1/30)
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
        -- g:led(x, y, y == pattern_seq[x] and 15 or 4)
        g:led(x,y, x == pattern_seq_position and 7 or 3)
        if y == pattern_seq[x] then
          g:led(x, y, 15)
        end
      end
    end
  elseif view_name == 'Chord' then
  for i = 1,4 do
    g:led(16,i, i == pattern and 15 or 4)
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
        for i = 1,16 do
          if pattern_seq[i] == 0 then
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
      elseif x == 16 and y <5 then
        pattern = y
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
      params:set("do_follow", util.clamp(params:get("do_follow") + d, 1, 2))
  elseif page_name == 'Chord' then
      mode = util.clamp(mode + d, 1, 9)
      scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
  elseif page_name == 'Arp' then
      arp_source_index = util.clamp(arp_source_index + d, 1, #arp_source_list)
      arp_source = arp_source_list[arp_source_index]
  elseif page_name == 'Global' then
    if selected_menu == 'Tempo' then
      params:set("clock_tempo", util.clamp(params:get("clock_tempo") + d, 1, 300))
    elseif selected_menu == 'Scale' then
      mode = util.clamp(mode + d, 1, 9)
      scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
    end
  end
  redraw()
end

function play_chord()
  chord = {music.generate_chord_scale_degree(chord_seq[pattern][chord_seq_position].o * 12, mode, chord_seq[pattern][chord_seq_position].c, false)}
  for i=1,#chord[1] do -- only one chord is stored but it's in index 1 for some reason
    engine.hz(music.note_num_to_freq(chord[1][i] + transpose)) -- same as above
  end
end

function crow_trigger(s)
  if arp_source == 'Crow' then -- this calls sample_crow via crow.input[1].query()
    state = s
    crow.send("input[1].query = function() stream_handler(1, input[1].volts) end") -- see below
    crow.input[1].query() -- see https://github.com/monome/crow/pull/463
  -- elseif arp_source == 'Internal' then
  --   -- sample_crow() -- if we want to layer arp transposition
  end
end

function sample_crow(v)
  volts = v
  arp_note_num =  round(volts * 12,0) + 1 
  harmonizer()
end
  
function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

function harmonizer() 
  prev_harmonizer_note = harmonizer_note
  harmonizer_note = chord[1][util.wrap(arp_note_num, 1, #chord[1])]
  harmonizer_octave = math.floor((arp_note_num - 1) / #chord[1],0)
  -- print("volts: " .. volts.. "  "  .. arp_note_num.. "  " .. harmonizer_note.."  "..harmonizer_octave)
  if chord_seq_retrig == true or harmo_filter == 0 or (harmo_filter == 1 and (prev_harmonizer_note ~= harmonizer_note)) then
    crow.output[4].volts = (harmonizer_note + (harmonizer_octave * 12)) / 12
    crow.output[3].slew = 0
    crow.output[3].volts = 8
    crow.output[3].slew = 0.005
    crow.output[3].volts = 0
  end
  chord_seq_retrig = false
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
  elseif page_name == 'Chord' then
    screen.text('Scale: ' .. music.SCALES[mode].name)
  elseif page_name == 'Arp' then
    screen.text('Source: ' .. arp_source)
  elseif page_name == 'Global' then
    screen.level(submenu_index == 1 and 15 or 3)
    screen.text('Tempo: '..params:get("clock_tempo"))
    screen.move(40,20)
    screen.level(submenu_index == 2 and 15 or 3)
    screen.text('Scale: ' .. music.SCALES[mode].name)
  end
  screen.update()
end