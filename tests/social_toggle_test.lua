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

GVE.guildSocialSelected = true
FriendsFrame.selectedTab = 1
equal(GVE:IsGuildSocialRequest(nil), true,
    "remembered Guild redirect survives clients resetting selectedTab")
GVE.guildSocialSelected = nil

FriendsFrame = nil
equal(GVE:IsGuildSocialRequest(nil), nil,
    "missing FriendsFrame does not redirect a generic Social request")

do
    local originalCalls, openCalls, toggleCalls = 0, 0, 0
    ToggleFriendsFrame = function() originalCalls = originalCalls + 1 end
    HideUIPanel = function(frame) frame.shown = false end
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
    GVE:HookGuildFrame()

    FriendsFrameTab3.scripts.OnClick()
    equal(openCalls, 1, "Guild tab opens Guild View")
    equal(GVE.guildSocialSelected, true, "Guild tab selection is remembered independently")

    FriendsFrame.selectedTab = 1 -- observed behavior on clients that reset the stock field
    ToggleFriendsFrame(nil)
    equal(toggleCalls, 1, "second O press still routes to Guild View")
    equal(originalCalls, 0, "stock Social window remains closed for remembered Guild route")

    FriendsFrameTab1.scripts.OnClick()
    ToggleFriendsFrame(nil)
    equal(originalCalls, 1, "choosing Friends restores the stock O behavior")
end

print("social_toggle_test.lua: all tests passed")
