-- ============================================================
--  phantom.lua  |  FIXED DEBUG VERSION  |  by maro
-- ============================================================
--[[
  .name    phantom
  .author  maro
  .version 1.1-fixed
]]

print("[phantom] Script wird geladen (top-level)")

local lib = nil
local C = {}
local F = {}
local M = {}
local EA = "lua>elements a"
local EB = "lua>elements b"

local _ready = false
local _init_attempts = 0
local _last_init_error = nil
local _notified_ready = false
local _gui_mode = "legacy"
local _group_cache = {}
local _pcall = _G and _G.pcall or nil
local _color_defaults_applied = false

local WEAPON_NAMES = {
    [1] = "Deagle",
    [7] = "AK-47",
    [9] = "AWP",
    [16] = "M4A4",
    [60] = "M4A1-S",
}

local cheaters = {}
local bb_names = {}
local stats = { kills = 0, deaths = 0, assists = 0, damage = 0, hs = 0, shots = 0, hits = 0 }
local dmg_log = {}
local hm_hits = {}
local ct_frame = 0
local ct_blink = true
local ct_tw = 1
local ct_fwd = true
local DB = "phantom_config.db"
local SHOT_LOG = "phantom_shots.txt"
local AX_FILE = "phantom_autoexec.cfg"

local function wpn_name(idx)
    return WEAPON_NAMES[idx] or ("wpn#" .. tostring(idx))
end

local function log_init_error(msg)
    if _last_init_error ~= msg then
        _last_init_error = msg
        print("[phantom] init fehlgeschlagen: " .. tostring(msg))
    end
end

local function try_call(fn, ...)
    if _pcall then
        return _pcall(fn, ...)
    end

    return true, fn(...)
end

local function detect_gui_mode()
    if gui and gui.control_id and gui.make_control and gui.ctx and gui.ctx.find then
        _gui_mode = "modern"
    else
        _gui_mode = "legacy"
    end
end

local function ctrl_get(ctrl, default)
    if not ctrl then
        return default
    end

    if ctrl.get then
        local ok, value = try_call(ctrl.get, ctrl)
        if ok then
            return value
        end
    end

    if ctrl.get_value then
        local ok, holder = try_call(ctrl.get_value, ctrl)
        if ok and holder and holder.get then
            local ok_value, value = try_call(holder.get, holder)
            if ok_value then
                return value
            end
        end
    end

    if ctrl.value ~= nil then
        return ctrl.value
    end

    return default
end

local function ctrl_set(ctrl, value)
    if not ctrl then
        return false
    end

    if ctrl.set then
        local ok = try_call(ctrl.set, ctrl, value)
        if ok then
            return true
        end
    end

    if ctrl.set_value then
        local ok = try_call(ctrl.set_value, ctrl, value)
        if ok then
            return true
        end
    end

    if ctrl.set_text and type(value) == "string" then
        local ok = try_call(ctrl.set_text, ctrl, value)
        if ok then
            return true
        end
    end

    return false
end

local function get_group(container_id)
    if _group_cache[container_id] then
        return _group_cache[container_id]
    end

    if _gui_mode ~= "modern" then
        return nil
    end

    local ok, group = try_call(gui.ctx.find, gui.ctx, container_id)
    if ok and group then
        _group_cache[container_id] = group
        return group
    end

    return nil
end

local function add_modern_control(container_id, label, control, extras)
    local group = get_group(container_id)
    if not group or not control then
        return control
    end

    local row = gui.make_control(label or "", control)
    if extras then
        for _, extra in ipairs(extras) do
            if extra then
                try_call(row.add, row, extra)
            end
        end
    end

    try_call(group.add, group, row)
    return control
end

local function mk_checkbox(id, container, label)
    if _gui_mode == "modern" then
        local modern_id = gui.control_id(id)
        local control = gui.checkbox(modern_id)
        return add_modern_control(container, label, control)
    end

    return gui.checkbox(id, container, label)
end

local function mk_color_picker(id, container, label, default, allow_alpha)
    if _gui_mode == "modern" then
        local modern_id = gui.control_id(id)
        local control = gui.color_picker(modern_id, allow_alpha ~= false)
        if default ~= nil then
            ctrl_set(control, default)
        end
        return add_modern_control(container, label, control)
    end

    return gui.color_picker(id, container, label, default, allow_alpha)
end

local function mk_slider(id, container, label, min_value, max_value)
    if _gui_mode == "modern" then
        local modern_id = gui.control_id(id)
        local control = gui.slider(modern_id, min_value, max_value, {"%.0f"})
        return add_modern_control(container, label, control)
    end

    return gui.slider(id, container, label, min_value, max_value)
end

local function mk_textbox(id, container, label)
    if _gui_mode == "modern" then
        local modern_id = gui.control_id(id)
        local control = gui.text_input(modern_id)
        return add_modern_control(container, label or "", control)
    end

    return gui.textbox(id, container)
end

local function mk_button(id, container, label)
    if _gui_mode == "modern" then
        local modern_id = gui.control_id(id)
        local control = gui.button(modern_id, label)
        return add_modern_control(container, label, control)
    end

    return gui.button(id, container, label)
end

local function mk_combobox(id, container, label, allow_multiple, ...)
    local items = { ... }

    if _gui_mode == "modern" and gui.combo_box and gui.selectable then
        local modern_id = gui.control_id(id)
        local control = gui.combo_box(modern_id)
        control.allow_multiple = allow_multiple and true or false
        for i, item in ipairs(items) do
            local sel = gui.selectable(gui.control_id(id .. ">sel" .. tostring(i)), item)
            try_call(control.add, control, sel)
        end
        return add_modern_control(container, label, control)
    end

    return gui.combobox(id, container, allow_multiple, label, ...)
end

local function mk_list(id, container, label, allow_multiple, visible_items)
    if _gui_mode == "modern" and gui.combo_box then
        local modern_id = gui.control_id(id)
        local control = gui.combo_box(modern_id)
        control.allow_multiple = allow_multiple and true or false
        return add_modern_control(container, label, control)
    end

    return gui.list(id, container, label, allow_multiple, visible_items)
end

local function try_load_file(path)
    if not utils or not utils.load_file then
        return nil
    end

    local ok, content = try_call(utils.load_file, path)
    if not ok then
        print("[phantom] utils.load_file Fehler bei '" .. tostring(path) .. "': " .. tostring(content))
        return nil
    end

    return content
end

local function load_phantom_lib()
    local candidates = {
        "fatality/scripts/phantom_lib.lua",
        "fatality\\scripts\\phantom_lib.lua",
        "phantom_lib.lua",
        ".\\phantom_lib.lua",
    }

    for _, path in ipairs(candidates) do
        local content = try_load_file(path)
        if content and #content > 0 then
            local chunk, err = load(content, "@phantom_lib.lua")
            if not chunk then
                return nil, "phantom_lib.lua konnte nicht kompiliert werden: " .. tostring(err)
            end

            local ok, result = try_call(chunk)
            if not ok then
                return nil, "phantom_lib.lua Laufzeitfehler: " .. tostring(result)
            end

            if type(result) ~= "table" then
                return nil, "phantom_lib.lua hat keine Tabelle zurueckgegeben"
            end

            print("[phantom] phantom_lib.lua geladen aus: " .. path)
            return result
        end
    end

    return nil, "phantom_lib.lua nicht gefunden"
end

local function ensure_runtime()
    if _ready then
        return true
    end

    _init_attempts = _init_attempts + 1

    if not gui then
        log_init_error("gui ist nil")
        return false
    end

    if not render then
        log_init_error("render ist nil")
        return false
    end

    if not mat then
        log_init_error("mat ist nil")
        return false
    end

    if not utils then
        log_init_error("utils ist nil")
        return false
    end

    if not utils.load_file then
        log_init_error("utils.load_file ist noch nicht verfuegbar")
        return false
    end

    if not lib then
        local loaded_lib, err = load_phantom_lib()
        if not loaded_lib then
            log_init_error(err)
            return false
        end

        lib = loaded_lib
    end

    if not F.esp then
        F.esp = render.create_font("verdana.ttf", 11, render.font_flag_outline)
        F.hud = render.create_font("verdana.ttf", 12, render.font_flag_outline)
        F.big = render.create_font("verdana.ttf", 13, render.font_flag_outline)
    end

    if not M.vis then
        M.vis = mat.create("phantom_vis", "VertexLitGeneric", [[
"VertexLitGeneric" { "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "0" "$model" "1" }
]])
        M.wall = mat.create("phantom_wall", "VertexLitGeneric", [[
"VertexLitGeneric" { "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "1" "$model" "1" "$additive" "1" }
]])
    end

    if not _color_defaults_applied then
        _color_defaults_applied = true
        ctrl_set(C.col_box_e, render.color("#DC3C3C"))
        ctrl_set(C.col_box_v, render.color("#3CFF3C"))
        ctrl_set(C.col_hm, render.color("#FF5050"))
        ctrl_set(C.col_cheater, render.color("#FFFF00"))
    end

    if lib.timer then
        lib.timer.every(200, function()
            if not C.ct_tag then
                return
            end

            local tag = ctrl_get(C.ct_tag, "") or ""
            local mode = ctrl_get(C.ct_mode, "Static") or "Static"
            ct_frame = ct_frame + 1
            ct_blink = not ct_blink

            if not C.ct_enable or not ctrl_get(C.ct_enable, false) then
                utils.set_clan_tag("")
                return
            end

            if mode == "Scroll" and #tag > 0 then
                local o = ct_frame % #tag
                utils.set_clan_tag(tag:sub(o + 1) .. tag:sub(1, o))
            elseif mode == "Blink" then
                utils.set_clan_tag(ct_blink and tag or "")
            elseif mode == "Typewriter" then
                if #tag == 0 then
                    utils.set_clan_tag("")
                else
                    if ct_fwd then
                        ct_tw = math.min(#tag, ct_tw + 1)
                        if ct_tw >= #tag then
                            ct_fwd = false
                        end
                    else
                        ct_tw = math.max(1, ct_tw - 1)
                        if ct_tw <= 1 then
                            ct_fwd = true
                        end
                    end

                    utils.set_clan_tag(tag:sub(1, ct_tw))
                end
            else
                utils.set_clan_tag(tag)
            end
        end)

        lib.timer.every(2000, function()
            bb_names = {}

            if not entities or not entities.for_each_player or not lib.player or not lib.player.local_ent then
                return
            end

            local _, local_idx = lib.player.local_ent()
            entities.for_each_player(function(pl)
                if not pl:is_valid() then
                    return
                end

                if pl:get_index() == local_idx then
                    return
                end

                if (pl:get_prop("m_iHealth") or 0) <= 0 then
                    return
                end

                bb_names[lib.player.name(pl, 24)] = pl:get_index()
            end)
        end)
    end

    _ready = true
    _last_init_error = nil

    if not _notified_ready and gui.add_notification then
        _notified_ready = true
        gui.add_notification("phantom", "Init erfolgreich")
    end

    print("[phantom] init erfolgreich nach Versuch #" .. tostring(_init_attempts))
    return true
end

-- Top-level GUI creation bleibt absichtlich hier, damit die Elemente sofort sichtbar sind.
detect_gui_mode()
print("[phantom] GUI-Modus: " .. _gui_mode)

C.debug_test = mk_checkbox(EA .. ">debug_test", EA, "DEBUG: Script geladen!")

C.v_enable = mk_checkbox(EA .. ">v_en", EA, "Enable Visuals")
C.v_watermark = mk_checkbox(EA .. ">v_wm", EA, "Watermark")
C.v_esp_box = mk_checkbox(EA .. ">v_box", EA, "ESP Box")
C.v_esp_hp = mk_checkbox(EA .. ">v_hp", EA, "Health Bar")
C.v_esp_name = mk_checkbox(EA .. ">v_nm", EA, "Name Flag")
C.v_esp_dist = mk_checkbox(EA .. ">v_di", EA, "Distance Flag")
C.v_hitmarker = mk_checkbox(EA .. ">v_hm", EA, "Hit Marker")
C.v_chams = mk_checkbox(EA .. ">v_ch", EA, "Chams")
C.v_stats = mk_checkbox(EA .. ">v_st", EA, "Session Stats")
C.v_dmg_log = mk_checkbox(EA .. ">v_dl", EA, "Damage Log")

C.col_box_e = mk_color_picker(EA .. ">cbe", EA, "Enemy Box", nil, true)
C.col_box_v = mk_color_picker(EA .. ">cbv", EA, "Visible Box", nil, true)
C.col_hm = mk_color_picker(EA .. ">chm", EA, "Hit Marker", nil, true)

C.ct_enable = mk_checkbox(EA .. ">ct_on", EA, "Clan Tag Enable")
C.ct_tag = mk_textbox(EA .. ">ct_tag", EA, "Clan Tag")
C.ct_mode = mk_combobox(EA .. ">ct_mo", EA, "CT Animation", false, "Static", "Scroll", "Blink", "Wave", "Typewriter")
C.ct_speed = mk_slider(EA .. ">ct_sp", EA, "CT Speed (ms)", 50, 1000)
ctrl_set(C.ct_tag, "fatality.win")
ctrl_set(C.ct_speed, 200)

C.m_rtt = mk_checkbox(EA .. ">m_rtt", EA, "RTT / Ping")
C.m_speedo = mk_checkbox(EA .. ">m_spd", EA, "Speedometer")
C.m_crosshair = mk_checkbox(EA .. ">m_xhair", EA, "Custom Crosshair")
C.m_cross_size = mk_slider(EA .. ">m_xsz", EA, "Crosshair Size", 2, 20)
C.m_cross_gap = mk_slider(EA .. ">m_xgap", EA, "Crosshair Gap", 0, 15)
ctrl_set(C.m_cross_size, 6)
ctrl_set(C.m_cross_gap, 4)

C.bb_enable = mk_checkbox(EB .. ">bb_en", EB, "Blockbot Enable")
C.bb_dist = mk_slider(EB .. ">bb_di", EB, "Blockbot Distance", 20, 80)
C.bb_player = mk_list(EB .. ">bb_pl", EB, "Blockbot Target", false, 100)
ctrl_set(C.bb_dist, 40)

C.ch_enable = mk_checkbox(EB .. ">ch_en", EB, "Cheater System")
C.ch_list = mk_list(EB .. ">ch_li", EB, "Marked Cheaters", false, 80)
C.col_cheater = mk_color_picker(EB .. ">ch_co", EB, "Cheater Color", nil, true)

C.cfg_save = mk_button(EB .. ">csave", EB, "Save Config")
C.cfg_load = mk_button(EB .. ">cload", EB, "Load Config")

function on_game_event(event)
    if not ensure_runtime() then
        return
    end

    local ename = event:get_name()
    local local_idx = engine.get_local_player()

    if ename == "player_hurt" and event:get_int("attacker") == local_idx then
        stats.damage = stats.damage + (event:get_int("dmg_health") or 0)
    end

    if ename == "player_death" then
        if event:get_int("attacker") == local_idx then
            stats.kills = stats.kills + 1
        end

        if event:get_int("userid") == local_idx then
            stats.deaths = stats.deaths + 1
        end
    end
end

function on_level_init()
    if not ensure_runtime() then
        return
    end

    stats = { kills = 0, deaths = 0, assists = 0, damage = 0, hs = 0, shots = 0, hits = 0 }
    hm_hits = {}
    dmg_log = {}
    cheaters = {}
    bb_names = {}
end

function on_draw_model_execute(dme, ent_index, model_name)
    if not ensure_runtime() then
        dme()
        return
    end

    local local_idx = engine.get_local_player()
    if ent_index == local_idx then
        dme()
        return
    end

    if not model_name or not model_name:find("models/player") then
        dme()
        return
    end

    local ent = entities.get_entity(ent_index)
    if not ent or not ent:is_valid() then
        dme()
        return
    end

    local lp = entities.get_entity(local_idx)
    local lteam = lp and lp:get_prop("m_iTeamNum") or 0
    if ent:get_prop("m_iTeamNum") == lteam then
        dme()
        return
    end

    if C.v_chams and ctrl_get(C.v_chams, false) then
        M.vis:modulate(render.color("#FF4444"))
        mat.override_material(M.vis)
    end

    dme()
end

function on_create_move(cmd, send_packet)
    ensure_runtime()
end

function on_paint()
    if not ensure_runtime() then
        return
    end

    if not engine.is_in_game() then
        return
    end

    local sw = select(1, render.get_screen_size())

    render.text(
        F.hud,
        10,
        10,
        string.format("[phantom] on_paint aktiv | ready=%s", tostring(_ready)),
        render.color(255, 100, 100),
        render.align_left,
        render.align_top
    )

    if C.v_watermark and ctrl_get(C.v_watermark, false) then
        local info = engine.get_player_info(engine.get_local_player())
        local uname = (info and info.name) or "unknown"
        local wm = "phantom  |  " .. uname
        local tw, th = render.get_text_size(F.big, wm)
        local px, py = sw - tw - 38, 26

        render.rect_filled(px - 7, py - 5, px + tw + 7, py + th + 5, render.color(10, 10, 20, 210))
        render.rect(px - 7, py - 5, px + tw + 7, py + th + 5, render.color(120, 60, 220, 200))
        render.text(F.big, px, py, wm, render.color(200, 160, 255), render.align_left, render.align_top)
    end

    if C.v_stats and ctrl_get(C.v_stats, false) then
        render.text(
            F.hud,
            sw - 120,
            60,
            string.format("K:%d D:%d DMG:%d", stats.kills, stats.deaths, stats.damage),
            render.color(200, 200, 200),
            render.align_left,
            render.align_top
        )
    end
end

function on_esp_flag(index)
    if not ensure_runtime() then
        return {}
    end

    return {}
end

function on_console_input(input)
    if input == "ph_debug" then
        print("[phantom] Status:")
        print("  _ready = " .. tostring(_ready))
        print("  _init_attempts = " .. tostring(_init_attempts))
        print("  _last_init_error = " .. tostring(_last_init_error))
        print("  lib = " .. tostring(lib))
        print("  utils = " .. tostring(utils))
        print("  utils.load_file = " .. tostring(utils and utils.load_file))
        print("  render = " .. tostring(render))
        print("  gui = " .. tostring(gui))
        print("  mat = " .. tostring(mat))
        if lib then
            print("  lib._version = " .. tostring(lib._version or "?"))
        end
    end
end

function on_config_save()
end

function on_config_load()
end

print("[phantom] Script vollstaendig geparsed - warte auf Fatality Callbacks")
print("[phantom] GUI wurde top-level erstellt, Runtime wird lazy initialisiert")
