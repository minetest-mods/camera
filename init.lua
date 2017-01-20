
--[[

Copyright 2017 - Elijah Duffy <theoctacian@gmail.com>

License:
    - Code: MIT
    - Models and textures: CC-BY-SA-3.0

Usage: /camera

    Execute command to start recording. While recording:
    - use up/down to accelerate/decelerate
    - use jump to brake
    - use crouch to stop recording

    Use /camera playback to play back a recording. While playing back:
    - use crouch to stop playing back

--]]

local recordings = {}

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
			-- backward acccelerate
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
			recordings[self.driver:get_player_name()] = table.copy(self.path)
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
		local player = minetest.get_player_by_name(name)  -- Get player name.

		if param == "play" or param == "playback" then
			if not recordings[name] then
				return false, "Could not find recording"
			end
			local object = minetest.add_entity(player:getpos(), "camera:camera")
			object:get_luaentity():init(player, 1)
			object:setyaw(player:get_look_yaw())
			player:set_attach(object, "", {x=5,y=10,z=0}, {x=0,y=0,z=0})
			object:get_luaentity().path = table.copy(recordings[player:get_player_name()])
			return true, "Playback started"
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
