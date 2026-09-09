return function(require)
	local HttpService = game:GetService("HttpService")
	local Players = game:GetService("Players")

	local Storage = {}
	Storage.__index = Storage
	Storage.MaxBytes = 196608
	Storage.VerifyUrl = "https://unknownhub.win/api/lua/key/verify"
	Storage.DefaultProjectId = "54474b4c5d5a4f459909c4cb70e7b4f3"

	function Storage.NormalizeKeyMetadata(payload)
		payload = type(payload) == "table" and payload or {}
		local metadata = {}
		local limits = {
			ticket = 8192,
			ticketType = 64,
			ticketExpiresAt = 64,
			keyPrefix = 128,
			keyType = 32,
			expiresAt = 64,
			projectId = 128,
			scriptId = 128,
			serverTime = 64,
			code = 128,
			message = 300,
		}
		for name, limit in pairs(limits) do
			local value = payload[name]
			if name == "ticket" then
				value = value or payload.unlockTicket or payload.keyTicket
			end
			if name == "ticketExpiresAt" then
				value = value or payload.ticket_expires_at or payload.unlockTicketExpiresAt
			end
			if type(value) == "string" then
				metadata[name] = value:sub(1, limit)
			end
		end
		for _, name in ipairs({ "noExpiry", "scriptKnown", "hwidBound", "ServerVerified", "Local", "Developer" }) do
			if type(payload[name]) == "boolean" then
				metadata[name] = payload[name]
			end
		end
		local ticketSeconds = tonumber(
			payload.ticketSecondsRemaining
				or payload.ticket_seconds_remaining
				or payload.ticketTtlSeconds
				or payload.ticket_ttl_seconds
		)
		local seconds = tonumber(
			payload.secondsRemaining
				or payload.keySecondsRemaining
				or payload.key_seconds_remaining
				or payload.seconds_remaining
		)
		if ticketSeconds and ticketSeconds == ticketSeconds and math.abs(ticketSeconds) < math.huge then
			metadata.ticketSecondsRemaining = ticketSeconds
		end
		if seconds and seconds == seconds and math.abs(seconds) < math.huge and not metadata.noExpiry then
			metadata.secondsRemaining = seconds
			metadata.keySecondsRemaining = seconds
		end
		if metadata.noExpiry then
			metadata.expiresAt = nil
		end
		metadata.unlockTicket = metadata.ticket
		return metadata
	end

	local function safeName(value)
		return type(value) == "string" and #value > 0 and #value <= 80 and value:match("^[%w_%-]+$") ~= nil
	end

	local function getRequestFunction()
		if type(request) == "function" then
			return request
		end
		if type(http_request) == "function" then
			return http_request
		end
		if type(http) == "table" and type(http.request) == "function" then
			return http.request
		end
		if type(syn) == "table" and type(syn.request) == "function" then
			return syn.request
		end
		if type(fluxus) == "table" and type(fluxus.request) == "function" then
			return fluxus.request
		end
		return nil
	end

	local function normalizeResponse(response)
		if type(response) == "string" then
			return { StatusCode = 200, Body = response }
		end
		if type(response) ~= "table" then
			return nil
		end
		return {
			StatusCode = tonumber(response.StatusCode or response.Status or response.status_code or response.status)
				or 0,
			Body = response.Body or response.body or response.ResponseBody,
		}
	end

	local function readFingerprint()
		local providers = {
			function()
				return type(get_hwid) == "function" and get_hwid() or nil
			end,
			function()
				return type(gethwid) == "function" and gethwid() or nil
			end,
			function()
				return game:GetService("RbxAnalyticsService"):GetClientId()
			end,
		}
		for _, provider in ipairs(providers) do
			local ok, value = pcall(provider)
			if ok and (type(value) == "string" or type(value) == "number") then
				value = tostring(value):match("^%s*(.-)%s*$")
				if #value > 0 and #value <= 512 and not value:find("%c") then
					return value
				end
			end
		end
		return nil
	end

	local function getQueueFunction()
		if type(queue_on_teleport) == "function" then
			return queue_on_teleport
		end
		if type(queueonteleport) == "function" then
			return queueonteleport
		end
		if type(syn) == "table" then
			if type(syn.queue_on_teleport) == "function" then
				return syn.queue_on_teleport
			end
			if type(syn.queueonteleport) == "function" then
				return syn.queueonteleport
			end
		end
		if type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
			return fluxus.queue_on_teleport
		end
		return nil
	end

	local function executorState(caps)
		if type(caps.RuntimeState) == "table" then
			return caps.RuntimeState
		end
		if type(getgenv) == "function" then
			local ok, value = pcall(getgenv)
			if ok and type(value) == "table" then
				return value
			end
		end
		return type(_G) == "table" and _G or {}
	end

	local function capabilities(options)
		if options.Capabilities then
			assert(type(options.Capabilities) == "table", "Capabilities must be a table")
			return options.Capabilities
		end
		return {
			readfile = readfile,
			writefile = writefile,
			isfile = isfile,
			isfolder = isfolder,
			makefolder = makefolder,
			delfile = delfile,
			listfiles = listfiles,
			request = getRequestFunction(),
			loadstring = loadstring,
			gethwid = readFingerprint,
			queue_on_teleport = getQueueFunction(),
		}
	end

	function Storage:RunLoader(url)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		local caps = self.Capabilities
		if type(caps.request) ~= "function" or type(caps.loadstring) ~= "function" then
			return false, "Executor request/loadstring capabilities are unavailable."
		end
		if type(url) ~= "string" or not url:match("^https://[^%s]+$") then
			return false, "Configure an HTTPS loader URL."
		end
		local ok, response = pcall(caps.request, { Url = url, Method = "GET" })
		response = normalizeResponse(response)
		local status = if type(response) == "table" then tonumber(response.StatusCode) else nil
		if not self.Alive then
			return false, "Loader was cancelled."
		end
		if
			not ok
			or type(response) ~= "table"
			or status == nil
			or status < 200
			or status >= 300
			or type(response.Body) ~= "string"
			or #response.Body > 4194304
		then
			return false, "Loader download failed."
		end
		local compiled, chunk = pcall(caps.loadstring, response.Body)
		if not self.Alive then
			return false, "Loader was cancelled."
		end
		if not compiled or type(chunk) ~= "function" then
			return false, "Loader compilation failed."
		end
		local ran, value = pcall(chunk)
		return ran, if ran then value else "Loader execution failed."
	end

	function Storage.new(options)
		options = options or {}
		local caps = capabilities(options)
		local runtimeState = executorState(caps)
		if type(runtimeState.__UI_LIBDataLocks) ~= "table" then
			runtimeState.__UI_LIBDataLocks = {}
		end
		local folder = options.ConfigFolder or "UI_LIB"
		assert(safeName(folder), "ConfigFolder must be a simple folder name")
		return setmetatable({
			Capabilities = caps,
			RuntimeState = runtimeState,
			DataLocks = runtimeState.__UI_LIBDataLocks,
			DataNamespace = "executor:" .. folder,
			Folder = folder,
			Backend = "Executor files",
			Persistent = false,
			Executor = true,
			ExecutorRuntime = true,
			Alive = true,
			LastError = nil,
		}, Storage)
	end

	function Storage:_result(ok, value)
		self.Persistent = ok == true
		self.LastError = if ok then nil else tostring(value)
		return ok, value
	end

	function Storage:Read(key)
		if not self.Alive or not safeName(key) then
			return false, "Invalid storage key."
		end
		local caps = self.Capabilities
		if type(caps.readfile) ~= "function" then
			return self:_result(false, "Executor readfile capability is unavailable.")
		end
		local path = self.Folder .. "/" .. key .. ".json"
		if type(caps.isfile) == "function" then
			local ok, exists = pcall(caps.isfile, path)
			if not self.Alive then
				return false, "Storage was destroyed."
			end
			if not ok then
				return self:_result(false, "Unable to check config file.")
			end
			if not exists then
				return true, nil
			end
		end
		local ok, raw = pcall(caps.readfile, path)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if not ok or type(raw) ~= "string" then
			return self:_result(false, "Unable to read config file.")
		end
		if #raw > Storage.MaxBytes then
			return self:_result(false, "Config file exceeds size limit.")
		end
		return self:_result(true, raw)
	end

	function Storage:Write(key, raw)
		if not self.Alive or not safeName(key) or type(raw) ~= "string" or #raw > Storage.MaxBytes then
			return false, "Invalid or oversized storage payload."
		end
		local caps = self.Capabilities
		if type(caps.writefile) ~= "function" or type(caps.readfile) ~= "function" then
			return self:_result(false, "Executor writefile/readfile capabilities are required for verified saves.")
		end
		local exists = false
		if type(caps.isfolder) == "function" then
			local ok, value = pcall(caps.isfolder, self.Folder)
			exists = ok and value == true
		end
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if not exists and type(caps.makefolder) == "function" then
			pcall(caps.makefolder, self.Folder)
		end
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		local path = self.Folder .. "/" .. key .. ".json"
		local ok = pcall(caps.writefile, path, raw)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if not ok then
			return self:_result(false, "Unable to write config file.")
		end
		local readOk, verified = pcall(caps.readfile, path)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if not readOk or verified ~= raw then
			return self:_result(false, "Config write verification failed.")
		end
		return self:_result(true, "Saved to executor files.")
	end

	function Storage:Delete(key)
		if not self.Alive or not safeName(key) then
			return false, "Invalid storage key."
		end
		if type(self.Capabilities.delfile) ~= "function" then
			return false, "delfile is unavailable."
		end
		local ok = pcall(self.Capabilities.delfile, self.Folder .. "/" .. key .. ".json")
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		return self:_result(ok, ok and "Deleted." or "Unable to delete config file.")
	end

	function Storage:List()
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if type(self.Capabilities.listfiles) ~= "function" then
			return false, "listfiles is unavailable."
		end
		local ok, files = pcall(self.Capabilities.listfiles, self.Folder)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if not ok or type(files) ~= "table" or #files > 4096 then
			return false, "Unable to list config files."
		end
		local result = {}
		local seen = {}
		for _, path in ipairs(files) do
			local name = tostring(path):gsub("\\", "/"):match("([^/]+)%.json$")
			if name and safeName(name) and not seen[name] then
				seen[name] = true
				table.insert(result, name)
			end
		end
		table.sort(result)
		return true, result
	end

	function Storage:VerifyKey(key, options)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if type(key) ~= "string" or #key == 0 or #key > 512 or key:find("%c") then
			return false, "Enter a valid key."
		end
		options = options or {}
		if type(options) ~= "table" then
			return false, "Verification options must be a table."
		end
		if type(self.Capabilities.request) ~= "function" then
			return false, "Executor request capability is unavailable."
		end
		local url = options.UnknownHubVerifyUrl or options.KeyVerifyUrl or Storage.VerifyUrl
		if type(url) ~= "string" or not url:match("^https://[^%s]+$") then
			return false, "Key verification requires an HTTPS URL."
		end
		local fingerprint = options.ClientFingerprint
		local provider = options.GetHWID
			or (type(fingerprint) == "function" and fingerprint)
			or self.Capabilities.gethwid
		if type(fingerprint) ~= "string" and type(provider) == "function" then
			local resolved, value = pcall(provider)
			if resolved then
				fingerprint = value
			end
		end
		if not self.Alive then
			return false, "Verification was cancelled."
		end
		if type(fingerprint) == "string" then
			fingerprint = fingerprint:match("^%s*(.-)%s*$")
		end
		if type(fingerprint) ~= "string" or #fingerprint == 0 or #fingerprint > 512 or fingerprint:find("%c") then
			return false,
				"Device-bound verification requires GetHWID, ClientFingerprint, or the executor gethwid capability."
		end
		local player = Players.LocalPlayer
		local scriptId = options.UnknownHubScriptId
			or options.UnknownHubScriptID
			or options.ScriptId
			or options.ScriptID
			or ""
		local projectId = options.UnknownHubProjectId
			or options.UnknownHubProjectID
			or options.ProjectId
			or options.ProjectID
			or Storage.DefaultProjectId
		if type(scriptId) ~= "string" or #scriptId > 128 or type(projectId) ~= "string" or #projectId > 128 then
			return false, "Verification target IDs must be bounded strings."
		end
		if scriptId == "" and projectId == "" then
			return false, "ScriptId or ProjectId is required."
		end
		local body = HttpService:JSONEncode({
			key = key,
			script_id = scriptId,
			project_id = projectId,
			roblox_user_id = player and tostring(player.UserId) or "",
			game_id = tostring(game.GameId),
			place_id = tostring(game.PlaceId),
			job_id = game.JobId,
			hwid = fingerprint,
		})
		local ok, response = pcall(self.Capabilities.request, {
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
			Body = body,
		})
		response = normalizeResponse(response)
		if not self.Alive then
			return false, "Verification was cancelled."
		end
		if not ok or type(response) ~= "table" then
			return false, "Key verification request failed."
		end
		if type(response.Body) ~= "string" or #response.Body > 32768 then
			return false, "Key server returned an invalid response."
		end
		local decoded, payload = pcall(HttpService.JSONDecode, HttpService, response.Body)
		if not decoded or type(payload) ~= "table" then
			return false, "Key server returned an invalid response."
		end
		local status = tonumber(response.StatusCode) or 0
		if status < 200 or status >= 300 then
			return false, payload.message or "Key server rejected the request."
		end
		return payload.valid == true, payload.message or (payload.valid and "Key accepted." or "Invalid key."), payload
	end

	function Storage:GetGames()
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		local requestFunction = self.Capabilities.request
		if type(requestFunction) ~= "function" then
			return false, "Executor request capability is unavailable."
		end
		local ok, response = pcall(requestFunction, { Url = "https://unknownhub.win/api/games", Method = "GET" })
		response = normalizeResponse(response)
		if not self.Alive then
			return false, "Catalog request was cancelled."
		end
		if
			not ok
			or type(response) ~= "table"
			or type(response.StatusCode) ~= "number"
			or response.StatusCode < 200
			or response.StatusCode >= 300
			or type(response.Body) ~= "string"
			or #response.Body > 524288
		then
			return false, "Game catalog request failed."
		end
		local decoded, payload = pcall(HttpService.JSONDecode, HttpService, response.Body)
		if not decoded or type(payload) ~= "table" or type(payload.games) ~= "table" or #payload.games > 500 then
			return false, "Invalid game catalog response."
		end
		local games = {}
		for _, record in ipairs(payload.games) do
			if type(record) ~= "table" or type(record.name) ~= "string" or #record.name > 120 then
				return false, "Invalid game catalog record."
			end
			local gameId = tonumber(record.gameId)
			if not gameId or gameId <= 0 or gameId % 1 ~= 0 or gameId > 9007199254740991 then
				return false, "Invalid catalog game ID."
			end
			table.insert(games, {
				gameId = gameId,
				name = record.name,
				status = type(record.status) == "string" and record.status:sub(1, 64) or "Unknown",
				thumbnailUrl = type(record.thumbnailUrl) == "string" and record.thumbnailUrl:sub(1, 2048) or "",
			})
		end
		return true, games
	end

	function Storage:ReadLegacy(name)
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		if
			type(name) ~= "string"
			or #name > 80
			or not (
				name == "key"
				or name == "autoload"
				or name == "universal"
				or name:match("^game_%d+$")
				or name:match("^place_%d+$")
			)
		then
			return false, "Unsupported legacy file name."
		end
		local caps = self.Capabilities
		if type(caps.readfile) ~= "function" then
			return false, "Executor readfile capability is unavailable."
		end
		local config = name ~= "key" and name ~= "autoload"
		local paths = { "UnknownHub/" .. name .. ".json" }
		if config then
			table.insert(paths, paths[1] .. ".bak")
			table.insert(paths, "UnknownHub_" .. name .. ".json")
			table.insert(paths, "UnknownHub_" .. name .. ".json.bak")
		end
		local invalid = false
		for _, path in ipairs(paths) do
			local exists = true
			if type(caps.isfile) == "function" then
				local checked, present = pcall(caps.isfile, path)
				if not self.Alive then
					return false, "Storage was destroyed."
				end
				if not checked then
					return false, "Unable to inspect legacy file."
				end
				exists = present == true
			end
			if exists then
				local read, raw = pcall(caps.readfile, path)
				if not self.Alive then
					return false, "Storage was destroyed."
				end
				if not read or type(raw) ~= "string" then
					invalid = true
				elseif #raw > Storage.MaxBytes then
					invalid = true
				elseif not config then
					return true, raw, path
				else
					local decoded, value = pcall(HttpService.JSONDecode, HttpService, raw)
					if decoded and type(value) == "table" then
						return true, raw, path
					end
					invalid = true
				end
			end
		end
		if invalid then
			return false, "Legacy file could not be read safely; original files were preserved."
		end
		return true, nil
	end

	function Storage:Destroy()
		self.Alive = false
		self.Capabilities = {}
	end

	return Storage
end
