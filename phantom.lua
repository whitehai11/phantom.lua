-- ============================================================
--  phantom.lua  |  DEBUG VERSION  |  by maro
-- ============================================================
--[[
  .name    phantom
  .author  maro
  .version 1.0-debug
]]

-- ============================================================
--  Schritt 1: Script wird geparsed
--  Wenn diese Zeile in der Console erscheint → Script laeuft
-- ============================================================
print("[phantom DEBUG] Script wird geladen (top-level)")

local _ready  = false
local _init_tried = false
local lib     = nil
local C       = {}
local F       = {}
local M       = {}
local EA      = 'lua>elements a'
local EB      = 'lua>elements b'

-- Weapon Names (reines Lua, kein API)
local WEAPON_NAMES = {
    [1]='Deagle',[7]='AK-47',[9]='AWP',[16]='M4A4',[60]='M4A1-S',
}
local function wpn_name(idx)
    return WEAPON_NAMES[idx] or ('wpn#'..tostring(idx))
end

local cheaters = {}
local bb_names = {}
local stats    = {kills=0,deaths=0,assists=0,damage=0,hs=0,shots=0,hits=0}
local dmg_log  = {}
local hm_hits  = {}
local ct_frame = 0; local ct_blink = true; local ct_tw = 1; local ct_fwd = true
local DB       = "phantom_config.db"
local SHOT_LOG = "phantom_shots.txt"
local AX_FILE  = "phantom_autoexec.cfg"

print("[phantom DEBUG] Variablen initialisiert")

-- ============================================================
--  INIT FUNKTION
-- ============================================================
local function init()
    if _ready then return true end
    if _init_tried then return false end  -- verhindert endlos-retry
    _init_tried = true

    print("[phantom DEBUG] init() wird ausgefuehrt...")

    -- utils verfuegbar?
    if not utils then
        print("[phantom DEBUG] FEHLER: utils ist nil!")
        return false
    end
    print("[phantom DEBUG] utils ist verfuegbar")

    -- utils.load_file verfuegbar?
    if not utils.load_file then
        print("[phantom DEBUG] FEHLER: utils.load_file ist nil!")
        return false
    end
    print("[phantom DEBUG] utils.load_file ist verfuegbar")

    -- Library laden
    print("[phantom DEBUG] Versuche phantom_lib.lua zu laden...")
    local content = utils.load_file("fatality/scripts/phantom_lib.lua")
    if not content then
        print("[phantom DEBUG] FEHLER: phantom_lib.lua nicht gefunden!")
        print("[phantom DEBUG] Pfad versucht: fatality/scripts/phantom_lib.lua")
        -- Zweiten Pfad versuchen
        content = utils.load_file("fatality\\scripts\\phantom_lib.lua")
        if not content then
            print("[phantom DEBUG] FEHLER: Auch mit Backslash nicht gefunden!")
            return false
        else
            print("[phantom DEBUG] Mit Backslash gefunden!")
        end
    else
        print("[phantom DEBUG] phantom_lib.lua gefunden, Laenge: "..#content)
    end

    local chunk, err = load(content)
    if not chunk then
        print("[phantom DEBUG] FEHLER beim Kompilieren der Lib: "..tostring(err))
        return false
    end
    print("[phantom DEBUG] Lib kompiliert")

    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then
        print("[phantom DEBUG] FEHLER beim Ausfuehren der Lib: "..tostring(result))
        return false
    end
    lib = result
    print("[phantom DEBUG] Lib geladen: v"..(lib._version or "?"))

    -- render verfuegbar?
    if not render then
        print("[phantom DEBUG] FEHLER: render ist nil!")
        return false
    end
    print("[phantom DEBUG] render ist verfuegbar")

    -- gui verfuegbar?
    if not gui then
        print("[phantom DEBUG] FEHLER: gui ist nil!")
        return false
    end
    print("[phantom DEBUG] gui ist verfuegbar")

    -- mat verfuegbar?
    if not mat then
        print("[phantom DEBUG] FEHLER: mat ist nil!")
        return false
    end
    print("[phantom DEBUG] mat ist verfuegbar")

    -- Fonts
    print("[phantom DEBUG] Erstelle Fonts...")
    F.esp = render.create_font("verdana.ttf", 11, render.font_flag_outline)
    F.hud = render.create_font("verdana.ttf", 12, render.font_flag_outline)
    F.big = render.create_font("verdana.ttf", 13, render.font_flag_outline)
    print("[phantom DEBUG] Fonts erstellt")

    -- Materials
    print("[phantom DEBUG] Erstelle Materials...")
    M.vis = mat.create("phantom_vis","VertexLitGeneric",[[
"VertexLitGeneric"{ "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "0" "$model" "1" }]])
    M.wall = mat.create("phantom_wall","VertexLitGeneric",[[
"VertexLitGeneric"{ "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "1" "$model" "1" "$additive" "1" }]])
    print("[phantom DEBUG] Materials erstellt")

    -- GUI
    print("[phantom DEBUG] Erstelle GUI Controls in '"..EA.."'...")

    -- Test: erstmal nur eine einzige Checkbox
    local test_cb = gui.checkbox(EA..'>debug_test', EA, 'DEBUG: Script geladen!')
    if test_cb then
        print("[phantom DEBUG] Test-Checkbox erstellt! Typ: "..type(test_cb))
    else
        print("[phantom DEBUG] FEHLER: Test-Checkbox ist nil!")
    end

    -- Weitere Controls
    C.v_enable    = gui.checkbox(EA..'>v_en',  EA, 'Enable Visuals')
    C.v_watermark = gui.checkbox(EA..'>v_wm',  EA, 'Watermark')
    C.v_esp_box   = gui.checkbox(EA..'>v_box', EA, 'ESP Box')
    C.v_esp_hp    = gui.checkbox(EA..'>v_hp',  EA, 'Health Bar')
    C.v_esp_name  = gui.checkbox(EA..'>v_nm',  EA, 'Name Flag')
    C.v_esp_dist  = gui.checkbox(EA..'>v_di',  EA, 'Distance Flag')
    C.v_hitmarker = gui.checkbox(EA..'>v_hm',  EA, 'Hit Marker')
    C.v_chams     = gui.checkbox(EA..'>v_ch',  EA, 'Chams')
    C.v_stats     = gui.checkbox(EA..'>v_st',  EA, 'Session Stats')
    C.v_dmg_log   = gui.checkbox(EA..'>v_dl',  EA, 'Damage Log')

    C.col_box_e   = gui.color_picker(EA..'>cbe', EA, 'Enemy Box',   render.color('#DC3C3C'), true)
    C.col_box_v   = gui.color_picker(EA..'>cbv', EA, 'Visible Box', render.color('#3CFF3C'), true)
    C.col_hm      = gui.color_picker(EA..'>chm', EA, 'Hit Marker',  render.color('#FF5050'), true)

    C.ct_enable = gui.checkbox( EA..'>ct_on',  EA, 'Clan Tag Enable')
    C.ct_tag    = gui.textbox(  EA..'>ct_tag', EA)
    C.ct_mode   = gui.combobox( EA..'>ct_mo',  EA, 'CT Animation', false,
        'Static','Scroll','Blink','Wave','Typewriter')
    C.ct_speed  = gui.slider(   EA..'>ct_sp',  EA, 'CT Speed (ms)', 50, 1000)
    C.ct_tag:set('fatality.win')
    C.ct_speed:set(200)

    C.m_rtt        = gui.checkbox(EA..'>m_rtt',  EA, 'RTT / Ping')
    C.m_speedo     = gui.checkbox(EA..'>m_spd',  EA, 'Speedometer')
    C.m_crosshair  = gui.checkbox(EA..'>m_xhair',EA, 'Custom Crosshair')
    C.m_cross_size = gui.slider(  EA..'>m_xsz',  EA, 'Crosshair Size', 2, 20)
    C.m_cross_gap  = gui.slider(  EA..'>m_xgap', EA, 'Crosshair Gap',  0, 15)
    C.m_cross_size:set(6); C.m_cross_gap:set(4)

    print("[phantom DEBUG] Elements A Controls erstellt")

    -- Elements B
    print("[phantom DEBUG] Erstelle GUI Controls in '"..EB.."'...")
    C.bb_enable = gui.checkbox(EB..'>bb_en', EB, 'Blockbot Enable')
    C.bb_dist   = gui.slider(  EB..'>bb_di', EB, 'Blockbot Distance', 20, 80)
    C.bb_player = gui.list(    EB..'>bb_pl', EB, 'Blockbot Target', false, 100)
    C.bb_dist:set(40)

    C.ch_enable   = gui.checkbox(    EB..'>ch_en', EB, 'Cheater System')
    C.ch_list     = gui.list(        EB..'>ch_li', EB, 'Marked Cheaters', false, 80)
    C.col_cheater = gui.color_picker(EB..'>ch_co', EB, 'Cheater Color', render.color('#FFFF00'), true)

    C.cfg_save  = gui.button(EB..'>csave',  EB, 'Save Config')
    C.cfg_load  = gui.button(EB..'>cload',  EB, 'Load Config')

    print("[phantom DEBUG] Elements B Controls erstellt")

    -- Timers
    lib.timer.every(200, function()
        if not C.ct_tag then return end
        local tag  = C.ct_tag:get()  or ''
        local mode = C.ct_mode and C.ct_mode:get() or 'Static'
        ct_frame=ct_frame+1; ct_blink=not ct_blink
        if not C.ct_enable or not C.ct_enable:get() then
            utils.set_clan_tag(''); return
        end
        if mode=='Scroll' and #tag>0 then
            local o=ct_frame%#tag
            utils.set_clan_tag(tag:sub(o+1)..tag:sub(1,o))
        else
            utils.set_clan_tag(tag)
        end
    end)

    lib.timer.every(2000, function()
        bb_names = {}
        if not lib then return end
        local _,li = lib.player.local_ent()
        entities.for_each_player(function(pl)
            if not pl:is_valid() then return end
            if pl:get_index()==li then return end
            if (pl:get_prop("m_iHealth") or 0)<=0 then return end
            bb_names[lib.player.name(pl,24)] = pl:get_index()
        end)
    end)

    _ready = true
    print("[phantom DEBUG] init() ERFOLGREICH abgeschlossen!")
    gui.add_notification('phantom DEBUG', 'Init erfolgreich!')
    return true
end

-- ============================================================
--  CALLBACKS
-- ============================================================
function on_game_event(event)
    if not init() then return end
    local ename = event:get_name()
    local local_idx = engine.get_local_player()
    if ename=='player_hurt' and event:get_int('attacker')==local_idx then
        stats.damage = stats.damage + (event:get_int('dmg_health') or 0)
    end
    if ename=='player_death' then
        if event:get_int('attacker')==local_idx then stats.kills=stats.kills+1 end
        if event:get_int('userid')==local_idx   then stats.deaths=stats.deaths+1 end
    end
end

function on_level_init()
    print("[phantom DEBUG] on_level_init() aufgerufen")
    if not init() then
        print("[phantom DEBUG] init() in on_level_init fehlgeschlagen!")
        return
    end
    stats   = {kills=0,deaths=0,assists=0,damage=0,hs=0,shots=0,hits=0}
    hm_hits = {}
    dmg_log = {}
end

function on_draw_model_execute(dme, ent_index, model_name)
    if not _ready then dme(); return end
    local local_idx = engine.get_local_player()
    if ent_index==local_idx then dme(); return end
    if not model_name:find("models/player") then dme(); return end
    local ent = entities.get_entity(ent_index)
    if not ent or not ent:is_valid() then dme(); return end
    local lp    = entities.get_entity(local_idx)
    local lteam = lp and lp:get_prop("m_iTeamNum") or 0
    if ent:get_prop("m_iTeamNum")==lteam then dme(); return end
    if C.v_chams and C.v_chams:get() then
        M.vis:modulate(render.color('#FF4444'))
        mat.override_material(M.vis)
    end
    dme()
end

function on_create_move(cmd, send_packet)
    if not init() then return end
end

function on_paint()
    print("[phantom DEBUG] on_paint() aufgerufen")  -- wird einmalig geloggt
    if not init() then
        print("[phantom DEBUG] init() in on_paint fehlgeschlagen!")
        return
    end
    if not engine.is_in_game() then return end

    local sw,sh = render.get_screen_size()

    -- Immer ein Debug-Overlay zeichnen um zu sehen ob on_paint laeuft
    render.text(F.hud, 10, 10,
        string.format('[phantom DEBUG] on_paint laeuft | ready=%s', tostring(_ready)),
        render.color(255,100,100), render.align_left, render.align_top)

    if not C.v_watermark then return end

    if C.v_watermark:get() then
        local info  = engine.get_player_info(engine.get_local_player())
        local uname = (info and info.name) or 'unknown'
        local wm    = 'phantom  |  '..uname
        local tw,th = render.get_text_size(F.big, wm)
        local px,py = sw-tw-38, 26
        render.rect_filled(px-7,py-5,px+tw+7,py+th+5, render.color(10,10,20,210))
        render.rect(px-7,py-5,px+tw+7,py+th+5, render.color(120,60,220,200))
        render.text(F.big,px,py,wm, render.color(200,160,255), render.align_left, render.align_top)
    end

    if C.v_stats and C.v_stats:get() then
        render.text(F.hud, sw-120, 60,
            string.format('K:%d D:%d DMG:%d', stats.kills, stats.deaths, stats.damage),
            render.color(200,200,200), render.align_left, render.align_top)
    end
end

function on_esp_flag(index)
    if not _ready then return {} end
    return {}
end

function on_console_input(input)
    local cmd = input:match('^(%S+)')
    if cmd == 'ph_debug' then
        print("[phantom DEBUG] Status:")
        print("  _ready = "..tostring(_ready))
        print("  _init_tried = "..tostring(_init_tried))
        print("  lib = "..tostring(lib))
        print("  utils = "..tostring(utils))
        print("  render = "..tostring(render))
        print("  gui = "..tostring(gui))
        if lib then
            print("  lib._version = "..(lib._version or "?"))
        end
    end
end

function on_config_save() end
function on_config_load() end

print("[phantom DEBUG] Script vollstaendig geparsed – warte auf ersten Callback")
