-- PoliceUnit
-- The barangay's walking police: NPC officers that respond to crimes in progress.
--
-- A crime (chopping someone else's bodega, or being reported at your own open tolda) makes
-- the offender Wanted for 60 seconds from the LAST offence. Each offender draws one officer
-- out of the station (capped), who walks to the scene, watches it for at least four
-- minutes, and chases anyone Wanted it can see -- firing the taser, which can miss. A hit
-- puts the target down; an officer who reaches a downed target cuffs them and drags them
-- back to the station on foot, and only there books them through PoliceService. The walk
-- is the point: an arrest you watch happen to you reads as being detained, a teleport does
-- not.
--
-- Wanted is the ONLY thing that makes a player a target, for these officers and for the
-- player pulis's taser alike, and it is only ever set here, from a server-verified crime.
--
-- PoliceService owns paralysis and sentencing, so it plugs those in through the On* hooks
-- at startup rather than this module reaching into it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")

local assets = ServerStorage:WaitForChild("PoliceAssets")
local jailStatus = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JailStatus")
local isla = workspace:WaitForChild("IslaMarahuyo")

local M = {}

-- ===== tuning =====
M.WANTED_SECONDS = 60 -- from the last offence
local WATCH_SECONDS = 240 -- how long an officer keeps watching the crime scene
local MAX_UNITS = 6
local SIGHT_RANGE = 90
local SHOOT_RANGE = 45
local SHOT_COOLDOWN = 2.5
local HIT_CHANCE = 0.4 -- misses are what give a runner a real chance to get away
local CUFF_RANGE = 6
local PATROL_RADIUS = 25
local RESPOND_SPEED = 24 -- hurrying to a call
local CHASE_SPEED = 16 -- same as a player: a runner with a lead can keep it
local PATROL_SPEED = 10
local ESCORT_SPEED = 12
-- a path that never arrives (terrain the officer cannot solve) still ends in a booking
local ESCORT_MAX_SECONDS = 120
-- held by the collar just behind the officer, tipped back so the feet trail
local DRAG_OFFSET = CFrame.new(0.6, -1.2, 3) * CFrame.Angles(math.rad(-55), 0, 0)
local ESCORT_GROUP = "PulisEscort"
local PROBE_SPEED = 110 -- studs per second
-- just inside the station door, so officers visibly come out of it
local SPAWN_AT = Vector3.new(-173, 24.5, -93)

local WALK_ANIM = "rbxassetid://507777826" -- Roblox's own R15 walk, playable in any game
local IDLE_ANIM = "rbxassetid://507766388"

local REASONS = {
	bodega = "Caught breaking into a bodega.",
	tolda = "Caught running an illegal stall.",
}

-- set by PoliceService
M.OnParalyse = nil -- function(target, seconds)
M.OnCapture = nil -- function(target, reason)
M.IsParalysed = nil -- function(target) -> boolean
M.OnCuffed = nil -- function(target): hold them still for the whole walk, not just the tranq window
M.OnReleased = nil -- function(target): an escort that ended without reaching the station
M.PARALYSE_SECONDS = 8

local wanted = {} -- [userId] = { untilAt, kind, scene }
local units = {}

-- The dragged body must not snag on doorframes and stairs on the way in: it collides with
-- nothing while it is being carried, and the weld keeps it from falling.
pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(ESCORT_GROUP) then
		PhysicsService:RegisterCollisionGroup(ESCORT_GROUP)
	end
	for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable(ESCORT_GROUP, group.name, false)
	end
end)

local unitFolder = isla:FindFirstChild("PoliceUnits")
if not unitFolder then
	unitFolder = Instance.new("Folder")
	unitFolder.Name = "PoliceUnits"
	unitFolder.Parent = isla
end

local function rootOf(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- ===== wanted =====
function M.IsWanted(player)
	local entry = wanted[player.UserId]
	return entry ~= nil and os.clock() < entry.untilAt
end

function M.WantedReason(player)
	local entry = wanted[player.UserId]
	return entry and REASONS[entry.kind] or "Caught in the act."
end

function M.ClearWanted(player)
	wanted[player.UserId] = nil
	player:SetAttribute("Wanted", nil)
	player:SetAttribute("WantedFor", nil)
end

-- ===== the taser shot, shared with the player pulis's taser =====
-- Two barbs trail a wire from the muzzle, like the real thing. `hit` is decided by the
-- caller before the shot leaves; a miss flies past the target instead of into it.
function M.FireProbe(muzzle, targetRoot, hit, onLanded)
	local from = muzzle.Position
	local aim = targetRoot.Position
	local goal
	if hit then
		goal = aim
	else
		local dir = (aim - from).Unit
		local side = dir:Cross(Vector3.yAxis)
		if side.Magnitude < 0.01 then
			side = Vector3.xAxis
		end
		side = side.Unit * (math.random() < 0.5 and -1 or 1)
		goal = aim + side * (3 + math.random() * 3) + dir * 12 + Vector3.new(0, math.random() * 2 - 1, 0)
	end
	local travel = math.clamp((goal - from).Magnitude / PROBE_SPEED, 0.08, 0.8)

	local startAtt = Instance.new("Attachment")
	startAtt.Parent = muzzle
	Debris:AddItem(startAtt, travel + 1.2)
	for i = 1, 2 do
		local probe = assets.Probe:Clone()
		probe.CFrame = CFrame.lookAt(from, goal)
		probe.Parent = workspace
		local endAtt = Instance.new("Attachment")
		endAtt.Parent = probe
		local wire = Instance.new("Beam")
		wire.Attachment0 = startAtt
		wire.Attachment1 = endAtt
		wire.Width0, wire.Width1 = 0.06, 0.06
		wire.Color = ColorSequence.new(Color3.fromRGB(255, 226, 90))
		wire.LightEmission = 0.6
		wire.FaceCamera = true
		wire.Parent = probe
		local spread = Vector3.new(0, (i == 1) and 0.35 or -0.35, 0)
		TweenService:Create(probe, TweenInfo.new(travel, Enum.EasingStyle.Linear),
			{CFrame = CFrame.lookAt(goal + spread, goal + spread + (goal - from).Unit)}):Play()
		Debris:AddItem(probe, travel + 1.2)
	end

	if hit and onLanded then
		task.delay(travel, function()
			if targetRoot.Parent then
				local spark = Instance.new("ParticleEmitter")
				spark.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
				spark.LightEmission = 1
				spark.Size = NumberSequence.new(0.25, 0)
				spark.Lifetime = NumberRange.new(0.2, 0.4)
				spark.Speed = NumberRange.new(6, 10)
				spark.SpreadAngle = Vector2.new(180, 180)
				spark.Rate = 60
				spark.Parent = targetRoot
				Debris:AddItem(spark, 1.2)
				onLanded()
			end
		end)
	end
	return travel
end

-- ===== one officer =====
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true

local function canSee(unit, player)
	local head = unit.model:FindFirstChild("Head")
	local target = player.Character and player.Character:FindFirstChild("Head")
	if not (head and target) then
		return false
	end
	local offset = target.Position - head.Position
	if offset.Magnitude > SIGHT_RANGE then
		return false
	end
	sightParams.FilterDescendantsInstances = {unitFolder, player.Character}
	return workspace:Raycast(head.Position, offset, sightParams) == nil
end

local function pickTarget(unit)
	-- whoever this officer was sent for first, then anyone else Wanted in sight
	if unit.target and unit.target.Parent and M.IsWanted(unit.target) and rootOf(unit.target) then
		return unit.target
	end
	local best, bestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local r = rootOf(player)
		if r and M.IsWanted(player) and canSee(unit, player) then
			local d = (r.Position - unit.root.Position).Magnitude
			if not bestDist or d < bestDist then
				best, bestDist = player, d
			end
		end
	end
	return best
end

local function setGoal(unit, goal)
	if unit.goal and (flat(unit.goal) - flat(goal)).Magnitude < 6 and os.clock() - unit.pathedAt < 1.5 then
		return -- close enough to the path already being walked
	end
	unit.goal = goal
	unit.pathedAt = os.clock()
	unit.waypoints = nil
	unit.wp = 1
	local path = PathfindingService:CreatePath({
		AgentRadius = 2, AgentHeight = 5.6, AgentCanJump = true, WaypointSpacing = 6,
	})
	local ok = pcall(function()
		path:ComputeAsync(unit.root.Position, goal)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		unit.waypoints = path:GetWaypoints()
		unit.wp = math.min(2, #unit.waypoints)
	end
end

local function stepMovement(unit)
	if not unit.goal then
		return
	end
	local pos = unit.root.Position
	local nextPoint = unit.goal
	if unit.waypoints and unit.waypoints[unit.wp] then
		local wp = unit.waypoints[unit.wp]
		if (flat(wp.Position) - flat(pos)).Magnitude < 3 then
			unit.wp += 1
			wp = unit.waypoints[unit.wp]
		end
		if wp then
			nextPoint = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then
				unit.humanoid.Jump = true
			end
		end
	end
	unit.humanoid:MoveTo(nextPoint)

	-- Stuck on terrain the path could not solve: drop a little further along, the way a
	-- responding car would, rather than standing against a wall forever.
	if (pos - unit.lastPos).Magnitude > 1.5 then
		unit.lastPos = pos
		unit.lastMovedAt = os.clock()
	elseif os.clock() - unit.lastMovedAt > 4 and (flat(unit.goal) - flat(pos)).Magnitude > 10 then
		local toward = flat(unit.goal) - flat(pos)
		local hop = pos + toward.Unit * math.min(30, toward.Magnitude - 4)
		local ground = workspace:Raycast(hop + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), sightParams)
		if ground then
			unit.model:PivotTo(CFrame.new(ground.Position + Vector3.new(0, 3.2, 0)))
		end
		unit.lastMovedAt = os.clock()
		unit.pathedAt = 0 -- re-path from the new spot
	end
end

-- ===== the escort =====
local function attach(unit, target)
	local character = target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return false
	end
	local saved = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			saved[part] = {group = part.CollisionGroup, massless = part.Massless}
			part.CollisionGroup = ESCORT_GROUP
			part.Massless = true -- or the officer could not walk carrying them
		end
	end
	targetRoot.CFrame = unit.root.CFrame * DRAG_OFFSET
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PulisCuffs"
	weld.Part0 = unit.root
	weld.Part1 = targetRoot
	weld.Parent = unit.root
	-- one assembly now; the server walks all of it, so every client sees the same drag
	pcall(function()
		unit.root:SetNetworkOwner(nil)
	end)
	unit.escort = {target = target, weld = weld, saved = saved, root = targetRoot}
	return true
end

local function detach(unit)
	local e = unit.escort
	if not e then
		return
	end
	unit.escort = nil
	e.weld:Destroy()
	for part, s in pairs(e.saved) do
		if part.Parent then
			part.CollisionGroup = s.group
			part.Massless = s.massless
		end
	end
	if e.root.Parent then
		e.root.CFrame = CFrame.new(e.root.Position + Vector3.new(0, 2, 0)) -- back on their feet
		pcall(function()
			e.root:SetNetworkOwner(e.target)
		end)
	end
end

local function despawn(unit)
	if unit.escort then
		-- removed mid-walk: let the prisoner go rather than leave them frozen in place
		local target = unit.escort.target
		detach(unit)
		if target.Parent and M.OnReleased then
			M.OnReleased(target)
		end
	end
	unit.gone = true
	if unit.model then
		unit.model:Destroy()
	end
	for i, u in ipairs(units) do
		if u == unit then
			table.remove(units, i)
			break
		end
	end
end

local function shoot(unit, target)
	unit.lastShot = os.clock()
	local muzzle = unit.model:FindFirstChild("Barrel", true)
	local targetRoot = rootOf(target)
	if not (muzzle and targetRoot) then
		return
	end
	unit.root.CFrame = CFrame.lookAt(unit.root.Position,
		Vector3.new(targetRoot.Position.X, unit.root.Position.Y, targetRoot.Position.Z))
	local hit = math.random() < HIT_CHANCE
	M.FireProbe(muzzle, targetRoot, hit, function()
		if M.IsWanted(target) and M.OnParalyse then
			M.OnParalyse(target, M.PARALYSE_SECONDS)
		end
	end)
	if not hit then
		jailStatus:FireClient(target, "info", "A taser shot just missed you. Keep moving.", 0)
	end
end

local function startEscort(unit, target)
	unit.escortReason = M.WantedReason(target)
	-- no longer a target for anyone else: they are in custody
	M.ClearWanted(target)
	if M.OnCuffed then
		M.OnCuffed(target)
	end
	if not attach(unit, target) then
		unit.target = nil
		if M.OnCapture then
			M.OnCapture(target, unit.escortReason)
		end
		return
	end
	unit.state = "escort"
	unit.target = target
	unit.escortStartedAt = os.clock()
	unit.humanoid.WalkSpeed = ESCORT_SPEED
	unit.goal = nil
	setGoal(unit, SPAWN_AT)
	jailStatus:FireClient(target, "info", "You're cuffed. The pulis are dragging you to the station.", 0)
end

local function escortStep(unit)
	local target = unit.target
	local e = unit.escort
	local character = target and target.Parent and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (e and humanoid and humanoid.Health > 0 and e.root.Parent) or target:GetAttribute("Jailed") then
		-- gone, dead, or already booked by a player pulis: nothing left to carry
		detach(unit)
		if target and target.Parent and M.OnReleased then
			M.OnReleased(target)
		end
		unit.target = nil
		unit.state = "return"
		unit.watchUntil = 0
		return
	end

	unit.humanoid.WalkSpeed = ESCORT_SPEED
	setGoal(unit, SPAWN_AT)
	local arrived = (flat(SPAWN_AT) - flat(unit.root.Position)).Magnitude < 8
	if arrived or os.clock() - unit.escortStartedAt > ESCORT_MAX_SECONDS then
		detach(unit)
		unit.target = nil
		if M.OnCapture then
			M.OnCapture(target, unit.escortReason or "Caught in the act.")
		end
		despawn(unit)
	end
end

local function think(unit)
	if unit.state == "escort" then
		escortStep(unit)
		return
	end
	local now = os.clock()
	local target = pickTarget(unit)

	if target then
		local targetRoot = rootOf(target)
		local dist = (targetRoot.Position - unit.root.Position).Magnitude
		local down = M.IsParalysed and M.IsParalysed(target)
		unit.humanoid.WalkSpeed = unit.state == "respond" and dist > SIGHT_RANGE and RESPOND_SPEED or CHASE_SPEED
		if down then
			unit.humanoid.WalkSpeed = RESPOND_SPEED
			if dist <= CUFF_RANGE then
				startEscort(unit, target)
				return
			end
			setGoal(unit, targetRoot.Position)
		elseif canSee(unit, target) then
			unit.state = "chase"
			unit.lastSeen = targetRoot.Position
			if dist <= SHOOT_RANGE and now - unit.lastShot > SHOT_COOLDOWN then
				shoot(unit, target)
			end
			setGoal(unit, targetRoot.Position)
		else
			-- lost sight: head for where they were last seen, then the crime scene
			setGoal(unit, unit.lastSeen or (wanted[target.UserId] and wanted[target.UserId].scene) or unit.scene)
		end
		return
	end

	-- nobody Wanted in reach: watch the scene until the watch runs out, then go home
	if now < unit.watchUntil then
		unit.state = "patrol"
		unit.humanoid.WalkSpeed = (flat(unit.scene) - flat(unit.root.Position)).Magnitude > PATROL_RADIUS * 2
			and RESPOND_SPEED or PATROL_SPEED
		if not unit.goal or (flat(unit.goal) - flat(unit.root.Position)).Magnitude < 4 or unit.goalIsHome then
			local angle = math.random() * math.pi * 2
			local r = math.random() * PATROL_RADIUS
			unit.goalIsHome = false
			setGoal(unit, unit.scene + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
		end
	else
		unit.state = "return"
		unit.humanoid.WalkSpeed = PATROL_SPEED + 4
		unit.goalIsHome = true
		setGoal(unit, SPAWN_AT)
		if (flat(SPAWN_AT) - flat(unit.root.Position)).Magnitude < 8 then
			despawn(unit)
		end
	end
end

local function spawnUnit(target, scene)
	local model = assets.Officer:Clone()
	model.Name = "PulisUnit"
	model:PivotTo(CFrame.new(SPAWN_AT))
	model.Parent = unitFolder
	local root = model:WaitForChild("HumanoidRootPart")
	pcall(function()
		root:SetNetworkOwner(nil) -- the server walks it, so every client sees the same officer
	end)
	local humanoid = model:WaitForChild("Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local walk = Instance.new("Animation")
	walk.AnimationId = WALK_ANIM
	local idle = Instance.new("Animation")
	idle.AnimationId = IDLE_ANIM
	local walkTrack = animator:LoadAnimation(walk)
	local idleTrack = animator:LoadAnimation(idle)
	walkTrack.Looped = true
	idleTrack.Looped = true
	idleTrack:Play()
	humanoid.Running:Connect(function(speed)
		if speed > 1 then
			if not walkTrack.IsPlaying then
				idleTrack:Stop(0.2)
				walkTrack:Play(0.2)
			end
			walkTrack:AdjustSpeed(speed / 14)
		elseif walkTrack.IsPlaying then
			walkTrack:Stop(0.2)
			idleTrack:Play(0.2)
		end
	end)

	local unit = {
		model = model, root = root, humanoid = humanoid,
		target = target, scene = scene, watchUntil = os.clock() + WATCH_SECONDS,
		state = "respond", lastShot = 0, pathedAt = 0, wp = 1,
		lastPos = root.Position, lastMovedAt = os.clock(),
	}
	table.insert(units, unit)
	-- Each officer thinks on its own thread: path computation yields, and a yield inside one
	-- shared Heartbeat handler would let the next frame start a second, overlapping pass.
	task.spawn(function()
		while not unit.gone do
			if not unit.model.Parent or not unit.root.Parent then
				despawn(unit)
				break
			end
			think(unit)
			if not unit.gone then
				stepMovement(unit)
			end
			task.wait(0.2)
		end
	end)
	return unit
end

-- ===== reporting a crime =====
-- Called for every counted offence. Refreshes the offender's 60 seconds, keeps any officer
-- already watching that scene watching it longer, and sends a new officer out for an
-- offender nobody has been sent for yet.
function M.ReportCrime(player, position, kind)
	local now = os.clock()
	local fresh = not M.IsWanted(player)
	wanted[player.UserId] = { untilAt = now + M.WANTED_SECONDS, kind = kind, scene = position }
	player:SetAttribute("Wanted", true)
	player:SetAttribute("WantedFor", kind)

	local assigned = false
	for _, unit in ipairs(units) do
		if (flat(unit.scene) - flat(position)).Magnitude < 60 then
			unit.watchUntil = math.max(unit.watchUntil, now + WATCH_SECONDS)
		end
		if unit.target == player then
			assigned = true
		end
	end
	if not assigned and #units < MAX_UNITS then
		spawnUnit(player, position)
	end
	if fresh then
		jailStatus:FireClient(player, "info",
			"You were seen. The pulis are on the way -- they will be after you for 60 seconds.", 0)
	end
end

-- A closed scene (the bodega packed away or broken) releases the officers watching it:
-- they head home now instead of patrolling an empty lot for the rest of the watch. Anyone
-- still chasing a live Wanted suspect keeps chasing.
function M.EndWatch(position)
	local now = os.clock()
	for _, unit in ipairs(units) do
		if unit.state ~= "escort" and (flat(unit.scene) - flat(position)).Magnitude < 60 then
			local t = unit.target
			if not (t and t.Parent and M.IsWanted(t)) then
				unit.watchUntil = math.min(unit.watchUntil, now)
			end
		end
	end
end

-- ===== the tick =====
-- Only the Wanted clock runs here; each officer has its own loop (see spawnUnit).
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.2 then
		return
	end
	accumulated = 0
	local now = os.clock()

	for userId, entry in pairs(wanted) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			wanted[userId] = nil
		elseif now >= entry.untilAt or player:GetAttribute("Jailed") then
			M.ClearWanted(player)
			if now >= entry.untilAt then
				jailStatus:FireClient(player, "info", "The pulis lost your trail. You got away -- this time.", 0)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	wanted[player.UserId] = nil
	for _, unit in ipairs(units) do
		if unit.target == player then
			unit.target = nil
		end
	end
end)

return M
