
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

-- [function] Load recordings
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

-- Call load
load()

-- [function] Save recordings
function save()
	io.open(path.."/recordings.txt", "w"):write(minetest.serialize(recordings))
end

-- [function] Get recording list per-player for chat
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

-- [event] On shutdown save recordings
minetest.register_on_shutdown(save)

-- Table for storing unsaved temporary recordings
local temp = {}

-- Camera definition
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


-- [event] On step
function camera:on_step(dtime)
	-- if not driver, remove object
	if not self.driver then
		self.object:remove()
		return
	end

	local pos = self.object:getpos()
	local vel = self.object:getvelocity()
	local dir = self.driver:get_look_dir()

	-- if record mode
	if self.mode == 0 then
		-- Update path
		self.path[#self.path + 1] = {
			pos = pos,
			velocity = vel,
			pitch = self.driver:get_look_pitch(),
			yaw = self.driver:get_look_yaw()
		}

		-- Modify yaw and pitch to match driver (player)
		self.object:set_look_pitch(self.driver:get_look_pitch())
		self.object:set_look_yaw(self.driver:get_look_yaw())

		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- Initialize speed
		local speed = vector.distance(vector.new(), vel)

		-- if up, accelerate forward
		if ctrl.up then
			speed = math.min(speed + 0.1, 20)
		end

		-- if down, accelerate backward
		if ctrl.down then
			speed = math.max(speed - 0.1, -20)
		end

		-- if jump, brake
		if ctrl.jump then
			speed = math.max(speed * 0.9, 0.0)
		end

		-- if sneak, stop recording
		if ctrl.sneak then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Recorded stopped after " .. #self.path .. " points")
			temp[self.driver:get_player_name()] = table.copy(self.path)
			self.object:remove()
			return
		end

		-- Set updated velocity
		self.object:setvelocity(vector.multiply(self.driver:get_look_dir(), speed))
	elseif self.mode == 1 then -- elseif playback mode
		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- if sneak or no path, stop playback
		if ctrl.sneak or #self.path < 1 then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Playback stopped")
			self.object:remove()
			return
		end

		-- Update position
		self.object:moveto(self.path[1].pos, true)
		-- Update yaw/pitch
		self.driver:set_look_yaw(self.path[1].yaw - (math.pi/2))
		self.driver:set_look_pitch(0 - self.path[1].pitch)
		-- Update velocity
		self.object:setvelocity(self.path[1].velocity)
		-- Remove path table
		table.remove(self.path, 1)
	end
end

-- Register entity
minetest.register_entity("camera:camera", camera)

-- Register chatcommand
minetest.register_chatcommand("camera", {
	description = "Manipulate recording",
	params = "<option> <value>",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local param1, param2 = param:split(" ")[1], param:split(" ")[2]

		-- if play, begin playback preperation
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
				-- if recording exists, start
				if recordings[name][param2] then
					play(table.copy(recordings[name][param2]))
				else -- else, return error
					return false, "Invalid recording "..param2..". Use /camera list to list recordings."
				end
			else -- else, check temp for a recording path
				if temp[name] then
					play(table.copy(temp[name]))
				else
					return false, "No recordings could be found"
				end
			end

			return true, "Playback started"
		elseif param1 == "save" then -- elseif save, prepare to save path
			-- if no table for player in recordings, initialize
			if not recordings[name] then
				recordings[name] = {}
			end

			-- if param2 is not blank, save
			if param2 and param2 ~= "" then
				recordings[name][param2] = temp[name]
				return true, "Saved recording as "..param2
			else -- else, return error
				return false, "Missing name to save recording under (/camera save <name>)"
			end
		elseif param1 == "list" then -- elseif list, list recordings
			return true, "Recordings: "..get_recordings(name)
		else -- else, begin recording
			local object = minetest.add_entity(player:getpos(), "camera:camera")
			object:get_luaentity():init(player, 0)
			object:setyaw(player:get_look_yaw())
			player:set_attach(object, "", {x=0,y=10,z=0}, {x=0,y=0,z=0})
			return true, "Recording started"
		end
	end,
})
