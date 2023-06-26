--------------------------------------------
-- GLOBAL VAR FUNCTIONS SETTING FUNCTIONS --
--------------------------------------------



-- EVENT-SPECIFIC FUNCTIONS ------------------------------------------------------

-- init functions

function gen_event_tables()
    event_subcategories = {}
    event_indices = {}
  
    for i, entry in ipairs(events_lookup) do
      local category = entry.category
      local subCategory = entry.subcategory
  
      -- Generate event_subcategories table
      if not event_subcategories[category] then
        event_subcategories[category] = {}
      end
  
      -- Check if the subcategory already exists in the table
      local exists = false
      for _, value in ipairs(event_subcategories[category]) do
        if value == subCategory then
           exists = true
          break
        end
      end
  
      -- Add the subcategory to the table if it doesn't exist
      if not exists then
         table.insert(event_subcategories[category], subCategory)
      end
  
      -- Generate event_indices
      local combination = category .. "_" .. subCategory
      if not event_indices[combination] then
        event_indices[combination] = {first_index = i, last_index = i}
      else
        event_indices[combination].last_index = i
      end
    end
  
  end
  
  
  -- functions called by scheduled events
  
  -- --for queuing pset load in-advance
  -- function load_pset()
  --   pset_load_source = 'load_event'
  --   pset_queue = params:get('load_pset')
  -- end
  
  
  -- --for queuing pset load in-advance
  -- function splice_pset()
  --   pset_load_source = 'splice_event'
  --   pset_queue = params:get('splice_pset')
  -- end
  
  
  -- function save_pset()
  --   params:write(params:get('save_pset'), 'ds ' ..os.date())
  --   -- local filepath = norns.state.data.."/"..number.."/"
  -- end
  
  
  -- Variation on the standard generators that will just run the algos and reset arp (but not chord pattern seq position or arranger)
  function event_gen()
    generator()
    arp_seq_position = 0
  end    
  
  
  function event_chord_gen()
    chord_generator_lite()
    arp_seq_position = 0
  end   
  
  
  function event_arp_gen()
    arp_generator('run')
    arp_seq_position = 0
  end    
  
  
  function shuffle_arp()
    local shuffled_arp_seq = shuffle(arp_seq[arp_pattern])
    arp_seq[arp_pattern] = shuffled_arp_seq
  end
        
            
  -- Passes along 'Arp' var so we can have a specific event for just arp
  function rotate_arp(direction)
    rotate_pattern('Arp', direction)
  end
  
  
  -- Event Crow trigger out
  function crow_event_trigger()
    crow.output[4].action = 'pulse(.001,10,1)' -- (time,level,polarity)
    crow.output[4]()
  end
  
  
  -- for event triggers
  function transpose_chord_pattern(direction)
    transpose_pattern('Chord', direction)
  end
  
  
  -- for event triggers
  function transpose_arp_pattern(direction)
    transpose_pattern('Arp', direction)
  end
  
  
  -- "Transposes" pattern if you can call it that
  function transpose_pattern(view, direction)
    if view == 'Chord' then
      for y = 1,8 do
        if chord_seq[pattern][y] ~= 0 then
          chord_seq[pattern][y] = util.wrap(chord_seq[pattern][y] + direction, 1, 14)
        end
      end
    elseif view == 'Arp' then
      for y = 1,8 do
        if arp_seq[arp_pattern][y] ~= 0 then
          arp_seq[arp_pattern][y] = util.wrap(arp_seq[arp_pattern][y] + direction, 1, 14)
        end
      end
    end  
  end   
  
  
  -- Fetches the min and max index for the selected event category (Global, Chord, Arp, etc...) + subcategory
  -- Also called when K3 opens events menu and when recalling a populated event slot
  function set_selected_event_indices()
    local event_category = params:string('event_category')
  
    -- Also swaps out the events_subcategory with whatever the active category is so this can be used for enc and redraw functions
    -- lookup is done on an "id" that doesn't exist in the og lookup table yet
    selected_event_subcategory_param = event_subcategory_param[params:get('event_category')]
    local event_subcategory = params:string(selected_event_subcategory_param)
  
  
    event_category_min_index = event_indices[event_category .. '_' .. event_subcategory].first_index
    event_category_max_index = event_indices[event_category .. '_' .. event_subcategory].last_index
    
    --wag if this should be here because I think this also needs to fire when changing event_name but let's try
    -- loads event_operations param with new options based on the currently-active event_type
    update_event_operation_options()
  end
  
  
  function get_options(param)
    local options = params.params[params.lookup[param]].options
    return (options)
  end
    
    
  -- loads event_operations param with new options based on the currently-active event_type
  function update_event_operation_options()
  
    swap_param_options('event_operation', _G['event_operation_options_' .. events_lookup[params:get('event_name')].value_type])
    -- print('loaded ' .. events_lookup[params:get('event_name')].name .. ' ' .. events_lookup[params:get('event_name')].value_type .. ' options')
  end
  
  -- called whenever event_name changes to point to the correct param
  function set_selected_event_value_type(event_index)
    local value_type = events_lookup[event_index].value_type
    if value_type ~= 'trigger' then
      event_value_type_param = 'event_value_type_' .. value_type
    end
  end
          
  
  -- END OF EVENT-SPECIFIC FUNCTIONS ------------------------------------------------------
  
  
  
  --- UTILITY FUNCTIONS
  
  
  -- function to swap options table on an existing param and reset count
  function swap_param_options(param, table)
    params:lookup_param(param).options = table
    params:lookup_param(param).count = #table
  end
  
  
  -- converts the string value of an 'add_options' param into a value index # suitable for params:set
  -- args: param id and string value         eg 'event_category', 'Arp' == 3
  function param_option_to_index(param, str)
    return(tab.key(params.params[params.lookup[param]].options, str))
  end
  
  
  function spaces_to_underscores(str)
    local replacedStr = string.gsub(str, " ", "_")
    return replacedStr
  end
  
  
  -- text_extents sucks so I gotta make some adjustments
  -- spaces should count as 3 and </> count as 3
  function text_width(str)
    local extents = screen.text_extents(str) -- raw count that ain't great
    
    local symbols = "<>"
    local pattern = "[" .. symbols:gsub("[<>]", "%%%0") .. "]" -- character class to identify < and >
    local extents = extents - (select(2, string.gsub(str, pattern, ""))) -- subtract 1 for each < and >
  
    local count = select(2, string.gsub(str, pattern, ""))
    local extents = extents + (string.len(string.gsub(str, "[^%s]", "")) * 3) -- spaces count as 3 pixels
    
    return extents
  end