--[[
Name: Astrolabe
Revision: $Rev: 92 $
$Date: 2008-10-05 17:22:44 -0700 (Sun, 05 Oct 2008) $
Author(s): Esamynn (esamynn at wowinterface.com)
Inspired By: Gatherer by Norganna
             MapLibrary by Kristofer Karlsson (krka at kth.se)
Documentation: http://wiki.esamynn.org/Astrolabe
SVN: http://svn.esamynn.org/astrolabe/
Description:
	This is a library for the World of Warcraft UI system to place
	icons accurately on both the Minimap and on Worldmaps.  
	This library also manages and updates the position of Minimap icons 
	automatically.  

Copyright (C) 2006-2008 James Carrothers

License:
	This library is free software; you can redistribute it and/or
	modify it under the terms of the GNU Lesser General Public
	License as published by the Free Software Foundation; either
	version 2.1 of the License, or (at your option) any later version.

	This library is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	Lesser General Public License for more details.

	You should have received a copy of the GNU Lesser General Public
	License along with this library; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

Note:
	This library's source code is specifically designed to work with
	World of Warcraft's interpreted AddOn system.  You have an implicit
	licence to use this library with these facilities since that is its
	designated purpose as per:
	http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
]]


-- Guild-View-Extended: static WotLK map dimensions extracted from Astrolabe.
-- Original source: https://github.com/CoronaCore/Tools/blob/master/AddOns/QuestHelper/Astrolabe/Astrolabe.lua
-- Only geographical data is used; no Astrolabe runtime or dependencies.
if not _G.GVE then return end
local maps = {
	-- World Map of Azeroth
	[0] = {
		parentContinent = 0,
		height = 29688.932932224,
		width = 44537.340058402,
	},
	-- Kalimdor
	{ -- [1]
		parentContinent = 0,
		height = 24533.025279205,
		width = 36800.210572494,
		xOffset = -8311.793923510446,
		yOffset = 1815.215685280706,
		zoneData = {
			Ashenvale = {
				height = 3843.722811451077,
				width = 5766.728884700476,
				xOffset = 15366.76755576002,
				yOffset = 8126.925260781192,
			},
			Aszhara = {
				height = 3381.225696279877,
				width = 5070.888165752819,
				xOffset = 20343.90485013144,
				yOffset = 7458.180046130774,
			},
			AzuremystIsle = {
				height = 2714.561862167815,
				width = 4070.883253576282,
				xOffset = 9966.70736478994,
				yOffset = 5460.278138661794,
			},
			Barrens = {
				height = 6756.202067150937,
				width = 10133.44343943073,
				xOffset = 14443.84117394525,
				yOffset = 11187.32013604393,
			},
			BloodmystIsle = {
				height = 2174.984710698752,
				width = 3262.517428121028,
				xOffset = 9541.713418184554,
				yOffset = 3424.874558234072,
			},
			Darkshore = {
				height = 4366.636219106706,
				width = 6550.06962983463,
				xOffset = 14125.08809600818,
				yOffset = 4466.534412478246,
			},
			Darnassis = {
				height = 705.7248633938184,
				width = 1058.342927027606,
				xOffset = 14128.39258617903,
				yOffset = 2561.565012455802,
			},
			Desolace = {
				height = 2997.895174253872,
				width = 4495.882023201739,
				xOffset = 12833.40729836031,
				yOffset = 12347.72848626745,
			},
			Durotar = {
				height = 3524.975114832228,
				width = 5287.558038649864,
				xOffset = 19029.30699887344,
				yOffset = 10991.48801260963,
			},
			Dustwallow = {
				height = 3499.975146240067,
				width = 5250.057259791282,
				xOffset = 18041.79657043901,
				yOffset = 14833.12751666842,
			},
			Felwood = {
				height = 3833.305958270781,
				width = 5750.062034325837,
				xOffset = 15425.10163773161,
				yOffset = 5666.526367166872,
			},
			Feralas = {
				height = 4633.30011661694,
				width = 6950.075260353015,
				xOffset = 11625.06045254075,
				yOffset = 15166.45834829251,
			},
			Moonglade = {
				height = 1539.572509508711,
				width = 2308.356845256911,
				xOffset = 18448.05172159372,
				yOffset = 4308.20254319874,
			},
			Mulgore = {
				height = 3424.975945100366,
				width = 5137.555355060729,
				xOffset = 15018.84750987729,
				yOffset = 13072.72336630089,
			},
			Ogrimmar = {
				height = 935.4100697456119,
				width = 1402.621211455915,
				xOffset = 20747.42666130799,
				yOffset = 10525.94769396873,
			},
			Silithus = {
				height = 2322.899061688691,
				width = 3483.371975265956,
				xOffset = 14529.25864164056,
				yOffset = 18758.10068625832,
			},
			StonetalonMountains = {
				height = 3256.226691571251,
				width = 4883.385977951072,
				xOffset = 13820.91773479217,
				yOffset = 9883.162892509636,
			},
			Tanaris = {
				height = 4599.965662459992,
				width = 6900.073766103516,
				xOffset = 17285.539010128,
				yOffset = 18674.7673661939,
			},
			Teldrassil = {
				height = 3393.726923234355,
				width = 5091.720903621394,
				xOffset = 13252.16205313556,
				yOffset = 968.6418744503761,
			},
			TheExodar = {
				height = 704.6826864472878,
				width = 1056.781131437323,
				xOffset = 10533.08314172693,
				yOffset = 6276.205331713322,
			},
			ThousandNeedles = {
				height = 2933.312180524323,
				width = 4400.046681282484,
				xOffset = 17500.12437633161,
				yOffset = 16766.44698282704,
			},
			ThunderBluff = {
				height = 695.8282721105132,
				width = 1043.761263579803,
				xOffset = 16550.11410485969,
				yOffset = 13649.80260929285,
			},
			UngoroCrater = {
				height = 2466.647220780505,
				width = 3700.040077455555,
				xOffset = 16533.44712326324,
				yOffset = 18766.4334494793,
			},
			Winterspring = {
				height = 4733.299561046713,
				width = 7100.077599808275,
				xOffset = 17383.45606038691,
				yOffset = 4266.536453420381,
			},
		},
	},
	-- Eastern Kingdoms
	{ -- [2]
		parentContinent = 0,
		height = 27149.795290881,
		width = 40741.175327834,
		xOffset = 14407.1086092051,
		yOffset = 290.3230897653046,
		zoneData = {
			Alterac = {
				height = 1866.673586850316,
				width = 2800.000436369314,
				xOffset = 17388.63313899802,
				yOffset = 9676.382605411302,
			},
			Arathi = {
				height = 2400.0092446309,
				width = 3599.999380663208,
				xOffset = 19038.63328411639,
				yOffset = 11309.72201070757,
			},
			Badlands = {
				height = 1658.340965090961,
				width = 2487.498490907989,
				xOffset = 20251.1337564772,
				yOffset = 17065.99404487956,
			},
			BlastedLands = {
				height = 2233.343415116865,
				width = 3349.999381676505,
				xOffset = 19413.63362865575,
				yOffset = 21743.09582955139,
			},
			BurningSteppes = {
				height = 1952.091972408385,
				width = 2929.16694293186,
				xOffset = 18438.633261567,
				yOffset = 18207.66513379744,
			},
			DeadwindPass = {
				height = 1666.673818905317,
				width = 2499.999888210889,
				xOffset = 19005.29993968603,
				yOffset = 21043.0932328648,
			},
			DunMorogh = {
				height = 3283.345779814337,
				width = 4924.998791911572,
				xOffset = 16369.8840376619,
				yOffset = 15053.48695195484,
			},
			Duskwood = {
				height = 1800.007653419076,
				width = 2699.999669551933,
				xOffset = 17338.63354148773,
				yOffset = 20893.09259181909,
			},
			EasternPlaguelands = {
				height = 2581.259876367526,
				width = 3870.832396995169,
				xOffset = 20357.38356562001,
				yOffset = 7376.373692430854,
			},
			Elwynn = {
				height = 2314.591970284716,
				width = 3470.831971412848,
				xOffset = 16636.55099386465,
				yOffset = 19116.0027890283,
			},
			EversongWoods = {
				height = 3283.346366715794,
				width = 4924.998483501337,
				xOffset = 20259.46725884782,
				yOffset = 2534.687567863296,
			},
			Ghostlands = {
				height = 2200.008945183733,
				width = 3300.002855743766,
				xOffset = 21055.29786070095,
				yOffset = 5309.698546426793,
			},
			Hilsbrad = {
				height = 2133.341840477916,
				width = 3200.000391416799,
				xOffset = 17105.29968281043,
				yOffset = 10776.38652289269,
			},
			Hinterlands = {
				height = 2566.676323518885,
				width = 3849.998492380244,
				xOffset = 19746.96704279287,
				yOffset = 9709.715966757984,
			},
			Ironforge = {
				height = 527.6056771582851,
				width = 790.6252518322632,
				xOffset = 18885.55815177769,
				yOffset = 15745.64795436116,
			},
			LochModan = {
				height = 1839.590356444166,
				width = 2758.33360594204,
				xOffset = 20165.71623436714,
				yOffset = 15663.90573348468,
			},
			Redridge = {
				height = 1447.922213393415,
				width = 2170.833229570681,
				xOffset = 19742.79960560691,
				yOffset = 19751.42209395218,
			},
			SearingGorge = {
				height = 1487.505203229038,
				width = 2231.250200533406,
				xOffset = 18494.88325409831,
				yOffset = 17276.41231120941,
			},
			SilvermoonCity = {
				height = 806.7751969249011,
				width = 1211.458551923779,
				xOffset = 22172.71573747824,
				yOffset = 3422.647395021269,
			},
			Silverpine = {
				height = 2800.011187621704,
				width = 4200.000573479695,
				xOffset = 14721.96646274185,
				yOffset = 9509.714741967448,
			},
			Stormwind = {
				height = 896.3598437319051,
				width = 1344.270269919159,
				xOffset = 16790.9956264139,
				yOffset = 19455.27053790398,
			},
			Stranglethorn = {
				height = 4254.18312444072,
				width = 6381.248484543122,
				xOffset = 15951.13375783437,
				yOffset = 22345.18258706305,
			},
			Sunwell = {
				height = 2218.756638064149,
				width = 3327.084777999942,
				xOffset = 21074.0484502027,
				yOffset = 7.595267688679496,
			},
			SwampOfSorrows = {
				height = 1529.173695058727,
				width = 2293.753807610138,
				xOffset = 20394.88183258176,
				yOffset = 20797.25913588854,
			},
			Tirisfal = {
				height = 3012.510490816506,
				width = 4518.749381850256,
				xOffset = 15138.63417865412,
				yOffset = 7338.874503644808,
			},
			Undercity = {
				height = 640.1067253394195,
				width = 959.3752013853186,
				xOffset = 17298.77399735696,
				yOffset = 9298.435338905521,
			},
			WesternPlaguelands = {
				height = 2866.677213191588,
				width = 4299.998717025251,
				xOffset = 17755.30067544475,
				yOffset = 7809.708745090687,
			},
			Westfall = {
				height = 2333.342039971409,
				width = 3500.001170481545,
				xOffset = 15155.29922254704,
				yOffset = 20576.42557120998,
			},
			Wetlands = {
				height = 2756.260286844545,
				width = 4135.414389381328,
				xOffset = 18561.55091405621,
				yOffset = 13324.31339403164,
			},
		},
	},
	-- Outland
	{ -- [3]
		parentContinent = 3,
		height = 11642.355227091,
		width = 17463.987300595,
		zoneData = {
			BladesEdgeMountains = {
				height = 3616.553511321226,
				width = 5424.972055480694,
				xOffset = 4150.184214583454,
				yOffset = 1412.98225932006,
			},
			Hellfire = {
				height = 3443.642450656037,
				width = 5164.556104714847,
				xOffset = 7456.417230912641,
				yOffset = 4339.973750274888,
			},
			Nagrand = {
				height = 3683.218538167106,
				width = 5524.971495006054,
				xOffset = 2700.192018521809,
				yOffset = 5779.511974812862,
			},
			Netherstorm = {
				height = 3716.550608724641,
				width = 5574.970083688359,
				xOffset = 7512.667416095402,
				yOffset = 365.0979827402549,
			},
			ShadowmoonValley = {
				height = 3666.552070430093,
				width = 5499.971770418525,
				xOffset = 8770.993458280615,
				yOffset = 7769.033264592288,
			},
			ShattrathCity = {
				height = 870.8059516186869,
				width = 1306.242821388422,
				xOffset = 6860.744740098593,
				yOffset = 7295.086120456203,
			},
			TerokkarForest = {
				height = 3599.887783533737,
				width = 5399.971351016305,
				xOffset = 5912.675516998205,
				yOffset = 6821.146319031154,
			},
			Zangarmarsh = {
				height = 3351.978710181591,
				width = 5027.057650868489,
				xOffset = 3521.020638264577,
				yOffset = 3885.821278366336,
			},
		},
	},
}

--- WotLK Adjustments
do
	maps[0].height = 31809.64859753034;
	maps[0].width = 47714.27770954026;
	
	maps[1].xOffset = -8590.409362625034;
	maps[1].yOffset = 5628.694276155668;
	
	maps[2].xOffset = 18542.31268111796;
	maps[2].yOffset = 3585.574682467752;
	maps[2].zoneData.Stormwind = {
		height = 1158.33686894901,
		width = 1737.498058940429,
		xOffset = 16449.05164642256,
		yOffset = 19172.25350774846,
	}
	maps[2].zoneData.EasternPlaguelands = {
		height = 2687.510360231216,
		width = 4031.249051993366,
		xOffset = 20459.46801235962,
		yOffset = 7472.207045901617,
	}
	
	maps[4] = {
		parentContinent = 0,
		height = 11834.31067391958,
		width = 17751.3936186856,
		xOffset = 16020.94093549576,
		yOffset = 454.2464807713226,
		zoneData = {
			BoreanTundra = {
				height = 3843.765503862232,
				width = 5764.58206497758,
				xOffset = 646.3186767730767,
				yOffset = 5695.480016983896,
			},
			CrystalsongForest = {
				height = 1814.590053385046,
				width = 2722.916164555434,
				xOffset = 7773.400227973558,
				yOffset = 4091.307437548815,
			},
			Dalaran = {
				height = 553.3419356683534,
				width = 830.014625253355,
				xOffset = 8164.640128758279,
				yOffset = 4526.722218200071,
			},
			Dragonblight = {
				height = 3739.597759999098,
				width = 5608.331259502691,
				xOffset = 5590.067753073641,
				yOffset = 5018.394106536425,
			},
			GrizzlyHills = {
				height = 3500.013349296343,
				width = 5249.9986179934,
				xOffset = 10327.56614428777,
				yOffset = 5076.727864214266,
			},
			HowlingFjord = {
				height = 4031.266275060274,
				width = 6045.831339550668,
				xOffset = 10615.0658552538,
				yOffset = 7476.736868262738,
			},
			IcecrownGlacier = {
				height = 4181.266116737856,
				width = 6270.831861693458,
				xOffset = 3304.65133149085,
				yOffset = 1166.296192718834,
			},
			LakeWintergrasp = {
				height = 1983.342901980711,
				width = 2974.999377667768,
				xOffset = 4887.984320612982,
				yOffset = 4876.725348039468,
			},
			SholazarBasin = {
				height = 2904.177559586215,
				width = 4356.248328680455,
				xOffset = 2287.985279107324,
				yOffset = 3305.887993444818,
			},
			TheStormPeaks = {
				height = 4741.684940421732,
				width = 7112.498205872217,
				xOffset = 7375.483315518691,
				yOffset = 395.4596828327046,
			},
			ZulDrak = {
				height = 3329.179510740043,
				width = 4993.747919923504,
				xOffset = 9817.150055203074,
				yOffset = 2924.636381254688,
			},
		},
	}
end


_G.GVE.GuildMapData = maps

