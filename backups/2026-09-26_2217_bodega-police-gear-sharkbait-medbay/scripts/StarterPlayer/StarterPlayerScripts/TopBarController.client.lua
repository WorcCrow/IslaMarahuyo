-- TopBarController
-- Everything that opens a panel lives in Roblox's own top bar, via TopbarPlus.
--
-- The old strip was hand-laid by TopBarLayout from pieces four scripts built (a balance
-- chip, three icon buttons, a music pill, an ADMIN button, a VISITOR button) and it spent
-- its life fighting over the same corners. Now there are three icons and two dropdowns:
--   balance    -- read-only
--   Bag        -- open the bag, place / pack up your bodega
--   Dance      -- the emote bar (G on a keyboard)
--   Menu       -- Tasks, Account, Players, Settings, Help, Music, and for admins
--                 Visitors, Admin, Cave Map
-- Each entry only asks PanelUtil to toggle a panel its own script registered, so nothing
-- here knows how any panel is built.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Icon = require(ReplicatedStorage:WaitForChild("TopbarPlus"):WaitForChild("Icon"))
local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shellsUpdated = remotes:WaitForChild("ShellsUpdated")
local requestShells = remotes:WaitForChild("RequestShells")
local requestBodega = remotes:WaitForChild("RequestBodega")

local TOUCH = UserInputService.TouchEnabled
local MONEY = "\u{1F4B0}"
local BAG = "\u{1F392}"

-- ===== balance =====
local shellsIcon = Icon.new()
	:setName("Shells")
	:setLabel(MONEY .. " --")
	:setOrder(1)
	:oneClick()

local function setShells(amount)
	if typeof(amount) == "number" then
		shellsIcon:setLabel(string.format("%s %d", MONEY, amount))
	end
end

-- The server announces the balance once, the moment the profile loads -- which can be
-- before this script is listening -- and asking before the load answers 0. So keep asking
-- for a few seconds, and stop as soon as a live update has arrived.
local heardLive = false
shellsUpdated.OnClientEvent:Connect(function(amount)
	heardLive = true
	setShells(amount)
end)
task.spawn(function()
	for _ = 1, 10 do
		local ok, amount = pcall(function()
			return requestShells:InvokeServer()
		end)
		if heardLive then
			return
		end
		if ok then
			setShells(amount)
		end
		task.wait(1)
	end
end)

-- ===== dropdown helpers =====
-- A dropdown entry is a one-click icon: it runs its action, then folds its parent away so
-- the menu never stays hanging open over the game.
local function entry(label, action)
	local item = Icon.new():setLabel(label):oneClick()
	item:bindEvent("selected", function()
		action(item)
	end)
	return item
end

-- ===== bag + bodega =====
local bagIcon

local openBag = entry("Open bag", function()
	bagIcon:deselect()
	PanelUtil.Toggle("bag")
end)

local bodegaEntry = entry("Place bodega", function()
	bagIcon:deselect()
	if player:GetAttribute("BodegaPacking") == true then
		return
	end
	requestBodega:FireServer(player:GetAttribute("BodegaUp") == true and "pack" or "spawn")
end)

bagIcon = Icon.new()
	:setName("Bag")
	:setLabel(BAG .. " Bag")
	:setOrder(2)
	:setDropdown({openBag, bodegaEntry})
if not TOUCH then
	bagIcon:setCaption("Bag and bodega  [N]")
end

local function refreshBodegaEntry()
	if player:GetAttribute("BodegaPacking") == true then
		bodegaEntry:setLabel("Packing up...")
	elseif player:GetAttribute("BodegaUp") == true then
		bodegaEntry:setLabel("Pack up bodega")
	else
		bodegaEntry:setLabel("Place bodega")
	end
end
player:GetAttributeChangedSignal("BodegaUp"):Connect(refreshBodegaEntry)
player:GetAttributeChangedSignal("BodegaPacking"):Connect(refreshBodegaEntry)
refreshBodegaEntry()

-- ===== dance =====
-- Its own icon rather than a menu entry: it is something you reach for mid-play, and it
-- replaces the floating dancer button touch screens used to get.
local danceIcon = Icon.new()
	:setName("Dance")
	:setLabel("\u{1F57A} Dance")
	:setOrder(3)
	:oneClick()
danceIcon:bindEvent("selected", function()
	PanelUtil.Toggle("dance")
end)
if not TOUCH then
	danceIcon:setCaption("Emotes  [G]")
end

-- ===== the menu =====
local menuIcon

-- `gate` decides whether the entry is offered at all; admin tools are hidden, not greyed,
-- for everyone who cannot use them.
local visitorGui = playerGui:WaitForChild("AVisitorList", 15)
local MENU = {
	{panel = "tasks", label = "\u{1F4CB} Tasks"},
	{panel = "account", label = "\u{1F4D2} Account"},
	{panel = "roster", label = "\u{1F465} Players"},
	{panel = "settings", label = "\u{2699} Settings"},
	{panel = "help", label = "\u{2753} Help"},
	{panel = "music", label = "\u{1F3B5} Music"},
	{panel = "visitors", label = "\u{1F4DC} Visitors", gate = function()
		return visitorGui ~= nil and visitorGui.Enabled
	end},
	{panel = "admin", label = "\u{1F6E0} Admin", gate = function()
		return player:GetAttribute("ClientIsAdmin") == true
	end},
	{panel = "cavemap", label = "\u{1F5FA} Cave Map", gate = function()
		return player:GetAttribute("ClientCaveXray") == true
	end},
}

local menuItems = {}
for _, spec in ipairs(MENU) do
	spec.icon = entry(spec.label, function()
		menuIcon:deselect()
		PanelUtil.Toggle(spec.panel)
	end)
	table.insert(menuItems, spec.icon)
end

menuIcon = Icon.new()
	:setName("Menu")
	:setLabel("Menu")
	:setOrder(4)
	:setDropdown(menuItems)

-- the tasks entry carries today's progress, which the old always-on tab used to show
local function refreshTasksLabel()
	local badge = player:GetAttribute("TasksBadge")
	MENU[1].icon:setLabel(badge and ("\u{1F4CB} Tasks  " .. badge) or "\u{1F4CB} Tasks")
end
player:GetAttributeChangedSignal("TasksBadge"):Connect(refreshTasksLabel)
refreshTasksLabel()

local function refreshGates()
	for _, spec in ipairs(MENU) do
		if spec.gate then
			spec.icon:setEnabled(spec.gate() == true)
		end
	end
end
player:GetAttributeChangedSignal("ClientIsAdmin"):Connect(refreshGates)
player:GetAttributeChangedSignal("ClientCaveXray"):Connect(refreshGates)
if visitorGui then
	visitorGui:GetPropertyChangedSignal("Enabled"):Connect(refreshGates)
end
refreshGates()
