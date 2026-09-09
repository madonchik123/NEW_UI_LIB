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
		StatusCode = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0,
		Body = response.Body or response.body or response.ResponseBody,
	}
end

local requestFunction = getRequestFunction()
assert(type(requestFunction) == "function", "The executor request capability is unavailable.")
assert(type(loadstring) == "function", "The executor loadstring capability is unavailable.")
local response = normalizeResponse(requestFunction({
	Url = "https://raw.githubusercontent.com/madonchik123/NEW_UI_LIB/executor/UI_LIB.lua",
	Method = "GET",
}))
local status = type(response) == "table" and tonumber(response.StatusCode)
assert(status and status >= 200 and status < 300 and type(response.Body) == "string", "Unable to download UI_LIB.")
local Library = assert(loadstring(response.Body))()
local Window = Library:CreateApp({
	Name = "Unknown Hub",
	Title = "Unknown Hub",
	KeySystem = true,
	UnknownHubKeySystem = true,
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
Window:ConfigureAutoLoad({
	loaderUrl = "https://raw.githubusercontent.com/madonchik123/NEW_UI_LIB/executor/example.lua",
})
