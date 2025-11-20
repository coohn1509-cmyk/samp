script_name("Recording Route")
script_author("Adolfahytam")

require('lib.moonloader')
local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new = imgui.new
local ffi = require 'ffi'
require("sampfuncs")
local os_clock = os.clock
local inicfg = require("inicfg")


local window = {
    state = new.bool(false), selected_route = new.char[256](""), routes = {},
    is_recording = new.bool(false), is_playing = false, is_looping = new.int(0),
    save_popup_active = false, mark_point = new.bool(false), input_save_name = new.char[128](""),
    playback_speed = imgui.new.float(20.0)
}
local menu = {
    active = { show_menu = new.bool(false), active_stat = new.bool(false) },
    settings = { value_slider = new.float(30), option_type1 = new.int(0), option_type2 = new.int(0) }
}
local route_data = {
    current = {}, current_index = 1, last_stop_index = 1, last_record_time = 0, record_interval = 100,
    last_movement_time = 0, current_stop_time = 0, mark_start_time = 0, current_mark_duration = 0,
    is_waiting_at_mark = false, next_mark_point = nil, mark_point_distance = 0, current_mode = "ONFOOT",
    target_nav_speed = 20.0,
    current_nav_speed = 20.0,
    is_currently_marking_segment = false,
    notified_next_mark_index = nil
}

local COLORS = { PINK_BRIGHT = "{FF69B4}", PINK_SOFT = "{FFB6C1}", PURPLE_DEEP = "{8A2BE2}", GREEN = "{98FB98}", GOLD = "{FFD700}", CYAN = "{00CED1}", OFF = "{E6A8D7}", ON = "{B4EEB4}" }
local UI_PINK_TEXT_COLOR = imgui.ImVec4(1.00, 0.75, 0.80, 1.00)

local SCRIPT_INI_FILE = "AUTORECORD_ADOLF_settings.ini"
local settings_ini = inicfg.load({
    playback = {
        speed = 20.0
    }
}, SCRIPT_INI_FILE)

window.playback_speed[0] = settings_ini.playback.speed

local function savePlaybackSpeedToIni()
    settings_ini.playback.speed = window.playback_speed[0]
    inicfg.save(settings_ini, SCRIPT_INI_FILE)
end

local function getDistanceBetweenCoords3d(x1,y1,z1,x2,y2,z2) if type(x1)~="number" or type(y1)~="number" or type(z1)~="number" or type(x2)~="number" or type(y2)~="number" or type(z2)~="number" then return math.huge end; return math.sqrt((x2-x1)^2+(y2-y1)^2+(z2-z1)^2) end
local function clearRoute() route_data.current={};route_data.current_index=1;route_data.last_stop_index=1;route_data.current_mode="ONFOOT";window.is_playing=false;window.is_recording[0]=false;route_data.is_currently_marking_segment = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; sampAddChatMessage(COLORS.GREEN.."Route telah dibersihkan!",-1) end
local function returnCharacterToDriver() if isCharInAnyCar(PLAYER_PED) then local v=storeCarCharIsInNoSave(PLAYER_PED); if v and v~=0 then taskWarpCharIntoCarAsDriver(PLAYER_PED,v); sampAddChatMessage(COLORS.CYAN.."Karakter kembali ke driver.",-1) end end end

local function detectNextMarkPoint()
    if not window.is_playing or #route_data.current == 0 then return end
    local ci = route_data.current_index; local new_next_mark_point_obj = nil; local new_next_mark_point_idx_val = -1
    for i = ci + 1, #route_data.current do if route_data.current[i] and route_data.current[i].is_marked then new_next_mark_point_obj = route_data.current[i]; new_next_mark_point_idx_val = i; break end end
    if new_next_mark_point_obj then
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        if type(px) == "number" then
            local dist = getDistanceBetweenCoords3d(px, py, pz, new_next_mark_point_obj.x, new_next_mark_point_obj.y, new_next_mark_point_obj.z); route_data.mark_point_distance = dist
            if (route_data.notified_next_mark_index == nil or route_data.notified_next_mark_index ~= new_next_mark_point_idx_val) and dist < 50.0 then sampAddChatMessage(COLORS.CYAN .. "Mark point berikutnya (#" .. new_next_mark_point_idx_val .."): " .. string.format("%.1f", dist) .. "m", -1); route_data.notified_next_mark_index = new_next_mark_point_idx_val end
        else route_data.mark_point_distance = 0 end
        route_data.next_mark_point = new_next_mark_point_obj
    else route_data.next_mark_point = nil; route_data.mark_point_distance = 0; if route_data.notified_next_mark_index ~= nil then route_data.notified_next_mark_index = nil end end
end

local function stopCharacterMovement() clearCharTasksImmediately(PLAYER_PED) end
local function createPositionData(is_marked,mark_duration) local x,y,z=getCharCoordinates(PLAYER_PED); if type(x)~="number" or type(y)~="number" or type(z)~="number" then sampAddChatMessage(COLORS.PINK_BRIGHT.."[ERROR] createPositionData: Invalid player coords!", -1); return nil end; local is_veh=isCharInAnyCar(PLAYER_PED); local head=0.0; if is_veh then local car=storeCarCharIsInNoSave(PLAYER_PED); if car and car~=0 then head=getCarHeading(car) end else head=getCharHeading(PLAYER_PED) end; return {x=x,y=y,z=z,heading=head or 0.0,mode=is_veh and "VEHICLE" or "ONFOOT",is_marked=is_marked or false,mark_duration=mark_duration or 0,timestamp=os_clock()*2000} end
local function refreshRouteList() window.routes={}; local ps=getWorkingDirectory().."/routes_Adolfhytam/"; if not doesDirectoryExist(ps) then pcall(createDirectory,ps) end; local cmd='ls "'..ps..'"'; local dh=io.popen(cmd); if dh then for fn in dh:lines() do if type(fn)=="string" and fn:match("%.csv$") then table.insert(window.routes,fn:sub(1,-5)) end end; pcall(function() dh:close() end) else sampAddChatMessage(COLORS.PINK_BRIGHT.."[ERROR] Gagal baca dir rute.",-1) end; table.sort(window.routes) end
local function saveRouteToFile(name) if #route_data.current==0 then sampAddChatMessage(COLORS.PINK_BRIGHT.."Tidak ada rute u/ disimpan.",-1); return false end; local p=getWorkingDirectory().."/routes_Adolfhytam/"; if not doesDirectoryExist(p) then pcall(createDirectory,p) end; local fp=p..name..".csv"; local f,err=io.open(fp,"w"); if f then for _,pos in ipairs(route_data.current) do if type(pos.x)=="number" and type(pos.y)=="number" and type(pos.z)=="number" and type(pos.heading)=="number" and type(pos.mode)=="string" and type(pos.is_marked)=="boolean" and type(pos.mark_duration)=="number" then f:write(string.format("%.4f,%.4f,%.4f,%.4f,%s,%d,%.0f\n",pos.x,pos.y,pos.z,pos.heading,pos.mode,pos.is_marked and 1 or 0,pos.mark_duration)) else sampAddChatMessage(COLORS.PINK_BRIGHT.."[ERROR] saveRoute: Data rute invalid.", -1) end end; f:close(); sampAddChatMessage(COLORS.GREEN.."Rute disimpan: "..name..".csv",-1); refreshRouteList(); return true else sampAddChatMessage(COLORS.PINK_BRIGHT.."[ERROR] Gagal simpan file: "..(err or "unknown"),-1) end; return false end
local function loadRouteFromFile(name) local p=getWorkingDirectory().."/routes_Adolfhytam/"..name..".csv"; local f,err=io.open(p,"r"); if not f then sampAddChatMessage(COLORS.PINK_BRIGHT.."Rute tdk ditemukan: "..name.." ("..(err or "unknown")..")",-1); return false end; clearRoute(); for line in f:lines() do local xs,ys,zs,hs,ms,marks,durs=line:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)"); if xs and ys and zs and hs and ms and marks and durs then local x,y,z,h,dur=tonumber(xs),tonumber(ys),tonumber(zs),tonumber(hs),tonumber(durs); if x and y and z and h and dur and type(ms)=="string" and type(marks)=="string" then table.insert(route_data.current,{x=x,y=y,z=z,heading=h,mode=ms,is_marked=(tonumber(marks)==1),mark_duration=dur}) else sampAddChatMessage(COLORS.PINK_SOFT.."[WARN] loadRoute: Baris invalid/konversi gagal: "..line, -1) end else sampAddChatMessage(COLORS.PINK_SOFT.."[WARN] loadRoute: Format baris salah: "..line, -1) end end; f:close(); sampAddChatMessage(COLORS.GREEN.."Rute dimuat: "..name,-1); route_data.last_stop_index=1; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; return true end

local function updateRecording()
    if not window.is_recording[0] then if route_data.is_currently_marking_segment then route_data.is_currently_marking_segment = false; route_data.mark_start_time = 0 end; return end
    local ct = os_clock() * 2000
    if ct - route_data.last_record_time >= route_data.record_interval then
        local should_record_normal_point = true
        if window.mark_point[0] then
            if not route_data.is_currently_marking_segment then route_data.is_currently_marking_segment = true; route_data.mark_start_time = ct; sampAddChatMessage(COLORS.GOLD .. "Mulai menandai titik berhenti...", -1) end
            local current_duration_at_mark = ct - route_data.mark_start_time; local marked_pos_data = createPositionData(true, current_duration_at_mark)
            if marked_pos_data then
                local last_idx = #route_data.current
                if last_idx > 0 and route_data.current[last_idx].is_marked and route_data.current[last_idx].timestamp >= route_data.mark_start_time then route_data.current[last_idx].x = marked_pos_data.x; route_data.current[last_idx].y = marked_pos_data.y; route_data.current[last_idx].z = marked_pos_data.z; route_data.current[last_idx].heading = marked_pos_data.heading; route_data.current[last_idx].mode = marked_pos_data.mode; route_data.current[last_idx].mark_duration = current_duration_at_mark;
                else table.insert(route_data.current, marked_pos_data); sampAddChatMessage(COLORS.GOLD .. "Titik berhenti baru ditambahkan (durasi: " .. string.format("%.1fs", current_duration_at_mark / 2000) .. ")", -1) end
                should_record_normal_point = false
            end
        else if route_data.is_currently_marking_segment then route_data.is_currently_marking_segment = false; route_data.mark_start_time = 0 end end
        if should_record_normal_point then local normal_pos_data = createPositionData(false, 0); if normal_pos_data then table.insert(route_data.current, normal_pos_data) end end
        route_data.last_record_time = ct
    end
end


local function AutoPilot()
    if not window.is_playing or #route_data.current == 0 then return end
    detectNextMarkPoint()
    local current_point_idx = route_data.current_index
    local current_point = route_data.current[current_point_idx]

    if not current_point or type(current_point.x) ~= "number" then
        sampAddChatMessage(COLORS.PINK_BRIGHT .. "[AP] Titik rute #" .. current_point_idx .. " invalid. Stop.", -1)
        window.is_playing = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; returnCharacterToDriver(); return
    end

    local pX, pY, pZ = getCharCoordinates(PLAYER_PED)
    if type(pX) ~= "number" then
        sampAddChatMessage(COLORS.PINK_BRIGHT .. "[AP] Gagal get coord pemain. Stop.", -1)
        window.is_playing = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; returnCharacterToDriver(); return
    end
    local distance_to_target = getDistanceBetweenCoords3d(pX, pY, pZ, current_point.x, current_point.y, current_point.z)
    local is_in_veh = isCharInAnyCar(PLAYER_PED)
    local current_player_mode = is_in_veh and "VEHICLE" or "ONFOOT"

    if route_data.is_waiting_at_mark then
        local waiting_point = route_data.current[current_point_idx]
        if not waiting_point or not waiting_point.is_marked then
            route_data.is_waiting_at_mark = false
        elseif (os_clock()*2000) - route_data.current_stop_time >= waiting_point.mark_duration then
            route_data.is_waiting_at_mark = false
            route_data.current_index = route_data.current_index + 1
            route_data.notified_next_mark_index = nil
            sampAddChatMessage(COLORS.CYAN .. "Lanjut dari mark.", -1)
            return
        else
            if current_player_mode == "VEHICLE" then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                if car and car ~= 0 then
                    
                end
            end
            return
        end
    elseif current_point.is_marked then
        local stop_dist_mark = (current_player_mode == "ONFOOT" and 1.0 or 1.8)
        if distance_to_target < stop_dist_mark then
            route_data.is_waiting_at_mark = true
            route_data.current_stop_time = os_clock() * 2000
            if current_player_mode == "ONFOOT" then stopCharacterMovement()
            else local car = storeCarCharIsInNoSave(PLAYER_PED); if car and car ~= 0 then end
            end
            sampAddChatMessage(COLORS.CYAN .. "Stop di mark #" .. current_point_idx .. " (selama " .. string.format("%.1fs", current_point.mark_duration/2000) .. ")", -1)
            return
        end
    end

    if current_player_mode ~= current_point.mode then
        if not (current_point.is_marked and route_data.current_index > 1 and route_data.current[route_data.current_index-1].mode ~= current_player_mode) then
            sampAddChatMessage(COLORS.PINK_BRIGHT .. "Mode Beda! Rute:"..current_point.mode..", Player:"..current_player_mode..". Stop.",-1)
            window.is_playing = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; returnCharacterToDriver(); return
        end
    end

    local threshold_to_advance_waypoint
    if current_point.mode == "ONFOOT" then
        threshold_to_advance_waypoint = 8.0
        if distance_to_target <= threshold_to_advance_waypoint then
            setCharHeading(PLAYER_PED, current_point.heading or 0)
            if not current_point.is_marked then route_data.current_index = route_data.current_index + 1; route_data.notified_next_mark_index = nil; end
        else taskGoToCoordAnyMeans(PLAYER_PED, current_point.x, current_point.y, current_point.z, 2.0, nil, false, 0, 0.8) end
    elseif current_point.mode == "VEHICLE" then
        if not is_in_veh then sampAddChatMessage(COLORS.PINK_SOFT .. "Player onfoot, rute butuh kendaraan. Stop.", -1); window.is_playing = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; returnCharacterToDriver(); return end
        local player_car = storeCarCharIsInNoSave(PLAYER_PED)
        if player_car and player_car ~= 0 then
            local speed_from_slider = window.playback_speed[0];
            local stop_range_setting = 10.0;
            threshold_to_advance_waypoint = 8.0;

            if distance_to_target <= threshold_to_advance_waypoint then
                if not current_point.is_marked then route_data.current_index = route_data.current_index + 1; route_data.notified_next_mark_index = nil; end
            else taskCarDriveToCoord(PLAYER_PED, player_car, current_point.x, current_point.y, current_point.z, speed_from_slider, 1, 0,0, stop_range_setting, 10.0) end
        else sampAddChatMessage(COLORS.PINK_BRIGHT .. "[AP] Gagal get handle mobil (nav). Stop.", -1); window.is_playing = false; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false; returnCharacterToDriver(); return end
    end

    if route_data.current_index > #route_data.current then
        if window.is_looping[0] == 1 then
            route_data.current_index = 1; route_data.current_stop_time = 0; route_data.is_waiting_at_mark = false; route_data.notified_next_mark_index = nil;
            sampAddChatMessage(COLORS.GREEN .. "Rute loop.", -1)
        else
            sampAddChatMessage(COLORS.GREEN .. "Rute Selesai.", -1)
            window.is_playing = false;
            route_data.notified_next_mark_index = nil;
            route_data.is_waiting_at_mark = false;

            -- --- FIX
            if isCharInAnyCar(PLAYER_PED) then
                local player_car = storeCarCharIsInNoSave(PLAYER_PED)
                if player_car and player_car ~= 0 then
                    setCarSpeed(player_car, 0.0) -- 0
                    clearCarTasksImmediately(player_car) -- clear job
                    
                    wait(100) -- pause

                    setCharIntoVehicle(PLAYER_PED, player_car, 0)
                    setPlayerControlEnabled(true)
                    
                    
                    
                    setGameKeyState(1, 1)
                    wait(20)
                    setGameKeyState(1, 0)
                    setGameKeyState(1, 128)
                    wait(20)
                    setGameKeyState(1, 0)

                    sampAddChatMessage(COLORS.GREEN .. "Kontrol kendaraan dikembalikan!", -1)
                end
            else
                stopCharacterMovement() -- onfoot
                setPlayerControlEnabled(true)
            end
            -- --- final repair end
        end
    end
end


local newFrame = imgui.OnFrame(
    function() return menu.active.show_menu[0] end,
    function(player)
        local scrX, scrY = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(scrX / 2, scrY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(350, 480), imgui.Cond.FirstUseEver)

        if menu.active.show_menu[0] then
            imgui.Begin("Routes recorder | by Adolfhytam v2", menu.active.show_menu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

            
            local full_button_width = imgui.GetWindowContentRegionWidth()
            local half_button_width = (imgui.GetWindowContentRegionWidth() - imgui.GetStyle().ItemSpacing.x) / 2

            if imgui.CollapsingHeader("Main##MainHeader") then
                imgui.Text("Route:")
                imgui.PushItemWidth(full_button_width)
                if imgui.BeginCombo("##RouteSelector", ffi.string(window.selected_route)) then
                    if #window.routes == 0 then imgui.Text("Tidak ada rute tersimpan.") end
                    for _, n_route in ipairs(window.routes) do
                        if imgui.Selectable(n_route, n_route == ffi.string(window.selected_route)) then ffi.copy(window.selected_route, n_route) end
                    end
                    imgui.EndCombo()
                end
                imgui.PopItemWidth()
                if imgui.Button("Muat Rute", imgui.ImVec2(full_button_width, 0)) then
                    local selected_route_name = ffi.string(window.selected_route)
                    if selected_route_name ~= "" then loadRouteFromFile(selected_route_name)
                    else sampAddChatMessage(COLORS.PINK_BRIGHT .. "Pilih rute dari daftar dulu!", -1) end
                end
                imgui.Separator()

                if imgui.Button("Record New Route", imgui.ImVec2(half_button_width, 30)) then
                    if not window.is_recording[0] and #route_data.current > 0 then clearRoute(); sampAddChatMessage(COLORS.CYAN .. "Rute lama clear.", -1) end
                    window.is_recording[0] = true; route_data.current = {}; route_data.current_index = 1; route_data.last_stop_index = 1; route_data.mark_start_time = 0; route_data.is_currently_marking_segment = false; route_data.is_waiting_at_mark = false;
                    sampAddChatMessage(COLORS.GREEN .. "Mulai rekam...", -1)
                end
                imgui.SameLine()
                if imgui.Button("Stop Record", imgui.ImVec2(half_button_width, 30)) then
                    window.is_recording[0] = false; route_data.is_currently_marking_segment = false; sampAddChatMessage(COLORS.PINK_BRIGHT .. "Record stop.", -1)
                end

                if imgui.Button("Play Route", imgui.ImVec2(half_button_width, 30)) then
                    if #route_data.current == 0 then
                        sampAddChatMessage(COLORS.PINK_BRIGHT .. "Tidak ada rute!", -1)
                    else
                        window.is_playing = true; route_data.current_index = route_data.last_stop_index > 1 and route_data.last_stop_index <= #route_data.current and route_data.last_stop_index or 1; route_data.is_waiting_at_mark = false;
                        route_data.notified_next_mark_index = nil;
                        sampAddChatMessage(COLORS.GREEN .. "Play rute dari #" .. route_data.current_index .. " Speed: " .. string.format("%.1f", window.playback_speed[0]), -1)
                    end
                end
                imgui.SameLine()
                if imgui.Button("Stop Playing (Pause)", imgui.ImVec2(half_button_width, 30)) then
                    window.is_playing = false; route_data.last_stop_index = route_data.current_index; route_data.notified_next_mark_index = nil; route_data.is_waiting_at_mark = false;
                    sampAddChatMessage(COLORS.PINK_BRIGHT .. "Playback stop di #" .. route_data.current_index, -1);
                    if isCharInAnyCar(PLAYER_PED) then returnCharacterToDriver() else stopCharacterMovement() end
                end
                imgui.Separator()

                imgui.Checkbox("Tandai Titik Berhenti", window.mark_point)
                if window.mark_point[0] then imgui.TextWrapped(COLORS.GOLD .. "Centang untuk menandai titik berhenti berikutnya.") else imgui.TextWrapped(" ") end

                imgui.Text("Simpan Rute Saat Ini Sebagai:")
                imgui.PushItemWidth(full_button_width); imgui.InputText("##RouteSaveName", window.input_save_name, 128); imgui.PopItemWidth()
                if imgui.Button("Simpan Rute ke File", imgui.ImVec2(full_button_width, 0)) then
                    local route_save_name = ffi.string(window.input_save_name)
                    if route_save_name ~= "" then
                        if saveRouteToFile(route_save_name) then ffi.copy(window.input_save_name, "") end
                    else sampAddChatMessage(COLORS.PINK_BRIGHT .. "Masukkan nama file untuk rute!", -1) end
                end

                imgui.Spacing()
                if imgui.Button("Bersihkan Rute Saat Ini", imgui.ImVec2(full_button_width, 0)) then clearRoute() end
            end

            if imgui.CollapsingHeader("Settings##SettingsHeader") then
                imgui.Text("Loop Playback:")
                imgui.SameLine(); imgui.RadioButtonIntPtr("Aktif##LoopOn", window.is_looping, 1)
                imgui.SameLine(); imgui.RadioButtonIntPtr("Nonaktif##LoopOff", window.is_looping, 0)

                imgui.Text(u8"Kecepatan Playback Kendaraan:")
                imgui.PushItemWidth(full_button_width)
                if imgui.SliderFloat("##playbackspeed", window.playback_speed, 10.0, 60.0, "%.1f km/jam") then
                    savePlaybackSpeedToIni()
                end
                imgui.PopItemWidth()
                if imgui.IsItemHovered() then
                    imgui.SetTooltip("Atur kecepatan mobil saat playback rute.\nIni akan konstan di sepanjang rute.")
                end
            end

            imgui.End()
        end
    end
)

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then
        print("[RecordingRoute] Lib utama tidak termuat!")
        return
    end
    while not isSampAvailable() do wait(100) end

    pcall(refreshRouteList)
    sampAddChatMessage(string.format("%sRecording Route by adolfhytam loaded! %sCmd: /route. %sKecepatan awal: %.1f km/jam.", COLORS.PINK_BRIGHT, COLORS.CYAN, COLORS.GOLD, window.playback_speed[0]), -1)

    sampRegisterChatCommand("route", function()
        menu.active.show_menu[0] = not menu.active.show_menu[0]
    end)

    while true do
        wait(0)
        if window.is_recording[0] then
            pcall(updateRecording)
        end
        if window.is_playing then
            pcall(AutoPilot)
        end
    end
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    imgui.GetStyle().WindowPadding = imgui.ImVec2(5, 5)
    imgui.GetStyle().FramePadding = imgui.ImVec2(5, 4)
    imgui.GetStyle().ItemSpacing = imgui.ImVec2(9, 5)
    imgui.GetStyle().ItemInnerSpacing = imgui.ImVec2(4, 4)
    imgui.GetStyle().TouchExtraPadding = imgui.ImVec2(0, 0)

    imgui.GetStyle().IndentSpacing = 21
    imgui.GetStyle().ScrollbarSize = 14
    imgui.GetStyle().GrabMinSize = 0

    imgui.GetStyle().WindowBorderSize = 0
    imgui.GetStyle().ChildBorderSize = 1
    imgui.GetStyle().PopupBorderSize = 5
    imgui.GetStyle().FrameBorderSize = 1
    imgui.GetStyle().TabBorderSize = 1

    imgui.GetStyle().WindowRounding = 5
    imgui.GetStyle().ChildRounding = 5
    imgui.GetStyle().PopupRounding = 5
    imgui.GetStyle().FrameRounding = 5
    imgui.GetStyle().ScrollbarRounding = 2.5
    imgui.GetStyle().GrabRounding = 5
    imgui.GetStyle().TabRounding = 5

    imgui.GetStyle().WindowTitleAlign = imgui.ImVec2(0.50, 0.50)
    colors[clr.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)

    colors[clr.WindowBg]               = ImVec4(0.15, 0.16, 0.37, 1.00)
    colors[clr.ChildBg]                = ImVec4(0.17, 0.18, 0.43, 1.00)
    colors[clr.PopupBg]                = colors[clr.WindowBg]

    colors[clr.Border]                 = ImVec4(0.33, 0.34, 0.62, 1.00)
    colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)

    colors[clr.TitleBg]                = ImVec4(0.18, 0.20, 0.46, 1.00)
    colors[clr.TitleBgActive]          = ImVec4(0.18, 0.20, 0.46, 1.00)
    colors[clr.TitleBgCollapsed]       = ImVec4(0.18, 0.20, 0.46, 1.00)
    colors[clr.MenuBarBg]              = colors[clr.ChildBg]
    
    colors[clr.ScrollbarBg]            = ImVec4(0.14, 0.14, 0.36, 1.00)
    colors[clr.ScrollbarGrab]          = ImVec4(0.22, 0.22, 0.53, 1.00)
    colors[clr.ScrollbarGrabHovered]   = ImVec4(0.20, 0.21, 0.53, 1.00)
    colors[clr.ScrollbarGrabActive]    = ImVec4(0.25, 0.25, 0.58, 1.00)

    colors[clr.Button]                 = ImVec4(0.25, 0.25, 0.58, 1.00)
    colors[clr.ButtonHovered]          = ImVec4(0.23, 0.23, 0.55, 1.00)
    colors[clr.ButtonActive]           = ImVec4(0.27, 0.27, 0.62, 1.00)

    colors[clr.CheckMark]              = ImVec4(0.39, 0.39, 0.83, 1.00)
    colors[clr.SliderGrab]             = ImVec4(0.39, 0.39, 0.83, 1.00)
    colors[clr.SliderGrabActive]       = ImVec4(0.48, 0.48, 0.96, 1.00)

    colors[clr.FrameBg]                = colors[clr.Button]
    colors[clr.FrameBgHovered]         = colors[clr.ButtonHovered]
    colors[clr.FrameBgActive]          = colors[clr.ButtonActive]

    colors[clr.Header]                 = colors[clr.Button]
    colors[clr.HeaderHovered]          = colors[clr.ButtonHovered]
    colors[clr.HeaderActive]           = colors[clr.ButtonActive]

    colors[clr.Separator]              = ImVec4(0.43, 0.43, 0.50, 0.50)
    colors[clr.SeparatorHovered]       = colors[clr.SliderGrabActive]
    colors[clr.SeparatorActive]        = colors[clr.SliderGrabActive]

    colors[clr.ResizeGrip]             = colors[clr.Button]
    colors[clr.ResizeGripHovered]      = colors[clr.ButtonHovered]
    colors[clr.ResizeGripActive]       = colors[clr.ButtonActive]

    colors[clr.Tab]                    = colors[clr.Button]
    colors[clr.TabHovered]             = colors[clr.ButtonHovered]
    colors[clr.TabActive]              = colors[clr.ButtonActive]
    colors[clr.TabUnfocused]           = colors[clr.Button]
    colors[clr.TabUnfocusedActive]     = colors[clr.Button]

    colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)

    colors[clr.TextSelectedBg]         = ImVec4(0.33, 0.33, 0.57, 1.00)
    colors[clr.DragDropTarget]         = ImVec4(1.00, 1.00, 0.00, 0.90)

    colors[clr.NavHighlight]           = ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[clr.NavWindowingHighlight]  = ImVec4(1.00, 1.00, 1.00, 0.70)
    colors[clr.NavWindowingDimBg]      = ImVec4(0.80, 0.80, 0.80, 0.20)
    colors[clr.ModalWindowDimBg]       = ImVec4(0.00, 0.00, 0.00, 0.90)
end)
