-- Regression test for the 3.3.5a Social/Guild redirect.
-- This file is not listed in the TOC and is never loaded by World of Warcraft.

_G = _G or {}
StaticPopupDialogs = {}
UISpecialFrames = {}
CLOSE = "Close"
OKAY = "Okay"
tinsert = table.insert
format = string.format
date = function() return "00:00:00" end
GetLocale = function() return "enUS" end

function CreateFrame()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end

dofile("Guild-View-Extended.lua")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label.."\nExpected: "..tostring(expected).."\nActual: "..tostring(actual))
    end
end

FriendsFrame = {selectedTab=3}
equal(GVE:IsGuildSocialRequest(nil), true,
    "O key redirects when the remembered Social tab is Guild")

FriendsFrame.selectedTab = 1
equal(GVE:IsGuildSocialRequest(nil), false,
    "O key keeps Blizzard behavior when Friends is remembered")
equal(GVE:IsGuildSocialRequest(3), true,
    "explicit Guild keybind redirects")
equal(GVE:IsGuildSocialRequest(2), false,
    "other explicit Social tabs are untouched")

FriendsFrame = nil
equal(GVE:IsGuildSocialRequest(nil), nil,
    "missing FriendsFrame does not redirect a generic Social request")

do
    local originalCalls, originalTab, openCalls, toggleCalls, closeCalls = 0, nil, 0, 0, 0
    ToggleFriendsFrame = function(tab) originalCalls, originalTab = originalCalls + 1, tab end
    HideUIPanel = function(frame) frame.shown = false end
    PanelTemplates_SetTab = function(frame, tab) frame.templateTab = tab end
    GuildFrame = {Hide=function(self) self.hidden = true end}
    FriendsFrame = {
        selectedTab=1, shown=true, scripts={},
        IsShown=function(self) return self.shown end,
        HookScript=function(self, event, handler) self.scripts[event] = handler end,
    }
    local function NewTab()
        return {scripts={}, HookScript=function(self, event, handler) self.scripts[event] = handler end}
    end
    FriendsFrameTab1, FriendsFrameTab2, FriendsFrameTab3, FriendsFrameTab4 = NewTab(), NewTab(), NewTab(), NewTab()
    GVE.Open = function() openCalls = openCalls + 1 end
    GVE.Toggle = function() toggleCalls = toggleCalls + 1 end
    GVE.Close = function() closeCalls = closeCalls + 1; GVE.f.shown = false end
    GVE.f = {shown=false, IsShown=function(self) return self.shown end}
    GVE:HookGuildFrame()

    FriendsFrameTab3.scripts.OnClick()
    equal(openCalls, 1, "Guild tab opens Guild View")
    equal(FriendsFrame.selectedTab, 1, "Guild redirect resets stock Social frame to Friends")
    equal(FriendsFrame.templateTab, 1, "visible stock tab state resets to Friends")

    FriendsFrame.selectedTab = 1
    ToggleFriendsFrame(nil)
    equal(originalCalls, 1, "O opens the stock Social frame after Guild redirect")

    FriendsFrame.selectedTab = 3
    ToggleFriendsFrame(nil)
    equal(toggleCalls, 1, "remembered stock Guild tab redirects to Guild View once")
    equal(FriendsFrame.selectedTab, 1, "remembered Guild redirect also resets to Friends")

    GVE.f.shown = true
    ToggleFriendsFrame(nil)
    equal(closeCalls, 1, "O closes an open Guild View before showing Friends")
    equal(originalCalls, 2, "O switches directly from Guild View to Friends")
    equal(originalTab, 1, "switch from Guild View explicitly opens Friends tab")

    ToggleFriendsFrame(2)
    equal(originalCalls, 3, "other explicit Social tabs remain stock behavior")
end

print("social_toggle_test.lua: all tests passed")
