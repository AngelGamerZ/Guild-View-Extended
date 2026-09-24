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
local CHUNK_BYTES = 175
local MAX_CHUNKS = 256
local MAX_BYTES = MAX_CHUNKS * CHUNK_BYTES
local CACHE_TTL = 30 * 24 * 60 * 60
local REQUEST_TIMEOUT = 15
local REQUEST_COOLDOWN = 10
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
    footerShort="Gespeicherte Berufs-Snapshots · nicht live",
    clickToOpen="Klicken, um den verlinkten Beruf zu öffnen.",
    shareP="Eigene Berufe teilen", captured="Lokaler Snapshot aktualisiert.", players="%d Spieler",
    professionSearch="Berufe durchsuchen ...", professionCount="%d Berufe",
    current="aktuell", stale="veraltet", never="keine Daten",
    sec="Sek.", min="Min.", hour="Std.", day="Tage",
    openProfession="Kein vollständiger Berufslink gefunden. Öffne dein Zauberbuch oder deinen eigenen Beruf und versuche es erneut.",
    lastCaptured="zuletzt erfasst vor %s",
    synchronized="%d synchronisierte Spieler", categoryPlayers="%d Spieler",
    tooBig="Die Berufsdaten sind für die Synchronisierung zu groß.",
    notSynchronized="Noch nicht synchronisiert",
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
    footerShort="Cached profession snapshots · not live",
    clickToOpen="Click to open the linked profession.",
    shareP="Share my professions", captured="Local snapshot updated.", players="%d players",
    professionSearch="Search professions ...", professionCount="%d professions",
    current="current", stale="stale", never="no data",
    sec="sec", min="min", hour="hr", day="days",
    openProfession="No complete profession link was found. Open your spellbook or your own profession and try again.",
    lastCaptured="last captured %s ago",
    synchronized="%d synchronized players", categoryPlayers="%d players",
    tooBig="The profession data is too large to synchronize.",
    notSynchronized="Not synchronized",
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
    return value, label, skill, maxSkill
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

local function PaintDetailRow(row, alternate)
    local color = row.rowHover and UI_COLOR.hover or (alternate and UI_COLOR.rowB or UI_COLOR.rowA)
    SetTextureColor(row.bg, color)
end

function Sync:InitDB()
    if type(GVESyncData) ~= "table" then
        GVESyncData = {schema=PROTOCOL, players={}, ownByCharacter={}, settings={}}
    end
    local db = GVESyncData
    local previousSchema = tonumber(db.schema) or 0
    if previousSchema > PROTOCOL then
        -- Daten einer neueren, unbekannten Version niemals als v4 umdeuten.
        -- Nur die harmlosen Freigabeeinstellungen koennen uebernommen werden.
        db = {schema=PROTOCOL, players={}, ownByCharacter={}, settings=type(db.settings) == "table" and db.settings or {}}
        GVESyncData = db
        previousSchema = PROTOCOL
    end
    -- Alte Berufslinks bleiben erhalten. Nicht mehr verwendete Bank- und
    -- Rezeptindexdaten werden bei der Migration ersatzlos entfernt.
    db.schema = PROTOCOL
    db.players = type(db.players) == "table" and db.players or {}
    db.ownByCharacter = type(db.ownByCharacter) == "table" and db.ownByCharacter or {}
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
    end
    -- Spieler, Berufslinks und Freigabeeinstellung bleiben dabei erhalten.
    MigrateSnapshot(db.own)
    for _, snapshot in pairs(db.ownByCharacter) do MigrateSnapshot(snapshot) end
    for _, snapshot in pairs(db.players) do MigrateSnapshot(snapshot) end

    local guildName = GetGuildInfo("player")
    if (not guildName or guildName == "") and type(IsInGuild) == "function" and IsInGuild() then
        -- Direkt bei PLAYER_LOGIN kann der Gildenname noch ungeladen sein.
        -- Niemals deshalb einen gueltigen gespeicherten Guild-Scope leeren.
        self.db = db
        self.own = self.own or {}
        self.waitingForGuild = true
        return false
    end
    guildName = guildName or ""
    self.waitingForGuild = nil
    local guildKey = (GetRealmName() or "").."\031"..guildName
    if db.guildKey and db.guildKey ~= guildKey then
        wipe(db.players)
        wipe(db.ownByCharacter)
        db.own = nil
        if self.sendQueue then wipe(self.sendQueue) end
        if self.pending then wipe(self.pending) end
        if self.receiving then wipe(self.receiving) end
        if self.cooldowns then wipe(self.cooldowns) end
        if self.incomingCooldown then wipe(self.incomingCooldown) end
        if self.viewMessages then wipe(self.viewMessages) end
    end
    db.guildKey = guildKey
    local characterKey = guildKey.."\031"..(UnitName("player") or "Unknown")
    if type(db.ownByCharacter[characterKey]) ~= "table" then
        -- Einmalige Migration frueher lokaler Testdaten auf den gerade
        -- angemeldeten Charakter; danach keine accountweite Vermischung.
        db.ownByCharacter[characterKey] = type(db.own) == "table" and db.own or {}
    end
    db.own = nil
    self.own = db.ownByCharacter[characterKey]
    local cutoff = time() - CACHE_TTL
    for key, entry in pairs(db.players) do
        if type(entry) ~= "table" or (tonumber(entry.receivedAt) or 0) < cutoff then
            db.players[key] = nil
        end
    end
    self.db = db
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

function Sync:GetPlayerData(name)
    if IsOwn(name) then return self.own end
    return self.db.players[KeyName(name) or ""]
end

---------------------------------------------------------------------------
-- Lokale Erfassung
---------------------------------------------------------------------------
function Sync:CaptureProfession(showMessage)
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

function Sync:QueueMessage(message, target)
    if #self.sendQueue >= MAX_CHUNKS * 2 then return end
    self.sendQueue[#self.sendQueue + 1] = {message=message, target=target}
end

function Sync:QueueControlMessage(message, target)
    if #self.sendQueue >= MAX_CHUNKS * 2 then return false end
    table.insert(self.sendQueue, 1, {message=message, target=target})
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
    self:QueueMessage("B|"..requestID.."|"..(tonumber(capturedAt) or time()).."|"..chunks, target)
    for index = 1, chunks do
        local part = payload:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES)
        self:QueueMessage("D|"..requestID.."|"..index.."|"..part, target)
    end
    self:QueueMessage("E|"..requestID, target)
end

function Sync:Request(name)
    local clean = CleanName(name)
    local key = KeyName(clean)
    if not clean or not key or not self:IsGuildMember(clean) then return end
    if IsOwn(clean) then
        self:CaptureProfession(true)
        return
    end
    local now = GetTime()
    if self.cooldowns[key] and now - self.cooldowns[key] < REQUEST_COOLDOWN then return end
    self.cooldowns[key] = now
    local requestID = tostring(math.floor(now * 1000) % 10000000)..tostring(math.random(100, 999))
    self.pending[key] = {started=now, lastActivity=now, deadline=now + ABSOLUTE_TRANSFER_TIMEOUT, requestID=requestID}
    SendAddonMessage(PREFIX, "Q|"..requestID, "WHISPER", clean)
    self.viewMessages[key] = L.pending
    self:RefreshUI()
end

function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 240 then return end
    local cleanSender = CleanName(sender)
    if not cleanSender or not self:IsGuildMember(cleanSender) then return end
    local fields = Split(message, "|")
    local command, requestID = fields[1], fields[2]
    if not requestID or #requestID > 12 or not requestID:match("^%d+$") then return end

    if command == "Q" and channel == "WHISPER" then
        if #fields ~= 2 then return end
        local senderKey = KeyName(cleanSender)
        local now = GetTime()
        if self.incomingCooldown[senderKey] and now - self.incomingCooldown[senderKey] < 30 then return end
        self.incomingCooldown[senderKey] = now
        self:CaptureProfession(false)
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
        local entry = self.db.players[playerKey] or {displayName=cleanSender}
        entry.professions = decoded.professions
        entry.professionsCapturedAt = decoded.professionsCapturedAt
        entry.displayName = cleanSender
        entry.receivedAt = time()
        self.db.players[playerKey] = entry
        local cached = {}
        for key, value in pairs(self.db.players) do cached[#cached + 1] = {key=key, receivedAt=tonumber(value.receivedAt) or 0} end
        table.sort(cached, function(a, b) return a.receivedAt < b.receivedAt end)
        while #cached > MAX_CACHED_PLAYERS do
            self.db.players[cached[1].key] = nil
            table.remove(cached, 1)
        end
        self.viewMessages[pendingKey] = nil
        self:RefreshUI()
    end
end

---------------------------------------------------------------------------
-- Benutzeroberflaeche
---------------------------------------------------------------------------
function Sync:SelectPlayer(member)
    self.selectedName = member and member.name or nil
    if self.detailScroll then FauxScrollFrame_SetOffset(self.detailScroll, 0) end
    self:RefreshUI()
end

local function ContainsFolded(value, needle)
    return needle == "" or Fold(value):find(needle, 1, true) ~= nil
end

function Sync:BuildPlayerList()
    local needle = self.playerSearch and Fold(self.playerSearch:GetText()) or ""
    local categories, synchronized = {}, {}
    local function Add(categoryName, member, order, countSynchronized)
        local key = Fold(categoryName)
        local category = categories[key]
        if not category then
            category = {name=categoryName, order=order, members={}, memberKeys={}}
            categories[key] = category
        end
        local memberKey = KeyName(member.name)
        if memberKey and not category.memberKeys[memberKey] then
            category.memberKeys[memberKey] = true
            category.members[#category.members + 1] = member
            if countSynchronized ~= false then synchronized[memberKey] = true end
        end
    end

    for _, member in ipairs(GVE:GetMembers() or {}) do
        local data = self:GetPlayerData(member.name)
        local memberMatch = ContainsFolded(member.name, needle)
        local hasData = false
        if data then
            for professionName, profession in pairs(data.professions or {}) do
                if memberMatch or ContainsFolded(professionName, needle) then
                    Add(professionName, member, 1, true)
                end
                hasData = true
            end
        end
        if not hasData and memberMatch then
            Add(L.notSynchronized, member, 2, false)
        end
    end

    local orderedCategories = {}
    for _, category in pairs(categories) do orderedCategories[#orderedCategories + 1] = category end
    table.sort(orderedCategories, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return Fold(a.name) < Fold(b.name)
    end)

    local list = {}
    for _, category in ipairs(orderedCategories) do
        table.sort(category.members, function(a, b)
            if a.online ~= b.online then return a.online and true or false end
            return Fold(a.name) < Fold(b.name)
        end)
        list[#list + 1] = {header=true, category=category.name, count=#category.members}
        for _, member in ipairs(category.members) do
            list[#list + 1] = {member=member, category=category.name}
        end
    end
    local playerCount = 0
    for _ in pairs(synchronized) do playerCount = playerCount + 1 end
    self.playerMatchCount = playerCount
    self.playerList = list
end

function Sync:RefreshPlayers()
    if not self.panel then return end
    self:BuildPlayerList()
    local offset = FauxScrollFrame_GetOffset(self.playerScroll)
    FauxScrollFrame_Update(self.playerScroll, #self.playerList, #self.playerRows, 42)
    self.playerCount:SetText(format(L.synchronized, self.playerMatchCount or 0))
    for index, row in ipairs(self.playerRows) do
        local entry = self.playerList[index + offset]
        local member = entry and entry.member
        if entry and entry.header then
            row.member = nil
            row.name:SetText(entry.category)
            row.name:SetTextColor(0.35, 0.72, 1)
            row.rank:SetText(format(L.categoryPlayers, entry.count or 0))
            row.statusDot:Hide()
            row.rowSelected = false
            row.rowAlternate = false
            PaintPlayerRow(row, false)
            row:Show()
        elseif member then
            row.member = member
            row.name:SetText(member.name)
            row.name:SetTextColor(member.online and 0.93 or 0.66, member.online and 0.96 or 0.71, member.online and 0.99 or 0.77)
            local statusText = member.online and (FRIENDS_LIST_ONLINE or "Online") or (FRIENDS_LIST_OFFLINE or "Offline")
            row.rank:SetText(((member.rank and member.rank ~= "") and (member.rank.."  ·  ") or "")..statusText)
            row.statusDot:Show()
            SetTextureColor(row.statusDot, member.online and {0.25, 0.84, 0.51, 1} or {0.34, 0.40, 0.47, 1})
            row.rowSelected = KeyName(member.name) == KeyName(self.selectedName)
            row.rowAlternate = (index + offset) % 2 == 0
            PaintPlayerRow(row, row.rowAlternate)
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end
end

function Sync:BuildDetailRows()
    local rows = {}
    local data = self:GetPlayerData(self.selectedName)
    local needle = self.detailSearch and Fold(self.detailSearch:GetText()) or ""
    if data and data.professions then
        local professionNames = {}
        for name in pairs(data.professions) do professionNames[#professionNames + 1] = name end
        table.sort(professionNames)
        local matchCount = 0
        for _, professionName in ipairs(professionNames) do
            local profession = data.professions[professionName]
            if needle == "" or Fold(professionName):find(needle, 1, true) then
                local detail = (profession.skill or 0).." / "..(profession.maxSkill or 0).." · "..format(L.lastCaptured, AgeText(profession.capturedAt))
                rows[#rows + 1] = {text=profession.tradeLink or ("["..professionName.."]"), detail=detail, tradeLink=profession.tradeLink}
                matchCount = matchCount + 1
            end
        end
        self.summary:SetText(matchCount > 0 and format(L.professionCount, matchCount) or "")
        self.emptyMessage = matchCount == 0 and L.noProfessions or nil
    else
        self.summary:SetText("")
        self.emptyMessage = L.noData
    end
    self.detailList = rows
end

function Sync:RefreshDetails()
    if not self.panel then return end
    local member = self:GetMember(self.selectedName)
    if not member then
        self.detailName:SetText(L.noSelection)
        self.detailMeta:SetText("")
        self.ageText:SetText("")
        self.ageText:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
        self.summary:SetText("")
        self.requestButton:Disable()
        self.detailList = {}
        self.emptyMessage = L.noSelection
    else
        self.detailName:SetText(member.name)
        self.detailMeta:SetText((member.rank or "").."  ·  "..(member.online and (FRIENDS_LIST_ONLINE or "Online") or L.offline))
        local viewKey = KeyName(member.name)
        if (member.online or IsOwn(member.name)) and not self.pending[viewKey] then self.requestButton:Enable() else self.requestButton:Disable() end
        self.requestButton:SetText(self.pending[viewKey] and L.pending or IsOwn(member.name) and L.capture or L.request)
        self:BuildDetailRows()
        local data = self:GetPlayerData(member.name)
        local stamp = data and data.professionsCapturedAt or nil
        local state = stamp and format(L.fresh, AgeText(stamp)) or L.never
        if stamp and time() - stamp > 7 * 86400 then state = L.stale.." · "..state end
        if self.viewMessages[viewKey] then state = self.viewMessages[viewKey] end
        self.ageText:SetText(state)
        if self.pending[viewKey] then
            self.ageText:SetTextColor(UI_COLOR.borderFocus[1], UI_COLOR.borderFocus[2], UI_COLOR.borderFocus[3])
        elseif self.viewMessages[viewKey] == L.timeout or self.viewMessages[viewKey] == L.denied then
            self.ageText:SetTextColor(UI_COLOR.error[1], UI_COLOR.error[2], UI_COLOR.error[3])
        elseif stamp and time() - stamp <= 7 * 86400 then
            self.ageText:SetTextColor(UI_COLOR.good[1], UI_COLOR.good[2], UI_COLOR.good[3])
        elseif stamp then
            self.ageText:SetTextColor(UI_COLOR.warn[1], UI_COLOR.warn[2], UI_COLOR.warn[3])
        else
            self.ageText:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
        end
    end
    local rowHeight = 48
    self.detailRowHeight = rowHeight
    for index, row in ipairs(self.detailRows) do
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.detailScroll, "TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", self.detailScroll, "RIGHT", -23, 0)
    end
    local offset = FauxScrollFrame_GetOffset(self.detailScroll)
    FauxScrollFrame_Update(self.detailScroll, #self.detailList, #self.detailRows, rowHeight)
    if self.emptyText then
        if #self.detailList == 0 then
            self.emptyText:SetText(self.emptyMessage or L.noData)
            self.emptyText:Show()
        else
            self.emptyText:Hide()
        end
    end
    for index, row in ipairs(self.detailRows) do
        local value = self.detailList[index + offset]
        if value then
            row.value = value
            row.text:SetText(value.text)
            row.detail:SetText(value.detail or "")
            if value.tradeLink then row.text:SetTextColor(1, 0.82, 0.24)
            else row.text:SetTextColor(0.88, 0.92, 0.96) end
            row.detail:SetTextColor(value.tradeLink and 0.69 or 0.58, value.tradeLink and 0.76 or 0.66, value.tradeLink and 0.82 or 0.73)
            row.rowAlternate = (index + offset) % 2 == 0
            PaintDetailRow(row, row.rowAlternate)
            row:Show()
        else row.value = nil; row:Hide() end
    end
end

function Sync:RefreshUI()
    if not self.panel then return end
    self:RefreshPlayers()
    self:RefreshDetails()
end

function Sync:SetMainTab(tab)
    if self.playerSearch then self.playerSearch:ClearFocus() end
    if self.detailSearch then self.detailSearch:ClearFocus() end
    if GVE.searchBox then GVE.searchBox:ClearFocus() end
    if tab == "sync" then
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT", GVE.f, "TOPLEFT", 10, -5)
        self.header:SetPoint("TOPRIGHT", GVE.f, "TOPRIGHT", -10, -5)
        self.header:SetHeight(48)
        self.closeButton:Show()
        self.headerTitle:Show()
        if GVE.filterPanel then GVE.filterPanel:Hide() end
        if GVE.lastOnlineWin then GVE.lastOnlineWin:Hide() end
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
        self.header:SetSize(309, 28)
        self.closeButton:Hide()
        self.headerTitle:Hide()
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

    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8); left:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 8)
    left:SetWidth(310); left:EnableMouse(true); MakeFlatPanel(left, UI_COLOR.section)

    local leftTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 13, -12); leftTitle:SetText(L.members); leftTitle:SetTextColor(0.78, 0.88, 0.95)

    local search = MakeFlatSearch(left, 268, 26)
    search:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -35)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function() if Sync.playerScroll then FauxScrollFrame_SetOffset(Sync.playerScroll, 0) end; Sync:RefreshPlayers() end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    self.playerSearch = search
    local placeholder = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 9, 0); placeholder:SetText(L.search); placeholder:SetTextColor(0.42, 0.52, 0.61)
    search:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
    search:HookScript("OnEditFocusLost", function(self) if self:GetText() == "" then placeholder:Show() end end)
    search:HookScript("OnTextChanged", function(self) if self:GetText() ~= "" then placeholder:Hide() end end)

    self.playerCount = left:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.playerCount:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -8); self.playerCount:SetTextColor(0.49, 0.63, 0.73)

    self.playerRows = {}
    for index = 1, 10 do
        local row = CreateFrame("Button", nil, left)
        row:SetHeight(42); row:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -82 - (index - 1) * 42); row:SetPoint("RIGHT", left, "RIGHT", -25, 0)
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        row.selectionBar = row:CreateTexture(nil, "ARTWORK"); row.selectionBar:SetWidth(3); row.selectionBar:SetPoint("TOPLEFT"); row.selectionBar:SetPoint("BOTTOMLEFT"); SetTextureColor(row.selectionBar, UI_COLOR.borderFocus); row.selectionBar:Hide()
        row.statusDot = row:CreateTexture(nil, "ARTWORK"); row.statusDot:SetSize(6, 6); row.statusDot:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -6); row.name:SetWidth(235); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.rank:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 22, 6); row.rank:SetWidth(235); row.rank:SetJustifyH("LEFT"); row.rank:SetWordWrap(false); row.rank:SetTextColor(0.47, 0.57, 0.65)
        row:SetScript("OnClick", function(self) if self.member then Sync:SelectPlayer(self.member) end end)
        row:SetScript("OnEnter", function(self) self.rowHover = true; PaintPlayerRow(self, self.rowAlternate) end)
        row:SetScript("OnLeave", function(self) self.rowHover = nil; PaintPlayerRow(self, self.rowAlternate) end)
        self.playerRows[index] = row
    end
    local ps = CreateFrame("ScrollFrame", "GVESyncPlayerScroll", left, "FauxScrollFrameTemplate")
    ps:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -82); ps:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -7, 0)
    ps:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 42, function() Sync:RefreshPlayers() end) end)
    ps:EnableMouseWheel(true)
    ps:SetScript("OnMouseWheel", function(self, delta) local bar = _G[(self:GetName() or "").."ScrollBar"]; if bar then bar:SetValue(bar:GetValue() - delta * 42) end end)
    self.playerScroll = ps

    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 8)
    right:EnableMouse(true); MakeFlatPanel(right, UI_COLOR.section)

    local identity = CreateFrame("Frame", nil, right)
    identity:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -10); identity:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, -10); identity:SetHeight(50)
    MakeFlatPanel(identity, UI_COLOR.field)
    self.detailName = identity:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); self.detailName:SetPoint("TOPLEFT", identity, "TOPLEFT", 13, -9); self.detailName:SetText(L.noSelection); self.detailName:SetTextColor(0.91, 0.96, 1)
    self.detailMeta = identity:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.detailMeta:SetPoint("TOPLEFT", self.detailName, "BOTTOMLEFT", 0, -3); self.detailMeta:SetTextColor(0.52, 0.64, 0.73)
    self.requestButton = MakeFlatButton(identity, 132, 25, L.request, true); self.requestButton:SetPoint("TOPRIGHT", identity, "TOPRIGHT", -10, -8)
    self.requestButton:SetScript("OnClick", function() if Sync.selectedName then Sync:Request(Sync.selectedName) end end)
    self.ageText = identity:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.ageText:SetPoint("TOPRIGHT", self.requestButton, "BOTTOMRIGHT", 0, -4); self.ageText:SetWidth(310); self.ageText:SetJustifyH("RIGHT"); self.ageText:SetTextColor(0.78, 0.69, 0.39)
    local identityLine = right:CreateTexture(nil, "ARTWORK"); identityLine:SetHeight(1); identityLine:SetPoint("TOPLEFT", identity, "BOTTOMLEFT", 0, -5); identityLine:SetPoint("TOPRIGHT", identity, "BOTTOMRIGHT", 0, -5); SetTextureColor(identityLine, UI_COLOR.border)

    local professionTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    professionTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 13, -78)
    professionTitle:SetText(L.professions); professionTitle:SetTextColor(0.78, 0.88, 0.95)

    local ds = MakeFlatSearch(right, 285, 26); ds:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -105); ds:SetMaxLetters(60); ds:SetScript("OnTextChanged", function() if Sync.detailScroll then FauxScrollFrame_SetOffset(Sync.detailScroll, 0) end; Sync:RefreshDetails() end); ds:SetScript("OnEscapePressed", ds.ClearFocus); self.detailSearch = ds
    local detailPlaceholder = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); detailPlaceholder:SetPoint("LEFT", ds, "LEFT", 9, 0); detailPlaceholder:SetText(L.professionSearch); detailPlaceholder:SetTextColor(0.42, 0.52, 0.61); self.detailPlaceholder = detailPlaceholder
    ds:HookScript("OnEditFocusGained", function() detailPlaceholder:Hide() end)
    ds:HookScript("OnEditFocusLost", function(self) if self:GetText() == "" then detailPlaceholder:Show() end end)
    ds:HookScript("OnTextChanged", function(self) if self:GetText() ~= "" then detailPlaceholder:Hide() end end)
    self.summary = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.summary:SetPoint("LEFT", ds, "RIGHT", 13, 0); self.summary:SetTextColor(0.49, 0.63, 0.73)

    self.detailRows = {}
    for index = 1, 7 do
        local row = CreateFrame("Button", nil, right); row:SetHeight(29); row:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -140 - (index - 1) * 29); row:SetPoint("RIGHT", right, "RIGHT", -30, 0)
        row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.text:SetPoint("LEFT", row, "LEFT", 9, 0); row.text:SetPoint("RIGHT", row, "RIGHT", -148, 0); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0); row.detail:SetTextColor(0.62, 0.68, 0.74)
        row:SetScript("OnClick", function(self) if self.value and self.value.tradeLink then OpenTradeLink(self.value.tradeLink) end end)
        row:SetScript("OnEnter", function(self) self.rowHover = true; PaintDetailRow(self, self.rowAlternate); if self.value and self.value.tradeLink then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L.clickToOpen); GameTooltip:Show() end end)
        row:SetScript("OnLeave", function(self) self.rowHover = nil; PaintDetailRow(self, self.rowAlternate); GameTooltip:Hide() end)
        self.detailRows[index] = row
    end
    local detailScroll = CreateFrame("ScrollFrame", "GVESyncDetailScroll", right, "FauxScrollFrameTemplate"); detailScroll:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -140); detailScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -7, 8); detailScroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, Sync.detailRowHeight or 48, function() Sync:RefreshDetails() end) end); detailScroll:EnableMouseWheel(true); detailScroll:SetScript("OnMouseWheel", function(self, delta) local bar = _G[(self:GetName() or "").."ScrollBar"]; if bar then bar:SetValue(bar:GetValue() - delta * (Sync.detailRowHeight or 48)) end end); self.detailScroll = detailScroll
    self.emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.emptyText:SetPoint("CENTER", detailScroll, "CENTER", -8, 4); self.emptyText:SetWidth(420); self.emptyText:SetJustifyH("CENTER"); self.emptyText:SetTextColor(0.48, 0.58, 0.67); self.emptyText:Hide()

    local help = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); help:SetPoint("LEFT", footer, "LEFT", 10, 0); help:SetWidth(405); help:SetJustifyH("LEFT"); help:SetText(L.footerShort); help:SetTextColor(0.48, 0.58, 0.67)
    local helpButton = MakeFlatButton(footer, 22, 20, "?"); helpButton:SetPoint("LEFT", help, "RIGHT", 6, 0); helpButton:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.help, 0.88, 0.93, 0.98, true); GameTooltip:Show() end); helpButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local shareP = MakeCheck(footer, L.shareP); shareP:SetPoint("RIGHT", footer, "RIGHT", -150, 0); shareP:SetChecked(self.db.settings.shareProfessions); shareP:SetScript("OnClick", function(self) Sync.db.settings.shareProfessions = self:GetChecked() and true or false end)

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
Sync.elapsed = 0

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
    elseif event == "CHAT_MSG_ADDON" then
        Sync:OnAddonMessage(...)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "SPELLS_CHANGED" then
        Sync.capturePending = GetTime() + 0.25
    elseif event == "PLAYER_GUILD_UPDATE" then
        Sync:InitDB()
        Sync.capturePending = GetTime() + 0.25
        Sync:RefreshUI()
    elseif event == "GUILD_ROSTER_UPDATE" and Sync.waitingForGuild then
        Sync:InitDB()
        Sync.capturePending = GetTime() + 0.25
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
    if Sync.elapsed < SEND_INTERVAL then return end
    Sync.elapsed = 0
    local queued = table.remove(Sync.sendQueue, 1)
    if queued then SendAddonMessage(PREFIX, queued.message, "WHISPER", queued.target) end
    local now = GetTime()
    for key, request in pairs(Sync.pending) do
        if now > (request.deadline or 0) or now - (request.lastActivity or request.started) > REQUEST_TIMEOUT then
            Sync.pending[key] = nil
            Sync.receiving[key] = nil
            Sync.viewMessages[key] = L.timeout
            Sync:RefreshUI()
        end
    end
end)
