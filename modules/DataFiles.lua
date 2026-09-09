return function(require)
	local HttpService = game:GetService("HttpService")
	local Core = require("Core")
	local DataFiles = {}
	DataFiles.__index = DataFiles
	local locks = setmetatable({}, { __mode = "k" })
	local MAX_BYTES = 196608

	local function validate(name, value)
		assert(name == "key" or name == "autoload", "Unsupported data file")
		assert(
			type(value) == "table"
				or (name == "key" and type(value) == "string")
				or (name == "autoload" and type(value) == "boolean"),
			"Invalid data record"
		)
		local count = 0
		local seen = {}
		local function visit(item, depth)
			count += 1
			assert(count <= 4096 and depth <= 16, "Data record exceeds structure limits")
			local kind = type(item)
			if kind == "string" then
				assert(#item <= 16384, "Data string is too long")
			elseif kind == "number" then
				assert(item == item and math.abs(item) < math.huge, "Invalid data number")
			elseif kind == "table" then
				assert(not seen[item] and getmetatable(item) == nil, "Invalid data table")
				seen[item] = true
				for key, child in pairs(item) do
					assert(
						(type(key) == "string" and #key <= 256)
							or (type(key) == "number" and key > 0 and key % 1 == 0 and key <= 4096),
						"Invalid data key"
					)
					visit(child, depth + 1)
				end
				seen[item] = nil
			else
				assert(kind == "boolean", "Unsupported data value")
			end
		end
		visit(value, 0)
		return value
	end

	local function copy(value)
		if type(value) ~= "table" then
			return value
		end
		local result = {}
		for key, child in pairs(value) do
			result[key] = copy(child)
		end
		return result
	end

	function DataFiles.new(storage, scope, fallbackReader)
		return setmetatable(
			{ Storage = storage, Scope = Core.scope(scope), FallbackReader = fallbackReader, Cache = {} },
			DataFiles
		)
	end

	function DataFiles:_locked(callback)
		if not self.Scope.Alive then
			return false, "Data files were destroyed."
		end
		local registry = self.Storage.DataLocks or locks
		local namespace = self.Storage.DataNamespace or self.Storage
		local lock = registry[namespace]
		if not lock then
			lock = { Queue = {}, Running = false }
			registry[namespace] = lock
		end
		if #lock.Queue >= 128 then
			return false, "Too many pending data file operations."
		end
		local ticket = { Owner = self, Callback = callback, Done = false }
		table.insert(lock.Queue, ticket)
		if not lock.Running then
			lock.Running = true
			task.spawn(function()
				while #lock.Queue > 0 do
					local pending = table.remove(lock.Queue, 1)
					if pending.Owner.Scope.Alive then
						local called, ok, value, note = pcall(pending.Callback)
						if called then
							pending.Ok, pending.Value, pending.Note = ok == true, value, note
						else
							pending.Ok, pending.Value = false, "Data file operation failed."
						end
					else
						pending.Ok, pending.Value = false, "Data files were destroyed."
					end
					pending.Callback, pending.Owner = nil, nil
					pending.Done = true
				end
				lock.Running = false
			end)
		end
		while not ticket.Done do
			if not self.Scope.Alive then
				return false, "Data files were destroyed."
			end
			task.wait()
		end
		if not self.Scope.Alive then
			return false, "Data files were destroyed."
		end
		return ticket.Ok, ticket.Value, ticket.Note
	end

	function DataFiles:_read(name)
		local called, ok, raw = pcall(self.Storage.Read, self.Storage, name)
		if not self.Scope.Alive then
			return false, "Data files were destroyed."
		end
		if not called or not ok then
			return false, called and raw or "Data file read failed."
		end
		local note = "primary"
		local value
		if raw == nil and type(self.FallbackReader) == "function" then
			local readOk, fallback = pcall(self.FallbackReader, name)
			if not self.Scope.Alive then
				return false, "Data files were destroyed."
			end
			if not readOk then
				return false, "Inline data migration failed."
			end
			if fallback ~= nil then
				value, note = fallback, "inline migration"
			end
		end
		if raw == nil and value == nil and type(self.Storage.ReadLegacy) == "function" then
			local readOk, found, legacy = pcall(self.Storage.ReadLegacy, self.Storage, name)
			if not self.Scope.Alive then
				return false, "Data files were destroyed."
			end
			if not readOk or not found then
				return false, readOk and legacy or "Legacy data read failed."
			end
			raw, note = legacy, "legacy migration"
		end
		if raw ~= nil then
			if type(raw) ~= "string" or #raw > MAX_BYTES then
				return false, "Data file exceeds size limits."
			end
			local decoded, result = pcall(HttpService.JSONDecode, HttpService, raw)
			if not decoded then
				return false, "Data file contains invalid JSON; it was not overwritten."
			end
			value = result
		end
		if value ~= nil then
			local valid = pcall(validate, name, value)
			if not valid then
				return false, "Data file contains an invalid record; it was not overwritten."
			end
		end
		self.Cache[name] = { Value = copy(value), Note = value == nil and "missing" or note }
		return true, copy(value), self.Cache[name].Note
	end

	function DataFiles:Read(name, force)
		if name ~= "key" and name ~= "autoload" then
			return false, "Unsupported data file."
		end
		return self:_locked(function()
			local cached = self.Cache[name]
			if cached and not force then
				return true, copy(cached.Value), cached.Note
			end
			return self:_read(name)
		end)
	end

	function DataFiles:Write(name, data)
		local valid = pcall(validate, name, data)
		if not valid then
			return false, "Invalid data file record."
		end
		local snapshot = copy(data)
		local encoded, raw = pcall(HttpService.JSONEncode, HttpService, snapshot)
		if not encoded or #raw > MAX_BYTES then
			return false, "Data file exceeds size limits."
		end
		return self:_locked(function()
			local readOk, problem = self:_read(name)
			if not readOk then
				return false, problem
			end
			if not self.Scope.Alive then
				return false, "Data files were destroyed."
			end
			local called, ok, message = pcall(self.Storage.Write, self.Storage, name, raw)
			if not self.Scope.Alive then
				return false, "Data files were destroyed."
			end
			if not called or not ok then
				return false, called and message or "Data file write failed."
			end
			self.Cache[name] = { Value = snapshot, Note = "primary" }
			return true, message or "Saved data file."
		end)
	end

	function DataFiles:Destroy()
		self.Scope:Destroy()
		table.clear(self.Cache)
	end

	return DataFiles
end
