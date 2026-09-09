return function(require)
	local Core = require("Core")
	local Icons = require("Icons")
	local Text = require("Text")

	local Search = {}

	local function contextFor(window, object)
		local names = {}
		local parent = object.Parent
		while parent and parent ~= window do
			local registered = window.SearchEntries[parent]
			local name = registered and registered.Name
			if name == "Theme tabs" then
				name = nil
			end
			if name and not parent.RawText then
				name = Text.display(name)
			end
			if name and names[1] ~= name then
				table.insert(names, 1, name)
			end
			parent = parent.Parent
		end
		return #names > 0 and table.concat(names, " / ") or "Page"
	end

	function Search.query(window, query)
		local results = {}
		query = string.lower(query):match("^%s*(.-)%s*$")
		for object, entry in pairs(window.SearchEntries) do
			if not object.Scope.Alive or (object.Page and object.Page.Disabled) or object.Disabled then
				continue
			end
			local context = contextFor(window, object)
			local name = string.lower(entry.Name)
			local haystack = name .. " " .. string.lower(entry.Description .. " " .. context)
			local matches = true
			local score = 0
			for term in query:gmatch("%S+") do
				local at = string.find(haystack, term, 1, true)
				if not at then
					matches = false
					break
				end
				if string.find(name, term, 1, true) then
					score += 10
				end
			end
			if matches then
				if name == query then
					score += 100
				end
				if query ~= "" and name:sub(1, #query) == query then
					score += 30
				end
				if query == "" and window.Pages[object] then
					score += 20
				end
				table.insert(results, {
					Object = object,
					Name = if object.RawText then entry.Name else Text.display(entry.Name),
					RawName = entry.Name,
					Description = Text.display(entry.Description),
					Context = context,
					Score = score,
				})
			end
		end
		table.sort(results, function(a, b)
			if a.Score ~= b.Score then
				return a.Score > b.Score
			end
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			return a.Context < b.Context
		end)
		return results
	end

	local function contains(instance, point)
		local position, size = instance.AbsolutePosition, instance.AbsoluteSize
		return point.X >= position.X
			and point.X <= position.X + size.X
			and point.Y >= position.Y
			and point.Y <= position.Y + size.Y
	end

	function Search.mount(window)
		local scope = Core.scope(window.Scope)
		local panel = Core.new("CanvasGroup", {
			Name = "SearchPanel",
			Visible = false,
			BackgroundTransparency = 0.03,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(360, 300),
			BorderSizePixel = 0,
			ZIndex = 40,
		}, window.Root)
		Core.bind(window, panel, "BackgroundColor3", "Surface")
		Core.round(panel, window)
		Core.stroke(panel, window)
		local field = Core.new("Frame", {
			Name = "SearchField",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 38),
			BorderSizePixel = 0,
			ZIndex = 41,
		}, panel)
		Core.bind(window, field, "BackgroundColor3", "Background")
		Core.round(field, window)
		local border = Core.stroke(field, window)
		local icon = Icons.create(window, field, "search", "TextMuted", 15)
		icon.Position = UDim2.fromOffset(11, 11)
		icon.ZIndex = 42
		local box = Core.new("TextBox", {
			Name = "Search",
			PlaceholderText = "Search features...",
			Text = "",
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(35, 0),
			Size = UDim2.new(1, -70, 1, 0),
			ZIndex = 42,
		}, field)
		Core.bind(window, box, "TextColor3", "Text")
		Core.bind(window, box, "PlaceholderColor3", "TextMuted")
		Core.bind(window, box, "Font", "Font")
		local clear = Core.new("TextButton", {
			Name = "Clear",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -33, 0, 3),
			Size = UDim2.fromOffset(32, 32),
			ZIndex = 43,
		}, field)
		local clearIcon = Icons.create(window, clear, "close", "TextMuted", 13)
		clearIcon.Position = UDim2.fromOffset(9, 9)
		clearIcon.ZIndex = 44
		window:Tooltip(clear, "Clear search", scope)
		local count = Core.text(window, panel, "Browse features", 10, "TextMuted")
		count.Position = UDim2.fromOffset(14, 53)
		count.Size = UDim2.new(1, -28, 0, 17)
		count.ZIndex = 41
		local results = Core.new("ScrollingFrame", {
			Name = "Results",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 75),
			Size = UDim2.new(1, -16, 1, -106),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
			BorderSizePixel = 0,
			ZIndex = 41,
		}, panel)
		Core.bind(window, results, "ScrollBarImageColor3", "Border")
		Core.list(results, 3)
		local hint = Core.text(window, panel, "↑ ↓ navigate    Enter open    Esc close", 10, "TextMuted")
		hint.Position = UDim2.new(0, 14, 1, -26)
		hint.Size = UDim2.new(1, -28, 0, 18)
		hint.ZIndex = 41
		window.SearchPanel, window.SearchBox, window.SearchResults = panel, box, results
		local entries, buttons = {}, {}
		local selected = 1
		local resultScope, pending
		local refresh
		local renderedQuery = ""
		local shown = 0
		local function fit()
			local width = math.max(200, math.min(360, window.Root.Size.X.Offset - 16))
			local height = math.max(
				132,
				math.min(
					106 + math.max(1, math.min(shown, 5)) * 43,
					window.Root.Size.Y.Offset - window.Theme.HeaderHeight - 16
				)
			)
			panel.Position = UDim2.new(1, -8, 0, window.Theme.HeaderHeight + 6)
			panel.Size = UDim2.fromOffset(width, height)
			hint.Text = window.IsMobile and "Tap a result to open its setting"
				or "↑ ↓ navigate    Enter open    Esc close"
		end
		window.FitSearch = fit
		local function select(index, scroll)
			selected = math.clamp(index, 1, math.max(1, shown))
			window.SearchFirst = entries[selected]
			window.SearchSelectedIndex = selected
			for i, button in ipairs(buttons) do
				Core.tween(window, button, { BackgroundTransparency = i == selected and 0 or 1 }, 0.08)
			end
			local button = buttons[selected]
			if scroll and button then
				local top = button.AbsolutePosition.Y - results.AbsolutePosition.Y + results.CanvasPosition.Y
				local bottom = top + button.AbsoluteSize.Y
				if top < results.CanvasPosition.Y then
					results.CanvasPosition = Vector2.new(0, top)
				elseif bottom > results.CanvasPosition.Y + results.AbsoluteSize.Y then
					results.CanvasPosition = Vector2.new(0, bottom - results.AbsoluteSize.Y)
				end
			end
		end
		local function activate()
			if renderedQuery ~= box.Text then
				if pending then
					pending()
					pending = nil
				end
				refresh()
			end
			local entry = entries[selected]
			if entry and entry.Object.Scope.Alive then
				window:Reveal(entry.Object)
			end
		end
		refresh = function()
			if resultScope then
				resultScope:Destroy()
			end
			resultScope = Core.scope(scope)
			entries = window:Search(box.Text)
			renderedQuery = box.Text
			buttons = {}
			shown = math.min(#entries, 40)
			clear.Visible = box.Text ~= ""
			count.Text = box.Text == "" and "Browse features"
				or (#entries .. (#entries == 1 and " result" or " results"))
			results.CanvasPosition = Vector2.zero
			for index = 1, shown do
				local entry = entries[index]
				local button = Core.new("TextButton", {
					Name = "Result",
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -4, 0, 40),
					LayoutOrder = index,
					BorderSizePixel = 0,
					ZIndex = 42,
				}, results)
				resultScope:Add(button)
				table.insert(buttons, button)
				Core.bind(window, button, "BackgroundColor3", "SurfaceActive")
				Core.round(button, window)
				local label = Core.text(window, button, entry.Name, 12, nil, true)
				Core.bind(window, label, "Font", "FontBold")
				label.Position = UDim2.fromOffset(10, 3)
				label.Size = UDim2.new(1, -33, 0, 18)
				label.ZIndex = 43
				local path = Core.text(window, button, entry.Context, 10, "TextMuted")
				path.Position = UDim2.fromOffset(10, 20)
				path.Size = UDim2.new(1, -33, 0, 15)
				path.ZIndex = 43
				local arrow = Icons.create(window, button, "chevron-right", "TextMuted", 12)
				arrow.Position = UDim2.new(1, -23, 0, 14)
				arrow.ZIndex = 43
				window:Tooltip(
					button,
					entry.Description ~= "" and entry.Description or entry.Context .. " / " .. entry.Name,
					resultScope
				)
				resultScope:Add(button.MouseEnter:Connect(function()
					select(index, false)
				end))
				resultScope:Add(button.Activated:Connect(function()
					select(index, false)
					activate()
				end))
			end
			if shown == 0 then
				local empty = Core.text(window, results, "No features found. Try a shorter search.", 11, "TextMuted")
				empty.TextWrapped = true
				empty.Size = UDim2.new(1, -12, 0, 40)
				empty.Position = UDim2.fromOffset(6, 0)
				empty.ZIndex = 42
				resultScope:Add(empty)
			end
			select(1, false)
			fit()
		end
		function window:CloseSearch()
			panel.Visible = false
			box:ReleaseFocus()
			window.Tooltips:Hide()
		end
		function window:OpenSearch()
			if not self:GetVisible() then
				return
			end
			if panel.Visible then
				self:CloseSearch()
				return
			end
			if self.OpenDropdown then
				self.OpenDropdown:SetOpen(false, true)
			end
			panel.Visible = true
			panel.GroupTransparency = 1
			refresh()
			Core.tween(window, panel, { GroupTransparency = 0 }, 0.13)
			box:CaptureFocus()
		end
		function window:HandleSearchInput(input)
			if not panel.Visible then
				return false
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				self:CloseSearch()
				return true
			end
			if input.KeyCode == Enum.KeyCode.Down then
				select(selected + 1, true)
				return true
			end
			if input.KeyCode == Enum.KeyCode.Up then
				select(selected - 1, true)
				return true
			end
			if input.KeyCode == Enum.KeyCode.Return then
				activate()
				return true
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local point = Vector2.new(input.Position.X, input.Position.Y)
				if not contains(panel, point) and not contains(window.SearchButton, point) then
					self:CloseSearch()
				end
			end
			return false
		end
		scope:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
			if pending then
				pending()
				pending = nil
			end
			if panel.Visible then
				pending = Core.delay(scope, 0.035, function()
					pending = nil
					refresh()
				end)
			end
		end))
		scope:Add(box.Focused:Connect(function()
			Core.tween(window, border, { Color = window.Theme.Accent })
		end))
		scope:Add(box.FocusLost:Connect(function(enterPressed)
			Core.tween(window, border, { Color = window.Theme.Border })
			if enterPressed and panel.Visible then
				activate()
			end
		end))
		scope:Add(clear.Activated:Connect(function()
			box.Text = ""
			box:CaptureFocus()
		end))
		fit()
	end

	return Search
end
