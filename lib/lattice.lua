-- DS modified version of Lattice with logic for on-the-fly division changes as well as some extra sprocket actions

---- module for creating a lattice of sprockets based on a single fast "superclock"
--
-- @module Lattice
-- @release v2.0
-- @author tyleretters & ezra & zack & rylee

local Lattice, Sprocket = {}, {}

--- instantiate a new lattice
-- @tparam[opt] table args optional named attributes are:
-- - "auto" (boolean) turn off "auto" pulses from the norns clock, defaults to true
-- - "ppqn" (number) the number of pulses per quarter cycle of this superclock, defaults to 96
-- @treturn table a new lattice
function Lattice:new(args)
  local l = setmetatable({}, { __index = Lattice })
  args = args == nil and {} or args
  l.auto = args.auto == nil and true or args.auto
  l.ppqn = args.ppqn == nil and 96 or args.ppqn
  l.enabled = false
  l.transport = 0
  l.superclock_id = nil
  l.sprocket_id_counter = 100
  l.sprockets = {}
  l.sprocket_ordering = {{}, {}, {}, {}, {}}
  return l
end

--- start running the lattice
function Lattice:start()
  self.enabled = true
  if self.auto and self.superclock_id == nil then
    self.superclock_id = clock.run(self.auto_pulse, self)
  end
end

--- reset the norns clock without restarting lattice
function Lattice:reset()
  -- destroy clock, but not the sprockets
  self:stop()
  if self.superclock_id ~= nil then
    clock.cancel(self.superclock_id)
    self.superclock_id = nil
  end
  for i, sprocket in pairs(self.sprockets) do
    sprocket.phase = sprocket.division * self.ppqn * 4 * (1 - sprocket.delay) -- "4" because in music a "quarter note" == "1/4"
    sprocket.downbeat = false
  end
  self.transport = 0
  params:set("clock_reset", 1)
end

--- reset the norns clock and restart lattice
function Lattice:hard_restart()
  self:reset()
  self:start()
end

--- stop the lattice
function Lattice:stop()
  self.enabled = false
end

--- toggle the lattice
function Lattice:toggle()
  self.enabled = not self.enabled
end

--- destroy the lattice
function Lattice:destroy()
  self:stop()
  if self.superclock_id ~= nil then
    clock.cancel(self.superclock_id)
  end
  self.sprockets = {}
  self.sprocket_ordering = {}
end

--- set_meter is deprecated
function Lattice:set_meter(_)
  print("meter is deprecated")
end

--- use the norns clock to pulse
-- @tparam table s this lattice
function Lattice.auto_pulse(s)
  while true do
    s:pulse()
    clock.sync(1/s.ppqn)
  end
end

--- advance all sprockets in this lattice by a single pulse, call this manually if lattice.auto = false
function Lattice:pulse()
  if self.enabled then
    local ppc = self.ppqn * 4 -- pulses per cycle; "4" because in music a "quarter note" == "1/4"
    local flagged=false
    for i = 1, 5 do
      for _, id in ipairs(self.sprocket_ordering[i]) do
        local sprocket = self.sprockets[id]

        -- -- debugging. kill off
        -- local sprocket_name
        -- if sprocket.id == sprocket_notes.id then 
        --   sprocket_name = "notes"    
        -- elseif sprocket.id == sprocket_measure.id then 
        --   sprocket_name = "measure"     
        -- elseif sprocket.id == sprocket_16th.id then 
        --   sprocket_name = "16th"             
        -- elseif sprocket.id == sprocket_chord.id then 
        --   sprocket_name = "chord"     
        -- elseif sprocket.id == sprocket_seq_1.id then 
        --   sprocket_name = "seq_1"                     
        -- elseif sprocket.id == sprocket_crow_clock.id then 
        --   sprocket_name = "crow_clock"
        -- elseif sprocket.id == sprocket_cv_harm.id then 
        --   sprocket_name = "cv_harm"                                
        -- end

          -- if sprocket_name == "chord" then
          --   print("phase " ..sprocket.phase, "txp " .. self.transport)
          -- end

          if sprocket.phase == sprocket.division * ppc then
            sprocket.pre_action()-- self.transport) -- script-specific custom action set only on sprocket_chord

            -- todo p2 move down to "RELOCATE LOCALS HERE" once done debugging
            local ppd = ppc * (sprocket.division_new or sprocket.division)  -- NEW pulses per div
            local txp_mod = self.transport % ppd -- pulses/phase past previous valid beat div
            local prev_div_txp = math.floor(self.transport / ppd) * ppd -- previous on-div transport  (no swing)
            local next_div_txp = prev_div_txp + ppd -- upcoming valid beat (no swing)
            local next_div_downbeat = next_div_txp / ppd % 2 == 0 -- whether the upcoming beat is downbeat (std) or not (swing)
            
            -- print("next_div_downbeat " .. tostring(next_div_downbeat))

            -- -- debugging
            -- local sprocket_name
            -- if sprocket.id == sprocket_transport.id then 
            --   sprocket_name = "transport"     
            -- elseif sprocket.id == sprocket_chord.id then 
            --   sprocket_name = "chord"     
            -- elseif sprocket.id == sprocket_seq_1.id then 
            --   sprocket_name = "seq_1"                     
            -- elseif sprocket.id == sprocket_crow_clock.id then 
            --   sprocket_name = "crow_clock"
            -- elseif sprocket.id == sprocket_cv_harm.id then 
            --   sprocket_name = "cv_harm"                                
            -- end

            if sprocket.division_new ~= nil then  -- flip!

              -- "RELOCATE LOCALS HERE" 
              -- local ppd = ppc * (sprocket.division_new or sprocket.division)  -- NEW pulses per div
              -- local txp_mod = self.transport % ppd -- pulses/phase past previous valid beat div
              -- local prev_div_txp = math.floor(self.transport / ppd) * ppd -- previous on-div transport  (no swing)
              -- local next_div_txp = prev_div_txp + ppd -- upcoming valid beat (no swing)
              -- local next_div_downbeat = next_div_txp / ppd % 2 == 0 -- whether the upcoming beat is downbeat (std) or not (swing)


              -- params:set("chord_duration_index", params:get("chord_div_index")) -- todo: make a feature

            
              sprocket.division = sprocket.division_new
              sprocket.division_new = nil
              -- sprocket.div_action()

              -- -- debugging
              -- print(
              --   sprocket_name .. " new div: " .. sprocket.division,
              --   sprocket_name .. " new phase: " .. sprocket.phase
              -- )              
              

              sprocket.phase = (txp_mod == 0 and ppd or txp_mod) -- alt. phase 0 is "wrapped" to ppd to fire immediately
              if txp_mod == 0 then
                sprocket.downbeat = next_div_downbeat
              else
                sprocket.downbeat = not next_div_downbeat
              end

            end 

            -- if sprocket_name == "chord" then
            --   print(
            --     sprocket_name,
            --     "div "..round(sprocket.division, 2),
            --     "txp "..string.format("%05d", (self.transport or 0)),
            --     "txp_mod "..txp_mod,
            --     "next_div_txp "..next_div_txp,
            --     "next_db "..tostring(sprocket.downbeat),
            --     "\u{F8} "..sprocket.phase,
            --     "beat "..round(clock.get_beats(),2),
            --     "en "..tostring(sprocket.enabled)
            --   )
            -- end

          end

        if sprocket.enabled then
          sprocket.phase = sprocket.phase + 1
          local swing_val = 2 * sprocket.swing / 100
          if not sprocket.downbeat then
            swing_val = 1
          end
          if sprocket.phase > sprocket.division * ppc * swing_val then
            sprocket.phase = sprocket.phase - (sprocket.division * ppc)
            if sprocket.delay_new ~= nil then
              sprocket.phase = sprocket.phase - (sprocket.division * ppc) * (1 - (sprocket.delay - sprocket.delay_new))
              sprocket.delay = sprocket.delay_new
              sprocket.delay_new = nil
            end

            sprocket.action(self.transport)
            sprocket.downbeat = not sprocket.downbeat
          end
        elseif sprocket.flag then
          self.sprockets[sprocket.id] = nil
          flagged = true
        end
      end
    end
    if flagged then
      self:order_sprockets()
    end
    self.transport = self.transport + 1

  else -- self.disabled!

    -- hack to sustain notes when lattice is paused/stopped
    -- this is the same as sprocket_notes.action
    -- could make this a bit more "elegant" by adding a flag like sprocket.continuous_action
    process_notes()

  end
end

--- factory method to add a new sprocket to this lattice
-- @tparam[opt] table args optional named attributes are:
-- - "action" (function) called on each step of this division (lattice.transport is passed as the argument), defaults to a no-op
-- - "division" (number) the division of the sprocket, defaults to 1/4
-- - "enabled" (boolean) is this sprocket enabled, defaults to true
-- - "swing" (number) is the percentage of swing (0 - 100%), defaults to 50
-- - "delay" (number) specifies amount of delay, as fraction of division (0.0 - 1.0), defaults to 0
-- - "order" (number) specifies the place in line this lattice occupies from 1 to 5, lower first, defaults to 3
-- @treturn table a new sprocket
function Lattice:new_sprocket(args)
  self.sprocket_id_counter = self.sprocket_id_counter + 1
  args = args == nil and {} or args
  args.id = self.sprocket_id_counter
  args.order = args.order == nil and 3 or util.clamp(args.order, 1, 5)
  args.pre_action = args.pre_action == nil and function(t) return end or args.pre_action
  args.action = args.action == nil and function(t) return end or args.action
  -- args.div_action = args.div_action == nil and function(t) return end or args.div_action
  args.division = args.division == nil and 1/4 or args.division
  args.enabled = args.enabled == nil and true or args.enabled
  args.phase = args.division * self.ppqn * 4 -- "4" because in music a "quarter note" == "1/4"
  args.swing = args.swing == nil and 50 or util.clamp(args.swing,0,100)
  args.delay = args.delay == nil and 0 or util.clamp(args.delay,0,1)
  local sprocket = Sprocket:new(args)
  self.sprockets[self.sprocket_id_counter] = sprocket
  self:order_sprockets()
  return sprocket
end

--- new_pattern is deprecated
function Lattice:new_pattern(args)
  print("'new_pattern' is deprecated; use 'new_sprocket' instead.")
  return self:new_sprocket(args)
end

--- "private" method to keep numerical order of the sprocket ids
-- for use when pulsing
function Lattice:order_sprockets()
  self.sprocket_ordering = {{}, {}, {}, {}, {}}
  for id, sprocket in pairs(self.sprockets) do
    table.insert(self.sprocket_ordering[sprocket.order],id)
  end
  for i = 1, 5 do
    table.sort(self.sprocket_ordering[i])
  end
end

--- "private" method to instantiate a new sprocket, only called by Lattice:new_sprocket()
-- @treturn table a new sprocket
function Sprocket:new(args)
  local p = setmetatable({}, { __index = Sprocket })
  p.id = args.id
  p.order = args.order
  p.division = args.division
  p.pre_action = args.pre_action
  p.action = args.action
  -- p.div_action = args.div_action
  p.enabled = args.enabled
  p.flag = false
  p.swing = args.swing
  p.downbeat = false
  p.delay = args.delay
  p.phase = args.phase * (1-args.delay)
  return p
end

--- start the sprocket
function Sprocket:start()
  self.enabled = true
end

--- stop the sprocket
function Sprocket:stop()
  self.enabled = false
end

--- toggle the sprocket
function Sprocket:toggle()
  self.enabled = not self.enabled
end

--- flag the sprocket to be destroyed
function Sprocket:destroy()
  self.enabled = false
  self.flag = true
end

--- set the division of the sprocket
-- @tparam number n the division of the sprocket
function Sprocket:set_division(n)
   self.division_new = n
end

--- set the action for this sprocket
-- @tparam function the action
function Sprocket:set_action(fn)
  self.action = fn
end

--- set the swing of the sprocket
-- @tparam number the swing value 0-100%
function Sprocket:set_swing(swing)
  self.swing = util.clamp(swing,0,100)
end

--- set the delay for this sprocket
-- @tparam fraction of the time between beats to delay (0-1)
function Sprocket:set_delay(delay)
  self.delay_new = util.clamp(delay,0,1)
end

return Lattice