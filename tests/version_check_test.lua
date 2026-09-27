-- Standalone Lua 5.1-compatible tests for peer-based version discovery.
-- This file is not listed in the TOC and is never loaded by World of Warcraft.

_G = _G or {}
UISpecialFrames = {}
tinsert = table.insert
format = string.format
GetLocale = function() return "enUS" end
GetTime = function() return 100 end
GetAddOnMetadata = function(_, field) return field == "Version" and "1.1" or nil end
IsInGuild = function() return true end
UnitName = function() return "Tester" end

local messages, addonPackets = {}, {}
DEFAULT_CHAT_FRAME = {AddMessage=function(_, message) messages[#messages + 1] = message end}
SendAddonMessage = function(prefix, payload, channel, target)
    addonPackets[#addonPackets + 1] = {prefix=prefix, payload=payload, channel=channel, target=target}
end

local eventFrame
function CreateFrame()
    eventFrame = {
        scripts={},
        RegisterEvent=function() end,
        SetScript=function(self, event, handler) self.scripts[event] = handler end,
    }
    return eventFrame
end

GVE = {
    GetMembers=function()
        return {
            {name="Tester", online=true},
            {name="Jaina", online=true},
        }
    end,
}

dofile("Guild-View-Extended-Version.lua")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label.."\nExpected: "..tostring(expected).."\nActual: "..tostring(actual))
    end
end

equal(GVE.VersionCheck:CompareVersions("1.2", "1.1"), 1, "two-component newer version")
equal(GVE.VersionCheck:CompareVersions("1.1", "1.1.0"), 0, "missing patch equals zero")
equal(GVE.VersionCheck:CompareVersions("1.2-beta", "1.2-rc"), -1, "prerelease order")
equal(GVE.VersionCheck:CompareVersions("1.2", "1.2-rc1"), 1, "release newer than release candidate")
equal(GVE.VersionCheck:CompareVersions("invalid", "1.1"), nil, "invalid version rejected")

GVE.VersionCheck.marker = {
    shown=false,
    Show=function(self) self.shown=true end,
    Hide=function(self) self.shown=false end,
}
equal(GVE.VersionCheck:OnAddonMessage("GVEVER1", "H|1.2", "GUILD", "Jaina"), true,
    "newer guild member announcement accepted")
equal(#messages, 2, "newer version creates chat information once")
equal(GVE.VersionCheck.marker.shown, true, "newer version shows quest marker")
equal(addonPackets[1].channel, "WHISPER", "guild hello acknowledged privately")
equal(addonPackets[1].target, "Jaina", "acknowledgement target")

GVE.VersionCheck:OnAddonMessage("GVEVER1", "H|1.2", "GUILD", "Jaina")
equal(#messages, 2, "same version notification does not spam")
equal(GVE.VersionCheck:OnAddonMessage("GVEVER1", "H|9.9", "GUILD", "Stranger"), false,
    "non-guild sender rejected")
equal(GVE.VersionCheck:OnAddonMessage("WRONG", "H|9.9", "GUILD", "Jaina"), false,
    "wrong addon prefix rejected")

local kind, remote, nonce = GVE.VersionCheck:ParseRealmPacket("GVEV1:R:1.3:100-1234")
equal(kind, "R", "realm packet kind")
equal(remote, "1.3", "realm packet version")
equal(nonce, "100-1234", "realm packet nonce")
equal(GVE.VersionCheck:ParseRealmPacket("GVEV1|R|9.9|bad"), nil,
    "chat escape-style packet rejected")

print("version_check_test.lua: all tests passed")
