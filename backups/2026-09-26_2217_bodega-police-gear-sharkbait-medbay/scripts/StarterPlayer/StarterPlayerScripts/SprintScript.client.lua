local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Speed settings
local NORMAL_SPEED = 16
local SPRINT_SPEED = 32
local SPRINT_ACTION_NAME = "Sprint"

-- Jump settings
local WATER_JUMP_COOLDOWN = 5
local lastWaterJumpTime = 0
local isSprinting = false

-- Raycast setup for water detection
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = false

-- Checks if water is directly below or around the character
local function isOverOrInWater()
	if humanoid:GetState() == Enum.HumanoidStateType.Swimming or humanoid.FloorMaterial == Enum.Material.Water then
		return true
	end

	-- Check 8 units below feet to catch water during jump peaks
	raycastParams.FilterDescendantsInstances = {character}
	local rayResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -8, 0), raycastParams)

	if rayResult and rayResult.Material == Enum.Material.Water then
		return true
	end

	return false
end

-- Frame-by-frame check to manage jumping & speed based on terrain state
RunService.Stepped:Connect(function()
	if isOverOrInWater() then
		-- On water: enforce speed restrictions
		humanoid.WalkSpeed = NORMAL_SPEED

		-- Block jump state if jump cooldown is active
		if tick() - lastWaterJumpTime < WATER_JUMP_COOLDOWN then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	else
		-- On land: restore full jump ability immediately and respect sprint state
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

		if isSprinting then
			humanoid.WalkSpeed = SPRINT_SPEED
		else
			humanoid.WalkSpeed = NORMAL_SPEED
		end
	end
end)

-- Handle Jump Requests (Space bar / Mobile Jump Button)
UserInputService.JumpRequest:Connect(function()
	if isOverOrInWater() then
		local currentTime = tick()
		if currentTime - lastWaterJumpTime < WATER_JUMP_COOLDOWN then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		else
			lastWaterJumpTime = currentTime
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	else
		-- Instantly allow normal/spam jumping on land
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end)

-- Sprint input handler
local function handleSprint(actionName, userInputState, inputObject)
	if userInputState == Enum.UserInputState.Begin then
		isSprinting = true
	elseif userInputState == Enum.UserInputState.End then
		isSprinting = false
	end
end

-- Bind Sprint key and create Mobile support button
ContextActionService:BindAction(
	SPRINT_ACTION_NAME,
	handleSprint,
	true,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift
)
ContextActionService:SetTitle(SPRINT_ACTION_NAME, "Sprint")

-- Re-initialize references on character respawn
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	lastWaterJumpTime = 0
end)