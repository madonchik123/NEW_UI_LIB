local HttpService = game:GetService("HttpService")
local Core = require(script.Parent.Core)
local DataFiles = require(script.Parent.DataFiles)

local AutoLoad = {}
AutoLoad.__index = AutoLoad
AutoLoad.BootstrapUrl = "https://raw.githubusercontent.com/madonchik123/NEW_UI_LIB/executor/UI_LIB.lua"
AutoLoad.ProjectId = "54474b4c5d5a4f459909c4cb70e7b4f3"

local aliases = {
	enabled = { "enabled", "Enabled", "AutoLoadUI", "AutoloadUI", "autoLoad", "AutoLoad", "Autoload" },
	loaderUrl = {
		"loaderUrl",
		"LoaderUrl",
		"AutoLoadUrl",
		"AutoloadUrl",
		"UnknownHubAutoLoadUrl",
		"UnknownHubLoaderUrl",
		"url",
		"Url",
	},
	bootstrapUrl = { "bootstrapUrl", "BootstrapUrl", "AutoLoadBootstrapUrl" },
	scriptId = { "scriptId", "ScriptId", "ScriptID", "UnknownHubScriptId", "UnknownHubScriptID", "script_id" },
	projectId = { "projectId", "ProjectId", "ProjectID", "UnknownHubProjectId", "UnknownHubProjectID", "project_id" },
	gameIds = {
		"gameIds",
		"GameIds",
		"AutoLoadGameIds",
		"AutoloadGameIds",
		"SupportedGameIds",
		"game_id",
		"gameId",
		"GameId",
	},
	placeIds = {
		"placeIds",
		"PlaceIds",
		"AutoLoadPlaceIds",
		"AutoloadPlaceIds",
		"SupportedPlaceIds",
		"place_id",
		"placeId",
		"PlaceId",
	},
	mode = { "mode", "Mode" },
	configName = { "configName", "ConfigName" },
}

local function trim(value)
	if type(value) ~= "string" and type(value) ~= "number" then
		return ""
	end
	return tostring(value):match("^%s*(.-)%s*$")
end

local function ids(...)
	local result, seen, visited = {}, {}, {}
	local function collect(value)
		if type(value) == "table" then
			if visited[value] then
				return
			end
			visited[value] = true
			for key, entry in pairs(value) do
				if entry == true then
					collect(key)
				elseif entry ~= false then
					collect(entry)
				end
			end
		else
			local id = trim(value)
			if id ~= "" and not seen[id] and #result < 256 then
				seen[id] = true
				table.insert(result, id)
			end
		end
	end
	for index = 1, select("#", ...) do
		collect(select(index, ...))
	end
	table.sort(result)
	return result
end

local function canonical(raw)
	if type(raw) == "boolean" then
		return { enabled = raw }
	end
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	for field, names in pairs(aliases) do
		for _, name in ipairs(names) do
			local value = raw[name]
			if value ~= nil then
				if field == "enabled" then
					if type(value) == "boolean" then
						result[field] = value
					end
				elseif field == "gameIds" or field == "placeIds" then
					result[field] = ids(result[field], value)
				else
					value = trim(value)
					if value ~= "" then
						result[field] = value
					end
				end
				if field ~= "gameIds" and field ~= "placeIds" then
					break
				end
			end
		end
	end
	return result
end

local function copy(data)
	local result = table.clone(data)
	result.gameIds = table.clone(data.gameIds or {})
	result.placeIds = table.clone(data.placeIds or {})
	return result
end

local function https(url)
	return type(url) == "string" and url:match("^https://[^%s]+$") ~= nil
end

local function merge(saved, options, previous, includeCurrent)
	local result = {
		version = 1,
		enabled = true,
		loaderUrl = "",
		bootstrapUrl = AutoLoad.BootstrapUrl,
		scriptId = "",
		projectId = "",
		mode = "",
		configName = "",
		gameIds = {},
		placeIds = {},
	}
	for _, raw in ipairs({ saved or {}, previous or {}, options or {} }) do
		for key, value in pairs(canonical(raw)) do
			if key == "gameIds" or key == "placeIds" then
				result[key] = ids(result[key], value)
			else
				result[key] = value
			end
		end
	end
	local raw = type(options) == "table" and options or {}
	if result.projectId == "" and raw.KeySystem == true and trim(raw.RequiredKey or raw.Key) == "" then
		result.projectId = AutoLoad.ProjectId
	end
	local optionUrl = canonical(raw).loaderUrl
	local explicitIds = canonical(raw)
	if not optionUrl and (result.loaderUrl == "" or explicitIds.projectId or explicitIds.scriptId) then
		local verify = trim(raw.UnknownHubVerifyUrl or raw.KeyVerifyUrl or raw.VerifyUrl)
		local origin = verify:match("^(https://[^/]+)") or "https://unknownhub.win"
		if result.projectId ~= "" then
			result.loaderUrl = origin .. "/api/projects/" .. HttpService:UrlEncode(result.projectId) .. "/loader"
			result.mode = "project"
		elseif result.scriptId ~= "" then
			result.loaderUrl = origin .. "/api/scripts/" .. HttpService:UrlEncode(result.scriptId) .. "/loader"
			result.mode = "script"
		end
	end
	if includeCurrent then
		result.gameIds = ids(result.gameIds, game.GameId)
	end
	return result
end

function AutoLoad.BuildQueuedSource(_data)
	return nil
end

function AutoLoad.new(storage, scope, options, dataFiles)
	local owned = Core.scope(scope)
	local caps = storage.Capabilities or {}
	local runtime = caps.RuntimeState or (storage.ExecutorRuntime and storage.RuntimeState)
	if type(runtime) ~= "table" then
		runtime = {}
	end
	local state = runtime.__UI_LIBAutoLoad
	if type(state) ~= "table" then
		state = { Runs = {} }
		runtime.__UI_LIBAutoLoad = state
	end
	state.Runs = type(state.Runs) == "table" and state.Runs or {}
	local self = setmetatable({
		Storage = storage,
		Scope = owned,
		Files = dataFiles or DataFiles.new(storage, owned),
		Options = table.clone(options or {}),
		Runtime = state,
		Listeners = {},
		Initialized = false,
		Busy = false,
	}, AutoLoad)
	self.Data = merge(nil, self.Options, nil, false)
	owned:Add(function()
		table.clear(self.Listeners)
	end)
	return self
end

function AutoLoad:GetData()
	return copy(self.Data)
end

function AutoLoad:GetEnabled()
	return self.Data.enabled
end

function AutoLoad:Subscribe(scope, callback)
	if not self.Scope.Alive or (scope and not scope.Alive) then
		return { Disconnect = function() end }
	end
	self.Listeners[callback] = true
	local function disconnect()
		self.Listeners[callback] = nil
	end
	(scope or self.Scope):Add(disconnect)
	Core.callback(callback, self:GetData())
	return { Disconnect = disconnect }
end

function AutoLoad:Initialize(options)
	if self.Initialized and options == nil then
		return self:GetData(), true, "Already initialized."
	end
	local initial = table.clone(self.Options)
	for key, value in pairs(canonical(self.Options)) do
		initial[key] = value
	end
	for key, value in pairs(options or {}) do
		initial[key] = value
	end
	for key, value in pairs(canonical(options)) do
		initial[key] = value
	end
	return self:Configure(initial)
end

function AutoLoad:Configure(options)
	if not self.Scope.Alive then
		return self:GetData(), false, "Autoload was destroyed."
	end
	if self.Busy then
		return self:GetData(), false, "Autoload configuration is busy."
	end
	self.Busy = true
	local ok, saved, message = self.Files:Read("autoload", true)
	if not ok or not self.Scope.Alive then
		self.Busy = false
		return self:GetData(), false, message or "Autoload was cancelled."
	end
	local data = merge(saved, options, nil, true)
	local written, writeMessage = self.Files:Write("autoload", data)
	self.Busy = false
	if not written or not self.Scope.Alive then
		return self:GetData(), false, writeMessage or "Autoload was cancelled."
	end
	self.Data, self.Initialized = data, true
	self.Runtime.Enabled = data.enabled
	for callback in pairs(self.Listeners) do
		if not self.Scope.Alive then
			break
		end
		Core.callback(callback, self:GetData())
	end
	if self.Scope.Alive and data.enabled and data.loaderUrl ~= "" then
		self:Queue(data)
	end
	return self:GetData(), true, writeMessage or "Autoload configured."
end

function AutoLoad:SetEnabled(enabled, options)
	local data = copy(self.Data)
	for key, value in pairs(canonical(options)) do
		data[key] = value
	end
	data.enabled = enabled == true
	return self:Configure(data)
end

function AutoLoad:_effective(data)
	if not self.Scope.Alive then
		return nil, "Autoload was destroyed."
	end
	local ok, saved, message = self.Files:Read("autoload", true)
	if not ok or not self.Scope.Alive then
		return nil, message or "Autoload was cancelled."
	end
	if canonical(saved).enabled == false then
		self.Runtime.Enabled = false
		return nil, "Automatic loading is disabled."
	end
	local effective = merge(saved, data or self.Data, nil, false)
	local provided = canonical(data)
	if provided.gameIds ~= nil or provided.placeIds ~= nil then
		effective.gameIds = provided.gameIds or {}
		effective.placeIds = provided.placeIds or {}
	end
	if effective.enabled == false or self.Runtime.Enabled == false then
		return nil, "Automatic loading is disabled."
	end
	if not https(effective.loaderUrl) or not https(effective.bootstrapUrl) then
		return nil, "Configure HTTPS loader and bootstrap URLs."
	end
	return effective
end

function AutoLoad:Queue(_data)
	return false, "Teleport code loading is unavailable in Studio."
end

function AutoLoad:_load(url, data)
	if not self.Scope.Alive or self.Runtime.Enabled == false then
		return false, "Loader was cancelled."
	end
	if type(self.Options.AutoLoadCallback) == "function" then
		return pcall(self.Options.AutoLoadCallback, copy(data))
	end
	return self.Storage:RunLoader(url)
end

function AutoLoad:Run(data)
	local effective, message = self:_effective(data)
	if not effective then
		return false, message
	end
	self:Queue(effective)
	if not self.Scope.Alive or self.Runtime.Enabled == false then
		return false, "Loader was cancelled."
	end
	local gameIds, placeIds = effective.gameIds, effective.placeIds
	local matched = if #gameIds > 0
		then table.find(gameIds, tostring(game.GameId)) ~= nil
		elseif #placeIds > 0 then table.find(placeIds, tostring(game.PlaceId)) ~= nil
		else false
	if not matched then
		return false, "Game does not match the configured loader."
	end
	local key =
		table.concat({ effective.loaderUrl, tostring(game.GameId), tostring(game.PlaceId), tostring(game.JobId) }, "::")
	if self.Runtime.Runs[key] then
		return false, "Loader already ran for this job."
	end
	self.Runtime.Runs[key] = "loading"
	local called, loaded, result = pcall(self._load, self, effective.loaderUrl, effective)
	if not called or not loaded then
		self.Runtime.Runs[key] = nil
		return false, tostring(if called then result else loaded)
	end
	self.Runtime.Runs[key] = "loaded"
	return true, result
end

function AutoLoad:Destroy()
	self.Scope:Destroy()
end

return AutoLoad
