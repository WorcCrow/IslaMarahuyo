-- TEMPORARY verification harness for the tolda. Delete after reading.
local Players = game:GetService("Players")
local PlayerProfileService = require(game:GetService("ServerScriptService").PlayerProfileService)
local LootService = require(game:GetService("ServerScriptService").LootService)

local function line(...) print("[TOLDATEST]", ...) end

local function run(plr)
	task.wait(5)
	local profile = PlayerProfileService.Get(plr.UserId)
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not (profile and root) then line("no profile/character") return end

	-- stock the player the way Suki would: the tolda lands in the BODEGA, not the bag
	profile.Inventory = profile.Inventory or {}
	profile.Inventory.tolda = 1
	profile.Gear = profile.Gear or {}
	LootService.Give(plr, "kabibe", 6)
	game:GetService("ServerStorage").InventoryRefresh:Fire(plr)
	line("granted 1 tolda to the BODEGA (bag has", (profile.Gear or {}).tolda or 0, ")")

	-- stand somewhere legal: dry land, well clear of the Palengke exclusion
	root.CFrame = CFrame.new(-225, 28, -67)
	task.wait(1)
	line("standing at the plaza, root Y =", string.format("%.2f", root.Position.Y))

	-- the client harness fires the pitch here
	task.wait(6)
	local folder = workspace.IslaMarahuyo:FindFirstChild("Toldas")
	local tent = folder and folder:GetChildren()[1]
	line("tent pitched =", tent ~= nil)
	if tent then
		local floor = tent.Floor
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { folder, plr.Character }
		local hit = workspace:Raycast(floor.Position + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
		local bottom = floor.Position.Y - floor.Size.Y / 2
		local gap = hit and (bottom - hit.Position.Y) or -999
		line(string.format("  floor bottom %.2f | ground %.2f | gap %+.2f -> %s",
			bottom, hit and hit.Position.Y or -999, gap,
			(math.abs(gap) < 0.5) and "SITTING ON THE GROUND" or "FLOATING"))
		line("  tolda left in bodega =", (profile.Inventory or {}).tolda or 0, "(expect 0 -- it is the tent now)")
	end

	-- the client harness lists a find here
	task.wait(4)
	line("finds left after listing =", (profile.Finds or {}).kabibe or 0, "(expect 2 -- 4 went on the rack)")
	if tent then
		local sign = tent.Floor.Sign.Label
		line("  tent sign reads:", string.format("%q", sign.Text))
	end
	line("=== done ===")
end

for _, plr in ipairs(Players:GetPlayers()) do task.spawn(run, plr) end
Players.PlayerAdded:Connect(function(plr) task.spawn(run, plr) end)
