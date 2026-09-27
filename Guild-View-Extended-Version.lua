---------------------------------------------------------------------------
-- Guild-View-Extended: Versionspruefung fuer WoW 3.3.5a
-- Erkennt neuere Versionen ausschliesslich ueber andere Addon-Nutzer. Ein
-- Addon kann weder GitHub noch andere HTTP-Endpunkte direkt abfragen.
---------------------------------------------------------------------------
local GVE = _G.GVE
if not GVE then return end

local Version = {
    addonPrefix = "GVEVER1",
    realmChannel = "GuildViewVersion",
    realmProtocol = "GVEV1",
    githubURL = "https://github.com/AngelGamerZ/Guild-View-Extended/releases/latest",
    notified = {}, acknowledgements = {}, realmResponses = {},
    lastGuildBroadcast = -1000, guildBroadcastInterval = 900,
    realmQueryInterval = 1800, realmQueryLifetime = 25,
    realmResponseInterval = 8, lastRealmResponse = -1000,
}
GVE.VersionCheck = Version

local localeDE = GetLocale and GetLocale() == "deDE"
local TEXT = localeDE and {
    available="Eine neue Version von Guild-View-Extended ist verfügbar! Installiert: %s · Neu: %s",
    chatLink="Öffne GuildView und klicke auf das gelbe Questzeichen für den Download-Link.",
    tooltipTitle="Update verfügbar",
    tooltipBody="Installiert: %s\nNeu erkannt: %s\nKlicken für den GitHub-Link.",
    windowTitle="Guild-View-Extended aktualisieren",
    windowBody="Eine neuere Version wurde bei einem anderen Guild-View-Extended-Nutzer erkannt.",
    copy="Markiere den Link und drücke Strg+C.", close="Schließen",
} or {
    available="A new Guild-View-Extended version is available! Installed: %s · New: %s",
    chatLink="Open GuildView and click the yellow quest marker for the download link.",
    tooltipTitle="Update available",
    tooltipBody="Installed: %s\nDetected: %s\nClick for the GitHub link.",
    windowTitle="Update Guild-View-Extended",
    windowBody="A newer version was detected from another Guild-View-Extended user.",
    copy="Select the link and press Ctrl+C.", close="Close",
}

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function CurrentVersion()
    local value = type(GetAddOnMetadata) == "function"
        and GetAddOnMetadata("Guild-View-Extended", "Version") or nil
    return tostring(value or "0.0.0")
end

local STAGE = {alpha=1, beta=2, rc=3}
local function ParseVersion(value)
    if type(value) ~= "string" or #value > 32 then return nil end
    local normalized = value:lower():gsub("^%s*v", ""):gsub("%s+$", "")
    local major, minor, rest = normalized:match("^(%d+)%.(%d+)(.*)$")
    if not major then return nil end
    local patch, suffix = rest:match("^%.(%d+)(.*)$")
    if not patch then patch, suffix = "0", rest end
    suffix = (suffix or ""):gsub("^[%._%-]+", "")
    local stage = suffix == "" and 4 or 0
    for name, weight in pairs(STAGE) do
        if suffix:find(name, 1, true) then stage = weight break end
    end
    local revision = tonumber(suffix:match("(%d+)")) or 0
    return {tonumber(major), tonumber(minor), tonumber(patch), stage, revision}
end

function Version:CompareVersions(left, right)
    local a, b = ParseVersion(left), ParseVersion(right)
    if not a or not b then return nil end
    for index = 1, 5 do
        if a[index] < b[index] then return -1 end
        if a[index] > b[index] then return 1 end
    end
    return 0
end

local function CleanSender(value)
    if type(value) ~= "string" then return nil end
    local name = value:gsub("%-.*$", ""):gsub("[\r\n]", "")
    return name ~= "" and name or nil
end

function Version:IsGuildMember(name)
    local wanted = CleanSender(name)
    if not wanted then return false end
    wanted = wanted:lower()
    for _, member in ipairs(GVE:GetMembers() or {}) do
        local memberName = CleanSender(member.name)
        if memberName and memberName:lower() == wanted then return true end
    end
    return false
end

function Version:BuildUpdateWindow()
    if self.window then return end
    local w = CreateFrame("Frame", "GVEUpdateWindow", UIParent)
    w:SetSize(590, 245); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG")
    w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=14,
        insets={left=4,right=4,top=4,bottom=4},
    })
    w:SetBackdropColor(0.018, 0.027, 0.047, 0.98)
    w:SetBackdropBorderColor(0.20, 0.50, 0.72, 1)
    w:Hide(); self.window = w
    tinsert(UISpecialFrames, "GVEUpdateWindow")

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18); title:SetText("|cffffd200"..TEXT.windowTitle.."|r")
    local body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -15); body:SetWidth(520); body:SetJustifyH("CENTER")
    body:SetText(TEXT.windowBody)
    w.versions = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.versions:SetPoint("TOP", body, "BOTTOM", 0, -10); w.versions:SetTextColor(0.35, 0.75, 1)

    local edit = CreateFrame("EditBox", nil, w)
    edit:SetPoint("TOPLEFT", w, "TOPLEFT", 28, -112); edit:SetPoint("TOPRIGHT", w, "TOPRIGHT", -28, -112)
    edit:SetHeight(30); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(8, 8, 0, 0); edit:SetMaxLetters(300)
    edit:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10})
    edit:SetBackdropColor(0.01, 0.015, 0.025, 1); edit:SetBackdropBorderColor(0.2, 0.5, 0.72, 1)
    edit:SetText(self.githubURL)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); w:Hide() end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= Version.githubURL then
            self:SetText(Version.githubURL)
            self:HighlightText()
        end
    end)
    w.edit = edit

    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", edit, "BOTTOM", 0, -8); hint:SetText(TEXT.copy)
    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetSize(120, 24); close:SetPoint("BOTTOM", 0, 16); close:SetText(TEXT.close)
    close:SetScript("OnClick", function() w:Hide() end)
    local x = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 1, 1); x:SetScript("OnClick", function() w:Hide() end)
end

function Version:ShowUpdateWindow()
    self:BuildUpdateWindow()
    self.window.versions:SetText("v"..CurrentVersion().."  |cff778899→|r  |cffffd200v"..tostring(self.latestVersion or "?").."|r")
    self.window:Show(); self.window:Raise()
    self.window.edit:SetFocus(); self.window.edit:HighlightText()
end

function Version:BuildMarker()
    if self.marker or not GVE.f then return end
    local marker = CreateFrame("Button", "GVEUpdateMarker", GVE.f)
    marker:SetSize(30, 30); marker:SetPoint("TOPRIGHT", GVE.f, "TOPRIGHT", -38, -8)
    marker:SetFrameLevel(GVE.f:GetFrameLevel() + 100)
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetAllPoints(); marker.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    marker:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    marker:SetScript("OnClick", function() Version:ShowUpdateWindow() end)
    marker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(TEXT.tooltipTitle, 1, 0.82, 0)
        GameTooltip:AddLine(format(TEXT.tooltipBody, CurrentVersion(), tostring(Version.latestVersion or "?")), 0.88, 0.93, 0.98, true)
        GameTooltip:Show()
    end)
    marker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    marker:Hide(); self.marker = marker
end

function Version:RefreshMarker()
    self:BuildMarker()
    if not self.marker then return end
    if self.latestVersion and self:CompareVersions(self.latestVersion, CurrentVersion()) == 1 then
        self.marker:Show()
    else
        self.marker:Hide()
    end
end

function Version:ConsiderVersion(remote, sender, transport)
    if not ParseVersion(remote) or self:CompareVersions(remote, CurrentVersion()) ~= 1 then return false end
    if not self.latestVersion or self:CompareVersions(remote, self.latestVersion) == 1 then
        self.latestVersion, self.latestSource, self.latestTransport = remote, sender, transport
    end
    self:RefreshMarker()
    if not self.notified[remote] then
        self.notified[remote] = true
        local message = format(TEXT.available, CurrentVersion(), remote)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[Guild-View-Extended]|r |cffffd200"..message.."|r")
            DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[Guild-View-Extended]|r "..TEXT.chatLink)
        else
            print("[Guild-View-Extended] "..message)
        end
    end
    return true
end

function Version:SendGuild(kind, target)
    if type(SendAddonMessage) ~= "function" then return false end
    local channel = target and "WHISPER" or "GUILD"
    if not target and type(IsInGuild) == "function" and not IsInGuild() then return false end
    SendAddonMessage(self.addonPrefix, kind.."|"..CurrentVersion(), channel, target)
    return true
end

function Version:BroadcastGuild(force)
    if not force and Now() - self.lastGuildBroadcast < self.guildBroadcastInterval then return false end
    if self:SendGuild("H") then self.lastGuildBroadcast = Now(); return true end
    return false
end

function Version:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= self.addonPrefix or type(message) ~= "string" or #message > 48 then return false end
    local kind, remote = message:match("^([HA])|([^|]+)$")
    if not kind or not ParseVersion(remote) or not self:IsGuildMember(sender) then return false end
    self:ConsiderVersion(remote, sender, channel)
    if kind == "H" and channel == "GUILD" then
        local key, current = (CleanSender(sender) or ""):lower(), Now()
        if current - (self.acknowledgements[key] or -1000) >= 5 then
            self.acknowledgements[key] = current
            self:SendGuild("A", sender)
        end
    end
    return true
end

function Version:GetRealmChannelID()
    if type(GetChannelName) ~= "function" then return nil end
    local ok, channelID = pcall(GetChannelName, self.realmChannel)
    channelID = ok and tonumber(channelID) or nil
    return channelID and channelID > 0 and channelID or nil
end

function Version:ChannelMatches(...)
    local wanted, channelID = self.realmChannel:lower(), self:GetRealmChannelID()
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if channelID and tonumber(value) == channelID then return true end
        if type(value) == "string" and value:lower():find(wanted, 1, true) then return true end
    end
    return false
end

function Version:ParseRealmPacket(message)
    if type(message) ~= "string" or #message > 100 then return nil end
    local protocol, kind, remote, nonce = message:match("^([^:]+):([^:]+):([^:]+):([^:]+)$")
    if protocol ~= self.realmProtocol or (kind ~= "Q" and kind ~= "R")
    or not ParseVersion(remote) or not nonce or #nonce > 40 or not nonce:match("^[%w%-]+$") then return nil end
    return kind, remote, nonce
end

function Version:SendRealm(kind, remote, nonce)
    local channelID = self:GetRealmChannelID()
    if not channelID or type(SendChatMessage) ~= "function" then return false end
    local packet = table.concat({self.realmProtocol, kind, remote, nonce}, ":")
    return pcall(SendChatMessage, packet, "CHANNEL", nil, channelID)
end

function Version:StartRealmQuery()
    local channelID = self:GetRealmChannelID()
    if not channelID then
        local join = JoinTemporaryChannel or JoinChannelByName
        if type(join) ~= "function" then return false end
        if not self.joinRequested then pcall(join, self.realmChannel); self.joinRequested = true end
        self.joinRetryAt = Now() + 1
        self.joinAttempts = (self.joinAttempts or 0) + 1
        return false
    end
    self.realmNonce = tostring(math.floor(Now() * 1000)).."-"..tostring(math.random(1000, 9999))
    self.realmQueryAt = Now(); self.nextRealmQueryAt = Now() + self.realmQueryInterval
    return self:SendRealm("Q", CurrentVersion(), self.realmNonce)
end

function Version:OnRealmMessage(message, sender, ...)
    if not self:ChannelMatches(...) then return false end
    local kind, remote, nonce = self:ParseRealmPacket(message)
    if not kind or CleanSender(sender) == CleanSender(UnitName and UnitName("player") or "") then return false end
    if kind == "Q" then
        if self:CompareVersions(CurrentVersion(), remote) ~= 1 then return true end
        local key, current = tostring(sender).."|"..nonce, Now()
        if current - (self.realmResponses[key] or -1000) < self.realmResponseInterval
        or current - self.lastRealmResponse < 2 then return true end
        local responseCount = 0
        for responseKey, timestamp in pairs(self.realmResponses) do
            if current - timestamp > 60 then
                self.realmResponses[responseKey] = nil
            else
                responseCount = responseCount + 1
            end
        end
        if responseCount >= 100 then return true end
        self.realmResponses[key], self.lastRealmResponse = current, current
        self.pendingRealmResponse = {at=current + 0.25 + math.random(0, 125) / 100, nonce=nonce}
        return true
    end
    if nonce ~= self.realmNonce or Now() - (self.realmQueryAt or -1000) > self.realmQueryLifetime then return false end
    self:ConsiderVersion(remote, sender, "REALM")
    return true
end

function Version:OnUpdate()
    local current = Now()
    if self.guildBroadcastAt and current >= self.guildBroadcastAt then
        self.guildBroadcastAt = nil; self:BroadcastGuild(true)
    end
    if self.joinRetryAt and current >= self.joinRetryAt then
        self.joinRetryAt = nil
        if (self.joinAttempts or 0) <= 8 then self:StartRealmQuery() end
    end
    if self.realmQueryAtPending and current >= self.realmQueryAtPending then
        self.realmQueryAtPending = nil; self:StartRealmQuery()
    end
    if self.nextRealmQueryAt and current >= self.nextRealmQueryAt then self:StartRealmQuery() end
    if self.pendingRealmResponse and current >= self.pendingRealmResponse.at then
        local response = self.pendingRealmResponse; self.pendingRealmResponse = nil
        self:SendRealm("R", CurrentVersion(), response.nonce)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Version:BuildMarker()
        Version.guildBroadcastAt = Now() + 2
        Version.realmQueryAtPending = Now() + 3
        if type(ChatFrame_AddMessageEventFilter) == "function" then
            Version.realmFilter = function(_, _, message, ...)
                return Version:ParseRealmPacket(message) ~= nil and Version:ChannelMatches(...)
            end
            ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", Version.realmFilter)
        end
    elseif event == "GUILD_ROSTER_UPDATE" and Now() - Version.lastGuildBroadcast >= Version.guildBroadcastInterval then
        Version.guildBroadcastAt = Version.guildBroadcastAt or Now() + 1
    elseif event == "CHAT_MSG_ADDON" then
        Version:OnAddonMessage(...)
    elseif event == "CHAT_MSG_CHANNEL" then
        Version:OnRealmMessage(...)
    end
end)
frame:SetScript("OnUpdate", function() Version:OnUpdate() end)

