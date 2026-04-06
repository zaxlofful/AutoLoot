-------------------------------------------------------------------------------
-- EbonholdAutoLoot  v1.3
--
-- Automatically loots using the Greedy Scavenger companion pet, then switches
-- to the Goblin Merchant companion to sell unwanted items when bags are full.
--
-- In-combat selling:
--   CallCompanion / InteractUnit are protected functions and cannot be called
--   by addon scripts during combat lockdown.  The addon summons the Goblin
--   Merchant automatically; the player then clicks the "Open Vendor" button
--   (SecureActionButtonTemplate — counts as a hardware event) to open the
--   vendor window in combat.  Auto-sell fires the moment MERCHANT_SHOW fires.
--   Use /eal macro to create a matching action-bar macro.
--
-- GUI Features:
--   - Enable / Disable the full loot+sell cycle
--   - "Open Vendor" secure button (works in combat) + "Create Macro" helper
--   - Per-quality sell toggles: Grey / White / Uncommon / Rare / Epic
--   - Item blacklist: named items are never sold regardless of quality
--   - Live status display with free-slot counter
--
-- Slash commands:  /eal   /autoloot   /eal macro
-------------------------------------------------------------------------------

local ADDON_NAME      = "EbonholdAutoLoot"
local LOOT_PET_NAME   = "Greedy Scavenger"
local VENDOR_PET_NAME = "Goblin Merchant"

-- Item quality constants (matches GetItemInfo quality return)
local Q_GREY     = 0
local Q_WHITE    = 1
local Q_UNCOMMON = 2
local Q_RARE     = 3
local Q_EPIC     = 4

local QUALITY_LABEL = { [0]="Grey", [1]="White", [2]="Uncommon", [3]="Rare", [4]="Epic" }
local QUALITY_HEX   = { [0]="9d9d9d", [1]="ffffff", [2]="1eff00", [3]="0070dd", [4]="a335ee" }

-- State machine values
local S_IDLE    = "IDLE"
local S_LOOTING = "LOOTING"
local S_SELLING = "SELLING"

-- Companion stuck detection
local MAX_COMPANION_DISTANCE = 5   -- yards; resummon if pet exceeds this from player

-- Macro that players can place on their action bar for quick in-combat targeting.
-- InteractUnit is Blizzard-UI-only and cannot be called from any macro or addon
-- script.  This macro targets the NPC; the player then opens the vendor by
-- right-clicking the NPC model OR pressing their "Interact with Target" keybind
-- (Key Bindings > Targeting > Interact With Target).
local VENDOR_MACRO_NAME = "EBVendor"
local VENDOR_MACRO_BODY = "/targetexact " .. VENDOR_PET_NAME

-- SavedVariables schema / defaults
local DEFAULTS = {
    enabled       = false,
    sellGrey      = true,
    sellWhite     = false,
    sellUncommon  = false,
    sellRare      = false,
    sellEpic      = false,
    blacklist     = {},
    checkInterval = 3,     -- seconds between free-slot checks while looting
    windowX       = 100,
    windowY       = -200,
}

-------------------------------------------------------------------------------
-- Runtime state
-------------------------------------------------------------------------------
local EAL_DB             -- assigned from SavedVariables on ADDON_LOADED
local currentState       = S_IDLE
local bagCheckTimer      = 0
local waitingForMerchant = false

-- GUI handles populated by EAL_BuildGUI
local g_statusLabel
local g_enableBtn
local g_blacklistRows = {}
local g_scrollFrame
local ROW_HEIGHT      = 22
local MAX_ROWS        = 8

-------------------------------------------------------------------------------
-- 1. TIMER HELPER  (C_Timer does not exist in 3.3.5a)
-------------------------------------------------------------------------------
local pendingTimers = {}

local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    for i = #pendingTimers, 1, -1 do
        local t = pendingTimers[i]
        t.remaining = t.remaining - elapsed
        if t.remaining <= 0 then
            table.remove(pendingTimers, i)
            t.fn()
        end
    end
end)

local function After(delay, fn)
    table.insert(pendingTimers, { remaining = delay, fn = fn })
end

-------------------------------------------------------------------------------
-- 2. UTILITY
-------------------------------------------------------------------------------

local function Print(msg, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff9900[AutoLoot]|r " .. tostring(msg), r or 1, g or 0.8, b or 0)
end

local function GetTotalFreeSlots()
    local free = 0
    for bag = 0, 4 do
        local f = GetContainerNumFreeSlots(bag)
        if f then free = free + f end
    end
    return free
end

local function IsBlacklisted(itemName)
    if not itemName then return false end
    local lower = itemName:lower()
    for _, entry in ipairs(EAL_DB.blacklist) do
        if entry:lower() == lower then return true end
    end
    return false
end

-- Returns companion index (1-based) and whether it is currently summoned.
-- Comparison is case-insensitive so "Greedy scavenger" matches "Greedy Scavenger".
local function FindCompanion(name)
    local n = GetNumCompanions("CRITTER")
    local nameLower = name:lower()
    for i = 1, n do
        local _, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
        if cName and cName:lower() == nameLower then
            return i, (summoned == 1 or summoned == true)
        end
    end
    return nil, false
end

local function SummonPet(name)
    local idx, active = FindCompanion(name)
    if not idx then
        Print("Companion '" .. name .. "' not found in your companion list.", 1, 0.3, 0.3)
        return false
    end
    if not active then
        CallCompanion("CRITTER", idx)
        Print("Summoning " .. name .. "...")
    end
    return true
end

local function DismissPet()
    DismissCompanion("CRITTER")
end

-- Returns true when the player should not be disturbed by a resummon
-- (airborne or on a ground/flying mount).  Both functions are guarded in
-- case a particular emulator build doesn't expose them.
local function IsPlayerMountedOrFlying()
    if IsFlying  and IsFlying()  then return true end
    if IsMounted and IsMounted() then return true end
    return false
end

-- Returns the 2-D distance in yards between the player and the summoned
-- companion critter.  Companion critters occupy the "pet" unit token when
-- the player has no active combat pet.  Returns nil if either position is
-- unavailable (unit doesn't exist, UnitPosition not supported, etc.).
local function GetCompanionDistance()
    local px, py = UnitPosition("player")
    local cx, cy = UnitPosition("pet")
    if not px or not cx then return nil end
    local dx, dy = px - cx, py - cy
    return math.sqrt(dx * dx + dy * dy)
end

-------------------------------------------------------------------------------
-- 3. VENDOR MACRO HELPER
--    Creates (or updates) an in-game macro the player can drag to their bar.
--    Clicking it from the action bar counts as a hardware event, so
--    InteractUnit fires even during combat lockdown.
-------------------------------------------------------------------------------
local function CreateVendorMacro()
    local idx = GetMacroIndexByName(VENDOR_MACRO_NAME)
    if idx and idx > 0 then
        EditMacro(idx, VENDOR_MACRO_NAME, nil, VENDOR_MACRO_BODY, nil)
        Print("|cffffff00" .. VENDOR_MACRO_NAME ..
              "|r macro updated. Drag it from your macro book to your action bar.")
    else
        -- Icon: use the gold coin bag icon (available in all WotLK clients)
        CreateMacro(VENDOR_MACRO_NAME, "INV_Misc_Bag_10_Green", VENDOR_MACRO_BODY, nil)
        Print("|cffffff00" .. VENDOR_MACRO_NAME ..
              "|r macro created! Open your macro book (/macro) and drag it to your action bar.")
    end
end

-------------------------------------------------------------------------------
-- 4. STATUS / GUI REFRESH
-------------------------------------------------------------------------------
local function EAL_UpdateStatus()
    if not g_statusLabel then return end

    local stateColor
    if     currentState == S_IDLE    then stateColor = "|cffaaaaaa"
    elseif currentState == S_LOOTING then stateColor = "|cff44ff44"
    elseif currentState == S_SELLING then stateColor = "|cffff9900"
    else                                  stateColor = "|cffaaaaaa"
    end

    local free      = GetTotalFreeSlots()
    local freeColor = (free == 0) and "|cffff4444" or (free <= 4 and "|cffff9900" or "|cffffff00")

    g_statusLabel:SetText(
        "Status: " .. stateColor .. currentState .. "|r" ..
        "   Free Slots: " .. freeColor .. free .. "|r"
    )

    if g_enableBtn then
        g_enableBtn:SetText(EAL_DB.enabled and "Disable" or "Enable")
    end
end

local function EAL_RefreshBlacklist()
    if not g_scrollFrame then return end
    local total  = #EAL_DB.blacklist
    FauxScrollFrame_Update(g_scrollFrame, total, MAX_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(g_scrollFrame)

    for i = 1, MAX_ROWS do
        local row = g_blacklistRows[i]
        local idx = offset + i
        if row then
            if idx <= total then
                local itemName = EAL_DB.blacklist[idx]
                row.label:SetText(itemName)
                local capturedIdx = idx
                row.removeBtn:SetScript("OnClick", function()
                    table.remove(EAL_DB.blacklist, capturedIdx)
                    EAL_RefreshBlacklist()
                end)
                row:Show()
            else
                row:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- 5. SELLING LOGIC
-------------------------------------------------------------------------------
local function SellItems()
    local sold    = 0
    local skipped = 0

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, quality = GetItemInfo(link)
                if quality and name then
                    local sell =
                        (quality == Q_GREY     and EAL_DB.sellGrey)     or
                        (quality == Q_WHITE    and EAL_DB.sellWhite)    or
                        (quality == Q_UNCOMMON and EAL_DB.sellUncommon) or
                        (quality == Q_RARE     and EAL_DB.sellRare)     or
                        (quality == Q_EPIC     and EAL_DB.sellEpic)

                    if sell and IsBlacklisted(name) then
                        sell    = false
                        skipped = skipped + 1
                    end

                    if sell then
                        UseContainerItem(bag, slot)
                        sold = sold + 1
                    end
                end
            end
        end
    end

    if sold > 0 or skipped > 0 then
        Print("Sold |cffffff00" .. sold ..
              "|r item(s). Blacklist protected: |cffffff00" .. skipped .. "|r.")
    else
        Print("Nothing to sell with current quality settings.")
    end

    return sold
end

-------------------------------------------------------------------------------
-- 6. STATE MACHINE
-------------------------------------------------------------------------------
local function SetState(state)
    currentState = state
    EAL_UpdateStatus()
end

local function StartLootCycle()
    if not EAL_DB or not EAL_DB.enabled then return end
    SetState(S_LOOTING)
    bagCheckTimer = 0
    Print("Loot cycle started. Summoning " .. LOOT_PET_NAME .. "...")
    SummonPet(LOOT_PET_NAME)
end

local function StartSellCycle()
    if currentState == S_SELLING then return end
    SetState(S_SELLING)
    Print("Bags full — summoning " .. VENDOR_PET_NAME .. "...")
    DismissPet()

    After(1.5, function()
        local ok = SummonPet(VENDOR_PET_NAME)
        if ok then
            waitingForMerchant = true
            -- If in combat, prompt the player to click the secure button / macro
            if InCombatLockdown() then
                Print("|cffffd700In combat:|r click |cffffff00Target Vendor|r to select the merchant," ..
                      " then |cffffd700right-click its model|r or press your" ..
                      " |cffffff00Interact with Target|r keybind to open the vendor.")
            end
            -- Remind after 8 seconds if window still hasn't opened
            After(8, function()
                if waitingForMerchant and currentState == S_SELLING then
                    Print("|cffffd700Reminder:|r target " .. VENDOR_PET_NAME ..
                          " then right-click it or press Interact with Target.", 1, 1, 0)
                end
            end)
        end
    end)
end

-- Called when any merchant window opens
local function OnMerchantShow()
    waitingForMerchant = false
    if currentState == S_SELLING or EAL_DB.enabled then
        After(0.3, function()
            SellItems()
            EAL_UpdateStatus()
        end)
    end
end

-- Called when merchant window closes
local function OnMerchantClosed()
    if currentState == S_SELLING then
        local free = GetTotalFreeSlots()
        if EAL_DB.enabled and free > 0 then
            After(1, StartLootCycle)
        else
            SetState(S_IDLE)
        end
    end
end

-- Dismisses and re-summons the Greedy Scavenger if it has drifted more than
-- MAX_COMPANION_DISTANCE yards from the player.  Skipped when the player is
-- mounted or flying so the pet isn't needlessly bounced during travel.
local function CheckCompanionStuck()
    if IsPlayerMountedOrFlying() then return end

    local dist = GetCompanionDistance()
    if dist == nil then return end   -- position data not available; skip silently

    if dist > MAX_COMPANION_DISTANCE then
        Print("Greedy Scavenger is stuck (" .. math.floor(dist) ..
              " yds away) — resummoning...", 1, 0.75, 0.2)
        DismissPet()
        After(0.5, function()
            SummonPet(LOOT_PET_NAME)
        end)
    end
end

-- Per-frame bag check + button pulse while looting / selling
local function OnUpdate(self, elapsed)
    if not EAL_DB then return end

    -- Bag check + companion stuck detection (share the same interval timer)
    if EAL_DB.enabled and currentState == S_LOOTING then
        bagCheckTimer = bagCheckTimer + elapsed
        if bagCheckTimer >= (EAL_DB.checkInterval or 3) then
            bagCheckTimer = 0
            if GetTotalFreeSlots() == 0 then
                StartSellCycle()
            else
                -- Only run stuck check when we're not already switching to sell;
                -- avoids a dismiss colliding with the sell-cycle dismiss.
                CheckCompanionStuck()
            end
        end
    end

end

-------------------------------------------------------------------------------
-- 7. GUI
-------------------------------------------------------------------------------
local function MakeHeader(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText("|cffffd700" .. text .. "|r")
    return fs
end

local function MakeDivider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 14, y)
    t:SetWidth(312); t:SetHeight(1)
    t:SetTexture(0.45, 0.35, 0.15, 0.9)
    return t
end

local function MakeCheckbox(parent, labelText, x, y, getValue, setValue)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetWidth(24); cb:SetHeight(24)
    cb:SetChecked(getValue())

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    lbl:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked() and true or false)
    end)
    return cb
end

local function EAL_BuildGUI()
    -- ----------------------------------------------------------------
    -- Main window  (550 tall to accommodate the extra vendor row)
    -- ----------------------------------------------------------------
    local win = CreateFrame("Frame", "EAL_Window", UIParent)
    win:SetWidth(340); win:SetHeight(510)
    win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", EAL_DB.windowX, EAL_DB.windowY)
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        EAL_DB.windowX = self:GetLeft()
        EAL_DB.windowY = self:GetTop() - UIParent:GetHeight()
    end)
    win:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    win:Hide()

    -- Title bar
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffff9900Ebonhold|r AutoLoot  |cffaaaaaa& Sell|r")

    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        if not InCombatLockdown() then win:Hide() end
    end)

    -- ----------------------------------------------------------------
    -- Status row
    -- ----------------------------------------------------------------
    MakeDivider(win, -36)
    local statusLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", 18, -48)
    statusLabel:SetWidth(300)
    statusLabel:SetJustifyH("LEFT")
    g_statusLabel = statusLabel

    -- ----------------------------------------------------------------
    -- Row 1: Enable / Disable  +  Force Sell
    -- ----------------------------------------------------------------
    MakeDivider(win, -66)

    local enableBtn = CreateFrame("Button", nil, win, "GameMenuButtonTemplate")
    enableBtn:SetPoint("TOPLEFT", 18, -80)
    enableBtn:SetWidth(140); enableBtn:SetHeight(26)
    enableBtn:SetText(EAL_DB.enabled and "Disable" or "Enable")
    g_enableBtn = enableBtn
    enableBtn:SetScript("OnClick", function(self)
        EAL_DB.enabled = not EAL_DB.enabled
        if EAL_DB.enabled then
            StartLootCycle()
        else
            DismissPet()
            SetState(S_IDLE)
        end
        EAL_UpdateStatus()
    end)

    local sellNowBtn = CreateFrame("Button", nil, win, "GameMenuButtonTemplate")
    sellNowBtn:SetPoint("TOPLEFT", 176, -80)
    sellNowBtn:SetWidth(146); sellNowBtn:SetHeight(26)
    sellNowBtn:SetText("Force Sell Now")
    sellNowBtn:SetScript("OnClick", function() StartSellCycle() end)

    -- ----------------------------------------------------------------
    -- Row 2: In-combat vendor — macro button + instruction text
    -- SecureActionButtonTemplate cannot be parented to a regular addon
    -- frame; doing so blocks Show/Hide on the parent window.  The correct
    -- in-combat approach is an action-bar macro (hardware event on click).
    -- ----------------------------------------------------------------
    MakeDivider(win, -114)
    MakeHeader(win, "IN-COMBAT VENDOR", 18, -124)

    local macroBtn = CreateFrame("Button", nil, win, "GameMenuButtonTemplate")
    macroBtn:SetPoint("TOPLEFT", 18, -140)
    macroBtn:SetWidth(140); macroBtn:SetHeight(26)
    macroBtn:SetText("Create Macro")
    macroBtn:SetScript("OnClick", function() CreateVendorMacro() end)
    macroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffd700Create |cffffff00" .. VENDOR_MACRO_NAME .. "|cffffd700 Macro|r", 1, 1, 1)
        GameTooltip:AddLine("Writes a /targetexact macro to your macro book.", 1, 1, 1)
        GameTooltip:AddLine("Drag it to your action bar, then:", 1, 1, 1)
        GameTooltip:AddLine("1. Click macro to target the vendor.", 1, 1, 1)
        GameTooltip:AddLine("2. Right-click NPC  OR  press Interact with Target keybind.", 1, 1, 1)
        GameTooltip:AddLine("|cffaaaaaa(Key Bindings > Targeting > Interact With Target)|r", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    macroBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local vendorHint = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vendorHint:SetPoint("TOPLEFT", 166, -146)
    vendorHint:SetWidth(156)
    vendorHint:SetJustifyH("LEFT")
    vendorHint:SetText("|cffaaaaaarTarget vendor → right-click or\nInteract With Target keybind|r")

    -- ----------------------------------------------------------------
    -- Quality sell toggles
    -- ----------------------------------------------------------------
    MakeDivider(win, -172)
    MakeHeader(win, "SELL QUALITY", 18, -182)

    local qualityDefs = {
        { Q_GREY,     "sellGrey",      18,  -202 },
        { Q_WHITE,    "sellWhite",    110,  -202 },
        { Q_UNCOMMON, "sellUncommon", 210,  -202 },
        { Q_RARE,     "sellRare",      18,  -226 },
        { Q_EPIC,     "sellEpic",     110,  -226 },
    }

    for _, def in ipairs(qualityDefs) do
        local qIdx, dbKey, cx, cy = def[1], def[2], def[3], def[4]
        local label = "|cff" .. QUALITY_HEX[qIdx] .. QUALITY_LABEL[qIdx] .. "|r"
        MakeCheckbox(win, label, cx, cy,
            function() return EAL_DB[dbKey] end,
            function(v) EAL_DB[dbKey] = v end)
    end

    -- ----------------------------------------------------------------
    -- Blacklist section
    -- ----------------------------------------------------------------
    MakeDivider(win, -252)
    MakeHeader(win, "ITEM BLACKLIST  (these items are never sold)", 18, -262)

    local inputBox = CreateFrame("EditBox", "EAL_BlacklistInput", win, "InputBoxTemplate")
    inputBox:SetPoint("TOPLEFT", 18, -284)
    inputBox:SetWidth(224); inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(64)

    local function AddBlacklistEntry()
        local text = inputBox:GetText():match("^%s*(.-)%s*$")
        if text == "" then return end
        for _, v in ipairs(EAL_DB.blacklist) do
            if v:lower() == text:lower() then
                inputBox:SetText("")
                return
            end
        end
        table.insert(EAL_DB.blacklist, text)
        inputBox:SetText("")
        EAL_RefreshBlacklist()
    end

    inputBox:SetScript("OnEnterPressed", function(self)
        AddBlacklistEntry()
        self:ClearFocus()
    end)

    local addBtn = CreateFrame("Button", nil, win, "GameMenuButtonTemplate")
    addBtn:SetPoint("TOPLEFT", 250, -282)
    addBtn:SetWidth(72); addBtn:SetHeight(22)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", AddBlacklistEntry)

    -- ----------------------------------------------------------------
    -- Scrollable blacklist
    -- ----------------------------------------------------------------
    local listBg = CreateFrame("Frame", nil, win)
    listBg:SetPoint("TOPLEFT", 14, -310)
    listBg:SetWidth(312); listBg:SetHeight(MAX_ROWS * ROW_HEIGHT + 8)
    listBg:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    listBg:SetBackdropColor(0, 0, 0, 0.85)

    local scrollFrame = CreateFrame("ScrollFrame", "EAL_ScrollFrame", listBg,
        "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetWidth(292); scrollFrame:SetHeight(MAX_ROWS * ROW_HEIGHT)
    g_scrollFrame = scrollFrame

    local listContainer = CreateFrame("Frame", nil, scrollFrame)
    listContainer:SetWidth(292); listContainer:SetHeight(MAX_ROWS * ROW_HEIGHT)
    scrollFrame:SetScrollChild(listContainer)

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, listContainer)
        row:SetWidth(292); row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetTexture(0.12, 0.12, 0.12, 0.6)
        else
            rowBg:SetTexture(0.06, 0.06, 0.06, 0.6)
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", 6, 0)
        lbl:SetWidth(224)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetPoint("RIGHT", -4, 0)
        removeBtn:SetWidth(54); removeBtn:SetHeight(18)
        removeBtn:SetText("Remove")
        removeBtn:GetNormalFontObject():SetTextColor(1, 0.4, 0.4)

        row.label     = lbl
        row.removeBtn = removeBtn
        row:Hide()
        g_blacklistRows[i] = row
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, EAL_RefreshBlacklist)
    end)

    -- ----------------------------------------------------------------
    -- Bottom hint
    -- ----------------------------------------------------------------
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", 0, 14)
    hint:SetText("|cffaaaaaa/eal — toggle  |  /eal macro — create bar macro  |  then right-click vendor|r")

    EAL_UpdateStatus()
    EAL_RefreshBlacklist()

    return win
end

-------------------------------------------------------------------------------
-- 8. EVENT FRAME
-------------------------------------------------------------------------------
local gui

local eventFrame = CreateFrame("Frame", "EAL_EventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            EAL_SavedDB = EAL_SavedDB or {}
            EAL_DB = EAL_SavedDB
            for k, v in pairs(DEFAULTS) do
                if EAL_DB[k] == nil then
                    EAL_DB[k] = (type(v) == "table") and {} or v
                end
            end
        end

    elseif event == "PLAYER_LOGIN" then
        if not EAL_DB then
            EAL_SavedDB = EAL_SavedDB or {}
            EAL_DB = EAL_SavedDB
            for k, v in pairs(DEFAULTS) do
                if EAL_DB[k] == nil then
                    EAL_DB[k] = (type(v) == "table") and {} or v
                end
            end
        end
        gui = EAL_BuildGUI()
        Print("v1.3 loaded.  |cffffff00/eal|r to open  |  |cffffff00/eal macro|r to create action-bar macro.")

    elseif event == "MERCHANT_SHOW" then
        OnMerchantShow()

    elseif event == "MERCHANT_CLOSED" then
        OnMerchantClosed()
    end
end)

eventFrame:SetScript("OnUpdate", OnUpdate)

-------------------------------------------------------------------------------
-- 9. SLASH COMMANDS
-------------------------------------------------------------------------------
SLASH_EBAUTOLOOT1 = "/eal"
SLASH_EBAUTOLOOT2 = "/autoloot"

SlashCmdList["EBAUTOLOOT"] = function(msg)
    if not gui then
        Print("GUI not ready yet.", 1, 0.5, 0.5)
        return
    end

    local cmd = msg and msg:lower():match("^%s*(%S*)") or ""

    if cmd == "macro" then
        CreateVendorMacro()
    elseif cmd == "reset" then
        EAL_DB.blacklist = {}
        EAL_RefreshBlacklist()
        Print("Blacklist cleared.")
    elseif cmd == "enable" then
        EAL_DB.enabled = true
        StartLootCycle()
        EAL_UpdateStatus()
    elseif cmd == "disable" then
        EAL_DB.enabled = false
        DismissPet()
        SetState(S_IDLE)
    else
        if InCombatLockdown() then
            Print("Cannot open the settings window during combat.", 1, 0.5, 0.5)
            return
        end
        if gui:IsShown() then
            gui:Hide()
        else
            EAL_UpdateStatus()
            EAL_RefreshBlacklist()
            gui:Show()
        end
    end
end
