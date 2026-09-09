local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Storage = {}
Storage.__index = Storage
Storage.MaxBytes = 196608

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

local remoteQueues = setmetatable({}, { __mode = "k" })
local nativeRuntimeState = {}
local nativeDataLocks = {}

local function drainRemote(remote, state)
	while #state.Queue > 0 do
		local ticket = table.remove(state.Queue, 1)
		local writing = ticket.Action == "Write" or ticket.Action == "Delete"
		local verifying = ticket.Action == "Verify"
		local due = math.max(
			state.LastRequest + 0.11,
			writing and state.LastWrite + 2.05 or -math.huge,
			verifying and state.LastVerify + 5.05 or -math.huge
		)
		while ticket.Owner.Alive and os.clock() < due do
			task.wait(math.min(0.05, due - os.clock()))
		end
		if ticket.Owner.Alive then
			local now = os.clock()
			state.LastRequest = now
			if writing then
				state.LastWrite = now
			end
			if verifying then
				state.LastVerify = now
			end
			ticket.Called, ticket.Response =
				pcall(remote.InvokeServer, remote, ticket.Action, ticket.Key, ticket.Payload)
		else
			ticket.Called = false
		end
		ticket.Owner, ticket.Payload = nil, nil
		ticket.Done = true
	end
	state.Running = false
end

function Storage.new(options)
	options = options or {}
	local folder = options.ConfigFolder or "UI_LIB"
	assert(safeName(folder), "ConfigFolder must be a simple folder name")
	return setmetatable({
		Capabilities = {},
		RuntimeState = nativeRuntimeState,
		DataLocks = nativeDataLocks,
		DataNamespace = options.StorageRemote or "UI_LIB_Storage",
		Folder = folder,
		Backend = "Roblox DataStore",
		Persistent = false,
		Executor = false,
		ExecutorRuntime = false,
		Remote = options.StorageRemote,
		Alive = true,
		LastError = nil,
	}, Storage)
end

function Storage:_remote(action, key, payload)
	if not self.Alive then
		return false, "Storage was destroyed."
	end
	local remote = self.Remote or ReplicatedStorage:FindFirstChild("UI_LIB_Storage")
	if typeof(remote) ~= "Instance" or not remote:IsA("RemoteFunction") then
		return false, "Native storage server is not installed."
	end
	local state = remoteQueues[remote]
	if not state then
		state =
			{ Queue = {}, Running = false, LastRequest = -math.huge, LastWrite = -math.huge, LastVerify = -math.huge }
		remoteQueues[remote] = state
	end
	if #state.Queue >= 128 then
		return false, "Too many pending storage operations."
	end
	local ticket = { Owner = self, Action = action, Key = key, Payload = payload, Done = false }
	table.insert(state.Queue, ticket)
	if not state.Running then
		state.Running = true
		task.spawn(drainRemote, remote, state)
	end
	while not ticket.Done do
		if not self.Alive then
			return false, "Storage was destroyed."
		end
		task.wait()
	end
	if not self.Alive then
		return false, "Storage was destroyed."
	end
	local response = ticket.Response
	if not ticket.Called or type(response) ~= "table" then
		return false, "Storage server request failed."
	end
	if response.Ok ~= true then
		return false, type(response.Message) == "string" and response.Message or "Storage request failed."
	end
	return true, response.Value, response.Message
end

function Storage:_result(ok, value)
	self.Persistent = ok == true
	self.LastError = if ok then nil else tostring(value)
	return ok, value
end

function Storage:Read(key)
	if not self.Alive or not safeName(key) then
		return false, "Invalid storage key or destroyed storage."
	end
	local ok, value = self:_remote("Read", key)
	if ok and value ~= nil and (type(value) ~= "string" or #value > Storage.MaxBytes) then
		return self:_result(false, "Storage server returned an invalid config payload.")
	end
	return self:_result(ok, value)
end

function Storage:Write(key, raw)
	if not self.Alive or not safeName(key) or type(raw) ~= "string" or #raw > Storage.MaxBytes then
		return false, "Invalid or oversized storage payload."
	end
	local ok, value = self:_remote("Write", key, raw)
	return self:_result(ok, value)
end

function Storage:Delete(key)
	if not self.Alive or not safeName(key) then
		return false, "Invalid storage key or destroyed storage."
	end
	local ok, value = self:_remote("Delete", key)
	return self:_result(ok, value)
end

function Storage:List()
	local ok, values = self:_remote("List")
	if not ok then
		return false, values
	end
	if type(values) ~= "table" or #values > 4096 then
		return false, "Storage server returned an invalid file list."
	end
	for _, name in ipairs(values) do
		if not safeName(name) then
			return false, "Storage server returned an invalid file name."
		end
	end
	return true, values
end

function Storage:VerifyKey(key, _options)
	if type(key) ~= "string" or #key == 0 or #key > 512 or key:find("%c") then
		return false, "Enter a valid key."
	end
	local ok, value = self:_remote("Verify", nil, key)
	if not ok then
		return false, value
	end
	if type(value) ~= "table" or type(value.Valid) ~= "boolean" then
		return false, "Storage server returned an invalid verification response."
	end
	local message = type(value.Message) == "string" and value.Message
		or (value.Valid and "Key accepted." or "Invalid key.")
	return value.Valid, message, value.Metadata
end

function Storage:GetGames()
	local ok, values = self:_remote("Games")
	if not ok then
		return false, values
	end
	if type(values) ~= "table" or #values > 500 then
		return false, "Storage server returned an invalid game catalog."
	end
	for _, record in ipairs(values) do
		if type(record) ~= "table" or type(record.name) ~= "string" or #record.name > 120 then
			return false, "Storage server returned an invalid game record."
		end
		local gameId = tonumber(record.gameId)
		if not gameId or gameId <= 0 or gameId % 1 ~= 0 or gameId > 9007199254740991 then
			return false, "Storage server returned an invalid game ID."
		end
	end
	return true, values
end

function Storage:RunLoader(_url)
	return false, "Runtime loaders are unavailable in Studio."
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
	return true, nil
end

function Storage:Destroy()
	self.Alive = false
	self.Remote = nil
end

return Storage
