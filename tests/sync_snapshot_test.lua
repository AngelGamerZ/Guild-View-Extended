-- Standalone Lua 5.1-compatible tests for the sync serialization layer.
_G = _G or {}
format = string.format
wipe = function(t) for key in pairs(t) do t[key] = nil end end
time = function() return 1800000000 end
GetTime = function() return 100 end
GetLocale = function() return "deDE" end
GetGuildInfo = function() return "Test Guild" end
GetRealmName = function() return "Test Realm" end
UnitName = function() return "Tester" end

GVE = {
    GetMembers = function() return {{name="Jaina", online=true}} end,
    SetRosterListener = function() end,
}

local eventFrame = {scripts={}}
function eventFrame:RegisterEvent() end
function eventFrame:SetScript(name, handler) self.scripts[name] = handler end
function CreateFrame() return eventFrame end

dofile("Guild-View-Extended-Sync.lua")
GVE.Sync:InitDB()

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label.."\nExpected: "..tostring(expected).."\nActual: "..tostring(actual))
    end
end

do
    local realWotlkLink = "|cffffd000|Htrade:27028:375:375:3111EE:xG{_yK|h[Erste Hilfe]|h|r"
    local opaqueBitmapLink = "|cffffd000|Htrade:3908:450:450:00000000ABCDEF12:A+:B/_|h[Schneiderei]|h|r"
    local shortOwnerLink = "|cffffd000|Htrade:2018:43:75:A74B:XEGAAAAAAAIAAAAAIAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwHAA|h[Blacksmithing]|h|r"
    local source = {
        professions = {
            ["Erste Hilfe"] = {
                skill=375, maxSkill=375, capturedAt=1799999000,
                tradeLink=realWotlkLink,
            },
            ["Schneiderei"] = {
                skill=450, maxSkill=450, capturedAt=1799999000,
                tradeLink=opaqueBitmapLink,
            },
            ["Blacksmithing"] = {
                skill=43, maxSkill=75, capturedAt=1799999000,
                tradeLink=shortOwnerLink,
            },
        },
    }
    local payload = GVE.Sync:SerializeProfessions(source)
    local decoded = GVE.Sync:DeserializeProfessions(payload, 1799999000)
    equal(decoded.professions["Erste Hilfe"].skill, 375, "profession skill")
    equal(decoded.professions["Erste Hilfe"].tradeLink, realWotlkLink,
        "real 3.3.5a trade link remains byte-for-byte intact")
    equal(decoded.professions["Schneiderei"].tradeLink, opaqueBitmapLink,
        "opaque bitmap including a colon remains intact")
    equal(decoded.professions["Blacksmithing"].tradeLink, shortOwnerLink,
        "four-character owner id from a live 3.3.5a server is accepted")
    equal(decoded.professionsCapturedAt, 1799999000, "profession timestamp")
end

do
    local unsafe = "Schmiedekunst~450~450~1799999000~"..
        "%7Ccffffffff%7CHitem%3A19019%7Ch%5BThunderfury%5D%7Ch%7Cr"
    equal(GVE.Sync:DeserializeProfessions(unsafe, 1799999000), nil,
        "non-trade hyperlink rejected")
end

do
    local ownLink = "|cffffd000|Htrade:51309:450:450:ABCDEF:xG{_yK|h[Schmiedekunst]|h|r"
    GetNumSpellTabs = function() return 1 end
    GetSpellTabInfo = function() return "Berufe", nil, 0, 1 end
    GetSpellLink = function(slot, bookType)
        equal(slot, 1, "spellbook slot")
        equal(bookType, "spell", "3.3.5a spellbook type")
        return "|cff71d5ff|Hspell:2018|h[Schmiedekunst]|h|r", ownLink
    end
    BOOKTYPE_SPELL = "spell"
    GVE.Sync.own = {}
    equal(GVE.Sync:CaptureProfession(false), true, "second GetSpellLink return captured")
    equal(GVE.Sync.own.professions["Schmiedekunst"].tradeLink, ownLink,
        "spellbook profession link captured unchanged")

    GetNumSpellTabs = function() return 0 end
    GetTradeSkillListLink = function() return ownLink end
    IsTradeSkillLinked = function() return true end
    GVE.Sync.own = {}
    equal(GVE.Sync:CaptureProfession(false), false, "linked foreign profession rejected")
    equal(GVE.Sync.own.professions, nil, "foreign link does not become own data")
end

do
    local oldLink = "|cffffd000|Htrade:3908:438:450:ABCDEF:xG{_yK|h[Schneiderei]|h|r"
    GVESyncData = {
        schema=3,
        players={jaina={
            receivedAt=1800000000,
            reagents={items={[14047]=10}},
            professions={Schneiderei={
                name="Schneiderei", skill=438, maxSkill=450,
                capturedAt=1799999000, tradeLink=oldLink,
                recipes={{spell=26745, item=21840}}, recipeIndexComplete=true,
            }},
        }},
        ownByCharacter={},
        settings={shareProfessions=true, shareReagents=true},
    }
    GVE.Sync:InitDB()
    equal(GVESyncData.schema, 4, "schema migrated to profession-only v4")
    equal(GVESyncData.settings.shareReagents, nil, "obsolete sharing setting removed")
    equal(GVESyncData.players.jaina.reagents, nil, "obsolete snapshot data removed")
    equal(GVESyncData.players.jaina.professions.Schneiderei.tradeLink, oldLink,
        "existing valid profession link retained")
    equal(GVESyncData.players.jaina.professions.Schneiderei.recipes, nil,
        "obsolete embedded index removed")

    GVESyncData.players.jaina.professions.Alchemie = {
        name="Alchemie", skill=450, maxSkill=450, capturedAt=1799999000,
        tradeLink="|cffffd000|Htrade:51304:450:450:ABCDEF:A+:B/_|h[Alchemie]|h|r",
    }
    GVE.GetMembers = function()
        return {
            {name="Jaina", rank="Offizier", online=true},
            {name="Thrall", rank="Mitglied", online=false},
        }
    end
    GVE.Sync.playerSearch = {GetText=function() return "" end}
    GVE.Sync:BuildPlayerList()
    GVE.Sync:SetAllCategories(true)
    GVE.Sync:BuildPlayerList()
    local jainaRows, thrallRows = 0, 0
    for _, row in ipairs(GVE.Sync.playerList) do
        if row.member and row.member.name == "Jaina" then jainaRows = jainaRows + 1 end
        if row.member and row.member.name == "Thrall" then thrallRows = thrallRows + 1 end
    end
    equal(jainaRows, 2, "player appears once in each profession category")
    equal(thrallRows, 1, "player without data appears in unsynchronized category")

    GVE.Sync.playerSearch = {GetText=function() return "schnei" end}
    GVE.Sync:BuildPlayerList()
    equal(#GVE.Sync.playerList, 2, "profession search returns header and matching player")
    equal(GVE.Sync.playerList[2].member.name, "Jaina", "profession search result")
end

do
    wipe(GVE.Sync.autoQueue)
    wipe(GVE.Sync.autoQueued)
    wipe(GVE.Sync.autoLastRequest)
    wipe(GVE.Sync.sendQueue)

    GVE.Sync:OnAddonMessage("GVEX4", "H|1800000000", "GUILD", "Jaina")
    equal(#GVE.Sync.autoQueue, 1, "guild discovery queues automatic request")
    equal(GVE.Sync.autoQueue[1].name, "Jaina", "automatic request target")

    GVE.Sync:OnAddonMessage("GVEX4", "H|1800000000", "GUILD", "Jaina")
    equal(#GVE.Sync.autoQueue, 1, "duplicate discovery is coalesced")

    -- A manual guild-wide refresh must ask a compatible client again even if
    -- its advertised timestamp matches the cached snapshot exactly. This is
    -- what makes refreshes reliable across addon release differences that use
    -- the same synchronization protocol.
    wipe(GVE.Sync.autoQueue)
    wipe(GVE.Sync.autoQueued)
    wipe(GVE.Sync.autoLastRequest)
    GVE.Sync.db.players.jaina.professionsCapturedAt = 1800000000
    GVE.Sync.forceDiscoveryUntil = GetTime() + 15
    GVE.Sync:OnAddonMessage("GVEX4", "A|1800000000", "WHISPER", "Jaina")
    equal(#GVE.Sync.autoQueue, 1, "manual discovery forces refresh for equal cached timestamp")
    equal(GVE.Sync.autoQueue[1].name, "Jaina", "forced refresh target")

    GVE.Sync.own = {
        professionsCapturedAt=1799999000,
        professions={Schmiedekunst={
            name="Schmiedekunst", skill=450, maxSkill=450, capturedAt=1799999000,
            tradeLink="|cffffd000|Htrade:51309:450:450:ABCDEF:xG{_yK|h[Schmiedekunst]|h|r",
        }},
    }

    GetNumSpellTabs = function() return 1 end
    GetSpellTabInfo = function() return "Berufe", nil, 0, 1 end
    GetSpellLink = function()
        return "|cff71d5ff|Hspell:2018|h[Schmiedekunst]|h|r",
            "|cffffd000|Htrade:51309:450:450:ABCDEF:xG{_yK|h[Schmiedekunst]|h|r"
    end
    IsTradeSkillLinked = function() return false end
    equal(GVE.Sync:CaptureProfession(false, true), true, "direct request refreshes unchanged local snapshot")
    equal(GVE.Sync.own.professionsCapturedAt, 1800000000, "unchanged snapshot receives fresh confirmation time")
    wipe(GVE.Sync.sendQueue)
    equal(GVE.Sync:ManualBroadcastSync(), true, "manual guild synchronization starts")
    local foundUpdate, foundDiscovery, foundCatalog = false, false, false
    for _, packet in ipairs(GVE.Sync.sendQueue) do
        if packet.message == "U|1800000000" then foundUpdate = true end
        if packet.message == "H|1800000000" then foundDiscovery = true end
        if packet.message:find("^C|%d+$") then foundCatalog = true end
    end
    equal(foundUpdate, true, "manual synchronization pushes own snapshot")
    equal(foundDiscovery, true, "manual synchronization broadcasts discovery request")
    equal(foundCatalog, true, "manual synchronization requests peer relay catalogs")
    equal(#GVE.Sync.autoQueue, 1, "manual synchronization directly queues online guild members")
    equal(GVE.Sync.autoQueue[1].force, true, "manual synchronization bypasses cached timestamps")

    wipe(GVE.Sync.sendQueue)
    equal(GVE.Sync:Announce("H"), true, "discovery announcement queued")
    equal(GVE.Sync.sendQueue[1].channel, "GUILD", "discovery uses guild addon channel")
    equal(GVE.Sync.sendQueue[1].message, "H|1800000000", "discovery advertises snapshot time")

    local sent = {}
    SendAddonMessage = function(prefix, message, channel, target)
        sent[#sent + 1] = {prefix=prefix, message=message, channel=channel, target=target}
    end
    GVE.Sync.elapsed = 0
    GVE.Sync.autoElapsed = 0
    eventFrame.scripts.OnUpdate(eventFrame, 1.1)
    equal(sent[1].prefix, "GVEX4", "automatic request uses sync prefix")
    equal(sent[1].channel, "WHISPER", "automatic snapshot request uses whisper")
    equal(sent[1].target, "Jaina", "automatic request is sent to discovered member")
    equal(sent[2].channel, "GUILD", "queued discovery announcement is sent to guild")
end

do
    local oldLink = "|cffffd000|Htrade:3908:151:300:ABCDEF:OLD|h[Tailoring]|h|r"
    local newLink = "|cffffd000|Htrade:3908:300:300:ABCDEF:NEW|h[Tailoring]|h|r"
    local newSnapshot = {
        professionsCapturedAt=1800000000,
        professions={Tailoring={
            name="Tailoring", skill=300, maxSkill=300,
            capturedAt=1800000000, tradeLink=newLink,
        }},
    }
    GVE.GetMembers = function()
        return {
            {name="Tester", online=true},
            {name="Astera", online=false},
            {name="Konrat", online=true},
            {name="Muri", online=true},
            {name="Twinka", online=false},
        }
    end
    GVE.Sync.db.players = {
        astera={
            displayName="Astera", receivedAt=1799999900,
            professionsCapturedAt=1799999000, directSource=true,
            professions={Tailoring={
                name="Tailoring", skill=151, maxSkill=300,
                capturedAt=1799999000, tradeLink=oldLink,
            }},
        },
    }
    GVE.Sync.db.ownByCharacter["Realm\031Guild\031Twinka"] = {
        professionsCapturedAt=1799999500, receivedAt=1799999500,
        professions={Tailoring={
            name="Tailoring", skill=225, maxSkill=300,
            capturedAt=1799999500,
            tradeLink="|cffffd000|Htrade:3908:225:300:ABCDEF:TWINK|h[Tailoring]|h|r",
        }},
    }

    wipe(GVE.Sync.sendQueue)
    GVE.Sync:SendRelayCatalog("Konrat", "700")
    local foundAstera, foundTwink = false, false
    for _, packet in ipairs(GVE.Sync.sendQueue) do
        if packet.message == "V|700|Astera|1799999000" then foundAstera = true end
        if packet.message == "V|700|Twinka|1799999500" then foundTwink = true end
    end
    equal(foundAstera, true, "relay catalog advertises directly cached offline player")
    equal(foundTwink, true, "relay catalog advertises account-wide offline twink")
    equal(GVE.Sync:QueueRelayCandidate("Konrat", "Twinka", 1799999400), false,
        "older relay cannot replace a newer account-wide offline twink snapshot")

    wipe(GVE.Sync.relayQueue)
    wipe(GVE.Sync.relayQueued)
    wipe(GVE.Sync.relayPending)
    wipe(GVE.Sync.relayReceiving)
    wipe(GVE.Sync.relayOwnerPending)
    GVE.Sync.relayCatalogPending.konrat = {requestID="701", deadline=200}
    GVE.Sync:OnAddonMessage("GVEX4", "V|701|Astera|1800000000", "WHISPER", "Konrat")
    equal(#GVE.Sync.relayQueue, 1, "newer relayed owner snapshot is queued")
    local candidate = table.remove(GVE.Sync.relayQueue, 1)
    GVE.Sync.relayQueued[candidate.ownerKey] = nil

    local sent = {}
    SendAddonMessage = function(prefix, message, channel, target)
        sent[#sent + 1] = {prefix=prefix, message=message, channel=channel, target=target}
    end
    equal(GVE.Sync:RequestRelayedSnapshot(candidate), true, "relay snapshot request starts")
    local requestID = sent[#sent].message:match("^R|(%d+)|Astera$")
    if not requestID then error("relay request packet missing owner") end

    local payload = GVE.Sync:SerializeProfessions(newSnapshot)
    local chunks = math.ceil(#payload / 175)
    GVE.Sync:OnAddonMessage("GVEX4",
        "RB|"..requestID.."|Astera|1800000000|"..chunks, "WHISPER", "Konrat")
    for index = 1, chunks do
        local part = payload:sub((index - 1) * 175 + 1, index * 175)
        GVE.Sync:OnAddonMessage("GVEX4",
            "RD|"..requestID.."|"..index.."|"..part, "WHISPER", "Konrat")
    end
    GVE.Sync:OnAddonMessage("GVEX4", "RE|"..requestID, "WHISPER", "Konrat")
    equal(GVE.Sync.db.players.astera.professions.Tailoring.skill, 300,
        "newer relayed profession replaces older cache")
    equal(GVE.Sync.db.players.astera.relayFrom, "Konrat",
        "last relay source is retained for UI provenance")

    wipe(GVE.Sync.sendQueue)
    GVE.Sync:SendRelayCatalog("Muri", "702")
    foundAstera = false
    for _, packet in ipairs(GVE.Sync.sendQueue) do
        if packet.message == "V|702|Astera|1800000000" then foundAstera = true end
    end
    equal(foundAstera, true, "relayed snapshot can propagate while prior relay is offline")
    equal(GVE.Sync:QueueRelayCandidate("Muri", "Astera", 1800000000), false,
        "equal timestamp stops relay loops")
end

print("Guild View Extended sync snapshot tests passed")
