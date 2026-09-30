-- NightAmbienceController
-- Toggles firefly glow on/off with the day/night cycle and periodically spawns
-- shooting stars across the sky while it's nighttime.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local root = workspace:WaitForChild("IslaMarahuyo")
local nightFX = root:WaitForChild("NightFX")
local fireflyFolder = nightFX:WaitForChild("Fireflies")
local shootingStarFolder = nightFX:WaitForChild("ShootingStars")

local rng = Random.new()

local function isNight()
	local ct = Lighting.ClockTime
	return ct >= 19 or ct <= 5
 end

local night = isNight()

local function setFirefliesEnabled(enabled)
	for _, zoneFolder in ipairs(fireflyFolder:GetChildren()) do
		for _, fly in ipairs(zoneFolder:GetChildren()) do
			if fly:IsA("BasePart") then
				TweenService:Create(fly, TweenInfo.new(2), {Transparency = enabled and 0 or 1}):Play()
				local light = fly:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = enabled end
			end
		end
	end
end

setFirefliesEnabled(night)

-- ambient wander: gently drift each firefly around its zone center, with a slow
-- pulsing brightness so they don't all blink in sync
RunService.Heartbeat:Connect(function()
	if not night then return end
	local t = os.clock()
	for _, zoneFolder in ipairs(fireflyFolder:GetChildren()) do
		local cx = zoneFolder:GetAttribute("CenterX") or 0
		local cy = zoneFolder:GetAttribute("CenterY") or 0
		local cz = zoneFolder:GetAttribute("CenterZ") or 0
		local radius = zoneFolder:GetAttribute("Radius") or 15
		for _, fly in ipairs(zoneFolder:GetChildren()) do
			if fly:IsA("BasePart") then
				local seed = fly:GetAttribute("Seed")
				if not seed then
					seed = rng:NextNumber(0, 1000)
					fly:SetAttribute("Seed", seed)
				end
				local ox = math.sin(t * 0.4 + seed) * radius * 0.5
				local oz = math.cos(t * 0.33 + seed * 1.3) * radius * 0.5
				local oy = math.sin(t * 0.6 + seed * 2.1) * 2 + 3
				fly.Position = Vector3.new(cx + ox, cy + oy, cz + oz)
				local light = fly:FindFirstChildOfClass("PointLight")
				if light then
					light.Brightness = 1.4 + math.sin(t * 2 + seed * 3) * 0.8
				end
			end
		end
	end
end)

local SKY_RADIUS = 900

local function spawnShootingStar()
	local angle = rng:NextNumber(0, math.pi * 2)
	local startPos = Vector3.new(math.cos(angle) * SKY_RADIUS, rng:NextNumber(420, 520), math.sin(angle) * SKY_RADIUS)
	local travel = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.35, -0.15), rng:NextNumber(-1, 1)).Unit * rng:NextNumber(500, 700)
	local endPos = startPos + travel

	local star = Instance.new("Part")
	star.Name = "ShootingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.new(2.2, 2.2, 2.2)
	star.Material = Enum.Material.Neon
	star.Color = Color3.fromRGB(255, 255, 245)
	star.Anchored = true
	star.CanCollide = false
	star.CanQuery = false
	star.CastShadow = false
	star.Position = startPos
	star.Parent = shootingStarFolder

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.4, 0)
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.4, 0)
	a1.Parent = star

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.MinLength = 0
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 235))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	trail.Parent = star

	local duration = rng:NextNumber(0.7, 1.1)
	local tween = TweenService:Create(star, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Position = endPos})
	tween:Play()
	tween.Completed:Connect(function()
		task.wait(trail.Lifetime + 0.1)
		star:Destroy()
	end)
end

task.spawn(function()
	while true do
		task.wait(rng:NextNumber(9, 22))
		if night then
			spawnShootingStar()
		end
	end
end)

-- recheck day/night transition every few seconds
task.spawn(function()
	while true do
		task.wait(3)
		local nowNight = isNight()
		if nowNight ~= night then
			night = nowNight
			setFirefliesEnabled(night)
		end
	end
end)

print("[NightAmbienceController] Fireflies + shooting stars online -- currently", night and "night" or "day")
