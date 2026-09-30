-- TitleTagService
-- The floating title above a player's head.
--
-- Deliberate split: the titles you EARN are free and always shown -- clearing the cave
-- puts "Scuba Diving Professional" over your head whether or not you have ever spent a
-- Robux. What the Custom Title pass sells is the right to write your own instead, and what
-- Island Legend sells is a gold plate. Neither buys a title anybody could otherwise earn,
-- which is the same line the rest of the catalogue holds.
--
-- Priority: your custom title (if you bought the right to write one) > Island Legend >
-- your earned cave title. Island Legend gives the GOLD, not the words -- someone who owns
-- both passes writes their own title and it shows in gold. Letting the prestige pass
-- override the title pass would mean the second purchase did nothing at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local PlayerProfileService = require(script.Parent.PlayerProfileService)
local GamePassService = require(script.Parent.GamePassService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function ensureRemote(name, className)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local setTitle = ensureRemote("SetPlayerTitle", "RemoteEvent")
local titleFeedback = ensureRemote("TitleFeedback", "RemoteEvent")

local MAX_TITLE = 22
local SET_COOLDOWN = 10
local lastSetAt = {}

local LEGEND_GOLD = Color3.fromRGB(255, 206, 92)
local EARNED_BLUE = Color3.fromRGB(150, 210, 235)
local CUSTOM_CREAM = Color3.fromRGB(236, 228, 210)

-- Resolves what this player's tag should say right now, and in what colour.
local function resolveTitle(player)
	local isLegend = player:GetAttribute("IslandLegend") == true

	local profile = PlayerProfileService.Get(player.UserId)
	local custom = profile and profile.CustomTitle
	if custom and custom ~= "" and GamePassService.Owns(player, "NameTitle") then
		-- their words; gold if they also hold the prestige pass
		return custom, isLegend and LEGEND_GOLD or CUSTOM_CREAM
	end

	if isLegend then
		return "Island Legend", LEGEND_GOLD
	end

	-- earned, free, and the reason most tags on the island will have anything on them
	local earned = player:GetAttribute("CaveTitle")
	if earned and earned ~= "" then
		return earned, EARNED_BLUE
	end

	return nil
end

local function buildTag(character)
	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end

	local existing = head:FindFirstChild("TitleTag")
	if existing then
		return existing
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "TitleTag"
	gui.Size = UDim2.new(0, 200, 0, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90 -- matches the name-tag draw distance
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = ""
	label.Parent = gui

	return gui
end

local function refresh(player)
	local character = player.Character
	if not character then
		return
	end
	local gui = buildTag(character)
	if not gui then
		return
	end

	local text, colour = resolveTitle(player)
	local label = gui:FindFirstChild("Label")
	if not label then
		return
	end

	if text then
		label.Text = text
		label.TextColor3 = colour
		gui.Enabled = true
	else
		label.Text = ""
		gui.Enabled = false
	end

	-- mirrored so the settings panel can show what's currently above your head without
	-- re-deriving the earned/custom/prestige precedence on the client
	player:SetAttribute("DisplayTitle", text)
end

-- Returns filtered text, or nil + a reason the player can be shown.
local function filterFor(player, text)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok then
		warn("[TitleTagService] filtering unavailable:", result)
		return nil, "Your title couldn't be checked just now -- try again in a moment."
	end
	local okBroadcast, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not okBroadcast or type(filtered) ~= "string" then
		return nil, "Your title couldn't be checked just now -- try again in a moment."
	end
	return filtered
end

setTitle.OnServerEvent:Connect(function(player, text)
	if type(text) ~= "string" then
		return
	end

	if not GamePassService.Owns(player, "NameTitle") then
		titleFeedback:FireClient(player, false, "Custom titles need the Custom Title pass.")
		return
	end

	local now = os.clock()
	local last = lastSetAt[player.UserId]
	if last and now - last < SET_COOLDOWN then
		titleFeedback:FireClient(player, false, "Give it a second before changing it again.")
		return
	end

	text = text:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
	if #text > MAX_TITLE then
		text = text:sub(1, MAX_TITLE)
	end

	local profile = PlayerProfileService.Get(player.UserId)
	if not profile then
		return
	end

	if #text == 0 then
		-- clearing falls back to whatever they've earned, which is the point
		profile.CustomTitle = nil
		lastSetAt[player.UserId] = now
		refresh(player)
		titleFeedback:FireClient(player, true, "Title cleared -- your earned title is showing again.")
		return
	end

	local filtered, reason = filterFor(player, text)
	if not filtered then
		titleFeedback:FireClient(player, false, reason)
		return
	end

	profile.CustomTitle = filtered
	lastSetAt[player.UserId] = now
	refresh(player)
	titleFeedback:FireClient(player, true, string.format("Title set to \"%s\".", filtered))
end)

local function watch(player)
	player:GetAttributeChangedSignal("CaveTitle"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("IslandLegend"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the Head land
		refresh(player)
	end)
	if player.Character then
		refresh(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player)
	lastSetAt[player.UserId] = nil
end)

print("[TitleTagService] name titles online (earned titles free, custom titles pass-gated)")
