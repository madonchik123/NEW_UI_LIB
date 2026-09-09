return function(require)
	local Core = require("Core")

	local Advanced = {}

	local function tooltip(window, instance, text, scope)
		if window.Tooltip then
			window:Tooltip(instance, text, scope)
		end
	end

	local function selectedMap(values)
		local selected = {}
		if type(values) ~= "table" then
			return selected
		end
		if #values > 0 then
			for _, value in ipairs(values) do
				selected[value] = true
			end
		else
			for value, enabled in pairs(values) do
				if enabled then
					selected[value] = true
				end
			end
		end
		return selected
	end

	function Advanced.StatsGraph(container, options)
		options = table.clone(options or {})
		local window = container.Window
		local target = container
		local host
		if options.TopPadding ~= nil or options.SidePadding ~= nil then
			host = container:Custom({
				Name = options.Name or options.Title or "Stats",
				Height = 0,
				AutomaticSize = true,
				Searchable = false,
			})
			Core.list(host.Body, 0)
			local padding = Core.pad(host.Body, math.max(0, tonumber(options.SidePadding) or 0))
			padding.PaddingTop = UDim.new(0, math.max(0, tonumber(options.TopPadding) or 0))
			padding.PaddingBottom = UDim.new(0, 0)
			target = host
		end
		local card = target:Card({
			Title = options.Name or options.Title or "Stats",
			Icon = options.Icon or "version",
			Description = options.Description,
			Collapsible = false,
		})
		local metrics = options.Metrics or { "Status", "Found", "Matched", "Polls", "Last ms" }
		local heading = card:Label({ Name = options.Subtitle or "Live statistics" })
		local metricRow = card:Row({ Name = "Metrics" })
		local metricLabels = {}
		for _, name in ipairs(metrics) do
			metricLabels[name] = metricRow:Label({ Name = "—", Description = tostring(name) })
		end
		local graph = card:Custom({
			Name = options.SeriesName or "History",
			Height = math.max(64, (options.Height or 248) - 132),
		})
		local plot = Core.new("Frame", {
			Name = "Plot",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -10, 1, -24),
			Position = UDim2.fromOffset(5, 4),
			ClipsDescendants = true,
		}, graph.Body)
		Core.stroke(plot, window)
		local caption = Core.text(window, graph.Body, "No samples", 10, "TextMuted")
		caption.Position = UDim2.new(0, 0, 1, -18)
		caption.Size = UDim2.new(1, 0, 0, 18)
		local lines = {}
		local control = {
			Root = card.Root,
			Frame = card.Root,
			Panel = card,
			Container = card.Body,
			Content = card.Body,
			Scope = card.Scope,
			Window = window,
			Samples = {},
			MaxSamples = math.clamp(math.floor(tonumber(options.MaxSamples) or 32), 2, 512),
			Status = tostring(options.Status or "Idle"),
		}
		local function redraw()
			if not card.Scope.Alive then
				return
			end
			local peak = 1
			for _, sample in ipairs(control.Samples) do
				peak = math.max(peak, sample.Value)
			end
			local size = plot.AbsoluteSize / window.ScaleObject.Scale
			for index = 1, math.max(#control.Samples - 1, #lines) do
				local line = lines[index]
				if index < #control.Samples then
					if not line then
						line = Core.new(
							"Frame",
							{ Name = "Segment", AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0 },
							plot
						)
						if options.AccentColor then
							line.BackgroundColor3 = options.AccentColor
						else
							Core.bind(window, line, "BackgroundColor3", "Accent")
						end
						lines[index] = line
					end
					local first = Vector2.new(
						(index - 1) / (#control.Samples - 1) * size.X,
						(1 - control.Samples[index].Value / peak) * math.max(1, size.Y - 4) + 2
					)
					local last = Vector2.new(
						index / (#control.Samples - 1) * size.X,
						(1 - control.Samples[index + 1].Value / peak) * math.max(1, size.Y - 4) + 2
					)
					local delta = last - first
					line.Position = UDim2.fromOffset((first.X + last.X) / 2, (first.Y + last.Y) / 2)
					line.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
					line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
					line.Visible = true
				elseif line then
					line.Visible = false
				end
			end
			local latest = control.Samples[#control.Samples]
			caption.Text = string.format(
				"%s   ·   %d samples   ·   Now %g   ·   Peak %g",
				options.SeriesName or "History",
				#control.Samples,
				latest and latest.Value or 0,
				latest and peak or 0
			)
		end
		function control:SetStats(stats)
			if not self.Scope.Alive or type(stats) ~= "table" then
				return self
			end
			if stats.Subtitle ~= nil then
				heading:Set(stats.Subtitle)
			end
			if stats.SeriesName ~= nil then
				options.SeriesName = tostring(stats.SeriesName)
			end
			if stats.Status ~= nil then
				self.Status = tostring(stats.Status)
			end
			for name, label in pairs(metricLabels) do
				local value = stats[name]
				if value == nil then
					value = stats[tostring(name):gsub("%s+", "")]
				end
				if value ~= nil then
					label:Set(tostring(value))
				end
			end
			redraw()
			return self
		end
		local function normalize(value, sample)
			local result = type(sample) == "table" and table.clone(sample) or {}
			local number = tonumber(result.Value or value) or 0
			if number ~= number or math.abs(number) == math.huge then
				number = 0
			end
			result.Value = math.max(0, number)
			result.Time = result.Time or os.clock()
			return result
		end
		function control:AddSample(value, sample)
			if not self.Scope.Alive then
				return self
			end
			table.insert(self.Samples, normalize(value, sample))
			if #self.Samples > self.MaxSamples then
				table.remove(self.Samples, 1)
			end
			redraw()
			return self
		end
		function control:SetSamples(samples)
			if not self.Scope.Alive then
				return self
			end
			self.Samples = {}
			if type(samples) == "table" then
				for index = math.max(1, #samples - self.MaxSamples + 1), #samples do
					local value = samples[index]
					table.insert(self.Samples, normalize(value, type(value) == "table" and value or nil))
				end
			end
			redraw()
			return self
		end
		function control:Refresh()
			redraw()
			return self
		end
		function control:Destroy()
			card:Destroy()
			if host then
				host:Destroy()
			end
			table.clear(lines)
			table.clear(self.Samples)
		end
		function control:TrackConnection(connection)
			return self.Scope:Add(connection)
		end
		function control:TrackInstance(instance)
			return self.Scope:Add(instance)
		end
		card.Scope:Add(plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(redraw))
		tooltip(
			window,
			plot,
			options.Tooltip or "Recent samples. The vertical scale follows the largest value in the current history.",
			card.Scope
		)
		control:SetStats(options.DefaultStats or {})
		control:SetSamples(options.Samples or {})
		return control
	end

	local BODY_PARTS = {
		{ Body = "Head", X = 0.4, Y = 0.04, W = 0.2, H = 0.17 },
		{ Body = "Chest", X = 0.33, Y = 0.24, W = 0.34, H = 0.2 },
		{ Body = "Stomach", X = 0.33, Y = 0.46, W = 0.34, H = 0.16 },
		{ Body = "Left Arm", X = 0.12, Y = 0.24, W = 0.17, H = 0.38 },
		{ Body = "Right Arm", X = 0.71, Y = 0.24, W = 0.17, H = 0.38 },
		{ Body = "Left Leg", X = 0.33, Y = 0.65, W = 0.15, H = 0.31 },
		{ Body = "Right Leg", X = 0.52, Y = 0.65, W = 0.15, H = 0.31 },
	}

	function Advanced.HitboxPreview(container, options)
		options = options or {}
		local window = container.Window
		local control = container:Button({
			Name = options.Name or "Hitbox Preview",
			Text = "Preview",
			Tooltip = options.Tooltip or "Choose body parts in an interactive preview.",
			ConfigKey = options.ConfigKey,
			Persist = false,
		})
		local modal = window:Modal({
			Title = options.Name or "Hitbox Preview",
			Size = UDim2.fromOffset(280, 345),
			Page = container.Page,
		})
		control.Scope:Add(modal)
		local canvas = modal:Custom({ Name = "Body regions", Height = 252 })
		local root = canvas.Body
		local configs = {}
		for _, raw in ipairs(options.Parts or BODY_PARTS) do
			local config = type(raw) == "table" and raw or { Body = raw }
			local body = config.Body or config.BodyPart or config.Frame or config.Name or config.Label or config.Display
			if body then
				local values = config.Values
					or config.Value
					or config.LinkedValues
					or config.LinkedValue
					or config.Keys
					or config.Parts
					or { body }
				if type(values) ~= "table" then
					values = { values }
				end
				configs[body] = { Label = config.Label or config.Display or config.Name or body, Values = values }
			end
		end
		local selected = selectedMap(options.Default)
		local linked = options.LinkedDropdown
		local rows = {}
		local syncing = false
		local function refresh()
			if not control.Scope.Alive then
				return
			end
			for body, button in pairs(rows) do
				local active = false
				for _, value in ipairs(configs[body].Values) do
					if selected[value] then
						active = true
						break
					end
				end
				Core.bind(window, button, "BackgroundColor3", active and "SurfaceActive" or "Surface")
				Core.bind(window, button, "TextColor3", active and "Accent" or "TextSecondary")
			end
		end
		function control:Get()
			return table.clone(selected)
		end
		function control:Set(value, silent)
			if not self.Scope.Alive then
				return
			end
			local nextSelection = selectedMap(value)
			local changed = false
			for key in pairs(selected) do
				if not nextSelection[key] then
					changed = true
					break
				end
			end
			if not changed then
				for key in pairs(nextSelection) do
					if not selected[key] then
						changed = true
						break
					end
				end
			end
			if not changed then
				return self
			end
			selected = nextSelection
			refresh()
			if linked and not syncing then
				syncing = true
				linked:Set(selected)
				syncing = false
			end
			if not self.Scope.Alive then
				return self
			end
			if window.ControlChanged then
				window:ControlChanged(self)
			end
			if not silent then
				Core.callback(options.Callback, self:Get())
			end
		end
		function control:SetParts(value)
			self:Set(value, true)
			return self
		end
		function control:Refresh()
			refresh()
			return self
		end
		function control:Open()
			modal:Open()
		end
		function control:Close()
			modal:Close()
		end
		function control:Fire()
			if self.Scope.Alive and not self.Disabled then
				modal:Open()
			end
		end
		for _, layout in ipairs(BODY_PARTS) do
			local config = configs[layout.Body]
			if config then
				local button = Core.new("TextButton", {
					Name = layout.Body,
					Text = config.Label,
					TextWrapped = true,
					TextSize = 10,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(layout.X, layout.Y),
					Size = UDim2.fromScale(layout.W, layout.H),
				}, root)
				Core.bind(window, button, "Font", "Font")
				Core.round(button, window)
				Core.stroke(button, window)
				rows[layout.Body] = button
				tooltip(window, button, "Toggle " .. tostring(config.Label), control.Scope)
				control.Scope:Add(button.Activated:Connect(function()
					if control.Disabled then
						return
					end
					local enabled = true
					for _, value in ipairs(config.Values) do
						if selected[value] then
							enabled = false
							break
						end
					end
					local nextState = table.clone(selected)
					for _, value in ipairs(config.Values) do
						nextState[value] = enabled or nil
					end
					control:Set(nextState)
				end))
			end
		end
		if linked then
			local function synchronize()
				if syncing or not control.Scope.Alive then
					return
				end
				syncing = true
				selected = selectedMap(linked:Get())
				refresh()
				syncing = false
			end
			if linked.Observe then
				control.Scope:Add(linked:Observe(synchronize))
			else
				local previous = linked._onChange
				local listener = function(...)
					if previous then
						Core.callback(previous, ...)
					end
					synchronize()
				end
				linked._onChange = listener
				control.Scope:Add(function()
					if linked._onChange == listener then
						linked._onChange = previous
					end
				end)
			end
			synchronize()
		end
		refresh()
		return control
	end

	return Advanced
end
