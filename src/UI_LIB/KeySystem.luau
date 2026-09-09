local Core = require(script.Parent.Core)
local Storage = require(script.Parent.Storage)

local KeySystem = {}
KeySystem.__index = KeySystem

local function text(value)
	return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function KeySystem.new(window, options)
	options = options or {}
	local scope = Core.scope(window.Scope)
	local storage = options.Storage or (window.Config and window.Config.Storage) or Storage.new(options)
	local required = options.RequiredKey or options.Key
	local enabled = options.KeySystem == true
		or options.UnknownHubKey == true
		or options.UnknownHubKeySystem == true
		or required ~= nil
	local self = setmetatable({
		Window = window,
		Scope = scope,
		Options = options,
		Storage = storage,
		Enabled = enabled,
		Verified = not enabled,
		Busy = false,
		Key = nil,
		Metadata = nil,
		Message = enabled and "Enter your key to continue." or "Key system disabled.",
		Listeners = {},
		Generation = 0,
		LastAttempt = -math.huge,
		Link = options.GetKeyLink or options.KeyLink or "https://unknownhub.win/#get-key",
	}, KeySystem)
	scope:Add(function()
		self.Generation += 1
		self.Busy = false
		self.Key = nil
		self.Metadata = nil
		table.clear(self.Listeners)
		if not options.Storage and not (window.Config and window.Config.Storage == storage) then
			storage:Destroy()
		end
	end)
	return self
end

function KeySystem:GetStatus()
	return table.freeze({ Enabled = self.Enabled, Verified = self.Verified, Busy = self.Busy, Message = self.Message })
end

function KeySystem:_notify()
	if not self.Scope.Alive then
		return
	end
	local status = self:GetStatus()
	for callback in pairs(self.Listeners) do
		Core.callback(callback, status)
	end
end

function KeySystem:Subscribe(scope, callback)
	self.Listeners[callback] = true
	local function disconnect()
		self.Listeners[callback] = nil
	end
	(scope or self.Scope):Add(disconnect)
	Core.callback(callback, self:GetStatus())
	return { Disconnect = disconnect }
end

function KeySystem:GetKey()
	return self.Verified and self.Key or nil
end

function KeySystem:GetKeyLink()
	Core.callback(self.Options.OnGetKey, self.Link)
	return self.Link
end

function KeySystem:GetCachedKey()
	if self.Options.CacheKey ~= true and self.Options.SaveKey ~= true then
		return ""
	end
	local config = self.Window.Config
	local record = config and config:ReadData("__unknownhub_key_system")
	if type(record) == "table" then
		return text(record.key)
	end
	return ""
end

function KeySystem:Verify(key)
	if not self.Scope.Alive then
		return false, "Key system was destroyed."
	end
	if not self.Enabled then
		return true, "Key system disabled.", {}
	end
	if self.Busy then
		return false, "Verification is already running."
	end
	key = text(key)
	if #key == 0 or #key > 512 or key:find("%c") then
		return false, "Enter a valid key."
	end
	if os.clock() - self.LastAttempt < 1 then
		return false, "Wait a moment before trying again."
	end
	self.LastAttempt = os.clock()
	self.Busy = true
	self.Message = "Verifying key…"
	self:_notify()
	if not self.Scope.Alive then
		self.Busy = false
		return false, "Verification was cancelled."
	end
	local generation = self.Generation
	local custom = self.Options.Verify
	local function verify()
		if type(custom) == "function" then
			return custom(key, self.Options)
		end
		local executor = self.Storage.ExecutorRuntime or self.Storage.Executor
		local developerKey = text(self.Options.DeveloperKey or self.Options.DevKey)
		if executor and developerKey ~= "" and key == developerKey then
			return true,
				"Developer key accepted.",
				{ Local = true, Developer = true, keyType = "developer", noExpiry = true }
		end
		local required = self.Options.RequiredKey or self.Options.Key
		local unknownHub = self.Options.UnknownHubKey == true or self.Options.UnknownHubKeySystem == true
		if required ~= nil and executor and not unknownHub then
			local valid = if type(required) == "table" then table.find(required, key) ~= nil else text(required) == key
			return valid,
				valid and "Key accepted." or "Invalid key.",
				{ Local = true, keyType = "local", noExpiry = true }
		end
		return self.Storage:VerifyKey(key, self.Options)
	end
	local callOk, accepted, message, metadata = pcall(verify)
	self.Busy = false
	if not self.Scope.Alive or generation ~= self.Generation then
		return false, "Verification was cancelled."
	end
	if not callOk then
		accepted, message = false, "Key verification failed."
	end
	if type(message) == "table" then
		metadata, message = message, message.message
	end
	metadata = type(metadata) == "table" and metadata or {}
	if type(custom) ~= "function" then
		metadata = Storage.NormalizeKeyMetadata(metadata)
	end

	if accepted == true and type(custom) ~= "function" and not metadata.Local then
		local ticket = text(metadata.ticket or metadata.unlockTicket or metadata.keyTicket)
		local ttl =
			tonumber(metadata.ticketSecondsRemaining or metadata.ticket_seconds_remaining or metadata.ticketTtlSeconds)
		if #ticket < 80 or not ticket:match("^[%w_%-]+%.[%w_%-]+$") then
			accepted, message = false, "Key server did not return a signed unlock ticket."
		elseif ttl and ttl <= 0 then
			accepted, message = false, "Key unlock ticket has expired."
		end
	end
	self.Verified = accepted == true
	self.Message = type(message) == "string" and message or (self.Verified and "Key accepted." or "Invalid key.")
	if self.Verified then
		self.Key, self.Metadata = key, metadata
		self.MetadataReceivedAt = os.clock()
		if self.Options.CacheKey == true or self.Options.SaveKey == true then
			local config = self.Window.Config
			if config then
				local saved, cacheMessage =
					config:WriteData("__unknownhub_key_system", { key = key, ticket = metadata.ticket })
				metadata.CacheSaved = saved == true
				metadata.CacheMessage = cacheMessage
			end
		end
		if not self.Scope.Alive then
			return false, "Verification was cancelled."
		end
		Core.callback(self.Options.OnKeyAccepted, key, metadata)
	else
		self.Key, self.Metadata = nil, nil
	end
	self:_notify()
	return self.Verified, self.Message, metadata
end

function KeySystem:Destroy()
	self.Scope:Destroy()
end

return KeySystem
