-- PomPom: Prayer of Mending tracker (self-cast only).
-- Layout: icon (left) with bounce-count badge, target name (top-right),
-- gold 30s duration bar and blue 10s recast cooldown bar (stacked below name).

local POM_SPELL_ID   = 33076
local POM_SPELL_NAME = GetSpellInfo(POM_SPELL_ID) or "Prayer of Mending"
local POM_ICON       = "Interface\\Icons\\Spell_Holy_PrayerofMending"
local POM_MAX        = 5
local POM_DURATION   = 30
local POM_COOLDOWN   = 10
local IDLE_GRACE     = 0.3 -- seconds to wait after AURA_REMOVED before declaring idle (lets bounces land)

PomPomDB = PomPomDB or {}
local defaults = {
    point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
    scale = 1.0,
    locked = true,
    bgAlpha = 0.85,
    sound = true,
    soundIndex = 1,
    fadeOOC = true,
}

-- Sound presets: id is either a file/fileID (PlaySoundFile) or a SOUNDKIT number (PlaySound)
local SOUND_PRESETS = {
    { name = "Beep 1", id = "Interface\\AddOns\\PomPom\\sounds\\beep1.ogg", kit = false },
    { name = "Beep 2", id = "Interface\\AddOns\\PomPom\\sounds\\beep2.ogg", kit = false },
    { name = "Beep 3", id = "Interface\\AddOns\\PomPom\\sounds\\beep3.ogg", kit = false },
    { name = "Beep 4", id = "Interface\\AddOns\\PomPom\\sounds\\beep4.ogg", kit = false },
}

local function PlayPomSound(idx)
    local s = SOUND_PRESETS[idx or (PomPomDB and PomPomDB.soundIndex) or 1]
    if not s then return end
    if s.kit then
        PlaySound(s.id, "Master")
    else
        PlaySoundFile(s.id, "Master")
    end
end

local function DB()
    for k, v in pairs(defaults) do
        if PomPomDB[k] == nil then PomPomDB[k] = v end
    end
    return PomPomDB
end

local state = {
    active     = false,
    targetName = nil,
    charges    = 0,
    bounceEnd  = 0,
    idleAt     = 0,
}

local main, iconTex, iconGlow, iconGlow2, countBg, countText, nameText, durationBar, cdBar, dragHandle
local config, configLock, configScale, configBgAlpha, configSound, configSoundPick, configSoundTest, configFadeOOC, availabilityLabel
local wasCdReady = true -- edge-trigger for the recast-ready sound
local pomAvailable = false
local availabilityReason = nil
local inCombat = false
local mainCreated = false
local UpdateLockVisuals, ApplyBgAlpha, ApplyConfigAvailability, ApplyFadeState, UpdateAvailability

-- ── Helpers ──────────────────────────────────────────────────────────

local function StripRealm(name)
    if not name then return nil end
    local base = strsplit("-", name)
    return base
end

local function IsMe(guid)
    return guid == UnitGUID("player")
end

local function ClassColorFor(name)
    if not name or not RAID_CLASS_COLORS then return nil end
    local short = StripRealm(name)

    if UnitName("player") == short then
        local _, cls = UnitClass("player")
        return RAID_CLASS_COLORS[cls]
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == short then
            local _, cls = UnitClass(u)
            return RAID_CLASS_COLORS[cls]
        end
    end
    for i = 1, 40 do
        local u = "raid" .. i
        if UnitExists(u) and UnitName(u) == short then
            local _, cls = UnitClass(u)
            return RAID_CLASS_COLORS[cls]
        end
    end
    return nil
end

local function ResolveIcon()
    local t = GetSpellTexture and GetSpellTexture(POM_SPELL_ID)
    if t and t ~= "" then return t end
    return POM_ICON
end

-- ── Visual state ─────────────────────────────────────────────────────

local function ApplyActiveVisual()
    iconTex:SetDesaturated(false)
    iconTex:SetAlpha(1.0)
    countText:SetText(tostring(state.charges))
    countBg:Show()

    local short = StripRealm(state.targetName) or ""
    nameText:SetText(short)
    local c = ClassColorFor(state.targetName)
    if c then
        nameText:SetTextColor(c.r, c.g, c.b, 1)
    else
        nameText:SetTextColor(1, 1, 1, 1)
    end
end

local function ApplyIdleVisual()
    iconTex:SetDesaturated(true)
    iconTex:SetAlpha(0.55)
    countBg:Hide()
    nameText:SetText("No target")
    nameText:SetTextColor(0.72, 0.70, 0.64, 1)
end

local function GoActive(target, charges)
    state.active     = true
    state.targetName = target
    state.charges    = charges or POM_MAX
    state.bounceEnd  = GetTime() + POM_DURATION
    state.idleAt     = 0
    ApplyActiveVisual()
end

local function GoIdle()
    state.active     = false
    state.targetName = nil
    state.charges    = 0
    state.bounceEnd  = 0
    state.idleAt     = 0
    ApplyIdleVisual()
    if iconGlow then iconGlow:Hide() end
    if iconGlow2 then iconGlow2:Hide() end
end

-- ── Availability + combat fade ──────────────────────────────────

local function IsShadowSpec()
    if GetSpecialization then
        local s = GetSpecialization()
        if s then return s == 3 end
    end
    if GetTalentTabInfo then
        local group = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
        local ok1, _, _, disc = pcall(GetTalentTabInfo, 1, false, false, group)
        local ok2, _, _, holy = pcall(GetTalentTabInfo, 2, false, false, group)
        local ok3, _, _, shadow = pcall(GetTalentTabInfo, 3, false, false, group)
        if not ok3 or not shadow then return false end
        return shadow > (disc or 0) and shadow > (holy or 0)
    end
    return false
end

local function CheckAvailability()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then
        return false, "PomPom is priest-only."
    end
    local known = (IsPlayerSpell and IsPlayerSpell(POM_SPELL_ID))
        or (IsSpellKnown and IsSpellKnown(POM_SPELL_ID))
    if not known then
        return false, "Prayer of Mending is not in your spellbook."
    end
    if IsShadowSpec() then
        return false, "Shadow spec doesn't need Prayer of Mending tracking."
    end
    return true
end

function ApplyFadeState()
    if not main or not pomAvailable then return end
    local d = DB()
    local shouldFadeOut = d.fadeOOC and not inCombat
    local target = shouldFadeOut and 0.25 or 1.0
    local current = main:GetAlpha() or 1.0
    if math.abs(current - target) < 0.01 then return end
    if target < current then
        UIFrameFadeOut(main, 0.4, current, target)
    else
        UIFrameFadeIn(main, 0.4, current, target)
    end
end

function ApplyConfigAvailability()
    if not config then return end
    local enabled = pomAvailable

    local checks = { configLock, configSound, configFadeOOC }
    for _, cb in ipairs(checks) do
        if cb then
            if enabled then cb:Enable() else cb:Disable() end
        end
    end
    if configScale then
        if enabled then configScale:Enable() else configScale:Disable() end
    end
    if configBgAlpha then
        if enabled then configBgAlpha:Enable() else configBgAlpha:Disable() end
    end
    if configSoundPick then
        if enabled and DB().sound then
            UIDropDownMenu_EnableDropDown(configSoundPick)
        else
            UIDropDownMenu_DisableDropDown(configSoundPick)
        end
    end
    if configSoundTest then
        if enabled and DB().sound then
            configSoundTest:Enable()
        else
            configSoundTest:Disable()
        end
    end
    if availabilityLabel then
        if enabled then
            availabilityLabel:SetText("")
            availabilityLabel:Hide()
        else
            availabilityLabel:SetText(availabilityReason or "")
            availabilityLabel:Show()
        end
    end
end

-- ── Combat log ───────────────────────────────────────────────────────

local function HandleCombatLog()
    local _, event, _, srcGUID, _, _, _,
          _, dstName, _, _,
          spellID, spellName = CombatLogGetCurrentEventInfo()
    local rest = { select(15, CombatLogGetCurrentEventInfo()) }

    if not IsMe(srcGUID) then return end
    if spellID ~= POM_SPELL_ID and spellName ~= POM_SPELL_NAME then return end

    if event == "SPELL_AURA_APPLIED" then
        -- Don't trust rest[2] on APPLIED here — some Classic clients report a
        -- wrong value (the max stack, not the current). Infer purely from state:
        -- if we were already tracking and the target changed, it's a bounce.
        if state.active and dstName ~= state.targetName then
            GoActive(dstName, math.max(1, state.charges - 1))
        else
            GoActive(dstName, POM_MAX)
        end
    elseif event == "SPELL_AURA_APPLIED_DOSE" then
        -- rest = { auraType, amount }
        local amount = rest[2] or state.charges
        GoActive(dstName, amount)
    elseif event == "SPELL_AURA_REFRESH" then
        GoActive(dstName, POM_MAX)
    elseif event == "SPELL_AURA_REMOVED" then
        if state.active and dstName == state.targetName then
            state.idleAt = GetTime() + IDLE_GRACE
        end
    end
end

-- ── Update loop ──────────────────────────────────────────────────────

local throttle = 0
local function OnUpdate(self, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.05 then return end
    throttle = 0

    local now = GetTime()

    -- Idle grace
    if state.idleAt > 0 and now >= state.idleAt then
        GoIdle()
    end
    -- Duration expiry
    if state.active and now >= state.bounceEnd then
        GoIdle()
    end

    -- Duration bar
    if state.active then
        local remain = math.max(0, state.bounceEnd - now)
        durationBar:SetValue(remain / POM_DURATION)
    else
        durationBar:SetValue(0)
    end

    -- Cooldown bar (from actual spell CD)
    local start, duration = GetSpellCooldown(POM_SPELL_ID)
    local cdReady = true
    if start and duration and duration > 1.5 then
        local remain = math.max(0, (start + duration) - now)
        cdBar:SetValue(remain / POM_COOLDOWN)
        if remain > 0 then cdReady = false end
    else
        cdBar:SetValue(0)
    end

    -- Pulse the icon glow whenever recast is available but PoM is still bouncing.
    if state.active and cdReady then
        if not iconGlow:IsShown() then
            iconGlow:Show()
            iconGlow2:Show()
        end
        local pulse = 0.55 + 0.45 * math.sin(now * 8) -- fast pulse, alpha 0.10-1.00
        iconGlow:SetAlpha(pulse)
        iconGlow2:SetAlpha(pulse * 0.55)
    elseif iconGlow:IsShown() then
        iconGlow:Hide()
        iconGlow2:Hide()
    end

    -- Edge-trigger: recast just became available while PoM is still active.
    -- Only beep in combat — an OOC ready-cue would be noise between fights.
    if state.active and cdReady and not wasCdReady and inCombat then
        if DB().sound then PlayPomSound() end
    end
    wasCdReady = cdReady
end

-- ── Main frame ───────────────────────────────────────────────────────

local function CreateMainFrame()
    local db = DB()

    main = CreateFrame("Frame", "PomPomMain", UIParent, "BackdropTemplate")
    main:SetSize(240, 54)
    main:ClearAllPoints()
    main:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    main:SetScale(db.scale)
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    main:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    main:SetBackdropColor(0.06, 0.05, 0.08, db.bgAlpha or 0.85)
    main:SetBackdropBorderColor(0, 0, 0, 0.9)

    main:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not DB().locked then
            self:StartMoving()
        end
    end)
    main:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        local d = DB()
        d.point, d.relPoint, d.x, d.y = p, rp, x, y
    end)
    main:SetScript("OnUpdate", OnUpdate)

    -- Icon container
    local iconSize = 44
    local iconFrame = CreateFrame("Frame", nil, main, "BackdropTemplate")
    iconFrame:SetSize(iconSize, iconSize)
    iconFrame:SetPoint("LEFT", main, "LEFT", 7, 0)
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    iconFrame:SetBackdropBorderColor(0, 0, 0, 0.85)

    iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetTexture(ResolveIcon())
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)

    -- Bounce count badge (black backdrop + text, drawn above glow via frame level)
    countBg = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    countBg:SetSize(22, 20)
    countBg:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 4, -3)
    countBg:SetFrameLevel(iconFrame:GetFrameLevel() + 8)
    countBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    countBg:SetBackdropColor(0, 0, 0, 0.88)
    countBg:SetBackdropBorderColor(0, 0, 0, 0.95)
    countBg:Hide()

    countText = countBg:CreateFontString(nil, "OVERLAY")
    countText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    countText:SetTextColor(1, 0.82, 0, 1)
    countText:SetPoint("CENTER", countBg, "CENTER", 0, -1)

    -- Pulsing glow: two additive layers — an outer soft halo and an inner brightener.
    iconGlow = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    iconGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    iconGlow:SetBlendMode("ADD")
    iconGlow:SetVertexColor(1, 0.85, 0.30, 1)
    iconGlow:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -16, 16)
    iconGlow:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 16, -16)
    iconGlow:Hide()

    iconGlow2 = iconFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    iconGlow2:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconGlow2:SetBlendMode("ADD")
    iconGlow2:SetVertexColor(1, 0.68, 0.15, 1)
    iconGlow2:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -4, 4)
    iconGlow2:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 4, -4)
    iconGlow2:Hide()

    -- Target name (upper-right of icon)
    nameText = main:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    nameText:SetJustifyH("LEFT")
    nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 9, -1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)

    -- Cooldown bar (top, blue) — the shorter timer
    cdBar = CreateFrame("StatusBar", nil, main, "BackdropTemplate")
    cdBar:SetSize(170, 7)
    cdBar:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
    cdBar:SetMinMaxValues(0, 1)
    cdBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    cdBar:SetStatusBarColor(0.31, 0.58, 0.96, 1)
    cdBar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    cdBar:SetBackdropColor(0, 0, 0, 0.6)
    cdBar:SetBackdropBorderColor(0, 0, 0, 0.9)

    -- Duration bar (bottom, gold) — the longer timer
    durationBar = CreateFrame("StatusBar", nil, main, "BackdropTemplate")
    durationBar:SetSize(170, 7)
    durationBar:SetPoint("TOPLEFT", cdBar, "BOTTOMLEFT", 0, -3)
    durationBar:SetMinMaxValues(0, 1)
    durationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    durationBar:SetStatusBarColor(0.95, 0.76, 0.29, 1)
    durationBar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    durationBar:SetBackdropColor(0, 0, 0, 0.6)
    durationBar:SetBackdropBorderColor(0, 0, 0, 0.9)

    -- Drag handle (shown when unlocked)
    dragHandle = main:CreateTexture(nil, "OVERLAY")
    dragHandle:SetTexture("Interface\\Buttons\\WHITE8X8")
    dragHandle:SetVertexColor(1, 0.84, 0, 0.75)
    dragHandle:SetSize(4, 30)
    dragHandle:SetPoint("RIGHT", main, "LEFT", -4, 0)
    dragHandle:Hide()

    ApplyIdleVisual()
end

-- ── Config frame ─────────────────────────────────────────────────────

function ApplyBgAlpha()
    if not main then return end
    main:SetBackdropColor(0.06, 0.05, 0.08, DB().bgAlpha or 0.85)
end

function UpdateLockVisuals()
    if DB().locked then
        dragHandle:Hide()
        main:SetBackdropBorderColor(0, 0, 0, 0.9)
        main:EnableMouse(false)
    else
        dragHandle:Show()
        main:SetBackdropBorderColor(1, 0.84, 0, 0.75)
        main:EnableMouse(true)
    end
end

local function CreateConfigFrame()
    config = CreateFrame("Frame", "PomPomConfig", UIParent, "BackdropTemplate")
    config:SetSize(292, 296)
    config:SetPoint("CENTER")
    config:SetFrameStrata("DIALOG")
    config:SetMovable(true)
    config:EnableMouse(true)
    config:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    config:SetBackdropColor(0.09, 0.09, 0.10, 0.70)
    config:SetBackdropBorderColor(0.02, 0.02, 0.02, 0.95)
    config:Hide()

    config:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    config:SetScript("OnMouseUp",   function(self) self:StopMovingOrSizing() end)

    -- Title: bold gold "PomPom" + small-caps subtitle sharing the baseline
    local title = config:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetPoint("TOPLEFT", config, "TOPLEFT", 14, -14)
    title:SetText("PomPom")

    local subtitle = config:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    subtitle:SetTextColor(0.72, 0.68, 0.60, 1)
    subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
    subtitle:SetText("PRAYER OF MENDING TRACKER")

    -- Hairline divider under the title
    local rule = config:CreateTexture(nil, "OVERLAY")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(1, 0.82, 0, 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    rule:SetPoint("RIGHT", subtitle, "RIGHT", 0, 0)

    local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", config, "TOPRIGHT", -3, -3)

    -- Lock checkbox
    configLock = CreateFrame("CheckButton", "PomPomConfigLock", config, "UICheckButtonTemplate")
    configLock:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    _G[configLock:GetName() .. "Text"]:SetText("Lock frame")
    configLock:SetScript("OnClick", function(self)
        DB().locked = self:GetChecked() and true or false
        UpdateLockVisuals()
    end)

    local function ApplySoundEnabledUI()
        if not configSoundPick then return end
        -- When PoM isn't available, availability owns the disable — don't fight it.
        if not pomAvailable then
            UIDropDownMenu_DisableDropDown(configSoundPick)
            if configSoundTest then configSoundTest:Disable() end
            return
        end
        if DB().sound then
            UIDropDownMenu_EnableDropDown(configSoundPick)
            configSoundTest:Enable()
        else
            UIDropDownMenu_DisableDropDown(configSoundPick)
            configSoundTest:Disable()
        end
    end

    -- Enable sounds checkbox
    configSound = CreateFrame("CheckButton", "PomPomConfigSound", config, "UICheckButtonTemplate")
    configSound:SetPoint("TOPLEFT", configLock, "BOTTOMLEFT", 0, -6)
    _G[configSound:GetName() .. "Text"]:SetText("Enable sounds")
    configSound:SetScript("OnClick", function(self)
        DB().sound = self:GetChecked() and true or false
        ApplySoundEnabledUI()
    end)

    -- Fade out of combat checkbox
    configFadeOOC = CreateFrame("CheckButton", "PomPomConfigFadeOOC", config, "UICheckButtonTemplate")
    configFadeOOC:SetPoint("TOPLEFT", configSound, "BOTTOMLEFT", 0, -6)
    _G[configFadeOOC:GetName() .. "Text"]:SetText("Fade out of combat")
    configFadeOOC:SetScript("OnClick", function(self)
        DB().fadeOOC = self:GetChecked() and true or false
        ApplyFadeState()
    end)

    -- Sound dropdown + Test button
    configSoundPick = CreateFrame("Frame", "PomPomConfigSoundPick", config, "UIDropDownMenuTemplate")
    configSoundPick:SetPoint("TOPLEFT", configFadeOOC, "BOTTOMLEFT", -12, -2)
    UIDropDownMenu_SetWidth(configSoundPick, 150)

    local function OnPick(self, idx)
        if not SOUND_PRESETS[idx] then return end
        DB().soundIndex = idx
        UIDropDownMenu_SetSelectedID(configSoundPick, idx)
        UIDropDownMenu_SetText(configSoundPick, SOUND_PRESETS[idx].name)
    end

    UIDropDownMenu_Initialize(configSoundPick, function(self, level)
        for i, snd in ipairs(SOUND_PRESETS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = snd.name
            info.value    = i
            info.checked  = (DB().soundIndex == i)
            info.func     = function(btn) OnPick(btn, i) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Scale the flyout list to 75% when our sound picker opens it.
    -- The list frame (DropDownListN) is parented to UIParent, so scaling
    -- the picker itself wouldn't affect the flyout — we hook after ToggleDropDownMenu.
    hooksecurefunc("ToggleDropDownMenu", function(level)
        level = level or 1
        local list = _G["DropDownList" .. level]
        if list and list:IsShown() and UIDROPDOWNMENU_OPEN_MENU == configSoundPick then
            list:SetScale(0.75)
        end
    end)

    configSoundTest = CreateFrame("Button", "PomPomConfigSoundTest", config, "UIPanelButtonTemplate")
    configSoundTest:SetSize(60, 22)
    configSoundTest:SetPoint("LEFT", configSoundPick, "RIGHT", -10, 2)
    configSoundTest:SetText("Test")
    configSoundTest:SetScript("OnClick", function() PlayPomSound(DB().soundIndex) end)

    -- Scale slider
    configScale = CreateFrame("Slider", "PomPomConfigScale", config, "OptionsSliderTemplate")
    configScale:SetPoint("TOPLEFT", configSoundPick, "BOTTOMLEFT", 12, -20)
    configScale:SetSize(240, 16)
    configScale:SetMinMaxValues(0.5, 2.0)
    configScale:SetValueStep(0.05)
    if configScale.SetObeyStepOnDrag then configScale:SetObeyStepOnDrag(true) end
    _G[configScale:GetName() .. "Low"]:SetText("0.5")
    _G[configScale:GetName() .. "High"]:SetText("2.0")
    _G[configScale:GetName() .. "Text"]:SetText("Scale")
    configScale:SetScript("OnValueChanged", function(self, value)
        DB().scale = value
        if main then main:SetScale(value) end
    end)

    -- Background opacity slider
    configBgAlpha = CreateFrame("Slider", "PomPomConfigBgAlpha", config, "OptionsSliderTemplate")
    configBgAlpha:SetPoint("TOPLEFT", configScale, "BOTTOMLEFT", 0, -32)
    configBgAlpha:SetSize(240, 16)
    configBgAlpha:SetMinMaxValues(0, 1)
    configBgAlpha:SetValueStep(0.05)
    if configBgAlpha.SetObeyStepOnDrag then configBgAlpha:SetObeyStepOnDrag(true) end
    _G[configBgAlpha:GetName() .. "Low"]:SetText("0%")
    _G[configBgAlpha:GetName() .. "High"]:SetText("100%")
    _G[configBgAlpha:GetName() .. "Text"]:SetText("Background opacity")
    configBgAlpha:SetScript("OnValueChanged", function(self, value)
        DB().bgAlpha = value
        ApplyBgAlpha()
    end)

    -- Availability message (shown when PoM is not usable on this character)
    availabilityLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    availabilityLabel:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", 14, 14)
    availabilityLabel:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -14, 14)
    availabilityLabel:SetJustifyH("LEFT")
    availabilityLabel:SetJustifyV("MIDDLE")
    availabilityLabel:SetTextColor(1, 0.55, 0.35, 1)
    availabilityLabel:Hide()

    config:SetScript("OnShow", function()
        local d = DB()
        configLock:SetChecked(d.locked and true or false)
        configScale:SetValue(d.scale or 1.0)
        configBgAlpha:SetValue(d.bgAlpha or 0.85)
        configSound:SetChecked(d.sound and true or false)
        configFadeOOC:SetChecked(d.fadeOOC and true or false)
        local idx = d.soundIndex or 1
        if not SOUND_PRESETS[idx] then idx = 1; d.soundIndex = 1 end
        UIDropDownMenu_SetSelectedID(configSoundPick, idx)
        UIDropDownMenu_SetText(configSoundPick, SOUND_PRESETS[idx].name)
        ApplySoundEnabledUI()
        ApplyConfigAvailability()
    end)
end

-- ── Slash command ────────────────────────────────────────────────────

SLASH_POMPOM1 = "/pom"
SLASH_POMPOM2 = "/pompom"
SlashCmdList["POMPOM"] = function()
    if not config then return end
    if config:IsShown() then config:Hide() else config:Show() end
end

-- ── Init ─────────────────────────────────────────────────────────────

local ev = CreateFrame("Frame")

function UpdateAvailability()
    pomAvailable, availabilityReason = CheckAvailability()

    if pomAvailable and not mainCreated then
        CreateMainFrame()
        UpdateLockVisuals()
        mainCreated = true
    end

    if main then
        if pomAvailable then
            main:Show()
        else
            main:Hide()
            GoIdle()
        end
    end

    if pomAvailable then
        ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        ev:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end

    ApplyConfigAvailability()
    ApplyFadeState()
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        DB()
        CreateConfigFrame()
        inCombat = UnitAffectingCombat("player") and true or false
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("PLAYER_TALENT_UPDATE")
        self:RegisterEvent("CHARACTER_POINTS_CHANGED")
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        UpdateAvailability()
        print("|cffFFD100PomPom|r loaded. Use |cffFFD100/pom|r for options.")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        ApplyFadeState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        ApplyFadeState()
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        UpdateAvailability()
    end
end)
