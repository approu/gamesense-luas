local vector = require "vector"

local ref_dt, ref_dt_key = ui.reference("RAGE", "Aimbot", "Double tap")
local ref_dt_fl_limit = ui.reference("RAGE", "Aimbot", "Double tap fake lag limit")
local ref_min_damage = ui.reference("RAGE", "Aimbot", "Minimum damage")

local lua_enable = ui.new_checkbox("LUA", "B", "DT FL on Visible Vectors")
local lua_hotkey = ui.new_hotkey("LUA", "B", "DT FL Hotkey", true)
local menu_radius = ui.new_slider("LUA", "B", "Vector Radius", 10, 150, 50)
local menu_segments = ui.new_slider("LUA", "B", "Vector Segments", 4, 32, 8)
local menu_fl_amount = ui.new_slider("LUA", "B", "Target DT FL Limit", 0, 10, 10) -- Максимум 10!

local is_hit_active = false
local original_limit = 1 

local function reset_fakelag()
    if is_hit_active then
        is_hit_active = false
        local safe_original = math.max(0, math.min(10, original_limit))
        ui.set(ref_dt_fl_limit, safe_original)
        client.color_log(255, 100, 100, "[FL Debug] Reset DT Fake Lag limit to: " .. tostring(safe_original))
    end
end

local function generate_3d_vectors(origin, radius, segments)
    local points = {}
    local angle_step = 360 / segments
    for i = 0, segments - 1 do
        local rad = math.rad(i * angle_step)
        local vec_point = vector(
            origin.x + math.cos(rad) * radius,
            origin.y + math.sin(rad) * radius,
            origin.z
        )
        table.insert(points, vec_point)
    end
    return points
end

local function check_vector_visibility(points)
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return false end

    local target = client.current_threat()
    if not target or not entity.is_alive(target) then return false end

    local enemy_x, enemy_y, enemy_z = entity.hitbox_position(target, 0)
    if not enemy_x then return false end

    local min_dmg = ui.get(ref_min_damage)

    for i = 1, #points do
        local pt = points[i]
        local _, damage = client.trace_bullet(me, pt.x, pt.y, pt.z, enemy_x, enemy_y, enemy_z)
        if damage >= min_dmg then
            return true
        end
    end

    return false
end

client.set_event_callback("setup_command", function()
    if not ui.get(lua_enable) or not ui.get(lua_hotkey) then
        reset_fakelag()
        return
    end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        reset_fakelag()
        return
    end

    local dt_active = ui.get(ref_dt) and ui.get(ref_dt_key)
    local eye_x, eye_y, eye_z = client.eye_position()
    local my_origin = vector(eye_x, eye_y, eye_z)

    local generated_points = generate_3d_vectors(my_origin, ui.get(menu_radius), ui.get(menu_segments))
    local is_visible = check_vector_visibility(generated_points)

    if is_visible and dt_active then
        if not is_hit_active then
            original_limit = ui.get(ref_dt_fl_limit)
            is_hit_active = true
            local target_limit = math.max(0, math.min(10, ui.get(menu_fl_amount)))
            ui.set(ref_dt_fl_limit, target_limit)
            
            client.color_log(100, 255, 100, "[FL Debug] Vector visible! Applied DT Fake Lag limit: " .. tostring(target_limit))
        end
    else
        reset_fakelag()
    end
end)

client.set_event_callback("round_start", reset_fakelag)
client.set_event_callback("player_death", function(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then
        reset_fakelag()
    end
end)
-- making fakelag on peek so you'll not get hit by awp etc
