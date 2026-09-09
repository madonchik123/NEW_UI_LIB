local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VERIFY_URL = "https://unknownhub.win/api/lua/key/verify"
local store = DataStoreService:GetDataStore("UnknownHubProfiles_v1")
local MAX_BYTES = 196608
local MAX_TOTAL_BYTES = 1048576
local states = {}
local gamesCache = nil
local gamesFetchedAt = -math.huge
local gamesBusy = false
local gamesAttemptedAt = -math.huge
local alive = true
local remote = Instance.new("RemoteFunction")
remote.Name = "UI_LIB_Storage"
assert(not ReplicatedStorage:FindFirstChild(remote.Name), "UnknownHub storage server is already installed")
remote.Parent = ReplicatedStorage

local function result(ok, value, message)
	return { Ok = ok, Value = value, Message = message }
end

local function validKey(key)
	return type(key) == "string" and #key > 0 and #key <= 80 and key:match("^[%w_%-]+$") ~= nil
end

local function validatePayload(raw, storageKey)
	if type(raw) ~= "string" or #raw > MAX_BYTES then
		return false
	end
	local decoded, document = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded then
		return false
	end
	if storageKey == "key" then
		local value = type(document) == "table" and (document.key or document.value) or document
		if type(value) ~= "string" or #value == 0 or #value > 512 or value:find("%c") then
			return false
		end
	elseif storageKey == "autoload" then
		if type(document) ~= "table" or document.version ~= 1 or type(document.enabled) ~= "boolean" then
			return false
		end
	elseif type(document) ~= "table" or document.Version ~= 1 then
		return false
	end
	local nodes = 0
	local function visit(value, depth)
		nodes += 1
		if nodes > 20000 or depth > 24 then
			return false
		end
		if type(value) == "table" then
			for key, child in pairs(value) do
				if type(key) == "string" and #key > 256 then
					return false
				end
				if not visit(child, depth + 1) then
					return false
				end
			end
		elseif type(value) == "number" then
			if value ~= value or math.abs(value) == math.huge then
				return false
			end
		elseif type(value) == "string" and #value > 16384 then
			return false
		end
		return true
	end
	return visit(document, 0)
end

local function load(player, state)
	if state.Document then
		return true
	end
	local ok, document = pcall(store.GetAsync, store, "player_" .. player.UserId)
	if not ok then
		return false
	end
	if document == nil then
		document = { Version = 1, Entries = {} }
	end
	if type(document) ~= "table" or document.Version ~= 1 or type(document.Entries) ~= "table" then
		return false
	end
	if not player.Parent then
		return false
	end
	state.Document = document
	return true
end

local function verify(player, key)
	if type(key) ~= "string" or #key < 1 or #key > 512 or key:find("%c") then
		return result(false, nil, "Invalid key input.")
	end
	local developerKey = script:GetAttribute("DeveloperKey") or script:GetAttribute("DevKey")
	if type(developerKey) == "string" then
		developerKey = developerKey:match("^%s*(.-)%s*$")
	end
	if type(developerKey) == "string" and #developerKey > 0 and key == developerKey then
		return result(true, {
			Valid = true,
			Message = "Developer key accepted.",
			Metadata = { Local = true, ServerVerified = true, Developer = true, keyType = "developer", noExpiry = true },
		})
	end
	local required = script:GetAttribute("RequiredKey")
	if type(required) == "string" and #required > 0 then
		local accepted = key == required
		return result(true, {
			Valid = accepted,
			Message = accepted and "Key accepted." or "Invalid key.",
			Metadata = { Local = true, ServerVerified = true, keyType = "local", noExpiry = true },
		})
	end
	local scriptId = script:GetAttribute("UnknownHubScriptId") or ""
	local projectId = script:GetAttribute("UnknownHubProjectId") or ""
	if type(scriptId) ~= "string" or type(projectId) ~= "string" or (#scriptId == 0 and #projectId == 0) then
		return result(false, nil, "Configure UnknownHubProjectId or UnknownHubScriptId on the storage server.")
	end
	local provider = script:FindFirstChild("ResolveKeyFingerprint")
	if not provider or not provider:IsA("BindableFunction") then
		return result(
			false,
			nil,
			"Native device-bound verification requires a server-configured ResolveKeyFingerprint provider."
		)
	end
	local resolved, fingerprint = pcall(provider.Invoke, provider, player)
	if type(fingerprint) == "string" then
		fingerprint = fingerprint:match("^%s*(.-)%s*$")
	end
	if
		not resolved
		or type(fingerprint) ~= "string"
		or #fingerprint == 0
		or #fingerprint > 512
		or fingerprint:find("%c")
	then
		return result(false, nil, "The server fingerprint provider did not return a valid identity.")
	end
	if not alive or not player.Parent then
		return result(false, nil, "Verification was cancelled.")
	end
	local body = HttpService:JSONEncode({
		key = key,
		script_id = scriptId,
		project_id = projectId,
		roblox_user_id = tostring(player.UserId),
		game_id = tostring(game.GameId),
		place_id = tostring(game.PlaceId),
		job_id = game.JobId,
		hwid = fingerprint,
	})
	local ok, response = pcall(HttpService.RequestAsync, HttpService, {
		Url = VERIFY_URL,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
		Body = body,
	})
	if not ok or not response.Success or type(response.Body) ~= "string" or #response.Body > 32768 then
		return result(false, nil, "Key server request failed. Check server HTTP configuration.")
	end
	local decoded, payload = pcall(HttpService.JSONDecode, HttpService, response.Body)
	if not decoded or type(payload) ~= "table" then
		return result(false, nil, "Invalid key server response.")
	end
	local ticket = payload.ticket or payload.unlockTicket or payload.keyTicket
	local ttl = tonumber(payload.ticketSecondsRemaining or payload.ticket_seconds_remaining or payload.ticketTtlSeconds)
	local accepted = payload.valid == true
		and type(ticket) == "string"
		and #ticket >= 80
		and ticket:match("^[%w_%-]+%.[%w_%-]+$") ~= nil
		and (not ttl or ttl > 0)

	local metadata = { ServerVerified = true }
	local stringFields = {
		ticketType = 64,
		ticketExpiresAt = 64,
		keyPrefix = 128,
		keyType = 32,
		expiresAt = 64,
		projectId = 128,
		scriptId = 128,
		serverTime = 64,
	}
	for field, limit in pairs(stringFields) do
		if type(payload[field]) == "string" then
			metadata[field] = payload[field]:sub(1, limit)
		end
	end
	for _, field in ipairs({ "noExpiry", "scriptKnown", "hwidBound" }) do
		if type(payload[field]) == "boolean" then
			metadata[field] = payload[field]
		end
	end
	metadata.ticket = type(ticket) == "string" and ticket:sub(1, 8192) or nil
	if ttl and ttl == ttl and math.abs(ttl) < math.huge then
		metadata.ticketSecondsRemaining = ttl
	end
	local seconds = tonumber(payload.secondsRemaining or payload.keySecondsRemaining or payload.key_seconds_remaining)
	if seconds and seconds == seconds and math.abs(seconds) < math.huge and not metadata.noExpiry then
		metadata.secondsRemaining = seconds
		metadata.keySecondsRemaining = seconds
	end
	if metadata.noExpiry then
		metadata.expiresAt = nil
	end
	local message = accepted and "Key accepted." or "Invalid or expired key ticket."
	if type(payload.message) == "string" then
		message = payload.message:sub(1, 300)
	end
	return result(true, { Valid = accepted, Message = message, Metadata = metadata })
end

local function getGames()
	if gamesCache and os.clock() - gamesFetchedAt < 60 then
		return result(true, gamesCache)
	end
	if gamesBusy then
		return result(false, nil, "Game catalog refresh is already running.")
	end
	if os.clock() - gamesAttemptedAt < 60 then
		return result(false, nil, "Live game catalog is temporarily unavailable.")
	end
	gamesBusy = true
	gamesAttemptedAt = os.clock()
	local ok, response =
		pcall(HttpService.RequestAsync, HttpService, { Url = "https://unknownhub.win/api/games", Method = "GET" })
	gamesBusy = false
	if not alive then
		return result(false, nil, "Storage server was unloaded.")
	end
	if not ok or not response.Success or type(response.Body) ~= "string" or #response.Body > 524288 then
		return result(false, nil, "Live game catalog is unavailable.")
	end
	local decoded, payload = pcall(HttpService.JSONDecode, HttpService, response.Body)
	if not decoded or type(payload) ~= "table" or type(payload.games) ~= "table" or #payload.games > 500 then
		return result(false, nil, "Invalid game catalog response.")
	end
	local games = {}
	for _, record in ipairs(payload.games) do
		if type(record) ~= "table" or type(record.name) ~= "string" or #record.name > 120 then
			return result(false, nil, "Invalid game catalog record.")
		end
		local gameId = tonumber(record.gameId)
		if not gameId or gameId <= 0 or gameId % 1 ~= 0 or gameId > 9007199254740991 then
			return result(false, nil, "Invalid catalog game ID.")
		end
		table.insert(games, {
			gameId = gameId,
			name = record.name,
			status = type(record.status) == "string" and record.status:sub(1, 64) or "Unknown",
			thumbnailUrl = type(record.thumbnailUrl) == "string" and record.thumbnailUrl:sub(1, 2048) or "",
		})
	end
	gamesCache, gamesFetchedAt = games, os.clock()
	return result(true, games)
end

local function invoke(player, action, key, payload)
	if not alive then
		return result(false, nil, "Storage server was unloaded.")
	end
	if
		action ~= "Read"
		and action ~= "Write"
		and action ~= "Delete"
		and action ~= "List"
		and action ~= "Verify"
		and action ~= "Games"
	then
		return result(false, nil, "Unknown operation.")
	end
	local state = states[player]
	if not state then
		state = { Busy = false, LastRequest = -math.huge, LastWrite = -math.huge, LastVerify = -math.huge }
		states[player] = state
	end
	local now = os.clock()
	if state.Busy or now - state.LastRequest < 0.1 then
		return result(false, nil, "Storage is busy; try again shortly.")
	end
	state.LastRequest = now
	if action == "Verify" then
		if now - state.LastVerify < 5 then
			return result(false, nil, "Wait before verifying another key.")
		end
		state.LastVerify = now
	elseif action ~= "List" and action ~= "Games" and not validKey(key) then
		return result(false, nil, "Invalid storage key.")
	end
	if action == "Write" and not validatePayload(payload, key) then
		return result(false, nil, "Invalid or oversized configuration.")
	end
	if action == "Write" or action == "Delete" then
		if now - state.LastWrite < 2 then
			return result(false, nil, "Writes are limited to one every two seconds.")
		end
		state.LastWrite = now
	end
	state.Busy = true
	local ok, response = pcall(function()
		if action == "Games" then
			return getGames()
		end
		if action == "Verify" then
			return verify(player, payload)
		end
		if not load(player, state) then
			return result(
				false,
				nil,
				"DataStore unavailable. Publish the experience and enable Studio API access for testing."
			)
		end
		if action == "Read" then
			return result(true, state.Document.Entries[key])
		end
		if action == "List" then
			local names = {}
			for name in pairs(state.Document.Entries) do
				table.insert(names, name)
			end
			table.sort(names)
			return result(true, names)
		end
		local saved = store:UpdateAsync("player_" .. player.UserId, function(current)
			current = current or { Version = 1, Entries = {} }
			if type(current) ~= "table" or current.Version ~= 1 or type(current.Entries) ~= "table" then
				error("Invalid stored document")
			end
			local entries = table.clone(current.Entries)
			entries[key] = if action == "Delete" then nil else payload
			local count, total = 0, 0
			for _, value in pairs(entries) do
				count += 1
				if type(value) ~= "string" then
					error("Invalid stored entry")
				end
				total += #value
			end
			if count > 8 or total > MAX_TOTAL_BYTES then
				error("Player configuration quota exceeded")
			end
			return { Version = 1, Entries = entries }
		end)
		state.Document = saved
		return result(true, "Saved to Roblox DataStore.")
	end)
	state.Busy = false
	if not ok then
		return result(false, nil, "Storage operation failed; no persistent success was reported.")
	end
	return response
end

remote.OnServerInvoke = invoke
local removing = Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
script.Destroying:Once(function()
	alive = false
	gamesCache = nil
	remote.OnServerInvoke = nil
	remote:Destroy()
	removing:Disconnect()
	table.clear(states)
end)
