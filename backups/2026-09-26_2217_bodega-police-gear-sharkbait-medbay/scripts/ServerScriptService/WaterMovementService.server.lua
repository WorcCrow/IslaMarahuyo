-- WaterMovementService
-- Owns "is this player in or near water", and nerfs jumping there.
--
-- Two things were wrong at the waterline: you could launch out of the sea as high as you
-- can jump on land, and you could spam-hop at the surface to skip across water (and to
-- refill air without ever properly surfacing). Both are fixed here.
--
-- Important: the nerf NEVER applies while the Humanoid is actually Swimming. Jump input
-- is what drives swim-ascent underwater, so zeroing the jump mid-dive would trap players
-- at the bottom of the cave system. The reduced jump and the cooldown only apply in the
-- brief window right after you leave the water -- which is exactly the surface hop.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NORMAL_JUMP_HEIGHT = 7.2 -- matches StarterPlayer.CharacterJumpHeight
local NORMAL_JUMP_POWER = 50
local WATER_JUMP_HEIGHT = 2.4 -- about a third of a land jump
local WATER_JUMP_POWER = 18
local JUMP_COOLDOWN = 8 -- seconds before another jump is allowed at the waterline
local WATER_GRACE = 2.5 -- how long after leaving water you still count as "at the surface"

local state = {} -- [userId] = {lastSwim=, cooldownUntil=, jumpConn=}

-- The place uses JumpHeight (StarterPlayer.CharacterUseJumpPower = false), but handle
-- both so this keeps working if that setting is ever flipped.
local function setJump(humanoid, waterMode, blocked)
	if humanoid.UseJumpPower then
		humanoid.JumpPower = blocked and 0 or (waterMode and WATER_JUMP_POWER or NORMAL_JUMP_POWER)
	else
		humanoid.JumpHeight = blocked and 0 or (waterMode and WATER_JUMP_HEIGHT or NORMAL_JUMP_HEIGHT)
	end
end

local function stateFor(player)
	local s = state[player.UserId]
	if not s then
		s = { lastSwim = -math.huge, cooldownUntil = 0 }
		state[player.UserId] = s
	end
	return s
end

local function hookCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local s = stateFor(player)
	if s.jumpConn then
		s.jumpConn:Disconnect()
	end
	-- A jump that starts while you're at the waterline arms the cooldown.
	s.jumpConn = humanoid.Jumping:Connect(function(active)
		if not active then
			return
		end
		if os.clock() - s.lastSwim < WATER_GRACE then
			s.cooldownUntil = os.clock() + JUMP_COOLDOWN
		end
	end)
end

local function onPlayerAdded(player)
	stateFor(player)
	if player.Character then
		hookCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		local s = stateFor(player)
		s.lastSwim = -math.huge
		s.cooldownUntil = 0
		hookCharacter(player, character)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local s = state[player.UserId]
	if s and s.jumpConn then
		s.jumpConn:Disconnect()
	end
	state[player.UserId] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- ReviveService owns the character completely while a player is down at the Health
		-- Post; writing JumpHeight here would undo the freeze it just applied.
		if humanoid and not player:GetAttribute("Reviving") then
			local s = stateFor(player)
			local swimming = humanoid:GetState() == Enum.HumanoidStateType.Swimming
			if swimming then
				s.lastSwim = now
			end
			local nearWater = swimming or (now - s.lastSwim < WATER_GRACE)

			if swimming then
				-- never touch the jump while submerged: it's the swim-ascend control
				setJump(humanoid, false, false)
			elseif nearWater then
				setJump(humanoid, true, now < s.cooldownUntil)
			else
				setJump(humanoid, false, false)
			end

			player:SetAttribute("InWater", swimming)
			player:SetAttribute("NearWater", nearWater)
		end
	end
end)

print("[WaterMovementService] Waterline jump nerf online -- water jump", WATER_JUMP_HEIGHT, "studs,", JUMP_COOLDOWN .. "s cooldown")
