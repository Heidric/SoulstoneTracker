local SST_ADDON_NAME = "SoulstoneTracker"
local SST_VERSION = "0.1.3"
local SST_DURATION_SECONDS = 1800
local SST_WARN_FIVE_SECONDS = 300
local SST_WARN_ONE_SECONDS = 60
local SST_FRAME_WIDTH = 220
local SST_FRAME_HEIGHT = 28
local SST_DEFAULT_X = 0
local SST_DEFAULT_Y = 120
local SST_SCREEN_PADDING = 12
local SST_MIN_VISIBLE_WIDTH = 36
local SST_MIN_VISIBLE_HEIGHT = 14

local SST = {}
local SST_Frame = CreateFrame("Frame", "SoulstoneTrackerFrame", UIParent)
local SST_Text = nil
local SST_UpdateText = nil
local SST_Pending = nil
local SST_LastUpdate = 0
local SST_OriginalSpellTargetUnit = nil
local SST_Drag = nil

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

local function SST_Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

local function SST_GetSafeScale(value)
    local scale = tonumber(value)
    if not scale then
        return 1
    end

    if scale < 0.5 then
        return 0.5
    end

    if scale > 2 then
        return 2
    end

    return scale
end

local function SST_GetParentScale()
    if UIParent and UIParent.GetEffectiveScale then
        local scale = UIParent:GetEffectiveScale()
        if scale and scale > 0 then
            return scale
        end
    end

    if UIParent and UIParent.GetScale then
        local scale = UIParent:GetScale()
        if scale and scale > 0 then
            return scale
        end
    end

    return 1
end

local function SST_GetFrameScale()
    if SoulstoneTrackerDB then
        return SST_GetSafeScale(SoulstoneTrackerDB.scale)
    end

    return 1
end

local function SST_MaxDimension(currentValue, candidateValue)
    local current = tonumber(currentValue) or 0
    local candidate = tonumber(candidateValue) or 0

    if candidate > current then
        return candidate
    end

    return current
end

local function SST_GetCanvasSize()
    local width = 0
    local height = 0

    if UIParent and UIParent.GetWidth and UIParent.GetHeight then
        width = SST_MaxDimension(width, UIParent:GetWidth())
        height = SST_MaxDimension(height, UIParent:GetHeight())
    end

    local parentScale = SST_GetParentScale()
    if not parentScale or parentScale <= 0 then
        parentScale = 1
    end

    if GetScreenWidth and GetScreenHeight then
        local screenWidth = tonumber(GetScreenWidth())
        local screenHeight = tonumber(GetScreenHeight())

        if screenWidth and screenWidth > 0 then
            width = SST_MaxDimension(width, screenWidth)
            width = SST_MaxDimension(width, screenWidth / parentScale)
        end

        if screenHeight and screenHeight > 0 then
            height = SST_MaxDimension(height, screenHeight)
            height = SST_MaxDimension(height, screenHeight / parentScale)
        end
    end

    if GetCVar then
        local resolution = GetCVar("gxResolution")
        if resolution then
            local _, _, resolutionWidth, resolutionHeight = string.find(resolution, "(%d+)x(%d+)")
            resolutionWidth = tonumber(resolutionWidth)
            resolutionHeight = tonumber(resolutionHeight)

            if resolutionWidth and resolutionWidth > 0 then
                width = SST_MaxDimension(width, resolutionWidth)
                width = SST_MaxDimension(width, resolutionWidth / parentScale)
            end

            if resolutionHeight and resolutionHeight > 0 then
                height = SST_MaxDimension(height, resolutionHeight)
                height = SST_MaxDimension(height, resolutionHeight / parentScale)
            end
        end
    end

    if width <= 0 then
        width = 1024
    end

    if height <= 0 then
        height = 768
    end

    return width, height
end

local function SST_GetSafePosition(x, y, strict)
    local safeX = tonumber(x)
    local safeY = tonumber(y)

    if not safeX or not safeY then
        return SST_DEFAULT_X, SST_DEFAULT_Y, true
    end

    local canvasWidth, canvasHeight = SST_GetCanvasSize()

    if not canvasWidth or not canvasHeight or canvasWidth <= 0 or canvasHeight <= 0 then
        return safeX, safeY, false
    end

    local scale = SST_GetFrameScale()
    local visualWidth = SST_FRAME_WIDTH * scale
    local visualHeight = SST_FRAME_HEIGHT * scale

    local minX
    local maxX
    local minY
    local maxY

    if strict then
        minX = -(canvasWidth / 2) + (visualWidth / 2) + SST_SCREEN_PADDING
        maxX = (canvasWidth / 2) - (visualWidth / 2) - SST_SCREEN_PADDING
        minY = -(canvasHeight / 2) + (visualHeight / 2) + SST_SCREEN_PADDING
        maxY = (canvasHeight / 2) - (visualHeight / 2) - SST_SCREEN_PADDING
    else
        local visibleWidth = SST_MIN_VISIBLE_WIDTH
        local visibleHeight = SST_MIN_VISIBLE_HEIGHT

        if visibleWidth > visualWidth then
            visibleWidth = visualWidth
        end

        if visibleHeight > visualHeight then
            visibleHeight = visualHeight
        end

        minX = -(canvasWidth / 2) - (visualWidth / 2) + visibleWidth
        maxX = (canvasWidth / 2) + (visualWidth / 2) - visibleWidth
        minY = -(canvasHeight / 2) - (visualHeight / 2) + visibleHeight
        maxY = (canvasHeight / 2) + (visualHeight / 2) - visibleHeight
    end

    if minX > maxX then
        minX = -canvasWidth / 2
        maxX = canvasWidth / 2
    end

    if minY > maxY then
        minY = -canvasHeight / 2
        maxY = canvasHeight / 2
    end

    local clampedX = SST_Clamp(safeX, minX, maxX)
    local clampedY = SST_Clamp(safeY, minY, maxY)

    return clampedX, clampedY, clampedX ~= safeX or clampedY ~= safeY
end

local function SST_GetCursorPositionInParent()
    if not GetCursorPosition then
        return nil, nil
    end

    local cursorX, cursorY = GetCursorPosition()
    local parentScale = SST_GetParentScale()

    if not cursorX or not cursorY or parentScale <= 0 then
        return nil, nil
    end

    return cursorX / parentScale, cursorY / parentScale
end

local function SST_GetCurrentFramePosition()
    if not SST_Frame or not SST_Frame.GetCenter or not UIParent or not UIParent.GetCenter then
        return nil, nil
    end

    local frameX, frameY = SST_Frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()

    if not frameX or not frameY or not parentX or not parentY then
        return nil, nil
    end

    local frameEffectiveScale = 1
    if SST_Frame.GetEffectiveScale then
        frameEffectiveScale = SST_Frame:GetEffectiveScale() or 1
    end

    local parentScale = SST_GetParentScale()
    if parentScale <= 0 then
        parentScale = 1
    end

    frameX = frameX * frameEffectiveScale / parentScale
    frameY = frameY * frameEffectiveScale / parentScale

    return frameX - parentX, frameY - parentY
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

    SoulstoneTrackerDB.scale = SST_GetSafeScale(SoulstoneTrackerDB.scale)

    if SoulstoneTrackerDB.warnFive == nil then
        SoulstoneTrackerDB.warnFive = true
    end

    if SoulstoneTrackerDB.warnOne == nil then
        SoulstoneTrackerDB.warnOne = true
    end

    SoulstoneTrackerDB.x, SoulstoneTrackerDB.y = SST_GetSafePosition(SoulstoneTrackerDB.x, SoulstoneTrackerDB.y)
end

local function SST_SavePosition()
    if not SoulstoneTrackerDB then
        return
    end

    local x, y = SST_GetCurrentFramePosition()

    if x and y then
        local safeX, safeY = SST_GetSafePosition(x, y)
        SoulstoneTrackerDB.x = safeX
        SoulstoneTrackerDB.y = safeY
        return
    end

    SoulstoneTrackerDB.x = SST_DEFAULT_X
    SoulstoneTrackerDB.y = SST_DEFAULT_Y
end

local function SST_ApplyPosition()
    SST_Frame:ClearAllPoints()

    if SoulstoneTrackerDB and SoulstoneTrackerDB.x and SoulstoneTrackerDB.y then
        SoulstoneTrackerDB.x, SoulstoneTrackerDB.y = SST_GetSafePosition(SoulstoneTrackerDB.x, SoulstoneTrackerDB.y)
        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", SoulstoneTrackerDB.x, SoulstoneTrackerDB.y)
    else
        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", SST_DEFAULT_X, SST_DEFAULT_Y)
    end
end

local function SST_ApplyFrameState()
    if not SoulstoneTrackerDB then
        return
    end

    SoulstoneTrackerDB.scale = SST_GetSafeScale(SoulstoneTrackerDB.scale)
    SST_Frame:SetScale(SoulstoneTrackerDB.scale)
    SST_Frame:EnableMouse(not SoulstoneTrackerDB.locked)

    if SoulstoneTrackerDB.locked and SST_Drag then
        SST_Drag = nil
    end

    if SoulstoneTrackerDB.visible then
        SST_Frame:Show()
    else
        SST_Drag = nil
        SST_Frame:Hide()
    end
end

local function SST_ResetFrame()
    if not SoulstoneTrackerDB then
        SoulstoneTrackerDB = {}
    end

    SoulstoneTrackerDB.visible = true
    SoulstoneTrackerDB.locked = false
    SoulstoneTrackerDB.scale = 1
    SoulstoneTrackerDB.x = SST_DEFAULT_X
    SoulstoneTrackerDB.y = SST_DEFAULT_Y

    SST_ApplyPosition()
    SST_ApplyFrameState()
    SST_UpdateText()
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

function SST_UpdateText()
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

local function SST_StartDrag()
    if not SoulstoneTrackerDB or SoulstoneTrackerDB.locked then
        return
    end

    local cursorX, cursorY = SST_GetCursorPositionInParent()
    if not cursorX or not cursorY then
        return
    end

    local startX = SoulstoneTrackerDB.x
    local startY = SoulstoneTrackerDB.y

    if not startX or not startY then
        startX, startY = SST_GetCurrentFramePosition()
    end

    if not startX or not startY then
        startX = SST_DEFAULT_X
        startY = SST_DEFAULT_Y
    end

    startX, startY = SST_GetSafePosition(startX, startY)

    SST_Drag = {
        cursorX = cursorX,
        cursorY = cursorY,
        startX = startX,
        startY = startY
    }
end

local function SST_StopDrag()
    if not SST_Drag then
        return
    end

    SST_Drag = nil

    if SoulstoneTrackerDB then
        SoulstoneTrackerDB.x, SoulstoneTrackerDB.y = SST_GetSafePosition(SoulstoneTrackerDB.x, SoulstoneTrackerDB.y)
        SST_ApplyPosition()
    end
end

local function SST_UpdateDrag()
    if not SST_Drag or not SoulstoneTrackerDB then
        return
    end

    local cursorX, cursorY = SST_GetCursorPositionInParent()
    if not cursorX or not cursorY then
        return
    end

    local newX = SST_Drag.startX + (cursorX - SST_Drag.cursorX)
    local newY = SST_Drag.startY + (cursorY - SST_Drag.cursorY)

    SoulstoneTrackerDB.x, SoulstoneTrackerDB.y = SST_GetSafePosition(newX, newY)
    SST_ApplyPosition()
end

local function SST_OnUpdate()
    SST_UpdateDrag()

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
    SST_Frame:SetWidth(SST_FRAME_WIDTH)
    SST_Frame:SetHeight(SST_FRAME_HEIGHT)
    SST_Frame:SetMovable(false)
    SST_Frame:SetFrameStrata("HIGH")
    if SST_Frame.SetFrameLevel then
        SST_Frame:SetFrameLevel(100)
    end
    if SST_Frame.SetToplevel then
        SST_Frame:SetToplevel(true)
    end
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

    SST_Frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            SST_StartDrag()
        end
    end)

    SST_Frame:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" then
            SST_StopDrag()
        end
    end)

    SST_Frame:SetScript("OnHide", function()
        SST_StopDrag()
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
    SST_Print("commands: /sst status, /sst clear, /sst lock, /sst unlock, /sst show, /sst hide, /sst reset, /sst scale <value>, /sst pos, /sst test [name] [seconds]")
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
        SST_ApplyPosition()
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

    if msg == "reset" or msg == "center" then
        SST_ResetFrame()
        SST_Print("frame reset to the screen center.")
        return
    end

    if msg == "pos" or msg == "debugpos" then
        local canvasWidth, canvasHeight = SST_GetCanvasSize()
        local parentWidth = 0
        local parentHeight = 0
        local screenWidth = 0
        local screenHeight = 0

        if UIParent and UIParent.GetWidth and UIParent.GetHeight then
            parentWidth = UIParent:GetWidth() or 0
            parentHeight = UIParent:GetHeight() or 0
        end

        if GetScreenWidth and GetScreenHeight then
            screenWidth = GetScreenWidth() or 0
            screenHeight = GetScreenHeight() or 0
        end

        SST_Print("pos x=" .. (SoulstoneTrackerDB.x or "nil") .. ", y=" .. (SoulstoneTrackerDB.y or "nil") .. ", scale=" .. (SoulstoneTrackerDB.scale or "nil") .. ".")
        SST_Print("ui parent=" .. parentWidth .. "x" .. parentHeight .. ", screen=" .. screenWidth .. "x" .. screenHeight .. ", canvas=" .. canvasWidth .. "x" .. canvasHeight .. ", parentScale=" .. SST_GetParentScale() .. ".")
        return
    end

    local _, _, scaleValue = string.find(msg, "^scale%s+([0-9%.]+)$")
    if scaleValue then
        local scale = tonumber(scaleValue)
        if scale and scale >= 0.5 and scale <= 2 then
            SoulstoneTrackerDB.scale = scale
            SST_ApplyFrameState()
            SST_ApplyPosition()
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
