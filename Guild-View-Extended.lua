---------------------------------------------------------------------------
-- Guild-View-Extended
-- Erweitertes Gildenfenster fuer World of Warcraft 3.3.5a (Build 12340)
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

-- Auch optionale GuildView-Module schreiben in denselben kopierbaren Log.
function GVE:AddLog(msg)
    Log(msg)
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
local W, H     = 1080, 640
local PAD      = 12
local TITLE_H  = 48
local FILTER_H = 56
local COL_H    = 22
local ROW_H    = 32
local BOTTOM_H = 122
local ROSTER_REFRESH_SECONDS = 5

local ROSTER_W = W - PAD * 2
-- Platz fuer die komplette FauxScrollFrame-Scrollbar innerhalb des Fensters.
local LIST_W   = ROSTER_W - 24
local ROSTER_H = H - PAD - TITLE_H - 6 - FILTER_H - 4 - COL_H - 2 - BOTTOM_H - PAD - 10
local NUM_ROWS = math.floor(ROSTER_H / ROW_H)

---------------------------------------------------------------------------
-- Klassen-Farben. Nichts hard-coden: der Client befuellt
-- RAID_CLASS_COLORS. Die Filterliste entsteht dynamisch aus dem Roster.
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
    {key=nil,      label="",                  w=36, icon=true},
    {key="name",  label=NAME or "Name",      w=155},
    {key="level", label=(LEVEL or "Level").." & "..(CLASS or "Class"), w=170},
    {key="zone",  label=ZONE or "Zone",      w=180},
    {key="rank",  label=RANK or "Rank",      w=150},
    {key="note",  label=LABEL_NOTE or "Note",  w=0},
}
do
    local used = 0
    for _, c in ipairs(COLS) do used = used + c.w end
    COLS[#COLS].w = LIST_W - used - (#COLS - 1)
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

function GVE:CaseFoldName(value)
    return CaseFoldName(tostring(value or ""))
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

-- Flache, client-neutrale Gestaltung fuer die GuildView-eigenen Buttons.
-- Das 3.3.5a-UIPanelButtonTemplate kann je nach Client-Skin sehr dominant
-- (zum Beispiel rot) erscheinen. Blizzards eigene Dialoge bleiben davon
-- unberuehrt.
local UI_COLOR = {
    window     = {0.035, 0.047, 0.078, 0.98},
    panel      = {0.063, 0.086, 0.129, 0.96},
    panelAlt   = {0.082, 0.114, 0.165, 0.96},
    hover      = {0.105, 0.170, 0.235, 0.98},
    pressed    = {0.050, 0.145, 0.220, 0.98},
    selected   = {0.075, 0.205, 0.305, 0.98},
    line       = {0.153, 0.204, 0.278, 0.90},
    accent     = {0.200, 0.667, 1.000, 1.00},
    text       = {0.933, 0.957, 0.984, 1.00},
    muted      = {0.573, 0.635, 0.710, 1.00},
    disabled   = {0.250, 0.290, 0.340, 0.90},
}

local function SetRGBA(target, method, color)
    target[method](target, color[1], color[2], color[3], color[4])
end

local function RefreshFlatButton(button)
    local background, border
    if not button:IsEnabled() then
        background, border = UI_COLOR.window, UI_COLOR.disabled
    elseif button.flatPressed then
        background, border = UI_COLOR.pressed, UI_COLOR.accent
    elseif button.flatSelected then
        background, border = UI_COLOR.selected, UI_COLOR.accent
    elseif button.flatHovered then
        background, border = UI_COLOR.hover, UI_COLOR.accent
    elseif button.flatPrimary then
        background, border = UI_COLOR.selected, UI_COLOR.accent
    else
        background, border = UI_COLOR.panelAlt, UI_COLOR.line
    end
    SetRGBA(button, "SetBackdropColor", background)
    SetRGBA(button, "SetBackdropBorderColor", border)
end

local function MakeFlatButton(parent, width, height, text, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetBackdrop(PANEL_BD)
    button:SetNormalFontObject(GameFontNormalSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetDisabledFontObject(GameFontDisableSmall)
    button:SetText(text or "")
    button.flatPrimary = primary and true or false
    button:SetScript("OnEnter", function(self)
        self.flatHovered = true
        RefreshFlatButton(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.flatHovered = nil
        self.flatPressed = nil
        RefreshFlatButton(self)
    end)
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.flatPressed = true; RefreshFlatButton(self) end
    end)
    button:SetScript("OnMouseUp", function(self)
        self.flatPressed = nil
        RefreshFlatButton(self)
    end)
    button:SetScript("OnEnable", RefreshFlatButton)
    button:SetScript("OnDisable", RefreshFlatButton)
    RefreshFlatButton(button)
    return button
end

local function StyleFlatEditBox(editBox)
    editBox:SetBackdrop(PANEL_BD)
    SetRGBA(editBox, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(editBox, "SetBackdropBorderColor", UI_COLOR.line)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetTextColor(UI_COLOR.text[1], UI_COLOR.text[2], UI_COLOR.text[3])
    if editBox.SetTextInsets then editBox:SetTextInsets(7, 7, 0, 0) end
end

-- Ausschliesslich Texturen, die im originalen 3.3.5a-Client vorhanden sind.
local function AddButtonIcon(button, texturePath)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(15, 15)
    icon:SetPoint("LEFT", button, "LEFT", 7, 0)
    icon:SetTexture(texturePath or "Interface\\Icons\\INV_Misc_QuestionMark")
    local label = button:GetFontString()
    if label then
        label:ClearAllPoints()
        label:SetPoint("CENTER", button, "CENTER", 8, 0)
    end
    button.icon = icon
    return icon
end

-- Die urspruenglichen, einzeln vorhandenen Klassenmotive des 3.3.5a-Clients.
-- Bewusst kein Atlas: angepasste Clients koennen dessen Inhalt oder globale
-- Koordinatentabellen ersetzen und dadurch alle Klassen falsch darstellen.
local CLASS_ICON_TEXTURES_335 = {
    WARRIOR     = "Interface\\Icons\\INV_Sword_27",
    PALADIN     = "Interface\\Icons\\INV_Hammer_01",
    HUNTER      = "Interface\\Icons\\INV_Weapon_Bow_07",
    ROGUE       = "Interface\\Icons\\INV_ThrowingKnife_04",
    PRIEST      = "Interface\\Icons\\INV_Staff_30",
    DEATHKNIGHT = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
    SHAMAN      = "Interface\\Icons\\INV_Jewelry_Talisman_04",
    MAGE        = "Interface\\Icons\\INV_Staff_13",
    WARLOCK     = "Interface\\Icons\\Spell_Nature_Drowsy",
    DRUID       = "Interface\\Icons\\INV_Misc_MonsterClaw_04",
}

local function ResolveClassToken(classKey)
    local raw = tostring(classKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local token = raw:upper():gsub("[%s_%-]", "")
    if CLASS_ICON_TEXTURES_335[token] then return token end
    for english, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
        if tostring(localized or ""):lower() == raw:lower() then
            return english:upper():gsub("[%s_%-]", "")
        end
    end
    for english, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
        if tostring(localized or ""):lower() == raw:lower() then
            return english:upper():gsub("[%s_%-]", "")
        end
    end
    return token
end

local function SetClassIcon(texture, classKey, online)
    local token = ResolveClassToken(classKey)
    texture:SetTexture(CLASS_ICON_TEXTURES_335[token]
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1)
    texture:SetAlpha(online and 1 or 0.42)
end

local function StyleGuildControlPopup(popup)
    if popup.gveFlatStyled then return end
    popup.gveFlatStyled = true
    -- Das globale Blizzard-Fenster selbst bleibt unangetastet. Eine flache
    -- Huelle dahinter gibt ihm GVE-Kontrast, ohne seine Originaltexturen oder
    -- eine spaetere Verwendung im Standardfenster dauerhaft zu veraendern.
    local shell = CreateFrame("Frame", nil, popup)
    shell:SetPoint("TOPLEFT", popup, "TOPLEFT", -5, 5)
    shell:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 5, -5)
    shell:SetFrameLevel(math.max(0, popup:GetFrameLevel() - 1))
    shell:SetBackdrop(PANEL_BD)
    SetRGBA(shell, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(shell, "SetBackdropBorderColor", UI_COLOR.line)
    popup.gveFlatShell = shell
end

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
            -- Bei fehlender Lokalisierung auf den classFile-Token
            -- zurueckfallen (und umgekehrt).
            local disp = (class and class ~= "" and class) or cf or ""
            local displayToken = ResolveClassToken(disp)
            local fileToken = ResolveClassToken(cf)
            -- Der kanonische classFile-Token ist in 3.3.5a die Primaerquelle;
            -- der lokalisierte Anzeigename bleibt ein unabhaengiger Fallback.
            local key
            if CLASS_ICON_TEXTURES_335[fileToken] then
                key = fileToken
            elseif CLASS_ICON_TEXTURES_335[displayToken] then
                key = displayToken
            else
                key = (cf and cf ~= "" and cf) or disp
            end

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
    if type(self.rosterListener) == "function" then
        Guard("RosterListener", self.rosterListener, self)
    end
end

-- Schmale, nur-lesende Schnittstelle fuer optionale GuildView-Module.
-- Die Tabelle darf von Verbrauchern nicht veraendert werden.
function GVE:GetMembers()
    return members
end

function GVE:SetRosterListener(listener)
    self.rosterListener = listener
end

function GVE:ApplyFilter()
    wipe(filtered)
    local s    = CaseFoldName(searchStr)
    local hcf  = next(filterClasses) ~= nil
    local hrf  = next(filterRanks)   ~= nil
    for _, m in ipairs(members) do
        if  (not hcf          or filterClasses[m.classKey])
        and (not hrf          or filterRanks[m.rank])
        and (not filterOnline or m.online)
        and (s == "" or CaseFoldName(table.concat({
            m.name or "", m.class or "", m.zone or "", m.rank or "", m.note or ""
        }, " ")):find(s, 1, true))
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
        if va == vb then
            local an, bn = CaseFoldName(a.name or ""), CaseFoldName(b.name or "")
            if an == bn then return (a.name or "") < (b.name or "") end
            return an < bn
        end
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
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop(PANEL_BD)
    SetRGBA(f, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(f, "SetBackdropBorderColor", UI_COLOR.line)
    f:Hide()
    self.f = f

    -- ESC schliesst das Fenster. Hat die Suchleiste den Fokus, faengt ihr
    -- OnEscapePressed das ESC ab -> nur Fokus verlassen, Fenster bleibt.
    tinsert(UISpecialFrames, "GVEMainFrame")

    -- ESC ruft f:Hide() direkt auf (nicht GVE:Close) -> Aufraeumen hier
    f:SetScript("OnHide", function()
        GVE:CloseFilterPanel()
        if GVE.lastOnlineWin then GVE.lastOnlineWin:Hide() end
        if GVE.logPanel then GVE.logPanel:Hide() end
        if GVE.detail then GVE.detail:Hide() end
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
    mc:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
    self.memberCount = mc

    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

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

    local sbox = CreateFrame("EditBox", "GVESearchBox", f)
    sbox:SetSize(225, 26)
    sbox:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, yOff)
    StyleFlatEditBox(sbox)
    sbox:SetAutoFocus(false)
    sbox:SetMaxLetters(40)
    sbox:SetScript("OnTextChanged", function(self)
        searchStr = self:GetText()
        GVE:ApplyFilter()
    end)
    sbox:SetScript("OnEscapePressed", sbox.ClearFocus)
    self.searchBox = sbox

    local placeholder = sbox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", sbox, "LEFT", 8, 0)
    placeholder:SetText((SEARCH or "Search").." …")
    sbox:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    sbox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then placeholder:Show() end end)
    local oldChanged = sbox:GetScript("OnTextChanged")
    sbox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" and not self:HasFocus() then placeholder:Show() else placeholder:Hide() end
        oldChanged(self)
    end)

    local fbtn = MakeFlatButton(f, 88, 26, FILTER or "Filter")
    fbtn:SetPoint("LEFT", sbox, "RIGHT", 8, 0)
    AddButtonIcon(fbtn, "Interface\\Icons\\INV_Misc_Spyglass_03")
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
    local gcb = MakeFlatButton(f, 126, 26, GUILDCONTROL or "Guild Controls")
    gcb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, yOff)
    AddButtonIcon(gcb, "Interface\\Icons\\INV_Gizmo_02")
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
        GVE:CloseFilterPanel()
        if GVE.lastOnlineWin then GVE.lastOnlineWin:Hide() end
        if GVE.logPanel then GVE.logPanel:Hide() end
        if GVE.detail then GVE.detail:Hide() end
        GuildRoster()   -- Rangdaten anfordern
        GVE.guildControlOwned = true
        -- Blizzard verankert das Popup am FriendsFrame; an unser Fenster haengen
        p:ClearAllPoints()
        p:SetPoint("CENTER", f, "CENTER", 0, 0)
        p:SetFrameStrata("DIALOG")
        StyleGuildControlPopup(p)
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
    local amb = MakeFlatButton(f, 112, 26, ADD_GUILDMEMBER or "Add Member", true)
    amb:SetPoint("RIGHT", gcb, "LEFT", -6, 0)
    AddButtonIcon(amb, "Interface\\Icons\\INV_Misc_GroupLooking")
    amb:SetScript("OnClick", function()
        StaticPopup_Show("ADD_GUILDMEMBER")
    end)
    self.addMemberBtn = amb

    -- "Zuletzt Online": nur fuer Gildenmeister/Offiziere (siehe
    -- UpdateGuildControlButton). Oeffnet Panel mit Sortierung + Zeitfilter.
    local lob = MakeFlatButton(f, 112, 26, LASTONLINE or "Zuletzt Online")
    lob:SetPoint("RIGHT", amb, "LEFT", -6, 0)
    AddButtonIcon(lob, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    lob:SetScript("OnClick", function() GVE:ToggleLastOnlineWindow() end)
    lob:Hide()
    self.lastOnlineBtn = lob

    local logb = MakeFlatButton(f, 96, 26, GUILD_EVENT_LOG_TITLE or "Guild Log")
    logb:SetPoint("RIGHT", lob, "LEFT", -6, 0)
    AddButtonIcon(logb, "Interface\\Icons\\INV_Scroll_03")
    logb:SetScript("OnClick", function() GVE:ToggleGuildLogWindow() end)
    self.guildLogBtn = logb

    local csvButton = MakeFlatButton(f, 120, 26, CSV_TEXT.button, true)
    csvButton:SetPoint("RIGHT", logb, "LEFT", -6, 0)
    AddButtonIcon(csvButton, "Interface\\Icons\\INV_Misc_Note_01")
    csvButton:SetScript("OnClick", function()
        Guard("CSVExportRequest", function() GVE:RequestCSVExport() end)
    end)
    self.csvButton = csvButton

    -- Trefferzahl unterhalb der Werkzeugleiste; der Titel bleibt im gemeinsamen Header.
    self.memberCount:ClearAllPoints()
    self.memberCount:SetPoint("TOPLEFT", sbox, "BOTTOMLEFT", 1, -7)
    self.filterLabel:ClearAllPoints()
    self.filterLabel:SetPoint("LEFT", self.memberCount, "RIGHT", 14, 0)
end

---------------------------------------------------------------------------
-- "Zuletzt Online"-Fenster (nur GM/Offiziere): eigene Liste aller
-- Mitglieder mit letzter Online-Zeit, auf-/absteigend sortierbar und
-- nach eigener Zeitspanne filterbar (X Tage / Wochen / Monate offline).
-- Im Hauptfenster wird "zuletzt online" bewusst NICHT angezeigt.
---------------------------------------------------------------------------
local LO_ROWS  = 11
local LO_ROW_H = 36
local loSortAsc     = false   -- Standard: laengste Offline-Zeit zuerst
local loFilterHours = nil
local loSearchStr   = ""

local LO_TEXT = GetLocale() == "deDE" and {
    searchLabel = "Spieler suchen:",
    clearSearch = "Löschen",
    offlineFor  = "Offline seit mindestens:",
    days        = "Tage",
    weeks       = "Wochen",
    months      = "Monate",
    name        = "Name",
    rank        = "Rang",
    empty       = "Keine Gildenmitglieder verfügbar.",
    noResults   = "Keine Treffer für aktuelle Suche und Filter.",
    count       = "%d von %d Mitgliedern",
} or {
    searchLabel = "Search player:",
    clearSearch = "Clear",
    offlineFor  = "Offline for at least:",
    days        = "Days",
    weeks       = "Weeks",
    months      = "Months",
    name        = "Name",
    rank        = "Rank",
    empty       = "No guild members available.",
    noResults   = "No matches for the current search and filters.",
    count       = "%d of %d members",
}

function GVE:BuildLastOnlineList(sourceMembers, searchText, filterHours, ascending)
    local list = {}
    local search = CaseFoldName(searchText or "")
    for _, m in ipairs(sourceMembers or {}) do
        local matchesSearch = search == ""
            or CaseFoldName(m.name or ""):find(search, 1, true) ~= nil
            or CaseFoldName(m.rank or ""):find(search, 1, true) ~= nil
        local matchesTime = not filterHours
            or (m.lastOnline or 0) >= filterHours
        if matchesSearch and matchesTime then list[#list+1] = m end
    end
    table.sort(list, function(a, b)
        local va, vb = a.lastOnline or 0, b.lastOnline or 0
        if va == vb then
            local an, bn = CaseFoldName(a.name or ""), CaseFoldName(b.name or "")
            if an == bn then return (a.name or "") < (b.name or "") end
            return an < bn
        end
        if ascending then return va < vb else return va > vb end
    end)
    return list
end

function GVE:ResetLastOnlineScroll()
    local w = self.lastOnlineWin
    if not (w and w.scroll) then return end
    w.scroll:SetVerticalScroll(0)
    FauxScrollFrame_SetOffset(w.scroll, 0)
end

function GVE:BuildLastOnlineWindow()
    local w = CreateFrame("Frame", "GVELastOnlineWindow", self.f)
    w:SetPoint("TOPLEFT", self.f, "TOPLEFT", 10, -58)
    w:SetPoint("BOTTOMRIGHT", self.f, "BOTTOMRIGHT", -10, 10)
    w:EnableMouse(true)
    w:SetFrameLevel(self.f:GetFrameLevel() + 25)
    w:SetBackdrop(PANEL_BD)
    SetRGBA(w, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(w, "SetBackdropBorderColor", UI_COLOR.line)
    w:Hide()
    self.lastOnlineWin = w

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", w, "TOP", 0, -12)
    title:SetText("|cff33aaff"..(LASTONLINE or "Zuletzt Online").."|r")

    local titleIcon = w:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(18, 18)
    titleIcon:SetPoint("RIGHT", title, "LEFT", -7, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

    local xb = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)

    -- Eigene, deutlich abgesetzte Namenssuche, unabhaengig von der Suche
    -- im Hauptfenster.
    local searchPanel = CreateFrame("Frame", nil, w)
    searchPanel:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -34)
    searchPanel:SetWidth(640)
    searchPanel:SetHeight(36)
    searchPanel:SetBackdrop(PANEL_BD)
    searchPanel:SetBackdropColor(0.04, 0.08, 0.14, 0.92)

    local sl = searchPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sl:SetPoint("LEFT", searchPanel, "LEFT", 12, 0)
    sl:SetText(LO_TEXT.searchLabel)
    sl:SetTextColor(1, 0.82, 0)

    local search = CreateFrame("EditBox", "GVELastOnlineSearch", searchPanel)
    search:SetWidth(360); search:SetHeight(22)
    search:SetPoint("LEFT", sl, "RIGHT", 10, 0)
    StyleFlatEditBox(search)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(self)
        loSearchStr = self:GetText() or ""
        GVE:ResetLastOnlineScroll()
        GVE:RefreshLastOnlineWindow()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        w:Hide()
    end)
    w.search = search

    local clearSearch = MakeFlatButton(searchPanel, 82, 20, LO_TEXT.clearSearch)
    clearSearch:SetWidth(82); clearSearch:SetHeight(20)
    clearSearch:SetPoint("LEFT", search, "RIGHT", 8, 0)
    clearSearch:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)

    -- Zeitfilter in einer eigenen Zeile.
    local fl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fl:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -84)
    fl:SetText(LO_TEXT.offlineFor)
    fl:SetTextColor(0.75, 0.75, 0.75)

    local amount = CreateFrame("EditBox", "GVELastOnlineAmount", w)
    amount:SetWidth(36); amount:SetHeight(20)
    amount:SetPoint("LEFT", fl, "RIGHT", 10, 0)
    StyleFlatEditBox(amount)
    amount:SetAutoFocus(false)
    amount:SetNumeric(true)
    amount:SetMaxLetters(3)
    w.amount = amount
    w.unitHours = 24

    local function ApplyTimeFilter()
        local n = tonumber(amount:GetText())
        loFilterHours = (n and n > 0) and (n * w.unitHours) or nil
        GVE:ResetLastOnlineScroll()
        GVE:RefreshLastOnlineWindow()
    end
    amount:SetScript("OnEnterPressed", function(self)
        ApplyTimeFilter()
        self:ClearFocus()
    end)
    amount:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local UNITS = {
        {label=LO_TEXT.days,   hours=24},
        {label=LO_TEXT.weeks,  hours=168},
        {label=LO_TEXT.months, hours=720},
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
            info.arg1    = u.label
            info.func    = function(btn, label)
                w.unitHours = btn.value
                UIDropDownMenu_SetSelectedValue(unitDD, btn.value)
                UIDropDownMenu_SetText(unitDD, label)
                ApplyTimeFilter()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(unitDD, 24)
    UIDropDownMenu_SetText(unitDD, LO_TEXT.days)

    local clr = MakeFlatButton(w, 60, 20, RESET or "Reset")
    clr:SetWidth(60); clr:SetHeight(20)
    clr:SetPoint("LEFT", unitDD, "RIGHT", -8, 2)
    clr:SetScript("OnClick", function()
        amount:SetText("")
        loFilterHours = nil
        GVE:ResetLastOnlineScroll()
        GVE:RefreshLastOnlineWindow()
    end)

    -- Spaltenkoepfe: Klick auf "Zuletzt Online" wechselt die Richtung
    local nameHdr = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHdr:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -126)
    nameHdr:SetText(LO_TEXT.name)
    nameHdr:SetTextColor(1, 0.82, 0)

    local rankHdr = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankHdr:SetPoint("TOPLEFT", w, "TOPLEFT", 330, -126)
    rankHdr:SetText(LO_TEXT.rank)
    rankHdr:SetTextColor(1, 0.82, 0)

    local timeHdr = CreateFrame("Button", nil, w)
    timeHdr:SetWidth(170); timeHdr:SetHeight(16)
    timeHdr:SetPoint("TOPRIGHT", w, "TOPRIGHT", -42, -126)
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
    sf:SetWidth(944); sf:SetHeight(LO_ROWS * LO_ROW_H)
    sf:SetPoint("TOPLEFT", w, "TOPLEFT", 18, -144)
    sf:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, LO_ROW_H, function() GVE:RefreshLastOnlineWindow() end)
    end)
    w.scroll = sf

    w.rows = {}
    for i = 1, LO_ROWS do
        local row = CreateFrame("Frame", nil, w)
        row:SetWidth(944); row:SetHeight(LO_ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 2, -(i-1) * LO_ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetTexture(0.08, 0.11, 0.17, 0.38)
        else
            bg:SetTexture(0.03, 0.05, 0.09, 0.26)
        end
        row.bg = bg

        local divider = row:CreateTexture(nil, "BORDER")
        divider:SetHeight(1)
        divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
        divider:SetTexture(0.22, 0.38, 0.55, 0.42)
        row.divider = divider

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name:SetWidth(300); row.name:SetHeight(LO_ROW_H)
        row.name:SetJustifyH("LEFT"); row.name:SetJustifyV("MIDDLE")
        row.name:SetWordWrap(false)
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rank:SetPoint("LEFT", row, "LEFT", 310, 0)
        row.rank:SetWidth(390); row.rank:SetHeight(LO_ROW_H)
        row.rank:SetJustifyH("LEFT"); row.rank:SetJustifyV("MIDDLE")
        row.rank:SetWordWrap(false)
        row.rank:SetTextColor(0.6, 0.6, 0.6)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.time:SetWidth(210); row.time:SetHeight(LO_ROW_H)
        row.time:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.time:SetJustifyH("RIGHT"); row.time:SetJustifyV("MIDDLE")
        row.time:SetWordWrap(false)
        row:Hide()
        w.rows[i] = row
    end

    -- Zaehler unten
    w.countText = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w.countText:SetPoint("BOTTOM", w, "BOTTOM", 0, 12)
    w.countText:SetTextColor(0.6, 0.6, 0.6)

    w.emptyText = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.emptyText:SetPoint("CENTER", sf, "CENTER", 0, 0)
    w.emptyText:SetTextColor(0.65, 0.65, 0.65)
    w.emptyText:Hide()
end

function GVE:RefreshLastOnlineWindow()
    local w = self.lastOnlineWin
    if not (w and w:IsShown()) then return end

    local list = self:BuildLastOnlineList(members, loSearchStr, loFilterHours, loSortAsc)

    w.timeHdr.lbl:SetText((LASTONLINE or "Zuletzt Online")..(loSortAsc and " v" or " ^"))
    w.countText:SetText(format(LO_TEXT.count, #list, #members))
    if #list == 0 then
        w.emptyText:SetText(#members == 0 and LO_TEXT.empty or LO_TEXT.noResults)
        w.emptyText:Show()
    else
        w.emptyText:Hide()
    end

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
        self:CloseFilterPanel()
        if self.logPanel then self.logPanel:Hide() end
        if self.detail then self.detail:Hide() end
        if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then GuildControlPopupFrame:Hide() end
        SetGuildRosterShowOffline(true)
        GuildRoster()
        w:Show()
        self:RefreshLastOnlineWindow()
    end
end

function GVE:UpdateGuildControlButton()
    -- Der originale 3.3.5a-Guild-Control-Dialog ist nur fuer den
    -- Gildenmeister bestimmt.
    if self.guildControlBtn then
        if IsGuildLeader() then
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
        self.filterBtn.flatPrimary = true
    else
        self.filterBtn:SetText("Filter")
        self.filterLabel:SetText("")
        self.filterBtn.flatPrimary = nil
    end
    RefreshFlatButton(self.filterBtn)
end

---------------------------------------------------------------------------
-- Filter-Panel
-- Rang-Checkboxen werden einmalig pre-allokiert (WoW max = 10 Raenge).
-- Bei GUILD_ROSTER_UPDATE werden nur Text + Sichtbarkeit aktualisiert,
-- KEINE neuen Frames erstellt -> vermeidet "already exists"-Lua-Fehler.
---------------------------------------------------------------------------
local MAX_RANKS   = 10
local MAX_CLASSES = 20   -- dynamische Liste; Puffer fuer 3.3.5a-Clients

function GVE:BuildFilterPanel()
    local f   = self.f
    local btn = self.filterBtn

    local fp = CreateFrame("Frame", "GVEFilterPanel", f)
    fp:SetWidth(520)
    fp:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
    fp:SetFrameStrata("DIALOG")
    fp:EnableMouse(true)   -- Klicks schlucken, nicht zur Spielerliste durchreichen
    fp:SetBackdrop(PANEL_BD)
    SetRGBA(fp, "SetBackdropColor", UI_COLOR.panel)
    SetRGBA(fp, "SetBackdropBorderColor", UI_COLOR.line)
    fp:Hide()
    self.filterPanel = fp

    local ROW_STRIDE = 22
    local NCOLS      = 3
    local COL_X      = 168
    local yy = -10

    -- ---- Klasse (dynamisch aus dem Roster, wie die Raenge) ----
    local cTitle = fp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cTitle:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    cTitle:SetText("|cff33aaff"..(CLASS_LABEL or CLASS or "Class").."|r")
    yy = yy - 18

    local callBtn = MakeFlatButton(fp, 62, 20, ALL or "All")
    callBtn:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    callBtn:SetScript("OnClick", function()
        wipe(filterClasses)
        self:RefreshClassChecks()
        self:ApplyFilter()
    end)
    yy = yy - 24

    self.classCBs    = {}
    self.classCBRows = math.ceil(MAX_CLASSES / NCOLS)
    for i = 1, MAX_CLASSES do
        local col = (i - 1) % NCOLS
        local row = math.floor((i - 1) / NCOLS)
        local cb  = MakeCheckbox(fp)
        cb:SetPoint("TOPLEFT", fp, "TOPLEFT", 10 + col * COL_X, yy - row * ROW_STRIDE)
        cb.classIcon = cb:CreateTexture(nil, "ARTWORK")
        cb.classIcon:SetSize(16, 16)
        cb.classIcon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.lbl:ClearAllPoints()
        cb.lbl:SetPoint("LEFT", cb.classIcon, "RIGHT", 3, 0)
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
    rTitle:SetText("|cff33aaff"..(RANK_LABEL or "Rank").."|r")
    yy = yy - 18

    local rallBtn = MakeFlatButton(fp, 62, 20, ALL or "All")
    rallBtn:SetPoint("TOPLEFT", fp, "TOPLEFT", 10, yy)
    rallBtn:SetScript("OnClick", function()
        wipe(filterRanks)
        self:RefreshRankChecks()
        self:ApplyFilter()
    end)
    yy = yy - 24

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
    local ordered, seen = {}, {}
    for _, member in ipairs(members) do
        local r = member.rank
        if r and r ~= "" and not seen[r] then
            seen[r] = true
            ordered[#ordered+1] = {name=r, index=member.rankIndex or 99}
        end
    end
    table.sort(ordered, function(a, b)
        if a.index == b.index then return CaseFoldName(a.name) < CaseFoldName(b.name) end
        return a.index < b.index
    end)
    local i = 0
    for _, entry in ipairs(ordered) do
        i = i + 1
        if i > MAX_RANKS then break end
        local r = entry.name
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
            SetClassIcon(cb.classIcon, e.key, true)
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
    if fp:IsShown() then
        fp:Hide()
        self.filterBtn.flatSelected = nil
    else
        if self.lastOnlineWin then self.lastOnlineWin:Hide() end
        if self.logPanel then self.logPanel:Hide() end
        if self.detail then self.detail:Hide() end
        if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then GuildControlPopupFrame:Hide() end
        fp:Show()
        self.filterBtn.flatSelected = true
    end
    RefreshFlatButton(self.filterBtn)
end

function GVE:CloseFilterPanel()
    if self.filterPanel then self.filterPanel:Hide() end
    if self.filterBtn then
        self.filterBtn.flatSelected = nil
        RefreshFlatButton(self.filterBtn)
    end
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
        bg:SetTexture(UI_COLOR.panelAlt[1], UI_COLOR.panelAlt[2], UI_COLOR.panelAlt[3], 0.96)

        local brd = btn:CreateTexture(nil, "BORDER")
        brd:SetHeight(1)
        brd:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT")
        brd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
        brd:SetTexture(UI_COLOR.line[1], UI_COLOR.line[2], UI_COLOR.line[3], 0.95)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", btn, "LEFT", 4, 0)
        lbl:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
        btn.lbl = lbl; btn.colKey = col.key; btn.colLabel = col.label

        if col.key then
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            btn:SetScript("OnClick", function(self)
                if sortKey == self.colKey then sortAsc = not sortAsc
                else sortKey = self.colKey; sortAsc = true end
                GVE:ApplyFilter()
            end)
        else
            btn:EnableMouse(false)
        end
        self.colHeaders[i] = btn
        xOff = xOff + col.w + 1
    end
    self:RefreshColHeaders()
end

function GVE:RefreshColHeaders()
    for _, btn in ipairs(self.colHeaders or {}) do
        local arrow = btn.colKey and (sortKey == btn.colKey) and (sortAsc and " v" or " ^") or ""
        btn.lbl:SetText(btn.colLabel .. arrow)
        if sortKey == btn.colKey then
            btn.lbl:SetTextColor(UI_COLOR.accent[1], UI_COLOR.accent[2], UI_COLOR.accent[3])
        else
            btn.lbl:SetTextColor(UI_COLOR.muted[1], UI_COLOR.muted[2], UI_COLOR.muted[3])
        end
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
    sf:SetSize(LIST_W, ROSTER_H)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, yStart)
    self.sf = sf
    sf:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, function() GVE:RefreshRoster() end)
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local bar = _G[(self:GetName() or "").."ScrollBar"]
        if bar then bar:SetValue(bar:GetValue() - delta * ROW_H) end
    end)

    self.rows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(LIST_W, ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i-1)*ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetTexture(0.063, 0.086, 0.129, 0.80)
        else
            bg:SetTexture(0.035, 0.047, 0.078, 0.72)
        end

        local line = row:CreateTexture(nil, "BORDER")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        line:SetTexture(UI_COLOR.line[1], UI_COLOR.line[2], UI_COLOR.line[3], 0.55)

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(UI_COLOR.accent[1], UI_COLOR.accent[2], UI_COLOR.accent[3], 0.12)
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
            if col.icon then
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(24, 24)
                icon:SetPoint("LEFT", row, "LEFT", fx + 6, 0)
                row.classIcon = icon
            else
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetWidth(col.w - 8)
                fs:SetHeight(ROW_H)
                fs:SetPoint("LEFT", row, "LEFT", fx + 4, 0)
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("MIDDLE")
                fs:SetWordWrap(false)
                row.fields[#row.fields+1] = fs
            end
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
            SetClassIcon(row.classIcon, m.classKey, m.online)
            local vals = {m.name, tostring(m.level or 0).."  "..(m.class or ""), m.zone, m.rank, m.note}
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
                elseif j == 2 then
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
local function MakeNoteBox(parent, name, onSave, width, height)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetWidth(width or 180); bg:SetHeight(height or 48)
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
    d:SetSize(600, 370)
    d:SetPoint("CENTER", self.f, "CENTER", 0, 10)
    d:SetFrameLevel(self.f:GetFrameLevel() + 26)
    d:EnableMouse(true)
    d:SetBackdrop(PANEL_BD)
    SetRGBA(d, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(d, "SetBackdropBorderColor", UI_COLOR.line)
    d:Hide()
    self.detail = d

    local xb = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    xb:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)

    d.classIcon = d:CreateTexture(nil, "ARTWORK")
    d.classIcon:SetSize(40, 40)
    d.classIcon:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -16)

    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.name:SetPoint("TOPLEFT", d.classIcon, "TOPRIGHT", 11, -2)
    d.name:SetWidth(500)
    d.name:SetWordWrap(false)

    d.info = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
    d.info:SetTextColor(0.8, 0.8, 0.8)

    -- Rang: EIN Dropdown statt Befoerdern/Degradieren-Buttons.
    -- Zeigt den aktuellen Rang; eine Auswahl setzt den Rang schrittweise.
    d.rank = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local divider = d:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -68)
    divider:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -68)
    divider:SetTexture(UI_COLOR.line[1], UI_COLOR.line[2], UI_COLOR.line[3], 0.85)

    d.rank:SetPoint("TOPLEFT", d, "TOPLEFT", 18, -82)
    d.rank:SetTextColor(0.6, 0.6, 0.6)
    d.rank:SetText((RANK or "Rank")..":")

    -- Gildenmeister uebertragen: nur fuer den Gildenmeister sichtbar,
    -- sitzt UEBER dem Rang-Dropdown. Mit Sicherheitsabfrage.
    d.gmBtn = MakeFlatButton(d, 260, 26, GUILD_PROMOTE or "Promote to Guildmaster")
    d.gmBtn:SetPoint("TOPRIGHT", d, "TOPRIGHT", -18, -99)
    d.gmBtn:SetScript("OnClick", function()
        if d.member then
            local dlg = StaticPopup_Show("GVE_SET_GUILDMASTER", d.member.name)
            if dlg then dlg.data = d.member.name end
        end
    end)
    d.gmBtn:Hide()

    d.rankDD = CreateFrame("Frame", "GVEDetailRankDD", d, "UIDropDownMenuTemplate")
    d.rankDD:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -97)
    UIDropDownMenu_SetWidth(d.rankDD, 250)
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
    nl:SetPoint("TOPLEFT", d, "TOPLEFT", 18, -148)
    nl:SetText(LABEL_NOTE or "Note")
    nl:SetTextColor(0.6, 0.6, 0.6)
    d.noteBox = MakeNoteBox(d, "GVEDetailNote", function(text)
        if d.member then
            GuildRosterSetPublicNote(d.member.index, text)
            Log("Notiz gesetzt fuer "..d.member.name)
        end
    end, 270, 112)
    d.noteBox.bg:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 0, -3)

    -- Offiziersnotiz (3-zeilige Box)
    local ol = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ol:SetPoint("TOPLEFT", d, "TOPLEFT", 312, -148)
    ol:SetText(GUILD_OFFICERNOTES_LABEL or "Officer Note")
    ol:SetTextColor(0.6, 0.6, 0.6)
    d.officerLabel = ol
    d.officerBox = MakeNoteBox(d, "GVEDetailOfficerNote", function(text)
        if d.member then
            GuildRosterSetOfficerNote(d.member.index, text)
            Log("Offiziersnotiz gesetzt fuer "..d.member.name)
        end
    end, 270, 112)
    d.officerBox.bg:SetPoint("TOPLEFT", ol, "BOTTOMLEFT", 0, -3)

    d.invite = MakeFlatButton(d, 164, 28, ACTION_TEXT.inviteGroup, true)
    d.invite:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 52)
    AddButtonIcon(d.invite, "Interface\\Icons\\INV_Misc_GroupLooking")
    d.invite:SetScript("OnClick", function()
        if d.member and not IsPlayerCharacterName(d.member.name) then
            InviteUnit(d.member.name)
            Log("Gruppeneinladung gesendet an "..d.member.name)
        end
    end)

    d.remove = MakeFlatButton(d, 164, 28, "|cffff6666"..(REMOVE or "Remove").."|r")
    d.remove:SetPoint("TOPRIGHT", d.invite, "BOTTOMRIGHT", 0, -6)
    d.remove:SetScript("OnClick", function()
        if d.member then
            if IsPlayerCharacterName(d.member.name) then
                StaticPopup_Show("GVE_LEAVE_GUILD")
            else
                local dlg = StaticPopup_Show("GVE_REMOVE_MEMBER", d.member.name)
                if dlg then dlg.data = d.member.name end
            end
        end
    end)
end

function GVE:ShowMemberDetail(m)
    if not self.detail then self:BuildMemberDetail() end
    local d = self.detail
    self:CloseFilterPanel()
    if self.logPanel then self.logPanel:Hide() end
    if self.lastOnlineWin then self.lastOnlineWin:Hide() end
    d.member = m

    local r, g, b = ClassColor(m.classKey)
    d.name:SetText(m.name)
    d.name:SetTextColor(r, g, b)
    d.info:SetText((LEVEL or "Level").." "..m.level.."  "..m.class)
    SetClassIcon(d.classIcon, m.classKey, m.online)

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
    if IsPlayerCharacterName(m.name) then
        d.remove:SetText("|cffff3333"..ACTION_TEXT.leaveGuild.."|r")
        d.remove:Enable()
    else
        d.remove:SetText("|cffff3333"..(REMOVE or "Remove").."|r")
        if CanGuildRemove() then d.remove:Enable() else d.remove:Disable() end
    end
    if IsPlayerCharacterName(m.name) then d.invite:Disable() else d.invite:Enable() end

    d.noteBox:SetText(m.note or "")
    if CanEditPublicNote() then d.noteBox:EnableMouse(true); d.noteBox:SetTextColor(1,1,1)
    else d.noteBox:EnableMouse(false); d.noteBox:SetTextColor(0.5,0.5,0.5) end

    if CanViewOfficerNote() then
        d.officerLabel:Show(); d.officerBox:Show(); d.officerBox.bg:Show()
        d.officerBox:SetText(m.officerNote or "")
        if CanEditOfficerNote() then d.officerBox:EnableMouse(true); d.officerBox:SetTextColor(1,1,1)
        else d.officerBox:EnableMouse(false); d.officerBox:SetTextColor(0.5,0.5,0.5) end
    else
        d.officerLabel:Hide(); d.officerBox:Hide(); d.officerBox.bg:Hide()
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
    SetRGBA(mf, "SetBackdropColor", UI_COLOR.panel)
    SetRGBA(mf, "SetBackdropBorderColor", UI_COLOR.line)
    local mt = mf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mt:SetPoint("TOPLEFT", mf, "TOPLEFT", 7, -5)
    mt:SetText("|cff33aaff"..(GUILD_MOTD_LABEL or "Message of the Day").."|r")

    -- Bearbeiten (nur mit MOTD-Recht sichtbar)
    local meb = MakeFlatButton(mf, 70, 20, EDIT or "Edit")
    meb:SetPoint("TOPRIGHT", mf, "TOPRIGHT", -6, -4)
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
    self.motdText:SetWordWrap(true)
    self.motdText:SetTextColor(UI_COLOR.text[1], UI_COLOR.text[2], UI_COLOR.text[3])

    local gf = CreateFrame("Frame", nil, f)
    gf:SetSize(halfW, panH)
    gf:SetPoint("BOTTOMLEFT", mf, "BOTTOMRIGHT", 8, 0)
    gf:SetBackdrop(PANEL_BD)
    SetRGBA(gf, "SetBackdropColor", UI_COLOR.panel)
    SetRGBA(gf, "SetBackdropBorderColor", UI_COLOR.line)
    local gt = gf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gt:SetPoint("TOPLEFT", gf, "TOPLEFT", 7, -5)
    gt:SetText("|cff33aaff"..(GUILD_INFORMATION or "Guild Information").."|r")

    -- Bearbeiten (nur mit Gildeninfo-Recht sichtbar)
    local geb = MakeFlatButton(gf, 70, 20, EDIT or "Edit")
    geb:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -6, -4)
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
    it:SetWordWrap(true)
    it:SetTextColor(UI_COLOR.text[1], UI_COLOR.text[2], UI_COLOR.text[3])
    self.infoText   = it
    self.infoScroll = isf
    self.infoChild  = child

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
        local info = GetGuildInfoText() or ""
        if info ~= self.lastGuildInfoText then
            self.lastGuildInfoText = info
            self.infoText:SetText(info)
            if self.infoChild and self.infoScroll then
                self.infoChild:SetHeight(math.max(self.infoScroll:GetHeight(), self.infoText:GetStringHeight() + 4))
            end
            if self.infoScroll then self.infoScroll:SetVerticalScroll(0) end
        end
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
local LOG_ROW_H = 28
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
    local f = self.f
    local lf = CreateFrame("Frame", nil, f)
    lf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -58)
    lf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    lf:SetFrameLevel(f:GetFrameLevel() + 25)
    lf:EnableMouse(true)
    lf:SetBackdrop(PANEL_BD)
    SetRGBA(lf, "SetBackdropColor", UI_COLOR.window)
    SetRGBA(lf, "SetBackdropBorderColor", UI_COLOR.line)
    lf:Hide()
    self.logPanel = lf

    local lt = lf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lt:SetPoint("TOPLEFT", lf, "TOPLEFT", 18, -16)
    lt:SetText("|cff33aaff"..(GUILD_EVENT_LOG_TITLE or "Guild Log").."|r")

    local close = CreateFrame("Button", nil, lf, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", lf, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() lf:Hide() end)

    local lsf = CreateFrame("ScrollFrame", "GVELogScroll", lf, "FauxScrollFrameTemplate")
    lsf:SetPoint("TOPLEFT",     lf, "TOPLEFT",     14, -46)
    lsf:SetPoint("BOTTOMRIGHT", lf, "BOTTOMRIGHT", -14, 12)
    self.lsf = lsf

    local maxLogRows = 18
    self.logRows = {}
    for i = 1, maxLogRows do
        local row = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetWidth(920)
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
    lsf:EnableMouseWheel(true)
    lsf:SetScript("OnMouseWheel", function(self, delta)
        local bar = _G[(self:GetName() or "").."ScrollBar"]
        if bar then bar:SetValue(bar:GetValue() - delta * LOG_ROW_H) end
    end)
end

function GVE:ToggleGuildLogWindow()
    local lf = self.logPanel
    if not lf then return end
    if lf:IsShown() then
        lf:Hide()
        return
    end
    self:CloseFilterPanel()
    if self.lastOnlineWin then self.lastOnlineWin:Hide() end
    if self.detail then self.detail:Hide() end
    if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then GuildControlPopupFrame:Hide() end
    lf:Show()
    -- Nur beim bewussten Oeffnen anfragen; RefreshLog selbst fragt nie an.
    QueryGuildEventLog()
    self:RefreshLog()
end

-- WICHTIG: hier KEIN QueryGuildEventLog() aufrufen! Das wuerde
-- GUILD_EVENT_LOG_UPDATE ausloesen -> Event-Handler ruft RefreshLog ->
-- Endlosschleife -> Spiel haengt. Query passiert nur beim Klick auf Guild Log.
function GVE:RefreshLog()
    if not (self.logPanel and self.logPanel:IsShown()) then return end
    local n      = tonumber(GetNumGuildEvents()) or 0
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
    self:UpdateGuildControlButton()
    GuildRoster()        -- frische Daten anfordern (async -> GUILD_ROSTER_UPDATE)
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

-- Blizzards 3.3.5a-Guild-Keybind (TOGGLEGUILDTAB) ruft
-- ToggleFriendsFrame(3) auf. TOGGLESOCIAL (Standard: O) ruft die Funktion
-- dagegen ohne Argument auf und verwendet den zuletzt gewaehlten Tab. Darum
-- muessen sowohl der explizite Tab 3 als auch ein gespeicherter Guild-Tab
-- umgeleitet werden.
function GVE:IsGuildSocialRequest(tab)
    if tab == 3 then return true end
    if tab ~= nil then return false end
    return FriendsFrame and tonumber(FriendsFrame.selectedTab) == 3
end

function GVE:ResetBlizzardSocialTab()
    if not FriendsFrame then return end
    -- Nach der Weiterleitung darf O nicht dauerhaft an der alten Guild-Seite
    -- haengen bleiben. Der unsichtbare Blizzard-Rahmen merkt sich stattdessen
    -- den Freunde-Tab fuer sein naechstes normales Oeffnen.
    FriendsFrame.selectedTab = 1
    if type(PanelTemplates_SetTab) == "function" then
        PanelTemplates_SetTab(FriendsFrame, 1)
    end
end

function GVE:HideBlizzardGuildFrame()
    -- GuildFrame vorsorglich separat verstecken. Je nach Aufrufreihenfolge
    -- kann es bereits eingeblendet worden sein, obwohl FriendsFrame erst im
    -- selben UI-Zyklus sichtbar wird.
    if GuildFrame and GuildFrame.Hide then GuildFrame:Hide() end
    if FriendsFrame and FriendsFrame:IsShown() then HideUIPanel(FriendsFrame) end
end

function GVE:HookGuildFrame()
    local orig = ToggleFriendsFrame
    _G["ToggleFriendsFrame"] = function(tab)
        local selectedTab = FriendsFrame and FriendsFrame.selectedTab
        Log("ToggleFriendsFrame("..tostring(tab).."), selectedTab="..tostring(selectedTab))
        -- Ist GVE bereits offen, soll O unmittelbar zur Freundesliste
        -- wechseln statt GVE nur zu schliessen oder erneut zu toggeln.
        if tab == nil and GVE.f and GVE.f:IsShown() then
            GVE:ResetBlizzardSocialTab()
            GVE:Close()
            return orig(1)
        end
        if GVE:IsGuildSocialRequest(tab) then
            GVE:ResetBlizzardSocialTab()
            GVE:HideBlizzardGuildFrame()
            GVE:Toggle()
            return
        end
        if tab ~= nil and GVE.f and GVE.f:IsShown() then GVE:Close() end
        return orig(tab)
    end
    Log("Hook: ToggleFriendsFrame ersetzt")

    -- GuildStatus_Update() oeffnet beim Speichern direkt FriendsFrame.
    -- Nur fuer das aus GuildView geoeffnete Popup wird genau dieser eine
    -- Aufruf unterdrueckt; Blizzards eigentliche Speicherlogik bleibt intakt.
    local saveButton = _G["GuildControlPopupAcceptButton"]
    if saveButton and saveButton:GetScript("OnClick") then
        local originalSaveScript = saveButton:GetScript("OnClick")
        saveButton:SetScript("OnClick", function(self, ...)
            local owned = GVE.guildControlOwned
            local originalStatusUpdate = _G["GuildStatus_Update"]
            if owned and type(originalStatusUpdate) == "function" then
                _G["GuildStatus_Update"] = function() end
            end
            local ok, err = pcall(originalSaveScript, self, ...)
            if owned then _G["GuildStatus_Update"] = originalStatusUpdate end
            if not ok then Log("FEHLER in GuildControlSave: "..tostring(err)) end
            if owned then
                GVE.guildControlOwned = nil
                GuildRoster()
                if GVE.f then GVE.f:Show() end
            end
        end)
        Log("Hook: GuildControl-Speichern bleibt in GuildView")
    end

    -- Gilden-Tab im Social-Fenster: der Klick auf den Tab laeuft NICHT
    -- ueber ToggleFriendsFrame -> eigenen Hook setzen, sonst landet man
    -- im alten (leeren) Gilden-Tab.
    if FriendsFrameTab3 then
        FriendsFrameTab3:HookScript("OnClick", function()
            Log("FriendsFrameTab3 geklickt")
            GVE:ResetBlizzardSocialTab()
            GVE:HideBlizzardGuildFrame()
            GVE:Open()
        end)
        Log("Hook: FriendsFrameTab3 ok")
    else
        Log("Hook: FriendsFrameTab3 existiert nicht!")
    end

    -- Sicherheitsnetz fuer Addons oder Blizzard-Code, die FriendsFrame direkt
    -- anzeigen und ToggleFriendsFrame dadurch vollstaendig umgehen.
    if FriendsFrame and FriendsFrame.HookScript then
        FriendsFrame:HookScript("OnShow", function(self)
            if tonumber(self.selectedTab) == 3 then
                Log("FriendsFrame direkt mit Guild-Tab geoeffnet -> GuildView")
                GVE:ResetBlizzardSocialTab()
                GVE:HideBlizzardGuildFrame()
                GVE:Open()
            end
        end)
        Log("Hook: FriendsFrame-OnShow prueft gespeicherten Guild-Tab")
    end

    if GuildControlPopupFrame then
        GuildControlPopupFrame:HookScript("OnHide", function()
            GVE.guildControlOwned = nil
        end)
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
        local version = GetAddOnMetadata and GetAddOnMetadata("Guild-View-Extended", "Version") or "?"
        print("|cff33aaff[Guild-View-Extended "..tostring(version).."]|r loaded  |cffffcc00/gve|r oeffnet,  |cffffcc00/gve log|r zeigt das Log.")

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
