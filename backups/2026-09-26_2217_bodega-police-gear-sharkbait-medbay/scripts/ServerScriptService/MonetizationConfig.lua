-- MonetizationConfig
-- Fill in real IDs here once the passes/products exist on the Creator Dashboard.
-- Everything downstream (GamePassService, MonetizationBootstrap, the shop UI) reads
-- from this table, so wiring up a real ID is the only change needed at launch time.
-- An id of 0 means "not created yet" -- those are safely ignored rather than erroring.
--
-- `icon` names the artwork file in Desktop/Isla Marahuyo/gamepass-icons, so whoever
-- uploads a pass knows exactly which image belongs to it. `price` is a SUGGESTED Robux
-- price only -- the real price is set on the Dashboard and Roblox never reads this.
--
-- THE MONETIZATION RULE THIS TABLE FOLLOWS
-- Nothing sold here makes the cave shorter, the sharks safer, the maze readable, or the
-- revive quicker. Breath capacity is earned with Lung Corals, the cave is meant to be
-- survived on planning, and drowning is meant to cost something -- selling around any of
-- that would undo the design rather than extend it. So every pass below sells looks,
-- time, or social reach. Where a piece of the icon art promised real power, it was
-- reshaped into an honest equivalent (see COSMETIC REFRAMES at the bottom), and two were
-- left unsold entirely because no honest version of them exists.

return {
	GamePasses = {
		-- ===== flagship =====
		KasamaVIP = {
			id = 1979048670,
			name = "Kasama VIP Pass",
			description = "A second bodega slot, 2x Shells from minigames, exclusive dance emote.",
			icon = "01_island-vip.png",
			price = 399,
		},
		IslandLegend = {
			id = 1979006627,
			name = "Island Legend",
			description = "A gold nameplate, the Island Legend title, and a legend badge by your name. Pure prestige -- it changes nothing you can do.",
			icon = "47_island-legend-badge.png",
			price = 499,
		},

		-- ===== access & convenience (sells time, never advantage) =====
		KalangitanIsleAccess = {
			id = 1977242795,
			name = "Kalangitan Isle Access",
			description = "Unlocks the bangkero ferry to the private offshore isle.",
			icon = "13_fast-ferry.png",
			price = 199,
		},
		ZiplinePass = {
			id = 1977152864,
			name = "Zipline Pass",
			description = "Ride every zipline leg free, forever. The route is open to everyone either way -- this just stops charging you 25 Shells a leg.",
			icon = "12_zipline-pass.png",
			price = 99,
		},
		-- Cabin plots were retired in favour of the bodega -- this pass now grants a second
		-- bodega slot instead of a second buildable plot. Kept under its old key/id so
		-- everyone who already bought it keeps getting real value from it.
		ExtraCabinPlot = {
			id = 1980146373,
			name = "Extra Bodega Slot",
			description = "Place a second bodega at the same time.",
			icon = "02_cabin-plot-1.png",
			price = 149,
		},

		-- ===== building & decor =====
		-- Also retired from cabins: now grants the Stone Bodega upgrade (200 health, vs the
		-- free wood tier's 100) for free instead of its 10,000-Peso price.
		CabinBuilder = {
			id = 1979048673,
			name = "Stone Bodega",
			description = "Unlocks the tougher stone bodega tier (200 health) for free.",
			icon = "20_terrace-add.png",
			price = 199,
		},
		BangkaCustom = {
			id = 1976486900,
			name = "Bangka Customs",
			description = "Paint, sail and name-plate options for any bangka you take out.",
			icon = "06_bangka-custom.png",
			price = 149,
		},

		-- ===== expression & social =====
		NameTitle = {
			id = 1977446913,
			name = "Custom Title",
			description = "Choose the title shown above your name.",
			icon = "26_name-title.png",
			price = 99,
		},
		DanceEmotes = {
			id = 1976480863,
			name = "Sayawan Emote Pack",
			description = "Six extra emotes, usable anywhere on the island.",
			icon = "25_dance-emotes.png",
			price = 99,
		},
		BroadcastLicense = {
			id = 1978988681,
			name = "Broadcast License",
			description = "Play your chosen track out loud to everyone standing near you.",
			icon = "24_broadcast-license.png",
			price = 149,
		},
		AudioCustomizer = {
			id = 1980296334,
			name = "Audio Customizer",
			description = "Build your own playlist and reorder the island radio for yourself.",
			icon = "11_audio-customizer.png",
			price = 79,
		},
		PhotoFX = {
			id = 1980332328,
			name = "Photo FX",
			description = "Cinematic filters and frames at every photo spot.",
			icon = "27_photo-fx.png",
			price = 99,
		},

		-- ===== FLAGGED, NOT RECOMMENDED =====
		-- Kept because it predates this catalog, but worth a decision before you create it:
		-- the island ranks players by Fastest Lap on the plaza board, so a paid speed boost
		-- is a paid advantage on a competitive leaderboard. Either drop it, or exclude boosted
		-- laps from that board. Leaving it at id = 0 keeps it unsold and inert in the meantime.
		BrightBeam = {
			id = 0,
			name = "Malakas na Sulo",
			description = "A brighter, wider flashlight beam -- about half again the throw and a much broader cone. It still runs on the same batteries.",
			icon = "",
			price = 129,
			flagged = "Sits on the advantage side of the line drawn in ApplyPerks: a wider beam makes the cave maze easier to read, and the maze is named there as off-limits. Sells clarity, not air or speed -- decide before creating.",
		},
		DiverBag = {
			id = 0,
			name = "Kaban ng Dagat",
			description = "The largest dive bag, straight away -- 20 slots of gear. Every tier below it is still buyable with Shells; this only skips the grind.",
			icon = "",
			price = 149,
			flagged = "Carrying capacity is close to the advantage line -- a bigger bag means more tanks on a deep run. Sells convenience, but decide before creating.",
		},
		BangkeroSpeed = {
			id = 0,
			name = "Bangkero Speed Pass",
			description = "Faster boats.",
			icon = "",
			price = 149,
			-- The objection here has since gone away: the bangka race and the Fastest Lap
			-- board were both removed, so there is no longer a competitive leaderboard for
			-- a paid speed boost to sit on top of. Boats are now pure travel time, which is
			-- squarely on the "sells time" side of the line. Safe to create.
			flagged = nil,
		},
		MalakingLambat = {
			id = 0,
			name = "Malaking Lambat",
			description = "A 20-stud lambat instead of the standard 12 -- about 2.8x the water swept. One net at a time either way.",
			icon = "",
			price = 179,
			flagged = "Sits on the advantage side of the line this file draws: a wider net sweeps more sharks and so earns more, which is yield, not looks or time. It is capped to ONE net per player so it cannot be stacked, and the free 12-stud net is fully usable on its own -- but this sells earning rate. Decide before creating.",
		},
	},

	DeveloperProducts = {
		ShellsSmall = { id = 3712370090, name = "Sigla Shells - Small", shells = 100, price = 49 },
		ShellsMedium = { id = 3712370280, name = "Sigla Shells - Medium", shells = 550, price = 199 },
		ShellsLarge = { id = 3712370418, name = "Sigla Shells - Large", shells = 1200, price = 399 },
		ShellsMega = { id = 3712370743, name = "Sigla Shells - Mega", shells = 3000, price = 899 },
		InstantRestock = { id = 3712371226, name = "Instant Restock", price = 25 },
		-- Random cosmetic crate. Roblox's random-item-generator policy requires the odds
		-- to be published inside the experience, so they live in BilaoBoxOdds below and
		-- are rendered verbatim in the shop's "Drop rates" panel. Change them in one place.
		BilaoBox = { id = 3712370973, name = "Bilao Box", price = 79 },
		TaskReroll = {
			id = 3712371948,
			name = "Task Reroll",
			description = "Swap one of today's island tasks for a different one.",
			icon = "29_task-reroll.png",
			price = 25,
		},
		StreakSaver = {
			id = 3712372079,
			name = "Streak Saver",
			description = "Protects your daily login streak for one missed day.",
			icon = "30_streak-saver.png",
			price = 49,
		},
	},

	-- Bilao Box contents. `weight` values are relative; the shop panel converts them to
	-- percentages at display time so the published odds can never drift from the table
	-- the server actually rolls on. Every entry is decoration, a wearable, a trail or a
	-- log -- there is deliberately nothing in this box that affects what a player can do,
	-- which is also what keeps a paid random crate defensible.
	BilaoBoxOdds = {
		-- common
		{ key = "BannerCommon", name = "Barangay Banner", rarity = "Common", weight = 16, shells = 15, icon = "28_banner.png" },
		{ key = "HatSalakot", name = "Salakot Hat", rarity = "Common", weight = 12, shells = 20 },
		{ key = "VentureShirt", name = "Venture Shirt", rarity = "Common", weight = 10, shells = 20, icon = "43_venture-shirt.png" },
		{ key = "BayongBag", name = "Woven Bayong", rarity = "Common", weight = 10, shells = 20, icon = "09_expanded-bag.png" },
		{ key = "SnorkelSet", name = "Snorkel Set (worn)", rarity = "Common", weight = 9, shells = 25, icon = "14_snorkel-gear.png" },
		{ key = "DiveTankSkin", name = "Vintage Dive Tank (worn)", rarity = "Common", weight = 9, shells = 25, icon = "03_oxygen-tank.png" },

		-- uncommon
		{ key = "LanternParol", name = "Parol Lantern", rarity = "Uncommon", weight = 7, shells = 40 },
		{ key = "LagoonHammock", name = "Lagoon Hammock", rarity = "Uncommon", weight = 6, shells = 45, icon = "40_lagoon-hammock.png" },
		{ key = "CabinGarden", name = "Cabin Garden", rarity = "Uncommon", weight = 6, shells = 45, icon = "41_cabin-garden.png" },
		{ key = "CoralGloves", name = "Coral Gloves (worn)", rarity = "Uncommon", weight = 5, shells = 50, icon = "44_coral-harvester.png" },
		{ key = "MedicOutfit", name = "Barangay Medic Outfit", rarity = "Uncommon", weight = 5, shells = 50, icon = "46_barangay-health-care.png" },
		{ key = "CatchLogbook", name = "Palakaya Logbook", rarity = "Uncommon", weight = 5, shells = 50, icon = "05_fishing-sonar.png" },
		{ key = "TravelLog", name = "Lagoon Travel Log", rarity = "Uncommon", weight = 5, shells = 50, icon = "15_lagoon-map.png" },
		{ key = "SarongTinalak", name = "Tinalak Sarong", rarity = "Uncommon", weight = 4, shells = 60 },

		-- rare
		{ key = "AquariumProp", name = "Reef Aquarium", rarity = "Rare", weight = 3.5, shells = 90, icon = "42_aquarium-prop.png" },
		{ key = "AcousticJukebox", name = "Acoustic Jukebox", rarity = "Rare", weight = 3.5, shells = 90, icon = "23_acoustic-jukebox.png" },
		{ key = "GlowingTrail", name = "Glowing Trail", rarity = "Rare", weight = 3, shells = 100, icon = "37_glowing-trail.png" },
		{ key = "SplashTrail", name = "Surface Splash Trail", rarity = "Rare", weight = 3, shells = 100, icon = "45_surface-hopper.png" },
		{ key = "CaveLog", name = "Yungib Survey Log", rarity = "Rare", weight = 3, shells = 100, icon = "16_abyss-scanner.png" },
		{ key = "LapChronometer", name = "Bangka Chronometer", rarity = "Rare", weight = 2.5, shells = 110, icon = "39_chronometer.png" },
		{ key = "BangkaPaintGold", name = "Gold Bangka Paint", rarity = "Rare", weight = 2.5, shells = 120 },
		{ key = "VendorStallSkin", name = "Master Vendor Stall", rarity = "Rare", weight = 2.5, shells = 120, icon = "10_market-master.png" },

		-- legendary
		{ key = "DanceSpotlight", name = "Sayawan Spotlight", rarity = "Legendary", weight = 1.5, shells = 220, icon = "33_dance-leader.png" },
		{ key = "DugongCompanion", name = "Dugong Companion", rarity = "Legendary", weight = 1.2, shells = 260, icon = "35_dugong-whisperer.png" },
		{ key = "RecoveryCot", name = "Gold Scanner Bay", rarity = "Legendary", weight = 1.2, shells = 260, icon = "34_health-post-vip.png" },
		{ key = "FiestaCrown", name = "Reyna ng Pista Crown", rarity = "Legendary", weight = 1, shells = 300 },
	},

	-- ===== COSMETIC REFRAMES =====
	-- What each piece of power-selling art became, so nobody re-adds the original later by
	-- reading the icon name and assuming. Every one of these sells the LOOK of the thing,
	-- never the effect:
	--   Oxygen Tank / Snorkel Gear -> worn dive gear. Breath capacity is still Lung Corals only.
	--   Abyss Scanner   -> Yungib Survey Log: lists chambers you have ALREADY found. Never
	--                      reveals an unvisited one, so the maze stays a maze.
	--   Lagoon Map      -> Travel Log: same rule, for zones you have already visited.
	--   Health Post VIP -> gold trim on your scanner bay. You still wait the full 20 seconds.
	--   Bonus Bank / Market Master -> a treasure-chest prop and a stall skin. No multipliers.
	--   Surface Hopper  -> a splash trail. The waterline jump nerf is untouched.
	--   Dugong Whisperer-> a dugong that follows you on land. The rescue itself is unchanged.
	--   Coral Harvester -> gloves you wear. Harvest rates are unchanged.
	--   Fishing Sonar   -> a logbook of what you have caught. No bite timing.
	--   Dance Leader    -> a spotlight effect. No Shells bonus.
	--
	-- ===== DELIBERATELY NOT SOLD =====
	-- Two icons have no honest non-power version, because the thing the art promises IS the
	-- advantage, and selling them under a reshaped meaning would mislead whoever bought them:
	--   Shark Repellent (07/08) -- selling safety from the game's only real threat.
	--   Pating Tracker  (36)    -- live positions of that threat.
	-- Both are better as EARNED unlocks. The cave milestone system already exists and would
	-- carry them well: award them at Seasoned Diver / Scuba Diving Professional, where they
	-- read as a reward for knowing the cave rather than a way to skip learning it.
}
