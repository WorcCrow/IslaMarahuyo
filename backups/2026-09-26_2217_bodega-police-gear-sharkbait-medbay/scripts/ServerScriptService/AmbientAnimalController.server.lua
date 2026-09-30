-- AmbientAnimalController
-- Gives each ambient chicken a lightweight random walk within its home radius,
-- purely visual (Anchored parts moved by CFrame) so it's cheap even with many of them.

local RunService = game:GetService("RunService")
local chickenFolder = workspace.IslaMarahuyo.AmbientAnimals:WaitForChild("Chickens")
local rng = Random.new()

local WALK_SPEED = 4
local TURN_SPEED = 6

local state = {}

local function pickNewTarget(chicken)
	local cx = chicken:GetAttribute("CenterX")
	local cz = chicken:GetAttribute("CenterZ")
	local radius = chicken:GetAttribute("Radius") or 15
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(0, radius)
	return Vector3.new(cx + math.cos(angle) * dist, 0, cz + math.sin(angle) * dist)
end

for _, chicken in ipairs(chickenFolder:GetChildren()) do
	if chicken:IsA("Model") then
		state[chicken] = {
			target = pickNewTarget(chicken),
			waitUntil = 0,
			facing = 0,
		}
	end
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for chicken, s in pairs(state) do
		if not chicken.Parent then
			state[chicken] = nil
			continue
		end
		local part = chicken.PrimaryPart or chicken:FindFirstChildWhichIsA("BasePart")
		if not part then continue end

		local pos = part.Position
		local flat = Vector3.new(pos.X, 0, pos.Z)
		local toTarget = s.target - flat

		if toTarget.Magnitude < 1.5 then
			if now >= s.waitUntil then
				s.target = pickNewTarget(chicken)
				s.waitUntil = now + rng:NextNumber(1.5, 4)
			end
		else
			local step = math.min(WALK_SPEED * dt, toTarget.Magnitude)
			local dir = toTarget.Unit
			local newPos = pos + Vector3.new(dir.X, 0, dir.Z) * step

			local desiredFacing = math.atan2(dir.X, dir.Z)
			local delta = (desiredFacing - s.facing + math.pi) % (math.pi * 2) - math.pi
			s.facing = s.facing + math.clamp(delta, -TURN_SPEED * dt, TURN_SPEED * dt)

			chicken:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, s.facing, 0))
		end
	end
end)

print("[AmbientAnimalController] " .. #chickenFolder:GetChildren() .. " chickens wandering")
