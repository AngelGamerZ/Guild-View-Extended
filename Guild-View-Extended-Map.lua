---------------------------------------------------------------------------
-- Guild map / nearby markers, WoW 3.3.5a. Positions are live and never saved.
---------------------------------------------------------------------------
local GVE = _G.GVE
if not GVE then return end
local Map = {peers={}, members={}, plates={}, pinPool={}, tick=0, sendElapsed=0, sampleElapsed=0}
GVE.GuildMap = Map
local PREFIX, INTERVAL, TTL, MAX_PEERS = "GVEM1", 3, 18, 300
local de = GetLocale() == "deDE"
local L = de and {guild="Gilde", nearby="Gildenmitglieder in der Nähe", enabled="Gildenkarte aktiviert.",
    disabled="Gildenkarte deaktiviert.", nearOn="Gilden-Markierungen aktiviert. Plaketten an: Balken bleiben; Plaketten aus: nur Gildenname + G.",
    nearOff="Nähe-Markierungen deaktiviert.", names="Gildenmitglieder: nur Namen + G.", auto="Gildenmarkierungen folgen den Plaketten-Tasten/Einstellungen.",
    plates="Gildenmitglieder: Namen + G mit vorhandenen Balken.", help="/gvemap on | off | nearby on | nearby off | auto | names | plates | debug"}
    or {guild="Guild", nearby="Nearby guild members", enabled="Guild map enabled.", disabled="Guild map disabled.",
    nearOn="Guild markers enabled. Plates on: keep bars; plates off: guild names + G only.", nearOff="Nearby markers disabled.",
    names="Guild members: names + G only.", plates="Guild members: names + G with existing bars.", auto="Guild markers follow plate keys/settings.",
    help="/gvemap on | off | nearby on | nearby off | auto | names | plates | debug"}

local function Key(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^([^%-]+)")
    return name and name ~= "" and name:lower() or nil
end
local function Integer(n, lo, hi)
    return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end
local function Coordinate(n)
    return type(n) == "number" and n == n and n >= 0 and n <= 1
end
local function Settings()
    if type(GVESyncData) ~= "table" then return nil end
    GVESyncData.settings = type(GVESyncData.settings) == "table" and GVESyncData.settings or {}
    local settings = GVESyncData.settings
    if settings.guildMapEnabled == nil then settings.guildMapEnabled = true end
    if settings.guildNearbyEnabled == nil then settings.guildNearbyEnabled = true end
    return settings
end
local function Say(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33dd66GVE:|r "..message) end
end

-- Map dimensions/offsets are in yards. Convert any supported zone into its
-- continent's coordinate space; minimap distances work across zone borders.
function Map:ToContinent(p)
    local c = GVE.GuildMapData and GVE.GuildMapData[p.continent]
    if c and p.map == "CONTINENT" then return p.x*c.width, p.y*c.height end
    local zone = c and c.zoneData[p.map]
    if not zone then return nil end
    return p.x * zone.width + zone.xOffset, p.y * zone.height + zone.yOffset
end

function Map:Project(p, continent, map)
    if p.continent ~= continent and continent ~= 0 then return nil end
    local x, y = self:ToContinent(p)
    local c = GVE.GuildMapData and GVE.GuildMapData[continent]
    if not x or not c then return nil end
    if continent == 0 then
        local source = GVE.GuildMapData[p.continent]
        if source.parentContinent ~= 0 then return nil end
        return (x+source.xOffset)/c.width, (y+source.yOffset)/c.height
    end
    if map then
        local zone = c.zoneData[map]
        if not zone then return nil end
        return (x-zone.xOffset)/zone.width, (y-zone.yOffset)/zone.height
    end
    return x/c.width, y/c.height
end

function Map:RefreshMembers()
    local members = {}
    for _, member in ipairs(GVE:GetMembers() or {}) do
        local key = Key(member.name)
        if key then members[key] = member end
    end
    self.members = members
end

function Map:ReleasePeer(key)
    local peer = self.peers[key]
    if not peer then return end
    if peer.pins then
        peer.pins.world:Hide(); peer.pins.mini:Hide()
        peer.pins.world.peer, peer.pins.mini.peer = nil, nil
        self.pinPool[#self.pinPool+1] = peer.pins
    end
    self.peers[key] = nil
end

function Map:Clear()
    local keys = {}
    for key in pairs(self.peers) do keys[#keys+1] = key end
    for _, key in ipairs(keys) do self:ReleasePeer(key) end
    self.position = nil
    if self.nearby then self.nearby:Hide() end
    if self.ClearMarkers then self:ClearMarkers() end
end

function Map:CheckGuild()
    local guild = GetGuildInfo("player")
    if not guild or guild == "" then
        if type(IsInGuild) == "function" and IsInGuild() then return false end
        guild = ""
    end
    local scope = (GetRealmName() or "").."\031"..guild
    if scope ~= self.scope then self:Clear(); self.scope = scope end
    self.inGuild = guild ~= ""
    return self.inGuild
end

function Map:Receive(prefix, message, channel, sender)
    local settings = Settings()
    if prefix ~= PREFIX or channel ~= "GUILD" or not settings or not settings.guildMapEnabled
    or type(message) ~= "string" or #message > 100 or not self:CheckGuild() then return end
    local key = Key(sender)
    if not key or key == Key(UnitName("player")) or not self.members[key] then return end
    if message == "X" then self:ReleasePeer(key); return end
    local c, map, floor, x, y = message:match("^P|(%d+)|([%a%d_]+)|(%d+)|([%d%.]+)|([%d%.]+)$")
    c, floor, x, y = tonumber(c), tonumber(floor), tonumber(x), tonumber(y)
    local continent = c and GVE.GuildMapData and GVE.GuildMapData[c]
    if not Integer(c, 1, 4) or not Integer(floor, 0, 20) or not Coordinate(x) or not Coordinate(y)
    or not continent or map ~= "CONTINENT" and not continent.zoneData[map]
    or x == 0 and y == 0 then return end
    local now, peer = GetTime(), self.peers[key]
    if peer and now - peer.receivedAt < 1 then return end
    if not peer then
        local count = 0
        for _ in pairs(self.peers) do count = count + 1 end
        if count >= MAX_PEERS then return end
        peer = {}; self.peers[key] = peer
    end
    peer.name, peer.continent, peer.map, peer.floor = self.members[key].name, c, map, floor
    peer.x, peer.y, peer.receivedAt = x, y, now
end

function Map:Sample()
    if not self:CheckGuild() then return nil end
    if type(IsInInstance) == "function" and IsInInstance() then
        self.position = nil
        return nil
    end
    -- Never change the user's selected map while it is visible. The player's
    -- coordinates can still be sampled on a selected zone/continent map.
    local mapVisible = WorldMapFrame and WorldMapFrame:IsShown()
    if not mapVisible then SetMapToCurrentZone() end
    local x, y = GetPlayerMapPosition("player")
    local c, map = GetCurrentMapContinent(), GetMapInfo()
    if GetCurrentMapZone() == 0 then map = "CONTINENT" end
    local floor = type(GetCurrentMapDungeonLevel) == "function" and GetCurrentMapDungeonLevel() or 0
    local continent = GVE.GuildMapData and GVE.GuildMapData[c]
    if not continent or map ~= "CONTINENT" and not continent.zoneData[map]
    or not Coordinate(x) or not Coordinate(y) or x == 0 and y == 0 then
        if mapVisible then return nil, true end
        self.position = nil; return nil
    end
    self.position = {continent=c, map=map, floor=floor, x=x, y=y, receivedAt=GetTime()}
    return self.position
end

function Map:Broadcast()
    local settings = Settings()
    if not settings or not settings.guildMapEnabled or not self:CheckGuild() then return end
    local position, mapVisible = self:Sample()
    if mapVisible then return end
    local message = "X"
    if position then
        message = string.format("P|%d|%s|%d|%.5f|%.5f", position.continent,
            position.map, position.floor, position.x, position.y)
    end
    SendAddonMessage(PREFIX, message, "GUILD")
end

local function NewPin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetWidth(size); pin:SetHeight(size); pin:SetFrameLevel(parent:GetFrameLevel()+8)
    local dot = pin:CreateTexture(nil, "OVERLAY")
    dot:SetAllPoints(pin); dot:SetTexture("Interface\\COMMON\\Indicator-Green")
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        if not self.peer then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.peer.name, 0.2, 1, 0.3)
        GameTooltip:AddLine(L.guild, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:Hide()
    return pin
end

function Map:GetPins(peer)
    if peer.pins then return peer.pins end
    if not WorldMapButton or not Minimap then return nil end
    local pins = table.remove(self.pinPool)
    if not pins then pins = {world=NewPin(WorldMapButton, 12), mini=NewPin(Minimap, 9)} end
    pins.world.peer, pins.mini.peer = peer, peer
    peer.pins = pins
    return pins
end

local DIAMETERS = {
    indoor={[0]=300, 240, 180, 120, 80, 50},
    outdoor={[0]=466.666667, 400, 333.333333, 266.666667, 200, 133.333333},
}

function Map:DetectMinimapIndoor()
    if not Minimap or self.detectingZoom then return end
    local zoom = Minimap:GetZoom()
    if GetCVar("minimapInsideZoom") ~= GetCVar("minimapZoom") then
        self.indoors = zoom == tonumber(GetCVar("minimapInsideZoom"))
        return
    end
    -- Legacy Astrolabe technique: briefly change and restore zoom to learn
    -- which of the two CVars Blizzard updates. Guard recursive zoom events.
    if type(Minimap.SetZoom) == "function" then
        self.detectingZoom = true
        Minimap:SetZoom(zoom < 2 and zoom+1 or zoom-1)
        self.indoors = Minimap:GetZoom() ~= tonumber(GetCVar("minimapZoom"))
        Minimap:SetZoom(zoom)
        self.detectingZoom = nil
    end
end

function Map:MinimapOffset(peer)
    local own = self.position
    if not own or GetTime()-own.receivedAt > TTL or peer.continent ~= own.continent
    or peer.floor ~= own.floor then return nil end
    local x, y = self:ToContinent(peer)
    local px, py = self:ToContinent(own)
    if not x or not px then return nil end
    local dx, dy = x-px, y-py
    local distance = math.sqrt(dx*dx+dy*dy)
    local zoom = Minimap:GetZoom()
    -- Blizzard keeps independent indoor/outdoor zoom CVars.
    local indoorZoom = tonumber(GetCVar("minimapInsideZoom"))
    local outdoorZoom = tonumber(GetCVar("minimapZoom"))
    local indoors = zoom == indoorZoom and zoom ~= outdoorZoom
    if indoorZoom == outdoorZoom then indoors = self.indoors end
    local diameter = DIAMETERS[indoors and "indoor" or "outdoor"][zoom]
    if not diameter or distance > diameter/2-6 then return nil, nil, distance end
    if GetCVar("rotateMinimap") == "1" and type(GetPlayerFacing) == "function" then
        local facing = MiniMapCompassRing and type(MiniMapCompassRing.GetFacing) == "function"
            and -MiniMapCompassRing:GetFacing() or GetPlayerFacing() or 0
        local cos, sin = math.cos(facing), math.sin(facing)
        dx, dy = dx*cos-dy*sin, dx*sin+dy*cos
    end
    return dx/diameter*Minimap:GetWidth(), -dy/diameter*Minimap:GetHeight(), distance
end

function Map:Render()
    local settings = Settings()
    if not settings then return end
    local now, expired = GetTime(), {}
    local worldShown = WorldMapFrame and WorldMapFrame:IsShown()
    local c = worldShown and GetCurrentMapContinent()
    local map = worldShown and GetMapInfo()
    if worldShown and GetCurrentMapZone() == 0 then map = nil end
    local floor = worldShown and type(GetCurrentMapDungeonLevel) == "function" and GetCurrentMapDungeonLevel() or 0
    for key, peer in pairs(self.peers) do
        local member = self.members[key]
        if now-peer.receivedAt > TTL or not member or member.online == false then
            expired[#expired+1] = key
        else
            local pins = self:GetPins(peer)
            if pins then
                pins.world:Hide(); pins.mini:Hide()
                if settings.guildMapEnabled and worldShown and floor == peer.floor then
                    local x, y = self:Project(peer, c, map)
                    if Coordinate(x) and Coordinate(y) then
                        pins.world:ClearAllPoints()
                        pins.world:SetPoint("CENTER", WorldMapButton, "TOPLEFT",
                            x*WorldMapButton:GetWidth(), -y*WorldMapButton:GetHeight())
                        pins.world:Show()
                    end
                end
                local x, y, distance = self:MinimapOffset(peer)
                if settings.guildMapEnabled and x and Minimap:IsShown() then
                    pins.mini:ClearAllPoints(); pins.mini:SetPoint("CENTER", Minimap, "CENTER", x, y)
                    pins.mini:Show()
                end
            end
        end
    end
    for _, key in ipairs(expired) do self:ReleasePeer(key) end
end


local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("MINIMAP_UPDATE_ZOOM")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then Map:Receive(...); return end
    if event == "MINIMAP_UPDATE_ZOOM" then Map:DetectMinimapIndoor(); return end
    if event == "PLAYER_LOGIN" then
        local settings = Settings()
        if settings then Map:EnableNearby(settings.guildNearbyEnabled) end
        SLASH_GVEGUILDMAP1 = "/gvemap"
        SlashCmdList.GVEGUILDMAP = function(message)
            local command = (message or ""):lower():match("^%s*(.-)%s*$")
            local options = Settings()
            if not options then return end
            if command == "on" then options.guildMapEnabled = true; Map:Broadcast(); Say(L.enabled)
            elseif command == "off" then
                if Map.inGuild then SendAddonMessage(PREFIX, "X", "GUILD") end
                options.guildMapEnabled = false; Map:Clear(); Say(L.disabled)
            elseif command == "nearby on" then Map:EnableNearby(true); Say(L.nearOn)
            elseif command == "nearby off" then Map:EnableNearby(false); Say(L.nearOff)
            elseif command == "debug" then Map:RefreshMembers(); Map:CheckGuild(); Map:UpdateNameplates(); Map:MarkerDiagnostics()
            elseif command == "names" or command == "plates" or command == "auto" then
                Map:EnableNearby(true); options.guildMarkerStyle = command; Map:UpdateNameplates()
                Say(L[command])
            else Say(L.help) end
        end
    end
    Map:RefreshMembers(); Map:CheckGuild()
    if event == "PLAYER_ENTERING_WORLD" then
        Map:Clear(); Map:DetectMinimapIndoor()
        local settings = Settings()
        if settings then Map:EnableNearby(settings.guildNearbyEnabled) end
    end
    Map.sendElapsed = INTERVAL
end)
events:SetScript("OnUpdate", function(_, elapsed)
    Map.tick, Map.sendElapsed, Map.sampleElapsed = Map.tick+elapsed, Map.sendElapsed+elapsed, Map.sampleElapsed+elapsed
    local settings = Settings()
    if settings and settings.guildMapEnabled and Map.sampleElapsed >= 0.5 then
        Map.sampleElapsed = 0; Map:Sample()
    end
    if Map.sendElapsed >= INTERVAL then
        Map.sendElapsed = 0; Map:RefreshMembers(); Map:Broadcast()
    end
    if Map.tick >= 0.2 then
        Map.tick = 0; Map:Render(); Map:UpdateNameplates()
    end
end)
