-- FerryService
-- Gives the Kalangitan Isle Access game pass something to actually unlock. The isle
-- sits offshore with no bridge, so the ferry is the way across: pass holders ride it,
-- everyone else gets the purchase prompt instead of a silent no-op.
--
-- Ownership is re-checked here on every ride rather than trusted from the client.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GamePassService = require(script.Parent.GamePassService)
local MonetizationConfig = require(script.Parent.MonetizationConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ferryFeedback = remotes:FindFirstChild("FerryFeedback")
if not ferryFeedback then
	ferryFeedback = Instance.new("RemoteEvent")
	ferryFeedback.Name = "FerryFeedback"
	ferryFeedback.Parent = remotes
end

local ferryFolder = Workspace.IslaMarahuyo.Activities:WaitForChild("Ferry")
local PASS_KEY = "KalangitanIsleAccess"
local RIDE_COOLDOWN = 2

local lastRide = {}

local function destinationFor(landingName)
	if landingName == "MainlandLanding" then
		return ferryFolder:FindFirstChild("IsleLanding")
	end
	return ferryFolder:FindFirstChild("MainlandLanding")
end

local function ride(landing, player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if lastRide[player] and now - lastRide[player] < RIDE_COOLDOWN then
		-- say so rather than no-op, which just reads as a broken prompt
		ferryFeedback:FireClient(player, "The bangkero is still tying up -- one moment.", false)
		return
	end

	-- Leaving the isle is always allowed, so nobody can be stranded there if their pass
	-- check fails or the pass is refunded mid-session.
	local leavingIsle = landing.Name == "IsleLanding"
	if not leavingIsle and not GamePassService.Owns(player, PASS_KEY) then
		local pass = MonetizationConfig.GamePasses[PASS_KEY]
		if pass and pass.id ~= 0 then
			local ok = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
			end)
			ferryFeedback:FireClient(
				player,
				ok and "You need Kalangitan Isle Access to ride across."
					or "The bangkero can't take you across right now.",
				false
			)
		else
			ferryFeedback:FireClient(player, "Kalangitan Isle isn't open yet -- the pass hasn't gone on sale.", false)
		end
		return
	end

	local target = destinationFor(landing.Name)
	if not target then
		return
	end

	lastRide[player] = now
	local x = target:GetAttribute("LandingX")
	local y = target:GetAttribute("LandingY")
	local z = target:GetAttribute("LandingZ")
	character:PivotTo(CFrame.new(x, y + 4, z + 4))
	ferryFeedback:FireClient(
		player,
		leavingIsle and "Back at the barangay." or "Welcome to Kalangitan Isle.",
		true
	)
end

for _, landing in ipairs(ferryFolder:GetChildren()) do
	local deck = landing:FindFirstChild("Deck")
	local prompt = deck and deck:FindFirstChild("FerryPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			ride(landing, player)
		end)
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastRide[player] = nil
end)

print("[FerryService] Kalangitan ferry ready")
