local dashboards = {
  funcs = {},
  ids = {false},
  names = {"Off"}
}
local lvl = {}
local blinky
local led_pulse

local pattern_name = {"A","B","C","D"}

function dashboards.update_animations(b, p) -- passes animation.blinky and animation.led_pulse
  blinky = b -- from animation.blinky
  led_pulse = p -- from animation.led_pulse
end




------------------------------
-- MODULAR DASHBOARD FUNCTIONS
------------------------------
local dash_x = 93
local width = 35

local lvl_pane
local lvl_pane_selected
local lvl_pane_deselected
local lvl_chart_deselected
local lvl_menu_selected

-- function called from dreamsequence.lua when we need to switch between normal and dim levels
function dashboards.update_dash_lvls(lvl_tab)
  lvl = lvl_tab

  lvl_pane = lvl.pane
  lvl_pane_selected = lvl.pane_selected
  lvl_pane_deselected = lvl.pane_deselected
  lvl_chart_deselected = lvl.chart_deselected
  lvl_menu_selected = lvl.menu_selected
end




--------------------------------------------
-- ARRANGER DASH
--------------------------------------------
table.insert(dashboards.ids, "arranger_chart")
table.insert(dashboards.names,"Arranger chart")

function dashboards.funcs.arranger_chart()  
  local state = arranger_state
  local on = params:string("arranger") == "On"
  local final_seg = arranger_next == 0 -- arranger_position or 0 >= arranger_length
  local valid_jump = arranger_q and (arranger_q <= arranger_length)

  -- ARRANGER PANE
  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 22)
  screen.fill()

  -- ARRANGER POSITION READOUT
  -- dark = synced with arranger
  -- dim = arranger off
  -- pulsing = syncing

  screen.move(dash_x + 3, dash_y + 8)
  -- if arranger_active == false then  -- DE-SYNC, waiting until next chord pattern to sync
  if state ~= "on" then  -- off or syncing

    if state == "syncing" then
      screen.level(lvl_pane_selected + led_pulse) -- pulse while waiting to enter arrangement, (0 to 3)
    else
      screen.level(lvl_pane_deselected)
    end

    -- todo norns.ttf change to ↳ probably
    if valid_jump then
      screen.text("→" .. arranger_q)
    elseif final_seg and params:string("playback") == "1-shot" then
      screen.text("→End") -- indicate we'll hit end, not wrap
    else
      if arranger_position == 0 and chord_pattern_position == 0 then -- stopped
        screen.text("1") -- when arranger is off but we can enter arranger_state "on" without any count-in
      else
        screen.text("→1") -- if there's a jump but it's invalid so we are looping
      end

    end

  elseif arranger_position == 0 and chord_pattern_position == 0 then -- stopped
    screen.level(lvl_pane_selected)
    if valid_jump then
    screen.text(arranger_q)
    else
    screen.text(arranger_position == 0 and 1 or arranger_position)
    end
  else                                          -- standard playback
    screen.level(lvl_pane_selected)
    screen.text(arranger_position or 1)
  end
  screen.fill()


  -- ARRANGER MODE GLYPH
  -- glyph type: loop or one-shot
  -- todo norns.ttf 
  if params:string("playback") == "Loop" then

    if final_seg and not valid_jump then                              -- pulse final-segment warning when looping
      screen.level(lvl_pane_selected + led_pulse)
    else
      screen.level(on and lvl_pane_selected or lvl_pane_deselected)   -- standard level: bright == on/dark == off
    end

    for i = 1, #glyphs.loop do
      screen.pixel(120 + glyphs.loop[i][1], glyphs.loop[i][2] + dash_y + 3)
    end
  else
    if final_seg and not valid_jump then                              -- blink final-segment warning when about to stop
      screen.level(lvl_pane_selected + (blinky * 2))
    else
      screen.level(on and lvl_pane_selected or lvl_pane_deselected)   -- standard level: bright == on/dark == off
    end

    for i = 1, #glyphs.one_shot do
      screen.pixel(120 + glyphs.one_shot[i][1], glyphs.one_shot[i][2] + dash_y + 3)
    end
  end

  screen.fill() -- remove when switching to norns.ttf


  -- -- ARRANGER CHART
  -- -- todo break into sub-function so we can do a variation without chart portion (just seg and glyph)
  
  -- black chart background
  screen.level(on and lvl_pane_selected or 1)
  screen.rect(dash_x + 3, dash_y + 10, 29, 9)
  screen.fill()
  
  -- Axis reference marks
  screen.level(on and lvl_chart_deselected or lvl_chart_deselected + 1)
  for i = 1, 4 do
    screen.rect(dash_x + 4, dash_y + 9 + i * 2, 1, 1)
  end
  -- screen.pixel(dash_x + 4, dash_y + 21)
  screen.fill()
  
  local reset_shift = arranger_position == 0 and 2 or 0
  local arranger_dash_x = dash_x + 4 + reset_shift -- If arranger is reset, add an initial gap (and chop off the end)

  -- todo make these proper globals if we're doing this
  local dash_patterns = dash_patterns
  -- local dash_events = dash_events
  local dash_levels = dash_levels

  -- Draw arranger patterns and events timeline straight from x_dash_flat
  for i = 1, #dash_patterns do -- - reset_shift do
    local y = dash_patterns[i]
    if y > 0 and (arranger_dash_x < 125) then -- todo p1 optimize this
      -- arranger segment patterns
      screen.level(lvl[dash_levels[i]] + (on and 0 or 1)) -- less efficient to access lvl but got to
      screen.rect(arranger_dash_x, dash_y + 7 + ((y + 1) * 2), 1, 1)
      screen.fill()
    end

    -- -- events pips
    -- screen.level(lvl[dash_events[i]])
    -- screen.pixel(arranger_dash_x, dash_y + 21)
    -- screen.fill()

    arranger_dash_x = arranger_dash_x + 1
  end


  dash_y = dash_y + 23 -- position for next dash
end




---------------------
-- CHORD READOUT: NAME
---------------------
table.insert(dashboards.ids, "chord_active_name")
table.insert(dashboards.names, "Chord name")

function dashboards.funcs.chord_active_name()
  -- pane
  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 17)
  screen.fill()

  screen.level(lvl_pane_selected)
  if active_chord_name_2 then                           -- 2-row chord
    screen.move(dash_x + 17, dash_y + 8)
    screen.text_center(active_chord_name_1 or "")
    screen.move(dash_x + 17, dash_y + 14)
    screen.text_center(active_chord_name_2)
  else                                                  -- 1-row chord
    screen.move(dash_x + 17, dash_y + 11)
    screen.text_center(active_chord_name_1 or "")
  end

  dash_y = dash_y + 18 -- position for next dash
end



---------------------
-- CHORD READOUT: KEYBOARD VIZ
---------------------
table.insert(dashboards.ids, "chord_active_kbd")
table.insert(dashboards.names, "Chord kbd")

function dashboards.funcs.chord_active_kbd()
  local dark_g = lvl_pane_selected + 2
  local state_white = dash_keys_white
  local state_black = dash_keys_black
  local b_x = {6, 10, 18, 22, 26} -- x coords for black keys

  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 17)
  screen.fill()

  screen.level(dark_g) -- outlines
  screen.rect(dash_x + 3, dash_y + 3, 29, 11)
  screen.fill()


  for i = 1, 7 do
    screen.level(state_white[i] and lvl_pane or (lvl_pane_deselected + 2)) -- normal = white, playing = gray

    screen.rect(dash_x + 4 + ((i - 1) * 4), dash_y + 4, 3, 9)
    screen.fill()
  end
  
  for i = 1, 5 do
    screen.level(state_black[i] and lvl_pane_selected or dark_g) -- normal = black, playing = gray
    screen.rect(dash_x + b_x[i], dash_y + 4, 3, 5)
    screen.fill()
  end

  dash_y = dash_y + 18 -- position for next dash
end




----------------------------------------------------
-- CHORD PATTERN PROGRESS
----------------------------------------------------
table.insert(dashboards.ids, "chord_progress")
table.insert(dashboards.names, "Chord progress")

function dashboards.funcs.chord_progress()
  -- pane
  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 11)
  screen.fill()

  -- chord pattern text A-D
  screen.level(lvl_pane_selected)
  screen.move(dash_x + 3, dash_y + 8)
  screen.text(pattern_name[active_chord_pattern])

  -- CHORD PATTERN PROGRESS BAR
  -- dim chart area (black)
  screen.level(lvl_pane_selected)
  screen.rect(dash_x + 12, dash_y + 3, 18, 5)
  screen.fill()

  -- pattern length (gray)
  screen.level(lvl_chart_deselected)
  screen.rect(dash_x + 13, dash_y + 4, chord_pattern_length[active_chord_pattern], 3)
  screen.fill()

  -- progress bar (white)
  screen.level(lvl_menu_selected)
  screen.rect(dash_x + 13, dash_y + 4, chord_pattern_position, 3)
  screen.fill()

  dash_y = dash_y + 12 -- position for next dash
end




----------------------------------------------------
-- METRONOME, TIME REMAINING IN ARRANGEMENT
----------------------------------------------------
table.insert(dashboards.ids, "metro_remaining")
table.insert(dashboards.names, "Metro T-")

function dashboards.funcs.metro_remaining()
  -- pane
  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 11)
  screen.fill()

  -- transport state/metro glyph level
  if transport_state == "starting" and params:string("clock_source") == "link" then -- blink glyph. can't do metronome count-in due to https://github.com/monome/norns/issues/1756
    screen.level(blinky == 1 and lvl_pane_deselected or lvl_pane)
  elseif transport_state == "playing" then -- metronome with emphasis on new measure
    screen.level((metro_measure and lvl_pane_selected) or (sprocket_metro.downbeat and lvl_pane_deselected) or lvl_pane - 2)
  else
    screen.level(lvl_pane_selected)
  end

  -- redefine/simplify for glyphs
  local transport_state = transport_state == "starting" and "playing" or transport_state == "pausing" and "paused" or transport_state -- fix?

  -- glyph
  for i = 1, #glyphs[transport_state] do
    screen.pixel(dash_x + 3 + glyphs[transport_state][i][1], dash_y + 3 + glyphs[transport_state][i][2]) -- left
  end
  screen.fill()
  
  -- time elapsed text
  screen.level(params:string("arranger") == "On" and lvl_pane_selected or lvl_pane_deselected) -- dim if arranger is off
  screen.move(dash_x + 11, dash_y + 8)
  screen.text(seconds_remaining or "00:00")

  dash_y = dash_y + 12 -- position for next dash
end




----------------------------------------------------
-- METRONOME, TIME ELAPSED
----------------------------------------------------
table.insert(dashboards.ids, "metro_elapsed")
table.insert(dashboards.names, "Metro T+")

function dashboards.funcs.metro_elapsed()
  -- pane
  screen.level(lvl_pane)
  screen.rect(dash_x, dash_y, width, 11)
  screen.fill()

  -- transport state/metro glyph level
  if transport_state == "starting" and params:string("clock_source") == "link" then -- blink glyph. can't do metronome count-in due to https://github.com/monome/norns/issues/1756
    screen.level(blinky == 1 and lvl_pane_deselected or lvl_pane)
  elseif transport_state == "playing" then -- metronome with emphasis on new measure
    screen.level((metro_measure and lvl_pane_selected) or (sprocket_metro.downbeat and lvl_pane_deselected) or lvl_pane - 2)
  else
    screen.level(lvl_pane_selected)
  end

  -- redefine/simplify for glyphs
  local transport_state = transport_state == "starting" and "playing" or transport_state == "pausing" and "paused" or transport_state -- fix?

  -- glyph
  for i = 1, #glyphs[transport_state] do
    screen.pixel(dash_x + 3 + glyphs[transport_state][i][1], dash_y + 3 + glyphs[transport_state][i][2]) -- left
  end
  screen.fill()
  
  -- time elapsed text
  screen.level(lvl_pane_selected)
  screen.move(dash_x + 11, dash_y + 8)
  screen.text(seconds_elapsed or "00:00")

  dash_y = dash_y + 12 -- position for next dash
end

return dashboards