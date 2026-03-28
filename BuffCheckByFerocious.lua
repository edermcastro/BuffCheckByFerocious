--[[
    Addon: BuffCheckByFerocious
    Version: 2.1.0 (Clean Performance Edition)
    Author: Ferocious
    Description: Real-time raid/party buff and consumable monitor for Midnight.
]]

local addonName, ns = ...

-- --- CONFIGURAÇÕES & BANCO DE DADOS ---
BuffCheckDB = BuffCheckDB or {
    minimapPos = 45,
    visible = true,
    alpha = 0.5,
    isLocked = false,
}

local lastUpdate = 0
local UPDATE_INTERVAL = 1.5 -- Intervalo otimizado para performance
local inCombat = false
local playerLines = {}

-- --- TABELAS DE IDs (Midnight 12.0.1) ---
local CLASS_BUFFS_IDS = {
    [1459]   = "MAGE",
    [21562]  = "PRIEST",
    [6673]   = "WARRIOR",
    [381732] = "EVOKER",
    [1126]   = "DRUID",
}

local FLASK_IDS_WEAK = { 
    [1235057] = true, [1235058] = true, [1235059] = true, [1235060] = true, 
    [1250100] = true, [1250101] = true, [1250102] = true, [1250103] = true, 
    [1250104] = true, [1250105] = true 
}

local FLASK_IDS_STRONG = { 
    [1230874] = true, [1230857] = true, [1235061] = true, [1230875] = true, 
    [1230877] = true, [1230876] = true, [1230878] = true, [1250200] = true, 
    [1250201] = true, [1250205] = true, [1250210] = true, [435422] = true, 
    [435416] = true,  [438499] = true,  [435418] = true, [435417] = true, 
    [443393] = true,  [443210] = true 
}

local RUNE_IDS = { 
    [1235065] = true, [1264426] = true, [1270500] = true 
}

local FOOD_IDS_WEAK = { 
    [1232317] = true, [1232318] = true, [1232319] = true, [1284616] = true, 
    [1284617] = true, [1284618] = true, [1284619] = true, [1245102] = true, 
    [1245103] = true, [1245104] = true, [1245105] = true, [1245106] = true, 
    [1245107] = true, [1246210] = true, [1246211] = true, [1246212] = true, 
    [1246215] = true, [1246220] = true, [1246225] = true 
}

local FOOD_IDS_STRONG = { 
    [1233709] = true, [1233710] = true, [1233711] = true, [1233712] = true, 
    [1233713] = true, [1233714] = true, [1233715] = true, [1233716] = true, 
    [1247001] = true, [1247002] = true, [1247003] = true, [1247004] = true 
}

-- --- INTERFACE GRÁFICA ---
local mainFrame = CreateFrame("Frame", "BuffCheckByFerociousFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(200, 40)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetClampedToScreen(true)
mainFrame:RegisterForDrag("LeftButton")

mainFrame:SetScript("OnDragStart", function(self) 
    if not BuffCheckDB.isLocked then self:StartMoving() end 
end)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

local function UpdateVisuals()
    mainFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    local a = BuffCheckDB.alpha or 0.5
    mainFrame:SetBackdropColor(0, 0, 0, a)
    mainFrame:SetBackdropBorderColor(1, 1, 1, math.min(a, 0.4))
end

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -10)
title:SetText("BuffCheck")

local lockBtn = CreateFrame("Button", nil, mainFrame)
lockBtn:SetSize(18, 18)
lockBtn:SetPoint("TOPRIGHT", -8, -8)
local lockIcon = lockBtn:CreateTexture(nil, "ARTWORK")
lockIcon:SetAllPoints()

local function UpdateLockIcon()
    if BuffCheckDB.isLocked then
        lockIcon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
        lockIcon:SetVertexColor(1, 0.5, 0.5)
    else
        lockIcon:SetAtlas("EditorMode-icon-move")
        lockIcon:SetVertexColor(0.5, 1, 0.5)
    end
end

lockBtn:SetScript("OnClick", function() 
    BuffCheckDB.isLocked = not BuffCheckDB.isLocked
    UpdateLockIcon() 
end)

local reportBtn = CreateFrame("Button", nil, mainFrame)
reportBtn:SetSize(18, 18)
reportBtn:SetPoint("TOPLEFT", 8, -8)
reportBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_02")
reportBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

-- --- LÓGICA DE SCAN ---
local function ScanUnitBuffs(unit, requiredClassBuffs)
    local statusFO, statusFL, hasR, hasB = 0, 0, false, true
    local foundBuffs = {}

    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not data then break end
        
        local sid = data.spellId
        foundBuffs[sid] = true

        if data.isFullBody or FOOD_IDS_STRONG[sid] then 
            statusFO = 2
        elseif statusFO < 2 and FOOD_IDS_WEAK[sid] then 
            statusFO = 1 
        end

        if FLASK_IDS_STRONG[sid] then 
            statusFL = 2
        elseif statusFL < 2 and FLASK_IDS_WEAK[sid] then 
            statusFL = 1 
        end

        if RUNE_IDS[sid] then hasR = true end
        i = i + 1
    end

    if requiredClassBuffs then
        for sid in pairs(requiredClassBuffs) do
            if not foundBuffs[sid] then hasB = false; break end
        end
    end
    
    return statusFO, statusFL, hasR, hasB
end

local function GetUnitList()
    local units = {}
    local num = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, num do table.insert(units, "raid"..i) end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, num - 1 do table.insert(units, "party"..i) end
    else
        table.insert(units, "player")
    end
    return units
end

local function ReportBuffsToChat()
    local units = GetUnitList()
    local req = {}
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        for sid, bclass in pairs(CLASS_BUFFS_IDS) do 
            if class == bclass then req[sid] = true end 
        end
    end

    local noFood, noFlask, needsRebuff = {}, {}, false
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local sFO, sFL, hR, hB = ScanUnitBuffs(u, req)
            local name = UnitName(u)
            if sFO == 0 then table.insert(noFood, name) end
            if sFL == 0 then table.insert(noFlask, name) end
            if not hB then needsRebuff = true end
        end
    end

    local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    if #noFood > 0 then SendChatMessage("Sem Comida: " .. table.concat(noFood, ", "), chan) end
    if #noFlask > 0 then SendChatMessage("Sem Frasco: " .. table.concat(noFlask, ", "), chan) end
    if needsRebuff then SendChatMessage("!! REBUFF !!", chan) end
end

reportBtn:SetScript("OnClick", ReportBuffsToChat)

-- --- UI UPDATES ---
local function ApplyColor(indicator, status)
    if status == 2 or status == true then 
        indicator:SetTextColor(0, 1, 0)
    elseif status == 1 then 
        indicator:SetTextColor(1, 1, 0)
    else 
        indicator:SetTextColor(1, 0, 0) 
    end
end

local function CreatePlayerLine(index)
    local f = CreateFrame("Frame", nil, mainFrame)
    f:SetSize(190, 22)
    f:SetPoint("TOP", mainFrame, "TOP", 0, -(index * 24) - 15)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(1, 1, 1, 0.05)
    
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", 5, 0)
    f.name:SetWidth(70)
    f.name:SetJustifyH("LEFT")
    
    f.indicators = {}
    local tags = {"FO", "FL", "R", "B"}
    for i, tag in ipairs(tags) do
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("RIGHT", -5 - (4-i)*22, 0)
        txt:SetText(tag)
        f.indicators[tag] = txt
    end
    return f
end

local function UpdateGroupBuffs()
    if not mainFrame:IsShown() or InCombatLockdown() then return end
    
    local units = GetUnitList()
    local req = {}
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        for sid, bclass in pairs(CLASS_BUFFS_IDS) do 
            if class == bclass then req[sid] = true end 
        end
    end
    
    for _, line in ipairs(playerLines) do line:Hide() end
    
    local dIdx = 1
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local sFO, sFL, hR, hB = ScanUnitBuffs(unit, req)
            if not (sFO == 2 and sFL == 2 and hR and hB) then
                if not playerLines[dIdx] then 
                    playerLines[dIdx] = CreatePlayerLine(dIdx) 
                end
                local line = playerLines[dIdx]
                line.name:SetText(UnitName(unit))
                ApplyColor(line.indicators["FO"], sFO)
                ApplyColor(line.indicators["FL"], sFL)
                ApplyColor(line.indicators["R"], hR)
                ApplyColor(line.indicators["B"], hB)
                line:Show()
                dIdx = dIdx + 1
            end
        end
    end
    mainFrame:SetHeight(math.max(40, 40 + ((dIdx - 1) * 24) + 5))
end

-- --- TIMER & EVENTOS ---
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    if InCombatLockdown() then return end
    lastUpdate = lastUpdate + elapsed
    if lastUpdate >= UPDATE_INTERVAL then 
        lastUpdate = 0
        UpdateGroupBuffs() 
    end
end)

mainFrame:EnableMouseWheel(true)
mainFrame:SetScript("OnMouseWheel", function(self, delta)
    if BuffCheckDB.isLocked then return end
    BuffCheckDB.alpha = math.max(0.1, math.min(1, (BuffCheckDB.alpha or 0.5) + (delta * 0.05)))
    UpdateVisuals()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        UpdateVisuals()
        UpdateLockIcon()
        UpdateMinimapPosition()
        mainFrame:SetShown(BuffCheckDB.visible)
    elseif event == "PLAYER_REGEN_DISABLED" then 
        mainFrame:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then 
        if BuffCheckDB.visible then mainFrame:Show() end 
    end
end)

-- --- MINIMAP ---
local miniButton = CreateFrame("Button", "BuffCheckByFerociousMinimap", Minimap)
miniButton:SetSize(31, 31)
miniButton:SetFrameLevel(10)
miniButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local icon = miniButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15")
icon:SetSize(20, 20)
icon:SetPoint("CENTER")
local border = miniButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(52, 52)
border:SetPoint("TOPLEFT")

function UpdateMinimapPosition()
    local angle = math.rad(BuffCheckDB.minimapPos or 45)
    miniButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 102, math.sin(angle) * 102)
end

miniButton:RegisterForDrag("LeftButton")
miniButton:SetScript("OnDragStart", function(self) 
    self:SetScript("OnUpdate", function()
        local cx, cy = Minimap:GetCenter()
        local ux, uy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        BuffCheckDB.minimapPos = math.deg(math.atan2((uy/scale)-cy, (ux/scale)-cx))
        UpdateMinimapPosition()
    end) 
end)
miniButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
miniButton:SetScript("OnClick", function() 
    BuffCheckDB.visible = not BuffCheckDB.visible
    mainFrame:SetShown(BuffCheckDB.visible) 
end)

-- --- SLASH ---
SLASH_BUFFCHECK1 = "/bc"
SlashCmdList["BUFFCHECK"] = function() 
    BuffCheckDB.visible = not BuffCheckDB.visible
    mainFrame:SetShown(BuffCheckDB.visible) 
end