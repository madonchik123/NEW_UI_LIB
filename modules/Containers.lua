return function(require)
	local Core = require("Core")
	local Icons = require("Icons")
	local Controls = require("Controls")
	local Container = {}
	Container.__index = Container

	local function make(window, root, body, parent, page)
		local self = setmetatable({
			Window = window,
			Root = root,
			Body = body,
			Scope = Core.scope(parent.Scope),
			Parent = parent,
			Page = page,
			Count = 0,
		}, Container)
		self.Scope:Add(root)
		return self
	end

	function Container:Destroy()
		self.Scope:Destroy()
	end

	function Container:Register(control, options)
		self.Count += 1
		control.Root.LayoutOrder = self.Count
		control.Parent = self
		control.Page = self.Page
		self.Window:RegisterControl(control, options)
		if options.Searchable == false then
			return
		end
		self.Window:Register(control, options.Name or options.Title or "", options.Description)
	end

	for name, constructor in pairs(Controls) do
		Container[name] = function(self, options)
			return constructor(self, options or {})
		end
	end

	function Container:Custom(options)
		options = options or {}
		local root = Core.new("Frame", {
			Name = options.Name or "Custom",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, options.Height or 40),
			AutomaticSize = options.AutomaticSize and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		}, self.Body)
		local custom = make(self.Window, root, root, self, self.Page)
		self:Register(custom, options)
		return custom
	end

	function Container:Row(options)
		options = options or {}
		local row = self:Custom({ Name = options.Name or "Row", Height = 0, AutomaticSize = true })
		local gap = options.Gap or self.Window.Theme.Gap
		Core.list(row.Body, gap, Enum.FillDirection.Horizontal)
		local function reflow()
			if not row.Scope.Alive then
				return
			end
			local children = {}
			for _, child in ipairs(row.Body:GetChildren()) do
				if child:IsA("GuiObject") then
					table.insert(children, child)
				end
			end
			for _, child in ipairs(children) do
				child.Size = UDim2.new(
					1 / #children,
					-gap * (#children - 1) / #children,
					child.Size.Y.Scale,
					child.Size.Y.Offset
				)
			end
		end
		local register = row.Register
		function row:Register(control, controlOptions)
			register(self, control, controlOptions)
			reflow()
		end
		row.Scope:Add(row.Body.ChildAdded:Connect(reflow))
		row.Scope:Add(row.Body.ChildRemoved:Connect(reflow))
		return row
	end

	function Container:Columns(options)
		options = options or {}
		local window = self.Window
		local row = self:Custom({ Name = "Columns", Height = 0, AutomaticSize = true, Searchable = false })
		local gap = options.Gap or window.Theme.Gap
		local layout = Core.list(row.Root, gap, Enum.FillDirection.Horizontal)
		local columns = {}
		for index = 1, options.Count or 2 do
			local root = Core.new("Frame", {
				Name = "Column" .. index,
				BackgroundTransparency = 1,
				Size = UDim2.new(1 / (options.Count or 2), -gap / 2, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = index,
			}, row.Root)
			local column = make(window, root, root, row, self.Page)
			Core.list(root, gap)
			table.insert(columns, column)
		end
		local function reflow()
			if not row.Scope.Alive then
				return
			end
			local narrow = row.Root.AbsoluteSize.X / window.ScaleObject.Scale < (options.Breakpoint or 440)
			layout.FillDirection = narrow and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
			for _, column in ipairs(columns) do
				column.Root.Size = narrow and UDim2.new(1, 0, 0, 0)
					or UDim2.new(1 / #columns, -gap * (#columns - 1) / #columns, 0, 0)
			end
		end
		for _, column in ipairs(columns) do
			column.Scope:Add(function()
				local index = table.find(columns, column)
				if index then
					table.remove(columns, index)
				end
				reflow()
			end)
		end
		row.Scope:Add(row.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow))
		reflow()
		row.Columns = columns
		return table.unpack(columns)
	end

	function Container:Card(options)
		options = options or {}
		local window = self.Window
		local root = Core.new("Frame", {
			Name = options.Title or options.Name or "Card",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,
		}, self.Body)
		Core.bind(window, root, "BackgroundColor3", "Surface")
		Core.bind(window, root, "BackgroundTransparency", "PanelTransparency")
		Core.round(root, window)
		Core.stroke(root, window)
		Core.list(root, 0)
		local header = Core.new("TextButton", {
			Name = "Header",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = 0,
			Selectable = options.Collapsible ~= false,
		}, root)
		local icon = Icons.create(window, header, options.Icon or "version")
		icon.Position = UDim2.fromOffset(window.Theme.Padding, 9)
		local title = Core.text(window, header, options.Title or options.Name or "Section", 12)
		Core.bind(window, title, "Font", "FontBold")
		title.Position = UDim2.fromOffset(window.Theme.Padding + 23, 0)
		title.Size = UDim2.new(1, options.Action and -115 or -65, 1, 0)
		local chevron = Icons.create(window, header, "chevron")
		chevron.Position = UDim2.new(1, -27, 0, 9)
		chevron.Visible = options.Collapsible ~= false
		if options.Status then
			local dot = Core.new(
				"Frame",
				{ Size = UDim2.fromOffset(5, 5), Position = UDim2.new(1, -43, 0, 15), BorderSizePixel = 0 },
				header
			)
			Core.bind(window, dot, "BackgroundColor3", options.Status)
			Core.round(dot, window)
		end
		local clip = Core.new("Frame", {
			Name = "ContentClip",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			ClipsDescendants = true,
			LayoutOrder = 1,
		}, root)
		local body = Core.new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, clip)
		local padding = Core.pad(body, window.Theme.Padding)
		if options.Header ~= false then
			padding.PaddingTop = UDim.new(0, 0)
		end
		local layout = Core.list(body, window.Theme.Gap)
		local card = make(window, root, body, self, self.Page)
		window:Tooltip(header, options.Tooltip or options.Title or options.Name, card.Scope)
		if options.Header == false then
			header.Visible = false
		end
		card.Expanded = options.Expanded ~= false
		card.Clip = clip
		local function refresh(animate)
			if not card.Scope.Alive then
				return
			end
			local height = card.Expanded
					and layout.AbsoluteContentSize.Y / window.ScaleObject.Scale + padding.PaddingTop.Offset + padding.PaddingBottom.Offset
				or 0
			local target = { Size = UDim2.new(1, 0, 0, height) }
			if animate then
				Core.tween(window, clip, target)
			else
				local tween = window.Tweens[clip]
				if tween then
					tween:Cancel()
					tween:Destroy()
					window.Tweens[clip] = nil
				end
				clip.Size = target.Size
			end
			Core.tween(window, chevron, { Rotation = card.Expanded and 0 or -90 })
		end
		function card:SetExpanded(value)
			self.Expanded = value == true
			refresh(true)
		end
		function card:ToggleExpanded()
			self:SetExpanded(not self.Expanded)
		end
		card.Scope:Add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			refresh(false)
		end))
		card.Scope:Add(window.ScaleObject:GetPropertyChangedSignal("Scale"):Connect(function()
			refresh(false)
		end))
		card.Scope:Add(padding:GetPropertyChangedSignal("PaddingTop"):Connect(function()
			refresh(false)
		end))
		card.Scope:Add(padding:GetPropertyChangedSignal("PaddingBottom"):Connect(function()
			refresh(false)
		end))
		if options.Collapsible ~= false then
			card.Scope:Add(header.Activated:Connect(function()
				card:ToggleExpanded()
			end))
		end
		if options.Action then
			local action = Core.new("TextButton", {
				Name = "Action",
				Text = options.Action.Text or "Open",
				Font = window.Theme.Font,
				TextSize = 11,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(54, 26),
				Position = UDim2.new(1, -90, 0, 4),
			}, header)
			Core.bind(window, action, "TextColor3", "Accent")
			card.Scope:Add(action.Activated:Connect(function()
				Core.callback(options.Action.Callback, card)
			end))
		end
		if options.Description then
			card:Label({ Name = options.Description })
		end
		if options.Footer then
			local footer = Core.text(window, root, options.Footer, 10, "TextMuted")
			footer.LayoutOrder = 2
			footer.Size = UDim2.new(1, 0, 0, 25)
			footer.TextXAlignment = Enum.TextXAlignment.Center
			function card:SetFooter(text)
				footer.Text = tostring(text)
			end
		end
		self:Register(card, options)
		refresh(false)
		return card
	end

	Container.Section = Container.Card

	function Container:InfoRow(options)
		options = options or {}
		local row = self:Custom({ Name = options.Name or "Info", Height = 17 })
		local label = Core.text(self.Window, row.Body, options.Name, 11, "TextSecondary")
		label.Size = UDim2.new(0.52, 0, 1, 0)
		local value = Core.text(self.Window, row.Body, options.Value, 11)
		value.Position = UDim2.fromScale(0.52, 0)
		value.Size = UDim2.new(0.48, 0, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		function row:Set(text)
			value.Text = tostring(text)
		end
		function row:Get()
			return value.Text
		end
		return row
	end

	function Container:StatusCard(options)
		options = options or {}
		local card = self:Card(options)
		card.Value = card:Label({ Name = options.Value or "Ready", Description = options.StatusText })
		function card:Set(value)
			self.Value:Set(value)
		end
		return card
	end

	function Container:ListCard(options)
		options = options or {}
		local card = self:Card(options)
		local scroll = Core.new("ScrollingFrame", {
			Name = "Items",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, options.Height or 156),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, card.Body)
		Core.bind(self.Window, scroll, "ScrollBarImageColor3", "Border")
		Core.list(scroll, 1)
		local itemScope
		function card:SetItems(items)
			if itemScope then
				itemScope:Destroy()
			end
			itemScope = Core.scope(self.Scope)
			for index, item in ipairs(items) do
				if type(item) == "string" then
					item = { Name = item }
				end
				local row = Core.new("Frame", {
					Name = item.Name,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -5, 0, 13),
					LayoutOrder = index,
				}, scroll)
				itemScope:Add(row)
				self.Window:Tooltip(row, item.Tooltip or item.Name, itemScope)
				local dot = Core.new(
					"Frame",
					{ BorderSizePixel = 0, Size = UDim2.fromOffset(5, 5), Position = UDim2.fromOffset(0, 6) },
					row
				)
				Core.bind(self.Window, dot, "BackgroundColor3", item.Status or "Success")
				Core.round(dot, self.Window)
				local title = Core.text(self.Window, row, item.Name, 11, item.Status or "Success")
				title.Position = UDim2.fromOffset(12, 0)
				title.Size = UDim2.new(item.Description and 0.64 or 1, -12, 1, 0)
				if item.Description then
					local detail = Core.text(self.Window, row, item.Description, 10, "TextMuted")
					detail.Position = UDim2.fromScale(0.64, 0)
					detail.Size = UDim2.fromScale(0.36, 1)
					detail.TextXAlignment = Enum.TextXAlignment.Right
				end
			end
		end
		card:SetItems(options.Items or {})
		return card
	end

	function Container:Tabs()
		local owner = self
		local root = Core.new("Frame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, self.Body)
		Core.list(root, 6)
		local tabs = make(self.Window, root, root, self, self.Page)
		local bar = Core.new(
			"Frame",
			{ Name = "TabBar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 0 },
			root
		)
		Core.list(bar, 0, Enum.FillDirection.Horizontal)
		tabs.Items = {}
		function tabs:Tab(options)
			local content = Core.new("Frame", {
				Name = options.Name,
				Visible = false,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 1,
			}, root)
			Core.list(content, owner.Window.Theme.Gap)
			local tab = make(owner.Window, content, content, tabs, owner.Page)
			local button = Core.new("TextButton", {
				Name = options.Name,
				Text = options.Icon and "" or options.Name,
				TextSize = 11,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
			}, bar)
			Core.bind(owner.Window, button, "Font", "FontBold")
			Core.bind(owner.Window, button, "TextColor3", "TextSecondary")
			Core.bind(owner.Window, button, "BackgroundColor3", "SurfaceActive")
			tab.Scope:Add(button)
			if options.Icon then
				local icon = Icons.create(owner.Window, button, options.Icon)
				icon.Position = UDim2.new(0.5, -8, 0.5, -8)
			end
			tab.TabButton = button
			owner.Window:Tooltip(button, options.Tooltip or options.Name, tab.Scope)
			table.insert(tabs.Items, tab)
			for _, item in ipairs(tabs.Items) do
				item.TabButton.Size = UDim2.new(1 / #tabs.Items, 0, 1, 0)
			end
			function tab:Select()
				for _, item in ipairs(tabs.Items) do
					item.Root.Visible = item == self
					Core.tween(owner.Window, item.TabButton, { BackgroundTransparency = item == self and 0.5 or 1 })
				end
				tabs.Selected = self
			end
			tab.Reveal = tab.Select
			tab.Scope:Add(button.Activated:Connect(function()
				tab:Select()
			end))
			tab.Scope:Add(function()
				local index = table.find(tabs.Items, tab)
				if index then
					table.remove(tabs.Items, index)
				end
				if tabs.Scope.Alive then
					for _, item in ipairs(tabs.Items) do
						item.TabButton.Size = UDim2.new(1 / #tabs.Items, 0, 1, 0)
					end
					if tabs.Selected == tab and tabs.Items[1] then
						tabs.Items[1]:Select()
					end
				end
			end)
			if #tabs.Items == 1 then
				tab:Select()
			end
			owner.Window:Register(tab, options.Name, options.Description)
			return tab
		end
		self:Register(tabs, { Name = "Theme tabs" })
		return tabs
	end

	function Container.modal(window, options)
		local root = Core.new("TextButton", {
			Name = options.Title or "Modal",
			Text = "",
			AutoButtonColor = false,
			Visible = false,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 30,
		}, window.Root)
		Core.bind(window, root, "BackgroundColor3", "Background")
		local panel = Core.new("Frame", {
			Name = "Panel",
			Active = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = options.Size or UDim2.fromOffset(390, 210),
			BorderSizePixel = 0,
		}, root)
		Core.bind(window, panel, "BackgroundColor3", "Surface")
		Core.round(panel, window)
		Core.stroke(panel, window)
		local title = Core.text(window, panel, options.Title or "Details", 14)
		title.Position = UDim2.fromOffset(18, 12)
		title.Size = UDim2.new(1, -60, 0, 28)
		local close = Core.new("TextButton", {
			Name = "Close",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -34, 0, 8),
			Size = UDim2.fromOffset(26, 26),
		}, panel)
		local icon = Icons.create(window, close, "close")
		icon.Position = UDim2.fromOffset(5, 5)
		local body = Core.new("ScrollingFrame", {
			Name = "Body",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 48),
			Size = UDim2.new(1, -36, 1, -60),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
		}, panel)
		Core.bind(window, body, "ScrollBarImageColor3", "Border")
		Core.list(body, 8)
		local modal = make(window, root, body, window, options.Page)
		window:Tooltip(close, "Close", modal.Scope)
		function modal:Open()
			root.Visible = true
		end
		function modal:Close()
			root.Visible = false
		end
		modal.Reveal = modal.Open
		modal.Scope:Add(close.Activated:Connect(function()
			modal:Close()
		end))
		modal.Scope:Add(root.Activated:Connect(function()
			modal:Close()
		end))
		local function fit()
			if not modal.Scope.Alive then
				return
			end
			local requested = options.Size or UDim2.fromOffset(390, 210)
			local width = window.Root.Size.X.Offset
			local height = window.Root.Size.Y.Offset
			panel.Size = UDim2.fromOffset(
				math.clamp(requested.X.Offset + requested.X.Scale * width, 1, math.max(1, width - 24)),
				math.clamp(requested.Y.Offset + requested.Y.Scale * height, 1, math.max(1, height - 24))
			)
		end
		modal.Scope:Add(window.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
		fit()
		return modal
	end

	function Container.page(window, options, navigation)
		local root = Core.new("ScrollingFrame", {
			Name = options.Name,
			Visible = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, window.Content)
		Core.bind(window, root, "ScrollBarImageColor3", "Border")
		local pagePadding = Core.pad(root, window.Theme.MainPadding)
		pagePadding.PaddingTop = UDim.new(0, 8)
		Core.list(root, window.Theme.Gap)
		local page = make(window, root, root, window, nil)
		page.Page = page
		page.Name = options.Name
		page.Subtitle = options.Subtitle
		page.Breadcrumb = options.Breadcrumb
		page.Navigation = navigation
		page.Disabled = options.Disabled == true
		function page:Select()
			if not self.Disabled then
				window:SelectPage(self)
			end
		end
		function page:SetDisabled(disabled)
			self.Disabled = disabled == true
			self.Navigation.TextTransparency = self.Disabled and 0.6 or 0
			self.Navigation.Selectable = not self.Disabled
			if self.Disabled and window.SelectedPage == self then
				window:DeselectPage()
			end
		end
		page.Scope:Add(navigation)
		page.Scope:Add(function()
			window.Pages[page] = nil
			if window.SelectedPage == page then
				window:DeselectPage()
			end
		end)
		page:SetDisabled(page.Disabled)
		window:Register(page, options.Name, options.Subtitle)
		return page
	end

	return Container
end
