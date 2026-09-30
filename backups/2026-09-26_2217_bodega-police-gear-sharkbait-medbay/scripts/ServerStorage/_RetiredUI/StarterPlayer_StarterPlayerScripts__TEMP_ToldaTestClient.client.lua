-- TEMPORARY verification harness for the tolda. Delete after reading.
-- Fires the real remotes, because the Studio sandbox cannot FireServer by itself.
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local requestTolda = remotes:WaitForChild("RequestTolda")
local toldaStatus = remotes:WaitForChild("ToldaStatus")
local toldaUpdated = remotes:WaitForChild("ToldaUpdated")

toldaStatus.OnClientEvent:Connect(function(message, ok)
	print(string.format("[TOLDATEST-C] server says (%s): %s", ok and "ok" or "refused", tostring(message)))
end)

-- This is the event the stock panel listens to. If it never arrives, the player never
-- sees a UI -- which was the whole complaint.
toldaUpdated.OnClientEvent:Connect(function(tentId, ownerName, ownerId, rows, isMine)
	print(string.format("[TOLDATEST-C] PANEL PUSHED -- tent %s, owner %s, mine=%s, %d row(s) on the rack",
		tostring(tentId), tostring(ownerName), tostring(isMine), #rows))
end)

task.wait(11)
print("[TOLDATEST-C] pitching a tolda straight from the bodega")
requestTolda:FireServer("pitch")

task.wait(6)
print("[TOLDATEST-C] putting 4 kabibe on the rack at 40 Peso")
requestTolda:FireServer("list", "kabibe", 4, 40)
