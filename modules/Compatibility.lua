return function(require)
	local TweenService = game:GetService("TweenService")
	local Core = require("Core")
	local Advanced = require("Advanced")
	local PlayerESP = require("PlayerESP")

	local Compatibility = {}

	local function map(values)
		local result = {}
		for _, value in ipairs(values or {}) do
			result[value] = true
		end
		return result
	end

	local function same(left, right)
		if type(left) ~= "table" or type(right) ~= "table" then
			return left == right
		end
		for key, value in pairs(left) do
			if not same(value, right[key]) then
				return false
			end
		end
		for key in pairs(right) do
			if left[key] == nil then
				return false
			end
		end
		return true
	end

	local function values(raw, choices)
		local selected = {}
		if type(raw) == "table" then
			if #raw > 0 then
				selected = map(raw)
			else
				selected = raw
			end
		elseif raw ~= nil then
			selected[raw] = true
		end
		local result = {}
		for _, choice in ipairs(choices) do
			if selected[choice] then
				table.insert(result, choice)
			end
		end
		return result
	end

	local function optionsList(source)
		if type(source) == "function" then
			local success, result = pcall(source)
			if success then
				source = result
			else
				warn("[Unknown Hub] Options provider: " .. tostring(result))
				source = {}
			end
		end
		if type(source) ~= "table" then
			source = source ~= nil and { source } or {}
		end
		local result = {}
		local function add(value)
			if type(value) == "string" then
				value = value:match("^%s*(.-)%s*$")
			end
			if
				(type(value) == "number" or type(value) == "string" and value ~= "") and not table.find(result, value)
			then
				table.insert(result, value)
			end
		end
		local indices = {}
		for key in pairs(source) do
			if type(key) == "number" then
				table.insert(indices, key)
			end
		end
		if #indices > 0 then
			table.sort(indices)
			for _, index in ipairs(indices) do
				add(source[index])
			end
		else
			for key, value in pairs(source) do
				if type(value) == "boolean" then
					if value then
						add(key)
					end
				else
					add(value)
				end
			end
			table.sort(result, function(a, b)
				return tostring(a) < tostring(b)
			end)
		end
		return result
	end

	local function normalize(container, raw)
		local options = table.clone(raw or {})
		options.Name = options.Name or options.Title or "Control"
		options.ConfigKey = options.SaveKey
			or options.ConfigKey
			or options.Flag
			or ((container._legacyPath or (container.Page and container.Page.Name) or "UI") .. "." .. options.Name)
		options.Flag = options.ConfigKey
		options.Increment = options.Step or options.Increment
		local precision = options.Precision or options.Decimals or options.Decimal
		if not options.Increment and precision then
			options.Increment = 10 ^ -math.clamp(precision, 0, 6)
		end
		options.ClearOnFocus = options.ClearTextOnFocus or options.ClearOnFocus
		options.Tooltip = options.Tooltip or options.Description or options.Name
		if type(options.Default) == "table" and options.Default.R and options.Default.G and options.Default.B then
			options.Default = Color3.fromRGB(options.Default.R, options.Default.G, options.Default.B)
		end
		return options
	end

	local function isSilent(options)
		if type(options) == "boolean" then
			return options
		end
		return not (
			type(options) == "table"
			and (options.fireCallbacks == true or options.FireCallback == true or options.Silent == false)
		)
	end

	local function proxyFor(base, kind)
		local proxy = {
			Native = base,
			_root = base.Root,
			Frame = base.Root,
			Container = base.Body or base.Root,
			Content = base.Body or base.Root,
		}
		local observers = {}
		local function notify()
			if not base.Scope.Alive then
				return
			end
			for observer in pairs(observers) do
				Core.callback(observer, proxy:Get())
			end
			if proxy._onChange then
				Core.callback(proxy._onChange, proxy:Get())
			end
		end
		setmetatable(proxy, {
			__index = function(_, key)
				if key == "Value" then
					local value = base.Get and base:Get()
					return kind == "Composite" and value.value or value
				end
				if key == "Values" then
					local value = base.Get and base:Get()
					return value and map(kind == "Composite" and value.selections or value)
				end
				if key == "Enabled" and kind == "Composite" then
					return base:Get().enabled
				end
				if key == "_destroyed" then
					return not base.Scope.Alive
				end
				local member = base[key]
				if type(member) == "function" then
					return function(first, ...)
						local result
						if first == proxy then
							result = member(base, ...)
						else
							result = member(base, first, ...)
						end
						return result == base and proxy or result
					end
				end
				return member
			end,
		})
		function proxy:Get()
			if base.Get then
				return base:Get()
			end
			return nil
		end
		function proxy:Set(value, setOptions)
			if not base.Scope.Alive then
				return self
			end
			if kind == "Textbox" and type(value) == "table" then
				value = value.Text or value.text or value.Value or value.value or ""
			end
			if kind == "ColorPicker" and type(value) == "table" then
				value = Color3.fromRGB(value.R or 255, value.G or 255, value.B or 255)
			end
			if base.Set then
				base:Set(value, isSilent(setOptions))
			end
			return self
		end
		if base.Set then
			local nativeSet = base.Set
			function base:Set(...)
				local result = table.pack(nativeSet(self, ...))
				notify()
				return table.unpack(result, 1, result.n)
			end
		end
		proxy.GetValue = proxy.Get
		proxy.GetState = proxy.Get
		proxy.SetValue = proxy.Set
		proxy.SetState = proxy.Set
		function proxy:Observe(callback)
			observers[callback] = true
			return function()
				observers[callback] = nil
			end
		end
		function proxy:Destroy()
			base:Destroy()
			table.clear(observers)
			self._onChange = nil
		end
		function proxy:SetVisible(visible)
			if base.SetVisible then
				base:SetVisible(visible ~= false)
			else
				base.Root.Visible = visible ~= false
			end
			return self
		end
		function proxy:GetVisible()
			return base.Scope.Alive and base.Root.Visible
		end
		function proxy:SetDisabled(disabled)
			if base.SetDisabled then
				base:SetDisabled(disabled)
			end
			return self
		end
		function proxy:Refresh()
			if base.Refresh then
				base:Refresh()
			end
			return self
		end
		function proxy:TrackConnection(connection, key)
			self._tracked = self._tracked or {}
			if key and self._tracked[key] then
				local previous = self._tracked[key]
				base.Scope.Resources[previous] = nil
				if typeof(previous) == "RBXScriptConnection" then
					previous:Disconnect()
				else
					previous:Destroy()
				end
			end
			if key then
				self._tracked[key] = connection
			end
			return base.Scope:Add(connection)
		end
		function proxy:TrackInstance(instance, key)
			self._tracked = self._tracked or {}
			if key and self._tracked[key] then
				local previous = self._tracked[key]
				base.Scope.Resources[previous] = nil
				if typeof(previous) == "RBXScriptConnection" then
					previous:Disconnect()
				else
					previous:Destroy()
				end
			end
			if key then
				self._tracked[key] = instance
			end
			return base.Scope:Add(instance)
		end
		if kind == "Textbox" then
			proxy.GetText = proxy.Get
			proxy.SetText = function(first, second)
				return proxy:Set(if first == proxy then second else first)
			end
		end
		base.Scope:Add(function()
			table.clear(observers)
			proxy._onChange = nil
			if proxy._tracked then
				table.clear(proxy._tracked)
			end
		end)
		return proxy, notify
	end

	local function legacyControl(container, kind, raw)
		local options = normalize(container, raw)
		local callback = options.Callback
		local proxy, notify
		options.Callback = function(...)
			Core.callback(callback, ...)
		end
		local base = container[kind](container, options)
		proxy, notify = proxyFor(base, kind)
		return proxy
	end

	local function dropdown(container, raw, multiple)
		local options = normalize(container, raw)
		local provider = options.Options or options.Items or {}
		local choices = optionsList(provider)
		local allOption = options.ChoiceAll or options.SelectAll or options.AllChoice or options.ChoiceAllOption
		local allLabel
		if multiple and allOption then
			allLabel = type(allOption) == "table"
					and (allOption.Label or allOption.Name or allOption.Text or allOption.Value)
				or (allOption ~= true and tostring(allOption) or "All")
		end
		local function displayOptions()
			local result = table.clone(choices)
			if allLabel then
				table.insert(result, 1, allLabel)
			end
			return result
		end
		options.Options = displayOptions()
		options.Default = multiple and values(options.Default or options.Selected, choices)
			or (options.Default or choices[1])
		local callback = options.Callback
		local base, proxy, notify
		local lastSelection = multiple and table.clone(options.Default) or nil
		options.Callback = function(value)
			if multiple and allLabel and table.find(value, allLabel) then
				value = #lastSelection == #choices and {} or table.clone(choices)
				base:Set(value, true)
			end
			if multiple then
				lastSelection = table.clone(value)
			end
			if multiple then
				Core.callback(callback, table.clone(value), map(value))
			else
				Core.callback(callback, value)
			end
		end
		base = container[multiple and "MultiDropdown" or "Dropdown"](container, options)
		proxy, notify = proxyFor(base, multiple and "MultiDropdown" or "Dropdown")
		local originalSet = proxy.Set
		function proxy:Set(value, setOptions)
			if multiple then
				value = values(value, choices)
				lastSelection = table.clone(value)
			elseif not table.find(choices, value) then
				value = choices[1]
			end
			return originalSet(self, value, setOptions)
		end
		proxy.GetSelection = proxy.Get
		proxy.GetSelections = proxy.Get
		proxy.SetSelection = function(first, second)
			return proxy:Set(if first == proxy then second else first)
		end
		proxy.SetText = proxy.SetSelection
		proxy.SetValues = proxy.SetSelection
		proxy.SetValue = proxy.SetSelection
		proxy.SetState = proxy.Set
		function proxy:SetOptions(first, second)
			if not base.Scope.Alive then
				return self
			end
			provider = first
			choices = optionsList(provider)
			if not base.Scope.Alive then
				return self
			end
			base:SetOptions(displayOptions())
			self:Set(second ~= nil and second or self:Get())
			return self
		end
		local setOptions = proxy.SetOptions
		proxy.SetOptions = function(first, second, third)
			if first == proxy then
				return setOptions(proxy, second, third)
			end
			return setOptions(proxy, first, second)
		end
		proxy.RefreshOptions = function()
			return setOptions(proxy, provider, proxy:Get())
		end
		if multiple then
			proxy.SetSelected = function(first, second, third)
				local name, state = first, second
				if first == proxy then
					name, state = second, third
				end
				local selected = map(base:Get())
				selected[name] = state ~= false or nil
				return proxy:Set(selected)
			end
			proxy.Select = proxy.SetSelected
		end
		return proxy
	end

	local function combined(container, raw, kind)
		local options = normalize(container, raw)
		local host = container:Custom({ Name = options.Name, Height = 0, AutomaticSize = true, Searchable = false })
		host._legacyPath = options.ConfigKey
		Core.list(host.Body, container.Window.Theme.Gap / 2)
		local enabled = options.Enabled
		if enabled == nil then
			enabled = options.DefaultToggle
		end
		if enabled == nil then
			enabled = kind ~= "MultiDropdown"
		end
		local syncing = true
		local slider, check
		local function fireValue(markDirty)
			if syncing or not host.Scope.Alive then
				return
			end
			if markDirty ~= false and container.Window.ControlChanged then
				container.Window:ControlChanged(host)
			end
			if kind == "Slider" then
				Core.callback(options.Callback or options.OnSliderChange, slider:Get())
			elseif kind == "Dropdown" then
				Core.callback(options.Callback, slider:Get(), check:Get())
			else
				local list = slider:Get()
				Core.callback(options.Callback, check:Get(), list, map(list))
			end
		end
		local itemOptions = table.clone(options)
		itemOptions.Persist = false
		itemOptions.Callback = fireValue
		if kind == "Slider" then
			slider = legacyControl(host, kind, itemOptions)
		else
			slider = dropdown(host, itemOptions, kind == "MultiDropdown")
		end
		check = host:Toggle({
			Name = options.ToggleName or "Enabled",
			Default = enabled,
			Persist = false,
			Tooltip = options.Tooltip,
			Callback = function(value)
				if syncing then
					return
				end
				if kind == "Slider" and container.Window.ControlChanged then
					container.Window:ControlChanged(host)
				end
				Core.callback(options.OnToggle or options.OnToggleChange, value)
				if kind ~= "Slider" then
					fireValue()
				end
			end,
		})
		syncing = false

		if kind ~= "MultiDropdown" or options.Inline or options.Compact or options.OneLine then
			check.Header.Parent = slider.Native.Header
			check.Scope:Add(check.Header)
			check.Header.Position = UDim2.new(1, -28, 0, 0)
			check.Header.Size = UDim2.fromOffset(28, container.Window.Theme.ControlHeight)
			check.Title.Visible = false
			check.Root.Visible = false
			local action = slider.Native.Header:FindFirstChild("Action")
			if action then
				action.Position = UDim2.new(1, -34, 0.5, 0)
			end
			if kind == "Slider" then
				for _, child in ipairs(slider.Native.Header:GetChildren()) do
					if child:IsA("TextLabel") and child ~= slider.Native.Title then
						child.Position = UDim2.new(1, -34, 0.5, 0)
					end
				end
			end
			slider.Native.Title.Size = UDim2.new(1, kind == "Slider" and -120 or -162, 1, 0)
		end
		function host:Get()
			if kind == "MultiDropdown" then
				return { selections = slider:Get(), toggled = check:Get(), enabled = check:Get() }
			end
			return { value = slider:Get(), enabled = check:Get() }
		end
		function host:Set(value, silent)
			if not self.Scope.Alive or type(value) ~= "table" then
				return
			end
			local previous = self:Get()
			syncing = true
			local selected = value.value
			if kind == "MultiDropdown" then
				selected = value.selections or value.selected
			end
			if selected ~= nil then
				slider:Set(selected)
			end
			local nextEnabled = value.enabled
			if value.toggled ~= nil then
				nextEnabled = value.toggled
			end
			if nextEnabled ~= nil then
				check:Set(nextEnabled, true)
			end
			syncing = false
			if same(previous, self:Get()) then
				return
			end
			if container.Window.ControlChanged then
				container.Window:ControlChanged(self)
			end
			if not silent then
				fireValue(false)
				if self.Scope.Alive and nextEnabled ~= nil then
					Core.callback(options.OnToggle or options.OnToggleChange, check:Get())
				end
			end
		end
		function host:SetDisabled(value)
			slider:SetDisabled(value)
			check:SetDisabled(value)
			self.Disabled = value == true
		end
		if container.Window.RegisterControl then
			container.Window:RegisterControl(host, options, string.lower(kind) .. "toggle")
		end
		local proxy = proxyFor(host, "Composite")
		proxy.Multi = kind == "MultiDropdown" and slider or nil
		proxy.Dropdown = kind == "Dropdown" and slider or nil
		proxy.Slider = kind == "Slider" and slider or nil
		proxy.Toggle = check
		proxy.GetSliderValue = function()
			return slider:Get()
		end
		proxy.GetSelection = proxy.GetSliderValue
		proxy.GetSelections = proxy.GetSliderValue
		proxy.SetSliderValue = function(first, second)
			local value = if first == proxy then second else first
			return proxy:Set(kind == "MultiDropdown" and { selections = value } or { value = value })
		end
		proxy.SetSelection = proxy.SetSliderValue
		proxy.SetValues = proxy.SetSliderValue
		proxy.GetToggleState = function()
			return check:Get()
		end
		proxy.SetToggleState = function(first, second)
			return proxy:Set({ enabled = if first == proxy then second else first })
		end
		if kind == "MultiDropdown" then
			proxy.GetState = proxy.GetToggleState
			proxy.SetState = proxy.SetToggleState
			proxy.SetValue = proxy.SetSelection
		end
		if kind ~= "Slider" then
			proxy.SetOptions = function(first, second, third)
				local previous = host:Get()
				if first == proxy then
					slider:SetOptions(second, third)
				else
					slider:SetOptions(first, second)
				end
				if not same(previous, host:Get()) and container.Window.ControlChanged then
					container.Window:ControlChanged(host)
				end
				return proxy
			end
			proxy.RefreshOptions = function()
				local previous = host:Get()
				slider:RefreshOptions()
				if not same(previous, host:Get()) and container.Window.ControlChanged then
					container.Window:ControlChanged(host)
				end
				return proxy
			end
		end
		if kind == "MultiDropdown" then
			proxy.SetSelected = function(first, second, third)
				local name = if first == proxy then second else first
				local enabled = if first == proxy then third else second
				local selected = map(slider:Get())
				selected[name] = enabled ~= false or nil
				return proxy:Set({ selections = selected })
			end
			proxy.Select = proxy.SetSelected
		end
		return proxy
	end

	local function decorate(container, path)
		container._legacyPath = path or container._legacyPath
		container.Frame = container.Root
		container.Container = container.Body
		container.Content = container.Body
		container._root = container.Root
		container._win = container.Window
		return container
	end

	function Compatibility.install(Library, WindowClass, ContainerClass)
		if Library._compatibilityInstalled then
			return
		end
		Library._compatibilityInstalled = true
		local selectPage = WindowClass.SelectPage
		function WindowClass:SelectPage(page)
			selectPage(self, page)
			self.ActiveMenu = self.SelectedPage
		end
		WindowClass.SelectMenu = WindowClass.SelectPage
		local deselectPage = WindowClass.DeselectPage
		function WindowClass:DeselectPage()
			deselectPage(self)
			self.ActiveMenu = nil
		end
		local constructors = {
			AddButton = "Button",
			AddInputBox = "Textbox",
			AddSlider = "Slider",
			AddColorPicker = "ColorPicker",
			AddLabel = "Label",
			AddDivider = "Divider",
			AddKeybind = "Keybind",
		}
		for legacy, modern in pairs(constructors) do
			ContainerClass[legacy] = function(self, options)
				return legacyControl(self, modern, options)
			end
		end
		function ContainerClass:AddDropdown(options)
			return dropdown(self, options, false)
		end
		function ContainerClass:AddMultiDropdown(options)
			return dropdown(self, options, true)
		end
		function ContainerClass:AddSliderToggle(options)
			return combined(self, options, "Slider")
		end
		function ContainerClass:AddDropdownToggle(options)
			return combined(self, options, "Dropdown")
		end
		function ContainerClass:AddMultiDropdownToggle(options)
			return combined(self, options, "MultiDropdown")
		end
		function ContainerClass:AddHitboxPreview(raw)
			local options = normalize(self, raw)
			local base = Advanced.HitboxPreview(self, options)
			base.Persist = options.Persist ~= false
			base.Configurable = true
			if self.Window.RegisterControl then
				self.Window:RegisterControl(base, options, "hitbox")
			end
			return proxyFor(base, "Hitbox")
		end
		function ContainerClass:AddToggle(raw)
			local options = normalize(self, raw)
			local host =
				self:Custom({ Name = options.Name .. " group", Height = 0, AutomaticSize = true, Searchable = false })
			host._legacyPath = options.ConfigKey
			Core.list(host.Body, self.Window.Theme.Gap / 2)
			local toggle = legacyControl(host, "Toggle", options)
			toggle._root = host.Root
			toggle.Frame = host.Root
			local branch
			local function children()
				if not branch then
					branch = decorate(
						host:Custom({ Name = "Options", Height = 0, AutomaticSize = true, Searchable = false }),
						options.ConfigKey
					)
					Core.list(branch.Body, self.Window.Theme.Gap / 2)
					Core.pad(branch.Body, 6)
					branch.Root.Visible = toggle:Get()
					branch.Reveal = function()
						toggle.Native:Set(true, true)
						branch.Root.Visible = true
					end
				end
				return branch
			end
			for _, name in ipairs({
				"AddColorPicker",
				"AddDropdown",
				"AddMultiDropdown",
				"AddToggle",
				"AddInputBox",
				"AddButton",
				"AddSlider",
				"AddSliderToggle",
				"AddDropdownToggle",
				"AddMultiDropdownToggle",
				"AddHitboxPreview",
				"AddKeybind",
			}) do
				toggle[name] = function(_, childOptions)
					local target = children()
					return target[name](target, childOptions)
				end
			end
			toggle.Native.Scope:Add(toggle:Observe(function()
				if branch then
					branch.Root.Visible = toggle:Get()
				end
			end))
			local originalDestroy = toggle.Destroy
			function toggle:Destroy()
				originalDestroy(self)
				host:Destroy()
			end
			function toggle:SetVisible(visible)
				host.Root.Visible = visible ~= false
				return self
			end
			function toggle:GetVisible()
				return host.Scope.Alive and host.Root.Visible
			end
			return toggle
		end
		function ContainerClass:TrackConnection(resource, key)
			if key then
				if not self._legacyTracked then
					self._legacyTracked = {}
					self.Scope:Add(function()
						table.clear(self._legacyTracked)
					end)
				end
				local previous = self._legacyTracked[key]
				if previous then
					self.Scope.Resources[previous] = nil
					if typeof(previous) == "RBXScriptConnection" then
						previous:Disconnect()
					else
						previous:Destroy()
					end
				end
				self._legacyTracked[key] = resource
			end
			return self.Scope:Add(resource)
		end
		ContainerClass.TrackInstance = ContainerClass.TrackConnection
		function ContainerClass:AddSection(options)
			options = options or {}
			local name = options.Name or options.Title or "Section"
			local target = self
			if self._legacyColumns then
				target = self._legacyColumns[math.clamp(options.Column or 1, 1, #self._legacyColumns)] or self
			end
			local section = decorate(
				target:Card({
					Title = name,
					Icon = options.Icon,
					Description = options.Description,
					Collapsible = options.Collapsible,
					Expanded = options.Expanded,
				}),
				(self._legacyPath or self.Name or "Menu") .. "." .. name
			)
			section._title = section.Root:FindFirstChild("Header"):FindFirstChild("Text")
			section.TitleLabel = section._title
			self.Sections = self.Sections or {}
			table.insert(self.Sections, section)
			section.Scope:Add(function()
				local index = table.find(self.Sections, section)
				if index then
					table.remove(self.Sections, index)
				end
			end)
			return section
		end
		function ContainerClass:AddWidePanel(options)
			options = options or {}
			local host = self:Custom({
				Name = options.Name or options.Title or "Panel",
				Height = 0,
				AutomaticSize = true,
				Searchable = false,
			})
			Core.list(host.Body, 0)
			local padding = Core.pad(host.Body, math.max(0, tonumber(options.SidePadding) or 0))
			padding.PaddingTop = UDim.new(0, math.max(0, tonumber(options.TopPadding) or 0))
			padding.PaddingBottom = UDim.new(0, 0)
			local card = host:Card({
				Title = options.Name or options.Title or "Panel",
				Icon = options.Icon,
				Collapsible = false,
			})
			local custom = card:Custom({ Height = math.max(36, (options.Height or 220) - 34) })
			card.Container = custom.Body
			card.Content = custom.Body
			card.Frame = card.Root
			card.TitleLabel = card.Root:FindFirstChild("Header"):FindFirstChild("Text")
			function card:RefreshLayout()
				self:SetExpanded(true)
				return self
			end
			local destroyCard = card.Destroy
			function card:Destroy()
				destroyCard(self)
				host:Destroy()
			end
			return card
		end
		function ContainerClass:AddStatsGraph(options)
			return Advanced.StatsGraph(self, options)
		end
		function WindowClass:AddMenu(options)
			options = options or {}
			local name = options.Name or options.Title or "Menu"
			local page = self.Overview and self.Overview.Page
			if string.lower(tostring(name)) ~= "overview" or not page or not page.Scope.Alive then
				page = self:Page({
					Name = name,
					Icon = options.Icon,
					Group = options.Group or "workspace",
					Subtitle = options.Subtitle,
					Disabled = options.Disabled,
				})
			end
			page = decorate(page, name)
			if page._legacyColumns then
				return page
			end
			local count = math.clamp(math.floor(tonumber(options.Columns) or 3), 1, 6)
			page._legacyColumns = { page:Columns({ Count = count, Breakpoint = options.Breakpoint or 440 }) }
			page._columns = {}
			for _, column in ipairs(page._legacyColumns) do
				table.insert(page._columns, column.Body)
			end
			page.Sections = {}
			page._page = page.Root
			page.Button = page.Navigation
			page.Scope:Add(page.Root.ChildAdded:Connect(function(child)
				if page.Scope.Alive and child:IsA("GuiObject") and child.LayoutOrder == 0 then
					page.Count += 1
					child.LayoutOrder = page.Count
				end
			end))
			self.Menus = self.Menus or {}
			table.insert(self.Menus, page)
			page.Scope:Add(function()
				local index = table.find(self.Menus, page)
				if index then
					table.remove(self.Menus, index)
				end
			end)
			return page
		end
		function Library:CreateWindow(raw)
			local options = table.clone(raw or {})
			options.Name = options.Name or "Unknown Hub"
			options.Title = options.Title or "Unknown Hub"
			options._Legacy = true
			options.MinWidth = options.MinWidth or (self.Config and self.Config.MinWindowWidth)
			options.MinHeight = options.MinHeight or (self.Config and self.Config.MinWindowHeight)
			options.DeveloperKey = options.DeveloperKey or options.DevKey or (self.Config and self.Config.DeveloperKey)
			options.ToggleKey = options.Keybind or options.ToggleKey or (self.Config and self.Config.ToggleKey)
			options.Size = options.Size
				or UDim2.fromOffset(
					self.Config and self.Config.WindowWidth or 760,
					self.Config and self.Config.WindowHeight or 500
				)
			local window = self.new(options)
			window.Legacy = true
			window.Menus = window.Menus or {}
			self._activeWindow = window
			window.Scope:Add(function()
				if self._activeWindow == window then
					self._activeWindow = nil
				end
			end)
			return window
		end
		Library.AddPlayerESPSection = function(first, second, third)
			if first == Library then
				return PlayerESP.section(second, third)
			end
			return PlayerESP.section(first, second)
		end
		Library.CreatePlayerESPSection = Library.AddPlayerESPSection
		function ContainerClass:AddPlayerESPSection(options)
			return PlayerESP.section(self, options)
		end
		ContainerClass.CreatePlayerESPSection = ContainerClass.AddPlayerESPSection
		Library.Motion = {
			Smooth = { 1, 6 },
			Hover = { 0.9, 8 },
			Press = { 0.8, 11 },
			Select = { 0.82, 9 },
			Open = { 0.72, 8 },
			Close = { 0.92, 8 },
			Snappy = { 0.8, 8 },
			Bouncy = { 0.5, 6 },
			Gentle = { 1, 4 },
			Quick = { 1, 12 },
			Drag = { 1, 16 },
			Popup = { 0.7, 7 },
			Responsive = { 0.85, 14 },
		}
		Library.Springs = Library.Motion
		local animations = {}
		local function releaseAnimation(instance, property, record)
			if record.Completed then
				record.Completed:Disconnect()
			end
			if record.Destroying then
				record.Destroying:Disconnect()
			end
			record.Tween:Cancel()
			record.Tween:Destroy()
			local active = animations[instance]
			if active and active[property] == record then
				active[property] = nil
				if not next(active) then
					animations[instance] = nil
				end
			end
		end
		function Library:Stop(instance, property)
			local active = animations[instance]
			if not active then
				return
			end
			for name, record in pairs(active) do
				if not property or property == name then
					releaseAnimation(instance, name, record)
				end
			end
			if not next(active) then
				animations[instance] = nil
			end
		end
		function Library:Animate(instance, token, properties)
			local settings = self.Motion[token] or self.Motion.Smooth
			for property, value in pairs(properties or {}) do
				self:Stop(instance, property)
				local tween = TweenService:Create(
					instance,
					TweenInfo.new(
						math.clamp(settings[1] / settings[2], 0.05, 0.4),
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out
					),
					{ [property] = value }
				)
				local active = animations[instance] or {}
				animations[instance] = active
				local record = { Tween = tween }
				active[property] = record
				record.Destroying = instance.Destroying:Connect(function()
					self:Stop(instance)
				end)
				record.Completed = tween.Completed:Connect(function()
					releaseAnimation(instance, property, record)
				end)
				tween:Play()
			end
		end
		Library.Spring = Library.Animate
		Library.Cleaner = {
			new = function()
				local cleaner = { Tasks = {} }
				local function release(record)
					if record.Method then
						record.Value[record.Method](record.Value)
					elseif type(record.Value) == "function" then
						record.Value()
					elseif typeof(record.Value) == "RBXScriptConnection" then
						record.Value:Disconnect()
					else
						record.Value:Destroy()
					end
				end
				function cleaner:Remove(key)
					local record = self.Tasks[key]
					if record then
						self.Tasks[key] = nil
						release(record)
					end
				end
				function cleaner:Add(value, method, key)
					key = key or value
					self:Remove(key)
					self.Tasks[key] = { Value = value, Method = method }
					return value
				end
				function cleaner:Cleanup()
					local tasks = self.Tasks
					self.Tasks = {}
					for _, record in pairs(tasks) do
						release(record)
					end
				end
				cleaner.Destroy = cleaner.Cleanup
				return cleaner
			end,
		}
		local destroy = Library.Destroy
		function Library:Destroy()
			for instance in pairs(animations) do
				self:Stop(instance)
			end
			destroy(self)
		end
	end

	return Compatibility
end
