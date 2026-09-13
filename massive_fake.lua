local vector = require("vector") -- Not mine
local sv_ui = ui.reference("MISC", "Settings", "sv_maxusrcmdprocessticks2")
local fakewalk_key = ui.new_hotkey("AA", "Other", "Fakewalk")
local discharge_key = ui.new_hotkey("AA", "Other", "Exploit Discharge / Flick")
local enable_def_aa = ui.new_checkbox("AA", "Other", "Enable Default AA")
local lock_yaw = ui.new_hotkey("AA", "Other", "Lock Flick Yaw")
local force_choke = ui.new_checkbox("AA", "Other", "Force choke")
local unsafe_choke = ui.new_checkbox("AA", "Other", "Unsafe choke")
local force_slowdown = ui.new_checkbox("AA", "Other", "Force slowdown")
local force_fs = ui.new_checkbox("AA", "Other", "Force freestand")
local enable_onpeek = ui.new_checkbox("AA", "Other", "Force exploit on peek")
local enable_hg = ui.new_checkbox("AA", "Other", "Revert on High/Low Ground")
local hg_checks = ui.new_combobox("AA", "Other", "Revert Mode", "Always", "Enemy Highground", "Enemy Lowground")
local discharge_flmode = ui.new_combobox("AA", "Other", "FL Mode", "Dynamic", "Maximum", "Fluctuate")
local aa_yaw, aa_yaw_offset = ui.reference("AA", "Anti-aimbot angles", "Yaw")
local aa_yaw_base = ui.reference("AA", "Anti-aimbot angles", "Yaw base")
local aa_yaw_jitter, aa_yaw_jitter_offset = ui.reference("AA", "Anti-aimbot angles", "Yaw jitter")
local freestand, fs_bind = ui.reference("AA", "Anti-aimbot angles", "Freestanding")
local fl_limit = ui.reference("AA", "fake lag", "limit")
local fl_amount = ui.reference("AA", "fake lag", "amount")
local fl_enabled = ui.reference("AA", "fake lag", "enabled")
local dt_ref, dt_key = ui.reference("RAGE", "Aimbot", "Double tap")
local aa_fake_yaw, aa_fake_yaw_slider = ui.reference("AA", "Anti-aimbot angles", "body yaw")
local L3 = require "gamesense/antiaim_funcs" or error "https://gamesense.pub/forums/viewtopic.php?id=29665"
local ffi = require("ffi")
local c_entity = require "gamesense/entity"

ffi.cdef[[
    typedef unsigned char wchar_t;

    typedef bool (__thiscall *IsButtonDown_t)(void*, int);
]]
local interface_ptr = ffi.typeof('void***')

local raw_inputsystem = client.create_interface('inputsystem.dll', 'InputSystemVersion001')

-- cast the lightuserdata to a type that we can dereference
local inputsystem = ffi.cast(interface_ptr, raw_inputsystem) -- void***

-- dereference the interface pointer to get its vtable
local inputsystem_vtbl = inputsystem[0] -- void**

-- vtable is an array of functions, the 15th is IsButtonDown
local raw_IsButtonDown = inputsystem_vtbl[15] -- void*

-- cast the function pointer to a callable type
local is_button_pressed = ffi.cast('IsButtonDown_t', raw_IsButtonDown)

local move_ticks = 0
local unpredicted_vel = 0
local local_yaw = 0
local local_abs_yaw = 0
local chooseside = 0

local curtime = 0
local curtime2 = 0
local from_move = false
local from_stand = false
local flick_count = 0

local now_rt = 0
local delay_last = 0
local passed = 0

local do_jitter = false

local is_flicking = false
local lock_bodyyaw = false
local reenable_dt = false
local is_alyx = 18
local onShotFire = 2

local enemyclosesttocrosshair = nil

local engine_client = ffi.cast("void***", client.create_interface("engine.dll", "VEngineClient014"))
local get_net_channel_info = ffi.cast("void*(__thiscall*)(void*)", engine_client[0][78])

local function get_server_ip()
    local net_channel_info = ffi.cast("void***", get_net_channel_info(engine_client))
    if net_channel_info == ffi.NULL then
        return "Not connected"
    end

    local get_address = ffi.cast("const char*(__thiscall*)(void*)", net_channel_info[0][1])
    return ffi.string(get_address(net_channel_info))
end

client.set_event_callback("round_start", function (e)
	is_alyx = ui.get(unsafe_choke) and ( get_server_ip() == "188.212.100.123:27015" and 21 or 18 ) or ( get_server_ip() == "188.212.100.123:27015" and 20 or 17 )
end)

client.set_event_callback("cs_game_disconnected", function (e)
	is_alyx = ui.get(unsafe_choke) and ( get_server_ip() == "188.212.100.123:27015" and 21 or 18 ) or ( get_server_ip() == "188.212.100.123:27015" and 20 or 17 )
end)

client.set_event_callback("game_newmap", function (e)
	is_alyx = ui.get(unsafe_choke) and ( get_server_ip() == "188.212.100.123:27015" and 21 or 18 ) or ( get_server_ip() == "188.212.100.123:27015" and 20 or 17 )
end)

local function vec3_dot(ax, ay, az, bx, by, bz)
	return ax*bx + ay*by + az*bz
end

local function vec3_normalize(x, y, z)
	local len = math.sqrt(x * x + y * y + z * z)
	if len == 0 then
		return 0, 0, 0
	end
	local r = 1 / len
	return x*r, y*r, z*r
end

local function angle_to_vec(pitch, yaw)
	local p, y = math.rad(pitch), math.rad(yaw)
	local sp, cp, sy, cy = math.sin(p), math.cos(p), math.sin(y), math.cos(y)
	return cp*cy, cp*sy, -sp
end

local function get_fov_cos(ent, vx,vy,vz, lx,ly,lz)
	local ox,oy,oz = entity.get_prop(ent, "m_vecOrigin")
	if ox == nil then
		return -1
	end

	-- get direction to player
	local dx,dy,dz = vec3_normalize(ox-lx, oy-ly, oz-lz)
	return vec3_dot(dx,dy,dz, vx,vy,vz)
end
local function calculate_freestand()
    local local_player = entity.get_local_player()
    local eye_pos = vector(client.eye_position())
    local yaw = vector(client.camera_angles())
    local enemy = client.current_threat()
    local frac_num = {
        ["f_left"] = 0,
        ["f_right"] = 0
    }

    for i = yaw.y - 90, yaw.y + 90, 30 do
        if i ~= yaw.y then
            local rad = math.rad(i)
            local destination = vector(eye_pos.x + 256 * math.cos(rad), eye_pos.y + 256 * math.sin(rad), eye_pos.z)
            local trace, fraction = client.trace_line(local_player, eye_pos.x, eye_pos.y, eye_pos.z, destination.x, destination.y, destination.z)
            local side = i < yaw.y and "f_left" or "f_right"
            frac_num[side] = frac_num[side] + trace
        end
    end

	return frac_num["f_left"] > frac_num["f_right"] and -1 or 1

end

local toticks = function(time)
	if not time then return 0 end -- @note inshallah fix.
	return math.floor(0.5 + time / globals.tickinterval())
end

local refs = {
    dt = {ui.reference("RAGE", "Aimbot", "Double tap")},
    hs = {ui.reference("AA", "Other", "On shot anti-aim")},

}

clamper = function(L_365_arg0)
	if L_365_arg0 > 180 then
		return -180 + L_365_arg0 - 180
	elseif L_365_arg0 < -180 then
		return 180 - (-180 - L_365_arg0)
	else
        return L_365_arg0
    end
end;

function clamp(x, min, max)
	return math.max(min, math.min(x, max))
end



local function getspeed(player_index)
    return vector(entity.get_prop(player_index, "m_vecVelocity")):length2d()
end

local function copysignf(x, y)
    local abs_x = math.abs(x)
    return (y < 0 or (y == 0 and 1 / y < 0)) and -abs_x or abs_x
end

client.set_event_callback('paint', function(c)
 	local scrsize_x, scrsize_y = client.screen_size()
	local center_x, center_y = scrsize_x / 2, scrsize_y / 2
    if ui.get(discharge_key) then
        renderer.text( center_x, center_y+20, 255, 255, 255, 255, "-", 0, "FAKE")
        --renderer.text( center_x, center_y+10, 255, 255, 255, 255, "-", 0, onShotFire)
        if is_flicking then
            renderer.text( center_x + 20, center_y+20, 0, 255, 0, 255, "-", 0, "SAFE")
        else
            renderer.text( center_x + 20, center_y+20, 255, 0, 0, 255, "-", 0, "UNSAFE")
        end
        if ui.get(lock_yaw) then
            renderer.text( center_x, center_y+10, 255, 255, 255, 200, "-", 0, "LOCK")
        end
    end
end)

local function angle_diff(destination, source)
    local delta = math.fmod(destination - source, 360.0)

    if destination > source then
        if delta >= 180.0 then
            delta = delta - 360.0
        end
    else
        if delta <= -180.0 then
            delta = delta + 360.0
        end
    end

    return delta
end

local function ticks_to_time(predicted)
	return globals.tickinterval( ) * predicted
end

local function vec_3( _x, _y, _z )
	return { x = _x or 0, y = _y or 0, z = _z or 0 }
end



client.set_event_callback("aim_fire", function (e)
    local me = entity.get_local_player(); if not me then return end
        onShotFire = 2
    --end
end)

local function player_will_peek( )
	local enemies = entity.get_players( true )
	if not enemies then
		return false
	end

	local eye_position = vec_3( client.eye_position( ) )
	local velocity_prop_local = vec_3( entity.get_prop( entity.get_local_player( ), "m_vecVelocity" ) )
	local predicted_eye_position = vec_3( eye_position.x + velocity_prop_local.x * ticks_to_time( 32 ), eye_position.y + velocity_prop_local.y * ticks_to_time( 32 ), eye_position.z + velocity_prop_local.z * ticks_to_time( 32 ) )

	for i = 1, #enemies do
		local player = enemies[ i ]

		local velocity_prop = vec_3( entity.get_prop( player, "m_vecVelocity" ) )

		-- Store and predict player origin
		local origin = vec_3( entity.get_prop( player, "m_vecOrigin" ) )
		local predicted_origin = vec_3( origin.x + velocity_prop.x * ticks_to_time(16), origin.y + velocity_prop.y * ticks_to_time(16), origin.z + velocity_prop.z * ticks_to_time(16) )

		-- Set their origin to their predicted origin so we can run calculations on it
		entity.get_prop( player, "m_vecOrigin", predicted_origin )

		-- Predict their head position and fire an autowall trace to see if any damage can be dealt
		local head_origin = vec_3( entity.hitbox_position( player, 0 ) )
		local predicted_head_origin = vec_3( head_origin.x + velocity_prop.x * ticks_to_time(16), head_origin.y + velocity_prop.y * ticks_to_time(16), head_origin.z + velocity_prop.z * ticks_to_time(16) )
		local trace_entity, damage = client.trace_bullet( entity.get_local_player( ), predicted_eye_position.x, predicted_eye_position.y, predicted_eye_position.z, predicted_head_origin.x, predicted_head_origin.y, predicted_head_origin.z )

        text3 = damage

		-- Restore their origin to their networked origin
		entity.get_prop( player, "m_vecOrigin", origin )

		-- Check if damage can be dealt to their predicted head
		if damage > 0 then
			return true
		end
	end

	return false
end

local function calculate_freestand()
    local local_player = entity.get_local_player()
    local eye_pos = vector(client.eye_position())
    local yaw = vector(client.camera_angles())
    local enemy = client.current_threat()
    local frac_num = {
        ["f_left"] = 0,
        ["f_right"] = 0
    }

    for i = yaw.y - 90, yaw.y + 90, 30 do
        if i ~= yaw.y then
            local rad = math.rad(i)
            local destination = vector(eye_pos.x + 256 * math.cos(rad), eye_pos.y + 256 * math.sin(rad), eye_pos.z)
            local trace, fraction = client.trace_line(local_player, eye_pos.x, eye_pos.y, eye_pos.z, destination.x, destination.y, destination.z)
            local side = i < yaw.y and "f_left" or "f_right"
            frac_num[side] = frac_num[side] + trace
        end
    end


	return frac_num["f_left"] > frac_num["f_right"] and -80 or 80

end

client.set_event_callback('setup_command', function(cmd)

    local lp = entity.get_local_player()
    if not lp then return end

	local lx,ly,lz = entity.get_prop(lp, "m_vecOrigin")
	if lx == nil then return end

    	-- get closest player to crosshair
	local players = entity.get_players(true)
	local pitch, yaw = client.camera_angles()
	local vx, vy, vz = angle_to_vec(pitch, yaw)

	local closest_fov_cos = -1
	enemyclosesttocrosshair = nil
	for i=1, #players do
		local idx = players[i]
		if entity.is_alive(idx) then
			local fov_cos = get_fov_cos(idx, vx,vy,vz, lx,ly,lz)
			if fov_cos > closest_fov_cos then
				closest_fov_cos = fov_cos
				enemyclosesttocrosshair = idx
			end
		end
	end

	local origin = {entity.get_prop(entity.get_local_player(), "m_vecOrigin")}
    if origin[1] ~= nil then origin[3] = origin[3] + entity.get_prop(entity.get_local_player(), "m_vecViewOffset[2]") end  -- Adjust Z position

	local origin_enemy = {entity.get_prop(enemyclosesttocrosshair, "m_vecOrigin")}
    if origin_enemy[1] ~= nil then origin_enemy[3] = origin_enemy[3] + entity.get_prop(enemyclosesttocrosshair, "m_vecViewOffset[2]") end -- Adjust Z position

    unpredicted_vel = getspeed(entity.get_local_player())

    local weaponn = entity.get_player_weapon()

	if weaponn ~= nil and entity.get_classname(weaponn) == "CC4" then
		if cmd.in_attack == 1 then
			cmd.in_attack = 0
			cmd.in_use = 1
		end
	else
		if cmd.chokedcommands == 0 then
			cmd.in_use = 0
		end
	end

    if unpredicted_vel > 0 then
        curtime = globals.curtime() + 0.22
        from_move = true
        from_stand = false
    else
        if globals.curtime() > curtime then curtime = globals.curtime() + 1.1 from_move = false from_stand = true end
    end

    local is_diagonal_pressed = ( is_button_pressed(inputsystem,29) or is_button_pressed(inputsystem,33) ) and ( is_button_pressed(inputsystem,11) or is_button_pressed(inputsystem,14) )

    local vel_clamp = is_diagonal_pressed and 75 or 125

    now_rt = globals.realtime()
	delay_last = delay_last or now_rt
	passed = toticks(now_rt - delay_last)

	if passed % 3 + 1 > 2 then
		do_jitter = not do_jitter
	end

    chooseside = calculate_freestand()
    local caca = 180 + (chooseside < 0 and -130 or 140)

    if player_will_peek() then curtime2 = globals.curtime() end

    local freestand_angle = calculate_freestand()

    if not ui.get(dt_key) and ui.get(discharge_key) and (not ui.get(enable_onpeek) or (ui.get(enable_onpeek) and(player_will_peek() or globals.curtime() < curtime2 + 1))) then
        is_flicking = true
		reenable_dt = true
        --ui.set(dt_ref, false)
        ui.set(sv_ui, is_alyx)
        cvar.sv_maxusrcmdprocessticks:set_int(is_alyx, true)
        ui.set(fl_amount, ui.get(discharge_flmode))
        if ui.get(force_choke) then
            cmd.allow_send_packet = false cmd.no_choke = false
            ui.set(fl_limit, is_alyx-1)
        else
            if onShotFire > 0 then
                onShotFire = onShotFire - 1
                ui.set(fl_limit, 1)
            else
                cmd.allow_send_packet = false cmd.no_choke = false
                ui.set(fl_limit, is_alyx-1)
            end
        end
		ui.set(aa_yaw_base, "At Targets")
        ui.set(aa_fake_yaw, "static")
        if ui.get(force_fs) then
            if not lock_bodyyaw then
                if ui.get(enable_hg) and origin[1] ~=  nil and origin_enemy[1] ~=  nil  and origin[3] + 120 < origin_enemy[3] then
                    ui.set(aa_fake_yaw_slider, freestand_angle)
                else
                    ui.set(aa_fake_yaw_slider, -freestand_angle)
                end
                ui.set(aa_yaw_offset, freestand_angle)
            end
        else
            if not lock_bodyyaw then
                ui.set(aa_fake_yaw_slider, chooseside < 0 and -60 or 60) --@robi or 56
                ui.set(aa_yaw_offset, chooseside < 0 and -10 or 10) --@robi -30 or 30
            end
        end
        if ui.get(lock_yaw) and not lock_bodyyaw then
            lock_bodyyaw = true
        end
        if ui.get(force_slowdown) then
            if cmd.forwardmove ~= nil then cmd.forwardmove = clamp(cmd.forwardmove, -vel_clamp,vel_clamp) end
            if cmd.sidemove ~= nil then cmd.sidemove = clamp(cmd.sidemove, -vel_clamp,vel_clamp) end 
        end 
    else
        is_flicking = false
        if ui.get(enable_def_aa) then
		    ui.set(aa_yaw_base, "At Targets")
            ui.set(aa_fake_yaw, "off")
            ui.set(aa_yaw_jitter_offset, 0)
		    ui.set(fl_amount, "Dynamic")
            ui.set(aa_yaw_offset, do_jitter and -25 or 40)
        end
        ui.set(sv_ui, 16)
        cvar.sv_maxusrcmdprocessticks:set_int(16, true)
        ui.set(fl_limit, 14)
		--if reenable_dt == true then
			--ui.set(dt_ref, true)
			reenable_dt = false
		--end
        lock_bodyyaw = false
    end

    if ui.get(fakewalk_key) and ui.get(discharge_key) then
		move_ticks = move_ticks + 1
        if cmd.forwardmove ~= nil then cmd.forwardmove = clamp(cmd.forwardmove, -25,25) end
        if cmd.sidemove ~= nil then cmd.sidemove = clamp(cmd.sidemove, -25,25) end
		if move_ticks > 10 then move_ticks = 0 end
        if move_ticks < 6 then cmd.forwardmove = 0 cmd.sidemove = 0 end
    end
end)
