--[[
    Addon: BuffCheckByFerocious
    Versão: 1.9.3 (Universal Aura Fix)
    Descrição: Verifica consumíveis e buffs. Compatibilidade total com APIs Retail/Midnight sem erros de Taint.
    Controle: 
        - Clique no Cadeado/Setas: Bloqueia/Desbloqueia movimento da janela.
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

-- Comidas (IDs específicos como fallback caso isFullBody falhe)
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

local lockBtn = CreateFrame("Button", nil, mainFrame)
lockBtn:SetSize(20, 20)
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

-- --- LÓGICA DE SCAN SEGURO ---

local function GetRequiredBuffs()
    local required = {}
    local numGroup = GetNumGroupMembers()
    
    local function CheckUnit(unit)
        local _, class = UnitClass(unit)
        for spellID, buffClass in pairs(CLASS_BUFFS_IDS) do
            if class == buffClass then required[spellID] = true end
        end
    end

    if IsInRaid() then
        for i = 1, numGroup do CheckUnit("raid"..i) end
    elseif IsInGroup() then
        CheckUnit("player")
        for i = 1, numGroup - 1 do CheckUnit("party"..i) end
    else
        CheckUnit("player")
    end
    return required
end

local function UpdateGroupBuffs()
    if not mainFrame:IsShown() or inCombat or InCombatLockdown() then 
        BuffCheckDB.visible = false
        mainFrame:SetShown(BuffCheckDB.visible)
    return end
    
    local requiredClassBuffs = GetRequiredBuffs()
    local numGroup = GetNumGroupMembers()
    local units = {}
    
    if IsInRaid() then
        for i = 1, numGroup do table.insert(units, "raid"..i) end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, numGroup - 1 do table.insert(units, "party"..i) end
    else
        table.insert(units, "player")
    end
    
    for _, line in ipairs(playerLines) do line:Hide() end
    
    local displayIndex = 1
    
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local hasC, hasF, hasR, hasB = false, false, false, true
            
            -- 1. Verificar Buffs de Classe (API Segura)
            for spellID in pairs(requiredClassBuffs) do
                if not C_UnitAuras.GetPlayerAuraBySpellID(spellID, unit) then
                    hasB = false
                    break
                end
            end

            -- 2. Verificar Frascos (API Segura)
            for _, id in ipairs(FLASK_IDS) do
                if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then
                    hasF = true
                    break
                end
            end

            -- 3. Verificar Runas (API Segura)
            for _, id in ipairs(RUNE_IDS) do
                if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then
                    hasR = true
                    break
                end
            end

            -- 4. Verificar Comida (Usa loop numérico em vez de ForEachAura para compatibilidade)
            -- IMPORTANTE: Não tocamos no campo 'name' para evitar Taint
            for j = 1, 40 do
                local data = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
                if not data then break end
                if data.isFullBody then 
                    hasC = true 
                    break 
                end
            end
            
            -- Fallback para IDs específicos de comida se isFullBody não detectar
            if not hasC then
                for _, id in ipairs(FOOD_IDS) do
                    if C_UnitAuras.GetPlayerAuraBySpellID(id, unit) then
                        hasC = true
                        break
                    end
                end
            end

            -- Exibição
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