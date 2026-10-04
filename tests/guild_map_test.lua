-- Standalone Lua 5.1 regression tests; never loaded by WoW.
local now, guild, instance, mapShown = 100, "Test Guild", false, false
local continent, zone, mapFile, mapX, mapY = 2, 1, "Elwynn", 0.5, 0.5
local cv = {nameplateShowFriends="0", nameplateShowEnemies="0", minimapInsideZoom="3", minimapZoom="0", rotateMinimap="0"}
local sent, worldChildren = {}, {}
local cvarHook, combat, bindings = nil, false, {}
hooksecurefunc=function(name, fn) if name=="SetCVar" then cvarHook=fn end end
GetTime = function() return now end
GetLocale = function() return "enUS" end
GetGuildInfo = function() return guild end
GetRealmName = function() return "Test Realm" end
UnitName = function() return "Main" end
IsInGuild = function() return guild ~= nil end
IsInInstance = function() return instance end
GetCVar = function(key) return cv[key] end
SetCVar = function(key,value) cv[key] = tostring(value); if cvarHook then cvarHook(key,value) end end
InCombatLockdown=function() return combat end
GetBindingKey=function(action) return ({NAMEPLATES="V",FRIENDNAMEPLATES="SHIFT-V",ALLNAMEPLATES="CTRL-V"})[action] end
ClearOverrideBindings=function() bindings={} end
SetOverrideBindingClick=function(_,_,key,button) bindings[key]=button end
GetPlayerFacing = function() return 0 end
GetCurrentMapContinent = function() return continent end
GetCurrentMapZone = function() return zone end
GetMapInfo = function() return mapFile end
GetCurrentMapDungeonLevel = function() return 0 end
GetPlayerMapPosition = function() return mapX, mapY end
local mapChanges = 0
SetMapToCurrentZone = function() mapChanges = mapChanges+1 end
SendAddonMessage = function(prefix, message, channel) sent[#sent+1]={prefix, message, channel} end
SlashCmdList = {}
GVESyncData = {settings={}}
GVE = {GetMembers=function()
    return {{name="Main",online=true},{name="Jaina",online=true},{name="Thrall",online=true}}
end}

local function object(kind)
    local o = {kind=kind or "Frame", scripts={}, shown=true, width=140, height=140, alpha=1, color={1,0,0}}
    function o:GetObjectType() return self.kind end
    function o:RegisterEvent() end
    function o:SetScript(event,fn) self.scripts[event]=fn end
    function o:SetWidth(value) self.width=value end
    function o:SetHeight(value) self.height=value end
    function o:GetWidth() return self.width end
    function o:GetHeight() return self.height end
    function o:SetFrameLevel() end
    function o:GetFrameLevel() return 1 end
    function o:GetZoom() return 0 end
    function o:SetPoint(...) self.point={...} end
    function o:ClearAllPoints() end
    function o:SetAllPoints() end
    function o:EnableMouse() end
    function o:Show() self.shown=true end
    function o:Hide() self.shown=false end
    function o:IsShown() return self.shown end
    function o:GetName() return self.name end
    function o:RegisterForClicks() end
    function o:SetText(value) self.text=value end
    function o:GetText() return self.text end
    function o:SetTextColor(...) self.color={...} end
    function o:GetTextColor() return unpack(self.color) end
    function o:GetStatusBarColor() return unpack(self.color) end
    function o:GetAlpha() return self.alpha end
    function o:SetAlpha(value) self.alpha=value end
    function o:GetFont() return "Fonts\\FRIZQT__.TTF",12,"" end
    function o:SetFont(...) self.font={...} end
    function o:SetShadowColor() end
    function o:SetShadowOffset() end
    function o:SetBackdrop() end
    function o:SetBackdropColor() end
    function o:SetBackdropBorderColor() end
    function o:SetJustifyH() end
    function o:SetJustifyV() end
    function o:SetTexture(value) self.texture=value end
    function o:GetTexture() return self.texture end
    function o:CreateTexture() return object("Texture") end
    function o:CreateFontString() return object("FontString") end
    function o:GetRegions() return unpack(self.regions or {}) end
    function o:GetChildren() return unpack(self.children or {}) end
    return o
end
CreateFrame = function(_,name) local frame=object(); frame.name=name; return frame end
UIParent, Minimap, WorldMapButton = object(), object(), object()
WorldMapFrame = {IsShown=function() return mapShown end}
WorldFrame = {GetChildren=function() return unpack(worldChildren) end}
GameTooltip = {Hide=function() end}
dofile("Guild-View-Extended-MapData.lua")
dofile("Guild-View-Extended-Map.lua")
dofile("Guild-View-Extended-Markers.lua")
local Map = GVE.GuildMap
local function equal(a,b,label) if a~=b then error(label..": "..tostring(a).." != "..tostring(b)) end end
local function near(a,b,label) if math.abs(a-b)>0.001 then error(label) end end
Map:RefreshMembers()
Map:CheckGuild()
Map:Broadcast()
equal(sent[1][1],"GVEM1","dedicated legacy prefix")
equal(sent[1][3],"GUILD","guild-only transmission")
equal(sent[1][2],"P|2|Elwynn|0|0.50000|0.50000","valid position packet")

local packet="P|2|Elwynn|0|0.50100|0.50000"
Map:Receive("GVEM1",packet,"GUILD","Jaina")
equal(Map.peers.jaina.name,"Jaina","guild peer accepted")
Map:Receive("GVEM1",packet,"WHISPER","Thrall")
equal(Map.peers.thrall,nil,"non-guild channel rejected")
Map:Receive("GVEM1",packet,"GUILD","Stranger")
equal(Map.peers.stranger,nil,"non-guild sender rejected")
now=now+1
Map:Receive("GVEM1","P|2|Elwynn|0|1.50000|0.50000","GUILD","Jaina")
equal(Map.peers.jaina.x,0.501,"out-of-range coordinate rejected")
Map:Receive("GVEM1","P|4|Unknown|0|0.5|0.5","GUILD","Thrall")
equal(Map.peers.thrall,nil,"unknown map rejected")
Map:Receive("GVEM1","P|2|Elwynn|0|0.00000|0.00000","GUILD","Thrall")
equal(Map.peers.thrall,nil,"invalid zero position rejected")

local x,y,distance=Map:MinimapOffset(Map.peers.jaina)
near(distance,3.470832,"yard conversion")
equal(x>0,true,"east is right on minimap")
near(y,0,"equal latitude")
cv.rotateMinimap="1"
GetPlayerFacing=function() return math.pi/2 end
local rx,ry=Map:MinimapOffset(Map.peers.jaina)
near(rx,0,"rotated minimap projects east onto vertical axis")
equal(ry<0,true,"minimap rotation sign")
cv.rotateMinimap="0"
GetPlayerFacing=function() return 0 end
mapShown=true
local before=mapChanges
Map:Broadcast()
equal(mapChanges,before,"visible map selection is never changed")
Map:Render()
equal(Map.peers.jaina.pins.world.shown,true,"world-map pin visible")
equal(Map.peers.jaina.pins.mini.shown,true,"nearby minimap pin visible")
equal(Map.nearby,nil,"no unwanted proximity HUD")

zone, mapFile = 0, "Azeroth"
local cx,cy=Map:Project(Map.peers.jaina,2,nil)
local continentData=GVE.GuildMapData[2]
mapX,mapY=cx,cy
Map:Broadcast()
equal(sent[#sent][2]:find("P|2|CONTINENT|",1,true),1,"visible continent map can broadcast")
local wx,wy=Map:Project(Map.peers.jaina,0,nil)
equal(wx>0 and wx<1 and wy>0 and wy<1,true,"Azeroth world-map projection")
equal(Map:Project({continent=3,map="Hellfire",x=.5,y=.5},0,nil),nil,
    "Outland is not plotted on Azeroth")

local plate=object()
plate.regions={}
for i=1,7 do plate.regions[i]=object("Texture") end
plate.regions[1]:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
plate.regions[7]=object("FontString")
plate.regions[7]:SetText("Thrall")
local health=object("StatusBar")
health.color={0,0,1}
plate.children={health}
local unrelated=object()
unrelated.UnitFrame={}
unrelated.extended={}
worldChildren={plate,unrelated}
Map:EnableNearby(true)
equal(cv.nameplateShowFriends,"1","friendly plates enabled")
equal(Map.plates[unrelated],nil,"unrelated UI fields are not nameplate ownership evidence")
equal(Map.plates[plate].marker.shown,true,"guild plate marked without peer addon")
equal(Map.plates[plate].marker.badge.shown,true,"generic G badge")
equal(Map.plates[plate].marker.label.color[1],.4,"neon green friendly label")
equal(Map.plates[plate].marker.label.font[3],"THICKOUTLINE","black outlined label")
equal(Map.plates[plate].marker.guild.text,"<Test Guild>","actual guild name")
equal(health.alpha,0,"friendly names-only mode removes bar")
equal(plate.regions[7].alpha,0,"original name not duplicated")
plate.regions[7]:SetText("Other Player")
Map:UpdateNameplates()
equal(Map.plates[plate].marker.shown,false,"reused plate removes guild marker")
equal(health.alpha,0,"non-guild bars stay off while friendly plates disabled")
Map:SetPlatePreference("friends",true)
Map:UpdateNameplates()
equal(health.alpha,1,"recycled plate bar restored when user enables plates")
equal(plate.regions[7].alpha,1,"recycled plate name restored when user enables plates")
plate.regions[7]:SetText("Thrall")
health.color={1,0,0}
Map:UpdateNameplates()
equal(health.alpha,0,"cross-faction names mode hides bar")
equal(health.color[1],1,"actual hostile health colour remains red")
equal(Map.plates[plate].marker.label.color[1],.4,"cross-faction guild name is neon green")
health.color={0,0,1}
GVESyncData.settings.guildMarkerStyle="plates"
Map:UpdateNameplates()
equal(health.alpha,1,"existing plate style keeps bars")
Map:SetPlatePreference("friends",false)
Map:EnableNearby(false)
equal(cv.nameplateShowFriends,"0","previous friendly plate preference restored")
equal(cv.nameplateShowEnemies,"0","previous enemy plate preference restored")
equal(Map.plates[plate].marker.shown,false,"disabled marker hidden")

-- The original CVar must survive a reload of the module while GVE's friendly
-- plate setting is active, so disabling afterwards restores the real choice.
Map:EnableNearby(true)
dofile("Guild-View-Extended-Map.lua")
dofile("Guild-View-Extended-Markers.lua")
GVE.GuildMap:EnableNearby(false)
equal(cv.nameplateShowFriends,"0","friendly plate preference survives module reload")
GVE.GuildMap=Map
dofile("Guild-View-Extended-Markers.lua")

-- ElvUI-style replacement: visible name can be abbreviated; use UnitName.
local external=object()
external.UnitFrame=object()
external.UnitFrame.Name=object("FontString")
external.UnitFrame.Name:SetText("Th.")
external.UnitFrame.Name.color={.8,.2,.9}
external.UnitFrame.UnitName="Thrall"
external.UnitFrame.Health=object("StatusBar")
ElvUI={{private={nameplates={enable=true}}}}
worldChildren={external}
GVESyncData.settings.guildMarkerStyle="auto"
external.UnitFrame.UnitType="ENEMY_PLAYER"
Map:EnableNearby(true)
equal(cv.nameplateShowFriends,"1","friendly anchors enabled with ElvUI")
equal(cv.nameplateShowEnemies,"1","hostile anchors enabled with ElvUI")
equal(GVESyncData.settings.guildFriendlyPrevious,"0","original addon visibility saved")
equal(Map.plates[external].marker.shown,true,"ElvUI visible-name badge")
equal(external.UnitFrame.Name.color[1],.8,"foreign name colour unchanged")
equal(external.UnitFrame.Name.alpha,0,"foreign name hidden while overlay shown")
equal(external.UnitFrame.Health.alpha,0,"foreign healthbar hidden in names mode")
equal(Map.plates[external].marker.label.shown,true,"shared green name style on foreign plate")
equal(Map.plates[external].marker.label.color[1],.4,"foreign guild name neon green")
external.UnitFrame.Name:Hide()
Map:UpdateNameplates()
equal(Map.plates[external].marker.shown,true,"hidden addon name still supports GVE overlay")
cv.nameplateShowFriends="0"
Map:UpdateNameplates()
equal(cv.nameplateShowFriends,"1","anchor visibility recovers after addon toggle")
external.UnitFrame.Name:Show()
Map:SetPlatePreference("enemies",true)
external.UnitFrame.UnitName="Stranger"
Map:UpdateNameplates()
equal(Map.plates[external].marker.shown,false,"recycled foreign plate unmarked")
equal(external.UnitFrame.Name.alpha,1,"recycled foreign name alpha restored")
equal(external.UnitFrame.Health.alpha,1,"recycled foreign bar alpha restored")
external.UnitFrame.UnitName="Jaina"
external.UnitFrame.UnitType="FRIENDLY_PLAYER"
Map:UpdateNameplates()
equal(Map.plates[external].marker.label.text,"Jaina","friendly member overlay without peer addon")
Map:EnableNearby(false)
equal(external.UnitFrame.Health.alpha,1,"foreign bar restored on disable")
equal(cv.nameplateShowFriends,"0","external friendly preference restored")
equal(cv.nameplateShowEnemies,"1","latest external enemy preference restored")
Map:EnableNearby(true)

-- Explicit user setting writes and stock key presses affect visible bars,
-- while GVE keeps actual engine anchors active. No addon profile is changed.
SetCVar("nameplateShowFriends","1")
Map:UpdateNameplates()
equal(external.UnitFrame.Health.alpha,1,"ElvUI bars preserved with friendly plates on")
SetCVar("nameplateShowFriends","0")
Map:UpdateNameplates()
equal(cv.nameplateShowFriends,"1","friends-off retains engine anchors")
equal(external.UnitFrame.Health.alpha,0,"friends-off hides guild bars but keeps green name")
equal(Map.plates[external].marker.shown,true,"friends-off keeps guild marker")
Map:TogglePlatePreference("ALLNAMEPLATES") -- enemies currently on -> both off
equal(external.UnitFrame.Health.alpha,0,"all-off guild remains names-only")
Map:TogglePlatePreference("ALLNAMEPLATES") -- both off -> both on
equal(external.UnitFrame.Health.alpha,1,"second all-plates key restores healthbars")
Map:TogglePlatePreference("FRIENDNAMEPLATES") -- friends-only
equal(GVESyncData.settings.guildEnemyPrevious,"0","friendly key keeps hostile visual preference separate")
Map:TogglePlatePreference("FRIENDNAMEPLATES") -- friends off
equal(external.UnitFrame.Health.alpha,0,"second friendly key hides bars again")
equal(bindings["V"],"GVEGuildMarkerToggleNAMEPLATES","stock enemy key temporarily integrated")
combat=true
Map:EnableNearby(false)
equal(Map.markerBindingsPending,true,"binding cleanup deferred safely during combat")
combat=false
Map:UpdateMarkerBindings()
equal(next(bindings),nil,"temporary bindings removed on disable")
Map:EnableNearby(true)
local tidy=object()
tidy.extended=object()
tidy.extended.visual={name=object("FontString")}
tidy.extended.unit={name="Jaina"}
worldChildren={tidy}
Map:UpdateNameplates()
equal(Map.plates[tidy].marker.shown,true,"TidyPlates badge adapter")
tidy.extended.bars={healthbar=object("StatusBar"),castbar=object("StatusBar")}
tidy.extended.unit.reaction="FRIENDLY"
Map:SetPlatePreference("friends",true)
Map:UpdateNameplates()
equal(tidy.extended.bars.healthbar.alpha,1,"TidyPlates bars retained when on")
Map:SetPlatePreference("friends",false)
Map:UpdateNameplates()
equal(tidy.extended.bars.healthbar.alpha,0,"TidyPlates bars hidden when off")
local refined=object()
refined.RealPlate=object()
refined.RBP_nameString="Thrall"
refined.RBP_barlessPlateIsShown=true
refined.RBP_barlessPlate_nameText=object("FontString")
worldChildren={refined}
Map:UpdateNameplates()
equal(Map.plates[refined].marker.shown,true,"RefinedBlizzPlates barless adapter")
refined.RBP_isFriendly=false
refined.RBP_healthBar=object("StatusBar")
refined.RBP_castBar=object("StatusBar")
Map:SetPlatePreference("enemies",true)
Map:UpdateNameplates()
equal(refined.RBP_healthBar.alpha,1,"Refined enemy bars retained when on")
Map:SetPlatePreference("enemies",false)
Map:UpdateNameplates()
equal(refined.RBP_healthBar.alpha,0,"Refined enemy bars hidden when off")
equal(Map.plates[refined].marker.label.color[1],.4,"Refined cross-faction name green")
worldChildren={plate}
Map:UpdateNameplates()
equal(Map.plates[plate].marker.shown,true,"generic stock-preserving skin fallback")
local stable=Map.plates[plate].marker
Map:UpdateNameplates()
equal(Map.plates[plate].marker,stable,"generic fallback does not repeatedly replace transparent name")
Map:EnableNearby(false)
equal(health.alpha,1,"generic stock fallback restores healthbar")
ElvUI=nil

-- No third-party addon: independent friendly and hostile auto modes.
local enemy=object()
enemy.regions={unpack(plate.regions)}
enemy.regions[7]=object("FontString")
enemy.regions[7]:SetText("Jaina")
enemy.children={object("StatusBar")}
enemy.children[1].color={1,0,0}
worldChildren={plate,enemy}
Map:EnableNearby(true)
Map:SetPlatePreference("friends",true)
Map:SetPlatePreference("enemies",false)
Map:UpdateNameplates()
equal(health.alpha,1,"stock friendly bars on")
equal(enemy.children[1].alpha,0,"stock hostile bars off independently")
equal(Map.plates[enemy].marker.shown,true,"stock cross-faction marker survives plates-off")
Map:TogglePlatePreference("ALLNAMEPLATES") -- both off
Map:TogglePlatePreference("ALLNAMEPLATES") -- both on
equal(enemy.children[1].alpha,1,"stock enemy bars restored by second toggle")
equal(health.alpha,1,"stock friendly bars restored by second toggle")
Map:TogglePlatePreference("ALLNAMEPLATES") -- both off
plate.shown=false
Map:UpdateNameplates()
equal(Map.plates[plate].marker.shown,false,"out-of-view plate never retains floating marker")
plate.shown=true
Map:EnableNearby(false)

now=now+20
Map:Render()
equal(Map.peers.jaina,nil,"stale positions expire")
equal(Map.nearby,nil,"stale data does not create HUD")
mapShown=false
continent,zone,mapFile,mapX,mapY=2,1,"Elwynn",.5,.5
Map:Broadcast()
Map:Receive("GVEM1",packet,"GUILD","Jaina")
Map:Receive("GVEM1","X","GUILD","Jaina")
equal(Map.peers.jaina,nil,"explicit unavailable position removes peer")
Map:Receive("GVEM1",packet,"GUILD","Jaina")
guild="Other Guild"
Map:CheckGuild()
equal(Map.peers.jaina,nil,"guild change clears live positions")
guild="Test Guild"
instance=true
Map:Broadcast()
equal(sent[#sent][2],"X","instance positions withdrawn")
equal(Map.position,nil,"instance never reuses outdoor position")
equal(GVESyncData.peers,nil,"positions are not saved")
local diagnostics={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,line) diagnostics[#diagnostics+1]=line end}
Map:MarkerDiagnostics()
equal(#diagnostics,2,"diagnostics report visibility and matching counts")
equal(diagnostics[2]:find("guildMatches=",1,true)~=nil,true,"diagnostics expose matching stage")
print("guild_map_test.lua: all tests passed")
