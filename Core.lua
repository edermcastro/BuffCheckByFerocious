--[[
    Addon: BuffCheckByFerocious
    Versão: 2.0.4 (Quality Color Grading)
    Descrição: Verifica consumíveis e buffs. Diferencia qualidade (Verde = Melhor, Amarelo = Fraco).
    Controle: 
        - Clique no Cadeado/Setas: Bloqueia/Desbloqueia movimento da janela.
        - Clique no Pergaminho (Esquerda): Relata no chat da Raid/Grupo.
        - Scroll no título: Ajustar transparência.
]]

local addonName, ns = ...

-- Configurações de Banco de Dados
BuffCheckDB = BuffCheckDB or {
    minimapPos = 45,
    visible = true,
    alpha = 0.5,
    isLocked = false,
}

-- Variáveis de controle de atualização
local lastUpdate = 0
local UPDATE_INTERVAL = 1.0 
local inCombat = false

-- --- TABELAS DE IDs (Categorizados por Qualidade) ---

-- Buffs de Classe
local CLASS_BUFFS_IDS = {
    [1459] = "MAGE",    -- Arcane Intellect
    [21562] = "PRIEST",  -- Power Word: Fortitude
    [6673] = "WARRIOR", -- Battle Shout
    [381732] = "EVOKER", -- Blessing of Bronze
    [1126] = "DRUID",   -- Mark of the Wild
}

-- FRASCOS
local FLASK_IDS_WEAK = {
    1235057, -- Frasco da Resistencia Talassiana (Versatilidade)
    1235058, -- Frasco dos Cavaleiros de Sangue (Aceleração)
    1235059, -- Frasco dos Magisteres (Maestria)
    1235060, -- Frasco do Sol Estilhaçado (Crítico)
}

local FLASK_IDS_STRONG = {
    1230874, 1230857, -- Calderões
    1235061, -- PVP
    1230875, 1230877, 1230876, 1230878, -- Melhores Individuais
    435422, 435416, 438499, 435418, 435417, 443393, 443210 -- TWW Fallback (Considerados fortes para 12.0)
}

-- RUNAS
local RUNE_IDS = {
    [1235065] = true, -- Runa de Aumento Tocada pelo Caos (Midnight)
    [1264426] = true, -- Runa de Aumento Tocada pelo Caos (Midnight)
}

-- COMIDAS
local FOOD_IDS_WEAK = {
    1232317, -- Bem alimentado (Base)
    1232318, -- Silvermoon Parade (Banquete)
    1232319, -- Royal Toast (Status único)
    1284616, 1284617, 1284618, 1284619, -- Marmita do Campeão
}

local FOOD_IDS_STRONG = {
    1233709, 1233710, 1233711, 1233712, 1233713, 1233714, 1233715, 1233716, -- Substancialmente Bem Alimentado
}

-- --- INTERFACE GRÁFICA ---
local mainFrame = CreateFrame("Frame", "BuffCheckByFerociousFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(220, 40)
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
title:SetText("BuffCheckByFerocious")

-- --- BOTÕES ---
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

local function HasAura(unit, spellID)
    if not UnitExists(unit) then return false end
    for i = 1, 40 do
        local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not data then break end
        if data.spellId == spellID then return true end
    end
    return false
end

-- Retorna 0: Off, 1: Weak, 2: Strong
local function GetQualityStatus(unit, weakList, strongList, useFullBody)
    if useFullBody then
        for i = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not data then break end
            if data.isFullBody then return 2 end -- FullBody geralmente é banquete/flask forte
        end
    end

    for _, id in ipairs(strongList) do
        if HasAura(unit, id) then return 2 end
    end
    for _, id in ipairs(weakList) do
        if HasAura(unit, id) then return 1 end
    end
    return 0
end

local function GetUnitList()
    local units = {}
    local numGroup = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, numGroup do table.insert(units, "raid"..i) end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, numGroup - 1 do table.insert(units, "party"..i) end
    else
        table.insert(units, "player")
    end
    return units
end

local function ScanUnitBuffs(unit, requiredClassBuffs)
    -- FO: Food, FL: Flask, R: Rune, B: ClassBuff
    local statusFO = GetQualityStatus(unit, FOOD_IDS_WEAK, FOOD_IDS_STRONG, true)
    local statusFL = GetQualityStatus(unit, FLASK_IDS_WEAK, FLASK_IDS_STRONG, false)
    
    local hasR = false
    for id in pairs(RUNE_IDS) do
        if HasAura(unit, id) then hasR = true break end
    end

    local hasB = true
    for spellID in pairs(requiredClassBuffs) do
        if not HasAura(unit, spellID) then hasB = false break end
    end
    
    return statusFO, statusFL, hasR, hasB
end

local function ReportBuffsToChat()
    local units = GetUnitList()
    local requiredClassBuffs = {}
    for _, unit in ipairs(units) do
        local _, class = UnitClass(unit)
        for spellID, buffClass in pairs(CLASS_BUFFS_IDS) do
            if class == buffClass then requiredClassBuffs[spellID] = true end
        end
    end

    local noFood, noFlask = {}, {}
    local needsRebuff = false

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local sFO, sFL, hasR, hasB = ScanUnitBuffs(unit, requiredClassBuffs)
            local name = UnitName(unit)
            if sFO == 0 then table.insert(noFood, name) end
            if sFL == 0 then table.insert(noFlask, name) end
            if not hasB then needsRebuff = true end
        end
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    if #noFood > 0 then SendChatMessage("noFood: " .. table.concat(noFood, ", "), channel) end
    if #noFlask > 0 then SendChatMessage("noFlask: " .. table.concat(noFlask, ", "), channel) end
    if needsRebuff then SendChatMessage("!! REBUFF !!", channel) end
    
    if #noFood == 0 and #noFlask == 0 and not needsRebuff then
        print("|cFFFFFF00BuffCheck:|r Todos estão bufados!")
    end
end

reportBtn:SetScript("OnClick", ReportBuffsToChat)

-- --- UI UPDATES ---
local playerLines = {}

local function ApplyIndicatorColor(indicator, status)
    if status == 2 or status == true then
        indicator:SetTextColor(0, 1, 0) -- Verde (Forte/Ok)
    elseif status == 1 then
        indicator:SetTextColor(1, 1, 0) -- Amarelo (Fraco)
    else
        indicator:SetTextColor(1, 0, 0) -- Vermelho (Faltando)
    end
end

local function CreatePlayerLine(index)
    local f = CreateFrame("Frame", nil, mainFrame)
    f:SetSize(210, 22)
    f:SetPoint("TOP", mainFrame, "TOP", 0, -(index * 24) - 15)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(1, 1, 1, 0.05)
    
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", 5, 0)
    f.name:SetWidth(90)
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
    if not mainFrame:IsShown() or inCombat or InCombatLockdown() then return end
    
    local units = GetUnitList()
    local requiredClassBuffs = {}
    for _, unit in ipairs(units) do
        local _, class = UnitClass(unit)
        for spellID, buffClass in pairs(CLASS_BUFFS_IDS) do
            if class == buffClass then requiredClassBuffs[spellID] = true end
        end
    end
    
    for _, line in ipairs(playerLines) do line:Hide() end
    
    local displayIndex = 1
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local sFO, sFL, hasR, hasB = ScanUnitBuffs(unit, requiredClassBuffs)
            
            -- Se não estiver tudo VERDE, mostra na lista
            if not (sFO == 2 and sFL == 2 and hasR and hasB) then
                if not playerLines[displayIndex] then playerLines[displayIndex] = CreatePlayerLine(displayIndex) end
                local line = playerLines[displayIndex]
                line.name:SetText(UnitName(unit))
                
                ApplyIndicatorColor(line.indicators["FO"], sFO)
                ApplyIndicatorColor(line.indicators["FL"], sFL)
                ApplyIndicatorColor(line.indicators["R"], hasR)
                ApplyIndicatorColor(line.indicators["B"], hasB)
                
                line:Show()
                displayIndex = displayIndex + 1
            end
        end
    end

    if not InCombatLockdown() then
        local targetHeight = math.max(40, 40 + ((displayIndex - 1) * 24) + 5)
        if mainFrame:GetHeight() ~= targetHeight then mainFrame:SetHeight(targetHeight) end
    end
end

-- --- TIMER & EVENTOS ---
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    if inCombat or InCombatLockdown() then return end 
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
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        UpdateVisuals()
        UpdateLockIcon()
        UpdateMinimapPosition()
        mainFrame:SetShown(BuffCheckDB.visible)
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        mainFrame:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if BuffCheckDB.visible then mainFrame:Show() UpdateGroupBuffs() end
    else
        UpdateGroupBuffs()
    end
end)

-- --- MINIMAP ICON ---
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
    self:LockHighlight() 
    self:SetScript("OnUpdate", function()
        local cx, cy = Minimap:GetCenter()
        local ux, uy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        BuffCheckDB.minimapPos = math.deg(math.atan2((uy/scale)-cy, (ux/scale)-cx))
        UpdateMinimapPosition()
    end) 
end)
miniButton:SetScript("OnDragStop", function(self) self:UnlockHighlight() self:SetScript("OnUpdate", nil) end)
miniButton:SetScript("OnClick", function()
    BuffCheckDB.visible = not BuffCheckDB.visible
    mainFrame:SetShown(BuffCheckDB.visible)
end)

-- --- SLASH CMDS ---
SLASH_BUFFCHECK1 = "/buffcheck"
SlashCmdList["BUFFCHECK"] = function(msg)
    if msg == "debug" then
        print("|cFFFFFF00BuffCheck Debug:|r IDs ativos:")
        for j = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex("player", j, "HELPFUL")
            if data then print(string.format("- |cFF00FF00ID: %d|r | %s", data.spellId, data.name)) end
        end
    else
        BuffCheckDB.visible = not BuffCheckDB.visible
        mainFrame:SetShown(BuffCheckDB.visible)
    end
end