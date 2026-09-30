-- SharkLure
-- Where SharkBaitService (which throws and eats bait) and SharkService (which hunts) meet.
-- SharkService is a Script and cannot be required, so the shared state lives here.
--
-- A thrown bait is {pos = where a shark goes to take it, model, owner, expiresAt}.

local M = {}

local thrown = {}

M.EatHeld = nil -- function(player): a shark bit someone holding bait
M.OnEaten = nil -- function(bait): a shark reached a thrown bait

function M.Add(bait)
	table.insert(thrown, bait)
end

function M.Thrown()
	return thrown
end

function M.Remove(bait)
	bait.gone = true
	for i, b in ipairs(thrown) do
		if b == bait then
			table.remove(thrown, i)
			return
		end
	end
end

function M.Consume(bait)
	if bait.gone then
		return
	end
	M.Remove(bait)
	if M.OnEaten then
		M.OnEaten(bait)
	end
end

return M
