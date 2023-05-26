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
  -- May be overwritten depending on algo type
  params:set('chord_pp_amp', 50)
  params:set('chord_pp_gain', math.random(0,350))
  params:set('chord_pp_pw', math.random(10,90))
  params:set('chord_div_index', 15)
  params:set('chord_duration_index', params:get('chord_div_index'))
  

-- sketchy_chords = false  -- reset this once per generator
chord_reroll_attempt = 0  -- same

chord_generator('run')


if sketchy_chords == true then
    
  while (chord_reroll_attempt < 100) == true do
  
    chord_reroll_attempt = chord_reroll_attempt + 1
    -- print('Sketchy chords. Reroll attempt ' .. chord_reroll_attempt .. ', Mode ' .. params:get('mode'))
      chord_generator('run')
      -- load(chord_algos['func'][chord_algo])
      
      
    -- for i = 1, pattern_length[pattern] do
    --   if chord_seq[pattern][i].c > 0 then
    --     local chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_seq[pattern][i].c]
    --     -- chord_check[i] = get_chord_name(2, params:get('mode'), chord_degree)
    --     if get_chord_name(2, params:get('mode'), chord_degree) == 'dim' then
    --       sketchy_chords = true
    --     end
    --   end
    -- end
  
  end
  if chord_reroll_attempt <100 then
    print('Mode ' .. params:get('mode') .. ' passed ' .. chord_algos['name'][chord_algo] .. ' after ' .. chord_reroll_attempt .. ' attempts')
    chord_reroll_attempt = 0
  else
  print(chord_reroll_attempt .. ' reroll attempts. Exclude mode ' .. params:get('mode') .. ' from ' .. chord_algos['name'][chord_algo])
    params:set('mode', math.random(1,9))
    chord_reroll_attempt = 0
    print('Trying with mode ' .. params:get('mode'))
    generator()

  end
end
  
print('Chord algo: ' .. chord_algos['name'][chord_algo])
arp_generator('run')
grid_redraw()
redraw()
end


-- Hacky stripped-down version of full chord+arp generator to be used for Events and Chord grid view gen
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
  

-- sketchy_chords = false  -- reset this once per generator
chord_reroll_attempt = 0  -- same

chord_generator('run')


if sketchy_chords == true then
    
  while (chord_reroll_attempt < 100) == true do
    chord_reroll_attempt = chord_reroll_attempt + 1
      chord_generator('run')
  end
  
  if chord_reroll_attempt <100 then
    print('Mode ' .. params:get('mode') .. ' passed ' .. chord_algos['name'][chord_algo] .. ' after ' .. chord_reroll_attempt .. ' attempts')
    chord_reroll_attempt = 0
  else
  print(chord_reroll_attempt .. ' reroll attempts. Exclude mode ' .. params:get('mode') .. ' from ' .. chord_algos['name'][chord_algo])
    params:set('mode', math.random(1,9))
    chord_reroll_attempt = 0
    print('Trying with mode ' .. params:get('mode'))
    -- chord_generator('run')
    -- generator()
    chord_generator_lite()
  end
end
  
print('Chord algo: ' .. chord_algos['name'][chord_algo])
-- arp_generator('run')
grid_redraw()
redraw()
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
    print('--------')
    print('mode ' .. params:get('mode') .. ' chord types')    
    tab.print(mode_chord_types)
    print('--------')
    -- print('safe chords')    
    -- tab.print(safe_chord_degrees)
    -----------------------------------------------------------------
end

-- Chance of playing higher chord degrees an octave lower
-- Anything over this is going to get transposed down an octave
function octave_split_down()
  local split = math.random(9,14)
  for i = 1,4 do
    local x = progression[i] + 7
    progression[i] = x < split and x or x - 7
  end  
end

-- -- Chance of playing lower chord degrees an octave higher
-- -- Anything under this split is going to get transposed up an octave
-- local split = math.random(1,7)
-- for i = 1,4 do
--   local x = progression[i]
--   progression[i] = x < split and x or x - 7
-- end  
-----------------------------------------------------------------
    

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


  -- ARP ALGOS LISTED BELOW ARE INSERTED INTO chord_algos
  
  local chord_algo_name = '4-passing'
  -- Rules:
  -- 4 chords
  -- Don't start with a dim or aug chord
  -- Aug and dim chords are used as 'passing chords', resulting in the following chord being +/- one degree, respectively
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()      
    
    pattern_length[pattern] = 4
    build_mode_chord_types()
    progression_valid = false
    local progression = {}
    
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
            print('reroll')
          else
            progression_valid = true
          end
        end
      end
    end
    
    -- since this is one of the rare algos that can result in an x value <1, transpose up an octave with a chance of knocking some chords down an octave
    local split = math.random(8,14)
    for i = 1,4 do
      local x = progression[i] + 7
      progression[i] = x < split and x or x - 7
    end  

    -- pattern will be shifted up an octave since x < 1 is valid
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor((x) / 8) --octave
    end  
    
    -- transpose_pattern(7)    
    
    -- rotate_pattern('Chord', math.random(0, 3))
    -- transpose_pattern(math.random() >= .5 and 7 or 0)    

  -- todo: split octaves
  end)
  
  
  local chord_algo_name = 'I-V-vi-IV'
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()  
    
    local modes = {1,2,3,8}  -- Verified as modes not containing diminished chords
    params:set('mode', modes[math.random(1,4)])
    local progression = {1,5,6,4}
    pattern_length[pattern] = 4
    
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    rotate_pattern('Chord', math.random(0, 3))
    transpose_pattern(math.random() >= .5 and 7 or 0)
  end) 

  
  local chord_algo_name = 'I-vi based'
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()      
    
    -- exclusions: 2, 3, 4, 6, 7, 8, 9
    -- OK at least once: 1, 5, 9
    
    -- local modes = {1,5,6,7,9} --Preferred but kinda optional. Check this again.
    -- params:set('mode', 1) -- modes[math.random(1,4)])
    local progression = {1,2,3,4,5,6}
    local progression = shuffle(progression)
    pattern_length[pattern] = 4
    -- 
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    rotate_pattern('Chord', math.random(0, 3))
    transpose_pattern(math.random() >= .5 and 7 or 0)    

  end) 


  local chord_algo_name = 'I-vi stagger'
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()      

    -- All modes are pretty okay here but setting to triads only
    -- params:set('mode', math.random(1, 9))
    params:set('chord_type', 3)
    
    local first = math.random(1,6)
    local second = util.wrap(first + math.random(1,5), 1, 6)
    local offset = first - second
    local third = offset > 0 and math.random(1 + offset, 6) or math.random(1, 6 + offset)
    local fourth = third - offset
    local progression = {first, second, third, fourth}

    pattern_length[pattern] = 4
    
    for i = 1, pattern_length[pattern] do
      local x = progression[i]
      chord_seq[pattern][i].x = x --raw key x coordinate
      chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
      chord_seq[pattern][i].o = math.floor(x / 8) --octave
    end  
    
    -- Reroll if it's repeating.
    if second == third or first == third then
      load(chord_algos['func'][chord_algo])
    end
    
  end) 
  
  -- local chord_algo_name = 'Weird'
  -- table.insert(chord_algos['name'], chord_algo_name)
  -- table.insert(chord_algos['func'], function()      
    
  --   local random_pattern_lengths = {3,4,6,8}
  --   -- Mostly 4-chord paternt, chance of others
  --   pattern_length[pattern] = random_pattern_lengths[2 + (percent_chance(20) and math.random(-1,2) or 0)]
  --   local random_chord_offset = math.random (0,7)
  --   for i = 1, 8 do
  --     chord_seq[pattern][i].x = 0
  --     chord_seq[pattern][i].c = 0
  --     chord_seq[pattern][i].o = 0
  --   end
  --   for i = 1, pattern_length[pattern] do
  --     local random_1_14 = math.random(1,7) + random_chord_offset
  --     chord_seq[pattern][i].x = random_1_14 --raw key x coordinate
  --     chord_seq[pattern][i].c = util.wrap(random_1_14, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][i].o = math.floor(random_1_14 / 8) --octave
  --   end
    
  --   if random_pattern_length > 4 and percent_chance(90) then  --Repeat the first half of 6/8-chord patterns
  --     local half_random_pattern_length = random_pattern_length / 2
  --     for i = 1, random_pattern_length / 2 do
  --       chord_seq[pattern][i + half_random_pattern_length].x = chord_seq[pattern][i].x
  --       chord_seq[pattern][i + half_random_pattern_length].c = chord_seq[pattern][i].c
  --       chord_seq[pattern][i + half_random_pattern_length].o = chord_seq[pattern][i].o
  --     end
  --     -- Modify the last chord of the pattern. Kinda cheesy.
  --     local random_1_14 = math.random(0,7) + random_chord_offset
  --     chord_seq[pattern][random_pattern_length].x = random_1_14 --raw key x coordinate
  --     chord_seq[pattern][random_pattern_length].c = util.wrap(random_1_14, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][random_pattern_length].o = math.floor(random_1_14 / 8) --octave
  --   end
  
  -- end)


  local chord_algo_name = 'I-vi 2-chord'
  table.insert(chord_algos['name'], chord_algo_name)
  table.insert(chord_algos['func'], function()  
    
    params:set('chord_div_index', div_to_index('1/4'))
    pattern_length[pattern] = 8
    -- local modes = {1} -- to-do: see what other modes work well
    -- params:set('mode', modes[math.random(1,#modes)])
    local progression = {1,2,3,4,5,6}
    local progression = shuffle(progression)
    
    -- Transposes a value up an octave if the split is too wide.
    progression[2] = progression[2] + ((progression[1] - progression[2] > 3) and 7 or 0)
    progression[1] = progression[1] + ((progression[2] - progression[1] > 3) and 7 or 0)
    
    local x = progression[1]
    chord_seq[pattern][1].x = x --raw key x coordinate
    chord_seq[pattern][1].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
    chord_seq[pattern][1].o = math.floor(x / 8) --octave
    local x = progression[2]
    chord_seq[pattern][5].x = x --raw key x coordinate
    chord_seq[pattern][5].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
    chord_seq[pattern][6].o = math.floor(x / 8) --octave

 end)   


  -- local chord_algo_name = 'Circle'
  -- table.insert(chord_algos['name'], chord_algo_name)
  -- table.insert(chord_algos['func'], function()  
    
  --   -- vi-ii-V-I based circle progression ***
  --   -- keeps ii–V–I turnaround at the end with random pattern length
  --   local modes = {1}
  --   params:set('mode', modes[math.random(1,#modes)])
  --   local progression = {1,5,6,4}
  --   local progression = {8,4,7,3,6,2,5,1}
  --   local swappable_index_iii = {1,2,6,7,8} --Spots we might swap in a iii (avoiding repeat iii chords)
  --   local swappable_index_v = {1,2,3,4,5}   --Spots we might swap in a V (avoiding repeat V chords)
  --   -- Chance of adding a iii and V
  --   local chord_index = swappable_index_iii[math.random(1,4)]
  --   progression[chord_index] = percent_chance(50) and 3 or progression[chord_index]
  --   local chord_index = swappable_index_v[math.random(1,4)]
  --   progression[chord_index] = percent_chance(50) and 5 or progression[chord_index]
  --   pattern_length[pattern] = math.random(2,4) * 2
    
  --   for i = 1, pattern_length[pattern] do
  --     local x = progression[i + (8 - pattern_length[pattern])]
  --     chord_seq[pattern][i].x = x --raw key x coordinate
  --     chord_seq[pattern][i].c = util.wrap(x, 1, 7) --chord 1-7 (no octave)
  --     chord_seq[pattern][i].o = math.floor(x / 8) --octave
  --   end  
  --   -- 50% chance of rotating to end on I−vi−ii−V turnaround
  --   if percent_chance(50) then
  --     rotate_pattern('Chord', math.random() >= .5 and 1 or 0)
  --     -- optional octave shift of first chord. Doesn't really sound better IMO.
  --     -- if chord_seq[pattern][1].x == 1 then
  --     --   chord_seq[pattern][1].x = 8 --raw key x coordinate
  --     --   chord_seq[pattern][1].c = 1 --chord 1-7 (no octave)
  --     --   chord_seq[pattern][1].o = 1 --octave 
  --     -- end
  --   end
    
  -- end)


  -- Set the chord pattern if not mode == 'init'
  if mode == 'run' then
    clear_chord_pattern()
  -- chord_generator index 1 is reserved for Randomize, otherwise fire the selected algo. Non-local for rerolls.
    chord_algo = params:get('chord_generator') == 1 and math.random(2,#chord_algos['name']) or params:get('chord_generator')
    load(chord_algos['func'][chord_algo])

    sketchy_chords = false  -- reset this

    -- FLAGS sketchy_chords IF THERE IS A DIMINISHED CHORD BECAUSE THERE IS A HIGH PROBABILITY OF IT SOUNDING NASTY
    -- This needs to be refactored with better chord name/degree/type lookup functions, and made to run only on certain algos prob
    -- for i = 1, pattern_length[pattern] do
    --   if chord_seq[pattern][i].c > 0 then
    --     local chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_seq[pattern][i].c]
    --     if get_chord_name(2, params:get('mode'), chord_degree) == 'dim' 
    --     or get_chord_name(2, params:get('mode'), chord_degree) == 'aug' then
    --       sketchy_chords = true
    --     end
    --   end
    -- end
    -- do_filter_sketchy_chords = false  -- determines if we screen for aug/dim chords
    if do_filter_sketchy_chords == true then filter_sketchy_chords() end
  end
end -- of chord_generator

--FLAGS sketchy_chords IF THERE IS A DIMINISHED CHORD BECAUSE THERE IS A HIGH PROBABILITY OF IT SOUNDING NASTY
--This needs to be refactored with better chord name/degree/type lookup functions
function filter_sketchy_chords()
    for i = 1, pattern_length[pattern] do
      if chord_seq[pattern][i].c > 0 then
        local chord_degree = musicutil.SCALE_CHORD_DEGREES[params:get('mode')]['chords'][chord_seq[pattern][i].c]
        if get_chord_name(2, params:get('mode'), chord_degree) == 'dim' 
        or get_chord_name(2, params:get('mode'), chord_degree) == 'aug' then
          sketchy_chords = true
        end
      end
    end
end

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
    local er_note_on_count = er_note_on_count + (er_table[i] and 1 or 0) -- made er_note_on_count local. Dis work?
  end

  -- Pre-randomizations which can be overwritten by the individual algorithms
  -- This step is omitted when running init (used to populate algo table for menus)
  if mode == 'run' then
    -- Pattern/session randomizations
    arp_pattern_length[arp_pattern] = length
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
    arp_pattern_length[arp_pattern] = math.random(3,4) * 2 -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    print(params:get('clock_tempo') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    local peak = math.random(2, arp_pattern_length[arp_pattern] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_min - 1 + i
    end
    for i = 1, arp_pattern_length[arp_pattern] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] - i
    end
    
  end)


  local arp_algo_name = 'Seq down-up'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
 
    -- Pretty fast arps here so no shifting octave down
    params:set('arp_octave', math.max(params:get('arp_octave'), 0))

    -- Sequence length of 6(tuplet) or 8 steps
    arp_pattern_length[arp_pattern] = math.random(3,4) * 2 -- 6 (tuplet) or 8 length
    tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set('arp_div_index', (math.random(3,4) * 2) - tuplet_shift - (params:get('clock_tempo') < 85 and 2 or 0))
    
    -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    -- print(params:get('clock_tempo') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    local peak = math.random(2, arp_pattern_length[arp_pattern] - 1)
    for i = 1, peak do
      arp_seq[1][i] = arp_max - 1 - i
    end
    for i = 1, arp_pattern_length[arp_pattern] - peak do
      arp_seq[1][i + peak] = arp_seq[1][peak] + i
    end  
    
  end)
  
  
  local arp_algo_name = 'ER 1-note'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
    
    for i = 1, #er_table do
      arp_seq[1][i] = er_table[i] and arp_root or 0
    end
    rotate_pattern('Arp', math.random(0,percent_chance(50) and 7 or 0))
    
  end)
  

  local arp_algo_name = 'Strum up'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
    
    params:set('arp_mode', 2)
    params:set('arp_pp_amp',35) --Turn down amp since a lot of notes can clip
    params:set('arp_duration_index',15)
    arp_pattern_length[arp_pattern] = math.random(3,4) * 2

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
    arp_pattern_length[arp_pattern] = math.random(3,4) * 2

    -- Strum speed from 1/64T to 1/32T
    params:set('arp_div_index', math.random(1,5))
    
    for i = 1, arp_pattern_length[arp_pattern] do
      arp_seq[1][i] = arp_max - 1 - i
    end
    
  end)
  
  
  local arp_algo_name = 'ER seq +rests'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
    
    local note_shift = 0
    if arp_root - er_note_on_count < 1 then
      for i = 1, #er_table do
        arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
        note_shift = note_shift + (er_table[i] and 1 or 0)
      end
    elseif arp_root + er_note_on_count > 14 then
      for i = 1, #er_table do
        arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
        note_shift = note_shift - (er_table[i] and 1 or 0)
      end
    else
      local direction = (arp_root + math.random() > .5 and 1 or -1)
      for i = 1, #er_table do    -- I don't think this is firing?
        arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
        note_shift = note_shift + (er_table[i] and direction or 0)
      end
    end
    
  end)


  local arp_algo_name = 'ER drunk+rest'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function() 

    local note_shift = 0
    for i = 1, #er_table do
      arp_seq[1][i] = er_table[i] and (arp_root + note_shift) or 0
      direction = math.random() > .5 and 1 or -1
      note_shift = note_shift + (er_table[i] and direction or 0)
    end
    
  end)


  local arp_algo_name = 'Seq. up'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()
  
    -- arp_pattern_length[arp_pattern] = math.random(3,4) * (percent_chance(30) and 2 or 1)
    -- local tuplet_shift = (arp_pattern_length[arp_pattern] / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) arp pattern length
    
    -- -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    -- if params:get('clock_tempo') < 80 then
    --   params:set('arp_div_index', math.random(2,3) * 2 - tuplet_shift)
    -- elseif params:get('clock_tempo') < 100 then
    --   params:set('arp_div_index', math.random(3,4) * 2 - tuplet_shift)
    -- elseif params:get('clock_tempo') < 120 then
    --   params:set('arp_div_index', math.random(4,5) * 2 - tuplet_shift)
    -- else
    --   params:set('arp_div_index', math.random(5,6) * 2 - tuplet_shift)
    -- end
    
    
    -- -- Duration from min of the arp_div to +4 arp_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    -- params:set('arp_duration_index',math.max(math.random(params:get('arp_div_index'), params:get('arp_div_index') + 4), 5))
    
    -- print(params:get('clock_tempo') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    
    for i = 1, arp_pattern_length[arp_pattern] do
      arp_seq[1][i] = arp_min - 1 + i
    end
    
  end)


  local arp_algo_name = 'Seq. down'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
  
    -- arp_pattern_length[arp_pattern] = math.random(3,4) * (percent_chance(30) and 2 or 1)
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
  arp_pattern_length[arp_pattern] = length
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
  -- for i = 1, length do
    arp_seq[1][i*2 - 1] = arp_min - 1 + i * x
  end

  local x = math.random(1,2)
  for i = 1, length/2  do
  -- for i = 1, length do
    arp_seq[1][i*2 - 1 + 1] = arp_max + 1 - i * x
  end
  
  end)
  
  
  local arp_algo_name = 'Rnd. +ER rest'
  table.insert(arp_algos['name'], arp_algo_name)
  table.insert(arp_algos['func'], function()  
    
    for i = 1, length do
      arp_seq[1][i] = math.random(1,7) + random_note_offset
    end
    if percent_chance(60) then --add some rests to the arp
      for i = 1, length do
        arp_seq[1][i] = er_table[i] and arp_seq[1][i] or 0
      end
    end
    
  end)


  -- Set the arp pattern  
  if mode == 'run' then
    -- Clear pattern.
    for i = 1,8 do
      arp_seq[1][i] = 0
    end
    
  -- arp_generator index 1 is reserved for Randomize, otherwise fire the selected algo.
    local arp_algo = params:get('arp_generator') == 1 and math.random(2,#arp_algos['name']) or params:get('arp_generator')
    print('Arp algo: ' .. arp_algos['name'][arp_algo])
    print(params:get('clock_tempo') .. ' ' .. params:get('arp_div_index') .. ' ' .. divisions_string(params:get('arp_div_index')) .. ' ' .. divisions_string(params:get('arp_duration_index')))
    load(arp_algos['func'][arp_algo])
  end
end