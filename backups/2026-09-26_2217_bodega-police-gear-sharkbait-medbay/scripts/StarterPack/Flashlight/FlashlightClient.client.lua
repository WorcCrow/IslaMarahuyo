local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RENDER_NAME = "FlashlightBeam"
-- Keeps the light source just past the face so the head does not occlude the beam.
local MAX_OFFSET = 1
local MIN_OFFSET = 0.6

local tool = script.Parent
local player = Players.LocalPlayer

local emitter = Instance.new("Part")
emitter.Name = "FlashlightBeam"
emitter.Size = Vector3.new(0.2, 0.2, 0.2)
emitter.Transparency = 1
emitter.Anchored = true
emitter.CanCollide = false
emitter.CanQuery = false
emitter.CanTouch = false
emitter.CastShadow = false
emitter.Locked = true

local beam = Instance.new("SpotLight")
beam.Face = Enum.NormalId.Front
beam.Angle = 48
beam.Range = 42
beam.Brightness = 2.5
beam.Color = Color3.fromRGB(255, 248, 224)
beam.Shadows = true
beam.Parent = emitter

local fill = Instance.new("PointLight")
fill.Range = 10
fill.Brightness = 0.6
fill.Color = Color3.fromRGB(255, 248, 224)
fill.Shadows = false
fill.Parent = emitter

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local isOn = false

local function aim()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not head or not camera then
		return
	end

	local cf = camera.CFrame
	local look = cf.LookVector

	-- A pinched tunnel can push a fixed offset inside rock, which blocks the beam entirely.
	rayParams.FilterDescendantsInstances = {character, emitter}
	local hit = workspace:Raycast(head.Position, look * MAX_OFFSET, rayParams)
	local offset = hit and math.max(hit.Distance - 0.15, MIN_OFFSET) or MAX_OFFSET

	emitter.CFrame = cf.Rotation + (head.Position + look * offset)
end

local function setOn(on)
	if on == isOn then
		return
	end
	isOn = on

	if on then
		aim()
		emitter.Parent = workspace
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, aim)
	else
		RunService:UnbindFromRenderStep(RENDER_NAME)
		emitter.Parent = nil
	end
end

-- The server owns the switch. We ask for the light; it answers by setting the attribute,
-- so a flat battery simply never comes back on.
local requestFlashlight = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestFlashlight")

local equipped, want = false, false

local function ask(state)
	want = state
	requestFlashlight:FireServer(state)
end

local function refresh()
	setOn(equipped and player:GetAttribute("FlashlightOn") == true)
end

-- A dying battery browns out before it quits, so the warning is in the light itself.
-- The Malakas na Sulo pass widens and brightens the cone but changes nothing about the
-- drain: an upgraded torch still burns the same battery in the same 240 seconds.
local function applyCharge()
	local pct = tonumber(player:GetAttribute("FlashlightBattery")) or 100
	local t = math.clamp(pct / 35, 0, 1)
	local upgraded = player:GetAttribute("BrightBeam") == true

	beam.Brightness = (0.9 + 1.6 * t) * (upgraded and 1.8 or 1)
	beam.Range = (22 + 20 * t) * (upgraded and 1.5 or 1)
	beam.Angle = upgraded and 66 or 48
	beam.Color = Color3.fromRGB(255, 248, 224):Lerp(Color3.fromRGB(196, 132, 56), 1 - t)
	fill.Brightness = (0.2 + 0.4 * t) * (upgraded and 1.8 or 1)
	fill.Range = upgraded and 16 or 10
end

tool.Equipped:Connect(function()
	equipped = true
	ask(true)
end)

tool.Unequipped:Connect(function()
	equipped = false
	ask(false)
	refresh()
end)

tool.Activated:Connect(function()
	ask(not want)
end)

player:GetAttributeChangedSignal("FlashlightOn"):Connect(refresh)
player:GetAttributeChangedSignal("FlashlightBattery"):Connect(applyCharge)
player:GetAttributeChangedSignal("BrightBeam"):Connect(applyCharge)
applyCharge()

script.Destroying:Connect(function()
	setOn(false)
	emitter:Destroy()
end)
