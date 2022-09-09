-- norns-arp
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
  pages = {'Arrange','Chord','Arp'}
  view = 'Chord' 
  transport = 'play'
  arp_clock_div = 8 --8th notes, etc
  arp_source_list = {'Internal', 'Crow', 'MIDI'}
  arp_source = 'Internal'
  chord_seq = {} --needs to have a sub table for each pattern!
  for i = 1,8 do
    chord_seq[i] = {x = 1} -- equivalent to chord_seq[i]["x"] = 1
    chord_seq[i]["c"] = 1 -- chord wrapped 1-7   
    chord_seq[i]["o"] = 0 -- octave
  end
  chord_seq_position = 0
  chord = {} --probably doesn't need to be a table but might change how chords are loaded
  chord = {music.generate_chord_scale_degree(chord_seq[1].o * 12, mode, chord_seq[1].c, false)}
  pattern_length = {4,8,8,8} -- loop length for each of the 4 patterns
  pattern = 1
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
  seq_div = {}
  -- seq_div[1] = clock.run(clock_out,1,1) -- seq number, rate divisor. Like 1 PPQN LOL
  -- seq_div[2] = clock.run(chord_loop,2,.25)
  seq_div[2] = clock.run(loop, 8) --fixed global clock at 32nd notes
end

-- function clock_out(index,rate) --investigate nondeterministic clock firing
--   while true do
--     clock.sync(1/rate)
--     crow.output[1].slew = 0
--     crow.output[1].volts = 8
--     crow.output[1].slew = 0.005
--     crow.output[1].volts = 0  
--   end
-- end

-- function chord_loop(index,rate)
--   while true do
--     clock.sync(1/rate)
--     chord_seq_retrig = true -- indicates when we're on a new chord seq step for harmonizer filtering
--     if chord_seq_position > pattern_length[pattern] then 
--       chord_seq_position = 1
--     else  
--       chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
--     end
--     if chord_seq[chord_seq_position].c > 0 then
--       play_chord()
--     end
--     grid_redraw()
--   end
-- end

function loop(rate) --using one clock to control all sequence events
  while transport == 'play' do
    clock.sync(1/8)
    clock_step = util.wrap(clock_step + 1, 0, 31) -- 0-indexed counter for checking when to fire events
    
    --chord clock
    if clock_step % 32 == 0 then
      chord_seq_retrig = true -- indicates when we're on a new chord seq step for harmonizer filtering
      if chord_seq_position > pattern_length[pattern] then 
        chord_seq_position = 1
      else  
        chord_seq_position = util.wrap(chord_seq_position + 1, 1, pattern_length[pattern])
      end
      if chord_seq[chord_seq_position].c > 0 then
        play_chord()
      end
      grid_redraw() -- move
    end
    
    -- arp clock
    -- if arp_source == 'internal' then
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

function grid_redraw_clock() --IDK if this is even needed. Maybe for pulsing LEDs etc...
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
  if view == 'Arrange' then
    g:led(16,6,15)
    --nothin yet!
  elseif view == 'Chord' then
    g:led(16,7,15)
    for i = 1,14 do                                           -- chord seq playhead
      g:led(i, chord_seq_position, 3)
    end
    for i = 1,8 do
      g:led(15, i, pattern_length[pattern] < i and 4 or 15)   --set pattern_length LEDs
      if chord_seq[i].x > 0 then                              -- muted steps
        g:led(chord_seq[i].x, i, 15)                          --set LEDs for chord sequence
      end
    end
  elseif view == 'Arp' then
    g:led(16,8,15)
    for i = 1,14 do                                           -- chord seq playhead
      g:led(i, arp_seq_position, 3)
    end
    for i = 1,8 do
      g:led(15, i, arp_pattern_length[arp_pattern] < i and 4 or 15)   --set pattern_length LEDs
      if arp_seq[arp_pattern][i] > 0 then                              -- muted steps
        g:led(arp_seq[arp_pattern][i], i, 15)                          --set LEDs for arp sequence
      end
    end
  elseif view == 'Arrange' then
    -- g:refresh()
  end
  g:refresh()
end

function g.key(x,y,z)
  if z == 1 then
    if x == 16 and y > 5 then --view switcher buttons
      view = pages[y - 5]
      -- redraw()
      -- grid_redraw()
    elseif view == 'Arrange' then
      -- grid_redraw() --redundant?
      -- redraw()
      
    --chord keys
    elseif view == 'Chord' then
      if x < 15 then
        if x == chord_seq[y].x then
          chord_seq[y].x = 0 -- Only need to set one of these TBH
          chord_seq[y].c = 0 -- Only need to set one of these TBH
          chord_seq[y].o = 0 -- Only need to set one of these TBH
        else
          chord_seq[y].x = x --raw
          chord_seq[y].c = util.wrap(x, 1, 7) --wrap so we can store octave in second index of chord_seq
          chord_seq[y].o = math.floor(x / 8) --octave
          grid_dirty = true
        end
      elseif x == 15 then
        pattern_length[pattern] = y
      end
      -- grid_redraw() --redundant?
      
    -- arp keys
    elseif view == 'Arp' then
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
  if z == 1 then
  end
end

function enc(n,d)
  if view == 'Chord' then
    if n == 1 then
    elseif n == 2 then
    elseif n == 3 then
      mode = util.clamp(mode + d, 1, 9)
      scale = music.generate_scale_of_length(60,music.SCALES[mode].name,8)
    end
  elseif view == 'Arp' then
    if n == 1 then
    elseif n == 2 then
    elseif n == 3 then  
      if arp_source == 'Internal' then                             --This is so shitty yikes
        arp_source = arp_source_list[util.clamp(1 + d, 1,3)]
      elseif arp_source == 'Crow' then 
        arp_source = arp_source_list[util.clamp(2 + d, 1,3)]
      elseif arp_source == 'MIDI' then 
        arp_source = arp_source_list[util.clamp(3 + d, 1,3)]
      end
    end
    -- redraw()
  end
  redraw()
end

function play_chord()
  chord = {music.generate_chord_scale_degree(chord_seq[chord_seq_position].o * 12, mode, chord_seq[chord_seq_position].c, false)}
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
  screen.level(15)
  screen.move(36,0)
  screen.line_rel(0,64)
  screen.stroke()
  screen.move(0,10)
  screen.level(view == 'Arrange' and 15 or 5)
  screen.text('Arrange')
  screen.move(0,20)
  screen.level(view == 'Chord' and 15 or 5)
  screen.text('Chord')
  screen.move(0,30)
  screen.level(view == 'Arp' and 15 or 5)
  screen.text('Arp')
  screen.move(40,10)
  screen.level(15)
  if view == 'Arrange' then
  elseif view == 'Chord' then
    screen.text('Scale: ' .. music.SCALES[mode].name)
  elseif view == 'Arp' then
    screen.text('Source: ' .. arp_source)
  end
  screen.update()
end