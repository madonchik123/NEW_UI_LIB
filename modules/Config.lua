return function(require)
	local HttpService = game:GetService("HttpService")
	local Core = require("Core")
	local Storage = require("Storage")

	local ThemeAliases = require("ThemeAliases")
	local Config = {}
	Config.__index = Config
	local VERSION = 1
	local MAX_ITEMS = 2048
	local queuedSources = {}
	local queuedCount = 0

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function numericTag(kind, values)
		for _, value in ipairs(values) do
			assert(finite(value), "Config numbers must be finite")
		end
		return { Tag = kind, Value = values }
	end

	local function encode(value, depth, seen)
		depth = depth or 0
		seen = seen or {}
		assert(depth <= 16, "Config nesting is too deep")
		local kind = typeof(value)
		if value == nil then
			return { Tag = "Nil" }
		end
		if kind == "boolean" then
			return value
		end
		if kind == "string" then
			assert(#value <= 16384, "Config string is too long")
			return value
		end
		if kind == "number" then
			assert(finite(value), "Config numbers must be finite")
			return value
		end
		if kind == "Color3" then
			return numericTag(kind, { value.R, value.G, value.B })
		end
		if kind == "EnumItem" then
			return { Tag = kind, Enum = tostring(value.EnumType), Value = value.Name }
		end
		if kind == "UDim" then
			return numericTag(kind, { value.Scale, value.Offset })
		end
		if kind == "UDim2" then
			return numericTag(kind, { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset })
		end
		if kind == "Vector2" then
			return numericTag(kind, { value.X, value.Y })
		end
		if kind == "Vector3" then
			return numericTag(kind, { value.X, value.Y, value.Z })
		end
		assert(kind == "table" and not seen[value], "Unsupported or cyclic config value")
		seen[value] = true
		local entries = {}
		for key, child in pairs(value) do
			assert(
				(type(key) == "string" and #key <= 256) or (finite(key) and key % 1 == 0),
				"Unsupported config table key"
			)
			assert(#entries < MAX_ITEMS, "Too many config entries")
			table.insert(entries, { Key = key, Value = encode(child, depth + 1, seen) })
		end
		seen[value] = nil
		return { Tag = "Table", Value = entries }
	end

	local function decode(value, depth)
		depth = depth or 0
		assert(depth <= 16, "Config nesting is too deep")
		if type(value) ~= "table" then
			assert(
				type(value) == "boolean" or (type(value) == "string" and #value <= 16384) or finite(value),
				"Invalid config value"
			)
			return value
		end
		local tag, values = value.Tag, value.Value
		if tag == "Nil" then
			return nil
		end
		if tag == "EnumItem" then
			assert(type(value.Enum) == "string" and type(values) == "string", "Invalid enum")
			local name = value.Enum:gsub("^Enum%.", "")
			return Enum[name][values]
		end
		assert(type(values) == "table" and #values <= MAX_ITEMS, "Invalid tagged value")
		if tag == "Table" then
			local result = {}
			for _, entry in ipairs(values) do
				assert(type(entry) == "table", "Invalid table entry")
				local key = entry.Key
				assert((type(key) == "string" and #key <= 256) or (finite(key) and key % 1 == 0), "Invalid table key")
				assert(result[key] == nil, "Duplicate table key")
				result[key] = decode(entry.Value, depth + 1)
			end
			return result
		end
		for _, number in ipairs(values) do
			assert(finite(number), "Invalid numeric tag")
		end
		if tag == "Color3" and #values == 3 then
			return Color3.new(math.clamp(values[1], 0, 1), math.clamp(values[2], 0, 1), math.clamp(values[3], 0, 1))
		end
		if tag == "UDim" and #values == 2 then
			return UDim.new(values[1], values[2])
		end
		if tag == "UDim2" and #values == 4 then
			return UDim2.new(values[1], values[2], values[3], values[4])
		end
		if tag == "Vector2" and #values == 2 then
			return Vector2.new(values[1], values[2])
		end
		if tag == "Vector3" and #values == 3 then
			return Vector3.new(values[1], values[2], values[3])
		end
		error("Unknown config value tag")
	end

	local function profileName(name)
		if type(name) ~= "string" then
			return nil
		end
		name = name:match("^%s*(.-)%s*$")
		if #name == 0 or #name > 64 or name:find("[%c/\\]") then
			return nil
		end
		return name
	end

	local function automaticName()
		if game.GameId > 0 then
			return "game_" .. game.GameId
		end
		if game.PlaceId > 0 then
			return "place_" .. game.PlaceId
		end
		return "universal"
	end

	local function validateEntries(entries)
		assert(type(entries) == "table", "Invalid config entries")
		local count = 0
		for id, entry in pairs(entries) do
			count += 1
			assert(
				count <= MAX_ITEMS
					and type(id) == "string"
					and #id <= 256
					and type(entry) == "table"
					and type(entry.Type) == "string"
					and #entry.Type <= 64,
				"Invalid config entry"
			)
			decode(entry.Value)
		end
	end

	local function validateDocument(document)
		assert(type(document) == "table" and document.Version == VERSION, "Unsupported configuration version")
		assert(
			type(document.Preferences) == "table"
				and type(document.Profiles) == "table"
				and type(document.ThemeProfiles) == "table"
				and type(document.Data) == "table",
			"Invalid configuration"
		)
		local prefs = document.Preferences
		assert(prefs.AutoSave == nil or type(prefs.AutoSave) == "boolean", "Invalid autosave preference")
		assert(prefs.AutoLoad == nil or type(prefs.AutoLoad) == "boolean", "Invalid autoload preference")
		assert(prefs.ActiveProfile == nil or profileName(prefs.ActiveProfile), "Invalid active profile")
		validateEntries(prefs.Values or {})
		for _, group in ipairs({ document.Profiles, document.ThemeProfiles }) do
			local count = 0
			for name, value in pairs(group) do
				count += 1
				assert(count <= 64 and profileName(name), "Invalid profile name or count")
				if group == document.Profiles then
					validateEntries(value)
				else
					assert(type(decode(value)) == "table", "Invalid theme profile")
				end
			end
		end
		local count = 0
		for tag, value in pairs(document.Data) do
			count += 1
			assert(count <= 128 and type(tag) == "string" and #tag <= 128, "Invalid data tag")
			decode(value)
		end
		return document
	end

	local function cancel(thread)
		if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end

	function Config.new(window, options)
		options = options or {}
		local scope = Core.scope(window.Scope)
		local storage = options.Storage or Storage.new(options)
		local namespace = tostring(options.ConfigName or automaticName()):gsub("[^%w_%-]", "_"):sub(1, 64)
		local self = setmetatable({
			Window = window,
			Scope = scope,
			Storage = storage,
			StorageKey = "config_" .. namespace,
			Items = {},
			Order = {},
			Listeners = {},
			ThemeBindings = {},
			ThemeCallbacks = {},
			AutoSave = options.AutoSave ~= false,
			AutoLoad = options.AutoLoad ~= false,
			ActiveProfile = "Default",
			Dirty = false,
			Replaying = false,
			Initialized = false,
			Busy = false,
			Revision = 0,
			Generation = 0,
			Pending = nil,
			Loaded = nil,
			Message = "Configuration has not been loaded.",
			Status = "idle",
			Delay = math.clamp(tonumber(options.AutoSaveDelay) or 2, 0.25, 30),
			DefaultTheme = table.clone(window.Theme),
			Options = options,
			Document = {
				Version = VERSION,
				Preferences = { Values = {} },
				Profiles = {},
				ThemeProfiles = {},
				Data = {},
			},
		}, Config)
		scope:Add(function()
			cancel(self.Pending)
			self.Pending = nil
			table.clear(self.Listeners)
			table.clear(self.Items)
			table.clear(self.Order)
			table.clear(self.ThemeBindings)
			table.clear(self.ThemeCallbacks)
			if not options.Storage then
				storage:Destroy()
			end
		end)
		return self
	end

	function Config:GetStatus()
		return table.freeze({
			State = self.Status,
			Message = self.Message,
			Backend = self.Storage.Backend or "Custom storage",
			Persistent = self.Storage.Persistent == true,
			Dirty = self.Dirty,
			Busy = self.Busy,
			AutoSave = self.AutoSave,
			AutoLoad = self.AutoLoad,
			ActiveProfile = self.ActiveProfile,
		})
	end

	function Config:_status(state, message)
		if not self.Scope.Alive then
			return
		end
		self.Status, self.Message = state, tostring(message)
		local snapshot = self:GetStatus()
		for callback in pairs(self.Listeners) do
			Core.callback(callback, snapshot)
		end
	end

	function Config:Subscribe(scope, callback)
		assert(type(callback) == "function", "Subscribe requires a callback")
		self.Listeners[callback] = true
		local function disconnect()
			self.Listeners[callback] = nil
		end
		(scope or self.Scope):Add(disconnect)
		Core.callback(callback, self:GetStatus())
		return { Disconnect = disconnect }
	end

	function Config:_apply(id, item)
		local source = item.Options.Preference and self.Document.Preferences.Values or self.Loaded
		local entry = source and source[id]
		if not entry then
			for _, alias in ipairs(item.Options.Aliases or {}) do
				entry = source and source[alias]
				if entry then
					break
				end
			end
		end
		if not entry or item.Applied == self.Generation or (item.Scope and not item.Scope.Alive) then
			return true
		end
		if type(entry) ~= "table" or entry.Type ~= item.Kind then
			return false, "Config type mismatch: " .. id
		end
		local decoded, value = pcall(decode, entry.Value)
		if not decoded then
			return false, "Invalid config value: " .. id
		end
		item.Applied = self.Generation
		local wasReplaying = self.Replaying
		self.Replaying = true
		local ok = pcall(item.Setter, value, false)
		self.Replaying = wasReplaying
		if not ok then
			return false, "Config callback failed: " .. id
		end
		return true
	end

	function Config:Register(id, kind, getter, setter, scope, options)
		if
			type(id) ~= "string"
			or #id == 0
			or #id > 256
			or type(getter) ~= "function"
			or type(setter) ~= "function"
		then
			return false, "Invalid config registration."
		end
		if type(kind) ~= "string" or #kind == 0 or #kind > 64 then
			return false, "Invalid config type."
		end
		if self.Items[id] then
			return false, "Duplicate ConfigKey: " .. id
		end
		if #self.Order >= MAX_ITEMS then
			return false, "Too many registered controls."
		end
		local item =
			{ Kind = kind, Getter = getter, Setter = setter, Scope = scope, Options = options or {}, Applied = -1 }
		self.Items[id] = item
		table.insert(self.Order, id)
		if scope then
			scope:Add(function()
				if self.Items[id] == item then
					self:UnregisterConfig(id)
				end
			end)
		end
		if self.Initialized then
			return self:_apply(id, item)
		end
		return true
	end

	function Config:RegisterConfig(id, kind, getter, setter, options)
		return self:Register(id, kind, getter, function(value)
			setter(value, { fireCallbacks = true, fromConfig = true })
		end, nil, options)
	end

	function Config:UnregisterConfig(id)
		self.Items[id] = nil
		local index = table.find(self.Order, id)
		if index then
			table.remove(self.Order, index)
		end
		return index ~= nil
	end

	function Config:_snapshot()
		local result = self.Loaded and table.clone(self.Loaded) or {}
		for _, id in ipairs(self.Order) do
			local item = self.Items[id]
			if item and (not item.Scope or item.Scope.Alive) then
				local ok, value = pcall(item.Getter)
				if not ok then
					return nil, "Unable to read config value: " .. id
				end
				local encoded, packed = pcall(encode, value)
				if not encoded then
					return nil, "Unable to serialize config value: " .. id
				end
				if item.Options.Preference then
					self.Document.Preferences.Values[id] = { Type = item.Kind, Value = packed }
					result[id] = nil
				else
					result[id] = { Type = item.Kind, Value = packed }
				end
			end
		end
		return result
	end

	function Config:_savingSuspended()
		local library = self.Window.Library
		return self.Window.Legacy
			and library
			and library._defaultSaveConfig
			and library.SaveConfig ~= library._defaultSaveConfig
	end

	function Config:_commit(capturedControls)
		if self:_savingSuspended() then
			return false, "Saving is temporarily suspended."
		end
		if not self.Scope.Alive then
			return false, "Config was destroyed."
		end
		if self.Busy then
			return false, "A config operation is already running."
		end
		if not self.Initialized or self.ReadFailed then
			return false, "Load storage successfully before saving; call Initialize() to retry."
		end
		self.Document.Preferences.AutoSave = self.AutoSave
		self.Document.Preferences.AutoLoad = self.AutoLoad
		self.Document.Preferences.ActiveProfile = self.ActiveProfile
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, self.Document)
		if not ok or #raw > Storage.MaxBytes then
			self:_status("error", "Configuration is invalid or exceeds the storage limit.")
			return false, self.Message
		end
		local revision = self.Revision
		self.Busy = true
		self:_status("saving", "Saving configuration…")
		if not self.Scope.Alive then
			self.Busy = false
			return false, "Config was destroyed."
		end
		local callOk, saved, message = pcall(self.Storage.Write, self.Storage, self.StorageKey, raw)
		self.Busy = false
		if not self.Scope.Alive then
			return false, "Config was destroyed."
		end
		if not callOk or not saved then
			self:_status("error", callOk and message or "Storage write failed.")
			return false, self.Message
		end
		if capturedControls and self.Revision == revision then
			self.Dirty = false
		end
		self:_status("saved", type(message) == "string" and message or "Configuration saved.")
		if self.Dirty and self.AutoSave then
			self:_schedule()
		end
		return true, self.Message
	end

	function Config:_schedule()
		cancel(self.Pending)
		self.Pending = task.delay(self.Delay, function()
			self.Pending = nil
			if self.Scope.Alive and self.Dirty and self.AutoSave then
				if self.Busy then
					self:_schedule()
				else
					self:Save()
				end
			end
		end)
	end

	function Config:Changed()
		if not self.Scope.Alive or self.Replaying then
			return
		end
		if self:_savingSuspended() then
			cancel(self.Pending)
			self.Pending = nil
			return
		end
		self.Revision += 1
		self.Dirty = true
		if self.Initialized and self.AutoSave then
			self:_schedule()
		end
		self:_status("dirty", "Unsaved changes.")
	end

	function Config:Save(name)
		if self:_savingSuspended() then
			return false, "Saving is temporarily suspended."
		end
		if self.Busy then
			return false, "A config operation is already running."
		end
		if not self.Initialized then
			return false, "Initialize configuration before saving."
		end
		name = profileName(name or self.ActiveProfile)
		if not name then
			return false, "Enter a valid profile name."
		end
		local snapshot, message = self:_snapshot()
		if not snapshot then
			self:_status("error", message)
			return false, message
		end
		self.Document.Profiles[name] = snapshot
		return self:_commit(true)
	end

	function Config:Load(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		name = profileName(name or self.ActiveProfile)
		local snapshot = name and self.Document.Profiles[name]
		if type(snapshot) ~= "table" then
			return false, "Profile not found."
		end
		cancel(self.Pending)
		self.Pending = nil
		self.ActiveProfile = name
		self.Generation += 1
		self.Loaded = snapshot
		local failures = {}
		for _, id in ipairs(table.clone(self.Order)) do
			local item = self.Items[id]
			if item then
				local ok, message = self:_apply(id, item)
				if not ok then
					table.insert(failures, message)
				end
			end
			if not self.Scope.Alive then
				return false, "Config was destroyed during replay."
			end
		end
		self.Dirty = false
		if #failures > 0 then
			self:_status("error", table.concat(failures, "; "))
			return false, self.Message
		end
		self:_status("loaded", "Loaded profile: " .. name)
		return true, self.Message
	end

	function Config:Initialize()
		if self.Initialized and not self.ReadFailed then
			return true, self.Message
		end
		if self.Busy then
			return false, "A config operation is already running."
		end
		self.Busy = true
		local callOk, ok, raw = pcall(self.Storage.Read, self.Storage, self.StorageKey)
		self.Busy = false
		if not self.Scope.Alive then
			return false, "Config was destroyed."
		end
		if not callOk or not ok then
			self.Initialized = true
			self.ReadFailed = true
			self:_status("error", callOk and raw or "Storage read failed.")
			return false, self.Message
		end
		if raw ~= nil then
			local decoded, document = pcall(HttpService.JSONDecode, HttpService, raw)
			local valid = decoded and pcall(validateDocument, document)
			if not valid then
				self.Initialized = true
				self.ReadFailed = true
				self:_status("error", "Unsupported or invalid configuration version.")
				return false, self.Message
			end
			self.Document = document
			self.Document.Preferences.Values = document.Preferences.Values or {}
			local prefs = document.Preferences
			if type(prefs.AutoSave) == "boolean" then
				self.AutoSave = prefs.AutoSave
			end
			if type(prefs.AutoLoad) == "boolean" then
				self.AutoLoad = prefs.AutoLoad
			end
			self.ActiveProfile = profileName(prefs.ActiveProfile) or "Default"
		end
		self.Initialized = true
		self.ReadFailed = false
		if self.AutoLoad and self.Document.Profiles[self.ActiveProfile] then
			return self:Load()
		end
		self.Generation += 1
		for _, id in ipairs(table.clone(self.Order)) do
			local item = self.Items[id]
			if item and item.Options.Preference then
				self:_apply(id, item)
			end
		end
		self:_status("ready", self.AutoLoad and "No saved profile yet." or "Automatic loading is disabled.")
		return true, self.Message
	end

	function Config:Create(name)
		name = profileName(name)
		if not name then
			return false, "Enter a valid profile name."
		end
		if self.Document.Profiles[name] then
			return false, "Profile already exists."
		end
		return self:Save(name)
	end

	function Config:List(includeWorkingProfile)
		local names = {}
		for name in pairs(self.Document.Profiles) do
			table.insert(names, name)
		end
		if includeWorkingProfile ~= false and not table.find(names, self.ActiveProfile) then
			table.insert(names, self.ActiveProfile)
		end
		table.sort(names)
		return names
	end

	function Config:Rename(oldName, newName)
		if self.Busy then
			return false, "A config operation is already running."
		end
		newName = profileName(newName)
		if not newName or not self.Document.Profiles[oldName] then
			return false, "Invalid profile name."
		end
		if self.Document.Profiles[newName] then
			return false, "Profile already exists."
		end
		self.Document.Profiles[newName] = self.Document.Profiles[oldName]
		self.Document.Profiles[oldName] = nil
		if self.ActiveProfile == oldName then
			self.ActiveProfile = newName
		end
		return self:_commit()
	end

	function Config:Delete(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		if not self.Document.Profiles[name] then
			return false, "Profile not found."
		end
		self.Document.Profiles[name] = nil
		if self.ActiveProfile == name then
			self.ActiveProfile = "Default"
			self.Loaded = nil
		end
		return self:_commit()
	end

	function Config:Switch(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		if self.Dirty and self.AutoSave then
			local snapshot, message = self:_snapshot()
			if not snapshot then
				return false, message
			end
			self.Document.Profiles[self.ActiveProfile] = snapshot
		end
		local ok, message = self:Load(name)
		if not ok then
			return false, message
		end
		return self:_commit()
	end

	function Config:SetAutoSave(enabled)
		if self.Busy then
			return false, "A config operation is already running."
		end
		self.AutoSave = enabled == true
		if not self.AutoSave then
			cancel(self.Pending)
			self.Pending = nil
		end
		return self:_commit()
	end

	function Config:SetAutoLoad(enabled)
		if self.Busy then
			return false, "A config operation is already running."
		end
		self.AutoLoad = enabled == true
		return self:_commit()
	end

	function Config:Flush()
		cancel(self.Pending)
		self.Pending = nil
		if self.Dirty and self.AutoSave then
			return self:Save()
		end
		return true, "No pending automatic save."
	end

	function Config:ReadData(tag)
		local value = self.Document.Data[tag]
		if value == nil then
			return nil
		end
		local ok, decoded = pcall(decode, value)
		return if ok then decoded else nil
	end

	function Config:WriteData(tag, value)
		if self.Busy then
			return false, "A config operation is already running."
		end
		if type(tag) ~= "string" or #tag > 128 then
			return false, "Invalid data tag."
		end
		local ok, packed = pcall(encode, value)
		if not ok then
			return false, "Invalid data value."
		end
		self.Document.Data[tag] = packed
		return self:_commit()
	end

	function Config:SaveThemePreset(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		name = profileName(name)
		if not name then
			return false, "Enter a valid theme profile name."
		end
		local ok, packed = pcall(encode, self.Window.Theme)
		if not ok then
			return false, "Invalid theme."
		end
		self.Document.ThemeProfiles[name] = packed
		return self:_commit()
	end

	function Config:LoadThemePreset(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		local packed = self.Document.ThemeProfiles[name]
		if not packed then
			return false, "Theme profile not found."
		end
		local ok, theme = pcall(decode, packed)
		if not ok or type(theme) ~= "table" then
			return false, "Invalid theme profile."
		end
		local patch = {}
		for key, value in pairs(theme) do
			if typeof(value) == typeof(self.Window.Theme[key]) then
				patch[key] = value
			end
		end
		self.Window:SetTheme(patch)
		self:Changed()
		return true, "Theme profile loaded."
	end

	function Config:ListThemePresets()
		local result = {}
		for name in pairs(self.Document.ThemeProfiles) do
			table.insert(result, name)
		end
		table.sort(result)
		return result
	end

	function Config:DeleteThemePreset(name)
		if self.Busy then
			return false, "A config operation is already running."
		end
		if not self.Document.ThemeProfiles[name] then
			return false, "Theme profile not found."
		end
		self.Document.ThemeProfiles[name] = nil
		return self:_commit()
	end

	function Config:RenameThemePreset(oldName, newName)
		if self.Busy then
			return false, "A config operation is already running."
		end
		newName = profileName(newName)
		if not newName or not self.Document.ThemeProfiles[oldName] or self.Document.ThemeProfiles[newName] then
			return false, "Invalid theme profile name."
		end
		self.Document.ThemeProfiles[newName] = self.Document.ThemeProfiles[oldName]
		self.Document.ThemeProfiles[oldName] = nil
		return self:_commit()
	end

	function Config:SaveTheme()
		return self:WriteData("theme", self.Window.Theme)
	end
	function Config:LoadTheme()
		local theme = self:ReadData("theme")
		if type(theme) ~= "table" then
			return false, "No saved theme."
		end
		local patch = {}
		for key, value in pairs(theme) do
			if typeof(value) == typeof(self.Window.Theme[key]) then
				patch[key] = value
			end
		end
		self.Window:SetTheme(patch)
		return true
	end
	function Config:ResetThemeDefaults(persist)
		self.Window:SetTheme(table.clone(self.DefaultTheme))
		if persist ~= false then
			return self:SaveTheme()
		end
		return true
	end
	function Config:SetThemeValue(token, value, persist)
		self.Window:SetTheme({ [token] = value })
		if persist ~= false then
			return self:SaveTheme()
		end
		return true
	end
	function Config:GetThemeValue(token)
		return self.Window.Theme[ThemeAliases.token(token)]
	end

	function Config:RegisterThemeBinding(instance, property, token, transform)
		token = ThemeAliases.token(token)
		local record = { Instance = instance, Property = property, Token = token, Transform = transform }
		self.ThemeBindings[record] = true
		local connection
		connection = instance.Destroying:Once(function()
			self.ThemeBindings[record] = nil
			self.Scope.Resources[connection] = nil
		end)
		self.Scope:Add(connection)
		return record
	end
	function Config:RegisterThemeCallback(callback, owner)
		local record = { Callback = callback, Owner = owner }
		self.ThemeCallbacks[record] = true
		if type(owner) == "table" and owner.Scope then
			owner.Scope:Add(function()
				self.ThemeCallbacks[record] = nil
			end)
		end
		return {
			Disconnect = function()
				self.ThemeCallbacks[record] = nil
			end,
		}
	end
	function Config:ApplyTheme()
		if self.ApplyingTheme then
			return
		end
		self.ApplyingTheme = true
		for record in pairs(self.ThemeBindings) do
			local value = self.Window.Theme[record.Token]
			if record.Transform then
				local ok, transformed = pcall(record.Transform, value, self.Window.Theme)
				if ok then
					value = transformed
				end
			end
			pcall(function()
				record.Instance[record.Property] = value
			end)
		end
		for record in pairs(self.ThemeCallbacks) do
			local owner = record.Owner
			if
				(typeof(owner) == "Instance" and owner.Parent == nil)
				or (type(owner) == "table" and (owner._destroyed or (owner.Scope and not owner.Scope.Alive)))
			then
				self.ThemeCallbacks[record] = nil
			else
				Core.callback(record.Callback, self.Window.Theme)
			end
		end
		self.ApplyingTheme = false
	end

	function Config:ConfigureAutoLoad(options)
		options = options or {}
		local data = self:ReadData("__uilib.autoload") or {}
		for key, value in pairs(options) do
			data[key] = value
		end
		local requested = options.enabled
		if requested == nil then
			requested = options.Enabled
		end
		if requested == nil then
			requested = options.AutoLoad
		end
		if requested ~= nil then
			data.enabled = requested == true
		end
		data.loaderUrl = data.loaderUrl
			or data.LoaderUrl
			or data.AutoLoadUrl
			or self.Options.AutoLoadUrl
			or self.Options.LoaderUrl
			or ""
		data.gameIds = data.gameIds or data.GameIds or { tostring(game.GameId) }
		data.placeIds = data.placeIds or data.PlaceIds or {}
		if data.enabled ~= nil then
			self.AutoLoad = data.enabled == true
		end
		data.enabled = self.AutoLoad
		self.AutoLoadData = data
		local ok, message = self:WriteData("__uilib.autoload", data)
		if self.AutoLoad and ((type(data.loaderUrl) == "string" and #data.loaderUrl > 0) or data.Source) then
			local queued, queueMessage = self:QueueAutoLoad(data)
			data.QueueStatus = queueMessage
			data.Queued = queued
		end
		return data, ok, message
	end
	function Config:SetAutoLoadEnabled(enabled, options)
		options = table.clone(options or {})
		options.enabled = enabled == true
		return self:ConfigureAutoLoad(options)
	end
	function Config:QueueAutoLoad(data)
		data = data or self.AutoLoadData or {}
		if not self.AutoLoad or data.enabled == false then
			return false, "Automatic loading is disabled."
		end
		local queue = self.Storage.Capabilities and self.Storage.Capabilities.queue_on_teleport
		if type(queue) ~= "function" then
			return false, "queue_on_teleport is unavailable in this runtime."
		end
		local source = data.Source
		if type(source) ~= "string" or #source == 0 then
			local url = data.loaderUrl or data.LoaderUrl
			if type(url) ~= "string" or not url:match("^https://[^%s]+$") then
				return false, "Configure an HTTPS loader URL."
			end
			local payload = HttpService:JSONEncode({
				Url = url,
				GameIds = data.gameIds or {},
				PlaceIds = data.placeIds or {},
				Path = self:GetConfigFolder() .. "/" .. self.StorageKey .. ".json",
			})

			source = string.format(
				[=[do
local data = game:GetService("HttpService"):JSONDecode(%q)
if type(readfile) == "function" then
 local ok, raw = pcall(readfile, data.Path)
 if ok then
  local parsed, config = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
  if parsed and type(config) == "table" and type(config.Preferences) == "table" and config.Preferences.AutoLoad == false then return end
 end
end
local function matches(ids, target)
 for _, id in ipairs(ids) do if tostring(id) == tostring(target) then return true end end
 return false
end
if #data.GameIds > 0 and not matches(data.GameIds, game.GameId) then return end
if #data.GameIds == 0 and #data.PlaceIds > 0 and not matches(data.PlaceIds, game.PlaceId) then return end
if type(request) ~= "function" or type(loadstring) ~= "function" then return end
local ok, response = pcall(request, {Url = data.Url, Method = "GET"})
if not ok or type(response) ~= "table" or type(response.StatusCode) ~= "number" or response.StatusCode < 200 or response.StatusCode >= 300 then return end
local chunk = loadstring(response.Body)
if chunk then chunk() end
end]=],
				payload
			)
		end
		if self.QueuedSource == source then
			return true, "Already queued."
		end
		if #source > 262144 then
			return false, "Teleport source exceeds the size limit."
		end
		if queuedSources[source] then
			return true, "Already queued in this runtime."
		end
		if queuedCount >= 16 then
			return false, "Teleport loader queue limit reached."
		end
		local ok = pcall(queue, source)
		if ok then
			self.QueuedSource = source
			queuedSources[source] = true
			queuedCount += 1
		end
		return ok, ok and "Queued for teleport." or "Unable to queue for teleport."
	end
	function Config:RunAutoLoad(data)
		if not self.AutoLoad then
			return false, "Automatic loading is disabled."
		end
		data = data or self.AutoLoadData or self:ReadData("__uilib.autoload") or {}
		if data.enabled == false then
			return false, "Automatic loading is disabled."
		end
		local function matches(ids, target)
			for _, id in ipairs(ids or {}) do
				if tostring(id) == tostring(target) then
					return true
				end
			end
			return false
		end
		local gameIds, placeIds = data.gameIds or {}, data.placeIds or {}
		if
			(#gameIds > 0 and not matches(gameIds, game.GameId))
			or (#gameIds == 0 and #placeIds > 0 and not matches(placeIds, game.PlaceId))
		then
			return false, "Game does not match the configured loader."
		end
		local loader = self.Options.AutoLoadCallback
		if self.LoaderRan then
			return false, "Loader already ran for this window."
		end
		self.LoaderRan = true
		local ok, message
		if type(loader) == "function" then
			ok, message = pcall(loader, data)
		else
			ok, message = self.Storage:RunLoader(data.loaderUrl or data.LoaderUrl)
		end
		if not ok then
			self.LoaderRan = false
		end
		if ok then
			self:QueueAutoLoad(data)
		end
		return ok, message
	end

	function Config:GetConfigFolder()
		return self.Storage.Folder or "UI_LIB"
	end
	function Config:GetAutomaticConfigName()
		return automaticName()
	end
	function Config:GetAutoSave()
		return self.AutoSave
	end
	function Config:GetAutoLoad()
		return self.AutoLoad
	end
	function Config:Destroy()
		self.Scope:Destroy()
	end

	Config.SaveConfig = Config.Save
	Config.LoadConfig = Config.Load
	Config.SaveConfigPreset = Config.Save
	Config.LoadConfigPreset = Config.Load
	function Config:ListConfigPresets()
		return self:List(false)
	end
	Config.DeleteConfigPreset = Config.Delete
	Config.RenameConfigPreset = Config.Rename
	Config.Encode = encode
	Config.Decode = decode

	return Config
end
