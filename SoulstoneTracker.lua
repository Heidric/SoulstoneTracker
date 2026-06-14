local SST_ADDON_NAME = "SoulstoneTracker"
local SST_VERSION = "0.2.1"
local SST_DURATION_SECONDS = 1800
local SST_WARN_FIVE_SECONDS = 300
local SST_WARN_ONE_SECONDS = 60
local SST_FRAME_WIDTH = 220
local SST_FRAME_HEIGHT = 28
local SST_BUTTON_SIZE = 32
local SST_SETTINGS_WIDTH = 440
local SST_SETTINGS_HEIGHT = 360
local SST_SOULSTONE_TEXTURE = "Interface\\Icons\\Spell_Shadow_SoulGem"
local SST_DEFAULT_X = 0
local SST_DEFAULT_Y = 120
local SST_SCREEN_PADDING = 12
local SST_MIN_VISIBLE_WIDTH = 36
local SST_MIN_VISIBLE_HEIGHT = 14

local SST = {}
local SST_CoreFrame = CreateFrame("Frame", "SoulstoneTrackerCoreFrame", UIParent)
local SST_Frame = CreateFrame("Frame", "SoulstoneTrackerFrame", UIParent)
local SST_Text = nil
local SST_UpdateText = nil
local SST_Pending = nil
local SST_LastUpdate = 0
local SST_OriginalSpellTargetUnit = nil
local SST_Drag = nil
local SST_ButtonDrag = nil
local SST_SettingsFrame = nil
local SST_SettingsTitle = nil
local SST_SettingsTabs = {}
local SST_SettingsPages = {}
local SST_SettingsControls = {}
local SST_MinimapButton = nil
local SST_MinimapButtonIcon = nil
local SST_RefreshSettingsUI = nil
local SST_ToggleSettingsFrame = nil
local SST_ApplyButtonState = nil
local SST_SetSettingsTab = nil
local SST_LastAnnouncementAt = 0
local SST_LastAnnouncementTarget = nil
local SST_PositionsReady = false

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

local SST_ANNOUNCE_CHANNELS = {
    { key = "SMART", label = "Smart: Raid > Party > Say" },
    { key = "SAY", label = "Say" },
    { key = "PARTY", label = "Party" },
    { key = "RAID", label = "Raid" },
    { key = "GUILD", label = "Guild" },
    { key = "YELL", label = "Yell" },
    { key = "EMOTE", label = "Emote" }
}

local SST_DEFAULT_ANNOUNCE_MESSAGE = "Soulstone applied to {target}. It will expire in {duration}."

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

local function SST_GetUIParentSize()
    local width = 1024
    local height = 768

    if UIParent and UIParent.GetWidth and UIParent.GetHeight then
        local parentWidth = tonumber(UIParent:GetWidth())
        local parentHeight = tonumber(UIParent:GetHeight())

        if parentWidth and parentWidth > 0 then
            width = parentWidth
        end

        if parentHeight and parentHeight > 0 then
            height = parentHeight
        end
    end

    return width, height
end

local function SST_GetRelativeCenterToUIParent(frame)
    if not frame or not frame.GetCenter or not UIParent or not UIParent.GetCenter then
        return nil, nil
    end

    local frameX, frameY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()

    if not frameX or not frameY or not parentX or not parentY then
        return nil, nil
    end

    return frameX - parentX, frameY - parentY
end

local function SST_GetSafePositionForSize(x, y, width, height, scale, minVisibleWidth, minVisibleHeight, strict)
    local safeX = tonumber(x)
    local safeY = tonumber(y)

    if not safeX or not safeY then
        return SST_DEFAULT_X, SST_DEFAULT_Y, true
    end

    local canvasWidth, canvasHeight = SST_GetCanvasSize()

    if not canvasWidth or not canvasHeight or canvasWidth <= 0 or canvasHeight <= 0 then
        return safeX, safeY, false
    end

    local actualScale = tonumber(scale) or 1
    if actualScale <= 0 then
        actualScale = 1
    end

    local visualWidth = (tonumber(width) or SST_FRAME_WIDTH) * actualScale
    local visualHeight = (tonumber(height) or SST_FRAME_HEIGHT) * actualScale

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
        local visibleWidth = minVisibleWidth or SST_MIN_VISIBLE_WIDTH
        local visibleHeight = minVisibleHeight or SST_MIN_VISIBLE_HEIGHT

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

local function SST_GetSafePosition(x, y, strict)
    return SST_GetSafePositionForSize(x, y, SST_FRAME_WIDTH, SST_FRAME_HEIGHT, SST_GetFrameScale(), SST_MIN_VISIBLE_WIDTH, SST_MIN_VISIBLE_HEIGHT, strict)
end

local function SST_GetDefaultButtonPosition()
    local minimapX, minimapY = SST_GetRelativeCenterToUIParent(Minimap)
    if minimapX and minimapY then
        return minimapX - 54, minimapY - 54
    end

    local parentWidth, parentHeight = SST_GetUIParentSize()
    return (parentWidth / 2) - 78, (parentHeight / 2) - 96
end

local function SST_GetSafeButtonPosition(x, y)
    local safeX = tonumber(x)
    local safeY = tonumber(y)

    if not safeX or not safeY then
        return SST_GetDefaultButtonPosition()
    end

    return SST_GetSafePositionForSize(safeX, safeY, SST_BUTTON_SIZE, SST_BUTTON_SIZE, 1, 8, 8, false)
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

    local previousAddonVersion = SoulstoneTrackerDB.addonVersion
    local shouldResetButtonPosition = previousAddonVersion ~= SST_VERSION and not SoulstoneTrackerDB.buttonPositionUserMoved

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

    if SoulstoneTrackerDB.announceEnabled == nil then
        SoulstoneTrackerDB.announceEnabled = false
    end

    if not SoulstoneTrackerDB.announceChannel then
        SoulstoneTrackerDB.announceChannel = "SMART"
    end

    if not SoulstoneTrackerDB.announceMessage or SoulstoneTrackerDB.announceMessage == "" then
        SoulstoneTrackerDB.announceMessage = SST_DEFAULT_ANNOUNCE_MESSAGE
    end

    if SoulstoneTrackerDB.buttonVisible == nil then
        SoulstoneTrackerDB.buttonVisible = true
    end

    if not SoulstoneTrackerDB.settingsTab then
        SoulstoneTrackerDB.settingsTab = "general"
    end

    SoulstoneTrackerDB.x = tonumber(SoulstoneTrackerDB.x)
    SoulstoneTrackerDB.y = tonumber(SoulstoneTrackerDB.y)

    if not SoulstoneTrackerDB.x or not SoulstoneTrackerDB.y then
        SoulstoneTrackerDB.x = SST_DEFAULT_X
        SoulstoneTrackerDB.y = SST_DEFAULT_Y
    end

    if shouldResetButtonPosition or not SoulstoneTrackerDB.buttonX or not SoulstoneTrackerDB.buttonY then
        SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetDefaultButtonPosition()
    end

    SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetSafeButtonPosition(SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY)
    SoulstoneTrackerDB.addonVersion = SST_VERSION
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
        local x = tonumber(SoulstoneTrackerDB.x)
        local y = tonumber(SoulstoneTrackerDB.y)

        if not x or not y then
            x = SST_DEFAULT_X
            y = SST_DEFAULT_Y
            SoulstoneTrackerDB.x = x
            SoulstoneTrackerDB.y = y
        end

        if SST_PositionsReady then
            x, y = SST_GetSafePosition(x, y)
            SoulstoneTrackerDB.x = x
            SoulstoneTrackerDB.y = y
        end

        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    else
        SST_Frame:SetPoint("CENTER", UIParent, "CENTER", SST_DEFAULT_X, SST_DEFAULT_Y)
    end
end

local function SST_ApplyPositionsAfterLayout()
    SST_PositionsReady = true
    SST_ApplyPosition()
    if SST_ApplyButtonState then
        SST_ApplyButtonState()
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

    if SST_RefreshSettingsUI then
        SST_RefreshSettingsUI()
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

local function SST_GetAnnounceChannelIndex(channel)
    local i
    for i = 1, table.getn(SST_ANNOUNCE_CHANNELS) do
        if SST_ANNOUNCE_CHANNELS[i].key == channel then
            return i
        end
    end

    return 1
end

local function SST_GetAnnounceChannelLabel(channel)
    return SST_ANNOUNCE_CHANNELS[SST_GetAnnounceChannelIndex(channel)].label
end

local function SST_SetAnnounceChannelByDelta(delta)
    if not SoulstoneTrackerDB then
        return
    end

    local index = SST_GetAnnounceChannelIndex(SoulstoneTrackerDB.announceChannel) + delta
    local count = table.getn(SST_ANNOUNCE_CHANNELS)

    if index < 1 then
        index = count
    end

    if index > count then
        index = 1
    end

    SoulstoneTrackerDB.announceChannel = SST_ANNOUNCE_CHANNELS[index].key

    if SST_RefreshSettingsUI then
        SST_RefreshSettingsUI()
    end
end

local function SST_SetAnnounceChannel(channel)
    if not SoulstoneTrackerDB or not channel then
        return false
    end

    local normalized = string.upper(channel)
    local i
    for i = 1, table.getn(SST_ANNOUNCE_CHANNELS) do
        if SST_ANNOUNCE_CHANNELS[i].key == normalized then
            SoulstoneTrackerDB.announceChannel = normalized
            if SST_RefreshSettingsUI then
                SST_RefreshSettingsUI()
            end
            return true
        end
    end

    return false
end

local function SST_GetSmartAnnounceChannel()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return "RAID"
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return "PARTY"
    end

    return "SAY"
end

local function SST_ResolveAnnounceChannel(channel)
    if channel == "SMART" then
        return SST_GetSmartAnnounceChannel()
    end

    return channel or "SAY"
end

local function SST_CanSendToAnnounceChannel(channel)
    if channel == "PARTY" then
        if GetNumPartyMembers and GetNumPartyMembers() > 0 then
            return true
        end

        return false, "party"
    end

    if channel == "RAID" then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            return true
        end

        return false, "raid"
    end

    if channel == "GUILD" then
        if IsInGuild and IsInGuild() then
            return true
        end

        return false, "guild"
    end

    return true
end

local function SST_FormatAnnouncementText(targetName)
    local text = SST_DEFAULT_ANNOUNCE_MESSAGE

    if SoulstoneTrackerDB and SoulstoneTrackerDB.announceMessage and SoulstoneTrackerDB.announceMessage ~= "" then
        text = SoulstoneTrackerDB.announceMessage
    end

    local target = targetName or "unknown target"
    local playerName = UnitName("player") or "warlock"

    text = string.gsub(text, "{target}", target)
    text = string.gsub(text, "{name}", target)
    text = string.gsub(text, "{player}", playerName)
    text = string.gsub(text, "{duration}", "30 minutes")

    return text
end

local function SST_SendAnnouncement(targetName, source)
    if not SoulstoneTrackerDB or not SoulstoneTrackerDB.announceEnabled then
        return
    end

    if source == "test" then
        return
    end

    local now = SST_MonoNow()
    local normalizedTarget = targetName or "unknown target"

    if SST_LastAnnouncementTarget == normalizedTarget and (now - SST_LastAnnouncementAt) < 4 then
        return
    end

    local channel = SST_ResolveAnnounceChannel(SoulstoneTrackerDB.announceChannel)
    local canSend, required = SST_CanSendToAnnounceChannel(channel)
    if not canSend then
        SST_Print("announcement not sent: selected channel requires " .. required .. ".")
        return
    end

    local text = SST_FormatAnnouncementText(normalizedTarget)

    if SendChatMessage then
        SendChatMessage(text, channel)
        SST_LastAnnouncementAt = now
        SST_LastAnnouncementTarget = normalizedTarget
    else
        SST_Print("announcement not sent: SendChatMessage is unavailable.")
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
    SST_SendAnnouncement(targetName, source)
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
        SST_ApplyButtonState()
        SST_SetSettingsTab(SoulstoneTrackerDB.settingsTab or "general")
        SST_UpdateText()
        SST_RefreshSettingsUI()

        if SST_IsSuperWoWAvailable() then
            SST_Print("loaded " .. SST_VERSION .. " with SuperWoW support.")
        else
            SST_Print("loaded " .. SST_VERSION .. " without SuperWoW. Target tracking will be approximate.")
        end

        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        SST_ApplyPositionsAfterLayout()
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

    if SoulstoneTrackerDB then
        local x = SoulstoneTrackerDB.x
        local y = SoulstoneTrackerDB.y
        local cursorX, cursorY = SST_GetCursorPositionInParent()

        if cursorX and cursorY then
            x = SST_Drag.startX + (cursorX - SST_Drag.cursorX)
            y = SST_Drag.startY + (cursorY - SST_Drag.cursorY)
        end

        x, y = SST_GetSafePosition(x, y)
        SoulstoneTrackerDB.x = x
        SoulstoneTrackerDB.y = y
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

local function SST_ApplyButtonPosition()
    if not SST_MinimapButton or not SoulstoneTrackerDB then
        return
    end

    if not SoulstoneTrackerDB.buttonX or not SoulstoneTrackerDB.buttonY then
        SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetDefaultButtonPosition()
    end

    SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetSafeButtonPosition(SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY)
    SST_MinimapButton:ClearAllPoints()
    SST_MinimapButton:SetPoint("CENTER", UIParent, "CENTER", SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY)
end

function SST_ApplyButtonState()
    if not SST_MinimapButton or not SoulstoneTrackerDB then
        return
    end

    SST_ApplyButtonPosition()

    if SoulstoneTrackerDB.buttonVisible then
        SST_MinimapButton:Show()
        if SST_MinimapButton.Raise then
            SST_MinimapButton:Raise()
        end
    else
        SST_ButtonDrag = nil
        SST_MinimapButton:Hide()
    end

    if SST_RefreshSettingsUI then
        SST_RefreshSettingsUI()
    end

    SST_Drag = nil
    SST_ApplyPosition()
end

local function SST_ResetButtonPosition()
    if not SoulstoneTrackerDB then
        return
    end

    SoulstoneTrackerDB.buttonVisible = true
    SoulstoneTrackerDB.buttonPositionUserMoved = nil
    SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetDefaultButtonPosition()
    SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetSafeButtonPosition(SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY)
    SST_ApplyButtonState()
end

local function SST_StartButtonDrag()
    if not SoulstoneTrackerDB then
        return
    end

    local cursorX, cursorY = SST_GetCursorPositionInParent()
    if not cursorX or not cursorY then
        return
    end

    if not SoulstoneTrackerDB.buttonX or not SoulstoneTrackerDB.buttonY then
        SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetDefaultButtonPosition()
    end

    SST_ButtonDrag = {
        cursorX = cursorX,
        cursorY = cursorY,
        startX = SoulstoneTrackerDB.buttonX,
        startY = SoulstoneTrackerDB.buttonY,
        moved = false
    }
end

local function SST_UpdateButtonDrag()
    if not SST_ButtonDrag or not SoulstoneTrackerDB then
        return
    end

    local cursorX, cursorY = SST_GetCursorPositionInParent()
    if not cursorX or not cursorY then
        return
    end

    local dx = cursorX - SST_ButtonDrag.cursorX
    local dy = cursorY - SST_ButtonDrag.cursorY

    if dx > 3 or dx < -3 or dy > 3 or dy < -3 then
        SST_ButtonDrag.moved = true
    end

    SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetSafeButtonPosition(SST_ButtonDrag.startX + dx, SST_ButtonDrag.startY + dy)
    SST_ApplyButtonPosition()
end

local function SST_StopButtonDrag()
    if not SST_ButtonDrag then
        return false
    end

    local moved = SST_ButtonDrag.moved
    SST_ButtonDrag = nil

    if SoulstoneTrackerDB then
        SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY = SST_GetSafeButtonPosition(SoulstoneTrackerDB.buttonX, SoulstoneTrackerDB.buttonY)
        if moved then
            SoulstoneTrackerDB.buttonPositionUserMoved = true
        end
        SST_ApplyButtonPosition()
    end

    return moved
end

local function SST_CreateLabel(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text or "")
    return label
end

local function SST_CreatePanelButton(parent, text, width, height, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 90)
    button:SetHeight(height or 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text or "")
    button:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    return button
end

local function SST_CreateCheckButton(parent, name, label, x, y, onClick)
    local button = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local text = getglobal(name .. "Text")
    if text then
        text:SetText(label or "")
    end

    button:SetScript("OnClick", function()
        if onClick then
            onClick(this:GetChecked())
        end
    end)

    return button
end

function SST_SetSettingsTab(tab)
    if not SoulstoneTrackerDB then
        return
    end

    if not SST_SettingsPages[tab] then
        tab = "general"
    end

    SoulstoneTrackerDB.settingsTab = tab

    local key
    for key in pairs(SST_SettingsPages) do
        if key == tab then
            SST_SettingsPages[key]:Show()
        else
            SST_SettingsPages[key]:Hide()
        end
    end

    for key in pairs(SST_SettingsTabs) do
        if key == tab then
            SST_SettingsTabs[key]:LockHighlight()
        else
            SST_SettingsTabs[key]:UnlockHighlight()
        end
    end

    if SST_RefreshSettingsUI then
        SST_RefreshSettingsUI()
    end
end

local function SST_ToggleTrackerVisibility()
    if not SoulstoneTrackerDB then
        return
    end

    SoulstoneTrackerDB.visible = not SoulstoneTrackerDB.visible
    SST_ApplyPosition()
    SST_ApplyFrameState()

    if SoulstoneTrackerDB.visible then
        SST_Print("frame shown.")
    else
        SST_Print("frame hidden.")
    end
end

local function SST_SendTestAnnouncement()
    if not SoulstoneTrackerDB then
        return
    end

    local targetName = SST_ResolveUnitName("target") or SST_ResolveUnitName("mouseover") or SST_ResolveUnitName("player") or "Target"
    local channel = SST_ResolveAnnounceChannel(SoulstoneTrackerDB.announceChannel)
    local canSend, required = SST_CanSendToAnnounceChannel(channel)

    if not canSend then
        SST_Print("test announcement not sent: selected channel requires " .. required .. ".")
        return
    end

    local text = SST_FormatAnnouncementText(targetName)

    if SendChatMessage then
        SendChatMessage(text, channel)
    else
        SST_Print("test announcement: " .. text)
    end
end

local function SST_CreateGeneralSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    SST_CreateLabel(page, "Tracker window", 16, -12, "GameFontNormal")

    SST_SettingsControls.visibleCheck = SST_CreateCheckButton(page, "SoulstoneTrackerVisibleCheck", "Show tracker window", 16, -38, function(checked)
        SoulstoneTrackerDB.visible = checked
        SST_ApplyPosition()
        SST_ApplyFrameState()
    end)

    SST_SettingsControls.lockedCheck = SST_CreateCheckButton(page, "SoulstoneTrackerLockedCheck", "Lock tracker window", 16, -66, function(checked)
        SoulstoneTrackerDB.locked = checked
        SST_ApplyFrameState()
    end)

    SST_SettingsControls.buttonVisibleCheck = SST_CreateCheckButton(page, "SoulstoneTrackerButtonVisibleCheck", "Show launcher button", 16, -94, function(checked)
        SoulstoneTrackerDB.buttonVisible = checked
        SST_ApplyButtonState()
    end)

    SST_SettingsControls.warnFiveCheck = SST_CreateCheckButton(page, "SoulstoneTrackerWarnFiveCheck", "Warn at 5 minutes remaining", 16, -122, function(checked)
        SoulstoneTrackerDB.warnFive = checked
    end)

    SST_SettingsControls.warnOneCheck = SST_CreateCheckButton(page, "SoulstoneTrackerWarnOneCheck", "Warn at 1 minute remaining", 16, -150, function(checked)
        SoulstoneTrackerDB.warnOne = checked
    end)

    SST_SettingsControls.scaleLabel = SST_CreateLabel(page, "Scale: 1", 16, -190, "GameFontNormalSmall")

    SST_CreatePanelButton(page, "-", 32, 22, 110, -184, function()
        SoulstoneTrackerDB.scale = SST_GetSafeScale((SoulstoneTrackerDB.scale or 1) - 0.1)
        SST_ApplyFrameState()
        SST_ApplyPosition()
    end)

    SST_CreatePanelButton(page, "+", 32, 22, 148, -184, function()
        SoulstoneTrackerDB.scale = SST_GetSafeScale((SoulstoneTrackerDB.scale or 1) + 0.1)
        SST_ApplyFrameState()
        SST_ApplyPosition()
    end)

    SST_CreatePanelButton(page, "Reset tracker", 120, 22, 16, -226, function()
        SST_ResetFrame()
        SST_Print("frame reset to the screen center.")
    end)

    SST_CreatePanelButton(page, "Reset button", 120, 22, 146, -226, function()
        SST_ResetButtonPosition()
        SST_Print("launcher button reset near the minimap.")
    end)

    return page
end

local function SST_CreateNotificationSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    SST_CreateLabel(page, "Soulstone announcement", 16, -12, "GameFontNormal")

    SST_SettingsControls.announceEnabledCheck = SST_CreateCheckButton(page, "SoulstoneTrackerAnnounceEnabledCheck", "Announce when you apply Soulstone", 16, -38, function(checked)
        SoulstoneTrackerDB.announceEnabled = checked
    end)

    SST_CreateLabel(page, "Channel", 16, -82, "GameFontNormalSmall")
    SST_SettingsControls.channelLabel = SST_CreateLabel(page, "Smart: Raid > Party > Say", 92, -82, "GameFontHighlightSmall")

    SST_CreatePanelButton(page, "Previous", 80, 22, 16, -108, function()
        SST_SetAnnounceChannelByDelta(-1)
    end)

    SST_CreatePanelButton(page, "Next", 80, 22, 104, -108, function()
        SST_SetAnnounceChannelByDelta(1)
    end)

    SST_CreateLabel(page, "Message", 16, -154, "GameFontNormalSmall")

    local edit = CreateFrame("EditBox", "SoulstoneTrackerAnnounceMessageEditBox", page, "InputBoxTemplate")
    edit:SetWidth(380)
    edit:SetHeight(24)
    edit:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -176)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(180)
    edit:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function()
        this:ClearFocus()
    end)
    edit:SetScript("OnTextChanged", function()
        if SST_SettingsControls.refreshing then
            return
        end

        if SoulstoneTrackerDB then
            SoulstoneTrackerDB.announceMessage = this:GetText()
        end
    end)
    SST_SettingsControls.announceMessageEdit = edit

    SST_CreateLabel(page, "Placeholders: {target}, {name}, {player}, {duration}", 16, -212, "GameFontHighlightSmall")

    SST_CreatePanelButton(page, "Default text", 110, 22, 16, -244, function()
        SoulstoneTrackerDB.announceMessage = SST_DEFAULT_ANNOUNCE_MESSAGE
        if SST_RefreshSettingsUI then
            SST_RefreshSettingsUI()
        end
    end)

    SST_CreatePanelButton(page, "Send test", 110, 22, 136, -244, function()
        SST_SendTestAnnouncement()
    end)

    return page
end

local function SST_CreateDebugSettingsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    SST_CreateLabel(page, "Status and diagnostics", 16, -12, "GameFontNormal")
    SST_SettingsControls.debugStatusLabel = SST_CreateLabel(page, "", 16, -42, "GameFontHighlightSmall")
    SST_SettingsControls.debugPositionLabel = SST_CreateLabel(page, "", 16, -64, "GameFontHighlightSmall")
    SST_SettingsControls.debugSuperWowLabel = SST_CreateLabel(page, "", 16, -86, "GameFontHighlightSmall")

    SST_CreatePanelButton(page, "Print status", 110, 22, 16, -126, function()
        if SoulstoneTrackerDB and SoulstoneTrackerDB.record then
            local remaining = SoulstoneTrackerDB.record.expiresAt - SST_Now()
            SST_Print("active: " .. (SoulstoneTrackerDB.record.name or "unknown target") .. ", remaining " .. SST_FormatTime(remaining) .. ".")
        else
            SST_Print("no active tracked soulstone.")
        end
    end)

    SST_CreatePanelButton(page, "Clear tracker", 110, 22, 136, -126, function()
        SST_ClearRecord("tracking cleared.")
        SST_UpdateText()
        if SST_RefreshSettingsUI then
            SST_RefreshSettingsUI()
        end
    end)

    SST_CreatePanelButton(page, "Print position", 110, 22, 256, -126, function()
        local canvasWidth, canvasHeight = SST_GetCanvasSize()
        SST_Print("tracker x=" .. (SoulstoneTrackerDB.x or "nil") .. ", y=" .. (SoulstoneTrackerDB.y or "nil") .. ", scale=" .. (SoulstoneTrackerDB.scale or "nil") .. ".")
        SST_Print("button x=" .. (SoulstoneTrackerDB.buttonX or "nil") .. ", y=" .. (SoulstoneTrackerDB.buttonY or "nil") .. ", canvas=" .. canvasWidth .. "x" .. canvasHeight .. ".")
    end)

    SST_CreateLabel(page, "Command aliases: /sst options, /sst config, /sst button reset, /sst announce test", 16, -174, "GameFontHighlightSmall")

    return page
end

function SST_RefreshSettingsUI()
    if not SoulstoneTrackerDB or not SST_SettingsFrame then
        return
    end

    SST_SettingsControls.refreshing = true

    if SST_SettingsControls.visibleCheck then
        SST_SettingsControls.visibleCheck:SetChecked(SoulstoneTrackerDB.visible)
    end

    if SST_SettingsControls.lockedCheck then
        SST_SettingsControls.lockedCheck:SetChecked(SoulstoneTrackerDB.locked)
    end

    if SST_SettingsControls.buttonVisibleCheck then
        SST_SettingsControls.buttonVisibleCheck:SetChecked(SoulstoneTrackerDB.buttonVisible)
    end

    if SST_SettingsControls.warnFiveCheck then
        SST_SettingsControls.warnFiveCheck:SetChecked(SoulstoneTrackerDB.warnFive)
    end

    if SST_SettingsControls.warnOneCheck then
        SST_SettingsControls.warnOneCheck:SetChecked(SoulstoneTrackerDB.warnOne)
    end

    if SST_SettingsControls.scaleLabel then
        SST_SettingsControls.scaleLabel:SetText("Scale: " .. (SoulstoneTrackerDB.scale or 1))
    end

    if SST_SettingsControls.announceEnabledCheck then
        SST_SettingsControls.announceEnabledCheck:SetChecked(SoulstoneTrackerDB.announceEnabled)
    end

    if SST_SettingsControls.channelLabel then
        local resolved = SST_ResolveAnnounceChannel(SoulstoneTrackerDB.announceChannel)
        local label = SST_GetAnnounceChannelLabel(SoulstoneTrackerDB.announceChannel)
        if SoulstoneTrackerDB.announceChannel == "SMART" then
            label = label .. " (current: " .. resolved .. ")"
        end
        SST_SettingsControls.channelLabel:SetText(label)
    end

    if SST_SettingsControls.announceMessageEdit then
        local hasFocus = false
        if SST_SettingsControls.announceMessageEdit.HasFocus then
            hasFocus = SST_SettingsControls.announceMessageEdit:HasFocus()
        end

        if not hasFocus then
            SST_SettingsControls.announceMessageEdit:SetText(SoulstoneTrackerDB.announceMessage or SST_DEFAULT_ANNOUNCE_MESSAGE)
        end
    end

    if SST_SettingsControls.debugStatusLabel then
        if SoulstoneTrackerDB.record then
            local remaining = SoulstoneTrackerDB.record.expiresAt - SST_Now()
            SST_SettingsControls.debugStatusLabel:SetText("Tracked: " .. (SoulstoneTrackerDB.record.name or "unknown target") .. ", remaining " .. SST_FormatTime(remaining))
        else
            SST_SettingsControls.debugStatusLabel:SetText("Tracked: none")
        end
    end

    if SST_SettingsControls.debugPositionLabel then
        SST_SettingsControls.debugPositionLabel:SetText("Tracker: x=" .. (SoulstoneTrackerDB.x or "nil") .. ", y=" .. (SoulstoneTrackerDB.y or "nil") .. ", scale=" .. (SoulstoneTrackerDB.scale or "nil") .. "; Button: x=" .. (SoulstoneTrackerDB.buttonX or "nil") .. ", y=" .. (SoulstoneTrackerDB.buttonY or "nil"))
    end

    if SST_SettingsControls.debugSuperWowLabel then
        if SST_IsSuperWoWAvailable() then
            SST_SettingsControls.debugSuperWowLabel:SetText("SuperWoW: detected")
        else
            SST_SettingsControls.debugSuperWowLabel:SetText("SuperWoW: not detected; target tracking is approximate")
        end
    end

    SST_SettingsControls.refreshing = false
end

local function SST_CreateSettingsFrame()
    if SST_SettingsFrame then
        return
    end

    local frame = CreateFrame("Frame", "SoulstoneTrackerSettingsFrame", UIParent)
    SST_SettingsFrame = frame
    frame:SetWidth(SST_SETTINGS_WIDTH)
    frame:SetHeight(SST_SETTINGS_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    SST_SettingsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    SST_SettingsTitle:SetPoint("TOP", frame, "TOP", 0, -16)
    SST_SettingsTitle:SetText("SoulstoneTracker Settings")

    local close = CreateFrame("Button", "SoulstoneTrackerSettingsCloseButton", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    local tabGeneral = SST_CreatePanelButton(frame, "General", 92, 22, 18, -46, function()
        SST_SetSettingsTab("general")
    end)
    local tabNotifications = SST_CreatePanelButton(frame, "Notifications", 112, 22, 114, -46, function()
        SST_SetSettingsTab("notifications")
    end)
    --local tabDebug = SST_CreatePanelButton(frame, "Debug", 92, 22, 230, -46, function()
    --    SST_SetSettingsTab("debug")
    --end)

    SST_SettingsTabs.general = tabGeneral
    SST_SettingsTabs.notifications = tabNotifications
    --SST_SettingsTabs.debug = tabDebug

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -78)
    content:SetWidth(SST_SETTINGS_WIDTH - 44)
    content:SetHeight(SST_SETTINGS_HEIGHT - 100)

    SST_SettingsPages.general = SST_CreateGeneralSettingsPage(content)
    SST_SettingsPages.notifications = SST_CreateNotificationSettingsPage(content)
    --SST_SettingsPages.debug = SST_CreateDebugSettingsPage(content)

    frame:Hide()
end

function SST_ToggleSettingsFrame(forceShow)
    if not SST_SettingsFrame then
        return
    end

    if forceShow or not SST_SettingsFrame:IsVisible() then
        SST_SettingsFrame:Show()
        SST_SetSettingsTab(SoulstoneTrackerDB and SoulstoneTrackerDB.settingsTab or "general")
        SST_RefreshSettingsUI()
    else
        SST_SettingsFrame:Hide()
    end
end

local function SST_CreateMinimapButton()
    if SST_MinimapButton then
        return
    end

    local button = CreateFrame("Button", "SoulstoneTrackerLauncherButton", UIParent)
    SST_MinimapButton = button
    button:SetWidth(SST_BUTTON_SIZE)
    button:SetHeight(SST_BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    if button.SetFrameLevel then
        button:SetFrameLevel(80)
    end
    button:EnableMouse(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    SST_MinimapButtonIcon = icon
    icon:SetTexture(SST_SOULSTONE_TEXTURE)
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    if icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetWidth(32)
    highlight:SetHeight(32)
    highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    highlight:SetBlendMode("ADD")

    button:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            SST_StartButtonDrag()
        end
    end)

    button:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" then
            local moved = SST_StopButtonDrag()
            if not moved then
                SST_ToggleSettingsFrame(true)
            end
        elseif arg1 == "RightButton" then
            SST_StopButtonDrag()
            SST_ToggleTrackerVisibility()
        end
    end)

    button:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine("SoulstoneTracker")
            GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
            GameTooltip:AddLine("Right-click: show/hide tracker", 1, 1, 1)
            GameTooltip:AddLine("Drag: move button", 1, 1, 1)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function SST_OnUpdate()
    SST_UpdateDrag()
    SST_UpdateButtonDrag()

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
    SST_Frame:SetFrameStrata("LOW")
    if SST_Frame.SetFrameLevel then
        SST_Frame:SetFrameLevel(20)
    end
    if SST_Frame.SetToplevel then
        SST_Frame:SetToplevel(false)
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

    SST_CoreFrame:SetScript("OnEvent", SST_OnEvent)
    SST_CoreFrame:SetScript("OnUpdate", SST_OnUpdate)

    SST_CoreFrame:RegisterEvent("ADDON_LOADED")
    SST_CoreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    SST_CoreFrame:RegisterEvent("SPELLCAST_START")
    SST_CoreFrame:RegisterEvent("SPELLCAST_STOP")
    SST_CoreFrame:RegisterEvent("SPELLCAST_FAILED")
    SST_CoreFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
    SST_CoreFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    SST_CoreFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    SST_CoreFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    SST_CoreFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

    if SST_IsSuperWoWAvailable() then
        SST_CoreFrame:RegisterEvent("UNIT_CASTEVENT")
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
    SST_Print("commands: /sst options, /sst status, /sst clear, /sst lock, /sst unlock, /sst show, /sst hide, /sst reset, /sst scale <value>, /sst pos, /sst button reset, /sst announce on|off|test|channel <name>|text <message>")
end

local function SST_SlashHandler(message)
    local msg = SST_NormalizeSlashCommand(message)

    if msg == "" or msg == "help" then
        SST_PrintHelp()
        return
    end

    if msg == "options" or msg == "config" or msg == "settings" then
        SST_ToggleSettingsFrame(true)
        return
    end

    if msg == "button reset" or msg == "button center" then
        SST_ResetButtonPosition()
        SST_Print("launcher button reset near the minimap.")
        return
    end

    if msg == "button show" then
        SoulstoneTrackerDB.buttonVisible = true
        SST_ApplyButtonState()
        SST_Print("launcher button shown.")
        return
    end

    if msg == "button hide" then
        SoulstoneTrackerDB.buttonVisible = false
        SST_ApplyButtonState()
        SST_Print("launcher button hidden. Use /sst button show to restore it.")
        return
    end

    if msg == "announce on" then
        SoulstoneTrackerDB.announceEnabled = true
        if SST_RefreshSettingsUI then
            SST_RefreshSettingsUI()
        end
        SST_Print("announcements enabled.")
        return
    end

    if msg == "announce off" then
        SoulstoneTrackerDB.announceEnabled = false
        if SST_RefreshSettingsUI then
            SST_RefreshSettingsUI()
        end
        SST_Print("announcements disabled.")
        return
    end

    if msg == "announce test" then
        SST_SendTestAnnouncement()
        return
    end

    local _, _, announceChannel = string.find(msg, "^announce%s+channel%s+([%a_]+)$")
    if announceChannel then
        if SST_SetAnnounceChannel(announceChannel) then
            SST_Print("announcement channel set to " .. SST_GetAnnounceChannelLabel(SoulstoneTrackerDB.announceChannel) .. ".")
        else
            SST_Print("unknown announcement channel. Use SMART, SAY, PARTY, RAID, GUILD, YELL, or EMOTE.")
        end
        return
    end

    local _, _, announceText = string.find(message or "", "^announce%s+text%s+(.+)$")
    if announceText then
        SoulstoneTrackerDB.announceMessage = announceText
        if SST_RefreshSettingsUI then
            SST_RefreshSettingsUI()
        end
        SST_Print("announcement text updated.")
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
SST_CreateSettingsFrame()
SST_CreateMinimapButton()
SST_HookSpellTargetUnit()

SLASH_SOULSTONETRACKER1 = "/sst"
SLASH_SOULSTONETRACKER2 = "/soulstone"
SlashCmdList["SOULSTONETRACKER"] = SST_SlashHandler
