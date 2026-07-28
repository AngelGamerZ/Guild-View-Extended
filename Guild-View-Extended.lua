---------------------------------------------------------------------------
-- Guild-View-Extended
-- Erweitertes Gildenfenster fuer WoW 3.3.5a / Ascension: Conquest of Azeroth
-- Oeffnen: /gve oder /guildview  (oder die eigene Gildentaste)
---------------------------------------------------------------------------
local GVE = {}
_G["GVE"] = GVE

---------------------------------------------------------------------------
-- Log-System:  /gve log  oeffnet ein Fenster mit kopierbarem Text.
-- Kritische Pfade laufen in pcall -- Fehler landen im Log statt das
-- Addon zu toeten.
---------------------------------------------------------------------------
local LOG_MAX = 200
GVE.log = {}

local CSV_MAX_NAMES = 5000
local CSV_TEXT = GetLocale() == "deDE" and {
    button       = "CSV exportieren",
    loading      = "Roster wird geladen ...",
    title        = "CSV-Export",
    copyHint     = "Drücke Strg+C, um die CSV zu kopieren.",
    count        = "%d Charaktere exportiert",
    close        = "Schließen",
    tooMany      = "CSV-Export abgebrochen: Mehr als %d eindeutige Charaktere gefunden.",
} or {
    button       = "Export CSV",
    loading      = "Loading roster ...",
    title        = "CSV Export",
    copyHint     = "Press Ctrl+C to copy the CSV.",
    count        = "%d characters exported",
    close        = CLOSE or "Close",
    tooMany      = "CSV export cancelled: More than %d unique characters were found.",
}

local ACTION_TEXT = GetLocale() == "deDE" and {
    inviteGroup  = "Invite GRP",
    leaveGuild   = "Gilde verlassen",
    leaveConfirm = "Möchtest du die Gilde wirklich verlassen?",
} or {
    inviteGroup  = "Invite GRP",
    leaveGuild   = "Leave Guild",
    leaveConfirm = "Are you sure you want to leave the guild?",
}

local function Log(msg)
    local t = GVE.log
    t[#t+1] = date("%H:%M:%S").."  "..tostring(msg)
    if #t > LOG_MAX then table.remove(t, 1) end
end

local function Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        Log("FEHLER in "..label..": "..tostring(err))
        if not GVE.errorNotified then
            GVE.errorNotified = true
            print("|cffff3333[Guild-View-Extended]|r Fehler aufgetreten -- |cffffcc00/gve log|r")
        end
    end
    return ok
end

-- Log-Fenster mit markierbarem Text (Strg+C zum Kopieren)
local logFrame
local function ShowLogWindow()
    if not logFrame then
        local w = CreateFrame("Frame", "GVELogWindow", UIParent)
        w:SetWidth(560); w:SetHeight(360)
        w:SetPoint("CENTER")
        w:SetMovable(true); w:EnableMouse(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop",  w.StopMovingOrSizing)
        w:SetFrameStrata("DIALOG")
        w:SetBackdrop({
            bgFile="Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        w:SetBackdropColor(0, 0, 0, 0.95)
        tinsert(UISpecialFrames, "GVELogWindow")

        local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", w, "TOP", 0, -8)
        title:SetText("|cff33aaffGuild-View-Extended|r - Log  (Strg+C kopiert Markiertes)")

        local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 2, 2)

        local sf = CreateFrame("ScrollFrame", "GVELogWindowScroll", w, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", w, "TOPLEFT", 10, -28)
        sf:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -30, 10)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(500)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        w.editBox = eb
        logFrame = w
    end
    logFrame.editBox:SetText(table.concat(GVE.log, "\n"))
    logFrame:Show()
    logFrame.editBox:HighlightText()   -- alles vormarkiert -> direkt Strg+C
end

---------------------------------------------------------------------------
-- Layout-Konstanten
---------------------------------------------------------------------------
local W, H     = 1020, 640
local LOG_W    = 220
local PAD      = 12
local TITLE_H  = 32
local FILTER_H = 30
local COL_H    = 18
local ROW_H    = 16
local BOTTOM_H = 130
local ROSTER_REFRESH_SECONDS = 5

local ROSTER_W = W - LOG_W - PAD * 3
local ROSTER_H = H - PAD - TITLE_H - 6 - FILTER_H - 4 - COL_H - 2 - BOTTOM_H - PAD - 10
local NUM_ROWS = math.floor(ROSTER_H / ROW_H)

---------------------------------------------------------------------------
-- Klassen-Farben
-- Ascension CoA hat 31 Klassen (10 Standard + 21 Custom). Nichts hard-
-- coden: der Client befuellt RAID_CLASS_COLORS selbst (inkl. Customs).
-- Klassenliste fuer den Filter wird dynamisch aus dem Roster aufgebaut.
---------------------------------------------------------------------------
local function ClassColor(token)
    local c = token and ((CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[token])
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

---------------------------------------------------------------------------
-- Spalten
---------------------------------------------------------------------------
local COLS = {
    {key="name",  label="Name",  w=160},
    {key="level", label="Lvl",   w=38},
    {key="class", label="Class", w=100},
    {key="zone",  label="Zone",  w=165},
    {key="rank",  label="Rank",  w=120},
    {key="note",  label="Note",  w=0},
}
do
    local used = 0
    for _, c in ipairs(COLS) do used = used + c.w end
    COLS[#COLS].w = ROSTER_W - used - 20
end

---------------------------------------------------------------------------
-- Zustand
---------------------------------------------------------------------------
local members   = {}
local filtered  = {}
local ranks     = {}   -- {[rankName]=true}
local classes   = {}   -- {[classKey]=Anzeigename}, dynamisch aus Roster

local sortKey   = "name"
local sortAsc   = true
local searchStr = ""

-- Filter: leeres Set = kein Filter (alle sichtbar)
local filterClasses = {}
local filterRanks   = {}
local filterOnline  = false

-- Lua 5.1 lower() behandelt UTF-8 je nach Client nur eingeschraenkt.
-- Die in WoW-Namen ueblichen lateinischen Grossbuchstaben werden deshalb
-- vor dem ASCII-lower() explizit gefaltet. Der Originalname bleibt unveraendert.
local UTF8_CASE_PAIRS = {
    {"À","à"}, {"Á","á"}, {"Â","â"}, {"Ã","ã"}, {"Ä","ä"}, {"Å","å"},
    {"Æ","æ"}, {"Ç","ç"}, {"È","è"}, {"É","é"}, {"Ê","ê"}, {"Ë","ë"},
    {"Ì","ì"}, {"Í","í"}, {"Î","î"}, {"Ï","ï"}, {"Ð","ð"}, {"Ñ","ñ"},
    {"Ò","ò"}, {"Ó","ó"}, {"Ô","ô"}, {"Õ","õ"}, {"Ö","ö"}, {"Ø","ø"},
    {"Ù","ù"}, {"Ú","ú"}, {"Û","û"}, {"Ü","ü"}, {"Ý","ý"}, {"Þ","þ"},
    {"Ā","ā"}, {"Ă","ă"}, {"Ą","ą"}, {"Ć","ć"}, {"Ĉ","ĉ"}, {"Ċ","ċ"},
    {"Č","č"}, {"Ď","ď"}, {"Đ","đ"}, {"Ē","ē"}, {"Ĕ","ĕ"}, {"Ė","ė"},
    {"Ę","ę"}, {"Ě","ě"}, {"Ĝ","ĝ"}, {"Ğ","ğ"}, {"Ġ","ġ"}, {"Ģ","ģ"},
    {"Ĥ","ĥ"}, {"Ħ","ħ"}, {"Ĩ","ĩ"}, {"Ī","ī"}, {"Ĭ","ĭ"}, {"Į","į"},
    {"İ","i"}, {"Ĳ","ĳ"}, {"Ĵ","ĵ"}, {"Ķ","ķ"}, {"Ĺ","ĺ"}, {"Ļ","ļ"},
    {"Ľ","ľ"}, {"Ŀ","ŀ"}, {"Ł","ł"}, {"Ń","ń"}, {"Ņ","ņ"}, {"Ň","ň"},
    {"Ŋ","ŋ"}, {"Ō","ō"}, {"Ŏ","ŏ"}, {"Ő","ő"}, {"Œ","œ"}, {"Ŕ","ŕ"},
    {"Ŗ","ŗ"}, {"Ř","ř"}, {"Ś","ś"}, {"Ŝ","ŝ"}, {"Ş","ş"}, {"Š","š"},
    {"Ţ","ţ"}, {"Ť","ť"}, {"Ŧ","ŧ"}, {"Ũ","ũ"}, {"Ū","ū"}, {"Ŭ","ŭ"},
    {"Ů","ů"}, {"Ű","ű"}, {"Ų","ų"}, {"Ŵ","ŵ"}, {"Ŷ","ŷ"}, {"Ÿ","ÿ"},
    {"Ź","ź"}, {"Ż","ż"}, {"Ž","ž"}, {"ẞ","ß"},
}

local function CaseFoldName(value)
    local folded = value
    for _, pair in ipairs(UTF8_CASE_PAIRS) do
        folded = folded:gsub(pair[1], pair[2])
    end
    return folded:lower()
end

local function CleanCharacterName(value)
    if type(value) ~= "string" then return nil end
    local name = value:gsub("[\r\n]", "")
    name = name:gsub("%-.*$", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name:find("%c") then return nil end
    return name
end

local function IsPlayerCharacterName(value)
    local playerName = UnitName("player")
    local name = CleanCharacterName(value)
    if not playerName or not name then return false end
    return CaseFoldName(name) == CaseFoldName(playerName)
end

local function EscapeCSVValue(value)
    if value:find('[,"\r\n]') then
        return '"'..value:gsub('"', '""')..'"'
    end
    return value
end

-- Reine Hilfsfunktion, damit die CSV-Regeln ausserhalb des WoW-Clients
-- automatisiert getestet werden koennen. Bei Namensduplikaten bleiben
-- Schreibweise und Gildenrang des ersten Eintrags erhalten.
function GVE:BuildCSVFromMembers(rawMembers)
    local unique, names = {}, {}
    for _, rawMember in ipairs(rawMembers or {}) do
        local rawName = type(rawMember) == "table" and rawMember.name or rawMember
        local rank = type(rawMember) == "table" and rawMember.rank or ""
        if type(rank) ~= "string" then rank = "" end
        rank = rank:gsub("[\r\n]", "")

        local name = CleanCharacterName(rawName)
        if name then
            local key = CaseFoldName(name)
            if not unique[key] then
                unique[key] = true
                names[#names+1] = {name=name, rank=rank, key=key}
                if #names > CSV_MAX_NAMES then
                    return nil, nil, format(CSV_TEXT.tooMany, CSV_MAX_NAMES)
                end
            end
        end
    end

    table.sort(names, function(a, b)
        if a.key == b.key then return a.name < b.name end
        return a.key < b.key
    end)

    local lines = {"character_name,guild_rank"}
    for _, entry in ipairs(names) do
        lines[#lines+1] = EscapeCSVValue(entry.name)..","..EscapeCSVValue(entry.rank)
    end
    return table.concat(lines, "\n"), #names
end

-- "Zuletzt Online" ist nur fuer Gildenmeister und Offiziere gedacht;
-- als Offizier-Merkmal dient das Recht, Offiziersnotizen zu sehen.
local function CanSeeLastOnline()
    return IsGuildLeader() or CanViewOfficerNote()
end

---------------------------------------------------------------------------
-- Backdrop-Definitionen
---------------------------------------------------------------------------
local MAIN_BD = {
    bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={left=11,right=12,top=12,bottom=11},
}
local PANEL_BD = {
    bgFile="Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3},
}

---------------------------------------------------------------------------
-- Hilfsfunktion: einfache Checkbox ohne globalen Namen
---------------------------------------------------------------------------
local function MakeCheckbox(parent)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(16, 16)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetDisabledTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 3, 0)
    cb.lbl = lbl
    -- Label mit anklickbar machen: Trefferflaeche nach rechts erweitern
    cb.SetLabel = function(self, text)
        self.lbl:SetText(text)
        self:SetHitRectInsets(0, -(self.lbl:GetStringWidth() + 6), 0, 0)
    end
    return cb
end

---------------------------------------------------------------------------
-- Daten laden
---------------------------------------------------------------------------
function GVE:LoadRoster()
    wipe(members)
    wipe(ranks)
    wipe(classes)

    -- 3.3.5a: GetNumGuildMembers() liefert nur EINEN Wert (sichtbare Eintraege);
    -- Online-Zaehler gibt es erst ab Cataclysm -> selbst zaehlen.
    local total  = GetNumGuildMembers()
    local online = 0
    for i = 1, total do
        local name, rank, rankIndex, level, class, zone,
              note, onote, isOnline, status, cf = GetGuildRosterInfo(i)
        if name then
            -- Custom-Klassen (CoA) liefern teils leeren lokalisierten Namen;
            -- dann auf den classFile-Token zurueckfallen (und umgekehrt).
            local disp = (class and class ~= "" and class) or cf or ""
            local key  = (cf and cf ~= "" and cf) or disp

            -- Zuletzt online (in Stunden) + Kurztext
            local lastH, lastText
            if isOnline then
                lastH, lastText = 0, "|cff33ff33"..(FRIENDS_LIST_ONLINE or "Online").."|r"
            else
                local yy, mo, dd, hh = GetGuildRosterLastOnline(i)
                yy, mo, dd, hh = yy or 0, mo or 0, dd or 0, hh or 0
                lastH = ((yy * 12 + mo) * 30 + dd) * 24 + hh
                if     yy > 0 then lastText = yy.." J."
                elseif mo > 0 then lastText = mo.." Mon."
                elseif dd > 0 then lastText = dd.." Tage"
                else               lastText = hh.." Std." end
            end
            members[#members+1] = {
                name=name, rank=rank or "", rankIndex=rankIndex or 0,
                level=level or 0, class=disp, classKey=key,
                zone=zone or "", note=note or "", officerNote=onote or "",
                online=isOnline, status=status or 0,
                index=i,   -- Roster-Index fuer Notiz-APIs
                lastOnline=lastH, lastOnlineText=lastText,
            }
            if isOnline then online = online + 1 end
            if rank and rank ~= "" then ranks[rank] = true end
            if key  and key  ~= "" then classes[key] = disp end
        end
    end

    if self.memberCount then
        local gname = GetGuildInfo("player") or GUILD or "Guild"
        self.memberCount:SetText(
            "|cffffff00"..gname.."|r   "..
            "|cff33aaff"..(online or 0).."|r"..
            "|cff888888/"..(total or 0).." online|r"
        )
    end

    self:UpdateRankCheckboxes()
    self:UpdateClassCheckboxes()
    self:ApplyFilter()
end

function GVE:ApplyFilter()
    wipe(filtered)
    local s    = searchStr:lower()
    local hcf  = next(filterClasses) ~= nil
    local hrf  = next(filterRanks)   ~= nil
    for _, m in ipairs(members) do
        if  (not hcf          or filterClasses[m.classKey])
        and (not hrf          or filterRanks[m.rank])
        and (not filterOnline or m.online)
        and (s == ""          or m.name:lower():find(s, 1, true))
        then
            filtered[#filtered+1] = m
        end
    end
    local sk, asc = sortKey, sortAsc
    -- WICHTIG: bei Gleichheit false liefern, sonst ist der Comparator
    -- ungueltig und table.sort wirft "invalid order function".
    table.sort(filtered, function(a, b)
        local va, vb = a[sk], b[sk]
        if type(va) ~= "number" then
            va, vb = tostring(va or ""):lower(), tostring(vb or ""):lower()
        end
        if va == vb then return false end
        if asc then return va < vb else return va > vb end
    end)
    self:RefreshRoster()
    self:RefreshColHeaders()
    self:RefreshFilterButton()
end

---------------------------------------------------------------------------
-- Hauptrahmen
---------------------------------------------------------------------------
function GVE:Build()
    local f = CreateFrame("Frame", "GVEMainFrame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop(MAIN_BD)
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:Hide()
    self.f = f

    -- ESC schliesst das Fenster. Hat die Suchleiste den Fokus, faengt ihr
    -- OnEscapePressed das ESC ab -> nur Fokus verlassen, Fenster bleibt.
    tinsert(UISpecialFrames, "GVEMainFrame")

    -- ESC ruft f:Hide() direkt auf (nicht GVE:Close) -> Aufraeumen hier
    f:SetScript("OnHide", function()
        if GVE.filterPanel then GVE.filterPanel:Hide() end
        if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then
            GuildControlPopupFrame:Hide()
        end
    end)
    f:SetScript("OnShow", function(self)
        self.rosterRefreshElapsed = 0
    end)
    -- 3.3.5a sendet fremde Notiz-/Roster-Aenderungen nicht in jeder
    -- Situation ungefragt an den Client. Solange GuildView sichtbar ist,
    -- fragen wir deshalb moderat nach und lassen GUILD_ROSTER_UPDATE die
    -- bestehenden Listen und ein offenes Detailfenster aktualisieren.
    f:SetScript("OnUpdate", function(self, elapsed)
        GVE:OnRosterRefreshUpdate(self, elapsed)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cff33aaffGuild-View-Extended|r")

    local mc = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mc:SetPoint("TOP", f, "TOP", 0, -27)
    self.memberCount = mc

    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -(LOG_W + PAD*2 + 2), -PAD)
    sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(LOG_W + PAD*2 + 2),  PAD)
    sep:SetTexture(0.3, 0.5, 0.8, 0.3)

    self:BuildFilterBar()
    self:BuildFilterPanel()   -- vor ColHeaders, damit filterPanel referenzierbar
    self:BuildColHeaders()
    self:BuildRosterRows()
    self:BuildBottomPanels()
    self:BuildLogPanel()
end

function GVE:OnRosterRefreshUpdate(frame, elapsed)
    frame.rosterRefreshElapsed = (frame.rosterRefreshElapsed or 0) + elapsed
    if frame.rosterRefreshElapsed >= ROSTER_REFRESH_SECONDS then
        frame.rosterRefreshElapsed = 0
        SetGuildRosterShowOffline(true)
        GuildRoster()
    end
end

---------------------------------------------------------------------------
-- CSV-Export: Charakternamen + Gildenrang, kein automatischer Clipboard-Zugriff.
-- Das Fenster ist nicht modal und verwendet dasselbe Dialog-Design wie die
-- vorhandenen Log-, Detail- und Texteditor-Fenster.
---------------------------------------------------------------------------
StaticPopupDialogs["GVE_CSV_ERROR"] = {
    text = "%s",
    button1 = OKAY or "OK",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GVE_LEAVE_GUILD"] = {
    text = ACTION_TEXT.leaveConfirm,
    button1 = YES or "Yes",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        GuildLeave()
        Log("Gilde verlassen angefordert")
    end,
    showAlert = 1,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function GVE:BuildCSVWindow()
    local w = CreateFrame("Frame", "GVECSVWindow", UIParent)
    w:SetWidth(600); w:SetHeight(430)
    w:SetPoint("CENTER")
    w:SetMovable(true); w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop",  w.StopMovingOrSizing)
    w:SetFrameStrata("DIALOG")
    w:SetBackdrop(MAIN_BD)
    w:SetBackdropColor(0, 0, 0, 0.97)
    w:Hide()
    tinsert(UISpecialFrames, "GVECSVWindow")
    self.csvWindow = w

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", w, "TOP", 0, -12)
    title:SetText("|cff33aaff"..CSV_TEXT.title.."|r")

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)

    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -36)
    hint:SetText(CSV_TEXT.copyHint)

    w.countText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.countText:SetPoint("TOPRIGHT", w, "TOPRIGHT", -18, -38)
    w.countText:SetTextColor(0.65, 0.65, 0.65)

    local bg = CreateFrame("Frame", nil, w)
    bg:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -58)
    bg:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -14, 48)
    bg:SetBackdrop(PANEL_BD)
    bg:SetBackdropColor(0.02, 0.02, 0.04, 0.95)

    local sf = CreateFrame("ScrollFrame", "GVECSVScroll", bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -7)
    sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -28, 7)
    w.scroll = sf

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(520)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        w:Hide()
    end)
    sf:SetScrollChild(eb)
    w.editBox = eb
    w:SetScript("OnHide", function() eb:ClearFocus() end)

    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetWidth(110); close:SetHeight(22)
    close:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -16, 16)
    close:SetText(CSV_TEXT.close)
    close:SetScript("OnClick", function() w:Hide() end)
end

function GVE:ShowCSVWindow(csv, count)
    if not self.csvWindow then self:BuildCSVWindow() end
    local w = self.csvWindow
    w.editBox:SetText(csv)
    w.countText:SetText(format(CSV_TEXT.count, count))
    w.scroll:SetVerticalScroll(0)
    w:Show()
    w.editBox:SetFocus()
    w.editBox:HighlightText()
end

function GVE:CreateCSVExport()
    local csv, count, err = self:BuildCSVFromMembers(members)
    if not csv then
        Log(err)
        print("|cffff3333[Guild-View-Extended]|r "..err)
        StaticPopup_Show("GVE_CSV_ERROR", err)
        return
    end

    Log("CSV-Export erstellt: "..count.." Charaktere")
    self:ShowCSVWindow(csv, count)
end

function GVE:UpdateCSVButton()
    if not self.csvButton then return end
    if self.csvPending then
        self.csvButton:SetText(CSV_TEXT.loading)
        self.csvButton:Disable()
    else
        self.csvButton:SetText(CSV_TEXT.button)
        self.csvButton:Enable()
    end
end

function GVE:RequestCSVExport()
    if self.rosterLoaded then
        self:CreateCSVExport()
        return
    end
    if self.csvPending then return end

    self.csvPending = true
    self:UpdateCSVButton()
    Log("CSV-Export wartet auf GUILD_ROSTER_UPDATE")

    -- 3.3.5a-API: Offline-Mitglieder vor der asynchronen Abfrage einschalten.
    SetGuildRosterShowOffline(true)
    GuildRoster()
end

---------------------------------------------------------------------------
-- Filterleiste: nur Suchfeld + Filter-Button
---------------------------------------------------------------------------
function GVE:BuildFilterBar()
    local f    = self.f
    local yOff = -(PAD + TITLE_H + 2)

    local slbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, yOff)
    slbl:SetText(SEARCH or "Search")
    slbl:SetTextColor(0.7, 0.7, 0.7)

    local sbox = CreateFrame("EditBox", "GVESearchBox", f, "InputBoxTemplate")
    sbox:SetSize(160, 20)
    sbox:SetPoint("LEFT", slbl, "RIGHT", 5, 0)
    sbox:SetAutoFocus(false)
    sbox:SetMaxLetters(40)
    sbox:SetScript("OnTextChanged", function(self)
        searchStr = self:GetText()
        GVE:ApplyFilter()
    end)
    sbox:SetScript("OnEscapePressed", sbox.ClearFocus)
    self.searchBox = sbox

    local fbtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    fbtn:SetSize(90, 20)
    fbtn:SetPoint("LEFT", sbox, "RIGHT", 8, 0)
    fbtn:SetText("Filter")
    fbtn:SetScript("OnClick", function() GVE:ToggleFilterPanel() end)
    self.filterBtn = fbtn

    -- "Nur Online" direkt in der Leiste, nicht im Filter-Panel
    local olCB = MakeCheckbox(f)
    olCB:SetPoint("LEFT", fbtn, "RIGHT", 10, 0)
    olCB:SetLabel(FRIENDS_LIST_ONLINE or "Online")
    olCB.lbl:SetTextColor(0.8, 0.8, 0.8)
    olCB:SetScript("OnClick", function(self)
        filterOnline = self:GetChecked() and true or false
        GVE:ApplyFilter()
    end)
    self.onlineCB = olCB

    local fl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fl:SetPoint("LEFT", olCB.lbl, "RIGHT", 12, 0)
    fl:SetTextColor(0.6, 0.9, 0.6)
    self.filterLabel = fl

    -- Gildenoptionen (Blizzards GuildControlPopupFrame) -- nur fuer den
    -- Gildenmeister aktiv, wie beim Standard-Gildenfenster.
    local gcb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gcb:SetSize(130, 20)
    gcb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(LOG_W + PAD * 2 + 8), yOff)
    gcb:SetText(GUILDCONTROL or "Guild Controls")
    gcb:SetScript("OnClick", function()
        local p = GuildControlPopupFrame
        if not p then
            Log("GuildControl: GuildControlPopupFrame existiert nicht!")
            return
        end
        if p:IsShown() then
            p:Hide()
            return
        end
        GuildRoster()   -- Rangdaten anfordern
        -- Blizzard verankert das Popup am FriendsFrame; an unser Fenster haengen
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", f, "TOPRIGHT", -6, -12)
        p:Show()
        -- WICHTIG: Erst die Initialisierung befuellt Raenge + Haken.
        -- Blizzards Funktionsname enthaelt in 3.3.5a einen Tippfehler
        -- (kleines "f") -- beide Schreibweisen probieren.
        local init = _G["GuildControlPopupframe_Initialize"]
                  or _G["GuildControlPopupFrame_Initialize"]
        if init then
            Guard("GuildControlInit", init)
            Log("GuildControl: initialisiert")
        else
            Log("GuildControl: keine Initialize-Funktion gefunden!")
        end
    end)
    self.guildControlBtn = gcb

    -- Mitglied einladen: Blizzards Standard-Dialog (ADD_GUILDMEMBER),
    -- nur aktiv mit Einladerecht -- wie beim Standard-Gildenfenster.
    local amb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    amb:SetSize(120, 20)
    amb:SetPoint("RIGHT", gcb, "LEFT", -6, 0)
    amb:SetText(ADD_GUILDMEMBER or "Add Member")
    amb:SetScript("OnClick", function()
        StaticPopup_Show("ADD_GUILDMEMBER")
    end)
    self.addMemberBtn = amb

    -- "Zuletzt Online": nur fuer Gildenmeister/Offiziere (siehe
    -- UpdateGuildControlButton). Oeffnet Panel mit Sortierung + Zeitfilter.
    local lob = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lob:SetWidth(110); lob:SetHeight(20)
    lob:SetPoint("RIGHT", amb, "LEFT", -6, 0)
    lob:SetText(LASTONLINE or "Zuletzt Online")
    lob:SetScript("OnClick", function() GVE:ToggleLastOnlineWindow() end)
    lob:Hide()
    self.lastOnlineBtn = lob
end

---------------------------------------------------------------------------
-- "Zuletzt Online"-Fenster (nur GM/Offiziere): eigene Liste aller
-- Mitglieder mit letzter Online-Zeit, auf-/absteigend sortierbar und
-- nach eigener Zeitspanne filterbar (X Tage / Wochen / Monate offline).
-- Im Hauptfenster wird "zuletzt online" bewusst NICHT angezeigt.
---------------------------------------------------------------------------
local LO_ROWS  = 18
local LO_ROW_H = 16
local loSortAsc     = false   -- Standard: laengste Offline-Zeit zuerst
local loFilterHours = nil

function GVE:BuildLastOnlineWindow()
    local w = CreateFrame("Frame", "GVELastOnlineWindow", UIParent)
    w:SetWidth(400); w:SetHeight(430)
    w:SetPoint("CENTER")
    w:SetMovable(true); w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop",  w.StopMovingOrSizing)
    w:SetFrameStrata("DIALOG")
    w:SetBackdrop(MAIN_BD)
    w:SetBackdropColor(0, 0, 0, 0.97)
    w:Hide()
    tinsert(UISpecialFrames, "GVELastOnlineWindow")
    self.lastOnlineWin = w

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", w, "TOP", 0, -12)
    title:SetText("|cff33aaff"..(LASTONLINE or "Zuletzt Online").."|r")

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)

    -- Filterzeile: Offline seit mindestens [n] [Einheit]  [Reset]
    local fl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fl:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -34)
    fl:SetText("Offline seit mind.:")
    fl:SetTextColor(0.6, 0.6, 0.6)

    local amount = CreateFrame("EditBox", "GVELastOnlineAmount", w, "InputBoxTemplate")
    amount:SetWidth(36); amount:SetHeight(20)
    amount:SetPoint("LEFT", fl, "RIGHT", 10, 0)
    amount:SetAutoFocus(false)
    amount:SetNumeric(true)
    amount:SetMaxLetters(3)
    w.amount = amount
    w.unitHours = 24

    local function ApplyTimeFilter()
        local n = tonumber(amount:GetText())
        loFilterHours = (n and n > 0) and (n * w.unitHours) or nil
        GVE:RefreshLastOnlineWindow()
    end
    amount:SetScript("OnEnterPressed", function(self)
        ApplyTimeFilter()
        self:ClearFocus()
    end)
    amount:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local UNITS = {
        {label="Tage",   hours=24},
        {label="Wochen", hours=168},
        {label="Monate", hours=720},
    }
    local unitDD = CreateFrame("Frame", "GVELastOnlineUnitDD", w, "UIDropDownMenuTemplate")
    unitDD:SetPoint("LEFT", amount, "RIGHT", -12, -2)
    UIDropDownMenu_SetWidth(unitDD, 80)
    UIDropDownMenu_Initialize(unitDD, function(self, level)
        for _, u in ipairs(UNITS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = u.label
            info.value   = u.hours
            info.checked = (w.unitHours == u.hours)
            info.func    = function(btn)
                w.unitHours = btn.value
                UIDropDownMenu_SetSelectedValue(unitDD, btn.value)
                UIDropDownMenu_SetText(unitDD, u.label)
                ApplyTimeFilter()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(unitDD, 24)
    UIDropDownMenu_SetText(unitDD, "Tage")

    local clr = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    clr:SetWidth(60); clr:SetHeight(20)
    clr:SetPoint("LEFT", unitDD, "RIGHT", -8, 2)
    clr:SetText(RESET or "Reset")
    clr:SetScript("OnClick", function()
        amount:SetText("")
        loFilterHours = nil
        GVE:RefreshLastOnlineWindow()
    end)

    -- Spaltenkoepfe: Klick auf "Zuletzt Online" wechselt die Richtung
    local nameHdr = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHdr:SetPoint("TOPLEFT", w, "TOPLEFT", 18, -64)
    nameHdr:SetText("Name")
    nameHdr:SetTextColor(1, 0.82, 0)

    local timeHdr = CreateFrame("Button", nil, w)
    timeHdr:SetWidth(140); timeHdr:SetHeight(14)
    timeHdr:SetPoint("TOPRIGHT", w, "TOPRIGHT", -40, -64)
    timeHdr.lbl = timeHdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeHdr.lbl:SetPoint("RIGHT", timeHdr, "RIGHT", 0, 0)
    timeHdr.lbl:SetTextColor(1, 0.82, 0)
    timeHdr:SetScript("OnClick", function()
        loSortAsc = not loSortAsc
        GVE:RefreshLastOnlineWindow()
    end)
    w.timeHdr = timeHdr

    -- Liste
    local sf = CreateFrame("ScrollFrame", "GVELastOnlineScroll", w, "FauxScrollFrameTemplate")
    sf:SetWidth(340); sf:SetHeight(LO_ROWS * LO_ROW_H)
    sf:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -80)
    sf:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, LO_ROW_H, function() GVE:RefreshLastOnlineWindow() end)
    end)
    w.scroll = sf

    w.rows = {}
    for i = 1, LO_ROWS do
        local row = CreateFrame("Frame", nil, w)
        row:SetWidth(360); row:SetHeight(LO_ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 2, -(i-1) * LO_ROW_H)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name:SetWidth(150); row.name:SetJustifyH("LEFT")
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.rank:SetPoint("LEFT", row, "LEFT", 155, 0)
        row.rank:SetWidth(90); row.rank:SetJustifyH("LEFT")
        row.rank:SetTextColor(0.6, 0.6, 0.6)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.time:SetJustifyH("RIGHT")
        row:Hide()
        w.rows[i] = row
    end

    -- Zaehler unten
    w.countText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.countText:SetPoint("BOTTOM", w, "BOTTOM", 0, 12)
    w.countText:SetTextColor(0.6, 0.6, 0.6)
end

function GVE:RefreshLastOnlineWindow()
    local w = self.lastOnlineWin
    if not (w and w:IsShown()) then return end

    -- Liste aufbauen (eigene Sortierung/Filter, unabhaengig vom Roster)
    local list = {}
    for _, m in ipairs(members) do
        if not loFilterHours or (m.lastOnline or 0) >= loFilterHours then
            list[#list+1] = m
        end
    end
    table.sort(list, function(a, b)
        local va, vb = a.lastOnline or 0, b.lastOnline or 0
        if va == vb then return a.name < b.name end
        if loSortAsc then return va < vb else return va > vb end
    end)

    w.timeHdr.lbl:SetText((LASTONLINE or "Zuletzt Online")..(loSortAsc and " v" or " ^"))
    w.countText:SetText(#list.." / "..#members)

    local offset = FauxScrollFrame_GetOffset(w.scroll)
    FauxScrollFrame_Update(w.scroll, #list, LO_ROWS, LO_ROW_H)
    for i = 1, LO_ROWS do
        local row = w.rows[i]
        local m   = list[i + offset]
        if m then
            local r, g, b = ClassColor(m.classKey)
            row.name:SetText(m.name)
            row.name:SetTextColor(r, g, b)
            row.rank:SetText(m.rank)
            row.time:SetText(m.lastOnlineText or "")
            row:Show()
        else
            row:Hide()
        end
    end
end

function GVE:ToggleLastOnlineWindow()
    if not CanSeeLastOnline() then return end
    if not self.lastOnlineWin then self:BuildLastOnlineWindow() end
    local w = self.lastOnlineWin
    if w:IsShown() then
        w:Hide()
    else
        w:Show()
        self:RefreshLastOnlineWindow()
    end
end

function GVE:UpdateGuildControlButton()
    -- Gildenoptionen auch fuer Offiziere (koennen auf Ascension z.B.
    -- Raenge anpassen); was genau erlaubt ist, setzt der Server durch.
    if self.guildControlBtn then
        if IsGuildLeader() or CanViewOfficerNote() then
            self.guildControlBtn:Enable()
        else
            self.guildControlBtn:Disable()
        end
    end
    if self.addMemberBtn then
        if CanGuildInvite() then self.addMemberBtn:Enable()
        else self.addMemberBtn:Disable() end
    end
    -- "Zuletzt Online" nur fuer Gildenmeister/Offiziere
    if self.lastOnlineBtn then
        if CanSeeLastOnline() then
            self.lastOnlineBtn:Show()
        else
            self.lastOnlineBtn:Hide()
            if self.lastOnlineWin then self.lastOnlineWin:Hide() end
        end
    end
end

function GVE:RefreshFilterButton()
    local parts = {}
    if next(filterClasses) then
        local n = 0; for _ in pairs(filterClasses) do n = n + 1 end
        parts[#parts+1] = n.." class(es)"
    end
    if next(filterRanks) then
        local n = 0; for _ in pairs(filterRanks) do n = n + 1 end
        parts[#parts+1] = n.." rank(s)"
    end
    if #parts > 0 then
        self.filterBtn:SetText("|cff33aaff* Filter|r")
        self.filterLabel:SetText(table.concat(parts, "  |cff444444·|r  "))
    else
        self.filterBtn:SetText("Filter")
        self.filterLabel:SetText("")
    end
end

---------------------------------------------------------------------------
-- Filter-Panel
-- Rang-Checkboxen werden einmalig pre-allokiert (WoW max = 10 Raenge).
-- Bei GUILD_ROSTER_UPDATE werden nur Text + Sichtbarkeit aktualisiert,
-- KEINE neuen Frames erstellt -> vermeidet "already exists"-Lua-Fehler.
---------------------------------------------------------------------------
local MAX_RANKS   = 10
local MAX_CLASSES = 33   -- CoA hat aktuell 31 Klassen, etwas Puffer

function GVE:BuildFilterPanel()
    local f   = self.f
    local btn = self.filterBtn

    local fp = CreateFrame("Frame", "GVEFilterPanel", f)
    fp:SetWidth(520)
    fp:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
    fp:SetFrameStrata("DIALOG")
    fp:EnableMouse(true)   -- Klicks schlucken, nicht zur Spielerliste durchreichen
    fp:SetBackdrop(MAIN_BD)
    fp:SetBackdropColor(0, 0, 0, 0.97)
    fp:Hide()
    self.filterPanel = fp

    local ROW_STRIDE = 22
    local NCOLS      = 3
    local COL_X      = 168
    local yy = -10

    -- ---- Klasse (dynamisch aus dem Roster, wie die Raenge) ----
    local cTitle = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cTitle:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    cTitle:SetText("|cff33aaff-- "..(CLASS_LABEL or CLASS or "Class").." --|r")
    yy = yy - 18

    local callBtn = CreateFrame("Button", nil, fp, "UIPanelButtonTemplate")
    callBtn:SetSize(56, 16); callBtn:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    callBtn:SetText(ALL or "All")
    callBtn:SetScript("OnClick", function()
        wipe(filterClasses)
        self:RefreshClassChecks()
        self:ApplyFilter()
    end)
    yy = yy - 20

    self.classCBs    = {}
    self.classCBRows = math.ceil(MAX_CLASSES / NCOLS)
    for i = 1, MAX_CLASSES do
        local col = (i - 1) % NCOLS
        local row = math.floor((i - 1) / NCOLS)
        local cb  = MakeCheckbox(fp)
        cb:SetPoint("TOPLEFT", fp, "TOPLEFT", 10 + col * COL_X, yy - row * ROW_STRIDE)
        cb.classKey = ""
        cb:SetScript("OnClick", function(self)
            if self:GetChecked() then filterClasses[self.classKey] = true
            else filterClasses[self.classKey] = nil end
            GVE:ApplyFilter()
        end)
        cb:Hide()
        self.classCBs[i] = cb
    end
    yy = yy - self.classCBRows * ROW_STRIDE - 8

    -- Trennlinie
    local sep1 = fp:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT",  fp, "TOPLEFT",   8, yy)
    sep1:SetPoint("TOPRIGHT", fp, "TOPRIGHT", -8, yy)
    sep1:SetTexture(0.25, 0.4, 0.6, 0.5)
    yy = yy - 10

    -- ---- Rang ----
    local rTitle = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    rTitle:SetText("|cff33aaff-- "..(RANK_LABEL or "Rank").." --|r")
    yy = yy - 18

    local rallBtn = CreateFrame("Button", nil, fp, "UIPanelButtonTemplate")
    rallBtn:SetSize(56, 16); rallBtn:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    rallBtn:SetText(ALL or "All")
    rallBtn:SetScript("OnClick", function()
        wipe(filterRanks)
        self:RefreshRankChecks()
        self:ApplyFilter()
    end)
    yy = yy - 20

    -- Pre-allokiere MAX_RANKS Checkboxen (keine globalen Namen -> kein Kollisionsproblem)
    self.rankCBs    = {}   -- die Checkbox-Widgets
    self.rankCBYOff = yy   -- Y-Startposition fuer UpdateRankCheckboxes()
    for i = 1, MAX_RANKS do
        local col = (i - 1) % NCOLS
        local row = math.floor((i - 1) / NCOLS)
        local cb  = MakeCheckbox(fp)
        cb:SetPoint("TOPLEFT", fp, "TOPLEFT", 10 + col * COL_X, yy - row * ROW_STRIDE)
        cb.rankName = ""
        cb.lbl:SetTextColor(0.75, 0.88, 0.7)
        cb:SetScript("OnClick", function(self)
            if self:GetChecked() then filterRanks[self.rankName] = true
            else filterRanks[self.rankName] = nil end
            GVE:ApplyFilter()
        end)
        cb:Hide()
        self.rankCBs[i] = cb
    end
    yy = yy - (math.ceil(MAX_RANKS / NCOLS)) * ROW_STRIDE - 8

    fp:SetHeight(-yy + 12)
end

-- Aktualisiert Text + Sichtbarkeit der pre-allokierten Rang-Checkboxen.
-- Erstellt KEINE neuen Frames -> sicher bei mehrfachem Aufruf.
function GVE:UpdateRankCheckboxes()
    if not self.rankCBs then return end
    local i = 0
    for r in pairs(ranks) do
        i = i + 1
        if i > MAX_RANKS then break end
        local cb = self.rankCBs[i]
        cb.rankName = r
        cb:SetLabel(r)
        cb:SetChecked(filterRanks[r] or false)
        cb:Show()
    end
    for j = i + 1, MAX_RANKS do
        self.rankCBs[j]:Hide()
    end
end

-- Aktualisiert die pre-allokierten Klassen-Checkboxen aus den im Roster
-- gefundenen Klassen (alphabetisch). Erstellt KEINE neuen Frames.
function GVE:UpdateClassCheckboxes()
    if not self.classCBs then return end
    local list = {}
    for key, disp in pairs(classes) do
        list[#list+1] = {key=key, disp=disp}
    end
    table.sort(list, function(a, b) return a.disp < b.disp end)
    for i = 1, MAX_CLASSES do
        local cb = self.classCBs[i]
        local e  = list[i]
        if e then
            cb.classKey = e.key
            cb:SetLabel(e.disp)
            cb.lbl:SetTextColor(ClassColor(e.key))
            cb:SetChecked(filterClasses[e.key] or false)
            cb:Show()
        else
            cb:Hide()
        end
    end
end

function GVE:RefreshClassChecks()
    for _, cb in ipairs(self.classCBs or {}) do
        cb:SetChecked(filterClasses[cb.classKey] or false)
    end
end

function GVE:RefreshRankChecks()
    for _, cb in ipairs(self.rankCBs or {}) do
        if cb.rankName and cb.rankName ~= "" then
            cb:SetChecked(filterRanks[cb.rankName] or false)
        end
    end
end

function GVE:ToggleFilterPanel()
    local fp = self.filterPanel
    if fp:IsShown() then fp:Hide() else fp:Show() end
end

---------------------------------------------------------------------------
-- Spaltenkoepfe
---------------------------------------------------------------------------
function GVE:BuildColHeaders()
    local f    = self.f
    local yOff = -(PAD + TITLE_H + 2 + FILTER_H + 4)
    local xOff = PAD
    self.colHeaders = {}
    for i, col in ipairs(COLS) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(col.w, COL_H)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.10, 0.16, 0.26, 0.9)

        local brd = btn:CreateTexture(nil, "BORDER")
        brd:SetHeight(1)
        brd:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT")
        brd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
        brd:SetTexture(0.2, 0.4, 0.65, 0.6)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", btn, "LEFT", 4, 0)
        lbl:SetTextColor(1, 0.82, 0)
        btn.lbl = lbl; btn.colKey = col.key; btn.colLabel = col.label

        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        btn:SetScript("OnClick", function(self)
            if sortKey == self.colKey then sortAsc = not sortAsc
            else sortKey = self.colKey; sortAsc = true end
            GVE:ApplyFilter()
        end)
        self.colHeaders[i] = btn
        xOff = xOff + col.w + 1
    end
    self:RefreshColHeaders()
end

function GVE:RefreshColHeaders()
    for _, btn in ipairs(self.colHeaders or {}) do
        local arrow = (sortKey == btn.colKey) and (sortAsc and " v" or " ^") or ""
        btn.lbl:SetText(btn.colLabel .. arrow)
    end
end

---------------------------------------------------------------------------
-- Roster-Zeilen
---------------------------------------------------------------------------
function GVE:AddLeaveGuildMenuItem()
    local info = UIDropDownMenu_CreateInfo()
    info.text = ACTION_TEXT.leaveGuild
    info.notCheckable = true
    info.func = function()
        CloseDropDownMenus()
        StaticPopup_Show("GVE_LEAVE_GUILD")
    end
    UIDropDownMenu_AddButton(info, 1)
end

function GVE:BuildRosterRows()
    local f      = self.f
    local yStart = -(PAD + TITLE_H + 2 + FILTER_H + 4 + COL_H + 1)

    local sf = CreateFrame("ScrollFrame", "GVEScroll", f, "FauxScrollFrameTemplate")
    sf:SetSize(ROSTER_W, ROSTER_H)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, yStart)
    self.sf = sf
    sf:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, function() GVE:RefreshRoster() end)
    end)

    self.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(ROSTER_W - 17, ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i-1)*ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(i%2==0 and 0.09 or 0.05, i%2==0 and 0.09 or 0.05, 0.15, 0.55)

        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        -- Rechtsklick: Blizzards Standard-Kontextmenue (Fluestern, Einladen,
        -- Ziel, ...) -- dasselbe wie im normalen Gildenfenster.
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            local m = self.member
            if not m then return end
            if button == "RightButton" then
                FriendsFrame_ShowDropdown(m.name, m.online)
                if IsPlayerCharacterName(m.name) then
                    GVE:AddLeaveGuildMenuItem()
                end
            elseif IsShiftKeyDown() and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
                -- Shift-Klick: Name in offene Chatzeile einfuegen
                ChatEdit_InsertLink(m.name)
            else
                -- Linksklick: Detailfenster wie im Standard-Gildenfenster
                GVE:ShowMemberDetail(m)
            end
        end)
        row.fields = {}
        local fx = 0
        for _, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetWidth(col.w - 4)
            fs:SetHeight(ROW_H)
            fs:SetPoint("LEFT", row, "LEFT", fx + 2, 0)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("MIDDLE")
            row.fields[#row.fields+1] = fs
            fx = fx + col.w + 1
        end
        row:Hide()
        self.rows[i] = row
    end
end

function GVE:RefreshRoster()
    local offset = FauxScrollFrame_GetOffset(self.sf)
    FauxScrollFrame_Update(self.sf, #filtered, NUM_ROWS, ROW_H)
    for i = 1, NUM_ROWS do
        local row = self.rows[i]
        local m   = filtered[i + offset]
        row.member = m
        if m then
            row:Show()
            local vals = {m.name, m.level, m.class, m.zone, m.rank, m.note}
            for j, fs in ipairs(row.fields) do
                local v = tostring(vals[j] or "")
                if j == 1 then
                    if m.online then
                        if     m.status == 1 then v = "<AFK> "..v; fs:SetTextColor(1, 0.6, 0)
                        elseif m.status == 2 then v = "<DND> "..v; fs:SetTextColor(1, 0.3, 0.3)
                        else                       fs:SetTextColor(1, 1, 1) end
                    else
                        fs:SetTextColor(0.4, 0.4, 0.4)
                    end
                elseif j == 3 then
                    local r, g, b = ClassColor(m.classKey)
                    if not m.online then r, g, b = r*0.4, g*0.4, b*0.4 end
                    fs:SetTextColor(r, g, b)
                else
                    fs:SetTextColor(m.online and 0.82 or 0.35, m.online and 0.82 or 0.35, m.online and 0.82 or 0.35)
                end
                fs:SetText(v)
            end
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Mitglieder-Detailfenster (wie Blizzards GuildMemberDetailFrame):
-- Linksklick auf einen Spieler -> Notiz, Offiziersnotiz, Befoerdern/
-- Degradieren, aus Gilde entfernen. Rechte werden geprueft, der Server
-- setzt sie zusaetzlich durch.
---------------------------------------------------------------------------
-- Gildenmeister uebertragen: Sicherheitsabfrage, Yes fuehrt aus,
-- "No - Cancel" schliesst ohne Aktion.
StaticPopupDialogs["GVE_SET_GUILDMASTER"] = {
    text = "Are you sure you want to promote %s to Guildmaster?",
    button1 = YES or "Yes",
    button2 = (NO or "No").." - "..(CANCEL or "Cancel"),
    OnAccept = function(self, data)
        GuildSetLeader(data)
        Log("Gildenmeister uebertragen an "..tostring(data))
    end,
    showAlert = 1,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs["GVE_REMOVE_MEMBER"] = {
    text = "Are you sure you want to remove %s from the guild?",
    button1 = YES or "Yes",
    button2 = (NO or "No").." - "..(CANCEL or "Cancel"),
    OnAccept = function(self, data)
        GuildUninvite(data)
        Log("Aus Gilde entfernt: "..tostring(data))
    end,
    showAlert = 1,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- Mehrzeilige Notiz-Box (3 Zeilen) mit eigenem Rahmen
local function MakeNoteBox(parent, name, onSave)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetWidth(180); bg:SetHeight(48)
    bg:SetBackdrop(PANEL_BD)
    bg:SetBackdropColor(0, 0, 0, 0.6)

    local eb = CreateFrame("EditBox", name, bg)
    eb:SetMultiLine(true)
    eb:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, -4)
    eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 4)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(31)   -- Serverlimit fuer Gildennotizen
    eb:SetScript("OnEnterPressed", function(self)
        onSave((self:GetText() or ""):gsub("\n", " "))
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Klick auf den Rahmen fokussiert das Feld
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)
    eb.bg = bg
    return eb
end

-- Rangliste (rankIndex -> Name). Bevorzugt die offizielle API (liefert
-- nur beim Gildenmeister Daten), sonst aus dem Roster abgeleitet.
local function GetRankList()
    local list = {}
    local ok, n = pcall(GuildControlGetNumRanks)
    if ok and n and n > 0 then
        for i = 1, n do list[i-1] = GuildControlGetRankName(i) end
        return list
    end
    for _, m in ipairs(members) do
        if m.rank ~= "" then list[m.rankIndex] = m.rank end
    end
    return list
end

-- Rang setzen: 3.3.5a kennt nur GuildPromote/GuildDemote (je 1 Stufe).
-- Wir steigen schrittweise; jeder Schritt wird vom Server per
-- GUILD_ROSTER_UPDATE bestaetigt, dann folgt der naechste.
function GVE:SetMemberRank(name, targetIdx)
    Log("SetMemberRank: "..name.." -> Rangindex "..targetIdx)
    self.rankTarget = {name=name, idx=targetIdx, tries=0}
    self:StepRank()
end

function GVE:StepRank()
    local t = self.rankTarget
    if not t then return end
    local cur
    for _, m in ipairs(members) do
        if m.name == t.name then cur = m.rankIndex; break end
    end
    if not cur or cur == t.idx then
        self.rankTarget = nil   -- Ziel erreicht (oder Spieler weg)
        return
    end
    if t.last == cur then
        -- Roster-Update ohne Rangaenderung: warten, nach 4x aufgeben
        t.tries = t.tries + 1
        if t.tries > 4 then
            Log("StepRank abgebrochen: Rang von "..t.name.." aendert sich nicht (fehlendes Recht?)")
            self.rankTarget = nil
        end
        return
    end
    t.last, t.tries = cur, 0
    if cur > t.idx then GuildPromote(t.name) else GuildDemote(t.name) end
end

function GVE:BuildMemberDetail()
    local d = CreateFrame("Frame", "GVEMemberDetail", self.f)
    d:SetWidth(210); d:SetHeight(338)
    d:SetPoint("TOPLEFT", self.f, "TOPRIGHT", 2, -60)
    d:SetFrameStrata("DIALOG")
    d:EnableMouse(true)
    d:SetBackdrop(MAIN_BD)
    d:SetBackdropColor(0, 0, 0, 0.97)
    d:Hide()
    self.detail = d

    local xb = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)

    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -14)

    d.info = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    d.info:SetTextColor(0.8, 0.8, 0.8)

    -- Rang: EIN Dropdown statt Befoerdern/Degradieren-Buttons.
    -- Zeigt den aktuellen Rang; eine Auswahl setzt den Rang schrittweise.
    d.rank = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.rank:SetPoint("TOPLEFT", d.info, "BOTTOMLEFT", 0, -6)
    d.rank:SetTextColor(0.6, 0.6, 0.6)
    d.rank:SetText((RANK or "Rank")..":")

    -- Gildenmeister uebertragen: nur fuer den Gildenmeister sichtbar,
    -- sitzt UEBER dem Rang-Dropdown. Mit Sicherheitsabfrage.
    d.gmBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.gmBtn:SetWidth(180); d.gmBtn:SetHeight(18)
    d.gmBtn:SetPoint("TOPLEFT", d.rank, "BOTTOMLEFT", 0, -3)
    d.gmBtn:SetText(GUILD_PROMOTE or "Promote to Guildmaster")
    local gmFS = d.gmBtn:GetFontString()
    if gmFS then gmFS:SetFontObject(GameFontNormalSmall) end
    d.gmBtn:SetScript("OnClick", function()
        if d.member then
            local dlg = StaticPopup_Show("GVE_SET_GUILDMASTER", d.member.name)
            if dlg then dlg.data = d.member.name end
        end
    end)
    d.gmBtn:Hide()

    d.rankDD = CreateFrame("Frame", "GVEDetailRankDD", d, "UIDropDownMenuTemplate")
    d.rankDD:SetPoint("TOPLEFT", d.gmBtn, "BOTTOMLEFT", -18, -2)
    UIDropDownMenu_SetWidth(d.rankDD, 145)
    UIDropDownMenu_Initialize(d.rankDD, function(self, level)
        local m = d.member
        if not m then return end
        local ranklist = GetRankList()
        for idx = 1, 20 do   -- Rangindex 0 = Gildenmeister, bewusst nicht waehlbar
            local rname = ranklist[idx]
            if rname then
                local info = UIDropDownMenu_CreateInfo()
                info.text    = rname
                info.value   = idx
                info.checked = (idx == m.rankIndex)
                info.func    = function(btn)
                    UIDropDownMenu_SetSelectedValue(d.rankDD, btn.value)
                    UIDropDownMenu_SetText(d.rankDD, rname)
                    GVE:SetMemberRank(m.name, btn.value)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)

    -- Spielernotiz (3-zeilige Box)
    local nl = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nl:SetPoint("TOPLEFT", d.rankDD, "BOTTOMLEFT", 18, -6)
    nl:SetText(LABEL_NOTE or "Note")
    nl:SetTextColor(0.6, 0.6, 0.6)
    d.noteBox = MakeNoteBox(d, "GVEDetailNote", function(text)
        if d.member then
            GuildRosterSetPublicNote(d.member.index, text)
            Log("Notiz gesetzt fuer "..d.member.name)
        end
    end)
    d.noteBox.bg:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 0, -3)

    -- Offiziersnotiz (3-zeilige Box)
    local ol = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ol:SetPoint("TOPLEFT", d.noteBox.bg, "BOTTOMLEFT", 0, -8)
    ol:SetText(GUILD_OFFICERNOTES_LABEL or "Officer Note")
    ol:SetTextColor(0.6, 0.6, 0.6)
    d.officerLabel = ol
    d.officerBox = MakeNoteBox(d, "GVEDetailOfficerNote", function(text)
        if d.member then
            GuildRosterSetOfficerNote(d.member.index, text)
            Log("Offiziersnotiz gesetzt fuer "..d.member.name)
        end
    end)
    d.officerBox.bg:SetPoint("TOPLEFT", ol, "BOTTOMLEFT", 0, -3)

    d.invite = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.invite:SetWidth(180); d.invite:SetHeight(20)
    d.invite:SetPoint("TOPLEFT", d.officerBox.bg, "BOTTOMLEFT", 0, -12)
    d.invite:SetText(ACTION_TEXT.inviteGroup)
    d.invite:SetScript("OnClick", function()
        if d.member and not IsPlayerCharacterName(d.member.name) then
            InviteUnit(d.member.name)
            Log("Gruppeneinladung gesendet an "..d.member.name)
        end
    end)

    d.remove = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.remove:SetWidth(180); d.remove:SetHeight(20)
    d.remove:SetPoint("TOPLEFT", d.invite, "BOTTOMLEFT", 0, -6)
    d.remove:SetText("|cffff3333"..(REMOVE or "Remove").."|r")
    d.remove:SetScript("OnClick", function()
        if d.member then
            local dlg = StaticPopup_Show("GVE_REMOVE_MEMBER", d.member.name)
            if dlg then dlg.data = d.member.name end
        end
    end)
end

function GVE:ShowMemberDetail(m)
    if not self.detail then self:BuildMemberDetail() end
    local d = self.detail
    d.member = m

    local r, g, b = ClassColor(m.classKey)
    d.name:SetText(m.name)
    d.name:SetTextColor(r, g, b)
    d.info:SetText((LEVEL or "Level").." "..m.level.."  "..m.class)

    -- GM-Transfer-Button: nur der Gildenmeister sieht ihn, und nicht
    -- bei sich selbst
    if IsGuildLeader() and m.name ~= UnitName("player") then
        d.gmBtn:Show()
    else
        d.gmBtn:Hide()
    end

    -- Dropdown zeigt den aktuellen Rang, solange nichts gewaehlt wurde
    UIDropDownMenu_SetSelectedValue(d.rankDD, m.rankIndex)
    UIDropDownMenu_SetText(d.rankDD, m.rank)
    -- Rechte pruefen wie im Standardfenster
    if CanGuildPromote() or CanGuildDemote() then
        UIDropDownMenu_EnableDropDown(d.rankDD)
    else
        UIDropDownMenu_DisableDropDown(d.rankDD)
    end
    if CanGuildRemove() then d.remove:Enable() else d.remove:Disable() end
    if IsPlayerCharacterName(m.name) then d.invite:Disable() else d.invite:Enable() end

    d.noteBox:SetText(m.note or "")
    if CanEditPublicNote() then d.noteBox:EnableMouse(true); d.noteBox:SetTextColor(1,1,1)
    else d.noteBox:EnableMouse(false); d.noteBox:SetTextColor(0.5,0.5,0.5) end

    if CanViewOfficerNote() then
        d.officerLabel:Show(); d.officerBox:Show()
        d.officerBox:SetText(m.officerNote or "")
        if CanEditOfficerNote() then d.officerBox:EnableMouse(true); d.officerBox:SetTextColor(1,1,1)
        else d.officerBox:EnableMouse(false); d.officerBox:SetTextColor(0.5,0.5,0.5) end
    else
        d.officerLabel:Hide(); d.officerBox:Hide()
    end

    d:Show()
end

-- Nach GUILD_ROSTER_UPDATE offene Details aktualisieren (Rang/Notizen
-- koennen sich durch eigene Aktionen geaendert haben)
function GVE:RefreshMemberDetail()
    local d = self.detail
    if not (d and d:IsShown() and d.member) then return end
    for _, m in ipairs(members) do
        if m.name == d.member.name then
            self:ShowMemberDetail(m)
            return
        end
    end
    d:Hide()   -- Spieler nicht mehr in der Gilde
end

---------------------------------------------------------------------------
-- Untere Panels
---------------------------------------------------------------------------
-- Gemeinsamer Text-Editor fuer MOTD und Gildeninfo:
-- mehrzeilig, waechst automatisch mit dem Text und ist am Griff unten
-- rechts manuell groesser ziehbar.
function GVE:ShowTextEditor(titleText, maxLetters, initialText, onSave)
    if not self.textEditor then
        local w = CreateFrame("Frame", "GVETextEditor", UIParent)
        w:SetWidth(440); w:SetHeight(220)
        w:SetPoint("CENTER")
        w:SetMovable(true); w:EnableMouse(true)
        w:SetResizable(true)
        w:SetMinResize(320, 160)
        w:SetMaxResize(900, 700)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving)
        w:SetScript("OnDragStop",  w.StopMovingOrSizing)
        w:SetFrameStrata("DIALOG")
        w:SetBackdrop(MAIN_BD)
        w:SetBackdropColor(0, 0, 0, 0.97)
        tinsert(UISpecialFrames, "GVETextEditor")
        self.textEditor = w

        w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        w.title:SetPoint("TOP", w, "TOP", 0, -12)

        local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)

        local sf = CreateFrame("ScrollFrame", "GVETextEditorScroll", w, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -32)
        sf:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -34, 44)
        w.scroll = sf

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(380)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        w.editBox = eb

        -- Editor-Breite folgt der Fensterbreite, Hoehe waechst mit dem
        -- Text (nur nach unten, manuelles Ziehen bleibt moeglich)
        w:SetScript("OnSizeChanged", function(self)
            eb:SetWidth(self:GetWidth() - 60)
        end)
        eb:SetScript("OnTextChanged", function(self)
            local needed = self:GetHeight() + 90
            if needed > w:GetHeight() then
                w:SetHeight(math.min(700, needed))
            end
        end)

        -- Griff zum Groesserziehen (unten rechts)
        local grip = CreateFrame("Button", nil, w)
        grip:SetWidth(16); grip:SetHeight(16)
        grip:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -4, 4)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function() w:StartSizing("BOTTOMRIGHT") end)
        grip:SetScript("OnMouseUp",   function() w:StopMovingOrSizing() end)

        w.save = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        w.save:SetWidth(100); w.save:SetHeight(20)
        w.save:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -26, 14)
        w.save:SetText(SAVE or "Save")

        local cancel = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        cancel:SetWidth(100); cancel:SetHeight(20)
        cancel:SetPoint("RIGHT", w.save, "LEFT", -6, 0)
        cancel:SetText(CANCEL or "Cancel")
        cancel:SetScript("OnClick", function() w:Hide() end)
    end

    local w = self.textEditor
    w.title:SetText("|cff33aaff"..titleText.."|r")
    w.editBox:SetMaxLetters(maxLetters)
    w.editBox:SetText(initialText or "")
    w.save:SetScript("OnClick", function()
        onSave(w.editBox:GetText())
        w:Hide()
    end)
    w:SetHeight(220)   -- Startgroesse; waechst mit dem Text
    w:Show()
    w.editBox:SetFocus()
end

function GVE:BuildBottomPanels()
    local f     = self.f
    local halfW = math.floor((ROSTER_W - 8) / 2)
    local panH  = BOTTOM_H - 8

    local mf = CreateFrame("Frame", nil, f)
    mf:SetSize(halfW, panH)
    mf:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    mf:SetBackdrop(PANEL_BD)
    mf:SetBackdropColor(0.04, 0.04, 0.10, 0.85)
    local mt = mf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mt:SetPoint("TOPLEFT", mf, "TOPLEFT", 7, -5)
    mt:SetText("|cff33aaff>> |r"..(GUILD_MOTD_LABEL or "Message of the Day"))

    -- Bearbeiten (nur mit MOTD-Recht sichtbar)
    local meb = CreateFrame("Button", nil, mf, "UIPanelButtonTemplate")
    meb:SetWidth(70); meb:SetHeight(16)
    meb:SetPoint("TOPRIGHT", mf, "TOPRIGHT", -6, -4)
    meb:SetText(EDIT or "Edit")
    meb:SetScript("OnClick", function()
        GVE:ShowTextEditor(GUILD_MOTD_LABEL or "Message of the Day", 128,
            GetGuildRosterMOTD() or "",
            function(text)
                -- MOTD ist serverseitig einzeilig: Umbrueche -> Leerzeichen
                GuildSetMOTD((text or ""):gsub("\n", " "))
                Log("MOTD gesetzt")
            end)
    end)
    meb:Hide()
    self.motdEditBtn = meb
    self.motdText = mf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.motdText:SetPoint("TOPLEFT",     mt, "BOTTOMLEFT", 0, -3)
    self.motdText:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT", -6, 5)
    self.motdText:SetJustifyH("LEFT"); self.motdText:SetJustifyV("TOP")
    self.motdText:SetWordWrap(true); self.motdText:SetTextColor(0.88, 0.88, 0.78)

    local gf = CreateFrame("Frame", nil, f)
    gf:SetSize(halfW, panH)
    gf:SetPoint("BOTTOMLEFT", mf, "BOTTOMRIGHT", 8, 0)
    gf:SetBackdrop(PANEL_BD)
    gf:SetBackdropColor(0.04, 0.04, 0.10, 0.85)
    local gt = gf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gt:SetPoint("TOPLEFT", gf, "TOPLEFT", 7, -5)
    gt:SetText("|cff33aaff>> |r"..(GUILD_INFORMATION or "Guild Information"))

    -- Bearbeiten (nur mit Gildeninfo-Recht sichtbar)
    local geb = CreateFrame("Button", nil, gf, "UIPanelButtonTemplate")
    geb:SetWidth(70); geb:SetHeight(16)
    geb:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -6, -4)
    geb:SetText(EDIT or "Edit")
    geb:SetScript("OnClick", function()
        GVE:ShowTextEditor(GUILD_INFORMATION or "Guild Information", 500,
            GetGuildInfoText() or "",
            function(text)
                SetGuildInfoText(text)
                Log("Gildeninfo gesetzt")
                GuildRoster()   -- Anzeige-Aktualisierung anstossen
            end)
    end)
    geb:Hide()
    self.infoEditBtn = geb

    -- Gildeninfo scrollbar (Mausrad), falls der Text nicht ins Panel passt
    local isf = CreateFrame("ScrollFrame", nil, gf)
    isf:SetPoint("TOPLEFT",     gt, "BOTTOMLEFT", 0, -3)
    isf:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", -6, 5)
    local child = CreateFrame("Frame", nil, isf)
    child:SetSize(halfW - 16, 1)
    isf:SetScrollChild(child)

    local it = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    it:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    it:SetWidth(halfW - 16)
    it:SetJustifyH("LEFT"); it:SetJustifyV("TOP")
    it:SetWordWrap(true); it:SetTextColor(0.88, 0.88, 0.78)
    self.infoText   = it
    self.infoScroll = isf

    isf:EnableMouseWheel(true)
    isf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, it:GetStringHeight() - self:GetHeight())
        local cur = self:GetVerticalScroll() - delta * 20
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur)))
    end)
end

function GVE:RefreshBottomPanels()
    if self.motdText then self.motdText:SetText(GetGuildRosterMOTD() or "") end
    if self.infoText then
        self.infoText:SetText(GetGuildInfoText() or "")
        if self.infoScroll then self.infoScroll:SetVerticalScroll(0) end
    end
    -- Bearbeiten-Buttons nach Rechten ein-/ausblenden
    if self.motdEditBtn then
        if CanEditMOTD() then self.motdEditBtn:Show() else self.motdEditBtn:Hide() end
    end
    if self.infoEditBtn then
        if CanEditGuildInfo() then self.infoEditBtn:Show() else self.infoEditBtn:Hide() end
    end
end

---------------------------------------------------------------------------
-- Gildenprotokoll
---------------------------------------------------------------------------
local LOG_ROW_H = 36
-- Argumente: (player1, player2) wie von GetGuildEventInfo geliefert.
-- player1 = Ausfuehrender; player2 = Betroffener (bei invite/promote/etc.)
local ELOG_FMT = {
    invite      = function(p1,p2) return "|cff00ff88"..p2.."|r invited by |cffffcc00"..p1.."|r" end,
    join        = function(p1)    return "|cff00ff88"..p1.."|r has joined" end,
    promote     = function(p1,p2) return "|cff88ff88"..p2.."|r promoted by |cffffcc00"..p1.."|r" end,
    demote      = function(p1,p2) return "|cffff8888"..p2.."|r demoted by |cffffcc00"..p1.."|r" end,
    remove      = function(p1,p2) return "|cffff4444"..p2.."|r removed by |cffffcc00"..p1.."|r" end,
    quit        = function(p1)    return "|cffff4444"..p1.."|r has left" end,
    bankdeposit = function(p1)    return "|cffaaaaaa"..p1..": bank deposit|r" end,
    bankwithdraw= function(p1)    return "|cffaaaaaa"..p1..": bank withdraw|r" end,
}

function GVE:BuildLogPanel()
    local f    = self.f
    local logH = H - PAD * 2 - 2

    local lf = CreateFrame("Frame", nil, f)
    lf:SetSize(LOG_W - PAD, logH)
    lf:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
    lf:SetBackdrop(PANEL_BD)
    lf:SetBackdropColor(0.04, 0.04, 0.10, 0.85)

    local lt = lf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lt:SetPoint("TOP", lf, "TOP", 0, -5)
    lt:SetText("|cff33aaff>> |r"..(GUILD_EVENT_LOG_TITLE or "Guild Log"))

    local csvButton = CreateFrame("Button", nil, lf, "UIPanelButtonTemplate")
    csvButton:SetWidth(150); csvButton:SetHeight(20)
    csvButton:SetPoint("TOP", lf, "TOP", 0, -24)
    csvButton:SetText(CSV_TEXT.button)
    csvButton:SetScript("OnClick", function()
        Guard("CSVExportRequest", function() GVE:RequestCSVExport() end)
    end)
    self.csvButton = csvButton

    local lsf = CreateFrame("ScrollFrame", "GVELogScroll", lf, "FauxScrollFrameTemplate")
    lsf:SetPoint("TOPLEFT",     lf, "TOPLEFT",     4, -50)
    lsf:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", -4, 4)
    self.lsf = lsf

    local maxLogRows = math.floor((logH - 56) / LOG_ROW_H)
    self.logRows = {}
    for i = 1, maxLogRows do
        local row = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetWidth(LOG_W - PAD - 24)
        row:SetHeight(LOG_ROW_H - 2)
        row:SetPoint("TOPLEFT", lsf, "TOPLEFT", 4, -(i-1)*LOG_ROW_H - 2)
        row:SetJustifyH("LEFT"); row:SetJustifyV("TOP")
        row:SetWordWrap(true)
        row:Hide()
        self.logRows[i] = row
    end

    lsf:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, LOG_ROW_H, function() GVE:RefreshLog() end)
    end)
end

-- WICHTIG: hier KEIN QueryGuildEventLog() aufrufen! Das wuerde
-- GUILD_EVENT_LOG_UPDATE ausloesen -> Event-Handler ruft RefreshLog ->
-- Endlosschleife -> Spiel haengt. Query passiert nur in Open().
function GVE:RefreshLog()
    local n      = GetNumGuildEvents()
    local offset = FauxScrollFrame_GetOffset(self.lsf)
    FauxScrollFrame_Update(self.lsf, n, #self.logRows, LOG_ROW_H)
    for i = 1, #self.logRows do
        local row = self.logRows[i]
        -- GetGuildEventInfo: Index 1 = aeltester Eintrag -> rueckwaerts
        -- lesen, damit der neuste oben steht
        local idx = n - (i + offset) + 1
        if idx >= 1 then
            -- 3.3.5a: type, player1, player2, rank, year, month, day, hour
            local etype, p1, p2, _, _, _, day, hour = GetGuildEventInfo(idx)
            p1 = p1 or "?"; p2 = p2 or "?"
            local fn   = ELOG_FMT[etype]
            local text = fn and fn(p1, p2) or (tostring(etype).." "..p1)
            local age  = ""
            if (day  or 0) > 0 then age = " |cff555555["..(day ).."d]|r"
            elseif (hour or 0) > 0 then age = " |cff555555["..(hour).."h]|r" end
            row:SetText(text..age)
            row:Show()
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Oeffentliche API
---------------------------------------------------------------------------
function GVE:Open()
    Log("Open()")
    self.f:Show()
    Guard("LoadRoster", function() GVE:LoadRoster() end)
    Guard("BottomPanels", function() GVE:RefreshBottomPanels() end)
    Guard("GuildLog", function() GVE:RefreshLog() end)
    self:UpdateGuildControlButton()
    GuildRoster()        -- frische Daten anfordern (async -> GUILD_ROSTER_UPDATE)
    QueryGuildEventLog()
end

function GVE:Close()
    self.f:Hide()   -- Aufraeumen (Filter-Panel, Gildenoptionen) macht OnHide
end

function GVE:Toggle()
    if not self.f then
        Log("Toggle: Fenster existiert nicht (Init fehlgeschlagen?)")
        return
    end
    if self.f:IsShown() then self:Close() else self:Open() end
end

-- In 3.3.5a gibt es KEIN ToggleGuildFrame (das kam erst mit Cataclysm).
-- Blizzards Guild-Keybind (TOGGLEGUILDTAB) ruft ToggleFriendsFrame(3) auf --
-- Tab 3 = Gilde im Social-Fenster. Wir fangen genau diesen Aufruf ab und
-- oeffnen stattdessen unser Fenster; alle anderen Tabs (Freunde, Wer, Raid)
-- laufen unveraendert ueber das Original. Die Taste selbst bleibt frei
-- konfigurierbar, weil wir nur die Zielfunktion umleiten.
function GVE:HookGuildFrame()
    local orig = ToggleFriendsFrame
    _G["ToggleFriendsFrame"] = function(tab)
        Log("ToggleFriendsFrame("..tostring(tab)..")")
        if tab == 3 then
            GVE:Toggle()
            return
        end
        return orig(tab)
    end
    Log("Hook: ToggleFriendsFrame ersetzt")

    -- Falls Ascension zusaetzlich ein Cataclysm-artiges ToggleGuildFrame
    -- definiert hat (Custom-Client), auch das umleiten.
    if type(_G["ToggleGuildFrame"]) == "function" then
        _G["ToggleGuildFrame"] = function()
            Log("ToggleGuildFrame()")
            GVE:Toggle()
        end
        Log("Hook: ToggleGuildFrame ersetzt")
    end

    -- Gilden-Tab im Social-Fenster: der Klick auf den Tab laeuft NICHT
    -- ueber ToggleFriendsFrame -> eigenen Hook setzen, sonst landet man
    -- im alten (leeren) Gilden-Tab.
    if FriendsFrameTab3 then
        FriendsFrameTab3:HookScript("OnClick", function()
            Log("FriendsFrameTab3 geklickt")
            if FriendsFrame then HideUIPanel(FriendsFrame) end
            GVE:Open()
        end)
        Log("Hook: FriendsFrameTab3 ok")
    else
        Log("Hook: FriendsFrameTab3 existiert nicht!")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("PLAYER_LOGIN")
evtFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
evtFrame:RegisterEvent("GUILD_EVENT_LOG_UPDATE")

evtFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Slash-Befehle ZUERST, damit /gve log auch bei Init-Fehlern geht
        SLASH_GVE1 = "/gve"
        SLASH_GVE2 = "/guildview"
        SlashCmdList["GVE"] = function(msg)
            msg = (msg or ""):lower()
            if msg == "log" then
                ShowLogWindow()
            elseif msg == "clearlog" then
                wipe(GVE.log)
                GVE.errorNotified = nil
                print("|cff33aaff[Guild-View-Extended]|r Log geleert.")
            else
                GVE:Toggle()
            end
        end
        Log("PLAYER_LOGIN: Start")

        Guard("Init", function()
            GVE:Build()
            Log("Init: Fenster gebaut")
            GVE:HookGuildFrame()
            Log("Init: Hooks ok")

            -- Offline-Mitglieder in den Roster-Daten einschliessen, sonst
            -- liefert GetGuildRosterInfo nur Online-Spieler (3.3.5a-Verhalten).
            GVE.rosterLoaded = false
            SetGuildRosterShowOffline(true)
            GuildRoster()  -- Daten vorhalten fuer das erste Oeffnen
            Log("Init: Roster angefordert")
        end)

        Log("PLAYER_LOGIN: Ende")
        print("|cff33aaff[Guild-View-Extended]|r loaded  |cffffcc00/gve|r oeffnet,  |cffffcc00/gve log|r zeigt das Log.")

    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Feuert beim Laden schon VOR PLAYER_LOGIN -> erst reagieren,
        -- wenn das Fenster gebaut ist (sonst nil-Fehler im ScrollFrame)
        if not GVE.f then return end
        local rosterOK = Guard("RosterUpdate", function()
            GVE:LoadRoster()
            GVE:RefreshBottomPanels()
            GVE:StepRank()          -- laufenden Rangwechsel fortsetzen
            GVE:RefreshMemberDetail()
            GVE:RefreshLastOnlineWindow()
        end)
        if rosterOK then
            GVE.rosterLoaded = true
            if GVE.csvPending then
                GVE.csvPending = nil
                GVE:UpdateCSVButton()
                Guard("CSVExport", function() GVE:CreateCSVExport() end)
            end
        end

    elseif event == "GUILD_EVENT_LOG_UPDATE" then
        if GVE.f and GVE.f:IsShown() then
            Guard("GuildLogUpdate", function() GVE:RefreshLog() end)
        end
    end
end)
