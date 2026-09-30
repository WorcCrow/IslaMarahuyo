-- QuestController
-- Renders today's island tasks. All progress is computed on the server; this only
-- draws whatever the server last sent, so nothing here can be edited to award Shells.
-- The panel opens from the top bar's menu (TopBarController), which shows the done/total
-- count in its label; the old always-on tab is hidden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("QuestGui")
local tab = gui:WaitForChild("Tab")
local badge = tab:WaitForChild("Badge")
local panel = gui:WaitForChild("Panel")
local list = panel:WaitForChild("List")
local bonusLabel = panel:WaitForChild("Bonus")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local tasksUpdated = remotes:WaitForChild("TasksUpdated")
local taskCompleted = remotes:WaitForChild("TaskCompleted")
local requestTasks = remotes:WaitForChild("RequestTasks")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local TEAL = Color3.fromRGB(31, 140, 122)
local DONE = Color3.fromRGB(120, 175, 90)
local MUTED = Color3.fromRGB(122, 102, 82)
local INK = Color3.fromRGB(58, 44, 32)

local function render(payload)
	if not payload or not payload.tasks then
		return
	end

	local doneCount = 0
	for i = 1, 4 do
		local row = list:FindFirstChild("Task" .. i)
		local data = payload.tasks[i]
		if not row then
			continue
		end
		if not data then
			row.Visible = false
			continue
		end

		row.Visible = true
		row.Title.Text = data.title
		row.Hint.Text = data.hint
		row.Reward.Text = "+" .. data.reward
		row.Count.Text = string.format("%d / %d", data.progress, data.goal)

		local ratio = math.clamp(data.progress / math.max(1, data.goal), 0, 1)
		TweenService:Create(row.Track.Fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			Size = UDim2.new(ratio, 0, 1, 0),
		}):Play()

		if data.done then
			doneCount += 1
			row.Track.Fill.BackgroundColor3 = DONE
			row.Title.TextColor3 = MUTED
			row.Count.Text = "done"
			row.Reward.TextColor3 = DONE
		else
			row.Track.Fill.BackgroundColor3 = TEAL
			row.Title.TextColor3 = INK
			row.Reward.TextColor3 = Color3.fromRGB(201, 102, 42)
		end
	end

	local total = #payload.tasks
	badge.Text = string.format("%d/%d", doneCount, total)
	-- local-only: the menu entry reads this for its label
	player:SetAttribute("TasksBadge", badge.Text)

	if payload.bonusPaid then
		bonusLabel.Text = "All tasks done -- bonus claimed"
		bonusLabel.TextColor3 = DONE
	elseif doneCount >= total and total > 0 then
		bonusLabel.Text = "All done! Bonus incoming..."
		bonusLabel.TextColor3 = DONE
	else
		bonusLabel.Text = string.format("Finish all %d for +%d Shells", total, payload.bonus or 50)
		bonusLabel.TextColor3 = MUTED
	end
end

tab.Visible = false
PanelUtil.Register("tasks", {
	open = function() panel.Visible = true end,
	close = function() panel.Visible = false end,
	isOpen = function() return panel.Visible end,
})
PanelUtil.AddCloseButton(panel, "tasks")

tasksUpdated.OnClientEvent:Connect(render)

local function announce(text, color)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color,
			Font = Enum.Font.GothamMedium,
		})
	end)
end

taskCompleted.OnClientEvent:Connect(function(title, reward, isBonus)
	if isBonus then
		announce(string.format("%s -- +%d Shells bonus!", title, reward), Color3.fromRGB(226, 168, 61))
	else
		announce(string.format("Task complete: %s -- +%d Shells", title, reward), Color3.fromRGB(120, 210, 180))
	end
	-- flash the tab so a collapsed panel still tells you something happened
	local original = tab.BackgroundColor3
	tab.BackgroundColor3 = Color3.fromRGB(120, 175, 90)
	task.delay(0.9, function()
		if tab.Parent then
			tab.BackgroundColor3 = original
		end
	end)
end)

-- Ask for the current state on join, in case the server pushed before this script ran.
task.spawn(function()
	for _ = 1, 12 do
		local ok, payload = pcall(function()
			return requestTasks:InvokeServer()
		end)
		if ok and payload then
			render(payload)
			return
		end
		task.wait(1)
	end
end)
