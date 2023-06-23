function gen_event_tables()
    event_sub_categories = {}
    event_indices = {}
  
    for i, entry in ipairs(events_lookup) do
      local category = entry.category
      local subCategory = entry.sub_category
  
      -- Generate event_sub_categories table
      if not event_sub_categories[category] then
        event_sub_categories[category] = {}
      end
  
      -- Check if the sub_category already exists in the table
      local exists = false
      for _, value in ipairs(event_sub_categories[category]) do
        if value == subCategory then
           exists = true
          break
        end
      end
  
      -- Add the sub_category to the table if it doesn't exist
      if not exists then
         table.insert(event_sub_categories[category], subCategory)
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