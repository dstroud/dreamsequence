local er = require("er")
local max_seqs = 3
local max_seq_cols = 15 - max_seqs

function init_generator()
  chord_reroll_attempt = 0
  chord_generator("init")
  seq_generator("init")
end


function generator()

  params:set("chord_octave", math.random(-1,0))
  params:set("seq_octave_"..selected_seq_no, math.random(-1,1))
    
  --SEQUENCE RANDOMIZATION
  params:set("tonic", math.random(-6,6))

  if params:get("clock_source") == 1 then 
    params:set("clock_tempo", math.random(50,140))
  end
  
  params:set("scale", math.random(1, 9)) -- Currently this is called each time c-gen runs, but might change this
  -- not really the best option but this is what the OG algos were built around
  set_param_string("seq_start_on_"..selected_seq_no, "Loop")
  set_param_string("seq_reset_on_"..selected_seq_no, "Measure")

  params:set("seq_note_map_"..selected_seq_no, math.random(1, 2))
  params:set("chord_div_index", 15)
  params:set("chord_duration_index", params:get("chord_div_index"))

  chord_generator("run")
  print("Chord algo: " .. chord_algos["name"][chord_algo])
  seq_generator("run")
  grid_redraw()
  redraw()
end


-- Hacky stripped-down version of full chord+seq generator to be used for Events and Chord grid view gen
-- Why does this exist? I don't remember.
function chord_generator_lite()
  params:set("chord_octave", math.random(-1,0))
    
  --SEQUENCE RANDOMIZATION
  params:set("tonic", math.random(-6,6))

  if params:get("clock_source") == 1 then 
    params:set("clock_tempo", math.random(50,140))
  end
  
  params:set("scale", math.random(1,9))
  params:set("chord_div_index", 15)
  params:set("chord_duration_index", params:get("chord_div_index"))
  
  chord_generator("run")
  print("Chord algo: " .. chord_algos["name"][chord_algo])
  grid_redraw()
  -- gen_dash("chord_generator_lite")
  redraw()
end


function chord_generator(mode)
  -- Some common random ranges that will be re-rolled for the Seq section
  -- local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  -- local random_1_7 = math.random(1,7)
  -- local random_4_11 = math.random(4,11)
  -- local random_1_14 = math.random(1,14)
  
  -- Table containing chord algos. This runs at init as well.
  chord_algos = {name = {}, func = {}}
  -- Index 1 reserved for Random
  table.insert(chord_algos["name"], "Random")
  table.insert(chord_algos["func"], "Random")


  -- ALGOS LISTED BELOW ARE INSERTED INTO chord_algos. Eventually these will be moved into individual files I think.
  local chord_algo_name = "4-passing"
  -- Don't start with a dim or aug chord
  -- Aug and dim chords are used as "passing chords" so a dim chord will be followed by a chord one degree down, and an aug will be followed by a chord one degree up.
  table.insert(chord_algos["name"], chord_algo_name)
  table.insert(chord_algos["func"], function()
    params:set("chord_pattern_length", 4)
    build_mode_chord_types()
    progression_valid = false
    progression = {}
    while progression_valid == false do
      for i = 1,4 do
        if i == 1 then
          -- Pick a "safe" chord (not dim or aug) for the first chord in the pattern
          table.insert(progression, safe_chord_degrees[math.random(1,#safe_chord_degrees)])
        else
          local prev_chord_type = mode_chord_types[util.wrap(progression[i-1],1,7)] -- wrapped since we can get values <1
          if prev_chord_type == "dim" then
            table.insert(progression, progression[i-1] - 1)
          elseif prev_chord_type == "aug" then  
            table.insert(progression, progression[i-1] + 1)
          else
            table.insert(progression, math.random(1,7))
          end  
        end
        
      -- If the last chord is dim or aug, wrap around and set the first chord +/- 1
      -- This works for everything except Melodic Minor which can result in chord 4 being a vii dim and thus chord 1 being a vi dim
        if i == 4 then
          if mode_chord_types[progression[4]] == "dim" then
            progression[1] = progression[4] - 1
          elseif mode_chord_types[progression[4]] == "aug" then
            progression[1] = progression[4] + 1
          end
          -- one final check to see if the 1st chord is a dim which should be rare and will just result in a reroll
          local prev_chord_type = mode_chord_types[util.wrap(progression[1],1,7)] -- wrapped since we can get values <1
          if prev_chord_type == "dim" or prev_chord_type == "aug" then
            progression = {}
            progression_valid = false
            -- print("reroll")
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
    --   print("double_space")
    --   double_space()
    -- end
    
  end)


  local chord_algo_name = "I-vi stagger"
  -- Preserves relationship between chords 1 and 2 and applies this to chords 3 and 4
  -- Runs until there are no aug/dims which is pretty inefficient. Should refactor when I am feeling more smart
  -- Still seeing the occasional aug/dim slip through but I have no idea how
  table.insert(chord_algos["name"], chord_algo_name)
  table.insert(chord_algos["func"], function()      

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
      if (this_type == "aug") or (this_type == "dim") then
        -- print("reroll")
        reroll = true
      end
    end
    if reroll == true then
      load(chord_algos["func"][chord_algo])
    end
      
    params:set("chord_pattern_length", 4)
    for i = 1, chord_pattern_length[active_chord_pattern] do
      local x = progression[i]
      chord_pattern[active_chord_pattern][i] = x
    end
    
    -- IDK may as well mix it up
    -- this causes some infinite loop that is bad news. Come back to it.
    -- if math.random() < .5 then
    --   print("double_space")
    --   double_space()
    -- end
    
  end)


  local chord_algo_name = "2-chord+"
  -- 2 chords with adjusted step length for possibility of embellishment chords
  table.insert(chord_algos["name"], chord_algo_name)
  table.insert(chord_algos["func"], function()  
    
    params:set("chord_div_index", div_to_index("1/4"))
    params:set("chord_pattern_length", 8)
    
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
    if (progression[1] < 14) and mode_chord_types[util.wrap(progression[1], 1, 7) + 1] == "dim" and math.random() <.25 then
      chord_pattern[active_chord_pattern][4] = x
      chord_pattern[active_chord_pattern][8] = x
      local x = progression[1] + 1
      chord_pattern[active_chord_pattern][position] = x
    elseif (progression[1] >1) and mode_chord_types[util.wrap(progression[1], 1, 7) - 1] == "aug"  and math.random() <.25 then
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
  
  
  -- Set the chord pattern if not mode == "init"
  if mode == "run" then
    clear_chord_pattern()
  -- chord_generator index 1 is reserved for Randomize, otherwise fire the selected algo. Non-local for rerolls.
    chord_algo = params:get("chord_generator") == 1 and math.random(2,#chord_algos["name"]) or params:get("chord_generator")
    load(chord_algos["func"][chord_algo])
  end
end 
---------- end of chord_generator --------------


-- SEQ GENERATOR
function seq_generator(mode)
  
  -- local min_div_index = util.round(0.0375 * params:get("clock_tempo") + 0.75)
  local min_div_index = util.round(0.025 * params:get("clock_tempo") + 1.5)
  local max_div_index = util.round(0.0375 * params:get("clock_tempo") + 6.75)
  local div = math.random(min_div_index, max_div_index)
  local tuplet_shift = div % 2  -- even or odd(tuplets) seq pattern length
  local length = (4 - tuplet_shift) * (percent_chance(70) and 2 or 1)
  
  -- if params:get("clock_tempo") < 80 then
  -- local div = math.random(2,3) * 2 - tuplet_shift
  -- elseif params:get("clock_tempo") < 100 then
  -- local div =  math.random(3,4) * 2 - tuplet_shift
  -- elseif params:get("clock_tempo") < 120 then
  --   local div =  math.random(4,5) * 2 - tuplet_shift
  -- else
  --   local div =  math.random(5,6) * 2 - tuplet_shift
  -- end
    
  -- 50% chance of the seq note map including 7th notes
  local seq_note_map = math.random(1, 2) --percent_chance(50) and 1 or 2

  -- Commonly-used random values

  local seq_min = math.random(1, math.floor(max_seq_cols / 2))
  local seq_max = math.random(math.ceil(max_seq_cols / 2) + (max_seq_cols % 2 == 0 and 1 or 0), max_seq_cols)
  -- local random_1_3 = math.random(1,3) * math.random(0,1) and -1 or 1
  -- local random_1_7 = math.random(1,7)
  -- local random_4_11 = math.random(4,11)   --seq note distribution center
  -- local random_1_14 = math.random(1,14)  
  -- local random_note_offset = math.random (0,7)
  local seq_root = math.random(seq_min, seq_max)  -- made local
  local seq_offset = util.wrap(seq_root + math.random(1, seq_max - seq_min), seq_min, seq_max)
  
  -- Generate Euclydian rhythm
  local er_table = {}
  er_table = er.gen(math.random(1, math.max(1,length - 1)), length, 0) --pulses, steps, shift  -- max pulses?
  local er_note_on_count = 0
  for i = 1, #er_table do
    er_note_on_count = er_note_on_count + (er_table[i] and 1 or 0)
  end

  -- Pre-randomizations which can be overwritten by the individual algorithms
  -- This step is omitted when running init (used to populate algo table for menus)
  if mode == "run" then
    params:set("seq_grid_"..selected_seq_no, 1) -- for now, only does mono seq
    -- clear_seq(selected_seq_no) -- moving this into each algo instead
    -- Pattern/session randomizations
    params:set("seq_pattern_length_" .. selected_seq_no, length)
    params:set("seq_div_index_"..selected_seq_no, div)
    -- params:set("seq_duration_index_1", div)
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set("seq_duration_index_"..selected_seq_no, math.max(math.random(params:get("seq_div_index_1"), params:get("seq_div_index_1") + 4), 5))
    params:set("seq_note_map_"..selected_seq_no, seq_note_map)
    -- not really the best option but this is what the OG algos were built around. todo revisit this as they may have changed
    set_param_string("seq_start_on_"..selected_seq_no, "Loop")
    set_param_string("seq_reset_on_"..selected_seq_no, "Measure")
  end
    
  -- Table containing seq algos. This runs at init as well.
  seq_algos = {name = {}, func = {}}
  -- Index 1 reserved for Random
  table.insert(seq_algos["name"], "Random")
  table.insert(seq_algos["func"], "Random")


  -- SEQ ALGOS LISTED BELOW ARE INSERTED INTO seq_algos
  
  
  local seq_algo_name = "Seq. up" -- why no seq up??
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()  
  
    local pattern = {}
    local length = math.random(3,4) * (percent_chance(30) and 2 or 1)
    local x_origin = math.random(1, max_seq_cols - length - 1)

    params:set("seq_pattern_length_" .. selected_seq_no, length)
    tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set("seq_div_index_"..selected_seq_no, (math.random(3,4) * 2) - tuplet_shift - (params:get("clock_tempo") < 85 and 2 or 0))

    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T
    params:set("seq_duration_index_"..selected_seq_no,math.max(math.random(params:get("seq_div_index_"..selected_seq_no), params:get("seq_div_index_"..selected_seq_no) + 4), 5))

    for i = 1, length do
      pattern[i] = x_origin + i
    end

    write_seq(pattern)
    
  end)
  
  local seq_algo_name = "Seq. down"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()  
  
    local pattern = {}
    local length = math.random(3,4) * (percent_chance(30) and 2 or 1)
    local x_origin = math.random(length, max_seq_cols) + 1

    params:set("seq_pattern_length_" .. selected_seq_no, length)
    tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set("seq_div_index_"..selected_seq_no, (math.random(3,4) * 2) - tuplet_shift - (params:get("clock_tempo") < 85 and 2 or 0))

    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T
    params:set("seq_duration_index_"..selected_seq_no,math.max(math.random(params:get("seq_div_index_"..selected_seq_no), params:get("seq_div_index_"..selected_seq_no) + 4), 5))

    for i = 1, length do
      pattern[i] = x_origin - i
    end

    write_seq(pattern)
    
  end)


  local seq_algo_name = "Seq up-down"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()

    local pattern = {}
    local length = math.random(3, 4) * 2
    local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- switches lattice div to tuplet if 6 steps
    local peak_y = math.random(2, length - 1)
    local early_peak = peak_y <= (length / 2) -- whether peak of rise-fall is in first half of pattern length
    local peak_x_min

    if early_peak then -- assign trough_x val so we stay within pattern limits
      peak_x_min = length - peak_y + 1
    else
      peak_x_min = peak_y
    end

    local peak_x = math.random(peak_x_min, max_seq_cols)

    for y = 1, length do
      local x

      if y < peak_y then
        x = peak_x - (peak_y - y)
      else
        x = peak_x - (y - peak_y)
      end

      pattern[y] = x

    end

    write_seq(pattern)
    
    params:set("seq_pattern_length_" .. selected_seq_no, length) -- 6 (tuplet) or 8 length

    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set("seq_div_index_"..selected_seq_no, (math.random(3, 4) * 2) - tuplet_shift - (params:get("clock_tempo") < 85 and 2 or 0))
    
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T because 1/32 is a bit too quick for PolyPerc in most cases
    params:set("seq_duration_index_"..selected_seq_no,math.max(math.random(params:get("seq_div_index_"..selected_seq_no), params:get("seq_div_index_"..selected_seq_no) + 4), 5))

  end)


  local seq_algo_name = "Seq down-up"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()  

    local pattern = {}
    local length = math.random(3, 4) * 2
    local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- switches lattice div to tuplet if 6 steps
    local trough_y = math.random(2, length - 1)
    local early_trough = trough_y <= (length / 2) -- whether trough of fall-rise is in first half of pattern length
    local trough_x_max

    if early_trough then -- assign trough_x val so we stay within pattern limits
      trough_x_max = max_seq_cols - (length - trough_y)
    else
      trough_x_max = max_seq_cols - trough_y + 1
    end

    local trough_x = math.random(1, trough_x_max)

    for y = 1, length do
      local x

      if y < trough_y then
        x = trough_x + (trough_y - y)
      else
        x = trough_x + (y - trough_y)
      end

      pattern[y] = x

    end

    write_seq(pattern)
    
    params:set("seq_pattern_length_" .. selected_seq_no, length) -- 6 (tuplet) or 8 length

    -- 1/16T - 1/8 if >= 85bpm, 1/32T - 1/16 if under 85bpm
    params:set("seq_div_index_"..selected_seq_no, (math.random(3, 4) * 2) - tuplet_shift - (params:get("clock_tempo") < 85 and 2 or 0))
    
    -- Duration from min of the seq_div to +4 seq_div, min of 1/16T
    params:set("seq_duration_index_"..selected_seq_no,math.max(math.random(params:get("seq_div_index_"..selected_seq_no), params:get("seq_div_index_"..selected_seq_no) + 4), 5))

  end)
  
  
  local seq_algo_name = "ER 1-note"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()
    
    local pattern = {}

    for i = 1, #er_table do
      pattern[i] = er_table[i] and seq_root or 0
    end

    pattern = rotate_tab_values(pattern, math.random(0,percent_chance(50) and 7 or 0))

    write_seq(pattern)
  end)
  

  local seq_algo_name = "ER 2-note"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()
    
    local pattern = {}

    for i = 1, #er_table do
      pattern[i] = er_table[i] and seq_root or seq_offset
    end
    
    pattern = rotate_tab_values(pattern, math.random(0,percent_chance(50) and 7 or 0))

    write_seq(pattern)
  
  end)
  
  
  local seq_algo_name = "Strum up"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()  

    local pattern = {}
    local length = math.random(3, 4) * 2

    params:set("seq_octave_"..selected_seq_no, math.random(0,1))
    set_param_string("seq_start_on_"..selected_seq_no, "Every step")
    set_param_string("seq_reset_on_"..selected_seq_no, "Every step")

    params:set("seq_duration_index_"..selected_seq_no, 15)
    params:set("seq_pattern_length_" .. selected_seq_no, length)

    -- Strum speed from 1/64T to 1/32T
    params:set("seq_div_index_"..selected_seq_no, math.random(1,5))
    
    for i = 1, length do
      pattern[i] = seq_min - 1 + i
    end
    
    write_seq(pattern)

  end)


  local seq_algo_name = "Strum down"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()

    local pattern = {}
    local length = math.random(3, 4) * 2

    params:set("seq_octave_"..selected_seq_no, math.random(0,1))
    set_param_string("seq_start_on_"..selected_seq_no, "Every step")
    set_param_string("seq_reset_on_"..selected_seq_no, "Every step")

    params:set("seq_duration_index_"..selected_seq_no, 15)
    params:set("seq_pattern_length_" .. selected_seq_no, length)

    -- Strum speed from 1/64T to 1/32T
    params:set("seq_div_index_"..selected_seq_no, math.random(1,5))
    
    for i = 1, length do
      pattern[i] = seq_max - 1 - i
    end
    
    write_seq(pattern)
    
  end)


  local seq_algo_name = "Dual seq"
  table.insert(seq_algos["name"], seq_algo_name)
  table.insert(seq_algos["func"], function()
  
    local pattern = {}
    local length = math.random(3, 4) * 2 -- 8 or 6(tuplet) length
    params:set("seq_pattern_length_" .. selected_seq_no, length)
    local tuplet_shift = (length / 2) % 2 == 0 and 0 or 1 -- even or odd(tuplets) seq pattern length
    
    -- 1/16 to 1/4 standard or tuplet
    params:set("seq_div_index_"..selected_seq_no, (math.random(3, 5) * 2) - tuplet_shift)
    -- Whole note duration seems nice here?
    params:set("seq_duration_index_"..selected_seq_no, div_to_index("1"))
  
    -- Lines originate from the each side of the grid and overlap
    local seq_min = math.random(1, 6)
    local seq_max = math.random(max_seq_cols - 4, max_seq_cols) -- leave room to shift this line left one step
    local do_shift = false
    local slope_1 = math.random(1, 2)
    local slope_2 = math.random(1, 2)

    local function gen_pattern()
      for i = 1, length / 2  do
        local y = i * 2 - 1
        local x_1 = seq_min - 1 + i * slope_1
        local x_2 = seq_max + 1 - i * slope_2

        if x_1 == x_2 or (y > 2 and x_1 == pattern[y - 1]) then
          do_shift = true
          break
        end

        pattern[y] = x_1
        pattern[y + 1] = x_2
      end
    end

    gen_pattern()

    if do_shift then
      seq_max = seq_max - 1 -- shift over line 2 so we don't have x repeating in 2 rows
      gen_pattern()
    end

    write_seq(pattern)

  end)
  

  -- Set the seq pattern  
  if mode == "run" then
    
  -- seq_generator index 1 is reserved for Randomize, otherwise fire the selected algo.
    seq_algo = params:get("seq_generator") == 1 and math.random(2,#seq_algos["name"]) or params:get("seq_generator")
    print("Seq algo: " .. seq_algos["name"][seq_algo])
    load(seq_algos["func"][seq_algo])
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
    local modifier = theory.chord_degree[params:get("scale")]["quality"][i]
    local chord_type = chord_type_simplified(modifier)
    
    mode_chord_types[i] = chord_type
    if chord_type == "maj" or chord_type == "min" then table.insert(safe_chord_degrees, i) end  --todo p0 what about 7ths here?
  end
  
  -- print("--------")
  -- print("mode " .. params:get("scale") .. " chord types")    
  -- tab.print(mode_chord_types)
  -- print("--------")
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


-- -- checks seq pattern for out-of-bound notes
-- -- if found, wipe pattern and rerun algo
-- -- don't hate the player- hate. the. game.
-- function seq_check_bounds(pattern)   
--   error_check = false
--   local length = seq_pattern_length[selected_seq_no][active_seq_pattern[selected_seq_no]]
--   for i = 2, length do
--     if pattern[i] < 0 or pattern[i] > max_seq_cols then
--       error_check = true
--       print("off-grid note on row " .. i)
--       break
--     end
--   end
--   if error_check then
--     print("clearing")
--     -- clear_seq(selected_seq_no)
--     print("rerolling")
--     load(seq_algos["func"][seq_algo])
--   else
--     return true
--   end
-- end


-- -- checks seq pattern for repeat notes
-- -- if found, wipe pattern and rerun algo
-- function seq_check_repeats()   
--   error_check = false
--   local length = seq_pattern_length[selected_seq_no][active_seq_pattern[selected_seq_no]]
--   for i = 2, length do
--     if seq_pattern[selected_seq_no][i] == seq_pattern[selected_seq_no][i - 1] then
--       error_check = true
--       -- print("repeat on row " .. i)
--       break
--     end
--   end
--   if error_check then
--     -- print("clearing")
--     clear_seq(selected_seq_no)
--     -- print("rerolling")
--     load(seq_algos["func"][seq_algo])
--   end
-- end


-- insert spaces between pattern and halves step length.
function double_space()
  for i = 8, 3, -1 do
    chord_pattern[active_chord_pattern][i] = (i % 2 == 0) and chord_pattern[active_chord_pattern][i / 2] or 0
  end
  chord_pattern[active_chord_pattern][2] = 0 -- lol ok
  params:set("chord_div_index", math.max(params:get("chord_div_index") - 3, 1))
end


function clear_seq(pattern)
  print("clear_seq")
  -- print("max_seq_pattern_length = " ..  max_seq_pattern_length)
  for i = 1, max_seq_pattern_length do -- seq_pattern_length[active_chord_pattern] do
    -- print("i = " .. i)
    seq_pattern[pattern][i] = 0
  end
end


-- Does some sort of weird check to see if we should apply an octave offset to x2 I guess
function pick_octave(x1, x2)
  return((math.max(x1, x2) -  math.min(x1, x2)) < (math.max(x1, x2 + 7) -  math.min(x1, x2 + 7)) and 0 or 7)
end                


-- function sketchy_chord(chord)
--   return(mode_chord_types[chord] == "dim" or mode_chord_types[chord] == "aug")
-- end


-- function to write a y-indexed table of x values to seq_pattern table, wiping existing pattern
function write_seq(pattern)
  local real_pattern = seq_pattern[selected_seq_no][active_seq_pattern[selected_seq_no]]

  for y = 1, max_seq_pattern_length do
    for x = 1, max_seq_cols do
      real_pattern[y][x] = (y <= #pattern) and (pattern[y] == x) and 1 or 0
    end
  end
end
-----------------------------------------------------------------