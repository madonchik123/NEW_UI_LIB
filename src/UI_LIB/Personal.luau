local Players = game:GetService("Players")
local Personal = {}
local function compact(card, gap)
	card.Body.UIListLayout.Padding = UDim.new(0, gap or 0)
	return card
end
function Personal.mount(window)
	local player = Players.LocalPlayer
	local username = player.Name
	local appearance = window:Page({ Name = "Appearance", Icon = "settings", Group = "Personal" })
	local appearanceLeft, appearanceRight = appearance:Columns()
	local appearanceCard = compact(appearanceLeft:Section({ Name = "Appearance", Icon = "settings" }), 1)
	local opacity = appearanceCard:Slider({
		Name = "Window opacity",
		Preference = true,
		Min = 35,
		Max = 100,
		Default = 72,
		Increment = 1,
		Callback = function(value)
			window:SetTheme({ WindowTransparency = 1 - value / 100 })
		end,
	})
	local panelOpacity = appearanceCard:Slider({
		Name = "Panel opacity",
		Preference = true,
		Min = 35,
		Max = 100,
		Default = 100,
		Increment = 1,
		Callback = function(value)
			window:SetTheme({ PanelTransparency = 1 - value / 100 })
		end,
	})
	local blur = appearanceCard:Toggle({
		Name = "Blur behind UI",
		Preference = true,
		Default = true,
		Callback = function(value)
			window:SetBlur(value)
		end,
	})
	local themeCard = compact(appearanceLeft:Card({ Title = "Theme", Icon = "settings" }))
	local themeTabs = themeCard:Tabs()
	local colors = themeTabs:Tab({ Name = "Colors", Icon = "palette" })
	colors.Body.UIListLayout.Padding = UDim.new(0, 0)
	local colorControls = {}
	local defaultColors = {
		Background = window.Theme.Background,
		Surface = window.Theme.Surface,
		Accent = window.Theme.Accent,
		Text = window.Theme.Text,
		Border = window.Theme.Border,
	}
	for _, entry in ipairs({
		{ "Window color", "Background" },
		{ "Panel color", "Surface" },
		{ "Accent color", "Accent" },
		{ "Text color", "Text" },
		{ "Border color", "Border" },
	}) do
		local token = entry[2]
		colorControls[token] = colors:ColorPicker({
			Name = entry[1],
			Default = window.Theme[token],
			Preference = true,
			Callback = function(color)
				window:SetTheme({ [token] = color })
			end,
		})
	end
	local presets = themeTabs:Tab({ Name = "Presets", Icon = "layers" })
	local preset = presets:Dropdown({
		Name = "Color preset",
		Preference = true,
		Default = "Unknown Hub",
		Options = { "Unknown Hub", "Slate", "Midnight" },
		Callback = function(value)
			local backgrounds = {
				["Unknown Hub"] = defaultColors.Background,
				Slate = Color3.fromRGB(28, 33, 42),
				Midnight = Color3.fromRGB(10, 19, 30),
			}
			colorControls.Background:Set(backgrounds[value])
		end,
	})
	local fontTab = themeTabs:Tab({ Name = "Typography", Icon = "text" })
	local font = fontTab:Dropdown({
		Name = "Font",
		Preference = true,
		Options = { "Builder Sans", "Gotham", "Code" },
		Default = "Builder Sans",
		Callback = function(value)
			window:SetTheme({
				Font = ({ ["Builder Sans"] = Enum.Font.BuilderSans, Gotham = Enum.Font.Gotham, Code = Enum.Font.Code })[value],
				FontBold = ({
					["Builder Sans"] = Enum.Font.BuilderSansBold,
					Gotham = Enum.Font.GothamBold,
					Code = Enum.Font.Code,
				})[value],
			})
		end,
	})
	local scale = fontTab:Slider({
		Name = "UI scale",
		Preference = true,
		Min = 0.75,
		Max = 1.25,
		Default = 1,
		Increment = 0.05,
		Callback = function(value)
			window:SetScale(value)
		end,
	})
	local interface = compact(appearanceRight:Section({ Name = "Interface", Icon = "routine" }), 6)
	local reducedMotion = interface:Toggle({
		Name = "Reduce motion",
		Preference = true,
		Default = false,
		Callback = function(value)
			window:SetTheme({ AnimationSpeed = value and 0 or 0.16 })
		end,
	})
	interface:Button({
		Name = "Hide interface",
		Callback = function()
			window:Close()
		end,
	})
	interface:Button({
		Name = "Unload",
		Callback = function()
			window:Destroy()
		end,
	})
	local function restore()
		opacity:Set(72)
		panelOpacity:Set(100)
		blur:Set(true)
		reducedMotion:Set(false)
		scale:Set(1)
		font:Set("Builder Sans")
		preset:Set("Unknown Hub")
		for token, control in pairs(colorControls) do
			control:Set(defaultColors[token])
		end
		local defaults = table.clone(defaultColors)
		defaults.WindowTransparency = 0.28
		defaults.PanelTransparency = 0
		defaults.AnimationSpeed = 0.16
		defaults.Font = Enum.Font.BuilderSans
		defaults.FontBold = Enum.Font.BuilderSansBold
		window:SetTheme(defaults)
		window:SetBlur(true)
		window:SetScale(1)
	end
	interface:Button({ Name = "Restore appearance", Callback = restore })
	local profile = compact(appearanceRight:Section({ Name = "Profile & status", Icon = "routine" }), 6)
	local profileDescription = profile:Textbox({
		Name = "Profile description",
		Preference = true,
		Default = "",
		TextChanged = function(value)
			window:SetProfile(value)
		end,
	})
	local statusText = profile:Textbox({
		Name = "Status text",
		Preference = true,
		Default = "Active",
		TextChanged = function(value)
			window:SetProfile(nil, value)
		end,
	})
	window:SetProfile("", "Online")
	local profileModal = window:Modal({ Title = "Unknown Hub", Size = UDim2.fromOffset(390, 210), Page = appearance })
	local modalColumnsLeft, modalColumnsRight = profileModal:Columns({ Breakpoint = 280 })
	local modalDescription = modalColumnsLeft:Label({ Name = "@" .. username })
	modalColumnsRight:InfoRow({ Name = "User ID", Value = tostring(player.UserId) })
	modalColumnsRight:InfoRow({ Name = "Account age", Value = player.AccountAge .. " days" })
	modalColumnsRight:InfoRow({ Name = "Membership", Value = player.MembershipType.Name })
	local modalStatus = modalColumnsRight:InfoRow({ Name = "Status", Value = "Active" })
	modalColumnsRight:InfoRow({ Name = "Key time", Value = "--" })
	window.Scope:Add(window.ProfileButton.Activated:Connect(function()
		local description = profileDescription:Get()
		modalDescription:Set(description ~= "" and description or "@" .. username)
		modalStatus:Set(statusText:Get())
		profileModal:Open()
	end))

	local reopen
	reopen = interface:Keybind({
		KeyboardOnly = true,
		Name = "Toggle UI key",
		Default = window.ToggleKey,
		Preference = true,
		Changed = function(key)
			if key then
				window:SetToggleKey(key)
			elseif reopen then
				reopen:Set(window.ToggleKey, true)
			end
		end,
		Tooltip = "Keyboard shortcut to minimize or reopen Unknown Hub",
	})
	local configuration = appearanceRight:Card({ Title = "Configuration", Icon = "save" })
	local config = window.Config
	local autoLoad = configuration:Toggle({
		Name = "Auto load UI",
		Default = true,
		Persist = false,
		Tooltip = "Restore your active configuration and interface preferences on startup",
		Callback = function(value)
			config:SetAutoLoad(value)
		end,
	})
	local autoSave = configuration:Toggle({
		Name = "Auto save settings",
		Default = true,
		Persist = false,
		Tooltip = "Save changes to the active configuration automatically",
		Callback = function(value)
			config:SetAutoSave(value)
		end,
	})
	local choice = configuration:Dropdown({
		Name = "Active config",
		Options = { "Default" },
		Default = "Default",
		Persist = false,
		Callback = function(value)
			local ok, message = config:Switch(value)
			if not ok and window.Scope.Alive then
				window:Notify({ Title = "Configuration", Text = message, Type = "error" })
			end
		end,
	})
	local configName =
		configuration:Textbox({ Name = "Config name", Placeholder = "New configuration", Persist = false })
	local function operation(method, ...)
		local ok, message = config[method](config, ...)
		if window.Scope.Alive then
			choice:SetOptions(config:List())
			choice:Set(config.ActiveProfile, true)
			window:Notify({
				Title = "Configuration",
				Text = message or (ok and "Saved" or "Could not save"),
				Type = ok and "success" or "error",
			})
		end
	end
	local row = configuration:Row()
	row:Button({
		Name = "Create",
		Callback = function()
			operation("Create", configName:Get())
		end,
	})
	row:Button({
		Name = "Rename",
		Callback = function()
			operation("Rename", config.ActiveProfile, configName:Get())
		end,
	})
	local actions = configuration:Row()
	actions:Button({
		Name = "Save",
		Callback = function()
			operation("Save")
		end,
	})
	actions:Button({
		Name = "Load",
		Callback = function()
			operation("Load", config.ActiveProfile)
		end,
	})
	configuration:Button({
		Name = "Delete config",
		Callback = function()
			operation("Delete", config.ActiveProfile)
		end,
	})
	local saveStatus = configuration:Label({ Name = "Configuration status", Text = "" })
	config:Subscribe(configuration.Scope, function(state)
		autoLoad:Set(state.AutoLoad, true)
		autoSave:Set(state.AutoSave, true)
		choice:SetOptions(config:List())
		choice:Set(state.ActiveProfile, true)
		saveStatus:Set(state.Message)
	end)
	local themeName = presets:Textbox({ Name = "Theme name", Placeholder = "My theme", Persist = false })
	local savedTheme = presets:Dropdown({ Name = "Saved theme", Options = {}, Persist = false })
	config:Subscribe(presets.Scope, function()
		savedTheme:SetOptions(config:ListThemePresets())
	end)
	config:RegisterThemeCallback(function()
		for token, control in pairs(colorControls) do
			control:Set(window.Theme[token], true)
		end
		opacity:Set((1 - window.Theme.WindowTransparency) * 100, true)
		panelOpacity:Set((1 - window.Theme.PanelTransparency) * 100, true)
		reducedMotion:Set(window.Theme.AnimationSpeed == 0, true)
		local fontName = ({
			[Enum.Font.BuilderSans] = "Builder Sans",
			[Enum.Font.Gotham] = "Gotham",
			[Enum.Font.Code] = "Code",
		})[window.Theme.Font]
		if fontName then
			font:Set(fontName, true)
		end
	end, appearance)
	presets:Button({
		Name = "Save theme",
		Callback = function()
			local ok, message = config:SaveThemePreset(themeName:Get())
			if not window.Scope.Alive then
				return
			end
			savedTheme:SetOptions(config:ListThemePresets())
			window:Notify({ Title = "Theme", Text = message })
		end,
	})
	presets:Button({
		Name = "Load theme",
		Callback = function()
			local ok, message = config:LoadThemePreset(savedTheme:Get())
			if window.Scope.Alive then
				window:Notify({ Title = "Theme", Text = message, Type = ok and "success" or "error" })
			end
		end,
	})
	window.Personal = {
		Page = appearance,
		Opacity = opacity,
		PanelOpacity = panelOpacity,
		Blur = blur,
		ThemeTabs = themeTabs,
		Colors = colorControls,
		Scale = scale,
		ReducedMotion = reducedMotion,
		ProfileDescription = profileDescription,
		StatusText = statusText,
		ProfileModal = profileModal,
		Restore = restore,
		ToggleKey = reopen,
		AutoLoad = autoLoad,
		AutoSave = autoSave,
		Profile = choice,
		ConfigName = configName,
	}
	return window.Personal
end
return Personal
