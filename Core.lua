--[[
    Addon: BuffCheckByFerocious
    Versão: 1.8.0 (Fix Combat Taint & Player Missing)
    Descrição: Verifica consumíveis e buffs. Proteção contra Taint de combate.
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

-- Mapeamento de Buffs por Classe (SpellIDs para evitar Taint)
local CLASS_BUFFS = {
    [1459] = "Arcane Intellect",
    [21562] = "Power Word: Fortitude",
    [6673] = "Battle Shout",
    [381732] = "Blessing of Bronze",
    [1126] = "Mark of the Wild",
}

-- Variáveis de controle de atualização
local lastUpdate = 0
local UPDATE_INTERVAL = 1.0 -- Varredura a cada 1 segundo

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

-- Botão de Bloqueio
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

-- --- LÓGICA DE SCAN ---

-- Obtém os buffs de classe necessários baseados na composição do grupo
local function GetRequiredBuffs()
    local required = {}
    local numGroup = GetNumGroupMembers()
    
    -- Função auxiliar para mapear buffs pela classe da unidade
    local function CheckUnit(unit)
        local _, class = UnitClass(unit)
        if class == "MAGE" then required[1459] = true end
        if class == "PRIEST" then required[21562] = true end
        if class == "WARRIOR" then required[6673] = true end
        if class == "EVOKER" then required[381732] = true end
        if class == "DRUID" then required[1126] = true end
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
    if not mainFrame:IsShown() then return end
    
    local requiredClassBuffs = GetRequiredBuffs()
    local numGroup = GetNumGroupMembers()
    
    -- Lista de unidades a verificar
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
            
            -- Verificar Buffs de Classe (Pelo SpellID para evitar Taint)
            for spellID in pairs(requiredClassBuffs) do
                if not C_UnitAuras.GetPlayerAuraBySpellID(spellID, unit) then
                    hasB = false
                    break
                end
            end

            -- Scan Consumíveis
            -- IMPORTANTE: Usamos C_Spell.GetSpellName(spellID) para evitar manipular a secret string diretamente
            for j = 1, 40 do
                local data = C_UnitAuras.GetAuraDataByIndex(unit, j, "HELPFUL")
                if not data then break end
                
                -- Obtemos o nome do feitiço de forma segura (não contaminada)
                local spellName = C_Spell.GetSpellName(data.spellId)
                if spellName then
                    local auraNameLower = spellName:lower()
                    
                    -- Lógica de busca por palavras-chave
                    if data.isFullBody or auraNameLower:find("well fed") or auraNameLower:find("alimentado") then hasC = true end
                    if auraNameLower:find("flask") or auraNameLower:find("frasco") or auraNameLower:find("phial") or auraNameLower:find("frasco") then hasF = true end
                    if auraNameLower:find("rune") or auraNameLower:find("runa") then hasR = true end
                end
            end
            
            -- Se faltar qualquer coisa, mostra na lista
            if not (hasC and hasF and hasR and hasB) then
                if not playerLines[displayIndex] then playerLines[displayIndex] = CreatePlayerLine(displayIndex) end
                local line = playerLines[displayIndex]
                line.name:SetText(UnitName(unit))
                
                -- Atualiza cores das letras
                line.indicators["FO"]:SetTextColor(hasC and 0 or 1, hasC and 1 or 0, 0)
                line.indicators["FL"]:SetTextColor(hasF and 0 or 1, hasF and 1 or 0, 0)
                line.indicators["R"]:SetTextColor(hasR and 0 or 1, hasR and 1 or 0, 0)
                line.indicators["B"]:SetTextColor(hasB and 0 or 1, hasB and 1 or 0, 0)
                
                line:Show()
                displayIndex = displayIndex + 1
            end
        end
    end

    -- Ajuste dinâmico de altura da janela
    local numDisplayed = displayIndex - 1
    local targetHeight = 40 + (numDisplayed * 24) + 5
    if numDisplayed == 0 then targetHeight = 40 end
    
    if mainFrame:GetHeight() ~= targetHeight then
        mainFrame:SetHeight(targetHeight)
    end
end

-- --- TIMER DE ATUALIZAÇÃO ---
mainFrame:SetScript("OnUpdate", function(self, elapsed)
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
    if not BuffCheckDB.minimapPos then BuffCheckDB.minimapPos = 45 end
    local angle = math.rad(BuffCheckDB.minimapPos)
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
miniButton:SetScript("OnDragStop", function(self) 
    self:UnlockHighlight() 
    self:SetScript("OnUpdate", nil) 
end)

miniButton:SetScript("OnClick", function()
    BuffCheckDB.visible = not BuffCheckDB.visible
    mainFrame:SetShown(BuffCheckDB.visible)
end)

-- --- EVENTOS ---
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        UpdateVisuals()
        UpdateLockIcon()
        UpdateMinimapPosition()
        mainFrame:SetShown(BuffCheckDB.visible)
    else
        UpdateGroupBuffs()
    end
end)