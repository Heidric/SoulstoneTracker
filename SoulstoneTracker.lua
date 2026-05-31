local SST_ADDON_NAME = "SoulstoneTracker"
local SST_VERSION = "0.1.0"
local SST_DURATION_SECONDS = 1800
local SST_WARN_FIVE_SECONDS = 300
local SST_WARN_ONE_SECONDS = 60

local SST = {}
local SST_Frame = CreateFrame("Frame", "SoulstoneTrackerFrame", UIParent)
local SST_Text = nil
local SST_Pending = nil
local SST_LastUpdate = 0
local SST_OriginalSpellTargetUnit = nil

local SST_SOULSTONE_SPELL_IDS = {
    [20707] = true, -- Minor Soulstone effect
    [20762] = true, -- Lesser Soulstone effect
    [20763] = true, -- Soulstone effect
    [20764] = true, -- Greater Soulstone effect
    [20765] = true  -- Major Soulstone effect
}

local SST_SOULSTONE_ITEM_IDS = {
    [5232] = true,  -- Minor Soulstone
    [16892] = true, -- Lesser Soulstone
    [16893] = true, -- Soulstone
    [16895] = true, -- Greater Soulstone
    [16896] = true  -- Major Soulstone
}

local function SST_Now()
    if time then
        return time()
    end

    return GetTime()
end

local function SST_MonoNow()
    return GetTime()
end

local function SST_Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9SST|r: " .. message)
    end
end

local function SST_FormatTime(seconds)
    if not seconds or seconds < 0 then
        seconds = 0
    end

    local minutes = floor(seconds / 60)
    local remainingSeconds = floor(seconds - (minutes * 60))

    if remainingSeconds < 10 then
        return minutes .. ":0" .. remainingSeconds
    end

    return minutes .. ":" .. remainingSeconds
end

local function SST_TableHasSoulstoneSpellID(value)
    local id = tonumber(value)
    if id and SST_SOULSTONE_SPELL_IDS[id] then
        return true
    end

    return false
end

local function SST_IsSuperWoWAvailable()
    if SUPERWOW_VERSION then
        return true
    end

    return false
end

local function SST_InitDB()
    if not SoulstoneTrackerDB then
        SoulstoneTrackerDB = {}
    end

    if SoulstoneTrackerDB.visible == nil then
        SoulstoneTrackerDB.visible = true
    end

    if SoulstoneTrackerDB.locked == nil then
        SoulstoneTrackerDB.locked = false
    end

    if not SoulstoneTrackerDB.scale then
        SoulstoneTrackerDB.scale = 1
    end

    if SoulstoneTrackerDB.warnFive == nil then
        SoulstoneTrackerDB.warnFive = true
    end

    if SoulstoneTrackerDB.warnOne == nil then
        SoulstoneTrackerDB.warnOne = true
    end
end

local function SST_SavePosition()
    if not SoulstoneTrackerDB then
        return
    end

    local x, y = SST_Frame:GetCenter()
    local ux, uy = UIParent:GetCenter()

    if x and y and ux and uy then
        SoulstoneTrackerDB.x = x - ux
        SoulstoneTrackerDB.y = y - uy
    end
end

local function SST_ApplyPosition()
    SST_Frame:ClearAllPoints()

    if SoulstoneTrackerDB and SoulstoneTrackerDB.x and SoulstoneTrackerDB.y then
        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", SoulstoneTrackerDB.x, SoulstoneTrackerDB.y)
    else
        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function SST_ApplyFrameState()
    if not SoulstoneTrackerDB then
        return
    end

    SST_Frame:SetScale(SoulstoneTrackerDB.scale or 1)
    SST_Frame:EnableMouse(not SoulstoneTrackerDB.locked)

    if SoulstoneTrackerDB.visible then
        SST_Frame:Show()
    else
        SST_Frame:Hide()
    end
end

local function SST_ResolveUnitName(unit)
    if unit and UnitExists(unit) then
        local name = UnitName(unit)
        if name and name ~= "" then
            return name
        end
    end

    return nil
end

local function SST_GetUnitGUID(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end

    if SST_IsSuperWoWAvailable() then
        local exists, guid = UnitExists(unit)
        if guid and guid ~= "" then
            return guid
        end
    end

    return nil
end

local function SST_IsFriendlyPlayerUnit(unit)
    if not unit or not UnitExists(unit) then
        return false
    end

    if UnitIsPlayer and not UnitIsPlayer(unit) then
        return false
    end

    if UnitIsFriend and not UnitIsFriend("player", unit) then
        return false
    end

    return true
end

local function SST_GetCandidateTarget(unit)
    if SST_IsFriendlyPlayerUnit(unit) then
        return {
            unit = unit,
            guid = SST_GetUnitGUID(unit),
            name = SST_ResolveUnitName(unit)
        }
    end

    return nil
end

local function SST_GetCurrentFriendlyTarget()
    local target = SST_GetCandidateTarget("target")
    if target then
        return target
    end

    target = SST_GetCandidateTarget("mouseover")
    if target then
        return target
    end

    return SST_GetCandidateTarget("player")
end

local function SST_FindTrackedUnit()
    if not SoulstoneTrackerDB or not SoulstoneTrackerDB.record then
        return nil
    end

    local record = SoulstoneTrackerDB.record

    if record.guid and SST_IsSuperWoWAvailable() and UnitExists(record.guid) then
        return record.guid
    end

    if record.guid then
        local units = { "player", "target", "mouseover", "party1", "party2", "party3", "party4" }
        local unitCount = table.getn(units)
        local i
        for i = 1, unitCount do
            local unit = units[i]
            local guid = SST_GetUnitGUID(unit)
            if guid and guid == record.guid then
                return unit
            end
        end

        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            local raidIndex
            for raidIndex = 1, 40 do
                local raidUnit = "raid" .. raidIndex
                local raidGuid = SST_GetUnitGUID(raidUnit)
                if raidGuid and raidGuid == record.guid then
                    return raidUnit
                end
            end
        end
    end

    if record.name then
        local unitsByName = { "player", "target", "mouseover", "party1", "party2", "party3", "party4" }
        local unitCountByName = table.getn(unitsByName)
        local j
        for j = 1, unitCountByName do
            local unitByName = unitsByName[j]
            if UnitExists(unitByName) and UnitName(unitByName) == record.name then
                return unitByName
            end
        end

        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            local raidNameIndex
            for raidNameIndex = 1, 40 do
                local raidNameUnit = "raid" .. raidNameIndex
                if UnitExists(raidNameUnit) and UnitName(raidNameUnit) == record.name then
                    return raidNameUnit
                end
            end
        end
    end

    return nil
end

local function SST_HasSoulstoneBuff(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end

    if SST_IsSuperWoWAvailable() and UnitBuff then
        local i
        for i = 1, 40 do
            local texture, applications, auraID, extra4, extra5, extra6 = UnitBuff(unit, i)
            if not texture then
                break
            end

            if SST_TableHasSoulstoneSpellID(auraID) or SST_TableHasSoulstoneSpellID(extra4) or SST_TableHasSoulstoneSpellID(extra5) or SST_TableHasSoulstoneSpellID(extra6) then
                return true
            end
        end

        return false
    end

    if unit == "player" and GetPlayerBuff and GetPlayerBuffID then
        local buffIndex
        for buffIndex = 0, 31 do
            local playerBuff = GetPlayerBuff(buffIndex, "HELPFUL")
            if playerBuff and playerBuff >= 0 then
                local auraID = GetPlayerBuffID(playerBuff)
                if SST_TableHasSoulstoneSpellID(auraID) then
                    return true
                end
            end
        end

        return false
    end

    return nil
end

local function SST_ClearRecord(reason)
    if SoulstoneTrackerDB then
        SoulstoneTrackerDB.record = nil
    end

    if reason then
        SST_Print(reason)
    end
end

local function SST_TrackSoulstone(targetGuid, targetName, spellID, source)
    if not SoulstoneTrackerDB then
        return
    end

    local now = SST_Now()
    local monoNow = SST_MonoNow()

    if not targetName and targetGuid and UnitExists(targetGuid) then
        targetName = SST_ResolveUnitName(targetGuid)
    end

    if not targetName or targetName == "" then
        targetName = "unknown target"
    end

    SoulstoneTrackerDB.record = {
        guid = targetGuid,
        name = targetName,
        spellID = tonumber(spellID),
        castAt = now,
        castAtMono = monoNow,
        expiresAt = now + SST_DURATION_SECONDS,
        confirmed = false,
        warnedFive = false,
        warnedOne = false,
        source = source or "unknown"
    }

    SST_Print("Soulstone tracked on " .. targetName .. " for 30:00.")
end

local function SST_StartPendingCast()
    local target = SST_GetCurrentFriendlyTarget()

    SST_Pending = {
        startedAt = SST_MonoNow(),
        targetUnit = target and target.unit or nil,
        targetGuid = target and target.guid or nil,
        targetName = target and target.name or nil
    }
end

local function SST_UpdatePendingTarget(unit)
    if not SST_Pending then
        return
    end

    local target = SST_GetCandidateTarget(unit)
    if target then
        SST_Pending.targetUnit = target.unit
        SST_Pending.targetGuid = target.guid
        SST_Pending.targetName = target.name
    end
end

local function SST_FinishPendingCast()
    if not SST_Pending then
        return
    end

    if SST_MonoNow() - SST_Pending.startedAt > 8 then
        SST_Pending = nil
        return
    end

    local targetName = SST_Pending.targetName
    local targetGuid = SST_Pending.targetGuid

    if not targetName then
        local currentTarget = SST_GetCurrentFriendlyTarget()
        if currentTarget then
            targetName = currentTarget.name
            targetGuid = currentTarget.guid
        end
    end

    SST_TrackSoulstone(targetGuid, targetName, nil, "fallback-spellcast")
    SST_Pending = nil
end

local function SST_UpdateText()
    if not SST_Text or not SoulstoneTrackerDB then
        return
    end

    local record = SoulstoneTrackerDB.record
    if not record then
        SST_Text:SetText("Soulstone: none")
        SST_Text:SetTextColor(0.7, 0.7, 0.7)
        return
    end

    local remaining = record.expiresAt - SST_Now()
    if remaining <= 0 then
        SST_Text:SetText("Soulstone: expired")
        SST_Text:SetTextColor(1, 0.2, 0.2)
        return
    end

    local name = record.name or "unknown target"
    SST_Text:SetText("Soulstone: " .. name .. " " .. SST_FormatTime(remaining))

    if remaining <= SST_WARN_ONE_SECONDS then
        SST_Text:SetTextColor(1, 0.2, 0.2)
    elseif remaining <= SST_WARN_FIVE_SECONDS then
        SST_Text:SetTextColor(1, 0.82, 0)
    else
        SST_Text:SetTextColor(0.2, 1, 0.2)
    end
end

local function SST_VerifyTrackedBuff()
    if not SoulstoneTrackerDB or not SoulstoneTrackerDB.record then
        return
    end

    local record = SoulstoneTrackerDB.record
    local unit = SST_FindTrackedUnit()
    if not unit then
        return
    end

    local hasBuff = SST_HasSoulstoneBuff(unit)
    if hasBuff == true then
        record.confirmed = true
        return
    end

    if hasBuff == false and record.confirmed and record.castAtMono and (SST_MonoNow() - record.castAtMono > 8) then
        SST_ClearRecord("Soulstone is no longer visible on " .. (record.name or "tracked target") .. ".")
    end
end

local function SST_CheckWarnings()
    if not SoulstoneTrackerDB or not SoulstoneTrackerDB.record then
        return
    end

    local record = SoulstoneTrackerDB.record
    local remaining = record.expiresAt - SST_Now()

    if remaining <= 0 then
        local name = record.name or "tracked target"
        SST_ClearRecord("Soulstone on " .. name .. " expired.")
        return
    end

    if SoulstoneTrackerDB.warnFive and not record.warnedFive and remaining <= SST_WARN_FIVE_SECONDS then
        record.warnedFive = true
        SST_Print("Soulstone on " .. (record.name or "tracked target") .. " expires in 5 minutes.")
    end

    if SoulstoneTrackerDB.warnOne and not record.warnedOne and remaining <= SST_WARN_ONE_SECONDS then
        record.warnedOne = true
        SST_Print("Soulstone on " .. (record.name or "tracked target") .. " expires in 1 minute.")
    end
end

local function SST_OnUnitCastEvent()
    local casterGuid = arg1
    local targetGuid = arg2
    local eventType = arg3
    local spellID = tonumber(arg4)

    if eventType ~= "CAST" then
        return
    end

    if not spellID or not SST_SOULSTONE_SPELL_IDS[spellID] then
        return
    end

    if not casterGuid or not UnitIsUnit(casterGuid, "player") then
        return
    end

    local targetName = nil
    if targetGuid and UnitExists(targetGuid) then
        targetName = UnitName(targetGuid)
    end

    SST_TrackSoulstone(targetGuid, targetName, spellID, "superwow-unit-castevent")
    SST_Pending = nil
end

local function SST_OnEvent()
    if event == "ADDON_LOADED" and arg1 == SST_ADDON_NAME then
        SST_InitDB()
        SST_ApplyPosition()
        SST_ApplyFrameState()
        SST_UpdateText()

        if SST_IsSuperWoWAvailable() then
            SST_Print("loaded " .. SST_VERSION .. " with SuperWoW support.")
        else
            SST_Print("loaded " .. SST_VERSION .. " without SuperWoW. Target tracking will be approximate.")
        end

        return
    end

    if event == "UNIT_CASTEVENT" then
        SST_OnUnitCastEvent()
        return
    end

    if event == "SPELLCAST_START" then
        if arg1 == "Soulstone Resurrection" then
            SST_StartPendingCast()
        end
        return
    end

    if event == "SPELLCAST_STOP" then
        SST_FinishPendingCast()
        return
    end

    if event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        SST_Pending = nil
        return
    end

    if event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        SST_VerifyTrackedBuff()
        return
    end
end

local function SST_OnUpdate()
    SST_LastUpdate = SST_LastUpdate + arg1
    if SST_LastUpdate < 1 then
        return
    end

    SST_LastUpdate = 0
    SST_CheckWarnings()
    SST_VerifyTrackedBuff()
    SST_UpdateText()
end

local function SST_CreateFrame()
    SST_Frame:SetWidth(220)
    SST_Frame:SetHeight(28)
    SST_Frame:SetMovable(true)
    SST_Frame:RegisterForDrag("LeftButton")
    SST_Frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    SST_Frame:SetBackdropColor(0, 0, 0, 0.75)

    SST_Text = SST_Frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    SST_Text:SetPoint("CENTER", SST_Frame, "CENTER", 0, 0)
    SST_Text:SetText("Soulstone: none")

    SST_Frame:SetScript("OnDragStart", function()
        if SoulstoneTrackerDB and not SoulstoneTrackerDB.locked then
            this:StartMoving()
        end
    end)

    SST_Frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SST_SavePosition()
    end)

    SST_Frame:SetScript("OnEvent", SST_OnEvent)
    SST_Frame:SetScript("OnUpdate", SST_OnUpdate)

    SST_Frame:RegisterEvent("ADDON_LOADED")
    SST_Frame:RegisterEvent("SPELLCAST_START")
    SST_Frame:RegisterEvent("SPELLCAST_STOP")
    SST_Frame:RegisterEvent("SPELLCAST_FAILED")
    SST_Frame:RegisterEvent("SPELLCAST_INTERRUPTED")
    SST_Frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    SST_Frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    SST_Frame:RegisterEvent("RAID_ROSTER_UPDATE")
    SST_Frame:RegisterEvent("PARTY_MEMBERS_CHANGED")

    if SST_IsSuperWoWAvailable() then
        SST_Frame:RegisterEvent("UNIT_CASTEVENT")
    end
end

local function SST_HookSpellTargetUnit()
    if SST_OriginalSpellTargetUnit then
        return
    end

    SST_OriginalSpellTargetUnit = SpellTargetUnit
    SpellTargetUnit = function(unit)
        SST_UpdatePendingTarget(unit)
        return SST_OriginalSpellTargetUnit(unit)
    end
end

local function SST_NormalizeSlashCommand(message)
    if not message then
        return ""
    end

    message = string.lower(message)
    return message
end

local function SST_PrintHelp()
    SST_Print("commands: /sst status, /sst clear, /sst lock, /sst unlock, /sst show, /sst hide, /sst scale <value>, /sst test [name] [seconds]")
end

local function SST_SlashHandler(message)
    local msg = SST_NormalizeSlashCommand(message)

    if msg == "" or msg == "help" then
        SST_PrintHelp()
        return
    end

    if msg == "status" then
        if SoulstoneTrackerDB and SoulstoneTrackerDB.record then
            local remaining = SoulstoneTrackerDB.record.expiresAt - SST_Now()
            SST_Print("active: " .. (SoulstoneTrackerDB.record.name or "unknown target") .. ", remaining " .. SST_FormatTime(remaining) .. ".")
        else
            SST_Print("no active tracked soulstone.")
        end
        return
    end

    if msg == "clear" then
        SST_ClearRecord("tracking cleared.")
        SST_UpdateText()
        return
    end

    if msg == "lock" then
        SoulstoneTrackerDB.locked = true
        SST_ApplyFrameState()
        SST_Print("frame locked.")
        return
    end

    if msg == "unlock" then
        SoulstoneTrackerDB.locked = false
        SST_ApplyFrameState()
        SST_Print("frame unlocked.")
        return
    end

    if msg == "show" then
        SoulstoneTrackerDB.visible = true
        SST_ApplyFrameState()
        SST_Print("frame shown.")
        return
    end

    if msg == "hide" then
        SoulstoneTrackerDB.visible = false
        SST_ApplyFrameState()
        SST_Print("frame hidden.")
        return
    end

    local _, _, scaleValue = string.find(msg, "^scale%s+([0-9%.]+)$")
    if scaleValue then
        local scale = tonumber(scaleValue)
        if scale and scale >= 0.5 and scale <= 2 then
            SoulstoneTrackerDB.scale = scale
            SST_ApplyFrameState()
            SST_Print("scale set to " .. scale .. ".")
        else
            SST_Print("scale must be between 0.5 and 2.")
        end
        return
    end

    local _, _, testName, testSeconds = string.find(message or "", "^test%s*([^%s]*)%s*(%d*)$")
    if testName then
        if testName == "" then
            testName = UnitName("player") or "test target"
        end

        local duration = tonumber(testSeconds) or SST_DURATION_SECONDS
        SST_TrackSoulstone(nil, testName, 20707, "test")
        SoulstoneTrackerDB.record.expiresAt = SST_Now() + duration
        SST_UpdateText()
        return
    end

    SST_PrintHelp()
end

SST_CreateFrame()
SST_HookSpellTargetUnit()

SLASH_SOULSTONETRACKER1 = "/sst"
SLASH_SOULSTONETRACKER2 = "/soulstone"
SlashCmdList["SOULSTONETRACKER"] = SST_SlashHandler
