local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Text = require(script.Parent.Text)
local Fonts = require(script.Parent.Fonts)

local Core = {}

function Core.delay(scope, seconds, callback)
	local pending
	local cancel
	cancel = function()
		scope.Resources[cancel] = nil
		if pending then
			pcall(task.cancel, pending)
			pending = nil
		end
	end
	scope:Add(cancel)
	pending = task.delay(seconds, function()
		pending = nil
		scope.Resources[cancel] = nil
		if scope.Alive then
			callback()
		end
	end)
	return cancel
end

function Core.scope(parent)
	local scope = { Alive = true, Resources = {} }
	function scope:Add(resource)
		assert(self.Alive, "Cannot add to a destroyed scope")
		self.Resources[resource] = true
		return resource
	end
	function scope:Destroy()
		if not self.Alive then
			return
		end
		self.Alive = false
		if parent then
			parent.Resources[self] = nil
		end
		local resources = self.Resources
		self.Resources = {}
		for resource in pairs(resources) do
			local success, message = pcall(function()
				if typeof(resource) == "RBXScriptConnection" then
					resource:Disconnect()
				elseif type(resource) == "function" then
					resource()
				else
					resource:Destroy()
				end
			end)
			if not success then
				warn("[Unknown Hub cleanup] " .. tostring(message))
			end
		end
	end
	if parent then
		parent:Add(scope)
	end
	return scope
end

function Core.assign(instance, property, value)
	if property == "Font" or property == "FontFace" then
		value = assert(Fonts.resolve(value), "Expected a Font or Enum.Font")
		instance[if typeof(value) == "Font" then "FontFace" else "Font"] = value
	else
		instance[property] = value
	end
end

function Core.new(className, properties, parent)
	local instance = Instance.new(className)
	for property, value in pairs(properties or {}) do
		Core.assign(instance, property, value)
	end
	instance.Parent = parent
	return instance
end

function Core.bind(window, instance, property, token)
	local bindings = window.Bindings[instance]
	if not bindings then
		bindings = {}
		window.Bindings[instance] = bindings
		instance.Destroying:Once(function()
			window.Bindings[instance] = nil
			local tween = window.Tweens[instance]
			if tween then
				tween:Cancel()
				tween:Destroy()
				window.Tweens[instance] = nil
				window.TweenGoals[instance] = nil
			end
		end)
	end
	bindings[property] = token
	local value = window.Theme[token]
	if property == "CornerRadius" then
		value = UDim.new(0, value)
	end
	Core.assign(instance, property, value)
end

function Core.round(instance, window, token)
	local corner = Core.new("UICorner", {}, instance)
	Core.bind(window, corner, "CornerRadius", token or "Radius")
	return corner
end

function Core.stroke(instance, window)
	local stroke = Core.new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, instance)
	Core.bind(window, stroke, "Color", "Border")
	Core.bind(window, stroke, "Thickness", "BorderSize")
	return stroke
end

function Core.text(window, parent, value, size, token, rawText)
	local label = Core.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = if rawText then tostring(value or "") else Text.display(value),
		TextSize = size or window.Theme.BodySize,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	Core.bind(window, label, "TextColor3", token or "Text")
	Core.bind(window, label, "Font", "Font")
	return label
end

function Core.pad(parent, amount)
	return Core.new("UIPadding", {
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
	}, parent)
end

function Core.list(parent, gap, direction)
	return Core.new("UIListLayout", {
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = direction or Enum.FillDirection.Vertical,
	}, parent)
end

function Core.tween(window, instance, properties, duration)
	if not window.Scope.Alive then
		return
	end
	if not window.Bindings[instance] then
		window.Bindings[instance] = {}
		instance.Destroying:Once(function()
			window.Bindings[instance] = nil
			local current = window.Tweens[instance]
			if current then
				current:Cancel()
				current:Destroy()
				window.Tweens[instance] = nil
				window.TweenGoals[instance] = nil
			end
		end)
	end
	local previous = window.Tweens[instance]
	if previous then
		previous:Cancel()
		previous:Destroy()
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(
			window.Theme.AnimationSpeed == 0 and 0 or (duration or window.Theme.AnimationSpeed),
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		properties
	)
	window.Tweens[instance] = tween
	window.TweenGoals[instance] = properties
	tween.Completed:Once(function()
		if window.Tweens[instance] == tween then
			window.Tweens[instance] = nil
			window.TweenGoals[instance] = nil
		end
		tween:Destroy()
	end)
	tween:Play()
	return tween
end

function Core.callback(callback, ...)
	if callback then
		local success, message = xpcall(callback, debug.traceback, ...)
		if not success then
			warn("[Unknown Hub] " .. tostring(message))
		end
	end
end

function Core.input(window)
	local router = { Listeners = {} }
	function router:Subscribe(scope, handlers)
		self.Listeners[handlers] = scope
		scope:Add(function()
			self.Listeners[handlers] = nil
		end)
	end
	function router:IsVisible()
		return window:GetVisible()
	end
	for event, signal in pairs({
		Began = UserInputService.InputBegan,
		Changed = UserInputService.InputChanged,
		Ended = UserInputService.InputEnded,
	}) do
		window.Scope:Add(signal:Connect(function(input, processed)
			for handlers, scope in pairs(router.Listeners) do
				if scope.Alive and handlers[event] then
					handlers[event](input, processed)
				end
			end
		end))
	end
	return router
end

function Core.hover(window, scope, button, normalToken)
	Core.bind(window, button, "BackgroundColor3", normalToken or "Surface")
	scope:Add(button.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			Core.tween(window, button, { BackgroundColor3 = window.Theme.SurfaceHover })
		end
	end))
	scope:Add(button.MouseLeave:Connect(function()
		Core.tween(window, button, { BackgroundColor3 = window.Theme[normalToken or "Surface"] })
	end))
end

return Core
