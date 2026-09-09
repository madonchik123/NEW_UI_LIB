return function(require)
	local Core = require("Core")
	local Theme = require("Theme")
	local Fonts = require("Fonts")
	local Window = require("Window")
	local Icons = require("Icons")
	local Config = require("Config")
	local KeySystem = require("KeySystem")
	local KeyGate = require("KeyGate")
	local Personal = require("Personal")
	local Notifications = require("Notifications")
	local Compatibility = require("Compatibility")
	local Containers = require("Containers")
	local Overview = require("Overview")
	local ThemeAliases = require("ThemeAliases")
	local LegacyHost = require("LegacyHost")
	local AutoLoad = require("AutoLoad")
	local Storage = require("Storage")

	local Library = {
		Theme = table.clone(Theme),
		Icons = Icons,
		Version = "2.0.0",
		Config = { WindowWidth = 720, WindowHeight = 466, AutoSave = true, AutoLoad = true },
	}
	Library.Colors = Library.Theme
	local windows = {}
	local generations = {}

	function Library.new(options)
		options = options or {}
		local name = options.Name or "Unknown Hub"
		local generation = (generations[name] or 0) + 1
		generations[name] = generation
		local scope = Core.scope()
		local success, result = xpcall(function()
			local theme = table.clone(Library.Theme)
			for token, value in pairs(Library.Config) do
				if token == "Font" or token == "FontBold" then
					local font = Fonts.resolve(value)
					if font then
						theme[token] = font
					end
				elseif theme[token] ~= nil and typeof(theme[token]) == typeof(value) then
					theme[token] = value
				end
			end
			local bold = Fonts.resolve(Library.Config.FontBold)
				or Fonts.resolve(Library.Config.FontSemiBold)
				or Fonts.resolve(Library.Config.FontMedium)
			if bold then
				theme.FontBold = bold
			elseif Fonts.resolve(Library.Config.Font) then
				theme.FontBold = Fonts.bold(theme.Font)
			end
			local window = Window.new(options, theme, scope)
			window.Library = Library
			window.Config = Config.new(window, options)
			window.KeySystem = KeySystem.new(window, options)
			window.Version = Library.Version
			window.KeyVerified = window.KeySystem.Verified
			window.KeySystem:Subscribe(scope, function(state)
				window.KeyVerified = state.Verified
			end)
			window.Config:Register("__window", "interface", function()
				return {
					Theme = window.Theme,
					Scale = window.UserScale,
					Size = window.DesiredSize,
					ToggleKey = window.ToggleKey,
				}
			end, function(value)
				if type(value) ~= "table" then
					return
				end
				if type(value.Theme) == "table" then
					window:SetTheme(value.Theme)
				end
				if type(value.Scale) == "number" then
					window:SetScale(value.Scale)
				end
				if typeof(value.Size) == "Vector2" then
					window:Resize(value.Size.X, value.Size.Y)
				end
				if typeof(value.ToggleKey) == "EnumItem" then
					window:SetToggleKey(value.ToggleKey)
				end
			end, scope, { Preference = true })
			window.Overview = Overview.mount(window, options)
			if options.Personal ~= false then
				Personal.mount(window)
			end
			KeyGate.mount(window, options)
			if options._Legacy then
				LegacyHost.mount(window)
			end
			return window
		end, debug.traceback)
		if not success then
			scope:Destroy()
			error(result, 2)
		end
		if generations[name] ~= generation then
			result:Destroy()
			local current = windows[name]
			return assert(current and current.Scope.Alive and current, "Window initialization was superseded")
		end
		local previous = windows[name]
		if previous then
			previous:Destroy()
		end
		if generations[name] ~= generation then
			result:Destroy()
			local current = windows[name]
			return assert(current and current.Scope.Alive and current, "Window initialization was superseded")
		end
		if options.AutoInitialize ~= false then
			Core.delay(scope, 0, function()
				result.Config:Initialize()
				if scope.Alive then
					result.KeySystem:Initialize()
				end
			end)
		end
		windows[name] = result
		Library._activeWindow = result
		scope:Add(function()
			if windows[name] == result then
				windows[name] = nil
			end
			if Library._activeWindow == result then
				Library._activeWindow = nil
			end
		end)
		return result
	end

	function Library:GetWindow(name)
		return windows[name or "Unknown Hub"]
	end

	function Library:CreateApp(options)
		return require("UI_LIB_App").mount(options)
	end

	function Library:SetTheme(patch)
		patch = ThemeAliases.patch(patch)
		if patch.Font ~= nil then
			patch.Font = assert(Fonts.resolve(patch.Font), "Invalid theme font")
			if patch.FontBold == nil then
				patch.FontBold = Fonts.bold(patch.Font)
			end
		end
		if patch.FontBold ~= nil then
			patch.FontBold = assert(Fonts.resolve(patch.FontBold), "Invalid heading font")
		end
		for key, value in pairs(patch) do
			self.Theme[key] = value
		end
		for _, window in pairs(windows) do
			window:SetTheme(patch)
		end
	end

	function Library:Destroy()
		local snapshot = table.clone(windows)
		for _, window in pairs(snapshot) do
			window:Destroy()
		end
	end

	function Window:Notify(options, text, duration)
		return Notifications.show(self, options, text, duration)
	end

	function Library:Notify(options, text, duration)
		local window = self._activeWindow
		if window and window.Scope.Alive then
			return window:Notify(options, text, duration)
		end
	end

	function Window:AwaitKey()
		if not self.KeySystem.Enabled or self.KeySystem.Verified then
			return true
		end
		local event = Instance.new("BindableEvent")
		local waiting = Core.scope(self.Scope)
		local resolved = false
		self.KeySystem:Subscribe(waiting, function(state)
			if state.Verified then
				resolved = true
				event:Fire()
			end
		end)
		waiting:Add(function()
			event:Fire()
		end)
		if not resolved then
			event.Event:Wait()
		end
		waiting:Destroy()
		event:Destroy()
		return resolved
	end

	function Window:VerifyKey(key)
		return self.KeySystem:Verify(key)
	end
	function Window:GetKey()
		return self.KeySystem:GetKey()
	end
	function Window:IsKeyVerified()
		return self.KeySystem.Verified
	end

	for _, name in ipairs({
		"ReadData",
		"WriteData",
		"RegisterConfig",
		"UnregisterConfig",
		"GetConfigFolder",
		"GetAutomaticConfigName",
		"SaveConfig",
		"LoadConfig",
		"SaveConfigPreset",
		"LoadConfigPreset",
		"ListConfigPresets",
		"RegisterThemeBinding",
		"RegisterThemeCallback",
		"ApplyTheme",
		"SetThemeValue",
		"GetThemeValue",
		"SaveTheme",
		"LoadTheme",
		"ResetThemeDefaults",
		"SaveThemePreset",
		"LoadThemePreset",
		"ListThemePresets",
		"ConfigureAutoLoad",
		"QueueAutoLoad",
		"RunAutoLoad",
		"SetAutoLoadEnabled",
	}) do
		Window[name] = function(self, ...)
			return self.Config[name](self.Config, ...)
		end
		Library[name] = function(self, ...)
			local window = self._activeWindow
			assert(window and window.Scope.Alive, "Create a window before using configuration")
			return window.Config[name](window.Config, ...)
		end
	end

	Compatibility.install(Library, Window, Containers)
	Library._defaultSaveConfig = Library.SaveConfig

	local function autoLoadOperation(library, method, ...)
		local window = library._activeWindow
		if window and window.Scope.Alive then
			return window.Config.AutoLoader[method](window.Config.AutoLoader, ...)
		end
		local scope = Core.scope()
		local options = table.clone(library.Config)
		options.BootstrapUrl = library.AutoLoadBootstrapUrl
		local storage = Storage.new(options)
		scope:Add(storage)
		local manager = AutoLoad.new(storage, scope, options)
		local result = table.pack(pcall(manager[method], manager, ...))
		scope:Destroy()
		if not result[1] then
			error(result[2], 2)
		end
		return table.unpack(result, 2, result.n)
	end

	function Library:ConfigureAutoLoad(options)
		return autoLoadOperation(self, "Configure", options)
	end
	function Library:SetAutoLoadEnabled(enabled, options)
		return autoLoadOperation(self, "SetEnabled", enabled, options)
	end
	function Library:QueueAutoLoad(data)
		return autoLoadOperation(self, "Queue", data)
	end
	function Library:RunAutoLoad(data)
		return autoLoadOperation(self, "Run", data)
	end

	function Library:SetThemeValue(token, value, persist)
		self:SetTheme({ [token] = value })
		local window = self._activeWindow
		if window and window.Scope.Alive then
			if persist ~= false then
				return window.Config:SaveTheme()
			end
		end
		return true
	end

	function Library:GetThemeValue(token)
		local window = self._activeWindow
		return (window and window.Scope.Alive and window.Theme or self.Theme)[ThemeAliases.token(token)]
	end

	Library.Colors = setmetatable({}, {
		__index = function(_, token)
			return Library:GetThemeValue(token)
		end,
		__newindex = function(_, token, value)
			Library:SetThemeValue(token, value, false)
		end,
	})

	local createWindow = Library.CreateWindow
	function Library:CreateWindow(options)
		options = options or {}
		local window = createWindow(self, options)
		if options.WaitForKey ~= false and options.BlockUntilKeyVerified ~= false then
			window:AwaitKey()
		end
		return window
	end

	return Library
end
