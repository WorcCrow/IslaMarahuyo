-- ItemIcon
-- Draws a 3D model as a UI picture: a ViewportFrame holding a script-free copy of it,
-- framed by a fixed camera. No uploaded images to keep in sync with the models.
--   View(source, parent)  -- any Tool/Model the client can see (the Hotbar's tools)
--   ForKey(key, parent)   -- an item by ItemConfig key, from ReplicatedStorage.ItemIcons
--                            (the prefabs themselves live in ServerStorage, out of reach)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

-- a LocalScript left in the copy would start running the moment it landed under PlayerGui
local STRIP = {"LuaSourceContainer", "Sound", "Light", "ProximityPrompt", "LayerCollector", "ParticleEmitter"}

local function strip(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		for _, class in ipairs(STRIP) do
			if d:IsA(class) then
				d:Destroy()
				break
			end
		end
	end
end

function M.View(source, parent)
	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.BackgroundTransparency = 1
	view.Size = UDim2.new(1, -8, 1, -8)
	view.Position = UDim2.fromOffset(4, 4)
	view.Ambient = Color3.fromRGB(200, 200, 200)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.LightDirection = Vector3.new(-1, -1, -1)
	view.Parent = parent

	local model = Instance.new("Model")
	for _, child in ipairs(source:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") then
			local ok, copy = pcall(child.Clone, child)
			if ok and copy then
				strip(copy)
				copy.Parent = model
			end
		end
	end
	if #model:GetChildren() == 0 then
		view:Destroy()
		return nil
	end

	local world = Instance.new("WorldModel")
	world.Parent = view
	model.Parent = world

	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local from = cf.Position + (cf.LookVector * -0.4 + cf.RightVector + cf.UpVector * 0.5).Unit * distance
	camera.CFrame = CFrame.lookAt(from, cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
	return view
end

function M.ForKey(key, parent)
	local folder = ReplicatedStorage:FindFirstChild("ItemIcons")
	local source = folder and folder:FindFirstChild(key)
	return source and M.View(source, parent) or nil
end

return M
