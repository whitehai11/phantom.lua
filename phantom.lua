-- ============================================================
--  phantom.lua  |  Fatality Lua API  |  by maro  |  v1.0
-- ============================================================
--[[
  .name    phantom
  .author  maro
  .version 1.0
]]

-- ============================================================
--  PURE LUA STATE ONLY
-- ============================================================
local lib        = nil
local _init_done = false
local fonts      = {}
local gui_ctrl   = {}
local mats       = {}

local cheaters        = {}
local bb_player_names = {}
local stats           = {kills=0,deaths=0,assists=0,damage=0,hs=0,shots=0,hits=0}
local dmg_log         = {}
local hm_hits         = {}
local ax_log_lines    = {}

local DB              = "phantom_config.db"
local SHOT_LOG        = "phantom_shots.txt"
local AX_FILE         = "phantom_autoexec.cfg"
local CURRENT_VERSION = "1.0"

local ct_frame = 0
local ct_blink = true
local ct_tw    = 1
local ct_fwd   = true

local AX_DEFAULT = [[// phantom autoexec by maro
// format: normaler cs2 command pro zeile, oder "cvar <n> <wert>"
// kommentare starten mit //

sensitivity 1.8
volume 0.3
voice_scale 0.5
cl_interp 0
cl_interp_ratio 1
rate 786432
fps_max 400
mat_fullbright 0
]]

local WEAPON_NAMES = {
    [1]='Deagle',[2]='Dual Berettas',[3]='Five-SeveN',[4]='Glock',
    [7]='AK-47',[8]='AUG',[9]='AWP',[10]='FAMAS',[11]='G3SG1',
    [13]='Galil AR',[14]='M249',[16]='M4A4',[17]='MAC-10',[19]='P90',
    [23]='MP5-SD',[24]='UMP-45',[25]='XM1014',[26]='PP-Bizon',
    [27]='MAG-7',[28]='Negev',[29]='Sawed-Off',[30]='Tec-9',
    [31]='Zeus',[32]='P2000',[33]='MP7',[34]='MP9',[35]='Nova',
    [36]='P250',[38]='SCAR-20',[39]='SG 553',[40]='SSG 08',
    [42]='Knife',[43]='Flashbang',[44]='HE Grenade',[45]='Smoke',
    [46]='Molotov',[47]='Decoy',[48]='Incendiary',[49]='C4',
    [60]='M4A1-S',[61]='USP-S',[63]='CZ75',[64]='R8',
    [500]='Bayonet',[505]='Flip',[506]='Gut',[507]='Karambit',
    [508]='M9 Bayonet',[509]='Huntsman',[512]='Falchion',
    [514]='Bowie',[515]='Butterfly',[516]='Shadow Daggers',
    [519]='Ursus',[522]='Stiletto',[523]='Talon',[525]='Skeleton',
}

local ct_anim = {
    Static     = function(t) return t end,
    Scroll     = function(t)
        if #t == 0 then return t end
        local o = ct_frame % #t
        return t:sub(o + 1) .. t:sub(1, o)
    end,
    Blink      = function(t) return ct_blink and t or '' end,
    Wave       = function(t)
        local r = ''
        for i = 1, #t do
            local c = t:sub(i, i)
            r = r .. ((i + ct_frame) % 2 == 0 and c:upper() or c:lower())
        end
        return r
    end,
    Typewriter = function(t) return t:sub(1, ct_tw) end,
}

local function wpn_name(idx)
    return WEAPON_NAMES[idx] or ('wpn#' .. tostring(idx))
end

local save_config
local load_config
local reset_config
local run_autoexec
local fetch_motd
local check_update
local mark_cheater

local function push_dmg(msg)
    table.insert(dmg_log, 1, {text=msg, alpha=255, t=0})
    if #dmg_log > 5 then table.remove(dmg_log) end
end

local function ax_ensure_file()
    if not fs.is_file(AX_FILE) then
        fs.write(AX_FILE, AX_DEFAULT)
        return true
    end
    return false
end

local function get_bb_target()
    local sel = gui_ctrl.bb_player and gui_ctrl.bb_player:get() or nil
    if not sel or sel == '' then return nil end
    local idx = bb_player_names[sel]
    if not idx then return nil end
    local ent = entities.get_entity(idx)
    if ent and ent:is_valid() and (ent:get_prop("m_iHealth") or 0) > 0 then
        return ent, idx
    end
    return nil
end

local function is_cheater(player)
    if not player or not player:is_valid() then return false end
    local pi = player:get_player_info()
    if not pi then return false end
    local sid = pi.steam_id64 or pi.steam_id or tostring(player:get_index())
    return cheaters[sid] ~= nil
end

local function log_shot(info)
    if not gui_ctrl.m_shotlog or not gui_ctrl.m_shotlog:get() then return end
    local line = string.format('[tick %d] %s  dmg=%d/%d  hg=%d/%d  bt=%d\n',
        info.tick or 0, info.result or '?',
        info.client_damage or 0, info.server_damage or 0,
        info.client_hitgroup or 0, info.server_hitgroup or 0,
        info.backtrack or 0)
    local prev = fs.is_file(SHOT_LOG) and fs.read(SHOT_LOG) or ''
    fs.write(SHOT_LOG, prev .. line)
end

local function ax_log(msg)
    table.insert(ax_log_lines, 1, msg)
    if #ax_log_lines > 30 then table.remove(ax_log_lines) end
    if gui_ctrl.ax_status then
        gui_ctrl.ax_status:add(msg)
    end
    if lib and lib.log and lib.log.info then
        lib.log.info('[autoexec] ' .. msg)
    end
end

mark_cheater = function(player)
    if not lib then return end
    if not player or not player:is_valid() then return end
    local pi = player:get_player_info()
    if not pi then return end
    local sid = pi.steam_id64 or pi.steam_id or tostring(player:get_index())
    if cheaters[sid] then return end
    cheaters[sid] = { name = pi.name or '?', index = player:get_index() }
    if gui_ctrl.ch_list then
        gui_ctrl.ch_list:add(string.format('[%d] %s', player:get_index(), pi.name or '?'))
    end
    lib.notify('phantom', 'Cheater markiert: ' .. (pi.name or '?'))
end

save_config = function()
    if not _init_done then return end
    database.save(DB, {
        v_enable=gui_ctrl.v_enable:get(), v_watermark=gui_ctrl.v_watermark:get(),
        v_esp_box=gui_ctrl.v_esp_box:get(), v_esp_hp=gui_ctrl.v_esp_hp:get(),
        v_esp_name=gui_ctrl.v_esp_name:get(), v_esp_dist=gui_ctrl.v_esp_dist:get(),
        v_esp_weapon=gui_ctrl.v_esp_weapon:get(), v_esp_ammo=gui_ctrl.v_esp_ammo:get(),
        v_esp_snap=gui_ctrl.v_esp_snap:get(), v_esp_vis=gui_ctrl.v_esp_vis:get(),
        v_hitmarker=gui_ctrl.v_hitmarker:get(), v_chams=gui_ctrl.v_chams:get(),
        v_chams_wall=gui_ctrl.v_chams_wall:get(), v_keybinds=gui_ctrl.v_keybinds:get(),
        v_stats=gui_ctrl.v_stats:get(), v_dmg_log=gui_ctrl.v_dmg_log:get(),
        v_snap_origin=gui_ctrl.v_snap_origin:get(),
        ct_enable=gui_ctrl.ct_enable:get(), ct_tag=gui_ctrl.ct_tag:get(),
        ct_mode=gui_ctrl.ct_mode:get(), ct_speed=gui_ctrl.ct_speed:get(),
        bb_enable=gui_ctrl.bb_enable:get(), bb_mode=gui_ctrl.bb_mode:get(), bb_dist=gui_ctrl.bb_dist:get(),
        ch_enable=gui_ctrl.ch_enable:get(), ch_esp_mark=gui_ctrl.ch_esp_mark:get(),
        ch_chams_mark=gui_ctrl.ch_chams_mark:get(), ch_auto_safe=gui_ctrl.ch_auto_safe:get(),
        ch_notify=gui_ctrl.ch_notify:get(),
        m_rtt=gui_ctrl.m_rtt:get(), m_speedo=gui_ctrl.m_speedo:get(),
        m_crosshair=gui_ctrl.m_crosshair:get(), m_cross_size=gui_ctrl.m_cross_size:get(),
        m_cross_gap=gui_ctrl.m_cross_gap:get(), m_shotlog=gui_ctrl.m_shotlog:get(),
        m_motd=gui_ctrl.m_motd:get(), m_autoupdate=gui_ctrl.m_autoupdate:get(),
        ax_enable=gui_ctrl.ax_enable:get(),
    })
    lib.notify('phantom', 'Config gespeichert!')
end

load_config = function()
    if not _init_done then return end
    local c = database.load(DB)
    if not c then
        lib.notify('phantom', 'Keine Config gefunden.')
        return
    end

    local function ap(ctrl, val)
        if ctrl and val ~= nil then ctrl:set(val) end
    end

    ap(gui_ctrl.v_enable, c.v_enable); ap(gui_ctrl.v_watermark, c.v_watermark)
    ap(gui_ctrl.v_esp_box, c.v_esp_box); ap(gui_ctrl.v_esp_hp, c.v_esp_hp)
    ap(gui_ctrl.v_esp_name, c.v_esp_name); ap(gui_ctrl.v_esp_dist, c.v_esp_dist)
    ap(gui_ctrl.v_esp_weapon, c.v_esp_weapon); ap(gui_ctrl.v_esp_ammo, c.v_esp_ammo)
    ap(gui_ctrl.v_esp_snap, c.v_esp_snap); ap(gui_ctrl.v_esp_vis, c.v_esp_vis)
    ap(gui_ctrl.v_hitmarker, c.v_hitmarker); ap(gui_ctrl.v_chams, c.v_chams)
    ap(gui_ctrl.v_chams_wall, c.v_chams_wall); ap(gui_ctrl.v_keybinds, c.v_keybinds)
    ap(gui_ctrl.v_stats, c.v_stats); ap(gui_ctrl.v_dmg_log, c.v_dmg_log)
    ap(gui_ctrl.v_snap_origin, c.v_snap_origin)
    ap(gui_ctrl.ct_enable, c.ct_enable); ap(gui_ctrl.ct_tag, c.ct_tag)
    ap(gui_ctrl.ct_mode, c.ct_mode); ap(gui_ctrl.ct_speed, c.ct_speed)
    ap(gui_ctrl.bb_enable, c.bb_enable); ap(gui_ctrl.bb_mode, c.bb_mode); ap(gui_ctrl.bb_dist, c.bb_dist)
    ap(gui_ctrl.ch_enable, c.ch_enable); ap(gui_ctrl.ch_esp_mark, c.ch_esp_mark)
    ap(gui_ctrl.ch_chams_mark, c.ch_chams_mark); ap(gui_ctrl.ch_auto_safe, c.ch_auto_safe)
    ap(gui_ctrl.ch_notify, c.ch_notify)
    ap(gui_ctrl.m_rtt, c.m_rtt); ap(gui_ctrl.m_speedo, c.m_speedo)
    ap(gui_ctrl.m_crosshair, c.m_crosshair); ap(gui_ctrl.m_cross_size, c.m_cross_size)
    ap(gui_ctrl.m_cross_gap, c.m_cross_gap); ap(gui_ctrl.m_shotlog, c.m_shotlog)
    ap(gui_ctrl.m_motd, c.m_motd); ap(gui_ctrl.m_autoupdate, c.m_autoupdate)
    ap(gui_ctrl.ax_enable, c.ax_enable)

    lib.notify('phantom', 'Config geladen!')
end

reset_config = function()
    if not _init_done then return end
    lib.dialog('ph_reset', 'Reset Config', 'Alles auf Standard zuruecksetzen?', function(yes)
        if not yes then return end
        gui_ctrl.v_enable:set(false); gui_ctrl.v_watermark:set(true)
        gui_ctrl.v_esp_box:set(false); gui_ctrl.v_esp_hp:set(false); gui_ctrl.v_esp_name:set(false)
        gui_ctrl.v_esp_dist:set(false); gui_ctrl.v_esp_weapon:set(false); gui_ctrl.v_esp_ammo:set(false)
        gui_ctrl.v_esp_snap:set(false); gui_ctrl.v_esp_vis:set(false)
        gui_ctrl.v_hitmarker:set(false); gui_ctrl.v_chams:set(false); gui_ctrl.v_chams_wall:set(false)
        gui_ctrl.v_keybinds:set(false); gui_ctrl.v_stats:set(false); gui_ctrl.v_dmg_log:set(false)
        gui_ctrl.ct_enable:set(false); gui_ctrl.ct_tag:set('fatality.win'); gui_ctrl.ct_speed:set(200)
        gui_ctrl.bb_enable:set(false); gui_ctrl.bb_dist:set(40)
        gui_ctrl.ch_enable:set(false); gui_ctrl.ch_esp_mark:set(true)
        gui_ctrl.ch_chams_mark:set(false); gui_ctrl.ch_auto_safe:set(false); gui_ctrl.ch_notify:set(true)
        gui_ctrl.m_rtt:set(false); gui_ctrl.m_speedo:set(false); gui_ctrl.m_crosshair:set(false)
        gui_ctrl.m_cross_size:set(6); gui_ctrl.m_cross_gap:set(4); gui_ctrl.m_shotlog:set(false)
        gui_ctrl.m_motd:set(false); gui_ctrl.m_autoupdate:set(false)
        gui_ctrl.ax_enable:set(false)
        lib.notify('phantom', 'Auf Standard zurueckgesetzt.')
    end)
end

local function ax_set_cvar(name, value)
    local ok, current = pcall(function()
        local v = cvar[name]
        if not v then return nil end
        return v:get_string()
    end)

    if ok and current then
        if current ~= tostring(value) then
            pcall(function() cvar[name]:set_string(tostring(value)) end)
            ax_log(string.format('cvar: %s = %s  (war: %s)', name, value, current))
        else
            ax_log(string.format('cvar: %s = %s  (ok)', name, value))
        end
    else
        engine.exec(string.format('%s %s', name, value))
        ax_log(string.format('exec: %s %s', name, value))
    end
end

run_autoexec = function()
    if not _init_done then return end
    if not gui_ctrl.ax_enable:get() then return end
    ax_ensure_file()
    local content = fs.read(AX_FILE)
    if not content then
        ax_log('FEHLER: datei nicht lesbar')
        return
    end

    local executed, skipped = 0, 0
    for line in content:gmatch('[^\r\n]+') do
        line = lib.str.trim(line)
        if line == '' or lib.str.starts(line, '//') then
            skipped = skipped + 1
        elseif lib.str.starts(line, 'cvar ') or lib.str.starts(line, 'set ') then
            local rest = line:match('^%S+%s+(.+)$')
            if rest then
                local name, value = rest:match('^(%S+)%s+(.+)$')
                if name and value then
                    ax_set_cvar(name, value)
                    executed = executed + 1
                end
            end
        else
            local blocked = lib.str.starts(line, 'quit') or lib.str.starts(line, 'exit')
                         or lib.str.starts(line, 'map ') or lib.str.starts(line, 'disconnect')
            if blocked then
                ax_log('BLOCKED: ' .. line)
                skipped = skipped + 1
            else
                engine.exec(line)
                ax_log('exec: ' .. line)
                executed = executed + 1
            end
        end
    end

    local summary = string.format('autoexec: %d commands, %d skipped', executed, skipped)
    ax_log(summary)
    lib.notify('phantom autoexec', summary)
end

fetch_motd = function()
    if not _init_done then return end
    lib.http.get('https://pastebin.com/raw/phantom_motd', nil, function(r)
        if r then
            lib.notify('phantom MOTD', r:gsub('\n', ''):sub(1, 64))
        end
    end)
end

check_update = function()
    if not _init_done then return end
    lib.http.get('https://pastebin.com/raw/phantom_version', nil, function(r)
        if not r then return end
        local remote = lib.str.trim(r)
        if remote ~= CURRENT_VERSION then
            lib.notify('phantom UPDATE',
                string.format('v%s verfuegbar (du: v%s)', remote, CURRENT_VERSION))
        end
    end)
end

local function phantom_init()
    if _init_done then return end
    if not utils or not utils.load_file then return end
    if not render or not gui or not mat or not engine or not entities or not database or not fs or not cvar then
        return
    end

    local content = utils.load_file("fatality/scripts/phantom_lib.lua")
    if not content then
        print("[phantom] lib nicht gefunden")
        return
    end

    local chunk, err = load(content)
    if not chunk then
        print("[phantom] lib fehler: " .. tostring(err))
        return
    end

    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then
        print("[phantom] lib exec fehler: " .. tostring(result))
        return
    end

    lib = result

    fonts.esp = render.create_font("verdana.ttf", 11, render.font_flag_outline)
    fonts.hud = render.create_font("verdana.ttf", 12, render.font_flag_outline)
    fonts.big = render.create_font("verdana.ttf", 13, render.font_flag_outline)

    mats.vis = mat.create("phantom_vis", "VertexLitGeneric", [[
"VertexLitGeneric"{ "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "0" "$model" "1" }]])

    mats.wall = mat.create("phantom_wall", "VertexLitGeneric", [[
"VertexLitGeneric"{ "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "1" "$model" "1" "$additive" "1" }]])

    mats.cheater = mat.create("phantom_cheater", "VertexLitGeneric", [[
"VertexLitGeneric"{ "$basetexture" "vgui/white_additive" "$flat" "1" "$ignorez" "1" "$model" "1" "$additive" "1" }]])

    gui_ctrl.v_enable      = gui.checkbox(    'lua>visuals>v_en',  'lua>visuals', 'Enable Visuals')
    gui_ctrl.v_watermark   = gui.checkbox(    'lua>visuals>v_wm',  'lua>visuals', 'Watermark')
    gui_ctrl.v_esp_box     = gui.checkbox(    'lua>visuals>v_box', 'lua>visuals', 'ESP Box')
    gui_ctrl.v_esp_hp      = gui.checkbox(    'lua>visuals>v_hp',  'lua>visuals', 'Health Bar')
    gui_ctrl.v_esp_name    = gui.checkbox(    'lua>visuals>v_nm',  'lua>visuals', 'Name Flag')
    gui_ctrl.v_esp_dist    = gui.checkbox(    'lua>visuals>v_di',  'lua>visuals', 'Distance Flag')
    gui_ctrl.v_esp_weapon  = gui.checkbox(    'lua>visuals>v_wp',  'lua>visuals', 'Weapon Flag')
    gui_ctrl.v_esp_ammo    = gui.checkbox(    'lua>visuals>v_am',  'lua>visuals', 'Ammo Bar')
    gui_ctrl.v_esp_snap    = gui.checkbox(    'lua>visuals>v_sn',  'lua>visuals', 'Snaplines')
    gui_ctrl.v_esp_vis     = gui.checkbox(    'lua>visuals>v_vi',  'lua>visuals', 'Visibility Check')
    gui_ctrl.v_hitmarker   = gui.checkbox(    'lua>visuals>v_hm',  'lua>visuals', 'Hit Marker')
    gui_ctrl.v_chams       = gui.checkbox(    'lua>visuals>v_ch',  'lua>visuals', 'Chams')
    gui_ctrl.v_chams_wall  = gui.checkbox(    'lua>visuals>v_cw',  'lua>visuals', 'Chams Through Wall')
    gui_ctrl.v_keybinds    = gui.checkbox(    'lua>visuals>v_kb',  'lua>visuals', 'Keybind List')
    gui_ctrl.v_stats       = gui.checkbox(    'lua>visuals>v_st',  'lua>visuals', 'Session Stats')
    gui_ctrl.v_dmg_log     = gui.checkbox(    'lua>visuals>v_dl',  'lua>visuals', 'Damage Log')
    gui_ctrl.v_snap_origin = gui.combobox(    'lua>visuals>v_so',  'lua>visuals', 'Snapline Origin', false, 'Bottom Center', 'Center Screen')
    gui_ctrl.col_box_e     = gui.color_picker('lua>visuals>cbe',   'lua>visuals', 'Enemy Box',    render.color('#DC3C3C'), true)
    gui_ctrl.col_box_v     = gui.color_picker('lua>visuals>cbv',   'lua>visuals', 'Visible Box',  render.color('#3CFF3C'), true)
    gui_ctrl.col_snap      = gui.color_picker('lua>visuals>csn',   'lua>visuals', 'Snapline',     render.color('#DC3C3C'), true)
    gui_ctrl.col_che       = gui.color_picker('lua>visuals>cce',   'lua>visuals', 'Chams Enemy',  render.color('#FF4444'), true)
    gui_ctrl.col_chw       = gui.color_picker('lua>visuals>ccw',   'lua>visuals', 'Chams Wall',   render.color('#8844FF'), true)
    gui_ctrl.col_hm        = gui.color_picker('lua>visuals>chm',   'lua>visuals', 'Hit Marker',   render.color('#FF5050'), true)

    gui_ctrl.ct_enable = gui.checkbox('lua>clantag>ct_on', 'lua>clantag', 'Enable')
    gui_ctrl.ct_tag    = gui.textbox( 'lua>clantag>ct_tag', 'lua>clantag')
    gui_ctrl.ct_mode   = gui.combobox('lua>clantag>ct_mo', 'lua>clantag', 'Animation', false,
        'Static', 'Scroll', 'Blink', 'Wave', 'Typewriter')
    gui_ctrl.ct_speed  = gui.slider(  'lua>clantag>ct_sp', 'lua>clantag', 'Speed (ms)', 50, 1000)

    gui_ctrl.bb_enable = gui.checkbox('lua>blockbot>bb_en', 'lua>blockbot', 'Enable Blockbot')
    gui_ctrl.bb_mode   = gui.combobox('lua>blockbot>bb_mo', 'lua>blockbot', 'Mode', false,
        'Front Block', 'Side Strafe', 'Reverse Block')
    gui_ctrl.bb_dist   = gui.slider(  'lua>blockbot>bb_di', 'lua>blockbot', 'Distance (units)', 20, 80)
    gui_ctrl.bb_player = gui.list(    'lua>blockbot>bb_pl', 'lua>blockbot', 'Target Player', false, 120)

    gui_ctrl.ch_enable     = gui.checkbox(    'lua>cheater>ch_en', 'lua>cheater', 'Enable Cheater System')
    gui_ctrl.ch_esp_mark   = gui.checkbox(    'lua>cheater>ch_es', 'lua>cheater', 'Mark in ESP')
    gui_ctrl.ch_chams_mark = gui.checkbox(    'lua>cheater>ch_ch', 'lua>cheater', 'Cheater Chams')
    gui_ctrl.ch_auto_safe  = gui.checkbox(    'lua>cheater>ch_sa', 'lua>cheater', 'Auto Safe Point')
    gui_ctrl.ch_notify     = gui.checkbox(    'lua>cheater>ch_no', 'lua>cheater', 'Notify when targeting')
    gui_ctrl.ch_list       = gui.list(        'lua>cheater>ch_li', 'lua>cheater', 'Marked Cheaters', false, 140)
    gui_ctrl.ch_unmark_btn = gui.button(      'lua>cheater>ch_un', 'lua>cheater', 'Unmark All')
    gui_ctrl.col_cheater   = gui.color_picker('lua>cheater>ch_co', 'lua>cheater', 'Cheater Color', render.color('#FFFF00'), true)

    gui_ctrl.m_rtt        = gui.checkbox(    'lua>misc>m_rtt',   'lua>misc', 'RTT / Ping')
    gui_ctrl.m_speedo     = gui.checkbox(    'lua>misc>m_spd',   'lua>misc', 'Speedometer')
    gui_ctrl.m_crosshair  = gui.checkbox(    'lua>misc>m_xhair', 'lua>misc', 'Custom Crosshair')
    gui_ctrl.m_cross_size = gui.slider(      'lua>misc>m_xsz',   'lua>misc', 'Crosshair Size', 2, 20)
    gui_ctrl.m_cross_gap  = gui.slider(      'lua>misc>m_xgap',  'lua>misc', 'Crosshair Gap', 0, 15)
    gui_ctrl.col_cross    = gui.color_picker('lua>misc>mxc',     'lua>misc', 'Crosshair Color', render.color('#FFFFFF'), true)
    gui_ctrl.m_shotlog    = gui.checkbox(    'lua>misc>m_sl',    'lua>misc', 'Shot Logger (file)')
    gui_ctrl.m_motd       = gui.checkbox(    'lua>misc>m_motd',  'lua>misc', 'Remote MOTD on load')
    gui_ctrl.m_autoupdate = gui.checkbox(    'lua>misc>m_upd',   'lua>misc', 'Check for updates on load')

    gui_ctrl.ax_enable   = gui.checkbox('lua>autoexec>ax_en',  'lua>autoexec', 'Enable Autoexec')
    gui_ctrl.ax_run_btn  = gui.button(  'lua>autoexec>ax_run', 'lua>autoexec', 'Run Autoexec Now')
    gui_ctrl.ax_open_btn = gui.button(  'lua>autoexec>ax_open','lua>autoexec', 'Open / Create File')
    gui_ctrl.ax_status   = gui.list(    'lua>autoexec>ax_log', 'lua>autoexec', 'Last Run Log', false, 120)

    gui_ctrl.cfg_save  = gui.button('lua>config>csave',  'lua>config', 'Save Config')
    gui_ctrl.cfg_load  = gui.button('lua>config>cload',  'lua>config', 'Load Config')
    gui_ctrl.cfg_reset = gui.button('lua>config>creset', 'lua>config', 'Reset Defaults')

    gui_ctrl.ct_tag:set('fatality.win')
    gui_ctrl.ct_speed:set(200)
    gui_ctrl.bb_dist:set(40)
    gui_ctrl.m_cross_size:set(6)
    gui_ctrl.m_cross_gap:set(4)

    gui_ctrl.cfg_save:add_callback(save_config)
    gui_ctrl.cfg_load:add_callback(load_config)
    gui_ctrl.cfg_reset:add_callback(reset_config)

    gui_ctrl.ch_unmark_btn:add_callback(function()
        lib.dialog('ph_unmark', 'Cheater Unmarken', 'Alle Cheater entfernen?', function(yes)
            if not yes then return end
            cheaters = {}
            lib.notify('phantom', 'Cheater-Liste geleert.')
        end)
    end)

    gui_ctrl.ax_run_btn:add_callback(function()
        ax_log_lines = {}
        run_autoexec()
    end)

    gui_ctrl.ax_open_btn:add_callback(function()
        local created = ax_ensure_file()
        lib.notify('phantom autoexec',
            created and 'datei erstellt: ' .. AX_FILE or 'datei: ' .. AX_FILE)
    end)

    lib.timer.every(2000, function()
        bb_player_names = {}
        local _, li = lib.player.local_ent()
        entities.for_each_player(function(pl)
            if not pl:is_valid() then return end
            if pl:get_index() == li then return end
            if (pl:get_prop("m_iHealth") or 0) <= 0 then return end
            local name = lib.player.name(pl, 24)
            bb_player_names[name] = pl:get_index()
        end)
    end)

    lib.timer.every(200, function()
        local tag  = gui_ctrl.ct_tag:get() or ''
        local mode = gui_ctrl.ct_mode:get() or 'Static'
        ct_frame = ct_frame + 1
        ct_blink = not ct_blink
        if mode == 'Typewriter' then
            if ct_fwd then
                ct_tw = ct_tw + 1
                if ct_tw > #tag then ct_fwd = false end
            else
                ct_tw = ct_tw - 1
                if ct_tw < 1 then
                    ct_tw = 1
                    ct_fwd = true
                end
            end
        end
        if not gui_ctrl.ct_enable:get() then
            if utils and utils.set_clan_tag then utils.set_clan_tag('') end
            return
        end
        if utils and utils.set_clan_tag then
            utils.set_clan_tag((ct_anim[mode] or ct_anim.Static)(tag))
        end
    end)

    _init_done = true

    load_config()
    if gui_ctrl.m_motd:get() then fetch_motd() end
    if gui_ctrl.m_autoupdate:get() then check_update() end
    if gui_ctrl.ax_enable:get() then
        lib.timer.after(3000, function() run_autoexec() end)
    end

    lib.notify('phantom v1.0', 'geladen by maro')
end

function on_shot_fired(info)
    phantom_init()
    if not lib or not _init_done then return end
    stats.shots = stats.shots + 1
end

function on_shot_registered(info)
    phantom_init()
    if not lib or not _init_done then return end
    if (info.server_damage or 0) > 0 then
        stats.hits = stats.hits + 1
    end
    log_shot(info)
end

function on_game_event(event)
    phantom_init()
    if not lib or not _init_done then return end

    local ename     = event:get_name()
    local local_idx = engine.get_local_player()

    if ename == 'player_hurt' then
        local attacker = event:get_int('attacker')
        if attacker == local_idx then
            local dmg    = event:get_int('dmg_health') or 0
            local victim = event:get_int('userid')
            stats.damage = stats.damage + dmg
            if gui_ctrl.v_dmg_log:get() then
                local ent = entities.get_entity(victim)
                local hp  = event:get_int('health') or 0
                local nm  = ent and ent:is_valid() and lib.player.name(ent, 12) or '?'
                push_dmg(string.format('-%d hp  %s  (%dhp)', dmg, nm, hp))
            end
            if gui_ctrl.v_hitmarker:get() then
                local ent = entities.get_entity(victim)
                if ent and ent:is_valid() then
                    local ox = ent:get_prop("m_vecOrigin", 1) or 0
                    local oy = ent:get_prop("m_vecOrigin", 2) or 0
                    local oz = (ent:get_prop("m_vecOrigin", 3) or 0) + 40
                    local sx, sy = lib.render.w2s(ox, oy, oz)
                    if sx then
                        table.insert(hm_hits, {x=sx, y=sy, alpha=255, t=0})
                    end
                end
            end
        end
    end

    if ename == 'player_death' then
        local att = event:get_int('attacker')
        local vic = event:get_int('userid')
        local ass = event:get_int('assister')
        if att == local_idx then
            stats.kills = stats.kills + 1
            if event:get_int('headshot') == 1 then stats.hs = stats.hs + 1 end
        end
        if vic == local_idx then stats.deaths = stats.deaths + 1 end
        if ass == local_idx then stats.assists = stats.assists + 1 end
    end
end

function on_level_init()
    phantom_init()
    if not lib or not _init_done then return end

    stats   = {kills=0,deaths=0,assists=0,damage=0,hs=0,shots=0,hits=0}
    hm_hits = {}
    dmg_log = {}
    bb_player_names = {}
    if gui_ctrl.m_shotlog:get() then
        fs.write(SHOT_LOG, '')
    end
end

function on_draw_model_execute(dme, ent_index, model_name)
    phantom_init()
    if not lib or not _init_done then dme(); return end

    local local_idx = engine.get_local_player()
    if ent_index == local_idx then dme(); return end
    if not model_name:find("models/player") then dme(); return end

    local ent = entities.get_entity(ent_index)
    if not ent or not ent:is_valid() then dme(); return end
    local lp    = entities.get_entity(local_idx)
    local lteam = lp and lp:get_prop("m_iTeamNum") or 0
    if ent:get_prop("m_iTeamNum") == lteam then dme(); return end

    if gui_ctrl.ch_enable:get() and gui_ctrl.ch_chams_mark:get() and is_cheater(ent) then
        mats.cheater:modulate(gui_ctrl.col_cheater:get())
        mat.override_material(mats.cheater)
        dme()
        return
    end

    if gui_ctrl.v_chams:get() then
        if gui_ctrl.v_chams_wall:get() then
            mats.wall:modulate(gui_ctrl.col_chw:get())
            mat.override_material(mats.wall)
            dme()
        end
        mats.vis:modulate(gui_ctrl.col_che:get())
        mat.override_material(mats.vis)
        dme()
        return
    end

    dme()
end

function on_create_move(cmd, send_packet)
    phantom_init()
    if not lib or not _init_done then return end
    if not engine.is_in_game() then return end

    local local_ent, local_idx = lib.player.local_ent()
    if not local_ent or not local_ent:is_valid() then return end

    if gui_ctrl.ch_enable:get() and gui_ctrl.ch_auto_safe:get() then
        local va = cmd:get_view_angles()
        local lo = lib.player.origin(local_ent)
        lib.player.each_enemy(function(player)
            if not is_cheater(player) then return end
            local po = lib.player.origin(player)
            po.z = po.z + 60
            lib.math.fov_to(va, po, math.vec3(lo.x, lo.y, lo.z + 64))
        end)
    end

    if not gui_ctrl.bb_enable:get() then return end
    local target = get_bb_target()
    if not target then return end

    local lo      = lib.player.origin(local_ent)
    local to      = lib.player.origin(target)
    local vel     = lib.player.velocity(target)
    local vlen    = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    local desired = gui_ctrl.bb_dist:get()
    local mode    = gui_ctrl.bb_mode:get() or 'Front Block'

    local dx = lo.x - to.x
    local dy = lo.y - to.y
    local dlen = math.sqrt(dx * dx + dy * dy)
    if dlen < 0.01 then return end
    local ndx = dx / dlen
    local ndy = dy / dlen

    local target_x, target_y
    if mode == 'Front Block' then
        if vlen > 10 then
            local nvx = vel.x / vlen
            local nvy = vel.y / vlen
            target_x = to.x + nvx * desired
            target_y = to.y + nvy * desired
        else
            target_x = to.x + ndx * desired
            target_y = to.y + ndy * desired
        end
    elseif mode == 'Side Strafe' then
        local sx = -ndy
        local sy = ndx
        local off = math.sin(ct_frame * 0.3) * desired
        target_x = to.x + ndx * desired * 0.5 + sx * off * 0.4
        target_y = to.y + ndy * desired * 0.5 + sy * off * 0.4
    elseif mode == 'Reverse Block' then
        target_x = to.x - ndx * desired
        target_y = to.y - ndy * desired
    end

    local mdx   = target_x - lo.x
    local mdy   = target_y - lo.y
    local mdist = math.sqrt(mdx * mdx + mdy * mdy)
    if mdist < 8 then return end

    local _, yaw = engine.get_view_angles()
    local yr     = math.rad(yaw)
    local cy     = math.cos(yr)
    local sy     = math.sin(yr)
    local fwd    = (mdx * cy + mdy * sy)
    local side   = (mdx * sy - mdy * cy) * -1
    local total  = math.sqrt(fwd * fwd + side * side)
    if total > 1 then
        fwd = fwd / total * 450
        side = side / total * 450
    end
    cmd:set_move(fwd, side)
end

function on_paint()
    phantom_init()
    if not lib or not _init_done then return end
    if not engine.is_in_game() then return end

    local sw, sh = render.get_screen_size()
    local local_ent, local_idx = lib.player.local_ent()

    if gui_ctrl.v_watermark:get() then
        local info  = engine.get_player_info(local_idx)
        local uname = (info and info.name) or 'unknown'
        local rtt   = utils.get_rtt and utils.get_rtt() or 0
        local wm    = string.format('phantom  |  %s  |  %dms', uname, rtt)
        local tw, th = render.get_text_size(fonts.big, wm)
        local px, py = sw - tw - 38, 26
        render.rect_filled(px - 7, py - 5, px + tw + 7, py + th + 5, render.color(10,10,20,210))
        render.rect(px - 7, py - 5, px + tw + 7, py + th + 5, render.color(120,60,220,200))
        render.text(fonts.big, px, py, wm, render.color(200,160,255), render.align_left, render.align_top)
    end

    if gui_ctrl.v_stats:get() then
        local acc = stats.shots > 0 and string.format('%.0f%%', stats.hits / stats.shots * 100) or '0%'
        local kd  = stats.deaths > 0 and string.format('%.2f', stats.kills / stats.deaths) or tostring(stats.kills)
        local lines = {
            string.format('K   %d',   stats.kills),
            string.format('D   %d',   stats.deaths),
            string.format('A   %d',   stats.assists),
            string.format('DMG %d',   stats.damage),
            string.format('HS  %d%%', stats.kills > 0 and math.floor(stats.hs / stats.kills * 100) or 0),
            string.format('KD  %s',   kd),
            string.format('ACC %s',   acc),
        }
        local lh, bw = 16, 108
        local bh     = #lines * lh + 10
        local bx, by = sw - bw - 14, 60
        render.rect_filled(bx, by, bx + bw, by + bh, render.color(10,10,20,200))
        render.rect(bx, by, bx + bw, by + bh, render.color(80,50,160,180))
        for i, line in ipairs(lines) do
            render.text(fonts.hud, bx + 8, by + 5 + (i - 1) * lh, line,
                render.color(200,200,200), render.align_left, render.align_top)
        end
    end

    if gui_ctrl.m_rtt:get() and not gui_ctrl.v_stats:get() then
        local rtt = utils.get_rtt and utils.get_rtt() or 0
        local col = lib.render.lerp_color(
            {220,60,60,220}, {60,220,60,220},
            lib.math.clamp((100 - rtt) / 100, 0, 1))
        lib.render.text_bg(fonts.hud, sw - 60, 60,
            string.format('%dms', rtt), col, render.color(0,0,0,160))
    end

    if gui_ctrl.m_speedo:get() and local_ent and local_ent:is_valid() then
        local spd = lib.player.speed(local_ent)
        local col = lib.render.lerp_color(
            {140,140,140,220}, {255,140,40,220},
            lib.math.clamp((spd - 100) / 200, 0, 1))
        local txt = string.format('%d u/s', math.floor(spd))
        local tw  = render.get_text_size(fonts.hud, txt)
        render.text(fonts.hud, sw / 2 - tw / 2, sh - 80, txt, col, render.align_left, render.align_top)
    end

    if gui_ctrl.m_crosshair:get() then
        local cx, cy = sw / 2, sh / 2
        local sz     = gui_ctrl.m_cross_size:get()
        local gap    = gui_ctrl.m_cross_gap:get()
        local col    = gui_ctrl.col_cross:get()
        render.line(cx - sz - gap, cy, cx - gap, cy, col)
        render.line(cx + gap, cy, cx + sz + gap, cy, col)
        render.line(cx, cy - sz - gap, cx, cy - gap, col)
        render.line(cx, cy + gap, cx, cy + sz + gap, col)
        render.rect_filled(cx - 1, cy - 1, cx + 1, cy + 1, col)
    end

    if gui_ctrl.v_dmg_log:get() then
        for i = #dmg_log, 1, -1 do
            local e = dmg_log[i]
            e.t = e.t + 1
            e.alpha = math.max(0, 255 - e.t * 2)
            if e.alpha <= 0 then
                table.remove(dmg_log, i)
            else
                render.text(fonts.hud, 14, sh - 120 - (i - 1) * 16, e.text,
                    render.color(255,120,60,e.alpha), render.align_left, render.align_top)
            end
        end
    end

    if gui_ctrl.v_keybinds:get() and gui.is_menu_open and not gui.is_menu_open() then
        local idx = 0
        gui.for_each_hotkey(function(name, key, mode, is_active)
            if not is_active then return end
            render.text(fonts.hud, 14, sh / 2 + idx * 16,
                string.format('[%s]  %s', name, mode == 1 and 'TOGGLE' or 'HOLD'),
                render.color(200,160,255,200), render.align_left, render.align_top)
            idx = idx + 1
        end)
    end

    if gui_ctrl.bb_enable:get() then
        local tgt = get_bb_target()
        local lbl = tgt and 'BLOCKBOT  ON' or 'BLOCKBOT  no target'
        local col = tgt and render.color(255,80,80,220) or render.color(180,180,180,160)
        render.text(fonts.hud, sw / 2, sh - 100, lbl, col, render.align_center, render.align_top)
    end

    if gui_ctrl.v_enable:get() then
        local snap_x = sw / 2
        local snap_y = gui_ctrl.v_snap_origin:get() == 'Bottom Center' and sh or sh / 2

        lib.player.each_enemy(function(player)
            local hp = player:get_prop("m_iHealth") or 0
            local cheater = gui_ctrl.ch_enable:get() and is_cheater(player)
            local visible = true
            if gui_ctrl.v_esp_vis:get() then
                visible = lib.player.visible(player, local_ent, local_idx)
            end

            local box_col = cheater and gui_ctrl.col_cheater:get()
                         or visible and gui_ctrl.col_box_v:get()
                         or             gui_ctrl.col_box_e:get()

            local vals = {lib.player.screen_box(player)}
            if not vals[1] then return end
            local bx1, by1, bx2, by2, bw, bh = vals[1], vals[2], vals[3], vals[4], vals[5], vals[6]
            local cx = (bx1 + bx2) / 2

            if gui_ctrl.v_esp_box:get() or cheater then
                lib.render.box(bx1, by1, bx2, by2, box_col)
                if cheater then
                    render.text(fonts.esp, cx, by1 - 26, '! CHEATER',
                        gui_ctrl.col_cheater:get(), render.align_center, render.align_top)
                end
            end

            if gui_ctrl.v_esp_hp:get() then
                lib.render.bar_v(bx1 - 6, by1, 3, bh, hp / 100, lib.render.hp_color(hp))
            end

            if gui_ctrl.v_esp_ammo:get() then
                local wpn, widx = lib.player.weapon(player)
                if wpn then
                    local clip  = wpn:get_prop("m_iClip1") or 0
                    local winfo = utils.get_weapon_info(widx)
                    local maxc  = winfo and winfo.max_clip1 or 30
                    if maxc > 0 then
                        local ac = clip <= math.floor(maxc * 0.25)
                            and render.color(220,60,60,200)
                            or  render.color(60,160,220,200)
                        lib.render.bar_v(bx2 + 3, by1, 3, bh, clip / maxc, ac)
                    end
                end
            end

            if gui_ctrl.v_esp_name:get() then
                render.text(fonts.esp, cx, by1 - 14, lib.player.name(player, 18),
                    render.color(255,255,255,220), render.align_center, render.align_top)
            end

            if gui_ctrl.v_esp_dist:get() then
                local dist = lib.player.dist(player)
                local dcol = dist < 10 and render.color(255,80,80,220)
                          or dist < 25 and render.color(255,200,40,220)
                          or              render.color(180,180,180,200)
                render.text(fonts.esp, cx, by2 + 2,
                    string.format('%.0fm', dist), dcol, render.align_center, render.align_top)
            end

            if gui_ctrl.v_esp_weapon:get() then
                local _, widx = lib.player.weapon(player)
                local wname = widx > 0 and wpn_name(widx) or '?'
                local yoff  = gui_ctrl.v_esp_dist:get() and 14 or 2
                render.text(fonts.esp, cx, by2 + yoff, wname,
                    render.color(140,200,255,200), render.align_center, render.align_top)
            end

            if gui_ctrl.v_esp_snap:get() then
                render.line(snap_x, snap_y, cx, by2, gui_ctrl.col_snap:get())
            end

            local tgt, tidx = get_bb_target()
            if gui_ctrl.bb_enable:get() and tgt and player:get_index() == tidx then
                render.rect(bx1 - 3, by1 - 3, bx2 + 3, by2 + 3, render.color(255,80,80,180))
            end
        end)
    end

    for i = #hm_hits, 1, -1 do
        local h = hm_hits[i]
        h.t = h.t + 1
        h.alpha = math.max(0, 255 - h.t * 10)
        if h.alpha <= 0 then
            table.remove(hm_hits, i)
        else
            local c = gui_ctrl.col_hm:get()
            lib.render.crossmark(h.x, h.y, 5,
                render.color(c[1] or 255, c[2] or 80, c[3] or 80, h.alpha))
        end
    end
end

function on_esp_flag(index)
    phantom_init()
    if not lib or not _init_done then return {} end
    if not gui_ctrl.ch_enable:get() or not gui_ctrl.ch_esp_mark:get() then return {} end
    local ent = entities.get_entity(index)
    if not ent or not is_cheater(ent) then return {} end
    return { render.esp_flag('CHEATER', gui_ctrl.col_cheater:get()) }
end

function on_console_input(input)
    phantom_init()
    if not lib or not _init_done then return end
    local cmd, arg = input:match('^(%S+)%s*(.*)$')
    if cmd == 'ph_mark' then
        local tidx = tonumber(arg)
        entities.for_each_player(function(player)
            if not player:is_valid() then return end
            local pi = player:get_player_info()
            if not pi then return end
            local match = (tidx and player:get_index() == tidx)
                       or (pi.name and pi.name:lower():find(arg:lower(), 1, true))
            if match then mark_cheater(player) end
        end)
    elseif cmd == 'ph_help' then
        print('[phantom] ph_mark <name/index>  - spieler als cheater markieren')
        print('[phantom] ph_help               - diese hilfe')
    end
end

function on_config_save()
    if _init_done then save_config() end
end

function on_config_load()
    if _init_done then load_config() end
end
