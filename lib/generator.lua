-- IT'S CRAZY IN HERE DON'T JUDGE Meeeeeee
function init_generator()
  chord_reroll_attempt = 0
  chord_generator('init')
  arp_generator('init')
end


function generator()
  params:set('chord_octave', math.random(-1,0))
  params:set('arp_octave', math.random(-1,1))
    
  --SEQUENCE RANDOMIZATION
  params:set('transpose', math.random(-6,6))
  
  -- 7ths are still kida risky and might be better left to the arp section
  params:set('chord_type', percent_chance(20) and 4 or 3)

  if params:get('clock_source') == 1 then 
    params:set('clock_tempo', math.random(50,140))
  end
  
  params:set('mode', math.random(1,9)) -- Currently this is called each time c-gen runs, but might change this

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
  arp_generator('run')
  grid_redraw()
  redraw()
end


-- Hacky stripped-down version of full chord+arp generator to be used for Events and Chord grid view gen
-- Why does this exist? I don't remember.
function chord_generator_lite()
  params:set('chord_octave', math.random(-1,0))
  -- params:set('arp_octave', math.random(-1,1))
    
  --SEQUENCE RANDOMIZATION
  params:set('transpose', math.random(-6,6))
  
  -- 7ths are still kida risky and might be better left to the arp section
  params:set('chord_type', percent_chance(20) and 4 or 3)

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
  -- Some common random ranges that will be re-rolled for the Arp section
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
    for i = 1, chord_pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i] = x
    end  
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
    for i = 1, chord_pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i] = x
    end  
    
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
    chord_seq[pattern][1] = x
    local x = progression[2]
    chord_seq[pattern][5] = x
    
    -- Chance of adding a transition chord at end of loop
    if math.random() >.7 then
      local position = 8
      local x = (math.max(progression[1], progression[3]) -  math.min(progression[1], progression[3])) < (math.max(progression[1], progression[3] + 7) -  math.min(progression[1], progression[3] + 7)) and 0 or 7
      local x = x + progression[3] 
      chord_seq[pattern][position] = x
    end
    
    -- Use diminished passing chord if possible
    if (progression[1] < 14) and mode_chord_types[util.wrap(progression[1], 1, 7) + 1] == 'dim' then --math.random() >.5 then
      local position = 8
      local x = progression[1] + 1
      chord_seq[pattern][position] = x
    end      

    -- Use augmented passing chord if possible
    if (progression[1] >1) and mode_chord_types[util.wrap(progression[1], 1, 7) - 1] == 'aug' then
      local position = 8
      local x = progression[1] - 1
      chord_seq[pattern][position] = x

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


-- ARP GENERATOR
function arp_generator(mode)

  -- Base arp pattern length, division, duration
  -- local length = math.random(3,4) * (percent_chance(70) and 2 or 1)
  -- local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length

  -- Clock tempo is used to determine good arp_div_index
  -- m*x+b: change b to set relative div
  -- local base_div_index = math.min(math.max(util.round(0.05 * params:get('clock_tempo') + 2),2),5)
  -- local base_div_index = math.min(math.max(util.round((.2/3 * params:get('clock_tempo') - 2)) * (percent_chance(70) and 2 or 1),3),12)
  
  -- local min_div_index = util.round(0.0375 * params:get('clock_tempo') + 0.75)
  local min_div_index = util.round(0.025 * params:get('clock_tempo') + 1.5)
  local max_div_index = util.round(0.0375 * params:get('clock_tempo') + 6.75)
  local div = math.random(min_div_index, max_div_index)
  local tuplet_shift = div % 2  -- even or odd(tuplets) arp pattern length
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
    
  -- 30% chance of the arp quantizer including 7th notes
  local chord_type = percent_chance(30) and 4 or 3

  -- Engine randomizations
  local gain = math.random(0,350)
  local pw = math.random(10,90)

  -- Commonly-used random values
  local arp_min = math.random(1,7)
  local arp_max = math.random(8,14)
  local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  local random_1_7 = math.random(1,7)
  local random_4_11 = math.random(4,11)   --arp note distribution center
  local random_1_14 = math.random(1,14)  
  local random_note_offset = math.random (0,7)
  local arp_root = math.random(arp_min, arp_max)  -- made local
  local arp_offset = util.wrap(arp_root + math.random(1, arp_max - arp_min), arp_min, arp_max)
  
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
    -- Pattern/session randomizations
    params:set('arp_pattern_length_' .. arp_pattern, length)
    params:set('arp_div_index', div)
    -- params:set('arp_duration_index', div)
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    params:set('arp_chord_type', chord_type)
    params:set('arp_mode', 1)
  
    -- Engine randomizations
    params:set('arp_pp_amp', 70)
    params:set('arp_pp_gain', gain)
    params:set('arp_pp_pw', pw)
  end 
    
  -- Table containing arp algos. This runs at init as well.
  arp_algos = {name = {}, func = {}}
  -- Index 1 reserved for Random
  table.insert(arp_algos['name'], 'Random')
  table.insert(arp_algos['func'], 'Random')


  -- ARP ALGOS LISTED BELOW ARE INSERTED INTO arp_algos
  
  local arp_algo_name = 'Seq up-down'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  

    -- Pretty fast arps here so no shifting octave down
    params:set('arp_octave', math.max(params:get('arp_octave'), 0))

    -- Prefer longer and faster sequence
    params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * 2) -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))

    local peak = math.random(2, arp_pattern_length[arp_pattern] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_min - 1 + i
    end
    for i = 1, arp_pattern_length[arp_pattern] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] - i
    end
    
    arp_check_bounds() -- confirmed issues
  end)


  local arp_algo_name = 'Seq down-up'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
 
    -- Pretty fast arps here so no shifting octave down
    params:set('arp_octave', math.max(params:get('arp_octave'), 0))

    -- Sequence length of 6(tuplet) or 8 steps
    params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * 2) -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))

    local peak = math.random(2, arp_pattern_length[arp_pattern] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_max - 1 - i
    end
    for i = 1, arp_pattern_length[arp_pattern] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] + i
    end  
    
    arp_check_bounds() -- confirmed issues
  end)
  
  
  local arp_algo_name = 'ER 1-note'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
    
    for i = 1, #er_table do
      arp_seq[1][i] = er_table[i] and arp_root or 0
    end
    rotate_pattern('Arp', math.random(0,percent_chance(50) and 7 or 0))
  
  end)
  

  local arp_algo_name = 'ER 2-note'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
    
    for i = 1, #er_table do
      arp_seq[1][i] = er_table[i] and arp_root or arp_offset
    end
    rotate_pattern('Arp', math.random(0,percent_chance(50) and 7 or 0))
  
  end)
  
  
  local arp_algo_name = 'Strum up'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
    
    params:set('arp_mode', 2)
    params:set('arp_pp_amp',35) --Turn down amp since a lot of notes can clip
    params:set('arp_duration_index',15)
    params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * 2)

    -- Strum speed from 1/64T to 1/32T
    params:set('arp_div_index', math.random(1,5))
    
    for i = 1, arp_pattern_length[arp_pattern] do
      arp_seq[1][i] = arp_min - 1 + i
    end
    
  end)


  local arp_algo_name = 'Strum down'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  

    params:set('arp_mode', 2)
    params:set('arp_pp_amp',35) --Turn down amp since a lot of notes can clip
    params:set('arp_duration_index',15)
    params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * 2)

    -- Strum speed from 1/64T to 1/32T
    params:set('arp_div_index', math.random(1,5))
    
    for i = 1, arp_pattern_length[arp_pattern] do
      arp_seq[1][i] = arp_max - 1 - i
    end
    
  end)
  
  
  -- local arp_algo_name = 'ER seq +rests'
  -- table.insert(arp_algos['name'], arp_algo_name)
  -- table.insert(arp_algos['func'], function()
    
  --   local note_shift = 0
  --   if arp_root - er_note_on_count < 1 then
  --     for i = 1, #er_table do
  --       arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
  --       note_shift = note_shift + (er_table[i] and 1 or 0)
  --     end
  --   elseif arp_root + er_note_on_count > 14 then
  --     for i = 1, #er_table do
  --       arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
  --       note_shift = note_shift - (er_table[i] and 1 or 0)
  --     end
  --   else
  --     local direction = (arp_root + math.random() > .5 and 1 or -1)
  --     for i = 1, #er_table do    -- I don't think this is firing?
  --       arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
  --       note_shift = note_shift + (er_table[i] and direction or 0)
  --     end
  --   end
  --   arp_check_bounds() -- confirmed issues
    
  -- end)


  -- local arp_algo_name = 'ER drunk+rest'
  -- table.insert(arp_algos['name'], arp_algo_name)
  -- table.insert(arp_algos['func'], function() 

  --   local note_shift = 0
  --   for i = 1, #er_table do
  --     arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
  --     direction = math.random() > .5 and 1 or -1
  --     note_shift = note_shift + (er_table[i] and direction or 0)
  --   end
    
  -- end)


  -- local arp_algo_name = 'Seq. up'
  -- table.insert(arp_algos['name'], arp_algo_name)
  -- table.insert(arp_algos['func'], function()
  
  --   -- params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * (percent_chance(30) and 2 or 1))
  --   -- local tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
  --   -- -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
  --   -- if params:get('clock_tempo') < 80 then
  --   --   params:set('arp_div_index', math.random(2,3) * 2 - tuplet_shift)
  --   -- elseif params:get('clock_tempo') < 100 then
  --   --   params:set('arp_div_index', math.random(3,4) * 2 - tuplet_shift)
  --   -- elseif params:get('clock_tempo') < 120 then
  --   --   params:set('arp_div_index', math.random(4,5) * 2 - tuplet_shift)
  --   -- else
  --   --   params:set('arp_div_index', math.random(5,6) * 2 - tuplet_shift)
  --   -- end
    
  --   -- -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
  --   -- params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    
  --   for i = 1, arp_pattern_length[arp_pattern] do
  --     arp_seq[1][i] = arp_min - 1 + i
  --   end
    
  -- end)


  local arp_algo_name = 'Seq. down'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
  
    -- params:set('arp_pattern_length_' .. arp_pattern, math.random(3,4) * (percent_chance(30) and 2 or 1))
    -- tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    -- params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    -- params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    
    for i = 1, arp_pattern_length[arp_pattern] do
      arp_seq[1][i] = arp_max + 1 - i
    end
    
  end)


  local arp_algo_name = 'Dual seq'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
  
    -- 8 or 6(tuplet) length
    local length = math.random(3,4) * 2
    params:set('arp_pattern_length_' .. arp_pattern, length)
    local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16 to 1/4 standard or tuplet
    params:set('arp_div_index', (math.random(3,5) * 2) - tuplet_shift)
    -- Whole note duration seems nice here?
    params:set('arp_duration_index', div_to_index('1'))
  
    -- Lines originate from the first/last 7 notes on the grid. Can overlap.
    local arp_min = math.random(1,7)
    local arp_max = math.random(11,14)
    
    local x = math.random(1,2)
    for i = 1, length/2  do
      arp_seq[1][i*2 - 1] = arp_min - 1 + i * x
    end
  
    local x = math.random(1,2)
    for i = 1, length/2  do
      arp_seq[1][i*2 - 1 + 1] = arp_max + 1 - i * x
    end

    arp_check_repeats()
    
    -- local x1 = math.random(1,2)
    -- local x2 = math.random(1,2)
    -- for i = 1, length / 2 do
    --   arp_seq[1][i*2 - 1] = arp_min - 1 + i * x1
    --   if arp_seq[1][i*2 - 1] == arp_seq[1][i*2 - 2] then
    --     print('dual seq repeat')
    --     arp_seq[1] = {0,0,0,0,0,0}
    --     load(arp_algos['func'][arp_algo])
    --     break
    --   end
      
    --   arp_seq[1][i*2 - 1 + 1] = arp_max + 1 - i * 2
    --   if arp_seq[1][i*2 - 1 + 1] == arp_seq[1][i*2 - 1] then
    --     print('dual seq repeat')
    --     arp_seq[1] = {}
    --     load(arp_algos['func'][arp_algo])
    --     break
    --   end
    -- end
    

    
      -- load(arp_algos['func'][chord_algo])

    -- pass = false
    -- while pass == false do
    --   local x = math.random(1,2)
    --   for i = 1, length/2  do
    --     arp_seq[1][i*2 - 1 + 1] = arp_max + 1 - i * x
    --     -- pass = arp_seq[1][i + 1] == arp_seq[1] and false or true
    --     if arp_seq[1][i*2 - 1 + 1] == arp_seq[1][i*2 - 1] then
    --       print('failed')
    --       pass = false
    --     else
    --       pass = true
    --     end
    --   if pass == false then break end
    --   end
    -- end
    
    -- if arp_max + 1 - i * x == arp_seq[1][i*2 - 1]
    
    -- tab.print(arp_seq[1])
    
    -- if arp_seq[1][1] < 7 then
    --   print('reroll')
    --   local x = math.random(1,2)
    --     for i = 1, length/2  do
    --       arp_seq[1][i*2 - 1 + 1] = arp_max + 1 - i * x
    --     end
    -- end


  end)
  
  
  -- local arp_algo_name = 'Rnd. +ER rest'
  -- table.insert(arp_algos['name'], arp_algo_name)
  -- table.insert(arp_algos['func'], function()  
    
  --   for i = 1, length do
  --     arp_seq[1][i] = math.random(1,7) + random_note_offset
  --   end
  --   if percent_chance(60) then --add some rests to the arp
  --     for i = 1, length do
  --       arp_seq[1][i] = er_table[i] and arp_seq[1][i] or 0
  --     end
  --   end
  
  -- arp_check_repeats()
  
  -- end)


  -- Set the arp pattern  
  if mode == 'run' then
    -- Clear pattern.
    for i = 1,8 do
      arp_seq[1][i] = 0
    end
    
  -- arp_generator index 1 is reserved for Randomize, otherwise fire the selected algo.
    arp_algo = params:get('arp_generator') == 1 and math.random(2,#arp_algos['name']) or params:get('arp_generator')
    print('Arp algo: ' .. arp_algos['name'][arp_algo])
    load(arp_algos['func'][arp_algo])
  end
end


--utility functions
-----------------------------------------------------------------
--builds a lookup table of chord types: aug/dim etc...
function build_mode_chord_types()
    mode_chord_types = {}
    safe_chord_degrees = {}    
    for i = 1,7 do
      local chord_type = get_chord_name(2, params:get('mode'), musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][i])
      mode_chord_types[i] = chord_type
      if chord_type == 'maj' or chord_type == 'min' then table.insert(safe_chord_degrees, i) end
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


-- checks arp pattern for out-of-bound notes
-- if found, wipe pattern and rerun algo
-- don't hate the player- hate. the. game.
function arp_check_bounds()   
  error_check = false
  local length = arp_pattern_length[arp_pattern]
  for i = 2, length do
    if arp_seq[1][i] < 0 or arp_seq[1][i] > 14 then
      error_check = true
      print('off-grid note on row ' .. i)
      break
    end
  end
  if error_check then
    print('clearing')
    clear_arp(arp_pattern)
    print('rerolling')
    load(arp_algos['func'][arp_algo])
  end
end


-- checks arp pattern for repeat notes
-- if found, wipe pattern and rerun algo
function arp_check_repeats()   
  error_check = false
  local length = arp_pattern_length[arp_pattern]
  for i = 2, length do
    if arp_seq[1][i] == arp_seq[1][i - 1] then
      error_check = true
      -- print('repeat on row ' .. i)
      break
    end
  end
  if error_check then
    -- print('clearing')
    clear_arp(arp_pattern)
    -- print('rerolling')
    load(arp_algos['func'][arp_algo])
  end
end


function clear_arp(pattern)
  for i = 1, arp_pattern_length[pattern] do
    arp_seq[1][i] = 0
  end
end




-----------------------------------------------------------------