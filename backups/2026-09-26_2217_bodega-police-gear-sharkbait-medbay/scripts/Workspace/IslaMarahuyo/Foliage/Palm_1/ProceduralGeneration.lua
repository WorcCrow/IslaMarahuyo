--!strict
-- generationId: c9211f49-668b-44a3-beb8-8feaeedd6d2e
local CSG = require(script.Dependencies.ConstructiveSolidGeometry)
local GP = require(script.Dependencies.GeometryPrimitives)
local SO = require(script.Dependencies.SmartObject)
local MU = require(script.Dependencies.MathUtils)


local PalmTree = {}

type Parameters = {
	Size: Vector3,
	Attributes: {
		ColorTrunk: Color3?,
		ColorLeafLight: Color3?,
		ColorLeafDark: Color3?,
		ColorCoconut: Color3?,
		Material: string?,
	},
}
local startTime = 0
local timerThread : thread = task.spawn(function()
while true do
	if not script:IsDescendantOf(game) then
		startTime = 0
		return
	end
	if startTime > 0 then
		local elapsed = tick() - startTime
		print("[ProceduralModel] " .. script:GetFullName() .. " rendering... " .. string.format("%.0f", elapsed) .. " seconds")
	end
	task.wait(3)
end
end)
script.Destroying:Connect(function()
	task.cancel(timerThread)
end)

PalmTree.OnGenerate = function(parameters: Parameters, targetContainer: Instance)
	-- Timer setup
	startTime = tick()

	local palmTree = GP.model("PalmTree", nil)-- Fix orientation of the model
	palmTree.WorldPivot = CFrame.identity
	
	
	-- == Smart Dimensions ==
	local smartWidth = parameters.Size.X
	local smartHeight = parameters.Size.Y
	local smartDepth = parameters.Size.Z
	
	local scaleX = smartWidth / 10
	local scaleY = smartHeight / 10
	local scaleZ = smartDepth / 10
	
	-- Base radii and scales
	local trunkBaseRadius = 0.8 * math.min(scaleX, scaleZ)
	local trunkTopRadius = 0.4 * math.min(scaleX, scaleZ)
	local canopySpread = 6.0 * math.max(scaleX, scaleZ)
	local treeHeight = 12.0 * scaleY
	
	-- Colors
	local c_trunk = parameters.Attributes.ColorTrunk or Color3.fromRGB(150, 100, 70)
	local c_leafLight = parameters.Attributes.ColorLeafLight or Color3.fromRGB(130, 200, 90)
	local c_leafDark = parameters.Attributes.ColorLeafDark or Color3.fromRGB(80, 160, 70)
	local c_coconut = parameters.Attributes.ColorCoconut or Color3.fromRGB(180, 120, 50)
	
	local material = parameters.Attributes.Material or "SmoothPlastic"
	
	-- == TOP LEVEL MODELS ==
	-- MUST BE EXACTLY THESE NAMES
	local trunkModel = GP.model("trunk", palmTree)
	local frondsModel = GP.model("fronds", palmTree)
	
	-- == TRUNK ==
	-- Create a gentle S-curve for the trunk
	local p0 = Vector3.new(0, 0, 0)
	local p1 = Vector3.new(2 * scaleX, treeHeight * 0.3, 1 * scaleZ)
	local p2 = Vector3.new(-1 * scaleX, treeHeight * 0.7, -1 * scaleZ)
	local p3 = Vector3.new(0, treeHeight, 0)
	
	local trunkSegments = 8
	local trunkPoints = MU.sampleBezierPoints(p0, p1, p2, p3, trunkSegments)
	local trunkSides = 6 -- Low poly look
	
	for i = 1, #trunkPoints - 1 do
	    local startP = trunkPoints[i]
	    local endP = trunkPoints[i+1]
	    
	    local t1 = (i - 1) / trunkSegments
	    local t2 = i / trunkSegments
	    
	    local r1 = MU.lerp(trunkBaseRadius, trunkTopRadius, t1)
	    local r2 = MU.lerp(trunkBaseRadius, trunkTopRadius, t2)
	    local rAvg = (r1 + r2) / 2
	    
	    -- Using regularPrism to get that faceted, low-poly trunk look
	    GP.regularPrism("Segment_" .. i, startP, endP, rAvg, trunkSides, c_trunk, material, trunkModel)
	end
	
	-- == COCONUTS ==
	-- We place these in the fronds model to keep the top-level clean
	local coconutCount = 3
	local coconutRadius = 0.6 * math.min(scaleX, scaleZ)
	
	for i = 1, coconutCount do
	    local angle = (i / coconutCount) * math.pi * 2
	    -- Offset slightly below the top of the trunk
	    local cCenter = p3 + Vector3.new(math.cos(angle) * trunkTopRadius * 1.5, -coconutRadius * 1.5, math.sin(angle) * trunkTopRadius * 1.5)
	    
	    -- Create a faceted coconut using a regular prism roughly shaped like a sphere/diamond
	    -- A low-segment prism looks appropriately chunky
	    GP.regularPrism("Coconut_" .. i, 
	        cCenter - Vector3.new(0, coconutRadius * 0.8, 0), 
	        cCenter + Vector3.new(0, coconutRadius * 0.8, 0), 
	        coconutRadius, 6, c_coconut, material, frondsModel)
	end
	
	-- == FRONDS ==
	-- Low poly fronds constructed from quads
	local function buildLowPolyFrond(namePrefix, startPos, dirXZ, length, droop, segments, width)
	    local p0 = startPos
	    local p1 = startPos + dirXZ * (length * 0.3) + Vector3.new(0, length * 0.3, 0)
	    local p2 = startPos + dirXZ * (length * 0.7) + Vector3.new(0, length * 0.1, 0)
	    local p3 = startPos + dirXZ * length + Vector3.new(0, -droop, 0)
	    
	    local spinePoints = MU.sampleBezierPoints(p0, p1, p2, p3, segments)
	    local frondGroup = GP.model(namePrefix, frondsModel)
	    
	    local thickness = 0.1 * scaleY
	    
	    for i = 1, #spinePoints - 1 do
	        local currP = spinePoints[i]
	        local nextP = spinePoints[i+1]
	        
	        local tCurr = (i - 1) / segments
	        local tNext = i / segments
	        
	        -- Width profile (tapers at ends)
	        local wCurr = width * math.sin(tCurr * math.pi)
	        local wNext = width * math.sin(tNext * math.pi)
	        if tCurr == 0 then wCurr = width * 0.2 end
	        if tNext == 1 then wNext = 0.05 end
	        
	        local forward = (nextP - currP).Unit
	        local right = Vector3.new(-forward.Z, 0, forward.X).Unit
	        local up = right:Cross(forward).Unit
	        
	        -- Create a V-shape cross section
	        local vDepthCurr = wCurr * 0.5
	        local vDepthNext = wNext * 0.5
	        
	        local lCurr = currP - right * (wCurr / 2) - up * vDepthCurr
	        local rCurr = currP + right * (wCurr / 2) - up * vDepthCurr
	        
	        local lNext = nextP - right * (wNext / 2) - up * vDepthNext
	        local rNext = nextP + right * (wNext / 2) - up * vDepthNext
	        
	        -- Alternate color slightly for facets
	        local cLeft = (i % 2 == 0) and c_leafLight or c_leafDark
	        local cRight = (i % 2 == 0) and c_leafDark or c_leafLight
	        
	        -- Left half
	        GP.quadFromFourPoints("Left_" .. i,
	            currP, lCurr, lNext, nextP,
	            thickness, up, cLeft, material, frondGroup)
	            
	        -- Right half
	        GP.quadFromFourPoints("Right_" .. i,
	            currP, nextP, rNext, rCurr,
	            thickness, up, cRight, material, frondGroup)
	    end
	end
	
	-- Generate layers of fronds
	local topCenter = p3 + Vector3.new(0, 0.2 * scaleY, 0)
	
	-- Inner layer (pointing mostly up and out)
	local innerCount = 5
	local innerOffset = 0
	for i = 1, innerCount do
	    local angle = (i / innerCount) * math.pi * 2 + innerOffset
	    local dirXZ = Vector3.new(math.cos(angle), 0, math.sin(angle))
	    buildLowPolyFrond("InnerFrond_"..i, topCenter, dirXZ, canopySpread * 0.7, 0, 4, canopySpread * 0.25)
	end
	
	-- Middle layer (pointing out and drooping)
	local midCount = 7
	local midOffset = math.pi / innerCount
	for i = 1, midCount do
	    local angle = (i / midCount) * math.pi * 2 + midOffset
	    local dirXZ = Vector3.new(math.cos(angle), 0, math.sin(angle))
	    buildLowPolyFrond("MidFrond_"..i, topCenter, dirXZ, canopySpread * 0.9, canopySpread * 0.3, 5, canopySpread * 0.3)
	end
	
	-- Outer layer (pointing out and drooping heavily)
	local outerCount = 6
	local outerOffset = math.pi / midCount
	for i = 1, outerCount do
	    local angle = (i / outerCount) * math.pi * 2 + outerOffset
	    local dirXZ = Vector3.new(math.cos(angle), 0, math.sin(angle))
	    buildLowPolyFrond("OuterFrond_"..i, topCenter, dirXZ, canopySpread * 1.0, canopySpread * 0.6, 5, canopySpread * 0.2)
	end
	
	palmTree.Parent = targetContainer
	-- reposition
	for _, part in targetContainer:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame -= Vector3.yAxis * parameters.Size.Y / 2
		end
	end
	for _, model in targetContainer:GetDescendants() do
		if model:IsA("Model") then
			model.WorldPivot -= Vector3.yAxis * parameters.Size.Y / 2
		end
	end

	-- Stop timer when generation completes
	local timeElapsed = tick() - startTime
	startTime = 0
	if timeElapsed > 3 and script:IsDescendantOf(game) then
		print("[ProceduralModel] " .. script:GetFullName() .. " rendering completed")
	end

end

return PalmTree
