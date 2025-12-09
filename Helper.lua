script_name("Newbie Helper")
script_version("2.0")

local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local function u8(text)
    return encoding.UTF8:decode(text)
end

local ev = require 'lib.samp.events'

local show_window = imgui.new.bool(true)
local question_queue = {}

function main()
    while not isSampAvailable() do wait(100) end
    
    sampRegisterChatCommand("rodion", function()
        show_window[0] = not show_window[0]
        sampAddChatMessage("{00FF00}[Rodion Veklov] " .. (show_window[0] and "ON" or "OFF"), -1)
    end)
    
    wait(-1)
end

function addQuestion(id, name)
    for i, q in ipairs(question_queue) do
        if q.id == id then
            return
        end
    end
    
    table.insert(question_queue, {id = id, name = name})
end

function removeQuestionByName(askerName)
    for i = #question_queue, 1, -1 do
        if question_queue[i].name == askerName then
            table.remove(question_queue, i)
            return true
        end
    end
    return false
end

function ev.onServerMessage(color, text)
    local cleanText = text:gsub("{%x%x%x%x%x%x}", "")
    
    local name, id1, id2 = cleanText:match("%*%* (.-)%((%d+)%)%s+da%s+gui%s+mot%s+cau%s+hoi%s+newb%.%s+%(su%s+dung%s+/cnch%s+(%d+)%)")
    
    if not name then
        name, id1, id2 = cleanText:match("(.-)%((%d+)%)%s+da%s+gui%s+mot%s+cau%s+hoi%s+newb.*cnch%s+(%d+)")
    end
    
    if not name then
        local temp = cleanText:match("(.-)%((%d+)%).*cnch%s+(%d+)")
        if temp then
            name = temp
            id1 = cleanText:match("%((%d+)%)")
            id2 = cleanText:match("cnch%s+(%d+)")
        end
    end
    
    if name and id1 and id2 and id1 == id2 then
        addQuestion(tonumber(id1), name:match("^%s*(.-)%s*$"))
    end
    
    local helperName, askerName = cleanText:match("%*([^%*]+)da%s+chap%s+nhan%s+cau%s+hoi%s+cua%s+(.-)%.?$")
    
    if not helperName or not askerName then
        helperName, askerName = cleanText:match("%*%s*(.-)%s+da%s+chap%s+nhan.-cua%s+(.-)%.?$")
    end
    
    if helperName and askerName then
        helperName = helperName:match("^%s*(.-)%s*$")
        askerName = askerName:match("^%s*(.-)%s*$")
        removeQuestionByName(askerName)
    end
end

imgui.OnFrame(
    function() return show_window[0] end,
    function(self)
        local resX, resY = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        
        local windowHeight = 100 + (#question_queue * 70)
        if windowHeight > resY * 0.8 then windowHeight = resY * 0.8 end
        
        imgui.SetNextWindowSize(imgui.ImVec2(350, windowHeight), imgui.Cond.Always)
        
        imgui.Begin("Rodion Veklov", show_window, imgui.WindowFlags.NoResize)
        
        if #question_queue > 0 then
            for i, q in ipairs(question_queue) do
                if i == 1 then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.8, 0.2, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.3, 0.9, 0.3, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.1, 0.7, 0.1, 1.0))
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.6, 0.6, 0.2, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.7, 0.7, 0.3, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.5, 0.5, 0.1, 1.0))
                end
                
                local buttonText = string.format("#%d: %s (ID: %d)##btn%d", i, q.name, q.id, i)
                if imgui.Button(buttonText, imgui.ImVec2(330, 50)) then
                    sampSendChat("/cnch " .. q.id)
                    table.remove(question_queue, i)
                end
                
                imgui.PopStyleColor(3)
                
                if i < #question_queue then
                    imgui.Spacing()
                end
            end
        end
        
        imgui.End()
    end
).HideCursor = true