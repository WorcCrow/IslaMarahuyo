-- FlashlightService
-- Owns the flashlight battery. The client may ask for the light, but the server decides
-- whether it burns, how fast it drains, and what a refill costs.
--
-- The beam itself has to be drawn client-side, because it follows the player's own camera.
-- That means a modified client could always render light for itself; what is protected here
-- is the half that touches the economy -- the charge and the Shells.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestFlashlight = remotes:WaitForChild("RequestFlashlight")
local flashlightFeedback = remotes:WaitForChild("FlashlightFeedback")

local FULL = 100
local RUNTIME_SECONDS = 240 -- a full charge burns for four minutes of light
local DRAIN = FULL / RUNTIME_SECONDS
local LOW_AT = 20
local TICK = 0.25

local warnedLow = {}

local function profileOf(player)
	return PlayerProfileService.Get(player.UserId)
end

local function batteryOf(player)
	local profile = profileOf(player)
	return profile and profile.FlashlightBattery or 0
end

local function setBattery(player, value)
	local profile = profileOf(player)
	if not profile then
		return
	end
	profile.FlashlightBattery = math.clamp(value, 0, FULL)
	player:SetAttribute("FlashlightBattery", math.floor(profile.FlashlightBattery + 0.5))
end

local function setLit(player, lit)
	player:SetAttribute("FlashlightOn", lit and true or false)
end

local function onPlayerAdded(player)
	player:SetAttribute("FlashlightOn", false)

	task.spawn(function()
		-- the profile loads asynchronously, so wait for it rather than writing a default over it
		for _ = 1, 150 do
			local profile = profileOf(player)
			if profile then
				if profile.FlashlightBattery == nil then
					profile.FlashlightBattery = FULL
				end
				player:SetAttribute("FlashlightBattery", math.floor(profile.FlashlightBattery + 0.5))
				return
			end
			task.wait(0.1)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	warnedLow[player.UserId] = nil
end)

requestFlashlight.OnServerEvent:Connect(function(player, wanted)
	if typeof(wanted) ~= "boolean" then
		return
	end

	if not wanted then
		setLit(player, false)
		return
	end

	if batteryOf(player) <= 0 then
		setLit(player, false)
		flashlightFeedback:FireClient(player, "The battery is flat -- fit a fresh one from your bag.", false)
		return
	end

	setLit(player, true)
end)

-- Fitting a battery is InventoryService's job now: it owns the item, and writes the
-- refilled charge straight onto the profile this script already reads each tick.

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < TICK then
		return
	end
	local step = accum
	accum = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("FlashlightOn") then
			local left = batteryOf(player) - DRAIN * step
			if left <= 0 then
				setBattery(player, 0)
				setLit(player, false)
				warnedLow[player.UserId] = false
				flashlightFeedback:FireClient(player, "The flashlight dies in your hand.", false)
			else
				setBattery(player, left)
				if left <= LOW_AT and not warnedLow[player.UserId] then
					warnedLow[player.UserId] = true
					flashlightFeedback:FireClient(player, "Battery low -- the beam is going yellow.", false)
				elseif left > LOW_AT then
					warnedLow[player.UserId] = false
				end
			end
		end
	end
end)

print(string.format("[FlashlightService] battery online -- %ds per charge", RUNTIME_SECONDS))
