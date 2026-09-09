return function(require)
	local UserInputService = game:GetService("UserInputService")

	local Core = require("Core")
	local Icons = require("Icons")
	local Text = require("Text")

	local Controls = {}

	local function isSilent(options)
		if type(options) == "table" then
			if options.FireCallback ~= nil then
				return options.FireCallback == false
			elseif options.fireCallbacks ~= nil then
				return options.fireCallbacks == false
			end
			return options.Silent == true or options.silent == true
		end
		return options == true
	end

	local function call(callback, ...)
		if type(callback) ~= "function" then
			return
		end
		local success, message = xpcall(callback, debug.traceback, ...)
		if not success then
			warn("[Unknown Hub control] " .. tostring(message))
		end
	end

	local function connect(control, signal, callback)
		control.Scope:Add(signal:Connect(callback))
	end

	local function notifyChanged(control)
		if control.Registered and control.Scope.Alive then
			call(control.Window.ControlChanged, control.Window, control)
		end
	end

	local function tooltip(control, target, text)
		if control.TooltipText == false then
			return
		end
		if control.Window.Tooltip then
			control.Window:Tooltip(target, control.TooltipText or text, control.Scope)
		end
	end

	local function tint(control, instance, property, token, animate)
		local previous = instance[property]
		Core.bind(control.Window, instance, property, token)
		if animate then
			local target = instance[property]
			instance[property] = previous
			Core.tween(control.Window, instance, { [property] = target })
		end
	end

	local function button(control, parent, text, width, style)
		local normalToken = if style == "field" then "Background" else "SurfaceActive"
		local instance = Core.new("TextButton", {
			Name = "Action",
			Size = UDim2.fromOffset(width or 88, control.Window.Theme.ControlHeight),
			Text = if control.RawText then tostring(text or "") else Text.display(text),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			TextSize = control.Window.Theme.BodySize,
			Font = control.Window.Theme.Font,
		}, parent)
		Core.round(instance, control.Window)
		if style ~= "field" then
			Core.stroke(instance, control.Window)
		end
		Core.bind(control.Window, instance, "TextColor3", "Text")
		Core.bind(control.Window, instance, "Font", "Font")
		Core.bind(control.Window, instance, "TextSize", "BodySize")
		Core.bind(control.Window, instance, "BackgroundColor3", normalToken)
		connect(control, instance.MouseEnter, function()
			if not control.Disabled then
				tint(control, instance, "BackgroundColor3", "SurfaceHover", true)
			end
		end)
		connect(control, instance.MouseLeave, function()
			tint(control, instance, "BackgroundColor3", normalToken, true)
		end)
		connect(control, instance.InputBegan, function(input)
			if
				not control.Disabled
				and (
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				tint(control, instance, "BackgroundColor3", "Surface", true)
			end
		end)
		connect(control, instance.InputEnded, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				tint(control, instance, "BackgroundColor3", normalToken, true)
			end
		end)
		return instance
	end

	local function rowButton(control)
		local action = Core.new("TextButton", {
			Name = "Action",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		}, control.Header)
		control.Title.Parent = action
		local icon = control.Header:FindFirstChild("Icon")
		if icon then
			icon.Parent = action
		end
		Core.bind(control.Window, action, "BackgroundColor3", "SurfaceHover")
		connect(control, action.MouseEnter, function()
			if not control.Disabled then
				Core.tween(control.Window, action, { BackgroundTransparency = 0.55 })
			end
		end)
		connect(control, action.MouseLeave, function()
			Core.tween(control.Window, action, { BackgroundTransparency = 1 })
		end)
		connect(control, action.InputBegan, function(input)
			if
				not control.Disabled
				and (
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				Core.tween(control.Window, action, { BackgroundTransparency = 0.2 })
			end
		end)
		connect(control, action.InputEnded, function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				Core.tween(control.Window, action, { BackgroundTransparency = 1 })
			end
		end)
		return action
	end

	local function shell(container, options)
		options = options or {}
		local window = container.Window
		local scope = Core.scope(container.Scope)
		local root = Core.new("Frame", {
			Name = options.Name or options.Title or "Control",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, container.Body)
		scope:Add(root)
		Core.list(root, 0)
		local header = Core.new("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, window.Theme.ControlHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 0,
		}, root)
		local title =
			Core.text(window, header, options.Name or options.Title or "", window.Theme.BodySize, nil, options.RawText)
		Core.bind(window, title, "TextSize", "BodySize")
		local titleInset = if options.Icon then 22 else 0
		title.Position = UDim2.fromOffset(titleInset, 0)
		title.Size = UDim2.new(1, -104 - titleInset, 1, 0)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		if options.Icon then
			local icon = Icons.create(window, header, options.Icon)
			icon.Position = UDim2.new(0, 0, 0.5, -8)
		end
		local control = {
			Root = root,
			Scope = scope,
			Window = window,
			Disabled = options.Disabled == true,
			Title = title,
			Header = header,
			TitleInset = titleInset,
			Flag = options.Flag,
			ConfigKey = options.ConfigKey or options.Flag,
			ConfigId = options.ConfigKey or options.Flag,
			Configurable = options.Configurable ~= false,
			Persist = options.Persist ~= false and options.Configurable ~= false,
			TooltipText = options.Tooltip,
			RawText = options.RawText == true,
		}
		if control.ConfigKey then
			root:SetAttribute("ConfigKey", tostring(control.ConfigKey))
		end
		function control:Destroy()
			self.Scope:Destroy()
		end
		function control:SetVisible(visible)
			self.Root.Visible = visible == true
			if not self.Root.Visible and self.SetOpen then
				self:SetOpen(false)
			end
		end
		function control:GetVisible()
			return self.Scope.Alive and self.Root.Visible
		end
		function control:TrackConnection(connection)
			return self.Scope:Add(connection)
		end
		function control:TrackInstance(instance)
			return self.Scope:Add(instance)
		end
		function control:SetDisabled(disabled)
			self.Disabled = disabled == true
			self.Title.TextTransparency = if self.Disabled then 0.5 else 0
			for _, descendant in ipairs(self.Root:GetDescendants()) do
				if descendant:IsA("TextButton") then
					descendant.TextTransparency = if self.Disabled then 0.5 else 0
					descendant.Selectable = not self.Disabled
				elseif descendant:IsA("TextBox") then
					descendant.TextEditable = not self.Disabled
				end
			end
			if self._disabledChanged then
				self._disabledChanged()
			end
		end
		if options.Description then
			local description = Core.text(window, root, options.Description, window.Theme.BodySize - 1, "TextMuted")
			description.Name = "Description"
			description.Size = UDim2.new(1, 0, 0, 0)
			description.AutomaticSize = Enum.AutomaticSize.Y
			description.TextWrapped = true
			description.TextTruncate = Enum.TextTruncate.None
			description.LayoutOrder = 1
		end
		return control
	end

	local function finish(container, control, options, kind)
		options = options or {}
		control.Kind = kind
		control.Type = kind
		if kind == "Button" or kind == "Label" or kind == "Divider" then
			control.Configurable = false
			control.Persist = false
		end
		if control.Get then
			function control:GetValue()
				return self:Get()
			end
			control.GetState = control.GetValue
		end
		function control:Refresh()
			self:SetDisabled(self.Disabled)
			return self
		end
		if control.Set then
			function control:SetValue(...)
				return self:Set(...)
			end
			control.SetState = control.SetValue
			function control:Refresh(nextOptions)
				if self.SetOptions and nextOptions then
					self:SetOptions(nextOptions)
				elseif kind == "ColorPicker" then
					local color, alpha = self:Get()
					self:Set(color, alpha, true)
				else
					self:Set(self:Get(), true)
				end
				return self
			end
		end
		control:SetDisabled(control.Disabled)
		container:Register(control, options)
		control.Registered = true
		tooltip(control, control.Root, options.Tooltip or options.Description or options.Name or options.Title or kind)
		return control
	end

	local function right(instance)
		instance.AnchorPoint = Vector2.new(1, 0.5)
		instance.Position = UDim2.new(1, 0, 0.5, 0)
	end

	local function editable(control, parent, placeholder)
		local field = Core.new("TextBox", {
			Name = "Input",
			Size = UDim2.new(1, 0, 0, control.Window.Theme.ControlHeight),
			Text = "",
			PlaceholderText = if control.RawText then tostring(placeholder or "") else Text.display(placeholder),
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = control.Window.Theme.BodySize,
			Font = control.Window.Theme.Font,
			BorderSizePixel = 0,
		}, parent)
		local padding = Core.pad(field, control.Window.Theme.Gap)
		padding.PaddingTop = UDim.new(0, 0)
		padding.PaddingBottom = UDim.new(0, 0)
		Core.round(field, control.Window)
		local outline = Core.stroke(field, control.Window)
		outline.Transparency = 1
		Core.bind(control.Window, field, "Font", "Font")
		Core.bind(control.Window, field, "TextSize", "BodySize")
		Core.bind(control.Window, field, "TextColor3", "Text")
		Core.bind(control.Window, field, "PlaceholderColor3", "TextMuted")
		Core.bind(control.Window, field, "BackgroundColor3", "Background")
		connect(control, field.Focused, function()
			if control.Disabled then
				return
			end
			tint(control, field, "BackgroundColor3", "SurfaceActive", true)
			Core.bind(control.Window, outline, "Color", "Accent")
			Core.tween(control.Window, outline, { Transparency = 0.1 })
		end)
		connect(control, field.FocusLost, function()
			tint(control, field, "BackgroundColor3", "Background", true)
			Core.tween(control.Window, outline, { Transparency = 1 })
		end)
		tooltip(control, field, placeholder or "Enter a value")
		return field
	end

	function Controls.Button(container, options)
		options = options or {}
		local control = shell(container, options)
		local action
		if options.Text then
			action = button(control, control.Header, options.Text, 88)
			right(action)
		else
			control.Title.Size = UDim2.new(1, -24 - control.TitleInset, 1, 0)
			action = rowButton(control)
			local chevron = Icons.create(control.Window, action, "chevron")
			chevron.AnchorPoint = Vector2.new(1, 0.5)
			chevron.Position = UDim2.new(1, 0, 0.5, 0)
			chevron.Rotation = -90
		end
		function control:Fire()
			if self.Scope.Alive and not self.Disabled then
				call(options.Callback)
			end
		end
		connect(control, action.Activated, function()
			control:Fire()
		end)
		return finish(container, control, options, "Button")
	end

	function Controls.Toggle(container, options)
		options = options or {}
		local control = shell(container, options)
		local track = rowButton(control)
		local checkbox = Core.new("Frame", {
			Name = "Checkbox",
			Size = UDim2.fromOffset(13, 13),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			BorderSizePixel = 0,
		}, track)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, checkbox)
		local check = Core.new("Frame", {
			Name = "Checkmark",
			Size = UDim2.fromOffset(11, 10),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, checkbox)
		local checkScale = Core.new("UIScale", { Scale = 0.55 }, check)
		local checkStrokes = {}
		for index, line in ipairs({ { 1, 5, 4, 8 }, { 4, 8, 10, 2 } }) do
			local delta = Vector2.new(line[3] - line[1], line[4] - line[2])
			local stroke = Core.new("Frame", {
				Name = "Stroke" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(delta.Magnitude, 1.5),
				Position = UDim2.fromOffset((line[1] + line[3]) * 0.5, (line[2] + line[4]) * 0.5),
				Rotation = math.deg(math.atan2(delta.Y, delta.X)),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, check)
			Core.bind(control.Window, stroke, "BackgroundColor3", "Background")
			Core.new("UICorner", { CornerRadius = UDim.new(1, 0) }, stroke)
			checkStrokes[index] = stroke
		end
		control.Title.Position = UDim2.fromOffset(20 + control.TitleInset, 0)
		control.Title.Size = UDim2.new(1, -20 - control.TitleInset, 1, 0)
		local icon = track:FindFirstChild("Icon")
		if icon then
			icon.Position = UDim2.new(0, 20, 0.5, -8)
		end
		local value = false
		local function render(animate)
			local function transition(instance, properties)
				if animate and control.Window.Theme.AnimationSpeed > 0 then
					Core.tween(control.Window, instance, properties)
				else
					local tween = control.Window.Tweens[instance]
					if tween then
						tween:Cancel()
					end
					for property, target in pairs(properties) do
						instance[property] = target
					end
				end
			end
			local previousColor = checkbox.BackgroundColor3
			Core.bind(control.Window, checkbox, "BackgroundColor3", if value then "Text" else "SurfaceActive")
			local targetColor = checkbox.BackgroundColor3
			checkbox.BackgroundColor3 = previousColor
			transition(checkbox, {
				BackgroundColor3 = targetColor,
				BackgroundTransparency = if control.Disabled then 0.5 else 0,
			})
			transition(checkScale, { Scale = if value then 1 else 0.55 })
			for _, stroke in ipairs(checkStrokes) do
				transition(
					stroke,
					{ BackgroundTransparency = if not value then 1 elseif control.Disabled then 0.5 else 0 }
				)
			end
		end
		function control:Set(nextValue, silent)
			local previous = value
			value = nextValue == true
			render(not isSilent(silent))
			if previous ~= value then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(silent) then
					call(options.Callback, value)
				end
			end
		end
		function control:Get()
			return value
		end
		function control:Toggle()
			self:Set(not value)
		end
		local bindingPanel = nil
		local bindingControl = nil
		local modeControl = nil
		local bindingMode = "toggle"
		local function ensureBinding()
			if bindingControl then
				return
			end
			bindingPanel = Core.new("Frame", {
				Name = "KeybindEditor",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = false,
				LayoutOrder = 3,
			}, control.Root)
			Core.list(bindingPanel, control.Window.Theme.Gap)
			local bindingContainer = {
				Window = control.Window,
				Body = bindingPanel,
				Scope = control.Scope,
				Page = container.Page,
				Count = 0,
			}
			function bindingContainer:Register(child)
				self.Count += 1
				child.Root.LayoutOrder = self.Count
				child.Parent = control
				child.Page = control.Page or container.Page
			end
			bindingControl = Controls.Keybind(bindingContainer, {
				Name = "Shortcut",
				Persist = false,
				Configurable = false,
				Tooltip = "Press to rebind · Escape cancels",
				Changed = function()
					notifyChanged(control)
					call(options.KeybindChanged, control:GetKeybind())
				end,
				Callback = function()
					if not control.Disabled then
						control:Set(if bindingMode == "hold" then true else not value)
					end
				end,
				Released = function()
					if bindingMode == "hold" and control.Scope.Alive then
						control:Set(false)
					end
				end,
			})
			modeControl = Controls.Dropdown(bindingContainer, {
				Name = "Shortcut mode",
				Options = { "Toggle", "Hold" },
				Default = "Toggle",
				Persist = false,
				Configurable = false,
				Callback = function(mode)
					bindingMode = string.lower(mode)
					notifyChanged(control)
					call(options.KeybindChanged, control:GetKeybind())
				end,
			})
		end
		function control:SetKeybind(binding, setterOptions)
			if not binding and not bindingControl then
				return
			end
			ensureBinding()
			local previousKey = bindingControl:Get()
			local previousMode = bindingMode
			local key = if type(binding) == "table" then binding.key or binding.Key or binding.KeyCode else binding
			if type(binding) == "table" then
				bindingMode = if string.lower(tostring(binding.mode or binding.Mode)) == "hold"
					then "hold"
					else "toggle"
			end
			bindingControl:Set(key, true)
			modeControl:Set(if bindingMode == "hold" then "Hold" else "Toggle", true)
			if previousKey ~= bindingControl:Get() or previousMode ~= bindingMode then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(setterOptions) then
					call(options.KeybindChanged, self:GetKeybind())
				end
			end
		end
		function control:GetKeybind()
			local key = bindingControl and bindingControl:Get()
			return { key = if key then key.Name else "None", mode = bindingMode }
		end
		function control:GetConfigValue()
			return { Value = value, Keybind = self:GetKeybind() }
		end
		function control:SetConfigValue(config, setterOptions)
			if type(config) == "table" then
				self:SetKeybind(config.Keybind, setterOptions)
				if self.Scope.Alive then
					self:Set(config.Value, setterOptions)
				end
			else
				self:Set(config, setterOptions)
			end
		end
		function control:SetOpen(opened)
			if opened and not self.Disabled then
				ensureBinding()
				bindingPanel.Visible = true
			elseif bindingPanel then
				bindingPanel.Visible = false
				bindingControl:CancelListening()
				modeControl:SetOpen(false)
			end
		end
		control._disabledChanged = function()
			render(false)
			if bindingControl then
				bindingControl:SetDisabled(control.Disabled)
				if control.Scope.Alive then
					modeControl:SetDisabled(control.Disabled)
					if control.Disabled then
						control:SetOpen(false)
					end
				end
			end
		end
		connect(control, track.Activated, function()
			if not control.Disabled then
				control:Toggle()
			end
		end)
		connect(control, track.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and not control.Disabled then
				control:SetOpen(not bindingPanel or not bindingPanel.Visible)
			end
		end)
		control:Set(options.Default == true, true)
		if options.Keybind then
			control:SetKeybind(options.Keybind, true)
		end
		control.Checkbox = checkbox
		control.Checkmark = check
		return finish(container, control, options, "Toggle")
	end

	local function visibleInWindow(control, target)
		if not control.Scope.Alive or not control.Window.Input:IsVisible() then
			return false
		end
		local ancestor = target
		while ancestor and ancestor ~= control.Window.Gui do
			if
				ancestor:IsA("GuiObject")
				and (not ancestor.Visible or (ancestor.ClipsDescendants and ancestor.AbsoluteSize.Y <= 0))
			then
				return false
			end
			ancestor = ancestor.Parent
		end
		return ancestor == control.Window.Gui
	end

	local function pointerDrag(control, target, changed, finished)
		local dragging = nil
		local function update(input)
			if control.Disabled or not visibleInWindow(control, target) then
				dragging = nil
				return
			end
			local size = target.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				local relative = input.Position - Vector3.new(target.AbsolutePosition.X, target.AbsolutePosition.Y, 0)
				changed(math.clamp(relative.X / size.X, 0, 1), math.clamp(relative.Y / size.Y, 0, 1))
			end
		end
		connect(control, target.InputBegan, function(input)
			if control.Disabled or dragging then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = input
				update(input)
			end
		end)
		control.Window.Input:Subscribe(control.Scope, {
			Changed = function(input)
				if
					dragging
					and (
						input == dragging
						or (
							dragging.UserInputType == Enum.UserInputType.MouseButton1
							and input.UserInputType == Enum.UserInputType.MouseMovement
						)
					)
				then
					update(input)
				end
			end,
			Ended = function(input)
				if input == dragging then
					dragging = nil
					if finished then
						finished()
					end
				end
			end,
		})
		return function()
			dragging = nil
		end
	end

	local function move(control, instance, properties, immediate)
		if immediate then
			local tween = control.Window.Tweens[instance]
			if tween then
				tween:Cancel()
			end
			for property, value in pairs(properties) do
				instance[property] = value
			end
		else
			Core.tween(control.Window, instance, properties, 0.1)
		end
	end

	local function sliderTrack(control, parent, changed)
		local track = Core.new("TextButton", {
			Name = "Track",
			Text = "",
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			LayoutOrder = 3,
		}, parent)
		local rail = Core.new("Frame", {
			Name = "Rail",
			Size = UDim2.new(1, 0, 0, 3),
			Position = UDim2.new(0, 0, 0.5, -1.5),
			BorderSizePixel = 0,
		}, track)
		Core.round(rail, control.Window)
		Core.bind(control.Window, rail, "BackgroundColor3", "SurfaceActive")
		local fill = Core.new("Frame", { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, rail)
		Core.round(fill, control.Window)
		Core.bind(control.Window, fill, "BackgroundColor3", "Text")
		local thumb = Core.new("Frame", {
			Name = "Thumb",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BorderSizePixel = 0,
		}, rail)
		Core.round(thumb, control.Window)
		Core.bind(control.Window, thumb, "BackgroundColor3", "Text")
		pointerDrag(control, track, changed)
		tooltip(control, track, "Drag to adjust · Arrow keys for a precise step")
		return function(fraction, immediate)
			Core.tween(control.Window, fill, { Size = UDim2.new(fraction, 0, 1, 0) }, if immediate then 0.055 else 0.1)
			move(control, thumb, { Position = UDim2.fromScale(fraction, 0.5) }, immediate)
		end,
			track
	end

	function Controls.Slider(container, options)
		options = options or {}
		local minimum = tonumber(options.Min) or 0
		local maximum = math.max(minimum, tonumber(options.Max) or 100)
		local increment = math.max(0.000001, tonumber(options.Increment) or 1)
		local control = shell(container, options)
		control.Header.Size = UDim2.new(1, 0, 0, control.Window.Theme.BodySize + 9)
		local number = Core.text(control.Window, control.Header, "", control.Window.Theme.BodySize, "TextSecondary")
		number.Size = UDim2.new(0, 90, 1, 0)
		number.TextXAlignment = Enum.TextXAlignment.Right
		right(number)
		local value = minimum
		local render, track = sliderTrack(control, control.Root, function(fraction)
			control:Set(minimum + (maximum - minimum) * fraction, { Pointer = true })
		end)
		function control:Set(nextValue, silent)
			nextValue = tonumber(nextValue)
			if not nextValue or nextValue ~= nextValue then
				return
			end
			local previous = value
			value =
				math.clamp(minimum + math.floor((nextValue - minimum) / increment + 0.5) * increment, minimum, maximum)
			number.Text = string.format("%.4g", value) .. (options.Suffix or "")
			render(
				if maximum == minimum then 0 else (value - minimum) / (maximum - minimum),
				type(silent) == "table" and (silent.Pointer or silent.Immediate)
			)
			if previous ~= value then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(silent) then
					call(options.Callback, value)
				end
			end
		end
		function control:Get()
			return value
		end
		connect(control, track.InputBegan, function(input)
			if control.Disabled then
				return
			end
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Down then
				control:Set(value - increment)
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Up then
				control:Set(value + increment)
			end
		end)
		control:Set(options.Default or minimum, { Silent = true, Immediate = true })
		control.Track = track
		control.ValueLabel = number
		return finish(container, control, options, "Slider")
	end

	local function dropdown(container, options, multiple)
		options = options or {}
		local control = shell(container, options)
		local window = control.Window
		local gap = window.Theme.Gap
		local popupLayer = 50

		local rowHeight = window.Theme.ControlHeight
		control.Header.Size = UDim2.new(1, 0, 0, window.Theme.BodySize + 5)
		control.Title.Size = UDim2.new(1, -control.TitleInset, 1, 0)
		local action = button(control, control.Root, "", nil, "field")
		action.Size = UDim2.new(1, 0, 0, rowHeight)
		action.LayoutOrder = 2
		local function selectorText(parent)
			local label = Core.text(window, parent, "Select", window.Theme.BodySize, "TextSecondary")
			label.Position = UDim2.fromOffset(gap, 0)
			label.Size = UDim2.new(1, -gap - 24, 1, 0)
			label.TextTruncate = Enum.TextTruncate.AtEnd
			local arrow = Icons.create(window, parent, "chevron", "TextMuted")
			arrow.AnchorPoint = Vector2.new(1, 0.5)
			arrow.Position = UDim2.new(1, -gap, 0.5, 0)
			return label, arrow
		end
		local selectionLabel, chevron = selectorText(action)

		local panel = Core.new("Frame", {
			Name = "DropdownPopup",
			Size = UDim2.fromOffset(0, 0),
			Visible = false,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = popupLayer,
		}, window.Gui)
		control.Scope:Add(panel)
		Core.bind(window, panel, "BackgroundColor3", "Background")
		Core.round(panel, window)
		Core.stroke(panel, window)
		local popupScale = Core.new("UIScale", { Scale = window.ScaleObject.Scale }, panel)
		local function setLayer(instance)
			if instance:IsA("GuiObject") then
				instance.ZIndex = math.max(instance.ZIndex, popupLayer + 1)
			end
		end
		connect(control, panel.DescendantAdded, setLayer)
		local footer = Core.new("TextButton", {
			Name = "SelectedValue",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, rowHeight),
		}, panel)
		Core.bind(window, footer, "BackgroundColor3", "SurfaceHover")
		local footerLabel, footerChevron = selectorText(footer)
		local seam = Core.new(
			"Frame",
			{ Name = "Seam", Size = UDim2.new(1, -gap * 2, 0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.4 },
			panel
		)
		Core.bind(window, seam, "BackgroundColor3", "Border")
		local search = editable(control, panel, "Filter options…")
		search.Size = UDim2.new(1, -gap * 2, 0, rowHeight)
		search.Visible = false
		local list = Core.new("ScrollingFrame", {
			Name = "Options",
			Size = UDim2.new(1, 0, 0, 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
		}, panel)
		Core.bind(window, list, "ScrollBarImageColor3", "Border")
		Core.list(list, 0)
		local empty = Core.text(window, panel, "No matching options", window.Theme.BodySize, "TextMuted")
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Visible = false
		for _, descendant in ipairs(panel:GetDescendants()) do
			setLayer(descendant)
		end
		footer.ZIndex = popupLayer + 3
		for _, descendant in ipairs(footer:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex = popupLayer + 4
			end
		end
		seam.ZIndex = popupLayer + 5
		local choices = {}
		local rows = {}
		local rowMarks = {}
		local selected = {}
		local value = nil
		local opened = false
		local above = true
		local focusedChoice = nil
		local rowsScope = Core.scope(control.Scope)
		local openScope = nil
		local cancelClose = nil
		local footerHeight = rowHeight
		local listInset = footerHeight + gap
		local function sizeList()
			list.Size = UDim2.new(1, 0, 0, math.max(0, panel.Size.Y.Offset - listInset))
			empty.Size = list.Size
		end
		connect(control, panel:GetPropertyChangedSignal("Size"), sizeList)

		local function contains(candidate)
			return table.find(choices, candidate) ~= nil
		end
		local function activeChoice(choice)
			return if multiple then table.find(selected, choice) ~= nil else value == choice
		end
		local function anchorVisible()
			if not control.Scope.Alive or control.Disabled or not window:GetVisible() or not window.Gui.Enabled then
				return false
			end
			local position = action.AbsolutePosition
			local size = action.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return false
			end
			local ancestor = action
			while ancestor and ancestor ~= window.Gui do
				if ancestor:IsA("GuiObject") then
					if not ancestor.Visible then
						return false
					end
					if ancestor.ClipsDescendants or ancestor:IsA("ScrollingFrame") then
						local bounds = ancestor.AbsolutePosition
						local extent = ancestor.AbsoluteSize
						if
							position.X < bounds.X - 1
							or position.Y < bounds.Y - 1
							or position.X + size.X > bounds.X + extent.X + 1
							or position.Y + size.Y > bounds.Y + extent.Y + 1
						then
							return false
						end
					end
				end
				ancestor = ancestor.Parent
			end
			return ancestor == window.Gui
		end
		local function refresh()
			local labels = {}
			for _, choice in ipairs(choices) do
				local active = activeChoice(choice)
				if active then
					table.insert(labels, if control.RawText then tostring(choice) else Text.display(choice))
				end
				local row = rows[choice]
				if row then
					rowMarks[choice].Visible = active
					row.BackgroundTransparency = if focusedChoice == choice then 0.45 elseif active then 0.8 else 1
					Core.bind(window, row, "TextColor3", if active then "Accent" else "TextSecondary")
				end
			end
			local label = if #labels > 0 then table.concat(labels, ", ") else "Select"
			selectionLabel.Text = label
			footerLabel.Text = label
			Core.tween(window, chevron, { Rotation = if opened then 180 else 0 })
			footerChevron.Rotation = if above then 180 else 0
		end
		local function layoutPopup(animate)
			if not opened then
				return
			end
			if not anchorVisible() then
				control:SetOpen(false, true)
				return
			end
			local scale = math.max(window.ScaleObject.Scale, 0.01)
			local origin = window.Gui.AbsolutePosition
			local viewport = window.Gui.AbsoluteSize
			local position = action.AbsolutePosition - origin
			local size = action.AbsoluteSize
			local margin = 6
			local padding = gap / 2
			footerHeight = size.Y / scale
			local searchable = options.Search ~= false
				and (options.Search == true or #choices >= (options.SearchThreshold or 8) or search.Text ~= "")
			local searchHeight = if searchable then rowHeight + gap else 0
			local naturalHeight = math.max(1, math.min(#choices, options.MaxVisible or 6)) * rowHeight
				+ padding * 2
				+ searchHeight
			local spaceAbove = math.max(0, (position.Y - margin) / scale)
			local spaceBelow = math.max(0, (viewport.Y - position.Y - size.Y - margin) / scale)
			above = if options.Direction == "Down"
				then spaceBelow < naturalHeight and spaceAbove > spaceBelow
				else spaceAbove >= naturalHeight or spaceAbove >= spaceBelow
			local menuHeight = math.min(naturalHeight, if above then spaceAbove else spaceBelow)
			if menuHeight < searchHeight + rowHeight + padding * 2 then
				searchable = false
				searchHeight = 0
			end
			local totalHeight = footerHeight + menuHeight
			local width = math.min(size.X, math.max(1, viewport.X - margin * 2)) / scale
			local x = math.clamp(position.X, margin, math.max(margin, viewport.X - width * scale - margin))
			popupScale.Scale = scale
			panel.AnchorPoint = Vector2.new(0, if above then 1 else 0)
			panel.Position = UDim2.fromOffset(x, position.Y + (if above then size.Y else 0))
			footer.Position = if above then UDim2.new(0, 0, 1, -footerHeight) else UDim2.fromOffset(0, 0)
			footer.Size = UDim2.new(1, 0, 0, footerHeight)
			seam.Position = if above then UDim2.new(0, gap, 1, -footerHeight) else UDim2.fromOffset(gap, footerHeight)
			local menuTop = if above then padding else footerHeight + padding
			search.Visible = searchable
			search.Position = UDim2.fromOffset(gap, menuTop)
			list.Position = UDim2.fromOffset(0, menuTop + searchHeight)
			listInset = footerHeight + padding * 2 + searchHeight
			sizeList()
			empty.Position = list.Position
			footerChevron.Rotation = if above then 180 else 0
			control.OpenDirection = if above then "Up" else "Down"
			if animate and window.Theme.AnimationSpeed > 0 then
				panel.Size = UDim2.fromOffset(width, footerHeight)
				Core.tween(window, panel, { Size = UDim2.fromOffset(width, totalHeight) })
			else
				move(control, panel, { Size = UDim2.fromOffset(width, totalHeight) }, true)
			end
		end
		local function filterRows()
			local query = string.lower(search.Text)
			local matches = 0
			for _, choice in ipairs(choices) do
				local row = rows[choice]
				row.Visible = string.find(string.lower(tostring(choice)), query, 1, true) ~= nil
				if row.Visible then
					matches += 1
				end
			end
			empty.Visible = matches == 0
			if focusedChoice and (not rows[focusedChoice] or not rows[focusedChoice].Visible) then
				focusedChoice = nil
			end
			layoutPopup(false)
		end
		local function choose(choice)
			if not opened or control.Disabled then
				return
			end
			if multiple then
				local nextSelection = table.clone(selected)
				local index = table.find(nextSelection, choice)
				if index then
					table.remove(nextSelection, index)
				else
					table.insert(nextSelection, choice)
				end
				control:Set(nextSelection)
			else
				control:SetOpen(false)
				if control.Scope.Alive then
					control:Set(choice)
				end
			end
		end
		function control:Get()
			return if multiple then table.clone(selected) else value
		end
		function control:Set(nextValue, silent)
			local previous = self:Get()
			if multiple then
				selected = {}
				if type(nextValue) == "table" then
					for _, choice in ipairs(nextValue) do
						if contains(choice) and not table.find(selected, choice) then
							table.insert(selected, choice)
						end
					end
				end
			else
				value = if contains(nextValue) then nextValue else nil
			end
			refresh()
			local changed = if multiple then #previous ~= #selected else previous ~= value
			if multiple and not changed then
				for _, choice in ipairs(previous) do
					if not table.find(selected, choice) then
						changed = true
						break
					end
				end
			end
			if changed then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(silent) then
					call(options.Callback, self:Get())
				end
			end
		end
		function control:SetOpen(nextOpen, instant)
			if not self.Scope.Alive then
				return
			end
			nextOpen = nextOpen == true and not self.Disabled
			if nextOpen and not anchorVisible() then
				return
			end
			if cancelClose then
				cancelClose()
				cancelClose = nil
			end
			if openScope then
				openScope:Destroy()
				openScope = nil
			end
			opened = nextOpen
			if not opened then
				if window.OpenDropdown == self then
					window.OpenDropdown = nil
				end
				if window.Tooltips then
					window.Tooltips:Hide()
				end
				search:ReleaseFocus()
				refresh()
				if instant or window.Theme.AnimationSpeed == 0 or not panel.Visible then
					panel.Visible = false
					move(self, panel, { Size = UDim2.new(0, panel.Size.X.Offset, 0, footerHeight) }, true)
				else
					Core.tween(window, panel, { Size = UDim2.new(0, panel.Size.X.Offset, 0, footerHeight) })
					cancelClose = Core.delay(self.Scope, window.Theme.AnimationSpeed, function()
						cancelClose = nil
						if not opened then
							panel.Visible = false
						end
					end)
				end
				return
			end
			if window.OpenDropdown and window.OpenDropdown ~= self then
				window.OpenDropdown:SetOpen(false, true)
			end
			window.OpenDropdown = self
			if window.Tooltips then
				window.Tooltips:Hide()
			end
			panel.Visible = true
			focusedChoice = if multiple then selected[1] else value
			refresh()
			layoutPopup(not instant)
			if not opened then
				return
			end
			openScope = Core.scope(self.Scope)
			local function relayout()
				layoutPopup(false)
			end
			openScope:Add(action:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout))
			openScope:Add(action:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
			openScope:Add(action.AncestryChanged:Connect(function()
				self:SetOpen(false, true)
			end))
			openScope:Add(window.ScaleObject:GetPropertyChangedSignal("Scale"):Connect(relayout))
			openScope:Add(window.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
			openScope:Add(window.Gui:GetPropertyChangedSignal("Enabled"):Connect(relayout))
			openScope:Add(window.Root:GetPropertyChangedSignal("GroupTransparency"):Connect(function()
				if not window:GetVisible() then
					self:SetOpen(false, true)
				end
			end))
			local ancestor = action.Parent
			while ancestor and ancestor ~= window.Gui do
				if ancestor:IsA("GuiObject") then
					openScope:Add(ancestor:GetPropertyChangedSignal("Visible"):Connect(relayout))
					if ancestor.ClipsDescendants or ancestor:IsA("ScrollingFrame") then
						openScope:Add(ancestor:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
					end
				end
				ancestor = ancestor.Parent
			end
			window.Input:Subscribe(openScope, {
				Began = function(input)
					if input.KeyCode == Enum.KeyCode.Escape then
						self:SetOpen(false)
						return
					end
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.MouseButton2
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local point = input.Position
						local position = panel.AbsolutePosition
						local size = panel.AbsoluteSize
						if
							point.X < position.X
							or point.Y < position.Y
							or point.X > position.X + size.X
							or point.Y > position.Y + size.Y
						then
							self:SetOpen(false, true)
						end
						return
					end
					local focused = UserInputService:GetFocusedTextBox()
					if focused and focused ~= search then
						return
					end
					if input.KeyCode == Enum.KeyCode.Return and focusedChoice then
						choose(focusedChoice)
					elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
						local visibleChoices = {}
						for _, choice in ipairs(choices) do
							if rows[choice].Visible then
								table.insert(visibleChoices, choice)
							end
						end
						if #visibleChoices > 0 then
							local index = table.find(visibleChoices, focusedChoice)
								or (if input.KeyCode == Enum.KeyCode.Down then 0 else 1)
							index = (index - 1 + (if input.KeyCode == Enum.KeyCode.Down then 1 else -1))
									% #visibleChoices
								+ 1
							focusedChoice = visibleChoices[index]
							refresh()
							local row = rows[focusedChoice]
							local rowY = row.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
							if rowY < list.CanvasPosition.Y then
								list.CanvasPosition = Vector2.new(0, rowY)
							elseif rowY + row.AbsoluteSize.Y > list.CanvasPosition.Y + list.AbsoluteSize.Y then
								list.CanvasPosition = Vector2.new(0, rowY + row.AbsoluteSize.Y - list.AbsoluteSize.Y)
							end
						end
					end
				end,
			})
		end
		function control:GetOpen()
			return opened
		end
		function control:SetOptions(nextOptions)
			rowsScope:Destroy()
			rowsScope = Core.scope(self.Scope)
			rows = {}
			rowMarks = {}
			choices = {}
			for _, choice in ipairs(nextOptions) do
				if not table.find(choices, choice) then
					table.insert(choices, choice)
				end
			end
			for index, choice in ipairs(choices) do
				local row = Core.new("TextButton", {
					Name = tostring(choice),
					Text = if control.RawText then tostring(choice) else Text.display(choice),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextSize = window.Theme.BodySize,
					Font = window.Theme.Font,
					Size = UDim2.new(1, 0, 0, rowHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					LayoutOrder = index,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = popupLayer + 1,
				}, list)
				rowsScope:Add(row)
				local rowPadding = Core.pad(row, gap)
				rowPadding.PaddingTop = UDim.new(0, 0)
				rowPadding.PaddingBottom = UDim.new(0, 0)
				rowPadding.PaddingRight = UDim.new(0, gap + 18)
				Core.bind(window, row, "Font", "Font")
				Core.bind(window, row, "TextSize", "BodySize")
				Core.bind(window, row, "BackgroundColor3", "SurfaceHover")
				local mark = Core.text(window, row, "✓", window.Theme.BodySize, "Accent")
				mark.AnchorPoint = Vector2.new(1, 0)
				mark.Position = UDim2.fromScale(1, 0)
				mark.Size = UDim2.new(0, 14, 1, 0)
				mark.TextXAlignment = Enum.TextXAlignment.Right
				mark.ZIndex = popupLayer + 2
				rows[choice] = row
				rowMarks[choice] = mark
				rowsScope:Add(row.Activated:Connect(function()
					choose(choice)
				end))
				rowsScope:Add(row.MouseEnter:Connect(function()
					if opened then
						Core.tween(window, row, { BackgroundTransparency = 0.45 })
					end
				end))
				rowsScope:Add(row.MouseLeave:Connect(function()
					Core.tween(window, row, { BackgroundTransparency = if activeChoice(choice) then 0.8 else 1 })
				end))
				if window.Tooltip and options.Tooltip ~= false then
					window:Tooltip(row, options.Tooltip or tostring(choice), rowsScope)
				end
			end
			self:Set(self:Get(), true)
			list.CanvasPosition = Vector2.zero
			filterRows()
		end
		connect(control, search:GetPropertyChangedSignal("Text"), filterRows)
		connect(control, action.Activated, function()
			control:SetOpen(not opened)
		end)
		connect(control, footer.Activated, function()
			control:SetOpen(false)
		end)
		connect(control, footer.MouseEnter, function()
			Core.tween(window, footer, { BackgroundTransparency = 0.55 })
		end)
		connect(control, footer.MouseLeave, function()
			Core.tween(window, footer, { BackgroundTransparency = 1 })
		end)
		control.Scope:Add(function()
			if window.OpenDropdown == control then
				window.OpenDropdown = nil
			end
		end)
		control._disabledChanged = function()
			selectionLabel.TextTransparency = if control.Disabled then 0.5 else 0
			footerLabel.TextTransparency = selectionLabel.TextTransparency
			if control.Disabled then
				control:SetOpen(false, true)
			end
		end
		control.Popup = panel
		control.Selector = action
		control.OptionsList = list
		control.SearchInput = search
		tooltip(control, footer, options.Name or "Close options")
		control:SetOptions(options.Options or {})
		control:Set(options.Default, true)
		return finish(container, control, options, if multiple then "MultiDropdown" else "Dropdown")
	end

	function Controls.Dropdown(container, options)
		return dropdown(container, options, false)
	end

	function Controls.MultiDropdown(container, options)
		return dropdown(container, options, true)
	end

	function Controls.Textbox(container, options)
		options = options or {}
		local control = shell(container, options)
		control.Header.Size = UDim2.new(1, 0, 0, control.Window.Theme.BodySize + 5)
		control.Title.Size = UDim2.new(1, -control.TitleInset, 1, 0)
		local field = editable(control, control.Root, options.Placeholder)
		field.LayoutOrder = 2
		field.ClearTextOnFocus = options.ClearOnFocus == true
		local value = tostring(options.Default or "")
		local updating = false
		field.Text = value
		function control:Set(nextValue, silent)
			local text = tostring(nextValue or "")
			if options.Numeric then
				local numeric = tonumber(text)
				if not numeric or numeric ~= numeric or math.abs(numeric) == math.huge then
					return
				end
				if type(silent) ~= "table" or not silent.Typing then
					numeric =
						math.clamp(numeric, tonumber(options.Min) or -math.huge, tonumber(options.Max) or math.huge)
					text = tostring(numeric)
				end
			end
			local maximumLength = tonumber(options.MaxLength)
			if maximumLength and maximumLength >= 0 then
				local cut = utf8.offset(text, math.floor(maximumLength) + 1)
				if cut then
					text = string.sub(text, 1, cut - 1)
				end
			end
			local previous = value
			value = text
			updating = true
			field.Text = value
			updating = false
			if value ~= previous then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(silent) then
					call(options.TextChanged or options.Callback, value)
				end
			end
		end
		function control:Get()
			return value
		end
		connect(control, field:GetPropertyChangedSignal("Text"), function()
			if not updating then
				control:Set(field.Text, { Typing = true })
			end
		end)
		connect(control, field.Focused, function()
			call(options.Focused)
		end)
		connect(control, field.FocusLost, function(enterPressed)
			control:Set(field.Text)
			if control.Scope.Alive then
				updating = true
				field.Text = value
				updating = false
				call(options.FocusLost, value, enterPressed)
			end
		end)
		control:Set(value, true)
		control.Input = field
		control.InputBox = field
		return finish(container, control, options, "Textbox")
	end

	function Controls.Keybind(container, options)
		options = options or {}
		local control = shell(container, options)
		local action = button(control, control.Header, "None", 100)
		right(action)
		local value = nil
		local listening = false
		local activeKey = nil
		local function render()
			action.Text = if listening then "Press a key…" elseif value then value.Name else "None"
			Core.bind(control.Window, action, "TextColor3", if listening then "Accent" else "TextSecondary")
		end
		function control:CancelListening()
			listening = false
			if self.Window.CaptureKeybind == self then
				self.Window.CaptureKeybind = nil
			end
			render()
		end
		function control:Set(nextValue, silent)
			if type(nextValue) == "string" then
				local keyName = string.match(nextValue, "[^%.]+$") or nextValue
				local success, resolved = pcall(function()
					return Enum.KeyCode[keyName]
				end)
				if not success then
					success, resolved = pcall(function()
						return Enum.UserInputType[keyName]
					end)
				end
				nextValue = if success then resolved else nil
			end
			if nextValue == Enum.KeyCode.Unknown then
				nextValue = nil
			end
			if
				nextValue ~= nil
				and (
					typeof(nextValue) ~= "EnumItem"
					or (nextValue.EnumType ~= Enum.KeyCode and nextValue.EnumType ~= Enum.UserInputType)
				)
			then
				return
			end
			if options.KeyboardOnly and nextValue and nextValue.EnumType ~= Enum.KeyCode then
				return
			end
			local previous = value
			value = nextValue
			self:CancelListening()
			if previous ~= value then
				notifyChanged(self)
				if self.Scope.Alive and not isSilent(silent) then
					call(options.Changed, value)
				end
			end
		end
		function control:Get()
			return value
		end
		function control:SetKey(nextValue, setterOptions)
			return self:Set(nextValue, setterOptions)
		end
		function control:GetKey()
			return value
		end
		function control:Listen()
			if not self.Disabled then
				local previous = self.Window.CaptureKeybind
				if previous and previous ~= self then
					previous:CancelListening()
				end
				self.Window.CaptureKeybind = self
				listening = true
				render()
			end
		end
		control.Scope:Add(function()
			if control.Window.CaptureKeybind == control then
				control.Window.CaptureKeybind = nil
			end
		end)
		connect(control, action.Activated, function()
			control:Listen()
		end)
		control.Window.Input:Subscribe(control.Scope, {
			Began = function(input, processed)
				if control.Window.ConsumedKeybindInput == input then
					return
				elseif control.Window.ConsumedKeybindInput then
					control.Window.ConsumedKeybindInput = nil
				end
				if control.Disabled or not control.Window.Input:IsVisible() or UserInputService:GetFocusedTextBox() then
					return
				end
				if control.Window.CaptureKeybind and control.Window.CaptureKeybind ~= control then
					return
				end
				if listening then
					control.Window.ConsumedKeybindInput = input
					if input.KeyCode == Enum.KeyCode.Escape then
						control:CancelListening()
						return
					end
					if processed then
						return
					end
					if input.UserInputType == Enum.UserInputType.Keyboard then
						control:Set(input.KeyCode)
					elseif
						not options.KeyboardOnly
						and (
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.MouseButton2
							or input.UserInputType == Enum.UserInputType.MouseButton3
						)
					then
						control:Set(input.UserInputType)
					end
				elseif not processed and value and (input.KeyCode == value or input.UserInputType == value) then
					activeKey = value
					call(options.Callback, value)
				end
			end,
			Ended = function(input)
				if activeKey and (input.KeyCode == activeKey or input.UserInputType == activeKey) then
					local released = activeKey
					activeKey = nil
					call(options.Released, released)
				end
			end,
		})
		control._disabledChanged = function()
			if control.Disabled then
				control:CancelListening()
				if activeKey then
					local released = activeKey
					activeKey = nil
					call(options.Released, released)
				end
			end
		end
		control:Set(options.Default, true)
		return finish(container, control, options, "Keybind")
	end

	function Controls.Label(container, options)
		options = options or {}
		local control = shell(container, options)
		control.Header.Size = UDim2.new(1, 0, 0, control.Window.Theme.BodySize + 8)
		local valueMode = options.Value ~= nil
		local rawValue = tostring(if valueMode then options.Value else options.Name or options.Title or "")
		control.Title.Size = UDim2.new(if valueMode then 0.55 else 1, -control.TitleInset, 1, 0)
		local value = Core.text(
			control.Window,
			control.Header,
			tostring(options.Value or ""),
			control.Window.Theme.BodySize,
			"TextSecondary",
			true
		)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.fromScale(0.45, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextTruncate = Enum.TextTruncate.AtEnd
		function control:Set(nextValue)
			rawValue = tostring(nextValue or "")
			if valueMode then
				value.Text = rawValue
			else
				self.Title.Text = if control.RawText then rawValue else Text.display(rawValue)
			end
		end
		function control:Get()
			return rawValue
		end
		return finish(container, control, options, "Label")
	end

	function Controls.Divider(container, options)
		options = options or {}
		local control = shell(container, options)
		control.Header:Destroy()
		control.Title = Core.text(control.Window, control.Root, "", 1)
		control.Title.Size = UDim2.new(1, 0, 0, 1)
		control.Title.BackgroundTransparency = 0
		Core.bind(control.Window, control.Title, "BackgroundColor3", "Border")
		return finish(container, control, options, "Divider")
	end

	local function colorHex(color)
		return string.format(
			"#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5)
		)
	end

	local function parseColor(value)
		if typeof(value) == "Color3" then
			return value
		end
		if type(value) ~= "string" then
			return nil
		end
		local hex = string.gsub(value, "[%s#]", "")
		if #hex == 3 and string.match(hex, "^%x+$") then
			hex = string.gsub(hex, ".", "%0%0")
		end
		if #hex ~= 6 or not string.match(hex, "^%x+$") then
			return nil
		end
		return Color3.fromRGB(
			tonumber(string.sub(hex, 1, 2), 16),
			tonumber(string.sub(hex, 3, 4), 16),
			tonumber(string.sub(hex, 5, 6), 16)
		)
	end

	local function checkerboard(control, parent)
		for row = 0, 1 do
			for column = 0, 19 do
				local cell = Core.new("Frame", {
					Name = "Checker",
					Size = UDim2.new(0.05, 1, 0.5, 0),
					Position = UDim2.fromScale(column / 20, row / 2),
					BorderSizePixel = 0,
				}, parent)
				Core.bind(
					control.Window,
					cell,
					"BackgroundColor3",
					if (row + column) % 2 == 0 then "TextMuted" else "SurfaceActive"
				)
			end
		end
	end

	local function paletteMarker(control, parent, circle)
		local marker = Core.new("Frame", {
			Name = "Cursor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if circle then UDim2.fromOffset(8, 8) else UDim2.new(0, 2, 1, 4),
			BackgroundTransparency = if circle then 1 else 0,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, parent)
		Core.bind(control.Window, marker, "BackgroundColor3", "Text")
		local outline = Core.stroke(marker, control.Window)
		Core.bind(control.Window, outline, "Color", if circle then "Text" else "Background")
		if circle then
			Core.new("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)
		end
		return marker
	end

	function Controls.ColorPicker(container, options)
		options = options or {}
		local control = shell(container, options)
		local window = control.Window
		local gap = window.Theme.Gap
		local fieldHeight = window.Theme.ControlHeight - 4
		local paletteHeight = options.PaletteHeight or 72
		control.Title.Size = UDim2.new(1, -36 - control.TitleInset, 1, 0)
		local action = rowButton(control)
		local swatch = Core.new("Frame", {
			Name = "Swatch",
			Size = UDim2.fromOffset(22, 15),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			BorderSizePixel = 0,
		}, action)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, swatch)
		local panel = Core.new("Frame", {
			Name = "ColorPanel",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			LayoutOrder = 2,
		}, control.Root)
		local body = Core.new("Frame", {
			Name = "PaletteBody",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, panel)
		Core.list(body, gap)
		local square = Core.new("TextButton", {
			Name = "SaturationValue",
			Text = "",
			Size = UDim2.new(1, 0, 0, paletteHeight),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, body)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, square)
		local white = Core.new("Frame", {
			Name = "Saturation",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
		}, square)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, white)
		Core.new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, white)
		local black = Core.new("Frame", {
			Name = "Value",
			BackgroundColor3 = Color3.new(0, 0, 0),
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
		}, square)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, black)
		Core.new("UIGradient", { Transparency = NumberSequence.new(1, 0), Rotation = 90 }, black)
		local cursor = paletteMarker(control, square, true)
		local hueStrip = Core.new("TextButton", {
			Name = "Hue",
			Text = "",
			Size = UDim2.new(1, 0, 0, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, body)
		Core.new("UICorner", { CornerRadius = UDim.new(0, 2) }, hueStrip)
		local hueStops = {}
		for index = 0, 6 do
			table.insert(hueStops, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 1, 1)))
		end
		Core.new("UIGradient", { Color = ColorSequence.new(hueStops) }, hueStrip)
		local hueCursor = paletteMarker(control, hueStrip, false)
		local alphaStrip = nil
		local alphaOverlay = nil
		local alphaCursor = nil
		local alphaLabel = nil
		if options.Transparency ~= false then
			local alphaRow = Core.new(
				"Frame",
				{ Name = "Transparency", Size = UDim2.new(1, 0, 0, 27), BackgroundTransparency = 1, LayoutOrder = 3 },
				body
			)
			alphaLabel = Core.text(window, alphaRow, "Transparency", window.Theme.BodySize - 1, "TextSecondary")
			alphaLabel.Size = UDim2.new(1, 0, 0, 15)
			alphaStrip = Core.new("TextButton", {
				Name = "Alpha",
				Text = "",
				Size = UDim2.new(1, 0, 0, 10),
				Position = UDim2.fromOffset(0, 17),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				ClipsDescendants = true,
			}, alphaRow)
			checkerboard(control, alphaStrip)
			alphaOverlay = Core.new(
				"Frame",
				{ Name = "Color", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 2 },
				alphaStrip
			)
			Core.new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, alphaOverlay)
			alphaCursor = paletteMarker(control, alphaStrip, false)
		end
		local hexRow = Core.new(
			"Frame",
			{ Name = "HexRow", Size = UDim2.new(1, 0, 0, fieldHeight), BackgroundTransparency = 1, LayoutOrder = 4 },
			body
		)
		local hexInput = editable(control, hexRow, "#RRGGBB")
		hexInput.Size = UDim2.new(1, -56, 1, 0)
		local copy = button(control, hexRow, "⧉", 22, "field")
		copy.Size = UDim2.fromOffset(22, fieldHeight)
		copy.Position = UDim2.new(1, -50, 0, 0)
		local paste = button(control, hexRow, "▣", 22, "field")
		paste.Size = UDim2.fromOffset(22, fieldHeight)
		paste.Position = UDim2.new(1, -22, 0, 0)
		local rgbRow = Core.new(
			"Frame",
			{ Name = "RGB", Size = UDim2.new(1, 0, 0, fieldHeight), BackgroundTransparency = 1, LayoutOrder = 5 },
			body
		)
		Core.list(rgbRow, gap / 2, Enum.FillDirection.Horizontal)
		local rgbInputs = {}
		for index, channel in ipairs({ "Red", "Green", "Blue" }) do
			local field = editable(control, rgbRow, channel .. " · 0–255")
			field.Name = channel
			field.LayoutOrder = index
			field.Size = UDim2.new(1 / 3, -gap / 3, 1, 0)
			rgbInputs[index] = field
		end
		local swatches = Core.new(
			"Frame",
			{ Name = "ColorSwatches", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 6 },
			body
		)
		local presetTab = button(control, swatches, "Presets", 54, "field")
		presetTab.Size = UDim2.fromOffset(54, 16)
		presetTab.BackgroundTransparency = 1
		local recentTab = button(control, swatches, "Recent", 54, "field")
		recentTab.Size = UDim2.fromOffset(54, 16)
		recentTab.BackgroundTransparency = 1
		recentTab.Position = UDim2.fromOffset(58, 0)
		local swatchRow = Core.new("Frame", {
			Name = "Swatches",
			Size = UDim2.new(1, 0, 0, 15),
			Position = UDim2.fromOffset(0, 21),
			BackgroundTransparency = 1,
		}, swatches)
		Core.list(swatchRow, gap, Enum.FillDirection.Horizontal)
		local presets = options.Presets or { "#E8E6E3", "#0D0E13", "#79B9CC", "#627EF0", "#9569D9", "#85C49D" }
		local swatchButtons = {}
		local swatchValues = {}
		local recentMode = false
		local color = Color3.new(1, 1, 1)
		local alpha = math.clamp(tonumber(options.Alpha) or 0, 0, 1)
		local hue, saturation, brightness = 2 / 3, 0, 1
		local opened = false
		local updating = false
		local cancelSquare, cancelHue, cancelAlpha
		local function refreshSwatches()
			local source = if recentMode then window.RecentColors or {} else presets
			Core.bind(window, presetTab, "TextColor3", if recentMode then "TextMuted" else "Text")
			Core.bind(window, recentTab, "TextColor3", if recentMode then "Text" else "TextMuted")
			for index, swatchButton in ipairs(swatchButtons) do
				local entry = source[index]
				local entryColor = if type(entry) == "table" then parseColor(entry.Color) else parseColor(entry)
				swatchValues[index] = if entryColor
					then { Color = entryColor, Alpha = if type(entry) == "table" then entry.Alpha or 0 else 0 }
					else nil
				swatchButton.Visible = entryColor ~= nil
				if entryColor then
					swatchButton.BackgroundColor3 = entryColor
				end
			end
		end
		local function remember()
			window.RecentColors = window.RecentColors or {}
			local recent = window.RecentColors
			for index, entry in ipairs(recent) do
				if entry.Color == color and entry.Alpha == alpha then
					table.remove(recent, index)
					break
				end
			end
			table.insert(recent, 1, { Color = color, Alpha = alpha })
			if #recent > 6 then
				table.remove(recent)
			end
			refreshSwatches()
		end
		local function refresh(forceFields)
			swatch.BackgroundColor3 = color
			swatch.BackgroundTransparency = alpha
			square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			cursor.Position = UDim2.fromScale(saturation, 1 - brightness)
			hueCursor.Position = UDim2.fromScale(hue, 0.5)
			if alphaOverlay then
				alphaOverlay.BackgroundColor3 = color
				alphaCursor.Position = UDim2.fromScale(alpha, 0.5)
				alphaLabel.Text = "Transparency  " .. tostring(math.floor(alpha * 100 + 0.5)) .. "%"
			end
			updating = true
			if forceFields or not hexInput:IsFocused() then
				hexInput.Text = colorHex(color)
			end
			local channels = { color.R, color.G, color.B }
			for index, field in ipairs(rgbInputs) do
				if forceFields or not field:IsFocused() then
					field.Text = tostring(math.floor(channels[index] * 255 + 0.5))
				end
			end
			updating = false
		end
		local function publish(nextColor, nextAlpha, silent)
			local changed = color ~= nextColor or alpha ~= nextAlpha
			color = nextColor
			alpha = nextAlpha
			refresh(false)
			if changed then
				notifyChanged(control)
				if control.Scope.Alive and not isSilent(silent) then
					call(options.Callback, color, alpha)
				end
			end
		end
		function control:Set(nextColor, nextAlpha, silent)
			if type(nextAlpha) == "boolean" or type(nextAlpha) == "table" then
				silent = nextAlpha
				nextAlpha = nil
			end
			if type(nextColor) == "table" then
				nextAlpha = nextColor.Alpha or nextColor.Transparency or nextAlpha
				nextColor = nextColor.Color
			end
			nextColor = parseColor(nextColor)
			if not nextColor then
				return
			end
			if type(nextAlpha) ~= "number" or nextAlpha ~= nextAlpha then
				nextAlpha = alpha
			end
			local nextHue, nextSaturation, nextBrightness = nextColor:ToHSV()
			if nextSaturation > 0 then
				hue = nextHue
			end
			saturation = nextSaturation
			brightness = nextBrightness
			publish(nextColor, math.clamp(nextAlpha, 0, 1), silent)
		end
		function control:SetHSV(nextHue, nextSaturation, nextBrightness, nextAlpha, silent)
			if type(nextHue) ~= "number" or type(nextSaturation) ~= "number" or type(nextBrightness) ~= "number" then
				return
			end
			if nextHue ~= nextHue or nextSaturation ~= nextSaturation or nextBrightness ~= nextBrightness then
				return
			end
			hue = math.clamp(nextHue, 0, 1)
			saturation = math.clamp(nextSaturation, 0, 1)
			brightness = math.clamp(nextBrightness, 0, 1)
			local nextTransparency = if type(nextAlpha) == "number" and nextAlpha == nextAlpha
				then math.clamp(nextAlpha, 0, 1)
				else alpha
			publish(Color3.fromHSV(hue, saturation, brightness), nextTransparency, silent)
		end
		function control:Get()
			return color, alpha
		end
		function control:GetHSV()
			return hue, saturation, brightness, alpha
		end
		function control:GetConfigValue()
			return { Color = colorHex(color), Alpha = alpha }
		end
		function control:SetConfigValue(value, setterOptions)
			self:Set(value, setterOptions)
		end
		function control:Copy()
			window.ColorClipboard = { Color = color, Alpha = alpha }
			return colorHex(color)
		end
		function control:Paste(value)
			local entry = value or window.ColorClipboard
			if entry then
				self:Set(entry)
				if self.Scope.Alive then
					remember()
				end
			end
		end
		function control:SetOpen(nextOpen)
			opened = nextOpen == true and not self.Disabled
			if opened then
				refreshSwatches()
				refresh(true)
			else
				if cancelSquare then
					cancelSquare()
					cancelHue()
					if cancelAlpha then
						cancelAlpha()
					end
				end
				hexInput:ReleaseFocus()
				for _, field in ipairs(rgbInputs) do
					if not self.Scope.Alive then
						return
					end
					field:ReleaseFocus()
				end
			end
			if not self.Scope.Alive then
				return
			end
			local height = paletteHeight
				+ 10
				+ fieldHeight * 2
				+ 36
				+ gap * 5
				+ (if alphaStrip then 27 + gap else 0)
				+ 3
			Core.tween(window, panel, { Size = UDim2.new(1, 0, 0, if opened then height else 0) })
		end
		function control:GetOpen()
			return opened
		end
		cancelSquare = pointerDrag(control, square, function(x, y)
			control:SetHSV(hue, x, 1 - y, alpha)
		end, remember)
		cancelHue = pointerDrag(control, hueStrip, function(x)
			control:SetHSV(x, saturation, brightness, alpha)
		end, remember)
		if alphaStrip then
			cancelAlpha = pointerDrag(control, alphaStrip, function(x)
				control:SetHSV(hue, saturation, brightness, x)
			end, remember)
		end
		connect(control, square.InputBegan, function(input)
			if not control.Disabled and input.KeyCode == Enum.KeyCode.Left then
				control:SetHSV(hue, saturation - 0.01, brightness, alpha)
			elseif not control.Disabled and input.KeyCode == Enum.KeyCode.Right then
				control:SetHSV(hue, saturation + 0.01, brightness, alpha)
			elseif not control.Disabled and input.KeyCode == Enum.KeyCode.Up then
				control:SetHSV(hue, saturation, brightness + 0.01, alpha)
			elseif not control.Disabled and input.KeyCode == Enum.KeyCode.Down then
				control:SetHSV(hue, saturation, brightness - 0.01, alpha)
			end
		end)
		connect(control, hexInput.FocusLost, function()
			local parsed = parseColor(hexInput.Text)
			if parsed then
				control:Set(parsed)
				if control.Scope.Alive then
					remember()
				end
			end
			if control.Scope.Alive then
				refresh(true)
			end
		end)
		for _, field in ipairs(rgbInputs) do
			connect(control, field.FocusLost, function()
				if updating then
					return
				end
				local red, green, blue =
					tonumber(rgbInputs[1].Text), tonumber(rgbInputs[2].Text), tonumber(rgbInputs[3].Text)
				if red and green and blue and red == red and green == green and blue == blue then
					control:Set(
						Color3.fromRGB(math.clamp(red, 0, 255), math.clamp(green, 0, 255), math.clamp(blue, 0, 255))
					)
					if control.Scope.Alive then
						remember()
					end
				end
				if control.Scope.Alive then
					refresh(true)
				end
			end)
		end
		for index = 1, 6 do
			local entry = Core.new("TextButton", {
				Name = "Color" .. index,
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Size = UDim2.new(1 / 6, -gap * 5 / 6, 1, 0),
				LayoutOrder = index,
			}, swatchRow)
			Core.new("UICorner", { CornerRadius = UDim.new(0, 3) }, entry)
			swatchButtons[index] = entry
			connect(control, entry.Activated, function()
				local selected = swatchValues[index]
				if not control.Disabled and selected then
					control:Set(selected.Color, selected.Alpha)
					if control.Scope.Alive then
						remember()
					end
				end
			end)
			tooltip(control, entry, "Apply saved color")
		end
		connect(control, presetTab.Activated, function()
			if control.Disabled then
				return
			end
			recentMode = false
			refreshSwatches()
		end)
		connect(control, recentTab.Activated, function()
			if control.Disabled then
				return
			end
			recentMode = true
			refreshSwatches()
		end)
		connect(control, copy.Activated, function()
			if not control.Disabled then
				control:Copy()
			end
		end)
		connect(control, paste.Activated, function()
			if not control.Disabled then
				control:Paste()
			end
		end)
		connect(control, action.Activated, function()
			control:SetOpen(not opened)
		end)
		control._disabledChanged = function()
			if control.Disabled then
				cancelSquare()
				cancelHue()
				if cancelAlpha then
					cancelAlpha()
				end
				control:SetOpen(false)
			end
		end
		tooltip(control, square, "Saturation and brightness · Drag or use arrow keys")
		tooltip(control, hueStrip, "Choose hue")
		if alphaStrip then
			tooltip(control, alphaStrip, "Transparency · Opaque on the left, clear on the right")
		end
		tooltip(control, copy, "Copy color")
		tooltip(control, paste, "Paste color")
		tooltip(control, presetTab, "Preset colors")
		tooltip(control, recentTab, "Recently used colors")
		control:Set(options.Default or window.Theme.Accent, alpha, true)
		refreshSwatches()
		control.Palette = square
		control.HexInput = hexInput
		control.RGBInputs = rgbInputs
		return finish(container, control, options, "ColorPicker")
	end

	return Controls
end
