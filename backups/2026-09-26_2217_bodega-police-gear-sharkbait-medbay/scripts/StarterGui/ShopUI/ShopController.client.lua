-- ShopController
-- Opens the shop panel from the Palengke market prompt and routes button clicks to the
-- purchase-request remotes. The server owns the real product/pass ids -- this only ever
-- sends a friendly key like "KasamaVIP", never a Robux amount or asset id.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelUtil = require(ReplicatedStorage:WaitForChild("PanelUtil"))

local ui = script.Parent
local panel = ui:WaitForChild("Panel")
-- Everything below the header lives in a scrolling frame now -- the shop's content is
-- taller than any sane fixed panel height, and it used to overflow off the card.
local content = panel:WaitForChild("Content")

-- Shift lock and first person pin the cursor to the middle of the screen, which left an
-- open shop unclickable. PanelUtil frees the cursor while any panel is open (the old
-- ModalEnabled approach also hid the phone thumbstick, so you could not walk away either),
-- and closes the shop once you leave the deck.
local oddsPanelRef = ui:FindFirstChild("OddsPanel")
PanelUtil.Register("islandshop", {
	open = function() panel.Visible = true end,
	close = function()
		panel.Visible = false
		if oddsPanelRef then
			oddsPanelRef.Visible = false
		end
	end,
	isOpen = function() return panel.Visible end,
})

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestProduct = remotes:WaitForChild("RequestProductPurchase")
local requestPass = remotes:WaitForChild("RequestGamePassPurchase")
local requestGift = remotes:WaitForChild("RequestGift")
local giftFeedback = remotes:WaitForChild("GiftFeedback")

local marketDeck = Workspace:WaitForChild("IslaMarahuyo"):WaitForChild("PalengkeMarketDeck")
local shopPrompt = marketDeck:WaitForChild("ShopPrompt")

shopPrompt.Triggered:Connect(function()
	PanelUtil.Toggle("islandshop", {anchor = "here", radius = 22})
end)

panel.CloseButton.Activated:Connect(function()
	PanelUtil.Close("islandshop")
end)

-- ===== Bilao Box drop rates =====
-- Roblox requires the odds for a random-item product to be visible inside the
-- experience. These are read from ReplicatedStorage.BilaoBoxOdds, which the server
-- publishes from the very table it rolls on.
do
	local oddsPanel = ui:WaitForChild("OddsPanel", 10)
	local oddsButton = content:WaitForChild("OddsButton", 10)
	if oddsPanel and oddsButton then
		local rendered = false

		local function renderOdds()
			local folder = ReplicatedStorage:FindFirstChild("BilaoBoxOdds")
			if not folder then
				return false
			end

			local entries = folder:GetChildren()
			table.sort(entries, function(a, b)
				return a.Name < b.Name
			end)

			local shown, sum = 0, 0
			for i = 1, 8 do
				local row = oddsPanel.Rows:FindFirstChild("Row" .. i)
				local entry = entries[i]
				if row then
					if entry then
						local pct = entry:GetAttribute("Percent") or 0
						row.Visible = true
						row.ItemName.Text = entry:GetAttribute("ItemName") or entry.Name
						row.Rarity.Text = entry:GetAttribute("Rarity") or ""
						row.Pct.Text = string.format("%.2f%%", pct)
						shown += 1
						sum += pct
					else
						row.Visible = false
					end
				end
			end

			oddsPanel.Total.Text = string.format("%d items -- total %.0f%%", shown, sum)
			return shown > 0
		end

		oddsButton.Activated:Connect(function()
			if not rendered then
				rendered = renderOdds()
			end
			oddsPanel.Visible = not oddsPanel.Visible
		end)

		oddsPanel.Close.Activated:Connect(function()
			oddsPanel.Visible = false
		end)

		task.spawn(function()
			for _ = 1, 15 do
				if renderOdds() then
					rendered = true
					return
				end
				task.wait(1)
			end
		end)
	end
end

for _, child in ipairs(content:GetChildren()) do
	if child:IsA("TextButton") and child.Name ~= "CloseButton" then
		local prefix, key = child.Name:match("^(%a+)_(.+)$")
		if prefix == "Pass" then
			child.Activated:Connect(function()
				requestPass:FireServer(key)
			end)
		elseif prefix == "Product" then
			child.Activated:Connect(function()
				requestProduct:FireServer(key)
			end)
		end
	end
end

local usernameBox = content:WaitForChild("UsernameBox")
local statusLabel = content:WaitForChild("StatusLabel")
local giftButtonRow = content:WaitForChild("GiftButtonRow")

for _, btn in ipairs(giftButtonRow:GetChildren()) do
	if btn:IsA("TextButton") then
		local amount = tonumber(btn.Name:match("^Gift_(%d+)$"))
		if amount then
			btn.Activated:Connect(function()
				local username = usernameBox.Text
				if username == "" then
					statusLabel.Text = "Type a friend's username first."
					return
				end
				statusLabel.Text = "Sending..."
				requestGift:FireServer(username, amount)
			end)
		end
	end
end

giftFeedback.OnClientEvent:Connect(function(message)
	statusLabel.Text = message
end)
