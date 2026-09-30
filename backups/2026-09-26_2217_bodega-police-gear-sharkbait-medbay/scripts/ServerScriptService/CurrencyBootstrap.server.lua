-- CurrencyBootstrap
-- Wires player join/leave to PlayerProfileService, serves the currency remotes,
-- and autosaves + saves-on-shutdown so nothing is lost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local CurrencyService = require(script.Parent.CurrencyService)
local DailyLoginService = require(script.Parent.DailyLoginService)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local shellsUpdated = remotesFolder:WaitForChild("ShellsUpdated")
local requestShells = remotesFolder:WaitForChild("RequestShells")
local dailyRewardClaimed = remotesFolder:WaitForChild("DailyRewardClaimed")

local AUTOSAVE_INTERVAL = 90 -- seconds

requestShells.OnServerInvoke = function(player)
	return CurrencyService.GetShells(player.UserId)
end

local function onPlayerAdded(player)
	local profile, failReason, mailboxDrained = PlayerProfileService.Load(player.UserId)
	if not profile then
		warn("[CurrencyBootstrap] Could not load profile for", player.Name, failReason)
		player:Kick("Your Isla Marahuyo data is still loading on another server. Please rejoin in a minute.")
		return
	end

	shellsUpdated:FireClient(player, profile.Shells)

	if mailboxDrained and mailboxDrained > 0 then
		print("[CurrencyBootstrap]", player.Name, "received", mailboxDrained, "Shells from gifts while away")
	end

	local reward, streak, alreadyClaimed = DailyLoginService.Claim(player)
	if not alreadyClaimed and reward > 0 then
		dailyRewardClaimed:FireClient(player, reward, streak)
	end
end

local function onPlayerRemoving(player)
	PlayerProfileService.Save(player.UserId, true)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Cover players already in-game if this script ever reloads.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerProfileService.Save(player.UserId, false)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerProfileService.Save(player.UserId, true)
	end
	task.wait(1)
end)

print("[CurrencyBootstrap] Isla Marahuyo currency/session system online. Session:", PlayerProfileService.GetSessionId())
