---------------------------------------------------------------------------
-- Guild names on 3.3.5a plate anchors. Keep unit reaction/health data and
-- addon scripts intact; reversible overlays supply a shared visual style.
---------------------------------------------------------------------------
local GVE = _G.GVE
local Map = GVE and GVE.GuildMap
if not Map then return end
local GREEN = {0.4, 1, 0.2}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function Settings()
    return type(GVESyncData) == "table" and GVESyncData.settings
end
local function Key(name)
    if type(name) ~= "string" then return end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^([^%-]+)")
    return name and name:lower()
end
local function Visible(region)
    return region and region.IsShown and region:IsShown()
        and (not region.GetAlpha or region:GetAlpha() > 0)
        and (not region.GetEffectiveAlpha or region:GetEffectiveAlpha() > 0)
end
local function IsLabel(region)
    return region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString"
end
local function HasAdapter(frame)
    -- Generic fields such as UnitFrame/extended also occur on unrelated UI
    -- frames. They are not sufficient evidence of a nameplate replacement.
    return frame.UnitFrame and IsLabel(frame.UnitFrame.Name) and frame.UnitFrame.oldHealthBar
        or frame.extended and frame.extended.visual and IsLabel(frame.extended.visual.name)
            and frame.extended.regions and IsLabel(frame.extended.regions.name)
        or frame.VirtualPlate and IsLabel(frame.VirtualPlate.RBP_nameText)
        or frame.RealPlate and IsLabel(frame.RBP_nameText)
end
local function ForeignActive()
    -- ElvUI may be loaded with its nameplate module disabled.
    local E = _G.ElvUI and _G.ElvUI[1]
    if E and E.private and E.private.nameplates and E.private.nameplates.enable then return true end
    if type(IsAddOnLoaded) == "function" then
        for _, addon in ipairs({"TidyPlates", "!!RefinedBlizzPlates", "RefinedBlizzPlates",
            "NotPlater", "ShaguPlates", "pfUI", "BetterNameplates", "BetterNamePlates",
            "BetterBlizzPlates", "Aloft", "Kui_Nameplates", "Plater"}) do
            if IsAddOnLoaded(addon) then return true end
        end
    end
    if WorldFrame then
        for _, frame in ipairs({WorldFrame:GetChildren()}) do
            if HasAdapter(frame) then return true end
        end
    end
    return false
end

-- Return the visible label and authoritative plain name separately: addons
-- can abbreviate their displayed names. Never guess from a healthbar label.
local function Resolve(frame, foreignActive)
    if frame.UnitFrame and IsLabel(frame.UnitFrame.Name) then
        local owner = frame.UnitFrame
        return owner, owner.Name, owner.UnitName or (owner.oldName and owner.oldName:GetText()), true
    end
    if frame.extended and frame.extended.visual and IsLabel(frame.extended.visual.name) then
        local owner = frame.extended
        return owner, owner.visual and owner.visual.name, owner.unit and owner.unit.name, true
    end
    local virtual = frame.VirtualPlate or (frame.RealPlate and frame)
    if virtual and (IsLabel(virtual.RBP_nameText) or IsLabel(virtual.RBP_barlessPlate_nameText)) then
        local name = virtual.RBP_barlessPlateIsShown and virtual.RBP_barlessPlate_nameText or virtual.RBP_nameText
        return virtual, name, virtual.RBP_nameString, true
    end
    if frame:GetName() then return end
    local regions = {frame:GetRegions()}
    local plate = false
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "Texture" then
            local texture = region:GetTexture()
            if texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash"
                or texture == "Interface\\Tooltips\\Nameplate-Border" then plate = true end
        end
    end
    local name = regions[7]
    if plate and name and name:GetObjectType() == "FontString" then
        if foreignActive then
            -- Generic fallback for skinning addons retaining the stock plate.
            -- Only accept an exact name match, never arbitrary health text.
            local plain = name:GetText()
            local previous = Map.plates[frame]
            local function FindLabel(parent, depth)
                for _, region in ipairs({parent:GetRegions()}) do
                    if IsLabel(region) and (Visible(region) or previous and previous.hidden and previous.hidden[region] ~= nil)
                        and Key(region:GetText()) == Key(plain) then
                        return region
                    end
                end
                if depth > 0 then
                    for _, child in ipairs({parent:GetChildren()}) do
                        if not child.GVEGuildMarker then
                            local found = FindLabel(child, depth-1)
                            if found then return found end
                        end
                    end
                end
            end
            return frame, FindLabel(frame, 2) or name, plain, "generic"
        end
        return frame, name, name:GetText(), false
    end
end

function Map:MarkerDiagnostics()
    local settings = Settings() or {}
    local children = WorldFrame and {WorldFrame:GetChildren()} or {}
    local foreignActive = ForeignActive()
    local recognised, visible, members, shown = 0,0,0,0
    for _, frame in ipairs(children) do
        local owner, name, plain = Resolve(frame, foreignActive)
        if owner and name then
            recognised = recognised+1
            if Visible(frame) and Visible(owner) then visible=visible+1 end
            if self.members[Key(plain) or ""] then members=members+1 end
        end
    end
    for _, data in pairs(self.plates) do if data.marker:IsShown() then shown=shown+1 end end
    local function Print(line)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("GVE markers: "..line) end
    end
    Print("enabled="..tostring(settings.guildNearbyEnabled)..", style="..tostring(settings.guildMarkerStyle)
        ..", revision="..tostring(settings.guildMarkerRevision)..", visualFriends="..tostring(settings.guildFriendlyPrevious)
        ..", visualEnemies="..tostring(settings.guildEnemyPrevious)..", inGuild="..tostring(self.inGuild)..", external="..tostring(not not foreignActive))
    Print("friends="..tostring(GetCVar("nameplateShowFriends"))..", enemies="..tostring(GetCVar("nameplateShowEnemies"))
        ..", worldFrames="..#children..", recognised="..recognised..", visible="..visible..", guildMatches="..members..", markers="..shown)
    if type(IsAddOnLoaded) == "function" then
        local loaded = {}
        for _, addon in ipairs({"ElvUI","TidyPlates","!!RefinedBlizzPlates","RefinedBlizzPlates",
            "NotPlater","ShaguPlates","pfUI","BetterNameplates","BetterNamePlates","BetterBlizzPlates","Aloft","Kui_Nameplates","Plater"}) do
            if IsAddOnLoaded(addon) then loaded[#loaded+1]=addon end
        end
        Print("addons="..(#loaded>0 and table.concat(loaded,", ") or "none detected"))
    end
end

local function Restore(data)
    for region, alpha in pairs(data.hidden or {}) do region:SetAlpha(alpha) end
    data.hidden = nil
    data.marker:Hide()
end
local function HideRegion(data, region)
    if not region or not region.SetAlpha or not region.GetAlpha then return end
    data.hidden = data.hidden or {}
    if data.hidden[region] == nil then data.hidden[region] = region:GetAlpha() end
    region:SetAlpha(0)
end
local function NewMarker(owner, visualOwner)
    local marker = CreateFrame("Frame", nil, owner)
    marker:SetWidth(1); marker:SetHeight(1)
    marker:SetFrameLevel(math.max(owner:GetFrameLevel(), visualOwner and visualOwner:GetFrameLevel() or 0)+10)
    marker:EnableMouse(false)
    marker.GVEGuildMarker = true
    local badge = CreateFrame("Frame", nil, marker)
    badge:SetWidth(20); badge:SetHeight(20); badge:EnableMouse(false)
    badge:SetBackdrop({bgFile=WHITE, edgeFile=WHITE, edgeSize=2})
    badge:SetBackdropColor(0, 0, 0, 0.95)
    badge:SetBackdropBorderColor(unpack(GREEN))
    local letter = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    letter:SetAllPoints(badge); letter:SetText("G"); letter:SetTextColor(unpack(GREEN))
    local name = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    local font = name:GetFont()
    name:SetFont(font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "THICKOUTLINE")
    name:SetShadowColor(0, 0, 0, 1); name:SetShadowOffset(1, -1)
    local guild = marker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guild:SetTextColor(0.35, 0.85, 0.25)
    guild:SetShadowColor(0, 0, 0, 1); guild:SetShadowOffset(1, -1)
    marker.badge, marker.label, marker.guild = badge, name, guild
    marker:Hide()
    return marker
end

function Map:ClearMarkers()
    for _, data in pairs(self.plates) do Restore(data) end
end

-- GVE needs both friendly and hostile engine anchors, including cross-faction
-- guilds. These are global CVars; restore saved values when disabled. Do not
-- alter any addon's saved profile or its combat/style-filter scripts.
function Map:MaintainMarkerAnchors()
    local settings = Settings()
    if not settings then return end
    local active = settings.guildNearbyEnabled and self.inGuild
    for _, entry in ipairs({{"nameplateShowFriends", "guildFriendlyPrevious"},
        {"nameplateShowEnemies", "guildEnemyPrevious"}}) do
        local cvar, saved = entry[1], entry[2]
        if active then
            if settings[saved] == nil then settings[saved] = GetCVar(cvar) or "0" end
            if GetCVar(cvar) ~= "1" then
                self.settingMarkerCvars = true; SetCVar(cvar, "1"); self.settingMarkerCvars = nil
            end
        elseif settings[saved] ~= nil then
            if GetCVar(cvar) == "1" then
                self.settingMarkerCvars = true; SetCVar(cvar, settings[saved]); self.settingMarkerCvars = nil
            end
            settings[saved] = nil
        end
    end
end

function Map:SetPlatePreference(side, enabled)
    local settings = Settings()
    if not settings then return end
    local saved = side == "friends" and "guildFriendlyPrevious" or "guildEnemyPrevious"
    settings[saved] = enabled and "1" or "0"
    settings.guildMarkerStyle = "auto"
end

function Map:TogglePlatePreference(binding)
    local settings = Settings()
    if not settings then return end
    local friends = settings.guildFriendlyPrevious == "1"
    local enemies = settings.guildEnemyPrevious == "1"
    -- Same intent as the stock 3.3.5a bindings, but use visual preferences,
    -- not the engine CVars which GVE retains as moving screen anchors.
    if binding == "NAMEPLATES" then
        self:SetPlatePreference("enemies", not (enemies and not friends))
        if not (enemies and not friends) then self:SetPlatePreference("friends", false) end
    elseif binding == "FRIENDNAMEPLATES" then
        self:SetPlatePreference("friends", not (friends and not enemies))
        if not (friends and not enemies) then self:SetPlatePreference("enemies", false) end
    elseif binding == "ALLNAMEPLATES" then
        self:SetPlatePreference("friends", not friends and not enemies)
        self:SetPlatePreference("enemies", not friends and not enemies)
    end
    self:UpdateNameplates()
end

function Map:UpdateMarkerBindings()
    if type(SetOverrideBindingClick) ~= "function" or type(GetBindingKey) ~= "function"
        or type(ClearOverrideBindings) ~= "function" then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then self.markerBindingsPending=true; return end
    if not self.markerBindingOwner then self.markerBindingOwner = CreateFrame("Frame") end
    ClearOverrideBindings(self.markerBindingOwner)
    self.markerBindingsPending = nil
    local settings = Settings()
    if not settings or not settings.guildNearbyEnabled or not self.inGuild then return end
    self.markerButtons = self.markerButtons or {}
    for _, binding in ipairs({"NAMEPLATES", "FRIENDNAMEPLATES", "ALLNAMEPLATES"}) do
        local button = self.markerButtons[binding]
        if not button then
            button = CreateFrame("Button", "GVEGuildMarkerToggle"..binding, UIParent)
            button:RegisterForClicks("AnyUp")
            button:SetScript("OnClick", function() Map:TogglePlatePreference(binding) end)
            self.markerButtons[binding] = button
        end
        for _, key in ipairs({GetBindingKey(binding)}) do
            SetOverrideBindingClick(self.markerBindingOwner, false, key, button:GetName(), "LeftButton")
        end
    end
end

local function Friendly(frame, owner)
    if owner.UnitType then return owner.UnitType:find("^FRIENDLY") ~= nil end
    if owner.RBP_isFriendly ~= nil then return owner.RBP_isFriendly end
    if owner.unit and owner.unit.reaction then
        local reaction = owner.unit.reaction
        if type(reaction) == "string" then return reaction == "FRIENDLY" end
    end
    local health = owner.oldHealthBar or (owner.bars and owner.bars.health) or frame:GetChildren()
    if health and health.GetStatusBarColor then
        local r,g,b = health:GetStatusBarColor()
        return r < .01 and (g < .01 and b > .99 or g > .99 and b < .01)
    end
    return false
end

local function Barless(settings, friendly)
    if settings.guildMarkerStyle == "names" then return true end
    if settings.guildMarkerStyle == "plates" then return false end
    return settings[friendly and "guildFriendlyPrevious" or "guildEnemyPrevious"] == "0"
end

local function HideBars(data, frame, owner, foreign)
    if not foreign then
        local regions = {frame:GetRegions()}
        for i=1,8 do HideRegion(data, regions[i]) end
        for _, child in ipairs({frame:GetChildren()}) do
            if not child.GVEGuildMarker then HideRegion(data, child) end
        end
    elseif frame.UnitFrame == owner then
        -- ElvUI Name may itself be parented to Health; our overlay isn't.
        for _, field in ipairs({"Health", "CutawayHealth", "CastBar", "Level", "Name"}) do
            HideRegion(data, owner[field])
        end
    elseif frame.extended == owner then
        for _, field in ipairs({"healthbar", "castbar"}) do HideRegion(data, owner.bars and owner.bars[field]) end
        for _, field in ipairs({"healthborder", "threatborder", "level", "spelltext", "customtext"}) do
            HideRegion(data, owner.visual and owner.visual[field])
        end
    elseif owner.RBP_nameText or owner.RBP_barlessPlate_nameText then
        for _, field in ipairs({"RBP_healthBar", "RBP_castBar", "RBP_healthBarBorder", "RBP_levelText",
            "RBP_healthText", "RBP_barlessPlate_healthText", "RBP_nameText", "RBP_barlessPlate_nameText"}) do
            HideRegion(data, owner[field])
        end
    else
        -- Unknown skins: only hide verified status bars, not entire UI trees.
        local function Bars(parent, depth)
            for _, child in ipairs({parent:GetChildren()}) do
                if not child.GVEGuildMarker then
                    if child:GetObjectType() == "StatusBar" then HideRegion(data, child) end
                    if depth > 0 then Bars(child, depth-1) end
                end
            end
        end
        Bars(frame, 2)
    end
end

function Map:UpdateNameplates()
    local settings = Settings()
    if not WorldFrame or not settings then return end
    self:MaintainMarkerAnchors()
    local seen = {}
    local foreignActive = ForeignActive()
    for _, frame in ipairs({WorldFrame:GetChildren()}) do
        local owner, name, plain, foreign = Resolve(frame, foreignActive)
        local data = self.plates[frame]
        -- A late-loading addon may take over a previously native plate.
        if data and (data.owner ~= owner or data.name ~= name or data.foreign ~= foreign) then
            Restore(data); self.plates[frame] = nil; data = nil
        end
        local key = Key(plain)
        local eligible = self.inGuild and settings.guildNearbyEnabled and Visible(frame)
            and owner and name and key and self.members[key] and key ~= Key(UnitName("player"))
        local suppress = not eligible and self.inGuild and settings.guildNearbyEnabled and Visible(frame)
            and owner and name and Barless(settings, Friendly(frame, owner))
        if eligible then
            if not data then
                -- Parent to the engine frame, not an addon health/name frame
                -- that may be hidden by a friendly-name or barless setting.
                local parent = frame.RealPlate or frame
                data = {owner=owner, name=name, foreign=foreign, marker=NewMarker(parent, owner)}
                self.plates[frame] = data
            end
            seen[frame] = true
            if data.key ~= key then Restore(data); data.key = key end
            data.suppressed = nil
            local marker = data.marker
            marker:ClearAllPoints(); marker:SetPoint("CENTER", name, "CENTER")
            marker.badge:ClearAllPoints()
                local barless = Barless(settings, Friendly(frame, owner))
                if data.barless ~= barless then Restore(data); data.barless = barless end
                if barless then HideBars(data, frame, owner, foreign) end
                HideRegion(data, name)
                marker.label:SetText(self.members[key].name)
                marker.label:SetTextColor(unpack(GREEN))
                marker.label:ClearAllPoints(); marker.label:SetPoint("CENTER", name, "CENTER", 0, barless and 0 or 14)
                marker.label:Show()
                marker.badge:SetPoint("RIGHT", marker.label, "LEFT", -5, 0)
                marker.guild:ClearAllPoints(); marker.guild:SetPoint("TOP", marker.label, "BOTTOM", 0, -2)
                local guildName = GetGuildInfo("player")
                marker.guild:SetText(guildName and "<"..guildName..">" or "")
                marker.guild:Show()
            marker:Show()
        elseif suppress then
            if not data then
                data = {owner=owner, name=name, foreign=foreign, marker=NewMarker(frame.RealPlate or frame, owner)}
                self.plates[frame] = data
            end
            seen[frame] = true
            if not data.suppressed then Restore(data) end
            data.suppressed, data.key = true, nil
            -- Anchors are global. Keep non-guild plate visuals off on the
            -- side the user disabled rather than revealing every NPC/bar.
            for _, region in ipairs({owner:GetRegions()}) do HideRegion(data, region) end
            for _, child in ipairs({owner:GetChildren()}) do
                if not child.GVEGuildMarker then HideRegion(data, child) end
            end
            HideRegion(data, name)
            HideBars(data, frame, owner, foreign)
            data.marker:Hide()
        elseif data then Restore(data); data.key = nil; data.suppressed=nil end
    end
    for frame, data in pairs(self.plates) do
        if not seen[frame] then Restore(data) end
    end
end

function Map:EnableNearby(enabled)
    local settings = Settings()
    if not settings then return end
    settings.guildNearbyEnabled = enabled
    if settings.guildMarkerRevision ~= 4 then
        settings.guildMarkerStyle = "auto"
        settings.guildMarkerRevision = 4
    end
    self:CheckGuild()
    self:UpdateNameplates()
    self:UpdateMarkerBindings()
end

-- Settings UI and third-party addons normally write these through SetCVar.
-- Observe their intent without replacing the API or any addon's functions.
if type(hooksecurefunc) == "function" then
    hooksecurefunc("SetCVar", function(cvar, value)
        local settings = Settings()
        if Map.settingMarkerCvars or not settings or not settings.guildNearbyEnabled or not Map.inGuild then return end
        cvar = type(cvar) == "string" and cvar:lower()
        if cvar == "nameplateshowfriends" or cvar == "nameplateshowenemies" then
            Map:SetPlatePreference(cvar == "nameplateshowfriends" and "friends" or "enemies",
                value == true or tonumber(value) == 1)
        end
    end)
end
local bindingEvents = CreateFrame("Frame")
for _, event in ipairs({"UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "PLAYER_GUILD_UPDATE"}) do bindingEvents:RegisterEvent(event) end
bindingEvents:SetScript("OnEvent", function() Map:CheckGuild(); Map:UpdateMarkerBindings() end)
