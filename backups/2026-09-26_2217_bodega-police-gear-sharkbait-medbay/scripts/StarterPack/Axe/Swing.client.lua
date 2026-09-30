-- Swing
-- Finds the nearest bodega in reach and tells the server which one was swung at. That is
-- all the client decides: whether the swing counts, and for how much, is BodegaService's
-- call (equipped axe, reach, cooldown), so a tampered client gains nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local CONFIG = ItemConfig.Bodega

local tool = script.Parent
local player = Players.LocalPlayer
local requestHit = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestBodegaHit")

local last = 0

local function gapTo(hitbox, position)
	local localPos = hitbox.CFrame:PointToObjectSpace(position)
	local half = hitbox.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z))
	return (localPos - clamped).Magnitude
end

tool.Activated:Connect(function()
	if os.clock() - last < CONFIG.HitCooldown then
		return
	end
	last = os.clock()

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local isla = workspace:FindFirstChild("IslaMarahuyo")
	local folder = isla and isla:FindFirstChild("Bodegas")
	if not (root and folder) then
		return
	end

	local best, bestGap = nil, math.huge
	for _, model in ipairs(folder:GetChildren()) do
		local hitbox = model.PrimaryPart
		if hitbox and model:GetAttribute("OwnerId") ~= player.UserId then
			local gap = gapTo(hitbox, root.Position)
			if gap <= CONFIG.AxeReach and gap < bestGap then
				best, bestGap = model, gap
			end
		end
	end
	if best then
		requestHit:FireServer(best)
	end
end)
