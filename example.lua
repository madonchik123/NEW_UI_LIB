local ReplicatedStorage = game:GetService("ReplicatedStorage")
local App = require(ReplicatedStorage:WaitForChild("UI_LIB_App"))
local Window = App.mount({
	Name = "Unknown Hub",
	Title = "Unknown Hub",
	KeySystem = false,
	UnknownHubKeySystem = false,
	UnknownHubProjectId = "54474b4c5d5a4f459909c4cb70e7b4f3",
	GetKeyLink = "https://unknownhub.win/#get-key",
	ConfigName = "unknown_hub",
	AutoSave = true,
	AutoInitialize = false,
	ToggleKey = Enum.KeyCode.RightShift,

	OnAction = function(settings)
		print("Routine settings:", settings.Mode, settings.Interval, settings.Enabled)
	end,
})

local Tools = Window:AddMenu({ Name = "Tools", Columns = 2, Icon = "settings" })
local General = Tools:AddSection({ Name = "General", Column = 1 })
local Filters = Tools:AddSection({ Name = "Filters", Column = 2 })
local Enabled = General:AddToggle({ Name = "Enabled", Default = false, Tooltip = "Enable your feature" })
Enabled:AddSlider({ Name = "Range", Min = 25, Max = 500, Default = 150, Suffix = " studs" })
Enabled:AddDropdown({ Name = "Strategy", Options = { "Closest", "Best value", "Safe path" }, Default = "Closest" })
Filters:AddMultiDropdown({
	Name = "Targets",
	Options = { "Common", "Rare", "Epic", "Legendary" },
	Default = { "Rare", "Epic" },
})
Filters:AddInputBox({ Name = "Name filter", Placeholder = "Type a name..." })
General:AddColorPicker({ Name = "Marker color", Default = Color3.fromRGB(117, 185, 204), Transparency = true })
Window.App.Overview:Select()
Window.Config:Initialize()
