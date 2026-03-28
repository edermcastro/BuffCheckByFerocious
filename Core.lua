--[[
    Addon: BuffCheckByFerocious
    Versão: 2.0.9 (EnchantID 8052 Integration)
    Descrição: Verifica consumíveis, buffs e óleos. Adicionado suporte para EnchantID 8052.
    Controle: 
        - Clique no Cadeado/Setas: Bloqueia/Desbloqueia movimento da janela.
        - Clique no Pergaminho (Esquerda): Relata no chat.
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
local playerLines = {}

-- --- TABELAS DE IDs (Midnight 12.0.1) ---

local CLASS_BUFFS_IDS = {
    [1459] = "MAGE", [21562] = "PRIEST", [6673] = "WARRIOR", [381732] = "EVOKER", [1126] = "DRUID",
}

local FLASK_IDS_WEAK = { [1235057]=true, [1235058]=true, [1235059]=true, [1235060]=true, [1250100]=true, [1250101]=true, [1250102]=true, [1250103]=true, [1250104]=true, [1250105]=true }
local FLASK_IDS_STRONG = { [1230874]=true, [1230857]=true, [1235061]=true, [1230875]=true, [1230877]=true, [1230876]=true, [1230878]=true, [1250200]=true, [1250201]=true, [1250205]=true, [1250210]=true, [435422]=true, [435416]=true, [438499]=true, [435418]=true, [435417]=true, [443393]=true, [443210]=true }

-- ÓLEOS: Adicionado EnchantID 8052 (Óleo de Fénix Talassiano)
local OIL_IDS = { 
    [8051]=true, [8052]=true, [8053]=true, [8054]=true -- ID de Encantamento de Arma
}

local RUNE_IDS = { [1235065]=true, [1264426]=true, [1270500]=true }
local FOOD_IDS_WEAK = { [1232317]=true, [1232318]=true, [1232319]=true, [1284616]=true, [1284617]=true, [1284618]=true, [1284619]=true, [1245102]=true, [1245103]=true, [1245104]=true, [1245105]=true, [1245106]=true, [1245107]=true, [1246210]=true, [1246211]=true, [1246212]=true, [1246215]=true, [1246220]=true, [1246225]=true }
local FOOD_IDS_STRONG = { [1233709]=true, [1233710]=true, [1233711]=true, [1233712]=true, [1233713]=true, [1233714]=true, [1233715]=true, [1233716]=true, [1247001]=true, [1247002]=true, [1247003]=true, [1247004]=true }

-- --- INTERFACE GRÁFICA ---
local mainFrame = CreateFrame("Frame", "BuffCheckByFerociousFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(220, 40)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetClampedToScreen(true)
mainFrame:RegisterForDrag("LeftButton")

mainFrame:SetScript("OnDragStart", function(self) if not BuffCheckDB.isLocked then self:StartMoving() end end)
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

-- Botões de Cabeçalho
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

lockBtn:SetScript("OnClick", function() BuffCheckDB.isLocked = not BuffCheckDB.isLocked; UpdateLockIcon() end)

local reportBtn = CreateFrame("Button", nil, mainFrame)
reportBtn:SetSize(18, 18)
reportBtn:SetPoint("TOPLEFT", 8, -8)
reportBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_02")
reportBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

-- --- LÓGICA DE SCAN ---

local function ScanUnitBuffsOptimized(unit, requiredClassBuffs)
    local statusFO, statusFL, hasOL, hasR, hasB = 0, 0, false, false, true
    local foundBuffs = {}

    -- Verificação de Auras convencionais
    for i = 1, 100 do
        local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not data then break end
        
        local sid = data.spellId
        foundBuffs[sid] = true

        if data.isFullBody or FOOD_IDS_STRONG[sid] then statusFO = 2
        elseif statusFO < 2 and FOOD_IDS_WEAK[sid] then statusFO = 1 end

        if FLASK_IDS_STRONG[sid] then statusFL = 2
        elseif statusFL < 2 and FLASK_IDS_WEAK[sid] then statusFL = 1 end

        if OIL_IDS[sid] then hasOL = true end
        if RUNE_IDS[sid] then hasR = true end
    end

    -- Verificação de Encantamento de Arma (Para óleos que não criam buffs de aura)
    if not hasOL and unit == "player" then
        local hasMainHand, _, _, mainHandEnchantID = GetWeaponEnchantInfo()
        if hasMainHand and OIL_IDS[mainHandEnchantID] then hasOL = true end
    end

    if requiredClassBuffs then
        for spellID in pairs(requiredClassBuffs) do
            if not foundBuffs[spellID] then hasB = false; break end
        end
    end
    
    return statusFO, statusFL, hasOL, hasR, hasB
end

local function GetUnitList()
    local units = {}
    local numGroup = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, numGroup do units[i] = "raid"..i end
    elseif IsInGroup() then
        units[1] = "player"
        for i = 1, numGroup - 1 do units[i+1] = "party"..i end
    else
        units[1] = "player"
    end
    return units
end

local function ReportBuffsToChat()
    local units = GetUnitList()
    local req = {}
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        for sid, bclass in pairs(CLASS_BUFFS_IDS) do if class == bclass then req[sid] = true end end
    end

    local noFood, noFlask, noOil, needsRebuff = {}, {}, {}, false
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local sFO, sFL, hOL, hR, hB = ScanUnitBuffsOptimized(u, req)
            local name = UnitName(u)
            if sFO == 0 then table.insert(noFood, name) end
            if sFL == 0 then table.insert(noFlask, name) end
            if not hOL then table.insert(noOil, name) end
            if not hB then needsRebuff = true end
        end
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    if #noFood > 0 then SendChatMessage("Comida: " .. table.concat(noFood, ", "), channel) end
    if #noFlask > 0 then SendChatMessage("Frasco: " .. table.concat(noFlask, ", "), channel) end
    if #noOil > 0 then SendChatMessage("Óleo/Pedra: " .. table.concat(noOil, ", "), channel) end
    if needsRebuff then SendChatMessage("!! REBUFF !!", channel) end
end

reportBtn:SetScript("OnClick", ReportBuffsToChat)

-- --- ATUALIZAÇÃO DA INTERFACE ---
local function ApplyColor(indicator, status)
    if status == 2 or status == true then indicator:SetTextColor(0, 1, 0) -- Verde
    elseif status == 1 then indicator:SetTextColor(1, 1, 0) -- Amarelo
    else indicator:SetTextColor(1, 0, 0) end -- Vermelho
end

local function CreatePlayerLine(index)
    local f = CreateFrame("Frame", nil, mainFrame)
    f:SetSize(210, 22)
    f:SetPoint("TOP", mainFrame, "TOP", 0, -(index * 24) - 15)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(); f.bg:SetColorTexture(1, 1, 1, 0.05)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", 5, 0); f.name:SetWidth(80); f.name:SetJustifyH("LEFT")
    f.indicators = {}
    local tags = {"FO", "FL", "OL", "R", "B"}
    for i, tag in ipairs(tags) do
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("RIGHT", -5 - (5-i)*21, 0)
        txt:SetText(tag)
        f.indicators[tag] = txt
    end
    return f
end

local function UpdateGroupBuffs()
    if not mainFrame:IsShown() or inCombat or InCombatLockdown() then return end
    
    local units = GetUnitList()
    local req = {}
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        for sid, bclass in pairs(CLASS_BUFFS_IDS) do if class == bclass then req[sid] = true end end
    end
    
    for _, line in ipairs(playerLines) do line:Hide() end
    
    local displayIndex = 1
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local sFO, sFL, hOL, hR, hB = ScanUnitBuffsOptimized(unit, req)
            if not (sFO == 2 and sFL == 2 and hOL and hR and hB) then
                if not playerLines[displayIndex] then playerLines[displayIndex] = CreatePlayerLine(displayIndex) end
                local line = playerLines[displayIndex]
                line.name:SetText(UnitName(unit))
                ApplyColor(line.indicators["FO"], sFO)
                ApplyColor(line.indicators["FL"], sFL)
                ApplyColor(line.indicators["OL"], hOL)
                ApplyColor(line.indicators["R"], hR)
                ApplyColor(line.indicators["B"], hB)
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

-- --- CRONÓMETRO E EVENTOS ---
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    if inCombat or InCombatLockdown() then return end 
    lastUpdate = lastUpdate + elapsed
    if lastUpdate >= UPDATE_INTERVAL then lastUpdate = 0 UpdateGroupBuffs() end
end)

mainFrame:EnableMouseWheel(true)
mainFrame:SetScript("OnMouseWheel", function(self, delta)
    if BuffCheckDB.isLocked then return end
    BuffCheckDB.alpha = math.max(0.1, math.min(1, (BuffCheckDB.alpha or 0.5) + (delta * 0.05)))
    UpdateVisuals()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD"); events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE"); events:RegisterEvent("PLAYER_REGEN_DISABLED"); events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        UpdateVisuals(); UpdateLockIcon(); UpdateMinimapPosition()
        mainFrame:SetShown(BuffCheckDB.visible)
    elseif event == "PLAYER_REGEN_DISABLED" then inCombat = true; mainFrame:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false
        if BuffCheckDB.visible then mainFrame:Show(); UpdateGroupBuffs() end
    else UpdateGroupBuffs() end
end)

-- --- ÍCONE DO MINIMAPA ---
local miniButton = CreateFrame("Button", "BuffCheckByFerociousMinimap", Minimap)
miniButton:SetSize(31, 31); miniButton:SetFrameLevel(10)
miniButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local icon = miniButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
local border = miniButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(52, 52); border:SetPoint("TOPLEFT")

function UpdateMinimapPosition()
    local angle = math.rad(BuffCheckDB.minimapPos or 45)
    miniButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 102, math.sin(angle) * 102)
end

miniButton:RegisterForDrag("LeftButton")
miniButton:SetScript("OnDragStart", function(self) self:LockHighlight(); self:SetScript("OnUpdate", function()
    local cx, cy = Minimap:GetCenter(); local ux, uy = GetCursorPosition(); local scale = Minimap:GetEffectiveScale()
    BuffCheckDB.minimapPos = math.deg(math.atan2((uy/scale)-cy, (ux/scale)-cx)); UpdateMinimapPosition()
end) end)
miniButton:SetScript("OnDragStop", function(self) self:UnlockHighlight(); self:SetScript("OnUpdate", nil) end)
miniButton:SetScript("OnClick", function() BuffCheckDB.visible = not BuffCheckDB.visible; mainFrame:SetShown(BuffCheckDB.visible) end)

-- --- COMANDOS DE DEPURAÇÃO ---
SLASH_BUFFCHECK1 = "/buffcheck"
SlashCmdList["BUFFCHECK"] = function(msg)
    if msg == "debug" then
        print("|cFFFFFF00--- BuffCheck Depuração Extrema ---|r")
        local found = false
        for j = 1, 100 do
            local data = C_UnitAuras.GetAuraDataByIndex("player", j, "HELPFUL")
            if data then 
                print(string.format("Aura: |cFF00FF00ID: %d|r | Nome: %s", data.spellId, data.name))
                found = true
            end
        end
        if not found then print("Nenhuma aura encontrada.") end
        local hasMain, _, _, mainID = GetWeaponEnchantInfo()
        if hasMain then print(string.format("Arma Principal: |cFF00FFFFEnchantID: %d|r", mainID)) end
        print("|cFFFFFF00-------------------------------|r")
    else 
        BuffCheckDB.visible = not BuffCheckDB.visible; mainFrame:SetShown(BuffCheckDB.visible) 
    end
end