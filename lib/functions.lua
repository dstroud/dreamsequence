--------------------------------------------
-- PATTERN TRANSFORMATIONS --
--------------------------------------------

-- Rotate looping portion of pattern
function rotate_pattern(view, direction)
    if view == 'Chord' then
      local length = chord_pattern_length[chord_pattern]
      local temp_chord_seq = {}
      for i = 1, length do
        temp_chord_seq[i] = chord_seq[chord_pattern][i]
      end
      for i = 1, length do
        chord_seq[chord_pattern][i] = temp_chord_seq[util.wrap(i - direction,1,length)]
      end
    elseif view == 'Seq' then
      local length = seq_pattern_length[seq_pattern]
      local temp_seq_seq = {}
      for i = 1, length do
        temp_seq_seq[i] = seq_seq[seq_pattern][i]
      end
      for i = 1, length do
        seq_seq[seq_pattern][i] = temp_seq_seq[util.wrap(i - direction,1,length)]
      end
    end
  end
  
  
  ------------------------------------------------------
  -- EVENT-SPECIFIC FUNCTIONS --
  ------------------------------------------------------
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
  
  
  
  ------------------------------------------------------------------------------------------------
    -- Event menu param options swapping functions
  ------------------------------------------------------------------------------------------------
  
  -- -- Fetches the min and max index for the selected event category (Global, Chord, Seq, etc...) + subcategory
  -- -- Also called when K3 opens events menu and when recalling a populated event slot
  -- function set_selected_event_indices()
  --   local event_category = params:string('event_category')
    
  --   update_event_subcategory_options('set_selected_event_indices')
  --   -- at this point there is a chance that the current subcategory index exceeds what was just set. need to reset but not every time or we can never actually change the subcategory value. Feels like we need to pull out all this and keep this function for just what it says on the tin: indices.
  --   -- params:set('event_subcategory', 1) -- set to index 1 because existing index may exceed #table
  
  --   -- print('post- subcategory_options update')
  --   local subcategory = params:string('event_subcategory')
  --   print('subcategory index == ' .. params:get('event_subcategory'))
  --   print('subcategory = ' .. (subcategory or 'nil'))
  --   event_category_min_index = event_indices[event_category .. '_' .. subcategory].first_index
  --   event_category_max_index = event_indices[event_category .. '_' .. subcategory].last_index
    
  --   --wag if this should be here because I think this also needs to fire when changing event_name but let's try
  --   -- loads event_operations param with new options based on the currently-active event_type
  --   update_event_operation_options('set_selected_event_indices')
  -- end
  
  
  -- function get_options(param)
  --   local options = params.params[params.lookup[param]].options
  --   return (options)
  -- end
  
  
  -- function update_event_subcategory_options(source)
  --   swap_param_options('event_subcategory', event_subcategories[params:string('event_category')])
  --   -- print(' post-options set subcategory string = ' .. params:string('event_subcategory'))
  --   print('update_event_subcategory_options called by ' .. (source or 'nil'))
  --   -- print('printing from update_event_operation_options:')
  --   -- print('>>loaded ' .. events_lookup[params:get('event_name')].name .. ' ' .. events_lookup[params:get('event_name')].value_type .. ' options')
  -- end
  
  -- function update_event_operation_options(source)
  --   print('update_event_operation_options called by ' .. (source or 'nil'))
  --   swap_param_options('event_operation', _G['event_operation_options_' .. events_lookup[params:get('event_name')].value_type])
  --   -- print('printing from update_event_operation_options:')
  --   -- print('>>loaded ' .. events_lookup[params:get('event_name')].name .. ' ' .. events_lookup[params:get('event_name')].value_type .. ' options')
  -- end
    
  -------------------------------------- 
  -- functions called by scheduled events
  ----------------------------------------
  
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
  
  
  -- Variation on the standard generators that will just run the algos and reset seq (but not chord pattern seq position or arranger)
  function event_gen()
    generator()
    seq_seq_position = 0
  end    
  
  
  function event_chord_gen()
    chord_generator_lite()
    seq_seq_position = 0
  end   
  
  
  function event_seq_gen()
    seq_generator('run')
    seq_seq_position = 0
  end    
  
  
  function shuffle_seq()
    local shuffled_seq_seq = shuffle(seq_seq[seq_pattern])
    seq_seq[seq_pattern] = shuffled_seq_seq
  end
        
            
  -- -- Passes along 'Seq' var so we can have a specific event for just seq
  -- function rotate_seq(direction)
  --   rotate_pattern('Seq', direction)
  -- end
  
  
  -- Event Crow trigger out
  function crow_event_trigger()
    crow.output[4].action = 'pulse(.001,10,1)' -- (time,level,polarity)
    crow.output[4]()
  end
  
  
  -- "Transposes" pattern if you can call it that
  function transpose_pattern(view, direction)
    if view == 'Chord' then
      for y = 1,8 do
        if chord_seq[chord_pattern][y] ~= 0 then
          chord_seq[chord_pattern][y] = util.wrap(chord_seq[chord_pattern][y] + direction, 1, 14)
        end
      end
    elseif view == 'Seq' then
      for y = 1,8 do
        if seq_seq[seq_pattern][y] ~= 0 then
          seq_seq[seq_pattern][y] = util.wrap(seq_seq[seq_pattern][y] + direction, 1, 14)
        end
      end
    end  
  end   
  
  -- END OF EVENT-SPECIFIC FUNCTIONS ------------------------------------------------------
  
  
  
  --- UTILITY FUNCTIONS
  
  
  -- always use this to set the current chord pattern so we can also silently update the param as well
  function set_chord_pattern(y)
    chord_pattern = y
    params:set('chord_pattern_length', chord_pattern_length[y], true) -- silent
  end
  
  
  function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
      copy = {}
      for orig_key, orig_value in next, orig, nil do
        copy[deepcopy(orig_key)] = deepcopy(orig_value)
      end
      setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
      copy = orig
    end
    return copy
  end
  
  
  -- equal probability of returning the inverse of arg
  function cointoss_inverse(val)
    return(val * (math.random(2) == 1 and -1 or 1))
  end
  
  
  -- function to swap options table on an existing param and reset count
  function swap_param_options(param, table)
    params:lookup_param(param).options = table
    -- print('setting ' .. param .. ' options to :')
    -- tab.print(table)
    params:lookup_param(param).count = #table   -- existing index may exceed this so it needs to be set afterwards by whatever called (not every time)
  end
  
  
  -- converts the string value of an 'add_options' param into a value index # suitable for params:set
  -- args: param id and string value         eg 'event_category', 'Seq' == 3
  function param_option_to_index(param, str)
    return(tab.key(params.params[params.lookup[param]].options, str))
  end
  
  
  -- passed string arg will be looked up in param's .options and set using index
  function set_param_string(param, str)
    params:set(param, param_option_to_index(param, str))
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
  
  
  -- param action to send cc out as encoder is turned
  function send_cc(source, cc_no, val)
    if val > -1 then
      local channel = params:get(source .. '_midi_ch')
      local port = params:get(source .. '_midi_out_port')
      midi_device[port]:cc(cc_no, val, channel)
    end
  end
  
  -------------------------
  -- UI FUNCTIONS
  -------------------------
  
  
  -- index of list, count of items in list, #viewable, line height
  -- function scroll_offset_simple(index, total, in_view, height)
  function scroll_offset_locked(index, height, locked_row)
    -- if total > in_view and index > locked_row then
    if index > locked_row then
    
      -- return(math.ceil(((index - 1) * (total - in_view) * height / total)))
      -- if index > 1 then 
        return((index - locked_row) * height)
      -- end
    else
      return(0)
    end
  end
        
        
  function scrollbar(index, total, in_view, locked_row, screen_height)
    local bar_size = in_view / total * screen_height
    local increment = (screen_height - bar_size) / (total - locked_row)
    index = math.max(index - locked_row, 0)
    local offset = 12 + (index * increment)
    return(offset)
  end
        
        
  function delete_all_events_segment()
    key_counter = 4
    
    while event_k2 == true do
      key_counter = key_counter - 1
      redraw()
      if key_counter == 0 then
        print('Deleting all events in segment ' .. event_edit_pattern)
        for step = 1,8 do
          events[event_edit_pattern][step] = {}
        end
        events[event_edit_pattern].populated = 0
        grid_redraw()
        key_counter = 4
        break
      end
      clock.sleep(.2)
    end
    key_counter = 4
    --todo p3 should probably have a 'Deleted message appear until key up'
    redraw()
  end