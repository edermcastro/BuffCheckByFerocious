--[[
    Addon: BuffCheckByFerocious
    Versão: 2.0.1 (UI Adjustment)
    Descrição: Verifica consumíveis e buffs. Botão de relatório movido para a esquerda.
    Controle: 
        - Clique no Cadeado/Setas: Bloqueia/Desbloqueia movimento da janela.
        - Clique no Pergaminho (Esquerda): Relata players sem buffs no chat.
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

-- --- TABELAS DE IDs (Seguro contra Taint) ---

-- Buffs de Classe
local CLASS_BUFFS_IDS = {
    [1459] = "MAGE",    -- Arcane Intellect
    [21562] = "PRIEST",  -- Power Word: Fortitude
    [6673] = "WARRIOR", -- Battle Shout
    [381732] = "EVOKER", -- Blessing of Bronze
    [1126] = "DRUID",   -- Mark of the Wild
}

-- Frascos / Elixires (IDs comuns de Retail/Midnight)
local FLASK_IDS = {
    435422, 435416, 438499, 435418, 435417, 443393, 443210, 443211, 443212
}

-- Runas
local RUNE_IDS = {
    434488, 393438
}

-- Comidas (IDs específicos como fallback)
local FOOD_IDS = {
    440401, 440402, 440403, 440316, 440317, 440318
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

-- --- BOTÕES DO CABEÇALHO ---

-- Botão de Lock (Mantido na Direita)
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

-- Botão de Relatório (Movido para a Esquerda)
local reportBtn = CreateFrame("Button", nil, mainFrame)
reportBtn:SetSize(18, 18)
reportBtn:SetPoint("TOPLEFT", 8, -8) -- Nova posição: Canto superior esquerdo
reportBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_02")
reportBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

-- --- LÓGICA DE RELATÓRIO NO CHAT ---

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
    local hasC, hasF, hasR, hasB = false, false, false, true
    for spellID in pairs(requiredClassBuffs) do
        if not C_UnitAuras.GetPlayerAuraBySpellID(spellID, unit) then
            hasB = false
            break
        end
    end
    for _, id in ipairs(FLASK_IDS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then hasF = true break end
    end
    for _, id in ipairs(RUNE_IDS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then hasR = true break end
    end
    for j = 1, 40 do
        local data = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
        if not data then break end
        if data.isFullBody then hasC = true break end
    end
    if not hasC then
        for _, id in ipairs(FOOD_IDS) do
            if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then hasC = true break end
        end
    end
    return hasC, hasF, hasR, hasB
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

    local noFood = {}
    local noFlask = {}
    local needsRebuff = false

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local hasC, hasF, hasR, hasB = ScanUnitBuffs(unit, requiredClassBuffs)
            local name = UnitName(unit)
            if not hasC then table.insert(noFood, name) end
            if not hasF then table.insert(noFlask, name) end
            if not hasB then needsRebuff = true end
        end
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    
    if #noFood > 0 then
        SendChatMessage("noFood: " .. table.concat(noFood, ", "), channel)
    end
    if #noFlask > 0 then
        SendChatMessage("noFlask: " .. table.concat(noFlask, ", "), channel)
    end
    if needsRebuff then
        SendChatMessage("!! REBUFF !!", channel)
    end
    
    if #noFood == 0 and #noFlask == 0 and not needsRebuff then
        print("|cFFFFFF00BuffCheck:|r Todos estão bufados!")
    end
end

reportBtn:SetScript("OnClick", function()
    ReportBuffsToChat()
end)
reportBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Relatar no Chat")
    GameTooltip:AddLine("Envia a lista de players sem buffs para a Raid/Grupo.", 1, 1, 1)
    GameTooltip:Show()
end)
reportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- --- RESTO DA INTERFACE ---

mainFrame:EnableMouseWheel(true)
mainFrame:SetScript("OnMouseWheel", function(self, delta)
    if BuffCheckDB.isLocked then return end
    local currentAlpha = BuffCheckDB.alpha or 0.5
    BuffCheckDB.alpha = math.max(0.1, math.min(1, currentAlpha + (delta * 0.05)))
    UpdateVisuals()
end)

local scrollFrame = CreateFrame("Frame", nil, mainFrame)
scrollFrame:SetPoint("TOPLEFT", 5, -35)
scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)

local playerLines = {}

local function CreatePlayerLine(index)
    local f = CreateFrame("Frame", nil, scrollFrame)
    f:SetSize(210, 22)
    f:SetPoint("TOP", 0, -(index - 1) * 24)
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
            local hasC, hasF, hasR, hasB = ScanUnitBuffs(unit, requiredClassBuffs)
            
            if not (hasC and hasF and hasR and hasB) then
                if not playerLines[displayIndex] then playerLines[displayIndex] = CreatePlayerLine(displayIndex) end
                local line = playerLines[displayIndex]
                line.name:SetText(UnitName(unit))
                
                line.indicators["FO"]:SetTextColor(hasC and 0 or 1, hasC and 1 or 0, 0)
                line.indicators["FL"]:SetTextColor(hasF and 0 or 1, hasF and 1 or 0, 0)
                line.indicators["R"]:SetTextColor(hasR and 0 or 1, hasR and 1 or 0, 0)
                line.indicators["B"]:SetTextColor(hasB and 0 or 1, hasB and 1 or 0, 0)
                
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

-- --- TIMER ---
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    if inCombat or InCombatLockdown() then return end 
    
    lastUpdate = lastUpdate + elapsed
    if lastUpdate >= UPDATE_INTERVAL then
        lastUpdate = 0
        UpdateGroupBuffs()
    end
end)

-- --- MINIMAP ICON ---
local miniButton = CreateFrame("Button", "BuffCheckByFerociousMinimap", Minimap)
miniButton:SetSize(31, 31)
miniButton:SetFrameLevel(10)
miniButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = miniButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\BuffCheckByFerocious\\icon") 
if not icon:GetTexture() then icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15") end
icon:SetSize(20, 20)
icon:SetPoint("CENTER")

local border = miniButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(52, 52)
border:SetPoint("TOPLEFT")

local function UpdateMinimapPosition()
    local angle = math.rad(BuffCheckDB.minimapPos or 45)
    local x, y = math.cos(angle) * 102, math.sin(angle) * 102
    miniButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
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

-- --- EVENTOS ---
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
        if BuffCheckDB.visible then
            mainFrame:Show()
            UpdateGroupBuffs()
        end
    else
        UpdateGroupBuffs()
    end
end)