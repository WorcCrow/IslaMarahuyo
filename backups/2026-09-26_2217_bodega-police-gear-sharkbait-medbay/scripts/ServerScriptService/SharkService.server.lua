-- SharkService (ServerScriptService)
-- Features: High-Intensity dynamic wiggle, explosive bite launch, 3x Sensory Buffs, 
-- dynamic day/night population scaling, underwater safety clamping, and leaping.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local BreathService = require(script.Parent.BreathService)
local SharkLure = require(script.Parent.SharkLure)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local diveFeedback = remotes:WaitForChild("DiveFeedback")

local sharkAlertUpdated = remotes:FindFirstChild("SharkAlertUpdated") or Instance.new("RemoteEvent", remotes)
sharkAlertUpdated.Name = "SharkAlertUpdated"

local sharkScare = remotes:FindFirstChild("SharkScare") or Instance.new("RemoteEvent", remotes)
sharkScare.Name = "SharkScare"

-- Configuration: Random Day & Night Ranges
local DAY_SHARK_MIN, DAY_SHARK_MAX = 20, 150      -- Safe Daytime Count
local NIGHT_SHARK_MIN, NIGHT_SHARK_MAX = 50, 200  -- High Density Night Count (>50 triggers warning)

local BITE_RANGE = 7
local BITE_BREATH_COST = 14 
local DISENGAGE_SECONDS = 10 

----------------------------------------------------
-- SHARK & PLAYER SPEED PARAMETERS --
----------------------------------------------------
local PLAYER_SWIM_SPEED = 8.4 
local CRUISE_SPEED = 14                   -- Patrolling speed
local CHASE_SPEED_MIN_RATIO = 1.1         -- Outpaces standard swim speed
local CHASE_SPEED_MAX_RATIO = 1.35        -- Fast chase ratio
local DASH_SPEED_MULT = 2.2               -- Burst attack speed (~25-30 studs/sec)
----------------------------------------------------

----------------------------------------------------
-- 3x ENHANCED SHARK SENSES & PERCEPTION PARAMETERS --
----------------------------------------------------
local DASH_RANGE = 54            -- Dash Charge Range
local NOTICE_RANGE = 180         -- Detection Distance
local FACING_CONE_DEG = 180      -- Vision Cone / 360 Full Field
local PERIPHERAL_RANGE_MULT = 2.1-- Peripheral Sensitivity
local ATTACK_CONE_DEG = 135      -- Attack Angle Width
local APPROACH_ALERT_RANGE = 78  -- Camera Scare Trigger Radius

-- Shark bait (SharkBaitService). Smelled from much further than a swimmer is noticed, and
-- it wins over everything: someone HOLDING bait, then bait THROWN in the water, then a
-- plain swimmer. With five divers out, whoever holds bait pulls most of the sharks.
local LURE_RANGE = 400
local BAIT_TOOL = "SharkBait"
----------------------------------------------------

local SHARK_RADIUS = 2.4
local SPOTTED_WARNING_THRESHOLD = 3
local SCARE_COOLDOWN = 6
local ROAM_MIN_SECONDS, ROAM_MAX_SECONDS = 14, 26

-- Water Boundary Clamping & Safety
local MIN_WATER_DEPTH = 8
local WATER_CEILING_OFFSET = 2.5
local WATER_FLOOR_OFFSET = 4.0

-- Dynamic Leaping Mechanics
local LEAP_CHANCE_PER_SEC = 0.05
local LEAP_COOLDOWN = 15
local LEAP_FORCE = 45

local MAP_BOUNDS = { minX = -1200, maxX = 1200, minZ = -1200, maxZ = 1200 }
local SAMPLE_ATTEMPTS = 400
local OPEN_WATER_POINT_TARGET = 120

local folder = workspace.IslaMarahuyo.Activities:FindFirstChild("Sharks") or Instance.new("Folder")
folder.Name = "Sharks"
folder.Parent = workspace.IslaMarahuyo.Activities

local rng = Random.new(os.time())
local sharks = {}
local lastScareAt = {}

-- Raycast Parameters
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = false

local collisionParams = RaycastParams.new()
collisionParams.FilterType = Enum.RaycastFilterType.Include
collisionParams.FilterDescendantsInstances = { workspace.Terrain }
collisionParams.IgnoreWater = true

----------------------------------------------------
-- CAVE EXCLUSION --
----------------------------------------------------
local CaveGen = require(game.ServerStorage.CaveGen)

local CAVE_BOUNDS = { minX = -340, maxX = 300, minY = -220, maxY = -4, minZ = -40, maxZ = 470 }
local CEILING_PROBE = 90

local entranceShafts = {}
for _, n in pairs(CaveGen.Nodes) do
	if n.kind == "entrance" then
		table.insert(entranceShafts, {
			x = n.x,
			z = n.z,
			topY = (n.seabedH or -14) + 4,
			r2 = (n.r * 1.6 + 12) ^ 2,
		})
	end
end

local function inEntranceShaft(pos)
	for _, e in ipairs(entranceShafts) do
		if pos.Y < e.topY then
			local dx, dz = pos.X - e.x, pos.Z - e.z
			if dx * dx + dz * dz < e.r2 then
				return true
			end
		end
	end
	return false
end

local function isInCave(pos)
	if pos.Y > CAVE_BOUNDS.maxY or pos.Y < CAVE_BOUNDS.minY
		or pos.X < CAVE_BOUNDS.minX or pos.X > CAVE_BOUNDS.maxX
		or pos.Z < CAVE_BOUNDS.minZ or pos.Z > CAVE_BOUNDS.maxZ then
		return false
	end
	if inEntranceShaft(pos) then
		return true
	end
	return workspace:Raycast(pos, Vector3.new(0, CEILING_PROBE, 0), collisionParams) ~= nil
end

local function isPositionInWater(pos)
	local check = workspace:Raycast(Vector3.new(pos.X, pos.Y + 50, pos.Z), Vector3.new(0, -100, 0), terrainParams)
	if check and check.Material == Enum.Material.Water then
		local surfaceY = check.Position.Y
		local floorCheck = workspace:Raycast(Vector3.new(pos.X, surfaceY - 1, pos.Z), Vector3.new(0, -200, 0), terrainParams)
		local floorY = floorCheck and floorCheck.Position.Y or (surfaceY - 50)

		return pos.Y < (surfaceY - WATER_CEILING_OFFSET) and pos.Y > (floorY + WATER_FLOOR_OFFSET)
	end
	return false
end

local function isSwimPositionInWater(pos)
	local check = workspace:Raycast(Vector3.new(pos.X, pos.Y + 50, pos.Z), Vector3.new(0, -100, 0), terrainParams)
	if check and check.Material == Enum.Material.Water then
		local surfaceY = check.Position.Y
		local floorCheck = workspace:Raycast(Vector3.new(pos.X, surfaceY - 1, pos.Z), Vector3.new(0, -200, 0), terrainParams)
		local floorY = floorCheck and floorCheck.Position.Y or (surfaceY - 50)

		return pos.Y <= surfaceY and pos.Y > floorY
	end
	return false
end

local function hasWaterPath(startPos, endPos)
	local dir = endPos - startPos
	local hit = workspace:Raycast(startPos, dir, collisionParams)
	return hit == nil
end

local function findOpenWaterPoint(x, z)
	local surface = workspace:Raycast(Vector3.new(x, 250, z), Vector3.new(0, -500, 0), terrainParams)
	if not surface or surface.Material ~= Enum.Material.Water then
		return nil
	end

	local surfaceY = surface.Position.Y
	local seabed = workspace:Raycast(Vector3.new(x, surfaceY - 1, z), Vector3.new(0, -300, 0), terrainParams)
	local seabedY = seabed and seabed.Position.Y or (surfaceY - 100)
	local depth = surfaceY - seabedY

	if depth < MIN_WATER_DEPTH then return nil end

	local minY = seabedY + WATER_FLOOR_OFFSET
	local maxY = surfaceY - WATER_CEILING_OFFSET
	local swimY = rng:NextNumber(minY, maxY)

	return Vector3.new(x, swimY, z)
end

local openWaterPoints = {}
for _ = 1, SAMPLE_ATTEMPTS do
	if #openWaterPoints >= OPEN_WATER_POINT_TARGET then break end
	local x = rng:NextNumber(MAP_BOUNDS.minX, MAP_BOUNDS.maxX)
	local z = rng:NextNumber(MAP_BOUNDS.minZ, MAP_BOUNDS.maxZ)
	local pt = findOpenWaterPoint(x, z)
	if pt and isPositionInWater(pt) and not isInCave(pt) then
		table.insert(openWaterPoints, pt)
	end
end

if #openWaterPoints == 0 then
	warn("[SharkService] no open-water roam points found -- sharks will hold position")
end

local FALLBACK_ROAM = Vector3.new(0, -20, 600)

local function randomRoamPoint(currentPos)
	if #openWaterPoints > 0 then
		for _ = 1, 15 do
			local pt = openWaterPoints[rng:NextInteger(1, #openWaterPoints)]
			if isPositionInWater(pt) and not isInCave(pt) then
				return pt
			end
		end
	end
	return currentPos or FALLBACK_ROAM
end

local SHARK_MESH_TEMPLATE = ReplicatedStorage:WaitForChild("SharkAssets"):WaitForChild("SharkMesh")
local SHARK_LENGTH = 15 

local function buildShark(startPos)
	local model = Instance.new("Model")
	model.Name = "Pating"

	local body = SHARK_MESH_TEMPLATE:Clone()
	body.Name = "Body"
	local scale = SHARK_LENGTH / body.Size.Z
	body.Size = body.Size * scale
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CastShadow = false
	body.Parent = model
	model.PrimaryPart = body
	model.Parent = folder

	return {
		model = model,
		body = body,
		pos = startPos,
		target = startPos,
		nextTargetAt = 0,
		ignoreUntil = {},
		phase = rng:NextNumber(0, math.pi * 2),
		swayPhase = rng:NextNumber(0, math.pi * 2),
		chaseSpeed = PLAYER_SWIM_SPEED * rng:NextNumber(CHASE_SPEED_MIN_RATIO, CHASE_SPEED_MAX_RATIO),
		isLeaping = false,
		leapVelocity = Vector3.zero,
		nextLeapAt = 0,
	}
end

local function destroyShark(s)
	if s.model then
		s.model:Destroy()
	end
end

-- Day/Night Cycle Population Management
local currentTargetCount = 0
local lastStateWasNight = nil

local function isNightTime()
	local time = Lighting.ClockTime
	return time < 6 or time >= 18
end

local function updateSharkPopulation()
	local nightNow = isNightTime()

	if nightNow ~= lastStateWasNight then
		lastStateWasNight = nightNow
		if nightNow then
			currentTargetCount = rng:NextInteger(NIGHT_SHARK_MIN, NIGHT_SHARK_MAX)
		else
			currentTargetCount = rng:NextInteger(DAY_SHARK_MIN, DAY_SHARK_MAX)
		end
	end

	while #sharks < currentTargetCount do
		local spawnPos = randomRoamPoint()
		table.insert(sharks, buildShark(spawnPos))
	end

	while #sharks > currentTargetCount do
		local removedShark = table.remove(sharks, #sharks)
		if removedShark then
			destroyShark(removedShark)
		end
	end
end

updateSharkPopulation()
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateSharkPopulation)

local function angleDeg(a, b)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function clampToWaterBounds(pos)
	local surface = workspace:Raycast(Vector3.new(pos.X, pos.Y + 100, pos.Z), Vector3.new(0, -200, 0), terrainParams)
	if surface and surface.Material == Enum.Material.Water then
		local surfaceY = surface.Position.Y
		local seabed = workspace:Raycast(Vector3.new(pos.X, surfaceY - 1, pos.Z), Vector3.new(0, -200, 0), terrainParams)
		local seabedY = seabed and seabed.Position.Y or (surfaceY - 50)

		local minY = seabedY + WATER_FLOOR_OFFSET
		local maxY = surfaceY - WATER_CEILING_OFFSET

		if maxY > minY then
			return Vector3.new(pos.X, math.clamp(pos.Y, minY, maxY), pos.Z)
		end
	end
	return pos
end

local function isSwimmerValid(character, humanoid, hrp)
	if not humanoid or not hrp or humanoid.Health <= 0 then return false end
	local state = humanoid:GetState()
	return (state == Enum.HumanoidStateType.Swimming or hrp.Position.Y < 1) and isSwimPositionInWater(hrp.Position)
end

-- Returns what this shark goes for: ("player", player, dist, hrp), ("bait", bait, dist),
-- or nil. Held bait > thrown bait > the nearest plain swimmer.
local function scanSwimmers(s, spottedCount, now, caveSafe, lured)
	local bestPlayer, bestDist, bestHrp
	local luredPlayer, luredDist, luredHrp
	local forward = s.body.CFrame.LookVector

	for _, player in ipairs(Players:GetPlayers()) do
		local ignoredUntil = s.ignoreUntil[player.UserId]
		local eligible = not caveSafe[player] and (not ignoredUntil or now >= ignoredUntil)
		if eligible then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")

			if isSwimmerValid(char, hum, hrp) then
				local toPlayer = hrp.Position - s.pos
				local dist = toPlayer.Magnitude
				local angle = angleDeg(forward, toPlayer)
				local range = (angle <= FACING_CONE_DEG) and NOTICE_RANGE or (NOTICE_RANGE * PERIPHERAL_RANGE_MULT)

				if lured[player] and dist <= LURE_RANGE and hasWaterPath(s.pos, hrp.Position) then
					spottedCount[player] = (spottedCount[player] or 0) + 1
					if not luredPlayer or dist < luredDist then
						luredPlayer, luredDist, luredHrp = player, dist, hrp
					end
				elseif dist <= range and hasWaterPath(s.pos, hrp.Position) then
					spottedCount[player] = (spottedCount[player] or 0) + 1
					if not bestPlayer or dist < bestDist then
						bestPlayer = player
						bestDist = dist
						bestHrp = hrp
					end
				end
			end
		end
	end
	if luredPlayer then
		return "player", luredPlayer, luredDist, luredHrp
	end

	local bait, baitDist
	for _, b in ipairs(SharkLure.Thrown()) do
		local d = (b.pos - s.pos).Magnitude
		if d <= LURE_RANGE and (not baitDist or d < baitDist) and hasWaterPath(s.pos, b.pos) then
			bait, baitDist = b, d
		end
	end
	if bait then
		return "bait", bait, baitDist
	end

	if bestPlayer then
		return "player", bestPlayer, bestDist, bestHrp
	end
	return nil
end

local function moveWithCollision(pos, moveVec)
	local dist = moveVec.Magnitude
	if dist < 1e-4 then return pos end

	local dir = moveVec.Unit
	local hit = workspace:Raycast(pos, dir * (dist + SHARK_RADIUS), collisionParams)
	if not hit then return pos + moveVec end

	local safeDist = math.max(hit.Distance - SHARK_RADIUS, 0)
	local newPos = pos + dir * safeDist
	local remaining = dist - safeDist

	if remaining > 0.05 then
		local slide = moveVec - hit.Normal * moveVec:Dot(hit.Normal)
		if slide.Magnitude > 0.05 then
			local slideDir = slide.Unit
			local slideHit = workspace:Raycast(newPos, slideDir * (remaining + SHARK_RADIUS), collisionParams)
			local slideSafe = slideHit and math.max(slideHit.Distance - SHARK_RADIUS, 0) or remaining
			newPos = newPos + slideDir * slideSafe
		end
	end

	return newPos
end

local function triggerScare(player, now)
	local last = lastScareAt[player.UserId]
	if not last or now - last >= SCARE_COOLDOWN then
		lastScareAt[player.UserId] = now
		sharkScare:FireClient(player)
	end
end

----------------------------------------------------
-- BITE FUNCTION (WITH HIGH-VELOCITY LAUNCH) --
----------------------------------------------------
local function bite(s, player, hrp)
	s.ignoreUntil[player.UserId] = os.clock() + DISENGAGE_SECONDS

	-- bait on the hook is what it was going for, and it is gone either way
	if player.Character and player.Character:FindFirstChild(BAIT_TOOL) and SharkLure.EatHeld then
		SharkLure.EatHeld(player)
	end

	-- 1. Deduct breath cost
	local runtime = BreathService.GetRuntime(player)
	if runtime then
		runtime.breath = math.max(0, runtime.breath - BITE_BREATH_COST)
		player:SetAttribute("Breath", runtime.breath)
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	-- 2. Enable Ragdoll & Flail State
	if hum then
		-- Disable getting up temporarily so player remains limp in air
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		hum:ChangeState(Enum.HumanoidStateType.Ragdoll)

		-- Temporarily disable Motor6Ds on character limbs to allow physical joint flail
		for _, motor in ipairs(char:GetDescendants()) do
			if motor:IsA("Motor6D") and motor.Name ~= "Neck" then
				motor.Enabled = false
			end
		end

		-- Automatically recover character after 2.5 seconds upon landing/water entry
		task.delay(2.5, function()
			if char and char.Parent and hum and hum.Health > 0 then
				-- Re-enable Motor6Ds
				for _, motor in ipairs(char:GetDescendants()) do
					if motor:IsA("Motor6D") then
						motor.Enabled = true
					end
				end
				-- Restore normal standing state
				hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end

	-- 3. Calculate launch direction (Away from shark's attack line)
	local sharkForward = s.cframe and s.cframe.LookVector or (s.target - s.pos).Unit
	local throwDir = Vector3.new(-sharkForward.X, 0, -sharkForward.Z).Unit

	local HORIZONTAL_LAUNCH_FORCE = 150 
	local VERTICAL_LAUNCH_FORCE = 400   

	-- 4. Apply Linear Launch Velocity
	hrp.AssemblyLinearVelocity = (throwDir * HORIZONTAL_LAUNCH_FORCE) + Vector3.new(0, VERTICAL_LAUNCH_FORCE, 0)

	-- 5. Apply Angular Tumbling Velocity (Tumbles character head-over-heels)
	local spinPower = 20
	hrp.AssemblyAngularVelocity = Vector3.new(
		rng:NextNumber(-spinPower, spinPower),
		rng:NextNumber(-spinPower, spinPower),
		rng:NextNumber(-spinPower, spinPower)
	)

	-- 6. Send client feedback
	diveFeedback:FireClient(player, "shark", string.format("A pating launched you! -- %ds of air gone!", BITE_BREATH_COST), 0)

	-- 7. Reset shark AI target
	s.target = randomRoamPoint(s.pos)
	s.nextTargetAt = os.clock() + rng:NextNumber(2, 4)
end

local function processLeap(s, dt, now)
	s.leapVelocity = s.leapVelocity - Vector3.new(0, 70 * dt, 0)
	s.pos = s.pos + s.leapVelocity * dt

	local surface = workspace:Raycast(Vector3.new(s.pos.X, s.pos.Y + 10, s.pos.Z), Vector3.new(0, -30, 0), terrainParams)
	if surface and surface.Material == Enum.Material.Water and s.pos.Y < (surface.Position.Y - WATER_CEILING_OFFSET) then
		s.isLeaping = false
		s.nextLeapAt = now + LEAP_COOLDOWN
	else
		local baseCF = CFrame.lookAt(s.pos, s.pos + s.leapVelocity)
		s.body.CFrame = s.body.CFrame:Lerp(baseCF, math.min(dt * 10, 1))
	end
end

local function tryTriggerLeap(s, now)
	if now < s.nextLeapAt or s.isLeaping then return end

	local surface = workspace:Raycast(Vector3.new(s.pos.X, s.pos.Y + 20, s.pos.Z), Vector3.new(0, -40, 0), terrainParams)
	if surface and surface.Material == Enum.Material.Water and math.abs(s.pos.Y - surface.Position.Y) < 8 then
		if rng:NextNumber() < LEAP_CHANCE_PER_SEC then
			s.isLeaping = true
			local forward = s.body.CFrame.LookVector
			s.leapVelocity = Vector3.new(forward.X * 20, LEAP_FORCE, forward.Z * 20)

			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - s.pos).Magnitude <= 80 then
					triggerScare(p, now)
				end
			end
		end
	end
end

-- Main Heartbeat Loop
local accumulatedDt = 0
RunService.Heartbeat:Connect(function(dt)
	accumulatedDt += dt
	if accumulatedDt < 0.033 then return end
	local stepDt = accumulatedDt
	accumulatedDt = 0

	local now = os.clock()
	local spottedCount = {}

	local caveSafe = {}
	local lured = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and isInCave(hrp.Position) then
			caveSafe[player] = true
		end
		-- a tool in the character is a tool in hand
		if char and char:FindFirstChild(BAIT_TOOL) then
			lured[player] = true
		end
	end

	for _, s in ipairs(sharks) do
		if isInCave(s.pos) then
			s.pos = randomRoamPoint(nil)
			s.target = s.pos
			s.nextTargetAt = now + rng:NextNumber(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS)
		end

		if s.isLeaping then
			processLeap(s, stepDt, now)
		else
			local kind, best, bestDist, bestHrp = scanSwimmers(s, spottedCount, now, caveSafe, lured)
			local speed = CRUISE_SPEED
			local target

			if kind == "bait" then
				if bestDist <= BITE_RANGE then
					SharkLure.Consume(best)
					s.target = randomRoamPoint(s.pos)
					s.nextTargetAt = now + rng:NextNumber(4, 8)
				else
					target = best.pos
					speed = (bestDist <= DASH_RANGE) and (s.chaseSpeed * DASH_SPEED_MULT) or s.chaseSpeed
				end
			elseif best then
				if bestDist <= BITE_RANGE then
					local angle = angleDeg(s.body.CFrame.LookVector, bestHrp.Position - s.pos)
					if angle <= ATTACK_CONE_DEG then
						bite(s, best, bestHrp)
					else
						target = bestHrp.Position
						speed = s.chaseSpeed
					end
				else
					target = bestHrp.Position
					speed = (bestDist <= DASH_RANGE) and (s.chaseSpeed * DASH_SPEED_MULT) or s.chaseSpeed
					if bestDist <= APPROACH_ALERT_RANGE then
						triggerScare(best, now)
					end
				end
			end

			-- Path/Target Validation Guard
			if not target or not hasWaterPath(s.pos, target) then
				if now >= s.nextTargetAt or (s.target - s.pos).Magnitude < 8 or not hasWaterPath(s.pos, s.target) then
					s.target = randomRoamPoint(s.pos)
					s.nextTargetAt = now + rng:NextNumber(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS)
				end
				target = s.target
				tryTriggerLeap(s, now)
			end

			local delta = target - s.pos
			if delta.Magnitude > 0.5 then
				local moveVec = delta.Unit * math.min(speed * stepDt, delta.Magnitude)
				local candidate = clampToWaterBounds(moveWithCollision(s.pos, moveVec))

				if isInCave(candidate) then
					s.target = randomRoamPoint(s.pos)
					s.nextTargetAt = now + rng:NextNumber(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS)
				else
					s.pos = candidate

					local baseCF = CFrame.lookAt(s.pos, s.pos + delta)

					----------------------------------------------------
					-- INTENSIFIED TAIL WIGGLE SYSTEM --
					----------------------------------------------------
					local currentSpeed = moveVec.Magnitude / stepDt
					local frequency = math.clamp(currentSpeed * 0.75, 4, 18)
					local amplitude = math.clamp(currentSpeed * 0.016, 0.12, 0.40)

					s.swayPhase = (s.swayPhase or s.phase) + (stepDt * frequency)

					local primarySway = math.sin(s.swayPhase) * amplitude
					local secondarySway = math.sin(s.swayPhase * 2) * (amplitude * 0.25)
					local sway = primarySway + secondarySway

					local targetCF = baseCF * CFrame.Angles(0, sway, 0)
					----------------------------------------------------

					s.body.CFrame = s.body.CFrame:Lerp(targetCF, math.min(stepDt * 8, 1))
				end
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local count = spottedCount[player] or 0
		sharkAlertUpdated:FireClient(
			player,
			count,
			count >= SPOTTED_WARNING_THRESHOLD,
			#sharks
		)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, s in ipairs(sharks) do
		s.ignoreUntil[player.UserId] = nil
	end
	lastScareAt[player.UserId] = nil
end)