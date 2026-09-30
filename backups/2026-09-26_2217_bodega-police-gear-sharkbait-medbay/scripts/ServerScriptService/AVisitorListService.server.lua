local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local visitorStore = DataStoreService:GetDataStore("GlobalVisitorHistory")
local visitorSessionStore = DataStoreService:GetDataStore("VisitorSessionHistory")

local ADMIN_USER_ID = 8745800367
local ADMIN_IDS = {
	[ADMIN_USER_ID] = true,
}

-- Track visitors per server session
local currentSessionVisitors = {}
local sessionStartTime = os.time()

-- Function to generate a unique session ID
local function generateSessionId()
	local timestamp = os.time()
	local randomValue = math.random(10000, 99999)
	return timestamp .. "_" .. randomValue
end

local SESSION_ID = generateSessionId()

local remoteEvent = ReplicatedStorage:FindFirstChild("UpdateVisitorHistory")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "UpdateVisitorHistory"
	remoteEvent.Parent = ReplicatedStorage
end

local function getPlayerInfo(player)
	return {
		UserId = player.UserId,
		Username = player.Name,
		DisplayName = player.DisplayName,
		JoinTime = os.time(),
		SessionId = SESSION_ID
	}
end

local function onPlayerAdded(player)
	-- Get player info
	local playerInfo = getPlayerInfo(player)
	
	-- Log visitor to global DataStore
	pcall(function()
		local history = visitorStore:GetAsync("AllVisitorsList") or {}
		if not table.find(history, player.UserId) then
			table.insert(history, player.UserId)
			visitorStore:SetAsync("AllVisitorsList", history)
		end
	end)
	
	-- Log visitor to session DataStore
	pcall(function()
		local sessionHistory = visitorSessionStore:GetAsync(SESSION_ID) or {}
		local playerExists = false
		for i, visitor in ipairs(sessionHistory) do
			if visitor.UserId == player.UserId then
				playerExists = true
				break
			end
		end
		if not playerExists then
			table.insert(sessionHistory, playerInfo)
			visitorSessionStore:SetAsync(SESSION_ID, sessionHistory)
		end
	end)
	
	-- Add to current session visitors table
	currentSessionVisitors[player.UserId] = playerInfo
	
	print("Player joined: " .. player.Name .. " (ID: " .. tostring(player.UserId) .. ")")

	local playerGui = player:WaitForChild("PlayerGui")
	local visitorUI = playerGui:WaitForChild("AVisitorList", 10)

	if visitorUI then
		if ADMIN_IDS[player.UserId] then
			-- Enable UI and send visitor history to admins
			print("Admin detected: Enabling Visitor UI")
			visitorUI.Enabled = true

			-- Send both global and session visitor data
			local success, globalHistory = pcall(function()
				return visitorStore:GetAsync("AllVisitorsList") or {}
			end)

			local sessionVisitors = {}
			for _, info in pairs(currentSessionVisitors) do
				table.insert(sessionVisitors, info.UserId)
			end
			
			if success then
				remoteEvent:FireClient(player, globalHistory, sessionVisitors, currentSessionVisitors)
			end
		else
			-- Disable UI for non-admin players
			print("Non-admin detected: Disabling Visitor UI")
			visitorUI.Enabled = false
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Run for existing players during Studio testing
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end