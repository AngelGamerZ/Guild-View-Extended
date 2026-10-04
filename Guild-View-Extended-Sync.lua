---------------------------------------------------------------------------
-- Guild-View-Extended: Berufe
-- WoW 3.3.5a: versionierte, anfragebasierte Snapshot-Synchronisierung ueber
-- SendAddonMessage. Keine Retail-APIs, keine Server- oder HTTP-Anfragen.
---------------------------------------------------------------------------
local GVE = _G.GVE
if not GVE then return end

local Sync = {}
GVE.Sync = Sync

local PREFIX = "GVEX4"
local PROTOCOL = 4
local STORAGE_SCHEMA = 2
local CHUNK_BYTES = 175
local MAX_CHUNKS = 256
local MAX_BYTES = MAX_CHUNKS * CHUNK_BYTES
local CACHE_TTL = 30 * 24 * 60 * 60
local REQUEST_TIMEOUT = 15
local REQUEST_COOLDOWN = 10
local AUTO_REQUEST_INTERVAL = 1.0
local AUTO_REQUEST_RETRY = 300
local SEND_INTERVAL = 0.09
local MAX_CACHED_PLAYERS = 300
local MAX_QUEUE_BEFORE_BUSY = 80
local ABSOLUTE_TRANSFER_TIMEOUT = 60

local L = GetLocale() == "deDE" and {
    members="Mitglieder", tab="Berufe", search="Spieler oder Beruf suchen ...",
    professions="Berufe", request="Daten anfragen",
    capture="Jetzt erfassen", noSelection="Wähle links einen Spieler aus.",
    noData="Noch keine Daten synchronisiert.", noProfessions="Keine passenden Berufe.", fresh="vor %s synchronisiert",
    pending="Anfrage gesendet ...", offline="Spieler ist offline – gespeicherte Daten",
    timeout="Keine Antwort. Spieler offline oder Addon nicht verfügbar.",
    denied="Freigabe wurde vom Spieler deaktiviert.", empty="Der Spieler hat diese Daten noch nicht erfasst.",
    busy="Der Spieler überträgt gerade andere Daten. Bitte später erneut versuchen.",
    help="Berufe werden als vollständige, anklickbare 3.3.5a-Berufslinks gespeichert – so wie beim Posten aus dem Zauberbuch in den Chat.",
    footerShort="Berufslinks aus der letzten Synchronisierung",
    clickToOpen="Klicken, um den verlinkten Beruf zu öffnen.",
    shareP="Eigene Berufe teilen", captured="Lokaler Snapshot aktualisiert.", players="%d Spieler",
    professionSearch="Berufe durchsuchen ...", professionCount="%d Berufe",
    current="aktuell", stale="veraltet", never="keine Daten",
    sec="Sek.", min="Min.", hour="Std.", day="Tage",
    openProfession="Kein vollständiger Berufslink gefunden. Öffne dein Zauberbuch oder deinen eigenen Beruf und versuche es erneut.",
    syncNow="Jetzt synchronisieren", syncSent="Gildenweite Synchronisierung gestartet: eigene Berufe verteilt und aktuelle Daten angefragt.",
    staleReply="Antwort erhalten, aber der Snapshot des Spielers ist weiterhin veraltet.",
    lastCaptured="zuletzt erfasst vor %s",
    synchronized="%d synchronisierte Spieler", categoryPlayers="%d Spieler",
    tooBig="Die Berufsdaten sind für die Synchronisierung zu groß.",
    notSynchronized="Noch nicht synchronisiert",
    columnPlayer="Beruf / Spieler", columnLink="Berufslink", columnSkill="Skill",
    columnAge="Aktualität", columnStatus="Status", allPlayers="Alle Spieler",
    onlineOnly="Online", offlineOnly="Offline", allData="Alle Daten",
    currentOnly="Aktuell", staleOnly="Veraltet", openAll="Alle öffnen",
    closeAll="Alle schließen", onlineCount="%d Spieler · %d online",
    syncActive="Automatische Synchronisierung aktiv", offlineCache="Offline · Cache",
    noResults="Keine passenden Spieler oder Berufe.", requestShort="Anfragen",
    relayedCurrent="über %s · aktuell", relayedStale="über %s · veraltet",
} or {
    members="Members", tab="Professions", search="Search player or profession ...",
    professions="Professions", request="Request data",
    capture="Capture now", noSelection="Select a player on the left.",
    noData="No synchronized data yet.", noProfessions="No matching professions.", fresh="synchronized %s ago",
    pending="Request sent ...", offline="Player is offline – showing cached data",
    timeout="No response. Player may be offline or not use the addon.",
    denied="Sharing was disabled by the player.", empty="The player has not captured this data yet.",
    busy="The player is transferring other data. Please try again later.",
    help="Professions are stored as complete, clickable 3.3.5a trade links – just like posting them from the spellbook into chat.",
    footerShort="Profession links from the latest synchronization",
    clickToOpen="Click to open the linked profession.",
    shareP="Share my professions", captured="Local snapshot updated.", players="%d players",
    professionSearch="Search professions ...", professionCount="%d professions",
    current="current", stale="stale", never="no data",
    sec="sec", min="min", hour="hr", day="days",
    openProfession="No complete profession link was found. Open your spellbook or your own profession and try again.",
    syncNow="Sync guild now", syncSent="Guild synchronization started: shared your professions and requested current data.",
    staleReply="Response received, but the player's snapshot is still outdated.",
    lastCaptured="last captured %s ago",
    synchronized="%d synchronized players", categoryPlayers="%d players",
    tooBig="The profession data is too large to synchronize.",
    notSynchronized="Not synchronized",
    columnPlayer="Profession / player", columnLink="Profession link", columnSkill="Skill",
    columnAge="Last update", columnStatus="Status", allPlayers="All players",
    onlineOnly="Online", offlineOnly="Offline", allData="All data",
    currentOnly="Current", staleOnly="Stale", openAll="Expand all",
    closeAll="Collapse all", onlineCount="%d players · %d online",
    syncActive="Automatic synchronization active", offlineCache="Offline · cache",
    noResults="No matching players or professions.", requestShort="Request",
    relayedCurrent="via %s · current", relayedStale="via %s · stale",
}

local function CleanName(value)
    if type(value) ~= "string" then return nil end
    local name = value:gsub("[\r\n]", ""):gsub("%-.*$", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function KeyName(value)
    local name = CleanName(value)
    return name and (GVE.CaseFoldName and GVE:CaseFoldName(name) or name:lower()) or nil
end

local function Fold(value)
    return GVE.CaseFoldName and GVE:CaseFoldName(value) or tostring(value or ""):lower()
end

local function SafeText(value, maxLength)
    if type(value) ~= "string" or #value > maxLength or value:find("%c") or value:find("|", 1, true) then return nil end
    return value
end

local function IsInteger(value, minimum, maximum)
    return value and value == math.floor(value) and value >= minimum and value <= maximum
end

local function ParseTradeLink(value)
    if type(value) ~= "string" or #value < 10 or #value > 12000 or value:find("%c") then return nil end
    local hyperlink, label = value:match("^|c%x%x%x%x%x%x%x%x|H([^|]+)|h%[([^|%[%]]+)%]|h|r$")
    if not hyperlink or not label then return nil end
    -- 3.3.5a-Serverimplementierungen nutzen auch sehr kurze Character-IDs und eine
    -- Custom-6-bit-Bitmap mit Zeichen wie "{". Das komplette letzte Feld
    -- bleibt deshalb opak; Pipes und Steuerzeichen sind oben ausgeschlossen.
    local spellID, skill, maxSkill, ownerGUID, tradeData = hyperlink:match("^trade:(%d+):(%d+):(%d+):([%x]+):([^|%c]*)$")
    spellID, skill, maxSkill = tonumber(spellID), tonumber(skill), tonumber(maxSkill)
    if not IsInteger(spellID, 1, 10000000) or not IsInteger(skill, 0, 1000) or not IsInteger(maxSkill, 0, 1000) then return nil end
    if #ownerGUID < 1 or #ownerGUID > 32 or #tradeData > 10000 then return nil end
    return value, label, skill, maxSkill, spellID
end

local function SafeTradeLink(value)
    return ParseTradeLink(value)
end

local function DebugLog(message)
    if type(GVE.AddLog) == "function" then
        GVE:AddLog("Berufe: "..tostring(message))
    end
end

local function DebugLink(value)
    if type(value) ~= "string" then return tostring(value) end
    local visible = value:gsub("|", "<PIPE>")
    visible = visible:gsub("[%c]", function(character)
        return format("<%02X>", string.byte(character))
    end)
    return "("..#value.." Bytes) "..visible
end

local function OpenTradeLink(link)
    local safe = SafeTradeLink(link)
    local hyperlink = safe and safe:match("|H([^|]+)|h")
    if hyperlink and type(SetItemRef) == "function" then
        pcall(SetItemRef, hyperlink, safe, "LeftButton")
    end
end

local function Encode(value)
    return tostring(value or ""):gsub("([^%w%-%_%.])", function(c)
        return format("%%%02X", string.byte(c))
    end)
end

local function Decode(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function Split(value, sep)
    local out, start = {}, 1
    if value == "" then return out end
    while true do
        local a, b = value:find(sep, start, true)
        if not a then
            out[#out + 1] = value:sub(start)
            break
        end
        out[#out + 1] = value:sub(start, a - 1)
        start = b + 1
    end
    return out
end

local function AgeText(stamp)
    local seconds = math.max(0, time() - (tonumber(stamp) or 0))
    if seconds < 60 then return seconds.." "..L.sec end
    if seconds < 3600 then return math.floor(seconds / 60).." "..L.min end
    if seconds < 86400 then return math.floor(seconds / 3600).." "..L.hour end
    return math.floor(seconds / 86400).." "..L.day
end

local function IsOwn(name)
    local player = UnitName("player")
    return player and KeyName(player) == KeyName(name)
end

local function MakeBackdrop(frame, r, g, b, a)
    frame:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    })
    frame:SetBackdropColor(r, g, b, a)
end

local function MakeCheck(parent, text)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(16, 16)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 3, 0)
    cb.text:SetText(text)
    return cb
end

-- Ruhige, flache UI-Bausteine. Sie verwenden nur Texturen, Backdrops und
-- FontObjects aus dem 3.3.5a-Client und vermeiden die roten Standardknöpfe.
local UI_COLOR = {
    panel       = {0.018, 0.027, 0.047, 1.00},
    section     = {0.028, 0.043, 0.071, 0.96},
    field       = {0.012, 0.020, 0.035, 0.98},
    border      = {0.16, 0.25, 0.34, 0.72},
    borderFocus = {0.20, 0.667, 1.00, 1.00},
    accent      = {0.08, 0.45, 0.68, 0.95},
    accentSoft  = {0.082, 0.114, 0.165, 1.00}, -- #151d2a
    hover       = {0.153, 0.204, 0.278, 1.00}, -- #273447
    selected    = {0.075, 0.204, 0.302, 1.00}, -- #13344d
    good        = {0.282, 0.835, 0.592, 1.00},
    warn        = {0.894, 0.722, 0.302, 1.00},
    error       = {0.86, 0.38, 0.38, 1.00},
    rowA        = {0.025, 0.039, 0.061, 0.74},
    rowB        = {0.035, 0.053, 0.080, 0.74},
    text        = {0.89, 0.94, 0.98},
    muted       = {0.51, 0.61, 0.69},
}

local function SetTextureColor(texture, color)
    texture:SetTexture(color[1], color[2], color[3], color[4])
end

local function MakeFlatPanel(frame, color)
    frame:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\ChatFrame\\ChatFrameBackground",
        tile=true, tileSize=16, edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1},
    })
    frame:SetBackdropColor(color[1], color[2], color[3], color[4])
    frame:SetBackdropBorderColor(UI_COLOR.border[1], UI_COLOR.border[2], UI_COLOR.border[3], UI_COLOR.border[4])
end

local function PaintFlatButton(button)
    local color
    if button.flatSelected then color = UI_COLOR.selected
    elseif button.flatDisabled then color = UI_COLOR.field
    elseif button.flatHover then color = UI_COLOR.hover
    elseif button.flatAccent then color = UI_COLOR.accentSoft
    else color = UI_COLOR.accentSoft end
    button:SetBackdropColor(color[1], color[2], color[3], color[4])
    local textColor = button.flatDisabled and not button.flatSelected and UI_COLOR.muted or UI_COLOR.text
    button.label:SetTextColor(textColor[1], textColor[2], textColor[3])
    if button.flatSelected or (button.flatHover and not button.flatDisabled) then
        button:SetBackdropBorderColor(UI_COLOR.borderFocus[1], UI_COLOR.borderFocus[2], UI_COLOR.borderFocus[3], UI_COLOR.borderFocus[4])
    else
        button:SetBackdropBorderColor(UI_COLOR.border[1], UI_COLOR.border[2], UI_COLOR.border[3], UI_COLOR.border[4])
    end
end

local function MakeFlatButton(parent, width, height, text, accent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    MakeFlatPanel(button, accent and UI_COLOR.accentSoft or UI_COLOR.section)
    button.flatAccent = accent and true or nil
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("CENTER")
    button.label:SetText(text or "")
    button.SetText = function(self, value) self.label:SetText(value or "") end
    button.GetText = function(self) return self.label:GetText() end
    button:SetScript("OnEnter", function(self) self.flatHover = true; PaintFlatButton(self) end)
    button:SetScript("OnLeave", function(self) self.flatHover = nil; PaintFlatButton(self) end)
    button:SetScript("OnDisable", function(self) self.flatDisabled = true; PaintFlatButton(self) end)
    button:SetScript("OnEnable", function(self) self.flatDisabled = nil; PaintFlatButton(self) end)
    PaintFlatButton(button)
    return button
end

local function SetFlatSelected(button, selected)
    if not button then return end
    button.flatSelected = selected and true or nil
    if button.selectionIndicator then
        if selected then button.selectionIndicator:Show() else button.selectionIndicator:Hide() end
    end
    PaintFlatButton(button)
end

local function MakeFlatSearch(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, height)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(9, 8, 0, 0)
    MakeFlatPanel(box, UI_COLOR.field)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(UI_COLOR.borderFocus[1], UI_COLOR.borderFocus[2], UI_COLOR.borderFocus[3], UI_COLOR.borderFocus[4])
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(UI_COLOR.border[1], UI_COLOR.border[2], UI_COLOR.border[3], UI_COLOR.border[4])
    end)
    return box
end

local function PaintPlayerRow(row, alternate)
    local color
    if row.rowSelected then color = UI_COLOR.selected
    elseif row.rowHover then color = UI_COLOR.hover
    elseif alternate then color = UI_COLOR.rowB
    else color = UI_COLOR.rowA end
    SetTextureColor(row.bg, color)
    if row.selectionBar then
        if row.rowSelected then row.selectionBar:Show() else row.selectionBar:Hide() end
    end
end

function Sync:InitDB()
    if type(GVESyncData) ~= "table" then
        GVESyncData = {schema=PROTOCOL, storageSchema=STORAGE_SCHEMA, guilds={}, settings={}}
    end
    local db = GVESyncData
    local previousSchema = tonumber(db.schema) or 0
    if previousSchema > PROTOCOL then
        -- Daten einer neueren, unbekannten Version niemals als v4 umdeuten.
        -- Nur die harmlosen Freigabeeinstellungen koennen uebernommen werden.
        db = {schema=PROTOCOL, storageSchema=STORAGE_SCHEMA, guilds={}, settings=type(db.settings) == "table" and db.settings or {}}
        GVESyncData = db
        previousSchema = PROTOCOL
    end
    -- Alte Berufslinks bleiben erhalten. Nicht mehr verwendete Bank- und
    -- Rezeptindexdaten werden bei der Migration ersatzlos entfernt.
    db.schema = PROTOCOL
    db.settings = type(db.settings) == "table" and db.settings or {}
    if db.settings.shareProfessions == nil then db.settings.shareProfessions = true end
    db.settings.shareReagents = nil

    local function MigrateSnapshot(snapshot)
        if type(snapshot) ~= "table" then return end
        snapshot.reagents = nil
        if type(snapshot.professions) ~= "table" then snapshot.professions = nil return end
        local migrated, oldestAt = {}, nil
        for professionName, profession in pairs(snapshot.professions) do
            if type(profession) == "table" then
                local tradeLink, linkLabel, skill, maxSkill = ParseTradeLink(profession.tradeLink)
                local capturedAt = tonumber(profession.capturedAt) or tonumber(snapshot.professionsCapturedAt)
                    or tonumber(snapshot.receivedAt) or time()
                if tradeLink and SafeText(professionName, 128) and Fold(linkLabel) == Fold(professionName) then
                    if not IsInteger(capturedAt, 1, time() + 3600) then capturedAt = time() end
                    migrated[linkLabel] = {
                        name=linkLabel, skill=skill, maxSkill=maxSkill,
                        capturedAt=capturedAt, tradeLink=tradeLink,
                    }
                    oldestAt = not oldestAt and capturedAt or math.min(oldestAt, capturedAt)
                end
            end
        end
        snapshot.professions = next(migrated) and migrated or nil
        snapshot.professionsCapturedAt = oldestAt
        snapshot.relayFrom = CleanName(snapshot.relayFrom)
        snapshot.directSource = snapshot.relayFrom and false or true
    end
    local guildName = GetGuildInfo("player")
    if (not guildName or guildName == "") and type(IsInGuild) == "function" and IsInGuild() then
        -- Direkt bei PLAYER_LOGIN kann der Gildenname noch ungeladen sein.
        -- Niemals deshalb einen gueltigen gespeicherten Guild-Scope leeren.
        self.db = db
        self.guildData = self.guildData or {players={}, ownByCharacter={}}
        self.own = self.own or {}
        self.waitingForGuild = true
        return false
    end
    guildName = guildName or ""
    self.waitingForGuild = nil
    local guildKey = (GetRealmName() or "").."\031"..guildName

    -- Bis Version 1.3 lagen nur die Daten der zuletzt angemeldeten Gilde an
    -- der Wurzel der SavedVariables. Verschiebe sie einmalig in den damals
    -- gespeicherten Gildenbereich. So bleiben sie auch erhalten, wenn der
    -- naechste Charakter in einer anderen Gilde oder gildenlos ist.
    db.guilds = type(db.guilds) == "table" and db.guilds or {}
    if type(db.players) == "table" or type(db.ownByCharacter) == "table" or type(db.own) == "table" then
        local legacyGuildKey = type(db.guildKey) == "string" and db.guildKey or guildKey
        local legacyGuild = type(db.guilds[legacyGuildKey]) == "table" and db.guilds[legacyGuildKey] or {}
        legacyGuild.players = type(legacyGuild.players) == "table" and legacyGuild.players or {}
        legacyGuild.ownByCharacter = type(legacyGuild.ownByCharacter) == "table" and legacyGuild.ownByCharacter or {}
        for key, snapshot in pairs(type(db.players) == "table" and db.players or {}) do
            if legacyGuild.players[key] == nil then legacyGuild.players[key] = snapshot end
        end
        for key, snapshot in pairs(type(db.ownByCharacter) == "table" and db.ownByCharacter or {}) do
            if legacyGuild.ownByCharacter[key] == nil then legacyGuild.ownByCharacter[key] = snapshot end
        end
        if type(db.own) == "table" and legacyGuildKey == guildKey then
            local legacyCharacterKey = guildKey.."\031"..(UnitName("player") or "Unknown")
            if legacyGuild.ownByCharacter[legacyCharacterKey] == nil then
                legacyGuild.ownByCharacter[legacyCharacterKey] = db.own
            end
        end
        db.guilds[legacyGuildKey] = legacyGuild
        db.players, db.ownByCharacter, db.own, db.guildKey = nil, nil, nil, nil
    end
    db.storageSchema = STORAGE_SCHEMA

    local guildData = type(db.guilds[guildKey]) == "table" and db.guilds[guildKey] or {}
    guildData.players = type(guildData.players) == "table" and guildData.players or {}
    guildData.ownByCharacter = type(guildData.ownByCharacter) == "table" and guildData.ownByCharacter or {}
    db.guilds[guildKey] = guildData

    -- Alle gespeicherten Gildenbereiche migrieren, nicht nur die gerade
    -- aktive Gilde. Dadurch bleibt auch ein spaeter wieder besuchter Cache
    -- gueltig und wird nicht beim Charakterwechsel verworfen.
    for _, storedGuild in pairs(db.guilds) do
        if type(storedGuild) == "table" then
            storedGuild.players = type(storedGuild.players) == "table" and storedGuild.players or {}
            storedGuild.ownByCharacter = type(storedGuild.ownByCharacter) == "table" and storedGuild.ownByCharacter or {}
            for _, snapshot in pairs(storedGuild.ownByCharacter) do MigrateSnapshot(snapshot) end
            for _, snapshot in pairs(storedGuild.players) do MigrateSnapshot(snapshot) end
        end
    end

    local characterKey = guildKey.."\031"..(UnitName("player") or "Unknown")
    if self.activeGuildKey ~= guildKey or self.activeCharacterKey ~= characterKey then
        if self.sendQueue then wipe(self.sendQueue) end
        if self.pending then wipe(self.pending) end
        if self.receiving then wipe(self.receiving) end
        if self.cooldowns then wipe(self.cooldowns) end
        if self.incomingCooldown then wipe(self.incomingCooldown) end
        if self.viewMessages then wipe(self.viewMessages) end
        if self.autoQueue then wipe(self.autoQueue) end
        if self.autoQueued then wipe(self.autoQueued) end
        if self.autoLastRequest then wipe(self.autoLastRequest) end
        if self.relayCatalogPending then wipe(self.relayCatalogPending) end
        if self.relayCatalogCooldown then wipe(self.relayCatalogCooldown) end
        if self.relayQueue then wipe(self.relayQueue) end
        if self.relayQueued then wipe(self.relayQueued) end
        if self.relayPending then wipe(self.relayPending) end
        if self.relayReceiving then wipe(self.relayReceiving) end
        if self.relayOwnerPending then wipe(self.relayOwnerPending) end
        if self.relayIncomingCooldown then wipe(self.relayIncomingCooldown) end
    end
    self.activeGuildKey = guildKey
    self.activeCharacterKey = characterKey
    if type(guildData.ownByCharacter[characterKey]) ~= "table" then
        guildData.ownByCharacter[characterKey] = {}
    end
    self.own = guildData.ownByCharacter[characterKey]
    local cutoff = time() - CACHE_TTL
    for key, entry in pairs(guildData.players) do
        if type(entry) ~= "table" or (tonumber(entry.receivedAt) or 0) < cutoff then
            guildData.players[key] = nil
        end
    end
    self.db = db
    self.guildData = guildData
    return true
end

function Sync:IsGuildMember(name)
    local key = KeyName(name)
    if not key then return false end
    for _, member in ipairs(GVE:GetMembers() or {}) do
        if KeyName(member.name) == key then return true end
    end
    return false
end

function Sync:GetMember(name)
    local key = KeyName(name)
    for _, member in ipairs(GVE:GetMembers() or {}) do
        if KeyName(member.name) == key then return member end
    end
end

function Sync:GetOwnCharacterSnapshot(name)
    local wanted = KeyName(name)
    if not wanted or not self.guildData or type(self.guildData.ownByCharacter) ~= "table" then return nil end
    for characterKey, snapshot in pairs(self.guildData.ownByCharacter) do
        local characterName = type(characterKey) == "string" and characterKey:match("([^\031]+)$")
        if characterName and KeyName(characterName) == wanted and type(snapshot) == "table" then
            return snapshot, characterName
        end
    end
end

function Sync:GetPlayerData(name)
    if IsOwn(name) then return self.own end
    local cached = self.guildData.players[KeyName(name) or ""]
    local ownAlt = self:GetOwnCharacterSnapshot(name)
    if ownAlt and (not cached
    or (tonumber(ownAlt.professionsCapturedAt) or 0) >= (tonumber(cached.professionsCapturedAt) or 0)) then
        return ownAlt
    end
    return cached
end

function Sync:GetShareableSnapshot(name)
    local ownerKey = KeyName(name)
    if not ownerKey then return nil end
    local cached = self.guildData.players[ownerKey]
    local ownAlt = self:GetOwnCharacterSnapshot(name)
    if ownAlt and (not cached
    or (tonumber(ownAlt.professionsCapturedAt) or 0) >= (tonumber(cached.professionsCapturedAt) or 0)) then
        return ownAlt
    end
    return cached
end

---------------------------------------------------------------------------
-- Lokale Erfassung
---------------------------------------------------------------------------
function Sync:CaptureProfession(showMessage, refreshTimestamp)
    if type(self.own) ~= "table" then return false end
    local capturedAt, professions, candidateCount = time(), {}, 0
    local function AddLink(value, source, logMissing)
        if type(value) ~= "string" or value == "" then
            if showMessage and logMissing then DebugLog(source.." liefert keinen Link") end
            return false
        end
        candidateCount = candidateCount + 1
        local tradeLink, name, skill, maxSkill = ParseTradeLink(value)
        if tradeLink then
            professions[name] = {name=name, skill=skill, maxSkill=maxSkill, capturedAt=capturedAt, tradeLink=tradeLink}
            if showMessage then DebugLog(source.." akzeptiert: "..DebugLink(tradeLink)) end
            return true
        end
        if showMessage and (logMissing or value:find("|Htrade:", 1, true)) then
            DebugLog(source.." abgelehnt: "..DebugLink(value))
        end
        return false
    end

    if showMessage then
        DebugLog("Capture gestartet; GetNumSpellTabs="..type(GetNumSpellTabs)
            ..", GetSpellTabInfo="..type(GetSpellTabInfo)
            ..", GetSpellLink="..type(GetSpellLink)
            ..", GetTradeSkillListLink="..type(GetTradeSkillListLink))
    end

    -- In 3.3.5a entspricht der zweite Rueckgabewert exakt dem Link, den der
    -- Client beim Shift-Klick des Berufs aus dem Zauberbuch in den Chat setzt.
    if type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" and type(GetSpellLink) == "function" then
        local tabCount = math.min(tonumber(GetNumSpellTabs()) or 0, 64)
        if showMessage then DebugLog("Zauberbuch-Tabs: "..tabCount) end
        for tab = 1, tabCount do
            local tabName, _, offset, spellCount = GetSpellTabInfo(tab)
            offset, spellCount = tonumber(offset) or 0, math.min(tonumber(spellCount) or 0, 5000)
            if showMessage then
                DebugLog("Tab "..tab.." ("..tostring(tabName).."): Offset "..offset..", Einträge "..spellCount)
            end
            for slot = offset + 1, offset + spellCount do
                local spellLink, tradeLink = GetSpellLink(slot, BOOKTYPE_SPELL or "spell")
                local accepted = AddLink(tradeLink, "GetSpellLink Slot "..slot.." Rückgabewert 2", false)
                -- Einige 3.3.5a-Serverimplementierungen geben den Trade-Link
                -- abweichend als ersten Wert zurück. Der strikte Parser stellt
                -- sicher, dass gewöhnliche Zauberlinks nicht übernommen werden.
                if not accepted and type(spellLink) == "string" and spellLink:find("|Htrade:", 1, true) then
                    AddLink(spellLink, "GetSpellLink Slot "..slot.." Rückgabewert 1", true)
                end
            end
        end
    elseif showMessage then
        DebugLog("Zauberbuch-APIs sind nicht vollständig verfügbar")
    end

    -- Fallback fuer Clients, die den Berufslink erst bei geoeffnetem eigenem
    -- TradeSkill-Fenster materialisieren. Fremde/verlinkte Fenster ablehnen.
    local ownTradeSkill = not (type(IsTradeSkillLinked) == "function" and IsTradeSkillLinked())
    local tradeSkillVisible = not TradeSkillFrame or TradeSkillFrame:IsShown()
    if showMessage then
        DebugLog("Berufefenster-Fallback: eigen="..tostring(ownTradeSkill)
            ..", sichtbar="..tostring(tradeSkillVisible))
    end
    if ownTradeSkill and type(GetTradeSkillListLink) == "function" and tradeSkillVisible then
        AddLink(GetTradeSkillListLink(), "GetTradeSkillListLink", true)
    end

    if not next(professions) then
        if showMessage then DebugLog("Capture beendet: 0 Berufe aus "..candidateCount.." Link-Kandidaten") end
        if showMessage then DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[GuildView]|r "..L.openProfession) end
        return false
    end

    local unchanged = true
    local previous = self.own.professions
    if type(previous) ~= "table" then
        unchanged = false
    else
        for name, profession in pairs(professions) do
            if type(previous[name]) ~= "table" or previous[name].tradeLink ~= profession.tradeLink then
                unchanged = false
                break
            end
        end
        if unchanged then
            for name in pairs(previous) do
                if not professions[name] then unchanged = false break end
            end
        end
    end

    if unchanged then
        if refreshTimestamp then
            -- Eine direkte Datenanfrage bestaetigt, dass diese Links gerade
            -- erneut im eigenen Zauberbuch gefunden wurden. Deshalb bekommt
            -- auch ein inhaltlich unveraenderter Snapshot einen frischen
            -- Synchronisierungszeitpunkt.
            for _, profession in pairs(previous) do profession.capturedAt = capturedAt end
            self.own.professionsCapturedAt = capturedAt
            self.own.receivedAt = capturedAt
        end
        if showMessage then
            local count = 0
            for _ in pairs(previous) do count = count + 1 end
            DebugLog("Capture beendet: "..count.." Berufe unverändert")
            DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[GuildView]|r "..L.captured)
        end
        self:RefreshUI()
        return true
    end

    self.own.professions = professions
    local oldestAt
    for _, profession in pairs(self.own.professions) do
        oldestAt = not oldestAt and profession.capturedAt or math.min(oldestAt, profession.capturedAt)
    end
    self.own.professionsCapturedAt = oldestAt or time()
    self.own.receivedAt = time()
    if showMessage then
        local count = 0
        for _ in pairs(self.own.professions) do count = count + 1 end
        DebugLog("Capture beendet: "..count.." Berufe gespeichert")
    end
    if showMessage then DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[GuildView]|r "..L.captured) end
    self:RefreshUI()
    if type(self.Announce) == "function" then self:Announce("U") end
    return true
end

---------------------------------------------------------------------------
-- Kompaktes, defensiv begrenztes Austauschformat
---------------------------------------------------------------------------
function Sync:SerializeProfessions(snapshot)
    local sections, professionKeys, professionCount = {}, {}, 0
    local names = {}
    for name in pairs(snapshot.professions or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return Fold(a) < Fold(b) end)
    for _, name in ipairs(names) do
        local profession = snapshot.professions[name]
        local tradeLink = type(profession) == "table" and SafeTradeLink(profession.tradeLink)
        if tradeLink then
            local safeName = SafeText(name, 128)
            local skill = tonumber(profession.skill)
            local maxSkill = tonumber(profession.maxSkill)
            local capturedAt = tonumber(profession.capturedAt)
            local _, linkLabel, linkSkill, linkMaxSkill = ParseTradeLink(tradeLink)
            if not safeName or not IsInteger(skill, 0, 1000) or not IsInteger(maxSkill, 0, 1000)
            or not IsInteger(capturedAt, 1, time() + 3600) or Fold(linkLabel) ~= Fold(safeName)
            or linkSkill ~= skill or linkMaxSkill ~= maxSkill then return nil, "INVALID" end
            local professionKey = Fold(safeName)
            if professionKeys[professionKey] then return nil, "INVALID" end
            professionKeys[professionKey] = true
            professionCount = professionCount + 1
            if professionCount > 16 then return nil, "TOOBIG" end
            sections[#sections + 1] = Encode(safeName).."~"..skill.."~"..maxSkill.."~"..capturedAt.."~"..Encode(tradeLink)
        end
    end
    local payload = table.concat(sections, "^")
    if #payload > MAX_BYTES then return nil, "TOOBIG" end
    return payload
end

function Sync:DeserializeProfessions(payload, capturedAt)
    if type(payload) ~= "string" or payload == "" then return nil end
    local professions, professionKeys, professionCount, oldestAt = {}, {}, 0, nil
    for _, section in ipairs(Split(payload, "^")) do
        local fields = Split(section, "~")
        if #fields ~= 5 then return nil end
        local name = SafeText(Decode(fields[1] or ""), 128)
        local skill, maxSkill, professionCapturedAt = tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[4])
        local professionKey = name and Fold(name)
        if not name or name == "" or not IsInteger(skill, 0, 1000) or not IsInteger(maxSkill, 0, 1000) or not IsInteger(professionCapturedAt, 1, time() + 3600) or professionKeys[professionKey] then return nil end
        professionCount = professionCount + 1
        if professionCount > 16 then return nil end
        local tradeLink, linkLabel, linkSkill, linkMaxSkill = ParseTradeLink(Decode(fields[5] or ""))
        if not tradeLink or Fold(linkLabel) ~= Fold(name) or linkSkill ~= skill or linkMaxSkill ~= maxSkill then return nil end
        professionKeys[professionKey] = true
        professions[name] = {name=name, skill=skill, maxSkill=maxSkill, capturedAt=professionCapturedAt, tradeLink=tradeLink}
        oldestAt = not oldestAt and professionCapturedAt or math.min(oldestAt, professionCapturedAt)
    end
    return {professions=professions, professionsCapturedAt=oldestAt or capturedAt}
end

function Sync:QueueMessage(message, target, channel)
    if #self.sendQueue >= MAX_CHUNKS * 2 then return end
    self.sendQueue[#self.sendQueue + 1] = {message=message, target=target, channel=channel or "WHISPER"}
end

function Sync:QueueControlMessage(message, target, channel)
    if #self.sendQueue >= MAX_CHUNKS * 2 then return false end
    table.insert(self.sendQueue, 1, {message=message, target=target, channel=channel or "WHISPER"})
    return true
end

local function NewRequestID()
    return tostring(math.floor(GetTime() * 1000) % 10000000)..tostring(math.random(100, 999))
end

function Sync:PruneCachedPlayers()
    local cached = {}
    for key, value in pairs(self.guildData.players) do
        cached[#cached + 1] = {key=key, receivedAt=tonumber(value.receivedAt) or 0}
    end
    table.sort(cached, function(a, b) return a.receivedAt < b.receivedAt end)
    while #cached > MAX_CACHED_PLAYERS do
        self.guildData.players[cached[1].key] = nil
        table.remove(cached, 1)
    end
end

function Sync:RequestRelayCatalog(peer, force)
    local clean, key = CleanName(peer), KeyName(peer)
    local member = clean and self:GetMember(clean)
    if not clean or not key or IsOwn(clean) or not member or not member.online then return false end
    local now = GetTime()
    if self.relayCatalogPending[key] then return false end
    if not force and self.relayCatalogCooldown[key]
    and now - self.relayCatalogCooldown[key] < AUTO_REQUEST_RETRY then return false end
    local requestID = NewRequestID()
    self.relayCatalogPending[key] = {requestID=requestID, deadline=now + REQUEST_TIMEOUT}
    self.relayCatalogCooldown[key] = now
    if self:QueueControlMessage("C|"..requestID, clean) then return true end
    self.relayCatalogPending[key] = nil
    return false
end

function Sync:SendRelayCatalog(target, requestID)
    local catalogByOwner = {}
    local function AddCatalogEntry(owner, entry)
        owner = CleanName(owner)
        local ownerKey = KeyName(owner)
        local stamp = type(entry) == "table" and tonumber(entry.professionsCapturedAt)
        if owner and ownerKey and stamp and entry.professions and self:IsGuildMember(owner)
        and IsInteger(stamp, 1, time() + 3600) then
            local previous = catalogByOwner[ownerKey]
            if not previous or stamp > previous.stamp then
                catalogByOwner[ownerKey] = {owner=owner, stamp=stamp}
            end
        end
    end
    for _, entry in pairs(self.guildData.players or {}) do
        -- Auch weitergeleitete Snapshots duerfen erneut angeboten werden.
        -- Empfaenger akzeptieren sie nur bei strikt neuerem Besitzer-Zeitstempel;
        -- dadurch laufen identische Daten nicht im Kreis.
        AddCatalogEntry(type(entry) == "table" and entry.displayName, entry)
    end
    -- Accountweite SavedVariables erlauben es, auch eigene derzeit offline
    -- Twinks mit ihrem letzten selbst erfassten Stand anzubieten.
    if self.db.settings.shareProfessions then
        for characterKey, entry in pairs(self.guildData.ownByCharacter or {}) do
            local owner = type(characterKey) == "string" and characterKey:match("([^\031]+)$")
            if not IsOwn(owner) then AddCatalogEntry(owner, entry) end
        end
    end
    local catalog = {}
    for _, value in pairs(catalogByOwner) do catalog[#catalog + 1] = value end
    table.sort(catalog, function(a, b) return KeyName(a.owner) < KeyName(b.owner) end)
    for _, value in ipairs(catalog) do
        self:QueueMessage("V|"..requestID.."|"..Encode(value.owner).."|"..value.stamp, target)
    end
    self:QueueMessage("K|"..requestID, target)
    DebugLog("Relay-Katalog an "..target..": "..#catalog.." neueste Snapshots")
end

function Sync:QueueRelayCandidate(peer, owner, advertisedAt)
    local cleanPeer, cleanOwner = CleanName(peer), CleanName(owner)
    local peerKey, ownerKey = KeyName(cleanPeer), KeyName(cleanOwner)
    local stamp = tonumber(advertisedAt)
    if not cleanPeer or not cleanOwner or not peerKey or not ownerKey
    or peerKey == ownerKey or IsOwn(cleanOwner) or not self:IsGuildMember(cleanOwner)
    or not IsInteger(stamp, 1, time() + 3600) then return false end
    -- Vergleiche gegen den besten lokal bekannten Stand. Dazu gehoeren auch
    -- eigene, derzeit offline gespielte Charaktere aus den SavedVariables.
    local cached = self:GetPlayerData(cleanOwner)
    if cached and (tonumber(cached.professionsCapturedAt) or 0) >= stamp then return false end
    if self.relayOwnerPending[ownerKey] then return false end
    local queued = self.relayQueued[ownerKey]
    if queued then
        if stamp > queued.stamp then queued.peer, queued.stamp = cleanPeer, stamp end
        return true
    end
    local candidate = {peer=cleanPeer, owner=cleanOwner, ownerKey=ownerKey, stamp=stamp}
    self.relayQueued[ownerKey] = candidate
    self.relayQueue[#self.relayQueue + 1] = candidate
    return true
end

function Sync:RequestRelayedSnapshot(candidate)
    if type(candidate) ~= "table" then return false end
    local cached = self:GetPlayerData(candidate.owner)
    if cached and (tonumber(cached.professionsCapturedAt) or 0) >= candidate.stamp then return false end
    local requestID = NewRequestID()
    local peerKey = KeyName(candidate.peer)
    local transferKey = peerKey.."|"..requestID
    self.relayPending[transferKey] = {
        requestID=requestID, peer=candidate.peer, owner=candidate.owner,
        ownerKey=candidate.ownerKey, advertisedAt=candidate.stamp,
        started=GetTime(), deadline=GetTime() + ABSOLUTE_TRANSFER_TIMEOUT,
    }
    self.relayOwnerPending[candidate.ownerKey] = transferKey
    SendAddonMessage(PREFIX, "R|"..requestID.."|"..Encode(candidate.owner), "WHISPER", candidate.peer)
    return true
end

function Sync:SendRelayedSnapshot(target, requestID, owner)
    local entry = self:GetShareableSnapshot(owner)
    local ownAlt = self:GetOwnCharacterSnapshot(owner)
    if entry == ownAlt and not self.db.settings.shareProfessions then return false end
    if not entry or not entry.professions or not self:IsGuildMember(owner) then return false end
    local payload = self:SerializeProfessions(entry)
    if not payload or payload == "" or #payload > MAX_BYTES then return false end
    local chunks = math.ceil(#payload / CHUNK_BYTES)
    if chunks < 1 or chunks > MAX_CHUNKS or #self.sendQueue + chunks + 2 > MAX_CHUNKS * 2 then return false end
    local capturedAt = tonumber(entry.professionsCapturedAt)
    if not IsInteger(capturedAt, 1, time() + 3600) then return false end
    self:QueueMessage("RB|"..requestID.."|"..Encode(owner).."|"..capturedAt.."|"..chunks, target)
    for index = 1, chunks do
        self:QueueMessage("RD|"..requestID.."|"..index.."|"..payload:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES), target)
    end
    self:QueueMessage("RE|"..requestID, target)
    DebugLog("Relay-Snapshot "..owner.." an "..target.." gesendet")
    return true
end

function Sync:Announce(command, target)
    if not target and type(IsInGuild) == "function" and not IsInGuild() then return false end
    if command ~= "H" then
        if not self.db or not self.db.settings.shareProfessions
        or not self.own or not self.own.professions then return false end
    end
    local stamp = self.own and tonumber(self.own.professionsCapturedAt) or 0
    local message = command.."|"..math.max(0, math.floor(stamp or 0))
    if target then return self:QueueControlMessage(message, target, "WHISPER") end
    self:QueueMessage(message, nil, "GUILD")
    return true
end

function Sync:QueueAutoRequest(name, advertisedAt, force)
    local clean, stamp = CleanName(name), tonumber(advertisedAt)
    local key = KeyName(clean)
    local minimumStamp = force and 0 or 1
    if not clean or not key or IsOwn(clean) or not IsInteger(stamp, minimumStamp, time() + 3600) then return false end
    local member = self:GetMember(clean)
    if not member then return false end
    local cached = self:GetPlayerData(clean)
    if not force and cached and cached.professions and (tonumber(cached.professionsCapturedAt) or 0) >= stamp then return false end
    local now = GetTime()
    if self.pending[key] or self.autoQueued[key]
    or not force and self.autoLastRequest[key] and now - self.autoLastRequest[key] < AUTO_REQUEST_RETRY then return false end
    if force then
        -- Der manuelle Knopf ist eine ausdrueckliche Benutzeraktion und darf
        -- deshalb einen alten automatischen Retry-/Cooldown-Zeitpunkt umgehen.
        self.autoLastRequest[key] = nil
        self.cooldowns[key] = nil
    end
    self.autoQueued[key] = true
    self.autoQueue[#self.autoQueue + 1] = {name=clean, key=key, force=force and true or false}
    return true
end

function Sync:ManualBroadcastSync()
    if not self.db then return false end

    -- Eigene Links unmittelbar neu einlesen. Auch wenn sie unveraendert sind,
    -- wird danach U gesendet: Der Benutzer hat den Push bewusst angefordert.
    local captured = self:CaptureProfession(false, true)
    if captured and self.own and self.own.professions then
        if self.db.settings.shareProfessions then self:Announce("U") end
    end

    -- H ist der kompatible, gildenweite Discovery-Broadcast. Auch aeltere
    -- Addon-Releases mit demselben Protokoll kennen ihn und antworten per A.
    -- Antworten in diesem kurzen Fenster werden absichtlich erneut abgefragt,
    -- selbst wenn der lokale Cache denselben Zeitstempel meldet.
    self.forceDiscoveryUntil = GetTime() + REQUEST_TIMEOUT
    -- Bereits bekannte Online-Mitglieder werden sofort eingeplant. Der
    -- Guild-Broadcast bleibt zusaetzlich aktiv, damit auch gerade erst
    -- entdeckte kompatible Clients antworten koennen.
    wipe(self.autoQueue)
    wipe(self.autoQueued)
    wipe(self.relayQueue)
    wipe(self.relayQueued)
    local directRequests = 0
    for _, member in ipairs(GVE:GetMembers() or {}) do
        if member.online and not IsOwn(member.name) then
            local memberKey = KeyName(member.name)
            if memberKey then
                self.pending[memberKey] = nil
                self.receiving[memberKey] = nil
                self.viewMessages[memberKey] = nil
                self.relayCatalogPending[memberKey] = nil
            end
            if self:QueueAutoRequest(member.name, 0, true) then directRequests = directRequests + 1 end
            self:RequestRelayCatalog(member.name, true)
        end
    end
    self:Announce("H")
    DebugLog("Manuelle Gildensynchronisierung: "..directRequests.." direkte Online-Anfragen + Guild-Broadcast")
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33aaff[GuildView]|r "..L.syncSent)
    end
    return true
end

function Sync:SendSnapshot(target, requestID)
    if not self.db.settings.shareProfessions then
        self:QueueControlMessage("N|"..requestID.."|DENIED", target)
        return
    end
    if #self.sendQueue > MAX_QUEUE_BEFORE_BUSY then
        self:QueueControlMessage("N|"..requestID.."|BUSY", target)
        return
    end
    local payload, payloadError
    if self.own.professions then payload, payloadError = self:SerializeProfessions(self.own) end
    local capturedAt = self.own.professionsCapturedAt
    if payloadError then
        self:QueueControlMessage("N|"..requestID.."|TOOBIG", target)
        return
    end
    if not payload or payload == "" then
        self:QueueControlMessage("N|"..requestID.."|EMPTY", target)
        return
    end
    if #payload > MAX_BYTES then
        self:QueueControlMessage("N|"..requestID.."|TOOBIG", target)
        return
    end
    local chunks = math.ceil(#payload / CHUNK_BYTES)
    if chunks < 1 then chunks = 1 end
    if chunks > MAX_CHUNKS then
        self:QueueControlMessage("N|"..requestID.."|TOOBIG", target)
        return
    end
    if #self.sendQueue + chunks + 2 > MAX_CHUNKS * 2 then
        self:QueueControlMessage("N|"..requestID.."|BUSY", target)
        return
    end
    DebugLog("Sende Berufs-Snapshot an "..tostring(target)..": "..chunks.." Teil(e), Zeitstempel "..tostring(capturedAt))
    self:QueueMessage("B|"..requestID.."|"..(tonumber(capturedAt) or time()).."|"..chunks, target)
    for index = 1, chunks do
        local part = payload:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES)
        self:QueueMessage("D|"..requestID.."|"..index.."|"..part, target)
    end
    self:QueueMessage("E|"..requestID, target)
end

function Sync:Request(name, automatic, force)
    local clean = CleanName(name)
    local key = KeyName(clean)
    if not clean or not key or not self:IsGuildMember(clean) then return end
    if IsOwn(clean) then
        self:CaptureProfession(true)
        return
    end
    local now = GetTime()
    if self.pending[key] then return false end
    if not force and self.cooldowns[key] and now - self.cooldowns[key] < REQUEST_COOLDOWN then return end
    self.cooldowns[key] = now
    if automatic then self.autoLastRequest[key] = now end
    local requestID = NewRequestID()
    self.pending[key] = {
        started=now, lastActivity=now, deadline=now + ABSOLUTE_TRANSFER_TIMEOUT,
        requestID=requestID, requireFresh=force and true or false,
        requestedAt=time(),
    }
    SendAddonMessage(PREFIX, "Q|"..requestID, "WHISPER", clean)
    self.viewMessages[key] = L.pending
    self:RefreshUI()
    return true
end

function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 240 then return end
    local cleanSender = CleanName(sender)
    if not cleanSender or not self:IsGuildMember(cleanSender) then return end
    local fields = Split(message, "|")
    local command, requestID = fields[1], fields[2]

    if command == "H" or command == "U" or command == "A" then
        if #fields ~= 2 then return end
        local advertisedAt = tonumber(requestID)
        if not IsInteger(advertisedAt, 0, time() + 3600) or IsOwn(cleanSender) then return end
        if command == "H" and channel == "GUILD" then
            self:Announce("A", cleanSender)
            if advertisedAt > 0 then self:QueueAutoRequest(cleanSender, advertisedAt) end
            self:RequestRelayCatalog(cleanSender, false)
        elseif command == "U" and channel == "GUILD" then
            self:QueueAutoRequest(cleanSender, advertisedAt)
        elseif command == "A" and channel == "WHISPER" then
            local force = self.forceDiscoveryUntil and GetTime() <= self.forceDiscoveryUntil
            self:QueueAutoRequest(cleanSender, advertisedAt, force and true or false)
            self:RequestRelayCatalog(cleanSender, force and true or false)
        end
        return
    end

    local senderKey = KeyName(cleanSender)
    if command == "C" and channel == "WHISPER" then
        if #fields ~= 2 or not requestID or not requestID:match("^%d+$") then return end
        self:SendRelayCatalog(cleanSender, requestID)
        return
    elseif command == "V" and channel == "WHISPER" then
        if #fields ~= 4 then return end
        local catalog = self.relayCatalogPending[senderKey]
        if not catalog or catalog.requestID ~= requestID then return end
        self:QueueRelayCandidate(cleanSender, Decode(fields[3] or ""), tonumber(fields[4]))
        return
    elseif command == "K" and channel == "WHISPER" then
        if #fields ~= 2 then return end
        local catalog = self.relayCatalogPending[senderKey]
        if catalog and catalog.requestID == requestID then self.relayCatalogPending[senderKey] = nil end
        return
    elseif command == "R" and channel == "WHISPER" then
        if #fields ~= 3 or not requestID or not requestID:match("^%d+$") then return end
        local owner = CleanName(Decode(fields[3] or ""))
        local relayCooldownKey = senderKey.."|"..tostring(KeyName(owner) or "")
        local now = GetTime()
        if owner and KeyName(owner) ~= senderKey
        and (not self.relayIncomingCooldown[relayCooldownKey]
            or now - self.relayIncomingCooldown[relayCooldownKey] >= REQUEST_COOLDOWN) then
            self.relayIncomingCooldown[relayCooldownKey] = now
            self:SendRelayedSnapshot(cleanSender, requestID, owner)
        end
        return
    elseif command == "RB" and channel == "WHISPER" then
        if #fields ~= 5 then return end
        local transferKey = senderKey.."|"..tostring(requestID or "")
        local pending = self.relayPending[transferKey]
        local owner = CleanName(Decode(fields[3] or ""))
        local capturedAt, chunks = tonumber(fields[4]), tonumber(fields[5])
        if not pending or not owner or KeyName(owner) ~= pending.ownerKey
        or not IsInteger(capturedAt, 1, time() + 3600)
        or not IsInteger(chunks, 1, MAX_CHUNKS) then return end
        pending.lastActivity = GetTime()
        self.relayReceiving[transferKey] = {
            requestID=requestID, owner=owner, capturedAt=capturedAt,
            chunks=chunks, parts={}, bytes=0,
        }
        return
    elseif command == "RD" and channel == "WHISPER" then
        if #fields ~= 4 then return end
        local transferKey = senderKey.."|"..tostring(requestID or "")
        local pending, transfer = self.relayPending[transferKey], self.relayReceiving[transferKey]
        local index, part = tonumber(fields[3]), fields[4] or ""
        if not pending or not transfer or not IsInteger(index, 1, transfer.chunks) or #part > CHUNK_BYTES then return end
        pending.lastActivity = GetTime()
        if not transfer.parts[index] then
            transfer.bytes = transfer.bytes + #part
            if transfer.bytes > MAX_BYTES then self.relayReceiving[transferKey] = nil return end
            transfer.parts[index] = part
        end
        return
    elseif command == "RE" and channel == "WHISPER" then
        if #fields ~= 2 then return end
        local transferKey = senderKey.."|"..tostring(requestID or "")
        local pending, transfer = self.relayPending[transferKey], self.relayReceiving[transferKey]
        if not pending or not transfer then return end
        local complete = {}
        for index = 1, transfer.chunks do
            if transfer.parts[index] == nil then return end
            complete[index] = transfer.parts[index]
        end
        local decoded = self:DeserializeProfessions(table.concat(complete), transfer.capturedAt)
        self.relayReceiving[transferKey] = nil
        self.relayPending[transferKey] = nil
        if self.relayOwnerPending[pending.ownerKey] == transferKey then self.relayOwnerPending[pending.ownerKey] = nil end
        if not decoded
        or (tonumber(decoded.professionsCapturedAt) or 0) ~= transfer.capturedAt
        or transfer.capturedAt < (tonumber(pending.advertisedAt) or 0) then return end
        local existing = self:GetPlayerData(pending.owner)
        if existing and (tonumber(existing.professionsCapturedAt) or 0) >= (tonumber(decoded.professionsCapturedAt) or 0) then return end
        self.guildData.players[pending.ownerKey] = {
            displayName=pending.owner,
            professions=decoded.professions,
            professionsCapturedAt=decoded.professionsCapturedAt,
            receivedAt=time(), relayFrom=cleanSender, directSource=false,
        }
        self.viewMessages[pending.ownerKey] = nil
        self:PruneCachedPlayers()
        DebugLog("Neuer Relay-Snapshot für "..pending.owner.." über "..cleanSender
            .." übernommen: "..tostring(decoded.professionsCapturedAt))
        self:RefreshUI()
        return
    end

    if not requestID or #requestID > 12 or not requestID:match("^%d+$") then return end

    if command == "Q" and channel == "WHISPER" then
        if #fields ~= 2 then return end
        local now = GetTime()
        if self.incomingCooldown[senderKey] and now - self.incomingCooldown[senderKey] < 30 then return end
        self.incomingCooldown[senderKey] = now
        local captured = self:CaptureProfession(false, true)
        DebugLog("Direkte Anfrage von "..cleanSender..": lokale Erfassung="..tostring(captured))
        self:SendSnapshot(cleanSender, requestID)
        return
    end
    if channel ~= "WHISPER" then return end

    local pendingKey = KeyName(cleanSender)
    local pending = self.pending[pendingKey]
    if not pending or pending.requestID ~= requestID then return end

    if command == "N" then
        if #fields ~= 3 then return end
        self.pending[pendingKey] = nil
        self.receiving[pendingKey] = nil
        self.viewMessages[pendingKey] = fields[3] == "DENIED" and L.denied or fields[3] == "BUSY" and L.busy or fields[3] == "TOOBIG" and L.tooBig or L.empty
        self:RefreshUI()
    elseif command == "B" then
        if #fields ~= 4 then return end
        local capturedAt, chunks = tonumber(fields[3]), tonumber(fields[4])
        if not capturedAt or capturedAt < 0 or capturedAt > time() + 3600 or not chunks or chunks < 1 or chunks > MAX_CHUNKS then return end
        pending.lastActivity = GetTime()
        self.receiving[pendingKey] = {requestID=requestID, capturedAt=capturedAt, chunks=chunks, parts={}, bytes=0}
    elseif command == "D" then
        if #fields ~= 4 then return end
        local transfer = self.receiving[pendingKey]
        local index, part = tonumber(fields[3]), fields[4] or ""
        if not transfer or transfer.requestID ~= requestID or not IsInteger(index, 1, transfer.chunks) or #part > CHUNK_BYTES then return end
        pending.lastActivity = GetTime()
        if not transfer.parts[index] then
            transfer.bytes = transfer.bytes + #part
            if transfer.bytes > MAX_BYTES then self.receiving[pendingKey] = nil return end
            transfer.parts[index] = part
        end
    elseif command == "E" then
        if #fields ~= 2 then return end
        local transfer = self.receiving[pendingKey]
        if not transfer or transfer.requestID ~= requestID then return end
        local complete = {}
        for index = 1, transfer.chunks do
            if transfer.parts[index] == nil then return end
            complete[index] = transfer.parts[index]
        end
        local payload = table.concat(complete)
        local decoded = self:DeserializeProfessions(payload, transfer.capturedAt)
        self.receiving[pendingKey] = nil
        self.pending[pendingKey] = nil
        if not decoded then
            self.viewMessages[pendingKey] = L.empty
            self:RefreshUI()
            return
        end
        local playerKey = KeyName(cleanSender)
        local existing = self.guildData.players[playerKey]
        if existing and (tonumber(existing.professionsCapturedAt) or 0) > (tonumber(decoded.professionsCapturedAt) or 0) then
            self.viewMessages[pendingKey] = nil
            self:RefreshUI()
            return
        end
        local entry = self.guildData.players[playerKey] or {displayName=cleanSender}
        entry.professions = decoded.professions
        entry.professionsCapturedAt = decoded.professionsCapturedAt
        entry.displayName = cleanSender
        entry.receivedAt = time()
        entry.relayFrom = nil
        entry.directSource = true
        self.guildData.players[playerKey] = entry
        self.autoLastRequest[pendingKey] = nil
        self:PruneCachedPlayers()
        if pending.requireFresh
        and (tonumber(decoded.professionsCapturedAt) or 0) < (tonumber(pending.requestedAt) or 0) - 60 then
            self.viewMessages[pendingKey] = L.staleReply
        else
            self.viewMessages[pendingKey] = nil
        end
        DebugLog("Snapshot von "..cleanSender.." empfangen: Zeitstempel "
            ..tostring(decoded.professionsCapturedAt)..", frisch angefordert="..tostring(pending.requireFresh))
        self:RefreshUI()
    end
end

---------------------------------------------------------------------------
-- Benutzeroberflaeche
---------------------------------------------------------------------------
local function ContainsFolded(value, needle)
    return needle == "" or Fold(value):find(needle, 1, true) ~= nil
end

-- Rank chains from AzerothCore's 3.3.5 spell_ranks table:
-- https://github.com/azerothcore/azerothcore-wotlk/blob/master/data/sql/base/db_world/spell_ranks.sql
-- A trade-link spell identifies the profession independently of the sender's
-- client language. Never rewrite its localized label or recipe bitmap.
local PROFESSION_FAMILIES = {
    {base=2259, en="Alchemy", de="Alchemie", ranks={2259,3101,3464,11611,28596,51304}},
    {base=2018, en="Blacksmithing", de="Schmiedekunst", ranks={2018,3100,3538,9785,29844,51300}},
    {base=7411, en="Enchanting", de="Verzauberkunst", ranks={7411,7412,7413,13920,28029,51313}},
    {base=4036, en="Engineering", de="Ingenieurskunst", ranks={4036,4037,4038,12656,30350,51306}},
    {base=45357, en="Inscription", de="Inschriftenkunde", ranks={45357,45358,45359,45360,45361,45363}},
    {base=25229, en="Jewelcrafting", de="Juwelenschleifen", ranks={25229,25230,28894,28895,28897,51311}},
    {base=2108, en="Leatherworking", de="Lederverarbeitung", ranks={2108,3104,3811,10662,32549,51302}},
    {base=3908, en="Tailoring", de="Schneiderei", ranks={3908,3909,3910,12180,26790,51309}},
    {base=2550, en="Cooking", de="Kochkunst", ranks={2550,3102,3413,18260,33359,51296}},
    {base=3273, en="First Aid", de="Erste Hilfe", ranks={3273,3274,7924,10846,27028,45542}},
    {base=7620, en="Fishing", de="Angeln", ranks={7620,7731,7732,18248,33095,51294}},
    {base=2575, en="Mining", de="Bergbau", ranks={2575,2576,3564,10248,29354,50310}},
    {base=2366, en="Herbalism", de="Kräuterkunde", ranks={2366,2368,3570,11993,28695,50300}},
    {base=8613, en="Skinning", de="Kürschnerei", ranks={8613,8617,8618,10768,32678,50305}},
}
local PROFESSION_BY_SPELL, PROFESSION_BY_NAME = {}, {}
for _, family in ipairs(PROFESSION_FAMILIES) do
    for _, spellID in ipairs(family.ranks) do PROFESSION_BY_SPELL[spellID] = family end
    PROFESSION_BY_NAME[Fold(family.en)] = family
    PROFESSION_BY_NAME[Fold(family.de)] = family
end

local function ProfessionCategoryKey(name, profession)
    local _, _, _, _, spellID = ParseTradeLink(profession and profession.tradeLink)
    local family = PROFESSION_BY_SPELL[spellID] or PROFESSION_BY_NAME[Fold(name)]
    if not family then return "name:"..Fold(name), spellID, name end
    local localName = type(GetSpellInfo) == "function" and GetSpellInfo(family.base)
    if type(localName) ~= "string" or localName == "" then
        localName = GetLocale() == "deDE" and family.de or family.en
    end
    return "profession:"..family.base, family.base, localName, family
end

local function ProfessionIsStale(profession)
    local stamp = profession and tonumber(profession.capturedAt)
    return stamp and time() - stamp > 7 * 86400 or false
end

function Sync:BuildPlayerList()
    local needle = self.playerSearch and Fold(self.playerSearch:GetText()) or ""
    local categories, synchronized = {}, {}
    local onlineFilter = self.onlineFilter or "all"
    local ageFilter = self.ageFilter or "all"
    local function MemberAllowed(member)
        return onlineFilter == "all" or onlineFilter == "online" and member.online
            or onlineFilter == "offline" and not member.online
    end
    local function Add(categoryKey, categoryName, member, profession, spellID, order, countSynchronized, relayFrom)
        if not MemberAllowed(member) then return end
        if profession then
            local stale = ProfessionIsStale(profession)
            if ageFilter == "current" and stale or ageFilter == "stale" and not stale then return end
        elseif ageFilter ~= "all" then
            return
        end
        local key = categoryKey
        local category = categories[key]
        if not category then
            category = {key=key, name=categoryName, spellID=spellID, order=order, members={}, memberKeys={}, onlineCount=0}
            categories[key] = category
        elseif Fold(categoryName) < Fold(category.name) then
            category.name = categoryName
        end
        local memberKey = KeyName(member.name)
        if memberKey and not category.memberKeys[memberKey] then
            category.memberKeys[memberKey] = true
            category.members[#category.members + 1] = {
                member=member, profession=profession,
                professionName=categoryName, relayFrom=relayFrom,
            }
            if member.online then category.onlineCount = category.onlineCount + 1 end
            if countSynchronized ~= false then synchronized[memberKey] = true end
        end
    end

    for _, member in ipairs(GVE:GetMembers() or {}) do
        local data = self:GetPlayerData(member.name)
        local memberMatch = ContainsFolded(member.name, needle)
        local hasData = false
        if data then
            for professionName, profession in pairs(data.professions or {}) do
                local tradeLink = type(profession) == "table" and SafeTradeLink(profession.tradeLink)
                if tradeLink then
                    hasData = true
                    local categoryKey, spellID, categoryName, family = ProfessionCategoryKey(professionName, profession)
                    local professionMatch = ContainsFolded(professionName, needle)
                        or ContainsFolded(categoryName, needle)
                        or family and (ContainsFolded(family.en, needle) or ContainsFolded(family.de, needle))
                    if memberMatch or professionMatch then
                        Add(categoryKey, categoryName, member, profession, spellID, 1, true, data.relayFrom)
                    end
                end
            end
        end
        if not hasData and memberMatch then
            Add("unsynchronized", L.notSynchronized, member, nil, nil, 2, false)
        end
    end

    local orderedCategories = {}
    for _, category in pairs(categories) do orderedCategories[#orderedCategories + 1] = category end
    table.sort(orderedCategories, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return Fold(a.name) < Fold(b.name)
    end)

    local list = {}
    self.categoryKeys = {}
    self.expandedProfessions = self.expandedProfessions or {}
    if not self.expansionInitialized and needle == "" then
        for _, category in ipairs(orderedCategories) do
            if category.order == 1 then self.expandedProfessions[category.key] = true break end
        end
        self.expansionInitialized = true
    end
    for _, category in ipairs(orderedCategories) do
        table.sort(category.members, function(a, b)
            if a.member.online ~= b.member.online then return a.member.online and true or false end
            return Fold(a.member.name) < Fold(b.member.name)
        end)
        self.categoryKeys[#self.categoryKeys + 1] = category.key
        local expanded = needle ~= "" or self.expandedProfessions[category.key]
        list[#list + 1] = {
            header=true, categoryKey=category.key, category=category.name,
            count=#category.members, onlineCount=category.onlineCount,
            expanded=expanded and true or false, spellID=category.spellID,
        }
        if expanded then
            for _, value in ipairs(category.members) do
                list[#list + 1] = {
                    member=value.member, profession=value.profession,
                    professionName=value.professionName, categoryKey=category.key,
                }
            end
        end
    end
    local playerCount = 0
    for _ in pairs(synchronized) do playerCount = playerCount + 1 end
    self.playerMatchCount = playerCount
    self.playerList = list
end

function Sync:ToggleCategory(categoryKey)
    if not categoryKey then return end
    if self.playerSearch and self.playerSearch:GetText() ~= "" then return end
    self.expandedProfessions = self.expandedProfessions or {}
    self.expandedProfessions[categoryKey] = not self.expandedProfessions[categoryKey]
    self:RefreshPlayers()
end

function Sync:SetAllCategories(expanded)
    self.expandedProfessions = self.expandedProfessions or {}
    for _, key in ipairs(self.categoryKeys or {}) do self.expandedProfessions[key] = expanded and true or nil end
    self:RefreshPlayers()
end

function Sync:UpdateExpandButton()
    if not self.expandButton then return end
    local anyExpanded = false
    for _, key in ipairs(self.categoryKeys or {}) do
        if self.expandedProfessions and self.expandedProfessions[key] then anyExpanded = true break end
    end
    self.expandButton:SetText(anyExpanded and L.closeAll or L.openAll)
    self.expandButton.expandNext = not anyExpanded
end

function Sync:RefreshPlayers()
    if not self.panel then return end
    self:BuildPlayerList()
    FauxScrollFrame_Update(self.playerScroll, #self.playerList, #self.playerRows, 42)
    local maximumOffset = math.max(0, #self.playerList - #self.playerRows)
    local offset = math.min(FauxScrollFrame_GetOffset(self.playerScroll), maximumOffset)
    FauxScrollFrame_SetOffset(self.playerScroll, offset)
    self.playerCount:SetText(format(L.synchronized, self.playerMatchCount or 0).."  ·  "..L.syncActive)
    self:UpdateExpandButton()
    if self.emptyText then
        if #self.playerList == 0 then self.emptyText:SetText(L.noResults); self.emptyText:Show() else self.emptyText:Hide() end
    end
    for index, row in ipairs(self.playerRows) do
        local entry = self.playerList[index + offset]
        local member = entry and entry.member
        row.entry = entry
        row.member = nil
        row.tradeLink = nil
        row.categoryKey = nil
        row.icon:Hide()
        row.statusDot:Hide()
        row.toggle:SetText("")
        row.name:SetText("")
        row.rank:SetText("")
        row.link:SetText("")
        row.skill:SetText("")
        row.age:SetText("")
        row.status:SetText("")
        row.rowSelected = false
        if entry and entry.header then
            row.categoryKey = entry.categoryKey
            row.toggle:SetText(entry.expanded and "-" or "+")
            row.name:SetText(entry.category)
            row.name:SetTextColor(0.88, 0.93, 0.97)
            row.rank:SetText(format(L.onlineCount, entry.count or 0, entry.onlineCount or 0))
            row.icon:Show()
            local texture
            if entry.spellID and type(GetSpellInfo) == "function" then
                local _, _, spellTexture = GetSpellInfo(entry.spellID)
                texture = spellTexture
            end
            if not texture and entry.spellID and type(GetSpellTexture) == "function" then
                texture = GetSpellTexture(entry.spellID)
            end
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.rowAlternate = false
            row.rowSelected = entry.expanded
            PaintPlayerRow(row, false)
            row:Show()
        elseif member then
            row.member = member
            row.tradeLink = entry.profession and entry.profession.tradeLink or nil
            row.name:SetText(member.name)
            row.name:SetTextColor(member.online and 0.93 or 0.66, member.online and 0.96 or 0.71, member.online and 0.99 or 0.77)
            local statusText = member.online and (FRIENDS_LIST_ONLINE or "Online") or (FRIENDS_LIST_OFFLINE or "Offline")
            row.rank:SetText(((member.rank and member.rank ~= "") and (member.rank.."  ·  ") or "")..statusText)
            row.statusDot:Show()
            SetTextureColor(row.statusDot, member.online and {0.25, 0.84, 0.51, 1} or {0.34, 0.40, 0.47, 1})
            if entry.profession then
                row.link:SetText(entry.profession.tradeLink or ("["..entry.professionName.."]"))
                row.link:SetTextColor(1, 0.82, 0.24)
                row.skill:SetText((entry.profession.skill or 0).." / "..(entry.profession.maxSkill or 0))
                row.age:SetText(AgeText(entry.profession.capturedAt))
                local memberKey = KeyName(member.name)
                local message = self.pending[memberKey] and L.pending or self.viewMessages[memberKey]
                if message then
                    row.status:SetText(message)
                    row.status:SetTextColor(UI_COLOR.borderFocus[1], UI_COLOR.borderFocus[2], UI_COLOR.borderFocus[3])
                elseif entry.relayFrom then
                    local stale = ProfessionIsStale(entry.profession)
                    row.status:SetText(format(stale and L.relayedStale or L.relayedCurrent, entry.relayFrom))
                    local color = stale and UI_COLOR.warn or UI_COLOR.borderFocus
                    row.status:SetTextColor(color[1], color[2], color[3])
                elseif not member.online then
                    row.status:SetText(L.offlineCache)
                    row.status:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
                elseif ProfessionIsStale(entry.profession) then
                    row.status:SetText(L.stale)
                    row.status:SetTextColor(UI_COLOR.warn[1], UI_COLOR.warn[2], UI_COLOR.warn[3])
                else
                    row.status:SetText(L.current)
                    row.status:SetTextColor(UI_COLOR.good[1], UI_COLOR.good[2], UI_COLOR.good[3])
                end
            else
                row.skill:SetText("—")
                row.age:SetText(L.never)
                local memberKey = KeyName(member.name)
                if self.pending[memberKey] then row.status:SetText(L.pending)
                elseif IsOwn(member.name) then row.status:SetText(L.capture)
                elseif member.online then row.status:SetText(L.requestShort)
                else row.status:SetText(FRIENDS_LIST_OFFLINE or "Offline") end
                local actionable = member.online or IsOwn(member.name)
                local color = actionable and UI_COLOR.borderFocus or UI_COLOR.muted
                row.status:SetTextColor(color[1], color[2], color[3])
            end
            row.rowAlternate = (index + offset) % 2 == 0
            PaintPlayerRow(row, row.rowAlternate)
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end
end

function Sync:RefreshUI()
    if not self.panel then return end
    self:RefreshPlayers()
end

function Sync:SetMainTab(tab)
    if self.playerSearch then self.playerSearch:ClearFocus() end
    if GVE.searchBox then GVE.searchBox:ClearFocus() end
    if tab == "sync" then
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT", GVE.f, "TOPLEFT", 10, -5)
        self.header:SetPoint("TOPRIGHT", GVE.f, "TOPRIGHT", -10, -5)
        self.header:SetHeight(48)
        self.closeButton:Show()
        self.headerTitle:Show()
        if GVE.CloseFilterPanel then GVE:CloseFilterPanel() end
        if GVE.lastOnlineWin then GVE.lastOnlineWin:Hide() end
        if GVE.logPanel then GVE.logPanel:Hide() end
        if GVE.detail then GVE.detail:Hide() end
        if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then GuildControlPopupFrame:Hide() end
        self.panel:Show()
        self.membersTab:Enable()
        self.syncTab:Disable()
        SetFlatSelected(self.membersTab, false)
        SetFlatSelected(self.syncTab, true)
        self:RefreshUI()
    else
        self.panel:Hide()
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT", GVE.f, "TOPLEFT", 10, -5)
        self.header:SetPoint("TOPRIGHT", GVE.f, "TOPRIGHT", -10, -5)
        self.header:SetHeight(48)
        self.closeButton:Show()
        self.headerTitle:Show()
        self.membersTab:Disable()
        self.syncTab:Enable()
        SetFlatSelected(self.membersTab, true)
        SetFlatSelected(self.syncTab, false)
    end
end

function Sync:BuildUI()
    if self.panel or not GVE.f then return end
    local root = GVE.f

    -- Hauptnavigation: bewusst flach gehalten, damit sie wie ein Teil des
    -- Fensters und nicht wie zwei rote Standarddialog-Knöpfe wirkt.
    local header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -5); header:SetPoint("TOPRIGHT", root, "TOPRIGHT", -10, -5); header:SetHeight(48)
    header:SetFrameLevel(root:GetFrameLevel() + 30); header:EnableMouse(true); MakeFlatPanel(header, UI_COLOR.panel)
    self.header = header

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", -1, 0)
    close:SetScript("OnClick", function() GVE:Close() end)
    self.closeButton = close

    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerTitle:SetPoint("CENTER", header, "CENTER", 0, 0)
    headerTitle:SetText("|cff33aaffGuild-View-Extended|r")
    self.headerTitle = headerTitle

    local membersTab = MakeFlatButton(header, 108, 28, L.members)
    membersTab:SetPoint("LEFT", header, "LEFT", 8, 0)
    membersTab:SetFrameLevel(root:GetFrameLevel() + 31)
    membersTab:SetScript("OnClick", function() Sync:SetMainTab("members") end)
    membersTab.selectionIndicator = membersTab:CreateTexture(nil, "OVERLAY")
    membersTab.selectionIndicator:SetHeight(2); membersTab.selectionIndicator:SetPoint("BOTTOMLEFT", 4, 0); membersTab.selectionIndicator:SetPoint("BOTTOMRIGHT", -4, 0)
    SetTextureColor(membersTab.selectionIndicator, UI_COLOR.borderFocus)
    self.membersTab = membersTab

    local syncTab = MakeFlatButton(header, 184, 28, L.tab)
    syncTab:SetPoint("LEFT", membersTab, "RIGHT", 5, 0)
    syncTab:SetFrameLevel(root:GetFrameLevel() + 31)
    syncTab:SetScript("OnClick", function() Sync:SetMainTab("sync") end)
    syncTab.selectionIndicator = syncTab:CreateTexture(nil, "OVERLAY")
    syncTab.selectionIndicator:SetHeight(2); syncTab.selectionIndicator:SetPoint("BOTTOMLEFT", 4, 0); syncTab.selectionIndicator:SetPoint("BOTTOMRIGHT", -4, 0)
    SetTextureColor(syncTab.selectionIndicator, UI_COLOR.borderFocus)
    self.syncTab = syncTab

    local panel = CreateFrame("Frame", nil, root)
    panel:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -58)
    panel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
    panel:SetFrameLevel(root:GetFrameLevel() + 20)
    panel:EnableMouse(true)
    MakeFlatPanel(panel, UI_COLOR.panel)
    -- Fuellt auch die schmale Fuge unter dem 48px-Header opak aus. Die
    -- Textur gehoert zum Panel und verschwindet beim Mitglieder-Tab mit ihm.
    local pageShield = panel:CreateTexture(nil, "BACKGROUND")
    pageShield:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, 5)
    pageShield:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    SetTextureColor(pageShield, UI_COLOR.panel)
    self.panel = panel

    local footer = CreateFrame("Frame", nil, panel)
    footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8); footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8); footer:SetHeight(32)
    MakeFlatPanel(footer, UI_COLOR.section)

    -- Berufsuebersicht als vollbreite, aufklappbare Tabelle. Ein flaches
    -- Zeilenmodell haelt die Scroll-Logik auch auf dem 3.3.5a-Client stabil.
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 8)
    content:EnableMouse(true)
    MakeFlatPanel(content, UI_COLOR.section)

    local search = MakeFlatSearch(content, 350, 26)
    search:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12)
    search:SetMaxLetters(60)
    search:SetScript("OnTextChanged", function()
        if Sync.playerScroll then FauxScrollFrame_SetOffset(Sync.playerScroll, 0) end
        Sync:RefreshPlayers()
    end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    self.playerSearch = search
    local placeholder = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 9, 0)
    placeholder:SetText(L.search)
    placeholder:SetTextColor(0.42, 0.52, 0.61)
    search:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
    search:HookScript("OnEditFocusLost", function(self) if self:GetText() == "" then placeholder:Show() end end)
    search:HookScript("OnTextChanged", function(self) if self:GetText() ~= "" then placeholder:Hide() end end)

    local onlineButton = MakeFlatButton(content, 112, 26, L.allPlayers)
    onlineButton:SetPoint("LEFT", search, "RIGHT", 8, 0)
    onlineButton:SetScript("OnClick", function(self)
        local nextValue = {all="online", online="offline", offline="all"}
        Sync.onlineFilter = nextValue[Sync.onlineFilter or "all"]
        self:SetText(Sync.onlineFilter == "online" and L.onlineOnly or Sync.onlineFilter == "offline" and L.offlineOnly or L.allPlayers)
        FauxScrollFrame_SetOffset(Sync.playerScroll, 0)
        Sync:RefreshPlayers()
    end)

    local ageButton = MakeFlatButton(content, 112, 26, L.allData)
    ageButton:SetPoint("LEFT", onlineButton, "RIGHT", 6, 0)
    ageButton:SetScript("OnClick", function(self)
        local nextValue = {all="current", current="stale", stale="all"}
        Sync.ageFilter = nextValue[Sync.ageFilter or "all"]
        self:SetText(Sync.ageFilter == "current" and L.currentOnly or Sync.ageFilter == "stale" and L.staleOnly or L.allData)
        FauxScrollFrame_SetOffset(Sync.playerScroll, 0)
        Sync:RefreshPlayers()
    end)

    local expandButton = MakeFlatButton(content, 116, 26, L.openAll)
    expandButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -12)
    expandButton:SetScript("OnClick", function(self) Sync:SetAllCategories(self.expandNext) end)
    self.expandButton = expandButton

    local syncNowButton = MakeFlatButton(content, 166, 26, L.syncNow, true)
    syncNowButton:SetPoint("RIGHT", expandButton, "LEFT", -6, 0)
    syncNowButton:SetScript("OnClick", function()
        Sync:ManualBroadcastSync()
    end)
    self.syncNowButton = syncNowButton

    self.playerCount = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.playerCount:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -7)
    self.playerCount:SetTextColor(0.49, 0.63, 0.73)

    local tableHeader = CreateFrame("Frame", nil, content)
    tableHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -66)
    tableHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -25, -66)
    tableHeader:SetHeight(25)
    MakeFlatPanel(tableHeader, UI_COLOR.field)
    local function HeaderLabel(text, x, width)
        local label = tableHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", tableHeader, "LEFT", x, 0)
        label:SetWidth(width); label:SetJustifyH("LEFT"); label:SetWordWrap(false)
        label:SetText(text); label:SetTextColor(0.56, 0.68, 0.77)
        return label
    end
    HeaderLabel(L.columnPlayer, 50, 210)
    HeaderLabel(L.columnLink, 270, 245)
    HeaderLabel(L.columnSkill, 525, 92)
    HeaderLabel(L.columnAge, 625, 112)
    HeaderLabel(L.columnStatus, 745, 175)

    self.playerRows = {}
    for index = 1, 10 do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(42)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -94 - (index - 1) * 42)
        row:SetPoint("RIGHT", content, "RIGHT", -25, 0)
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        row.selectionBar = row:CreateTexture(nil, "ARTWORK"); row.selectionBar:SetWidth(3); row.selectionBar:SetPoint("TOPLEFT"); row.selectionBar:SetPoint("BOTTOMLEFT"); SetTextureColor(row.selectionBar, UI_COLOR.borderFocus); row.selectionBar:Hide()
        row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); row.toggle:SetPoint("LEFT", row, "LEFT", 8, 0); row.toggle:SetWidth(15); row.toggle:SetJustifyH("CENTER"); row.toggle:SetTextColor(0.55, 0.75, 0.9)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", row, "LEFT", 27, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.statusDot = row:CreateTexture(nil, "OVERLAY"); row.statusDot:SetSize(6, 6); row.statusDot:SetPoint("LEFT", row, "LEFT", 53, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 64, -6); row.name:SetWidth(196); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.rank:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 64, 6); row.rank:SetWidth(196); row.rank:SetJustifyH("LEFT"); row.rank:SetWordWrap(false); row.rank:SetTextColor(0.47, 0.57, 0.65)
        row.link = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.link:SetPoint("LEFT", row, "LEFT", 270, 0); row.link:SetWidth(245); row.link:SetJustifyH("LEFT"); row.link:SetWordWrap(false)
        row.skill = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.skill:SetPoint("LEFT", row, "LEFT", 525, 0); row.skill:SetWidth(92); row.skill:SetJustifyH("LEFT"); row.skill:SetWordWrap(false); row.skill:SetTextColor(0.72, 0.78, 0.83)
        row.age = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.age:SetPoint("LEFT", row, "LEFT", 625, 0); row.age:SetWidth(112); row.age:SetJustifyH("LEFT"); row.age:SetWordWrap(false); row.age:SetTextColor(0.63, 0.7, 0.76)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.status:SetPoint("LEFT", row, "LEFT", 745, 0); row.status:SetPoint("RIGHT", row, "RIGHT", -8, 0); row.status:SetJustifyH("LEFT"); row.status:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.entry and self.entry.header then
                Sync:ToggleCategory(self.categoryKey)
            elseif self.tradeLink then
                OpenTradeLink(self.tradeLink)
            elseif self.member and (self.member.online or IsOwn(self.member.name)) then
                Sync:Request(self.member.name)
            end
        end)
        row:SetScript("OnEnter", function(self)
            self.rowHover = true; PaintPlayerRow(self, self.rowAlternate)
            if self.tradeLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L.clickToOpen); GameTooltip:Show()
            elseif self.member and (self.member.online or IsOwn(self.member.name)) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(IsOwn(self.member.name) and L.capture or L.request); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self) self.rowHover = nil; PaintPlayerRow(self, self.rowAlternate); GameTooltip:Hide() end)
        self.playerRows[index] = row
    end
    local ps = CreateFrame("ScrollFrame", "GVESyncPlayerScroll", content, "FauxScrollFrameTemplate")
    ps:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -94)
    ps:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -7, 4)
    ps:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 42, function() Sync:RefreshPlayers() end) end)
    ps:EnableMouseWheel(true)
    ps:SetScript("OnMouseWheel", function(self, delta) local bar = _G[(self:GetName() or "").."ScrollBar"]; if bar then bar:SetValue(bar:GetValue() - delta * 42) end end)
    -- Der FauxScrollFrame verarbeitet nur Scrollen; die sichtbaren Zeilen
    -- bleiben darueber anklickbar (Aufklappen, Berufslink, Datenanfrage).
    for _, row in ipairs(self.playerRows) do row:SetFrameLevel(ps:GetFrameLevel() + 1) end
    self.playerScroll = ps
    self.emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.emptyText:SetPoint("CENTER", ps, "CENTER", -8, 0); self.emptyText:SetWidth(500); self.emptyText:SetJustifyH("CENTER"); self.emptyText:SetTextColor(0.48, 0.58, 0.67); self.emptyText:Hide()

    local help = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); help:SetPoint("LEFT", footer, "LEFT", 10, 0); help:SetWidth(405); help:SetJustifyH("LEFT"); help:SetText(L.footerShort); help:SetTextColor(0.48, 0.58, 0.67)
    local helpButton = MakeFlatButton(footer, 22, 20, "?"); helpButton:SetPoint("LEFT", help, "RIGHT", 6, 0); helpButton:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.help, 0.88, 0.93, 0.98, true); GameTooltip:Show() end); helpButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local shareP = MakeCheck(footer, L.shareP); shareP:SetPoint("RIGHT", footer, "RIGHT", -150, 0); shareP:SetChecked(self.db.settings.shareProfessions); shareP:SetScript("OnClick", function(self)
        Sync.db.settings.shareProfessions = self:GetChecked() and true or false
        if Sync.db.settings.shareProfessions then Sync:Announce("H") end
    end)

    GVE:SetRosterListener(function() Sync:RefreshUI() end)
    self:SetMainTab("members")
end

---------------------------------------------------------------------------
-- Events, Timeout und gedrosselte Sendequeue
---------------------------------------------------------------------------
Sync.sendQueue = {}
Sync.pending = {}
Sync.receiving = {}
Sync.cooldowns = {}
Sync.incomingCooldown = {}
Sync.viewMessages = {}
Sync.autoQueue = {}
Sync.autoQueued = {}
Sync.autoLastRequest = {}
Sync.relayCatalogPending = {}
Sync.relayCatalogCooldown = {}
Sync.relayQueue = {}
Sync.relayQueued = {}
Sync.relayPending = {}
Sync.relayReceiving = {}
Sync.relayOwnerPending = {}
Sync.relayIncomingCooldown = {}
Sync.elapsed = 0
Sync.autoElapsed = 0

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

local spellbookHookInstalled = false
local function InstallSpellbookHook()
    if spellbookHookInstalled or type(hooksecurefunc) ~= "function"
    or type(SpellButton_OnModifiedClick) ~= "function"
    or type(SpellBook_GetSpellID) ~= "function" then return end
    hooksecurefunc("SpellButton_OnModifiedClick", function(button)
        if not button or type(IsModifiedClick) ~= "function" or not IsModifiedClick("CHATLINK")
        or type(GetSpellLink) ~= "function" or type(Sync.own) ~= "table" then return end
        local slot = SpellBook_GetSpellID(button:GetID())
        local bookType = SpellBookFrame and SpellBookFrame.bookType or BOOKTYPE_SPELL or "spell"
        local _, value = GetSpellLink(slot, bookType)
        local tradeLink, name, skill, maxSkill = ParseTradeLink(value)
        if not tradeLink then return end
        local previous = Sync.own.professions and Sync.own.professions[name]
        if previous and previous.tradeLink == tradeLink then return end
        local capturedAt = time()
        Sync.own.professions = type(Sync.own.professions) == "table" and Sync.own.professions or {}
        Sync.own.professions[name] = {name=name, skill=skill, maxSkill=maxSkill, capturedAt=capturedAt, tradeLink=tradeLink}
        local oldestAt
        for _, profession in pairs(Sync.own.professions) do
            local professionAt = tonumber(profession.capturedAt) or capturedAt
            oldestAt = not oldestAt and professionAt or math.min(oldestAt, professionAt)
        end
        Sync.own.professionsCapturedAt = oldestAt or capturedAt
        Sync.own.receivedAt = capturedAt
        Sync:RefreshUI()
        Sync:Announce("U")
    end)
    spellbookHookInstalled = true
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    InstallSpellbookHook()
    if event == "PLAYER_LOGIN" then
        Sync:InitDB()
        Sync:BuildUI()
        InstallSpellbookHook()
        Sync.capturePending = GetTime() + 2
        Sync.discoveryPending = GetTime() + 4
    elseif event == "CHAT_MSG_ADDON" then
        Sync:OnAddonMessage(...)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "SPELLS_CHANGED" then
        Sync.capturePending = GetTime() + 0.25
    elseif event == "PLAYER_GUILD_UPDATE" then
        Sync:InitDB()
        Sync.capturePending = GetTime() + 0.25
        Sync.discoveryPending = GetTime() + 2
        Sync:RefreshUI()
    elseif event == "GUILD_ROSTER_UPDATE" and Sync.waitingForGuild then
        Sync:InitDB()
        Sync.capturePending = GetTime() + 0.25
        Sync.discoveryPending = GetTime() + 2
        Sync:RefreshUI()
    end
end)

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if Sync.db and not Sync.panel and GVE.f then Sync:BuildUI() end
    Sync.elapsed = Sync.elapsed + elapsed
    if Sync.capturePending and GetTime() >= Sync.capturePending then
        Sync.capturePending = nil
        Sync:CaptureProfession(false)
    end
    if Sync.discoveryPending and GetTime() >= Sync.discoveryPending then
        Sync.discoveryPending = nil
        Sync:Announce("H")
    end
    Sync.autoElapsed = Sync.autoElapsed + elapsed
    if Sync.autoElapsed >= AUTO_REQUEST_INTERVAL and #Sync.autoQueue > 0 then
        Sync.autoElapsed = 0
        local request = table.remove(Sync.autoQueue, 1)
        if request then
            Sync.autoQueued[request.key] = nil
            Sync:Request(request.name, true, request.force)
        end
    elseif Sync.autoElapsed >= AUTO_REQUEST_INTERVAL and #Sync.relayQueue > 0 then
        Sync.autoElapsed = 0
        local candidate = table.remove(Sync.relayQueue, 1)
        if candidate then
            Sync.relayQueued[candidate.ownerKey] = nil
            Sync:RequestRelayedSnapshot(candidate)
        end
    end
    if Sync.elapsed < SEND_INTERVAL then return end
    Sync.elapsed = 0
    local queued = table.remove(Sync.sendQueue, 1)
    if queued then SendAddonMessage(PREFIX, queued.message, queued.channel or "WHISPER", queued.target) end
    local now = GetTime()
    for key, request in pairs(Sync.pending) do
        if now > (request.deadline or 0) or now - (request.lastActivity or request.started) > REQUEST_TIMEOUT then
            Sync.pending[key] = nil
            Sync.receiving[key] = nil
            Sync.viewMessages[key] = L.timeout
            Sync:RefreshUI()
        end
    end
    for key, request in pairs(Sync.relayCatalogPending) do
        if now > (request.deadline or 0) then Sync.relayCatalogPending[key] = nil end
    end
    for transferKey, request in pairs(Sync.relayPending) do
        if now > (request.deadline or 0)
        or now - (request.lastActivity or request.started) > REQUEST_TIMEOUT then
            Sync.relayPending[transferKey] = nil
            Sync.relayReceiving[transferKey] = nil
            if Sync.relayOwnerPending[request.ownerKey] == transferKey then
                Sync.relayOwnerPending[request.ownerKey] = nil
            end
        end
    end
end)
