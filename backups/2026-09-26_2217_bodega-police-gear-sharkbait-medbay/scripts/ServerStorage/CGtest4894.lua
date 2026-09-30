-- CaveGen -- Perlas ng Dagat, second cut.
--
-- What changed, and why:
--   * Every air chamber is now a POCKET, not a junction. It has exactly one
--     opening: a single vertical shaft through the middle of its floor. You swim
--     up into it, you breathe, you drop back down the same hole. Nothing routes
--     through a chamber any more -- all of that moved to the underwater junctions,
--     which is what makes finding a pocket feel like finding something.
--   * Every chamber is a different room. Twelve archetypes, one each, plus a
--     per-chamber seed that moves every lobe, so no two share a silhouette. Each
--     one has a real flat floor with standing room, because each one has to hold
--     signage, shells and a player posing for a screenshot.
--   * 100 tunnels, 6 deep runs, 12 chambers, across an expanded footprint.
--
-- The deep run lengths are not eyeballed. Each is solved against the TAUT line a
-- perfect swimmer could hold inside the bore -- not the centre line we carve --
-- so the lung gates cannot be beaten by cutting corners:
--     swim 8.4 studs/s, breath 1/s, lung caps 45 / 60 / 75 / 90
--     tier 1 needs 1 Lung Coral, tier 2 needs 2, tier 3 needs 3
--
-- CHAMBER INVARIANT: exactly one tunnel may ever terminate at an air chamber, and
-- no other passage may pass within CHAMBER_MARGIN of its sphere or shaft. The
-- layout generator enforces both, and CaveAudit re-checks them against the live
-- terrain. Do not hand-add a tunnel to a chamber.

local M = {}
local T = workspace.Terrain

local AIR_FLOOR_THICKNESS = 4        -- rock slab under the chamber floor
local AIR_ENTRY_DEPTH = 12           -- how far the shaft cuts down through it
local AIR_ENTRY_TOP = 2              -- how far the water surfaces above the floor
local AIR_ENTRY_RADIUS = 3.5
local AIR_TUNNEL_NECK_LENGTH = 8     -- extra drop to where tunnels actually meet
local AIR_ENDPOINT_NO_WOBBLE = 4
local NECK_DROP = AIR_ENTRY_DEPTH + AIR_TUNNEL_NECK_LENGTH

local MIN_WATER_RADIUS = 6
local SHELL_PAD = 4.5

M.BasementTop = -34

local function hash(x, y, z)
	return math.noise(x * 0.045, y * 0.045, z * 0.045)
end

-- 72 nodes: 12 air chambers, 34 water junctions, 14 dead ends, 6 entrances, 6 vaults
M.Nodes = {
	-- AIR CHAMBERS -- one bottom shaft each, one archetype each
	Hub = {x = -40, y = -46, z = 150, r = 16, archetype = "cathedral", flavor = "a vaulted nave with aisle alcoves", number = 1, entryR = 4.5, kind = "hub", label = "Gitnang Yungib"},
	RestB = {x = 215, y = -46, z = 70, r = 14, archetype = "gallery", flavor = "one long hall, end to end", number = 2, kind = "rest", label = "Ugat-Puno"},
	RestA = {x = -190, y = -50, z = 320, r = 13, archetype = "bubbles", flavor = "sea foam frozen into rock", number = 3, kind = "rest", label = "Bahay-Hangin"},
	RestC = {x = -285, y = -62, z = -30, r = 12, archetype = "crescent", flavor = "a curved hall round a rock horn", number = 4, kind = "rest", label = "Malamig na Silid"},
	RestD = {x = 70, y = -68, z = 330, r = 12, archetype = "chimney", flavor = "a throat opening into a high bell", number = 5, kind = "rest", label = "Huling Hininga"},
	RestE = {x = -120, y = -86, z = 195, r = 11, archetype = "terrace", flavor = "three shelves like a staircase", number = 6, kind = "rest", label = "Lihim na Hininga"},
	RestF = {x = 250, y = -94, z = 400, r = 12, archetype = "spine", flavor = "twin naves either side of a ridge", number = 7, kind = "rest", label = "Hatinggabi"},
	RestG = {x = -345, y = -106, z = 265, r = 13, archetype = "drum", flavor = "wide, round and low", number = 8, kind = "rest", label = "Bato-Kristal"},
	RestH = {x = 125, y = -120, z = 120, r = 11, archetype = "fork", flavor = "two bulbs pinched at the waist", number = 9, kind = "rest", label = "Sanctuario ng Dagat"},
	RestI = {x = -70, y = -142, z = 430, r = 12, archetype = "barrel", flavor = "a barrel vault running the long way", number = 10, kind = "rest", label = "Buntong-Hininga"},
	RestJ = {x = 340, y = -152, z = 230, r = 11, archetype = "star", flavor = "a core with six finger alcoves", number = 11, kind = "rest", label = "Tahimik na Silid"},
	Treasure = {x = -155, y = -178, z = 470, r = 16, archetype = "well", flavor = "a ring room round a raised island", number = 12, entryR = 4.0, kind = "treasure", label = "Perlas Hollow"},

	-- SURFACE SINKS
	EntranceWest = {x = -320, y = -36, z = 240, r = 7, seabedH = -18.6, kind = "entrance", label = "West Sink"},
	EntranceEast = {x = 260, y = -36, z = 195, r = 7, seabedH = -18.7, kind = "entrance", label = "East Sink"},
	EntranceSouth = {x = 95, y = -32, z = 360, r = 7, seabedH = -12.1, kind = "entrance", label = "South Sink"},
	EntranceNorth = {x = -400, y = -30, z = -260, r = 7, seabedH = -10.0, kind = "entrance", label = "Hilaga Trench"},
	EntranceDeepS = {x = -200, y = -32, z = 560, r = 7, seabedH = -11.9, kind = "entrance", label = "Timog Blowhole"},
	EntranceFarEast = {x = 340, y = -36, z = 420, r = 7, seabedH = -18.0, kind = "entrance", label = "Far East Blowhole"},

	-- WATER JUNCTIONS -- all routing happens here, never inside a chamber
	J1 = {x = 13, y = -114, z = 173, r = 8, kind = "junction", label = "Sangang Bato"},
	J2 = {x = 231, y = -112, z = 126, r = 8, kind = "junction", label = "Agos Pahalang"},
	J3 = {x = -224, y = -115, z = 367, r = 8, kind = "junction", label = "Bukana ng Dilim"},
	J4 = {x = -343, y = -126, z = -28, r = 8, kind = "junction", label = "Lubog na Sangga"},
	J5 = {x = 32, y = -132, z = 286, r = 8, kind = "junction", label = "Tahi ng Bato"},
	J6 = {x = -109, y = -149, z = 138, r = 8, kind = "junction", label = "Palikong Agos"},
	J7 = {x = 298, y = -158, z = 368, r = 8, kind = "junction", label = "Bulong ng Tubig"},
	J8 = {x = -309, y = -171, z = 310, r = 8, kind = "junction", label = "Gitnang Sanga"},
	J9 = {x = 106, y = -183, z = 175, r = 8, kind = "junction", label = "Silong ng Bato"},
	J10 = {x = -104, y = -188, z = 442, r = 8, kind = "junction", label = "Baluktot na Daan"},
	J11 = {x = 291, y = -215, z = 199, r = 8, kind = "junction", label = "Tagpuan ng Agos"},
	J12 = {x = -123, y = -246, z = 422, r = 8, kind = "junction", label = "Hukay na Sanga"},
	J13 = {x = -194, y = -213, z = -30, r = 7.4, kind = "junction", label = "Daloy ng Lamig"},
	J14 = {x = -141, y = -64, z = 426, r = 7, kind = "junction", label = "Ugat ng Bato"},
	J15 = {x = -231, y = -71, z = 413, r = 8.6, kind = "junction", label = "Pusod ng Tubig"},
	J16 = {x = -383, y = -232, z = 321, r = 8.6, kind = "junction", label = "Gilid ng Kadiliman"},
	J17 = {x = 210, y = -91, z = -111, r = 8.7, kind = "junction", label = "Tawid na Bato"},
	J18 = {x = -8, y = -55, z = -199, r = 8.1, kind = "junction", label = "Bitak ng Lupa"},
	J19 = {x = -241, y = -202, z = 136, r = 7.5, kind = "junction", label = "Sanga ng Buhangin"},
	J20 = {x = -209, y = -182, z = 26, r = 6.8, kind = "junction", label = "Lubak na Daanan"},
	J21 = {x = -11, y = -60, z = -126, r = 6.6, kind = "junction", label = "Hiwa ng Bato"},
	J22 = {x = -185, y = -157, z = 202, r = 9, kind = "junction", label = "Pook ng Alon"},
	J23 = {x = 144, y = -183, z = 1, r = 6.8, kind = "junction", label = "Pahinga ng Agos"},
	J24 = {x = -337, y = -76, z = 75, r = 8.6, kind = "junction", label = "Sulok ng Dilim"},
	J25 = {x = -364, y = -107, z = -110, r = 6.7, kind = "junction", label = "Kanlungan ng Bato"},
	J26 = {x = 269, y = -186, z = 295, r = 8.6, kind = "junction", label = "Pinto ng Lalim"},
	J27 = {x = -114, y = -182, z = -180, r = 7.9, kind = "junction", label = "Landas ng Tubig"},
	J28 = {x = 233, y = -193, z = 0, r = 6.7, kind = "junction", label = "Sapa sa Ilalim"},
	J29 = {x = 380, y = -106, z = 107, r = 8.8, kind = "junction", label = "Puwang ng Bato"},
	J30 = {x = 56, y = -120, z = 415, r = 8.5, kind = "junction", label = "Yungib na Munti"},
	J31 = {x = 24, y = -213, z = 115, r = 8.5, kind = "junction", label = "Bukal ng Lamig"},
	J32 = {x = 149, y = -196, z = 218, r = 8, kind = "junction", label = "Dulo ng Agos"},
	J33 = {x = 237, y = -227, z = -151, r = 7.5, kind = "junction", label = "Hantungan ng Bato"},
	J34 = {x = -220, y = -101, z = -151, r = 7.3, kind = "junction", label = "Tagong Sanga"},

	-- DEAD ENDS -- drowning traps, and the only tunnels a cave-in may seal
	DeadEnd1 = {x = 187, y = -128, z = 405, r = 6.7, kind = "deadend", label = "Hukay ng Kadiliman"},
	DeadEnd2 = {x = 289, y = -129, z = -143, r = 6.2, kind = "deadend", label = "Bulag na Lungga"},
	DeadEnd3 = {x = 232, y = -246, z = 222, r = 6.5, kind = "deadend", label = "Sump-Lock Pit"},
	DeadEnd4 = {x = 337, y = -213, z = 261, r = 7.1, kind = "deadend", label = "Coralline Pocket"},
	DeadEnd5 = {x = 242, y = -125, z = 244, r = 6.9, kind = "deadend", label = "Cold Silt Trap"},
	DeadEnd6 = {x = -284, y = -78, z = 484, r = 7.5, kind = "deadend", label = "Abyssal Squeeze"},
	DeadEnd7 = {x = -426, y = -177, z = -44, r = 6.1, kind = "deadend", label = "Stalactite Blind"},
	DeadEnd8 = {x = -310, y = -223, z = 356, r = 6.1, kind = "deadend", label = "Choke Chimney"},
	DeadEnd9 = {x = -312, y = -113, z = 386, r = 6.6, kind = "deadend", label = "Black Mud Siphon"},
	DeadEnd10 = {x = -302, y = -74, z = -229, r = 7.3, kind = "deadend", label = "No-Air Vault"},
	DeadEnd11 = {x = -325, y = -209, z = 184, r = 6.8, kind = "deadend", label = "Silt Curtain"},
	DeadEnd12 = {x = 196, y = -233, z = 173, r = 6.7, kind = "deadend", label = "Bone Crevice"},
	DeadEnd13 = {x = -168, y = -207, z = -108, r = 6.3, kind = "deadend", label = "Whisper Sump"},
	DeadEnd14 = {x = 321, y = -151, z = 139, r = 6.1, kind = "deadend", label = "Last Breath Niche"},

	-- DEEP VAULTS -- reachable only down a lung-gated run
	SilidAgosLihim = {x = -99, y = -149, z = -6, r = 9, kind = "vault", label = "Silid ng Agos"},
	SilidBituinBaha = {x = 401, y = -139, z = 94, r = 9, kind = "vault", label = "Silid ng Bituin"},
	SilidSiwangLamig = {x = -344, y = -182, z = 245, r = 10, kind = "vault", label = "Silid ng Lamig"},
	SilidDaluyongItim = {x = 221, y = -192, z = 409, r = 10, kind = "vault", label = "Silid ng Daluyong"},
	SilidLalimMundo = {x = -401, y = -248, z = 278, r = 12, kind = "vault", label = "Silid ng Lalim"},
	SilidHukayLangit = {x = 252, y = -248, z = 446, r = 11, kind = "vault", label = "Silid ng Kalangitan"},
}

-- 100 TUNNELS. Exactly one of these terminates at each air chamber.
M.Tunnels = {
	{"J1", "Hub", 4.5},  -- 1  THE throat of Hub
	{"J2", "RestB", 4.5},  -- 2  THE throat of RestB
	{"J3", "RestA", 4},  -- 3  THE throat of RestA
	{"J4", "RestC", 4},  -- 4  THE throat of RestC
	{"J5", "RestD", 4},  -- 5  THE throat of RestD
	{"J6", "RestE", 4},  -- 6  THE throat of RestE
	{"J7", "RestF", 4},  -- 7  THE throat of RestF
	{"J8", "RestG", 4},  -- 8  THE throat of RestG
	{"J9", "RestH", 4},  -- 9  THE throat of RestH
	{"J12", "RestI", 4},  -- 10  THE throat of RestI
	{"J11", "RestJ", 4},  -- 11  THE throat of RestJ
	{"J12", "Treasure", 4.5},  -- 12  THE throat of Treasure
	{"J7", "DeadEnd1", 3.3},  -- 13  dead end
	{"J17", "DeadEnd2", 3.3},  -- 14  dead end
	{"J32", "DeadEnd3", 3.4},  -- 15  dead end
	{"J7", "DeadEnd4", 3},  -- 16  dead end
	{"J2", "DeadEnd5", 3.1},  -- 17  dead end
	{"J15", "DeadEnd6", 3.4},  -- 18  dead end
	{"J4", "DeadEnd7", 3.5},  -- 19  dead end
	{"J16", "DeadEnd8", 3.5},  -- 20  dead end
	{"J15", "DeadEnd9", 3},  -- 21  dead end
	{"J34", "DeadEnd10", 3.5},  -- 22  dead end
	{"J19", "DeadEnd11", 3.2},  -- 23  dead end
	{"J32", "DeadEnd12", 3.2},  -- 24  dead end
	{"J13", "DeadEnd13", 3.1},  -- 25  dead end
	{"J2", "DeadEnd14", 3},  -- 26  dead end
	{"EntranceWest", "J8", 5.2},  -- 27  surface
	{"EntranceEast", "J2", 5.2},  -- 28  surface
	{"EntranceSouth", "J30", 5.2},  -- 29  surface
	{"EntranceNorth", "J25", 5.2},  -- 30  surface
	{"EntranceDeepS", "J14", 5.2},  -- 31  surface
	{"EntranceFarEast", "J7", 5.2},  -- 32  surface
	{"J9", "J32", 4.2},  -- 33
	{"J3", "J15", 4.2},  -- 34
	{"J10", "J12", 4.2},  -- 35
	{"J13", "J20", 4.2},  -- 36
	{"J18", "J21", 4.2},  -- 37
	{"J7", "J26", 4.2},  -- 38
	{"J4", "J25", 4.2},  -- 39
	{"J23", "J28", 4.2},  -- 40
	{"J14", "J15", 4.2},  -- 41
	{"J8", "J16", 4.2},  -- 42
	{"J19", "J22", 4.2},  -- 43
	{"J6", "J22", 4.2},  -- 44
	{"J11", "J26", 4.2},  -- 45
	{"J9", "J31", 4.2},  -- 46
	{"J4", "J24", 4.2},  -- 47
	{"J1", "J31", 4.2},  -- 48
	{"J1", "J5", 4.2},  -- 49
	{"J19", "J20", 4.2},  -- 50
	{"J3", "J8", 4.2},  -- 51
	{"J10", "J14", 4.2},  -- 52
	{"J1", "J6", 4.2},  -- 53
	{"J5", "J30", 4.2},  -- 54
	{"J27", "J34", 4.2},  -- 55
	{"J2", "J11", 4.2},  -- 56
	{"J26", "J32", 4.2},  -- 57
	{"J17", "J33", 4.2},  -- 58
	{"J2", "J28", 4.2},  -- 59
	{"J25", "J34", 4.2},  -- 60
	{"J2", "J29", 4.2},  -- 61
	{"J17", "J28", 4.2},  -- 62
	{"J4", "J20", 4.2},  -- 63
	{"J8", "J22", 4.2},  -- 64
	{"J18", "J27", 4.2},  -- 65
	{"J3", "J14", 4.2},  -- 66
	{"J1", "J9", 4.2},  -- 67
	{"J6", "J19", 4.2},  -- 68
	{"J5", "J9", 4.2},  -- 69
	{"J11", "J32", 4.2},  -- 70
	{"J6", "J31", 4.2},  -- 71
	{"J5", "J32", 4.2},  -- 72
	{"J6", "J20", 4.2},  -- 73
	{"J28", "J33", 4.2},  -- 74
	{"J3", "J10", 4.2},  -- 75
	{"J17", "J23", 4.2},  -- 76
	{"J31", "J32", 4.2},  -- 77
	{"J8", "J15", 4.2},  -- 78
	{"J13", "J34", 4.2},  -- 79
	{"J11", "J29", 4.2},  -- 80
	{"J23", "J31", 4.2},  -- 81
	{"J21", "J27", 4.2},  -- 82
	{"J19", "J24", 4.2},  -- 83
	{"J4", "J13", 4.2},  -- 84
	{"J13", "J27", 4.2},  -- 85
	{"J13", "J19", 4.2},  -- 86
	{"J20", "J24", 4.2},  -- 87
	{"J3", "J12", 4.2},  -- 88
	{"J3", "J22", 4.2},  -- 89
	{"J10", "J15", 4.2},  -- 90
	{"J4", "J34", 4.2},  -- 91
	{"J9", "J23", 4.2},  -- 92
	{"J7", "J11", 4.2},  -- 93
	{"J20", "J22", 4.2},  -- 94
	{"J12", "J14", 4.2},  -- 95
	{"J23", "J33", 4.2},  -- 96
	{"J9", "J11", 4.2},  -- 97
	{"J8", "J19", 4.2},  -- 98
	{"J5", "J31", 4.2},  -- 99
	{"J24", "J25", 4.2},  -- 100
}

-- 6 DEEP RUNS. `best` is the taut-line length the tier was solved against;
-- `centre` is the wobbly line we actually carve. The gap between them is
-- exactly the corner-cutting a good swimmer would otherwise get for free.
M.DeepRuns = {
	{
		key = "AgosLihim",
		label = "Deep Level 1: Agos Lihim",
		from = "RestC",
		endNode = "SilidAgosLihim",
		level = 1,
		tier = 1,
		style = "winding",
		radius = 1.5,
		best = 212.9,
		centre = 221.4,
		path = {
			Vector3.new(-253, -104, -50),
			Vector3.new(-220, -112, -37),
			Vector3.new(-188, -120, -51),
			Vector3.new(-163, -125, -29),
			Vector3.new(-128, -136, -30),
			Vector3.new(-99, -149, -6),
		},
	},
	{
		key = "BituinBaha",
		label = "Deep Level 2: Bituin Baha",
		from = "RestB",
		endNode = "SilidBituinBaha",
		level = 2,
		tier = 1,
		style = "winding",
		radius = 1.5,
		best = 215.6,
		centre = 225.8,
		path = {
			Vector3.new(245, -91, 64),
			Vector3.new(278, -103, 85),
			Vector3.new(312, -110, 66),
			Vector3.new(340, -118, 83),
			Vector3.new(376, -127, 67),
			Vector3.new(401, -139, 94),
		},
	},
	{
		key = "SiwangLamig",
		label = "Deep Level 3: Siwang ng Lamig",
		from = "RestA",
		endNode = "SilidSiwangLamig",
		level = 3,
		tier = 2,
		style = "zigzag",
		radius = 1.5,
		best = 271.1,
		centre = 290.8,
		path = {
			Vector3.new(-227, -95, 330),
			Vector3.new(-226, -107, 296),
			Vector3.new(-262, -122, 293),
			Vector3.new(-257, -139, 255),
			Vector3.new(-297, -151, 267),
			Vector3.new(-308, -166, 225),
			Vector3.new(-344, -182, 245),
		},
	},
	{
		key = "DaluyongItim",
		label = "Deep Level 4: Daluyong Itim",
		from = "RestD",
		endNode = "SilidDaluyongItim",
		level = 4,
		tier = 2,
		style = "zigzag",
		radius = 1.5,
		best = 272.6,
		centre = 293.2,
		path = {
			Vector3.new(101, -115, 303),
			Vector3.new(111, -132, 345),
			Vector3.new(154, -145, 338),
			Vector3.new(149, -159, 371),
			Vector3.new(189, -168, 369),
			Vector3.new(181, -175, 404),
			Vector3.new(221, -192, 409),
		},
	},
	{
		key = "LalimMundo",
		label = "Deep Level 5: Lalim ng Mundo",
		from = "RestG",
		endNode = "SilidLalimMundo",
		level = 5,
		tier = 3,
		style = "spiral",
		radius = 1.5,
		best = 345.3,
		centre = 361.7,
		path = {
			Vector3.new(-370, -150, 297),
			Vector3.new(-413, -170, 294),
			Vector3.new(-423, -181, 252),
			Vector3.new(-396, -195, 219),
			Vector3.new(-351, -209, 220),
			Vector3.new(-332, -223, 260),
			Vector3.new(-366, -235, 293),
			Vector3.new(-401, -248, 278),
		},
	},
	{
		key = "HukayLangit",
		label = "Deep Level 6: Hukay ng Kalangitan",
		from = "RestF",
		endNode = "SilidHukayLangit",
		level = 6,
		tier = 3,
		style = "corkscrew",
		radius = 1.5,
		best = 338.7,
		centre = 376.5,
		path = {
			Vector3.new(264, -139, 430),
			Vector3.new(235, -151, 426),
			Vector3.new(256, -163, 401),
			Vector3.new(269, -173, 432),
			Vector3.new(238, -183, 427),
			Vector3.new(254, -192, 405),
			Vector3.new(273, -202, 435),
			Vector3.new(245, -211, 446),
			Vector3.new(242, -226, 411),
			Vector3.new(274, -236, 419),
			Vector3.new(252, -248, 446),
		},
	},
}

-- Cave-in candidates. Dead ends and deep runs ONLY. A chamber's single throat
-- is never in here: sealing it would strand a diver inside, or delete an air
-- pocket from the map for a whole day.
M.Sealable = {
	{kind = "tunnel", index = 13, label = "the crawl into Hukay ng Kadiliman", beyond = {"DeadEnd1"}},
	{kind = "tunnel", index = 14, label = "the crawl into Bulag na Lungga", beyond = {"DeadEnd2"}},
	{kind = "tunnel", index = 15, label = "the crawl into Sump-Lock Pit", beyond = {"DeadEnd3"}},
	{kind = "tunnel", index = 16, label = "the crawl into Coralline Pocket", beyond = {"DeadEnd4"}},
	{kind = "tunnel", index = 17, label = "the crawl into Cold Silt Trap", beyond = {"DeadEnd5"}},
	{kind = "tunnel", index = 18, label = "the crawl into Abyssal Squeeze", beyond = {"DeadEnd6"}},
	{kind = "tunnel", index = 19, label = "the crawl into Stalactite Blind", beyond = {"DeadEnd7"}},
	{kind = "tunnel", index = 20, label = "the crawl into Choke Chimney", beyond = {"DeadEnd8"}},
	{kind = "tunnel", index = 21, label = "the crawl into Black Mud Siphon", beyond = {"DeadEnd9"}},
	{kind = "tunnel", index = 22, label = "the crawl into No-Air Vault", beyond = {"DeadEnd10"}},
	{kind = "tunnel", index = 23, label = "the crawl into Silt Curtain", beyond = {"DeadEnd11"}},
	{kind = "tunnel", index = 24, label = "the crawl into Bone Crevice", beyond = {"DeadEnd12"}},
	{kind = "tunnel", index = 25, label = "the crawl into Whisper Sump", beyond = {"DeadEnd13"}},
	{kind = "tunnel", index = 26, label = "the crawl into Last Breath Niche", beyond = {"DeadEnd14"}},
	{kind = "run", index = 1, label = "Agos Lihim", beyond = {"SilidAgosLihim"}},
	{kind = "run", index = 2, label = "Bituin Baha", beyond = {"SilidBituinBaha"}},
	{kind = "run", index = 3, label = "Siwang ng Lamig", beyond = {"SilidSiwangLamig"}},
	{kind = "run", index = 4, label = "Daluyong Itim", beyond = {"SilidDaluyongItim"}},
	{kind = "run", index = 5, label = "Lalim ng Mundo", beyond = {"SilidLalimMundo"}},
	{kind = "run", index = 6, label = "Hukay ng Kalangitan", beyond = {"SilidHukayLangit"}},
}

-- The first cut of the cave left holes where the old entrances and the tops of
-- the three shallowest old chambers used to be. Basement rock only pours below
-- BasementTop, so those would survive a rebuild as orphan pits in the seabed.
-- This plugs them once, before anything new is carved.
M.LegacyVoids = {
	{x = -300, y = -46, z = 220, r = 22},
	{x = 250, y = -44, z = 180, r = 22},
	{x = 80, y = -44, z = 350, r = 22},
	{x = -50, y = -42, z = -150, r = 22},
	{x = -40, y = -46, z = 150, r = 26},
	{x = -170, y = -42, z = 300, r = 22},
	{x = 190, y = -40, z = 60, r = 22},
}

function M.FillLegacyVoids()
	for _, v in ipairs(M.LegacyVoids) do
		T:FillBall(Vector3.new(v.x, v.y, v.z), v.r, Enum.Material.Rock)
		T:FillBlock(
			CFrame.new(v.x, (v.y - 6 + -8) / 2, v.z),
			Vector3.new(v.r * 2, math.abs(v.y - 6 - -8), v.r * 2),
			Enum.Material.Rock
		)
	end
	return string.format("Plugged %d leftover voids from the first cut.", #M.LegacyVoids)
end

M.AirKinds = { hub = true, rest = true, treasure = true }

-- Tunnels never meet an air chamber at its centre. They meet it at the NECK: a
-- point below the chamber floor, at the bottom of the single vertical shaft that
-- is the chamber's only opening. Every route in or out of a pocket passes through
-- that one hole, which is the whole point of the redesign.
function M.GetNodeConnectPos(nodeKey)
	local n = M.Nodes[nodeKey]
	if not n then return Vector3.zero end
	if M.AirKinds[n.kind] then
		return Vector3.new(n.x, n.y - n.r - NECK_DROP, n.z)
	end
	return Vector3.new(n.x, n.y, n.z)
end

function M.ChamberFloorY(n)
	return n.y - n.r + AIR_FLOOR_THICKNESS
end

-- ============================================================================
-- CHAMBER SHAPES
-- ============================================================================
-- A dozen pockets carved from the same blob primitive would all read as the same
-- lumpy sphere, and a player who has seen one would have seen them all. So every
-- chamber gets its own archetype -- a cathedral is not a gallery is not a
-- corkscrew well -- and inside the archetype a per-chamber seed moves every lobe,
-- so even the two rooms that share a family do not share a silhouette.
--
-- Two rules hold across all twelve, because the room has a job to do:
--   * a flat rock floor with real standing room, so signage and shells have
--     somewhere to sit and a player has somewhere to stand for the photo;
--   * the middle of that floor stays clear, because the single entry shaft
--     surfaces there. Pillars, islands and terraces are always pushed off-centre.

local function lcg(seed)
	local state = seed % 2147483647
	if state <= 0 then state += 2147483646 end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function chamberSeed(key)
	local s = 7
	for i = 1, #key do
		s = (s * 31 + key:byte(i)) % 100003
	end
	return s
end

local SHAFT_KEEPOUT = 6   -- nothing solid may be placed within this of the shaft

-- Returns the air blobs that hollow the room out, and the rock solids that are
-- put back afterwards to make pillars, spines, islands and terrace steps.
function M.ChamberShape(key)
	local n = M.Nodes[key]
	local R = n.r
	local floorY = M.ChamberFloorY(n)
	local rnd = lcg(chamberSeed(key))
	local arch = n.archetype or "bubbles"
	local blobs, solids = {}, {}

	local function air(dx, dy, dz, r)
		blobs[#blobs + 1] = { p = Vector3.new(n.x + dx, floorY + dy, n.z + dz), r = r }
	end
	local function rock(dx, dy, dz, sx, sy, sz)
		-- never let a solid swallow the entry shaft
		if math.sqrt(dx * dx + dz * dz) - math.max(sx, sz) * 0.5 < SHAFT_KEEPOUT then
			return
		end
		solids[#solids + 1] = {
			cf = CFrame.new(n.x + dx, floorY + dy, n.z + dz),
			size = Vector3.new(sx, sy, sz),
		}
	end
	local function jitter(a)
		return (rnd() - 0.5) * a
	end

	local spin = rnd() * math.pi * 2

	if arch == "cathedral" then
		-- a high vaulted nave over a broad floor, with aisle alcoves down the sides
		air(0, R * 0.55, 0, R * 0.78)
		air(jitter(R * 0.1), R * 1.15, jitter(R * 0.1), R * 0.62)
		air(jitter(R * 0.12), R * 1.62, jitter(R * 0.12), R * 0.44)
		for i = 1, 6 do
			local a = spin + i * math.pi / 3
			air(math.cos(a) * R * 0.74, R * 0.42 + jitter(R * 0.18), math.sin(a) * R * 0.74,
				R * (0.36 + rnd() * 0.12))
		end

	elseif arch == "gallery" then
		-- a long low hall: you can see the whole room end to end
		local a = spin
		for i = -3, 3 do
			local t = i / 3
			air(math.cos(a) * R * 0.92 * t, R * 0.50 + jitter(R * 0.12),
				math.sin(a) * R * 0.92 * t, R * (0.50 + 0.10 * (1 - math.abs(t))))
		end
		air(math.cos(a) * R * 1.0, R * 0.62, math.sin(a) * R * 1.0, R * 0.52)
		air(-math.cos(a) * R * 1.0, R * 0.62, -math.sin(a) * R * 1.0, R * 0.52)

	elseif arch == "bubbles" then
		-- sea foam frozen in rock: a cluster of unequal bulbs
		air(0, R * 0.55, 0, R * 0.58)
		for i = 1, 7 do
			local a = spin + i * 0.92
			local d = R * (0.30 + rnd() * 0.55)
			air(math.cos(a) * d, R * (0.40 + rnd() * 0.95), math.sin(a) * d,
				R * (0.28 + rnd() * 0.30))
		end

	elseif arch == "crescent" then
		-- a curved hall wrapped around an off-centre rock horn
		local sweep = math.pi * 1.35
		for i = 0, 8 do
			local a = spin + (i / 8) * sweep
			air(math.cos(a) * R * 0.62, R * 0.52 + jitter(R * 0.2), math.sin(a) * R * 0.62,
				R * (0.40 + rnd() * 0.10))
		end
		local ha = spin + sweep * 0.5
		rock(math.cos(ha) * R * 0.82, R * 0.75, math.sin(ha) * R * 0.82,
			R * 0.30, R * 1.5, R * 0.30)

	elseif arch == "chimney" then
		-- a narrow throat that opens into a bell high overhead
		air(0, R * 0.48, 0, R * 0.62)
		for i = 1, 4 do
			air(jitter(R * 0.14), R * (0.75 + i * 0.28), jitter(R * 0.14), R * (0.40 + i * 0.05))
		end
		air(jitter(R * 0.2), R * 1.95, jitter(R * 0.2), R * 0.80)

	elseif arch == "terrace" then
		-- three shelves at different heights: the room reads as a staircase
		air(0, R * 0.50, 0, R * 0.70)
		for i = 1, 3 do
			local a = spin + i * 2.1
			local d = R * (0.70 + i * 0.12)
			air(math.cos(a) * d, R * (0.55 + i * 0.36), math.sin(a) * d, R * (0.46 - i * 0.04))
			rock(math.cos(a) * d, R * (0.30 + i * 0.36), math.sin(a) * d,
				R * 0.50, R * 0.22, R * 0.50)
		end

	elseif arch == "spine" then
		-- two parallel naves either side of a rock spine
		local a = spin
		local px, pz = -math.sin(a), math.cos(a)
		for side = -1, 1, 2 do
			for i = -2, 2 do
				local t = i / 2
				air(math.cos(a) * R * 0.80 * t + px * side * R * 0.46,
					R * 0.50 + jitter(R * 0.14),
					math.sin(a) * R * 0.80 * t + pz * side * R * 0.46,
					R * (0.40 + rnd() * 0.10))
			end
		end
		for endd = -1, 1, 2 do
			rock(math.cos(a) * R * 0.78 * endd, R * 0.70, math.sin(a) * R * 0.78 * endd,
				R * 0.26, R * 1.3, R * 0.26)
		end

	elseif arch == "drum" then
		-- wide, round and low: the biggest clear floor of the twelve
		air(0, R * 0.44, 0, R * 0.74)
		for i = 1, 9 do
			local a = spin + i * (math.pi * 2 / 9)
			air(math.cos(a) * R * 0.66, R * 0.42 + jitter(R * 0.10), math.sin(a) * R * 0.66,
				R * (0.38 + rnd() * 0.08))
		end
		air(0, R * 0.92, 0, R * 0.52)

	elseif arch == "fork" then
		-- two bulbs pinched at the waist, like a figure eight seen from above
		local a = spin
		for side = -1, 1, 2 do
			air(math.cos(a) * R * 0.62 * side, R * 0.55 + jitter(R * 0.14),
				math.sin(a) * R * 0.62 * side, R * 0.60)
			air(math.cos(a) * R * 0.86 * side, R * 0.80 + jitter(R * 0.14),
				math.sin(a) * R * 0.86 * side, R * 0.40)
		end
		air(0, R * 0.48, 0, R * 0.40)

	elseif arch == "barrel" then
		-- a barrel vault: straight walls, a curved ceiling running the long way
		local a = spin
		for i = -4, 4 do
			local t = i / 4
			local lift = (1 - t * t) * R * 0.45
			air(math.cos(a) * R * 0.88 * t, R * 0.48 + lift, math.sin(a) * R * 0.88 * t,
				R * (0.46 + 0.06 * (1 - math.abs(t))))
		end

	elseif arch == "star" then
		-- a core with radial fingers; each finger a little alcove of its own
		air(0, R * 0.52, 0, R * 0.56)
		for i = 1, 6 do
			local a = spin + i * (math.pi * 2 / 6) + jitter(0.3)
			for j = 1, 3 do
				local d = R * (0.30 + j * 0.24)
				air(math.cos(a) * d, R * (0.46 + j * 0.10), math.sin(a) * d,
					R * (0.40 - j * 0.07))
			end
		end

	elseif arch == "well" then
		-- a ring room around a raised rock island, lit from a high oculus
		for i = 1, 10 do
			local a = spin + i * (math.pi * 2 / 10)
			air(math.cos(a) * R * 0.64, R * 0.50 + jitter(R * 0.12), math.sin(a) * R * 0.64,
				R * (0.40 + rnd() * 0.10))
		end
		air(0, R * 0.52, 0, R * 0.62)
		air(jitter(R * 0.15), R * 1.35, jitter(R * 0.15), R * 0.46)
		local ia = spin + 1.1
		rock(math.cos(ia) * R * 0.74, R * 0.30, math.sin(ia) * R * 0.74,
			R * 0.40, R * 0.44, R * 0.40)

	else -- "hollow": a plain but asymmetric dome, used as the safe fallback
		air(0, R * 0.55, 0, R * 0.72)
		for i = 1, 8 do
			local a = spin + i * 0.8
			air(math.cos(a) * R * 0.55, R * (0.45 + rnd() * 0.7), math.sin(a) * R * 0.55,
				R * (0.32 + rnd() * 0.2))
		end
	end

	return blobs, solids, floorY
end

-- Where the dressing goes: the shaft mouth, a sign wall, and floor spots for
-- shells and props, all kept clear of the hole a diver comes up through.
function M.ChamberSpots(key)
	local n = M.Nodes[key]
	local floorY = M.ChamberFloorY(n)
	local rnd = lcg(chamberSeed(key) + 991)
	local spin = rnd() * math.pi * 2
	local spots = {}
	local rings = { 0.52, 0.72, 0.88 }
	for ri, frac in ipairs(rings) do
		local count = 4 + ri * 2
		for i = 1, count do
			local a = spin + i * (math.pi * 2 / count) + (rnd() - 0.5) * 0.4
			local d = n.r * (frac + (rnd() - 0.5) * 0.08)
			spots[#spots + 1] = Vector3.new(n.x + math.cos(a) * d, floorY, n.z + math.sin(a) * d)
		end
	end
	local signA = spin + 0.7
	return {
		floorY = floorY,
		centre = Vector3.new(n.x, floorY, n.z),
		shaft = Vector3.new(n.x, floorY + AIR_ENTRY_TOP, n.z),
		sign = Vector3.new(n.x + math.cos(signA) * n.r * 0.80, floorY,
			n.z + math.sin(signA) * n.r * 0.80),
		signLook = Vector3.new(n.x, floorY + 3, n.z),
		photo = Vector3.new(n.x - math.cos(signA) * n.r * 0.62, floorY,
			n.z - math.sin(signA) * n.r * 0.62),
		ceiling = n.y + n.r,
		spots = spots,
	}
end

-- ============================================================================
-- CARVING
-- ============================================================================
local function carveVoid(pos, radius, finalMaterial)
	local r = radius + SHELL_PAD
	if finalMaterial ~= Enum.Material.Air then
		r = math.max(r, MIN_WATER_RADIUS)
	end
	T:FillBall(pos, r, Enum.Material.Air)
	if finalMaterial ~= Enum.Material.Air then
		T:FillBall(pos, r, finalMaterial)
	end
end

local function pourBasementColumn(x, y, z, pad)
	local bottom = y - pad - 10
	local top = M.BasementTop
	if bottom >= top then return end
	T:FillBlock(
		CFrame.new(x, (bottom + top) / 2, z),
		Vector3.new(pad * 2, top - bottom, pad * 2),
		Enum.Material.Rock
	)
end

-- WARNING: this buries the ENTIRE cave footprint in rock, by design. Running it
-- without following with a full CarveAll() silently re-buries every passage --
-- that failure has bitten this project twice. Use M.Rebuild(), which does both.
function M.CarveBasements()
	local nodeCount = 0
	for _, n in pairs(M.Nodes) do
		if n.kind ~= "entrance" then
			local extraPad = M.AirKinds[n.kind] and (NECK_DROP + 14) or 10
			pourBasementColumn(n.x, n.y, n.z, n.r + extraPad)
			nodeCount += 1
		end
	end

	for _, spec in ipairs(M.Tunnels) do
		local aKey, bKey, r = spec[1], spec[2], spec[3]
		local p0 = M.GetNodeConnectPos(aKey)
		local p1 = M.GetNodeConnectPos(bKey)
		local dist = (p1 - p0).Magnitude
		local steps = math.max(2, math.ceil(dist / 4.5))
		for i = 0, steps do
			local pos = p0:Lerp(p1, i / steps)
			if pos.Y < M.BasementTop then
				pourBasementColumn(pos.X, pos.Y, pos.Z, r + 11)
			end
		end
	end

	for _, run in ipairs(M.DeepRuns) do
		for _, pos in ipairs(M.DeepRunSamples(run)) do
			if pos.Y < M.BasementTop then
				pourBasementColumn(pos.X, pos.Y, pos.Z, run.radius + 9)
			end
		end
	end

	return string.format("Basement rock poured for %d nodes and %d tunnels.",
		nodeCount, #M.Tunnels)
end

function M.CarveChamber(key)
	local n = M.Nodes[key]
	if not (n and M.AirKinds[n.kind]) then return "not an air chamber: " .. tostring(key) end
	local blobs, solids, floorY = M.ChamberShape(key)

	-- 1. hollow the room out in air
	for _, b in ipairs(blobs) do
		carveVoid(b.p, b.r, Enum.Material.Air)
	end

	-- 2. put back the rock that gives the room its character
	for _, s in ipairs(solids) do
		T:FillBlock(s.cf, s.size, Enum.Material.Rock)
	end

	-- 3. keep the air directly over the hole clear. Whatever an archetype chose to
	--    build, a diver surfacing has to have somewhere to put their head.
	local entryClear = (n.entryR or AIR_ENTRY_RADIUS) + 3.5
	for h = 0, 12, 3 do
		T:FillBall(Vector3.new(n.x, floorY + h, n.z), entryClear, Enum.Material.Air)
	end

	-- 4. cut a true flat floor -- shells and signage need somewhere level to sit
	local slabThickness = AIR_FLOOR_THICKNESS + 8
	T:FillBlock(
		CFrame.new(n.x, floorY - slabThickness / 2, n.z),
		Vector3.new(n.r * 3.4, slabThickness, n.r * 3.4),
		Enum.Material.Rock
	)

	-- 5. bore THE one hole: a single vertical water shaft through the floor centre
	local entryRadius = n.entryR or AIR_ENTRY_RADIUS
	local shaftTopY = floorY + AIR_ENTRY_TOP
	local neckBottomY = M.GetNodeConnectPos(key).Y
	local steps = math.max(6, math.ceil((shaftTopY - neckBottomY) / 3))
	for step = 0, steps do
		local py = neckBottomY + (shaftTopY - neckBottomY) * (step / steps)
		local pos = Vector3.new(n.x, py, n.z)
		local rCurrent = entryRadius
		if py < (floorY - AIR_ENTRY_DEPTH) then
			rCurrent = math.max(entryRadius, 4.5)
		end
		T:FillBall(pos, rCurrent + SHELL_PAD, Enum.Material.Air)
		T:FillBall(pos, rCurrent, Enum.Material.Water)
	end

	return string.format("chamber %s (%s): %d air lobes, %d solids", key, n.archetype or "?",
		#blobs, #solids)
end

function M.CarveChambers()
	local airCount, waterCount = 0, 0
	for k, n in pairs(M.Nodes) do
		if n.kind ~= "entrance" then
			if M.AirKinds[n.kind] then
				M.CarveChamber(k)
				airCount += 1
			else
				carveVoid(Vector3.new(n.x, n.y, n.z), n.r, Enum.Material.Water)
				carveVoid(Vector3.new(n.x + n.r * 0.35, n.y + n.r * 0.15, n.z - n.r * 0.25),
					n.r * 0.65, Enum.Material.Water)
				carveVoid(Vector3.new(n.x - n.r * 0.30, n.y - n.r * 0.10, n.z + n.r * 0.35),
					n.r * 0.55, Enum.Material.Water)
				waterCount += 1
			end
		end
	end
	return string.format("Carved %d air chambers (one archetype each) and %d water nodes.",
		airCount, waterCount)
end

function M.EntranceSamples(n)
	local bottom = n.y
	local top = math.min((n.seabedH or -12) + 6, -6)
	local steps = 6
	local samples, radii = {}, {}
	for i = steps, 0, -1 do
		local t = i / steps
		samples[#samples + 1] = Vector3.new(n.x, bottom + (top - bottom) * t, n.z)
		radii[#radii + 1] = n.r + (n.r * 0.6) * t
	end
	return samples, radii
end

function M.CarveEntrances()
	local count = 0
	for _, n in pairs(M.Nodes) do
		if n.kind == "entrance" then
			local samples, radii = M.EntranceSamples(n)
			for i, pos in ipairs(samples) do
				carveVoid(pos, radii[i], Enum.Material.Water)
			end
			count += 1
		end
	end
	return string.format("%d entrances carved.", count)
end

function M.TunnelSamples(index)
	local spec = M.Tunnels[index]
	if not spec then return nil end
	local startKey, endKey, r = spec[1], spec[2], spec[3]
	local p0 = M.GetNodeConnectPos(startKey)
	local p1 = M.GetNodeConnectPos(endKey)
	local isStartAir = M.Nodes[startKey] and M.AirKinds[M.Nodes[startKey].kind]
	local isEndAir = M.Nodes[endKey] and M.AirKinds[M.Nodes[endKey].kind]

	local dist = (p1 - p0).Magnitude
	local n = math.max(2, math.ceil(dist / 4.5))
	local samples, radii = {}, {}
	for i = 0, n do
		local t = i / n
		local base = p0:Lerp(p1, t)
		local edge = math.min(1, math.min(t, 1 - t) * 6)

		local wobbleScale = 1
		if isStartAir and i < AIR_ENDPOINT_NO_WOBBLE then
			wobbleScale = math.clamp(i / AIR_ENDPOINT_NO_WOBBLE, 0, 1)
		end
		if isEndAir and (n - i) < AIR_ENDPOINT_NO_WOBBLE then
			wobbleScale = math.min(wobbleScale, math.clamp((n - i) / AIR_ENDPOINT_NO_WOBBLE, 0, 1))
		end
		if i == 0 or i == n then wobbleScale = 0 end

		local wob = hash(base.X, base.Y, startKey:byte(1) + i) * 5.5 * wobbleScale
		local wob2 = hash(base.Z, base.Y + 50, endKey:byte(1) + i) * 3.5 * wobbleScale
		samples[#samples + 1] = base + Vector3.new(wob, wob2 * 0.5, wob * 0.4)
		radii[#radii + 1] = r * (0.75 + 0.25 * edge)
	end
	return samples, radii
end

function M.CarveTunnel(index)
	local spec = M.Tunnels[index]
	if not spec then return "no such tunnel: " .. tostring(index) end
	local samples, radii = M.TunnelSamples(index)
	for i, pos in ipairs(samples) do
		carveVoid(pos, radii[i], Enum.Material.Water)
	end
	return string.format("Tunnel %d (%s -> %s): %d spheres", index, spec[1], spec[2], #samples)
end

function M.CarveAllTunnels()
	for i = 1, #M.Tunnels do
		M.CarveTunnel(i)
	end
	return string.format("Carved all %d tunnels.", #M.Tunnels)
end

-- Returns the sample centres AND the true arc length, because the deep run
-- plates quote that number to the player before they commit a lung to it.
function M.DeepRunSamples(run)
	local pStart = M.GetNodeConnectPos(run.from)
	local pts = { pStart }
	for _, p in ipairs(run.path) do pts[#pts + 1] = p end
	local samples, length = {}, 0
	local seed = run.key:byte(1) + run.key:byte(2)
	local isFromAir = M.Nodes[run.from] and M.AirKinds[M.Nodes[run.from].kind]

	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local seg = (p1 - p0).Magnitude
		length += seg
		local n = math.max(2, math.ceil(seg / 4.5))
		for j = (i == 1) and 0 or 1, n do
			local base = p0:Lerp(p1, j / n)
			local wobbleScale = 1
			if isFromAir and i == 1 and j < AIR_ENDPOINT_NO_WOBBLE then
				wobbleScale = math.clamp(j / AIR_ENDPOINT_NO_WOBBLE, 0, 1)
			end
			if i == 1 and j == 0 then wobbleScale = 0 end
			local wob = hash(base.X, base.Y, seed + i * 7 + j) * 1.5 * wobbleScale
			local wob2 = hash(base.Z, base.Y + 50, seed + i * 13 + j) * 1.1 * wobbleScale
			samples[#samples + 1] = base + Vector3.new(wob, wob2 * 0.5, wob * 0.4)
		end
	end
	return samples, length
end

function M.ProbeMaterial(pos)
	local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local mats = T:ReadVoxels(region, 4)
	return mats[1][1][1]
end

function M.EffectiveRadius(radius, watery)
	local r = radius + SHELL_PAD
	if watery then
		r = math.max(r, MIN_WATER_RADIUS)
	end
	return r
end

local function forceWater(pos, radius)
	for _, extra in ipairs({ 0, 2, 3, 5 }) do
		T:FillBall(pos, radius + extra, Enum.Material.Air)
		T:FillBall(pos, radius + extra, Enum.Material.Water)
		if M.ProbeMaterial(pos) == Enum.Material.Water then
			return true, extra
		end
	end
	return false, nil
end

function M.InAirChamber(pos)
	for _, n in pairs(M.Nodes) do
		if M.AirKinds[n.kind] and (pos - Vector3.new(n.x, n.y, n.z)).Magnitude < n.r + 2 then
			return true
		end
	end
	return false
end

function M.CarveDeepRun(index)
	local run = M.DeepRuns[index]
	if not run then return "no such deep run: " .. tostring(index) end
	local samples = M.DeepRunSamples(run)
	for i, pos in ipairs(samples) do
		local flare = math.max(0, 1 - (i - 1) / 4) * 2
		carveVoid(pos, run.radius + flare, Enum.Material.Water)
	end

	-- Terrain will sometimes refuse to relabel a voxel on the first pass and leave
	-- a rock plug in an otherwise open tube. Re-cut wider until it actually reads
	-- as water rather than trusting the fill.
	local base = M.EffectiveRadius(run.radius, true)
	local repaired = 0
	for i = 2, #samples do
		local pos = samples[i]
		if M.ProbeMaterial(pos) ~= Enum.Material.Water and not M.InAirChamber(pos) then
			if forceWater(pos, base) then repaired += 1 end
		end
	end
	return string.format("Deep run %s (%s -> %s): %d spheres, %d repaired",
		run.key, run.from, run.endNode, #samples, repaired)
end

function M.CarveAllDeepRuns()
	for i = 1, #M.DeepRuns do
		M.CarveDeepRun(i)
	end
	return string.format("Carved all %d deep runs.", #M.DeepRuns)
end

-- ============================================================================
-- CAVE-IN SUPPORT
-- ============================================================================
local SEAL_FRACTION = 0.82
local SEAL_SPAN = 3

function M.PassageSamples(entry)
	if entry.kind == "tunnel" then
		return M.TunnelSamples(entry.index), M.Tunnels[entry.index][3]
	end
	local run = M.DeepRuns[entry.index]
	return M.DeepRunSamples(run), run.radius
end

local function sealRange(entry)
	local samples, radius = M.PassageSamples(entry)
	local n = #samples
	local centre = math.clamp(math.floor(n * SEAL_FRACTION), 2, n - 1)
	return samples, radius, math.max(2, centre - SEAL_SPAN), math.min(n - 1, centre + SEAL_SPAN)
end

function M.SealPassage(entry)
	local samples, radius, from, to = sealRange(entry)
	local r = M.EffectiveRadius(radius, true)
	for i = from, to do
		T:FillBall(samples[i], r, Enum.Material.Basalt)
	end
	return samples[math.floor((from + to) / 2)], to - from + 1
end

function M.OpenPassage(entry)
	local samples, radius, from, to = sealRange(entry)
	for i = from, to do
		carveVoid(samples[i], radius, Enum.Material.Water)
	end
	return to - from + 1
end

function M.BeyondPoints(entry)
	local samples, _, from = sealRange(entry)
	local pts = {}
	for i = from, #samples do
		pts[#pts + 1] = samples[i]
	end
	for _, name in ipairs(entry.beyond) do
		local nd = M.Nodes[name]
		if nd then
			pts[#pts + 1] = Vector3.new(nd.x, nd.y, nd.z)
		end
		for _, run in ipairs(M.DeepRuns) do
			if run.from == name then
				for _, p in ipairs(M.DeepRunSamples(run)) do
					pts[#pts + 1] = p
				end
			end
		end
	end
	return pts
end

-- The only safe way to regenerate: basements first, then every passage re-cut,
-- then the chambers re-asserted last so their floors and single shafts win.
function M.Rebuild()
	local b = M.CarveBasements()
	local t = M.CarveAllTunnels()
	local r = M.CarveAllDeepRuns()
	local e = M.CarveEntrances()
	local c = M.CarveChambers()
	return table.concat({ b, t, r, e, c }, "\n")
end

return M
