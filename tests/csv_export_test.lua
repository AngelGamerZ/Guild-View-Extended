-- Standalone Lua 5.1-compatible tests for the production CSV helper.
-- This file is not listed in the TOC and is never loaded by World of Warcraft.

_G = _G or {}
StaticPopupDialogs = {}
UISpecialFrames = {}
CLOSE = "Close"
OKAY = "Okay"
tinsert = table.insert
format = string.format
date = function() return "00:00:00" end

function GetLocale()
    return "deDE"
end

local eventFrame
function CreateFrame()
    eventFrame = {
        scripts = {},
        RegisterEvent = function() end,
        SetScript = function(self, event, handler) self.scripts[event] = handler end,
    }
    return eventFrame
end

dofile("Guild-View-Extended.lua")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label.."\nExpected: "..tostring(expected).."\nActual: "..tostring(actual))
    end
end

local function build(members)
    return GVE:BuildCSVFromMembers(members)
end

do
    local csv, count = build({})
    equal(csv, "character_name,guild_rank", "empty guild")
    equal(count, 0, "empty guild count")
end

do
    local csv, count = build({{name="Arthas", rank="Guild Master"}})
    equal(csv, "character_name,guild_rank\nArthas,Guild Master", "one member")
    equal(count, 1, "one member count")
end

do
    local csv, count = build({
        {name="Thrall", rank="Officer"},
        {name="Jaina", rank="Raider"},
        {name="Arthas", rank="Guild Master"},
    })
    equal(csv, table.concat({
        "character_name,guild_rank",
        "Arthas,Guild Master",
        "Jaina,Raider",
        "Thrall,Officer",
    }, "\n"), "deterministic sample")
    equal(count, 3, "sample count")
end

do
    local csv, count = build({
        {name="arthas", rank="Officer, Lead"},
        {name="ARTHAS", rank="Duplicate rank ignored"},
        {name="Ärger", rank="Umlaut"},
        {name="ärger", rank="Duplicate"},
        {name="Thrall-Example Realm", rank="Officer"},
        {name="Jai\r\nna", rank="Mem\r\nber"},
        {name="O'Neil", rank="Raider"},
        {name="Comma,Name", rank='Raid "Lead"'},
        {name='Quote"Name', rank="Veteran"},
        {name="", rank="Invalid"},
        {name="   ", rank="Invalid"},
        {name=42, rank="Invalid"},
    })
    equal(csv, table.concat({
        "character_name,guild_rank",
        'arthas,"Officer, Lead"',
        '"Comma,Name","Raid ""Lead"""',
        "Jaina,Member",
        "O'Neil,Raider",
        '"Quote""Name",Veteran',
        "Thrall,Officer",
        "Ärger,Umlaut",
    }, "\n"), "cleanup, Unicode, dedupe, rank pairing, sort, and escaping")
    equal(count, 7, "complex count")
end

do
    local members = {}
    for i = 1, 5000 do
        members[i] = {name="Member"..i, rank="Rank"..i}
    end
    local csv, count, err = build(members)
    equal(count, 5000, "5,000-name limit")
    equal(err, nil, "5,000-name error")
    if not csv or not csv:find("^character_name,guild_rank\n") then
        error("5,000-name CSV missing exact header")
    end

    members[5001] = {name="Member5001", rank="Overflow"}
    csv, count, err = build(members)
    equal(csv, nil, "5,001-name CSV")
    equal(count, nil, "5,001-name count")
    if not err or not err:find("5000", 1, true) then
        error("5,001-name error must explain the 5,000-name limit")
    end
end

local function newWidget()
    local widget = {scripts = {}, shown = false}
    local methods = {
        CreateFontString = function() return newWidget() end,
        CreateTexture = function() return newWidget() end,
        SetScript = function(self, event, handler) self.scripts[event] = handler end,
        SetPoint = function(self, ...)
            local points = rawget(self, "points") or {}
            self.points = points
            points[#points+1] = {...}
        end,
        SetWidth = function(self, value) self.width = value end,
        SetHeight = function(self, value) self.height = value end,
        SetSize = function(self, width, height)
            self.width, self.height = width, height
        end,
        SetText = function(self, text) self.text = text end,
        SetWordWrap = function(self, value) self.wordWrap = value end,
        GetText = function(self) return self.text or "" end,
        SetFocus = function(self) self.focused = true end,
        ClearFocus = function(self) self.focused = false end,
        HighlightText = function(self) self.highlighted = true end,
        Show = function(self) self.shown = true end,
        Hide = function(self)
            self.shown = false
            if self.scripts.OnHide then self.scripts.OnHide(self) end
        end,
        IsShown = function(self) return self.shown end,
        GetFrameLevel = function() return 0 end,
        Enable = function(self) self.enabled = true end,
        Disable = function(self) self.enabled = false end,
    }
    return setmetatable(widget, {
        __index = function(_, key)
            return methods[key] or function() end
        end,
    })
end

do
    CreateFrame = function() return newWidget() end
    GVE.csvWindow = nil
    GVE:BuildCSVWindow()
    equal(UISpecialFrames[#UISpecialFrames], "GVECSVWindow", "Escape frame registration")

    GVE:ShowCSVWindow("character_name,guild_rank\nArthas,Guild Master", 1)
    equal(GVE.csvWindow.editBox.text,
        "character_name,guild_rank\nArthas,Guild Master", "dialog CSV text")
    equal(GVE.csvWindow.countText.text, "1 Charaktere exportiert", "dialog count")
    equal(GVE.csvWindow.shown, true, "dialog shown")
    equal(GVE.csvWindow.editBox.focused, true, "dialog focus")
    equal(GVE.csvWindow.editBox.highlighted, true, "dialog full selection")

    GVE.csvWindow.editBox.scripts.OnEscapePressed(GVE.csvWindow.editBox)
    equal(GVE.csvWindow.shown, false, "dialog closes via Escape")
    equal(GVE.csvWindow.editBox.focused, false, "dialog clears focus on Escape")
end

do
    UIDropDownMenu_SetWidth = function() end
    UIDropDownMenu_Initialize = function() end
    UIDropDownMenu_SetSelectedValue = function() end
    UIDropDownMenu_SetText = function() end
    FauxScrollFrame_SetOffset = function(frame, value) frame.offset = value end
    GVE.f = newWidget()
    GVE.lastOnlineWin = nil
    GVE:BuildLastOnlineWindow()
    local w = GVE.lastOnlineWin
    equal(#w.rows, 11, "last-online compact visible row count")
    equal(w.search.width, 360, "last-online search width")
    equal(w.rows[1].rank.wordWrap, false, "long ranks cannot wrap into next row")
    if not w.rows[1].divider then error("last-online row divider missing") end

    w.search:SetText("Arthas")
    w.search.scripts.OnTextChanged(w.search)
    equal(w.scroll.offset, 0, "last-online search resets scroll offset")
    w:Show()
    w.search.scripts.OnEscapePressed(w.search)
    equal(w.shown, false, "focused last-online search closes via Escape")
end

do
    local offlineRequests, rosterRequests = 0, 0
    SetGuildRosterShowOffline = function(value)
        if value then offlineRequests = offlineRequests + 1 end
    end
    GuildRoster = function() rosterRequests = rosterRequests + 1 end
    local frame = {rosterRefreshElapsed = 0}
    GVE:OnRosterRefreshUpdate(frame, 4.9)
    equal(rosterRequests, 0, "no early live roster refresh")
    GVE:OnRosterRefreshUpdate(frame, 0.1)
    equal(offlineRequests, 1, "live refresh includes offline members")
    equal(rosterRequests, 1, "live roster refresh after five seconds")
    equal(frame.rosterRefreshElapsed, 0, "live refresh timer reset")
end

do
    local source = {
        {name="Zulu", rank="Officer", lastOnline=240},
        {name="Ärger", rank="Raider", lastOnline=120},
        {name="ärztin", rank="Member", lastOnline=120},
        {name="Alpha", rank="Member", lastOnline=12},
    }

    local list = GVE:BuildLastOnlineList(source, "ÄR", nil, false)
    equal(#list, 2, "last-online search supports case-folded Umlauts")
    equal(list[1].name, "Ärger", "last-online equal-time sort is deterministic")
    equal(list[2].name, "ärztin", "last-online search returns all matches")

    list = GVE:BuildLastOnlineList(source, "ärger", 24, false)
    equal(#list, 1, "last-online search and time filter are combined")
    equal(list[1].name, "Ärger", "last-online combined filter result")

    list = GVE:BuildLastOnlineList(source, "", nil, true)
    equal(list[1].name, "Alpha", "last-online ascending sort")
    equal(list[#list].name, "Zulu", "last-online ascending sort end")

    list = GVE:BuildLastOnlineList(source, "no-match", nil, false)
    equal(#list, 0, "last-online no-result state")
end

do
    UnitName = function() return "Ownchar" end
    UIDropDownMenu_SetWidth = function() end
    UIDropDownMenu_Initialize = function() end
    GVE.f = newWidget()
    GVE.detail = nil
    GVE:BuildMemberDetail()
    equal(GVE.detail.invite.text, "Invite GRP", "group invite button label")
    equal(GVE.detail.remove.points[1][2], GVE.detail.invite,
        "group invite button is directly above remove")

    local invited
    InviteUnit = function(name) invited = name end
    GVE.detail.member = {name = "Otherchar"}
    GVE.detail.invite.scripts.OnClick()
    equal(invited, "Otherchar", "detail button immediately invites member")
    GVE.detail.member = {name = "Ownchar-Realm"}
    GVE.detail.invite.scripts.OnClick()
    equal(invited, "Otherchar", "detail button does not invite own character")
end

do
    local addedInfo, addedLevel, popup
    UIDropDownMenu_CreateInfo = function() return {} end
    UIDropDownMenu_AddButton = function(info, level)
        addedInfo, addedLevel = info, level
    end
    CloseDropDownMenus = function() end
    StaticPopup_Show = function(which) popup = which end
    GVE:AddLeaveGuildMenuItem()
    equal(addedInfo.text, "Gilde verlassen", "own-character leave menu label")
    equal(addedInfo.notCheckable, true, "leave menu item has no checkmark")
    equal(addedLevel, 1, "leave option added to primary context menu")
    addedInfo.func()
    equal(popup, "GVE_LEAVE_GUILD", "leave menu opens confirmation")

    local leftGuild = false
    GuildLeave = function() leftGuild = true end
    StaticPopupDialogs["GVE_LEAVE_GUILD"].OnAccept()
    equal(leftGuild, true, "leave confirmation invokes GuildLeave")
end

do
    local offlineRequested, rosterRequested = false, false
    SetGuildRosterShowOffline = function(value) offlineRequested = value end
    GuildRoster = function() rosterRequested = true end
    GVE.csvButton = newWidget()
    GVE.rosterLoaded = false
    GVE.csvPending = nil
    GVE:RequestCSVExport()
    equal(offlineRequested, true, "offline members requested")
    equal(rosterRequested, true, "asynchronous roster requested")
    equal(GVE.csvPending, true, "export waits for roster event")
    equal(GVE.csvButton.enabled, false, "button disabled while waiting")

    local exportCreated = false
    local rosterLoads, detailRefreshes = 0, 0
    GVE.f = {}
    GVE.LoadRoster = function() rosterLoads = rosterLoads + 1 end
    GVE.RefreshBottomPanels = function() end
    GVE.StepRank = function() end
    GVE.RefreshMemberDetail = function() detailRefreshes = detailRefreshes + 1 end
    GVE.RefreshLastOnlineWindow = function() end
    GVE.CreateCSVExport = function() exportCreated = true end
    eventFrame.scripts.OnEvent(eventFrame, "GUILD_ROSTER_UPDATE")
    equal(rosterLoads, 1, "roster event reloads members and notes")
    equal(detailRefreshes, 1, "roster event refreshes open member detail")
    equal(GVE.rosterLoaded, true, "roster marked loaded after event")
    equal(GVE.csvPending, nil, "pending export cleared after event")
    equal(GVE.csvButton.enabled, true, "button enabled after event")
    equal(exportCreated, true, "export created only after roster event")
end

print("Guild View Extended tests passed")
