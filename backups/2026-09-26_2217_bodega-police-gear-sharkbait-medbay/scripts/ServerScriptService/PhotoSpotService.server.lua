-- PhotoSpotService
-- The brag spots on Isla Ningning. The server only decides who may enter photo mode and
-- where they're standing; the framing, camera and postcard overlay all live on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local photoModeToggle = remotes:WaitForChild("PhotoModeToggle")

local island = workspace.IslaMarahuyo:WaitForChild("IslaNingning")
local spots = island:WaitForChild("PhotoSpots")

for _, model in ipairs(spots:GetChildren()) do
	local pad = model:FindFirstChild("Pad")
	local prompt = pad and pad:FindFirstChild("PhotoPrompt")
	if pad and prompt then
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp or (hrp.Position - pad.Position).Magnitude > 20 then
				return
			end
			photoModeToggle:FireClient(player, "enter", {
				spotName = pad:GetAttribute("SpotName"),
				blurb = pad:GetAttribute("Blurb"),
				facing = pad:GetAttribute("Facing"),
				position = pad.Position,
			})
		end)
	end
end

print("[PhotoSpotService] Photo spots live on Isla Ningning")
