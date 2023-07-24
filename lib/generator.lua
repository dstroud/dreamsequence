-- IT'S CRAZY IN HERE DON'T JUDGE Meeeeeee
function init_generator()
  chord_reroll_attempt = 0
  chord_generator('init')
  seq_generator('init')
end


function generator()
  params:set('chord_octave', math.random(-1,0))
  params:set('seq_octave_1', math.random(-1,1))
    
  --SEQUENCE RANDOMIZATION
  params:set('transpose', math.random(-6,6))
  
  -- 7ths are still kinda risky and might be better left to the seq section
  params:set('chord_type', percent_chance(50) and 1 or 2)

  if params:get('clock_source') == 1 then 
    params:set('clock_tempo', math.random(50,140))
  end
  
  params:set('mode', math.random(1, 9)) -- Currently this is called each time c-gen runs, but might change this
  -- not really the best option but this is what the OG algos were built around
  params:set('seq_start_on_1', 1)
  params:set('seq_reset_on_1', 3)
  params:set('seq_note_map_1', math.random(1, 2))

  --ENGINE BASED RANDOMIZATIONS
  -- This kinda sucks and only works for PolyPerc. Need to rethink this approach. 
  -- May be overwritten depending on algo type
  params:set('chord_pp_amp', 50)
  params:set('chord_pp_gain', math.random(0,350))
  params:set('chord_pp_pw', math.random(10,90))
  params:set('chord_div_index', 15)
  params:set('chord_duration_index', params:get('chord_div_index'))

  chord_generator('run')
  print('Chord algo: ' .. chord_algos['name'][chord_algo])
  seq_generator('run')
  grid_redraw()
  redraw()
end


-- Hacky stripped-down version of full chord+seq generator to be used for Events and Chord grid view gen
-- Why does this exist? I don't remember.
function chord_generator_lite()
  params:set('chord_octave', math.random(-1,0))
  -- params:set('seq_octave_1', math.random(-1,1))
    
  --SEQUENCE RANDOMIZATION
  params:set('transpose', math.random(-6,6))
  params:set('chord_type', percent_chance(50) and 1 or 2)

  if params:get('clock_source') == 1 then 
    params:set('clock_tempo', math.random(50,140))
  end
  
  params:set('mode', math.random(1,9))

  --ENGINE BASED RANDOMIZATIONS
  -- May be overwritten depending on algo type
  params:set('chord_pp_amp', 50)
  params:set('chord_pp_gain', math.random(0,350))
  params:set('chord_pp_pw', math.random(10,90))
  params:set('chord_div_index', 15)
  params:set('chord_duration_index', params:get('chord_div_index'))
  
  chord_generator('run')
  print('Chord algo: ' .. chord_algos['name'][chord_algo])
  grid_redraw()
  -- gen_dash('chord_generator_lite')
  redraw()
end


function chord_generator(mode)
  -- Some common random ranges that will be re-rolled for the Seq section
  local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  local random_1_7 = math.random(1,7)
  local random_4_11 = math.random(4,11)
  local random_1_14 = math.random(1,14)
  
  -- Table containing chord algos. This runs at init as well.
  chord_algos = {name = {}, func = {}}
  -- Index 1 reserved for Random
  table.insert(chord_algos['name'], 'Random')
  table.insert(chord_algos['func'], 'Random')


  -- ALGOS LISTED BELOW ARE INSERTED INTO chord_algos. Eventually these will be moved into individual files I think.
  local chord_algo_name = '4-passing'
  -- Don't start with a dim or aug chord
  -- Aug and dim chords are used as 'passing chords' so a dim chord will be followed by a chord one degree down, and an aug will be followed by a chord one degree up.
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()      
    
    params:set('chord_pattern_length', 4)
    build_mode_chord_types()
    progression_valid = false
    progression = {}
    
    while progression_valid == false do
      for i = 1,4 do
        if i == 1 then
          -- Pick a 'safe' chord (not dim or aug) for the first chord in the pattern
          table.insert(progression, safe_chord_degrees[math.random(1,#safe_chord_degrees)])
        else
          local prev_chord_type = mode_chord_types[util.wrap(progression[i-1],1,7)] -- wrapped since we can get values <1
          if prev_chord_type == 'dim' then
            table.insert(progression, progression[i-1] - 1)
          elseif prev_chord_type == 'aug' then  
            table.insert(progression, progression[i-1] + 1)
          else
            table.insert(progression, math.random(1,7))
          end  
        end
        
      -- If the last chord is dim or aug, wrap around and set the first chord +/- 1
      -- This works for everything except Melodic Minor which can result in chord 4 being a vii dim and thus chord 1 being a vi dim
        if i == 4 then
          if mode_chord_types[progression[4]] == 'dim' then
            progression[1] = progression[4] - 1
          elseif mode_chord_types[progression[4]] == 'aug' then
            progression[1] = progression[4] + 1
          end
          -- one final check to see if the 1st chord is a dim which should be rare and will just result in a reroll
          local prev_chord_type = mode_chord_types[util.wrap(progression[1],1,7)] -- wrapped since we can get values <1
          if prev_chord_type == 'dim' or prev_chord_type == 'aug' then
            progression = {}
            progression_valid = false
            -- print('reroll')
          else
            progression_valid = true
          end
        end
        
      end
    end
    
    octave_split_up()
    for i = 1, chord_pattern_length[active_chord_pattern] do
      local x = progression[i]
      chord_pattern[active_chord_pattern][i] = x
    end
    
    -- IDK may as well mix it up
    -- this causes some infinite loop that is bad news. Come back to it.
    -- if math.random() < .5 then
    --   print('double_space')
    --   double_space()
    -- end
    
  end)


  local chord_algo_name = 'I-vi stagger'
  -- Preserves relationship between chords 1 and 2 and applies this to chords 3 and 4
  -- Runs until there are no aug/dims which is pretty inefficient. Should refactor when I am feeling more smart
  -- Still seeing the occasional aug/dim slip through but I have no idea how
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()      

    build_mode_chord_types()
    local octave = math.random() >= .5 and 0 or 7
    local first = math.random(1,#safe_chord_degrees)
    
    while (third or first) == first do
      third = math.random(1,#safe_chord_degrees)
    end
    
    local first = first + octave
    local third = third + octave
    
    local min_chord = math.min(first, third)
    local max_chord = math.max(first, third)
    
    reroll = true
    while reroll == true do
      local max_jump = 10 -- Smaller number = smaller jumps to chord 2 and 4 but fewer pattern possibilities
      offset = math.random(math.max((1 - min_chord), -max_jump), math.min((14 - max_chord), max_jump))
      
      if (math.abs(offset) == 7) or (offset == 0) then 
        reroll = true 
      else
        reroll = false
      end
    end
    
    local second = first + offset
    local fourth = third + offset
    
    progression = {first, second, third, fourth}

    -- Reroll if dims/augs show up. This can result in a lot of rerolls but I'm just pretending I can't see this
    reroll = false
    for i = 1,#progression do
      local this_type = mode_chord_types[util.wrap(progression[i], 1, 7)]
      if (this_type == 'aug') or (this_type == 'dim') then
        -- print('reroll')
        reroll = true
      end
    end
    if reroll == true then
      load(chord_algos['func'][chord_algo])
    end
      
    params:set('chord_pattern_length', 4)
    for i = 1, chord_pattern_length[active_chord_pattern] do
      local x = progression[i]
      chord_pattern[active_chord_pattern][i] = x
    end
    
    -- IDK may as well mix it up
    -- this causes some infinite loop that is bad news. Come back to it.
    -- if math.random() < .5 then
    --   print('double_space')
    --   double_space()
    -- end
    
  end)


  local chord_algo_name = '2-chord+'
  -- 2 chords with adjusted step length for possibility of embellishment chords
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()  
    
    params:set('chord_div_index', div_to_index('1/4'))
    params:set('chord_pattern_length', 8)
    
    build_mode_chord_types()

    progression = {1,2,3,4,5,6,7}
    progression = shuffle(safe_chord_degrees)
    
    -- Transposes a value up an octave if the split is too wide.
    progression[2] = progression[2] + ((progression[1] - progression[2] > 3) and 7 or 0)
    progression[1] = progression[1] + ((progression[2] - progression[1] > 3) and 7 or 0)
  
    local x = progression[1]
    chord_pattern[active_chord_pattern][1] = x
    local x = progression[2]
    chord_pattern[active_chord_pattern][5] = x
    
    local position = 8 -- math.random(7, 8)
      
    -- Check if diminished/aug passing chord back to first step is possible. If so, some probability of doing this because it sounds fancii.
    if (progression[1] < 14) and mode_chord_types[util.wrap(progression[1], 1, 7) + 1] == 'dim' and math.random() <.25 then
      chord_pattern[active_chord_pattern][4] = x
      chord_pattern[active_chord_pattern][8] = x
      local x = progression[1] + 1
      chord_pattern[active_chord_pattern][position] = x
    elseif (progression[1] >1) and mode_chord_types[util.wrap(progression[1], 1, 7) - 1] == 'aug'  and math.random() <.25 then
      -- local position = 8
      local x = progression[1] - 1
      chord_pattern[active_chord_pattern][position] = x
    else
    -- Chance of adding a safe transition chord or two in the mix
      local octave_1 = pick_octave(progression[1], progression[3]) 
      local octave_2 = pick_octave(progression[1], progression[4]) 
      local x_1 = octave_1 + progression[3]
      local x_2 = octave_2 + progression[4]
      local option = math.random()
      if option < .2 then                     -- passing chord on step 4
        chord_pattern[active_chord_pattern][4] = x_1
      elseif option < .4 then                 -- passing chord on step 8
        chord_pattern[active_chord_pattern][8] = x_1
      elseif option < .6 then                 -- same passing chord on steps 4 and 8 (cheesy but kinda nice sometimes)
        chord_pattern[active_chord_pattern][4] = x_1
        chord_pattern[active_chord_pattern][8] = x_1
      elseif option < .8 then                 -- different passing chords on steps 4 and 8
        chord_pattern[active_chord_pattern][4] = x_1
        chord_pattern[active_chord_pattern][8] = x_2        
      end
      
    end
    
  end)
  
  
  -- Set the chord pattern if not mode == 'init'
  if mode == 'run' then
    clear_chord_pattern()
  -- chord_generator index 1 is reserved for Randomize, otherwise fire the selected algo. Non-local for rerolls.
    chord_algo = params:get('chord_generator') == 1 and math.random(2,#chord_algos['name']) or params:get('chord_generator')
    load(chord_algos['func'][chord_algo])
  end
end 
---------- end of chord_generator --------------


-- SEQ GENERATOR
function seq_generator(mode)
  -- print('seq_generator')
  -- clear_seq(active_seq_pattern)
  -- Base seq pattern length, division, duration
  -- local length = math.random(3,4) * (percent_chance(70) and 2 or 1)
  -- local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length

  -- Clock tempo is used to determine good seq_div_index_1
  -- m*x+b: change b to set relative div
  -- local base_div_index = math.min(math.max(util.round(0.05 * params:get('clock_tempo') + 2),2),5)
  -- local base_div_index = math.min(math.max(util.round((.2/3 * params:get('clock_tempo') - 2)) * (percent_chance(70) and 2 or 1),3),12)
  
  -- local min_div_index = util.round(0.0375 * params:get('clock_tempo') + 0.75)
  local min_div_index = util.round(0.025 * params:get('clock_tempo') + 1.5)
  local max_div_index = util.round(0.0375 * params:get('clock_tempo') + 6.75)
  local div = math.random(min_div_index, max_div_index)
  local tuplet_shift = div % 2  -- even or odd(tuplets) seq pattern length
  local length = (4 - tuplet_shift) * (percent_chance(70) and 2 or 1)
  
  -- if params:get('clock_tempo') < 80 then
  -- local div = math.random(2,3) * 2 - tuplet_shift
  -- elseif params:get('clock_tempo') < 100 then
  -- local div =  math.random(3,4) * 2 - tuplet_shift
  -- elseif params:get('clock_tempo') < 120 then
  --   local div =  math.random(4,5) * 2 - tuplet_shift
  -- else
  --   local div =  math.random(5,6) * 2 - tuplet_shift
  -- end
    
  -- 50% chance of the seq note map including 7th notes
  local seq_note_map_1 = math.random(1, 2) --percent_chance(50) and 1 or 2

  -- Engine randomizations
  local gain = math.random(0,350)
  local pw = math.random(10,90)

  -- Commonly-used random values
  local seq_min = math.random(1,7)
  local seq_max = math.random(8,14)
  local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  local random_1_7 = math.random(1,7)
  local random_4_11 = math.random(4,11)   --seq note distribution center
  local random_1_14 = math.random(1,14)  
  local random_note_offset = math.random (0,7)
  local seq_root = math.random(seq_min, seq_max)  -- made local
  local seq_offset = util.wrap(seq_root + math.random(1, seq_max - seq_min), seq_min, seq_max)
  
  -- Generate Euclydian rhythm
  local er_table = {}
  local er_table = ER.gen(math.random(1, math.max(1,length - 1)), length, 0) --pulses, steps, shift  -- max pulses?
  local er_note_on_count = 0
  for i = 1, #er_table do
    er_note_on_count = er_note_on_count + (er_table[i] and 1 or 0)
  end

  -- Pre-randomizations which can be overwritten by the individual algorithms
  -- This step is omitted when running init (used to populate algo table for menus)
  if mode == 'run' then
    clear_seq(active_seq_pattern)
    -- Pattern/session randomizations
    params:set('seq_pattern_length_' .. active_seq_pattern, length)
    params:set('seq_div_index_1', div)
    -- params:set('seq_duration_index_1', div)
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('seq_duration_index_1',math.max(math.random(params:get('seq_div_index_1'), params:get('seq_div_index_1') + 4), 5))
    params:set('seq_note_map_1', seq_note_map_1)
    -- not really the best option but this is what the OG algos were built around
    params:set('seq_start_on_1', 1)
    params:set('seq_reset_on_1', 3)
  
    -- Engine randomizations
    params:set('seq_pp_amp_1', 70)
    params:set('seq_pp_gain_1', gain)
    params:set('seq_pp_pw_1', pw)
  end 
    
  -- Table containing seq algos. This runs at init as well.
  seq_algos = {name = {}, func = {}}
  -- Index 1 reserved for Random
  table.insert(seq_algos['name'], 'Random')
  table.insert(seq_algos['func'], 'Random')


  -- SEQ ALGOS LISTED BELOW ARE INSERTED INTO seq_algos
  
  local seq_algo_name = 'Seq up-down'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()  

    -- Pretty fast seqs here so no shifting octave down
    params:set('seq_octave_1', math.max(params:get('seq_octave_1'), 0))

    -- Prefer longer and faster sequence
    params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * 2) -- 6 (tuplet) or 8 length
    tuplet_shift = (seq_pattern_length[active_seq_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('seq_div_index_1', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('seq_duration_index_1',math.max(math.random(params:get('seq_div_index_1'), params:get('seq_div_index_1') + 4), 5))

    local peak = math.random(2, seq_pattern_length[active_seq_pattern] - 1)
    for i = 1, peak do
      seq_pattern[1][i] = seq_min - 1 + i
    end
    for i = 1, seq_pattern_length[active_seq_pattern] - peak do
      seq_pattern[1][i + peak] = seq_pattern[1][peak] - i
    end
    
    seq_check_bounds() -- confirmed issues
  end)


  local seq_algo_name = 'Seq down-up'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()  
 
    -- Pretty fast seqs here so no shifting octave down
    params:set('seq_octave_1', math.max(params:get('seq_octave_1'), 0))

    -- Sequence length of 6(tuplet) or 8 steps
    params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * 2) -- 6 (tuplet) or 8 length
    tuplet_shift = (seq_pattern_length[active_seq_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('seq_div_index_1', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('seq_duration_index_1',math.max(math.random(params:get('seq_div_index_1'), params:get('seq_div_index_1') + 4), 5))

    local peak = math.random(2, seq_pattern_length[active_seq_pattern] - 1)
    for i = 1, peak do
      seq_pattern[1][i] = seq_max - 1 - i
    end
    for i = 1, seq_pattern_length[active_seq_pattern] - peak do
      seq_pattern[1][i + peak] = seq_pattern[1][peak] + i
    end  
    
    seq_check_bounds() -- confirmed issues
  end)
  
  
  local seq_algo_name = 'ER 1-note'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()
    
    for i = 1, #er_table do
      seq_pattern[1][i] = er_table[i] and seq_root or 0
    end
    rotate_pattern('Seq', math.random(0,percent_chance(50) and 7 or 0))
  
  end)
  

  local seq_algo_name = 'ER 2-note'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()
    
    for i = 1, #er_table do
      seq_pattern[1][i] = er_table[i] and seq_root or seq_offset
    end
    rotate_pattern('Seq', math.random(0,percent_chance(50) and 7 or 0))
  
  end)
  
  
  local seq_algo_name = 'Strum up'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()  
    params:set('seq_octave_1', math.random(0,1))

    params:set('seq_start_on_1', 3) -- chord
    params:set('seq_reset_on_1', 2) -- chord
    params:set('seq_pp_amp_1',35) --Turn down amp since a lot of notes can clip
    params:set('seq_duration_index_1',15)
    params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * 2)

    -- Strum speed from 1/64T to 1/32T
    params:set('seq_div_index_1', math.random(1,5))
    
    for i = 1, seq_pattern_length[active_seq_pattern] do
      seq_pattern[1][i] = seq_min - 1 + i
    end
    
  end)


  local seq_algo_name = 'Strum down'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()
    params:set('seq_octave_1', math.random(0,1))
    params:set('seq_start_on_1', 3) -- chord
    params:set('seq_reset_on_1', 2) -- chord
    params:set('seq_pp_amp_1',35) --Turn down amp since a lot of notes can clip
    params:set('seq_duration_index_1',15)
    params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * 2)

    -- Strum speed from 1/64T to 1/32T
    params:set('seq_div_index_1', math.random(1,5))
    
    for i = 1, seq_pattern_length[active_seq_pattern] do
      seq_pattern[1][i] = seq_max - 1 - i
    end
    
  end)
  
  
  -- local seq_algo_name = 'ER seq +rests'
  -- table.insert(seq_algos['name'], seq_algo_name)
  -- table.insert(seq_algos['func'], function()
    
  --   local note_shift = 0
  --   if seq_root - er_note_on_count < 1 then
  --     for i = 1, #er_table do
  --       seq_pattern[1][i] = er_table[i] and (seq_root + note_shift) or 0
  --       note_shift = note_shift + (er_table[i] and 1 or 0)
  --     end
  --   elseif seq_root + er_note_on_count > 14 then
  --     for i = 1, #er_table do
  --       seq_pattern[1][i] = er_table[i] and (seq_root + note_shift) or 0
  --       note_shift = note_shift - (er_table[i] and 1 or 0)
  --     end
  --   else
  --     local direction = (seq_root + math.random() > .5 and 1 or -1)
  --     for i = 1, #er_table do    -- I don't think this is firing?
  --       seq_pattern[1][i] = er_table[i] and (seq_root + note_shift) or 0
  --       note_shift = note_shift + (er_table[i] and direction or 0)
  --     end
  --   end
  --   seq_check_bounds() -- confirmed issues
    
  -- end)


  -- local seq_algo_name = 'ER drunk+rest'
  -- table.insert(seq_algos['name'], seq_algo_name)
  -- table.insert(seq_algos['func'], function() 

  --   local note_shift = 0
  --   for i = 1, #er_table do
  --     seq_pattern[1][i] = er_table[i] and (seq_root + note_shift) or 0
  --     direction = math.random() > .5 and 1 or -1
  --     note_shift = note_shift + (er_table[i] and direction or 0)
  --   end
    
  -- end)


  -- local seq_algo_name = 'Seq. up'
  -- table.insert(seq_algos['name'], seq_algo_name)
  -- table.insert(seq_algos['func'], function()
  
  --   -- params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * (percent_chance(30) and 2 or 1))
  --   -- local tuplet_shift = (seq_pattern_length[active_seq_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
  --   -- -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
  --   -- if params:get('clock_tempo') < 80 then
  --   --   params:set('seq_div_index_1', math.random(2,3) * 2 - tuplet_shift)
  --   -- elseif params:get('clock_tempo') < 100 then
  --   --   params:set('seq_div_index_1', math.random(3,4) * 2 - tuplet_shift)
  --   -- elseif params:get('clock_tempo') < 120 then
  --   --   params:set('seq_div_index_1', math.random(4,5) * 2 - tuplet_shift)
  --   -- else
  --   --   params:set('seq_div_index_1', math.random(5,6) * 2 - tuplet_shift)
  --   -- end
    
  --   -- -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
  --   -- params:set('seq_duration_index_1',math.max(math.random(params:get('seq_div_index_1'), params:get('seq_div_index_1') + 4), 5))
    
  --   for i = 1, seq_pattern_length[active_seq_pattern] do
  --     seq_pattern[1][i] = seq_min - 1 + i
  --   end
    
  -- end)


  local seq_algo_name = 'Seq. down'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()  
  
    -- params:set('seq_pattern_length_' .. active_seq_pattern, math.random(3,4) * (percent_chance(30) and 2 or 1))
    -- tuplet_shift = (seq_pattern_length[active_seq_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    -- params:set('seq_div_index_1', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    -- params:set('seq_duration_index_1',math.max(math.random(params:get('seq_div_index_1'), params:get('seq_div_index_1') + 4), 5))
    
    for i = 1, seq_pattern_length[active_seq_pattern] do
      seq_pattern[1][i] = seq_max + 1 - i
    end
    
  end)


  local seq_algo_name = 'Dual seq'
  table.insert(seq_algos['name'], seq_algo_name)
  table.insert(seq_algos['func'], function()
  
    -- 8 or 6(tuplet) length
    local length = math.random(3,4) * 2
    params:set('seq_pattern_length_' .. active_seq_pattern, length)
    local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16 to 1/4 standard or tuplet
    params:set('seq_div_index_1', (math.random(3,5) * 2) - tuplet_shift)
    -- Whole note duration seems nice here?
    params:set('seq_duration_index_1', div_to_index('1'))
  
    -- Lines originate from the first/last 7 notes on the grid. Can overlap.
    local seq_min = math.random(1,7)
    local seq_max = math.random(11,14)
    
    local x = math.random(1,2)
    for i = 1, length/2  do
      seq_pattern[1][i*2 - 1] = seq_min - 1 + i * x
    end
  
    local x = math.random(1,2)
    for i = 1, length/2  do
      seq_pattern[1][i*2 - 1 + 1] = seq_max + 1 - i * x
    end

    seq_check_repeats()
    
    -- local x1 = math.random(1,2)
    -- local x2 = math.random(1,2)
    -- for i = 1, length / 2 do
    --   seq_pattern[1][i*2 - 1] = seq_min - 1 + i * x1
    --   if seq_pattern[1][i*2 - 1] == seq_pattern[1][i*2 - 2] then
    --     print('dual seq repeat')
    --     seq_pattern[1] = {0,0,0,0,0,0}
    --     load(seq_algos['func'][seq_algo])
    --     break
    --   end
      
    --   seq_pattern[1][i*2 - 1 + 1] = seq_max + 1 - i * 2
    --   if seq_pattern[1][i*2 - 1 + 1] == seq_pattern[1][i*2 - 1] then
    --     print('dual seq repeat')
    --     seq_pattern[1] = {}
    --     load(seq_algos['func'][seq_algo])
    --     break
    --   end
    -- end
    

    
      -- load(seq_algos['func'][chord_algo])

    -- pass = false
    -- while pass == false do
    --   local x = math.random(1,2)
    --   for i = 1, length/2  do
    --     seq_pattern[1][i*2 - 1 + 1] = seq_max + 1 - i * x
    --     -- pass = seq_pattern[1][i + 1] == seq_pattern[1] and false or true
    --     if seq_pattern[1][i*2 - 1 + 1] == seq_pattern[1][i*2 - 1] then
    --       print('failed')
    --       pass = false
    --     else
    --       pass = true
    --     end
    --   if pass == false then break end
    --   end
    -- end
    
    -- if seq_max + 1 - i * x == seq_pattern[1][i*2 - 1]
    
    -- tab.print(seq_pattern[1])
    
    -- if seq_pattern[1][1] < 7 then
    --   print('reroll')
    --   local x = math.random(1,2)
    --     for i = 1, length/2  do
    --       seq_pattern[1][i*2 - 1 + 1] = seq_max + 1 - i * x
    --     end
    -- end


  end)
  
  
  -- local seq_algo_name = 'Rnd. +ER rest'
  -- table.insert(seq_algos['name'], seq_algo_name)
  -- table.insert(seq_algos['func'], function()  
    
  --   for i = 1, length do
  --     seq_pattern[1][i] = math.random(1,7) + random_note_offset
  --   end
  --   if percent_chance(60) then --add some rests to the seq
  --     for i = 1, length do
  --       seq_pattern[1][i] = er_table[i] and seq_pattern[1][i] or 0
  --     end
  --   end
  
  -- seq_check_repeats()
  
  -- end)


  -- Set the seq pattern  
  if mode == 'run' then
    -- Clear pattern.
    for i = 1,8 do
      seq_pattern[1][i] = 0
    end
    
  -- seq_generator index 1 is reserved for Randomize, otherwise fire the selected algo.
    seq_algo = params:get('seq_generator') == 1 and math.random(2,#seq_algos['name']) or params:get('seq_generator')
    print('Seq algo: ' .. seq_algos['name'][seq_algo])
    load(seq_algos['func'][seq_algo])
  end
end


--utility functions
-----------------------------------------------------------------

-- bit of a hack to get existing algos working with the expanded WIP musicutil chords. Just classifies as dim/aug/min/maj
-- todo p0 fix this up right
function chord_type_simplified(arg)
  if string.find(arg, "+") then
    return("aug")
  elseif string.find(arg, "\u{B0}") then 
    return("dim")
  elseif string.find(arg, "\u{F8}") then      -- todo p0 half dim!
    return("dim") 
  elseif arg == "7" then	                    -- todo p0 major minor!
    return("major")
  elseif string.find(arg, "m\u{266e}") then   -- todo p0 min-major!
    return("min")     
  elseif arg == "m7" then
    return("min")
  elseif arg == "m" then
    return("min")  
  elseif arg == "M7" then
    return("maj")
  elseif arg == "" or arg == nil then
    return("maj")       
  end  
end

--builds a lookup table of chord types: aug/dim etc...
function build_mode_chord_types()
    mode_chord_types = {}
    safe_chord_degrees = {}    
    for i = 1,7 do
      local chord_type = chord_type_simplified(get_chord_name(2, params:get('mode'), MusicUtil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][i]))
      mode_chord_types[i] = chord_type
      if chord_type == 'maj' or chord_type == 'min' then table.insert(safe_chord_degrees, i) end  --todo p0 what about 7ths here?
    end
    -- print('--------')
    -- print('mode ' .. params:get('mode') .. ' chord types')    
    -- tab.print(mode_chord_types)
    -- print('--------')
end

-- -- Chance of playing higher chord degrees an octave lower
-- -- Anything over this is going to get transposed down an octave
-- function octave_split_down()
--   local split = math.random(9,14)
--   for i = 1,4 do
--     local x = progression[i] + 7
--     progression[i] = x < split and x or x - 7
--   end  
-- end

-- Chance of playing lower chord degrees an octave higher
-- Anything under this split is going to get transposed up an octave. Also corrects for x < 0 scenarios
function octave_split_up()
  local split = math.random(1,8)
  for i = 1,#progression do
    local x = progression[i]
    progression[i] = x < split and x +7 or x
  end
end


-- checks seq pattern for out-of-bound notes
-- if found, wipe pattern and rerun algo
-- don't hate the player- hate. the. game.
function seq_check_bounds()   
  error_check = false
  local length = seq_pattern_length[active_seq_pattern]
  for i = 2, length do
    if seq_pattern[1][i] < 0 or seq_pattern[1][i] > 14 then
      error_check = true
      print('off-grid note on row ' .. i)
      break
    end
  end
  if error_check then
    print('clearing')
    clear_seq(active_seq_pattern)
    print('rerolling')
    load(seq_algos['func'][seq_algo])
  end
end


-- checks seq pattern for repeat notes
-- if found, wipe pattern and rerun algo
function seq_check_repeats()   
  error_check = false
  local length = seq_pattern_length[active_seq_pattern]
  for i = 2, length do
    if seq_pattern[1][i] == seq_pattern[1][i - 1] then
      error_check = true
      -- print('repeat on row ' .. i)
      break
    end
  end
  if error_check then
    -- print('clearing')
    clear_seq(active_seq_pattern)
    -- print('rerolling')
    load(seq_algos['func'][seq_algo])
  end
end


-- insert spaces between pattern and halves step length.
function double_space()
  for i = 8, 3, -1 do
    chord_pattern[active_chord_pattern][i] = (i % 2 == 0) and chord_pattern[active_chord_pattern][i / 2] or 0
  end
  chord_pattern[active_chord_pattern][2] = 0 -- lol ok
  params:set('chord_div_index', math.max(params:get('chord_div_index') - 3, 1))
end


function clear_seq()
  -- print('clear_seq')
  print('max_seq_pattern_length = ' ..  max_seq_pattern_length)
  for i = 1, max_seq_pattern_length do -- seq_pattern_length[active_chord_pattern] do
    -- print('i = ' .. i)
    seq_pattern[1][i] = 0
  end
end


-- Does some sort of weird check to see if we should apply an octave offset to x2 I guess
function pick_octave(x1, x2)
  return((math.max(x1, x2) -  math.min(x1, x2)) < (math.max(x1, x2 + 7) -  math.min(x1, x2 + 7)) and 0 or 7)
end                


-- function sketchy_chord(chord)
--   return(mode_chord_types[chord] == 'dim' or mode_chord_types[chord] == 'aug')
-- end
-----------------------------------------------------------------