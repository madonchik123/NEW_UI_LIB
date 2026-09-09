return function(require)
	local Players = game:GetService("Players")
	local Library = require("UI_LIB")
	local Core = require("Core")

	local App = {}

	local function compact(card, gap)
		card.Body.UIListLayout.Padding = UDim.new(0, gap or 0)
		return card
	end

	function App.mount(options)
		options = options or {}
		local player = Players.LocalPlayer
		local username = player.Name
		local windowOptions = table.clone(options)
		windowOptions.Name = options.Name or "Unknown Hub"
		windowOptions.Title = options.Title or "Unknown Hub"
		windowOptions.Username = options.Username or "@" .. username
		windowOptions.Size = options.Size or UDim2.fromOffset(720, 466)
		local window = Library.new(windowOptions)
		window:SetTheme({ WindowTransparency = 0.28 })
		window:SetBlur(true)
		local overview = window.Overview.Page
		local routine =
			window:Page({ Name = "Routine", Icon = "routine", Group = "Automation", Breadcrumb = "Automation" })
		local overlay = window:Page({ Name = "Overlay", Icon = "eye", Group = "Automation" })

		local routineLeft, routineRight = routine:Columns()
		local routineCard = compact(routineLeft:Section({ Name = "Routine", Icon = "routine" }), 1)
		local autoFarm = routineCard:Toggle({ Name = "Auto farm", Default = false })
		local autoCollect = routineCard:Toggle({ Name = "Auto collect", Default = false })
		local autoEquip = routineCard:Toggle({ Name = "Auto equip", Default = true })
		local pauseMenus = routineCard:Toggle({ Name = "Pause in menus", Default = true })
		local interval =
			routineCard:Slider({ Name = "Action interval", Min = 1, Max = 100, Default = 35, Increment = 1 })
		local mode = routineCard:Dropdown({
			Name = "Mode",
			Options = { "Balanced", "Fast", "Conservative" },
			Default = "Balanced",
		})
		local quick = compact(routineLeft:Card({ Title = "Quick actions", Icon = "routine" }))
		local function execute()
			if options.OnAction then
				Core.callback(
					options.OnAction,
					{ Mode = mode:Get(), Interval = interval:Get(), Enabled = autoFarm:Get() }
				)
			else
				window:Notify({ Title = "Routine", Text = mode:Get() .. " · Interval " .. tostring(interval:Get()) })
			end
		end
		quick:Button({ Name = "Run action", Callback = execute })
		local selection = compact(routineRight:Section({ Name = "Selection", Icon = "target" }), 1)
		local visibleOnly = selection:Toggle({ Name = "Visible targets only", Default = true })
		local priority = selection:Dropdown({
			Name = "Priority",
			Options = { "Nearest", "Lowest health", "Highest health" },
			Default = "Nearest",
		})
		local radius = selection:Slider({ Name = "Radius", Min = 0, Max = 250, Default = 60, Increment = 1 })
		local nameFilter = selection:Textbox({ Name = "Name filter", Placeholder = "Type a name...", Default = "" })

		local overlayLeft, overlayRight = overlay:Columns()
		local markers = compact(overlayLeft:Section({ Name = "Markers", Icon = "routine" }), 1)
		local marker = Core.new("BillboardGui", {
			Name = "UnknownHubMarker",
			Enabled = false,
			Size = UDim2.fromOffset(140, 32),
			StudsOffset = Vector3.new(0, 3, 0),
			AlwaysOnTop = true,
			MaxDistance = 200,
		}, player.PlayerGui)
		window.Scope:Add(marker)
		local markerText = Core.text(window, marker, username, 14)
		markerText.Size = UDim2.fromScale(1, 1)
		markerText.TextXAlignment = Enum.TextXAlignment.Center
		local function attach(character)
			marker.Adornee = character:FindFirstChild("Head")
		end
		if player.Character then
			attach(player.Character)
		end
		window.Scope:Add(player.CharacterAdded:Connect(attach))
		local markerEnabled = markers:Toggle({
			Name = "Enabled",
			Default = false,
			Callback = function(value)
				marker.Enabled = value
			end,
		})
		local showNames = markers:Toggle({
			Name = "Show names",
			Default = true,
			Callback = function(value)
				markerText.Visible = value
			end,
		})
		local rendering = compact(overlayRight:Section({ Name = "Rendering", Icon = "routine" }), 1)
		local distance = rendering:Slider({
			Name = "Distance",
			Min = 0,
			Max = 600,
			Default = 200,
			Increment = 1,
			Callback = function(value)
				marker.MaxDistance = value
			end,
		})
		local style = rendering:Dropdown({
			Name = "Style",
			Options = { "Minimal", "Outlined", "Bold" },
			Default = "Minimal",
			Callback = function(value)
				markerText.TextStrokeTransparency = value == "Outlined" and 0.25 or 1
				markerText.Font = value == "Bold" and Enum.Font.BuilderSansBold or window.Theme.Font
			end,
		})

		overview:Select()
		window.App = {
			Overview = overview,
			Routine = routine,
			Overlay = overlay,
			AutoFarm = autoFarm,
			AutoCollect = autoCollect,
			AutoEquip = autoEquip,
			PauseMenus = pauseMenus,
			Interval = interval,
			Mode = mode,
			VisibleOnly = visibleOnly,
			Priority = priority,
			Radius = radius,
			NameFilter = nameFilter,
			MarkerEnabled = markerEnabled,
			ShowNames = showNames,
			Distance = distance,
			Style = style,
		}

		return window
	end

	return App
end
