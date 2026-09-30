-- Export-FromStudio.luau
-- Run inside Roblox Studio (Edit mode, via the MCP execute_luau tool) while
-- Receive-StudioBackup.ps1 is listening. Posts:
--   place/<Service>.rbxm       every top-level service's children, serialized
--   scripts/<path>.<kind>.lua  every script's source, mirroring the DataModel path
-- HttpService.HttpEnabled is switched on only for the export and always put back.

local PORT = 8765
local BASE = "http://localhost:" .. PORT

local http = game:GetService("HttpService")
local ss = game:GetService("SerializationService")
local es = game:GetService("EncodingService")

local SERVICES = {
	"Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage",
	"StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService", "Teams", "Chat",
	"TextChatService", "MaterialService",
}

local sent, bytes, failed = 0, 0, {}

local function post(path, data)
	local body = buffer.tostring(es:Base64Encode(data))
	local ok, err = pcall(function()
		http:PostAsync(BASE .. "/file?path=" .. http:UrlEncode(path), body, Enum.HttpContentType.TextPlain)
	end)
	if ok then
		sent += 1
		bytes += buffer.len(data)
	end
	return ok, err
end

local function safe(name)
	return (name:gsub('[<>:"/\\|%?%*%c]', "_"))
end

local function serialize(list)
	return pcall(function()
		return ss:SerializeInstancesAsync(list)
	end)
end

local function exportPlace()
	for _, name in ipairs(SERVICES) do
		local okS, svc = pcall(game.GetService, game, name)
		if okS and svc then
			local list = {}
			for _, c in ipairs(svc:GetChildren()) do
				if c.Archivable and not c:IsA("Camera") then
					table.insert(list, c)
				end
			end
			if #list > 0 then
				local okZ, buf = serialize(list)
				local okP = okZ and post("place/" .. name .. ".rbxm", buf)
				if not okP then
					-- too big (or one child refused): fall back to one file per child
					for _, c in ipairs(list) do
						local okC, cb = serialize({ c })
						local okCP, err = false, cb
						if okC then
							okCP, err = post("place/" .. name .. "/" .. safe(c.Name) .. "_" .. c.ClassName .. ".rbxm", cb)
						end
						if not okCP then
							table.insert(failed, name .. "." .. c.Name .. ": " .. tostring(err))
						end
					end
				end
			end
		end
	end
end

local function exportScripts()
	local used = {}
	local count = 0
	for _, s in ipairs(game:GetDescendants()) do
		if s:IsA("LuaSourceContainer") then
			local parts = {}
			local node = s
			while node and node ~= game do
				table.insert(parts, 1, safe(node.Name))
				node = node.Parent
			end
			local ext = s:IsA("LocalScript") and ".client.lua" or s:IsA("ModuleScript") and ".lua" or ".server.lua"
			local stem = "scripts/" .. table.concat(parts, "/")
			local path = stem .. ext
			local n = 2
			while used[path] do
				path = stem .. "__" .. n .. ext
				n += 1
			end
			used[path] = true
			local okSrc, src = pcall(function()
				return s.Source
			end)
			if okSrc then
				local okP, err = post(path, buffer.fromstring(src))
				if okP then
					count += 1
				else
					table.insert(failed, path .. ": " .. tostring(err))
				end
			else
				table.insert(failed, path .. ": unreadable source")
			end
		end
	end
	return count
end

local wasEnabled = http.HttpEnabled
http.HttpEnabled = true
local scriptCount = 0
local ok, err = pcall(function()
	exportPlace()
	scriptCount = exportScripts()
end)
pcall(function()
	http:PostAsync(BASE .. "/done", "", Enum.HttpContentType.TextPlain)
end)
http.HttpEnabled = wasEnabled

return string.format("%s -- %d files (%d scripts), %d bytes, %d failures%s | HttpEnabled restored to %s",
	ok and "export finished" or ("export ERRORED: " .. tostring(err)), sent, scriptCount, bytes, #failed,
	#failed > 0 and ("\n  " .. table.concat(failed, "\n  ")) or "", tostring(http.HttpEnabled))
