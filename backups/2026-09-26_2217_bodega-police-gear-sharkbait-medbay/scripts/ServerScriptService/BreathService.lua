-- BreathService
-- Server-authoritative underwater breath meter. The CEILING is still not pay-gated: max
-- breath only grows by finding Lung Corals inside the cave system (skill/exploration),
-- never by spending Shells or Robux. The current bar is now a different matter -- an Oxygen
-- Tank bought with Shells refills it in full, anywhere (see M.Refill, driven by
-- InventoryService). That was a deliberate call taken knowing it softens the cave, and it
-- is written down here so this header stops claiming a rule the game no longer keeps. The cave's hub and rest chambers are "air pockets" that
-- refill breath fast even while still swimming, so resting there is a real relief valve.
-- Running out of air is a short, low-friction inconvenience (see RECOVERY_SECONDS), not a
-- long forced-wait penalty -- see the design notes in the V2 roadmap for why.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local ReviveService = require(script.Parent.ReviveService)
local CurrencyService = require(script.Parent.CurrencyService)
local CaveGen = require(game.ServerStorage.CaveGen)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local breathUpdated = remotes:WaitForChild("BreathUpdated")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

-- Fired where the diver went down; InventoryService turns it into a recoverable stash.
local drownedSignal = game:GetService("ServerStorage"):WaitForChild("PlayerDrowned")

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = false

local M = {}

local BASE_BREATH = 45
local UPGRADE_BONUS = 15
local MAX_UPGRADES = 3
local DRAIN_PER_SEC = 1
local REGEN_PER_SEC = 3
-- Cave air pockets used to refill faster than standing on dry land (10/s vs 3/s) -- free
-- top-ups that undercut the whole point of a dangerous cave. Now they're 60% SLOWER than
-- land instead: topping off in a grotto is a real time cost, not a reset button, so a
-- diver has to weigh "wait here and breathe" against "push on while I still have air".
local AIR_POCKET_REGEN_PER_SEC = REGEN_PER_SEC * 0.4 -- 1.2/s
local RESCUE_THRESHOLD = 12 -- seconds of air left that arms the guardian-creature rescue
-- You have to be properly out of the water for this long before air starts coming back.
-- Without it, every non-swimming frame refilled air at 3/sec against a 1/sec drain, so
-- bobbing at the surface -- jump, clip out of Swimming state for a frame, drop back in --
-- refilled your lungs faster than diving emptied them. Now hopping gains you nothing:
-- the meter simply holds until you've actually surfaced and stayed there.
local SURFACE_SETTLE = 3

-- Drowning costs Shells so it can't be used as a free fast-travel home, or as a way to
-- reset a dive for nothing. Scaled rather than flat: a percentage of what you're carrying,
-- capped, so it stings a rich diver without wiping out somebody's first hour.
local DROWN_FEE_FRACTION = 0.15
local DROWN_FEE_CAP = 25
local RECOVERY_SECONDS = ReviveService.REVIVE_SECONDS -- the full revive sequence at the Health Post

M.BASE_BREATH = BASE_BREATH
M.UPGRADE_BONUS = UPGRADE_BONUS
M.MAX_UPGRADES = MAX_UPGRADES
M.RESCUE_THRESHOLD = RESCUE_THRESHOLD

local runtime = {} -- [userId] = {breath=, max=, drowning=, lastSent=}

local AIR_POCKETS = {}
for _, node in pairs(CaveGen.Nodes) do
	if node.kind == "hub" or node.kind == "rest" then
		table.insert(AIR_POCKETS, node)
	end
end

local function maxBreathFor(profile)
	return BASE_BREATH + math.min(profile.BreathUpgrades or 0, MAX_UPGRADES) * UPGRADE_BONUS
end

local function waitForProfile(player, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local p = PlayerProfileService.Get(player.UserId)
		if p then
			return p
		end
		task.wait(0.5)
	end
	return PlayerProfileService.Get(player.UserId)
end

function M.InitPlayer(player)
	task.spawn(function()
		local profile = waitForProfile(player, 15)
		local max = profile and maxBreathFor(profile) or BASE_BREATH
		runtime[player.UserId] = { breath = max, max = max, drowning = false, lastSent = 0 }
		player:SetAttribute("BreathMax", max)
		player:SetAttribute("Breath", max)
		player:SetAttribute("Drowns", (profile and profile.Drowns) or 0)
	end)
end

function M.RemovePlayer(player)
	runtime[player.UserId] = nil
end

-- Called when a player collects a Lung Coral. Returns true + new count on success,
-- false + "max" if they've already found all 3.
function M.AddUpgrade(player)
	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return false, "no_profile"
	end
	if (profile.BreathUpgrades or 0) >= MAX_UPGRADES then
		return false, "max"
	end
	profile.BreathUpgrades = (profile.BreathUpgrades or 0) + 1
	local r = runtime[player.UserId]
	if r then
		r.max = maxBreathFor(profile)
		r.breath = math.min(r.max, r.breath + UPGRADE_BONUS)
		player:SetAttribute("BreathMax", r.max)
		player:SetAttribute("Breath", r.breath)
	end
	return true, profile.BreathUpgrades
end

local function inAirPocket(pos)
	for _, node in ipairs(AIR_POCKETS) do
		local dx, dy, dz = pos.X - node.x, pos.Y - node.y, pos.Z - node.z
		if (dx * dx + dy * dy + dz * dz) < (node.r * 0.85) ^ 2 then
			return true
		end
	end
	return false
end
M.InAirPocket = inAirPocket

-- Running out of air hands the player to ReviveService, which owns the whole 20-second
-- sequence in a scanner bay (held upright, medic working, staged countdown) and gives control back
-- at the end. Breath is restored here so they surface from it topped up.
local function drown(player, r)
	if r.drowning then
		return
	end
	r.drowning = true
	r.breath = r.max
	player:SetAttribute("Breath", r.breath)

	-- Drown count is persisted and shown on the plaza leaderboard -- a running tally of
	-- how badly the cave has beaten you, which is its own kind of bragging right.
	local profile = PlayerProfileService.Get(player.UserId)
	if profile then
		profile.Drowns = (profile.Drowns or 0) + 1
		player:SetAttribute("Drowns", profile.Drowns)
	end

	-- The old clinic fee is gone. Drowning now drops everything you were carrying where
	-- you went down (InventoryService owns that), and taking a cut on top would be
	-- punishing the same mistake twice.
	local where = nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		where = root.CFrame
	end
	drownedSignal:Fire(player, where)

	diveFeedback:FireClient(player, "drown",
		"You ran out of air and blacked out -- everything you carried sank where you fell. "
			.. "Nurse Fely is bringing you back at the Health Post.",
		RECOVERY_SECONDS)

	local started = ReviveService.Begin(player, function()
		r.drowning = false
	end)

	if not started then
		-- no character to revive (respawning, leaving); just clear the lock
		task.delay(1, function()
			r.drowning = false
		end)
	end
end
M.Drown = drown

-- Called by RescueCreatureService once the guardian creature reaches a critically-low
-- player: tops them back up to a partial amount rather than a full refill, so the save
-- still matters but isn't a free pass.
function M.RescueBoost(player)
	local r = runtime[player.UserId]
	if not r then
		return
	end
	r.breath = math.max(r.breath, r.max * 0.45)
	player:SetAttribute("Breath", r.breath)
	breathUpdated:FireClient(player, r.breath, r.max, true)
end

-- A full top-up, spent from an Oxygen Tank. RescueBoost above is deliberately partial
-- because the guardian creature is a free save; this one is not, because it was paid for.
-- Returns false when there was nothing to refill, so the caller can avoid eating the item.
function M.Refill(player)
	local r = runtime[player.UserId]
	if not r or r.breath >= r.max then
		return false
	end
	r.breath = r.max
	player:SetAttribute("Breath", r.breath)
	breathUpdated:FireClient(player, r.breath, r.max, true)
	return true
end

function M.GetRuntime(player)
	return runtime[player.UserId]
end

-- True once a player's air is low enough for the rescue creature to consider them,
-- and they haven't already drowned this episode.
function M.IsCritical(player)
	local r = runtime[player.UserId]
	return r and not r.drowning and r.breath <= RESCUE_THRESHOLD and r.breath > 0
end

-- Trusting Humanoid:GetState() alone lets a player dodge the drain below by spamming the
-- jump key: WaterMovementService zeroes JumpPower/JumpHeight during the water-jump
-- cooldown, but the Humanoid state still flickers to Jumping/Freefall on every press even
-- though a 0-power jump goes nowhere, and that alone was enough to read as "not swimming".
-- This checks whether the player is still physically inside a body of water regardless of
-- what the FSM says this frame, so bouncing at the surface no longer pauses the air clock.
local function isPositionInWaterBody(pos)
	local check = workspace:Raycast(Vector3.new(pos.X, pos.Y + 8, pos.Z), Vector3.new(0, -16, 0), terrainParams)
	if not check or check.Material ~= Enum.Material.Water then
		return false
	end
	local floorCheck = workspace:Raycast(Vector3.new(pos.X, check.Position.Y - 1, pos.Z), Vector3.new(0, -200, 0), terrainParams)
	local floorY = floorCheck and floorCheck.Position.Y or (check.Position.Y - 50)
	return pos.Y <= check.Position.Y and pos.Y > floorY
end

local function heartbeat(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local r = runtime[player.UserId]
		local character = player.Character
		if r and character and not r.drowning then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if humanoid and hrp then
				local now = os.clock()
				local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
				local rawSwimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
				-- still counts as swimming if they're airborne/ungrounded but physically still in
				-- the water -- catches the jump-spam FSM flicker described above
				local swimming = rawSwimming or (not grounded and isPositionInWaterBody(hrp.Position))
				if swimming then
					r.lastSwimAt = now
				end
				-- air pockets count whether or not you're swimming, so the dry cave chambers
				-- actually refill you now (they never did before -- that branch was dead)
				local atAirPocket = inAirPocket(hrp.Position)
				local settled = (now - (r.lastSwimAt or -math.huge)) >= SURFACE_SETTLE

				if swimming and not atAirPocket then
					r.breath = math.max(0, r.breath - DRAIN_PER_SEC * dt)
					if r.breath <= 0 then
						drown(player, r)
					end
				elseif atAirPocket then
					r.breath = math.min(r.max, r.breath + AIR_POCKET_REGEN_PER_SEC * dt)
				elseif settled and grounded then
					r.breath = math.min(r.max, r.breath + REGEN_PER_SEC * dt)
				end
				-- anything else (just surfaced, mid-air, treading at the waterline) holds steady
				player:SetAttribute("Breath", r.breath)
				r.lastSent = (r.lastSent or 0) + dt
				if r.lastSent > 0.25 then
					r.lastSent = 0
					breathUpdated:FireClient(player, r.breath, r.max, swimming)
				end
			end
		end
	end
end

local initialized = false
function M.Init()
	if initialized then
		return
	end
	initialized = true
	for _, player in ipairs(Players:GetPlayers()) do
		M.InitPlayer(player)
	end
	Players.PlayerAdded:Connect(M.InitPlayer)
	Players.PlayerRemoving:Connect(M.RemovePlayer)
	RunService.Heartbeat:Connect(heartbeat)
end

return M
