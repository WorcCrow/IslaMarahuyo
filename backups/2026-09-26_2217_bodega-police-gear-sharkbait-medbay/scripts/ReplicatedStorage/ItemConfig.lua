-- ItemConfig
-- Shared definitions for carryable gear. Both the server (which owns the real inventory)
-- and the HUD read this, so prices and sizes can never disagree between them.
--
-- `slots` is the point of the whole system: a tank is bulky and costs twice what a battery
-- does to carry, so one diver cannot quietly become the team's pack mule.

-- PRICING
-- Anchored to what the island actually pays, not picked by feel:
--   fishing catch 8/15/25 - bangka lap 15 (30 fast) - vendor cycle ~21-31
--   shallow sea finds 6-24 - DEEP CAVE finds 32-48 and 60-85
--   a daily task 30-80, and the full set plus its bonus lands near 230
--
-- Gear is priced in whole sessions rather than single catches, so kit has to be earned out
-- on the island first. The curve leans on the fact that the deep cave already pays best:
-- surface work buys the first gear, that gear opens the cave, and the cave pays for the
-- rest. A diver starts with 100 Shells and a full battery, so the first dive is free --
-- what costs effort is the second one.

local ItemConfig = {}

ItemConfig.Items = {
	battery = {
		key = "battery",
		label = "Flashlight Battery",
		short = "Battery",
		slots = 1,
		price = 90, -- about one short session, or two daily tasks
		asset = "Battery",
		glow = Color3.fromRGB(255, 196, 92),
		blurb = "Fits the flashlight.",
		order = 1,
	},
	glowstick = {
		key = "glowstick",
		label = "Glowstick",
		short = "Glowstick",
		-- a fifth of a slot each, so a full pack of ten costs the same room as one tank
		slots = 0.2,
		price = 140, -- 14 a stick: cheap enough to lay a trail, dear enough to go back for them
		bundle = 10, -- sold by the pack; dropped one at a time
		usable = false, -- nothing to consume: you drop it and leave it burning
		-- Two in-game days. DayNightCycle runs a full day in 24 real minutes, so that is
		-- 48 real minutes of burn -- long enough that a trail laid on the way in is still
		-- there on the way out. Walk back over one and you can pick it up and reuse it.
		dropLifetime = 2 * 24 * 60,
		-- a trail marker that rolls down a slope is not a marker; let it land, then pin it
		settles = true,
		asset = "Glowstick",
		glow = Color3.fromRGB(124, 255, 59),
		blurb = "Drop a trail you can follow back \u{2022} lasts 2 days",
		order = 2,
	},
	tolda = {
		key = "tolda",
		label = "Tolda (Stall Tent)",
		short = "Tolda",
		slots = 2,
		-- Not sold at the Palengke -- the fixer at Terminal Cove handles these, and he
		-- charges for the privilege. Priced so one confiscation genuinely hurts.
		price = 260,
		usable = false, -- you pitch it; there is nothing to consume
		contraband = true, -- the Palengke will not stock it and the pulis may seize it
		asset = "Tolda",
		glow = Color3.fromRGB(196, 118, 236),
		blurb = "Pitch a stall anywhere \u{2022} no cut taken \u{2022} the pulis may seize it",
		order = 5,
	},
	lambat = {
		key = "lambat",
		label = "Lambat (Net Set)",
		short = "Lambat",
		-- four stakes and a folded net: bulky, because a fisher heading out to set it is
		-- not also carrying a full dive kit
		slots = 2,
		-- Dearer than a tank, because it is not spent -- it comes back to you when the net
		-- is pulled up, and it earns while you are somewhere else.
		price = 320,
		usable = false, -- you plant it; there is nothing to consume
		asset = "Lambat",
		glow = Color3.fromRGB(120, 200, 235),
		blurb = "Plant four stakes at sea \u{2022} sharks shake loose what they pass over",
		order = 4,
	},
	sharkbait = {
		key = "sharkbait",
		label = "Shark Bait",
		short = "Shark Bait",
		slots = 0.5,
		-- a decoy can buy back a whole dive, and a lure pays out through a lambat: priced
		-- as something you think about spending, not a trail marker
		price = 80,
		-- held, it draws sharks to you; thrown, it draws them to where it lands. Either way
		-- the first shark to bite it eats it.
		usable = false,
		asset = "SharkBait",
		glow = Color3.fromRGB(235, 80, 70),
		blurb = "Hold to lure sharks \u{2022} throw as a decoy \u{2022} eaten on the first bite",
		order = 6,
	},
	oxygen = {
		key = "oxygen",
		label = "Oxygen Tank",
		short = "O2 Tank",
		slots = 2,
		price = 240, -- a full day's tasks; never a routine restock
		asset = "OxygenTank",
		glow = Color3.fromRGB(120, 214, 255),
		blurb = "A full lungful, anywhere.",
		order = 3,
	},
}

-- Bought in order with Shells. The pass grants the last one outright.
ItemConfig.BagTiers = {
	{ key = "sako",   label = "Sako",           slots = 4,  price = 0 },
	{ key = "bayong", label = "Bayong",         slots = 8,  price = 550 },
	{ key = "buslo",  label = "Buslo",          slots = 14, price = 1500 },
	{ key = "kaban",  label = "Kaban ng Dagat", slots = 20, price = 3800 },
}

-- ===== LOOT =====
-- What the sea and the cave actually give you: objects, not money. A find goes in the bag
-- and stays a find until you carry it up to the Palengke and sell it. That is the whole
-- risk in the game -- Shells in your pocket are safe, everything in your bag is not.
--
-- Finds do NOT live in the dive bag and have no cap -- you can gather as many as the sea
-- will give you. The bag is for equipment; a sack of shells rides separately and is shown
-- on its own counter. What finds DO cost you is the swim home: drown and the whole haul
-- scatters on the floor, while the money already banked at the Palengke is untouchable.
--
-- `slots` is kept only for the scatter: it decides whether a find drops as its own pickup
-- or as a stack, and how big the dropped nodule looks.
ItemConfig.Loot = {
	kabibe = {
		key = "kabibe", label = "Kabibe", short = "Kabibe",
		slots = 0.25, sell = 10, order = 1,
		color = Color3.fromRGB(240, 226, 190),
		blurb = "Shallow shell. Worth little, weighs nothing.",
	},
	bahura = {
		key = "bahura", label = "Bahura Coral", short = "Bahura",
		slots = 0.25, sell = 26, order = 2,
		color = Color3.fromRGB(255, 150, 170),
		blurb = "Reef coral from the shallows.",
	},
	yungib = {
		key = "yungib", label = "Cave Pearl", short = "Yungib",
		slots = 0.5, sell = 95, order = 3,
		color = Color3.fromRGB(170, 230, 255),
		blurb = "Only grows where there is no daylight.",
	},
	kailaliman = {
		key = "kailaliman", label = "Perlas ng Kailaliman", short = "Kailaliman",
		slots = 0.5, sell = 200, order = 4,
		color = Color3.fromRGB(200, 170, 255),
		blurb = "From past the last air pocket.",
	},
	kristal = {
		key = "kristal", label = "Kristal ng Kailaliman", short = "Kristal",
		slots = 1, sell = 280, order = 5,
		color = Color3.fromRGB(150, 245, 230),
		blurb = "Deep-chamber crystal. Bulky and priceless.",
	},
	yaman = {
		key = "yaman", label = "Dead-End Hoard", short = "Yaman",
		slots = 1, sell = 230, order = 6,
		color = Color3.fromRGB(255, 206, 120),
		blurb = "Hauled out of a crawl with no air in it.",
	},
	perlas = {
		key = "perlas", label = "Perlas Hollow Pearl", short = "Perlas",
		slots = 1, sell = 600, order = 7,
		color = Color3.fromRGB(255, 240, 210),
		blurb = "The one the whole cave is named for.",
	},
}

-- Gear and loot share the one Inventory table, so most code wants a single lookup.
function ItemConfig.Find(key)
	return ItemConfig.Items[key] or ItemConfig.Loot[key]
end

function ItemConfig.IsLoot(key)
	return ItemConfig.Loot[key] ~= nil
end

function ItemConfig.SortedLoot()
	local list = {}
	for _, entry in pairs(ItemConfig.Loot) do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

-- Pass-bought upgrades that sit on the Palengke shelf next to the Shell items. These are
-- not carried, so they take no slots -- buying one prompts Robux and the perk is permanent.
ItemConfig.PassItems = {
	{
		passKey = "BrightBeam",
		label = "Malakas na Sulo",
		blurb = "Brighter, wider beam",
		order = 50,
	},
	{
		passKey = "MalakingLambat",
		label = "Malaking Lambat",
		blurb = "A 100-stud net instead of 60",
		order = 51,
	},
}

-- ===== the lambat =====
-- Reach is fixed by tier, shape is not. Each stake only has to stay within LambatHalfSide
-- studs of the others' average -- the same footprint this side length always bounded --
-- but inside that circle a player draws whatever quadrilateral they like.
ItemConfig.LambatPass = "MalakingLambat"
ItemConfig.LambatSide = { free = 60, pass = 100 } -- 5x the original 12/20
ItemConfig.LambatStakes = 4
-- One live net per player at either tier: the pass sells area, never count.
ItemConfig.LambatPerPlayer = 1
ItemConfig.LambatLifetime = 30 * 60 -- real seconds before it is hauled in automatically

function ItemConfig.LambatHalfSide(hasPass)
	return (hasPass and ItemConfig.LambatSide.pass or ItemConfig.LambatSide.free) / 2
end

-- ===== the black market =====
-- A tolda undercuts the Palengke on every axis except safety: no stall fee, pitch it
-- anywhere, and it will take unconverted finds straight for Peso instead of making the
-- seller walk them to the counter. What it costs is exposure -- packing up is slow and
-- loud on purpose, so running a stall is a decision you can be caught making.
ItemConfig.ToldaPackSeconds = 12
ItemConfig.ToldaMaxListings = 6
ItemConfig.ConfiscationCut = 0.25 -- the officer's share of what a seized stall was asking

-- Items the Palengke refuses to stock, so the shop list and the stall board agree.
function ItemConfig.IsContraband(key)
	local item = ItemConfig.Items[key]
	return item ~= nil and item.contraband == true
end

function ItemConfig.SortedShopItems()
	local list = {}
	for _, item in pairs(ItemConfig.Items) do
		if not item.contraband then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

-- ===== the bodega =====
-- A physical storehouse the owner places in the world. Nothing moves between it and the
-- bag unless it is standing and the owner is beside it, and while it stands anyone with an
-- axe can go at it. Numbers are tuned so one thief needs well over a minute of uninterrupted
-- chopping at full health (100 hits) and a crew of five about fifteen seconds -- long enough
-- for an owner or a pulis to show up.
ItemConfig.Bodega = {
	-- QUICK-TEST VALUE: 20 breaks the wood bodega in 5 solo swings. Restore to 1 for the
	-- tuned 100-swing balance described above.
	AxeDamage = 20,
	HitCooldown = 0.8, -- seconds between counted swings, per attacker
	AxeReach = 7, -- studs from the attacker to the nearest face of the bodega
	UseRange = 16, -- how close the owner must stand to pack, stow or repair
	PackSeconds = 10, -- despawning takes this long beside it, so it is no instant escape
	RepairPerPoint = 4, -- Peso per missing point; a full rebuild from 1 costs ~400
	RebuildSeconds = 60, -- wait after a bodega is broken before a new one can go up
	MaxScatterPieces = 120, -- a huge hoard spills as stacks past this, not as 500 models
}

-- A bodega comes in tiers: the free wooden hut, and a tougher stone storehouse bought with
-- Peso or granted outright by the (repurposed) CabinBuilder pass. Everything else about a
-- bodega -- reach, use range, repair rate -- is shared across tiers; only health and looks
-- differ, so those live here rather than duplicating the whole config table per tier.
ItemConfig.BodegaTiers = {
	wood = {
		key = "wood", label = "Bodega", asset = "Bodega", maxHealth = 100, price = 0,
	},
	stone = {
		key = "stone", label = "Stone Bodega", asset = "BodegaStone", maxHealth = 200, price = 10000,
		-- owning this pass (repurposed from the old cabin-building upgrade) grants the stone
		-- tier for free instead of the 10,000 Peso price
		passKey = "CabinBuilder",
	},
}

function ItemConfig.BodegaTierFor(key)
	return ItemConfig.BodegaTiers[key] or ItemConfig.BodegaTiers.wood
end

-- A second bodega slot, wherever the owner wants it, is what the repurposed ExtraCabinPlot
-- pass now grants -- the two structures share one hoard and one health pool (two doors into
-- the same warehouse), so nothing about how the hoard is stored has to change.
ItemConfig.BodegaSlotPass = "ExtraCabinPlot"

ItemConfig.BagPass = "DiverBag"
ItemConfig.DropLifetime = 180 -- seconds a dropped item waits on the seabed before it dissolves
ItemConfig.PickupRange = 12

function ItemConfig.TierFor(index)
	return ItemConfig.BagTiers[math.clamp(index or 1, 1, #ItemConfig.BagTiers)]
end

-- Raw slot usage, which can be fractional because glowsticks are a fifth of a slot each.
-- Bag space counts EQUIPMENT only. Finds are carried separately and never crowd out a tank.
function ItemConfig.SlotsUsed(inventory)
	local used = 0
	for key, count in pairs(inventory or {}) do
		local item = ItemConfig.Items[key]
		if item and type(count) == "number" then
			used += item.slots * count
		end
	end
	return used
end

-- What a sack of finds is worth at the Palengke counter.
function ItemConfig.LootValue(finds)
	local total, pieces = 0, 0
	for key, count in pairs(finds or {}) do
		local loot = ItemConfig.Loot[key]
		if loot and type(count) == "number" and count > 0 then
			total += loot.sell * count
			pieces += count
		end
	end
	return total, pieces
end

-- What the player is shown. Rounds up, so a part-used slot never reads as free space.
function ItemConfig.SlotsShown(inventory)
	return math.ceil(ItemConfig.SlotsUsed(inventory) - 0.0001)
end

-- How much room a purchase needs: packs are bought whole.
function ItemConfig.PurchaseSlots(item)
	return item.slots * (item.bundle or 1)
end

function ItemConfig.SortedItems()
	local list = {}
	for _, item in pairs(ItemConfig.Items) do
		table.insert(list, item)
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

return ItemConfig
