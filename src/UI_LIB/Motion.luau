local RunService = game:GetService("RunService")
local Core = require(script.Parent.Core)
local Motion = {}

function Motion.bindWindow(window, header, grip)
	local drag, connection, target, resizing
	local function stop()
		drag = nil
		target = nil
		if connection then
			connection:Disconnect()
			window.Scope.Resources[connection] = nil
			connection = nil
		end
	end
	local function startFrame()
		if connection then
			return
		end
		connection = RunService.PreRender:Connect(function(delta)
			if not window.Visible or not target then
				stop()
				return
			end
			local alpha = window.Theme.AnimationSpeed == 0 and 1 or 1 - math.exp(-42 * math.min(delta, 0.1))
			local current = resizing and window.DesiredSize
				or Vector2.new(window.Root.Position.X.Offset, window.Root.Position.Y.Offset)
			local nextValue = current:Lerp(target, alpha)
			if (nextValue - target).Magnitude < 0.25 then
				nextValue = target
			end
			if resizing then
				window:Resize(nextValue.X, nextValue.Y)
			else
				window.Root.Position = UDim2.fromOffset(nextValue.X, nextValue.Y)
			end
			if nextValue == target and not drag then
				stop()
			end
		end)
		window.Scope:Add(connection)
	end
	local function begin(input, resize)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		stop()
		window.Tooltips:Hide()
		local position = window.Root.AbsolutePosition - window.Gui.AbsolutePosition
		window.Root.AnchorPoint = Vector2.zero
		window.Root.Position = UDim2.fromOffset(position.X, position.Y)
		resizing = resize
		drag = {
			Input = input,
			Start = Vector2.new(input.Position.X, input.Position.Y),
			Position = position,
			Size = window.DesiredSize,
		}
		target = resize and window.DesiredSize or position
	end
	window.Scope:Add(header.InputBegan:Connect(function(input)
		begin(input, false)
	end))
	window.Scope:Add(grip.InputBegan:Connect(function(input)
		begin(input, true)
	end))
	window.Input:Subscribe(window.Scope, {
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
			local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.Start
			local viewport = window.Gui.AbsoluteSize
			if resizing then
				local size = drag.Size + delta / window.ScaleObject.Scale
				local minimum = window.IsMobile and Vector2.new(340, 280) or window.MinimumSize
				target = Vector2.new(
					math.clamp(size.X, minimum.X, math.max(minimum.X, (viewport.X - 24) / window.ScaleObject.Scale)),
					math.clamp(size.Y, minimum.Y, math.max(minimum.Y, (viewport.Y - 24) / window.ScaleObject.Scale))
				)
			else
				local position = drag.Position + delta
				local size = window.Root.AbsoluteSize
				target = Vector2.new(
					math.clamp(position.X, 8, math.max(8, viewport.X - size.X - 8)),
					math.clamp(position.Y, 8, math.max(8, viewport.Y - size.Y - 8))
				)
			end
			startFrame()
		end,
		Ended = function(input)
			if drag and input == drag.Input then
				drag = nil
				if connection == nil then
					stop()
				end
			end
		end,
	})
	window.Scope:Add(stop)
	window.StopMotion = stop
end

return Motion
