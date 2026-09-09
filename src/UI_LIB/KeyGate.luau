local Core = require(script.Parent.Core)
local Icons = require(script.Parent.Icons)
local RunService = game:GetService("RunService")
local KeyGate = {}

function KeyGate.mount(window, options)
	local keySystem = window.KeySystem
	if not keySystem.Enabled then
		return
	end
	local scope = Core.scope(window.Scope)
	local layer = Core.new(
		"Frame",
		{ Name = "KeyGate", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 70 },
		window.Gui
	)
	scope:Add(layer)
	local panel = Core.new("CanvasGroup", {
		Name = "KeyWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 285),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.08,
		GroupTransparency = 1,
	}, layer)
	Core.bind(window, panel, "BackgroundColor3", "Background")
	Core.round(panel, window)
	Core.stroke(panel, window)
	local scale = Core.new("UIScale", {}, panel)
	local drag, frameConnection, target
	local moved = false
	local transitioning = false
	local function clampPosition(position)
		local viewport = window.Gui.AbsoluteSize
		local size = Vector2.new(360, 285) * scale.Scale
		return Vector2.new(
			math.clamp(position.X, 8, math.max(8, viewport.X - size.X - 8)),
			math.clamp(position.Y, 8, math.max(8, viewport.Y - size.Y - 8))
		)
	end
	local function stopMotion()
		drag, target = nil, nil
		if frameConnection then
			frameConnection:Disconnect()
			scope.Resources[frameConnection] = nil
			frameConnection = nil
		end
	end
	local function fit()
		scale.Scale =
			math.max(0.1, math.min(1, (window.Gui.AbsoluteSize.X - 24) / 360, (window.Gui.AbsoluteSize.Y - 24) / 285))
		if moved then
			stopMotion()
			local position = clampPosition(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset))
			panel.Position = UDim2.fromOffset(position.X, position.Y)
		end
	end
	scope:Add(window.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	fit()
	local emblem = Core.new(
		"Frame",
		{ Name = "Emblem", Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(34, 34), BorderSizePixel = 0 },
		panel
	)
	Core.bind(window, emblem, "BackgroundColor3", "SurfaceActive")
	Core.round(emblem, window)
	local emblemIcon = Icons.create(window, emblem, "key", "Text", 18)
	emblemIcon.Position = UDim2.fromOffset(8, 8)
	local heading = Core.text(window, panel, "Unknown Hub Key System", 16)
	Core.bind(window, heading, "Font", "FontBold")
	heading.Position = UDim2.fromOffset(65, 24)
	heading.Size = UDim2.new(1, -80, 0, 25)
	local header = Core.new("Frame", {
		Name = "DragHeader",
		BackgroundTransparency = 1,
		Active = true,
		Size = UDim2.new(1, 0, 0, 65),
		ZIndex = 3,
	}, panel)
	local function startFrame()
		if frameConnection then
			return
		end
		frameConnection = RunService.PreRender:Connect(function(delta)
			if not scope.Alive or not layer.Visible or not window.Gui.Enabled or not target then
				stopMotion()
				return
			end
			local current = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
			local alpha = window.Theme.AnimationSpeed == 0 and 1 or 1 - math.exp(-38 * math.min(delta, 0.1))
			local position = current:Lerp(target, alpha)
			if (position - target).Magnitude < 0.25 then
				position = target
			end
			panel.Position = UDim2.fromOffset(position.X, position.Y)
			if position == target then
				frameConnection:Disconnect()
				scope.Resources[frameConnection] = nil
				frameConnection = nil
				if not drag then
					target = nil
				end
			end
		end)
		scope:Add(frameConnection)
	end
	scope:Add(header.InputBegan:Connect(function(input)
		if transitioning then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		stopMotion()
		window.Tooltips:Hide()
		local position = clampPosition(panel.AbsolutePosition - window.Gui.AbsolutePosition)
		panel.AnchorPoint = Vector2.zero
		panel.Position = UDim2.fromOffset(position.X, position.Y)
		moved = true
		drag = { Input = input, Start = Vector2.new(input.Position.X, input.Position.Y), Position = position }
		target = position
	end))
	window.Input:Subscribe(scope, {
		Changed = function(input)
			if
				not drag
				or (
					input ~= drag.Input
					and not (
						drag.Input.UserInputType == Enum.UserInputType.MouseButton1
						and input.UserInputType == Enum.UserInputType.MouseMovement
					)
				)
			then
				return
			end
			target = clampPosition(drag.Position + Vector2.new(input.Position.X, input.Position.Y) - drag.Start)
			startFrame()
		end,
		Ended = function(input)
			if drag and input == drag.Input then
				drag = nil
				if not frameConnection then
					stopMotion()
				end
			end
		end,
	})
	scope:Add(stopMotion)
	local description =
		Core.text(window, panel, options.KeyDescription or "Enter your access key to continue.", 12, "TextSecondary")
	description.Position = UDim2.fromOffset(20, 68)
	description.Size = UDim2.new(1, -40, 0, 24)
	local label = Core.text(window, panel, "Access key", 11)
	Core.bind(window, label, "Font", "FontBold")
	label.Position = UDim2.fromOffset(20, 103)
	local box = Core.new("TextBox", {
		Name = "AccessKey",
		Text = "",
		PlaceholderText = "Paste your key",
		ClearTextOnFocus = false,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 125),
		Size = UDim2.new(1, -40, 0, 37),
		BorderSizePixel = 0,
	}, panel)
	Core.bind(window, box, "Font", "Font")
	Core.bind(window, box, "TextColor3", "Text")
	Core.bind(window, box, "PlaceholderColor3", "TextMuted")
	Core.bind(window, box, "BackgroundColor3", "Surface")
	Core.round(box, window)
	Core.pad(box, 12)
	local border = Core.stroke(box, window)
	window:Tooltip(box, "Your Unknown Hub access key", scope)
	local status = Core.text(window, panel, "", 11, "TextMuted")
	status.Position = UDim2.fromOffset(20, 170)
	status.Size = UDim2.new(1, -40, 0, 30)
	status.TextWrapped = true
	status.TextTruncate = Enum.TextTruncate.None
	local unlock = Core.new("TextButton", {
		Name = "Unlock",
		Text = options.SubmitKeyText or "Unlock",
		TextSize = 12,
		AutoButtonColor = false,
		Position = UDim2.fromOffset(20, 211),
		Size = UDim2.new(1, -40, 0, 35),
		BorderSizePixel = 0,
	}, panel)
	Core.bind(window, unlock, "Font", "FontBold")
	Core.bind(window, unlock, "BackgroundColor3", "Text")
	Core.bind(window, unlock, "TextColor3", "Background")
	Core.round(unlock, window)
	local getKey = Core.new("TextButton", {
		Name = "GetKey",
		Text = options.GetKeyText or "Get a key",
		TextSize = 11,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.fromOffset(20, 251),
	}, panel)
	Core.bind(window, getKey, "Font", "Font")
	Core.bind(window, getKey, "TextColor3", "TextSecondary")
	window:Tooltip(unlock, "Verify your key", scope)
	window:Tooltip(getKey, "Open the key link", scope)
	local feedbackScope
	local accepting = false
	local gate = {
		Root = layer,
		Panel = panel,
		Input = box,
		Submit = unlock,
		Status = status,
		Scope = scope,
		Header = header,
		Border = border,
		Heading = heading,
		Feedback = "idle",
		Phase = "entry",
		StopMotion = stopMotion,
		Emblem = emblemIcon,
		Scale = scale,
	}
	window.KeyGate = gate
	local function feedback(kind, message)
		if not scope.Alive then
			return
		end
		if feedbackScope then
			feedbackScope:Destroy()
		end
		feedbackScope = Core.scope(scope)
		local animationScope = feedbackScope
		gate.Feedback = kind
		status.Text = message or ""
		local token = kind == "success" and "Success"
			or kind == "error" and "Error"
			or kind == "pending" and "Accent"
			or "TextMuted"
		local color = window.Theme[token]
		window.Bindings[border].Color = kind == "idle" and "Border" or token
		window.Bindings[status].TextColor3 = token
		window.Bindings[unlock].BackgroundColor3 = kind == "success" and "Success"
			or kind == "error" and "Error"
			or "Text"
		window.Bindings[emblemIcon].ImageColor3 = kind == "idle" and "Text" or token
		Core.tween(
			window,
			border,
			{ Color = kind == "idle" and (box:IsFocused() and window.Theme.Accent or window.Theme.Border) or color }
		)
		Core.tween(window, status, { TextColor3 = color })
		Core.tween(window, unlock, { BackgroundColor3 = window.Theme[window.Bindings[unlock].BackgroundColor3] })
		Core.tween(window, emblemIcon, { ImageColor3 = kind == "idle" and window.Theme.Text or color })
		Icons:Apply(emblemIcon, kind == "success" and "check" or "key")
		Core.tween(window, box, { Position = UDim2.fromOffset(20, 125) }, 0)
		unlock.Text = kind == "success" and "Key verified"
			or kind == "pending" and "Verifying..."
			or (options.SubmitKeyText or "Unlock")
		box.TextEditable = kind ~= "success" and kind ~= "pending"
		unlock.Active = kind ~= "success" and kind ~= "pending"
		getKey.Active = kind ~= "success" and kind ~= "pending"
		if kind == "error" and window.Theme.AnimationSpeed ~= 0 then
			local offsets = { -5, 4, -2, 0 }
			local function step(index)
				if not animationScope.Alive then
					return
				end
				if window.Theme.AnimationSpeed == 0 then
					box.Position = UDim2.fromOffset(20, 125)
					return
				end
				Core.tween(window, box, { Position = UDim2.fromOffset(20 + offsets[index], 125) }, 0.055)
				if index < #offsets then
					Core.delay(animationScope, 0.06, function()
						step(index + 1)
					end)
				end
			end
			step(1)
		elseif kind == "pending" and window.Theme.AnimationSpeed ~= 0 then
			local index = 0
			local function pulse()
				if not animationScope.Alive then
					return
				end
				index = index % 3 + 1
				unlock.Text = "Verifying" .. string.rep(".", index)
				Core.delay(animationScope, 0.3, pulse)
			end
			pulse()
		end
	end
	scope:Add(box.Focused:Connect(function()
		if gate.Feedback == "idle" then
			Core.tween(window, border, { Color = window.Theme.Accent })
		end
	end))
	scope:Add(box.FocusLost:Connect(function()
		if gate.Feedback == "idle" then
			Core.tween(window, border, { Color = window.Theme.Border })
		end
	end))
	scope:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		if gate.Feedback == "error" and not keySystem.Busy then
			feedback("idle", "Enter your key to continue.")
		end
	end))
	local function verify()
		if not scope.Alive or keySystem.Busy or accepting then
			return
		end
		local ok, message = keySystem:Verify(box.Text)
		if scope.Alive and not ok then
			if gate.Feedback ~= "error" or status.Text ~= message then
				feedback("error", message)
			end
		end
	end
	gate.Verify = verify
	scope:Add(unlock.Activated:Connect(verify))
	scope:Add(box.FocusLost:Connect(function(enter)
		if enter then
			verify()
		end
	end))
	scope:Add(getKey.Activated:Connect(function()
		if keySystem.Busy or accepting then
			return
		end
		local link = keySystem:GetKeyLink()
		if not scope.Alive then
			return
		end
		box.Text = link
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #link + 1
		status.Text = "Copy this link to get your key, then paste it here."
	end))
	window.Locked = true
	window.Root.Visible = false
	window.RestoreButton.Visible = false
	local function handoff()
		if not scope.Alive then
			return
		end
		if not keySystem.Scope.Alive or not keySystem.Verified then
			accepting = false
			gate.Phase = "entry"
			feedback("error", "Verification is no longer valid. Try again.")
			return
		end
		transitioning = true
		stopMotion()
		header.Active = false
		box.Text = ""
		local transitionScope = Core.scope(scope)
		local function valid()
			return transitionScope.Alive and window.Scope.Alive and keySystem.Scope.Alive and keySystem.Verified
		end
		local function recover()
			transitionScope:Destroy()
			if not scope.Alive then
				return
			end
			transitioning, accepting = false, false
			header.Active = true
			panel.Visible = true
			Core.tween(window, panel, { GroupTransparency = 0 })
			gate.Phase = "entry"
			feedback("error", "Verification is no longer valid. Try again.")
		end
		local function reveal(shell)
			if not valid() then
				recover()
				return
			end
			gate.Phase = "opening"
			panel.Visible = false
			window.Root.GroupTransparency = 1
			window.Locked = false
			window:Open()
			Core.tween(window, window.Root, { GroupTransparency = 0 }, 0.25)
			if shell then
				Core.tween(window, shell, { GroupTransparency = 1 }, 0.25)
			end
			local duration = window.Theme.AnimationSpeed == 0 and 0 or 0.25
			Core.delay(transitionScope, duration + 0.01, function()
				gate.Phase = "complete"
				scope:Destroy()
			end)
		end
		if window.Theme.AnimationSpeed == 0 then
			reveal()
			return
		end
		gate.Phase = "preparing"
		local keyPosition = panel.AbsolutePosition - window.Gui.AbsolutePosition
		local keySize = panel.AbsoluteSize
		local shell = Core.new("CanvasGroup", {
			Name = "ExpansionShell",
			Position = UDim2.fromOffset(keyPosition.X, keyPosition.Y),
			Size = UDim2.fromOffset(keySize.X, keySize.Y),
			BackgroundColor3 = window.Theme.Background,
			BackgroundTransparency = panel.BackgroundTransparency,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, layer)
		transitionScope:Add(shell)
		Core.round(shell, window)
		Core.stroke(shell, window)
		gate.MorphShell = shell
		panel.ZIndex = 2
		Core.tween(window, panel, { GroupTransparency = 1 }, 0.12)
		Core.delay(transitionScope, 0.12, function()
			if not valid() then
				recover()
				return
			end
			panel.Visible = false
			gate.Phase = "expanding"
			local function bounds()
				local position = window.Root.AbsolutePosition - window.Gui.AbsolutePosition
				local size = window.Root.AbsoluteSize
				return {
					Position = UDim2.fromOffset(position.X, position.Y),
					Size = UDim2.fromOffset(size.X, size.Y),
					BackgroundTransparency = window.Theme.WindowTransparency,
				}
			end
			Core.tween(window, shell, bounds(), 0.24)
			local function refit()
				if not valid() then
					return
				end
				if gate.Phase == "expanding" then
					Core.tween(window, shell, bounds(), 0.1)
				elseif gate.Phase == "opening" then
					local endpoint = bounds()
					shell.Position = endpoint.Position
					shell.Size = endpoint.Size
				end
			end
			transitionScope:Add(window.Root:GetPropertyChangedSignal("AbsolutePosition"):Connect(refit))
			transitionScope:Add(window.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit))
			Core.delay(transitionScope, 0.24, function()
				if not valid() then
					recover()
					return
				end
				local endpoint = bounds()
				for property, value in pairs(endpoint) do
					shell[property] = value
				end
				reveal(shell)
			end)
		end)
	end
	keySystem:Subscribe(scope, function(state)
		if not scope.Alive then
			return
		end
		if state.Verified then
			if accepting then
				return
			end
			accepting = true
			gate.Phase = "confirming"
			feedback("success", state.Message ~= "" and state.Message or "Key accepted. Welcome to Unknown Hub.")
			box:ReleaseFocus()
			Core.delay(scope, 0.4, handoff)
		elseif state.Busy then
			feedback("pending", state.Message)
		elseif gate.Feedback == "pending" or gate.Feedback == "error" then
			feedback("error", state.Message)
		else
			feedback("idle", state.Message)
		end
	end)
	Core.tween(window, panel, { GroupTransparency = 0 })
	return window.KeyGate
end

return KeyGate
