-- SlashAnim
-- The default Animate script plays its tool-slash swing when a StringValue named toolanim
-- appears in the equipped tool, and it has to be created on the server to replicate.

local tool = script.Parent

tool.Activated:Connect(function()
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
end)
