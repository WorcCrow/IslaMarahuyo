-- InventoryService
-- Carryable gear: what a diver owns, how much of it fits in their bag, and what happens
-- when they hand it to someone else.
--
-- Everything here is server-side. The client sends intent ("buy a battery", "drop a tank")
-- and gets a fresh snapshot back; it never states what it owns. Dropping spawns a real
-- model in the world that anyone can pick up, which is the whole point -- gear is shared by
-- physically passing it, and bag capacity is what stops one diver carrying the team's kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local CurrencyService = require(script.Parent.CurrencyService)
local PlayerProfileService = require(script.Parent.PlayerProfileService)
local LootService = require(script.Parent.LootService)
local GamePassService = require(script.Parent.GamePassService)
local BreathService = require(script.Parent.BreathService)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestItemBuy = remotes:WaitForChild("RequestItemBuy")
local requestItemUse = remotes:WaitForChild("RequestItemUse")
local requestItemDrop = remotes:WaitForChild("RequestItemDrop")
local requestBagUpgrade = remotes:WaitForChild("RequestBagUpgrade")
local requestSellLoot = remotes:WaitForChild("RequestSellLoot")
local requestTransfer = remotes:FindFirstChild("RequestTransfer")
if not requestTransfer then
	requestTransfer = Instance.new("RemoteEvent")
	requestTransfer.Name = "RequestTransfer"
	requestTransfer.Parent = remotes
end
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local itemFeedback = remotes:WaitForChild("ItemFeedback")

-- Gear is sold at the Palengke and nowhere else. If you are deep in the cave and out of
-- air, the only way to get more is for a teammate to drop you theirs -- which is the point.
local MARKET_RADIUS = 65
local DROP_COOLDOWN = 0.4

local marketZone do
	local isla = workspace:FindFirstChild("IslaMarahuyo")
	local zones = isla and isla:FindFirstChild("Zones")
	marketZone = zones and zones:FindFirstChild("PalengkeMarket")
end

local dropsFolder = workspace:FindFirstChild("DroppedGear")
if not dropsFolder then
	dropsFolder = Instance.new("Folder")
	dropsFolder.Name = "DroppedGear"
	dropsFolder.Parent = workspace
end

local lastDrop = {}

-- Two in-game days, the same clock the glowsticks use: DayNightCycle runs a day in 24
-- real minutes, so a stash keeps for 48 real minutes before the cave swallows it.
local STASH_LIFETIME = 2 * 24 * 60
local drownedSignal = ServerStorage:WaitForChild("PlayerDrowned")
local refreshSignal = ServerStorage:WaitForChild("InventoryRefresh")
-- Announces a sale so the Palengke can put the goods on its shelves. A BindableEvent
-- rather than a direct call because MarketShiftService is a Script, and a Script cannot
-- be required -- the same reason InventoryRefresh exists.
local marketSold = ServerStorage:WaitForChild("MarketSold")
-- BodegaService asks for a broken bodega's contents to be spilled through here, for the
-- same Script-cannot-be-required reason as above.
local scatterItems = ServerStorage:FindFirstChild("ScatterItems")
if not scatterItems then
	scatterItems = Instance.new("BindableEvent")
	scatterItems.Name = "ScatterItems"
	scatterItems.Parent = ServerStorage
end

local function profileOf(player)
	return PlayerProfileService.Get(player.UserId)
end

local function say(player, message, ok)
	itemFeedback:FireClient(player, message, ok and true or false)
end

local function capacityOf(player, profile)
	local tierIndex = profile.BagTier or 1
	-- the pass hands over the biggest bag outright, without rewriting what they bought
	if GamePassService.Owns(player, ItemConfig.BagPass) then
		tierIndex = math.max(tierIndex, #ItemConfig.BagTiers)
	end
	local tier = ItemConfig.TierFor(tierIndex)
	return tier.slots, tier, tierIndex
end

local function push(player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	profile.Inventory = profile.Inventory or {}
	profile.Gear = profile.Gear or {}
	local slots, tier, tierIndex = capacityOf(player, profile)
	profile.Finds = profile.Finds or {}
	local lootValue, lootPieces = ItemConfig.LootValue(profile.Finds)
	inventoryUpdated:FireClient(player, {
		-- `items` stays the carried bag, so every existing HUD read keeps working
		items = profile.Gear,
		bodega = profile.Inventory,
		finds = profile.Finds,
		lootValue = lootValue,
		lootPieces = lootPieces,
		used = ItemConfig.SlotsShown(profile.Gear),
		capacity = slots,
		tierKey = tier.key,
		tierLabel = tier.label,
		tierIndex = tierIndex,
		owned = #ItemConfig.BagTiers,
		passBag = GamePassService.Owns(player, ItemConfig.BagPass),
	})
end

-- Everything below counts the CARRIED bag unless it says otherwise. The bodega
-- (profile.Inventory) is uncapped and is only touched by buying and transfers.
local function countOf(profile, key)
	return (profile.Gear or {})[key] or 0
end

local function bodegaCountOf(profile, key)
	return (profile.Inventory or {})[key] or 0
end

-- No capacity check: the bodega is deliberately unlimited.
local function giveBodega(profile, key, n)
	profile.Inventory = profile.Inventory or {}
	profile.Inventory[key] = math.max(0, bodegaCountOf(profile, key) + n)
	if profile.Inventory[key] == 0 then
		profile.Inventory[key] = nil
	end
end

-- forward-declared: give() below calls it, but it needs countOf/capacityOf defined first
local syncTools

local function give(player, profile, key, n)
	profile.Gear = profile.Gear or {}
	profile.Gear[key] = math.max(0, countOf(profile, key) + n)
	if profile.Gear[key] == 0 then
		profile.Gear[key] = nil
	end
	syncTools(player, profile)
	push(player)
end

-- `needed` lets a pack be checked as a whole: you cannot buy ten glowsticks into room for two.
local function roomFor(player, profile, item, needed)
	local slots = capacityOf(player, profile)
	return ItemConfig.SlotsUsed(profile.Gear) + (needed or item.slots) <= slots + 0.0001
end

-- How many whole units of `item` would still fit in the carried bag right now.
local function unitsThatFit(player, profile, item)
	local slots = capacityOf(player, profile)
	local free = slots - ItemConfig.SlotsUsed(profile.Gear)
	if item.slots <= 0 then
		return math.huge
	end
	return math.max(0, math.floor((free + 0.0001) / item.slots))
end

local function atMarket(player)
	if not marketZone then
		-- fail open rather than lock the shop out of the game entirely if the zone is renamed
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - marketZone.Position).Magnitude <= MARKET_RADIUS
end

-- Carried gear rides in the hotbar, so using it is one click (one tap on a phone) instead of
-- a trip into a menu -- and the screen needs no separate button for each item.
local TOOL_FOR = {
	oxygen = {prefab = "OxygenTool", name = "OxygenTank", tip = "Crack it open for a full lungful (x%d)"},
	glowstick = {prefab = "GlowstickTool", name = "Glowstick", tip = "Drop one to mark the way back (x%d)"},
	tolda = {prefab = "ToldaTool", name = "Tolda", tip = "Pitch a stall right here (x%d)"},
	sharkbait = {prefab = "SharkBaitTool", name = "SharkBait", tip = "Hold to lure sharks, click to throw a decoy (x%d)"},
	-- Only a picture of what you carry: staking is LambatController's H button and never
	-- needed the net in hand.
	lambat = {prefab = "LambatTool", name = "Lambat", tip = "Stand in open water and press H to stake it (x%d)"},
}

-- Dive gear only reaches the hotbar while the owner's bodega stands somewhere: the bodega
-- is the base you kit up from, so a diver who never puts one down goes in empty-handed.
-- Not the tolda -- a stall is the black-market alternative to a bodega, and a pitched
-- stall's tool must stay in hand to pack it back up.
local BODEGA_GATED = {oxygen = true, glowstick = true, sharkbait = true, lambat = true}

-- A phone's hotbar shows only its first three slots, and the backpack fills slots in the
-- order tools arrive -- so the StarterPack weapons used to push dive gear off-screen.
-- Re-seating in this order keeps what a diver needs in the slots a phone can see.
-- The axe sits third so it is on a phone's hotbar for everyone: at fifth, anyone carrying
-- an oxygen tank and glowsticks (most regular players) had it pushed off-screen.
local HOTBAR_RANK = {Flashlight = 1, OxygenTank = 2, Axe = 3, Glowstick = 4, SharkBait = 5, Lambat = 6, Tolda = 7, Binoculars = 8}

local reseating = {} -- [backpack] = {[toolName] = tool} while a re-seat is between frames

local function reseat(backpack)
	local tools = {}
	for i, t in ipairs(backpack:GetChildren()) do
		if t:IsA("Tool") then
			table.insert(tools, {tool = t, i = i})
		end
	end
	table.sort(tools, function(a, b)
		local ra, rb = HOTBAR_RANK[a.tool.Name] or 99, HOTBAR_RANK[b.tool.Name] or 99
		if ra ~= rb then
			return ra < rb
		end
		return a.i < b.i
	end)
	local pending = {}
	for _, e in ipairs(tools) do
		pending[e.tool.Name] = e.tool
		e.tool.Parent = nil
	end
	reseating[backpack] = pending
	-- Detach and re-attach on separate frames. Done in one frame, replication collapses the
	-- two moves into none and clients keep the StarterPack order -- which put both blasters
	-- ahead of the axe and pushed it off a phone's three-slot hotbar.
	task.spawn(function()
		RunService.Heartbeat:Wait()
		reseating[backpack] = nil
		if not backpack.Parent then
			return
		end
		for _, e in ipairs(tools) do
			if e.tool.Parent == nil then
				pcall(function()
					e.tool.Parent = backpack
				end)
			end
		end
	end)
end

function syncTools(player, profile, forceReseat)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local character = player.Character
	local added = false
	for key, spec in pairs(TOOL_FOR) do
		local held = (character and character:FindFirstChild(spec.name)) or backpack:FindFirstChild(spec.name)
			or (reseating[backpack] and reseating[backpack][spec.name])
		local count = countOf(profile, key)
		local keep = count > 0
		if BODEGA_GATED[key] and player:GetAttribute("BodegaUp") ~= true then
			keep = false
		end
		local tip = string.format(spec.tip, count)
		if key == "tolda" then
			-- pitched straight out of the bodega as well as the bag (BlackMarketService), and
			-- the same tool packs the stall back up while one is standing
			count += bodegaCountOf(profile, key)
			local up = player:GetAttribute("ToldaUp") == true
			keep = count > 0 or up
			tip = up and "Pack up your stall" or string.format(spec.tip, count)
		end

		if keep and not held then
			local prefab = ServerStorage.ItemAssets:FindFirstChild(spec.prefab)
			if prefab then
				local clone = prefab:Clone()
				clone.Name = spec.name
				clone.ToolTip = tip
				clone.Parent = backpack
				added = true
			end
		elseif not keep and held then
			held:Destroy()
		elseif held then
			held.ToolTip = tip
		end
	end
	if added or forceReseat then
		reseat(backpack)
	end
end

-- ===== buying =====
requestItemBuy.OnServerEvent:Connect(function(player, key)
	local item = ItemConfig.Items[key]
	local profile = profileOf(player)
	if not item or not profile then
		return
	end

	if ItemConfig.IsContraband(key) then
		-- the Palengke is a licensed market; it does not sell the means to avoid itself
		say(player, "No honest stall sells that. Ask around Terminal Cove.", false)
		return
	end
	if not atMarket(player) then
		say(player, "You can only buy gear at the Palengke -- or ask a teammate to drop you one.", false)
		return
	end
	local bundle = item.bundle or 1
	local bought = bundle > 1
		and string.format("%d %ss", bundle, item.short)
		or item.short
	-- A purchase goes into the bag on your back, never straight into the bodega: stocking
	-- the storehouse means carrying it there yourself. So a full bag refuses the sale up
	-- front rather than taking the money for something with nowhere to go.
	if not roomFor(player, profile, item, ItemConfig.PurchaseSlots(item)) then
		say(player, string.format("No room in your bag for %s -- stow gear at your bodega first.", bought), false)
		return
	end
	if not CurrencyService.TrySpend(player, item.price, "Item_" .. key) then
		say(player, string.format("%s costs %d Peso -- go earn a bit first.",
			bundle > 1 and ("A pack of " .. bundle .. " " .. string.lower(item.short) .. "s") or ("A " .. item.short),
			item.price), false)
		return
	end

	give(player, profile, key, bundle) -- give() re-syncs tools and pushes for us
	say(player, string.format("%s in your bag. -%d Peso.", bought, item.price), true)
end)

-- ===== using =====
requestItemUse.OnServerEvent:Connect(function(player, key)
	local item = ItemConfig.Items[key]
	local profile = profileOf(player)
	if not item or not profile or countOf(profile, key) <= 0 then
		return
	end

	if item.usable == false then
		say(player, string.format("A %s isn't used -- drop it to light the way.", item.short), false)
		return
	end

	if key == "battery" then
		if (profile.FlashlightBattery or 0) >= 100 then
			say(player, "That battery is already full.", false)
			return
		end
		-- FlashlightService reads the same profile field every tick, so writing it here is
		-- all the handoff that is needed between the two.
		profile.FlashlightBattery = 100
		player:SetAttribute("FlashlightBattery", 100)
		give(player, profile, key, -1)
		say(player, "Fresh battery fitted.", true)
		return
	end

	if key == "oxygen" then
		if not BreathService.Refill(player) then
			say(player, "Your lungs are already full.", false)
			return
		end
		give(player, profile, key, -1)
		say(player, "You crack the tank -- a full lungful.", true)
		return
	end
end)

-- ===== dropping and picking up =====
-- Finds have no model of their own, so they drop as a glowing nodule in the loot's own
-- colour. Gear uses its real prefab.
local function lootModel(item)
	local model = Instance.new("Model")
	local nodule = Instance.new("Part")
	nodule.Name = "Find"
	nodule.Shape = Enum.PartType.Ball
	nodule.Size = Vector3.new(1.5, 1.5, 1.5) * (item.slots >= 1 and 1.5 or 1)
	nodule.Material = Enum.Material.Neon
	nodule.Color = item.color or Color3.fromRGB(230, 230, 230)
	nodule.Parent = model

	local glow = Instance.new("PointLight")
	glow.Color = nodule.Color
	glow.Brightness = 1.8
	glow.Range = 16
	glow.Shadows = false
	glow.Parent = nodule

	model.PrimaryPart = nodule
	return model
end

local function makePickup(key, count, cframe)
	local item = ItemConfig.Find(key)
	if not item then
		return nil
	end

	local prefab = item.asset and ServerStorage.ItemAssets:FindFirstChild(item.asset)
	if not prefab and not ItemConfig.IsLoot(key) then
		return nil
	end

	local model = prefab and prefab:Clone() or lootModel(item)
	model.Name = "Dropped_" .. key
	model:SetAttribute("ItemKey", key)
	model:SetAttribute("Count", count)

	local primary = model.PrimaryPart
	if primary then
		model:PivotTo(cframe)
	end

	-- These prefabs are loose part salads off the Creator Store. Weld them to the primary
	-- BEFORE unanchoring or the drop bursts apart the moment it lands.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and primary and d ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = d
			weld.Parent = primary
		end
	end

	-- Finds are placed on verified clear ground and pinned there. Letting them roll is how
	-- a haul ends up wedged in a crevice you cannot reach.
	local pin = ItemConfig.IsLoot(key)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = pin
			d.CanCollide = not pin
			d.CanQuery = true
			d.CanTouch = false
		end
	end

	-- Gear gets dropped for teammates in a pitch-black cave, so it has to be findable
	-- without a flashlight pointed straight at it.
	if primary and item.glow then
		local glow = Instance.new("PointLight")
		glow.Color = item.glow
		glow.Brightness = 1.4
		glow.Range = 14
		glow.Shadows = false
		glow.Parent = primary

		local halo = Instance.new("Highlight")
		halo.FillColor = item.glow
		halo.FillTransparency = 0.75
		halo.OutlineColor = item.glow
		halo.OutlineTransparency = 0.2
		halo.DepthMode = Enum.HighlightDepthMode.Occluded
		halo.Parent = model
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = count > 1 and string.format("%s x%d", item.label, count) or item.label
	prompt.ActionText = "Pick up"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = ItemConfig.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary or model

	prompt.Triggered:Connect(function(player)
		local profile = profileOf(player)
		if not profile or not model.Parent then
			return
		end
		local want = model:GetAttribute("Count") or 1
		if ItemConfig.IsLoot(key) then
			-- finds never need room; they go straight back into the sack
			LootService.Give(player, key, want)
		else
			if not roomFor(player, profile, item, item.slots * want) then
				say(player, string.format("No room for %s -- your bag is full.", item.short), false)
				return
			end
			give(player, profile, key, want)
		end
		say(player, string.format("Picked up a %s.", item.short), true)
		model:Destroy()
	end)

	model.Parent = dropsFolder
	-- A dropped find keeps for two in-game days, same as a glowstick: long enough to swim
	-- back for it, short enough that the cave floor does not fill up with other people's
	-- bad dives.
	local lifetime = item.dropLifetime
		or (ItemConfig.IsLoot(key) and STASH_LIFETIME)
		or ItemConfig.DropLifetime
	Debris:AddItem(model, lifetime)

	-- Trail markers have to stay where they were put. Let physics drop them onto the floor,
	-- then pin them, or a trail laid down a slope ends up in a heap at the bottom.
	if item.settles then
		task.delay(1.5, function()
			if not model.Parent then
				return
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
		end)
	end

	return model
end

requestItemDrop.OnServerEvent:Connect(function(player, key)
	local item = ItemConfig.Items[key]
	local profile = profileOf(player)
	if not item or not profile or countOf(profile, key) <= 0 then
		return
	end

	local now = os.clock()
	if now - (lastDrop[player.UserId] or 0) < DROP_COOLDOWN then
		return
	end
	lastDrop[player.UserId] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local spot = root.CFrame * CFrame.new(0, 0, -3)
	if not makePickup(key, 1, spot) then
		say(player, "That won't come out of the bag.", false)
		return
	end

	give(player, profile, key, -1)
	say(player, string.format("Dropped a %s.", item.short), true)
end)

-- ===== selling finds =====
-- Peso is money and money is safe. Finds are objects and objects are not -- the only way
-- one becomes the other is by carrying it up to this counter alive.
requestSellLoot.OnServerEvent:Connect(function(player)
	local profile = profileOf(player)
	if not profile then
		return
	end
	if not atMarket(player) then
		say(player, "The buyer is at the Palengke -- bring your finds to him.", false)
		return
	end

	local earned, pieces, sold = LootService.SellAll(player)
	if pieces <= 0 then
		say(player, "Nothing to sell -- your bag has no finds in it.", false)
		return
	end

	-- the goods now belong to the market and have to physically turn up on its shelves
	marketSold:Fire(player, sold, earned)
	CurrencyService.AddShells(player, earned, true, "LootSold")
	say(player, string.format("Sold %d find%s for %d Peso.", pieces, pieces == 1 and "" or "s", earned), true)
end)

-- ===== the drowned diver's stash =====
-- Money never sinks. Peso is banked the moment you sell at the Palengke, so drowning
-- costs you the trip, not the bank -- what you lose is the sack of finds and the gear you
-- were carrying, scattered across the floor where you went down.
--
-- Placement is the fiddly part. A haul dropped blindly ends up inside rock or through the
-- floor, which is the same as deleting it. Every piece is therefore placed somewhere with
-- clear line of sight from the body, settled onto whatever is beneath it, and anchored --
-- so a find is always visible from where you died and never rolls into a crevice.
local scatterParams = RaycastParams.new()
scatterParams.FilterType = Enum.RaycastFilterType.Exclude
scatterParams.IgnoreWater = true

-- `spread` widens the ring as the index grows (a sunflower layout), for spills big enough
-- that one fixed ring would pile everything on top of itself.
local function recoverableSpot(origin, index, spread)
	scatterParams.FilterDescendantsInstances = {dropsFolder}

	for attempt = 1, 12 do
		local angle = index * 2.39996 + attempt * 0.55 -- golden angle: spreads, never stacks
		local radius = 2 + (attempt * 0.9) + (spread and math.sqrt(index) * 1.3 or 0)
		local candidate = origin + Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)

		-- reachable means visible: if rock sits between the body and the spot, try again
		if not workspace:Raycast(origin, candidate - origin, scatterParams) then
			local floor = workspace:Raycast(candidate, Vector3.new(0, -14, 0), scatterParams)
			local resting = floor and (floor.Position + Vector3.new(0, 1.2, 0)) or candidate
			-- and make sure the resting place itself is not buried
			if not workspace:Raycast(origin, resting - origin, scatterParams) then
				return CFrame.new(resting)
			end
		end
	end

	-- Nothing clear nearby: leave it at the body rather than risk burying it -- but still fanned
	-- out by index. Every piece that ends up here used to land on the exact same point, and a
	-- spill of ten read as a single glowstick in a heap.
	local angle = index * 2.39996
	local radius = 1.1 * math.sqrt(index)
	return CFrame.new(origin + Vector3.new(math.cos(angle) * radius, 1, math.sin(angle) * radius))
end

local function spawnStash(player, cframe)
	local profile = profileOf(player)
	if not profile or not cframe then
		return
	end

	-- finds live outside the bag now, so they are collected separately from the gear
	local haul = LootService.TakeAll(player)
	local carried = {}
	for key, count in pairs(haul) do
		carried[key] = count
	end
	-- Only the CARRIED bag scatters. The bodega is a storehouse on dry land; drowning
	-- with a hoard in it must never wipe the hoard.
	for key, count in pairs(profile.Gear or {}) do
		if ItemConfig.Items[key] and count > 0 then
			carried[key] = (carried[key] or 0) + count
		end
	end

	local stacks = 0
	for _ in pairs(carried) do
		stacks += 1
	end
	if stacks == 0 then
		return -- carrying nothing; nothing to scatter
	end

	-- strip the diver before anything spawns, so a failure between the two cannot duplicate
	profile.Gear = {}
	syncTools(player, profile)
	push(player)

	local origin = cframe.Position
	local index, droppedPieces = 0, 0

	for key, count in pairs(carried) do
		local item = ItemConfig.Find(key)
		-- bulky things drop one at a time; small stuff drops as a stack so a pack of
		-- glowsticks does not carpet the chamber
		local perDrop = (item.slots >= 0.5) and 1 or count
		local remaining = count
		while remaining > 0 do
			local batch = math.min(perDrop, remaining)
			remaining -= batch
			index += 1
			droppedPieces += batch
			makePickup(key, batch, recoverableSpot(origin, index))
		end
	end

	say(player, string.format("You went down carrying %d piece%s -- they are on the floor where you fell.",
		droppedPieces, droppedPieces == 1 and "" or "s"), false)
end

drownedSignal.Event:Connect(spawnStash)
refreshSignal.Event:Connect(function(player)
	local profile = profileOf(player)
	if profile then
		syncTools(player, profile)
		push(player)
	end
end)

-- ===== buying from anyone else =====
-- Suki and the tolda stalls sell gear too, and those purchases follow the same rule as the
-- Palengke: into the bag or not at all. Returns false (and changes nothing) when it will
-- not fit, so the seller can refuse before any money moves.
local giveToBag = ServerStorage:FindFirstChild("GiveToBag")
if not giveToBag then
	giveToBag = Instance.new("BindableFunction")
	giveToBag.Name = "GiveToBag"
	giveToBag.Parent = ServerStorage
end
giveToBag.OnInvoke = function(player, key, count, checkOnly)
	local item = ItemConfig.Items[key]
	local profile = profileOf(player)
	count = math.floor(tonumber(count) or 0)
	if not item or not profile or count < 1 then
		return false
	end
	if not roomFor(player, profile, item, item.slots * count) then
		return false
	end
	if not checkOnly then
		give(player, profile, key, count)
	end
	return true
end

-- ===== a broken bodega =====
-- Everything spills one piece per pickup, so looting it takes time and the owner has a
-- window to get back. A hoard past MaxScatterPieces is grouped into small stacks so a
-- single break can never flood the server with hundreds of models.
scatterItems.Event:Connect(function(position, items)
	local total = 0
	for _, count in pairs(items) do
		if type(count) == "number" then
			total += count
		end
	end
	local per = math.max(1, math.ceil(total / ItemConfig.Bodega.MaxScatterPieces))
	local index = 0
	for key, count in pairs(items) do
		if ItemConfig.Find(key) and type(count) == "number" and count > 0 then
			local remaining = count
			while remaining > 0 do
				local batch = math.min(per, remaining)
				remaining -= batch
				index += 1
				makePickup(key, batch, recoverableSpot(position, index, true))
			end
		end
	end
end)

-- ===== moving gear between the bodega and the bag =====
-- The bodega holds everything; the bag is what you can actually carry into the water.
-- Packing is therefore a dry-land decision, and deliberately so: if you could pull a
-- fresh tank out of an unlimited bodega mid-dive, the bag tiers would mean nothing and
-- the whole gear economy would collapse into "buy once, never plan again".
requestTransfer.OnServerEvent:Connect(function(player, key, direction, count)
	local item = ItemConfig.Items[key]
	local profile = profileOf(player)
	if not item or not profile then
		return
	end
	if direction ~= "toGear" and direction ~= "toBodega" then
		return
	end

	-- clamp whatever the client asked for; never trust the count on the wire
	count = math.floor(tonumber(count) or 1)
	if count < 1 then
		return
	end

	-- BodegaService sets this only while the player's own bodega is standing and they are
	-- beside it, so a server attribute is the whole check.
	if player:GetAttribute("AtBodega") ~= true then
		say(player, "Stand at your own bodega to pack or stow -- place it first if it is not up.", false)
		return
	end

	if direction == "toGear" then
		local have = bodegaCountOf(profile, key)
		if have <= 0 then
			say(player, string.format("No %s in the bodega.", item.short), false)
			return
		end
		local moved = math.min(count, have, unitsThatFit(player, profile, item))
		if moved <= 0 then
			say(player, string.format("No room -- a %s needs %s slot%s.",
				item.short, tostring(item.slots), item.slots == 1 and "" or "s"), false)
			return
		end
		giveBodega(profile, key, -moved)
		give(player, profile, key, moved)
		say(player, string.format("Packed %d %s.", moved, item.short), true)
	else
		local have = countOf(profile, key)
		if have <= 0 then
			say(player, string.format("No %s in your bag.", item.short), false)
			return
		end
		local moved = math.min(count, have)
		giveBodega(profile, key, moved)
		give(player, profile, key, -moved)
		say(player, string.format("Stowed %d %s in the bodega.", moved, item.short), true)
	end
end)

-- ===== bag upgrades =====
requestBagUpgrade.OnServerEvent:Connect(function(player)
	local profile = profileOf(player)
	if not profile then
		return
	end

	if GamePassService.Owns(player, ItemConfig.BagPass) then
		say(player, "The pass already gives you the biggest bag there is.", false)
		return
	end

	local current = profile.BagTier or 1
	local nextTier = ItemConfig.BagTiers[current + 1]
	if not nextTier then
		say(player, "That is already the biggest bag on the island.", false)
		return
	end
	if not atMarket(player) then
		say(player, "Bags are sold at the Palengke.", false)
		return
	end
	if not CurrencyService.TrySpend(player, nextTier.price, "BagUpgrade_" .. nextTier.key) then
		say(player, string.format("A %s costs %d Peso.", nextTier.label, nextTier.price), false)
		return
	end

	profile.BagTier = current + 1
	push(player)
	say(player, string.format("You sling on a %s -- %d slots.", nextTier.label, nextTier.slots), true)
end)

-- ===== lifecycle =====
local function onPlayerAdded(player)
	task.spawn(function()
		for _ = 1, 150 do
			local profile = profileOf(player)
			if profile then
				profile.Inventory = profile.Inventory or {}
				profile.Gear = profile.Gear or {}
				profile.BagTier = profile.BagTier or 1
				syncTools(player, profile, true)
				push(player)
				player.CharacterAdded:Connect(function()
					task.wait(0.5)
					-- a fresh backpack arrives in StarterPack order; always re-seat it
					syncTools(player, profile, true)
				end)
				-- BodegaService flips this on placing, packing, a break-in and leaving; one
				-- listener here covers every one of them
				player:GetAttributeChangedSignal("BodegaUp"):Connect(function()
					syncTools(player, profile)
				end)
				return
			end
			task.wait(0.1)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	lastDrop[player.UserId] = nil
end)

-- The shop only appears when you can actually use it, and the server decides that -- the
-- client is never left guessing whether a purchase would be accepted.
local marketAccum = 0
RunService.Heartbeat:Connect(function(dt)
	marketAccum += dt
	if marketAccum < 0.4 then
		return
	end
	marketAccum = 0
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("AtPalengke", atMarket(player))
	end
end)

print(string.format("[InventoryService] gear online -- %d items, %d bag tiers",
	#ItemConfig.SortedItems(), #ItemConfig.BagTiers))
