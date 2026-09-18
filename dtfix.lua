local ref_dt, ref_dt_key = ui.reference("RAGE", "Aimbot", "Double tap")
local ref_fl_limit = ui.reference("AA", "Fake lag", "Limit")

local lua_enable = ui.new_checkbox("LUA", "B", "Fake lag on DT (HIT)")
local lua_hotkey = ui.new_hotkey("LUA", "B", "Fake lag DT Hotkey", true)

local is_hit_active = false
local hit_time = 0
local original_limit = 14

local function reset_fakelag()
    if is_hit_active then
        is_hit_active = false
        ui.set(ref_fl_limit, original_limit)
    end
end

client.set_event_callback("player_hurt", function(e)
    if client.userid_to_entindex(e.attacker) == entity.get_local_player() then
        if not is_hit_active then
            original_limit = ui.get(ref_fl_limit)
        end
        is_hit_active = true
        hit_time = globals.curtime()
    end
end)

client.set_event_callback("setup_command", function()
    if not ui.get(lua_enable) or not ui.get(lua_hotkey) then
        reset_fakelag()
        return
    end

    if is_hit_active and ui.get(ref_dt) and ui.get(ref_dt_key) then
        ui.set(ref_fl_limit, 10)
        if globals.curtime() - hit_time > 0.5 then
            reset_fakelag()
        end
    else
        reset_fakelag()
    end
end)

client.set_event_callback("round_start", reset_fakelag)
-- making fakelag on peek so you'll not get hit by awp etc
