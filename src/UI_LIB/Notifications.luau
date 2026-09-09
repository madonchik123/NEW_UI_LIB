local Core = require(script.Parent.Core)
local Icons = require(script.Parent.Icons)
local Notifications = {}

function Notifications.show(window, options, body, duration)
	if type(options) == "string" then
		options = { Title = options, Text = body, Duration = duration }
	end
	options = options or {}
	if not window.Notifications then
		window.Notifications = Core.new("Frame", {
			Name = "Notifications",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -16),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 90,
		}, window.Gui)
		Core.new("UISizeConstraint", { MaxSize = Vector2.new(310, 10000) }, window.Notifications)
		Core.list(window.Notifications, 8).VerticalAlignment = Enum.VerticalAlignment.Bottom
		window.NotificationItems = {}
	end
	local scope = Core.scope(window.Scope)
	local root = Core.new("CanvasGroup", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 88),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 90,
	}, window.Notifications)
	scope:Add(root)
	Core.bind(window, root, "BackgroundColor3", "Surface")
	Core.round(root, window)
	Core.stroke(root, window)
	local icon = Icons.create(window, root, options.Icon or "info", options.Type == "error" and "Error" or "Accent", 18)
	icon.Position = UDim2.fromOffset(14, 15)
	local title = Core.text(window, root, options.Title or "Unknown Hub", 12)
	Core.bind(window, title, "Font", "FontBold")
	title.Position = UDim2.fromOffset(42, 10)
	title.Size = UDim2.new(1, -74, 0, 24)
	local message =
		Core.text(window, root, options.Text or options.Content or options.Description or "", 11, "TextSecondary")
	message.Position = UDim2.fromOffset(14, 37)
	message.Size = UDim2.new(1, -28, 0, 38)
	message.TextWrapped = true
	message.TextTruncate = Enum.TextTruncate.None
	message.TextYAlignment = Enum.TextYAlignment.Top
	local close = Core.new("TextButton", {
		Name = "Dismiss",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -32, 0, 7),
		ZIndex = 91,
	}, root)
	Icons.create(window, close, "close").Position = UDim2.fromOffset(6, 6)
	window:Tooltip(close, "Dismiss notification", scope)
	local item = { Scope = scope, Root = root }
	function item:Destroy()
		self.Scope:Destroy()
	end
	function item:Close()
		if not self.Scope.Alive then
			return
		end
		Core.tween(window, root, { GroupTransparency = 1 })
		Core.delay(scope, window.Theme.AnimationSpeed + 0.01, function()
			scope:Destroy()
		end)
	end
	scope:Add(close.Activated:Connect(function()
		item:Close()
	end))
	table.insert(window.NotificationItems, item)
	scope:Add(function()
		local index = table.find(window.NotificationItems, item)
		if index then
			table.remove(window.NotificationItems, index)
		end
	end)
	while #window.NotificationItems > 4 do
		window.NotificationItems[1]:Destroy()
	end
	Core.tween(window, root, { GroupTransparency = 0 })
	Core.delay(scope, math.clamp(tonumber(options.Duration) or 5, 1, 60), function()
		item:Close()
	end)
	return item
end

return Notifications
