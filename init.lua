
--[[

Copyright 2016-2017 - Auke Kok <sofar@foo-projects.org>
Copyright 2017 - Elijah Duffy <theoctacian@gmail.com>

License:
    - Code: MIT
    - Models and textures: CC-BY-SA-3.0

Usage: /camera

    Execute command to start recording. While recording:
    - use up/down to accelerate/decelerate
    - use jump to brake
    - use crouch to stop recording

    Use /camera play to play back the last recording. While playing back:
    - use crouch to stop playing back

    Use /camera play <name> to play a specific recording

    Use /camera save <name> to save the last recording
    - saved recordings exist through game restarts

    Use /camera list to show all saved recording

--]]

local recordings = {}

-- Load recordings
local path = minetest.get_worldpath()

local function load()
  local res = io.open(path.."/recordings.txt", "r")
  if res then
    res = minetest.deserialize(res:read("*all"))
    if type(res) == "table" then
      recordings = res
    end
  end
end

load()

function save()
  io.open(path.."/recordings.txt", "w"):write(minetest.serialize(recordings))
end

-- [function] Get recording list for chat
function get_recordings(name)
  local recs = recordings[name]
  local list = ""

  if recs then
    for name, path in pairs(recs) do
      list = list..name..", "
    end
    return list
  else
    return "You do not saved any recordings."
  end
end

-- Register on shutdown
minetest.register_on_shutdown(save)

-- Table for storing unsaved temporary recordings
local temp = {}

-- camera def
local camera = {
	description = "Camera",
	visual = "wielditem",
	textures = {},
	physical = false,
	is_visible = false,
	collide_with_objects = false,
	collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	physical = false,
	visual = "cube",
	driver = nil,
	mode = 0,
	velocity = {x=0, y=0, z=0},
	old_pos = nil,
	old_velocity = nil,
	pre_stop_dir = nil,
	MAX_V = 20,
	init = function(self, player, mode)
		self.driver = player
		self.mode = mode
		self.path = {}
	end,
}


-- on step
function camera:on_step(dtime)
	if not self.driver then
		self.object:remove()
		return
	end
	local pos = self.object:getpos()
	local vel = self.object:getvelocity()
	local dir = self.driver:get_look_dir()

	if self.mode == 0 then
		-- record
		self.path[#self.path + 1] = {
			pos = pos,
			velocity = vel,
			pitch = self.driver:get_look_pitch(),
			yaw = self.driver:get_look_yaw()
		}

		-- player control of vehicle
		-- always modify yaw/pitch to match player
		self.object:set_look_pitch(self.driver:get_look_pitch())
		self.object:set_look_yaw(self.driver:get_look_yaw())

		-- accel/decel/stop
		local ctrl = self.driver:get_player_control()
		local speed = vector.distance(vector.new(), vel)
		if ctrl.up then
			-- forward accelerate
			speed = math.min(speed + 0.1, 20)
		end
		if ctrl.down then
			-- backward accelerate
			speed = math.max(speed - 0.1, -20)
		end
		if ctrl.jump then
			-- brake
			speed = math.max(speed * 0.9, 0.0)
		end
		if ctrl.sneak then
			-- stop recording!
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Recorded stopped after " .. #self.path .. " points")
			temp[self.driver:get_player_name()] = table.copy(self.path)
			self.object:remove()
			return
		end
		self.object:setvelocity(vector.multiply(self.driver:get_look_dir(), speed))
	elseif self.mode == 1 then
		-- stop playback ?
		local ctrl = self.driver:get_player_control()
		if ctrl.sneak or #self.path < 1 then
			-- stop playback
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Playback stopped")
			self.object:remove()
			return
		end

		-- playback
		self.object:moveto(self.path[1].pos, true)
		self.driver:set_look_yaw(self.path[1].yaw - (math.pi/2))
		self.driver:set_look_pitch(0 - self.path[1].pitch)
		self.object:setvelocity(self.path[1].velocity)
		table.remove(self.path, 1)
	end
end

-- Register entity.
minetest.register_entity("camera:camera", camera)

-- Register chatcommand.
minetest.register_chatcommand("camera", {
	description = "Manipulate recording",
	params = "<option>",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)  -- Get player name
		local param1 = param:split(" ")[1]
		local param2 = param:split(" ")[2]

		if param1 == "play" then
			local function play(path)
				local object = minetest.add_entity(player:getpos(), "camera:camera")
				object:get_luaentity():init(player, 1)
				object:setyaw(player:get_look_yaw())
				player:set_attach(object, "", {x=5,y=10,z=0}, {x=0,y=0,z=0})
				object:get_luaentity().path = path
			end

			-- Check for param2 (recording name)
			if param2 and param2 ~= "" then
				if recordings[name][param2] then
					play(table.copy(recordings[name][param2]))
				else
					return false, "Invalid recording "..param2..". Use /camera list to list recordings."
				end
			else -- else, Check temp
				if temp[name] then
					play(table.copy(temp[name]))
				else
					return false, "No recordings could be found"
				end
			end

			return true, "Playback started"
		elseif param1 == "save" then
			if not recordings[name] then
				recordings[name] = {}
			end

			if param2 and param2 ~= "" then
				recordings[name][param2] = temp[name]
        return true, "Saved recording as "..param2
			else
				return false, "Missing name to save recording under (/camera save <name>)"
			end
    elseif param1 == "list" then
      return true, "Recordings: "..get_recordings(name)
		else
			local object = minetest.add_entity(player:getpos(), "camera:camera")
			object:get_luaentity():init(player, 0)
			object:setyaw(player:get_look_yaw())
			player:set_attach(object, "", {x=0,y=10,z=0}, {x=0,y=0,z=0})
			return true, "Recording started"
		end
	end,
})

-- FIXME
-- add permanent recording of a path
-- add autoplayback on start for singleplayer if autosave path exists.
-- add loop playback
