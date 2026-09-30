-- ZiplineService
-- Four towers, three cables, out across the northern rocks. The server validates the
-- launch and hands the ride to the rider's own client -- the character is client-owned,
-- so moving it there replicates smoothly to everyone else and you actually SEE people
-- crossing the line rather than blinking from one platform to the next.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = require(script.Parent.CurrencyService)
local GamePassService = require(script.Parent.GamePassService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ziplineStatus = remotes:WaitForChild("ZiplineStatus")

-- The zipline is the fast way to the outer rocks, so it's earned rather than free:
-- one fee per leg, about a couple of good net hauls for the full three-leg run.
local ZIP_FEE = 25

local root = workspace.IslaMarahuyo.Activities:WaitForChild("Zipline")
local cables = root:WaitForChild("Cables")

local ZIP_SPEED = 72 -- studs/sec
local riding = {} -- [userId] = true

-- index -> anchor position, read back off the cables that were built with them
local anchorOf = {}
for _, cable in ipairs(cables:GetChildren()) do
	local from, to = cable:GetAttribute("FromIndex"), cable:GetAttribute("ToIndex")
	anchorOf[from] = Vector3.new(cable:GetAttribute("AX"), cable:GetAttribute("AY"), cable:GetAttribute("AZ"))
	anchorOf[to] = Vector3.new(cable:GetAttribute("BX"), cable:GetAttribute("BY"), cable:GetAttribute("BZ"))
end

local function stationName(index)
	local model = root:FindFirstChild("Station" .. index)
	return model and model:GetAttribute("StationName") or ("Station " .. index)
end

local function launch(player, fromIndex, toIndex)
	if riding[player.UserId] then
		return
	end
	local a, b = anchorOf[fromIndex], anchorOf[toIndex]
	if not (a and b) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- must actually be up on the tower, not standing at the bottom
	if (hrp.Position - a).Magnitude > 26 then
		ziplineStatus:FireClient(player, "denied", "Climb up to the platform first.")
		return
	end

	-- Kasama VIP and the Zipline Pass both ride free; everyone else pays their way.
	-- The route itself is open to everybody either way -- the pass sells the fee, not access.
	local free = GamePassService.Owns(player, "KasamaVIP")
		or GamePassService.Owns(player, "ZiplinePass")
	if not free then
		if not CurrencyService.TrySpend(player, ZIP_FEE, "Zipline") then
			ziplineStatus:FireClient(player, "denied",
				string.format("The line costs %d Shells a leg -- go earn a bit first.", ZIP_FEE))
			return
		end
	end

	riding[player.UserId] = true
	local span = (b - a).Magnitude
	local duration = span / ZIP_SPEED
	ziplineStatus:FireClient(player, "ride", a, b, duration, stationName(toIndex))
	if not free then
		ziplineStatus:FireClient(player, "charged", string.format("-%d Shells for the line.", ZIP_FEE))
	end

	-- safety net: clear the flag even if the client never reports back
	task.delay(duration + 6, function()
		riding[player.UserId] = nil
	end)
end

ziplineStatus.OnServerEvent:Connect(function(player, kind)
	if kind == "arrived" then
		riding[player.UserId] = nil
	end
end)

for _, model in ipairs(root:GetChildren()) do
	local index = model:GetAttribute("Index")
	local platform = model:FindFirstChild("Platform")
	if index and platform then
		for _, prompt in ipairs(platform:GetChildren()) do
			if prompt:IsA("ProximityPrompt") then
				local target = prompt:GetAttribute("Target")
				prompt.Triggered:Connect(function(player)
					launch(player, index, target)
				end)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	riding[player.UserId] = nil
end)

print("[ZiplineService] Zipline ready --", #cables:GetChildren(), "cables")
